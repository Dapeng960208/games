extends RefCounted
## B05-only FSM. The published frozen command is the command released to the
## common runtime. CD begins on release; interrupted active casts spend half CD.
const RoleBehavior = preload("res://scripts/gameplay/monsters/enemy_role_behavior.gd")
const Skills = preload("res://scripts/levels/b05/combat/enemy_skills.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
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
var _cast_serial:=0
var _admission_key:=""

func configure(value: Dictionary) -> void:
	profile = value.duplicate(true)
	phase = &"emerging"
	age = 0.0
	cycle = 0
	cooldown = 0.0
	_remaining = .8
	_duration = .8
	_command.clear()

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if delta<=0 or not _alive(actor): return
	actor.velocity = Vector2.ZERO
	age += delta
	cooldown = maxf(0,cooldown-delta)
	_remaining = maxf(0,_remaining-delta)
	if not _alive(victim):
		if phase in [&"telegraph",&"locked"]:
			interrupt(actor)
			return
		if actor.has_meta("b05_leaf_guard"): actor.remove_meta("b05_leaf_guard")
		_command.clear()
		_set_phase(&"chase",0)
		_publish(actor)
		return
	if phase in [&"emerging",&"recovery"] and _remaining<=0:
		_command.clear()
		_set_phase(&"chase",0)
	if phase == &"chase":
		var candidate := Skills.active(profile,actor.position,victim.position,Skills.connected(actor),cycle) if cooldown<=0 else Skills.basic(profile,actor.position,victim.position)
		_active = bool(candidate.get("active",false))
		if _active and str(candidate.kind) in ["b05_heal","b05_share"]:
			var refs := _support_refs(actor,candidate)
			if refs.size()<int(candidate.get("target_count",1)):
				candidate = Skills.basic(profile,actor.position,victim.position)
				_active = false
			else: candidate["b05_target_refs"] = refs
		var range_value := float(candidate.get("range",90))
		if str(candidate.kind) in ["ground_area","b05_mode","b05_bud"]: range_value = maxf(range_value,float(profile.attack_range))
		var distance := actor.position.distance_to(victim.position)
		if distance>range_value+12.0 or not _sight(actor,actor.position,victim.position):
			actor.aim_direction = actor.position.direction_to(victim.position)
			actor.velocity = _navigate(actor,victim.position)*float(profile.move_speed)
		else:
			_cast_serial+=1
			_admission_key="b05:%d:%d"%[actor.get_instance_id(),_cast_serial]
			_command = candidate
			_constrain(actor)
			if not bool(_command.get("b05_admitted",true)) or not _can_cast(actor): interrupt(actor);return
			_retarget_support()
			_set_phase(&"telegraph",float(_command.telegraph_seconds))
			if actor.enemy_id == "B05-M06" and int(profile.difficulty)>=4:
				actor.set_meta("b05_leaf_guard",true)
	elif phase == &"telegraph":
		# The tracking pass rebuilds exactly the displayed shape from one source;
		# support recipients remain stable and cannot change at release.
		var refs: Array = _command.get("b05_target_refs",[])
		_command = Skills.active(profile,actor.position,victim.position,Skills.connected(actor),cycle) if _active else Skills.basic(profile,actor.position,victim.position)
		if not refs.is_empty(): _command["b05_target_refs"] = refs
		_constrain(actor)
		if not bool(_command.get("b05_admitted",true)) or not _can_cast(actor): interrupt(actor);return
		_retarget_support()
		actor.aim_direction = _command.direction
		if _remaining<=0:
			_locked_position = actor.position
			_freeze(actor)
			_constrain(actor,false)
			if not bool(_command.get("b05_admitted",true)) or not _can_cast(actor): interrupt(actor);return
			_set_phase(&"locked",float(_command.locked_seconds))
	elif phase == &"locked":
		actor.aim_direction = _command.direction
		if str(_command.kind) in ["melee","charge"] and actor.position.distance_to(_locked_position)>30:
			interrupt(actor)
		elif _remaining<=0:
			if (bool(_command.get("root_required",false)) and not Skills.connected(actor)) or not _can_cast(actor):
				interrupt(actor)
			else:
				if actor.has_meta("b05_leaf_guard"): actor.remove_meta("b05_leaf_guard")
				actor.state = &"execute"
				actor.cast_enemy_skill(_command.duplicate(true))
				if _active:
					cooldown = float(_command.cooldown)
					cycle += 1
				_set_phase(&"execute",maxf(.22,float(_command.get("duration",0)) if str(_command.kind)=="charge" else .22))
	elif phase == &"execute" and _remaining<=0 and not actor.has_meta("enemy_skill_motion"):
		_set_phase(&"recovery",maxf(1.0 if actor.enemy_id=="B05-M03" and int(profile.difficulty)>=4 else .45,RoleBehavior.recovery_seconds(profile,float(_command.get("recovery",1.15)))))
	_publish(actor)

func _freeze(actor: Node2D) -> void:
	var room: Variant = Props.read(actor,"room")
	if str(_command.kind)=="charge" and is_instance_valid(room) and room.has_method("blocked_fraction"):
		var endpoint: Vector2 = _command.target
		var fraction: float = room.blocked_fraction(actor.position,endpoint,float(profile.get("navigation_radius",18)))
		var impact: Vector2 = actor.position.lerp(endpoint,clampf(fraction,0,1))
		if actor.enemy_id=="B05-M09" and int(profile.difficulty)>=2 and fraction<1:
			var rebound: Vector2 = impact-Vector2(_command.direction)*110
			_command["rebound_point"] = rebound
			_command["paths"] = [[actor.position,impact],[impact,rebound]]
		else: _command["paths"] = [[actor.position,impact]]
	# Target locations and follow-up locations are now immutable.
	_command["cast_id"] = "%s:%d:%d" % [profile.enemy_id,actor.get_instance_id(),cycle]

func _support_refs(actor: Node2D, command: Dictionary) -> Array:
	var runtime: Variant = Props.read(Props.read(actor,"room"),"enemy_skills")
	var extension: Variant = Props.read(runtime,"b05")
	return extension.support_targets(actor,command) if extension is Object else []

func _retarget_support() -> void:
	var refs: Array = _command.get("b05_target_refs",[])
	if refs.is_empty(): return
	var points: Array = []
	for ref: WeakRef in refs:
		var ally: Node2D = ref.get_ref()
		if _alive(ally): points.append(ally.position)
	if points.is_empty(): return
	_command.target = points[0]
	_command.direction = Vector2(_command.origin).direction_to(points[0])
	_command.points = [_command.origin,points[0]]
	_command.paths = []
	for point: Vector2 in points: _command.paths.append([_command.origin,point])

func on_damaged(actor: Node2D, context: Dictionary = {}) -> void:
	if phase in [&"telegraph",&"locked"] and bool(_command.get("interruptible",false)) and bool(context.get("interrupt",true)) and str(context.get("kind","primary")) not in ["burn","corrosion","bleed","b05_share"]:
		interrupt(actor)

func on_displacement_committed(actor: Node2D, projected: Vector2) -> void:
	if phase in [&"locked",&"execute"] and str(_command.get("kind","")) in ["melee","charge"] and projected.distance_to(_locked_position)>30: interrupt(actor)

func interrupt(actor: Node2D) -> void:
	var mechanism: Variant=Skills.mechanics(actor)
	if mechanism is Object and mechanism.has_method("cancel_enemy_command"): mechanism.cancel_enemy_command(_command)
	if _active: cooldown = maxf(cooldown,float(_command.get("cooldown",0))*.5)
	if actor.has_meta("b05_leaf_guard"): actor.remove_meta("b05_leaf_guard")
	_command.clear()
	_set_phase(&"recovery",maxf(1.0,float(profile.recovery_seconds)))
	_publish(actor)

func current_skill() -> Dictionary:
	if _command.is_empty() or phase not in [&"telegraph",&"locked",&"execute",&"recovery"]: return {}
	var result := _command.duplicate(true)
	result.merge({"phase":str(phase),"locked":phase==&"locked","remaining":_remaining,"progress":clampf(1-_remaining/maxf(.001,_duration),0,1)},true)
	return result

func current_telegraph() -> Dictionary:
	return current_skill() if phase in [&"telegraph",&"locked"] else {}

func _set_phase(value: StringName, duration: float) -> void:
	phase = value
	_remaining = RoleBehavior.action_seconds(profile,duration) if value == &"execute" else duration
	_duration = _remaining

func _publish(actor: Node2D) -> void:
	actor.state = phase
	actor.state_time = _remaining

func _alive(actor: Node2D) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and (not actor.has_method("is_alive") or bool(actor.call("is_alive")))

func _sight(actor: Node2D, start: Vector2, end: Vector2) -> bool:
	var room: Variant = Props.read(actor,"room")
	return not is_instance_valid(room) or not room.has_method("has_line_of_sight") or room.has_line_of_sight(start,end)

func _navigate(actor: Node2D, target: Vector2) -> Vector2:
	var room: Variant = Props.read(actor,"room")
	return room.navigation_direction(actor.position,target,float(profile.get("navigation_radius",18))) if is_instance_valid(room) and room.has_method("navigation_direction") else actor.position.direction_to(target)

func _constrain(actor: Node2D,allow_reposition: bool=true) -> void:
	var mechanism: Variant=Skills.mechanics(actor)
	if mechanism is Object and mechanism.has_method("constrain_enemy_command"):
		_command["b05_admission_id"]=_admission_key
		_command=mechanism.constrain_enemy_command(_command,actor,allow_reposition)

func _can_cast(actor: Node2D) -> bool:
	var mechanism: Variant=Skills.mechanics(actor)
	return not mechanism is Object or not mechanism.has_method("can_enemy_cast") or bool(mechanism.can_enemy_cast(actor,_command))
