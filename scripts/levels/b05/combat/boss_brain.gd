extends "res://scripts/gameplay/bosses/boss_brain.gd"
## BO05 uses the existing BossBrain public contract, with an independent
## six-action selector and root-well windows. No B01-B04 sequence is changed.
const B05 = preload("res://scripts/levels/b05/combat/enemy_skills.gd")
var root_exposure_ready := 0.0
var destroyed_wells: Array[String] = []
var _root_step := 0
var _root_remaining := 0
var _last_victim: WeakRef

func configure(value: Dictionary, seed_value: int = 0) -> void:
	super.configure(value,seed_value)
	root_exposure_ready=0
	destroyed_wells.clear()
	_root_step=0
	_root_remaining=0
	_last_victim=null

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or delta<=0 or not _alive(actor) or not _alive(victim): return
	elapsed+=delta
	_last_actor=weakref(actor)
	_last_victim=weakref(victim)
	actor.velocity=Vector2.ZERO
	_update_weakpoint(actor,delta)
	var next_phase := _phase_for_ratio(_health_ratio(actor))
	if next_phase>phase:
		phase=next_phase
		_enter_phase(actor)
	state_time=maxf(0,state_time-delta)
	if state in [&"phase_shift",&"emerging"]:
		_set_actor_state(actor,&"recovery" if state==&"phase_shift" else &"emerging")
		if state_time<=0: _begin_action(actor,victim)
	elif state==&"telegraph":
		# Each root is aimed independently and freezes before its own hit.
		var replacement := _build_action(actor,victim,current_action)
		if not replacement.is_empty():
			var preserved: String = str(command.get("cast_id",""))
			command=replacement
			command["cast_id"]=preserved
			if not bool(command.get("b05_admitted",true)): _cancel_admitted_action(actor);return
		actor.aim_direction=command.direction
		_set_actor_state(actor,&"telegraph")
		if state_time<=0:
			state=&"locked"
			state_time=float(command.lock)
			state_duration=state_time
	elif state==&"locked":
		_set_actor_state(actor,&"locked")
		actor.aim_direction=command.direction
		if state_time<=0: _execute(actor)
	elif state==&"recovery":
		_recovery_elapsed+=delta
		_set_actor_state(actor,&"recovery")
		if state_time<=0: _begin_action(actor,victim)
		elif _recovery_elapsed>=2.0: _approach(actor,victim)

func _enter_phase(actor: Node2D) -> void:
	command.clear()
	_released_pose.clear()
	_root_remaining=0
	_root_step=0
	current_action=""
	state=&"phase_shift"
	state_time=1.2
	state_duration=1.2
	if actor.has_method("boss_phase_started"): actor.boss_phase_started(phase,_health_ratio(actor))
	var mechanism: Variant = B05.mechanics(actor)
	if mechanism is Object and mechanism.has_method("boss_phase_changed"): mechanism.boss_phase_changed(phase)

func available_actions(for_phase: int = -1) -> Array:
	var selected_phase: int=phase if for_phase<0 else for_phase
	var result: Array=[]
	for i in range(B05.BOSS_ACTIONS.size()):
		if int(definition.difficulty)>=int(B05.BOSS_GATES[i]) and selected_phase>=int(B05.BOSS_PHASES[i]): result.append(B05.BOSS_ACTIONS[i])
	return result

func _begin_action(actor: Node2D, victim: Node2D, forced_action: String = "") -> void:
	current_action=""
	var candidates := available_actions()
	if not forced_action.is_empty(): candidates=[forced_action] if forced_action in candidates else []
	for offset in range(candidates.size()):
		var action: String = candidates[(action_index+offset)%candidates.size()]
		if elapsed<6.0 and action!="crown_sweep": continue
		if float(_action_ready_at.get(action,0))>elapsed: continue
		if action=="bloom_transplant" and (brood_batches>=2 or _owned_add_count(actor)>=2): continue
		if action=="crown_sweep" and actor.position.distance_to(victim.position)>212: continue
		current_action=action
		break
	if current_action.is_empty():
		state=&"recovery"
		state_time=.25
		state_duration=.25
		_approach(actor,victim)
		return
	action_index+=1
	_root_step=0
	_root_remaining=3 if current_action=="three_roots" else 0
	command=_build_action(actor,victim,current_action)
	command["cast_id"]="BO05:%d:%d" % [actor.get_instance_id(),action_index]
	if not bool(command.get("b05_admitted",true)): _cancel_admitted_action(actor);return
	state=&"telegraph"
	state_time=float(command.tell)
	state_duration=state_time
	_released_pose.clear()
	_set_actor_state(actor,&"telegraph")

func _build_action(actor: Node2D, victim: Node2D, action: String) -> Dictionary:
	var mechanism: Variant = B05.mechanics(actor)
	var roots: Dictionary = mechanism.boss_root_state() if mechanism is Object and mechanism.has_method("boss_root_state") else {}
	var result := B05.boss_action(definition,action,actor.position,victim.position,phase,roots.get("active_positions",[]))
	if result.is_empty(): return result
	# Room host owns fixed safe-route / 30% hazard admission. The host may move
	# an entire warned footprint; it may never move only its eventual damage.
	if mechanism is Object and mechanism.has_method("constrain_boss_command"):
		result["b05_admission_id"]="BO05:%d:%d:%d"%[actor.get_instance_id(),action_index,_root_step]
		result=mechanism.constrain_boss_command(result,actor)
	if action=="three_roots" and _root_step>0:
		result["tell"]=.6-float(result.lock)
		result["telegraph_seconds"]=result.tell
		result["stage"]=_root_step
		result["stage_count"]=3
	return result

func _execute(actor: Node2D) -> void:
	var mechanism: Variant=B05.mechanics(actor)
	if mechanism is Object and mechanism.has_method("can_enemy_cast") and not bool(mechanism.can_enemy_cast(actor,command)):
		_cancel_admitted_action(actor);return
	var released := command.duplicate(true)
	released["b05_phase"]=phase
	actor.state=&"execute"
	actor.cast_enemy_skill(released)
	_released_pose={"direction":released.direction,"kind":released.kind}
	if current_action=="three_roots":
		if _root_step==0: _action_ready_at[current_action]=elapsed+float(released.cooldown)
		_root_remaining-=1
		if _root_remaining>0 and _last_victim!=null and _alive(_last_victim.get_ref()):
			_root_step+=1
			command=_build_action(actor,_last_victim.get_ref(),current_action)
			command["cast_id"]=str(released.cast_id)
			if not bool(command.get("b05_admitted",true)): _cancel_admitted_action(actor);return
			state=&"telegraph"
			state_time=float(command.tell)
			state_duration=state_time
			return
	if current_action=="bloom_transplant": brood_batches+=1
	_last_action=current_action
	_actions_used[current_action]=int(_actions_used.get(current_action,0))+1
	if current_action!="three_roots": _action_ready_at[current_action]=elapsed+float(released.cooldown)
	state=&"recovery"
	# Every multi-part hazard completes before a fresh 2-second approach window.
	var last_delay:=0.0
	for follow: Dictionary in released.get("followups",[]): last_delay=maxf(last_delay,float(follow.get("delay",0)))
	state_time=maxf(float(released.get("recovery",2)),last_delay+2.0) if last_delay>0 or current_action=="three_roots" else float(released.get("recovery",2))
	if current_action=="season_bloom" and mechanism is Object and mechanism.has_method("all_wells_closed") and mechanism.all_wells_closed(): state_time+=5.0
	state_duration=state_time
	_recovery_elapsed=0
	command.clear()
	_set_actor_state(actor,&"recovery")

func apply_arena_counter(counter_id: String, payload: Dictionary = {}) -> bool:
	if stopped or counter_id!="b05_root_well": return false
	var id:=str(payload.get("well_id",""))
	if id.is_empty() or id in destroyed_wells: return false
	destroyed_wells.append(id)
	if elapsed<root_exposure_ready: return true
	root_exposure_ready=elapsed+10.0
	var actor: Node2D=_last_actor.get_ref() if _last_actor!=null else null
	if is_instance_valid(actor): _open_weakpoint(actor,"flower_heart",4.0)
	else:
		weakpoint="flower_heart"
		weakpoint_time=4.0
	return true

func incoming_damage_multiplier() -> float:
	if weakpoint_open(): return 1.15
	var actor: Node2D=_last_actor.get_ref() if _last_actor!=null else null
	if is_instance_valid(actor):
		var mechanism: Variant=B05.mechanics(actor)
		if mechanism is Object and mechanism.has_method("boss_root_state") and int(mechanism.boss_root_state().get("active_count",0))>0: return .65
	return 1.0

func on_damaged(_actor: Node2D, _context: Dictionary) -> void:
	# A legal hit does not shorten the explicitly authored four-second opening.
	pass

func on_displacement_committed(_actor: Node2D, _projected: Vector2) -> void:
	pass

func counter_snapshot() -> Dictionary:
	return {"destroyed_wells":destroyed_wells.duplicate(),"exposure_ready_at":root_exposure_ready,"summon_attempts":brood_batches}

func _approach(actor: Node2D, victim: Node2D) -> void:
	var room_value: Variant=B05.Properties.read(actor,"room")
	if actor.position.distance_to(victim.position)>175 and is_instance_valid(room_value) and room_value.has_method("navigation_direction"):
		actor.velocity=room_value.navigation_direction(actor.position,victim.position,float(definition.navigation_radius))*float(definition.move_speed)
		actor.state=&"chase"

func _cancel_admitted_action(actor: Node2D) -> void:
	var mechanism: Variant=B05.mechanics(actor)
	if mechanism is Object and mechanism.has_method("cancel_enemy_command"): mechanism.cancel_enemy_command(command)
	_action_ready_at[current_action]=maxf(float(_action_ready_at.get(current_action,0)),elapsed+float(command.get("cooldown",0))*.5)
	command.clear();_released_pose.clear();_root_remaining=0
	state=&"recovery";state_time=1.0;state_duration=1.0;_recovery_elapsed=0.0
	_set_actor_state(actor,&"recovery")
