extends RefCounted
## Chapter-specific warning/lock/execute FSM. Fallback species only basic-hit;
## camouflage never suppresses a hitbox, legal targeting or hazard warnings.
const Skills = preload("res://scripts/combat/b07_enemy_skills.gd")
const Props = preload("res://scripts/combat/combat_properties.gd")
const RoleBehavior = preload("res://scripts/combat/enemy_role_behavior.gd")
var profile: Dictionary = {}
var phase: StringName = &"emerging"
var age := 0.0
var cycle := 0
var cooldown := 0.0
var _remaining := .8
var _duration := .8
var _command: Dictionary = {}
var _locked_position := Vector2.ZERO
var _active := false
var _cast_serial := 0

func configure(value: Dictionary) -> void:
	profile=value.duplicate(true)
	phase=&"emerging"
	age=0.0
	cycle=0
	cooldown=0.0
	_remaining=.8
	_duration=.8
	_command.clear()
	_locked_position=Vector2.ZERO
	_active=false
	_cast_serial=0

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if not is_finite(delta) or delta<=0 or not _alive(actor): return
	actor.velocity=Vector2.ZERO
	age+=delta
	cooldown=maxf(0,cooldown-delta)
	_remaining=maxf(0,_remaining-delta)
	if not _alive(victim):
		if phase in [&"telegraph",&"locked"]: interrupt(actor)
		_set_camouflage(actor,false)
		_command.clear()
		_set_phase(&"chase",0)
		_publish(actor)
		return
	if phase in [&"emerging",&"recovery"] and _remaining<=0:
		_command.clear()
		_set_phase(&"chase",0)
	match phase:
		&"chase":
			var candidate: Dictionary=_candidate(actor,victim,cooldown<=0)
			_active=bool(candidate.get("active",false))
			_set_camouflage(actor,_active and str(profile.enemy_id)=="B07-M02")
			if str(candidate.kind)!="b07_heal" and (actor.position.distance_to(victim.position)>float(candidate.get("range",90))+12 or not _sight(actor,victim.position)):
				actor.aim_direction=actor.position.direction_to(victim.position)
				actor.velocity=_navigate(actor,victim.position)*float(profile.move_speed)
			else:
				_command=candidate
				_set_phase(&"telegraph",float(_command.tell))
		&"telegraph":
			# Only the tracking tell may update geometry. Lock and followups use
			# this frozen command; a moved mirror may cancel but never re-aim it.
			if str(_command.get("kind",""))=="b07_heal":
				if not Skills.Support.valid(actor,_command): interrupt(actor); return
				_command=Skills.Support.link(actor,_command)
			else: _command=_candidate(actor,victim,_active)
			actor.aim_direction=_command.direction
			if _remaining<=0:
				_locked_position=actor.position
				_cast_serial+=1
				_command["cast_id"]="%s:%d:%d" % [profile.enemy_id,actor.get_instance_id(),_cast_serial]
				_set_phase(&"locked",float(_command.lock))
		&"locked":
			if str(_command.kind)=="b07_heal" and not Skills.Support.valid(actor,_command): interrupt(actor); return
			actor.aim_direction=_command.direction
			if str(_command.kind) in ["melee","charge","b07_shield","b07_heal"] and actor.position.distance_to(_locked_position)>30:
				interrupt(actor)
			elif _remaining<=0:
				_set_camouflage(actor,false)
				actor.state=&"execute"
				actor.cast_enemy_skill(_command.duplicate(true))
				if _active:
					cooldown=float(_command.cooldown)
					cycle+=1
				var hold: float=float(_command.get("duration",.22)) if str(_command.kind) in ["charge","b07_shield"] else .22
				_set_phase(&"execute",maxf(.22,hold))
		&"execute":
			if _remaining<=0 and not actor.has_meta("enemy_skill_motion"):
				_set_phase(&"recovery",RoleBehavior.recovery_seconds(profile,float(_command.get("recovery",1.15)),float(_command.get("recovery_floor",1.2 if str(profile.enemy_id)=="B07-M02" else .45))))
	_publish(actor)

func _candidate(actor: Node2D, victim: Node2D, use_active: bool) -> Dictionary:
	var command: Dictionary=Skills.active(profile,actor.position,victim.position,Skills.lit(actor),cycle) if use_active else Skills.basic(profile,actor.position,victim.position)
	command=Skills.constrain(actor,command)
	if str(command.kind)=="b07_heal" and command.get("b07_target_refs",[]).is_empty(): return Skills.basic(profile,actor.position,victim.position)
	return command

func on_damaged(actor: Node2D, context: Dictionary = {}) -> void:
	var mechanism: Variant=Skills.mechanics(actor)
	if mechanism is Object and mechanism.has_method("reveal_actor"): mechanism.reveal_actor(actor,3.0)
	if phase in [&"telegraph",&"locked"] and bool(_command.get("interruptible",false)) and bool(context.get("interrupt",true)) and (float(context.get("damage",0))>0 or float(context.get("shield_damage",0))>0):
		interrupt(actor)

func on_displacement_committed(actor: Node2D, projected: Vector2) -> void:
	if str(_command.get("kind",""))=="b07_heal" and phase in [&"telegraph",&"locked"]:
		interrupt(actor)
	elif phase in [&"locked",&"execute"] and str(_command.get("kind","")) in ["melee","charge","b07_shield"] and projected.distance_to(_locked_position)>30:
		interrupt(actor)

func interrupt(actor: Node2D) -> void:
	if _active: cooldown=maxf(cooldown,float(_command.get("cooldown",0))*.5)
	_set_camouflage(actor,false)
	_command.clear()
	_set_phase(&"recovery",maxf(.9,float(profile.get("recovery_seconds",1.15))))
	_publish(actor)

func reduce_cooldown(seconds: float) -> bool:
	if not is_finite(seconds) or seconds<=0 or cooldown<=.1: return false
	cooldown=maxf(.1,cooldown-seconds)
	return true

func extend_cooldown(seconds: float) -> void:
	if is_finite(seconds) and seconds>0: cooldown+=seconds

func current_skill() -> Dictionary:
	if _command.is_empty() or phase not in [&"telegraph",&"locked",&"execute",&"recovery"]: return {}
	var result := _command.duplicate(true)
	result.merge({"phase":str(phase),"locked":phase==&"locked","remaining":_remaining,"progress":clampf(1-_remaining/maxf(.001,_duration),0,1)},true)
	return result

func current_telegraph() -> Dictionary:
	return current_skill() if phase in [&"telegraph",&"locked"] else {}

func _set_phase(value: StringName, duration: float) -> void:
	phase=value
	_remaining=RoleBehavior.action_seconds(profile,duration) if value==&"execute" else duration
	_duration=_remaining

func _set_camouflage(actor: Node2D, active: bool) -> void:
	actor.set_meta("b07_camouflaged",active)

func _publish(actor: Node2D) -> void:
	actor.state=phase
	actor.state_time=_remaining

func _alive(actor: Node2D) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and (not actor.has_method("is_alive") or bool(actor.call("is_alive")))

func _sight(actor: Node2D, destination: Vector2) -> bool:
	var room: Variant=Props.read(actor,"room")
	return not is_instance_valid(room) or not room.has_method("has_line_of_sight") or bool(room.has_line_of_sight(actor.position,destination))

func _navigate(actor: Node2D, destination: Vector2) -> Vector2:
	var room: Variant=Props.read(actor,"room")
	return room.navigation_direction(actor.position,destination,float(profile.get("navigation_radius",18))) if is_instance_valid(room) and room.has_method("navigation_direction") else actor.position.direction_to(destination)
