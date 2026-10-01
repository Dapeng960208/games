class_name HeroFeedback
extends Node2D
## Presentation only. Callbacks originate from committed combat events; this
## node never damages, spends resources, aims attacks or changes their timing.

const AMBER := Color("eabb78")
const IVORY := Color("f5ebc9")
const CYAN := Color("78d9d1")
const COPPER := Color("df945a")
const VIOLET := Color("b7a1ec")
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

func configure(player: Node2D) -> void:
	actor = player
	name = "HeroFeedback"
	z_index = -1 # Below hero/enemy bodies and the enemy warning layer.
	set_process(false)
	set_physics_process(false)

func advance(delta: float) -> void:
	if not is_instance_valid(actor) or delta <= 0.0 or get_tree().paused:
		return
	var stopped: bool = float(actor.visual_hitstop) > 0.0
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
	_emit("swing" if hero == "CH01" else "muzzle" if hero == "CH02" else "arcane_release",actor.position,_basic_direction,.26 if hero == "CH01" else .14 if hero == "CH02" else .24,{"hero":hero,"slot":"basic","radius":105.0,"arc":100.0,"heavy":false})

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

func _draw() -> void:
	if not is_instance_valid(actor):
		return
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var quality: float = .52 if reduced else 1.0
	_draw_class_identity(quality)
	var pose: Dictionary = pose_state()
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
			"muzzle": _draw_muzzle(effect,t,fade,tint)
			"swing": _draw_cleave(at,dir,radius,float(effect.get("arc",100.0)),bool(effect.get("heavy",false)),t,fade,reduced)
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

func _draw_cleave(at: Vector2, dir: Vector2, radius: float, degrees: float, heavy: bool, t: float, fade: float, reduced: bool) -> void:
	# The broad axe face is present on contact, then thins into its copper wake.
	var arc: float = deg_to_rad(minf(degrees,220.0))
	var start: float = dir.angle()-arc*.5+arc*.16*t
	var finish: float = dir.angle()+arc*.5
	var thickness: float = (19.0 if heavy else 11.0)*(1.0-t*.65)
	var blade := PackedVector2Array()
	var points: int = 12 if reduced else 22
	for index in range(points+1):
		blade.append(at+Vector2.from_angle(lerpf(start,finish,float(index)/points))*radius)
	for index in range(points,-1,-1):
		blade.append(at+Vector2.from_angle(lerpf(start,finish,float(index)/points))*(radius-thickness))
	draw_colored_polygon(blade,Color(COPPER,fade*.29))
	# Copper ink separates the same cutting edge from the bright courtyard floor.
	draw_arc(at,radius,start,finish,points+1,Color("392a22",fade*.46),6.0,true)
	draw_arc(at,radius,start,finish,points+1,Color(AMBER,fade*.85),4.0 if heavy else 2.8,true)
	draw_arc(at,radius-thickness*.28,start+arc*.16,finish,points,Color(IVORY,fade*.92),1.8,true)
	if reduced: return
	draw_arc(at,radius-thickness-8.0,start,finish-arc*.16,points,Color(COPPER,fade*.4),2.0,true)
	var tip: Vector2 = Vector2.from_angle(finish)
	_sparks(at+tip*radius,tip,5 if heavy else 3,21.0 if heavy else 13.0,fade*.8,AMBER)

func _draw_fissure(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, reduced: bool, degrees: float = 360.0) -> void:
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
		draw_polyline(crack,Color("392a22",fade*.78),7.0,true)
		draw_polyline(crack,Color(COPPER,fade*.88),2.7,true)
		draw_polyline(crack,Color(IVORY,fade*.7),.9,true)
		if not reduced:
			var chip: Vector2 = at+ray*reach*.8+Vector2(0,-sin(t*PI)*13.0)
			draw_colored_polygon(PackedVector2Array([chip-ray*5,chip+ray*8,chip+ray.orthogonal()*5]),Color(AMBER,fade*.7))
	draw_arc(at,radius*(.28+.72*spread),dir.angle()-sector*.5 if frontal else 0.0,dir.angle()+sector*.5 if frontal else TAU,32,Color(AMBER,fade*.4),2.3,true)
	_sparks(at,dir,4 if reduced or frontal else 8,25.0,fade,IVORY)

func _draw_rush(at: Vector2, dir: Vector2, t: float, fade: float, reduced: bool) -> void:
	for side in [-1.0,1.0]:
		var edge: Vector2 = dir.orthogonal()*side*23.0
		draw_polyline(PackedVector2Array([at+edge-dir*74*(1.0-t),at+edge-dir*18,at+dir*31]),Color(COPPER,fade*.7),3.2,true)
		if not reduced:
			for index in 3:
				var dust: Vector2 = at+edge-dir*(25+index*20)+dir.orthogonal()*side*t*14
				draw_line(dust-dir*10,dust,Color(AMBER,fade*(.46-index*.1)),2.5,true)
	draw_arc(at,36.0,dir.angle()-.75,dir.angle()+.75,12,Color(IVORY,fade*.76),3.0,true)

func _draw_brace(at: Vector2, dir: Vector2, t: float, fade: float, reduced: bool) -> void:
	var front: Vector2 = at+dir*(21.0+t*13.0)
	var side: Vector2 = dir.orthogonal()
	var shield := PackedVector2Array([front+side*29-dir*8,front+side*25+dir*11,front+dir*23,front-side*25+dir*11,front-side*29-dir*8])
	draw_colored_polygon(shield,Color(COPPER,fade*.12))
	shield.append(shield[0])
	draw_polyline(shield,Color(AMBER,fade*.9),3.8,true)
	draw_polyline(PackedVector2Array([front+side*17,front+dir*12,front-side*17]),Color(IVORY,fade*.95),2.0,true)
	if not reduced:
		for sign in [-1.0,1.0]:
			var foot: Vector2 = at+side*sign*21
			draw_line(foot-dir*11,foot+dir*17,Color(COPPER,fade*.55),4.0,true)

func _draw_grenade_toss(effect: Dictionary, at: Vector2, t: float, fade: float, reduced: bool) -> void:
	var target: Vector2 = Vector2(effect.target)-actor.position
	var departure: Vector2 = at+Vector2(0,-25)
	var thrown: Vector2 = departure.lerp(target,t)+Vector2(0,-sin(t*PI)*35)
	var angle: float = t*TAU
	var axis: Vector2 = Vector2.from_angle(angle)
	var normal: Vector2 = axis.orthogonal()
	draw_colored_polygon(PackedVector2Array([thrown-axis*5-normal*4,thrown+axis*5-normal*4,thrown+axis*5+normal*4,thrown-axis*5+normal*4]),Color("e7b568",fade))
	draw_line(thrown-axis*3,thrown+axis*3,Color(IVORY,fade),1.5,true)
	if not reduced:
		var tail: float = maxf(0.0,t-.16)
		var previous: Vector2 = departure.lerp(target,tail)+Vector2(0,-sin(tail*PI)*35)
		draw_line(previous,thrown,Color(AMBER,fade*.25),1.5,true)

func _draw_grenade_burst(at: Vector2, radius: float, t: float, fade: float, reduced: bool) -> void:
	var spread: float = 1.0-pow(1.0-t,3.0)
	# The confirmed fuse explosion starts with a sharp white core, never ice.
	var core: float = 1.0-smoothstep(0.0,.25,t)
	draw_circle(at,11.0+spread*12,Color(IVORY,core*.7))
	draw_arc(at,radius*(.18+.82*spread),0,TAU,32,Color(AMBER,fade*.65),2.5,true)
	for index in (6 if reduced else 12):
		var ray: Vector2 = Vector2.from_angle(index*2.39996)
		var point: Vector2 = at+ray*radius*(.15+spread*.72)
		var length: float = (13.0+index%3*5)*(1.0-t)
		draw_line(point-ray*length,point,Color("ffd28b",fade*.9),2.2,true)
		if not reduced:
			draw_colored_polygon(PackedVector2Array([point+ray*4,point-ray*4+ray.orthogonal()*2.8,point-ray*3-ray.orthogonal()*2.8]),Color(COPPER,fade*.8))

func _draw_arcane_release(effect: Dictionary, t: float, fade: float, reduced: bool) -> void:
	var dir: Vector2 = effect.direction
	var at: Vector2 = actor.get_meta("hero_muzzle_local",dir*28+Vector2(0,-30))
	if not actor.room.has_line_of_sight(actor.position,actor.position+at):
		at = actor.room.move_actor(actor.position,at,2.0)-actor.position
	var power: float = 1.45 if str(effect.get("slot","")) == "q" else 1.0
	var reach: float = (12.0+t*15.0)*power
	_rune_polygon(at,reach,3,dir.angle()+PI*.5,Color(VIOLET,fade*.8),1.8)
	_segmented_ring(at,reach*.8,3,.55,Color(CYAN,fade*.9),1.8)
	draw_line(at,at+dir*(19.0+power*8)*(1.0-t*.5),Color(IVORY,fade),2.2,true)
	if reduced: return
	for index in 3:
		var ray: Vector2 = dir.rotated((index-1)*.85)
		var crystal: Vector2 = at+ray*reach
		_diamond(crystal,ray,5.0*(1-t*.45),Color(CYAN if index == 1 else VIOLET,fade*.85))

func _draw_rune_seed(at: Vector2, t: float, fade: float, reduced: bool) -> void:
	var reach: float = 18.0+t*26.0
	_rune_polygon(at,reach,6,PI/6,Color(VIOLET,fade*.85),1.8)
	_segmented_ring(at,reach*.74,3,.6,Color(CYAN,fade*.85),2.0)
	_diamond(at+Vector2(0,-10-t*16),Vector2.UP,10.0,Color(CYAN,fade*.65))
	if not reduced:
		for index in 3:
			var ray: Vector2 = Vector2.from_angle(index*TAU/3+PI/6)
			draw_line(at+ray*reach*.35,at+ray*reach,Color(IVORY,fade*.55),1.2,true)

func _draw_rune_collapse(at: Vector2, radius: float, t: float, fade: float, reduced: bool) -> void:
	var reach: float = radius*(.34+.66*(1.0-pow(1.0-t,3)))
	_rune_polygon(at,reach,6,PI/6,Color(VIOLET,fade*.75),2.3)
	_segmented_ring(at,reach*.70,6,.42,Color(CYAN,fade*.85),2.2)
	for index in (3 if reduced else 6):
		var ray: Vector2 = Vector2.from_angle(index*TAU/(3 if reduced else 6)+PI/6)
		var center: Vector2 = at+ray*reach*.78
		_diamond(center,ray,8.0*(1.0-t*.7),Color(IVORY,fade*.85))
		if not reduced:
			draw_line(at+ray*reach*.15,center,Color(VIOLET,fade*.35),1.3,true)

func _draw_spell_wave(at: Vector2, radius: float, t: float, fade: float, dome: bool, reduced: bool) -> void:
	var reach: float = radius*(.20+.80*(1.0-pow(1.0-t,2)))
	_segmented_ring(at,reach,6,.22,Color(CYAN,fade*.8),2.7 if dome else 1.8)
	_rune_polygon(at,reach*.86,6,PI/6,Color(VIOLET,fade*.58),1.8)
	if reduced: return
	for index in 6:
		var ray: Vector2 = Vector2.from_angle(index*TAU/6+PI/6)
		var point: Vector2 = at+ray*reach
		_diamond(point,ray,5.0,Color(IVORY,fade*.72))
		if dome:
			# Sparse arch ribs suggest a volume without covering enemy warnings.
			draw_polyline(PackedVector2Array([point,at+ray*reach*.5+Vector2(0,-reach*.20),at+Vector2(0,-reach*.27)]),Color(VIOLET,fade*.19),1.4,true)

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
	var charged := Color("c7b3ff") if energy == 3 else CYAN
	# Damage is immediate: the bright fractured core belongs to the first frame,
	# followed by an expanding thin wave. No delayed visual pretends to hit again.
	var release: float = 1.0 - pow(1.0-t,3.0)
	var core: float = 1.0-smoothstep(0.0,0.2,t)
	_segmented_ring(at,radius*(.18+.82*release),6,.28,Color(charged,fade*.85),2.5 if reduced else 3.3)
	if reduced:
		return
	var center := PackedVector2Array()
	# Filled polygons use unique vertices. sin(TAU) differs slightly from zero,
	# so a nearly repeated last vertex produces an invalid microscopic edge.
	for index in 6:
		center.append(at+Vector2.from_angle(index*TAU/6.0)*(8.0+energy*2.0+release*8.0))
	draw_colored_polygon(center,Color(IVORY,core*.66))
	for index in 6:
		var ray := Vector2.from_angle(index*TAU/6.0+.12)
		var side := ray.orthogonal()
		var tip: Vector2 = at+ray*radius*(.18+release*.68)
		var length: float = (9.0+energy*3.0)*(1.0-t)
		if length < 0.5:
			continue
		var shard := PackedVector2Array([tip+ray*length,tip+side*3.5,tip-ray*length*.65,tip-side*3.5])
		draw_line(at+ray*radius*.13,tip-ray*length,Color(charged,fade*.32),1.5,true)
		draw_colored_polygon(shard,Color(charged,fade*.55))
		shard.append(shard[0])
		draw_polyline(shard,Color(IVORY,fade*.9),1.4,true)

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
		_rune_polygon(at,reach,3,-value*1.2,Color(VIOLET,(.35+value*.5)*quality),1.8)
		_segmented_ring(at,reach*.75,3,.45,Color(CYAN,(.35+value*.5)*quality),1.7)
		for index in 3:
			var ray := Vector2.from_angle(index*TAU/3+value*.85)
			_diamond(at+ray*(25.0-value*9.0),ray,3.0+value*2.0,Color(IVORY,.66*quality))
		if slot in ["secondary","ultimate"] and not _cast.is_empty():
			var ground: Vector2 = Vector2(_cast.target)-actor.position
			var radius: float = 35.0 if slot == "secondary" else float(_cast.get("radius",180.0))*.65
			_rune_polygon(ground,radius,6,PI/6,Color(VIOLET,value*.27*quality),1.3)
		elif slot == "f":
			_rune_polygon(Vector2(0,5),28+value*15,6,PI/6,Color(VIOLET,value*.38*quality),1.5)
	elif hero == "CH02":
		var direction: Vector2 = pose.direction
		if str(pose.slot) == "secondary":
			var reach: Vector2 = direction * 780.0
			reach *= actor.room.blocked_fraction(actor.position + at, actor.position + at + reach, 1.0)
			draw_line(at, at + reach, Color(IVORY, (.10 + value * .20) * quality), 1.3, true)
			for side in [-1.0,1.0]:
				var normal: Vector2 = direction.orthogonal()*side
				draw_line(at+normal*7-direction*11,at+normal*7+direction*(5+value*20),Color(AMBER,value*.8*quality),2.0,true)
				if quality > .6:
					for index in 3:
						var coil: Vector2 = at-direction*(6+index*7)+normal*(5-value*2)
						draw_line(coil-direction*2,coil+direction*2,Color(IVORY,value*.75*quality),2.0,true)
		for side in [-1.0,1.0]:
			var offset: Vector2 = direction.orthogonal()*side*(9-value*5)
			draw_line(at+offset-direction*5,at+offset+direction*6,Color(IVORY,(.25+value*.55)*quality),1.4,true)
	else:
		var direction: Vector2 = pose.direction
		if str(pose.slot) == "f":
			draw_polyline(PackedVector2Array([direction*24-direction.orthogonal()*22,direction*37,direction*24+direction.orthogonal()*22]),Color(AMBER,(.2+value*.55)*quality),2.0,true)
		else:
			for side in [-1.0,1.0]:
				var edge: Vector2 = direction.orthogonal()*side*19
				draw_line(Vector2(0,8)+edge-direction*11,Vector2(0,8)+edge+direction*(4+value*13),Color(COPPER,(.2+value*.5)*quality),2.5,true)

func _draw_muzzle(effect: Dictionary, t: float, fade: float, tint: Color) -> void:
	var dir: Vector2 = effect.direction
	var at: Vector2 = actor.get_meta("hero_muzzle_local",dir*36+Vector2(0,-20))
	var room: Node2D = actor.room
	if not room.has_line_of_sight(actor.position,actor.position+at):
		at = room.move_actor(actor.position,at,2.0)-actor.position
	var final_shot: bool = str(effect.get("slot","")) == "ultimate" and bool(effect.get("last",false))
	var rail: bool = str(effect.get("slot","")) == "secondary"
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var scale: float = 1.8 if rail else 1.7 if final_shot else 1.35 if bool(effect.get("heavy",false)) else 1.0
	var length: float = (18.0+10.0*(1.0-t))*scale
	var end: Vector2 = at+dir*length
	end = at+(end-at)*room.blocked_fraction(actor.position+at,actor.position+end,1.0)
	var normal: Vector2 = dir.orthogonal()
	var dart := PackedVector2Array([at-dir*4,at+normal*4*scale,end,at-normal*4*scale])
	draw_colored_polygon(dart,Color(AMBER,fade*.7))
	draw_line(at,end,Color(IVORY,fade),2.0,true)
	if rail:
		for side in [-1.0,1.0]:
			draw_line(at+normal*side*5, end+normal*side*2,Color(IVORY,fade*.85),1.4,true)
		_segmented_ring(at,8+t*19,4,.85,Color(AMBER,fade*.6),1.7)
	if not reduced:
		_sparks(at-dir*9,normal,3,8.0*scale,fade*.5,tint)
		var shell: Vector2 = at-dir*16+normal*(9+t*23)+Vector2(0,-sin(t*PI)*9+t*t*12)
		var casing_direction: Vector2 = dir.rotated(t*4)
		draw_line(shell-casing_direction*3,shell+casing_direction*3,Color(AMBER,fade*.95),2.8,true)
		draw_line(at-dir*(12+t*19),at-dir*7,Color(IVORY,fade*.35),2.0,true)
	if str(effect.get("slot","")) == "ultimate":
		for index in int(effect.get("count",4)):
			var offset := Vector2(-18+index*8,-53)
			draw_line(offset,offset+Vector2(0,4),Color(tint,fade*(.9 if index <= int(effect.get("index",0)) else .16)),2,true)
	if final_shot:
		draw_arc(at,7+t*21,dir.angle()-PI*.4,dir.angle()+PI*.4,12,Color(IVORY,fade*.7),2.8,true)

func _draw_impact(at: Vector2, dir: Vector2, hero: String, heavy: bool, t: float, fade: float) -> void:
	var extent: float = (24.0 if heavy else 14.0)*(1.0+t*.3)
	if hero == "CH01":
		_sparks(at,dir,6,extent,fade,AMBER)
		for side in [-1.0,1.0]:
			var normal: Vector2 = dir.rotated(side*.85)
			draw_line(at+normal*5,at+normal*extent,Color(IVORY,fade*.8),2.4,true)
	elif hero == "CH02":
		draw_line(at-dir*extent*.6,at+dir*extent,Color(IVORY,fade*.9),1.6,true)
		for side in [-1.0,1.0]:
			var normal: Vector2 = dir.orthogonal()*side
			draw_line(at+normal*4-dir*4,at+normal*extent*.7+dir*5,Color(AMBER,fade*.65),1.3,true)
	else:
		var diamond := PackedVector2Array([at+Vector2(0,-extent*.6),at+Vector2(extent*.45,0),at+Vector2(0,extent*.6),at-Vector2(extent*.45,0),at+Vector2(0,-extent*.6)])
		draw_polyline(diamond,Color(CYAN,fade*.85),1.8,true)
		_sparks(at,dir,4,extent*.8,fade*.65,IVORY)

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
