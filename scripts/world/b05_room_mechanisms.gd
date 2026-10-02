extends "res://scripts/world/b05_mechanism_runtime.gd"
## Production host. Room owns tick ordering, checkpoint boundaries and bridges.
const WellTarget = preload("res://scripts/world/b05_root_well_target.gd")
const Geometry = preload("res://scripts/world/b05_room_geometry.gd")
const Numbers = preload("res://scripts/combat/b05_enemy_numbers.gd")
const Snapshot = preload("res://scripts/world/b05_mechanism_snapshot.gd")
const ROOT_SHIELD_DURATION := 12.0 # Explicit implementation supplement, 2026-10-02.
var room: Node2D
var _well_modes: Dictionary = {}
var _well_activation: Dictionary = {}
var _difficulty := 0
var _pending_guards: Dictionary = {}
var _boss_phase := 0
var _boss_cycle := 0.0
signal well_destroyed(well_id: String)

func configure_room(host: Node2D, definition: Dictionary, difficulty: int) -> bool:
	if not is_instance_valid(host) or definition.is_empty(): return false
	var wells := {}
	var gates := {}
	var frontline: Dictionary = Numbers.ordinary("B05-M01",int(definition.enemy_level),difficulty)
	if frontline.is_empty(): return false
	for source: Dictionary in definition.get("root_wells",[]):
		var point := Geometry.world_point(source.position)
		wells[str(source.id)] = {"x":point.x,"y":point.y,"frontline_hp":frontline.max_hp,"network_id":source.network_id}
	for source: Dictionary in definition.get("gates",[]):
		var point := Geometry.world_point(source.position)
		gates[str(source.id)] = {"x":point.x,"y":point.y,"well_ids":source.well_ids,"bridge_id":source.bridge_id}
	if not configure(str(definition.id),wells,gates,ROOT_SHIELD_DURATION,Balance.INTERACTION_RADIUS): return false
	room = host
	_difficulty = difficulty
	# Replace invisible unit-test targets with the ordinary combat actor path.
	for old in _targets.values(): old.free()
	_targets.clear()
	for id: String in wells:
		var value: Dictionary = _network.snapshot().wells[id]
		var target := WellTarget.new()
		target.room = room
		target.mechanism_host = self
		target.well_id = id
		target.position = Vector2(value.x,value.y)
		target.configure({"enemy_id":"B05-ROOT","enemy_level":int(definition.enemy_level),"max_hp":value.maximum,"armor":0,"magic_resist":0,"navigation_radius":28,"ruleset_version":2}, {"static_actor":true,"actor_kind":"objective","reward_enabled":false})
		room.enemies.add_child(target)
		_targets[id] = target
		_well_activation[id] = true
	return true

func well_is_active(id: String) -> bool:
	if not bool(_well_activation.get(id,false)): return false
	var value: Dictionary = _network.snapshot().wells.get(id,{})
	return not value.is_empty() and _network.well_reaches(id,Vector2(value.x,value.y))

func connected(actor: Node2D) -> bool:
	if not is_instance_valid(actor): return false
	for id: String in _targets:
		if well_is_active(id) and _network.well_reaches(id,to_local(actor.global_position)): return true
	return false

func nearest_active_well(point: Vector2) -> Dictionary:
	var result := {}
	var distance := INF
	for id: String in _targets:
		if not well_is_active(id): continue
		var value: Dictionary = _network.snapshot().wells[id]
		var at := Vector2(value.x,value.y)
		var candidate := point.distance_squared_to(at)
		if candidate < distance:
			distance = candidate
			result = {"id":id,"position":at,"mode":str(_well_modes.get(id,{}).get("mode","shield")),"remaining":float(_well_modes.get(id,{}).get("remaining",0.0))}
	return result

func set_well_mode(actor: Node2D, mode: String, duration: float) -> bool:
	if mode not in ["shield","speed"] or not is_finite(duration) or duration <= 0.0 or not connected(actor): return false
	var well := nearest_active_well(to_local(actor.global_position))
	if well.is_empty(): return false
	_well_modes[well.id] = {"mode":mode,"remaining":duration}
	return true

func boss_root_state() -> Dictionary:
	var positions: Array[Vector2] = []
	for id: String in _targets:
		if well_is_active(id): positions.append(_targets[id].position)
	return {"active_count":positions.size(),"active_positions":positions}

func boss_phase_changed(phase: int) -> void:
	_boss_phase = clampi(phase,1,3)
	_boss_cycle = 0.0
	var ids: Array = _targets.keys()
	ids.sort()
	for i in ids.size(): _well_activation[ids[i]] = i < (1 if _boss_phase == 1 else 2)

func all_wells_closed() -> bool:
	for value: Dictionary in _network.snapshot().wells.values():
		if float(value.hp) > 0.0 and not bool(value.closed): return false
	return true

func well_destroyed_by_hit(id: String, context: Dictionary) -> void:
	well_destroyed.emit(id)
	if is_instance_valid(room.get("_boss_actor")):
		room.get("_boss_actor").apply_arena_counter("b05_root_well",{"well_id":id})
	if is_instance_valid(room.player) and room.player.has_method("notify_hostile_destructible_destroyed") and (bool(context.get("equipment_eligible",false)) or not context.get("attacker_stats",{}).is_empty()):
		room.player.notify_hostile_destructible_destroyed(id)

func tick(delta: float, paused: bool = false) -> bool:
	var accepted := super.tick(delta,paused)
	if not accepted or paused: return accepted
	for id: String in _well_modes.keys():
		_well_modes[id].remaining = maxf(0.0,float(_well_modes[id].remaining)-delta)
		if float(_well_modes[id].remaining) <= 0.0: _well_modes.erase(id)
	for id: String in _targets:
		if is_instance_valid(_targets[id]): _targets[id].synchronize_well(_network.snapshot().wells[id])
	return accepted

func _exit_tree() -> void:
	for target in _targets.values():
		if is_instance_valid(target): target.queue_free()
	super._exit_tree()

func well_can_refresh(id: String) -> bool:
	return well_is_active(id) and str(_well_modes.get(id,{}).get("mode","shield")) == "shield"

func movement_multiplier(actor: Node2D) -> float:
	if not is_instance_valid(actor): return 1.0
	for id: String in _targets:
		if well_is_active(id) and str(_well_modes.get(id,{}).get("mode","shield")) == "speed" and _network.well_reaches(id,to_local(actor.global_position)):
			return 1.08
	return 1.0

func checkpoint() -> Dictionary:
	var result := super.checkpoint()
	var plants := _pending_guards.duplicate(true)
	for id: String in _plants:
		var binding: Dictionary = _plants[id]
		var actor = binding.actor.get_ref()
		var health = binding.health.get_ref()
		var status = binding.status.get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(health) or not is_instance_valid(status): continue
		plants[id] = {"enemy_id":actor.enemy_id,"maximum_hp":health.maximum,"guard":status.guards.get("b05_root_network",{}).duplicate(true)}
	result.merge({"production_version":1,"difficulty":_difficulty,"well_modes":_well_modes.duplicate(true),"well_activation":_well_activation.duplicate(true),"boss_phase":_boss_phase,"boss_cycle":_boss_cycle,"plant_guards":plants})
	return result

func restore_checkpoint(data: Dictionary) -> bool:
	if not Snapshot.validate_checkpoint(data) or data.room_id != _room_id or int(data.difficulty) != _difficulty: return false
	for id: String in data.plant_guards:
		if not _plants.has(id): continue
		var actor = _plants[id].actor.get_ref()
		var health = _plants[id].health.get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(health) or actor.enemy_id != data.plant_guards[id].enemy_id or float(health.maximum) != float(data.plant_guards[id].maximum_hp): return false
	if not super.restore_checkpoint(data): return false
	_well_modes = data.well_modes.duplicate(true)
	_well_activation = data.well_activation.duplicate(true)
	_boss_phase = int(data.boss_phase)
	_boss_cycle = float(data.boss_cycle)
	_pending_guards = data.plant_guards.duplicate(true)
	for id: String in _plants: _restore_guard(id)
	for id: String in _targets:
		if is_instance_valid(_targets[id]): _targets[id].synchronize_well(_network.snapshot().wells[id])
	return true

func register_plant(actor_id: String, actor: Node2D) -> bool:
	if _pending_guards.has(actor_id):
		var saved: Dictionary = _pending_guards[actor_id]
		if actor.enemy_id != saved.enemy_id or float(actor.health.maximum) != float(saved.maximum_hp): return false
	if not super.register_plant(actor_id,actor): return false
	_restore_guard(actor_id)
	return true

func _restore_guard(id: String) -> void:
	if not _pending_guards.has(id) or not _plants.has(id): return
	var status = _plants[id].status.get_ref()
	if not is_instance_valid(status): return
	status.guards.erase("b05_root_network")
	var guard: Dictionary = _pending_guards[id].guard
	if not guard.is_empty() and float(guard.remaining)>0.0 and float(guard.amount)>0.0:
		status.guards["b05_root_network"] = guard.duplicate(true)
	_pending_guards.erase(id)
