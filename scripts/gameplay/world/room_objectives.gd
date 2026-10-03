extends Node2D
## Stateful authored objectives, separate from the encounter completion gate.
## One module per biome owns its mechanics; this host owns collision-safe effects,
## attackable task objects, readable prompts and the common damage contract.
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
const Target = preload("res://scripts/gameplay/world/objective_target.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const Bounds = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const WorldArt = preload("res://scripts/infrastructure/assets/world_art.gd")
const BodyLayer = preload("res://scripts/presentation/world/objective_depth_layer.gd")
const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
const FirstFour = preload("res://scripts/levels/shared/first_four_objectives.gd")
const PropIdentity = preload("res://scripts/presentation/world/prop_identity.gd")
const Numerical = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const WorldLabels = preload("res://scripts/presentation/hud/world_label_layer.gd")
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
var body_layer: Node2D
var body_nodes: Dictionary = {}
var label_layer: Node2D

func configure(next_room: Node2D, next_layout: Dictionary, node_role: String = "branch") -> void:
	_configure_context(next_room, next_layout, node_role)
	var biome: String = str(definition.get("biome_id", layout.get("biome_id","")))
	if biome == "B10":
		module = preload("res://scripts/levels/b10/world/objectives.gd").new()
		module.configure(self)
		_add_fixed_optional_rewards()
		queue_redraw()
		return
	if biome == "B06" and bool(layout.get("b06_candidate",false)):
		module = preload("res://scripts/levels/b06/world/objectives.gd").new()
		module.configure(self)
		queue_redraw()
		return
	if biome == "B05":
		module = preload("res://scripts/levels/b05/world/objectives.gd").new()
		module.configure(self)
		_add_fixed_optional_rewards()
		queue_redraw()
		return
	if current_combat_rules():
		module = FirstFour.new()
		module.configure(self)
		_add_fixed_optional_rewards()
		queue_redraw()
		return
	var script_path: String = "res://scripts/levels/%s/world/objectives.gd" % biome.to_lower()
	if not biome.is_empty() and ResourceLoader.exists(AssetCatalog.resolve(script_path)):
		module = load(AssetCatalog.resolve(script_path)).new()
		module.configure(self)
	else:
		message = "目标模块未能加载"
	queue_redraw()

func configure_cleared(next_room: Node2D, next_layout: Dictionary, node_role: String = "branch", claimed_optional: Array = []) -> void:
	# A cleared-room restore must never replay machinery, hazards or completion
	# rewards. Only unclaimed optional caches remain available for interaction.
	_configure_context(next_room, next_layout, node_role)
	finished = true
	completed_count = required_count
	quality = "full"
	if str(layout.get("biome_id", "")) == "B10":
		module = preload("res://scripts/levels/b10/world/objectives.gd").new()
		module.configure(self)
	if bool(layout.get("fixed_layout", false)):
		_add_fixed_optional_rewards(claimed_optional)
	elif room_id == "L01":
		module = preload("res://scripts/levels/b01/world/objectives.gd").new()
		module.configure_cleared(self, claimed_optional)
	elif room_id == "L11":
		module = preload("res://scripts/levels/b02/world/objectives.gd").new()
		module.configure_cleared(self, claimed_optional)
	completed_count = required_count
	queue_redraw()

func _configure_context(next_room: Node2D, next_layout: Dictionary, node_role: String) -> void:
	reset()
	room = next_room
	layout = next_layout.duplicate(true)
	room_id = str(layout.get("room_id", ""))
	role = node_role
	definition = Catalog.room(room_id)
	required_count = int(layout.get("fixed_objective_count", definition.get("objective_count", 0)))
	objective_font = WorldLabels.font()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	z_index = 1
	material = WorldArt.material_for(str(definition.get("biome_id", "B01")))
	if not is_instance_valid(label_layer):
		label_layer = WorldLabels.new()
		label_layer.configure(self, _draw_labels)

func _add_fixed_optional_rewards(claimed: Array = []) -> void:
	for reward: Dictionary in layout.get("fixed_optional_rewards", []):
		var id: String = str(reward.id)
		if claimed.has(id): continue
		# The scenery layer already paints this authored chest. The task host
		# owns only its interaction ring and receipt, avoiding stacked sprites.
		add_element(id, reward.position, str(reward.get("name", "支线宝箱")), "utility", "", {
			"optional_reward":true, "required":false, "interactive":true,
			"description":"清场后领取 · 装备需成功撤离保留",
			"claim_event":"optional_salvage", "claim_message":"支线奖励已领取；新装备需成功撤离保留"})

func optional_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in elements:
		var item: Dictionary = elements[id]
		if bool(item.get("optional_reward", false)) and bool(item.get("active", true)) and not bool(item.get("done", false)):
			ids.append(id)
	return ids

func claim_optional(id: String) -> bool:
	if not finished or not optional_ids().has(id) or not is_instance_valid(room) or not room.has_method("claim_optional_objective_reward"):
		return false
	var item: Dictionary = elements[id]
	if bool(item.get("sealed", false)):
		return false
	var actor: Node2D = player()
	var at: Vector2 = item.get("interaction_position", item.position)
	if not is_instance_valid(actor) or actor.position.distance_to(at) > 100.0:
		return false
	if room.has_method("has_line_of_sight") and not room.has_line_of_sight(actor.position, at):
		return false
	if not bool(room.claim_optional_objective_reward(id)):
		message = str(item.label) + "尚未回收，可再次尝试"
		return false
	set_done(id)
	message = str(item.get("claim_message", "可选战利品已回收；装备需成功撤离保留"))
	event(str(item.get("claim_event", "optional_salvage")), {"id": id, "reward_tendency": str(item.get("reward_tendency", ""))})
	queue_redraw()
	return true

func reset() -> void:
	_remove_body_layer()
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
	if is_instance_valid(label_layer): label_layer.queue_redraw()

func _exit_tree() -> void:
	# The layer is our room sibling. Replacing just this host must also retire it.
	if is_instance_valid(body_layer):
		body_layer.visible = false
		body_layer.queue_free()
	body_layer = null
	body_nodes.clear()

func _remove_body_layer() -> void:
	if is_instance_valid(body_layer):
		var parent: Node = body_layer.get_parent()
		if parent != null:
			parent.remove_child(body_layer)
		body_layer.free()
	body_layer = null
	body_nodes.clear()

func _ensure_body_layer() -> bool:
	if is_instance_valid(body_layer):
		return true
	if not is_instance_valid(room):
		return false
	body_layer = BodyLayer.new()
	body_layer.name = "ObjectiveBodies"
	body_layer.objective_host = self
	body_layer.material = material
	room.add_child(body_layer)
	return true

func _sync_body(id: String, item: Dictionary) -> void:
	var asset: String = str(item.get("asset", ""))
	var carried: bool = bool(item.get("carried", false))
	var needs_body: bool = textures.has(asset) and (not bool(item.get("attackable", false)) or carried)
	if not needs_body:
		if body_nodes.has(id) and is_instance_valid(body_nodes[id]):
			body_nodes[id].visible = false
		return
	if not _ensure_body_layer():
		return
	var body: Node2D = body_nodes.get(id)
	if not is_instance_valid(body):
		body = Node2D.new()
		body.name = "Body_" + id
		body.use_parent_material = true
		body.draw.connect(func() -> void: draw_element_body(body, id))
		body_layer.add_child(body)
		body_nodes[id] = body
	body.visible = bool(item.get("active", true)) and not bool(item.get("destroyed", false))
	body.rotation = 0.0 if carried else float(item.get("rotation", 0.0))
	if carried:
		var actor: Node2D = player()
		body.visible = body.visible and is_instance_valid(actor)
		if is_instance_valid(actor):
			# Sort with the carrier, after their body, while preserving the held pose.
			body.position = actor.position + Vector2(0, .1)
	else:
		body.position = Vector2(item.position) if PropArt.has_authored_asset(asset) else Vector2(item.position)+Vector2(0,15).rotated(body.rotation)
	body.modulate = Color.WHITE
	if not carried and body.visible and is_instance_valid(player()):
		var height: float = float(item.get("visual_height", 96.0))
		var bounds: Rect2 = regions[asset]
		var width: float = minf(150.0, height * bounds.size.x / maxf(1.0, bounds.size.y))
		var relative_player: Vector2 = body.to_local(player().global_position)
		var covered: bool = PropArt.bounds_at(asset,Vector2.ZERO,Vector2(150,height)).grow(12).has_point(relative_player+Vector2(0,-28)) if PropArt.has_authored_asset(asset) else relative_player.y > -height-12 and absf(relative_player.x)<width*.5+16
		if player().position.y < body.position.y and covered:
			body.modulate.a = .48
	# Movement, rotation and occlusion alpha update canvas transforms directly.
	# Retain the body's painted draw list until its actual artwork/state changes.
	var visual_state: Array = [asset, carried, bool(item.get("done", false)), float(item.get("visual_height", 96.0))]
	if body.get_meta("objective_visual_state", []) != visual_state:
		body.set_meta("objective_visual_state", visual_state)
		body.queue_redraw()

func sync_body_layer() -> void:
	for id: String in body_nodes.keys():
		if not elements.has(id):
			if is_instance_valid(body_nodes[id]):
				body_nodes[id].free()
			body_nodes.erase(id)
	for id: String in elements.keys():
		var item: Dictionary = elements[id]
		_sync_body(id, item)
		if targets.has(id) and is_instance_valid(targets[id]):
			targets[id].visible = bool(item.get("active", true)) and not bool(item.get("destroyed", false)) and not bool(item.get("carried", false))

func draw_element_body(canvas: Node2D, id: String) -> void:
	var item: Dictionary = elements.get(id, {})
	if item.is_empty() or not bool(item.get("active", true)) or bool(item.get("destroyed", false)):
		return
	var asset: String = str(item.get("asset", ""))
	if not textures.has(asset):
		return
	if bool(item.get("carried", false)):
		if is_instance_valid(player()):
			canvas.draw_texture_rect_region(textures[asset], Rect2(17, -85.1, 38, 38), regions[asset],PropArt.authored_tint() if PropArt.has_authored_asset(asset) else Color.WHITE)
		return
	if bool(item.get("attackable", false)):
		return
	var bounds: Rect2 = regions[asset]
	var height: float = float(item.get("visual_height", 96.0))
	var width: float = minf(150.0, height * bounds.size.x / maxf(1.0, bounds.size.y))
	var tint := Color(.72, .83, .74, .6) if bool(item.get("done", false)) else Color.WHITE
	if PropArt.has_authored_asset(asset):
		PropArt.draw_asset(canvas,asset,Vector2.ZERO,Vector2(150,height),tint)
		return
	canvas.draw_texture_rect_region(textures[asset], Rect2(-width * .5, -height, width, height), bounds, tint)

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
		var texture: Texture2D = PropArt.texture_for_asset(asset)
		if texture != null:
			textures[asset] = texture
			regions[asset] = PropArt.local_region(asset) if PropArt.has_authored_asset(asset) else Bounds.visible_region(texture.get_image())
	_sync_body(id, item)
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
	var english: String = module.status_text_en() if module!=null and module.has_method("status_text_en") else ""
	if Words.locale=="en" and not english.is_empty(): detail=english
	return {"title": str(definition.get("name", room_id)), "text": detail, "text_en":english, "rules":"first_four_combat_v1" if current_combat_rules() else "legacy_non_expedition", "completed": completed_count, "required": required_count, "complete": finished, "quality": quality, "optional": message}

func current_combat_rules() -> bool:
	if not is_instance_valid(room): return false
	var context: Variant = room.get("expedition_context")
	return context is Dictionary and not context.is_empty() and str(definition.get("biome_id","")) in ["B01","B02","B03","B04"] and str(context.get("role",role)) not in ["entrance","supply","boss"]

func combat_actors() -> Array:
	var result: Array = []
	var actors: Node = room.get("enemies") if is_instance_valid(room) else null
	if not is_instance_valid(actors): return result
	for actor: Node2D in actors.get_children():
		if actor.has_method("is_alive") and actor.is_alive() and str(actor.get("actor_kind"))=="enemy" and not bool(actor.get("static_actor")):
			result.append(actor)
	return result

func combat_counter_effect(actor: Node2D, kind: String, duration: float = 6.0) -> bool:
	if not is_instance_valid(actor) or not actor.has_method("apply_biome_counter"): return false
	var applied: bool = bool(actor.apply_biome_counter(kind,duration))
	if applied: event("biome_counter_applied",{"kind":kind,"enemy_id":str(actor.get("enemy_id")),"position":actor.position,"duration":duration})
	return applied

func combat_objective_point(index: int, count: int) -> Vector2:
	if bool(layout.get("fixed_layout", false)):
		var authored: Array = layout.get("objective_points", [])
		if index >= 0 and index < authored.size(): return authored[index]
	var candidates: Array = layout.get("objective_points",[]).duplicate()
	for zone: Dictionary in layout.get("encounter_zones",[]): candidates.append(zone.center)
	candidates.append_array(layout.get("topology_probes",[]))
	var arena: Rect2 = layout.get("arena",Rect2(0,0,2800,1800))
	for ordinal: int in 6:
		candidates.append(arena.position+arena.size*Vector2(.25+.25*(ordinal%3),.32+.36*(ordinal/3)))
	# Wide legacy hazard bands can reject the sparse authored/grid candidates.
	# Search the open strips across the whole arena before reusing any point.
	for row: int in 6:
		for column: int in 8:
			candidates.append(arena.position+arena.size*Vector2(.10+.114*column,.12+.152*row))
	var selected: Array[Vector2] = []
	for candidate: Vector2 in candidates:
		var at: Vector2 = safe_point(candidate,35.0)
		var allowed: bool = at.distance_to(layout.get("entry",Vector2.ZERO))>140
		for previous: Vector2 in selected:
			if previous.distance_to(at)<180: allowed=false
		for hazard: Dictionary in layout.get("hazard_zones",[]):
			if hazard.get("rect",Rect2()).grow(64).has_point(at): allowed=false
		if allowed: selected.append(at)
		if selected.size()>=count: break
	return selected[clampi(index,0,selected.size()-1)] if not selected.is_empty() else safe_point(layout.get("exit",Vector2(2100,900)),35)

func combat_objective_label(index: int, fallback: String) -> String:
	var authored: Array = layout.get("fixed_room",{}).get("objectives",[])
	return str(authored[index].get("name",fallback)) if Words.locale!="en" and index<authored.size() else fallback

func combat_objective_asset(index: int, fallback: String) -> String:
	if not bool(layout.get("fixed_layout",false)): return fallback
	var keys: Array[String] = PropIdentity.objective_keys(str(definition.get("biome_id","B01")))
	return keys[index%keys.size()] if not keys.is_empty() else fallback

func interaction_key() -> String:
	return preload("res://scripts/infrastructure/input/control_bindings.gd").label_for("interact",Game.profile.get("settings",{}).get("controls",{}),Words.locale)

func notify_enemy_death(enemy: Node2D) -> void:
	if module!=null and module.has_method("notify_enemy_death"): module.notify_enemy_death(enemy)

func notify_charge_impact(caster: Node2D, from: Vector2, to: Vector2) -> Dictionary:
	return module.notify_charge_impact(caster,from,to) if module!=null and module.has_method("notify_charge_impact") else {"success":false}

func blocks_dash() -> bool:
	return module != null and module.has_method("blocks_dash") and bool(module.blocks_dash())

func encounter_directive(index: int) -> Dictionary:
	return module.encounter_directive(index) if module != null and module.has_method("encounter_directive") else {}

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
		if bool(item.get("optional_reward", false)) and not finished: continue
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
		closest["label"] = str(item.get("interaction_label", item.label))
		closest["world_position"] = item.position
		closest["position"] = interaction_position
		closest["kind"] = "objective"
	return closest

func interact(id: String, actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not elements.has(id):
		return false
	var item: Dictionary = elements[id]
	if bool(item.get("optional_reward", false)): return claim_optional(id)
	if module == null or not module.has_method("interact"): return false
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
	sync_body_layer()
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
	sync_body_layer()
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
	var version := _numerical_version()
	var maximum: Variant = Numerical.amount(hp if int(details.get("scale_version", 1)) == 10 else Numerical.scale(hp, version), version)
	details["ruleset_version"] = version
	details["scale_version"] = 10 if version == Numerical.V2 else 1
	details["interactive"] = false
	details["attackable"] = true
	var item: Dictionary = add_element(id, at, label, "target", asset, details)
	var target = Target.new()
	target.room = room
	target.objective_host = self
	target.objective_id = id
	target.position = item.position
	target.configure({"ruleset_version":version, "scale_version":details.scale_version, "max_hp":maximum, "armor":0, "navigation_radius":26.0}, {"static_actor": true, "reward_enabled": false, "actor_kind": "objective"})
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
	var version := _numerical_version()
	hazard["damage"] = Numerical.amount(float(hazard.damage) if int(hazard.get("scale_version", 1)) == 10 else Numerical.scale(float(hazard.damage), version), version)
	hazard["ruleset_version"] = version
	hazard["scale_version"] = 10 if version == Numerical.V2 else 1
	hazards.append(hazard)
	event("hazard_warned", {"position": at, "delay": hazard.delay, "shape": hazard.shape})
	return hazard

func _numerical_version() -> int:
	# Facilities follow the adventure frozen on their room, never player level
	# or the production rollout switch. Authored HP/hazard flats are legacy units.
	return int(room.call("enemy_ruleset")) if is_instance_valid(room) and room.has_method("enemy_ruleset") else Numerical.LEGACY

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
		canvas.draw_rect(rect, Color("52657b"))
		canvas.draw_rect(rect.grow(-3), Color("c4ac7c"), false, 2.0)
	for item: Dictionary in elements.values():
		if not bool(item.get("active", true)) or bool(item.get("carried", false)) or bool(item.get("destroyed", false)):
			continue
		var at: Vector2 = item.position
		var done: bool = bool(item.get("done", false))
		if not bool(item.get("attackable", false)):
			var asset: String = str(item.get("asset", ""))
			if not textures.has(asset):
				canvas.draw_arc(at, 28, 0, TAU, 32, Color("4b8554") if done else Color("257f83"), 2, true)
		if item.get("beam_to") is Vector2:
			canvas.draw_line(item.get("beam_from", at), item.beam_to, item.get("beam_color", Color(.52, .86, .85, .65)), 3.0, true)
		if not done:
			canvas.draw_arc(at + Vector2(0, 5), 29, 0, TAU, 32, Color(.15, .50, .51, .72), 2, true)
		var progress: float = clampf(float(item.get("progress", 0)), 0, 1)
		if progress > 0 and not done:
			canvas.draw_arc(at + Vector2(0, 5), 34, -PI * .5, -PI * .5 + TAU * progress, 32, Color("4b8554"), 3, true)
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

func _draw_labels(canvas: Node2D) -> void:
	if objective_font == null: return
	for item: Dictionary in elements.values():
		if not bool(item.get("active", true)) or bool(item.get("carried", false)) or bool(item.get("destroyed", false)):
			continue
		var at: Vector2 = item.position
		if not near(at, 260) and not bool(item.get("always_label", false)):
			continue
		var text: String = str(item.label) + (" ✓" if bool(item.get("done", false)) else "")
		if not str(item.get("phase", "")).is_empty():
			text += " · " + str(item.phase)
		WorldLabels.draw_objective(canvas, objective_font, at, text)
