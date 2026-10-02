extends RefCounted
## Small B05 extension of the common collision/runtime. All effects are finite,
## room-owned and cancellable. Helpers never manufacture rewards or recursive hits.
const Skills = preload("res://scripts/combat/b05_enemy_skills.gd")
const Props = preload("res://scripts/combat/combat_properties.gd")
var host: Node2D
var effects: Array[Dictionary] = []
var healed: Dictionary = {}
var hit_receipts: Dictionary = {}
var summon_attempts: Dictionary = {}
var clock := 0.0
var serial := 0

func configure(runtime: Node2D) -> void:
	host = runtime

func support_targets(caster: Node2D, command: Dictionary) -> Array:
	var result: Array = []
	var container: Variant = Props.read(host.room,"enemies")
	if not container is Node: return result
	var candidates: Array[Node2D] = []
	for node: Node in container.get_children():
		if not node is Node2D or node==caster or not eligible(node): continue
		if caster.position.distance_to(node.position)>float(command.get("range",240)) or not host._line_clear(caster.position,node.position): continue
		if str(command.kind)=="b05_heal":
			var hp: Variant = Props.read(node,"health")
			if hp.current>=hp.maximum or float(healed.get(node.get_instance_id(),0))>=float(hp.maximum)*.25: continue
		candidates.append(node)
	candidates.sort_custom(func(a: Node2D,b: Node2D) -> bool: return caster.position.distance_squared_to(a.position)<caster.position.distance_squared_to(b.position))
	for node: Node2D in candidates.slice(0,int(command.get("target_count",1))): result.append(weakref(node))
	return result

func eligible(node: Node2D) -> bool:
	return host._alive(node) and str(Props.read(node,"actor_kind",""))=="enemy" and str(Props.read(node,"rank","normal"))!="boss" and not node.has_meta("enemy_skill_anchor") and str(Props.read(node,"enemy_id","")).begins_with("B05-M")

func prepare(caster: Node2D, command: Dictionary) -> Dictionary:
	var result := Skills.freeze_damage(command,Props.read(caster,"profile",{}))
	if result.is_empty(): return {}
	result["owner"] = weakref(caster)
	result["owner_id"] = caster.get_instance_id()
	if not result.has("cast_id"):
		serial += 1
		result["cast_id"] = "b05:%d:%d" % [caster.get_instance_id(),serial]
	# One flower mark strengthens the next submitted attack, never every missile.
	if int(result.get("coefficient",0))>0 and not bool(result.get("derived",false)):
		for effect: Dictionary in effects.duplicate():
			if effect.kind=="flower_mark" and effect.target.get_ref()==caster and _valid(effect):
				var profile_value: Dictionary = Props.read(caster,"profile",{})
				result.coefficient = int(result.coefficient)+20
				result = Skills.freeze_damage(result,profile_value)
				effects.erase(effect)
				break
	return result

func execute(command: Dictionary) -> bool:
	var caster: Node2D = host._owner(command)
	if not host._alive(caster): return true
	if bool(command.get("root_required",false)) and not Skills.connected(caster): return true
	var kind := str(command.kind)
	if kind=="ground_area" and str(command.get("caster_enemy_id",""))=="B05-M02" and bool(command.get("lob",false)) and not bool(command.get("derived",false)) and not bool(command.get("b05_landed",false)):
		var landing:=command.duplicate(true)
		landing["b05_landed"]=true
		landing["origin"]=landing.target
		landing["remaining"]=.35
		host.jobs.append(landing)
		var body: Variant=Props.read(caster,"body_visual")
		var outlet: Dictionary=body.b05_visual_outlet() if body is Node2D and body.has_method("b05_visual_outlet") else {}
		_add(command,{"kind":"lob_visual","remaining":.35,"duration":.35,"visual_start":outlet.get("position",caster.position+Vector2(0,-45))})
		command["_b05_defer_followups"]=true
		return true
	if kind=="b05_heal":
		for ref: WeakRef in command.get("b05_target_refs",[]):
			var ally: Node2D = ref.get_ref()
			if not eligible(ally) or caster.position.distance_to(ally.position)>240 or not host._line_clear(caster.position,ally.position): continue
			var hp: Variant = Props.read(ally,"health")
			var before: float = hp.current
			var amount: float = limit_external_heal(ally,roundf(float(hp.maximum)*.06))
			if amount<=0: continue
			ally.heal(amount)
			var actual: float = maxf(0,float(hp.current)-before)
			if actual<=0: continue
			record_external_heal(ally,actual)
			if int(command.difficulty)>=2:
				if ally.has_method("clear_ordinary_slow"): ally.clear_ordinary_slow()
			if int(command.difficulty)>=4: ally.status.grant_guard(float(hp.maximum)*.06,3.0,"b05_dew",float(hp.maximum))
			host._flash(command,Color("8ad8cb"))
	elif kind=="b05_share":
		var refs: Array = command.get("b05_target_refs",[])
		if refs.size()!=2 or not eligible(refs[0].get_ref()) or not eligible(refs[1].get_ref()): return true
		if refs[0].get_ref().position.distance_to(refs[1].get_ref().position)>300: return true
		_add(command,{"kind":"share","targets":refs,"remaining":5.0})
		if int(command.difficulty)>=4: caster.status.grant_guard(float(caster.health.maximum)*.1,5,"b05_weaver",float(caster.health.maximum))
	elif kind=="b05_resin":
		_add(command,{"kind":"resin","target":weakref(caster),"remaining":3.0,"capacity":float(command.shield_hp)})
	elif kind=="b05_root_guard":
		caster.status.grant_guard(float(caster.health.maximum)*.1,1.3,"b05_ancient_root",float(caster.health.maximum))
		_add(command,{"kind":"root_guard","target":weakref(caster),"remaining":1.3})
	elif kind=="b05_mode":
		var mechanism: Variant = Skills.mechanics(caster)
		if mechanism is Object and mechanism.has_method("set_well_mode") and mechanism.set_well_mode(caster,str(command.mode),6.0):
			if int(command.difficulty)>=2:
				var refs := support_targets(caster,{"kind":"mark","range":220.0,"target_count":1})
				if not refs.is_empty():
					for old: Dictionary in effects.duplicate():
						if old.kind=="flower_mark" and old.target.get_ref()==refs[0].get_ref(): effects.erase(old)
					_add(command,{"kind":"flower_mark","target":refs[0],"remaining":6.0})
			if int(command.difficulty)>=4: _add(command,{"kind":"exposed","target":weakref(caster),"remaining":3.0})
	elif kind=="b05_reposition":
		var mechanism: Variant = Skills.mechanics(caster)
		var well: Dictionary = mechanism.nearest_active_well(caster.position) if mechanism is Object and mechanism.has_method("nearest_active_well") else {}
		if not well.is_empty():
			var tangent: Vector2 = (caster.position-Vector2(well.position)).orthogonal().normalized()
			caster.position = host.room.move_actor(caster.position,tangent*80, float(Props.read(caster,"navigation_radius",18)))
	elif kind=="b05_decoy":
		var visual := command.duplicate()
		visual.merge({"remaining":1.5,"color":Color("87cbbc"),"decoy":false},true)
		host.visuals.append(visual)
	elif kind in ["b05_bud","b05_shell"]:
		_spawn_growth(command)
	elif kind=="b05_summon":
		_summon(command)
	else:
		return false
	return true

func released(command: Dictionary) -> void:
	if bool(command.get("_b05_defer_followups",false)): return
	# Called exactly once after a command reaches its release. Follow-ups copy
	# frozen geometry, have their own honest damage coefficient and no recursion.
	var caster: Node2D = host._owner(command)
	if not host._alive(caster): return
	for authored: Dictionary in command.get("followups",[]):
		if host.active_effect_count()>=host.MAX_EFFECTS: break
		var follow := authored.duplicate(true)
		follow["cast_id"] = str(command.cast_id)
		follow["b05_phase"] = int(command.get("b05_phase",1))
		follow = prepare(caster,follow)
		if follow.is_empty(): continue
		follow["remaining"] = maxf(0,float(follow.get("delay",0)))
		if float(follow.remaining)>0: host.jobs.append(follow)
		else: host._execute(follow)
	if bool(command.get("b05_resin_shove",false)) and int(command.get("difficulty",0))>=2:
		var area := Skills.slow_area(command,Vector2(command.origin)+Vector2(command.direction)*80,40,2,0)
		area = prepare(caster,area)
		host._execute(area)

func motion_finished(motion: Dictionary, completed: bool) -> void:
	var caster: Node2D = host._owner(motion)
	if not host._alive(caster): return
	var after := str(motion.get("after_motion",""))
	var d := int(motion.get("difficulty",0))
	if after=="moss" and completed:
		if d>=2:
			var trail := Skills.child(motion,"ground_area","line",0,0)
			trail.merge({"origin":motion.start,"points":[motion.start,caster.position],"range":Vector2(motion.start).distance_to(caster.position),"width":30.0,"duration":2.0,"tick_interval":.5,"status":{"id":"slow","magnitude":.8,"duration":.8}},true)
			host._execute(prepare(caster,trail))
		if d>=4:
			var hop := Skills.child(motion,"charge","line",0,.05)
			hop.merge({"origin":caster.position,"target":caster.position-Vector2(motion.direction)*80,"direction":-Vector2(motion.direction),"travel_distance":80.0,"range":80.0,"duration":.25,"landing_only":true,"remaining":.05,"harmless":true},true)
			host.jobs.append(prepare(caster,hop))
	elif after=="leaf" and completed and d>=2:
		var leaf := Skills.child(motion,"projectile","line",40,.15)
		leaf.merge({"origin":caster.position,"target":caster.position+Vector2(motion.direction)*200,"range":200.0,"count":1,"speed":380.0,"remaining":.15},true)
		host.jobs.append(prepare(caster,leaf))
	elif after=="roll" and not completed and d>=2 and motion.has("rebound_point"):
		var rebound := Skills.child(motion,"charge","line",50,.1)
		rebound.merge({"origin":caster.position,"target":motion.rebound_point,"direction":-Vector2(motion.direction),"range":110.0,"travel_distance":110.0,"duration":.28,"after_motion":"roll_end","remaining":.1},true)
		host.jobs.append(prepare(caster,rebound))
	elif after=="roll_end" and completed and d>=4:
		var thorns := Skills.slow_area(motion,caster.position,38,2,0)
		host._execute(prepare(caster,thorns))

func projectile_landed(shot: Dictionary) -> void:
	if not bool(shot.get("b05_shells",false)) or int(shot.get("b05_projectile_index",1))==1: return
	var caster: Node2D = host._owner(shot)
	if not host._alive(caster): return
	var shell := Skills.child(shot,"b05_shell","cone",30,0)
	shell.merge({"origin":shot.position,"target":shot.position,"range":60.0,"radius":60.0,"angle":PI*.5,"direction":Vector2(shot.direction).rotated(-PI*.5 if int(shot.get("b05_projectile_index",0))==0 else PI*.5),"duration":3.0,"anchor_health":float(caster.health.maximum)*.1,"fires":int(shot.difficulty)>=4},true)
	_spawn_growth(prepare(caster,shell))

func allow_hit(victim: Node2D, command: Dictionary) -> bool:
	if bool(command.get("harmless",false)): return false
	var cap: int = int(command.get("b05_hit_cap",0))
	if cap<=0: return true
	var key: String = str(command.get("cast_id",""))+":"+str(victim.get_instance_id())
	return int(hit_receipts.get(key,{}).get("count",0))<cap

func confirmed_hit(victim: Node2D, command: Dictionary) -> void:
	if int(command.get("b05_hit_cap",0))>0:
		var key: String = str(command.cast_id)+":"+str(victim.get_instance_id())
		hit_receipts[key] = {"count":int(hit_receipts.get(key,{}).get("count",0))+1,"expires":clock+8}
	if float(command.get("b05_pull",0))>0:
		var displacement: Vector2 = victim.position.direction_to(Vector2(command.target))*float(command.b05_pull)
		var radius: float = host._radius(victim,12)
		displacement *= host._blocked(victim.position,victim.position+displacement,radius)
		victim.position = host.room.move_actor(victim.position,displacement,radius)

func filter_damage(target: Node2D, amount: float, kind: StringName, direction: Vector2, damage_type: String) -> float:
	if kind==&"b05_share": return amount
	var value := amount
	if damage_type!="true" and bool(target.get_meta("b05_leaf_guard",false)): value*=.8
	for effect: Dictionary in effects.duplicate():
		if not _valid(effect): continue
		if effect.kind=="exposed" and effect.target.get_ref()==target: value*=1.15
		if effect.kind=="resin" and effect.target.get_ref()==target and damage_type!="true" and not direction.is_zero_approx() and direction.normalized().dot(Vector2(effect.direction))<=-cos(PI/3):
			var reduced: float = minf(value*.35,float(effect.capacity))
			value-=reduced
			effect.capacity = float(effect.capacity)-reduced
			if float(effect.capacity)<=0:
				effects.erase(effect)
				if int(effect.get("difficulty",0))>=4:
					var shards := Skills.area(effect,target.position,80,40,.6)
					shards = prepare(target,shards)
					shards["remaining"] = .6
					host.jobs.append(shards)
		if effect.kind=="share":
			var a: Node2D = effect.targets[0].get_ref()
			var b: Node2D = effect.targets[1].get_ref()
			if target!=a and target!=b: continue
			var other: Node2D = b if target==a else a
			var shared: float = roundf(value*.2)
			if shared>0 and other.has_method("take_damage"):
				var accepted: bool = other.take_damage(shared,&"b05_share",Vector2.ZERO,{"damage_type":"true","damage_source":"b05_share","equipment_eligible":false,"proc_depth":1,"interrupt":false})
				if accepted: value-=shared
			break
	return maxf(0,value)

func movement_multiplier(actor: Node2D) -> float:
	var result := 1.0
	for effect: Dictionary in effects:
		if not _valid(effect): continue
		if effect.kind=="share" and int(effect.get("difficulty",0))>=2:
			for ref: WeakRef in effect.targets:
				if ref.get_ref()==actor: result=maxf(result,1.08)
		if effect.kind=="briar_haste" and effect.target.get_ref()==actor: result=maxf(result,1.08)
	var mechanism: Variant = Skills.mechanics(actor)
	if mechanism is Object and mechanism.has_method("nearest_active_well") and Skills.connected(actor):
		var well: Dictionary = mechanism.nearest_active_well(actor.position)
		if str(well.get("mode",""))=="speed": result=maxf(result,1.08)
	return result

func advance(delta: float) -> void:
	clock+=delta
	for key: String in hit_receipts.keys():
		if float(hit_receipts[key].expires)<=clock: hit_receipts.erase(key)
	for id in healed.keys():
		if not is_instance_valid(instance_from_id(id)): healed.erase(id)
	for effect: Dictionary in effects.duplicate():
		if not _valid(effect):
			_remove(effect)
			continue
		effect.remaining = float(effect.remaining)-delta
		if effect.kind=="root_guard" and not Skills.connected(effect.target.get_ref()):
			effect.target.get_ref().status.guards.erase("b05_ancient_root")
			_remove(effect)
			continue
		if effect.kind in ["bud","shell"] and bool(effect.get("fires",false)):
			effect.next_fire = float(effect.next_fire)-delta
			while float(effect.next_fire)<=0 and int(effect.get("shots",0))<int(effect.fire_limit):
				effect.shots = int(effect.get("shots",0))+1
				effect.next_fire = float(effect.next_fire)+2.0
				var strike := effect.duplicate(true)
				strike.kind = "melee"
				strike.erase("anchor_ref")
				strike.erase("followups")
				host._execute(strike)
		if float(effect.remaining)<=0: _remove(effect)

func tick_hazard(area: Dictionary) -> void:
	if not bool(area.get("b05_briar_haste",false)): return
	var container: Variant = Props.read(host.room,"enemies")
	if not container is Node: return
	for node: Node in container.get_children():
		if node is Node2D and eligible(node) and host.shape_contains(area,node.position,host._radius(node,18)):
			var found := false
			for old: Dictionary in effects:
				if old.kind=="briar_haste" and old.target.get_ref()==node: old.remaining=2.0; found=true
			if not found: _add(area,{"kind":"briar_haste","target":weakref(node),"remaining":2.0})

func cancel_owner(caster: Node2D) -> void:
	for effect: Dictionary in effects.duplicate():
		if int(effect.get("owner_id",0))==caster.get_instance_id(): _remove(effect)

func reset() -> void:
	for effect: Dictionary in effects.duplicate(): _remove(effect)
	healed.clear()
	hit_receipts.clear()
	summon_attempts.clear()
	clock=0
	serial=0

func _spawn_growth(command: Dictionary) -> void:
	var caster: Node2D = host._owner(command)
	var kind: String = "bud" if command.kind=="b05_bud" else "shell"
	var owned: Array[Dictionary] = []
	for effect: Dictionary in effects:
		if effect.kind==kind and int(effect.owner_id)==caster.get_instance_id(): owned.append(effect)
	while owned.size()>=int(command.get("max_buds",2)): _remove(owned.pop_front())
	var anchor: Node2D = host._spawn_anchor(command,Vector2(command.origin),float(command.anchor_health),"b05_"+kind)
	if not is_instance_valid(anchor): return
	if Props.read(anchor,"reward_enabled")!=null: anchor.reward_enabled=false
	_add(command,{"kind":kind,"anchor_ref":weakref(anchor),"remaining":float(command.get("duration",4)),"next_fire":2.0 if kind=="bud" else 1.0,"fire_limit":2 if kind=="bud" else 1,"shots":0})

func _summon(command: Dictionary) -> void:
	var caster: Node2D = host._owner(command)
	var id: int = caster.get_instance_id()
	if int(summon_attempts.get(id,0))>=2 or not host.room.has_method("spawn_enemy_summon"): return
	summon_attempts[id] = int(summon_attempts.get(id,0))+1
	var owned: Array = host.summon_owners.get(id,[])
	for ref: WeakRef in owned.duplicate():
		if not host._alive(ref.get_ref()): owned.erase(ref)
	for i in range(mini(2,2-owned.size())):
		var container: Variant = Props.read(host.room,"enemies")
		if container is Node and host._live_child_count(container)>=18: break
		var at: Vector2 = Vector2(command.target)+Vector2(command.direction).orthogonal()*(-40 if i==0 else 40)
		var child: Node2D = host.room.spawn_enemy_summon(caster,"B05-M02",at)
		if not is_instance_valid(child): continue
		child.reward_enabled=false
		child.owner_enemy=weakref(caster)
		child.health.reset(roundf(float(child.health.maximum)*.5),2)
		owned.append(weakref(child))
	host.summon_owners[id]=owned

func _add(command: Dictionary, values: Dictionary) -> void:
	if host.active_effect_count()>=host.MAX_EFFECTS: return
	var effect := command.duplicate(true)
	effect.merge(values,true)
	effects.append(effect)

func _valid(effect: Dictionary) -> bool:
	if not host._owner_alive(effect) or float(effect.get("remaining",0))<=0: return false
	if effect.has("target") and effect.target is WeakRef and not host._alive(effect.target.get_ref()): return false
	if effect.has("anchor_ref") and not host._alive(effect.anchor_ref.get_ref()): return false
	if effect.kind=="share":
		var a: Node2D = effect.targets[0].get_ref()
		var b: Node2D = effect.targets[1].get_ref()
		return eligible(a) and eligible(b) and a.position.distance_to(b.position)<=300 and host._line_clear(a.position,b.position)
	return true

func _remove(effect: Dictionary) -> void:
	effects.erase(effect)
	if effect.has("anchor_ref"):
		var anchor: Node2D = effect.anchor_ref.get_ref()
		if is_instance_valid(anchor): anchor.queue_free()

func draw(canvas: Node2D) -> void:
	for effect: Dictionary in effects:
		if not _valid(effect): continue
		var color := Color("8acac4")
		if effect.kind=="lob_visual":
			var t: float=clampf(1-float(effect.remaining)/float(effect.duration),0,1)
			var at: Vector2=Vector2(effect.visual_start).lerp(Vector2(effect.target),t)+Vector2(0,-45*sin(PI*t))
			canvas.draw_circle(at,7,Color("e8b17f"))
			canvas.draw_arc(at,8,0,TAU,16,Color("5c844b"),2,true)
		elif effect.kind=="share":
			canvas.draw_line(effect.targets[0].get_ref().position,effect.targets[1].get_ref().position,color,3,true)
		elif effect.kind in ["flower_mark","exposed","resin"]:
			var target: Node2D = effect.target.get_ref()
			canvas.draw_arc(target.position,30,0,TAU,24,Color("ffac82") if effect.kind=="exposed" else color,3,true)
		elif effect.kind in ["bud","shell"]:
			var warning := effect.duplicate(true)
			warning.shape = "line" if effect.kind=="bud" else "cone"
			host._draw_shape(warning,Color(.95,.4,.3,.08),Color("ed9b75"))

func watch_anchor(anchor: Node2D) -> void:
	var hp: Variant=Props.read(anchor,"health")
	if hp is Object and hp.has_signal("depleted"):
		hp.connect("depleted",_anchor_destroyed.bind(weakref(anchor)),CONNECT_ONE_SHOT)

func _anchor_destroyed(reference: WeakRef) -> void:
	var anchor: Node2D=reference.get_ref()
	if not is_instance_valid(anchor): return
	var context: Dictionary=Props.read(anchor,"last_damage_context",{})
	if not bool(context.get("equipment_eligible",false)) and context.get("attacker_stats",{}).is_empty(): return
	var player: Variant=Props.read(host.room,"player")
	if player is Node2D and player.has_method("notify_hostile_destructible_destroyed"):
		player.notify_hostile_destructible_destroyed("b05_growth:%d"%anchor.get_instance_id())

func limit_external_heal(target: Node2D, requested: float) -> float:
	var maximum: float=float(Props.read(Props.read(target,"health"),"maximum",0))
	return maxf(0,minf(requested,minf(roundf(maximum*.08),roundf(maximum*.25)-float(healed.get(target.get_instance_id(),0)))))

func record_external_heal(target: Node2D, actual: float) -> void:
	if actual>0: healed[target.get_instance_id()]=float(healed.get(target.get_instance_id(),0))+actual
