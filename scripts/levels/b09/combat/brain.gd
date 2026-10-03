extends "res://scripts/gameplay/bosses/boss_brain.gd"
## One frozen warning/command drives both B09 ordinary and queen execution.
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
var _active := false
var _ordinary_ready := 0.0
var _serial := 0

func configure(value: Dictionary, seed_value: int = 0) -> void:
	super.configure(value,seed_value)
	_active=false
	_ordinary_ready=0.0
	_serial=0

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or not is_finite(delta) or delta<=0 or not _alive(actor): return
	actor.velocity=Vector2.ZERO
	elapsed+=delta
	_last_actor=weakref(actor)
	if not _alive(victim):
		command.clear()
		state=&"recovery"
		return
	if definition.rank=="boss":
		var next := _phase_for_ratio(_health_ratio(actor))
		if next>phase:
			phase=next
			actor.boss_phase_started(phase,_health_ratio(actor))
			command.clear()
			state=&"phase_shift"
			state_time=0.8
	state_time=maxf(0,state_time-delta)
	match state:
		&"emerging", &"phase_shift", &"recovery", &"chase":
			if state_time<=0: _begin_action(actor,victim)
		&"telegraph":
			actor.aim_direction=command.direction
			if state_time<=0:
				state=&"locked"
				state_time=float(command.lock)
				state_duration=state_time
		&"locked":
			actor.aim_direction=command.direction
			if state_time<=0:
				actor.state=&"execute"
				actor.cast_enemy_skill(command.duplicate(true))
				if definition.rank=="boss":
					_action_ready_at[current_action]=elapsed+float(command.cooldown)
					if current_action=="crown_guards": brood_batches+=1
				elif _active: _ordinary_ready=elapsed+float(command.cooldown)
				_released_pose=command.duplicate(true)
				state=&"execute"
				state_time=maxf(0.3,float(command.get("duration",0)) if command.kind=="charge" else 0.3)
				for next: Dictionary in command.get("followups",[]): state_time=maxf(state_time,float(command.get("delay",0))+float(next.get("delay",0))+(float(next.get("duration",0)) if next.kind=="charge" else 0.0)+0.05)
				state_duration=state_time
		&"execute":
			if state_time<=0 and not actor.has_meta("enemy_skill_motion"):
				state=&"recovery"
				state_time=float(command.get("recovery",1.15))+_exposure_recovery(actor)
				state_duration=state_time
	actor.state=state
	actor.state_time=state_time

func _begin_action(actor: Node2D, victim: Node2D, forced_action: String = "") -> void:
	var c: Dictionary = {}
	if definition.rank=="boss":
		var choices := available_actions()
		if not forced_action.is_empty(): choices=[forced_action] if forced_action in choices else []
		for offset in choices.size():
			var key: String = choices[(action_index+offset)%choices.size()]
			if float(_action_ready_at.get(key,0))>elapsed: continue
			if key=="reform" and int(actor.get_meta("b09_layers",0))>=3: continue
			if key=="crown_guards" and (brood_batches>=2 or _owned_add_count(actor)>=2): continue
			if key=="court_arc" and actor.position.distance_to(victim.position)>210: continue
			current_action=key
			c=Skills.boss_action(definition,key,actor.position,victim.position,phase)
			break
	else:
		_active=elapsed>=_ordinary_ready
		c=Skills.active(definition,actor.position,victim.position) if _active else Skills.basic(definition,actor.position,victim.position)
		if c.kind=="b09_reform_allies" and actor.room.b09_mechanics.allies(actor).is_empty():
			c=Skills.basic(definition,actor.position,victim.position)
			_active=false
	if c.is_empty() or actor.position.distance_to(victim.position)>float(c.get("range",90))+12:
		state=&"chase"
		state_time=0.0
		actor.aim_direction=actor.position.direction_to(victim.position)
		actor.velocity=actor.room.navigation_direction(actor.position,victim.position,float(definition.navigation_radius))*float(definition.move_speed)
		return
	if not actor.room.has_line_of_sight(actor.position,victim.position) and str(c.kind) not in ["b09_bridge","b09_reform","b09_reform_allies"]:
		state=&"chase"
		state_time=0.0
		actor.velocity=actor.room.navigation_direction(actor.position,victim.position,float(definition.navigation_radius))*float(definition.move_speed)
		return
	c=actor.room.b09_mechanics.constrain(c,actor)
	if c.is_empty():
		state=&"recovery"
		state_time=0.2
		return
	if actor.enemy_id=="B09-M16" and c.has("refraction_points"):
		var anchor: Node2D=actor.room.spawn_enemy_skill_anchor(actor,c.refraction_points[0],actor.health.maximum*0.15,"crystal_column")
		if not is_instance_valid(anchor):
			state=&"recovery"
			state_time=0.5
			return
		c["b09_refraction_anchor"]=weakref(anchor)
		actor.room.b09_mechanics.walls.append({"rect":Rect2(),"actor":weakref(anchor),"until":actor.room.b09_mechanics.clock+6.0})
	action_index+=1
	_serial+=1
	c["cast_id"]="%s:%d:%d" % [definition.enemy_id,actor.get_instance_id(),_serial]
	command=Skills.freeze(c,definition)
	state=&"telegraph"
	state_time=float(c.tell)
	state_duration=state_time

func available_actions(for_phase: int = -1) -> Array:
	var selected := phase if for_phase<0 else for_phase
	var result: Array=[]
	for i in Skills.BOSS_ACTIONS.size():
		if int(definition.difficulty)<Skills.BOSS_GATES[i]: continue
		if i in [3,4] and selected<2: continue
		if i==5 and selected<3: continue
		result.append(Skills.BOSS_ACTIONS[i])
	return result

func _exposure_recovery(actor: Node2D) -> float:
	if int(definition.difficulty)<4: return 0.0
	if definition.enemy_id=="B09-M01" and actor.room.b09_mechanics.clock<float(actor.get_meta("b09_exposed_until",0.0)): return 1.0
	return 0.5 if definition.enemy_id=="B09-M17" and actor.room.b09_mechanics.warm_at(actor.position) else 0.0

func on_damaged(actor: Node2D, context: Dictionary) -> void:
	if state not in [&"telegraph",&"locked"] or not bool(command.get("interruptible",false)) or bool(context.get("dot",false)): return
	interrupt(actor)

func interrupt(actor: Node2D) -> void:
	if definition.enemy_id=="B09-M06" and int(definition.difficulty)>=4:
		actor.room.b09_mechanics.snow.append({"at":actor.position,"radius":60.0,"until":actor.room.b09_mechanics.clock+4.0})
	if _active: _ordinary_ready=maxf(_ordinary_ready,elapsed+float(command.get("cooldown",0))*0.5)
	if definition.rank=="boss": _action_ready_at[current_action]=elapsed+float(command.get("cooldown",0))*0.5
	command.clear()
	state=&"recovery"
	state_time=1.0
	state_duration=1.0
	actor.state=state
	if is_instance_valid(actor.room.enemy_skills): actor.room.enemy_skills.cancel_owner(actor)

func on_displacement_committed(actor: Node2D, projected: Vector2) -> void:
	if state==&"locked" and command.get("kind") in ["melee","charge"] and projected.distance_to(Vector2(command.origin))>30: interrupt(actor)

func current_skill() -> Dictionary:
	if command.is_empty() or state not in [&"telegraph",&"locked",&"execute",&"recovery"]: return {}
	var result := command.duplicate(true)
	result.merge({"phase":str(state),"locked":state==&"locked","remaining":state_time,"progress":clampf(1-state_time/maxf(0.001,state_duration),0,1)},true)
	return result

func current_telegraph() -> Dictionary:
	return current_skill() if state in [&"telegraph",&"locked"] else {}

func incoming_damage_multiplier() -> float: return 1.0
func outgoing_damage_multiplier() -> float: return 1.0
func apply_arena_counter(_counter_id: String, _payload: Dictionary = {}) -> bool: return false
