extends RefCounted
## B06-only execution adapter. Real collision/damage stays in the common host.
## Delayed stages own frozen warning geometry; cancellation retires all hazards.
const Skills = preload("res://scripts/combat/b06_enemy_skills.gd")
const Props = preload("res://scripts/combat/combat_properties.gd")
var host: Node2D
var effects: Array[Dictionary] = []
var hit_receipts: Dictionary = {}
var summon_attempts: Dictionary = {}
var clock := 0.0
var serial := 0
var shell_observations: Dictionary = {}
var banner_extensions: Dictionary = {}
var lock_slots: Array[Dictionary] = []
func configure(runtime: Node2D) -> void: host=runtime
func prepare(caster: Node2D, command: Dictionary) -> Dictionary:
	var result := Skills.freeze_damage(command,Props.read(caster,"profile",{}))
	if result.is_empty(): return {}
	result["owner"]=weakref(caster)
	result["owner_id"]=caster.get_instance_id()
	if not result.has("cast_id"):
		serial+=1
		result["cast_id"]="b06:%d:%d" % [caster.get_instance_id(),serial]
	var profile_value: Dictionary = Props.read(caster,"profile",{})
	if preload("res://scripts/combat/crit_policy.gd").enabled(profile_value):
		# Runtime serial is frozen by candidate snapshots; no instance ID in RNG key.
		var event_id: String = str(result.get("crit_event_id", str(result.cast_id).get_slice(":",0) + ":" + str(profile_value.get("enemy_id", "")) + ":" + str(result.cast_id).get_slice(":",2)))
		result = preload("res://scripts/combat/crit_policy.gd").freeze(result, profile_value, int(Props.read(host.room,"run_seed",0)), event_id)
	return result
func admitted(command: Dictionary, hit: bool = false) -> bool:
	var caster: Node2D=host._owner(command)
	if not host._alive(caster): return false
	var mechanism: Variant=Skills.mechanics(caster)
	var method := "can_enemy_hit" if hit else "can_enemy_cast"
	return not mechanism is Object or not mechanism.has_method(method) or bool(mechanism.call(method,command))
func execute(command: Dictionary) -> bool:
	var caster: Node2D=host._owner(command)
	var mechanism: Variant=Skills.mechanics(caster)
	if str(command.get("action_id",""))=="siege_claw" and mechanism is Object and mechanism.has_method("confirm_boss_claw"):
		mechanism.confirm_boss_claw(command)
	if bool(command.get("b06_thrust",false)):
		host._strike(command)
		host._flash(command)
		var motion := command.duplicate(true)
		motion.merge({"damage":0,"coefficient":0,"harmless":true,"landing_only":true,"target":Vector2(command.origin)+Vector2(command.direction)*50,"followups":[]},true)
		host._start_motion(motion)
		return true
	if str(command.kind)=="b06_reposition":
		caster.position=host.room.move_actor(caster.position,Vector2(command.displacement),float(Props.read(caster,"navigation_radius",18)))
		return true
	if str(command.kind)=="b06_summon":
		_summon(command)
		return true
	if str(command.kind) in ["b06_shield_stance","b06_shell"]:
		_add(command,{"kind":"stance","target_ref":weakref(caster),"remaining":float(command.duration),"direction":Vector2(command.direction),"reduction":float(command.reduction)})
		if str(command.kind)=="b06_shield_stance" and int(command.difficulty)>=2:
			var destination := nearest_dry_point(caster,70)
			caster.position=host.room.move_actor(caster.position,destination-caster.position,float(caster.navigation_radius))
			_shift_followups(command,caster.position-Vector2(command.origin))
		if str(command.kind)=="b06_shell" and int(command.difficulty)>=4:
			for ref: WeakRef in support_targets(caster,{"range":180.0,"target_count":18}):
				var ally: Node2D=ref.get_ref()
				if ally.status.guards.has("b06_bubble"):
					var guard: Dictionary=ally.status.guards.b06_bubble
					caster.status.grant_guard(float(guard.amount),minf(2,float(guard.remaining)),"b06_absorbed_bubble",float(caster.health.maximum))
					ally.status.guards.erase("b06_bubble")
					break
		return true
	if str(command.kind) in ["b06_shield","b06_hasten"]:
		var first := true
		for ref: WeakRef in command.get("b06_target_refs",[]):
			var ally: Node2D=ref.get_ref()
			if not eligible(ally) or caster.position.distance_to(ally.position)>float(command.range) or not host._line_clear(caster.position,ally.position): continue
			if str(command.kind)=="b06_shield":
				if ally.status.grant_guard(float(ally.health.maximum)*float(command.shield_ratio),5,"b06_bubble",float(ally.health.maximum)):
					_add(command,{"kind":"bubble","target_ref":ref,"remaining":5.0,"absorbed_at":float(ally.status.total_absorbed)})
			else:
				if ally.brain!=null and ally.brain.has_method("reduce_cooldown"): ally.brain.reduce_cooldown(1.0)
				if first and int(command.difficulty)>=2: _add(command,{"kind":"haste","target_ref":ref,"remaining":3.0,"speed_multiplier":1.1})
				first=false
		host._flash(command,Color("85e9d2"))
		return true
	if str(command.kind)=="b06_hop":
		var before: Vector2=caster.position
		caster.position=host.room.move_actor(before,Vector2(command.displacement),float(caster.navigation_radius))
		# A blocked sidestep cancels the future lance rather than shifting an
		# already published landing shape to an unmarked wall.
		if caster.position.distance_to(before+Vector2(command.displacement))>.5:
			command.followups=[]
		elif int(command.difficulty)>=4 and not Skills.high(caster):
			caster.status.grant_guard(float(caster.health.maximum)*.08,1.5,"b06_lance_step",float(caster.health.maximum))
		if int(command.difficulty)>=2 and not command.followups.is_empty():
			var line: Dictionary=command.followups[0].duplicate(true)
			line.merge({"kind":"waterline","remaining":1.5,"coefficient":0,"damage":0,"width":15.0},true)
			_add(command,line)
		return true
	if str(command.kind)=="b06_mine":
		_spawn_breakable(command,"mine",2.0,.10)
		if int(command.get("count",1))>1:
			var next := Skills.child(command,"b06_mine","circle",0,1.0)
			next.merge({"count":1,"target":Vector2(command.target)+Vector2(command.direction).orthogonal()*90,"fuse":2.0,"mine_coefficient":100},true)
			_queue(caster,next)
		return true
	if str(command.kind)=="b06_net":
		var effect := _spawn_breakable(command,"net",3.0,.10)
		if not effect.is_empty():
			var strike := command.duplicate(true)
			strike.origin=command.target
			host._strike(strike)
		return true
	if str(command.kind)=="b06_wall":
		if not wall_admitted(caster,command): return true
		var anchor:Node2D=host._spawn_anchor(command,Vector2(command.wall_center),roundf(float(caster.health.maximum)*.2),"b06_wall")
		if not host._alive(anchor): return true
		var effect:=_add(command,{"kind":"wall","remaining":7.0,"anchor_ref":weakref(anchor),"wall_half_width":6.0})
		if not effect.is_empty(): anchor.health.depleted.connect(_wall_broken.bind(effect),CONNECT_ONE_SHOT)
		return true
	if str(command.kind)=="b06_banner":
		_spawn_breakable(command,"banner",6.0,.20)
		return true
	return false
func released(command: Dictionary) -> void:
	var caster: Node2D=host._owner(command)
	if not host._alive(caster): return
	var stage := 0
	for source: Dictionary in command.get("followups",[]):
		stage+=1
		var follow := source.duplicate(true)
		follow["cast_id"]=str(command.cast_id)
		follow["stage"]=stage
		follow["b06_phase"]=int(command.get("b06_phase",1))
		_queue(caster,follow)
func _queue(caster: Node2D, follow: Dictionary) -> void:
	if host.active_effect_count()>=host.MAX_EFFECTS: return
	# A derived dangerous stage gets its own full minimum warning. Non-damage
	# continuations (foam/recoil) begin exactly at their authored release.
	var delay: float=maxf(0,float(follow.get("delay",0)))
	if int(follow.get("coefficient",0))>0:
		follow=Skills.timed(follow,maxf(.4,delay-.4),int(follow.difficulty),str(follow.caster_enemy_id)=="BO06")
		delay=maxf(delay,float(follow.tell)+float(follow.lock))
	if _coordinated(follow):
		var lock_at:=clock+maxf(0,delay-float(follow.get("lock",.22)))
		var reserved:=_reserve_lock(caster,lock_at)
		delay+=reserved-lock_at
	follow=prepare(caster,Skills.geometry(follow))
	if follow.is_empty(): return
	follow["remaining"]=delay
	if delay>0: host.jobs.append(follow)
	else: host._execute(follow)
func motion_finished(motion: Dictionary, completed: bool) -> void:
	var caster: Node2D=host._owner(motion)
	if not host._alive(caster): return
	var d := int(motion.get("difficulty",0))
	var after := str(motion.get("after_motion",""))
	if after=="sawfin" and completed and d>=2:
		for sign_value in [-1,1]:
			var spike := Skills.area(motion,caster.position+Vector2(motion.direction).orthogonal()*85*sign_value,30,30,.8)
			spike["stage"]=2 if sign_value<0 else 3
			_queue(caster,spike)
	if after=="needle" and completed:
		if d>=2: _queue(caster,Skills.area(motion,caster.position,60,30,.8))
		if d>=4 and bool(motion.get("high",false)):
			_add(motion,{"kind":"needle_return","remaining":8.0,"return_point":Vector2(motion.start)})
	if after=="siege" and not completed and caster.has_meta("enemy_charge_wall_stop") and d>=2:
		var splash := Skills.child(motion,"melee","line",40,.8)
		splash.merge({"origin":caster.position,"direction":Vector2(motion.direction).orthogonal(),"range":120.0,"width":35.0},true)
		_queue(caster,splash)
func allow_hit(victim: Node2D, command: Dictionary) -> bool:
	if bool(command.get("harmless",false)) or not admitted(command,true): return false
	if bool(command.get("continuous",false)): return true
	var key := "%s:%d:%d" % [str(command.get("cast_id","")),int(command.get("stage",0)),victim.get_instance_id()]
	return int(hit_receipts.get(key,{}).get("count",0)) < int(command.get("max_target_hits",1))
func confirmed_hit(victim: Node2D, command: Dictionary) -> void:
	var key := "%s:%d:%d" % [str(command.get("cast_id","")),int(command.get("stage",0)),victim.get_instance_id()]
	var old: Dictionary=hit_receipts.get(key,{})
	hit_receipts[key]={"count":int(old.get("count",0))+1,"expires":clock+30.0}
	var push := float(command.get("b06_push",0))
	var mechanism: Variant=Skills.mechanics(host._owner(command))
	if push>0 and mechanism is Object and mechanism.has_method("push_actor"):
		mechanism.push_actor(victim,Vector2(command.direction)*push)
func filter_damage(target: Node2D, amount: float, _kind: StringName, from_direction: Vector2, _damage_type: String, context: Dictionary = {}) -> float:
	if _damage_type!="true":
		for effect: Dictionary in effects:
			if not _valid(effect) or _target(effect)!=target: continue
			if effect.kind=="stance":
				if str(effect.get("caster_enemy_id",""))=="B06-M15" or Vector2(effect.direction).dot(-from_direction.normalized())>.5: amount*=1-float(effect.reduction)
			if effect.kind=="exposed": amount*=1.15
		if str(Props.read(target,"enemy_id",""))=="B06-M14" and int(target.profile.difficulty)>=4 and Skills.wet(target) and target.brain!=null and str(target.brain.phase) in ["telegraph","locked"]: amount*=.8
	if _damage_type!="true" and str(context.get("attack_delivery",""))=="projectile" and eligible(target):
		for effect:Dictionary in effects:
			if effect.kind!="wall" or not _valid(effect) or int(effect.difficulty)<2: continue
			var offset:Vector2=target.position-Vector2(effect.wall_center)
			if offset.dot(Vector2(effect.direction))<0 and offset.length()<=180 and absf(offset.dot(Vector2(effect.direction).orthogonal()))<=60:
				amount*=.9
				break
	if str(Props.read(target,"enemy_id",""))!="BO06": return amount
	var mechanism: Variant=Skills.mechanics(target)
	if not mechanism is Object: return amount
	var boss_state: Variant=Props.read(mechanism,"boss_state")
	if not boss_state is Object: return amount
	# from_direction is source->victim; negate to locate the attacking source.
	var facing: Vector2=Props.read(target,"aim_direction",Vector2.RIGHT)
	var region := "front_shell" if not from_direction.is_zero_approx() and facing.dot(-from_direction.normalized())>.5 else "side_abdomen"
	return amount*float(boss_state.incoming_multiplier(region))
func movement_multiplier(target: Node2D) -> float:
	var result := 1.0
	for effect: Dictionary in effects:
		if _valid(effect) and effect.kind=="haste" and _target(effect)==target: result=maxf(result,float(effect.speed_multiplier))
	return result
func advance(delta: float) -> void:
	clock+=delta
	for slot:Dictionary in lock_slots.duplicate():
		if float(slot.at)+.8<=clock or not host._alive(slot.owner.get_ref()): lock_slots.erase(slot)
	for effect: Dictionary in effects.duplicate():
		if not _valid(effect): _remove(effect); continue
		var previous := float(effect.remaining)
		effect.remaining=maxf(0,previous-delta)
		var actor: Node2D=_target(effect)
		if effect.kind=="needle_return" and not Skills.high(host._owner(effect)):
			var caster:Node2D=host._owner(effect)
			var back := Skills.child(effect,"charge","line",0,.8)
			back.merge({"origin":caster.position,"direction":caster.position.direction_to(Vector2(effect.return_point)),"target":effect.return_point,"range":minf(220,caster.position.distance_to(Vector2(effect.return_point))),"travel_distance":220.0,"duration":.45,"landing_only":true,"harmless":true},true)
			_queue(caster,back)
			_remove(effect)
			continue
		if effect.kind=="bubble" and int(effect.difficulty)>=2 and previous>delta and host._alive(actor) and not actor.status.guards.has("b06_bubble") and float(actor.status.total_absorbed)>float(effect.absorbed_at):
			var burst := Skills.area(effect,actor.position,80,0,0)
			burst.merge({"status":{"id":"slow","magnitude":.9,"duration":2.0},"continuous":true},true)
			host._execute(prepare(host._owner(effect),burst))
			_remove(effect)
			continue
		if effect.kind in ["mine","net"]:
			var anchor: Node2D=host._anchor(effect)
			var distance := 60.0 if effect.kind=="mine" and int(effect.difficulty)>=4 else 40.0 if effect.kind=="net" and int(effect.difficulty)>=2 else 0.0
			if distance>0:
				var step := Vector2(effect.tide_direction)*distance*minf(delta,previous)/float(effect.life)
				anchor.position=host.room.move_actor(anchor.position,step,10.0)
				effect.origin=anchor.position
				effect.target=anchor.position
			if effect.remaining<=0:
				if effect.kind=="mine" or int(effect.difficulty)>=4:
					var strike := Skills.area(effect,anchor.position,float(effect.radius),100 if effect.kind=="mine" else 40,0)
					strike["stage"]=int(effect.get("stage",0))+10
					strike=prepare(host._owner(effect),strike)
					host._strike(strike)
					host._flash(strike)
		if effect.kind=="banner":
			if _banner_drained(effect):
				if int(effect.difficulty)>=4: _add(effect,{"kind":"exposed","target_ref":weakref(host._owner(effect)),"remaining":3.0})
				_remove(effect)
				continue
			if int(effect.difficulty)>=2:
				effect.next_wave=float(effect.get("next_wave",2))-delta
				if effect.next_wave<=0 and effect.remaining>.8:
					effect.next_wave=2.0
					var wave := Skills.child(effect,"melee","line",40,.8)
					wave.merge({"origin":host._anchor(effect).position,"range":180.0,"width":28.0},true)
					_queue(host._owner(effect),wave)
		if effect.remaining<=0: _remove(effect)
	_track_shells(delta)
	_extend_banner_guards()
	for key in hit_receipts.keys():
		if float(hit_receipts[key].expires)<=clock: hit_receipts.erase(key)
func cancel_owner(caster: Node2D) -> void:
	for slot:Dictionary in lock_slots.duplicate():
		if slot.owner.get_ref()==caster: lock_slots.erase(slot)
	for effect: Dictionary in effects.duplicate():
		if int(effect.get("owner_id",0))==caster.get_instance_id(): _remove(effect)
	# Finite summon attempts survive phase cleanup. New room/retry resets them.
## Reconfiguration is a new encounter; phase cleanup is not.
func reset_owner(caster: Node2D) -> void:
	if not is_instance_valid(caster): return
	cancel_owner(caster)
	var id := caster.get_instance_id()
	summon_attempts.erase(id)
	shell_observations.erase(id)
	banner_extensions.erase(id)
	for key: String in hit_receipts.keys():
		var parts := key.split(":")
		if parts.size()>2 and parts[1]==str(id): hit_receipts.erase(key)
func reset() -> void:
	for effect: Dictionary in effects.duplicate(): _remove(effect)
	shell_observations.clear()
	banner_extensions.clear()
	lock_slots.clear()
	hit_receipts.clear()
	summon_attempts.clear()
	clock=0
	serial=0
func eligible(actor: Node2D) -> bool:
	return host._alive(actor) and str(Props.read(actor,"actor_kind",""))=="enemy" and str(Props.read(actor,"rank",""))!="boss" and str(Props.read(actor,"enemy_id","")).begins_with("B06-M") and not actor.has_meta("enemy_skill_anchor")
func support_targets(caster: Node2D, command: Dictionary) -> Array:
	var result: Array=[]
	var container: Variant=Props.read(host.room,"enemies")
	if not container is Node: return result
	var candidates: Array[Node2D]=[]
	for actor: Node in container.get_children():
		if actor==caster or not actor is Node2D or not eligible(actor): continue
		if caster.position.distance_to(actor.position)>float(command.get("range",240)) or not host._line_clear(caster.position,actor.position): continue
		candidates.append(actor)
	candidates.sort_custom(func(a:Node2D,b:Node2D)->bool: return caster.position.distance_squared_to(a.position)<caster.position.distance_squared_to(b.position))
	for actor:Node2D in candidates.slice(0,int(command.get("target_count",1))): result.append(weakref(actor))
	return result
func _summon(command: Dictionary) -> void:
	var caster: Node2D=host._owner(command)
	var id := caster.get_instance_id()
	if int(summon_attempts.get(id,0))>=2 or not host.room.has_method("spawn_enemy_summon"): return
	summon_attempts[id]=int(summon_attempts.get(id,0))+1
	var owned: Array=host.summon_owners.get(id,[])
	for ref: WeakRef in owned.duplicate():
		if not host._alive(ref.get_ref()): owned.erase(ref)
	for i in range(mini(2,2-owned.size())):
		var at: Vector2=Vector2(command.origin)+Vector2(command.direction).orthogonal()*(-80 if i==0 else 80)
		var child: Node2D=host.room.spawn_enemy_summon(caster,"B06-M01",at)
		if not is_instance_valid(child): continue
		child.reward_enabled=false
		child.owner_enemy=weakref(caster)
		child.health.reset(roundf(float(child.health.maximum)*.5),2)
		owned.append(weakref(child))
	host.summon_owners[id]=owned

func _add(command: Dictionary, values: Dictionary) -> Dictionary:
	if host.active_effect_count()>=host.MAX_EFFECTS: return {}
	var effect := command.duplicate(true)
	effect.merge(values,true)
	if str(effect.kind) not in ["mine","net","banner","wall"]: effect.erase("anchor_ref")
	effects.append(effect)
	return effect
func _target(effect: Dictionary) -> Node2D:
	var ref: WeakRef=effect.get("target_ref")
	return ref.get_ref() if ref!=null else null
func _valid(effect: Dictionary) -> bool:
	if not host._owner_alive(effect) or float(effect.get("remaining",0))<=0: return false
	if effect.has("anchor_ref") and not host._alive(host._anchor(effect)): return false
	return not effect.has("target_ref") or host._alive(_target(effect))
func _remove(effect: Dictionary) -> void:
	effects.erase(effect)
	var anchor: Node2D=host._anchor(effect)
	if is_instance_valid(anchor): anchor.queue_free()
func _spawn_breakable(command: Dictionary, kind: String, life: float, ratio: float) -> Dictionary:
	var caster: Node2D=host._owner(command)
	var owned := 0
	for effect: Dictionary in effects:
		if effect.kind==kind and effect.owner_id==command.owner_id: owned+=1
	if owned>=(2 if kind=="mine" else 1): return {}
	var at: Vector2=command.target
	var anchor: Node2D=host._spawn_anchor(command,at,roundf(float(caster.health.maximum)*ratio),"b06_"+kind)
	if not host._alive(anchor): return {}
	return _add(command,{"kind":kind,"origin":at,"target":at,"remaining":life,"life":life,"anchor_ref":weakref(anchor),"tide_direction":tidal_direction(caster,at),"next_wave":2.0})
func _shift_followups(command: Dictionary, displacement: Vector2) -> void:
	for c: Dictionary in command.get("followups",[]):
		c.origin=Vector2(c.origin)+displacement
		c.target=Vector2(c.target)+displacement
		c.erase("points")
		c.erase("paths")
func tidal_direction(caster: Node2D, point: Vector2) -> Vector2:
	var mechanism: Variant=Skills.mechanics(caster)
	if not mechanism is Object: return Vector2.ZERO
	var data := preload("res://scripts/world/b06_room_geometry.gd").room(str(mechanism.room_id))
	for patch: Dictionary in data.get("shallow_patches",[]):
		var polygon := preload("res://scripts/world/b06_room_geometry.gd").points(patch.polygon)
		if Geometry2D.is_point_in_polygon(point,polygon): return Vector2(float(patch.direction[0]),float(patch.direction[1])).normalized()
	return Vector2.ZERO
func nearest_dry_point(caster: Node2D, maximum: float) -> Vector2:
	var mechanism: Variant=Skills.mechanics(caster)
	if not mechanism is Object or not Skills.wet(caster): return caster.position
	var data := preload("res://scripts/world/b06_room_geometry.gd").room(str(mechanism.room_id))
	var best: Vector2=caster.position
	var distance := INF
	for patch: Dictionary in data.get("shallow_patches",[]):
		if str(patch.id)!=str(mechanism.patch_at(caster)): continue
		var polygon := preload("res://scripts/world/b06_room_geometry.gd").points(patch.polygon)
		for i in polygon.size():
			var point := Geometry2D.get_closest_point_to_segment(caster.position,polygon[i],polygon[(i+1)%polygon.size()])
			if point.distance_squared_to(caster.position)<distance:
				distance=point.distance_squared_to(caster.position)
				best=point
	return caster.position+caster.position.direction_to(best)*minf(maximum,sqrt(distance)+float(caster.navigation_radius)+2)
func _track_shells(delta: float) -> void:
	var container: Variant=Props.read(host.room,"enemies")
	if not container is Node: return
	for actor:Node in container.get_children():
		if not actor is Node2D or not eligible(actor) or actor.enemy_id!="B06-M03" or int(actor.profile.difficulty)<4: continue
		var id := actor.get_instance_id()
		var current: Dictionary=actor.status.guards.get("b06_tide_shell",{})
		var old: Dictionary=shell_observations.get(id,{})
		if float(old.get("amount",0))>0 and float(old.get("remaining",0))>delta and float(current.get("amount",0))<=0 and float(actor.status.total_absorbed)>float(old.get("absorbed",0)):
			var side: Vector2=Vector2(actor.aim_direction).orthogonal()*80
			var destination: Vector2=host.room.move_actor(actor.position,side,float(actor.navigation_radius))
			if actor.brain!=null: actor.brain.on_displacement_committed(actor,destination)
			actor.position=destination
		shell_observations[id]={"amount":current.get("amount",0),"remaining":current.get("remaining",0),"absorbed":float(actor.status.total_absorbed)}
func _banner_drained(effect: Dictionary) -> bool:
	var caster: Node2D=host._owner(effect)
	var mechanism: Variant=Skills.mechanics(caster)
	if not mechanism is Object: return false
	var anchor: Node2D=host._anchor(effect)
	var patch: String=str(mechanism.patch_at(anchor))
	var state: Dictionary=mechanism.state.snapshot()
	return not patch.is_empty() and int(state.drained_until.get(patch,0))>int(state.now_us)
func tide_guard_extension(actor: Node2D) -> float:
	if not eligible(actor): return 0
	for effect: Dictionary in effects:
		if effect.kind=="banner" and _valid(effect) and not _banner_drained(effect) and actor.position.distance_to(host._anchor(effect).position)<=180: return 2
	return 0
func _extend_banner_guards() -> void:
	var container: Variant=Props.read(host.room,"enemies")
	if not container is Node: return
	for actor:Node in container.get_children():
		if not actor is Node2D or not eligible(actor): continue
		var id := actor.get_instance_id()
		var guard: Dictionary=actor.status.guards.get("b06_tide_shell",{})
		if guard.is_empty(): banner_extensions.erase(id); continue
		if banner_extensions.has(id): continue
		if tide_guard_extension(actor)>0:
			guard.remaining=float(guard.remaining)+2.0
			banner_extensions[id]=true
func draw(canvas: Node2D) -> void:
	for effect: Dictionary in effects:
		if not _valid(effect): continue
		var tint := Color("62d9d7")
		if effect.kind=="waterline": canvas._draw_shape(effect,Color(tint,.1),Color(tint,.45))
		elif effect.kind=="wall":
			canvas.draw_line(effect.wall_start,effect.wall_end,Color("e998b4"),12,true)
			canvas.draw_line(effect.wall_start,effect.wall_end,Color("ffe3ce"),3,true)
		elif effect.kind in ["mine","net","banner"]:
			canvas._draw_shape(effect,Color(tint,.13),tint)
			var anchor:Node2D=host._anchor(effect)
			canvas.draw_circle(anchor.position,10,tint)
			if effect.kind=="mine": canvas.draw_arc(anchor.position,16,-PI/2,-PI/2+TAU*float(effect.remaining)/float(effect.life),24,Color("ffe795"),3,true)
		elif effect.kind=="stance":
			var actor:Node2D=_target(effect)
			canvas.draw_arc(actor.position,35,Vector2(effect.direction).angle()-.95,Vector2(effect.direction).angle()+.95,20,tint,4,true)
		elif effect.kind in ["bubble","haste"]:
			canvas.draw_line(host._owner(effect).position,_target(effect).position,Color(tint,.45),2,true)

func wall_admitted(caster:Node2D,command:Dictionary) -> bool:
	var mechanism:Variant=Skills.mechanics(caster)
	return mechanism is Object and mechanism.has_method("admit_coral_wall") and bool(mechanism.admit_coral_wall(command.wall_start,command.wall_end,6.0))
func _wall_broken(effect:Dictionary) -> void:
	if not effects.has(effect): return
	var caster:Node2D=host._owner(effect)
	if host._alive(caster) and int(effect.difficulty)>=4: _add(effect,{"kind":"exposed","target_ref":weakref(caster),"remaining":2.0})
	_remove(effect)
func wall_blocks_point(point:Vector2,radius:float) -> bool:
	for effect:Dictionary in effects:
		if effect.kind=="wall" and _valid(effect) and point.distance_to(Geometry2D.get_closest_point_to_segment(point,effect.wall_start,effect.wall_end))<float(effect.wall_half_width)+maxf(0,radius): return true
	return false
func blocked_fraction(start:Vector2,end:Vector2,radius:float) -> float:
	var result:=1.0
	for effect:Dictionary in effects:
		if effect.kind!="wall" or not _valid(effect): continue
		# LOS may target this wall's actual breakable center. The projectile
		# sweep remains blocked and reaches the center's collision disc first.
		if radius<=0 and end.distance_to(Vector2(effect.wall_center))<=10.01: continue
		result=minf(result,_capsule_entry(start,end,effect.wall_start,effect.wall_end,maxf(0,radius)+float(effect.wall_half_width)))
	return result
func navigation_obstructions() -> Array[Rect2]:
	var result:Array[Rect2]=[]
	for effect:Dictionary in effects:
		if effect.kind=="wall" and _valid(effect): result.append(Rect2(Vector2(effect.wall_start),Vector2.ZERO).expand(effect.wall_end).grow(float(effect.wall_half_width)))
	return result
static func _capsule_entry(start:Vector2,end:Vector2,a:Vector2,b:Vector2,radius:float)->float:
	var axis:Vector2=(b-a).normalized()
	var normal:Vector2=axis.orthogonal()
	var local_start:=Vector2((start-a).dot(axis),(start-a).dot(normal))
	var local_end:=Vector2((end-a).dot(axis),(end-a).dot(normal))
	var delta:Vector2=local_end-local_start
	var lower:=Vector2(0,-radius)
	var upper:=Vector2(a.distance_to(b),radius)
	var low:=0.0
	var high:=1.0
	var intersects:=true
	for i in 2:
		if absf(delta[i])<.000001:
			if local_start[i]<lower[i] or local_start[i]>upper[i]: intersects=false; break
		else:
			var t1:float=(lower[i]-local_start[i])/delta[i]
			var t2:float=(upper[i]-local_start[i])/delta[i]
			low=maxf(low,minf(t1,t2))
			high=minf(high,maxf(t1,t2))
			if low>high: intersects=false; break
	var result:=clampf(low,0,1) if intersects else 1.0
	return minf(result,minf(_disk_entry(start,end,a,radius),_disk_entry(start,end,b,radius)))
static func _disk_entry(start:Vector2,end:Vector2,center:Vector2,radius:float)->float:
	var offset:=start-center
	if offset.length_squared()<=radius*radius: return 0.0
	var delta:=end-start
	var a:=delta.length_squared()
	if a<.000001: return 1.0
	var b:=2*offset.dot(delta)
	var c:=offset.length_squared()-radius*radius
	var disc:=b*b-4*a*c
	if disc<0: return 1.0
	var t:=(-b-sqrt(disc))/(2*a)
	return t if t>=0 and t<=1 else 1.0

const SAVE_ARRAYS := ["jobs","projectiles","hazards","motions","supports","visuals","marks"]
const Codec = preload("res://scripts/combat/b06_combat_state_codec.gd")
func capture_candidate(actor_to_id:Callable)->Dictionary:
	if not actor_to_id.is_valid() or not is_instance_valid(host): return {}
	var payload:={"version":1,"clock":clock,"serial":serial,"hazard_serial":host._hazard_serial,"effects":effects,"arrays":{},"receipts":[],"summon_attempts":[],"summon_owners":[],"shell_observations":[],"banner_extensions":[],"lock_slots":lock_slots}
	for key:String in SAVE_ARRAYS:
		var array:Array=host.get(key)
		for command:Dictionary in array:
			if not bool(command.get("b06_command",false)): return {}
		payload.arrays[key]=array
	for key:String in hit_receipts:
		var last:=key.rfind(":")
		var previous:=key.rfind(":",last-1)
		if last<0 or previous<0: return {}
		var actor:Variant=instance_from_id(int(key.substr(last+1)))
		if not is_instance_valid(actor): continue
		var id:Variant=actor_to_id.call(actor)
		if not id is String or id.is_empty(): return {}
		payload.receipts.append({"cast_id":key.substr(0,previous),"stage":int(key.substr(previous+1,last-previous-1)),"target_id":id,"count":int(hit_receipts[key].count),"expires":float(hit_receipts[key].expires)})
	for key:String in ["summon_attempts","shell_observations","banner_extensions","summon_owners"]:
		var source:Dictionary=host.summon_owners if key=="summon_owners" else get(key)
		for instance:Variant in source:
			var actor:Variant=instance_from_id(int(instance))
			if not is_instance_valid(actor): continue
			var id:Variant=actor_to_id.call(actor)
			if not id is String or id.is_empty(): return {}
			payload[key].append({"id":id,"value":source[instance]})
	var encoded:=Codec.encode(payload,actor_to_id)
	return encoded.value if encoded.ok else {}
func validate_candidate(value:Dictionary,id_to_actor:Callable)->bool:
	return not _decode_candidate(value,id_to_actor).is_empty()
func restore_candidate(value:Dictionary,id_to_actor:Callable)->bool:
	var decoded:=_decode_candidate(value,id_to_actor)
	if decoded.is_empty(): return false
	# Validation is complete before any mutation. Keep rebound anchor actors;
	# room restoration owns their health, transform, rewards and stable IDs.
	var next_anchors:Array=[]
	for effect:Dictionary in decoded.effects:
		var anchor:Node2D=host._anchor(effect)
		if is_instance_valid(anchor): next_anchors.append(anchor)
	for effect:Dictionary in effects:
		var anchor:Node2D=host._anchor(effect)
		if not is_instance_valid(anchor): continue
		for connection:Dictionary in anchor.health.depleted.get_connections():
			var callable:Callable=connection.callable
			if callable.get_object()==self and callable.get_method()=="_wall_broken": anchor.health.depleted.disconnect(callable)
		if anchor not in next_anchors: anchor.queue_free()
	for motion:Dictionary in host.motions:
		var owner:Node2D=host._owner(motion)
		if is_instance_valid(owner): owner.remove_meta("enemy_skill_motion")
	for key:String in SAVE_ARRAYS:
		var array:Array=host.get(key)
		array.clear()
		for command:Dictionary in decoded.arrays[key]: array.append(command)
	effects.clear()
	for effect:Dictionary in decoded.effects:
		effects.append(effect)
		if effect.kind=="wall": host._anchor(effect).health.depleted.connect(_wall_broken.bind(effect),CONNECT_ONE_SHOT)
	clock=float(decoded.clock)
	serial=int(decoded.serial)
	host._hazard_serial=int(decoded.hazard_serial)
	hit_receipts=decoded.hit_receipts
	summon_attempts=decoded.resolved_summon_attempts
	shell_observations=decoded.resolved_shell_observations
	banner_extensions=decoded.resolved_banner_extensions
	host.summon_owners=decoded.resolved_summon_owners
	lock_slots.clear()
	for slot:Dictionary in decoded.lock_slots: lock_slots.append(slot)
	for motion:Dictionary in host.motions: host._owner(motion).set_meta("enemy_skill_motion",true)
	return true
func _decode_candidate(value:Dictionary,resolver:Callable)->Dictionary:
	var unpacked:=Codec.decode(value,resolver)
	if not unpacked.ok or not unpacked.value is Dictionary: return {}
	var result:Dictionary=unpacked.value
	var keys:=["version","clock","serial","hazard_serial","effects","arrays","receipts","summon_attempts","summon_owners","shell_observations","banner_extensions","lock_slots"]
	if result.size()!=keys.size() or not result.has_all(keys) or result.version!=1: return {}
	for key:String in ["clock","serial","hazard_serial"]:
		if not Codec._number(result[key]) or float(result[key])<0: return {}
	if result.serial!=int(result.serial) or result.hazard_serial!=int(result.hazard_serial) or float(result.clock)>1e12: return {}
	if not result.arrays is Dictionary or result.arrays.size()!=SAVE_ARRAYS.size() or not result.arrays.has_all(SAVE_ARRAYS) or not result.effects is Array: return {}
	if not result.lock_slots is Array or result.lock_slots.size()>128: return {}
	for slot:Variant in result.lock_slots:
		if not slot is Dictionary or not slot.has_all(["at","owner"]) or not Codec._number(slot.at) or not slot.owner is WeakRef: return {}
		if float(slot.at)<float(result.clock)-.8 or float(slot.at)>float(result.clock)+60: return {}
	var count:int=result.effects.size()
	for key:String in SAVE_ARRAYS:
		if not result.arrays[key] is Array: return {}
		count+=result.arrays[key].size()
		for command:Variant in result.arrays[key]:
			if not _saved_command_valid(command): return {}
	for effect:Variant in result.effects:
		if not _saved_command_valid(effect) or str(effect.get("kind","")) not in ["mine","net","banner","wall","stance","bubble","haste","exposed","waterline","needle_return"]: return {}
		if not Codec._number(effect.get("remaining")) or float(effect.remaining)<=0 or float(effect.remaining)>8: return {}
		if effect.kind in ["mine","net","banner","wall"]:
			if not effect.get("anchor_ref") is WeakRef: return {}
			var anchor:Node2D=host._anchor(effect)
			if not host._alive(anchor) or not bool(anchor.get_meta("enemy_skill_anchor",false)) or not bool(Props.read(anchor,"static_actor",false)): return {}
			var owner:Variant=Props.read(anchor,"owner_enemy")
			if not owner is WeakRef or owner.get_ref()!=host._owner(effect): return {}
		if effect.kind in ["stance","bubble","haste","exposed"]:
			if not effect.get("target_ref") is WeakRef or not eligible(_target(effect)): return {}
			if effect.kind in ["stance","exposed"] and _target(effect)!=host._owner(effect): return {}
	if count>host.MAX_EFFECTS: return {}
	result["hit_receipts"]={}
	if not result.receipts is Array or result.receipts.size()>4096: return {}
	for receipt:Variant in result.receipts:
		if not receipt is Dictionary or receipt.size()!=5 or not receipt.has_all(["cast_id","stage","target_id","count","expires"]): return {}
		if not receipt.cast_id is String or not receipt.target_id is String: return {}
		for key:String in ["stage","count","expires"]:
			if not Codec._number(receipt[key]): return {}
		if receipt.stage!=int(receipt.stage) or receipt.stage<0 or receipt.stage>100 or receipt.count!=int(receipt.count) or receipt.count<0 or receipt.count>8 or float(receipt.expires)<float(result.clock) or float(receipt.expires)>float(result.clock)+30.001: return {}
		var actor:Variant=resolver.call(receipt.target_id)
		if not actor is Node2D or not is_instance_valid(actor): return {}
		var key:="%s:%d:%d"%[receipt.cast_id,int(receipt.stage),actor.get_instance_id()]
		if result.hit_receipts.has(key): return {}
		result.hit_receipts[key]={"count":int(receipt.count),"expires":float(receipt.expires)}
	for key:String in ["summon_attempts","shell_observations","banner_extensions","summon_owners"]:
		if not result[key] is Array or result[key].size()>128: return {}
		var restored:Dictionary={}
		for item:Variant in result[key]:
			if not item is Dictionary or item.size()!=2 or not item.has_all(["id","value"]) or not item.id is String: return {}
			var actor:Variant=resolver.call(item.id)
			if not actor is Node2D or not is_instance_valid(actor) or restored.has(actor.get_instance_id()): return {}
			if key=="summon_attempts" and (not Codec._number(item.value) or item.value!=int(item.value) or item.value<0 or item.value>2): return {}
			if key=="banner_extensions" and not item.value is bool: return {}
			if key=="summon_owners":
				if not item.value is Array or item.value.size()>2: return {}
				for ref:Variant in item.value:
					if not ref is WeakRef: return {}
			if key=="shell_observations":
				if not item.value is Dictionary or not item.value.has_all(["amount","remaining","absorbed"]): return {}
				for number:Variant in item.value.values():
					if not Codec._number(number) or float(number)<0: return {}
			restored[actor.get_instance_id()]=item.value
		result["resolved_"+key]=restored
	return result
func _saved_command_valid(command:Variant)->bool:
	if not command is Dictionary or not bool(command.get("b06_command",false)) or not command.get("owner") is WeakRef: return false
	var caster:Node2D=command.owner.get_ref()
	if not host._alive(caster) or str(command.get("caster_enemy_id",""))!=str(Props.read(caster,"enemy_id","")): return false
	if not command.get("origin") is Vector2 or not command.get("direction") is Vector2: return false
	for key:String in ["remaining","duration","elapsed","delay"]:
		if command.has(key) and (not Codec._number(command[key]) or float(command[key])<0 or float(command[key])>60): return false
	var allowed:Dictionary={"B06-M01":[0,100,110,40],"B06-M02":[0,100,40],"B06-M03":[0,100],"B06-M04":[0,100,85,30],"B06-M05":[0,100],"B06-M06":[0,100],"B06-M07":[0,100,90,40],"B06-M08":[0,100],"B06-M09":[0,100,120,40],"B06-M10":[0,100,90,40],"B06-M11":[0,100,110],"B06-M12":[0,100,25],"B06-M13":[0,100],"B06-M14":[0,100,115,30],"B06-M15":[0,100,45],"B06-M16":[0,100,60,40],"B06-M17":[0,100,120],"B06-M18":[0,100,40],"BO06":[0,70,80,85,90,115]}
	if not Codec._number(command.get("coefficient")) or command.coefficient!=int(command.coefficient): return false
	if not allowed.has(str(caster.enemy_id)) or int(command.coefficient) not in allowed[str(caster.enemy_id)]: return false
	if int(command.get("max_target_hits",1))<1 or int(command.get("max_target_hits",1))>2: return false
	if bool(command.get("continuous",false)) and str(caster.enemy_id) not in ["B06-M02","B06-M05","B06-M12"]: return false
	if int(command.get("stage",0))<0 or int(command.get("stage",0))>100: return false
	for key:String in ["range","radius","width","travel_distance"]:
		if command.has(key) and (not Codec._number(command[key]) or float(command[key])<0 or float(command[key])>600): return false
	if command.has("damage"):
		var frozen:=Skills.freeze_damage(command,caster.profile)
		if frozen.is_empty() or command.damage!=frozen.damage: return false
		command["damage"]=int(frozen.damage)
	for key:String in ["coefficient","stage","stage_count","difficulty","b06_phase","ruleset_version","scale_version","enemy_command_version","count","max_target_hits"]:
		if command.has(key):
			if not Codec._number(command[key]) or command[key]!=int(command[key]): return false
			command[key]=int(command[key])
	return true

## D4 ordinary combinations reserve damaging lock points at least0.8s apart.
## Bosses are excluded: this cannot inflate Boss timings or its output window.
func _coordinated(command:Dictionary)->bool:
	return int(command.get("difficulty",0))>=4 and str(command.get("caster_enemy_id",""))!="BO06" and (int(command.get("coefficient",0))>0 or str(command.get("kind",""))=="b06_mine")
func admit_lock(caster:Node2D,command:Dictionary)->bool:
	if not _coordinated(command): return true
	for slot:Dictionary in lock_slots:
		if absf(float(slot.at)-clock)<.8-.000001: return false
	lock_slots.append({"at":clock,"owner":weakref(caster)})
	return true
func _reserve_lock(caster:Node2D,earliest:float)->float:
	var time:=earliest
	var ordered:Array=lock_slots.duplicate()
	ordered.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.at)<float(b.at))
	for slot:Dictionary in ordered:
		if absf(float(slot.at)-time)<.8-.000001: time=float(slot.at)+.8
	lock_slots.append({"at":time,"owner":weakref(caster)})
	return time
