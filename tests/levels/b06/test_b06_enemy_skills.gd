extends Node
const Skills=preload("res://scripts/levels/b06/combat/enemy_skills.gd")
const Runtime=preload("res://scripts/gameplay/monsters/enemy_skill_runtime.gd")
const Enemy=preload("res://scripts/gameplay/monsters/enemy_actor.gd")
class Victim extends Node2D:
	var hits: Array=[]
	var states: Array=[]
	var navigation_radius:=12.0
	func is_alive()->bool: return true
	func receive_damage(amount: float,_origin: Vector2)->bool:
		hits.append(amount)
		return true
	func receive_enemy_status(effect: Dictionary)->bool:
		states.append(effect)
		return true
class Arena extends Node2D:
	var enemy_skills: Node2D
	var b06_mechanics: Variant=null
	var enemies:=Node2D.new()
	var victim:=Victim.new()
	var blocked:=false
	func enemy_skill_targets()->Array: return [victim]
	func enemy_died(_actor:Node2D)->void: pass
	func spawn_enemy_skill_anchor(caster:Node2D,at:Vector2,hp:float,kind:String)->Node2D:
		var anchor:=Enemy.new()
		anchor.room=self
		anchor.position=at
		anchor.configure({"ruleset_version":2,"max_hp":hp,"navigation_radius":10.0},{"owner":caster,"reward_enabled":false,"static_actor":true,"actor_kind":"hazard_endpoint"})
		enemies.add_child(anchor)
		anchor.set_meta("enemy_skill_anchor_kind",kind)
		return anchor
	func blocked_fraction(_a: Vector2,_b: Vector2,_r: float=0)->float: return .5 if blocked else 1.0
	func has_line_of_sight(_a:Vector2,_b:Vector2)->bool: return not blocked
	func move_actor(start: Vector2,displacement: Vector2,_r:float)->Vector2: return start+displacement*(.5 if blocked else 1)
	func navigation_direction(a:Vector2,b:Vector2,_r:float)->Vector2: return a.direction_to(b)
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value: failures+=1; push_error("B06 SKILLS "+label)
func _ready()->void: _run.call_deferred()
func _run()->void:
	var arena:=Arena.new()
	arena.visible=false
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(arena)
	arena.add_child(arena.enemies)
	arena.add_child(arena.victim)
	arena.enemy_skills=Runtime.new()
	arena.add_child(arena.enemy_skills)
	arena.enemy_skills.configure(arena)
	for n in range(1,19):
		for d in 5:
			var id:="B06-M%02d"%n
			var p:=Skills.profile(id,30,d)
			check(not p.is_empty(),id+" lawful profile")
			check(bool(p.b06_candidate_contact_only)==not Skills.implemented(id),id+" honest coverage")
			if not Skills.implemented(id): continue
			var actor:=Enemy.new()
			actor.room=arena
			actor.configure(p,{"reward_enabled":false})
			arena.enemies.add_child(actor)
			check(actor.brain.get_script()==preload("res://scripts/levels/b06/combat/enemy_brain.gd"),id+" real actor factory")
			actor.state=&"execute"
			var c:=Skills.active(p,Vector2.ZERO,Vector2(100,0),true,true)
			check(c.active and c.cooldown==Skills.CDS[n-1],id+" authored cooldown")
			check(float(c.tell)>=float(c.timing.minimum_tell_seconds) and float(c.lock)>=.22,id+" shared warning floors")
			var frozen:=Skills.freeze_damage(c,p)
			check(int(frozen.damage)==Skills.Numbers.skill_damage(p,int(c.coefficient)),id+" single damage resolution")
			arena.victim.hits.clear()
			arena.victim.position=Vector2(100,0)
			actor.cast_enemy_skill(c)
			for step in 180: arena.enemy_skills.advance(1.0/60.0)
			check(arena.victim.hits.size()>0 or n in [5,8,13,18],id+" actual release reaches receive_damage D"+str(d))
			check(arena.victim.hits.size()<=4,id+" finite single/explicit stages")
			arena.enemy_skills.cancel_owner(actor)
			check(arena.enemy_skills.jobs.is_empty() and arena.enemy_skills.motions.is_empty() and arena.enemy_skills.hazards.is_empty(),id+" actor cancellation")
			actor.free()
	# Concrete support, breakable and finite-control behavior with real actors.
	var allies: Array[Node2D]=[]
	for n in [5,1,4,13,3,6,15,16,18]:
		var ally:=Enemy.new()
		ally.room=arena
		ally.configure(Skills.profile("B06-M%02d"%n,30,4),{"reward_enabled":false})
		arena.enemies.add_child(ally)
		ally.state=&"execute"
		ally.position=Vector2(allies.size()*12,0)
		allies.append(ally)
	var priest:Node2D=allies[0]
	var shield:=Skills.active(priest.profile,priest.position,Vector2(100,0),false,false)
	shield["b06_target_refs"]=arena.enemy_skills.b06.support_targets(priest,shield)
	check(shield.b06_target_refs.size()==2,"D4 priest freezes two eligible recipients")
	priest.cast_enemy_skill(shield)
	for ref:WeakRef in shield.b06_target_refs:
		var ally:Node2D=ref.get_ref()
		check(int(ally.status.shield())==int(round(float(ally.health.maximum)*.05)),"actual five-percent bubble shield")
		check(float(ally.status.guards.b06_bubble.remaining)==5,"bubble finite lifetime")
	var first:Node2D=shield.b06_target_refs[0].get_ref()
	arena.victim.position=first.position
	first.status.absorb(float(first.status.shield()))
	first.status.tick(.01)
	arena.enemy_skills.advance(.01)
	check(not arena.victim.states.is_empty() and arena.victim.states.back().id=="slow" and arena.victim.states.back().magnitude==.9,"actual broken bubble hostile slow")
	var bell:Node2D=allies[3]
	for ally:Node2D in allies:
		if ally.brain!=null: ally.brain.cooldown=.5
	var haste:=Skills.active(bell.profile,bell.position,Vector2(100,0),false,false)
	haste["b06_target_refs"]=arena.enemy_skills.b06.support_targets(bell,haste)
	bell.cast_enemy_skill(haste)
	for ref:WeakRef in haste.b06_target_refs: check(is_equal_approx(ref.get_ref().brain.cooldown,.1),"bell cannot zero ally cooldown")
	check(arena.enemy_skills.movement_multiplier(haste.b06_target_refs[0].get_ref())==1.1,"bell actual three-second haste")
	var guard:Node2D=allies[4]
	var stance:=Skills.active(guard.profile,guard.position,Vector2(150,0),false,false)
	guard.cast_enemy_skill(stance)
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(guard,100,&"primary",Vector2.LEFT,"physical"),65),"frontal shield stance35percent")
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(guard,100,&"primary",Vector2.RIGHT,"physical"),100),"shield flank unprotected")
	var mine:Node2D=allies[5]
	var cast:=Skills.active(mine.profile,mine.position,Vector2(100,0),false,false)
	mine.cast_enemy_skill(cast)
	var mine_effects:Array=[]
	for effect:Dictionary in arena.enemy_skills.b06.effects:
		if effect.kind=="mine": mine_effects.append(effect)
	check(mine_effects.size()==1,"first breakable mine exists before second throw")
	var anchor:Node2D=arena.enemy_skills._anchor(mine_effects[0])
	check(anchor!=null and not anchor.reward_enabled,"mine attackable and no farming reward")
	# The actual health component reports depletion; its actor is not kept alive
	# to manufacture a hit. Directed disarm is excluded from strength evidence.
	anchor.health.current=0
	anchor.health.dead=true
	arena.victim.hits.clear()
	arena.enemy_skills.advance(.1)
	check(not arena.enemy_skills.b06.effects.has(mine_effects[0]),"dead mine safely disarmed")
	check(arena.victim.hits.is_empty(),"mine disarm emits no blast")
	var shell:Node2D=allies[6]
	var shell_cast:=Skills.active(shell.profile,shell.position,Vector2(150,0),false,false)
	shell.cast_enemy_skill(shell_cast)
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(shell,100,&"primary",Vector2.RIGHT,"physical"),60),"closed clam40percent reduction")
	var net:Node2D=allies[7]
	arena.victim.position=Vector2(100,0)
	net.cast_enemy_skill(Skills.active(net.profile,net.position,arena.victim.position,false,false))
	check(arena.victim.states.back().id=="root" and arena.victim.states.back().duration==.6,"net actual0.6root")
	var banner:Node2D=allies[8]
	banner.cast_enemy_skill(Skills.active(banner.profile,banner.position,arena.victim.position,false,false))
	check(arena.enemy_skills.b06.tide_guard_extension(first)==2,"banner local tide extension")
	first.status.grant_guard(100,6,"b06_tide_shell",float(first.health.maximum))
	arena.enemy_skills.advance(.01)
	check(first.status.guards.b06_tide_shell.remaining==8,"banner extends tide shield exactlytwo")
	arena.enemy_skills.advance(.01)
	check(first.status.guards.b06_tide_shell.remaining==8,"banner does not refresh everyframe")
	arena.enemy_skills.reset_room()
	var tide:=preload("res://scripts/levels/b06/world/tide_runtime.gd").new()
	arena.add_child(tide)
	arena.b06_mechanics=tide
	check(tide.configure("L32"),"real tide for ordinary contracts")
	for i in allies.size():
		var ally:Node2D=allies[i]
		ally.position=Vector2(350+i*5,300)
		ally.status.guards.clear()
		check(tide.register_actor("ordinary-test-"+str(i),ally),"actual tide binding")
	check(arena.enemy_skills.b06.tidal_direction(mine,Vector2(380,300))==Vector2.DOWN,"mine reads authored patch direction")
	banner.cast_enemy_skill(Skills.active(banner.profile,banner.position,Vector2(450,300),false,false))
	tide.tick(10)
	arena.enemy_skills.advance(.01)
	check(Skills.wet(first) and Skills.high(first),"real high tide reaches ordinary runtime")
	check(float(first.status.guards.b06_tide_shell.remaining)==8,"banner extends actual admitted tide shell")
	var before_guard:Vector2=guard.position
	arena.enemy_skills.advance(.01)
	guard.status.absorb(float(guard.status.shield()))
	guard.status.tick(.01)
	arena.enemy_skills.advance(.01)
	check(is_equal_approx(before_guard.distance_to(guard.position),80),"D4 real shell break gives80side retreat")
	check(tide.state.begin_drain("drain_west","fixture"),"directed drain opens")
	tide.tick(.6)
	arena.enemy_skills.advance(.01)
	check(arena.enemy_skills.b06.tide_guard_extension(first)==0,"drain invalidates banner")
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(banner,100,&"primary",Vector2.LEFT,"physical"),115),"D4 drain exposes flag bearer")
	var builder:=Enemy.new()
	builder.room=arena
	builder.configure(Skills.profile("B06-M08",28,4),{"reward_enabled":false})
	arena.enemies.add_child(builder)
	builder.position=Vector2(650,300)
	builder.state=&"execute"
	var wall:=Skills.active(builder.profile,builder.position,Vector2(750,300),false,false)
	check(arena.enemy_skills.b06.wall_admitted(builder,wall),"safe authored coral wall admission")
	builder.cast_enemy_skill(wall)
	check(arena.enemy_skills.b06.wall_blocks_point(Vector2(705,300),18),"actual120widewall physical capsule")
	check(not arena.enemy_skills.b06.wall_blocks_point(Vector2(705,390),18),"wall has flank route")
	check(arena.enemy_skills.b06.blocked_fraction(Vector2(650,300),Vector2(750,300),18)<1,"swept player stops atwall")
	check(arena.enemy_skills.b06.blocked_fraction(Vector2(650,300),Vector2(705,300),0)==1,"wall center can be targeted")
	check(arena.enemy_skills.b06.navigation_obstructions().size()==1,"finitewall navigation obstruction")
	first.position=Vector2(650,300)
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(first,100,&"primary",Vector2.LEFT,"physical",{"attack_delivery":"projectile"}),90),"wall ranged-only10percent reduction")
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(first,100,&"primary",Vector2.LEFT,"physical",{"attack_delivery":"area"}),100),"wall does not reduce melee/area")
	var wall_effect:Dictionary={}
	for effect:Dictionary in arena.enemy_skills.b06.effects:
		if effect.kind=="wall": wall_effect=effect
	check(not wall_effect.is_empty() and int(arena.enemy_skills._anchor(wall_effect).health.maximum)==int(round(float(builder.health.maximum)*.2)),"wall real20percenthp")
	var wall_bindings:Dictionary={"player":arena.victim}
	var wall_ids:Dictionary={arena.victim.get_instance_id():"player"}
	for node:Node in arena.enemies.get_children():
		if not arena.enemy_skills._alive(node): continue
		var key:="actor:"+str(node.get_instance_id())
		wall_bindings[key]=node
		wall_ids[node.get_instance_id()]=key
	var wall_save:Dictionary=arena.enemy_skills.b06.capture_candidate(func(node:Node2D)->String:return str(wall_ids.get(node.get_instance_id(),"")))
	check(not wall_save.is_empty(),"wall and exposure snapshot capture")
	check(arena.enemy_skills.b06.restore_candidate(JSON.parse_string(JSON.stringify(wall_save)),func(key:String)->Node2D:return wall_bindings.get(key)),"livewall atomic restore keeps anchor")
	for effect:Dictionary in arena.enemy_skills.b06.effects:
		if effect.kind=="wall": wall_effect=effect
	arena.enemy_skills._anchor(wall_effect).health.damage(float(builder.health.maximum))
	check(arena.enemy_skills.b06.navigation_obstructions().is_empty(),"destroyedwall releasescollision")
	check(is_equal_approx(arena.enemy_skills.b06.filter_damage(builder,100,&"primary",Vector2.LEFT,"physical"),115),"D4wallbreak exposes builder")
	builder.free()
	var now:float=arena.enemy_skills.b06.clock
	get_tree().paused=true
	arena.enemy_skills.advance(1)
	check(arena.enemy_skills.b06.clock==now,"pause freezes effects and delayed commands")
	get_tree().paused=false
	arena.enemy_skills.reset_room()
	check(arena.enemy_skills.b06.effects.is_empty() and arena.enemy_skills.b06.summon_attempts.is_empty(),"retry resets finite effects")
	arena.b06_mechanics=null
	tide.free()
	for ally:Node2D in allies: ally.free()
	# Lock does not follow a later target move. Cooldown begins at release.
	var actor:=Enemy.new()
	actor.room=arena
	actor.configure(Skills.profile("B06-M01",26,0),{"reward_enabled":false})
	arena.enemies.add_child(actor)
	arena.victim.position=Vector2(100,0)
	actor.brain.tick(actor,.8,arena.victim)
	check(actor.brain.phase==&"telegraph" and actor.brain.cooldown==0,"telegraph starts without spending CD")
	actor.brain.tick(actor,1,arena.victim)
	var locked:Dictionary=actor.brain.current_telegraph()
	check(actor.brain.phase==&"locked","lock phase")
	arena.victim.position=Vector2(0,100)
	actor.brain.tick(actor,.01,arena.victim)
	check(actor.brain.current_telegraph().direction==locked.direction,"locked aim immutable")
	actor.brain.tick(actor,.4,arena.victim)
	check(actor.brain.cooldown==7,"release starts exact CD")
	actor.brain.configure(actor.profile)
	actor.brain.tick(actor,.8,arena.victim)
	actor.brain.interrupt(actor)
	check(actor.brain.cooldown==3.5,"interrupt half cooldown")
	arena.enemy_skills.reset_room()
	actor.brain.configure(actor.profile)
	actor.brain.cooldown=7
	actor.position=Vector2.ZERO
	arena.victim.position=Vector2(80,0)
	arena.victim.hits.clear()
	for frame in 420:
		actor.brain.tick(actor,1.0/60,arena.victim)
		arena.enemy_skills.advance(1.0/60)
	check(arena.victim.hits.size()>=3,"repeated basics each confirm once during active cooldown")
	check(actor.brain._cast_serial>=3,"everylockedcast gets unique serial")
	arena.enemy_skills.reset_room()
	var d4:=Skills.active(Skills.profile("B06-M01",30,4),Vector2.ZERO,Vector2(100,0),false,false)
	check(arena.enemy_skills.b06.admit_lock(actor,d4),"first D4 lock admitted")
	check(not arena.enemy_skills.b06.admit_lock(actor,d4),"simultaneous D4 damaging lock deferred")
	arena.enemy_skills.advance(.799)
	check(not arena.enemy_skills.b06.admit_lock(actor,d4),"D4 lock gap cannot shorten below0.8")
	arena.enemy_skills.advance(.001)
	check(arena.enemy_skills.b06.admit_lock(actor,d4),"D4 lock admits at authored0.8gap")
	var boss_command:=Skills.boss_action(Skills.boss_profile(4),"siege_claw",Vector2.ZERO,Vector2(100,0),1)
	check(arena.enemy_skills.b06.admit_lock(actor,boss_command),"ordinary coordinator never adds Boss wait")
	arena.enemy_skills.reset_room()
	actor.free()
	arena.free()
	print("B06_ENEMY_SKILLS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
