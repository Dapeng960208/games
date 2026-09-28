extends Node2D
## Stateful authored objectives, separate from the encounter completion gate.
## One module per biome owns its mechanics; this host owns collision-safe effects,
## attackable task objects, readable prompts and the common damage contract.
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Layouts = preload("res://scripts/world/room_layouts.gd")
const Target = preload("res://scripts/world/objective_target.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Bounds = preload("res://scripts/combat/hero_visual.gd")
var room: Node2D
var layout: Dictionary = {}
var room_id: String = ""
var role: String = "branch"
var elapsed: float = 0.0
var elements: Dictionary = {}
var completed_count: int = 0
var required_count: int = 0
var quality: String = "full"
var message: String = ""
var module: RefCounted
var hazards: Array[Dictionary] = []
var events: Array[Dictionary] = []
var blockers: Dictionary = {}
var targets: Dictionary = {}
var finished: bool = false
var definition: Dictionary = {}
var textures: Dictionary = {}
var regions: Dictionary = {}
var objective_font: Font
var ambient_darkness: float = 0.0
var light_positions: Array[Vector2] = []
var _event_serial: int = 0

func configure(next_room: Node2D, next_layout: Dictionary, node_role: String = "branch") -> void:
	reset()
	room = next_room
	layout = next_layout.duplicate(true)
	room_id = str(layout.get("room_id", ""))
	role = node_role
	definition = Catalog.room(room_id)
	required_count = int(definition.get("objective_count", 0))
	objective_font = load("res://assets/fonts/NotoSansSC.ttf") if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf") else ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	z_index = 1
	var biome: String = str(definition.get("biome_id", ""))
	var script_path: String = "res://scripts/world/objectives_" + biome.to_lower() + ".gd"
	if not biome.is_empty() and ResourceLoader.exists(script_path):
		module = load(script_path).new()
		module.configure(self)
	else:
		message = "目标模块未能加载"
	queue_redraw()

func reset() -> void:
	for target in targets.values():
		if is_instance_valid(target):
			target.queue_free()
	for id in blockers.keys():
		remove_blocker(str(id))
	elements.clear()
	hazards.clear()
	events.clear()
	targets.clear()
	module = null
	completed_count = 0
	required_count = 0
	elapsed = 0.0
	quality = "full"
	message = ""
	finished = false
	ambient_darkness = 0.0
	light_positions.clear()
	_event_serial = 0

func point(index: int) -> Vector2:
	var points: Array = layout.get("objective_points", [])
	if points.is_empty():
		return layout.get("entry", Vector2(160, 900))
	return points[clampi(index, 0, points.size() - 1)]

func add_element(id: String, at: Vector2, label: String, kind: String, asset: String, extra: Dictionary = {}) -> Dictionary:
	var item: Dictionary = {"id": id, "position": safe_point(at), "label": label, "kind": kind, "asset": asset, "done": false, "progress": 0.0, "active": true, "interactive": true, "description": "", "required": true}
	item.merge(extra, true)
	if extra.has("interactable"):
		item["interactive"] = bool(extra.interactable)
	elements[id] = item
	if not asset.is_empty() and not textures.has(asset):
		var texture: Texture2D = Sampler.sampled("res://assets/generated/props/" + asset + "_v1.png")
		if texture != null:
			textures[asset] = texture
			regions[asset] = Bounds._visible_region(texture.get_image())
	return item

func element(id: String) -> Dictionary:
	return elements.get(id, {})

func player() -> Node2D:
	return room.get("player") if is_instance_valid(room) else null

func near(at: Vector2, distance: float = 86.0) -> bool:
	var actor: Node2D = player()
	return is_instance_valid(actor) and actor.position.distance_to(at) <= distance

func set_done(id: String) -> void:
	if elements.has(id) and not bool(elements[id].done):
		elements[id].done = true
		elements[id].progress = 1.0
		if bool(elements[id].get("required", true)):
			completed_count += 1
		event("element_completed", {"id": id})

func finish(next_quality: String = "full") -> void:
	if finished:
		return
	quality = next_quality
	finished = true
	event("objective_completed", {"quality": quality, "completed": completed_count, "required": required_count})

func is_complete() -> bool:
	return finished

func status() -> Dictionary:
	var detail: String = str(definition.get("preview", {}).get("objective", ""))
	if module != null and module.has_method("status_text"):
		detail = module.status_text()
	return {"title": str(definition.get("name", room_id)), "text": detail, "completed": completed_count, "required": required_count, "complete": finished, "quality": quality, "optional": message}

func blocks_dash() -> bool:
	return module != null and module.has_method("blocks_dash") and bool(module.blocks_dash())

func navigation_target() -> Dictionary:
	var destination: Dictionary = {}
	if module != null and module.has_method("navigation_target"):
		destination = module.navigation_target()
	if destination.is_empty():
		var best: float = INF
		for item: Dictionary in elements.values():
			if not bool(item.get("active", true)) or bool(item.get("done", false)) or bool(item.get("destroyed", false)) or bool(item.get("carried", false)):
				continue
			if not bool(item.get("required", true)) and not bool(item.get("interactive", true)):
				continue
			var target_position: Vector2 = item.get("interaction_position", item.position)
			var distance: float = player().position.distance_squared_to(target_position) if is_instance_valid(player()) else 0.0
			if distance < best:
				best = distance
				destination = {"position": target_position, "id": item.id}
	if not destination.has("position"):
		destination["position"] = layout.get("exit", Vector2.ZERO)
	if not destination.has("title"):
		destination["title"] = status().text
	destination["kind"] = "objective"
	return destination

func nearby_interaction(at: Vector2) -> Dictionary:
	var closest: Dictionary = {}
	var best: float = 90.0
	var best_priority: int = -100
	for item: Dictionary in elements.values():
		if not bool(item.get("active", true)) or not bool(item.get("interactive", true)) or (bool(item.get("done", false)) and not bool(item.get("repeatable", false))):
			continue
		var interaction_position: Vector2 = item.get("interaction_position", item.position)
		var distance: float = at.distance_to(interaction_position)
		var priority: int = int(item.get("interaction_priority", 5 if str(item.kind) in ["delivery", "receiver", "scale", "assembly_table", "emergency_lamp"] else 0))
		if distance > 90.0 or priority < best_priority or (priority == best_priority and distance > best):
			continue
		if room.has_method("has_line_of_sight") and not room.has_line_of_sight(at, interaction_position):
			continue
		best = distance
		best_priority = priority
		closest = item.duplicate()
		closest["world_position"] = item.position
		closest["position"] = interaction_position
		closest["kind"] = "objective"
	return closest

func interact(id: String, actor: Node2D) -> bool:
	if module == null or not module.has_method("interact") or not is_instance_valid(actor) or not elements.has(id):
		return false
	var item: Dictionary = elements[id]
	var interaction_position: Vector2 = item.get("interaction_position", item.position)
	if not bool(item.get("active", true)) or not bool(item.get("interactive", true)) or actor.position.distance_to(interaction_position) > 100.0:
		return false
	if bool(item.get("done", false)) and not bool(item.get("repeatable", false)):
		return false
	if room.has_method("has_line_of_sight") and not room.has_line_of_sight(actor.position, interaction_position):
		return false
	var accepted: bool = bool(module.interact(id, actor))
	if accepted:
		event("interacted", {"id": id})
	queue_redraw()
	return accepted

func tick(delta: float) -> void:
	if delta <= 0 or not is_instance_valid(room) or (is_inside_tree() and get_tree().paused):
		return
	elapsed += delta
	if module != null and module.has_method("tick"):
		module.tick(delta)
	_tick_hazards(delta)
	for id: String in targets.keys():
		if is_instance_valid(targets[id]) and elements.has(id):
			targets[id].position = elements[id].position
	queue_redraw()

func safe_point(at: Vector2, radius: float = 26.0) -> Vector2:
	var current: Dictionary = layout.duplicate()
	if is_instance_valid(room) and room.get("obstructions") != null:
		current["obstructions"] = room.obstructions
	if Layouts.clear_for_actor(current, at, radius):
		return at
	for distance: int in range(32, 577, 32):
		for step: int in 16:
			var candidate: Vector2 = at + Vector2.RIGHT.rotated(TAU * float(step) / 16.0) * distance
			if Layouts.clear_for_actor(current, candidate, radius):
				return candidate
	return current.get("entry", Vector2(104, 900))

func move_element(id: String, toward: Vector2, speed: float, delta: float) -> bool:
	if not elements.has(id):
		return false
	var item: Dictionary = elements[id]
	var position: Vector2 = item.position
	var distance: float = position.distance_to(toward)
	if distance <= 12:
		return true
	var navigation_time: float = float(item.get("navigation_time", -1.0))
	var direction: Vector2 = item.get("navigation_direction", Vector2.ZERO)
	if elapsed >= navigation_time or direction.is_zero_approx():
		direction = room.navigation_direction(position, toward, 24.0) if room.has_method("navigation_direction") else position.direction_to(toward)
		item["navigation_direction"] = direction
		item["navigation_time"] = elapsed + .2
	var displacement: Vector2 = direction * minf(distance, speed * delta)
	item.position = room.move_actor(position, displacement, 24.0) if room.has_method("move_actor") else position + displacement
	return Vector2(item.position).distance_to(toward) <= 12

func displace(actor: Node2D, displacement: Vector2) -> void:
	if not is_instance_valid(actor) or displacement.is_zero_approx():
		return
	if actor == player() and float(actor.get("dash_remaining") if actor.get("dash_remaining") != null else 0.0) > 0:
		return
	var radius: float = 18.0 if actor == player() else float(actor.get("navigation_radius") if actor.get("navigation_radius") != null else 24.0)
	actor.position = room.move_actor(actor.position, displacement, radius) if room.has_method("move_actor") else actor.position + displacement

func enemies_near(at: Vector2, radius: float) -> Array:
	var result: Array = []
	if not is_instance_valid(room) or not is_instance_valid(room.get("enemies")):
		return result
	for actor in room.enemies.get_children():
		if actor.has_method("is_alive") and actor.is_alive() and str(actor.get("actor_kind")) == "enemy" and at.distance_to(actor.position) <= radius:
			result.append(actor)
	return result

func add_target(id: String, at: Vector2, hp: float, asset: String, label: String, extra: Dictionary = {}) -> Dictionary:
	var details: Dictionary = extra.duplicate()
	details["interactive"] = false
	details["attackable"] = true
	var item: Dictionary = add_element(id, at, label, "target", asset, details)
	var target = Target.new()
	target.room = room
	target.objective_host = self
	target.objective_id = id
	target.position = item.position
	target.configure({"max_hp": hp, "armor": 0.0, "navigation_radius": 26.0}, {"static_actor": true, "reward_enabled": false, "actor_kind": "objective"})
	targets[id] = target
	item["target_actor"] = target
	room.enemies.add_child(target)
	return item

func on_target_hit(id: String, context: Dictionary) -> void:
	if module != null and module.has_method("on_target_hit"):
		module.on_target_hit(id, context)
	event("target_hit", {"id": id, "damage": float(context.get("damage", 0))})

func on_target_destroyed(id: String) -> void:
	if elements.has(id):
		elements[id]["destroyed"] = true
	if module != null and module.has_method("on_target_destroyed"):
		module.on_target_destroyed(id)
	targets.erase(id)
	event("target_destroyed", {"id": id})

func set_blocker(id: String, rect: Rect2, active: bool = true) -> bool:
	if not active:
		remove_blocker(id)
		return true
	if not is_instance_valid(room) or not rect.has_area():
		return false
	var actor: Node2D = player()
	if is_instance_valid(actor) and rect.grow(30).has_point(actor.position):
		return false
	for enemy in enemies_near(rect.get_center(), rect.size.length()):
		if rect.grow(30).has_point(enemy.position):
			return false
	var candidate: Dictionary = layout.duplicate(true)
	var next: Array[Rect2] = []
	next.assign(room.obstructions)
	if blockers.has(id):
		next.erase(blockers[id])
	next.append(rect)
	candidate["obstructions"] = next
	# Topology probes describe an optional route sample, not a task item. A
	# temporary bridge can close over its probe while the other route is open.
	# Entry, exit, objective points and required interactables remain mandatory.
	var available_probes: Array[Vector2] = []
	for probe: Vector2 in candidate.get("topology_probes", []):
		var available: bool = true
		for obstacle: Rect2 in next:
			if obstacle.grow(26).has_point(probe):
				available = false
				break
		if available:
			available_probes.append(probe)
	candidate["topology_probes"] = available_probes
	# Slow validation is performed only when a mechanism changes, never per frame.
	if not bool(Layouts.validate_layout(candidate).valid):
		return false
	if blockers.has(id):
		room.obstructions.erase(blockers[id])
	room.obstructions.append(rect)
	blockers[id] = rect
	if room.has_method("invalidate_navigation"):
		room.invalidate_navigation()
	return true

func remove_blocker(id: String) -> void:
	if not blockers.has(id):
		return
	if is_instance_valid(room):
		room.obstructions.erase(blockers[id])
		if room.has_method("invalidate_navigation"):
			room.invalidate_navigation()
	blockers.erase(id)

func remove_static_obstacle(rect: Rect2) -> bool:
	if not is_instance_valid(room) or not rect.has_area():
		return false
	var changed: bool = room.obstructions.has(rect)
	room.obstructions.erase(rect)
	var layouts: Array = [layout]
	if room.get("layout") is Dictionary:
		layouts.append(room.layout)
	var props: Node2D = room.get("enemy_props")
	if is_instance_valid(props) and props.get("layout") is Dictionary:
		layouts.append(props.layout)
	for current: Dictionary in layouts:
		var index: int = current.get("obstructions", []).find(rect)
		if index >= 0:
			changed = true
			current.obstructions.remove_at(index)
			if index < current.get("obstruction_kinds", []).size():
				current.obstruction_kinds.remove_at(index)
		for instance: Dictionary in current.get("prop_instances", []):
			if instance.get("collision_rect", Rect2()) == rect:
				changed = changed or not bool(instance.get("destroyed", false))
				instance["destroyed"] = true
	if is_instance_valid(props):
		for recipe: Dictionary in props.get("obstacle_recipes"):
			if recipe.get("collision_rect", recipe.get("rect", Rect2())) == rect:
				changed = changed or not bool(recipe.get("destroyed", false))
				recipe["destroyed"] = true
		for entity: Dictionary in props.get("entities"):
			if entity.get("rect", Rect2()) == rect:
				entity["enabled"] = false
	if room.has_method("invalidate_navigation"):
		room.invalidate_navigation()
	room.queue_redraw()
	if changed:
		event("obstacle_destroyed", {"position": rect.get_center()})
	return changed

func cancel_hazard(hazard: Dictionary) -> void:
	hazards.erase(hazard)

func on_player_sound(at: Vector2, context: Dictionary = {}) -> void:
	if module != null and module.has_method("on_player_sound"):
		module.on_player_sound(at, context)

func add_hazard(at: Vector2, radius: float, damage: float, delay: float = 1.0, duration: float = .25, extra: Dictionary = {}) -> Dictionary:
	var hazard: Dictionary = {"position": at, "radius": maxf(1, radius), "damage": maxf(0, damage), "delay": maxf(.8, delay), "remaining": maxf(.05, duration), "shape": "circle", "hit_ids": [], "enemies": false, "player": true, "age": 0.0, "width": 35.0, "color": Color("eaae62")}
	hazard.merge(extra, true)
	hazards.append(hazard)
	event("hazard_warned", {"position": at, "delay": hazard.delay, "shape": hazard.shape})
	return hazard

func _tick_hazards(delta: float) -> void:
	for index: int in range(hazards.size() - 1, -1, -1):
		var hazard: Dictionary = hazards[index]
		hazard.age = float(hazard.age) + delta
		if float(hazard.delay) > 0:
			hazard.delay = float(hazard.delay) - delta
			continue
		hazard.remaining = float(hazard.remaining) - delta
		var actor: Node2D = player()
		if bool(hazard.get("player", true)) and is_instance_valid(actor) and not hazard.hit_ids.has(actor.get_instance_id()) and _hazard_contains(hazard, actor.position, 18):
			hazard.hit_ids.append(actor.get_instance_id())
			if actor.has_method("receive_damage"):
				actor.receive_damage(float(hazard.damage), hazard.position)
		if bool(hazard.get("enemies", false)):
			for enemy in enemies_near(hazard.position, 3000):
				if not hazard.hit_ids.has(enemy.get_instance_id()) and _hazard_contains(hazard, enemy.position, float(enemy.navigation_radius)):
					hazard.hit_ids.append(enemy.get_instance_id())
					enemy.take_damage(float(hazard.damage), &"environment", Vector2.ZERO, {"equipment_eligible": false, "damage_source": "environment"})
		if float(hazard.remaining) <= 0:
			hazards.remove_at(index)

func _hazard_contains(hazard: Dictionary, at: Vector2, actor_radius: float) -> bool:
	if str(hazard.shape) == "line":
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, hazard.position, hazard.get("target", hazard.position))
		return closest.distance_to(at) <= float(hazard.width) * .5 + actor_radius
	if str(hazard.shape) == "ring":
		var distance: float = Vector2(hazard.position).distance_to(at)
		return distance <= float(hazard.radius) + actor_radius and distance >= float(hazard.get("inner_radius", hazard.radius * .65)) - actor_radius
	return Vector2(hazard.position).distance_to(at) <= float(hazard.radius) + actor_radius

func event(event_name: String, data: Dictionary = {}) -> void:
	_event_serial += 1
	var item: Dictionary = data.duplicate()
	item.merge({"name": event_name, "time": elapsed, "serial": _event_serial}, true)
	events.append(item)
	if events.size() > 512:
		events.pop_front()
	if event_name in ["light_powered", "lighting_changed"]:
		ambient_darkness = float(data.get("ambient_darkness", 0.0))
		if data.get("position") is Vector2:
			light_positions.append(data.position)
	if is_instance_valid(room) and room.has_method("on_objective_event"):
		room.on_objective_event(event_name, data)

func _draw() -> void:
	draw_world(self)

func draw_world(canvas: Node2D) -> void:
	if module != null and module.has_method("draw_world"):
		module.draw_world(canvas)
	for blocker_id: String in blockers.keys():
		var rect: Rect2 = blockers[blocker_id]
		if blocker_id.contains("cover") or blocker_id.begins_with("weave_line"):
			# Independent original props / optical threads already depict these
			# colliders. Never put another large backing plate under their art.
			continue
		if blocker_id.contains("gate"):
			canvas.draw_rect(rect, Color(.62, .49, .28, .8), false, 2)
			for bar in range(8, int(rect.size.x), 18):
				canvas.draw_line(rect.position + Vector2(bar, 0), rect.position + Vector2(bar, rect.size.y), Color(.45, .4, .31, .85), 3, true)
			continue
		# These are actual temporary gaps/closed mechanisms, never a background
		# plate pasted beneath an unrelated prop sprite.
		canvas.draw_rect(rect, Color(.025, .035, .04, .9))
		canvas.draw_rect(rect.grow(-3), Color(.6, .47, .28, .8), false, 2.0)
	for item: Dictionary in elements.values():
		if not bool(item.get("active", true)) or bool(item.get("carried", false)) or bool(item.get("destroyed", false)):
			if bool(item.get("active", true)) and bool(item.get("carried", false)) and is_instance_valid(player()):
				var carried_asset: String = str(item.get("asset", ""))
				if textures.has(carried_asset):
					canvas.draw_texture_rect_region(textures[carried_asset], Rect2(player().position + Vector2(17, -85), Vector2(38, 38)), regions[carried_asset])
			continue
		var at: Vector2 = item.position
		var done: bool = bool(item.get("done", false))
		var tint := Color(.72, .83, .74, .6) if done else Color.WHITE
		if not bool(item.get("attackable", false)):
			var asset: String = str(item.get("asset", ""))
			if textures.has(asset):
				var bounds: Rect2 = regions[asset]
				var height: float = float(item.get("visual_height", 96.0))
				var width: float = minf(150.0, height * bounds.size.x / maxf(1.0, bounds.size.y))
				canvas.draw_set_transform(at, float(item.get("rotation", 0.0)))
				canvas.draw_texture_rect_region(textures[asset], Rect2(-width * .5, 15 - height, width, height), bounds, tint)
				canvas.draw_set_transform(Vector2.ZERO)
			else:
				canvas.draw_arc(at, 28, 0, TAU, 32, Color("b2d5cc") if done else Color("d9bc75"), 2, true)
		if item.get("beam_to") is Vector2:
			canvas.draw_line(item.get("beam_from", at), item.beam_to, item.get("beam_color", Color(.52, .86, .85, .65)), 3.0, true)
		if not done:
			canvas.draw_arc(at + Vector2(0, 5), 29, 0, TAU, 32, Color(.85, .72, .45, .48), 1.5, true)
		var progress: float = clampf(float(item.get("progress", 0)), 0, 1)
		if progress > 0 and not done:
			canvas.draw_arc(at + Vector2(0, 5), 34, -PI * .5, -PI * .5 + TAU * progress, 32, Color("cce6ab"), 3, true)
		var show_label: bool = near(at, 260) or bool(item.get("always_label", false))
		if show_label and objective_font != null:
			var text: String = str(item.label) + (" ✓" if done else "")
			if not str(item.get("phase", "")).is_empty():
				text += " · " + str(item.phase)
			var size: Vector2 = objective_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
			canvas.draw_string_outline(objective_font, at + Vector2(-size.x * .5, 44), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(.03, .04, .05, .9))
			canvas.draw_string(objective_font, at + Vector2(-size.x * .5, 44), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("e7e0c9"))
	for hazard: Dictionary in hazards:
		var color: Color = hazard.get("color", Color("eaae62"))
		color.a = .85 if float(hazard.delay) > 0 else 1.0
		if str(hazard.shape) == "line":
			canvas.draw_line(hazard.position, hazard.get("target", hazard.position), Color(color, .12), float(hazard.width), true)
			var normal: Vector2 = (Vector2(hazard.get("target", hazard.position)) - Vector2(hazard.position)).normalized().orthogonal() * float(hazard.width) * .5
			canvas.draw_line(hazard.position + normal, hazard.get("target", hazard.position) + normal, color, 2, true)
			canvas.draw_line(hazard.position - normal, hazard.get("target", hazard.position) - normal, color, 2, true)
		else:
			canvas.draw_arc(hazard.position, hazard.radius, 0, TAU, 48, color, 2.5, true)
			if str(hazard.shape) == "ring":
				canvas.draw_arc(hazard.position, float(hazard.get("inner_radius", hazard.radius * .65)), 0, TAU, 48, color, 2, true)
		if float(hazard.delay) > 0:
			canvas.draw_circle(hazard.position, 4, color)
