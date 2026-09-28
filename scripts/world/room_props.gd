class_name RoomProps
extends Node2D
## Room-owned, single-tick props. Buff sources never survive configure/clear.
## Utility success means an authored, visible entity was actually changed.

const Layouts = preload("res://scripts/world/room_layouts.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Appearance = preload("res://scripts/world/room_appearance.gd")
const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const INTERACTION_RADIUS := 68.0
const GUARD_SOURCE := "room_prop:guard"
const BUFFS := {
	"damage": {"name":"超载线圈", "name_en":"Overcharge coil", "description":"攻击加成 +20% · 15秒", "description_en":"Attack bonus +20% · 15s", "duration":15.0, "color":Color("eda55e")},
	"guard": {"name":"应急护盾", "name_en":"Emergency shield", "description":"获得生命上限25%的护盾 · 15秒", "description_en":"Shield for 25% maximum HP · 15s", "duration":15.0, "color":Color("70cfdf")},
	"haste": {"name":"急行蓄能器", "name_en":"Sprint capacitor", "description":"移动速度 +15% · 12秒", "description_en":"Movement speed +15% · 12s", "duration":12.0, "color":Color("b9d881")}
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
var _supply_textures: Dictionary = {}
var _supply_regions: Dictionary = {}
var _loot_serial: int = 0
var _displacement_until: Dictionary = {}
var _wall_break_counts: Dictionary = {}
var _wall_break_limits: Dictionary = {}
var _placement_rng := RandomNumberGenerator.new()
var configuration_errors: Array[String] = []

func configure(owner_room: Node2D, room_layout: Dictionary) -> bool:
	clear()
	room = owner_room
	layout = room_layout.duplicate(true)
	room_id = str(layout.get("room_id", ""))
	biome_id = str(Catalog.room(room_id).get("biome_id", "B01"))
	_placement_rng.seed = int(layout.get("seed", hash(room_id))) ^ 0x524F4F4D
	obstacle_recipes = Appearance.recipe(layout, biome_id)
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		_font = load("res://assets/fonts/NotoSansSC.ttf")
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)
	set_physics_process(false)
	if layout.is_empty():
		configuration_errors.append("Missing room layout")
		return false
	# Supplies are seeded once per room and spread over distinct encounter
	# regions. They are never a row of three choices at the entrance.
	var occupied: Array[Vector2] = []
	for effect: String in ["damage", "guard", "haste"]:
		var anchor: Dictionary = _find_position(occupied, props.size(), true)
		if anchor.is_empty():
			configuration_errors.append("No reachable separated supply position for "+effect+" in "+room_id+" seed "+str(layout.get("seed",0)))
			push_error(configuration_errors.back())
			return false
		var item: Dictionary = BUFFS[effect].duplicate(true)
		item.merge({"id":room_id + ":supply:" + effect, "kind":"buff", "effect":effect, "position":anchor.position, "anchor":anchor.anchor, "used":false, "remaining":0.0, "available":true})
		props.append(item)
		occupied.append(anchor.position)
	_build_world_entities(occupied)
	queue_redraw()
	return true

func clear() -> void:
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
	clear()

func _paused() -> bool:
	return is_inside_tree() and get_tree().paused

func update(delta: float) -> void:
	if delta <= 0.0 or _paused():
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
	queue_redraw()

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

func nearest_interaction(player_pos: Vector2) -> Dictionary:
	var closest: Dictionary = {}
	var nearest: float = INTERACTION_RADIUS + 0.001
	for item: Dictionary in props:
		var distance: float = player_pos.distance_to(item.position)
		var prefer_unused: bool = not bool(item.used) and bool(closest.get("used", false))
		var preserve_unused: bool = bool(item.used) and not closest.is_empty() and not bool(closest.get("used", false))
		if distance <= INTERACTION_RADIUS and not preserve_unused and (distance <= nearest or prefer_unused) and _line_clear(player_pos, item.position):
			closest = item.duplicate(true)
			closest["available"] = not bool(item.used) and not _paused()
			nearest = distance
	return closest

func interact(id: String, player: Node2D) -> Dictionary:
	if _paused() or not is_instance_valid(player):
		return {"success":false, "reason":"paused_or_missing_player"}
	for item: Dictionary in props:
		if item.id != id:
			continue
		if bool(item.used):
			return {"success":false, "reason":"already_used"}
		if player.position.distance_to(item.position) > INTERACTION_RADIUS or not _line_clear(player.position, item.position):
			return {"success":false, "reason":"out_of_reach"}
		if not grant_buff(str(item.effect), player):
			return {"success":false, "reason":"effect_unavailable"}
		item.used = true
		item.available = false
		item.remaining = float(BUFFS[item.effect].duration)
		queue_redraw()
		return {"success":true, "id":id, "effect":item.effect, "remaining":item.remaining, "used":true}
	return {"success":false, "reason":"unknown_prop"}

func grant_buff(effect: String, player: Node2D) -> bool:
	if not BUFFS.has(effect) or not is_instance_valid(player) or _paused():
		return false
	if effect == "guard":
		var maximum: float = player.stat("max_hp", 100.0) if player.has_method("stat") else 100.0
		var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
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
			canvas.draw_circle(entity.position, float(entity.get("dark_radius",110.0)), Color(0.015,0.023,0.035,0.27))

func draw_obstacles(canvas: CanvasItem) -> void:
	Appearance.draw_obstacles(canvas, obstacle_recipes, elapsed)

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
		_draw_entity(entity)
	for item: Dictionary in props:
		_draw_supply(item)

func _draw_supply(item: Dictionary) -> void:
	var at: Vector2 = item.position
	var used: bool = bool(item.used)
	var tint: Color = Color("63756e") if used else item.color
	draw_set_transform(at)
	draw_arc(Vector2(0,8), 34.0, 0.0, TAU, 40, Color(tint,0.17), 7.0, true)
	var artwork_drawn: bool = _draw_supply_art(str(item.effect), used)
	if not artwork_drawn:
		_draw_supply_fallback(item, tint)
	if not used:
		draw_circle(Vector2(0,25),3.0,tint)
	else:
		draw_line(Vector2(-12,-15),Vector2(12,8),Color("788780"),3,true)
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
		label = ("Used" if english else "已使用") + (" · %ds" % ceili(float(item.remaining)) if float(item.remaining) > 0.0 else "")
	var descriptions: Dictionary = {"damage":["攻击 +20% · 15秒", "+20% attack · 15s"], "guard":["25%生命护盾 · 15秒", "25% HP shield · 15s"], "haste":["移速 +15% · 12秒", "+15% speed · 12s"]}
	var detail: String = descriptions[str(item.effect)][1 if english else 0]
	if used:
		detail = "One use per room" if english else "本房间已耗尽"
	var width: float = _font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	var detail_width: float = _font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	var panel_width: float = maxf(width,detail_width)+12.0
	draw_rect(Rect2(at+Vector2(-panel_width*.5,32),Vector2(panel_width,40)),Color(.035,.055,.06,.86))
	draw_line(at+Vector2(-panel_width*.5,32),at+Vector2(panel_width*.5,32),Color(tint,.50),1.0,true)
	draw_string(_font,at+Vector2(-width*.5,49),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("bdc9c0") if used else tint.lightened(.35))
	draw_string(_font,at+Vector2(-detail_width*.5,67),detail,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("a6b8ad") if used else Color("e0ece0"))

func _draw_supply_art(effect: String, used: bool) -> bool:
	if not _supply_textures.has(effect):
		var asset: String = "pressure" if effect == "damage" else effect
		var texture: Texture2D = TextureSampler.sampled("res://assets/generated/props/buff_" + asset + "_v1.png")
		if texture == null:
			return false
		_supply_textures[effect] = texture
		var image: Image = texture.get_image()
		var low: Vector2i = Vector2i(image.get_width(),image.get_height())
		var high: Vector2i = Vector2i(-1,-1)
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x,y).a >= .20:
					low = low.min(Vector2i(x,y))
					high = high.max(Vector2i(x,y))
		_supply_regions[effect] = Rect2(Vector2(low),Vector2(high-low+Vector2i.ONE)) if high.x>=low.x else Rect2(Vector2.ZERO,texture.get_size())
	var source: Rect2 = _supply_regions[effect]
	var extent: Vector2 = source.size * minf(78.0/source.size.x,76.0/source.size.y)
	var destination := Rect2(Vector2(-extent.x*.5,27.0-extent.y),extent)
	draw_texture_rect_region(_supply_textures[effect],destination,source,Color(.46,.51,.49,.85) if used else Color.WHITE)
	return true

func _draw_supply_fallback(item: Dictionary, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-28,17),Vector2(-21,-19),Vector2(0,-29),Vector2(22,-19),Vector2(29,17),Vector2(0,27)]), Color("1b2d30"))
	draw_line(Vector2(-23,15),Vector2(23,15),tint.darkened(.4),4,true)
	match str(item.effect):
		"damage":
			for x: float in [-12.0,12.0]:
				draw_line(Vector2(x,-21),Vector2(x,8),tint.darkened(.15),6,true)
				for y: int in range(-18,9,6):
					draw_line(Vector2(x-5,y),Vector2(x+5,y+2),tint,2,true)
			draw_polyline(PackedVector2Array([Vector2(-5,-19),Vector2(5,-10),Vector2(-3,-3),Vector2(7,5)]),tint,3,true)
		"guard":
			draw_colored_polygon(PackedVector2Array([Vector2(-16,-19),Vector2(0,-24),Vector2(16,-19),Vector2(12,0),Vector2(0,12),Vector2(-12,0)]),tint.darkened(.3))
			draw_polyline(PackedVector2Array([Vector2(-14,-17),Vector2(0,-21),Vector2(14,-17),Vector2(10,-1),Vector2(0,8),Vector2(-10,-1),Vector2(-14,-17)]),tint,2,true)
		"haste":
			for x: float in [-7.0,7.0]:
				draw_polyline(PackedVector2Array([Vector2(x-7,4),Vector2(x,-8),Vector2(x-7,-20)]),tint,4,true)

func _draw_entity(entity: Dictionary) -> void:
	var at: Vector2 = entity.position
	match str(entity.kind):
		"loot_nest":
			for index: int in range(7):
				var offset: Vector2 = Vector2.RIGHT.rotated(index*TAU/7.0)*19.0
				draw_circle(at+offset,12.0,Color("3d4e43"))
			draw_circle(at,12,Color("172c2b"))
		"movable":
			draw_rect(Rect2(at-Vector2(21,17),Vector2(42,34)),Color("384954"))
			draw_rect(Rect2(at-Vector2(18,14),Vector2(36,28)),Color("93a89d"),false,2)
			draw_line(at-Vector2(13,0),at+Vector2(13,0),Color("d1bb76"),3)
			for side: float in [-1.0,1.0]:
				draw_circle(at+Vector2(side*15,19),4,Color("11242c"))
		"shield_socket":
			draw_circle(at,29,Color("182f38"))
			draw_arc(at,24,0,TAU,32,Color("76cad7") if float(entity.cooldown)<=0 else Color("4c656c"),3,true)
			for side: float in [-1.0,1.0]:
				draw_line(at+Vector2(side*8,-13),at+Vector2(side*8,3),Color("a0c4c4"),5)
			draw_arc(at+Vector2(0,3),8,0,PI,12,Color("a0c4c4"),4,true)
		"shallow_pool":
			draw_circle(at,float(entity.radius),Color("263e4d"))
			for radius: float in [12.0,23.0,31.0]:
				draw_arc(at,radius,0.2,TAU-.3,32,Color("627c84"),1,true)
		"scene_lamp":
			var dark: bool = float(entity.dark_remaining)>0.0
			if not dark:
				draw_circle(at,100,Color(.65,.76,.86,.045))
			draw_line(at+Vector2(0,20),at-Vector2(0,26),Color("7d8290"),5,true)
			draw_arc(at-Vector2(0,20),13,PI,TAU,16,Color("818897"),3,true)
			draw_circle(at-Vector2(0,20),8,Color("303946") if dark else Color("d6e2bb"))
