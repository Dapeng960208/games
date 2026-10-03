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
			for i in mini(raw.size(),1 if int(host.room.difficulty)<2 else 2):
				_spawn_core(first,i,roundf(float(first.profile.max_hp)*.6),false)
	for effect: Dictionary in effects.duplicate():
		effect.remaining=float(effect.remaining)-delta
		var target: Node2D=effect.target.get_ref()
		if effect.remaining<=0 or not host._alive(target): effects.erase(effect)
	# Receipts are bounded by recent combat time, not by the chapter duration.
	for key: String in hit_receipts.keys():
		if clock-float(hit_receipts[key])>12: hit_receipts.erase(key)

func _first_enemy() -> Node2D:
	for child: Node in host.room.enemies.get_children():
		if child is Node2D and host._alive(child) and str(Props.read(child,"enemy_id","")).begins_with("B10-M"): return child
	return null

func can_lock(caster: Node2D) -> bool:
	var active := 0
	for child: Node in host.room.enemies.get_children():
		if child==caster or not host._alive(child): continue
		if str(Props.read(child,"state","")) in ["telegraph","locked","windup"]: active+=1
	return active<2

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
			var end: Vector2=points[1]
			c.origin=start
			c.target=end
			c.direction=start.direction_to(end)
			c.range=start.distance_to(end)
			c.points=[start,end]
			c["gate_endpoints"]=[start,end]
	# During accepted transit, a new tracked landing attack cannot be placed
	# onto the reserved landing disk. Existing published commands are untouched.
	var player: Variant=Props.read(host.room,"player")
	if player is Node2D and float(player.get_meta("b10_portal_landing_until",0))>clock and str(c.kind)=="ground_area":
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
			if host._alive(ref.get_ref()): effects.append({"kind":"echo_mark","target":ref,"remaining":8.0})
	elif kind=="b10_scale_stone":
		var stone: Node2D=host.room.spawn_enemy_skill_anchor(caster,Vector2(c.target),float(c.anchor_health),"b10_scale_stone")
		if is_instance_valid(stone):
			stone.health.depleted.connect(func() -> void:
				if host._alive(caster) and int(c.difficulty)>=4 and caster.brain!=null and caster.brain.has_method("interrupt"): caster.brain.interrupt(caster))
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
		step=Skills.freeze_damage(step,caster.profile)
		step["remaining"]=maxf(.15,float(step.get("delay",.9)))
		host.jobs.append(step)
	# Delayed effects do not recursively schedule another echo or followup.
	if bool(c.get("derived",false)) or int(c.get("coefficient",0))<=0: return
	var marked := false
	for effect: Dictionary in effects.duplicate():
		if str(effect.kind)=="echo_mark" and effect.target.get_ref()==caster:
			marked=true
			effects.erase(effect)
			break
	var id: int=caster.get_instance_id()
	if (bool(c.get("b10_echo",false)) or marked) and connected(caster) and clock>=float(echo_ready.get(id,0)):
		var echo := Skills.child(c,str(c.kind),str(c.shape),25,.9)
		echo.merge({"owner":c.owner,"owner_id":c.owner_id,"cast_id":c.cast_id,"stage":99,"core_required":true,"b10_echo":false},true)
		echo=Skills.freeze_damage(echo,caster.profile)
		echo["remaining"]=.9
		host.jobs.append(echo)
		echo_ready[id]=clock+10

func allow_hit(victim: Node2D,c: Dictionary) -> bool:
	if not bool(c.get("b10_cross_gate",false)) and Geometry.zone_at(str(host.room.layout_id),victim.position)!=str(c.get("source_zone",Geometry.zone_at(str(host.room.layout_id),Vector2(c.origin)))): return false
	var key := "%s:%d:%d"%[str(c.get("cast_id","")),int(c.get("stage",0)),victim.get_instance_id()]
	if hit_receipts.has(key): return false
	hit_receipts[key]=clock
	return true

func filter_damage(target: Node2D,amount: float,_kind: StringName,direction: Vector2,damage_type: String) -> float:
	if damage_type=="true": return amount
	for effect: Dictionary in effects:
		if effect.target.get_ref()!=target: continue
		if str(effect.kind) in ["guard","stance"] and direction.normalized().dot(Vector2(effect.direction))<-.35: amount*=.65
	return amount

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
		canvas.draw_arc(at,31,0,TAU,32,Color("c89be1"),3,true)
		canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-46),at+Vector2(17,-27),at+Vector2(0,-8),at+Vector2(-17,-27)]),Color("bb8bdd"))
		canvas.draw_line(at+Vector2(0,-44),at+Vector2(0,-10),Color("fff6c9"),2,true)
		canvas.draw_rect(Rect2(at+Vector2(-24,7),Vector2(48*core.health.current/core.health.maximum,4)),Color("8a65b7"))
		for id: int in links:
			var actor: Object=instance_from_id(id)
			if int(links[id])==index and host._alive(actor): canvas.draw_line(at,actor.position,Color(.78,.58,.87,.55),2,true)
