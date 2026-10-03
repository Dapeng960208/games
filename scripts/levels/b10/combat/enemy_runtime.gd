extends RefCounted
## Finite final-court extension. Common runtime owns damage sweeps and warning
## jobs; this owns cores, one-layer echoes and interruptible support recipients.
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
var host: Node2D
var clock := 0.0
var serial := 0
var cores: Array[Dictionary] = []
var links: Dictionary = {}
var effects: Array[Dictionary] = []
var hit_receipts: Dictionary = {}
var echo_ready: Dictionary = {}
var repaired: Dictionary = {}
var boss_ref: WeakRef
var current_phase := 0
var exposed_phase := 0
var ordinary_initialized := false

func configure(runtime: Node2D) -> void:
	host=runtime

func _b10_room() -> bool:
	return is_instance_valid(host) and is_instance_valid(host.room) and str(host.room.layout.get("biome_id",""))=="B10"

func _spec() -> Dictionary:
	return host.room.layout.get("b10_geometry",{}) if _b10_room() else {}

func advance(delta: float) -> void:
	clock+=delta
	if not _b10_room(): return
	if str(host.room.layout_id)!="BO10" and not ordinary_initialized:
		var first: Node2D=_first_enemy()
		if first!=null:
			ordinary_initialized=true
			var raw: Array=_spec().get("star_cores",[])
			var frontliner: Dictionary=Skills.profile("B10-M01",int(first.profile.enemy_level),int(host.room.difficulty))
			for i in mini(raw.size(),1 if int(host.room.difficulty)<2 else 2):
				_spawn_core(first,i,roundf(float(frontliner.max_hp)*.6),false)
	for index in cores.size():
		var core: Dictionary=cores[index]
		if bool(core.boss) or _core_alive(index) or clock<float(core.get("restore_at",INF)): continue
		var owner_actor: Node2D=_first_enemy()
		if owner_actor!=null: _spawn_core(owner_actor,index,float(core.health),false)
	for effect: Dictionary in effects.duplicate():
		effect.remaining=float(effect.remaining)-delta
		var target: Node2D=effect.target.get_ref()
		if effect.remaining<=0 or not host._alive(target):
			effects.erase(effect)
			if effect.remaining<=0 and host._alive(target) and str(effect.kind) in ["stance","guard"]:
				_recover(target,1.2)
	# Receipts are bounded by recent combat time, not by the chapter duration.
	for key: String in hit_receipts.keys():
		if clock-float(hit_receipts[key])>12: hit_receipts.erase(key)
	for id: int in links.keys():
		if not host._alive(instance_from_id(id)): links.erase(id)

func _first_enemy() -> Node2D:
	for child: Node in host.room.enemies.get_children():
		if child is Node2D and host._alive(child) and str(Props.read(child,"enemy_id","")).begins_with("B10-M"): return child
	return null

func can_lock(caster: Node2D) -> bool:
	var active: Dictionary={}
	for child: Node in host.room.enemies.get_children():
		if child==caster or not host._alive(child): continue
		if str(Props.read(child,"state","")) in ["telegraph","locked","windup"]: active[child.get_instance_id()]=true
	for job: Dictionary in host.jobs:
		if not bool(job.get("b10_command",false)) or int(job.get("coefficient",0))<=0: continue
		if int(job.get("owner_id",0))==caster.get_instance_id(): return false
		active[int(job.get("owner_id",0))]=true
	return active.size()<2

func portal_endpoints() -> Array:
	var result: Array=[]
	for gate: Dictionary in _spec().get("gates",[]): result.append(Geometry.world_point(gate.position))
	return result

func constrain(caster: Node2D, value: Dictionary) -> Dictionary:
	var c := value.duplicate(true)
	var room_id: String=str(host.room.layout_id)
	c["source_zone"]=Geometry.zone_at(room_id,Vector2(c.origin))
	c["ranged_direct_damage"]=str(c.kind)=="projectile" or (str(c.shape)=="line" and str(c.kind)=="melee")
	if bool(c.get("b10_cross_gate",false)):
		var points := portal_endpoints()
		if points.size()>=2 and str(c.shape)=="line":
			var start: Vector2=points[0]
			var end: Vector2=host.room.clamp_actor(start+Vector2(c.direction)*float(c.range),5)
			var other_end: Vector2=host.room.clamp_actor(Vector2(points[1])+Vector2(c.direction)*float(c.range),5)
			c.origin=start
			c.target=end
			c.direction=start.direction_to(end)
			c.range=start.distance_to(end)
			c.points=[start,end]
			c["gate_endpoints"]=[start,points[1]]
			c["paths"]=[[start,end],[points[1],other_end]]
			for follow: Dictionary in c.get("followups",[]):
				if str(follow.shape)=="circle": follow.merge({"origin":points[1],"target":points[1]},true)
	# During accepted transit, a new tracked landing attack cannot be placed
	# onto the reserved landing disk. Existing published commands are untouched.
	var player: Variant=Props.read(host.room,"player")
	if player is Node2D and float(player.get_meta("b10_portal_landing_until",0))>float(Props.read(host.room,"elapsed",clock)) and str(c.kind)=="ground_area":
		var landing: Vector2=player.get_meta("b10_portal_destination",player.position)
		if Vector2(c.target).distance_to(landing)<100+float(c.get("radius",0)):
			c.target=host.room.clamp_actor(landing+Vector2(180,0),20)
			if str(c.shape) in ["circle","ring"]: c.origin=c.target
	var refs: Array=c.get("b10_target_refs",[])
	if not refs.is_empty() and host._alive(refs[0].get_ref()):
		c.target=refs[0].get_ref().position
		if str(c.kind)=="b10_transfer":
			var gates:=portal_endpoints()
			var destination := caster.position+Vector2(0,120)
			for point: Vector2 in gates:
				if point.distance_to(c.target)>80 and (not player is Node2D or point.distance_to(player.position)>150): destination=point; break
			c["transfer_destination"]=host.room.clamp_actor(destination,18)
			c["targets"]=[c.target,c.transfer_destination]
			c["paths"]=[[c.target,c.transfer_destination]]
	if str(c.get("caster_enemy_id",""))=="B10-M07":
		# Both segments are fixed before the first warning. Clamp only while
		# authoring this snapshot, never retarget the released charge.
		var middle: Vector2=host.room.clamp_actor(c.target,float(caster.navigation_radius))
		var second: Dictionary=c.followups[0]
		var finish: Vector2=host.room.clamp_actor(second.target,float(caster.navigation_radius))
		c.target=middle
		c.direction=Vector2(c.origin).direction_to(middle)
		c.range=Vector2(c.origin).distance_to(middle)
		c.travel_distance=c.range
		c.points=[c.origin,middle]
		c.paths=[[c.origin,middle,finish]]
		second.merge({"origin":middle,"target":finish,"direction":middle.direction_to(finish),"range":middle.distance_to(finish),"travel_distance":middle.distance_to(finish),"points":[middle,finish]},true)
	for i in c.get("followups",[]).size():
		c.followups[i]["source_zone"]=c.source_zone
		c.followups[i]["ranged_direct_damage"]=str(c.followups[i].kind)=="projectile" or (str(c.followups[i].shape)=="line" and str(c.followups[i].kind)=="melee")
	return c

func connected(actor: Node2D) -> bool:
	if not host._alive(actor): return false
	var id: int=actor.get_instance_id()
	if links.has(id): return _core_alive(int(links[id]))
	for index in cores.size():
		if not _core_alive(index): continue
		var count := 0
		for value: int in links.values():
			if value==index: count+=1
		if count<2:
			links[id]=index
			return true
	return false

func _core_alive(index: int) -> bool:
	return index>=0 and index<cores.size() and host._alive(cores[index].actor.get_ref())

func bind_boss(actor: Node2D, phase: int) -> void:
	_clear_cores()
	boss_ref=weakref(actor)
	current_phase=phase
	exposed_phase=0
	var count := phase if str(actor.enemy_id)=="BO10" else 1
	for i in range(count): _spawn_core(actor,i,roundf(float(actor.health.maximum)*.06),true)

func _spawn_core(owner_actor: Node2D, index: int, hp: float, for_boss: bool) -> void:
	var raw: Array=_spec().get("star_cores",[])
	if index>=raw.size(): return
	var at:=Geometry.world_point(raw[index].position)
	var profile_value := {"enemy_id":"B10-CORE","name":"星核 %d"%(index+1),"name_en":"Star Core %d"%(index+1),"max_hp":maxf(10,hp),"damage":0,"armor":0,"magic_resist":0,
		"ruleset_version":2,"scale_version":10,"navigation_radius":16.0,"effective_threat_cost":0.0,"b10_star_core":true}
	var anchor: Node2D=host.room.spawn_enemy(at,"",1,{"profile":profile_value,"static_actor":true,"actor_kind":"objective","reward_enabled":false,"zone_index":-1})
	if not is_instance_valid(anchor): return
	anchor.set_meta("b10_star_core",true)
	var data := {"index":index,"actor":weakref(anchor),"owner":weakref(owner_actor),"position":at,"health":hp,"boss":for_boss}
	if index<cores.size(): cores[index]=data
	else: cores.append(data)
	anchor.health.depleted.connect(_core_destroyed.bind(index,weakref(anchor)))

func _core_destroyed(index: int, ref: WeakRef) -> void:
	if index>=0 and index<cores.size() and not bool(cores[index].boss):
		cores[index]["restore_at"]=clock+8.0
	var core: Node2D=ref.get_ref()
	if is_instance_valid(core) and bool(core.last_damage_result.get("confirmed",false)):
		var player: Variant=Props.read(host.room,"player")
		if player is Object and Props.read(player,"loadout") is Object:
			player.loadout.event("hostile_shield_broken",{"player_attributed":true,"source_id":"B10-CORE","target":core})
	if boss_ref!=null and host._alive(boss_ref.get_ref()) and boss_core_count(boss_ref.get_ref())==0 and exposed_phase!=current_phase:
		exposed_phase=current_phase
		boss_ref.get_ref().boss_brain.cores_cleared(boss_ref.get_ref())
	# Detached ownership means another monster's death cannot delete a core.
	# One core connects at most two stable actors and never heals either actor.
	for link_id: int in links.keys():
		if int(links[link_id])==index:
			var actor: Object=instance_from_id(link_id)
			if host._alive(actor):
				for effect: Dictionary in effects.duplicate():
					if effect.target.get_ref()==actor and str(effect.kind) in ["stance","guard"]: effects.erase(effect)
				_recover(actor,1.2)
				if int(actor.profile.get("difficulty",0))>=4 and str(actor.enemy_id) in ["B10-M13","B10-M18"]:
					effects.append({"kind":"exposed","target":weakref(actor),"remaining":2.0,"direction":actor.aim_direction,"rear_only":str(actor.enemy_id)=="B10-M13"})
				for pending: Dictionary in host.jobs.duplicate():
					if int(pending.get("owner_id",0))==link_id and bool(pending.get("core_required",false)): host.jobs.erase(pending)

func boss_core_count(actor: Node2D) -> int:
	if boss_ref==null or boss_ref.get_ref()!=actor: return 0
	var count := 0
	for index in cores.size():
		if _core_alive(index): count+=1
	return count

func destroyed_core_indices(actor: Node2D) -> Array:
	var result: Array=[]
	if boss_ref==null or boss_ref.get_ref()!=actor: return result
	for index in cores.size():
		if not _core_alive(index): result.append(index)
	return result

func core_position(_actor: Node2D,index: int) -> Vector2:
	return Vector2(cores[index].position) if index>=0 and index<cores.size() else Vector2.ZERO

func rebuild_core(actor: Node2D,index: int) -> void:
	if index<0 or index>=cores.size() or _core_alive(index): return
	_spawn_core(actor,index,float(cores[index].health),true)

func support_targets(caster: Node2D, c: Dictionary) -> Array:
	var result: Array=[]
	if str(c.kind)=="b10_repair":
		for index in cores.size():
			if not _core_alive(index) or repaired.has(index): continue
			var core: Node2D=cores[index].actor.get_ref()
			if core.health.current<core.health.maximum and caster.position.distance_to(core.position)<=360: result.append(weakref(core)); break
		return result
	for node: Node in host.room.enemies.get_children():
		if node==caster or not host._alive(node) or not str(Props.read(node,"enemy_id","")).begins_with("B10-M"): continue
		if str(Props.read(node,"profile",{}).get("profile",""))=="S": continue
		if caster.position.distance_to(node.position)<=360 and host._line_clear(caster.position,node.position): result.append(weakref(node))
		if result.size()>=int(c.get("target_count",1)): break
	return result

func prepare(caster: Node2D, c: Dictionary) -> Dictionary:
	var result := Skills.freeze_damage(c,Props.read(caster,"profile",{}))
	if result.is_empty(): return {}
	result["owner"]=weakref(caster)
	result["owner_id"]=caster.get_instance_id()
	if not result.has("cast_id"):
		serial+=1
		result["cast_id"]="b10:%d:%d"%[caster.get_instance_id(),serial]
	result["stage"]=int(result.get("stage",0))
	return result

func execute(c: Dictionary) -> bool:
	var caster: Node2D=host._owner(c)
	if not host._alive(caster): return true
	if bool(c.get("core_required",false)) and not connected(caster): return true
	if c.has("core_index") and not _core_alive(int(c.core_index)): return true
	var kind := str(c.kind)
	if bool(c.get("derived",false)) and kind=="ground_area" and str(c.shape)=="line" and not c.get("paths",[]).is_empty():
		for path: Array in c.paths:
			for index in range(path.size()-1):
				var stroke:=c.duplicate(true)
				stroke.erase("paths")
				stroke.merge({"origin":path[index],"target":path[index+1],"direction":Vector2(path[index]).direction_to(path[index+1]),"points":[path[index],path[index+1]],"range":Vector2(path[index]).distance_to(path[index+1])},true)
				host._strike(stroke)
				host._flash(stroke)
		return true
	if bool(c.get("b10_cross_gate",false)) and str(c.shape)=="line" and c.get("paths",[]).size()==2:
		for path: Array in c.paths:
			var stroke:=c.duplicate(true)
			stroke.erase("paths")
			stroke.merge({"origin":path[0],"target":path[1],"direction":Vector2(path[0]).direction_to(path[1]),"points":path,"range":Vector2(path[0]).distance_to(path[1])},true)
			host._strike(stroke)
			host._flash(stroke)
		released(c)
		return true
	if not kind.begins_with("b10_"): return false
	if kind in ["b10_stance","b10_guard"]:
		if kind=="b10_stance" and not connected(caster): return true
		effects.append({"kind":"stance" if kind=="b10_stance" else "guard","target":weakref(caster),"remaining":float(c.get("guard_duration",2.0)),"direction":c.direction})
	elif kind=="b10_reposition":
		caster.position=host.room.move_actor(caster.position,Vector2(c.direction).orthogonal()*70,float(caster.navigation_radius))
	elif kind=="b10_transfer":
		for ref: WeakRef in c.get("b10_target_refs",[]):
			var ally: Node2D=ref.get_ref()
			if not host._alive(ally): continue
			var destination: Vector2=c.get("transfer_destination",ally.position)
			if ally.has_method("cancel_actions"): ally.cancel_actions()
			if host.room.valid_ground(destination,float(ally.navigation_radius)):
				if ally.brain!=null and ally.brain.has_method("interrupt"): ally.brain.interrupt(ally)
				ally.position=destination
			if float(c.get("haste_duration",0))>0: effects.append({"kind":"haste","target":ref,"remaining":2.0,"multiplier":1.08})
	elif kind=="b10_repair":
		for ref: WeakRef in c.get("b10_target_refs",[]):
			var core: Node2D=ref.get_ref()
			if not host._alive(core): continue
			for index in cores.size():
				if cores[index].actor.get_ref()==core and not repaired.has(index):
					core.heal(roundf(float(core.health.maximum)*.15))
					repaired[index]=true
					if int(c.difficulty)>=2: caster.status.grant_guard(roundf(float(caster.health.maximum)*.04),4.0,"b10_repair",float(caster.health.maximum))
	elif kind=="b10_harmonize":
		for ref: WeakRef in c.get("b10_target_refs",[]):
			if host._alive(ref.get_ref()): effects.append({"kind":"echo_mark","target":ref,"remaining":8.0,"source":weakref(caster)})
	elif kind=="b10_waymark":
		var marker:=c.duplicate(true)
		marker["fx_color"]=Color("86ceb4")
		marker["remaining"]=1.0
		marker["color"]=Color("86ceb4")
		marker["harmless"]=true
		host.visuals.append(marker)
	elif kind=="b10_summon":
		if can_summon_guards(caster):
			var count:=0
			for side: int in [-1,1]:
				var profile_value:=Skills.profile("B10-M01",50,int(host.room.difficulty))
				profile_value.max_hp=int(round(float(profile_value.max_hp)*.5))
				var at: Vector2=host.room.clamp_actor(caster.position+Vector2(side*180,100),18)
				var guard: Node2D=host.room.spawn_enemy(at,"B10-M01",50,{"owner":caster,"profile":profile_value,"reward_enabled":false,"zone_index":-1})
				if is_instance_valid(guard): count+=1
			if count>0: caster.set_meta("b10_guard_rounds",int(caster.get_meta("b10_guard_rounds",0))+1)
	elif kind=="b10_scale_stone":
		var stone: Node2D=host.room.spawn_enemy_skill_anchor(caster,Vector2(c.target),float(c.anchor_health),"b10_scale_stone")
		if is_instance_valid(stone):
			stone.health.depleted.connect(func() -> void:
				if host._alive(caster) and int(c.difficulty)>=4: _recover(caster,2.0))
			# A stone never blocks navigation or portal landings; it is a target.
			effects.append({"kind":"stone","target":weakref(stone),"remaining":6.0})
	host._flash(c,Color("c7adea"))
	released(c)
	return true

func released(c: Dictionary) -> void:
	var caster: Node2D=host._owner(c)
	if not host._alive(caster): return
	var followups: Array=c.get("followups",[])
	for i in followups.size():
		if host.active_effect_count()>=host.MAX_EFFECTS: break
		var step: Dictionary=followups[i].duplicate(true)
		step["owner"]=c.owner
		step["owner_id"]=c.owner_id
		step["cast_id"]=c.cast_id
		step["stage"]=i+1
		if bool(step.get("b10_relock",false)):
			var player: Variant=Props.read(host.room,"player")
			if player is Node2D:
				step.origin=caster.position
				step.direction=caster.position.direction_to(player.position)
				step.target=player.position
				step=Skills.geometry(step)
		step=Skills.freeze_damage(step,caster.profile)
		step["remaining"]=maxf(.15,float(step.get("delay",.9)))
		host.jobs.append(step)
	# Delayed effects do not recursively schedule another echo or followup.
	if bool(c.get("derived",false)) or not bool(c.get("active",false)) or int(c.get("coefficient",0))<=0: return
	var marked := false
	for effect: Dictionary in effects.duplicate():
		if str(effect.kind)=="echo_mark" and effect.target.get_ref()==caster:
			marked=true
			effects.erase(effect)
			break
	var id: int=caster.get_instance_id()
	var on_core:=connected(caster)
	if (on_core or marked) and clock>=float(echo_ready.get(id,0)):
		# Echoes repeat the original locked shape once; a charge leaves its
		# original swept line, never moves the body or schedules another charge.
		var echo := Skills.child(c,"ground_area" if str(c.kind)=="charge" else str(c.kind),str(c.shape),25,.9)
		if str(c.shape)=="line": echo["points"]=c.get("points",[c.origin,c.target]).duplicate()
		if not c.get("paths",[]).is_empty(): echo["paths"]=c.paths.duplicate(true)
		echo.merge({"owner":c.owner,"owner_id":c.owner_id,"cast_id":c.cast_id,"stage":99,"core_required":on_core,"b10_echo":false,"b10_swept_cast":false,"duration":0.0,"recovery":0.0},true)
		echo=Skills.freeze_damage(echo,caster.profile)
		echo["remaining"]=.9
		host.jobs.append(echo)
		echo_ready[id]=clock+10

func allow_hit(victim: Node2D,c: Dictionary) -> bool:
	if not bool(c.get("b10_cross_gate",false)) and Geometry.zone_at(str(host.room.layout_id),victim.position)!=str(c.get("source_zone",Geometry.zone_at(str(host.room.layout_id),Vector2(c.origin)))): return false
	var key := "%s:%d:%d"%[str(c.get("cast_id","")),0 if bool(c.get("b10_swept_cast",false)) else int(c.get("stage",0)),victim.get_instance_id()]
	if hit_receipts.has(key): return false
	hit_receipts[key]=clock
	return true

func can_summon_guards(caster: Node2D) -> bool:
	if int(caster.get_meta("b10_guard_rounds",0))>=2: return false
	for actor: Node in host.room.enemies.get_children():
		if host._alive(actor) and actor.get("owner_enemy") is WeakRef and actor.owner_enemy.get_ref()==caster: return false
	return host.room._living_enemy_count()<=host.MAX_ENEMIES-2

func filter_damage(target: Node2D,amount: float,_kind: StringName,direction: Vector2,damage_type: String) -> float:
	if damage_type=="true": return amount
	for effect: Dictionary in effects:
		if effect.target.get_ref()!=target: continue
		if str(effect.kind) in ["guard","stance"] and direction.normalized().dot(Vector2(effect.direction))<-.35: amount*=.65
		if str(effect.kind)=="exposed" and (not bool(effect.get("rear_only",false)) or direction.normalized().dot(Vector2(effect.direction))>.35): amount*=1.15
	return amount

func _recover(actor: Node2D, seconds: float) -> void:
	if host._alive(actor) and actor.brain!=null and actor.brain.has_method("hold_recovery"):
		actor.brain.hold_recovery(actor,seconds)

func recovery_remaining(actor: Node2D) -> float:
	var result:=0.0
	for effect: Dictionary in effects:
		if effect.target.get_ref()==actor and str(effect.kind) in ["guard","stance"]:
			result=maxf(result,float(effect.remaining)+1.2)
	return result

func motion_finished(c: Dictionary, impact: bool) -> void:
	if impact: return
	for pending: Dictionary in host.jobs.duplicate():
		if int(pending.get("owner_id",0))==int(c.get("owner_id",0)) and str(pending.get("cast_id",""))==str(c.get("cast_id","")):
			host.jobs.erase(pending)

func interrupted(caster: Node2D) -> void:
	# The support owns only uncommitted marks, so interrupting it cannot
	# withdraw an already published, delayed warning.
	for effect: Dictionary in effects.duplicate():
		if str(effect.kind)=="echo_mark" and effect.has("source") and effect.source.get_ref()==caster: effects.erase(effect)

func phase_started(caster: Node2D) -> void:
	for pending: Dictionary in host.jobs.duplicate():
		if int(pending.get("owner_id",0))==caster.get_instance_id() and bool(pending.get("b10_cross_gate",false)): host.jobs.erase(pending)
	_clear_cores()
	boss_ref=null

func movement_multiplier(target: Node2D) -> float:
	for effect: Dictionary in effects:
		if effect.target.get_ref()==target and str(effect.kind)=="haste": return 1.08
	return 1.0

func cancel_owner(caster: Node2D) -> void:
	for effect: Dictionary in effects.duplicate():
		if effect.target.get_ref()==caster: effects.erase(effect)
	if boss_ref!=null and boss_ref.get_ref()==caster:
		_clear_cores()
		boss_ref=null

func _clear_cores() -> void:
	for core: Dictionary in cores:
		var actor: Node=core.actor.get_ref()
		if is_instance_valid(actor): actor.queue_free()
	cores.clear()
	links.clear()

func reset() -> void:
	_clear_cores()
	for effect: Dictionary in effects:
		if str(effect.kind)=="stone" and is_instance_valid(effect.target.get_ref()): effect.target.get_ref().queue_free()
	effects.clear()
	hit_receipts.clear()
	echo_ready.clear()
	repaired.clear()
	boss_ref=null
	clock=0
	serial=0
	current_phase=0
	exposed_phase=0
	ordinary_initialized=false

func draw(canvas: Node2D) -> void:
	for index in cores.size():
		if not _core_alive(index): continue
		var core: Node2D=cores[index].actor.get_ref()
		var at: Vector2=core.position
		canvas.draw_circle(at,24,Color("f7edc6"))
		canvas.draw_arc(at,31,0,TAU,32,Color("9bcee8"),3,true)
		canvas.draw_rect(Rect2(at+Vector2(-24,7),Vector2(48*core.health.current/core.health.maximum,4)),Color("d6b763"))
		for id: int in links:
			var actor: Object=instance_from_id(id)
			if int(links[id])==index and host._alive(actor): canvas.draw_line(at,actor.position,Color(.48,.74,.87,.55),2,true)
