extends "res://scripts/levels/b05/world/mechanism_runtime.gd"
## Production host. Room owns tick ordering, checkpoint boundaries and bridges.
const WellTarget = preload("res://scripts/levels/b05/world/root_well_target.gd")
const Geometry = preload("res://scripts/levels/b05/world/room_geometry.gd")
const Numbers = preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
const Snapshot = preload("res://scripts/levels/b05/world/mechanism_snapshot.gd")
const BOSS_ROTATION_SECONDS := 6.0 # Implementation supplement; frozen design gives sequence, not timing.
const ROOT_SHIELD_DURATION := 12.0 # Explicit implementation supplement, 2026-10-02.
var room: Node2D
var _well_modes: Dictionary = {}
var _well_activation: Dictionary = {}
var _difficulty := 0
var _pending_guards: Dictionary = {}
var _boss_phase := 0
var _boss_cycle := 0.0
var _well_footprints: Array[Vector3] = []
var _well_navigation_bounds: Array[Rect2] = []
var _sunleaf_positions: Dictionary = {}
var _sunleaf_closed: Dictionary = {}
var _hazard_admission=preload("res://scripts/levels/b05/world/hazard_admission.gd").new()
var _runtime_command_serial:=0
var _sunleaf_visuals: Array[Node2D]=[]
signal well_destroyed(well_id: String)

func configure_room(host: Node2D, definition: Dictionary, difficulty: int) -> bool:
	if not _room_id.is_empty() or not is_instance_valid(host) or definition.is_empty(): return false
	var wells := {}
	var gates := {}
	var frontline: Dictionary = Numbers.ordinary("B05-M01",int(definition.enemy_level),difficulty,"normal",{},1)
	if frontline.is_empty(): return false
	for source: Dictionary in definition.get("root_wells",[]):
		var point := Geometry.world_point(source.position)
		wells[str(source.id)] = {"x":point.x,"y":point.y,"frontline_hp":frontline.max_hp,"network_id":source.network_id}
	for source: Dictionary in definition.get("gates",[]):
		var point := Geometry.world_point(source.position)
		gates[str(source.id)] = {"x":point.x,"y":point.y,"well_ids":source.well_ids,"bridge_id":source.bridge_id}
	if not configure(str(definition.id),wells,gates,ROOT_SHIELD_DURATION,Balance.INTERACTION_RADIUS): return false
	room = host
	if not _hazard_admission.configure(str(definition.id)): return false
	_difficulty = difficulty
	for source: Dictionary in definition.get("root_wells",[]):
		var point := Geometry.world_point(source.position)
		var radius := float(source.foot_radius_world)
		_well_footprints.append(Vector3(point.x,point.y,radius))
		_well_navigation_bounds.append(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2.0))
	for source: Dictionary in definition.get("spotlights",[]):
		_sunleaf_positions[str(source.id)] = Geometry.world_point(source.position)
		_sunleaf_closed[str(source.id)] = false
		var visual:=preload("res://scripts/levels/b05/world/sunleaf_visual.gd").new()
		if visual.configure(self,str(source.id),_sunleaf_positions[str(source.id)]):
			room.add_child(visual);_sunleaf_visuals.append(visual)
		else: visual.free()
	bridge_changed.connect(_sync_bridge_geometry)
	_sync_bridge_geometry("",false)
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
	if _room_id == "BO05": boss_phase_changed(1)
	if _room_id == "L27": encounter_started(0)
	return true

func well_is_active(id: String) -> bool:
	if not bool(_well_activation.get(id,false)): return false
	var target = _targets.get(id)
	return is_instance_valid(target) and _network.well_reaches(id,target.position)

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
		var at: Vector2 = _targets[id].position
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
	if _room_id != "BO05": return
	_boss_phase = clampi(phase,1,3)
	_boss_cycle = 0.0
	var ids: Array = _targets.keys()
	ids.sort()
	for i in ids.size(): _well_activation[ids[i]] = i < (1 if _boss_phase == 1 else 2)

func all_wells_closed() -> bool:
	for id: String in _targets:
		if _network.well_reaches(id,_targets[id].position): return false
	return true

func well_destroyed_by_hit(id: String, context: Dictionary) -> void:
	well_destroyed.emit(id)
	if bool(context.get("b05_active_well_destroyed",false)) and is_instance_valid(room.get("_boss_actor")):
		room.get("_boss_actor").apply_arena_counter("b05_root_well",{"well_id":id})
	if is_instance_valid(room.player) and room.player.has_method("notify_hostile_destructible_destroyed") and (bool(context.get("equipment_eligible",false)) or not context.get("attacker_stats",{}).is_empty()):
		room.player.notify_hostile_destructible_destroyed(id)

func tick(delta: float, paused: bool = false) -> bool:
	var accepted := super.tick(delta,paused)
	if not accepted or paused or (is_inside_tree() and get_tree().paused): return accepted
	_hazard_admission.advance(delta)
	if _room_id == "BO05" and _boss_phase == 3:
		_boss_cycle += delta
		var steps := int(floor(_boss_cycle / BOSS_ROTATION_SECONDS))
		_boss_cycle = fmod(_boss_cycle,BOSS_ROTATION_SECONDS)
		var ids: Array = _targets.keys()
		ids.sort()
		if steps > 0 and not ids.is_empty():
			var previous := _well_activation.duplicate()
			for index in ids.size():
				_well_activation[ids[index]] = previous[ids[posmod(index-steps,ids.size())]]
	for id: String in _well_modes.keys():
		_well_modes[id].remaining = maxf(0.0,float(_well_modes[id].remaining)-delta)
		if float(_well_modes[id].remaining) <= 0.0: _well_modes.erase(id)
	var wells: Dictionary = _network.snapshot().wells
	for id: String in _targets:
		if is_instance_valid(_targets[id]): _targets[id].synchronize_well(wells[id])
	return accepted

func _exit_tree() -> void:
	for visual: Node2D in _sunleaf_visuals:
		if is_instance_valid(visual): visual.queue_free()
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
	result.merge({"production_version":2,"sunleaf_closed":_sunleaf_closed.duplicate(),"difficulty":_difficulty,"well_modes":_well_modes.duplicate(true),"well_activation":_well_activation.duplicate(true),"boss_phase":_boss_phase,"boss_cycle":_boss_cycle,"plant_guards":plants})
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
	for id: String in _sunleaf_closed:
		_sunleaf_closed[id] = bool(data.get("sunleaf_closed",{}).get(id,false))
	for visual: Node2D in _sunleaf_visuals: visual.queue_redraw()
	_hazard_admission.reservations.clear()
	_cancel_shaded_casts()
	for id: String in _plants: _restore_guard(id)
	var wells: Dictionary = _network.snapshot().wells
	for id: String in _targets:
		if is_instance_valid(_targets[id]): _targets[id].synchronize_well(wells[id])
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

# Destroyed wells retain their authored ground footprint; only art/state changes.
func blocks_ground(point: Vector2, radius: float) -> bool:
	for footprint: Vector3 in _well_footprints:
		if point.distance_squared_to(Vector2(footprint.x,footprint.y)) < pow(footprint.z+radius,2): return true
	return false

func navigation_bounds() -> Array[Rect2]:
	return _well_navigation_bounds.duplicate()

func _sync_bridge_geometry(_bridge_id: String, _opened: bool) -> void:
	if not is_instance_valid(room): return
	var geometry: Array[Rect2] = []
	var kinds: Array = []
	var source: Array = room.layout.get("static_obstructions",[])
	var source_kinds: Array = room.layout.get("static_obstruction_kinds",[])
	for index in source.size():
		var kind := str(source_kinds[index]) if index < source_kinds.size() else ""
		if kind.begins_with("b05_bridge:") and bridge_is_open(kind.trim_prefix("b05_bridge:")): continue
		geometry.append(source[index])
		kinds.append(kind)
	room.layout.obstructions = geometry
	room.layout.obstruction_kinds = kinds
	room.obstructions.assign(geometry)
	room._refresh_terrain_canvas()
	room.queue_redraw()

func nearby_mechanism(point: Vector2) -> Dictionary:
	var gates: Dictionary = _network.snapshot().gates
	var result := {}
	var nearest := INF
	for id: String in _gate_positions:
		if bool(gates[id].open): continue
		var at: Vector2 = _gate_positions[id]
		var distance := point.distance_squared_to(at)
		if distance > Balance.INTERACTION_RADIUS * Balance.INTERACTION_RADIUS or distance >= nearest: continue
		if not room.has_line_of_sight(point,at): continue
		nearest = distance
		result = {"kind":"b05_gate","id":id,"position":at,"label":"关闭水闸 · 0.6秒" if Words.locale != "en" else "Close watergate · 0.6s"}
	for id: String in _sunleaf_positions:
		var at: Vector2 = _sunleaf_positions[id]
		var distance := point.distance_squared_to(at)
		if distance > Balance.INTERACTION_RADIUS * Balance.INTERACTION_RADIUS or distance >= nearest: continue
		if not room.has_line_of_sight(point,at): continue
		nearest = distance
		var closed: bool = _sunleaf_closed[id]
		result = {"kind":"b05_sunleaf","id":id,"position":at,"label":("打开聚光叶" if closed else "合拢聚光叶 · 遮光") if Words.locale != "en" else ("Open sunleaf" if closed else "Close sunleaf · Shade")}
	return result

func toggle_sunleaf(id: String, actor: Node2D) -> bool:
	if not _sunleaf_positions.has(id) or not is_instance_valid(actor): return false
	if Game.run == null or Game.run.hp <= 0.0 or not room.controls_enabled(): return false
	var at: Vector2 = _sunleaf_positions[id]
	if actor.position.distance_to(at) > Balance.INTERACTION_RADIUS or not room.has_line_of_sight(actor.position,at): return false
	_sunleaf_closed[id] = not bool(_sunleaf_closed[id])
	if bool(_sunleaf_closed[id]): _cancel_shaded_casts()
	for visual: Node2D in _sunleaf_visuals: visual.queue_redraw()
	return true

# Fixed authored leaves divide L29 by nearest source; other rooms keep daylight.
# This deterministic scope is an explicit implementation supplement.
func can_enemy_cast(actor: Node2D, command: Dictionary) -> bool:
	if command.has("b05_admission_id") and (not bool(command.get("b05_admitted",false)) or not _hazard_admission.admitted(str(command.b05_admission_id))): return false
	if not bool(command.get("requires_sunlight",false)) or _sunleaf_positions.is_empty(): return true
	if not is_instance_valid(actor): return false
	var nearest := INF
	var source := ""
	for id: String in _sunleaf_positions:
		var distance: float = actor.position.distance_squared_to(_sunleaf_positions[id])
		if distance < nearest:
			nearest = distance
			source = id
	return not bool(_sunleaf_closed.get(source,false))

func _cancel_shaded_casts() -> void:
	for actor in room.enemies.get_children():
		if not actor is Node2D or str(actor.get("enemy_id")) != "B05-M14": continue
		if can_enemy_cast(actor,{"requires_sunlight":true}): continue
		if is_instance_valid(room.enemy_skills): room.enemy_skills.cancel_sunlight(actor)
		var brain = actor.get("brain")
		if brain != null and brain.has_method("current_skill") and bool(brain.current_skill().get("requires_sunlight",false)):
			brain.interrupt(actor)

func constrain_enemy_command(command: Dictionary,actor: Node2D,allow_reposition: bool=true) -> Dictionary:
	var id:=str(command.get("b05_admission_id",command.get("cast_id","")))
	if id.is_empty():
		_runtime_command_serial+=1
		id="runtime:%d:%d"%[actor.get_instance_id(),_runtime_command_serial]
	var result: Dictionary=_hazard_admission.admit(command,id,allow_reposition)
	if bool(result.get("b05_admitted",false)):
		_hazard_admission.reservations[id]["owner_id"]=actor.get_instance_id()
	return result

func constrain_boss_command(command: Dictionary,actor: Node2D,allow_reposition: bool=true) -> Dictionary:
	return constrain_enemy_command(command,actor,allow_reposition)

func cancel_enemy_command(command: Dictionary) -> void:
	_hazard_admission.cancel(str(command.get("b05_admission_id","")))

func cancel_enemy_owner(actor: Node2D) -> void:
	if not is_instance_valid(actor): return
	for id: String in _hazard_admission.reservations.keys():
		if int(_hazard_admission.reservations[id].get("owner_id",0))==actor.get_instance_id(): _hazard_admission.cancel(id)

func encounter_started(index: int) -> void:
	if _room_id!="L27": return
	var ids: Array=_targets.keys();ids.sort()
	if ids.is_empty(): return
	for offset in ids.size(): _well_activation[ids[offset]]=offset==posmod(index,ids.size())
