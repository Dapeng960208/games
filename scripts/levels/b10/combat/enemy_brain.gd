extends RefCounted
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
var profile: Dictionary = {}
var phase: StringName = &"emerging"
var cooldown := 0.0
var remaining := .8
var duration := .8
var cycle := 0
var serial := 0
var command: Dictionary = {}
var active := false
var locked_origin := Vector2.ZERO

func configure(value: Dictionary) -> void:
	profile=value.duplicate(true)
	phase=&"emerging"
	cooldown=0
	remaining=.8
	duration=.8
	cycle=0
	serial=0
	command.clear()

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if delta<=0 or not _alive(actor): return
	actor.velocity=Vector2.ZERO
	cooldown=maxf(0,cooldown-delta)
	remaining=maxf(0,remaining-delta)
	var extension: Variant=Skills.runtime(actor)
	if extension is Object:
		var held: float=extension.recovery_remaining(actor)
		if held>0:
			hold_recovery(actor,held)
			return
	if not _alive(victim):
		if phase in [&"telegraph",&"locked"]: interrupt(actor)
		return
	if phase in [&"emerging",&"recovery"] and remaining<=0:
		command.clear()
		_transition(&"chase",0)
	if phase==&"chase":
		var candidate := Skills.active(profile,actor.position,victim.position,Skills.connected(actor),cycle) if cooldown<=0 else Skills.basic(profile,actor.position,victim.position)
		active=bool(candidate.get("active",false))
		if active and str(candidate.kind) in ["b10_transfer","b10_harmonize","b10_repair"]:
			var refs: Array=extension.support_targets(actor,candidate) if extension is Object else []
			if refs.is_empty():
				candidate=Skills.basic(profile,actor.position,victim.position)
				active=false
			else:
				candidate["b10_target_refs"]=refs
				candidate.target=refs[0].get_ref().position
		var range_value := float(candidate.range)
		if str(candidate.kind) in ["ground_area","b10_harmonize","b10_transfer","b10_repair"]: range_value=float(profile.attack_range)
		if actor.position.distance_to(victim.position)>range_value+12 or not actor.room.has_line_of_sight(actor.position,victim.position):
			actor.aim_direction=actor.position.direction_to(victim.position)
			actor.velocity=actor.room.navigation_direction(actor.position,victim.position,float(profile.navigation_radius))*float(profile.move_speed)
		elif not extension is Object or extension.can_lock(actor):
			command=candidate
			if extension is Object: command=extension.constrain(actor,command)
			_transition(&"telegraph",float(command.telegraph_seconds))
	elif phase==&"telegraph":
		# The first published warning fixes location and recipient, so portals
		# and moving targets cannot drag a late hit onto another landing pad.
		actor.aim_direction=command.direction
		if remaining<=0:
			locked_origin=actor.position
			serial+=1
			command["cast_id"]="%s:%d:%d"%[profile.enemy_id,actor.get_instance_id(),serial]
			_transition(&"locked",float(command.locked_seconds))
	elif phase==&"locked":
		actor.aim_direction=command.direction
		if str(command.kind) in ["melee","charge"] and actor.position.distance_to(locked_origin)>30:
			interrupt(actor)
		elif remaining<=0:
			actor.state=&"execute"
			actor.cast_enemy_skill(command.duplicate(true))
			if active:
				cooldown=float(command.cooldown)
				cycle+=1
			_transition(&"execute",maxf(.22,float(command.get("duration",0)) if str(command.kind)=="charge" else .22))
	elif phase==&"execute" and remaining<=0 and not actor.has_meta("enemy_skill_motion"):
		_transition(&"recovery",float(command.get("recovery",1.15)))
	actor.state=phase
	actor.state_time=remaining

func on_damaged(actor: Node2D, context: Dictionary = {}) -> void:
	if phase in [&"telegraph",&"locked"] and bool(command.get("interruptible",false)) and bool(context.get("interrupt",true)) and str(context.get("kind","primary")) not in ["burn","corrosion","bleed"]:
		interrupt(actor)

func on_displacement_committed(actor: Node2D, projected: Vector2) -> void:
	if phase in [&"locked",&"execute"] and str(command.get("kind","")) in ["melee","charge"] and projected.distance_to(locked_origin)>30: interrupt(actor)

func interrupt(actor: Node2D) -> void:
	if str(command.get("kind",""))=="b10_transfer" and int(profile.difficulty)>=4:
		for reference: WeakRef in command.get("b10_target_refs",[]):
			var recipient: Node2D=reference.get_ref()
			if _alive(recipient) and recipient.brain!=null and recipient.brain.has_method("hold_recovery"):
				recipient.brain.hold_recovery(recipient,1.0)
	var extension: Variant=Skills.runtime(actor)
	if extension is Object: extension.interrupted(actor)
	if active: cooldown=maxf(cooldown,float(command.get("cooldown",0))*.5)
	hold_recovery(actor,1.0)

func hold_recovery(actor: Node2D, seconds: float) -> void:
	command.clear()
	_transition(&"recovery",maxf(remaining if phase==&"recovery" else 0.0,seconds))
	actor.state=phase
	actor.state_time=remaining

func current_skill() -> Dictionary:
	if command.is_empty() or phase not in [&"telegraph",&"locked",&"execute",&"recovery"]: return {}
	var result := command.duplicate(true)
	result.merge({"phase":str(phase),"locked":phase==&"locked","remaining":remaining,"progress":clampf(1-remaining/maxf(.001,duration),0,1)},true)
	return result

func current_telegraph() -> Dictionary:
	return current_skill() if phase in [&"telegraph",&"locked"] else {}

func _transition(value: StringName, seconds: float) -> void:
	phase=value
	remaining=seconds
	duration=seconds

func _alive(actor: Node2D) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and (not actor.has_method("is_alive") or actor.is_alive())
