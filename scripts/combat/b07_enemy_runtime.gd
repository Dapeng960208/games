extends RefCounted
## B07 adapter only; common runtime owns actual hit collision, damage/status,
## projectiles, bounded effects and safe actor movement. Puzzle light is harmless.
const Skills = preload("res://scripts/combat/b07_enemy_skills.gd")
const Props = preload("res://scripts/combat/combat_properties.gd")
var host: Node2D
var effects: Array[Dictionary] = []
var hit_receipts: Dictionary = {}
var clock := 0.0
var serial := 0

func configure(runtime: Node2D) -> void:
	host=runtime

func prepare(caster: Node2D, command: Dictionary) -> Dictionary:
	var result := Skills.freeze_damage(command,Props.read(caster,"profile",{}))
	if result.is_empty(): return {}
	result["owner"]=weakref(caster)
	result["owner_id"]=caster.get_instance_id()
	if not result.has("cast_id"):
		serial+=1
		result["cast_id"]="b07:%d:%d" % [caster.get_instance_id(),serial]
	var profile: Dictionary=Props.read(caster,"profile",{})
	if preload("res://scripts/combat/crit_policy.gd").enabled(profile):
		var event_id: String=str(result.get("crit_event_id",str(profile.get("enemy_id",""))+":"+str(result.cast_id).get_slice(":",2)))
		result=preload("res://scripts/combat/crit_policy.gd").freeze(result,profile,int(Props.read(host.room,"run_seed",0)),event_id)
	return result

func admitted(command: Dictionary, _hit: bool = false) -> bool:
	var caster: Node2D=host._owner(command)
	if not host._alive(caster) or bool(command.get("admission_deferred",false)): return false
	if bool(command.get("body_bound",false)) and caster.position.distance_to(Vector2(command.origin))>30: return false
	if bool(command.get("b07_reposition_motion",false)) and caster.has_method("has_pending_displacement") and caster.has_pending_displacement(): return false
	var mechanism: Variant=Skills.mechanics(caster)
	if command.has("mirror_id"):
		if not mechanism is Object or not mechanism.has_method("enemy_line_valid") or not bool(mechanism.enemy_line_valid(command)): return false
	if bool(command.get("persistent_clearance",false)):
		if not mechanism is Object or not mechanism.has_method("admit_persistent_area") or not bool(mechanism.admit_persistent_area(command.target,float(command.radius))): return false
	return true

func execute(command: Dictionary) -> bool:
	var caster: Node2D=host._owner(command)
	match str(command.kind):
		"b07_heal":
			var receipt := "heal:"+str(command.cast_id)
			if hit_receipts.has(receipt): return true
			hit_receipts[receipt]=clock+30.0
			Skills.Support.execute(host,caster,command)
			return true
		"b07_reposition":
			caster.position=host.room.move_actor(caster.position,Vector2(command.displacement),float(Props.read(caster,"navigation_radius",18)))
			return true
		"b07_shield":
			cancel_shield(caster)
			caster.set_meta("b07_shield_active",true)
			caster.set_meta("b07_shield_direction",Vector2(command.direction))
			var effect := command.duplicate(true)
			effect.merge({"remaining":2.0,"was_lit":Skills.lit(caster),"penalty_applied":false},true)
			effects.append(effect)
			return true
		"b07_vortex":
			var vortex := command.duplicate(true)
			vortex.merge({"origin":command.target,"target":command.target,"pull_distance":40.0},true)
			host._pull(vortex)
			host._flash(vortex)
			return true
		"b07_altar_lines":
			# Every stroke retains its mirror identity. Turning it after lock
			# cancels that stroke rather than substituting a newly aimed beam.
			for line: Dictionary in command.get("mirror_lines",[]):
				var stroke := command.duplicate(true)
				stroke.merge(line,true)
				stroke["kind"]="melee"
				stroke["followups"]=[]
				if admitted(stroke):
					host._strike(stroke)
					host._flash(stroke)
			return true
	return false

func released(command: Dictionary) -> void:
	var caster: Node2D=host._owner(command)
	if not host._alive(caster): return
	var stage := int(command.get("stage",0))
	for source: Dictionary in command.get("followups",[]):
		stage+=1
		var follow := source.duplicate(true)
		follow["cast_id"]=str(command.cast_id)
		follow["stage"]=stage
		follow["b07_phase"]=int(command.get("b07_phase",1))
		_queue(caster,follow)

func _queue(caster: Node2D, source: Dictionary) -> void:
	if host.active_effect_count()>=host.MAX_EFFECTS or bool(source.get("admission_deferred",false)): return
	var follow := source.duplicate(true)
	var delay: float=maxf(0,float(follow.get("delay",0)))
	if int(follow.get("coefficient",0))>0 and not bool(follow.get("continuous",false)):
		follow=Skills.timed(follow,.6,int(follow.difficulty),str(follow.caster_enemy_id)=="BO07")
		follow=Skills.minimum_warning(follow,float(follow.get("minimum_visible_seconds",.8)))
		delay=maxf(delay,float(follow.tell)+float(follow.lock))
	follow=prepare(caster,Skills.geometry(follow))
	if follow.is_empty(): return
	follow["remaining"]=delay
	if delay>0: host.jobs.append(follow)
	else: host._execute(follow)

func motion_finished(motion: Dictionary, completed: bool, post_impact_seconds: float = 0.0) -> void:
	var caster: Node2D=host._owner(motion)
	if not completed or not host._alive(caster): return
	if str(motion.get("b07_after_motion",""))=="sand_emerge":
		if int(motion.difficulty)>=2:
			var sand := Skills.area(motion,Vector2(motion.target),70,0,0)
			sand.merge({"cast_id":str(motion.cast_id),"stage":1,"duration":2.0,"tick_interval":.5,"continuous":true,
				"persistent_clearance":true,"b07_birth_clock":host._biome_clock,"status":{"id":"slow","magnitude":.75,"duration":.5},"fx_color":Color("c5a15f")},true)
			var old_areas: Array=host.hazards.duplicate()
			_queue(caster,sand)
			if post_impact_seconds>0:
				for area: Dictionary in host.hazards.duplicate():
					if not old_areas.has(area): host._tick_hazard(area,post_impact_seconds)
		if int(motion.difficulty)>=4:
			# The full 1.2s exposed opening precedes a collision-safe, no-hit step.
			# The common motion admission rejects displacement instead of snapping.
			var step := Skills.child(motion,"charge","circle",0,maxf(0,1.2-post_impact_seconds))
			var direction: Vector2=Vector2(motion.direction).orthogonal()*(1 if int(motion.get("cycle",0))%2==0 else -1)
			step.merge({"cast_id":str(motion.cast_id),"stage":2,"origin":Vector2(motion.target),"target":Vector2(motion.target)+direction*80,
				"direction":direction,"range":80.0,"travel_distance":80.0,"duration":.25,"path_mode":"line","landing_only":true,
				"landing_shape":"circle","radius":18.0,"harmless":true,"body_bound":true,"b07_mound":false,
				"b07_reposition_motion":true,"damage_along_path":false,"points":[]},true)
			_queue(caster,step)
	if str(motion.get("b07_after_motion",""))=="sand_ball" and int(motion.get("difficulty",0))>=2:
		# Freeze the landing followup where the leap was warned, not at the
		# victim's new position. A blocked/interrupted leap gets no sand ball.
		var ball := Skills.area(motion,Vector2(motion.target),50,30,.8)
		ball.merge({"cast_id":str(motion.cast_id),"stage":1,"minimum_visible_seconds":.8,"lob":true},true)
		_queue(caster,ball)

func allow_hit(victim: Node2D, command: Dictionary) -> bool:
	if bool(command.get("harmless",false)) or not admitted(command,true): return false
	if bool(command.get("continuous",false)): return true
	return not hit_receipts.has(_receipt(victim,command))

func confirmed_hit(victim: Node2D, command: Dictionary) -> void:
	if not bool(command.get("continuous",false)): hit_receipts[_receipt(victim,command)]=clock+30.0
	var distance: float=float(command.get("b07_push",0))
	if distance>0:
		var displacement: Vector2=Vector2(command.direction)*distance
		var radius: float=float(Props.read(victim,"navigation_radius",12))
		victim.position=host.room.move_actor(victim.position,displacement,radius)

func _receipt(victim: Node2D, command: Dictionary) -> String:
	return "%s:%d:%d" % [str(command.get("cast_id","")),int(command.get("stage",0)),victim.get_instance_id()]

func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	clock+=delta
	for key: String in hit_receipts.keys():
		if float(hit_receipts[key])<=clock: hit_receipts.erase(key)
	for effect: Dictionary in effects.duplicate():
		var caster: Node2D=host._owner(effect)
		if not host._alive(caster):
			_clear_shield(caster)
			effects.erase(effect)
			continue
		effect.remaining=maxf(0,float(effect.remaining)-delta)
		var lit_now := Skills.lit(caster)
		if int(effect.difficulty)>=4 and bool(effect.was_lit) and not lit_now and not bool(effect.penalty_applied):
			var brain: Variant=Props.read(caster,"brain")
			if brain is Object and brain.has_method("extend_cooldown"): brain.extend_cooldown(2.0)
			effect.penalty_applied=true
		effect.was_lit=lit_now
		if float(effect.remaining)<=0 or caster.position.distance_to(Vector2(effect.origin))>30:
			_clear_shield(caster)
			effects.erase(effect)

func movement_multiplier(actor: Node2D) -> float:
	var profile: Dictionary=Props.read(actor,"profile",{})
	if str(profile.get("enemy_id",""))!="B07-M02" or int(profile.get("difficulty",0))<4: return 1.0
	if not bool(actor.get_meta("b07_camouflaged",false)) or Skills.lit(actor): return 1.0
	var mechanism: Variant=Skills.mechanics(actor)
	if mechanism is Object and mechanism.has_method("is_revealed") and bool(mechanism.is_revealed(actor)): return 1.0
	var player: Variant=Props.read(host.room,"player")
	if player is Node2D and actor.position.distance_to(player.position)<=120: return 1.0
	return 1.1

func cancel_shield(caster: Node2D) -> void:
	for effect: Dictionary in effects.duplicate():
		if host._owner(effect)==caster: effects.erase(effect)
	_clear_shield(caster)

func _clear_shield(caster: Node2D) -> void:
	if is_instance_valid(caster):
		caster.set_meta("b07_shield_active",false)
		if caster.has_meta("b07_shield_direction"): caster.remove_meta("b07_shield_direction")

func cancel_owner(caster: Node2D) -> void:
	cancel_shield(caster)
	if is_instance_valid(caster): caster.set_meta("b07_camouflaged",false)

func reset() -> void:
	for effect: Dictionary in effects: _clear_shield(host._owner(effect))
	effects.clear()
	hit_receipts.clear()
	clock=0.0
	serial=0

func draw(canvas: Node2D) -> void:
	for motion: Dictionary in host.motions:
		if not bool(motion.get("b07_mound",false)): continue
		var actor: Node2D=host._owner(motion)
		if host._alive(actor): Skills.Presentation.draw_mound(canvas,actor.position,Vector2(motion.target),float(motion.radius))
	for effect: Dictionary in effects:
		var caster: Node2D=host._owner(effect)
		if not host._alive(caster): continue
		var facing: Vector2=effect.direction
		var tint := Color("f3cb69") if Skills.lit(caster) else Color("847d62")
		canvas.draw_arc(caster.position,34,facing.angle()-PI/3,facing.angle()+PI/3,24,tint,4,true)
