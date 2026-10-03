extends "res://scripts/gameplay/bosses/boss_brain.gd"
const B10 = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const ACTIONS := {
	"sun":["sun_claw","solar_breath","sun_wing"],
	"mirror":["crystal_claw","mirror_shards","mirror_ring"],
	"comet":["comet_charge","comet_tail","comet_rain"],
	"resonance":["ring_pulse","tuning_fork","resonant_sweep"],
	"gate":["gate_claw","twin_gate_ray","gate_stars"],
	"meteor":["meteor_stomp","meteor_rain","meteor_tail"],
	"hydra":["nine_claws","star_breath","nine_tail","twin_starfall","nine_crown"]}
const NAMES := {"sun_claw":"日冕前爪","solar_breath":"日光吐息","sun_wing":"金翼扇流","crystal_claw":"镜鳞裂爪","mirror_shards":"鳞镜晶矢","mirror_ring":"晶鳞双环",
	"comet_charge":"彗轨冲刺","comet_tail":"长尾回旋","comet_rain":"彗轨星雨","ring_pulse":"双环律动","tuning_fork":"调律双线","resonant_sweep":"音鳞横扫",
	"gate_claw":"织门龙爪","twin_gate_ray":"双门星息","gate_stars":"星门对位","meteor_stomp":"陨鳞重踏","meteor_rain":"三曜陨星","meteor_tail":"陨星尾扫",
	"nine_claws":"九首前爪","star_breath":"九首星息","nine_tail":"九首扫庭","twin_starfall":"双门星落","nine_crown":"三曜归冠"}
var _cores_initialized := false
var _rebuild_at := 16.0
var _rebuild_index := -1
var _rebuild_used: Dictionary = {}
var _cast_serial := 0

func configure(value: Dictionary, seed_value: int = 0) -> void:
	super.configure(value,seed_value)
	_cores_initialized=false
	_rebuild_at=16
	_rebuild_index=-1
	_rebuild_used.clear()
	_cast_serial=0

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or delta<=0 or not _alive(actor) or not _alive(victim): return
	elapsed+=delta
	_last_actor=weakref(actor)
	actor.velocity=Vector2.ZERO
	var extension: Variant=B10.runtime(actor)
	if not extension is Object: return
	if not _cores_initialized:
		extension.bind_boss(actor,phase)
		_cores_initialized=true
	_update_weakpoint(actor,delta)
	var next_phase := _phase_for_ratio(_health_ratio(actor))
	if next_phase>phase:
		phase=next_phase
		_enter_phase(actor)
		return
	state_time=maxf(0,state_time-delta)
	if state==&"core_rebuild":
		_set_actor_state(actor,&"telegraph")
		if state_time<=0:
			extension.rebuild_core(actor,_rebuild_index)
			_rebuild_used[_rebuild_index]=true
			_rebuild_index=-1
			state=&"recovery"
			state_time=1.5
			state_duration=state_time
		return
	if state in [&"emerging",&"phase_shift",&"recovery"]:
		_set_actor_state(actor,&"emerging" if state==&"emerging" else &"recovery")
		if state_time<=0:
			if boss_id=="BO10" and elapsed>=_rebuild_at and not weakpoint_open():
				var destroyed: Array=extension.destroyed_core_indices(actor)
				for index: int in destroyed:
					if _rebuild_used.has(index): continue
					_rebuild_index=index
					_rebuild_at=elapsed+16
					state=&"core_rebuild"
					state_time=1.5
					state_duration=1.5
					command=B10.timed(B10.area(B10.base(definition,actor.position,victim.position),extension.core_position(actor,index),42,0,0),1.5,int(definition.difficulty),true)
					command.ability_name="星核重建 · 可打断"
					return
			_begin_action(actor,victim)
		elif state==&"recovery" and not weakpoint_open() and actor.position.distance_to(victim.position)>350 and actor.position.distance_to(Vector2(actor.room.layout.get("boss_spawn",actor.room.layout.get("dragon_spawn",actor.position))))<240:
			actor.velocity=actor.room.navigation_direction(actor.position,victim.position,float(definition.navigation_radius))*float(definition.move_speed)
	elif state==&"telegraph":
		actor.aim_direction=command.direction
		_set_actor_state(actor,&"telegraph")
		if state_time<=0:
			_cast_serial+=1
			command["cast_id"]="b10boss:%s:%d"%[boss_id,_cast_serial]
			state=&"locked"
			state_time=float(command.lock)
			state_duration=state_time
	elif state==&"locked":
		actor.aim_direction=command.direction
		_set_actor_state(actor,&"locked")
		if state_time<=0:
			actor.state=&"execute"
			actor.cast_enemy_skill(command.duplicate(true))
			_actions_used[current_action]=int(_actions_used.get(current_action,0))+1
			_action_ready_at[current_action]=elapsed+float(command.cooldown)
			_released_pose=command.duplicate(true)
			state=&"recovery"
			state_time=maxf(1.5,float(command.recovery))
			state_duration=state_time
			_recovery_elapsed=0
			_set_actor_state(actor,&"recovery")
	_recovery_elapsed+=delta

func _begin_action(actor: Node2D, victim: Node2D) -> void:
	var extension: Variant=B10.runtime(actor)
	if not extension.can_lock(actor):
		state=&"recovery"
		state_time=.3
		return
	var choices: Array=ACTIONS[str(definition.theme)]
	var chosen := ""
	for offset in choices.size():
		var action: String=choices[(action_index+offset)%choices.size()]
		if boss_id=="BO10" and action=="nine_tail" and int(definition.difficulty)<1: continue
		if boss_id=="BO10" and action=="twin_starfall" and int(definition.difficulty)<2: continue
		if boss_id=="BO10" and action=="nine_crown" and int(definition.difficulty)<4: continue
		if elapsed<float(_action_ready_at.get(action,0)): continue
		chosen=action
		action_index=(action_index+offset+1)%choices.size()
		break
	if chosen.is_empty():
		state=&"recovery"
		state_time=.5
		return
	current_action=chosen
	command=extension.constrain(actor,build_action(definition,chosen,actor.position,victim.position,phase,extension.portal_endpoints()))
	state=&"telegraph"
	state_time=float(command.tell)
	state_duration=state_time

static func build_action(p: Dictionary, action: String, origin: Vector2, target: Vector2, phase_value: int, portal_points: Array = []) -> Dictionary:
	var c := B10.base(p,origin,target)
	c.merge({"boss_id":p.boss_id,"action_id":action,"ability_id":str(p.boss_id)+":"+action,"ability_name":NAMES.get(action,action),"ability_name_en":action.replace("_"," "),
		"active":true,"b10_phase":phase_value,"cooldown":12.0,"range":360.0,"recovery":1.5,"tracks_target":false},true)
	var direction: Vector2=c.direction
	var tell_seconds := 1.3
	match action:
		"sun_claw","crystal_claw","gate_claw","nine_claws":
			c.merge({"range":180.0,"angle":2.0,"coefficient":120,"cooldown":7.0},true)
		"solar_breath","star_breath":
			c.merge({"shape":"line","range":360.0,"width":90.0,"coefficient":110,"cooldown":12.0},true)
			tell_seconds=1.4
		"sun_wing":
			c.merge({"shape":"cone","range":250.0,"angle":2.6,"coefficient":85,"cooldown":15.0,"recovery":2.0},true)
		"mirror_shards":
			c.merge({"kind":"projectile","shape":"line","range":360.0,"width":18.0,"coefficient":55,"count":3,"projectile_angles":[-28,0,28],"speed":320.0,"projectile_radius":8.0},true)
		"mirror_ring","ring_pulse","meteor_stomp":
			c.merge({"kind":"ground_area","shape":"circle","origin":origin,"target":origin,"radius":115.0,"coefficient":70,"cooldown":15.0,"recovery":2.0},true)
			var outer := B10.area(c,origin,235,70,1.1)
			outer.merge({"shape":"ring","inner_radius":130.0},true)
			c.followups.append(outer)
			tell_seconds=1.4
		"comet_charge":
			c.merge({"kind":"charge","shape":"line","range":260.0,"target":origin+direction*260,"travel_distance":260.0,"width":70.0,"radius":36.0,"coefficient":110,"duration":.75,"recovery":2.0},true)
			var tail := B10.child(c,"melee","cone",45,1.0)
			tail.merge({"origin":c.target,"direction":-direction,"target":c.target-direction*130,"range":130.0,"angle":2.4},true)
			c.followups.append(tail)
		"comet_tail","meteor_tail","nine_tail":
			c.merge({"origin":origin,"target":origin-direction*230,"direction":-direction,"range":230.0,"angle":PI,"coefficient":100,"cooldown":15.0},true)
		"comet_rain","meteor_rain","gate_stars","twin_starfall","nine_crown":
			var points: Array=[target-direction.orthogonal()*110,target+direction.orthogonal()*110]
			if action in ["gate_stars","twin_starfall"] and portal_points.size()>=2: points=portal_points.slice(0,2)
			if action in ["meteor_rain","nine_crown"]: points=[target-direction.orthogonal()*130,target,target+direction.orthogonal()*130]
			c.merge({"kind":"ground_area","shape":"circle","origin":points[0],"target":points[0],"radius":95.0,"coefficient":65 if points.size()==3 else 80,"cooldown":27.0 if action=="nine_crown" else 19.0,"recovery":2.5,"b10_cross_gate":action in ["gate_stars","twin_starfall"]},true)
			for i in range(1,points.size()):
				var fall := B10.area(c,points[i],95,int(c.coefficient),i*1.1)
				if action=="nine_crown": fall["core_index"]=i
				c.followups.append(fall)
			tell_seconds=1.8 if action=="nine_crown" else 1.5
		"tuning_fork":
			c.merge({"shape":"line","range":300.0,"width":35.0,"coefficient":65,"origin":origin-direction.orthogonal()*75},true)
			var second := B10.child(c,"melee","line",65,.9)
			second.origin=origin+direction.orthogonal()*75
			c.followups.append(second)
		"resonant_sweep":
			c.merge({"shape":"ring","origin":origin,"target":origin,"radius":230.0,"inner_radius":145.0,"ring_gap_degrees":100.0,"coefficient":95,"cooldown":15.0},true)
		"twin_gate_ray":
			c.merge({"shape":"line","range":320.0,"width":45.0,"coefficient":100,"b10_cross_gate":true},true)
			tell_seconds=1.5
	return B10.timed(c,tell_seconds,int(p.difficulty),true)

func _enter_phase(actor: Node2D) -> void:
	command.clear()
	_rebuild_used.clear()
	_rebuild_at=elapsed+16
	_rebuild_index=-1
	actor.boss_phase_started(phase,_health_ratio(actor))
	var extension: Variant=B10.runtime(actor)
	if extension is Object: extension.bind_boss(actor,phase)
	state=&"phase_shift"
	state_time=1.5
	state_duration=state_time

func incoming_damage_multiplier() -> float:
	if weakpoint_open(): return 1.15
	var actor: Node2D = _last_actor.get_ref() if _last_actor!=null else null
	var extension: Variant=B10.runtime(actor) if _alive(actor) else null
	var count: int=extension.boss_core_count(actor) if extension is Object else 0
	return 1.0-minf(.45,count*.15)

func on_damaged(actor: Node2D, context: Dictionary) -> void:
	if state==&"core_rebuild" and bool(context.get("interrupt",true)) and str(context.get("kind","primary")) not in ["burn","corrosion","bleed"]:
		_rebuild_used[_rebuild_index]=true
		_rebuild_index=-1
		command.clear()
		state=&"recovery"
		state_time=1.5
		state_duration=state_time

func cores_cleared(actor: Node2D) -> void:
	weakpoint="star_chest"
	weakpoint_time=5.0
	actor.boss_weakpoint_changed(true,weakpoint,5.0)
	# Already released attacks retain their source. Only this pending command is
	# cancelled before the advertised five-second chest opening.
	command.clear()
	state=&"recovery"
	state_time=5.0
	state_duration=5.0
