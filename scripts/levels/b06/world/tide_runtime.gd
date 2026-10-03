extends Node2D
## Room-owned adapter: no global clock, save path, release gate or auto-process.
const Tide = preload("res://scripts/levels/b06/world/tide_state.gd")
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
const BossState = preload("res://scripts/levels/b06/combat/boss_state.gd")
const Numbers = preload("res://scripts/levels/b06/combat/enemy_numbers.gd")
const Content = preload("res://scripts/levels/b06/world/content.gd")
signal drain_completed(receipt: Dictionary)
signal phase_changed(phase: String)
var state = Tide.new()
var room_id := ""
var _difficulty := 0
var _calibration: Dictionary = {}
var _numerical_version := 1
var native_water_visual := false # Candidate environment renderer owns base water only.
var boss_state: RefCounted
var _boss_actor: WeakRef
var _boss_claw_receipts: Dictionary = {}
var _gates: Dictionary = {}
var _definition: Dictionary = {}
var _patch_shapes: Dictionary = {}
var _bell_preview := false
var _prop_frames: Dictionary = {}
var _art_helper: Script
var _actors: Dictionary = {}
var _bindings: Dictionary = {}
var _interactor: WeakRef
var _alive := Callable()
var _sight := Callable()
var _active_id := ""
var _gate_id := ""
var interaction_radius := 68.0
func configure(id: String, difficulty: int = 0, calibration: Variant = null) -> bool:
	if not room_id.is_empty() or not Geometry.validate(id).is_empty(): return false
	var definition := Geometry.room(id)
	_definition = definition
	var patches: Array = []
	var links := {}
	for patch: Dictionary in definition.shallow_patches:
		patches.append(str(patch.id))
		_patch_shapes[str(patch.id)] = Geometry.points(patch.polygon)
	for gate: Dictionary in definition.gates:
		links[gate.id] = gate.patch_id
		_gates[gate.id] = Geometry.world_point(gate.position)
	if not state.configure(id,patches,links): return false
	if id == "BO06":
		var profile: Dictionary = Numbers.boss(difficulty,calibration)
		if profile.is_empty(): return false
		_calibration = profile.get("enemy_calibration_snapshot",{}).duplicate(true)
		_numerical_version = int(profile.b06_numerical_version)
		boss_state = BossState.new()
		if not boss_state.configure_shared(int(profile.max_hp),state,{"reef_west":"bay_west","reef_east":"bay_east"}): return false
	_difficulty = difficulty
	room_id = id
	z_index = -1
	queue_redraw()
	return true
func register_actor(id: String, actor: Node2D) -> bool:
	if id.is_empty() or _actors.size() >= 128 or not is_instance_valid(actor) or not actor.has_method("is_alive") or not actor.is_alive(): return false
	if _property(actor,"actor_kind") != "enemy" or Content.enemy(str(_property(actor,"enemy_id"))).is_empty(): return false
	var health = _property(actor,"health")
	var status = _property(actor,"status")
	if not is_instance_valid(health) or not is_instance_valid(status) or not status.has_method("grant_guard_result") or not _property(health,"maximum") is float and not _property(health,"maximum") is int: return false
	for key in _bindings.keys():
		var old = _bindings[key].actor.get_ref()
		if not is_instance_valid(old): _bindings.erase(key)
		elif old == actor and key != id: return false
	if _bindings.has(id) and _bindings[id].actor.get_ref() != actor: return false
	var binding := {"actor":weakref(actor),"health":weakref(health),"status":weakref(status),"enemy_id":str(actor.enemy_id)}
	_actors[id] = binding
	_bindings[id] = binding
	return true
func unregister_actor(id: String) -> void: _actors.erase(id)
func patch_at(actor: Node2D) -> String:
	if not is_instance_valid(actor): return ""
	var point := to_local(actor.global_position)
	if not point.is_finite(): return ""
	for id: String in _patch_shapes:
		if _patch_enabled(id) and Geometry2D.is_point_in_polygon(point,_patch_shapes[id]): return id
	return ""
## Read-only presentation query includes authored alternating groups and drains.
func is_patch_wet(id: String) -> bool:
	return _patch_enabled(id) and state.is_wet(id)
func _patch_enabled(id: String) -> bool:
	var groups: Array = _definition.get("alternating_patch_groups",[])
	if groups.is_empty(): return true
	return id in groups[maxi(0,int(state.clock_state().cycle)) % groups.size()]
func reveal_next_tide(actor: Node2D, alive: Callable, sight: Callable) -> bool:
	if not _definition.has("tide_bell") or not is_instance_valid(actor) or not alive.is_valid() or not sight.is_valid() or not bool(alive.call()): return false
	if is_inside_tree() and get_tree().paused: return false
	var target := to_global(Geometry.world_point(_definition.tide_bell))
	if not actor.global_position.is_finite() or actor.global_position.distance_to(target) > interaction_radius or not bool(sight.call(actor.global_position,target)): return false
	_bell_preview = true
	queue_redraw()
	return true
func next_tide_visible() -> bool: return _bell_preview or state.clock_state().phase == "warning"
func movement_multiplier(actor: Node2D, sea: bool = false, slow_reduction: float = 0.0) -> float:
	var patch := patch_at(actor)
	return state.sea_movement_multiplier(patch) if sea else state.player_movement_multiplier(patch,slow_reduction)
func interact(gate_id: String, actor: Node2D, actor_id: String, alive: Callable, sight: Callable) -> bool:
	if not _gates.has(gate_id) or not is_instance_valid(actor) or not alive.is_valid() or not sight.is_valid() or not bool(alive.call()): return false
	if is_inside_tree() and get_tree().paused: return false
	if not _in_range(actor,gate_id,sight) or not state.begin_drain(gate_id,actor_id): return false
	_interactor = weakref(actor)
	_alive = alive
	_sight = sight
	_active_id = actor_id
	_gate_id = gate_id
	return true
func _in_range(actor: Node2D, gate_id: String, sight: Callable) -> bool:
	var target: Vector2 = to_global(_gates[gate_id])
	return actor.global_position.is_finite() and actor.global_position.distance_to(target) <= interaction_radius and bool(sight.call(actor.global_position,target))
func cancel_interaction() -> void:
	state.cancel_drain(_active_id)
	_active_id = ""
	_gate_id = ""
	_interactor = null
	_alive = Callable()
	_sight = Callable()
func notify_actor_hit(actor_id: String, consumed: float) -> void:
	if actor_id == _active_id and is_finite(consumed) and consumed > 0: cancel_interaction()
func tick(delta: float, paused: bool = false) -> bool:
	if room_id.is_empty() or not is_finite(delta) or delta < 0 or delta > Tide.MAX_STEP_SECONDS: return false
	if paused or (is_inside_tree() and get_tree().paused):
		cancel_interaction()
		return true
	if not _active_id.is_empty():
		var actor = _interactor.get_ref()
		if not is_instance_valid(actor) or not _alive.is_valid() or not bool(_alive.call()) or not _in_range(actor,_gate_id,_sight): cancel_interaction()
	var previous_clock: Dictionary = state.clock_state()
	var result: Dictionary = boss_state.advance(delta) if boss_state != null else state.advance(delta)
	if not result.ok: return false
	var now_us: int = int(state.snapshot().now_us)
	for receipt_id: String in _boss_claw_receipts.keys():
		if int(_boss_claw_receipts[receipt_id]) <= now_us: _boss_claw_receipts.erase(receipt_id)
	if not result.events.is_empty() or previous_clock.phase != state.clock_state().phase: queue_redraw()
	for event: Dictionary in result.events:
		if event.event == "drain_completed":
			var completed_actor: Variant = _interactor.get_ref() if _interactor != null else null
			if is_instance_valid(completed_actor):
				var equipment: Variant = _property(completed_actor, "loadout")
				if equipment != null: equipment.event("combat_mechanism_completed", {"completed":true})
			cancel_interaction()
			drain_completed.emit(event.duplicate(true))
		elif str(event.event).begins_with("tide_"): phase_changed.emit(str(event.event).trim_prefix("tide_"))
	if state.clock_state().phase == "high": _bell_preview = false
	for id: String in _actors.keys():
		var binding: Dictionary = _actors[id]
		var actor = binding.actor.get_ref()
		var health = binding.health.get_ref()
		var status = binding.status.get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(health) or not is_instance_valid(status) or actor.health != health or actor.status != status or actor.enemy_id != binding.enemy_id or not actor.is_alive():
			_actors.erase(id)
			continue
		var maximum := float(health.maximum)
		if not is_finite(maximum) or maximum <= 0: continue
		var patch := patch_at(actor)
		if not state.is_wet(patch): continue
		var before: Dictionary = state.snapshot()
		var grant: Dictionary = state.enter_high_water(id,binding.enemy_id,patch,int(maximum))
		if grant.is_empty(): continue
		var receipt: Dictionary = status.grant_guard_result(grant.shield,grant.seconds,"b06_tide_shell",maximum)
		if not bool(receipt.get("accepted_refresh",false)): state.restore(before)
	return true
func checkpoint() -> Dictionary:
	var result: Dictionary = state.snapshot()
	if result.is_empty(): return result
	result["view_version"] = 1
	result["bell_preview"] = _bell_preview
	if boss_state != null:
		result["boss_numerical"] = {"version":_numerical_version,"calibration":_calibration.duplicate(true)}
		result["boss_state"] = boss_state.snapshot()
		result["claw_receipts"] = _boss_claw_receipts.duplicate(true)
	return result
func restore_checkpoint(value: Dictionary) -> bool:
	var tide_value := value.duplicate(true)
	var bell := false
	if tide_value.has("view_version") or tide_value.has("bell_preview"):
		if tide_value.get("view_version") != 1 or not tide_value.get("bell_preview") is bool: return false
		bell = bool(tide_value.bell_preview)
		if bell and not _definition.has("tide_bell"): return false
		tide_value.erase("view_version")
		tide_value.erase("bell_preview")
	var candidate_boss: RefCounted
	var receipts: Dictionary = {}
	var frozen: Dictionary = {}
	var numerical_version := 1
	if boss_state != null:
		# Missing provenance is the historical v1 contract, never current().
		if tide_value.has("boss_numerical"):
			var numerical: Variant = tide_value.boss_numerical
			if not numerical is Dictionary or numerical.size()!=2 or not numerical.has_all(["version","calibration"]): return false
			if not Tide._integer(numerical.version,1,Numbers.VERSION) or not numerical.calibration is Dictionary: return false
			frozen = numerical.calibration
			numerical_version = int(numerical.version)
			tide_value.erase("boss_numerical")
		var canonical := Numbers.boss(_difficulty,frozen,numerical_version)
		if canonical.is_empty(): return false
		if not tide_value.get("boss_state") is Dictionary or not tide_value.get("claw_receipts") is Dictionary: return false
		receipts = tide_value.claw_receipts.duplicate(true)
		if receipts.size() > 128: return false
		for key in receipts:
			if not key is String or key.is_empty() or not Tide._integer(receipts[key],int(tide_value.now_us)+1,int(tide_value.now_us)+16000000): return false
		candidate_boss = BossState.new()
		var current: Dictionary = boss_state.snapshot()
		if not candidate_boss.configure(int(canonical.max_hp),state.snapshot().patch_ids,state.snapshot().gates,current.pillars): return false
		if not candidate_boss.restore(tide_value.boss_state): return false
		var saved_tide: Dictionary = tide_value.boss_state.tide
		tide_value.erase("boss_state")
		tide_value.erase("claw_receipts")
		if JSON.stringify(saved_tide) != JSON.stringify(tide_value): return false
	if not state.restore(tide_value): return false
	if candidate_boss != null:
		_calibration = frozen.duplicate(true)
		_numerical_version = numerical_version
		boss_state = candidate_boss
		state = boss_state.tide_state()
		_boss_claw_receipts = receipts
	_bell_preview = bell
	queue_redraw()
	var channel: Dictionary = state.snapshot().channel
	if not channel.is_empty(): state.cancel_drain(str(channel.actor_id))
	cancel_interaction()
	return true
func clipped_push(actor_id: String, origin: Vector2, displacement: Vector2, safe_polygon: PackedVector2Array, reduction: float = 0.0) -> Vector2:
	if not displacement.is_finite(): return origin
	var grant: Dictionary = state.admit_push(actor_id,displacement.length(),reduction)
	return Tide.clip_push(origin,displacement.normalized()*float(grant.distance),safe_polygon) if not grant.is_empty() else origin
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED: cancel_interaction()
static func _property(object: Object, key: String) -> Variant:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == key: return object.get(key)
	return null

## Mechanics-only preview layer. Art remains a separate floor source; these
## polygons never introduce collision or alter the dry-route geometry.
func _draw() -> void:
	if room_id.is_empty(): return
	for patch: Dictionary in _definition.shallow_patches:
		var shape := Geometry.points(patch.polygon)
		var wet: bool = _patch_enabled(str(patch.id)) and state.is_wet(str(patch.id))
		var color := Color(0.08,0.65,0.82,0.28 if wet else 0.06)
		if next_tide_visible() and _patch_enabled(str(patch.id)): color = Color(1.0,0.74,0.24,0.22)
		if not native_water_visual or next_tide_visible(): draw_colored_polygon(shape,color)
		var outline := shape.duplicate()
		outline.append(shape[0])
		if not native_water_visual or (next_tide_visible() and _patch_enabled(str(patch.id))): draw_polyline(outline,Color(1.0,0.74,0.24,0.85) if native_water_visual else Color(0.3,0.85,0.95,0.85),2.0,true)
		if next_tide_visible() and _patch_enabled(str(patch.id)):
			var center := Vector2.ZERO
			for point in shape: center += point
			center /= shape.size()
			var direction := Vector2(float(patch.direction[0]),float(patch.direction[1]))
			# Candidate native pearl paving needs a dark keyline behind the same
			# production-authored direction. No new arrow state or timing.
			if native_water_visual:
				draw_line(center-direction*25,center+direction*25,Color("79501d"),7,true)
				draw_line(center+direction*25,center+direction*10+direction.orthogonal()*10,Color("79501d"),7,true)
				draw_line(center+direction*25,center+direction*10-direction.orthogonal()*10,Color("79501d"),7,true)
			draw_line(center-direction*25,center+direction*25,Color(1,0.9,0.5),4,true)
			draw_line(center+direction*25,center+direction*10+direction.orthogonal()*10,Color(1,0.9,0.5),4,true)
			draw_line(center+direction*25,center+direction*10-direction.orthogonal()*10,Color(1,0.9,0.5),4,true)
	for point: Vector2 in _gates.values():
		_draw_mechanism("drain_gate",point,92.0)
	if _definition.has("tide_bell"):
		_draw_mechanism("tide_clock",Geometry.world_point(_definition.tide_bell),120.0)
	for point: Array in _definition.get("reef_pillars",[]):
		_draw_mechanism("reef_pillar",Geometry.world_point(point),110.0)
func _draw_mechanism(identity: String, point: Vector2, height: float) -> void:
	var native: Dictionary = _prop_frames.get(identity,{})
	if not native.is_empty():
		_art_helper.draw_frame(self,native,point,height)
	else:
		draw_circle(point,24,Color(0.92,0.87,0.63,0.8))
		draw_arc(point,30,0,TAU,32,Color(0.12,0.32,0.4),3,true)

func bind_boss(actor: Node2D) -> bool:
	if boss_state == null or not is_instance_valid(actor) or _property(actor,"boss_id") != "BO06": return false
	var health = _property(actor,"health")
	if not is_instance_valid(health) or int(health.maximum) != int(boss_state.snapshot().maximum_hp): return false
	_boss_actor = weakref(actor)
	return boss_state.set_health(int(health.current))
func boss_phase_changed(_phase: int) -> void:
	var actor = _boss_actor.get_ref() if _boss_actor != null else null
	if is_instance_valid(actor) and is_instance_valid(actor.health): boss_state.set_health(int(actor.health.current))
func can_enemy_cast(_command: Dictionary = {}) -> bool:
	return boss_state == null or boss_state.damage_admitted()
func can_enemy_hit(_command: Dictionary = {}) -> bool:
	return can_enemy_cast(_command)
func constrain_enemy_command(command: Dictionary) -> Dictionary:
	if not can_enemy_cast(command): return {}
	for key in ["origin","direction"]:
		if not command.get(key) is Vector2 or not command[key].is_finite(): return {}
	var result := command.duplicate(true)
	if room_id == "BO06" and str(result.get("action_id","")) == "shell_bombard":
		if not result.get("target") is Vector2 or not result.target.is_finite(): return {}
		# A permanent, 180px-wide dry refuge is excluded by the ENTIRE warned
		# footprint, including an18px player body. Reposition before warning.
		var refuge := Geometry.world_point([1400,1000])
		var radius := float(result.get("radius",0))
		if not is_finite(radius) or not is_equal_approx(radius,90): return {}
		if refuge.distance_to(result.target) < radius+90+18:
			result["target"] = refuge+Vector2(-240 if int(result.get("stage",0)) == 0 else 240,-100)
		result["b06_dry_refuge"] = refuge
		result["b06_dry_refuge_radius"] = 90.0
	return result
func confirm_boss_claw(command: Dictionary) -> bool:
	if boss_state == null or not can_enemy_hit(command) or command.get("action_id") != "siege_claw" or command.get("shape") != "cone": return false
	if not bool(command.get("b06_command",false)) or str(command.get("boss_id",command.get("caster_enemy_id",""))) != "BO06": return false
	var cast_id := str(command.get("cast_id",""))
	if cast_id.is_empty() or _boss_claw_receipts.has(cast_id) or _boss_claw_receipts.size() >= 128: return false
	if not command.get("origin") is Vector2 or not command.get("direction") is Vector2: return false
	var origin: Vector2 = command.origin
	var direction: Vector2 = command.direction
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx(): return false
	if not is_equal_approx(float(command.get("range",0)),170.0) or not is_equal_approx(float(command.get("angle",0)),deg_to_rad(120)): return false
	_boss_claw_receipts[cast_id] = int(state.snapshot().now_us)+16000000
	var host := get_parent()
	for index in _definition.get("reef_pillars",[]).size():
		var point := Geometry.world_point(_definition.reef_pillars[index])
		var offset := point-origin
		if offset.length() > 170 or absf(direction.angle_to(offset)) > deg_to_rad(60): continue
		if host.has_method("has_line_of_sight") and not host.has_line_of_sight(origin,point): continue
		if boss_state.confirm_claw_pillar_contact("reef_west" if index == 0 else "reef_east"): return true
	return false

func push_actor(actor: Node2D, displacement: Vector2) -> Vector2:
	if not is_instance_valid(actor) or not displacement.is_finite() or displacement.is_zero_approx(): return Vector2.ZERO
	var host := get_parent()
	if not host.has_method("move_actor"): return Vector2.ZERO
	var radius := 18.0
	var raw_radius: Variant = _property(actor,"navigation_radius")
	if raw_radius is float or raw_radius is int: radius = float(raw_radius)
	var insets := Geometry2D.offset_polygon(Geometry.polygon(room_id),-radius)
	if insets.is_empty(): return Vector2.ZERO
	var actor_id := "player"
	if _property(actor,"actor_kind") == "enemy":
		actor_id = ""
		for key: String in _actors:
			if _actors[key].actor.get_ref() == actor: actor_id = key; break
		if actor_id.is_empty(): return Vector2.ZERO
	var origin: Vector2 = actor.position
	var reduction := 0.0
	if actor_id == "player":
		var equipment: Variant = _property(actor, "loadout")
		if equipment != null:
			equipment.refresh_modifiers()
			reduction = clampf(float(equipment.modifiers().get("received_displacement_reduction", 0.0)), 0.0, 0.5)
	var clipped := clipped_push(actor_id,origin,displacement,insets[0],reduction)
	actor.position = host.move_actor(origin,clipped-origin,radius)
	return actor.position-origin

## Return a reachable dry point only when one lies within the authored movement
## budget. No teleport or projected point beyond an obstruction is admitted.
func nearest_dry_point(actor: Node2D, max_distance: float = 70.0) -> Vector2:
	if not is_instance_valid(actor): return Vector2.ZERO
	var origin: Vector2 = actor.position
	if not is_finite(max_distance) or max_distance <= 0 or max_distance > 70: return origin
	var current := patch_at(actor)
	if current.is_empty() or not state.is_wet(current): return origin
	var shape: PackedVector2Array = _patch_shapes[current]
	var best := origin
	var distance := max_distance+0.001
	var host := get_parent()
	var radius: float = float(_property(actor,"navigation_radius")) if _property(actor,"navigation_radius") != null else 18.0
	for index in shape.size():
		var edge_start := shape[index]
		var edge_end := shape[(index+1)%shape.size()]
		var nearest := Geometry2D.get_closest_point_to_segment(origin,edge_start,edge_end)
		var outward := Vector2((edge_end-edge_start).y,-(edge_end-edge_start).x).normalized()
		var target := nearest+outward*1.0
		if origin.distance_to(target) > distance: continue
		if not Geometry2D.is_point_in_polygon(target,Geometry.polygon(room_id)): continue
		var dry := true
		for id: String in _patch_shapes:
			if _patch_enabled(id) and state.is_wet(id) and Geometry2D.is_point_in_polygon(target,_patch_shapes[id]): dry = false; break
		if not dry: continue
		if host.has_method("blocked_fraction") and host.blocked_fraction(origin,target,radius) < 1.0: continue
		best = target
		distance = origin.distance_to(target)
	return best
func tidal_direction_at(point: Vector2) -> Vector2:
	if not point.is_finite(): return Vector2.ZERO
	for patch: Dictionary in _definition.get("shallow_patches",[]):
		if _patch_enabled(str(patch.id)) and Geometry2D.is_point_in_polygon(point,_patch_shapes[str(patch.id)]):
			return Vector2(float(patch.direction[0]),float(patch.direction[1])).normalized()
	return Vector2.ZERO
func admit_coral_wall(start: Vector2, end: Vector2, half_width: float = 6.0) -> bool:
	if not start.is_finite() or not end.is_finite() or not is_finite(half_width) or half_width <= 0 or half_width > 12 or not is_equal_approx(start.distance_to(end),120.0): return false
	var shapes := Geometry2D.offset_polyline(PackedVector2Array([start,end]),half_width,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	if shapes.is_empty(): return false
	var floor_polygon := Geometry.polygon(room_id)
	for shape: PackedVector2Array in shapes:
		if not Geometry2D.clip_polygons(shape,floor_polygon).is_empty(): return false
		for path: Array in _definition.get("dry_routes",[]):
			for corridor: PackedVector2Array in Geometry2D.offset_polyline(Geometry.points(path),90.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
				if not Geometry2D.intersect_polygons(shape,corridor).is_empty(): return false
	var protected: Array = [_definition.entry,_definition.exit]
	if _definition.has("tide_bell"): protected.append(_definition.tide_bell)
	for gate: Dictionary in _definition.get("gates",[]): protected.append(gate.position)
	for value: Array in protected:
		if Geometry2D.get_closest_point_to_segment(Geometry.world_point(value),start,end).distance_to(Geometry.world_point(value)) <= 68+half_width: return false
	var host := get_parent()
	var actors: Array = []
	var player: Variant = _property(host,"player")
	if is_instance_valid(player): actors.append(player)
	var enemies: Variant = _property(host,"enemies")
	if is_instance_valid(enemies): actors.append_array(enemies.get_children())
	for actor: Node2D in actors:
		var radius: Variant = _property(actor,"navigation_radius")
		var body_radius: float = float(radius) if radius is float or radius is int else 18.0
		if Geometry2D.get_closest_point_to_segment(actor.position,start,end).distance_to(actor.position) <= body_radius+half_width: return false
	return true

func load_candidate_art() -> void:
	var path := "res://scripts/levels/b06/art/native_art.gd"
	if not ResourceLoader.exists(AssetCatalog.resolve(path)): return
	_art_helper = load(AssetCatalog.resolve(path))
	for identity: String in ["drain_gate","reef_pillar","tide_clock"]:
		_prop_frames[identity] = _art_helper.prop_frame(identity)
	queue_redraw()

func reset_boss_encounter(actor: Node2D) -> bool:
	if room_id!="BO06" or not is_instance_valid(actor) or _property(actor,"boss_id")!="BO06": return false
	var next_tide := Tide.new()
	var current: Dictionary = state.snapshot()
	if not next_tide.configure("BO06",current.patch_ids,current.gates): return false
	var next_boss := BossState.new()
	if not next_boss.configure_shared(int(actor.health.maximum),next_tide,{"reef_west":"bay_west","reef_east":"bay_east"}): return false
	cancel_interaction()
	state = next_tide
	boss_state = next_boss
	_boss_claw_receipts.clear()
	_boss_actor = weakref(actor)
	queue_redraw()
	return true
