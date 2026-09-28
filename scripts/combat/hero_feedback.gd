class_name HeroFeedback
extends Node2D
## Presentation only. Callbacks originate from committed combat events; this
## node never damages, spends resources, aims attacks or changes their timing.

const AMBER := Color("eabb78")
const IVORY := Color("f5ebc9")
const CYAN := Color("78d9d1")
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

func observe_basic(kind: String, duration: float) -> void:
	if kind not in ["attack_windup","attack_strike"] or not is_instance_valid(actor):
		return
	_basic = kind
	_basic_age = 0.0
	_frozen_pose.clear()
	_basic_duration = duration
	_shot_direction = actor.aim_direction
	if kind != "attack_strike":
		return
	basic_events += 1
	var hero: String = actor.hero_id()
	_emit("swing" if hero == "CH01" else "muzzle",actor.position,actor.aim_direction,.23 if hero == "CH01" else .14,{"hero":hero,"radius":105.0,"arc":100.0,"heavy":false})

func cast_started(data: Dictionary, direction: Vector2, target: Vector2, serial: int) -> void:
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
	var details: Dictionary = {"hero":hero,"slot":slot,"radius":float(data.get("radius",65.0)),"arc":float(data.get("arc",360.0)),"heavy":slot == "secondary" or slot == "ultimate","last":index == count-1,"index":index,"count":count}
	if hero == "CH01":
		_emit("swing" if slot == "secondary" else "ground_break" if slot == "ultimate" else "brace" if slot == "f" else "rush",at,direction,.44 if slot == "ultimate" else .30,details)
	elif hero == "CH02":
		_emit("deploy" if slot == "f" else "muzzle",at,direction,.24 if slot == "ultimate" and index == count-1 else .16,details)
	else:
		_emit("muzzle" if slot == "q" else "deploy" if slot == "secondary" else "frost" if slot == "f" else "resonance",at,direction,.48 if slot == "ultimate" else .32,details)
	queue_redraw()

func impact(at: Vector2, direction: Vector2, source: String, critical: bool = false) -> void:
	if not is_instance_valid(actor):
		return
	impact_events += 1
	_emit("impact",at,direction,.18,{"hero":actor.hero_id(),"heavy":critical or source in ["secondary","ultimate"],"slot":source})

func deployment_pulse(kind: String, at: Vector2, radius: float) -> void:
	deployment_events += 1
	_emit("resonance" if kind == "field" else "frost" if kind == "trap" else "deploy",at,Vector2.RIGHT,.42 if kind == "field" else .25,{"hero":"CH03" if kind != "trap" else "CH02","radius":radius,"heavy":kind == "field","deployment":true})

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
	elif _basic == "attack_windup" and _basic_age < _basic_duration:
		result.phase = "windup"
		result.progress = _basic_age/maxf(.01,_basic_duration)
		result.charge = result.progress
	elif _basic == "attack_strike" and _basic_age < .29:
		result.phase = "release" if _basic_age < .09 else "recovery"
		result.progress = _basic_age/.09 if _basic_age < .09 else (_basic_age-.09)/.2
		result.direction = _shot_direction
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
			"swing":
				var arc: float = deg_to_rad(float(effect.get("arc",100.0)))
				var sweep: float = dir.angle()-arc*.5+arc*minf(1.0,t*1.8)
				for ribbon in range(3):
					draw_arc(at,radius-ribbon*5.0,maxf(dir.angle()-arc*.5,sweep-.52),sweep,18,Color(tint,fade*(.8-ribbon*.23)),4.8-ribbon*1.1,true)
				_sparks(at+Vector2.from_angle(sweep)*radius,dir,5,14.0,fade,tint)
			"ground_break":
				_segmented_ring(at,radius*(.22+.78*t),12,.23,Color(tint,fade*.75),3.2)
				for index in range(8):
					var ray := Vector2.from_angle(index*TAU/8.0+.22)
					draw_polyline(PackedVector2Array([at+ray*18,at+ray*radius*.34+ray.orthogonal()*6,at+ray*radius*.64]),Color(tint,fade*.45),2,true)
				_sparks(at,dir,8,36.0,fade,tint)
			"rush":
				for side in [-1.0,1.0]:
					var edge: Vector2 = dir.orthogonal()*side*22.0
					draw_line(at+edge-dir*52*(1-t),at+edge+dir*12,Color(tint,fade*.65),3,true)
			"brace":
				_segmented_ring(at,31+t*25,4,.7,Color(tint,fade*.75),4)
			"frost","resonance":
				_segmented_ring(at,radius*(.14+.86*t),12,.18,Color(CYAN,fade*.72),2.7)
				_segmented_ring(at,radius*maxf(.05,t-.13),8,.36,Color(IVORY,fade*.40),1.6)
				for index in range(6):
					var ray := Vector2.from_angle(index*TAU/6.0)
					draw_line(at+ray*radius*maxf(.05,t-.2),at+ray*radius*t,Color(CYAN,fade*.38),1.4,true)
			"deploy":
				_segmented_ring(at,18+t*24,3,.35,Color(tint,fade*.8),2.2)
			"impact": _draw_impact(at,dir,str(effect.get("hero","")),bool(effect.get("heavy",false)),t,fade)

func _draw_charge(pose: Dictionary, quality: float) -> void:
	var value: float = float(pose.get("charge",pose.progress))
	var at: Vector2 = actor.get_meta("hero_muzzle_local",Vector2(23,-33))
	var hero: String = actor.hero_id()
	if hero == "CH03":
		_segmented_ring(at,15.0-value*7.0,3,.3,Color(CYAN,(.3+value*.4)*quality),1.8)
		for index in range(4):
			var ray := Vector2.from_angle(index*TAU/4.0+value*.8)
			draw_line(at+ray*(23-value*10),at+ray*(18-value*10),Color(IVORY,.6*quality),1.6,true)
	elif hero == "CH02":
		var direction: Vector2 = pose.direction
		for side in [-1.0,1.0]:
			var offset: Vector2 = direction.orthogonal()*side*(9-value*5)
			draw_line(at+offset-direction*5,at+offset+direction*6,Color(IVORY,(.25+value*.55)*quality),1.4,true)
	else:
		_segmented_ring(Vector2(0,5),23,3,.8,Color(AMBER,(.2+value*.45)*quality),1.7)

func _draw_muzzle(effect: Dictionary, t: float, fade: float, tint: Color) -> void:
	var dir: Vector2 = effect.direction
	var at: Vector2 = actor.get_meta("hero_muzzle_local",dir*36+Vector2(0,-20))
	var room: Node2D = actor.room
	if not room.has_line_of_sight(actor.position,actor.position+at):
		at = room.move_actor(actor.position,at,2.0)-actor.position
	var final_shot: bool = str(effect.get("slot","")) == "ultimate" and bool(effect.get("last",false))
	var scale: float = 1.7 if final_shot else 1.35 if bool(effect.get("heavy",false)) else 1.0
	var length: float = (18.0+10.0*(1.0-t))*scale
	var end: Vector2 = at+dir*length
	end = at+(end-at)*room.blocked_fraction(actor.position+at,actor.position+end,1.0)
	if str(effect.get("hero","")) == "CH03":
		_segmented_ring(at,5+t*13,4,.4,Color(CYAN,fade),2.0)
		draw_line(at,end,Color(IVORY,fade*.9),2.3,true)
	else:
		var normal: Vector2 = dir.orthogonal()
		var dart := PackedVector2Array([at-dir*4,at+normal*4*scale,end,at-normal*4*scale])
		draw_colored_polygon(dart,Color(tint,fade*.83))
		draw_line(at,end,Color(IVORY,fade),2.0,true)
		_sparks(at-dir*9,normal,3,8.0*scale,fade*.65,tint)
		if str(effect.get("slot","")) == "ultimate":
			for index in int(effect.get("count",4)):
				var offset := Vector2(-18+index*8,-53)
				draw_line(offset,offset+Vector2(0,4),Color(tint,fade*(.9 if index <= int(effect.get("index",0)) else .16)),2,true)
		if final_shot:
			_segmented_ring(at,7+t*19,4,.65,Color(tint,fade*.65),2.8)

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
