extends Node
## Real task machines share foot sorting with actors; task physics stays intact.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Objectives = preload("res://scripts/gameplay/world/room_objectives.gd")
const Arena = preload("res://scripts/gameplay/world/boss_arena.gd")
const Boss = preload("res://scripts/gameplay/bosses/boss_actor.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Layouts = preload("res://scripts/domain/world/boss_layouts.gd")
const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
var room: RoomController
var host: Node2D
var checks: int = 0
var failures: int = 0

class SortingProbe extends Node2D:
	var offset := Vector2.ZERO
	func _draw() -> void:
		draw_rect(Rect2(offset - Vector2(8, 8), Vector2(16, 16)), Color("ff00ff"))

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OBJECTIVE_DEPTH: " + label)

func fixture(id: String) -> void:
	if is_instance_valid(host):
		host.reset()
		host.free()
	room.objectives = null
	check(room.load_room_layout(id, 0, 47213), "production objective layout loads: " + id)
	host = Objectives.new()
	room.add_child(host)
	room.objectives = host
	host.configure(room, room.layout)
	host.sync_body_layer()

func expected_body_foot(item: Dictionary) -> Vector2:
	if bool(item.get("carried", false)):
		return room.player.position + Vector2(0, .1)
	if PropArt.has_authored_asset(str(item.get("asset", ""))):
		return Vector2(item.position)
	return Vector2(item.position) + Vector2(0, 15).rotated(float(item.get("rotation", 0)))

func _run() -> void:
	if not Game.profile_path.contains("test_objective_depth"):
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated objective-depth run")
	room = RoomScene.instantiate()
	room.run_seed = 47213
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	for actor: Node in room.enemies.get_children(): actor.free()
	check(room.y_sort_enabled and room.player.z_index == 2 and room.enemies.z_index == 2, "actual actors share the raised-object depth plane")
	for id: String in Catalog.room_ids():
		fixture(id)
		var original_obstructions: Array[Rect2] = room.obstructions.duplicate()
		for item: Dictionary in host.elements.values():
			var asset: String = str(item.get("asset", ""))
			if not host.textures.has(asset) or bool(item.get("attackable", false)):
				check(not host.body_nodes.has(str(item.id)), id + " attackable/ground-only element has no duplicate painted body: " + str(item.id))
				continue
			var body: Node2D = host.body_nodes.get(str(item.id))
			check(is_instance_valid(body), id + " painted task machine is a separate sortable node: " + str(item.id))
			if not is_instance_valid(body): continue
			check(host.body_layer.get_parent() == room and host.body_layer.z_index == 2 and host.body_layer.y_sort_enabled and body.z_index == 0, id + " task body participates in the actor depth plane")
			var expected_foot: Vector2 = expected_body_foot(item)
			check(body.position.is_equal_approx(expected_foot), id + " task body uses its actual rotated texture foot or carrier foot")
			if PropArt.has_authored_asset(asset):
				check(host.textures[asset] == PropArt.texture_for_asset(asset) and host.regions[asset] == PropArt.local_region(asset), id + " body uses its whole selected crop and crop-local ground anchor")
			check(body.visible == (bool(item.get("active", true)) and not bool(item.get("destroyed", false))), id + " initial active state controls body visibility")
		check(room.obstructions == original_obstructions, id + " body synchronization never changes collision or objectives")
	if DisplayServer.get_name() != "headless":
		await _gpu_body_sort_probe()
	fixture("L01")
	var legacy: Dictionary = host.add_element("legacy_foot_probe", Vector2(1400, 1000), "旧素材兼容探针", "utility", "asset://props/B01_winch_v1.png", {"required": false, "rotation": .45})
	check(not PropArt.has_authored_asset(str(legacy.asset)), "explicit legacy source exercises the compatibility path")
	check(is_instance_valid(host.body_nodes.get("legacy_foot_probe")) and host.body_nodes.legacy_foot_probe.position.is_equal_approx(expected_body_foot(legacy)), "legacy texture still registers its rotated bottom offset")
	var fresh: Dictionary = host.add_element("fresh_foot_probe", Vector2(1400, 1000), "新素材脚点探针", "utility", "B01_winch", {"required": false, "rotation": .45})
	check(host.body_nodes.fresh_foot_probe.position.is_equal_approx(Vector2(fresh.position)), "rotating fresh painted machinery preserves its projected world ground anchor")
	fixture("L02")
	var cart: Dictionary = host.element("cargo_cart")
	var body: Node2D = host.body_nodes.cargo_cart
	var old_foot: Vector2 = body.position
	room.player.position = cart.position
	host.tick(.2)
	check(body.position != old_foot and body.position.is_equal_approx(expected_body_foot(cart)), "actual automatic escort updates its own body foot")
	room.player.position = body.position + Vector2(0, -30)
	host.sync_body_layer()
	check(body.modulate.a < .6, "machine fades when it would hide the player's body behind it")
	room.player.position = body.position + Vector2(0, 40)
	host.sync_body_layer()
	check(is_equal_approx(body.modulate.a, 1.0), "machine returns to opaque when the player walks in front")
	fixture("L04")
	var carried: Dictionary = host.element("crate_0")
	room.player.position = carried.position
	check(host.interact("crate_0", room.player), "actual pickup starts crate carrying")
	body = host.body_nodes.crate_0
	check(body.visible and body.position.is_equal_approx(room.player.position + Vector2(0, .1)), "held object follows the player foot instead of remaining at its pickup point")
	room.player.position += Vector2(120, 70)
	host.sync_body_layer()
	check(body.position.is_equal_approx(room.player.position + Vector2(0, .1)), "moving a carrier updates its held body")
	carried.active = false
	host.sync_body_layer()
	check(not body.visible, "delivered carried object immediately disappears")
	carried.active = true
	carried.carried = false
	carried.position = Vector2(1000, 1000)
	host.sync_body_layer()
	check(body.visible and body.position.is_equal_approx(expected_body_foot(carried)), "dropped object regains its own ground foot")
	carried.destroyed = true
	host.sync_body_layer()
	check(not body.visible, "destroyed body cannot remain as stale scenery")
	fixture("L17")
	var part: Dictionary = host.element("part_0")
	room.player.position = part.position
	check(host.interact("part_0", room.player), "real attackable part is picked up")
	check(host.body_nodes.has("part_0") and host.body_nodes.part_0.visible and not host.targets.part_0.visible, "carried attackable object has one visible body")
	var old_layer: Node2D = host.body_layer
	host.reset()
	check(not is_instance_valid(old_layer) and host.body_nodes.is_empty() and not is_instance_valid(host.body_layer), "reset retires the sibling layer and all body nodes")
	host.free()
	room.objectives = null
	room.layout = Layouts.build("BO01", 47213)
	room.obstructions.assign(room.layout.obstructions)
	var boss: Node2D = Boss.new()
	boss.room = room
	boss.position = room.layout.boss_spawn
	boss.configure_boss("BO01", 0, 47213)
	room.enemies.add_child(boss)
	host = Arena.new()
	room.add_child(host)
	room.objectives = host
	host.configure_boss_arena(room, room.layout, boss)
	check(is_instance_valid(host.body_layer) and host.body_nodes.size() == room.layout.boss_counterplay.size(), "boss cooling valves inherit individual sortable bodies")
	var valve_id: String = str(room.layout.boss_counterplay[0].id)
	room.player.position = host.element(valve_id).position
	check(host.interact(valve_id, room.player), "boss valve interaction still reaches the actual boss")
	var valve: Dictionary = host.element(valve_id)
	valve.active = false
	# Completed objectives and boss arena valves no longer depend on room.tick.
	room.process_mode = Node.PROCESS_MODE_INHERIT
	room.set_process(false)
	room.set_physics_process(false)
	room.player.set_process(false)
	room.player.set_physics_process(false)
	boss.set_process(false)
	boss.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not host.body_nodes[valve_id].visible, "independent layer callback synchronizes a boss valve without objective ticking")
	old_layer = host.body_layer
	host.free()
	room.objectives = null
	await get_tree().process_frame
	check(not is_instance_valid(old_layer), "freeing only the objective host also frees its sibling body layer")
	if is_instance_valid(room.combat_audio): await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
	print("OBJECTIVE_DEPTH checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _rendered_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _gpu_body_sort_probe() -> void:
	get_window().size = Vector2i(1280, 720)
	fixture("L01")
	var item: Dictionary = host.element("brake_0")
	item.position = Vector2(1400, 1000)
	room.player.position = Vector2(1400, 1200)
	room.player.visible = false
	room.camera.follow_target()
	room.camera.force_update_scroll()
	host.sync_body_layer()
	var body: Node2D = host.body_nodes.brake_0
	var texture: Texture2D = host.textures[item.asset]
	var bounds: Rect2 = host.regions[item.asset]
	var source: Image = texture.get_image()
	var opaque: Vector2 = Vector2.ZERO
	var found: bool = false
	for y: int in range(4, int(bounds.size.y * .75), 4):
		for x: int in range(4, int(bounds.size.x) - 4, 4):
			if source.get_pixel(int(bounds.position.x) + x, int(bounds.position.y) + y).a > .99:
				opaque = Vector2(x, y)
				found = true
				break
		if found: break
	check(found, "GPU objective probe selects actual opaque upper winch art")
	if not found:
		room.player.visible = true
		return
	var height: float = float(item.get("visual_height", 96.0))
	var width: float = minf(150.0, height * bounds.size.x / bounds.size.y)
	var local_draw_bounds: Rect2 = PropArt.bounds_at(str(item.asset), Vector2.ZERO, Vector2(150, height)) if PropArt.has_authored_asset(str(item.asset)) else Rect2(-width * .5, -height, width, height)
	var at: Vector2 = body.position + local_draw_bounds.position + opaque / bounds.size * local_draw_bounds.size
	var marker := SortingProbe.new()
	marker.z_index = 2
	marker.position = at
	room.add_child(marker)
	await _rendered_frame()
	var pixel: Vector2i = Vector2i(room.get_global_transform_with_canvas() * at)
	var behind: Color = get_viewport().get_texture().get_image().get_pixelv(pixel)
	check(behind.g > .05 or behind.b < .9 or behind.r < .9, "actual winch body occludes an actor foot behind it")
	marker.position = Vector2(at.x, body.position.y + 35)
	marker.offset = at - marker.position
	marker.queue_redraw()
	await _rendered_frame()
	var in_front: Color = get_viewport().get_texture().get_image().get_pixelv(pixel)
	check(in_front.r > .95 and in_front.g < .05 and in_front.b > .95, "actor foot in front draws over the same actual winch art")
	marker.free()
	room.player.visible = true
