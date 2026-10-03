extends Node
## Controlled real GPU/rendering and combat integration, never natural balance.
## Fresh isolated production runs visit 49 rooms for each of three professions.
## Camera placements, disabled enemy AI, one durable target, resource/cooldown
## refills and cast repositioning are disclosed fixtures. No completion/reward
## injection and no player save outside the managed isolated test run.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const HudScene = preload("res://scenes/presentation/hud.tscn")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const Content = preload("res://scripts/levels/b10/world/content.gd")
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
const NativeArt = preload("res://scripts/levels/b10/art/native_art.gd")
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const SharedArt = preload("res://scripts/presentation/characters/hero_shared_action_family.gd")
const HEROES := ["CH01", "CH02", "CH03"]
const RADIUS := 14.0
const SEED := 101004
const INPUTS := ["move_left", "move_right", "move_up", "move_down", "click_move", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]
var checks := 0
var failures := 0
var output := ""
var room_filter := ""
var records: Array[Dictionary] = []
var captures: Array[String] = []
var source_files: Dictionary = {}
var original_paths: Dictionary = {}
var body_records: Array[Dictionary] = []
var prop_records: Array[Dictionary] = []
var combat_records: Array[Dictionary] = []
var mouse_at := Vector2.ZERO
var skill_events: Array[Dictionary] = []
var stage: SubViewport

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("B10_RUNTIME_ACCEPTANCE: " + label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if not Game.profile_path.contains("test_b10_runtime_acceptance") or output.is_empty() or not FileAccess.file_exists(output.path_join(".managed-test-run.json")) or DisplayServer.get_name() == "headless":
		printerr("B10 runtime acceptance requires its managed isolated profile and a real GPU window")
		get_tree().quit(2)
		return
	room_filter = OS.get_environment("GAMES_B10_ACCEPTANCE_ROOM")
	if not room_filter.is_empty() and not Content.room_ids().has(room_filter):
		check(false, "GAMES_B10_ACCEPTANCE_ROOM must name one exact B10 room ID: " + room_filter)
		get_tree().quit(2)
		return
	get_tree().create_timer(900).timeout.connect(func(): push_error("B10 runtime acceptance timed out"); get_tree().quit(1))
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().size = Vector2i(2560, 1440)
	# Reuse the B09 real-GPU local viewport pattern: native Window mouse queries
	# otherwise consult the OS cursor rather than the pushed mapped pointer.
	stage = SubViewport.new()
	stage.name = "B10LocalInput2K"
	stage.size = Vector2i(2560, 1440)
	stage.size_2d_override = Vector2i(1280, 720)
	stage.size_2d_override_stretch = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	get_tree().root.add_child(stage)
	reparent(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(presentation)
	await _frames(5)
	check(get_window().size == Vector2i(2560, 1440) and get_viewport().get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), "real 2K window presents the local-input logical 1280x720 GPU viewport")
	var rooms := _room_matrix()
	if room_filter.is_empty():
		check(rooms.size() == 49, "matrix owns 42 formal B01-B06 rooms and seven B10 rooms")
	else:
		check(rooms.size() == 1 and str(rooms[0].id) == room_filter, "subset contains only B10 room " + room_filter)
	for hero: String in HEROES:
		_release_all()
		Game.run = null
		if not (Game.new_profile() and Game.select_hero(hero)):
			check(false, hero + " fresh isolated profile selects profession")
			continue
		Game.set_setting("auto_attack", false)
		Game.set_setting("camera_shake", false)
		if not Game.start_run({"expedition": true, "biome_id": "B01", "difficulty": 0, "seed": SEED}):
			check(false, hero + " production B01 departure creates isolated run")
			continue
		check(Game.run.hero_id == hero and Game.run.skill_loadout_snapshot.size() == 4, hero + " production departure freezes real profession and four slots")
		for entry: Dictionary in rooms:
			await _inspect(hero, entry)
	if room_filter.is_empty():
		check(records.size() == 147, "all 49 rooms installed for all three professions")
		check(original_paths.size() == 49, "all 49 rooms own independent background paths")
	else:
		check(records.size() == HEROES.size(), "subset " + room_filter + " installed for all three professions")
		check(original_paths.size() == 1 and original_paths.has(room_filter), "subset owns only its requested independent background")
	if room_filter.is_empty() or room_filter == "L55":
		check(body_records.size() == 25, "all eighteen monster and seven dragon single-pose sources admitted")
		check(prop_records.size() == 4, "all four native scene-object sources admitted and drawn")
		check(combat_records.size() == 3, "all professions exercised real primary and four skill effects in B10")
	_release_all()
	Game.run = null
	var report := FileAccess.open(output.path_join("b10_runtime_acceptance.json"), FileAccess.WRITE)
	check(report != null, "managed report opens")
	if report != null:
		var report_data := {"checks": checks, "failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "display_server": DisplayServer.get_name(), "logical_viewport": [1280, 720], "framebuffer": [2560, 1440], "scope": "Controlled production render/navigation/HUD/combat integration; single native body pose per enemy; no natural clearing, balance, continuous animation, monitor visibility or long-session performance claim", "fixtures": ["fresh managed isolated profiles", "camera/actor placement for views", "ordinary spawned AI disabled", "one durable reward-disabled B10 target", "resource and identity cooldown refills between independent casts", "four-object gallery drawn through production native frame helper"], "records": records, "native_bodies": body_records, "native_props": prop_records, "combat": combat_records, "captures": captures}
		if not room_filter.is_empty():
			report_data["room_filter"] = room_filter
			report_data["scope"] = "Subset: B10 room " + room_filter + " for all three professions; controlled production render/navigation/HUD/native environment integration; no other room or full matrix acceptance claim; no natural clearing, balance, continuous animation, monitor visibility or long-session performance claim"
			if room_filter == "L55":
				report_data["scope"] += "; this room also exercises single-pose body sources, native props gallery, primary and four real skill effects"
			else:
				report_data["fixtures"] = report_data.fixtures.slice(0, 3)
		report.store_string(JSON.stringify(report_data, "\t"))
		report.close()
	print("B10_RUNTIME_ACCEPTANCE checks=", checks, " failures=", failures, " rooms=", records.size(), " output=", output)
	get_tree().quit(1 if failures else 0)

func _room_matrix() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not room_filter.is_empty():
		result.append({"id": room_filter, "biome": "B10", "capture": true})
		return result
	for chapter: int in range(1, 7):
		for index: int in range(6):
			result.append({"id": "L%02d" % ((chapter - 1) * 6 + index + 1), "biome": "B%02d" % chapter, "capture": index == 0})
		result.append({"id": "BO%02d" % chapter, "biome": "B%02d" % chapter, "capture": true})
	for id: String in Content.room_ids(): result.append({"id": id, "biome": "B10", "capture": true})
	return result

func _inspect(hero: String, entry: Dictionary) -> void:
	var id: String = entry.id
	var biome: String = entry.biome
	var label := hero + "/" + id
	var room: Node2D = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await _frames(2)
	room.combat_audio.audible = false
	# Formal B06 current_context supplies both historical fields; no debug switch.
	var context := {"room_id": id, "biome_id": biome, "role": "boss" if id.begins_with("BO") else "branch", "difficulty": 0, "seed": SEED, "node_index": 1, "node_count": 7, "phase": "combat", "expedition": true, "b06_candidate": biome == "B06", "b06_progression": biome == "B06"}
	var prepared: Dictionary = room.prepare_expedition_node(context)
	check(bool(prepared.get("valid", false)), label + " production room prepares: " + str(prepared.get("error", "")))
	if not bool(prepared.get("valid", false)):
		room.free()
		return
	room.apply_prepared_expedition_node(prepared)
	room.spawn_enabled = false
	var configured: bool = room.configuration_ready and room.configuration_error.is_empty() and is_instance_valid(room.player)
	check(configured, label + " actual room configuration: " + room.configuration_error)
	if not configured:
		check(await room.combat_audio.wait_for_cleanup(), label + " failed configuration audio cleanup")
		room.free()
		return
	for enemy: Node in room.enemies.get_children():
		enemy.training_ai_disabled = true
		enemy.reward_enabled = false
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	var hud = HudScene.instantiate()
	hud.room = room
	hud_layer.add_child(hud)
	hud.set_process(false)
	await _frames(3)
	check(room.player.hero_id() == hero, label + " actual actor profession")
	check(room.valid_ground(room.layout.entry, RADIUS) and room.valid_ground(room.exit_position, RADIUS), label + " entrance and exit have player clearance")
	var definition: Dictionary = Art.environment_definition(biome, id)
	_mapping(room, definition, biome, id, label)
	_hud(room, hud, hero, label)
	var geometry_before := var_to_str([room.ground_polygon, room.obstructions, room.layout.entry, room.exit_position, room.encounter_zones])
	room.process_mode = Node.PROCESS_MODE_INHERIT
	room.set_input_blocked(false)
	_release_all()
	await _frames(3)
	await _movement(room, label)
	room.set_input_blocked(true)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	if bool(entry.capture):
		await _views(room, hud, hero, id, biome)
	else:
		await _draw()
	_identity(room.player, hero, label)
	if biome == "B10":
		_native_details(room, definition, id, label)
		if hero == HEROES[0] and id == "L55":
			_native_bodies(room)
			await _native_props(room)
		if id == "L55": await _combat(room, hud, hero)
	check(geometry_before == var_to_str([room.ground_polygon, room.obstructions, room.layout.entry, room.exit_position, room.encounter_zones]), label + " views/input leave authored coordinates unchanged")
	records.append({"hero": hero, "room_id": id, "biome_id": biome, "texture": definition.get("path", ""), "camera_bounds": var_to_str(room.camera.render_bounds), "zoom": var_to_str(room.camera.zoom), "ground_vertices": room.ground_polygon.size(), "hero_source": room.player.get_meta("hero_visual_source", ""), "input": "mapped key and viewport click events through production physics"})
	_release_all()
	check(await room.combat_audio.wait_for_cleanup(), label + " audio cleanup")
	hud_layer.free()
	room.free()
	await _frames(2)

func _mapping(room: Node2D, definition: Dictionary, biome: String, id: String, label: String) -> void:
	var painting_ready: bool = not definition.is_empty() and bool(definition.get("room_specific", false)) and definition.get("texture") != null and definition.has("placement_normalized_rect")
	check(painting_ready, label + " independently registered room painting without faction fallback")
	if not painting_ready: return
	var path := str(definition.get("path", ""))
	if not original_paths.has(id):
		check(not original_paths.values().has(path), label + " background is independent of other rooms")
		original_paths[id] = path
	else: check(original_paths[id] == path, label + " profession reuses the same authored painting")
	var bounds: Rect2 = Art.environment_world_rect(room.layout.arena, biome, id)
	var backdrop: Node2D = room.get_node("MineBackdrop")
	check(bounds.has_area() and backdrop.environment_world_rect.is_equal_approx(bounds) and room.camera.render_bounds.is_equal_approx(bounds), label + " backdrop and camera share painting coordinates")
	check(_same_polygon(room.ground_polygon, Art.environment_ground_polygon(room.layout.arena, biome, id)), label + " actual passage edge comes from the painting mapping")
	check(is_equal_approx(room.camera.zoom.x, room.camera.zoom.y), label + " camera has uniform scale")
	var anchors := {"entry": room.layout.entry, "exit": room.exit_position}
	for index: int in room.encounter_zones.size(): anchors["encounter_" + str(index)] = Vector2(room.encounter_zones[index].get("center", room.layout.entry))
	if biome == "B10":
		var source := Geometry.room(id)
		var placement: Rect2 = definition.placement_normalized_rect
		check(room.ground_polygon == Geometry.polygon(id), label + " B10 authoritative authored ground")
		var blueprint_points: Array = source.walkable_polygon + source.main_route + [source.entry, source.exit, source.dragon_spawn]
		for kind: String in ["gates", "star_cores", "scenery_anchors"]:
			for point: Dictionary in source.get(kind, []):
				blueprint_points.append(point.position)
				anchors[str(point.id)] = Geometry.world_point(point.position)
		anchors["dragon"] = Geometry.world_point(source.dragon_spawn)
		for pixel: Array in blueprint_points:
			var blueprint := Vector2(float(pixel[0]), float(pixel[1]))
			var normalized := placement.position + blueprint / Vector2(2800, 1800) * placement.size
			check(Art.environment_point(room.layout.arena, biome, normalized, id).distance_to(blueprint * .58) < .003, label + " source/route/portal/core/dragon point shares blueprint transform " + str(pixel))
		var background_hash := str(definition.metadata.get("source_sha256", ""))
		if background_hash.is_empty():
			var provenance := _json(AssetCatalog.resolve(str(definition.manifest_path)).get_base_dir().path_join("environment.prompt.json"))
			background_hash = str(provenance.get("sha256", provenance.get("source_sha256", "")))
		_source_image(path, definition.metadata.get("source_size", []), background_hash, label + " background")
	for key: String in anchors:
		var world: Vector2 = anchors[key]
		check(bounds.has_point(world), label + " functional point lies within the original painting: " + key)
		if not key.ends_with("landmark"): check(room.valid_ground(world, RADIUS), label + " functional point has legal ground: " + key)

func _same_polygon(actual: PackedVector2Array, expected: PackedVector2Array) -> bool:
	if actual.size() != expected.size() or actual.size() < 3: return false
	for index: int in actual.size():
		if actual[index].distance_to(expected[index]) >= .003: return false
	return true

func _hud(room: Node2D, hud: Control, hero: String, label: String) -> void:
	hud.refresh()
	var view: Dictionary = room.player.combat_hud_view()
	check(str(view.get("hero_id", "")) == hero and str(hud.hero_definition.get("id", "")) == hero and hud.hero_bust.hero_id == hero, label + " HUD and portrait read actual profession")
	check(is_equal_approx(hud.health_bar.value, Game.run.hp) and is_equal_approx(hud.health_bar.max_value, Game.run.max_hp) and is_equal_approx(hud.resource_bar.value, Game.run.resource) and is_equal_approx(hud.resource_bar.max_value, float(view.resource_max)), label + " real HP and resource meters")
	check(is_equal_approx(hud.shield_bar.value, Game.run.shield), label + " real shield meter")
	check(hud.passive_snapshot == room.player.class_state_snapshot(), label + " real profession kit state")
	check(view.slots.size() == 4 and hud.skill_slots.size() == 5, label + " four real skills plus dodge")
	for slot: Dictionary in view.slots:
		var info: Dictionary = hud.skill_info(str(slot.input_slot), view)
		check(str(info.get("skill_id", "")) == str(slot.skill_id) and is_equal_approx(float(info.cost), float(slot.cost)) and is_equal_approx(float(info.cooldown), float(slot.remaining)), label + " HUD reads actual slot identity/cost/cooldown " + str(slot.skill_id))
	for rect: Rect2 in hud.coverage_rects(): check(get_viewport().get_visible_rect().encloses(rect), label + " HUD coverage stays inside logical viewport")

func _identity(player: Node2D, hero: String, label: String) -> void:
	check(str(player.get_meta("hero_visual_source", "")).begins_with("asset://heroes/" + hero.to_lower() + "_poses_") and int(player.get_meta("hero_visual_frame", -1)) >= 0, label + " actual drawing uses its current native profession body")
	check(SharedArt.DIRECTIONS.has(str(player.get_meta("hero_directional_key", ""))) and float(player.get_meta("hero_visual_flip", 0.0)) == 1.0 and Vector2(player.get_meta("hero_foot_local", Vector2.INF)).is_equal_approx(Vector2(0, 8)), label + " authored eight-direction identity and ground foot")

func _movement(room: Node2D, label: String) -> void:
	room.player.position = room.layout.entry
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await _frames(3)
	check(room.controls_enabled(), label + " production controls released")
	var navigation: RefCounted = room.player.click_navigation
	check(navigation.request(room.player.position, room.exit_position, RADIUS) and not navigation.path.is_empty(), label + " production route reaches exit")
	var previous: Vector2 = room.player.position
	for point: Vector2 in navigation.path:
		check(room.valid_ground(point, RADIUS) and (room.blocked_fraction(previous, point, RADIUS) >= 1.0 or navigation._segment_clear(previous, point, RADIUS)), label + " real route waypoint and swept player radius")
		previous = point
	navigation.cancel()
	_aim(room, room.exit_position)
	await _tap("click_move")
	check(navigation.is_active(), label + " mapped right mouse starts real movement path")
	var start: Vector2 = room.player.position
	await _frames(8)
	check(room.player.position.distance_to(start) > 3.0 and room.valid_ground(room.player.position, RADIUS), label + " actual click input advances lawful production physics")
	room.player.clear_movement_target()
	var direction := Vector2.ZERO
	for candidate: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if room.valid_ground(room.player.position + candidate * 40, RADIUS) and room.blocked_fraction(room.player.position, room.player.position + candidate * 40, RADIUS) >= 1.0:
			direction = candidate
			break
	check(not direction.is_zero_approx(), label + " legal keyboard movement segment")
	if direction.is_zero_approx(): return
	start = room.player.position
	var action: String = {Vector2.RIGHT: "move_right", Vector2.LEFT: "move_left", Vector2.UP: "move_up", Vector2.DOWN: "move_down"}[direction]
	_mapped_input(action, true)
	await _frames(6)
	_mapped_input(action, false)
	check(room.player.position.distance_to(start) > 1.0 and room.valid_ground(room.player.position, RADIUS), label + " mapped keyboard advances lawful production physics")

func _native_details(room: Node2D, definition: Dictionary, id: String, label: String) -> void:
	var geometry := Geometry.room(id)
	var rendered: Array = room.objectives.get_meta("b10_native_props", []) if is_instance_valid(room.objectives) else []
	check(rendered.count("stargate") == geometry.get("gates", []).size(), label + " production objectives draw every native stargate")
	for anchor: Dictionary in geometry.get("scenery_anchors", []):
		var key := str(anchor.key)
		if str(anchor.get("render_mode", "")) == "independent_sprite": check(rendered.has(key), label + " production objectives draw independent native landmark " + key)
		else: check(not rendered.has(key), label + " baked scenery does not receive a duplicate sprite " + key)
	if definition.is_empty() or definition.get("texture") == null: return
	var backdrop: Node2D = room.get_node("MineBackdrop")
	var chunks: Node2D = backdrop.environment_chunks
	var detail: Node2D = chunks.native_detail if is_instance_valid(chunks) else null
	check(is_instance_valid(detail) and detail.active_room_id == id and detail.tiles.size() == 6 and detail.resident_bytes > 0, label + " all six native detailed repaints resident, no mother-only fallback")
	if not is_instance_valid(detail): return
	var manifest := _json("asset://world/rooms_2k/" + id + "/manifest.json")
	check(manifest.get("tiles", []).size() == 6 and manifest.get("room_id", "") == id, label + " correct native detail source manifest")
	if manifest.get("tiles", []).size() != 6 or detail.tiles.size() != 6: return
	var source_size: Array = manifest.get("source_size", [])
	check(source_size.size() == 2 and float(source_size[0]) > 0 and float(source_size[1]) > 0, label + " detail manifest records two valid native source dimensions")
	if source_size.size() != 2 or float(source_size[0]) <= 0 or float(source_size[1]) <= 0: return
	var destination: Rect2 = Art.environment_world_rect(room.layout.arena, "B10", id)
	var source := Vector2(float(source_size[0]), float(source_size[1]))
	var distinct := {}
	for index: int in detail.tiles.size():
		var sprite: Sprite2D = detail.tiles[index]
		var tile: Dictionary = manifest.tiles[index]
		check(is_instance_valid(sprite) and sprite.texture != null, label + " detailed tile has a loaded source texture " + str(index))
		if not is_instance_valid(sprite) or sprite.texture == null: continue
		var region: Array = tile.source_rect
		var reference := Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		var expected := Rect2(destination.position + reference.position / source * destination.size, reference.size / source * destination.size)
		var actual := Rect2(sprite.position, sprite.region_rect.size * sprite.scale if sprite.region_enabled else sprite.texture.get_size() * sprite.scale)
		check(sprite.texture != null and sprite.texture != definition.texture and sprite.texture.get_image().has_mipmaps(), label + " detail owns native independent mipmapped pixels " + str(index))
		distinct[sprite.texture.get_instance_id()] = true
		check(actual.is_equal_approx(expected) and is_equal_approx(sprite.scale.x, sprite.scale.y), label + " detail has uniform source-to-ground mapping " + str(index))
		var screen: Transform2D = get_viewport().get_final_transform() * sprite.get_global_transform_with_canvas()
		check(screen.x.length() <= 1.0001 and screen.y.length() <= 1.0001 and is_equal_approx(screen.x.length(), screen.y.length()), label + " actual 2K final/canvas/detail scale never stretches or enlarges source pixels " + str(index))
		var native: Array = tile.get("native_size", [])
		check(native.size() == 2 and mini(int(native[0]), int(native[1])) >= 1254, label + " native detail meets original source pixel budget " + str(index))
		_source_image(str(tile.texture), native, str(tile.get("generated_png_sha256", "")), label + " detail " + str(index))
	check(distinct.size() == 6, label + " six distinct native textures")

func _native_bodies(room: Node2D) -> void:
	var ids: Array = Content.enemy_ids()
	for index: int in range(1, 7): ids.append("B10-D%02d" % index)
	ids.append("BO10")
	var finale := Skills.boss_definition("BO10")
	check(ids.size() == 25 and int(finale.get("heads", 0)) == 1 and int(finale.get("head_count", 0)) == 1 and str(finale.get("name", "")) == "星冠古龙", "eighteen ordinary identities, six guardians and the single-headed Starcrown Ancient Dragon")
	var seen := {}
	for id: String in ids:
		var frame: Dictionary = NativeArt.frame(id)
		check(not frame.is_empty() and frame.get("texture") != null and str(frame.get("texture_path", "")) == Skills.art_id(id) and frame.get("source_family", "") == "b10_bright_handpainted_2_5d", id + " production native single pose loads without fallback")
		if frame.is_empty() or frame.get("texture") == null: continue
		var path := AssetCatalog.resolve(str(frame.texture_path))
		seen[path] = true
		var provenance: Dictionary = frame.get("source_metadata", {})
		check(not provenance.is_empty(), id + " production frame reads canonical source provenance")
		var dimensions: Array = provenance.get("source_size", provenance.get("actual_dimensions", provenance.get("native_dimensions", [])))
		_source_image(str(frame.texture_path), dimensions, str(provenance.get("sha256", "")), id + " body")
		var factor := float(frame.get("scale", 0.0))
		var screen: Transform2D = get_viewport().get_final_transform() * room.player.get_global_transform_with_canvas()
		check(factor > 0 and factor * screen.x.length() <= 1.0001 and factor * screen.y.length() <= 1.0001 and is_equal_approx(screen.x.length(), screen.y.length()), id + " body reduces uniformly under actual 2K final/canvas transform")
		var source_foot: Vector2 = frame.get("source_foot_px", Vector2.INF)
		check(source_foot.is_finite() and (frame.bounds.position + source_foot * factor).is_zero_approx(), id + " source ground foot projects onto actor contact point")
		body_records.append({"id": id, "texture": frame.texture_path, "native_size": dimensions, "scale": factor, "source_foot_px": var_to_str(source_foot), "pose_count": 1, "provenance": "production NativeArt source_metadata"})
	check(seen.size() == 25, "all native body identities have independent source files")

func _native_props(room: Node2D) -> void:
	var gallery := Node2D.new()
	gallery.name = "ControlledNativePropGallery"
	room.add_child(gallery)
	room.player.position = room.clamp_actor(room.layout.arena.get_center(), RADIUS)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	var keys := ["stargate", "star_core", "survey_spire", "triune_obelisk"]
	for index: int in keys.size():
		var key: String = keys[index]
		var frame: Dictionary = NativeArt.props_frame(key)
		check(not frame.is_empty() and frame.get("texture") != null and str(frame.get("texture_path", "")) == "asset://level.b10.decorations." + key, key + " production native scene-object frame loads without fallback")
		if frame.is_empty() or frame.get("texture") == null: continue
		var provenance: Dictionary = frame.get("source_metadata", {})
		var dimensions: Array = provenance.get("source_size", provenance.get("actual_dimensions", provenance.get("native_dimensions", [])))
		_source_image(str(frame.texture_path), dimensions, str(provenance.get("sha256", "")), key + " scene object")
		var foot: Vector2 = room.player.position + Vector2((index - 1.5) * 140, 130)
		var sprite := Sprite2D.new()
		sprite.texture = frame.texture
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = frame.region
		sprite.position = foot + frame.bounds.position
		sprite.scale = Vector2.ONE * float(frame.scale)
		gallery.add_child(sprite)
		var source_foot: Vector2 = frame.get("source_foot_px", Vector2.INF)
		check(source_foot.is_finite() and (sprite.position + source_foot * sprite.scale).is_equal_approx(foot), key + " native scene-object source foot and world anchor agree")
		var screen: Transform2D = get_viewport().get_final_transform() * sprite.get_global_transform_with_canvas()
		check(is_equal_approx(sprite.scale.x, sprite.scale.y) and is_equal_approx(screen.x.length(), screen.y.length()) and screen.x.length() <= 1.0001 and screen.y.length() <= 1.0001, key + " actual scene-object 2K drawing never stretches or enlarges native pixels")
		prop_records.append({"key": key, "texture": frame.texture_path, "native_size": dimensions, "source_foot_px": var_to_str(source_foot), "screen_scale": screen.x.length(), "scope": "controlled gallery using production NativeArt.props_frame"})
	await _capture("B10_native_props_gallery")
	for child: Node in gallery.get_children(): check(child is Sprite2D and child.visible and child.texture != null, "native scene-object exists in actual GPU drawing tree")
	gallery.free()

func _combat(room: Node2D, hud: Control, hero: String) -> void:
	# The fixture exercises one B10 room per profession. All 36 skill identities
	# have their own existing direct suite; this matrix checks the four real slots.
	room.process_mode = Node.PROCESS_MODE_INHERIT
	room.set_input_blocked(false)
	_release_all()
	await _frames(3)
	var base: Vector2 = room.clamp_actor(room.layout.arena.get_center(), RADIUS)
	room.player.position = base
	var target: Node2D = room.spawn_enemy(base + Vector2(80, 0), "B10-M01", 46, {"profile": Skills.profile("B10-M01", 46, 0), "reward_enabled": false})
	check(is_instance_valid(target), hero + " real B10 damage target spawns")
	if not is_instance_valid(target): return
	target.training_ai_disabled = true
	target.reward_enabled = false
	target.health.reset(1000000.0)
	target.state = &"chase"
	room.player.invulnerable = 60.0
	room.player.skill_input_feedback.connect(_observe_skill)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await _frames(4)
	_aim(room, target.position)
	var hp_before: float = target.health.current
	var shots_before: int = room.telemetry.shots
	_mapped_input("attack", true)
	await _frames(60)
	_mapped_input("attack", false)
	check(room.telemetry.shots > shots_before and target.health.current < hp_before, hero + " actual mapped primary damages a B10 species")
	var result := {"hero": hero, "room_id": "L55", "primary_damage": hp_before - target.health.current, "skills": [], "fixture": "durable reward-disabled target, explicit resource/cooldown refills and reposition; not natural combat balance"}
	await _frames(30)
	for slot: String in ["q", "secondary", "f", "ultimate"]:
		room.player.cancel_actions()
		room.player.position = base
		target.position = base + Vector2(80, 0)
		Game.run.resource = float(Game.run.stats.resource_max)
		var spec: Dictionary = room.player.abilities.spec(slot)
		var identity := str(spec.get("skill_id", ""))
		room.player.cooldowns[identity] = 0.0
		skill_events.clear()
		var resource_before: float = Game.run.resource
		var shield_before: float = Game.run.shield
		hp_before = target.health.current
		_aim(room, target.position)
		await _tap("skill_" + slot)
		var accepted := skill_events.any(func(event: Dictionary) -> bool: return event.slot == slot and event.reason == "accepted")
		check(accepted and room.player.skill_cooldown(slot) > 0, hero + " mapped " + slot + " commits real identity cooldown")
		var minimum_resource: float = Game.run.resource
		var best_shield: float = Game.run.shield
		var until := Time.get_ticks_msec() + int(clampf(float(spec.get("duration", 2.0)) + .6, 2.0, 6.0) * 1000)
		while Time.get_ticks_msec() < until:
			await _frames(1)
			minimum_resource = minf(minimum_resource, Game.run.resource)
			best_shield = maxf(best_shield, Game.run.shield)
		var damage: float = hp_before - target.health.current
		var paid: float = resource_before - minimum_resource
		var guard: float = best_shield - shield_before
		check(damage > 0 or guard > 0 or paid > 0, hero + " " + identity + " resolves actual damage/guard/resource effect")
		if identity in ["CH01_SK03", "CH03_SK03"]: check(guard > 0, hero + " authored defensive skill resolves shield")
		else: check(damage > 0, hero + " authored offensive skill resolves B10 damage")
		result.skills.append({"slot": slot, "skill_id": identity, "accepted": accepted, "damage": damage, "shield_gain": guard, "resource_spent": paid, "feedback": skill_events.duplicate(true)})
		hud.refresh()
		_hud(room, hud, hero, hero + "/L55 after " + identity)
	combat_records.append(result)
	room.player.skill_input_feedback.disconnect(_observe_skill)
	room.set_input_blocked(true)
	room.process_mode = Node.PROCESS_MODE_DISABLED

func _views(room: Node2D, hud: Control, hero: String, id: String, biome: String) -> void:
	var points := {"center": Vector2(.5, .5)}
	if biome == "B10" and hero == HEROES[0]: points.merge({"northwest": Vector2(.14, .16), "northeast": Vector2(.86, .16), "southwest": Vector2(.14, .84), "southeast": Vector2(.86, .84)})
	for view: String in points:
		room.player.position = room.clamp_actor(room.layout.arena.position + room.layout.arena.size * points[view], RADIUS)
		if not room.valid_ground(room.player.position, RADIUS): room.player.position = room.layout.entry
		room.camera.follow_target()
		room.camera.force_update_scroll()
		hud.visible = view == "center"
		hud.refresh()
		await _capture(hero + "_" + id + "_" + view)
		hud.show()

func _json(path: String) -> Dictionary:
	var resolved := AssetCatalog.resolve(path)
	check(FileAccess.file_exists(resolved), "source manifest exists: " + path)
	if not FileAccess.file_exists(resolved): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	check(value is Dictionary, "source manifest parses: " + path)
	return value if value is Dictionary else {}

func _source_image(path: String, expected_size: Array, expected_hash: String, label: String) -> void:
	var resolved := AssetCatalog.resolve(path)
	check(FileAccess.file_exists(resolved), label + " registered source PNG exists")
	if not FileAccess.file_exists(resolved): return
	if not source_files.has(resolved):
		var bytes := FileAccess.get_file_as_bytes(resolved)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		var image := Image.new()
		var decoded := image.load_png_from_buffer(bytes) == OK
		check(decoded, label + " original PNG bytes decode")
		source_files[resolved] = {"sha256": digest.finish().hex_encode(), "size": [image.get_width(), image.get_height()] if decoded else []}
	var actual: Dictionary = source_files[resolved]
	# JSON numbers and Image dimensions carry different Variant number types.
	# Compare exact numeric components without truncating fractional metadata.
	check(expected_size.size() == 2 and actual["size"].size() == 2 and float(actual["size"][0]) == float(expected_size[0]) and float(actual["size"][1]) == float(expected_size[1]), label + " actual source dimensions match provenance")
	check(expected_hash.length() == 64 and actual.sha256 == expected_hash, label + " original PNG SHA256 matches generation provenance")

func _observe_skill(slot: String, reason: String, details: Dictionary) -> void:
	skill_events.append({"slot": slot, "reason": reason, "details": details.duplicate(true)})

func _frames(count: int = 1) -> void:
	for index: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _draw() -> void:
	await _frames(3)
	RenderingServer.force_draw(false)

func _capture(label: String) -> void:
	await _draw()
	var image := get_viewport().get_texture().get_image()
	check(image.get_size() == Vector2i(2560, 1440), label + " actual GPU framebuffer is 2560x1440")
	check(image.save_png(output.path_join(label + "_2560x1440.png")) == OK, label + " direct framebuffer saved in managed output")
	captures.append(label)

func _aim(room: Node2D, at: Vector2) -> void:
	mouse_at = room.get_canvas_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = mouse_at
	motion.global_position = mouse_at
	get_viewport().push_input(motion, true)

func _mapped_input(action: String, pressed: bool) -> void:
	var bindings := InputMap.action_get_events(action)
	if bindings.is_empty():
		check(false, "mapped input exists: " + action)
		return
	var event: InputEvent = bindings[0].duplicate()
	if event is InputEventMouseButton:
		event.position = mouse_at
		event.global_position = mouse_at
		event.pressed = pressed
	elif event is InputEventKey:
		event.pressed = pressed
		event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _release_all() -> void:
	for action: String in INPUTS: _mapped_input(action, false)

func _tap(action: String) -> void:
	_mapped_input(action, true)
	await _frames(1)
	_mapped_input(action, false)
