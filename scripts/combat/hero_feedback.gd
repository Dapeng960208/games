class_name HeroFeedback
extends Node2D
## Presentation only. Callbacks originate from committed combat events; this
## node never damages, spends resources, aims attacks or changes their timing.

const AMBER := Color("eabb78")
const IVORY := Color("f5ebc9")
const CYAN := Color("78d9d1")
const COPPER := Color("df945a")
const VIOLET := Color("b7a1ec")
const Chain = preload("res://scripts/combat/hit_chain.gd")
var actor: Node2D
var effects: Array[Dictionary] = []
var release_events: Array[Dictionary] = []
var basic_events: int = 0
var impact_events: int = 0
var deployment_events: int = 0
var _cast: Dictionary = {}
var _cast_age: float = 0.0
var _basic: String = ""
var _basic_age: float = 0.0
var _basic_duration: float = 0.1
var _basic_direction := Vector2.RIGHT
var _shot_age: float = 100.0
var _shot_direction := Vector2.RIGHT
var _shot_index: int = 0
var _shot_count: int = 1
var _frozen_pose: Dictionary = {}
var locomotion_events: int = 0
var _motion_position := Vector2.ZERO
var _motion_stride: float = 0.0
var _motion_ready: bool = false
var _moving: bool = false
var _motion_direction := Vector2.RIGHT
var _step_distance: float = 0.0
var _step_side: float = 1.0
var _was_dashing: bool = false
var _chain_font: Font

func configure(player: Node2D) -> void:
	actor = player
	name = "HeroFeedback"
	z_index = -1 # Below hero/enemy bodies and the enemy warning layer.
	set_process(false)
	set_physics_process(false)
	_motion_position = player.position
	_motion_stride = float(player.stride)
	_motion_ready = true
	_chain_font = MineStyle.make_theme().default_font

func advance(delta: float) -> void:
	if not is_instance_valid(actor) or delta <= 0.0 or get_tree().paused:
		return
	var stopped: bool = float(actor.visual_hitstop) > 0.0
	_sample_motion(stopped)
	if not stopped:
		_basic_age += delta
		_shot_age += delta
		_cast_age += delta
		if not _cast.is_empty() and _cast_age > float(_cast.duration)+.18:
			_cast.clear()
		for index in range(effects.size()-1,-1,-1):
			effects[index].age += delta
			if float(effects[index].age) >= float(effects[index].duration):
				effects.remove_at(index)
	queue_redraw()

func observe_basic(kind: String, duration: float, committed_direction: Vector2 = Vector2.ZERO) -> void:
	if kind not in ["attack_windup","attack_strike"] or not is_instance_valid(actor):
		return
	_basic = kind
	_basic_age = 0.0
	_frozen_pose.clear()
	_basic_duration = duration
	# A locked/automatic shot can differ from the live mouse aim. Preserve the
	# actual committed direction through release and recoil; legacy callers may
	# still omit it and use the actor aim at the moment they record the event.
	var direction: Vector2 = committed_direction if committed_direction.is_finite() and not committed_direction.is_zero_approx() else actor.aim_direction
	_basic_direction = direction.normalized() if direction.is_finite() and not direction.is_zero_approx() else Vector2.RIGHT
	_shot_direction = _basic_direction
	if kind != "attack_strike":
		return
	basic_events += 1
	var hero: String = actor.hero_id()
	_emit("swing" if hero == "CH01" else "muzzle" if hero == "CH02" else "arcane_release",actor.position,_basic_direction,.26 if hero == "CH01" else .18 if hero == "CH02" else .24,{"hero":hero,"slot":"basic","radius":105.0,"arc":100.0,"heavy":false,"variant":(basic_events-1)%3})

func chain_hit(state: Dictionary) -> void:
	var count: int = int(state.count)
	var milestone: bool = bool(state.get("advanced",false)) and count in Chain.MILESTONES
	_emit("chain_burst" if milestone else "chain_tick",actor.position,actor.aim_direction,.65 if milestone else .20,{"hero":actor.hero_id(),"tier":int(state.tier),"count":count})

func cast_started(data: Dictionary, direction: Vector2, target: Vector2, serial: int) -> void:
	_frozen_pose.clear()
	_cast = data.duplicate(true)
	_cast["serial"] = serial
	_cast["target"] = target
	_cast_age = 0.0
	_shot_age = 100.0
	_shot_direction = direction
	_basic = ""
	queue_redraw()

func cancel_cast() -> void:
	_cast.clear()
	_basic = ""
	_basic_age = 0.0
	_frozen_pose.clear()
	# Already released feedback is allowed to finish, just like a fired bolt.

func skill_released(data: Dictionary, direction: Vector2, at: Vector2, index: int, count: int, serial: int) -> void:
	if not is_instance_valid(actor):
		return
	_shot_age = 0.0
	_frozen_pose.clear()
	_shot_direction = direction
	_shot_index = index
	_shot_count = count
	release_events.append({"hero":str(data.hero),"slot":str(data.slot),"index":index,"count":count,"serial":serial})
	if release_events.size() > 128:
		release_events.pop_front()
	var hero: String = str(data.hero)
	var slot: String = str(data.slot)
	var details: Dictionary = {"hero":hero,"slot":slot,"radius":float(data.get("radius",65.0)),"arc":float(data.get("arc",360.0)),"heavy":slot == "secondary" or slot == "ultimate","last":index == count-1,"index":index,"count":count,"energy":int(data.get("break_stacks",0)),"target":at}
	if hero == "CH01":
		_emit("swing" if slot == "secondary" else "ground_break" if slot == "ultimate" else "brace" if slot == "f" else "rush",at,direction,.56 if slot == "ultimate" else .38 if slot == "f" else .32,details)
		if int(data.get("break_stacks", 0)) == 3 and slot in ["secondary", "ultimate"]:
			_emit("ground_break",at,direction,.52,details)
	elif hero == "CH02":
		_emit("grenade_toss" if slot == "f" else "muzzle",actor.position if slot == "f" else at,direction,.18 if slot == "f" else .24 if slot == "ultimate" and index == count-1 else .16,details)
	else:
		_emit("arcane_release" if slot == "q" else "rune_seed" if slot == "secondary" else "rune_collapse" if slot == "f" else "dome_wave",at,direction,.56 if slot == "ultimate" else .38,details)
	queue_redraw()

func impact(at: Vector2, direction: Vector2, source: String, critical: bool = false) -> void:
	if not is_instance_valid(actor):
		return
	impact_events += 1
	# Confirmed contacts have a world-space layer above bodies. Preserve the
	# callback/counter for animation telemetry without duplicating a feet flash.
	if not is_instance_valid(actor.room.get("impact_feedback")):
		_emit("impact",at,direction,.18,{"hero":actor.hero_id(),"heavy":critical or source in ["secondary","ultimate"],"slot":source})

func deployment_pulse(kind: String, at: Vector2, radius: float) -> void:
	deployment_events += 1
	var gunner: bool = kind in ["grenade","trap"]
	# A node's ordinary shot is a local emitter pulse, never a damage-area cue.
	var shown_radius: float = minf(radius,30.0) if kind == "node" else radius
	_emit("grenade_burst" if gunner else "dome_wave" if kind == "field" else "node_wave",at,Vector2.RIGHT,.36 if gunner else .46 if kind == "field" else .28,{"hero":"CH02" if gunner else "CH03","radius":shown_radius,"heavy":kind == "field" or gunner,"deployment":true})

func class_event(kind: String, at: Vector2, direction: Vector2, radius: float = 42.0, energy: int = 0) -> void:
	_emit(kind, at, direction, 0.48 if kind == "node_burst" else 0.32, {"hero":actor.hero_id(), "radius":radius, "energy":clampi(energy,0,3)})

func pose_state() -> Dictionary:
	if is_instance_valid(actor) and float(actor.visual_hitstop) > 0.0 and not _frozen_pose.is_empty():
		return _frozen_pose.duplicate()
	var result: Dictionary = {"phase":"idle","progress":0.0,"slot":"basic","direction":actor.aim_direction if is_instance_valid(actor) else Vector2.RIGHT,"shot":_shot_index,"shots":_shot_count,"charge":0.0}
	if not _cast.is_empty():
		result.slot = str(_cast.slot)
		result.direction = _shot_direction
		var active: Dictionary = actor.abilities.active if is_instance_valid(actor) and actor.abilities != null else {}
		var clock: float = float(active.get("elapsed",_cast_age))
		if not active.is_empty():
			result.direction = active.direction
		var windup: float = maxf(.01,float(_cast.windup))
		if _shot_age < .09:
			result.phase = "release"
			result.progress = _shot_age/.09
		elif clock < windup:
			result.phase = "windup"
			result.progress = clampf(clock/windup,0.0,1.0)
			result.charge = result.progress
		elif not active.is_empty() and int(active.next_event) < active.events.size() and float(active.events[int(active.next_event)].time)-clock < .085:
			result.phase = "windup"
			result.progress = 1.0-clampf((float(active.events[int(active.next_event)].time)-clock)/.085,0.0,1.0)
			result.charge = result.progress
		else:
			result.phase = "recovery"
			result.progress = clampf(_shot_age/.23,0.0,1.0)
		# These single-release clips need the entire recovery interval, while the
		# established progress remains unchanged for procedural FX and other skills.
		var authored_skill: bool = (str(_cast.hero) in ["CH01", "CH02"] and str(_cast.slot) == "secondary") or (str(_cast.hero) == "CH03" and str(_cast.slot) == "f")
		if authored_skill:
			result["authored_phase_progress"] = result.progress
			if str(result.phase) == "recovery":
				var recovery_duration: float = maxf(.01, float(_cast.duration) - float(_cast.windup) - .09)
				result["authored_phase_progress"] = clampf((_shot_age - .09)/recovery_duration, 0.0, 1.0)
	elif _basic == "attack_windup" and _basic_age < _basic_duration:
		result.phase = "windup"
		result.progress = _basic_age/maxf(.01,_basic_duration)
		result.charge = result.progress
		result.direction = _basic_direction
	elif _basic == "attack_strike" and _basic_age < .29:
		result.phase = "release" if _basic_age < .09 else "recovery"
		result.progress = _basic_age/.09 if _basic_age < .09 else (_basic_age-.09)/.2
		result.direction = _basic_direction
	_frozen_pose = result.duplicate()
	return result

func _emit(kind: String, at: Vector2, direction: Vector2, duration: float, details: Dictionary) -> void:
	if effects.size() >= 64:
		effects.pop_front()
	var packet: Dictionary = details.duplicate()
	packet.merge({"kind":kind,"at":at,"direction":direction.normalized(),"age":0.0,"duration":duration},true)
	effects.append(packet)
	queue_redraw()

func _sample_motion(stopped: bool) -> void:
	var at: Vector2 = actor.position
	if not _motion_ready:
		_motion_position = at
		_motion_ready = true
	var travel: Vector2 = at - _motion_position
	var distance: float = travel.length()
	var dashing: bool = float(actor.dash_remaining) > 0.0
	var skill_travel: bool = actor.abilities != null and actor.abilities.busy() and float(actor.abilities.active.spec.get("travel",0.0)) > 0.0
	# Input can clear requested velocity before abilities tick. The previous
	# resolved position AND distance clock prove travel without reading input.
	_moving = distance > .01 and distance < 48.0 and not dashing and not skill_travel and float(actor.stride) > _motion_stride + .00001
	if _moving:
		_motion_direction = travel.normalized()
	var hero: String = actor.hero_id()
	if dashing and not _was_dashing:
		if not stopped:
			_emit("dash_depart", _motion_position, actor.dash_direction, .30, {"hero":hero})
		_step_distance = 0.0
	elif _was_dashing and not dashing:
		if not stopped:
			_emit("dash_land", at, actor.dash_direction, .34, {"hero":hero})
		_step_distance = 0.0
	elif _moving and not stopped:
		_step_distance += distance
		var spacing: float = 26.0 if hero == "CH01" else 34.0 if hero == "CH02" else 30.0
		if _step_distance >= spacing:
			_step_distance = fmod(_step_distance, spacing)
			var side: Vector2 = _motion_direction.orthogonal() * _step_side * (8.0 if hero == "CH01" else 6.0)
			_emit("footfall", at + Vector2(side.x, side.y * .6) + Vector2(0, 8), _motion_direction, .30 if hero == "CH03" else .26, {"hero":hero})
			_step_side *= -1.0
			locomotion_events += 1
	# Fixture placement, blocked input and teleport travel never fabricate steps.
	if distance >= 48.0 or (not _moving and not dashing):
		_step_distance = 0.0
	_motion_position = at
	_motion_stride = float(actor.stride)
	_was_dashing = dashing

func motion_state() -> Dictionary:
	var pose: Dictionary = pose_state()
	var dashing: bool = is_instance_valid(actor) and float(actor.dash_remaining) > 0.0
	var direction: Vector2 = actor.dash_direction if dashing else Vector2(pose.direction) if str(pose.phase) != "idle" else _motion_direction if _moving else actor.aim_direction
	if not direction.is_finite() or direction.is_zero_approx():
		direction = Vector2.RIGHT
	return {"direction":direction.normalized(), "moving":_moving, "dashing":dashing, "steps":locomotion_events, "dash_progress":clampf(float(actor.dash_elapsed)/(.22 if actor.hero_id() == "CH02" else .18),0.0,1.0)}

func _draw() -> void:
	if not is_instance_valid(actor):
		return
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var quality: float = .52 if reduced else 1.0
	_draw_class_identity(quality)
	_draw_chain_aura(reduced)
	var pose: Dictionary = pose_state()
	_draw_facing(pose,reduced)
	var motion: Dictionary = motion_state()
	if bool(motion.dashing):
		_draw_dodge_travel(motion,reduced)
	if str(pose.phase) == "windup":
		_draw_charge(pose,quality)
	for effect: Dictionary in effects:
		var t: float = clampf(float(effect.age)/float(effect.duration),0.0,1.0)
		var fade: float = (1.0-t)*quality
		var at: Vector2 = Vector2(effect.at)-actor.position
		var dir: Vector2 = effect.direction
		var tint: Color = CYAN if str(effect.get("hero","")) == "CH03" else AMBER if str(effect.get("hero","")) == "CH01" else IVORY
		var radius: float = float(effect.get("radius",65.0))
		match str(effect.kind):
			"footfall": _draw_footfall(at,dir,str(effect.hero),t,fade,reduced)
			"dash_depart","dash_land": _draw_dodge_stamp(at,dir,str(effect.hero),t,fade,reduced,str(effect.kind) == "dash_land")
			"muzzle": _draw_muzzle(effect,t,fade,tint)
			"swing": _draw_cleave(at,dir,radius,float(effect.get("arc",100.0)),bool(effect.get("heavy",false)),t,fade,reduced,int(effect.get("variant",0)))
			"chain_tick","chain_burst": _draw_chain_pulse(effect,at,t,fade,reduced)
			"ground_break": _draw_fissure(at,dir,radius,t,fade,reduced,float(effect.get("arc",160.0)) if str(effect.get("slot","")) == "secondary" else 360.0)
			"rush": _draw_rush(at,dir,t,fade,reduced)
			"brace": _draw_brace(at,dir,t,fade,reduced)
			"grenade_toss": _draw_grenade_toss(effect,at,t,fade,reduced)
			"grenade_burst": _draw_grenade_burst(at,radius,t,fade,reduced)
			"arcane_release": _draw_arcane_release(effect,t,fade,reduced)
			"rune_seed": _draw_rune_seed(at,t,fade,reduced)
			"rune_collapse": _draw_rune_collapse(at,radius,t,fade,reduced)
			"dome_wave","node_wave","resonance","frost": _draw_spell_wave(at,radius,t,fade,str(effect.kind) == "dome_wave",reduced)
			"deploy": _draw_rune_seed(at,t,fade,reduced)
			"mark", "mark_burst":
				var reach: float = (18.0 + 30.0 * t) if effect.kind == "mark_burst" else 30.0 - 12.0 * t
				for side in [-1.0, 1.0]:
					var normal: Vector2 = dir.orthogonal() * side
					draw_line(at + normal * reach - dir * 10.0, at + normal * reach + dir * 10.0, Color(IVORY, fade), 2.5, true)
				if effect.kind == "mark_burst":
					draw_line(at - dir * 45.0, at + dir * 62.0, Color(IVORY, fade), 4.0, true)
			"node_burst":
				_draw_node_burst(at,radius,int(effect.get("energy",0)),t,fade,reduced)
			"impact": _draw_impact(at,dir,str(effect.get("hero","")),bool(effect.get("heavy",false)),t,fade)

func _draw_chain_aura(reduced: bool) -> void:
	var state: Dictionary = actor.hit_chain.snapshot()
	var tier: int = int(state.tier)
	if tier <= 0: return
	var phase: float = float(actor.stride)*.08 + float(actor.combat_time)*.3
	if reduced: phase = 0.0
	var opacity: float = .65 * minf(1.0,float(state.remaining)/.5)
	_draw_chain_crest(actor.hero_id(),Vector2.ZERO,27.0+tier*2,phase,opacity,reduced,tier)

func _draw_chain_pulse(effect: Dictionary, at: Vector2, t: float, fade: float, reduced: bool) -> void:
	var burst: bool = str(effect.kind) == "chain_burst"
	if burst:
		_draw_chain_crest(str(effect.hero),at+Vector2(0,-14),22.0+t*24.0,0.0 if reduced else t*.8,minf(1.0,fade*1.6),reduced,int(effect.tier))
		if _chain_font != null:
			var caption: String = "x%d" % int(effect.count)
			var size: int = 25+int(effect.tier)*2
			var width: float = _chain_font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
			var caption_at: Vector2 = at+Vector2(-width*.5,-128-(0.0 if reduced else t*9))
			var tint: Color = Color("d78aff") if str(effect.hero) == "CH03" else Color("ffd150")
			draw_string_outline(_chain_font,caption_at,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,size,5,Color(Color("4a2d48"),fade))
			draw_string(_chain_font,caption_at,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(tint,minf(1.0,fade*1.6)))
	else:
		var hero: String = str(effect.hero)
		var tint: Color = Color("ffbe37") if hero != "CH03" else Color("ce89ff")
		var side: float = -1.0 if int(effect.count)%2 == 0 else 1.0
		var spark: Vector2 = at+Vector2(side*(21+t*9),-24-t*17)
		_diamond(spark,Vector2.UP,5.0*(1-t*.5),Color(tint,fade))

func _draw_chain_crest(hero: String, at: Vector2, radius: float, phase: float, alpha: float, reduced: bool, tier: int) -> void:
	var tint: Color = Color("ff962d") if hero == "CH01" else Color("ffcb48") if hero == "CH02" else Color("bc77ff")
	var marks: int = 3 if reduced else 3+mini(tier,5)
	for index in marks:
		var angle: float = index*TAU/marks+phase
		var ray: Vector2 = Vector2(cos(angle),sin(angle)*.48)
		var center: Vector2 = at+ray*radius
		if hero == "CH01":
			# A convex upright flame remains valid at every projected orbit angle.
			var flame := PackedVector2Array([center+Vector2(0,-12-tier),center+Vector2(5,1),center+Vector2(0,5),center+Vector2(-5,1)])
			draw_colored_polygon(flame,Color(tint,alpha))
			draw_line(center-ray*3,center+ray*3+Vector2(0,-5),Color("fff2a8",alpha),2.3,true)
		elif hero == "CH02":
			draw_line(center-ray*4,center+ray*4,Color("68402e",alpha),5.0,true)
			draw_line(center-ray*3,center+ray*3,Color(tint,alpha),3.0,true)
		else:
			_diamond(center,Vector2.UP,5.0+mini(tier,3),Color("503073",alpha))
			_diamond(center,Vector2.UP,3.0+mini(tier,3),Color(tint,alpha))
			if not reduced:
				var next: Vector2 = at+Vector2(cos(angle+TAU/marks),sin(angle+TAU/marks)*.48)*radius
				draw_line(center,next,Color("2ed4da",alpha*.55),1.7,true)

func _draw_facing(pose: Dictionary, reduced: bool) -> void:
	var state: Dictionary = motion_state()
	var direction: Vector2 = state.direction
	var tint: Color = COPPER if actor.hero_id() == "CH01" else IVORY if actor.hero_id() == "CH02" else CYAN
	var active: bool = str(pose.phase) != "idle" or bool(state.dashing) or bool(state.moving)
	var opacity: float = .88 if active else .58
	var tip: Vector2 = Vector2(0,8)+direction*32.0
	var outline := PackedVector2Array([tip-direction*8.0+direction.orthogonal()*5.0,tip,tip-direction*8.0-direction.orthogonal()*5.0])
	draw_polyline(outline,Color("493645",opacity*.8),4.3,true)
	draw_polyline(outline,Color(tint,opacity),2.2,true)
	if not reduced and active:
		for side in [-1.0,1.0]:
			var at: Vector2 = tip-direction*13.0+direction.orthogonal()*side*7.0
			draw_line(at-direction*3.0,at+direction*2.0,Color(tint,opacity*.65),1.5,true)

func _draw_footfall(at: Vector2, dir: Vector2, hero: String, t: float, fade: float, reduced: bool) -> void:
	if hero == "CH03":
		draw_set_transform(at,0.0,Vector2(1,.52))
		_segmented_ring(Vector2.ZERO,7.0+t*9.0,4,.7,Color(VIOLET,fade*.7),1.5)
		draw_set_transform(Vector2.ZERO)
		if not reduced:
			_diamond(at+Vector2(-4,-5-t*9),Vector2.UP,3.0*(1-t),Color(CYAN,fade*.75))
		return
	var tint: Color = COPPER if hero == "CH01" else AMBER
	draw_set_transform(at,0.0,Vector2(1,.45))
	draw_arc(Vector2.ZERO,4.0+t*9.0,0,TAU,14,Color(tint,fade*.52),2.8 if hero == "CH01" else 1.8,true)
	draw_set_transform(Vector2.ZERO)
	if reduced: return
	for index in 3:
		var offset: Vector2 = -dir*(3.0+t*(10.0+index*3.0))+dir.orthogonal()*(index-1)*5.0+Vector2(0,-sin(t*PI)*(3.0+index))
		var point: Vector2 = at+offset
		var size: float = (2.6 if hero == "CH01" else 1.8)*(1.0-t*.55)
		draw_colored_polygon(PackedVector2Array([point+Vector2(-size,0),point+Vector2(0,-size),point+Vector2(size,0),point+Vector2(0,size*.7)]),Color(AMBER,fade*.62))

func _draw_dodge_travel(state: Dictionary, reduced: bool) -> void:
	var dir: Vector2 = state.direction
	var cross: Vector2 = dir.orthogonal()
	var hero: String = actor.hero_id()
	var tint: Color = COPPER if hero == "CH01" else IVORY if hero == "CH02" else CYAN
	var phase: float = float(state.dash_progress)
	var opacity: float = .42+.4*sin(phase*PI)
	for index in (2 if reduced else 3):
		var side: float = float(index-1)
		var tip: Vector2 = Vector2(0,-17)+cross*side*12.0-dir*15.0
		var tail: Vector2 = tip-dir*(22.0+index*8.0)*(1.0-phase*.4)
		var ribbon := PackedVector2Array([tip+cross*2.7,tail+cross*.7,tail-dir*8.0,tip-cross*2.7])
		draw_colored_polygon(ribbon,Color(tint,opacity*.62))
		draw_line(tail,tip,Color("493645",opacity*.55),3.8,true)
		draw_line(tail,tip,Color(tint,opacity),1.9,true)
		if hero == "CH03" and not reduced:
			_diamond(tail+cross*4.0,dir,4.0,Color(VIOLET,opacity*.9))

func _draw_dodge_stamp(at: Vector2, dir: Vector2, hero: String, t: float, fade: float, reduced: bool, landing: bool) -> void:
	var tint: Color = COPPER if hero == "CH01" else AMBER if hero == "CH02" else CYAN
	var reach: float = (12.0 if landing else 9.0)+t*13.0
	draw_set_transform(at+Vector2(0,8),0.0,Vector2(1,.58))
	if hero == "CH03":
		_segmented_ring(Vector2.ZERO,reach,6,.35,Color("624993",fade*.8),4.0)
		_segmented_ring(Vector2.ZERO,reach,6,.35,Color(tint,fade*.95),2.0)
	else:
		draw_arc(Vector2.ZERO,reach,0,TAU,20,Color(tint,fade*.65),3.0 if hero == "CH01" else 2.0,true)
	draw_set_transform(Vector2.ZERO)
	if reduced: return
	for index in 4:
		var ray: Vector2 = (-dir).rotated((index-1.5)*.5)
		var from: Vector2 = at+Vector2(0,8)+ray*reach*.6
		var end: Vector2 = from+ray*(9.0+t*13.0)
		draw_line(from,end,Color("493645",fade*.4),4.0,true)
		draw_line(from,end,Color(tint,fade*.8),2.0,true)

func _draw_cleave(at: Vector2, dir: Vector2, radius: float, degrees: float, heavy: bool, t: float, fade: float, reduced: bool, variant: int = 0) -> void:
	# The broad axe face is present on contact, then thins into its copper wake.
	var visible: float = minf(1.0,fade*1.45)
	var arc: float = deg_to_rad(minf(degrees,220.0))
	var start: float = dir.angle()-arc*.5+arc*.16*t*(0.0 if variant == 1 else 1.0)
	var finish: float = dir.angle()+arc*.5-arc*.16*t*(1.0 if variant == 1 else 0.0)
	var thickness: float = (34.0 if heavy else 29.0 if variant == 2 else 23.0)*(1.0-t*.45)
	var blade := PackedVector2Array()
	var points: int = 12 if reduced else 22
	for index in range(points+1):
		blade.append(at+Vector2.from_angle(lerpf(start,finish,float(index)/points))*radius)
	for index in range(points,-1,-1):
		blade.append(at+Vector2.from_angle(lerpf(start,finish,float(index)/points))*(radius-thickness))
	draw_colored_polygon(blade,Color("ffd24d" if variant == 2 else "ff6835" if variant == 1 else "ff8c32",visible*.9))
	# Copper ink separates the same cutting edge from the bright courtyard floor.
	draw_arc(at,radius-4,start,finish,points+1,Color("662b23",visible*.95),8.0,true)
	draw_arc(at,radius-3,start,finish,points+1,Color("ffb53f",visible),5.0,true)
	draw_arc(at,radius-thickness*.35,start+arc*.05,finish,points,Color("fff3c0",visible),4.2 if heavy else 3.2,true)
	draw_arc(at,radius-thickness+2,start,finish,points+1,Color("c5491b",visible*.85),4.0,true)
	if variant == 2 and not heavy:
		# Accent a third contact without implying another hit or a larger sector.
		draw_line(at+dir*(radius-thickness-20),at+dir*(radius-6),Color("fff6ca",visible),6.0,true)
		draw_line(at+dir*(radius-thickness-20)-dir.orthogonal()*10,at+dir*(radius-6),Color("ffbd35",visible),4.0,true)
	if reduced: return
	draw_arc(at,radius-thickness-8.0,start,finish-arc*.16,points,Color("ffb747",visible*.68),4.0,true)
	_sparks(at+dir*radius*.72,dir,5 if heavy else 3,minf(21.0,radius*.16),visible,Color("fff0b0"))

func _draw_fissure(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, reduced: bool, degrees: float = 360.0) -> void:
	var visible: float = minf(1.0,fade*1.4)
	var spread: float = 1.0-pow(1.0-t,3.0)
	var rays: int = 5 if reduced else 9
	var sector: float = deg_to_rad(degrees)
	var frontal: bool = degrees < 359.0
	for index in rays:
		var fraction: float = float(index)/maxf(1.0,rays-1)-.5
		var ray: Vector2 = dir.rotated(fraction*sector*.9 if frontal else index*TAU/rays)
		var reach: float = radius*(.38+.62*spread)*(.70+absf(sin(index*2.3))*.30)
		var bend: float = 10.0 if index%2 == 0 else -10.0
		if frontal: bend *= 1.0-absf(fraction)*1.8
		var crack := PackedVector2Array([at+ray*12.0,at+ray*reach*.34+ray.orthogonal()*bend,at+ray*reach*.65-ray.orthogonal()*bend*.45,at+ray*reach])
		draw_polyline(crack,Color("552b21",visible*.95),10.0,true)
		draw_polyline(crack,Color("ff8433",visible),5.0,true)
		draw_polyline(crack,Color("fff0b6",visible*.95),2.0,true)
		if not reduced:
			var chip: Vector2 = at+ray*reach*.8+Vector2(0,-sin(t*PI)*13.0)
			var fragment := PackedVector2Array([chip-ray*7,chip+ray*9,chip+ray.orthogonal()*7])
			draw_colored_polygon(fragment,Color("ffb548",visible*.9))
			fragment.append(fragment[0])
			draw_polyline(fragment,Color("7b3b24",visible),2.0,true)
	var pressure_radius: float = maxf(1.0,radius*(.28+.72*spread)-3.5)
	draw_arc(at,pressure_radius,dir.angle()-sector*.5 if frontal else 0.0,dir.angle()+sector*.5 if frontal else TAU,32,Color("74372a",visible*.7),7.0,true)
	draw_arc(at,pressure_radius,dir.angle()-sector*.5 if frontal else 0.0,dir.angle()+sector*.5 if frontal else TAU,32,Color("ffb13d",visible*.95),4.0,true)
	_sparks(at,dir,4 if reduced or frontal else 8,25.0,visible,Color("fff2be"))
	if not frontal:
		# The axe crest is already planted on the release frame. It lifts and
		# fades with the real shockwave, without suggesting a second delayed hit.
		var crest_alpha: float = visible*(1.0-smoothstep(.12,.48,t))
		var crest: Vector2 = at+Vector2(0,-26.0-t*16.0)
		draw_line(crest+Vector2(0,7),crest+Vector2(0,44),Color("65322a",crest_alpha),9.0,true)
		draw_line(crest+Vector2(-1,9),crest+Vector2(-1,42),Color("ffbf54",crest_alpha),4.0,true)
		var axe := PackedVector2Array([crest+Vector2(-40,-15),crest+Vector2(-22,-23),crest+Vector2(-7,-14),crest+Vector2(7,-14),crest+Vector2(22,-23),crest+Vector2(40,-15),crest+Vector2(33,11),crest+Vector2(13,18),crest+Vector2(-13,18),crest+Vector2(-33,11)])
		draw_colored_polygon(axe,Color("f77d2e",crest_alpha*.95))
		axe.append(axe[0])
		draw_polyline(axe,Color("6a3028",crest_alpha),6.0,true)
		draw_polyline(PackedVector2Array([crest+Vector2(-36,-12),crest+Vector2(-29,7),crest+Vector2(-12,14),crest+Vector2(12,14),crest+Vector2(29,7),crest+Vector2(36,-12)]),Color("fff0b8",crest_alpha),4.5,true)
		_diamond(crest,Vector2.UP,9.0,Color("fff4ce",crest_alpha))

func _draw_rush(at: Vector2, dir: Vector2, t: float, fade: float, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.4)
	for side in [-1.0,1.0]:
		var edge: Vector2 = dir.orthogonal()*side*23.0
		var trail := PackedVector2Array([at+edge-dir*74*(1.0-t),at+edge-dir*18,at+dir*31])
		draw_polyline(trail,Color("6f3225",visible*.9),8.0,true)
		draw_polyline(trail,Color("ff9e35",visible),5.0,true)
		if not reduced:
			for index in 3:
				var dust: Vector2 = at+edge-dir*(25+index*20)+dir.orthogonal()*side*t*14
				draw_line(dust-dir*10,dust,Color("ffcb63",visible*(.8-index*.13)),4.0,true)
	draw_arc(at,36.0,dir.angle()-.75,dir.angle()+.75,12,Color("733829",visible*.85),8.0,true)
	draw_arc(at,36.0,dir.angle()-.75,dir.angle()+.75,12,Color("fff1ba",visible),4.5,true)

func _draw_brace(at: Vector2, dir: Vector2, t: float, fade: float, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.45)
	var front: Vector2 = at+dir*(21.0+t*13.0)
	var side: Vector2 = dir.orthogonal()
	var shield := PackedVector2Array([front+side*29-dir*8,front+side*25+dir*11,front+dir*23,front-side*25+dir*11,front-side*29-dir*8])
	draw_colored_polygon(shield,Color("ffb33f",visible*.28))
	shield.append(shield[0])
	draw_polyline(shield,Color("6a3928",visible),9.0,true)
	draw_polyline(shield,Color("ffc85b",visible),5.0,true)
	draw_polyline(PackedVector2Array([front+side*17,front+dir*12,front-side*17]),Color("fff6cb",visible),3.8,true)
	if not reduced:
		for sign in [-1.0,1.0]:
			var foot: Vector2 = at+side*sign*21
			draw_line(foot-dir*11,foot+dir*17,Color("ff9f36",visible*.85),6.0,true)

func _draw_grenade_toss(effect: Dictionary, at: Vector2, t: float, fade: float, reduced: bool) -> void:
	var target: Vector2 = Vector2(effect.target)-actor.position
	var departure: Vector2 = at+Vector2(0,-25)
	var thrown: Vector2 = departure.lerp(target,t)+Vector2(0,-sin(t*PI)*35)
	var angle: float = t*TAU
	var axis: Vector2 = Vector2.from_angle(angle)
	var normal: Vector2 = axis.orthogonal()
	var shell := PackedVector2Array([thrown-axis*6-normal*5,thrown+axis*6-normal*5,thrown+axis*6+normal*5,thrown-axis*6+normal*5])
	draw_colored_polygon(shell,Color("ffb237",minf(1.0,fade*1.5)))
	shell.append(shell[0])
	draw_polyline(shell,Color("693f26",fade),2.5,true)
	draw_line(thrown-axis*3,thrown+axis*3,Color("fff3bf",fade),2.5,true)
	if not reduced:
		var tail: float = maxf(0.0,t-.16)
		var previous: Vector2 = departure.lerp(target,tail)+Vector2(0,-sin(tail*PI)*35)
		draw_line(previous,thrown,Color("ad5b29",fade*.6),5.0,true)
		draw_line(previous,thrown,Color("ffce6b",fade*.9),2.7,true)

func _draw_grenade_burst(at: Vector2, radius: float, t: float, fade: float, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.45)
	var spread: float = 1.0-pow(1.0-t,3.0)
	# The confirmed fuse explosion starts with a sharp white core, never ice.
	var core: float = 1.0-smoothstep(0.0,.38,t)
	var flame := PackedVector2Array()
	var flame_radius: float = 18.0+spread*19.0
	for index in 12:
		flame.append(at+Vector2.from_angle(index*TAU/12)*flame_radius*(1.0 if index%2 == 0 else .48))
	draw_colored_polygon(flame,Color("ff8530",visible*.78))
	flame.append(flame[0])
	draw_polyline(flame,Color("944224",visible*.85),3.0,true)
	draw_circle(at,10.0+spread*10,Color("fff2b5",core*.95))
	var pressure_radius: float = maxf(1.0,radius*(.18+.82*spread)-3.5)
	draw_arc(at,pressure_radius,0,TAU,32,Color("8c4928",visible*.8),7.0,true)
	draw_arc(at,pressure_radius,0,TAU,32,Color("ffc548",visible),4.3,true)
	for index in (6 if reduced else 12):
		var ray: Vector2 = Vector2.from_angle(index*2.39996)
		var point: Vector2 = at+ray*radius*(.15+spread*.72)
		var length: float = (13.0+index%3*5)*(1.0-t)
		draw_line(point-ray*length,point,Color("91502b",visible*.9),7.0,true)
		draw_line(point-ray*length,point,Color("ffe28a",visible),4.0,true)
		if not reduced:
			var shard := PackedVector2Array([point+ray*6,point-ray*5+ray.orthogonal()*4,point-ray*4-ray.orthogonal()*4])
			draw_colored_polygon(shard,Color("ff9b30",visible))
			shard.append(shard[0])
			draw_polyline(shard,Color("85402c",visible),2.2,true)

func _draw_arcane_release(effect: Dictionary, t: float, fade: float, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.45)
	var dir: Vector2 = effect.direction
	var at: Vector2 = actor.get_meta("hero_muzzle_local",dir*28+Vector2(0,-30))
	if not actor.room.has_line_of_sight(actor.position,actor.position+at):
		at = actor.room.move_actor(actor.position,at,2.0)-actor.position
	var power: float = 1.45 if str(effect.get("slot","")) == "q" else 1.0
	var reach: float = (12.0+t*15.0)*power
	var variant: int = int(effect.get("variant",0))
	var sides: int = 4 if variant == 1 else 6 if variant == 2 else 3
	_rune_polygon(at,reach,sides,dir.angle()+PI*.5+t*(1.0 if variant == 1 else -1.0),Color("4e276b",visible*.95),7.0)
	_rune_polygon(at,reach,sides,dir.angle()+PI*.5+t*(1.0 if variant == 1 else -1.0),Color("27e1dc" if variant == 1 else "da8cff" if variant == 2 else "a868ff",visible),3.8)
	_segmented_ring(at,reach*.8,3,.55,Color("1bdde6",visible),4.0)
	_diamond(at,dir,(10.0+power*3)*(1.0-t*.3),Color("9055ec",visible*.95))
	_diamond(at,dir,(6.0+power*2)*(1.0-t*.3),Color("baffee",visible))
	if variant == 2:
		_segmented_ring(at,reach+5.0,6,.50,Color("dd8fff",visible),3.0)
	draw_line(at,at+dir*(19.0+power*8)*(1.0-t*.5),Color("f1fff7",visible),4.0,true)
	if reduced: return
	for index in 3:
		var ray: Vector2 = dir.rotated((index-1)*.85)
		var crystal: Vector2 = at+ray*reach
		_diamond(crystal,ray,8.0*(1-t*.45),Color("22e4e3" if index == 1 else "a75aff",visible))

func _draw_rune_seed(at: Vector2, t: float, fade: float, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.5)
	var reach: float = 18.0+t*26.0
	_rune_polygon(at,reach,6,PI/6,Color("542b73",visible*.95),7.0)
	_rune_polygon(at,reach,6,PI/6,Color("ab65ff",visible),3.8)
	_segmented_ring(at,reach*.74,3,.6,Color("16dce5",visible),4.0)
	_diamond(at+Vector2(0,-10-t*16),Vector2.UP,15.0,Color("573780",visible))
	_diamond(at+Vector2(0,-10-t*16),Vector2.UP,12.0,Color("6affeb",visible))
	if not reduced:
		for index in 3:
			var ray: Vector2 = Vector2.from_angle(index*TAU/3+PI/6)
			draw_line(at+ray*reach*.35,at+ray*reach,Color("e8fff0",visible*.85),2.3,true)

func _draw_rune_collapse(at: Vector2, radius: float, t: float, fade: float, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.45)
	var reach: float = radius*(.34+.66*(1.0-pow(1.0-t,3)))
	_rune_polygon(at,maxf(1.0,reach-3.5),6,PI/6,Color("502b72",visible*.9),7.0)
	_rune_polygon(at,maxf(1.0,reach-3.5),6,PI/6,Color("aa61ff",visible),4.3)
	_segmented_ring(at,reach*.70,6,.42,Color("18dbe3",visible),4.5)
	for index in (3 if reduced else 6):
		var ray: Vector2 = Vector2.from_angle(index*TAU/(3 if reduced else 6)+PI/6)
		var center: Vector2 = at+ray*reach*.78
		_diamond(center,ray,12.0*(1.0-t*.5),Color("4b367b",visible))
		_diamond(center,ray,9.0*(1.0-t*.5),Color("c2fff0",visible))
		if not reduced:
			draw_line(at+ray*reach*.15,center,Color("9e54ef",visible*.7),2.7,true)

func _draw_spell_wave(at: Vector2, radius: float, t: float, fade: float, dome: bool, reduced: bool) -> void:
	var visible: float = minf(1.0,fade*1.4)
	var reach: float = radius*(.20+.80*(1.0-pow(1.0-t,2)))
	_segmented_ring(at,maxf(1.0,reach-3.5),6,.22,Color("3d347c",visible*.85),7.0 if dome else 5.0)
	_segmented_ring(at,maxf(1.0,reach-3.5),6,.22,Color("13dce4",visible),4.5 if dome else 3.2)
	_rune_polygon(at,reach*.86,6,PI/6,Color("a45dff",visible*.9),3.5)
	if reduced: return
	for index in 6:
		var ray: Vector2 = Vector2.from_angle(index*TAU/6+PI/6)
		var point: Vector2 = at+ray*reach
		_diamond(point,ray,7.5,Color("cffff0",visible))
		if dome:
			# Sparse arch ribs suggest a volume without covering enemy warnings.
			draw_polyline(PackedVector2Array([point,at+ray*reach*.5+Vector2(0,-reach*.20),at+Vector2(0,-reach*.27)]),Color("b874ff",visible*.32),2.1,true)

func _rune_polygon(at: Vector2, radius: float, sides: int, angle: float, tint: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in sides:
		points.append(at+Vector2.from_angle(angle+index*TAU/sides)*radius)
	points.append(points[0])
	draw_polyline(points,tint,width,true)

func _diamond(at: Vector2, direction: Vector2, radius: float, tint: Color) -> void:
	var normal: Vector2 = direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([at+direction*radius,at+normal*radius*.45,at-direction*radius,at-normal*radius*.45]),tint)

func _draw_node_burst(at: Vector2, radius: float, energy: int, t: float, fade: float, reduced: bool) -> void:
	if t >= 1.0 or fade <= 0.0:
		return
	var visible: float = minf(1.0,fade*1.45)
	var charged := Color("a860ff") if energy == 3 else Color("16dfe7")
	# Damage is immediate: the bright fractured core belongs to the first frame,
	# followed by an expanding thin wave. No delayed visual pretends to hit again.
	var release: float = 1.0 - pow(1.0-t,3.0)
	var core: float = 1.0-smoothstep(0.0,0.3,t)
	var reach: float = maxf(1.0,radius*(.18+.82*release)-4.0)
	_segmented_ring(at,reach,6,.28,Color("502d70",visible*.95),8.0)
	_segmented_ring(at,reach,6,.28,Color(charged,visible),4.8 if reduced else 5.5)
	_diamond(at,Vector2.UP,16.0+energy*3.0,Color("bf8dff",core*.9))
	_diamond(at,Vector2.UP,10.0+energy*2.0,Color("e5fff6",core))
	if reduced:
		return
	var center := PackedVector2Array()
	# Filled polygons use unique vertices. sin(TAU) differs slightly from zero,
	# so a nearly repeated last vertex produces an invalid microscopic edge.
	for index in 6:
		center.append(at+Vector2.from_angle(index*TAU/6.0)*(8.0+energy*2.0+release*8.0))
	draw_colored_polygon(center,Color("e8fff3",core*.9))
	for index in 6:
		var ray := Vector2.from_angle(index*TAU/6.0+.12)
		var side := ray.orthogonal()
		var tip: Vector2 = at+ray*radius*(.18+release*.68)
		var length: float = (12.0+energy*4.0)*(1.0-t)
		if length < 0.5:
			continue
		var shard := PackedVector2Array([tip+ray*length,tip+side*5.5,tip-ray*length*.65,tip-side*5.5])
		draw_line(at+ray*radius*.13,tip-ray*length,Color(charged,visible*.65),2.7,true)
		draw_colored_polygon(shard,Color(charged,visible*.95))
		shard.append(shard[0])
		draw_polyline(shard,Color("4d3370",visible),3.0,true)
		draw_line(tip-ray*length*.4,tip+ray*length*.65,Color("e5fff5",visible),1.8,true)

func _draw_class_identity(quality: float) -> void:
	if actor.hero_id() == "CH01":
		for index in range(3):
			var at := Vector2(-13.0 + index * 13.0, 17.0)
			draw_rect(Rect2(at - Vector2(4, 2), Vector2(8, 4)), Color(AMBER, quality * (.95 if index < actor.break_stacks else .18)))
	elif actor.hero_id() == "CH02":
		for entry: Dictionary in actor.class_marks.values():
			var target: Variant = entry.target.get_ref()
			if not is_instance_valid(target) or not target.is_alive():
				continue
			var at: Vector2 = target.position - actor.position
			var alpha: float = minf(1.0, float(entry.remaining)) * quality
			for side in [-1.0, 1.0]:
				var x: float = side * 19.0
				draw_polyline(PackedVector2Array([at + Vector2(x - side * 6, -17), at + Vector2(x, -17), at + Vector2(x, 12), at + Vector2(x - side * 6, 12)]), Color(IVORY, alpha * .85), 1.8, true)
			draw_line(at + Vector2(-5, -23), at + Vector2(5, -23), Color(AMBER, alpha), 2.0, true)
	else:
		var nodes: Array[Node2D] = actor.resonance_nodes()
		for node: Node2D in nodes:
			if actor.position.distance_to(node.position) > 260.0 or not actor.room.has_line_of_sight(actor.position, node.position):
				continue
			var at: Vector2 = node.position - actor.position
			var intensity: float = .12 + float(node.resonance_charge) * .07
			draw_line(Vector2(0, 7), at + Vector2(0, 7), Color(CYAN, quality * intensity), 1.3, true)
		if nodes.size() == 2 and actor.room.has_line_of_sight(nodes[0].position, nodes[1].position):
			draw_line(nodes[0].position - actor.position, nodes[1].position - actor.position, Color(CYAN, quality * .34), 1.7, true)

func _draw_charge(pose: Dictionary, quality: float) -> void:
	var value: float = float(pose.get("charge",pose.progress))
	var at: Vector2 = actor.get_meta("hero_muzzle_local",Vector2(23,-33))
	var hero: String = actor.hero_id()
	if hero == "CH03":
		var slot: String = str(pose.slot)
		var reach: float = 20.0-value*8.0
		_rune_polygon(at,reach,3,-value*1.2,Color("542d73",(.6+value*.4)*quality),6.0)
		_rune_polygon(at,reach,3,-value*1.2,Color("aa67ff",(.6+value*.4)*quality),3.5)
		_segmented_ring(at,reach*.75,3,.45,Color("1edfe6",(.6+value*.4)*quality),3.5)
		for index in 3:
			var ray := Vector2.from_angle(index*TAU/3+value*.85)
			_diamond(at+ray*(25.0-value*9.0),ray,4.0+value*3.0,Color("c9fff1",.95*quality))
		if slot in ["secondary","ultimate"] and not _cast.is_empty():
			var ground: Vector2 = Vector2(_cast.target)-actor.position
			var radius: float = float(_cast.get("burst_radius",35.0)) if slot == "secondary" else float(_cast.get("radius",180.0))
			draw_arc(ground,radius,0,TAU,64,Color(CYAN,(.32+value*.30)*maxf(.6,quality)),1.6,true)
			_rune_polygon(ground,radius,6,PI/6,Color("9551ef",value*.68*quality),3.0)
		elif slot == "f":
			draw_arc(Vector2.ZERO,float(_cast.get("radius",140.0)),0,TAU,64,Color(CYAN,(.32+value*.25)*maxf(.6,quality)),1.6,true)
			_rune_polygon(Vector2(0,5),28+value*15,6,PI/6,Color("9f5afd",value*.85*quality),3.5)
	elif hero == "CH02":
		var direction: Vector2 = pose.direction
		if str(pose.slot) == "secondary":
			var reach: Vector2 = direction * 780.0
			reach *= actor.room.blocked_fraction(actor.position + at, actor.position + at + reach, 1.0)
			draw_line(at, at + reach, Color(IVORY, (.10 + value * .20) * quality), 1.3, true)
			for side in [-1.0,1.0]:
				var normal: Vector2 = direction.orthogonal()*side
				draw_line(at+normal*7-direction*11,at+normal*7+direction*(5+value*20),Color("8a542c",value*quality),6.0,true)
				draw_line(at+normal*7-direction*11,at+normal*7+direction*(5+value*20),Color("ffe19a",value*quality),3.5,true)
				if quality > .6:
					for index in 3:
						var coil: Vector2 = at-direction*(6+index*7)+normal*(5-value*2)
						draw_line(coil-direction*2,coil+direction*2,Color(IVORY,value*.75*quality),2.0,true)
		for side in [-1.0,1.0]:
			var offset: Vector2 = direction.orthogonal()*side*(9-value*5)
			draw_line(at+offset-direction*5,at+offset+direction*6,Color("ffbd52",(.45+value*.55)*quality),2.7,true)
	else:
		var direction: Vector2 = pose.direction
		if str(pose.slot) == "f":
			draw_polyline(PackedVector2Array([direction*24-direction.orthogonal()*22,direction*37,direction*24+direction.orthogonal()*22]),Color("ffb441",(.4+value*.6)*quality),4.5,true)
		else:
			for side in [-1.0,1.0]:
				var edge: Vector2 = direction.orthogonal()*side*19
				draw_line(Vector2(0,8)+edge-direction*11,Vector2(0,8)+edge+direction*(4+value*13),Color("ef822d",(.45+value*.55)*quality),4.0,true)

func _draw_muzzle(effect: Dictionary, t: float, fade: float, tint: Color) -> void:
	var visible: float = minf(1.0,fade*1.45)
	var dir: Vector2 = effect.direction
	var at: Vector2 = actor.get_meta("hero_muzzle_local",dir*36+Vector2(0,-20))
	var room: Node2D = actor.room
	if not room.has_line_of_sight(actor.position,actor.position+at):
		at = room.move_actor(actor.position,at,2.0)-actor.position
	var final_shot: bool = str(effect.get("slot","")) == "ultimate" and bool(effect.get("last",false))
	var rail: bool = str(effect.get("slot","")) == "secondary"
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var scale: float = 1.8 if rail else 1.7 if final_shot else 1.35 if bool(effect.get("heavy",false)) else 1.0
	var variant: int = int(effect.get("variant",0))
	if str(effect.get("slot","")) == "basic": scale *= 1.24 if variant == 2 else .90 if variant == 1 else 1.0
	var length: float = (18.0+10.0*(1.0-t))*scale
	var end: Vector2 = at+dir*length
	end = at+(end-at)*room.blocked_fraction(actor.position+at,actor.position+end,1.0)
	var normal: Vector2 = dir.orthogonal()
	var dart := PackedVector2Array([at-dir*4,at+normal*9*scale,end,at-normal*9*scale])
	draw_colored_polygon(dart,Color("ffb13b",visible*.95))
	dart.append(dart[0])
	draw_polyline(dart,Color("87522a",visible*.9),2.8,true)
	draw_line(at,end,Color("fff4c8",visible),5.0 if rail else 3.8,true)
	if str(effect.get("slot","")) == "basic" and variant == 1:
		draw_line(at+normal*10,at+dir*12,Color("ffd97c",visible),3.2,true)
		draw_line(at-normal*10,at+dir*12,Color("ffd97c",visible),3.2,true)
	elif str(effect.get("slot","")) == "basic" and variant == 2:
		_segmented_ring(at,8+t*13,4,.8,Color("ffd45b",visible),3.6)
	if rail:
		for side in [-1.0,1.0]:
			draw_line(at+normal*side*8, end+normal*side*3,Color("fff3c3",visible),3.0,true)
		_segmented_ring(at,8+t*19,4,.85,Color("a9672a",visible),5.0)
		_segmented_ring(at,8+t*19,4,.85,Color("ffcf5b",visible),2.7)
	if not reduced:
		_sparks(at-dir*9,normal,3,8.0*scale,visible*.85,Color("ffd366"))
		var shell: Vector2 = at-dir*16+normal*(9+t*23)+Vector2(0,-sin(t*PI)*9+t*t*12)
		var casing_direction: Vector2 = dir.rotated(t*4)
		draw_line(shell-casing_direction*3,shell+casing_direction*3,Color("ffca58",visible),4.0,true)
		draw_line(at-dir*(12+t*19),at-dir*7,Color(IVORY,fade*.35),2.0,true)
	if str(effect.get("slot","")) == "ultimate":
		for index in int(effect.get("count",4)):
			var offset := Vector2(-18+index*8,-53)
			draw_line(offset,offset+Vector2(0,4),Color(tint,fade*(.9 if index <= int(effect.get("index",0)) else .16)),2,true)
	if final_shot:
		draw_arc(at,7+t*21,dir.angle()-PI*.4,dir.angle()+PI*.4,12,Color("fff2b9",visible),4.3,true)

func _draw_impact(at: Vector2, dir: Vector2, hero: String, heavy: bool, t: float, fade: float) -> void:
	var visible: float = minf(1.0,fade*1.4)
	var extent: float = (24.0 if heavy else 14.0)*(1.0+t*.3)
	if hero == "CH01":
		_sparks(at,dir,6,extent,visible,Color("ffb343"))
		for side in [-1.0,1.0]:
			var normal: Vector2 = dir.rotated(side*.85)
			draw_line(at+normal*5,at+normal*extent,Color("74372a",visible),6.5,true)
			draw_line(at+normal*5,at+normal*extent,Color("fff0b3",visible),3.5,true)
	elif hero == "CH02":
		draw_line(at-dir*extent*.6,at+dir*extent,Color("8d572e",visible),5.5,true)
		draw_line(at-dir*extent*.6,at+dir*extent,Color("fff3bb",visible),2.7,true)
		for side in [-1.0,1.0]:
			var normal: Vector2 = dir.orthogonal()*side
			draw_line(at+normal*4-dir*4,at+normal*extent*.7+dir*5,Color("ffc14f",visible),2.7,true)
	else:
		var diamond := PackedVector2Array([at+Vector2(0,-extent*.6),at+Vector2(extent*.45,0),at+Vector2(0,extent*.6),at-Vector2(extent*.45,0),at+Vector2(0,-extent*.6)])
		draw_polyline(diamond,Color("613783",visible),6.0,true)
		draw_polyline(diamond,Color("20e0e9",visible),3.2,true)
		_sparks(at,dir,4,extent*.8,visible,Color("cbfff0"))

func _sparks(at: Vector2, direction: Vector2, count: int, reach: float, opacity: float, tint: Color) -> void:
	for index in count:
		var ray := direction.rotated((index-float(count-1)*.5)*.64)
		var length: float = reach*(.65+.35*absf(sin(index*2.7)))
		draw_line(at+ray*length*.45,at+ray*length,Color(tint,opacity),1.7,true)

func _segmented_ring(at: Vector2, radius: float, segments: int, gap: float, tint: Color, width: float) -> void:
	for index in segments:
		var start: float = index*TAU/segments+gap*.5
		var finish: float = (index+1)*TAU/segments-gap*.5
		if finish > start:
			draw_arc(at,maxf(1.0,radius),start,finish,10,tint,width,true)
