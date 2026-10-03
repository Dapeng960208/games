extends "res://scripts/combat/boss_brain.gd"
## Sunwheel King first-playable sequence. Altar state remains room-owned;
## phase changes do not reset mirror progress or manufacture invulnerability.
const B07 = preload("res://scripts/combat/b07_enemy_skills.gd")
const Props = preload("res://scripts/combat/combat_properties.gd")

func configure(value: Dictionary, seed_value: int = 0) -> void:
	super.configure(value,seed_value)

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or not is_finite(delta) or delta<=0 or not _alive(actor): return
	actor.velocity=Vector2.ZERO
	if not _alive(victim):
		command.clear()
		state=&"recovery"
		state_time=.2
		_set_actor_state(actor,&"recovery")
		return
	elapsed+=delta
	_last_actor=weakref(actor)
	var next_phase := _phase_for_ratio(_health_ratio(actor))
	if next_phase>phase:
		phase=next_phase
		_enter_phase(actor)
	state_time=maxf(0,state_time-delta)
	match state:
		&"emerging", &"phase_shift":
			_set_actor_state(actor,&"recovery" if state==&"phase_shift" else &"emerging")
			if state_time<=0: _begin_action(actor,victim)
		&"telegraph":
			# Full geometry, including mirror identity and disc return path,
			# freezes when the tell starts. No post-lock targeting update.
			actor.aim_direction=command.direction
			_set_actor_state(actor,&"telegraph")
			if state_time<=0:
				state=&"locked"
				state_time=float(command.lock)
				state_duration=state_time
		&"locked":
			actor.aim_direction=command.direction
			_set_actor_state(actor,&"locked")
			if state_time<=0: _execute(actor)
		&"recovery":
			_recovery_elapsed+=delta
			_set_actor_state(actor,&"recovery")
			if current_action.is_empty(): _approach(actor,victim)
			if state_time<=0: _begin_action(actor,victim)

func _enter_phase(actor: Node2D) -> void:
	command.clear()
	_released_pose.clear()
	current_action=""
	state=&"phase_shift"
	state_time=.8
	state_duration=.8
	if actor.has_method("boss_phase_started"): actor.boss_phase_started(phase,_health_ratio(actor))
	var mechanism: Variant=B07.mechanics(actor)
	if mechanism is Object and mechanism.has_method("boss_phase_changed"): mechanism.boss_phase_changed(phase)

func available_actions(for_phase: int = -1) -> Array:
	var selected: int=phase if for_phase<0 else for_phase
	var result: Array=[]
	for i in B07.BOSS_ACTIONS.size():
		if int(definition.difficulty)<int(B07.BOSS_GATES[i]): continue
		if B07.BOSS_ACTIONS[i]=="altar_lines" and selected<2: continue
		result.append(B07.BOSS_ACTIONS[i])
	return result

func _begin_action(actor: Node2D, victim: Node2D, forced_action: String = "") -> void:
	var candidates := available_actions()
	if not forced_action.is_empty(): candidates=[forced_action] if forced_action in candidates else []
	current_action=""
	command.clear()
	var distance: float=actor.position.distance_to(victim.position)
	for offset in candidates.size():
		var action: String=candidates[(action_index+offset)%candidates.size()]
		if float(_action_ready_at.get(action,0))>elapsed: continue
		if forced_action.is_empty():
			if action=="sun_spear" and distance>252: continue
			if action=="sun_disc" and distance>372: continue
			if action=="golden_tail" and (distance>182 or Vector2(actor.aim_direction).dot(actor.position.direction_to(victim.position))>=0): continue
		var candidate := _build_action(actor,victim,action)
		if candidate.is_empty(): continue
		current_action=action
		command=candidate
		break
	if command.is_empty():
		state=&"recovery"
		state_time=.15
		state_duration=.15
		# Movement is a visible approach only, with normal collision. No
		# D4 three-stop teleport is claimed by this first-playable slice.
		_approach(actor,victim)
		return
	action_index+=1
	command["cast_id"]="BO07:%d:%d" % [actor.get_instance_id(),action_index]
	state=&"telegraph"
	state_time=float(command.tell)
	state_duration=state_time
	_released_pose.clear()
	_set_actor_state(actor,&"telegraph")

func _approach(actor: Node2D, victim: Node2D) -> void:
	if actor.position.distance_to(victim.position)<=170: return
	var room: Variant=Props.read(actor,"room")
	var direction: Vector2=room.navigation_direction(actor.position,victim.position,float(definition.navigation_radius)) if room is Object and room.has_method("navigation_direction") else actor.position.direction_to(victim.position)
	actor.velocity=direction*float(definition.move_speed)
	actor.aim_direction=direction
	actor.state=&"chase"

func _build_action(actor: Node2D, victim: Node2D, action: String) -> Dictionary:
	var target: Vector2=victim.position
	if action=="golden_tail": target=actor.position+Vector2(actor.aim_direction)*120
	var result := B07.boss_action(definition,action,actor.position,target,phase)
	if result.is_empty(): return {}
	if action=="altar_lines":
		var mechanism: Variant=B07.mechanics(actor)
		if not mechanism is Object or not mechanism.has_method("enemy_attack_lines"): return {}
		var lines: Array=mechanism.enemy_attack_lines(actor,2)
		if lines.is_empty(): return {}
		result["paths"]=[]
		result["mirror_lines"]=[]
		for value: Dictionary in lines.slice(0,2):
			var line := value.duplicate(true)
			line["points"]=[line.origin,line.target]
			line["direction"]=Vector2(line.origin).direction_to(line.target)
			line["range"]=Vector2(line.origin).distance_to(line.target)
			result.mirror_lines.append(line)
			result.paths.append([line.origin,line.target])
		result.origin=lines[0].origin
		result.target=lines[0].target
		result.points=[result.origin,result.target]
		result.direction=Vector2(result.origin).direction_to(result.target)
		result.range=Vector2(result.origin).distance_to(result.target)
	return B07.constrain(actor,result)

func _execute(actor: Node2D) -> void:
	var released := command.duplicate(true)
	actor.state=&"execute"
	actor.cast_enemy_skill(released)
	_action_ready_at[current_action]=elapsed+float(released.cooldown)
	_actions_used[current_action]=int(_actions_used.get(current_action,0))+1
	_last_action=current_action
	_released_pose={"direction":released.direction,"kind":released.kind}
	state=&"recovery"
	state_time=float(released.get("recovery",1.3))
	state_duration=state_time
	_recovery_elapsed=0.0
	command.clear()
	_set_actor_state(actor,&"recovery")

# Room.filter_damage owns both altar reduction and the exposed-back multiplier.
func incoming_damage_multiplier() -> float: return 1.0
func outgoing_damage_multiplier() -> float: return 1.0
func on_damaged(_actor: Node2D, _context: Dictionary) -> void: pass
func apply_arena_counter(_counter_id: String, _payload: Dictionary = {}) -> bool: return false
