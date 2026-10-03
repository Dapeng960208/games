extends "res://scripts/combat/boss_brain.gd"
## BO06 combat sequencing. The room owns the ONLY tide/exposure/output clock.
const B06 = preload("res://scripts/combat/b06_enemy_skills.gd")
var _stage := 0
var _locked_origin := Vector2.ZERO
var _locked_target := Vector2.ZERO
var _next_command: Dictionary = {}
func configure(value: Dictionary, seed_value: int = 0) -> void:
	super.configure(value,seed_value)
	_stage = 0
	_next_command.clear()
func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or not is_finite(delta) or delta <= 0 or not _alive(actor) or not _alive(victim): return
	elapsed += delta
	_last_actor = weakref(actor)
	actor.velocity = Vector2.ZERO
	var host: Variant = B06.mechanics(actor)
	if not is_instance_valid(host): return
	host.boss_phase_changed(phase)
	var next_phase := _phase_for_ratio(_health_ratio(actor))
	if next_phase > phase:
		phase = next_phase
		_enter_phase(actor)
	if not host.can_enemy_cast():
		command.clear()
		_next_command.clear()
		state = &"recovery"
		state_time = 0.0
		_set_actor_state(actor,&"recovery")
		return
	state_time = maxf(0,state_time-delta)
	match state:
		&"emerging", &"phase_shift":
			_set_actor_state(actor,&"recovery" if state == &"phase_shift" else &"emerging")
			if state_time <= 0: _begin_action(actor,victim)
		&"stage_gap":
			_set_actor_state(actor,&"recovery")
			if state_time <= 0:
				command = _next_command
				_next_command = {}
				_start_warning(actor)
		&"telegraph":
			# Freeze at warning start: eventual hit and stage followups use this
			# identical geometry even if the player crosses behind the boss.
			actor.aim_direction = command.direction
			_set_actor_state(actor,&"telegraph")
			if state_time <= 0:
				state = &"locked"
				state_time = float(command.lock)
				state_duration = state_time
		&"locked":
			actor.aim_direction = command.direction
			_set_actor_state(actor,&"locked")
			if state_time <= 0: _execute(actor)
		&"recovery":
			_recovery_elapsed += delta
			_set_actor_state(actor,&"recovery")
			if state_time <= 0: _begin_action(actor,victim)
func _enter_phase(actor: Node2D) -> void:
	command.clear()
	_next_command.clear()
	_released_pose.clear()
	current_action = ""
	state = &"phase_shift"
	state_time = .8
	state_duration = .8
	actor.boss_phase_started(phase,_health_ratio(actor))
	B06.mechanics(actor).boss_phase_changed(phase)
func available_actions(for_phase: int = -1) -> Array:
	var selected := phase if for_phase < 0 else for_phase
	var result: Array = []
	for index in B06.BOSS_ACTIONS.size():
		if int(definition.difficulty) < int(B06.BOSS_GATES[index]): continue
		if index >= 2 and selected < 2: continue
		result.append(B06.BOSS_ACTIONS[index])
	return result
func _begin_action(actor: Node2D, victim: Node2D, forced_action: String = "") -> void:
	var candidates := available_actions()
	if not forced_action.is_empty(): candidates = [forced_action] if forced_action in candidates else []
	current_action = ""
	for offset in candidates.size():
		var action: String = candidates[(action_index+offset)%candidates.size()]
		if float(_action_ready_at.get(action,0)) > elapsed: continue
		if action == "coral_escort" and (brood_batches >= 2 or _owned_add_count(actor) >= 2): continue
		if action == "siege_claw" and actor.position.distance_to(victim.position) > 190: continue
		current_action = action
		break
	if current_action.is_empty():
		state = &"recovery"
		state_time = .15
		state_duration = .15
		if actor.position.distance_to(victim.position) > 160 and actor.room.has_method("navigation_direction"):
			actor.velocity = actor.room.navigation_direction(actor.position,victim.position,float(definition.navigation_radius))*float(definition.move_speed)
			actor.state = &"chase"
		return
	action_index += 1
	_stage = 0
	_locked_origin = actor.position
	_locked_target = victim.position
	command = _build_action(actor,victim,current_action)
	if command.is_empty():
		state = &"recovery"
		state_time = .15
		return
	command["cast_id"] = "BO06:%d:%d" % [actor.get_instance_id(),action_index]
	_start_warning(actor)
func _start_warning(actor: Node2D) -> void:
	state = &"telegraph"
	state_time = float(command.tell)
	state_duration = state_time
	_released_pose.clear()
	_set_actor_state(actor,&"telegraph")
func _build_action(actor: Node2D, _victim: Node2D, action: String) -> Dictionary:
	var result := B06.boss_action(definition,action,_locked_origin,_locked_target,phase,_stage)
	return B06.mechanics(actor).constrain_enemy_command(result) if not result.is_empty() else {}
func _execute(actor: Node2D) -> void:
	var host: Variant = B06.mechanics(actor)
	if not host.can_enemy_cast(command):
		command.clear()
		state = &"recovery"
		state_time = .1
		return
	var released := command.duplicate(true)
	actor.cast_enemy_skill(released)
	_released_pose = {"direction":released.direction,"kind":released.kind}
	if _stage == 0:
		_action_ready_at[current_action] = elapsed + float(released.cooldown)
		_actions_used[current_action] = int(_actions_used.get(current_action,0))+1
		if current_action == "coral_escort": brood_batches += 1
	if _stage+1 < int(released.get("stage_count",1)):
		_stage += 1
		_next_command = _build_action(actor,null,current_action)
		if not _next_command.is_empty():
			_next_command["cast_id"] = str(released.cast_id)+":stage:"+str(_stage)
			state = &"stage_gap"
			state_time = maxf(0,float(released.stage_interval)-float(_next_command.tell)-float(_next_command.lock))
			state_duration = state_time
			command.clear()
			return
	_last_action = current_action
	state = &"recovery"
	state_time = float(released.get("recovery",1.4))
	state_duration = state_time
	_recovery_elapsed = 0
	command.clear()
	_set_actor_state(actor,&"recovery")
func incoming_damage_multiplier() -> float: return 1.0 # Region multiplier lives in the shared hit runtime.
func outgoing_damage_multiplier() -> float: return 1.0
func on_damaged(actor: Node2D, _context: Dictionary) -> void:
	var host: Variant = B06.mechanics(actor)
	if is_instance_valid(host): host.boss_phase_changed(phase)
func apply_arena_counter(_counter_id: String, _payload: Dictionary = {}) -> bool: return false

func capture_candidate(actor_to_id: Callable) -> Dictionary:
	var payload := {"version":1,"boss_id":"BO06","difficulty":int(definition.difficulty),"phase":phase,"state":str(state),"state_time":state_time,"state_duration":state_duration,"elapsed":elapsed,"action_index":action_index,"current_action":current_action,"command":command,"next_command":_next_command,"stage":_stage,"locked_origin":_locked_origin,"locked_target":_locked_target,"ready_at":_action_ready_at,"actions_used":_actions_used,"last_action":_last_action,"released_pose":_released_pose,"recovery_elapsed":_recovery_elapsed,"brood_batches":brood_batches,"stopped":stopped}
	var encoded := preload("res://scripts/combat/b06_combat_state_codec.gd").encode(payload,actor_to_id)
	return encoded.value if encoded.ok else {}
func validate_candidate(value: Dictionary, id_to_actor: Callable) -> bool:
	return not _decode_candidate(value,id_to_actor).is_empty()
func restore_candidate(value: Dictionary, id_to_actor: Callable) -> bool:
	var saved := _decode_candidate(value,id_to_actor)
	if saved.is_empty(): return false
	phase = int(saved.phase)
	state = StringName(saved.state)
	state_time = float(saved.state_time)
	state_duration = float(saved.state_duration)
	elapsed = float(saved.elapsed)
	action_index = int(saved.action_index)
	current_action = str(saved.current_action)
	command = saved.command
	_next_command = saved.next_command
	_stage = int(saved.stage)
	_locked_origin = saved.locked_origin
	_locked_target = saved.locked_target
	_action_ready_at = saved.ready_at
	_actions_used = saved.actions_used
	_last_action = str(saved.last_action)
	_released_pose = saved.released_pose
	_recovery_elapsed = float(saved.recovery_elapsed)
	brood_batches = int(saved.brood_batches)
	stopped = bool(saved.stopped)
	return true
func _decode_candidate(value: Dictionary, resolver: Callable) -> Dictionary:
	var decoded := preload("res://scripts/combat/b06_combat_state_codec.gd").decode(value,resolver)
	if not decoded.ok or not decoded.value is Dictionary: return {}
	var saved: Dictionary = decoded.value
	var keys := ["version","boss_id","difficulty","phase","state","state_time","state_duration","elapsed","action_index","current_action","command","next_command","stage","locked_origin","locked_target","ready_at","actions_used","last_action","released_pose","recovery_elapsed","brood_batches","stopped"]
	if saved.size() != keys.size() or not saved.has_all(keys) or saved.version != 1 or saved.boss_id != "BO06" or saved.difficulty != definition.difficulty: return {}
	if saved.state not in ["emerging","phase_shift","stage_gap","telegraph","locked","recovery"] or not saved.stopped is bool: return {}
	for field: String in ["phase","stage","action_index","brood_batches"]:
		if not preload("res://scripts/combat/b06_combat_state_codec.gd")._number(saved[field]) or saved[field] != int(saved[field]): return {}
	if int(saved.phase)<1 or int(saved.phase)>3 or int(saved.stage)<0 or int(saved.stage)>1 or int(saved.action_index)<0 or int(saved.brood_batches)<0 or int(saved.brood_batches)>2: return {}
	for field: String in ["state_time","state_duration","elapsed","recovery_elapsed"]:
		if not preload("res://scripts/combat/b06_combat_state_codec.gd")._number(saved[field]) or float(saved[field])<0: return {}
	if float(saved.state_time)>float(saved.state_duration) or float(saved.state_duration)>60: return {}
	if not saved.locked_origin is Vector2 or not saved.locked_target is Vector2: return {}
	for field: String in ["command","next_command","ready_at","actions_used","released_pose"]:
		if not saved[field] is Dictionary: return {}
	for field: String in ["command","next_command"]:
		var cast: Dictionary = saved[field]
		if cast.is_empty(): continue
		if cast.get("boss_id") != "BO06" or str(cast.get("action_id","")) not in B06.BOSS_ACTIONS or not cast.get("origin") is Vector2 or not cast.get("direction") is Vector2: return {}
		if B06.freeze_damage(cast,definition).is_empty(): return {}
	if saved.state in ["telegraph","locked"] and saved.command.is_empty(): return {}
	if saved.state == "stage_gap" and saved.next_command.is_empty(): return {}
	for action: String in saved.ready_at:
		if action not in B06.BOSS_ACTIONS or not preload("res://scripts/combat/b06_combat_state_codec.gd")._number(saved.ready_at[action]) or float(saved.ready_at[action])<0 or float(saved.ready_at[action])>float(saved.elapsed)+24: return {}
	for action: String in saved.actions_used:
		if action not in B06.BOSS_ACTIONS or not preload("res://scripts/combat/b06_combat_state_codec.gd")._number(saved.actions_used[action]) or float(saved.actions_used[action])<0 or saved.actions_used[action]!=int(saved.actions_used[action]): return {}
	return saved
