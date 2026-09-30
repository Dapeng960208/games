class_name RoomProps
extends Node2D
## Room-owned, single-tick props. Buff sources never survive configure/clear.
## Utility success means an authored, visible entity was actually changed.

const Layouts = preload("res://scripts/world/room_layouts.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Appearance = preload("res://scripts/world/room_appearance.gd")
const Art = preload("res://scripts/world/world_art.gd")
const PropArt = preload("res://scripts/world/world_prop_art.gd")
const BeaconBody = preload("res://scripts/world/room_beacon_body.gd")
const BEACON_RADIUS := 72.0
const BEACON_RECHARGE := 45.0
const BEACON_EFFECTS := ["heal", "resource", "damage", "guard", "haste"]
const GUARD_SOURCE := "room_prop:guard"
const BUFFS := {
	"heal": {"name":"复苏信标", "name_en":"Restoration beacon", "description":"恢复生命上限25%的生命", "description_en":"Restore 25% maximum HP", "duration":0.0, "color":Color("ee8eab")},
	"resource": {"name":"源能信标", "name_en":"Resource beacon", "description":"恢复职业资源上限30%的资源", "description_en":"Restore 30% class resource", "duration":0.0, "color":Color("65b9e0")},
	"damage": {"name":"战意信标", "name_en":"Valor beacon", "description":"攻击加成 +20% · 15秒", "description_en":"Attack bonus +20% · 15s", "duration":15.0, "color":Color("ec976e")},
	"guard": {"name":"守护信标", "name_en":"Guardian beacon", "description":"获得生命上限25%的护盾 · 15秒", "description_en":"Shield for 25% maximum HP · 15s", "duration":15.0, "color":Color("70cfb6")},
	"haste": {"name":"迅行信标", "name_en":"Swiftness beacon", "description":"移动速度 +15% · 12秒", "description_en":"Movement speed +15% · 12s", "duration":12.0, "color":Color("ecc36d")}
}

var room: Node2D
var layout: Dictionary = {}
var biome_id: String = "B01"
var room_id: String = ""
var props: Array[Dictionary] = []
var entities: Array[Dictionary] = []
var obstacle_recipes: Array = []
var buffs: Dictionary = {}
var stolen: Dictionary = {}
var elapsed: float = 0.0
var _buff_player: WeakRef
var _font: Font
var _loot_serial: int = 0
var _displacement_until: Dictionary = {}
var _wall_break_counts: Dictionary = {}
var _wall_break_limits: Dictionary = {}
var _placement_rng := RandomNumberGenerator.new()
var _beacon_rng := RandomNumberGenerator.new()
var configuration_errors: Array[String] = []
var _beacon_layer: Node2D
var _beacon_bodies: Array[Node2D] = []
var _entity_bodies: Dictionary = {}

func _ready() -> void:
	_ensure_beacon_layer()

func configure(owner_room: Node2D, room_layout: Dictionary) -> bool:
	clear()
	room = owner_room
	layout = room_layout.duplicate(true)
	room_id = str(layout.get("room_id", ""))
	biome_id = str(Catalog.room(room_id).get("biome_id", "B01"))
	_placement_rng.seed = int(layout.get("seed", hash(room_id))) ^ 0x524F4F4D
	_beacon_rng.seed = int(layout.get("seed", hash(room_id))) ^ 0x42454143
	obstacle_recipes = Appearance.recipe(layout, biome_id)
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		_font = load("res://assets/fonts/NotoSansSC.ttf")
	z_index = 1
	material = Art.material_for(biome_id)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)
	set_physics_process(false)
	if layout.is_empty():
		configuration_errors.append("Missing room layout")
		return false
	# Three flush, non-colliding beacons keep their positions for this room.
	# A separate random stream changes only their function, never geometry.
	var occupied: Array[Vector2] = []
	for ordinal: int in 3:
		var anchor: Dictionary = _find_position(occupied, props.size(), true)
		if anchor.is_empty():
			configuration_errors.append("No reachable separated beacon position "+str(ordinal)+" in "+room_id+" seed "+str(layout.get("seed",0)))
			push_error(configuration_errors.back())
			return false
		var effect: String = _roll_beacon_effect()
		var item: Dictionary = BUFFS[effect].duplicate(true)
		item.merge({"id":room_id + ":beacon:" + str(ordinal), "kind":"beacon", "effect":effect, "position":anchor.position, "anchor":anchor.anchor, "used":false, "remaining":0.0, "available":true, "cooldown":0.0, "generation":0, "activations":0, "armed":true})
		props.append(item)
		occupied.append(anchor.position)
	_build_world_entities(occupied)
	if is_inside_tree(): _ensure_beacon_layer()
	queue_redraw()
	return true

func clear() -> void:
	_remove_beacon_layer()
	if _buff_player != null:
		var actor: Node2D = _buff_player.get_ref()
		if is_instance_valid(actor):
			var actor_status: Variant = actor.get("status")
			if actor_status != null:
				actor_status.guards.erase(GUARD_SOURCE)
				_sync_player_shield(actor_status)
	_buff_player = null
	buffs.clear()
	props.clear()
	entities.clear()
	obstacle_recipes.clear()
	stolen.clear()
	_displacement_until.clear()
	_wall_break_counts.clear()
	_wall_break_limits.clear()
	configuration_errors.clear()
	elapsed = 0.0

func _exit_tree() -> void:
	# Sibling layer removal is deferred during tree exit to avoid editing the
	# room's child list while it is already tearing down that list.
	if is_instance_valid(_beacon_layer):
		_beacon_layer.visible = false
		_beacon_layer.queue_free()
	_beacon_layer = null
	_beacon_bodies.clear()
	_entity_bodies.clear()
	clear()

func _remove_beacon_layer() -> void:
	if is_instance_valid(_beacon_layer):
		var parent: Node = _beacon_layer.get_parent()
		if parent != null: parent.remove_child(_beacon_layer)
		_beacon_layer.free()
	_beacon_layer = null
	_beacon_bodies.clear()
	_entity_bodies.clear()

func _ensure_beacon_layer() -> void:
	if is_instance_valid(_beacon_layer) or not is_instance_valid(room) or props.is_empty(): return
	_beacon_layer = Node2D.new()
	_beacon_layer.name = "BeaconBodies"
	_beacon_layer.z_index = 2
	_beacon_layer.y_sort_enabled = true
	_beacon_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	room.add_child(_beacon_layer)
	for item: Dictionary in props:
		var body := BeaconBody.new()
		body.source = self
		body.item = item
		body.position = item.position
		_beacon_layer.add_child(body)
		_beacon_bodies.append(body)
	for entity: Dictionary in entities:
		if entity.has("recipe_index") or entity_art_key(entity).is_empty(): continue
		var body := BeaconBody.new()
		body.source = self
		body.item = entity
		body.draw_method = &"draw_entity_body"
		body.position = entity.position
		_beacon_layer.add_child(body)
		_beacon_bodies.append(body)
		_entity_bodies[str(entity.id)] = body

func _paused() -> bool:
	return is_inside_tree() and get_tree().paused

func update(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _paused():
		return
	elapsed += delta
	for effect: String in buffs.keys():
		buffs[effect].remaining = maxf(0.0, float(buffs[effect].remaining) - delta)
		if float(buffs[effect].remaining) <= 0.0:
			buffs.erase(effect)
	for entity: Dictionary in entities:
		entity["cooldown"] = maxf(0.0, float(entity.get("cooldown", 0.0)) - delta)
		if float(entity.get("dark_remaining", 0.0)) > 0.0:
			entity.dark_remaining = maxf(0.0, float(entity.dark_remaining) - delta)
			var carrier: Object = instance_from_id(int(entity.get("taken_by", 0)))
			if not is_instance_valid(carrier) or (carrier.has_method("is_alive") and not carrier.is_alive()):
				entity.dark_remaining = 0.0
			if entity.dark_remaining <= 0.0:
				entity["taken_by"] = 0
	for instance_id: int in stolen.keys():
		var owner: Object = instance_from_id(instance_id)
		if not is_instance_valid(owner) or (owner.has_method("is_alive") and not owner.is_alive()):
			return_stolen(instance_id)
	for instance_id: int in _wall_break_counts.keys():
		if not is_instance_valid(instance_from_id(instance_id)):
			_wall_break_counts.erase(instance_id)
			_wall_break_limits.erase(instance_id)
	for item: Dictionary in props:
		item.remaining = float(buffs.get(item.effect, {}).get("remaining", 0.0)) if item.used else 0.0
		_update_beacon(item, delta)
	for body: Node2D in _beacon_bodies:
		if is_instance_valid(body):
			body.position = body.item.position
			body.visible = bool(body.item.get("enabled",true))
			body.update_depth(delta)
			body.queue_redraw()
	queue_redraw()

func _roll_beacon_effect() -> String:
	return str(BEACON_EFFECTS[_beacon_rng.randi_range(0, BEACON_EFFECTS.size() - 1)])

func _refresh_beacon(item: Dictionary) -> void:
	var effect: String = _roll_beacon_effect()
	item.merge(BUFFS[effect].duplicate(true), true)
	item.merge({"effect":effect, "used":false, "available":true, "remaining":0.0, "cooldown":0.0, "generation":int(item.generation) + 1}, true)

func _update_beacon(item: Dictionary, delta: float) -> void:
	var actor: Node2D = room.get("player") if is_instance_valid(room) else null
	var near: bool = is_instance_valid(actor) and actor.position.distance_to(item.position) <= BEACON_RADIUS and _line_clear(actor.position, item.position)
	if not near:
		item.armed = true
	if float(item.cooldown) > 0.0:
		item.cooldown = maxf(0.0, float(item.cooldown) - delta)
		if float(item.cooldown) <= 0.0:
			_refresh_beacon(item)
			# Standing on a dormant beacon never repeatedly harvests it. A
			# refreshed beacon accepts the next approach after leaving its ring.
			item.armed = not near
		return
	if not near or bool(item.used) or not bool(item.armed) or not _living_player(actor):
		return
	if not grant_buff(str(item.effect), actor):
		# Full HP/resource keeps a ready beacon intact. If the actor needs it
		# later while nearby, the first real restoration consumes it once.
		return
	item.used = true
	item.available = false
	item.armed = false
	item.cooldown = BEACON_RECHARGE
	item.remaining = float(BUFFS[item.effect].duration)
	item.activations = int(item.activations) + 1
	if is_instance_valid(room) and room.has_method("add_ring"):
		room.add_ring(item.position, item.color, BEACON_RADIUS, 0.32)

func _living_player(player: Node2D) -> bool:
	if not is_instance_valid(player): return false
	var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if game != null and game.run != null:
		return float(game.run.hp) > 0.0
	return player.is_alive() if player.has_method("is_alive") else false

func active_buffs() -> Array:
	var result: Array = []
	for effect: String in buffs:
		var item: Dictionary = buffs[effect].duplicate(true)
		if effect == "guard" and _buff_player != null:
			var actor: Node2D = _buff_player.get_ref()
			if not is_instance_valid(actor) or not actor.status.guards.has(GUARD_SOURCE):
				continue
			item["amount"] = float(actor.status.guards[GUARD_SOURCE].amount)
		result.append(item)
	return result

func damage_bonus() -> float:
	return 0.20 if buffs.has("damage") else 0.0

func move_multiplier() -> float:
	return 1.15 if buffs.has("haste") else 1.0

func resource_regen_multiplier() -> float:
	return 1.0

func nearest_interaction(_player_pos: Vector2) -> Dictionary:
	# Beacons use proximity, so they never compete with tasks/supplies for E.
	return {}

func interact(_id: String, _player: Node2D) -> Dictionary:
	return {"success":false, "reason":"automatic_proximity"}

func grant_buff(effect: String, player: Node2D) -> bool:
	if not BUFFS.has(effect) or not is_instance_valid(player) or _paused():
		return false
	if not _living_player(player): return false
	var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if effect == "heal":
		if game == null or game.run == null or not player.has_method("heal"): return false
		return float(player.heal(float(game.run.max_hp) * 0.25)) > 0.0
	if effect == "resource":
		if game == null or game.run == null: return false
		return float(game.restore_resource(float(game.run.stats.get("resource_max", 0.0)) * 0.30)) > 0.0
	if effect == "guard":
		var maximum: float = player.stat("max_hp", 100.0) if player.has_method("stat") else 100.0
		if game != null and game.run != null:
			maximum = float(game.run.max_hp)
		if not player.has_method("grant_guard"):
			return false
		player.grant_guard(maximum * 0.25, 15.0, GUARD_SOURCE)
		var actor_status: Variant = player.get("status")
		if actor_status == null or not actor_status.guards.has(GUARD_SOURCE):
			return false
	_buff_player = weakref(player)
	# Assignment refreshes one source: same-kind devices never multiply stacks.
	buffs[effect] = BUFFS[effect].duplicate(true)
	buffs[effect].merge({"effect":effect, "id":"room_prop:" + effect, "remaining":float(BUFFS[effect].duration)})
	return true

func _sync_player_shield(actor_status: Variant) -> void:
	var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if game != null and game.run != null:
		game.run.shield = actor_status.shield()

func draw_floor(canvas: CanvasItem) -> void:
	Appearance.draw_floor(canvas, layout, biome_id, elapsed)
	# Floor-only shading is submitted before obstacles, actors and telegraphs.
	# It must never be moved to the prop/interaction foreground canvas.
	for entity: Dictionary in entities:
		if str(entity.kind) == "scene_lamp" and float(entity.get("dark_remaining", 0.0)) > 0.0:
			canvas.draw_circle(entity.position, float(entity.get("dark_radius",110.0)), Color(0.17,0.26,0.31,0.15))

func draw_obstacles(canvas: CanvasItem) -> void:
	Appearance.draw_ground_obstacles(canvas, obstacle_recipes, elapsed)

func collision_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.assign(layout.get("obstructions", []))
	return result

func effective_layout() -> Dictionary:
	return layout.duplicate(true)

func _clear_point(point: Vector2, radius: float = 26.0) -> bool:
	return Layouts.clear_for_actor(layout, point, radius)

func _line_clear(start: Vector2, finish: Vector2, radius: float = 0.0, ignored: Rect2 = Rect2()) -> bool:
	# Continuous slab test also handles diagonal interaction rays.
	if radius <= 0.0 and not ignored.has_area() and is_instance_valid(room) and room.has_method("has_line_of_sight"):
		return room.has_line_of_sight(start, finish)
	var offset: Vector2 = finish - start
	for obstacle: Rect2 in layout.get("obstructions", []):
		if obstacle == ignored and ignored.has_area():
			continue
		var box: Rect2 = obstacle.grow(radius)
		var near: float = 0.0
		var far: float = 1.0
		var intersects: bool = true
		for axis: int in range(2):
			if absf(offset[axis]) < 0.00001:
				if start[axis] < box.position[axis] or start[axis] > box.end[axis]:
					intersects = false
					break
			else:
				var a: float = (box.position[axis] - start[axis]) / offset[axis]
				var b: float = (box.end[axis] - start[axis]) / offset[axis]
				near = maxf(near, minf(a, b))
				far = minf(far, maxf(a, b))
				if near > far:
					intersects = false
					break
		if intersects and far >= 0.0 and near <= 1.0:
			return false
	return true

func _find_position(occupied: Array[Vector2], ordinal: int = 0, spread_buff: bool = false) -> Dictionary:
	var anchors: Array[Vector2] = []
	var zones: Array = layout.get("encounter_zones", [])
	for offset: int in zones.size():
		anchors.append(zones[(ordinal+offset)%zones.size()].center)
	anchors.append_array(layout.get("topology_probes", []))
	anchors.append_array(layout.get("objective_points", []))
	anchors.append_array(layout.get("spawn_points", []))
	for anchor: Vector2 in anchors:
		for attempt: int in range(96):
			var angle: float = _placement_rng.randf_range(0.0,TAU)
			var reach: float = _placement_rng.randf_range(110.0,340.0)
			var point: Vector2 = anchor + Vector2.from_angle(angle)*reach
			if not _clear_point(point,35.0) or not _line_clear(anchor,point,25.0):
				continue
			if _placement_allowed(point,occupied,spread_buff):
				return {"position":point, "anchor":anchor}
	# Rare dense seeds receive a deterministic exhaustive fallback. Success
	# still requires the same clear swept path and every separation rule.
	var arena: Rect2 = layout.get("arena",Rect2())
	var columns: int = maxi(1,int(arena.size.x/60.0))
	var rows: int = maxi(1,int(arena.size.y/60.0))
	var start: int = _placement_rng.randi_range(0,columns*rows-1)
	for offset: int in columns*rows:
		var index: int = (start+offset)%(columns*rows)
		var point: Vector2 = arena.position+Vector2((index%columns)*60.0+30.0,(index/columns)*60.0+30.0)
		if not _clear_point(point,35.0) or not _placement_allowed(point,occupied,spread_buff):
			continue
		for anchor: Vector2 in anchors:
			if _line_clear(anchor,point,25.0):
				return {"position":point,"anchor":anchor}
	return {}

func _placement_allowed(point: Vector2, occupied: Array[Vector2], spread_buff: bool) -> bool:
	if point.distance_to(layout.entry) < (300.0 if spread_buff else 160.0) or point.distance_to(layout.exit) < 160.0:
		return false
	for other: Vector2 in occupied:
		if point.distance_to(other) < (600.0 if spread_buff else 115.0):
			return false
	for spawn: Vector2 in layout.get("spawn_points", []):
		if point.distance_to(spawn) < 72.0:
			return false
	for target: Vector2 in layout.get("objective_points", []):
		if point.distance_to(target) < 125.0:
			return false
	for instance: Dictionary in layout.get("prop_instances",[]):
		var supply_bounds := Rect2(point+Vector2(-39,-49),Vector2(78,76))
		if not bool(instance.get("destroyed",false)) and instance.get("visual_rect",Rect2()).grow(8.0).intersects(supply_bounds):
			return false
	for zone: Dictionary in layout.get("hazard_zones", []):
		if zone.get("rect", Rect2()).grow(35.0).has_point(point):
			return false
	return true

func _build_world_entities(occupied: Array[Vector2]) -> void:
	var has_movable: bool = false
	for index: int in obstacle_recipes.size():
		var recipe: Dictionary = obstacle_recipes[index]
		if bool(recipe.get("destroyed",false)):
			continue
		var tags: Array = recipe.get("tags",[])
		if "non_solid" in tags:
			continue
		var rect: Rect2 = recipe.get("collision_rect",recipe.get("rect",Rect2()))
		if str(recipe.kind) == "breakable_wall" or "thin_wall" in tags:
			entities.append({"id":str(recipe.get("id",room_id+":thin_wall:"+str(index))), "kind":"thin_wall", "tags":["thin_wall"], "position":rect.get_center(), "rect":rect, "recipe_index":index, "enabled":true})
		elif "movable" in tags:
			has_movable = true
			entities.append({"id":str(recipe.id), "kind":"movable", "tags":["movable"], "position":rect.get_center(), "rect":rect, "recipe_index":index, "radius":maxf(rect.size.x,rect.size.y)*.5, "enabled":true})
	var kinds: Array = []
	if biome_id == "B02":
		kinds = ["loot_nest"]
	elif biome_id == "B03":
		kinds = ["shield_socket"] if has_movable else ["shield_socket", "movable", "movable"]
	elif biome_id == "B04":
		kinds = ["scene_lamp", "scene_lamp", "shallow_pool"]
	for kind: String in kinds:
		var anchor: Dictionary = _find_position(occupied, occupied.size())
		if anchor.is_empty():
			continue
		var radius: float = 32.0 if kind == "shallow_pool" else 22.0
		entities.append({"id":room_id + ":" + kind + ":" + str(entities.size()), "kind":kind, "tags":[kind], "position":anchor.position, "radius":radius, "enabled":true, "cooldown":0.0, "dark_remaining":0.0, "taken_by":0})
		occupied.append(anchor.position)

func query_tag(tag: String) -> Array:
	var result: Array = []
	for entity: Dictionary in entities:
		if bool(entity.get("enabled", true)) and tag in entity.get("tags", []):
			result.append(entity.duplicate(true))
		elif tag == "dark_field" and float(entity.get("dark_remaining", 0.0)) > 0.0:
			var field: Dictionary = entity.duplicate(true)
			field.merge({"kind":"dark_field", "radius":float(entity.get("dark_radius",110.0))}, true)
			result.append(field)
	if tag == "recoverable_loot" and is_instance_valid(room):
		for index: int in room.gold_drops.size():
			var drop: Dictionary = room.gold_drops[index]
			if not drop.has("_room_prop_id"):
				_loot_serial += 1
				drop["_room_prop_id"] = room_id + ":ground_loot:" + str(_loot_serial)
			result.append({"id":str(drop._room_prop_id), "kind":"recoverable_loot", "position":drop.at, "amount":drop.amount, "index":index})
	return result

func tags_at(point: Vector2) -> Array:
	var result: Array = []
	for entity: Dictionary in entities:
		if not bool(entity.get("enabled", true)):
			continue
		if float(entity.get("dark_remaining", 0.0)) > 0.0 and point.distance_to(entity.position) <= float(entity.get("dark_radius",110.0)) and "dark_field" not in result:
			result.append("dark_field")
		var within: bool = entity.rect.has_point(point) if entity.has("rect") else point.distance_to(entity.position) <= float(entity.get("radius", 24.0))
		if within:
			for tag: String in entity.get("tags", []):
				if tag not in result:
					result.append(tag)
	return result

func is_in_tag(point: Vector2, tag: String) -> bool:
	return tag in tags_at(point)

func target_for(caster: Node2D, action: String, focus: Variant = null, requested_id: String = "") -> Dictionary:
	if action == "bite_breakable_wall" and int(_wall_break_counts.get(caster.get_instance_id(),0)) >= int(_wall_break_limits.get(caster.get_instance_id(),1)):
		return {"valid":false, "reason":"wall_break_cap"}
	var tag: String = str({"steal_quest_object":"recoverable_loot", "return_to_nest":"loot_nest", "bite_breakable_wall":"thin_wall", "polarity_displacement":"movable", "socket_recharge":"shield_socket", "steal_scene_lamp":"scene_lamp", "visible_burrow_path":"shallow_pool"}.get(action, ""))
	var nearest: Dictionary = {"valid":false}
	var distance: float = INF
	var origin: Vector2 = focus if focus is Vector2 else caster.position
	for entity: Dictionary in query_tag(tag):
		if not requested_id.is_empty() and str(entity.id) != requested_id:
			continue
		if float(entity.get("cooldown", 0.0)) > 0.0 or int(entity.get("taken_by", 0)) != 0:
			continue
		var target: Vector2 = entity.position
		if tag == "thin_wall":
			var box: Rect2 = entity.rect
			target = Vector2(clampf(origin.x, box.position.x - 26.0, box.end.x + 26.0), clampf(origin.y, box.position.y - 26.0, box.end.y + 26.0))
			if box.grow(24.0).has_point(target):
				var sides: Array[Vector2] = [Vector2(box.position.x-27.0,target.y), Vector2(box.end.x+27.0,target.y), Vector2(target.x,box.position.y-27.0), Vector2(target.x,box.end.y+27.0)]
				var side_distance: float = INF
				for side: Vector2 in sides:
					if _clear_point(side, 24.0) and origin.distance_to(side) < side_distance:
						target = side
						side_distance = origin.distance_to(side)
				if side_distance == INF:
					continue
			if not _clear_point(target,24.0):
				continue
		var next: float = origin.distance_to(target)
		if next < distance:
			distance = next
			nearest = entity.duplicate(true)
			nearest.merge({"valid":true, "position":target}, true)
	return nearest

func utility(caster: Node2D, kind: String, params: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(caster) or _paused():
		return {"success":false, "reason":"invalid_caster_or_paused"}
	if kind == "polarity_displacement":
		return _polarity_displacement(caster, params)
	if kind == "bite_breakable_wall":
		_wall_break_limits[caster.get_instance_id()] = maxi(0,int(params.get("breakable_wall_cap",1)))
		if int(_wall_break_counts.get(caster.get_instance_id(),0)) >= int(_wall_break_limits[caster.get_instance_id()]):
			return {"success":false, "reason":"wall_break_cap"}
	var frozen: Variant = params.get("target", null)
	var target: Dictionary = target_for(caster, kind, frozen, str(params.get("target_id", "")))
	if not bool(target.get("valid", false)):
		return {"success":false, "reason":"no_authored_target", "kind":kind}
	if frozen is Vector2 and frozen.distance_to(target.position) > maxf(32.0, float(target.get("radius", 0.0))):
		return {"success":false, "reason":"target_moved", "kind":kind}
	var reach: float = float(params.get("range", params.get("radius", 95.0)))
	if caster.position.distance_to(target.position) > reach:
		return {"success":false, "reason":"out_of_reach", "kind":kind}
	var ignored: Rect2 = target.get("rect", Rect2()) if kind == "bite_breakable_wall" else Rect2()
	if not _line_clear(caster.position, target.position, 0.0, ignored):
		return {"success":false, "reason":"blocked", "kind":kind}
	match kind:
		"steal_quest_object":
			if stolen.get(caster.get_instance_id(),[]).size() >= maxi(0,int(params.get("carry_limit",1))):
				return {"success":false, "reason":"carry_limit"}
			var index: int = int(target.index)
			var payload: Dictionary = room.gold_drops[index].duplicate(true)
			room.gold_drops.remove_at(index)
			var owner_id: int = caster.get_instance_id()
			if not stolen.has(owner_id):
				stolen[owner_id] = []
			stolen[owner_id].append({"drop":payload, "position":caster.position})
			return {"success":true, "kind":kind, "amount":payload.amount, "recoverable":true}
		"bite_breakable_wall":
			var entity: Dictionary = _entity(str(target.id))
			entity.enabled = false
			room.obstructions.erase(entity.rect)
			for current: Dictionary in [layout,room.layout]:
				var physical_index: int = current.obstructions.find(entity.rect)
				if physical_index >= 0:
					current.obstructions.remove_at(physical_index)
					if physical_index < current.get("obstruction_kinds",[]).size():
						current.obstruction_kinds.remove_at(physical_index)
				for instance: Dictionary in current.get("prop_instances",[]):
					if str(instance.id)==str(entity.id):
						instance["destroyed"] = true
			obstacle_recipes[int(entity.recipe_index)].destroyed = true
			_wall_break_counts[caster.get_instance_id()] = int(_wall_break_counts.get(caster.get_instance_id(),0)) + 1
			room.queue_redraw()
		"socket_recharge":
			if not caster.has_method("apply_status"):
				return {"success":false, "reason":"no_shield_receiver"}
			var maximum: float = float(caster.health.maximum) if caster.get("health") != null else 100.0
			var ratio: float = clampf(float(params.get("guard_ratio", params.get("shield_ratio", .30))), 0.0, .50)
			if not caster.apply_status("guard", maximum * ratio, float(params.get("duration", 5.0))):
				return {"success":false, "reason":"guard_rejected"}
			_entity(str(target.id))["cooldown"] = 4.0
		"steal_scene_lamp":
			var carried_lamps: int = 0
			for lamp: Dictionary in entities:
				if str(lamp.kind)=="scene_lamp" and int(lamp.get("taken_by",0))==caster.get_instance_id():
					carried_lamps += 1
			if carried_lamps >= maxi(0,int(params.get("carry_limit",1))):
				return {"success":false, "reason":"carry_limit"}
			var entity: Dictionary = _entity(str(target.id))
			entity.dark_remaining = clampf(float(params.get("duration", 6.0)), 1.0, 12.0)
			entity.dark_radius = clampf(float(params.get("radius",110.0)), 1.0, 450.0)
			entity.taken_by = caster.get_instance_id()
		"visible_burrow_path":
			if not is_in_tag(caster.position, "shallow_pool"):
				return {"success":false, "reason":"not_in_shallow_pool"}
			return {"success":true, "kind":kind, "position":target.position, "terrain_only":true}
		_:
			return {"success":false, "reason":"unsupported_action"}
	queue_redraw()
	return {"success":true, "kind":kind, "id":target.id, "position":_entity(str(target.id)).get("position", target.position)}

func _polarity_displacement(caster: Node2D, params: Dictionary) -> Dictionary:
	var origin: Vector2 = params.get("origin", caster.position)
	var direction: Vector2 = params.get("direction", Vector2.RIGHT)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var reach: float = clampf(float(params.get("range", params.get("radius", 180.0))), 0.0, 450.0)
	var distance: float = clampf(float(params.get("travel_distance", 35.0)), 0.0, 140.0)
	var angle: float = clampf(float(params.get("angle", TAU)), 0.0, TAU)
	var pull: bool = str(params.get("polarity", "push")) == "pull"
	var cooldown: float = maxf(0.0, float(params.get("displacement_cooldown", 3.0)))
	var frozen: Variant = params.get("target", null)
	var requested_id: String = str(params.get("target_id", ""))
	var target: Dictionary = target_for(caster, "polarity_displacement", frozen, requested_id)
	if not requested_id.is_empty() and (not bool(target.get("valid", false)) or (frozen is Vector2 and frozen.distance_to(target.position) > 32.0)):
		return {"success":false, "reason":"locked_prop_missing_or_moved"}
	var moved_props: int = 0
	var moved_enemies: int = 0
	var prop_position: Vector2 = origin
	var ignored_rect: Rect2 = target.get("rect",Rect2())
	if bool(target.get("valid", false)) and displacement_ready(str(target.id)) and _within_polarity(target.position, origin, direction, reach, angle, ignored_rect):
		var entity: Dictionary = _entity(str(target.id))
		var from: Vector2 = entity.position
		var displacement: Vector2 = _polarity_motion(from, origin, direction, distance, pull)
		var destination: Vector2 = _swept_prop_position(from, displacement, float(entity.get("radius",20.0)), ignored_rect)
		if destination.distance_to(from) > .01:
			_move_prop_entity(entity,destination)
			record_displacement(str(entity.id), cooldown)
			prop_position = destination
			moved_props = 1
	# Only ordinary enemies are affected. Elite/boss anchors, the caster and
	# the player are excluded; player displacement/dash rules live in runtime.
	var enemy_root: Node = room.get_node_or_null("Enemies") if is_instance_valid(room) else null
	if enemy_root != null and room.has_method("move_actor"):
		for other: Node2D in enemy_root.get_children():
			if other == caster or not other.has_method("is_alive") or not other.is_alive():
				continue
			if str(other.get("rank")) != "normal" or not displacement_ready(other) or not _within_polarity(other.position, origin, direction, reach, angle):
				continue
			var radius_value: Variant = other.get("navigation_radius")
			var radius: float = float(radius_value) if radius_value != null else 18.0
			var from: Vector2 = other.position
			# Ordinary actors receive at most 35 units per telegraphed pulse.
			var displacement: Vector2 = _polarity_motion(from, origin, direction, minf(distance, 35.0), pull)
			other.position = room.move_actor(from, displacement, radius)
			if from.distance_to(other.position) > .01:
				record_displacement(other, cooldown)
				moved_enemies += 1
	queue_redraw()
	return {"success":moved_props + moved_enemies > 0, "kind":"polarity_displacement", "id":str(target.get("id", "")), "position":prop_position, "polarity":"pull" if pull else "push", "moved_props":moved_props, "moved_enemies":moved_enemies}

func displacement_ready(target: Variant) -> bool:
	var key: String = "actor:" + str(target.get_instance_id()) if target is Node else "prop:" + str(target)
	return elapsed >= float(_displacement_until.get(key, 0.0))

func record_displacement(target: Variant, cooldown: float) -> void:
	var key: String = "actor:" + str(target.get_instance_id()) if target is Node else "prop:" + str(target)
	_displacement_until[key] = elapsed + maxf(0.0, cooldown)

func _within_polarity(point: Vector2, origin: Vector2, direction: Vector2, reach: float, angle: float, ignored_rect: Rect2 = Rect2()) -> bool:
	var offset: Vector2 = point - origin
	return offset.length() <= reach and (offset.is_zero_approx() or angle >= TAU - .001 or direction.dot(offset.normalized()) >= cos(angle*.5)) and _line_clear(origin, point,0.0,ignored_rect)

func _polarity_motion(point: Vector2, origin: Vector2, fallback: Vector2, distance: float, pull: bool) -> Vector2:
	var offset: Vector2 = point - origin
	var axis: Vector2 = fallback if offset.is_zero_approx() else offset.normalized()
	if pull:
		return -axis * minf(distance, maxf(0.0, offset.length() - 25.0))
	return axis * distance

func _swept_prop_position(from: Vector2, displacement: Vector2, radius: float, ignored_rect: Rect2 = Rect2()) -> Vector2:
	var result: Vector2 = from
	var steps: int = maxi(1, ceili(displacement.length()/4.0))
	var part: Vector2 = displacement / float(steps)
	for index: int in steps:
		var next: Vector2 = result + part
		var clear: bool = layout.get("arena",Rect2()).grow(-radius).has_point(next)
		for obstacle: Rect2 in layout.get("obstructions",[]):
			if obstacle != ignored_rect and obstacle.grow(radius).has_point(next):
				clear = false
		if is_instance_valid(room):
			var actor_root: Node = room.get_node_or_null("Enemies")
			if actor_root != null:
				for actor: Node2D in actor_root.get_children():
					if actor.has_method("is_alive") and actor.is_alive():
						var actor_radius: Variant = actor.get("navigation_radius")
						if next.distance_to(actor.position) < radius + (float(actor_radius) if actor_radius != null else 18.0):
							clear = false
			var player: Node2D = room.get("player")
			if is_instance_valid(player) and next.distance_to(player.position)<radius+14.0:
				clear = false
		if not clear or not _line_clear(result, next, radius, ignored_rect):
			break
		result = next
	return result

func _move_prop_entity(entity: Dictionary, destination: Vector2) -> void:
	var offset: Vector2 = destination - Vector2(entity.position)
	entity.position = destination
	if not entity.has("rect"):
		return
	var previous: Rect2 = entity.rect
	var next: Rect2 = Rect2(previous.position+offset,previous.size)
	entity.rect = next
	for current: Dictionary in [layout, room.layout]:
		var index: int = current.obstructions.find(previous)
		if index >= 0:
			current.obstructions[index] = next
		for instance: Dictionary in current.get("prop_instances",[]):
			if str(instance.id)==str(entity.id):
				instance.position = destination
				instance.collision_rect = next
				if instance.has("visual_rect"):
					instance.visual_rect = Rect2(instance.visual_rect.position+offset,instance.visual_rect.size)
	var physical_index: int = room.obstructions.find(previous)
	if physical_index >= 0:
		room.obstructions[physical_index] = next
	var recipe: Dictionary = obstacle_recipes[int(entity.recipe_index)]
	recipe.position = destination
	recipe.collision_rect = next
	recipe.rect = next
	if recipe.has("visual_rect"):
		recipe.visual_rect = Rect2(recipe.visual_rect.position+offset,recipe.visual_rect.size)
	room.queue_redraw()

func _entity(id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if entity.id == id:
			return entity
	return {}

func carried_by(caster: Node2D) -> bool:
	if not is_instance_valid(caster):
		return false
	var owner_id: int = caster.get_instance_id()
	if not stolen.get(owner_id, []).is_empty():
		return true
	for entity: Dictionary in entities:
		if int(entity.get("taken_by", 0)) == owner_id:
			return true
	return false

func return_stolen(caster_or_id: Variant) -> int:
	var owner_id: int = int(caster_or_id) if caster_or_id is int else caster_or_id.get_instance_id()
	var count: int = 0
	var owner: Object = instance_from_id(owner_id)
	for payload: Dictionary in stolen.get(owner_id, []):
		var drop: Dictionary = payload.drop.duplicate(true)
		var at: Vector2 = owner.position if is_instance_valid(owner) else payload.position
		if not _clear_point(at, 4.0):
			at = drop.at
		drop.at = at
		drop.age = 0.0
		if is_instance_valid(room):
			room.gold_drops.append(drop)
			count += int(drop.amount)
	stolen.erase(owner_id)
	for entity: Dictionary in entities:
		if int(entity.get("taken_by", 0)) == owner_id:
			entity.taken_by = 0
			entity.dark_remaining = 0.0
	return count

func _draw() -> void:
	for entity: Dictionary in entities:
		if not bool(entity.get("enabled", true)) or str(entity.kind) == "thin_wall" or entity.has("recipe_index"):
			continue
		if _entity_bodies.has(str(entity.id)):
			_draw_entity_ground(entity)
		else:
			_draw_entity(entity)
	for item: Dictionary in props:
		_draw_supply(item)

func _draw_supply(item: Dictionary) -> void:
	var at: Vector2 = item.position
	var used: bool = bool(item.used)
	var tint: Color = Color("98aba0") if used else item.color
	draw_set_transform(at)
	# A quiet ground halo identifies the automatic proximity beacon.
	draw_set_transform(at, 0.0, Vector2(1.0,0.64))
	draw_arc(Vector2.ZERO, BEACON_RADIUS, 0.0, TAU, 48, Color(tint,0.16 if used else 0.35), 1.4, true)
	draw_set_transform(at)
	if not is_instance_valid(_beacon_layer):
		draw_beacon_body(self,item)
	if not used:
		draw_circle(Vector2(0,25),3.0,tint)
	draw_set_transform(Vector2.ZERO)
	if _font == null:
		return
	var observer: Node2D = room.get("player") if is_instance_valid(room) else null
	if not is_instance_valid(observer) or observer.position.distance_to(at) > 160.0 or not _line_clear(observer.position,at):
		return
	var game: Node = get_node_or_null("/root/Game")
	var english: bool = game != null and str(game.profile.get("settings",{}).get("language","zh_CN")) == "en"
	var label: String = str(item.name_en if english else item.name)
	if used:
		label = ("Recharging · %ds" if english else "信标休眠 · %d秒") % ceili(float(item.cooldown))
	var detail: String = str(item.description_en if english else item.description)
	if used:
		detail = "New function at this spot" if english else "原位刷新 · 功能随机"
	elif not bool(item.armed):
		detail = "Leave the ring, then approach" if english else "离开光环后再次靠近"
	else:
		detail += " · Approach" if english else " · 靠近生效"
	var width: float = _font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	var detail_width: float = _font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	var panel_width: float = maxf(width,detail_width)+12.0
	var panel := Rect2(at+Vector2(-panel_width*.5,32),Vector2(panel_width,40))
	draw_rect(Rect2(panel.position+Vector2(0,2),panel.size),Color(Color("827961"),0.16))
	draw_rect(panel,Color(Color("fff0d5"),0.96))
	draw_rect(panel,Color("d3b176"),false,1.0)
	draw_string(_font,at+Vector2(-width*.5,49),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("69776a") if used else Color("493950"))
	draw_string(_font,at+Vector2(-detail_width*.5,67),detail,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("879285") if used else Color("657368"))

func _draw_supply_art(canvas: CanvasItem, effect: String, used: bool) -> bool:
	var asset: String = "beacon_dormant" if used else "beacon_" + effect
	return PropArt.draw_asset(canvas,asset,Vector2.ZERO,Vector2(78,90))

func draw_beacon_body(canvas: CanvasItem, item: Dictionary) -> void:
	var used: bool = bool(item.used)
	if _draw_supply_art(canvas,str(item.effect),used): return
	_draw_supply_fallback(canvas,item,Color("98aba0") if used else item.color)

func _draw_supply_fallback(canvas: CanvasItem, item: Dictionary, tint: Color) -> void:
	# Cream stone and brass trim share the courtyard's raised architecture.
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-25,8),Vector2(0,19),Vector2(25,8),Vector2(25,18),Vector2(0,29),Vector2(-25,18)]),Color("cbb28e"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-25,8),Vector2(0,-3),Vector2(25,8),Vector2(0,19)]),Color("f5e8c9"))
	canvas.draw_polyline(PackedVector2Array([Vector2(-25,8),Vector2(0,19),Vector2(25,8)]),Color("d4a862"),2,true)
	canvas.draw_line(Vector2(-13,3),Vector2(-13,-15),Color("d3b675"),4,true)
	canvas.draw_line(Vector2(13,3),Vector2(13,-15),Color("d3b675"),4,true)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0,-40),Vector2(14,-23),Vector2(0,-7),Vector2(-14,-23)]),tint)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0,-40),Vector2(0,-7),Vector2(-14,-23)]),tint.darkened(0.24))
	canvas.draw_line(Vector2(0,-37),Vector2(10,-23),tint.lightened(.65),2,true)
	match str(item.effect):
		"heal":
			canvas.draw_line(Vector2(-6,-23),Vector2(6,-23),Color("fff5e3"),3,true)
			canvas.draw_line(Vector2(0,-29),Vector2(0,-17),Color("fff5e3"),3,true)
		"resource", "damage":
			canvas.draw_polyline(PackedVector2Array([Vector2(3,-32),Vector2(-4,-22),Vector2(3,-22),Vector2(-3,-13)]),Color("fff5e3"),2.4,true)
		"guard":
			canvas.draw_polyline(PackedVector2Array([Vector2(-6,-28),Vector2(0,-30),Vector2(6,-28),Vector2(4,-21),Vector2(0,-17),Vector2(-4,-21),Vector2(-6,-28)]),Color("fff5e3"),2,true)
		"haste":
			for x: float in [-4.0,4.0]:
				canvas.draw_polyline(PackedVector2Array([Vector2(x-3,-28),Vector2(x+3,-23),Vector2(x-3,-18)]),Color("fff5e3"),2,true)

func _draw_entity(entity: Dictionary) -> void:
	var at: Vector2 = entity.position
	_draw_entity_ground(entity)
	var asset: String = entity_art_key(entity)
	if not asset.is_empty():
		draw_set_transform(at)
		draw_entity_body(self,entity)
		draw_set_transform(Vector2.ZERO)
		return
	match str(entity.kind):
		"loot_nest":
			for index: int in range(7):
				var offset: Vector2 = Vector2.RIGHT.rotated(index*TAU/7.0)*19.0
				draw_circle(at+offset,12.0,Color("7fbd85"))
			draw_circle(at,12,Color("5b9d85"))
		"movable":
			draw_rect(Rect2(at-Vector2(21,17),Vector2(42,34)),Color("eddfc2"))
			draw_rect(Rect2(at-Vector2(18,14),Vector2(36,28)),Color("d3a261"),false,2)
			draw_line(at-Vector2(13,0),at+Vector2(13,0),Color("a1cabe"),3)
			for side: float in [-1.0,1.0]:
				draw_circle(at+Vector2(side*15,19),4,Color("687c79"))
		"shield_socket":
			draw_circle(at,29,Color("f0e3c9"))
			draw_arc(at,24,0,TAU,32,Color("54b7c2") if float(entity.cooldown)<=0 else Color("9ab2ab"),3,true)
			for side: float in [-1.0,1.0]:
				draw_line(at+Vector2(side*8,-13),at+Vector2(side*8,3),Color("a0c4c4"),5)
			draw_arc(at+Vector2(0,3),8,0,PI,12,Color("a0c4c4"),4,true)
		"shallow_pool":
			draw_circle(at,float(entity.radius),Color("68b9be"))
			for radius: float in [12.0,23.0,31.0]:
				draw_arc(at,radius,0.2,TAU-.3,32,Color("b8dfd8"),1,true)
		"scene_lamp":
			var dark: bool = float(entity.dark_remaining)>0.0
			draw_line(at+Vector2(0,20),at-Vector2(0,26),Color("c6aa7a"),5,true)
			draw_arc(at-Vector2(0,20),13,PI,TAU,16,Color("e0c394"),3,true)
			draw_circle(at-Vector2(0,20),8,Color("78959b") if dark else Color("f1efb9"))

func entity_art_key(entity: Dictionary) -> String:
	return str({"loot_nest":"B02_spore_nest", "shield_socket":"B03_transformer", "scene_lamp":"B04_broken_receiver", "movable":"B03_wrecked_drone"}.get(str(entity.get("kind","")),""))

func body_art_key(item: Dictionary) -> String:
	if str(item.get("kind",""))=="beacon":
		return "beacon_dormant" if bool(item.used) else "beacon_"+str(item.effect)
	return entity_art_key(item)

func body_art_size(item: Dictionary) -> Vector2:
	return Vector2(78,90) if str(item.get("kind",""))=="beacon" else Vector2(90,96)

func draw_entity_body(canvas: CanvasItem, entity: Dictionary) -> void:
	var asset: String = entity_art_key(entity)
	var tint := Color.WHITE
	if str(entity.kind)=="scene_lamp" and float(entity.get("dark_remaining",0.0))>0.0:
		tint = Color(.65,.72,.74,.84)
	elif str(entity.kind)=="shield_socket" and float(entity.get("cooldown",0.0))>0.0:
		tint = Color(.78,.83,.80,.90)
	PropArt.draw_asset(canvas,asset,Vector2.ZERO,body_art_size(entity),tint)

func _draw_entity_ground(entity: Dictionary) -> void:
	var at: Vector2 = entity.position
	if str(entity.kind)=="scene_lamp" and float(entity.get("dark_remaining",0.0))<=0.0:
		draw_circle(at,100,Color(.65,.76,.86,.045))
	elif str(entity.kind)=="shield_socket":
		draw_arc(at,27,0,TAU,32,Color(Color("54b7c2"),.32) if float(entity.cooldown)<=0 else Color(Color("9ab2ab"),.20),1.5,true)
