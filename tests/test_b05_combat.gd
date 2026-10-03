extends SceneTree
## Focused B05 executable contract, real common runtime and deterministic actors.
## Runs in an isolated project with no Game autoload or production save access.
const Skills = preload("res://scripts/combat/b05_enemy_skills.gd")
const Numbers = preload("res://scripts/combat/b05_enemy_numbers.gd")
const Brain = preload("res://scripts/combat/b05_enemy_brain.gd")
const KingBrain = preload("res://scripts/combat/b05_boss_brain.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
const Health = preload("res://scripts/combat/health.gd")
const Status = preload("res://scripts/combat/combat_status.gd")
class Actor extends Node2D:
	var room: Node2D
	var health=Health.new()
	var status=Status.new(2)
	var state: StringName=&"chase"
	var state_time:=0.0
	var enemy_id:="B05-M01"
	var actor_kind:="enemy"
	var rank:="normal"
	var zone_index:=0
	var profile: Dictionary={}
	var velocity:=Vector2.ZERO
	var aim_direction:=Vector2.RIGHT
	var knockback:=Vector2.ZERO
	var navigation_radius:=18.0
	var collision_radius:=12.0
	var move_speed:=60.0
	var contact_damage:=300.0
	var reward_enabled:=true
	var owner_enemy: WeakRef
	var hits: Array=[]
	var statuses: Array=[]
	var emitted: Array=[]
	var hazard_events: Array=[]
	var accepts:=true
	var phase_events: Array=[]
	var slow_remaining:=0.0
	func clear_ordinary_slow() -> void: slow_remaining=0
	func apply_ordinary_slow(_multiplier: float,duration: float) -> void: slow_remaining=duration
	func _init() -> void: add_child(health); health.reset(100000,2)
	func is_alive() -> bool: return not health.dead and not is_queued_for_deletion()
	func receive_damage(amount: float, origin: Vector2) -> bool:
		if not accepts: return false
		hits.append({"damage":amount,"origin":origin})
		return health.damage(amount)
	func take_damage(amount: float, kind: StringName, direction: Vector2=Vector2.ZERO, context: Dictionary={}) -> bool:
		amount=room.enemy_skills.b05.filter_damage(self,amount,kind,direction,str(context.get("damage_type","physical")))
		return health.damage(amount)
	func receive_enemy_status(effect: Dictionary) -> bool: statuses.append(effect.duplicate()); return true
	func dash_protected() -> bool: return not accepts
	func heal(amount: float) -> float:
		var before: float=health.current
		health.current=minf(float(health.maximum),before+amount)
		return float(health.current)-before
	func cast_enemy_skill(command: Dictionary) -> void: emitted.append(command.duplicate(true)); room.enemy_skills.emit_skill(self,command)
	func boss_phase_started(value: int, _ratio: float) -> void: phase_events.append(value); room.enemy_skills.cancel_owner(self)
	func boss_weakpoint_changed(_open: bool, _id: String, _duration: float) -> void: pass
	func notify_hostile_hazard(id: String, inside: bool, damaged: bool=false) -> void: hazard_events.append([id,inside,damaged])
class Mechanisms extends RefCounted:
	var online:=true
	var phase:=1
	var mode:="shield"
	func connected(_actor: Node2D) -> bool: return online
	func nearest_active_well(_point: Vector2) -> Dictionary: return {"id":"well","position":Vector2(600,400),"mode":mode} if online else {}
	func set_well_mode(_actor: Node2D, value: String, _duration: float) -> bool: mode=value; return online
	func boss_root_state() -> Dictionary: return {"active_count":mini(phase,2) if online else 0,"active_positions":[Vector2(600,400),Vector2(900,400)] if online else []}
	func boss_phase_changed(value: int) -> void: phase=value
	func all_wells_closed() -> bool: return not online
class Room extends Node2D:
	var enemies=Node2D.new()
	var player: Actor
	var enemy_skills: Node2D
	var b05_mechanics=Mechanisms.new()
	var spawned: Array=[]
	var wall_x:=INF
	func _init() -> void: add_child(enemies)
	func enemy_skill_targets() -> Array: return [player]
	func has_line_of_sight(start: Vector2,end: Vector2) -> bool: return blocked_fraction(start,end)>=1
	func blocked_fraction(start: Vector2,end: Vector2,_radius: float=0) -> float:
		return clampf((wall_x-start.x)/maxf(.0001,end.x-start.x),0,1) if end.x>wall_x and start.x<=wall_x else 1.0
	func move_actor(start: Vector2,displacement: Vector2,radius: float) -> Vector2: return start+displacement*blocked_fraction(start,start+displacement,radius)
	func navigation_direction(start: Vector2,end: Vector2,_radius: float) -> Vector2: return start.direction_to(end)
	func spawn_enemy_summon(owner: Node2D,id: String,at: Vector2) -> Node2D:
		if enemies.get_child_count()>=18: return null
		var a=Actor.new()
		a.enemy_id=id; a.room=self; a.position=at; a.profile=Skills.profile(id,25,4); a.health.reset(float(a.profile.max_hp),2); a.owner_enemy=weakref(owner); a.reward_enabled=false
		enemies.add_child(a); spawned.append(a); return a
	func spawn_enemy_skill_anchor(owner: Node2D,at: Vector2,hp: float,_kind: String) -> Node2D:
		if enemies.get_child_count()>=18: return null
		var a=Actor.new()
		a.room=self; a.position=at; a.health.reset(hp,2); a.actor_kind="objective"; a.reward_enabled=false; a.owner_enemy=weakref(owner)
		enemies.add_child(a); spawned.append(a); return a
var checks:=0
var failures:=0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B05 COMBAT: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	catalog_contract()
	for d in [0,2,4]:
		for i in range(1,19): runtime_contract("B05-M%02d"%i,d)
	heal_and_share_contract()
	brain_contract()
	boss_contract()
	specific_mechanics_contract()
	print("B05 combat: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
func fixture(id: String="B05-M01",d: int=0) -> Room:
	var room=Room.new(); root.add_child(room); room.process_mode=Node.PROCESS_MODE_DISABLED
	room.enemy_skills=Runtime.new(); room.add_child(room.enemy_skills); room.enemy_skills.configure(room)
	room.player=Actor.new(); room.player.actor_kind="player"; room.player.position=Vector2(220,100); room.player.room=room; room.add_child(room.player)
	return room
func actor(room: Room,id: String,d: int,at: Vector2=Vector2(100,100)) -> Actor:
	var a=Actor.new(); a.room=room; a.enemy_id=id; a.position=at; a.profile=Skills.boss_profile(d) if id=="BO05" else Skills.profile(id,25,d); a.health.reset(float(a.profile.max_hp),2); a.rank=str(a.profile.rank); room.enemies.add_child(a); return a
func catalog_contract() -> void:
	for d in range(5):
		for i in range(1,19):
			var id:="B05-M%02d"%i
			var p:=Skills.profile(id,25,d)
			check(not p.is_empty() and p.biome_id=="B05" and p.enemy_id==id,"profile "+id)
			var c:=Skills.active(p,Vector2(100,100),Vector2(220,100),true)
			check(c.ability_id.begins_with(id) and c.active,"independent active "+id)
			check(float(c.cooldown)==float(Skills.CDS[i-1]),"authored CD "+id)
			check(float(c.tell)>0 and float(c.lock)>=.22,"bounded warning "+id)
			check(c.timing.tell_factor==preload("res://scripts/combat/enemy_warning_timing.gd").TELL_FACTORS[d],"same warning authority")
			var frozen:=Skills.freeze_damage(c,p)
			check(int(frozen.damage)==Numbers.skill_damage(Numbers.ordinary(id,25,d),int(c.coefficient)),"one numerical packet "+id)
			for follow: Dictionary in c.followups: check(follow.followups.is_empty(),"finite nonrecursive followup")
			if i in [4,14]: check(float(c.tell)+float(c.lock)>=1.2 if i==4 else float(c.tell)+float(c.lock)>=1.5,"full visible channel")
		for action: String in Skills.BOSS_ACTIONS:
			var c:=Skills.boss_action(Skills.boss_profile(d),action,Vector2.ZERO,Vector2(160,0),3)
			check(c.is_empty()==(d<int(Skills.BOSS_GATES[Skills.BOSS_ACTIONS.find(action)])),"boss exact gate")
	check(Skills.profile("M01",25,4).is_empty(),"legacy identity not rerouted")
	check(Skills.profile("B06-M01",25,4).is_empty(),"future identity rejected")
func runtime_contract(id: String,d: int) -> void:
	var room=fixture(id,d); var caster=actor(room,id,d)
	var ally=actor(room,"B05-M01",d,Vector2(150,145)); ally.health.current=float(ally.health.maximum)*.5
	var other=actor(room,"B05-M02",d,Vector2(200,160))
	var c:=Skills.active(caster.profile,caster.position,room.player.position,true)
	if str(c.kind) in ["b05_heal","b05_share"]: c.b05_target_refs=room.enemy_skills.b05.support_targets(caster,c)
	room.enemy_skills.emit_skill(caster,c)
	for step in range(45): room.enemy_skills.advance(.2)
	check(room.enemy_skills.active_effect_count()<128,"finite runtime "+id+" D"+str(d))
	for hit: Dictionary in room.player.hits: check(hit.damage==roundf(hit.damage) and hit.damage>=0,"integer actual hit")
	for child: Actor in room.spawned: check(not child.reward_enabled,"derived objects have no rewards")
	room.enemy_skills.cancel_owner(caster)
	check(room.enemy_skills.active_effect_count()==0,"owner cancellation "+id)
	room.free()
func heal_and_share_contract() -> void:
	var room=fixture(); var healer=actor(room,"B05-M04",4); var ally=actor(room,"B05-M01",4,Vector2(150,100)); var other=actor(room,"B05-M02",4,Vector2(175,100))
	var boss=actor(room,"BO05",4,Vector2(125,100)); boss.actor_kind="boss"
	var objective=actor(room,"B05-M01",4,Vector2(120,100)); objective.actor_kind="objective"
	for a in [ally,boss,objective]: a.health.current=1
	var c:=Skills.active(healer.profile,healer.position,ally.position,true)
	c.b05_target_refs=[weakref(ally)]
	var maximum: float=ally.health.maximum
	for i in range(8):
		room.enemy_skills.emit_skill(healer,c)
		ally.health.current=1
	check(float(room.enemy_skills.b05.healed[ally.get_instance_id()])<=roundf(maximum*.25),"lifetime external heal <=25%")
	check(float(ally.status.shield())<=roundf(maximum*.06),"dew shield replacement")
	var refs: Array=room.enemy_skills.b05.support_targets(healer,c)
	for ref: WeakRef in refs: check(ref.get_ref()!=boss and ref.get_ref()!=objective,"no boss/objective recipients")
	var weaver=actor(room,"B05-M08",4)
	var link:=Skills.active(weaver.profile,weaver.position,room.player.position,true)
	link.b05_target_refs=[weakref(ally),weakref(other)]
	room.enemy_skills.emit_skill(weaver,link)
	ally.health.current=maximum; other.health.current=other.health.maximum
	var before: float=other.health.current
	var filtered: float=room.enemy_skills.b05.filter_damage(ally,100,&"primary",Vector2.LEFT,"physical")
	check(filtered==80 and before-float(other.health.current)==20,"single nonrecursive 20% share")
	other.position=Vector2(900,100)
	check(room.enemy_skills.b05.filter_damage(ally,100,&"primary",Vector2.LEFT,"physical")==100,"distance>300 breaks sharing")
	room.free()
func brain_contract() -> void:
	var room=fixture(); var caster=actor(room,"B05-M04",4); var ally=actor(room,"B05-M01",4,Vector2(150,100)); ally.health.current=1
	var brain=Brain.new(); brain.configure(caster.profile)
	for i in range(20): brain.tick(caster,.1,room.player)
	check(brain.phase in [&"telegraph",&"locked"],"healing channel visible")
	brain.on_damaged(caster,{"kind":"primary","interrupt":true})
	check(brain.cooldown>=5 and caster.emitted.is_empty(),"interrupt half CD and no heal release")
	room.free()
	room=fixture(); caster=actor(room,"B05-M14",4); brain=Brain.new(); brain.configure(caster.profile)
	for i in range(23): brain.tick(caster,.1,room.player)
	if brain.phase==&"locked":
		var locked:=brain.current_telegraph()
		room.player.position=Vector2(100,220)
		brain.tick(caster,.05,room.player)
		check(brain.current_telegraph().get("direction")==locked.direction,"locked geometry cannot retarget")
	for i in range(10): brain.tick(caster,.1,room.player)
	check(caster.emitted.size()==1,"one active release")
	check(brain.cooldown>9,"full CD starts release")
	room.free()
func boss_contract() -> void:
	var room=fixture(); var boss=actor(room,"BO05",4); boss.actor_kind="boss"; var brain=KingBrain.new(); brain.configure(boss.profile)
	check("pod_rain" not in brain.available_actions(1) and "bloom_transplant" not in brain.available_actions(1),"P1 single-root teaching excludes pods")
	check("pod_rain" in brain.available_actions(2) and "season_bloom" not in brain.available_actions(2),"P2 pods before P3 season bloom")
	check("season_bloom" in brain.available_actions(3),"P3 seasonal root rotation")
	brain.tick(boss,.1,room.player)
	check(brain.incoming_damage_multiplier()==.65,"root network mitigation35%")
	check(brain.apply_arena_counter("b05_root_well",{"well_id":"a"}),"root destroyed")
	check(brain.incoming_damage_multiplier()==1.15 and brain.weakpoint_time==4,"four second flower opening")
	brain.tick(boss,4.1,room.player)
	check(brain.apply_arena_counter("b05_root_well",{"well_id":"b"}) and not brain.weakpoint_open(),"exposure >=10second ICD")
	boss.health.current=float(boss.health.maximum)*.34
	brain.tick(boss,.01,room.player)
	check(brain.phase==3 and brain.state==&"phase_shift" and brain.state_duration==1.2,"phase thresholds and clear preparation")
	check(room.b05_mechanics.phase==3,"phase root activation seam")
	brain.elapsed=11
	check(brain.apply_arena_counter("b05_root_well",{"well_id":"c"}) and brain.weakpoint_open(),"ICD later allows new exposure")
	var summon:=Skills.boss_action(boss.profile,"bloom_transplant",boss.position,Vector2(350,100),3)
	for i in range(4):
		room.enemy_skills.emit_skill(boss,summon)
		for child: Node2D in room.spawned: child.health.dead=true
	check(int(room.enemy_skills.b05.summon_attempts[boss.get_instance_id()])==2 and room.spawned.size()==4,"two attempts, two adds each, lifetime finite")
	for child: Actor in room.spawned: check(child.health.maximum==roundf(float(child.profile.max_hp)*.5) and not child.reward_enabled,"half-HP no-reward derived M02")
	room.free()

func specific_mechanics_contract() -> void:
	var room=fixture(); var caster=actor(room,"B05-M02",4)
	var command:=Skills.active(caster.profile,caster.position,room.player.position,true)
	room.enemy_skills.emit_skill(caster,command)
	check(room.player.hits.is_empty(),"M02 no hit before seed flight")
	room.enemy_skills.advance(.34)
	check(room.player.hits.is_empty(),"M02 locked seed not early")
	room.enemy_skills.advance(.02)
	check(room.player.hits.size()==1 and room.enemy_skills.hazards.size()==1,"M02 main impact + D4 slow area")
	check(not room.player.hazard_events.is_empty(),"actual slow area event exists")
	var hazard_id: String=room.enemy_skills.hazards[0].hazard_id
	room.player.position=Vector2(800,600)
	room.enemy_skills.advance(.1)
	check(room.player.hazard_events.back()==[hazard_id,false,false],"same hazard ID actual exit")
	room.free()
	room=fixture(); caster=actor(room,"B05-M01",4)
	command=Skills.active(caster.profile,caster.position,room.player.position,true)
	room.enemy_skills.emit_skill(caster,command); room.enemy_skills.advance(.21)
	check(room.enemy_skills.hazards.size()==1,"M01 D2 root line exists")
	room.b05_mechanics.online=false; room.enemy_skills.advance(.1)
	check(room.enemy_skills.hazards.is_empty(),"root shutdown cancels existing line")
	var count: int=room.player.hits.size(); room.enemy_skills.advance(3)
	check(room.player.hits.size()==count,"root shutdown cancels delayed D4 flower")
	room.free()
	room=fixture(); caster=actor(room,"B05-M04",4)
	var ally=actor(room,"B05-M01",4,Vector2(150,100)); ally.health.current=1; ally.slow_remaining=3; ally.status.apply("chill",100,3)
	command=Skills.active(caster.profile,caster.position,ally.position,true); command.b05_target_refs=[weakref(ally)]
	room.enemy_skills.emit_skill(caster,command)
	check(ally.slow_remaining==0 and ally.status.has("chill"),"D2 clears ordinary slow only")
	room.free()
	room=fixture(); caster=actor(room,"B05-M06",4); caster.set_meta("b05_leaf_guard",true)
	check(room.enemy_skills.b05.filter_damage(caster,100,&"primary",Vector2.LEFT,"physical")==80,"leaf stance20% mitigation")
	check(room.enemy_skills.b05.filter_damage(caster,100,&"primary",Vector2.LEFT,"true")==100,"true damage bypasses leaf mitigation")
	room.free()
	room=fixture(); caster=actor(room,"B05-M08",4); ally=actor(room,"B05-M01",4,Vector2(150,100)); var other=actor(room,"B05-M02",4,Vector2(180,100))
	command=Skills.active(caster.profile,caster.position,room.player.position,true); command.b05_target_refs=[weakref(ally),weakref(other)]
	room.enemy_skills.emit_skill(caster,command)
	check(room.enemy_skills.movement_multiplier(ally)==1.08 and caster.status.shield()==roundf(float(caster.health.maximum)*.1),"weaver D2 speed/D4 self guard")
	room.free()
	room=fixture(); caster=actor(room,"B05-M11",4)
	command=Skills.active(caster.profile,caster.position,room.player.position,true); room.enemy_skills.emit_skill(caster,command)
	check(room.enemy_skills.b05.filter_damage(caster,100,&"primary",Vector2.LEFT,"physical")==65,"resin frontal35%")
	check(room.enemy_skills.b05.filter_damage(caster,100,&"primary",Vector2.RIGHT,"physical")==100,"resin flank open")
	room.free()
	room=fixture(); caster=actor(room,"B05-M16",4)
	command=Skills.active(caster.profile,caster.position,room.player.position,true); room.player.position=Vector2(900,600)
	room.enemy_skills.emit_skill(caster,command); room.enemy_skills.advance(.7)
	var shells: Array=[]
	for e: Dictionary in room.enemy_skills.b05.effects:
		if e.kind=="shell": shells.append(e)
	check(shells.size()==2,"only two outer rounds leave shells")
	if shells.size()==2:
		check(Vector2(shells[0].direction).y<0 and Vector2(shells[1].direction).y>0,"shell explosions face away from safe fan gap")
		check(float(shells[0].angle)<=PI*.5,"outward90degree blasts")
	room.free()
	room=fixture(); caster=actor(room,"B05-M18",4); ally=actor(room,"B05-M01",4,Vector2(150,100))
	command=Skills.active(caster.profile,caster.position,room.player.position,true,1); room.enemy_skills.emit_skill(caster,command)
	check(room.b05_mechanics.mode=="speed" and room.enemy_skills.movement_multiplier(ally)==1.08,"M18 alternate speed mode")
	check(is_equal_approx(room.enemy_skills.b05.filter_damage(caster,100,&"primary",Vector2.LEFT,"physical"),115),"M18 exposure15%")
	var attack:=Skills.basic(ally.profile,ally.position,room.player.position)
	var first: Dictionary=room.enemy_skills.b05.prepare(ally,attack)
	var second: Dictionary=room.enemy_skills.b05.prepare(ally,attack)
	check(first.coefficient==120 and second.coefficient==100,"one nonstacking flower mark consumes once")
	room.free()
