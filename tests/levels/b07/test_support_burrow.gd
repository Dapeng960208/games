extends Node
## Focused production-scene contract for candidate M05/M06. Real Lv31 actors,
## L38 light/cover, CombatHealth/Status and EnemySkillRuntime; deterministic
## clocks and wounded-health fixtures do not claim natural-play balance or art QA.
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
const Skills = preload("res://scripts/levels/b07/combat/enemy_skills.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Boss = preload("res://scripts/gameplay/bosses/boss_actor.gd")
var checks := 0
var failures := 0
var launch: Node
var room: Node2D
var difficulty := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("B07 SUPPORT/BURROW D%d: %s" % [difficulty,label])

func near(actual: float, expected: float, label: String, tolerance: float = .001) -> void:
	check(absf(actual-expected)<=tolerance,"%s (%.4f expected %.4f)" % [label,actual,expected])

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if not Rules.b07_candidate_enabled() or not Game.profile_path.begins_with("user://test_b07_candidate/"):
		get_tree().quit(2)
		return
	for d: int in [0,2,4]:
		difficulty=d
		launch=Launcher.new()
		launch.auto_start=false
		launch.process_mode=Node.PROCESS_MODE_DISABLED
		add_child(launch)
		check(launch.start_candidate("CH01",d,false),"isolated production launcher: "+launch.last_error)
		if Game.run==null or not is_instance_valid(launch.room):
			launch.free()
			continue
		room=launch.room
		room.process_mode=Node.PROCESS_MODE_DISABLED
		room.enemy_skills.process_mode=Node.PROCESS_MODE_DISABLED
		room.enemy_telegraphs.process_mode=Node.PROCESS_MODE_DISABLED
		room.combat_audio.audible=false
		check(Game.run.level==31 and Game.run.expedition.is_empty(),"real Lv31 independent candidate")
		_clear_fixture()
		room.objective_complete=true
		room._completion_emitted=true
		room.b07_mechanics.state.open_manual_gate(true)
		room.player.position=room.exit_position
		check(launch.traversal.advance(0) and room.layout_id=="L38","production traversal enters L38")
		room.enemy_skills.process_mode=Node.PROCESS_MODE_DISABLED
		room.enemy_telegraphs.process_mode=Node.PROCESS_MODE_DISABLED
		_test_healing_and_guard()
		_test_heal_release_counters()
		_test_heal_interrupts()
		if d==4:
			_test_two_recipient_heal()
			_test_frozen_chain()
		_test_burrow_landing()
		_test_burrow_counters()
		if d>=2: _test_pool_birth_frame()
		if d==4:
			_test_reposition_counters()
			_test_slow_checkpoint()
		check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
		launch.free()
		Game.run=null
	print("B07 SUPPORT BURROW ",checks," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)

func _clear_fixture() -> void:
	room.enemy_skills.reset_room()
	for actor: Node in room.enemies.get_children(): actor.free()
	for shot: Node in room.projectiles.get_children(): shot.free()
	room.enemy_telegraphs.clear()
	room.spawn_enabled=false
	room.input_blocked=false
	room.release_gate=false
	room.objective_complete=false
	room.objective_rewarded=false
	room._completion_emitted=false
	room.b07_mechanics.cancel_interaction()
	for id: String in room.b07_mechanics.state.mirrors: room.b07_mechanics.state.mirrors[id]=0
	room.player.cancel_actions()
	room.player.clear_movement_target()
	room.player.position=Vector2(700,630)
	room.player.invulnerable=0
	room.player.knockback=Vector2.ZERO
	room.player.status.states.clear()
	room.player.status.guards.clear()
	room.player._enemy_slow_remaining=0
	room.player._enemy_slow_multiplier=1
	Game.run.hp=Game.run.max_hp
	Game.run.shield=0

func _spawn(id: String, point: Vector2, options: Dictionary = {}) -> EnemyActor:
	options=options.duplicate(true)
	options["profile"]=Skills.profile(id,31,difficulty)
	options["reward_enabled"]=false
	var actor: EnemyActor=room.spawn_enemy(point,id,31,options)
	check(is_instance_valid(actor),id+" production spawn")
	if is_instance_valid(actor):
		actor.training_ai_disabled=true
		actor.state=&"chase"
		check(actor.position.distance_to(point)<.01,id+" fixture lies on actual L38 ground")
	return actor

func _wound(actor: EnemyActor) -> void:
	actor.health.current=Rules.integer(float(actor.health.maximum)*.5)

func _command(actor: EnemyActor, target: Vector2) -> Dictionary:
	return Skills.constrain(actor,Skills.active(actor.profile,actor.position,target,Skills.lit(actor)))

func _start_warning(actor: EnemyActor) -> Dictionary:
	actor.brain.configure(actor.profile)
	actor.brain.tick(actor,.81,room.player)
	var command: Dictionary=actor.brain.current_telegraph()
	check(not command.is_empty() and actor.state==&"telegraph",actor.enemy_id+" actual brain starts readable tell")
	return command

func _lock(actor: EnemyActor) -> Dictionary:
	var command:=_start_warning(actor)
	if command.is_empty(): return {}
	actor.brain.tick(actor,float(command.tell)+.001,room.player)
	command=actor.brain.current_telegraph()
	check(not command.is_empty() and actor.state==&"locked",actor.enemy_id+" actual brain locks")
	return command

func _release(actor: EnemyActor, command: Dictionary) -> void:
	if not command.is_empty(): actor.brain.tick(actor,float(command.lock)+.001,room.player)

func _advance(seconds: float) -> void:
	var was_blocked: bool=room.input_blocked
	room.input_blocked=true # Tick real player defenses/status without input or auto-attacks.
	var elapsed := 0.0
	while elapsed<seconds-.000001:
		var dt:=minf(.01,seconds-elapsed)
		room.player._physics_process(dt)
		room.enemy_skills.advance(dt)
		elapsed+=dt
	room.input_blocked=was_blocked

func _warning_entry(actor: EnemyActor) -> Dictionary:
	var settings: Dictionary=Game.profile.settings.duplicate(true)
	Game.profile.settings["reduced_fx"]=true
	Game.profile.settings["enemy_skill_paths"]=false
	room.enemy_telegraphs.refresh()
	var found: Dictionary={}
	for entry: Dictionary in room.enemy_telegraphs.snapshot():
		if int(entry.actor_id)==actor.get_instance_id(): found=entry.data
	Game.profile.settings=settings
	check(not found.is_empty(),actor.enemy_id+" locked essential warning survives low FX/path toggle")
	return found

func _test_healing_and_guard() -> void:
	_clear_fixture()
	var healer:=_spawn("B07-M05",Vector2(700,550))
	var ally:=_spawn("B07-M04",Vector2(610,470))
	_wound(healer)
	_wound(ally)
	check(Skills.lit(ally) and room.has_line_of_sight(healer.position,ally.position),"real lit wounded ally and clear sight")
	var before: float=ally.health.current
	var caster_before: float=healer.health.current
	var player_before: float=Game.run.hp
	var command:=_lock(healer)
	check(str(command.get("kind",""))=="b07_heal" and int(command.get("coefficient",-1))==0,"support is a zero-damage channel")
	check(float(command.get("tell",0))+float(command.get("lock",0))>=1.3-.000001,"full healing warning at least1.3s")
	var shown:=_warning_entry(healer)
	check(shown.get("points",[]).size()==2 and shown.get("paths",[]).size()==1,"one readable caster-to-ally line")
	_release(healer,command)
	var ratio: float=.03 if difficulty>=4 else .04 if difficulty>=2 else .06
	near(ally.health.current-before,Rules.integer(float(ally.health.maximum)*ratio),"actual heal follows difficulty maximum-HP ratio")
	near(healer.health.current,caster_before,"caster never heals itself")
	near(Game.run.hp,player_before,"healing channel cannot damage player")
	if difficulty<2:
		check(not ally.status.guards.has("b07_turquoise"),"D0 has no turquoise shield")
	else:
		var capacity: int=Rules.integer(float(ally.health.maximum)*.04)
		near(ally.status.shield(),capacity,"real turquoise guard capacity")
		near(float(ally.status.guards.get("b07_turquoise",{}).get("remaining",0)),3,"turquoise guard lasts3s")
		var healed_hp: float=ally.health.current
		check(ally.take_damage(1,&"test",Vector2.ZERO,{"damage_type":"true"}),"real guarded damage accepted")
		near(ally.health.current,healed_hp,"guard absorbs before actual HP")
		near(ally.status.shield(),capacity-1,"guard is consumed by real hit")
		ally.status.grant_guard(capacity*2,10,"test:stronger",ally.health.maximum)
		healer.cast_enemy_skill(_command(healer,room.player.position))
		near(ally.status.shield(),capacity*2,"turquoise and stronger guard use shared max, never sum")
		near(float(ally.status.guards.get("b07_turquoise",{}).get("amount",0)),capacity,"repeat heal refreshes only its own shield pool")
		ally.tick_statuses(3.01)
		check(not ally.status.guards.has("b07_turquoise") and ally.status.guards.has("test:stronger"),"turquoise expiration leaves independent stronger shield")
	check(launch.traversal.checkpoint().is_empty(),"active support room refuses clear-boundary save")

func _test_heal_release_counters() -> void:
	# A real mirror rotation after target lock removes eligibility at release.
	_clear_fixture()
	var healer:=_spawn("B07-M05",Vector2(700,550))
	var ally:=_spawn("B07-M04",Vector2(590,458))
	_wound(ally)
	var before: float=ally.health.current
	var command:=_lock(healer)
	room.player.position=Geometry.world_point(Geometry.room("L38").mirrors[0].position)
	check(room.objectives.interact("L38_mirror_1",room.player),"real mirror interaction starts after heal lock")
	room.b07_mechanics.tick(.6)
	check(not Skills.lit(ally),"rotated production beam no longer lights locked ally")
	_release(healer,command)
	near(ally.health.current,before,"lost light cancels actual heal")
	check(not ally.status.guards.has("b07_turquoise"),"lost light grants no shield")
	# The ally stays lit/in range but moves behind the authored stone cover.
	_clear_fixture()
	healer=_spawn("B07-M05",Vector2(590,480))
	ally=_spawn("B07-M04",Vector2(610,470))
	_wound(ally)
	before=ally.health.current
	command=_lock(healer)
	ally.position=Vector2(445,370)
	check(room.valid_ground(ally.position,ally.navigation_radius) and Skills.lit(ally),"occluded endpoint remains legal ground and lit")
	check(healer.position.distance_to(ally.position)<200 and not room.has_line_of_sight(healer.position,ally.position),"authored L38 cover occludes otherwise in-range recipient")
	_release(healer,command)
	near(ally.health.current,before,"release rechecks real stone-cover LOS")
	# Range is checked on the locked identity even if it remains lit.
	_clear_fixture()
	healer=_spawn("B07-M05",Vector2(700,550))
	ally=_spawn("B07-M04",Vector2(610,470))
	_wound(ally)
	before=ally.health.current
	command=_lock(healer)
	ally.position=Vector2(445,370)
	check(Skills.lit(ally) and healer.position.distance_to(ally.position)>200,"locked ally remains lit outside200")
	_release(healer,command)
	near(ally.health.current,before,"range loss cancels actual heal")
	_clear_fixture()
	healer=_spawn("B07-M05",Vector2(700,550))
	ally=_spawn("B07-M04",Vector2(610,470))
	check(Skills.lit(ally),"full-health fallback fixture is lit")
	var fallback: Dictionary=healer.brain._candidate(healer,room.player,true)
	check(str(fallback.kind)=="melee" and not bool(fallback.get("active",false)),"no wounded eligible ally falls back to basic")

func _test_heal_interrupts() -> void:
	for locked: bool in [false,true]:
		for counter: String in ["damage","push"]:
			_clear_fixture()
			var healer:=_spawn("B07-M05",Vector2(700,550))
			var ally:=_spawn("B07-M04",Vector2(610,470))
			_wound(ally)
			var before: float=ally.health.current
			var command: Dictionary=_lock(healer) if locked else _start_warning(healer)
			if counter=="damage":
				check(healer.take_damage(1,&"test",Vector2.ZERO,{"damage_type":"true"}),"real source damage during channel")
			else:
				healer.apply_knockback(Vector2.DOWN,12)
				check(healer.has_pending_displacement(),"real small forced movement commits during channel")
			check(healer.state==&"recovery" and healer.brain.current_telegraph().is_empty(),counter+" cancels "+("lock" if locked else "tell"))
			check(healer.brain.cooldown>0,"interrupted support pays its cooldown penalty")
			_advance(2)
			near(ally.health.current,before,"interrupted channel leaves no deferred heal")
			check(not ally.status.guards.has("b07_turquoise"),"interrupted channel leaves no deferred guard")

func _test_two_recipient_heal() -> void:
	_clear_fixture()
	var healer:=_spawn("B07-M05",Vector2(700,550))
	var first:=_spawn("B07-M04",Vector2(610,470))
	var second:=_spawn("B07-M01",Vector2(590,458))
	_wound(first)
	_wound(second)
	var before: Array=[first.health.current,second.health.current]
	var command:=_lock(healer)
	check(command.get("b07_target_refs",[]).size()==2,"successful D4 channel freezes two recipients")
	_release(healer,command)
	for index: int in range(2):
		var ally: EnemyActor=first if index==0 else second
		near(ally.health.current-float(before[index]),Rules.integer(float(ally.health.maximum)*.03),"D4 recipient%d receives actual3percent heal" % index)
		near(ally.status.shield(),Rules.integer(float(ally.health.maximum)*.04),"D4 recipient%d receives actual4percent guard" % index)
		ally.tick_statuses(.5)
	var restored: Array=[first.health.current,second.health.current]
	# Re-delivering the same frozen cast must not heal again or refresh guards.
	healer.cast_enemy_skill(command)
	for index: int in range(2):
		var ally: EnemyActor=first if index==0 else second
		near(ally.health.current,float(restored[index]),"same-cast replay cannot heal recipient%d twice" % index)
		near(float(ally.status.guards.get("b07_turquoise",{}).get("remaining",0)),2.5,"same-cast replay cannot refresh recipient%d shield" % index)

func _test_frozen_chain() -> void:
	_clear_fixture()
	var healer:=_spawn("B07-M05",Vector2(700,550))
	var first:=_spawn("B07-M04",Vector2(610,470))
	var second:=_spawn("B07-M01",Vector2(590,458))
	var reserve:=_spawn("B07-M06",Vector2(565,445))
	var peer:=_spawn("B07-M05",Vector2(630,480))
	var objective:=_spawn("B07-M04",Vector2(620,475),{"actor_kind":"objective","static_actor":true})
	var boss:=Boss.new()
	boss.room=room
	boss.position=Vector2(620,475)
	boss.configure(Skills.boss_profile(difficulty,room.enemy_calibration()),{"reward_enabled":false,"actor_kind":"boss"})
	check(boss.enemy_id=="BO07" and boss.rank=="boss","actual B07 candidate boss configuration for recipient exclusion")
	room.enemies.add_child(boss)
	boss.training_ai_disabled=true
	for actor: EnemyActor in [healer,first,second,reserve,peer,objective,boss]: _wound(actor)
	var command:=_lock(healer)
	var refs: Array=command.get("b07_target_refs",[])
	check(refs.size()==2,"D4 freezes exactly two eligible ordinary allies")
	if refs.size()!=2: return
	check(refs[0].get_ref()==first and refs[1].get_ref()==second,"caster/peer/objective/boss excluded despite closer wounded positions")
	check(command.get("paths",[]).size()==1 and command.get("points",[]).size()==3,"D4 is one ordered caster/first/second line")
	var shown:=_warning_entry(healer)
	check(shown.get("points",[])==command.get("points",[]),"low-FX presentation retains frozen healing line")
	var before: Array=[first.health.current,second.health.current,reserve.health.current,boss.health.current]
	second.position=Vector2(620,580)
	check(not Skills.lit(second) and Skills.lit(reserve),"locked final link invalid while unused eligible reserve stays lit")
	var frozen: Dictionary=healer.brain.current_telegraph()
	check(frozen.get("points",[])==command.get("points",[]) and frozen.b07_target_refs[1].get_ref()==second,"locked command preserves recipient identity and initial geometry")
	_release(healer,command)
	check(first.health.current==before[0] and second.health.current==before[1] and reserve.health.current==before[2],"one broken chain link cancels whole heal with no reserve retarget")
	near(boss.health.current,before[3],"boss never receives support heal")
	# A freed WeakRef must cancel safely rather than selecting the reserve.
	_clear_fixture()
	healer=_spawn("B07-M05",Vector2(700,550))
	first=_spawn("B07-M04",Vector2(610,470))
	_wound(first)
	command=_lock(healer)
	first.free()
	reserve=_spawn("B07-M01",Vector2(610,470))
	_wound(reserve)
	var reserve_before: float=reserve.health.current
	_release(healer,command)
	near(reserve.health.current,reserve_before,"freed locked recipient never heals replacement actor")

func _test_burrow_landing() -> void:
	_clear_fixture()
	var caster:=_spawn("B07-M06",Vector2(820,700))
	room.player.position=Vector2(970,700)
	var command:=_lock(caster)
	check(str(command.get("path_mode",""))=="burrow" and bool(command.get("landing_only",false)),"M06 uses landing-only production burrow")
	check(float(command.get("tell",0))+float(command.get("lock",0))>=1.1-.000001,"burrow full warning at least1.1s")
	near(float(command.get("radius",0)),70,"landing radius70")
	near(float(command.get("travel_distance",0)),150,"burrow capped150")
	var shown:=_warning_entry(caster)
	check(bool(shown.get("b07_mound",false)) and bool(shown.get("locked",false)) and Vector2(shown.get("target",Vector2.ZERO))==Vector2(970,700),"mound and exact locked landing survive reduced presentation")
	var hp_before: float=Game.run.hp
	_release(caster,command)
	check(room.enemy_skills.has_motion(caster),"brain release creates real body motion")
	if room.enemy_skills.motions.is_empty(): return
	var motion_duration: float=room.enemy_skills.motions[0].duration
	_advance(.1)
	check(caster.position.x>820 and caster.position.x<970,"body actually travels along locked burrow")
	near(Game.run.hp,hp_before,"burrow cannot damage along the transit path")
	_advance(.2)
	check(not room.enemy_skills.has_motion(caster) and caster.position.distance_to(Vector2(970,700))<.01,"completed motion lands at warned point")
	check(Game.run.hp<hp_before,"completed landing deals real player HP damage")
	var landed_hp: float=Game.run.hp
	caster.brain.tick(caster,.31,room.player)
	check(caster.state==&"recovery" and caster.state_time>=1.2-.000001,"actual post-landing brain exposes at least1.2s recovery")
	if difficulty<2:
		check(room.enemy_skills.hazards.is_empty() and room.enemy_skills.jobs.is_empty(),"D0 has neither slow pool nor side step")
		return
	check(room.enemy_skills.hazards.size()==1,"completed D2+ landing creates one bounded slow pool")
	if room.enemy_skills.hazards.is_empty(): return
	var pool: Dictionary=room.enemy_skills.hazards[0]
	check(int(pool.get("damage",-1))==0 and int(pool.get("coefficient",-1))==0,"pool is status-only")
	near(float(pool.get("duration",0)),2,"pool lifetime2s")
	near(float(pool.get("radius",0)),70,"pool radius70")
	near(float(pool.get("tick_interval",0)),.5,"pool tick interval0.5s")
	_advance(.35)
	near(room.player._enemy_slow_remaining,0,"pool does not apply before its first tick")
	var speed_before: float=room.player.stat("move_speed",220)
	_advance(.2)
	check(room.player.invulnerable>0 and room.player._enemy_slow_remaining==0,"first sand tick respects landing-hit invulnerability")
	_advance(.5)
	near(room.player._enemy_slow_multiplier,.75,"second sand tick applies real slow magnitude0.75")
	check(room.player._enemy_slow_remaining>0 and room.player.stat("move_speed",220)<speed_before,"slow changes actual player movement speed")
	check(not room.player.status.has("chill"),"ordinary sand slow does not become chill")
	near(Game.run.hp,landed_hp,"slow ticks add no damage")
	if difficulty>=4:
		var side_jobs: Array=[]
		for job: Dictionary in room.enemy_skills.jobs:
			if bool(job.get("b07_reposition_motion",false)): side_jobs.append(job)
		check(side_jobs.size()==1,"D4 landing queues exactly one harmless side step")
		if side_jobs.is_empty(): return
		var step: Dictionary=side_jobs[0]
		check(bool(step.get("harmless",false)) and bool(step.get("body_bound",false)) and int(step.get("damage",-1))==0,"side step is harmless and bound to landing body")
		near(float(step.remaining)+1.35-motion_duration,1.2,"D4 opening precedes side step by1.2s",.002)
		near(Vector2(step.target).distance_to(Vector2(step.origin)),80,"D4 step length80")
		near(absf(Vector2(step.direction).dot(Vector2(command.direction))),0,"D4 step is orthogonal")
		var landing: Vector2=caster.position
		# Advance to just before its actual pending delay, then verify travel.
		_advance(maxf(0,float(step.remaining)-.01))
		near(caster.position.distance_to(landing),0,"body holds its landing for complete opening")
		_advance(.3)
		near(caster.position.distance_to(landing),80,"harmless side step actually moves body")
		near(Game.run.hp,landed_hp,"D4 side step and continuing pool deal no added damage")
	_advance(2.1)
	check(room.enemy_skills.hazards.is_empty(),"sand pool expires without recurring followups")

func _test_burrow_counters() -> void:
	_clear_fixture()
	var caster:=_spawn("B07-M06",Vector2(450,410))
	room.player.position=Vector2(460,410)
	var command:=_command(caster,Vector2(600,410))
	check(room.blocked_fraction(caster.position,Vector2(command.target),caster.navigation_radius)<1,"authored L38 cover blocks intended burrow")
	var hp_before: float=Game.run.hp
	caster.cast_enemy_skill(command)
	_advance(.4)
	check(not room.enemy_skills.has_motion(caster) and caster.position.x<475,"blocked burrow stops before real stone")
	near(Game.run.hp,hp_before,"blocked burrow never relocates explosion onto wall-side player")
	check(room.enemy_skills.hazards.is_empty() and room.enemy_skills.jobs.is_empty() and room.enemy_skills.visuals.is_empty(),"blocked burrow creates no impact/pool/side step")
	_clear_fixture()
	caster=_spawn("B07-M06",Vector2(820,700))
	room.player.position=Vector2(850,700)
	command=_command(caster,Vector2(970,700))
	hp_before=Game.run.hp
	caster.cast_enemy_skill(command)
	_advance(.1)
	caster.apply_knockback(Vector2.DOWN,45)
	check(caster.has_pending_displacement() and not room.enemy_skills.has_motion(caster),"committed forced movement cancels burrow immediately")
	_advance(.5)
	near(Game.run.hp,hp_before,"displaced burrow cannot explode")
	check(room.enemy_skills.hazards.is_empty() and room.enemy_skills.jobs.is_empty(),"displaced burrow has no landing followups")
	if difficulty>=2:
		_clear_fixture()
		var mirror: Vector2=Geometry.world_point(Geometry.room("L38").mirrors[0].position)
		caster=_spawn("B07-M06",mirror+Vector2(0,130))
		room.player.position=mirror
		caster.cast_enemy_skill(_command(caster,mirror))
		_advance(.35)
		check(caster.position.distance_to(mirror)<.01,"burrow can land near mirror")
		check(room.enemy_skills.hazards.is_empty(),"persistent slow pool cannot block mirror interaction clearance")

func _test_pool_birth_frame() -> void:
	_clear_fixture()
	var caster:=_spawn("B07-M06",Vector2(820,700))
	room.player.position=Vector2(970,700)
	caster.cast_enemy_skill(_command(caster,room.player.position))
	check(room.enemy_skills.motions.size()==1,"coarse-frame real burrow motion exists")
	if room.enemy_skills.motions.is_empty(): return
	var duration: float=room.enemy_skills.motions[0].duration
	room.enemy_skills.advance(duration+.1)
	check(room.enemy_skills.hazards.size()==1,"coarse-frame completed motion creates one pool")
	if room.enemy_skills.hazards.is_empty(): return
	var pool: Dictionary=room.enemy_skills.hazards[0]
	near(float(pool.remaining),1.9,"new pool consumes only post-impact0.1s, not full finishing frame")
	near(float(pool.next_tick),.4,"new pool first tick retains correct birth-relative delay")
	if difficulty>=4:
		var found := false
		for job: Dictionary in room.enemy_skills.jobs:
			if bool(job.get("b07_reposition_motion",false)):
				found=true
				near(float(job.remaining),1.1,"coarse-frame side step retains full1.2s post-landing opening")
		check(found,"coarse frame retains a single delayed side-step command")

func _test_reposition_counters() -> void:
	for pending: bool in [false,true]:
		_clear_fixture()
		var caster:=_spawn("B07-M06",Vector2(820,700))
		room.player.position=Vector2(970,700)
		caster.cast_enemy_skill(_command(caster,room.player.position))
		_advance(.3)
		check(not room.enemy_skills.jobs.is_empty(),"D4 pending reposition fixture")
		if pending: caster.apply_knockback(Vector2.DOWN,10)
		else: caster.position+=Vector2(45,0)
		var displaced: Vector2=caster.position
		var hp_before: float=Game.run.hp
		_advance(1.6)
		near(caster.position.distance_to(displaced),0,"pending/body displacement prevents old landing side step")
		near(Game.run.hp,hp_before,"cancelled side step never adds damage")
		check(not room.enemy_skills.has_motion(caster),"cancelled reposition leaves no motion")

func _test_slow_checkpoint() -> void:
	_clear_fixture()
	var caster:=_spawn("B07-M06",Vector2(820,700))
	room.player.position=Vector2(970,700)
	caster.cast_enemy_skill(_command(caster,room.player.position))
	_advance(1.35)
	check(room.player._enemy_slow_remaining>0,"real sand pool second tick applied residual slow after landing invulnerability")
	check(launch.traversal.checkpoint().is_empty(),"active burrow/pool cannot masquerade as clear checkpoint")
	room.enemy_skills.reset_room()
	for actor: Node in room.enemies.get_children(): actor.free()
	room.objective_complete=true
	room.objective_rewarded=false
	room._completion_emitted=true
	room.b07_mechanics.state.open_manual_gate(true)
	room.input_blocked=true
	room.player._physics_process(.2)
	var remaining: float=room.player._enemy_slow_remaining
	var hp_before: float=Game.run.hp
	var speed_before: float=room.player.stat("move_speed",220)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(launch.traversal.checkpoint()))
	check(not saved.is_empty() and remaining>0 and remaining<.5,"clear-boundary JSON captures partially elapsed real slow")
	if saved.is_empty(): return
	near(float(saved.hero.status.slow_remaining),remaining,"JSON stores remaining duration, not initial duration")
	near(float(saved.hero.status.slow_multiplier),.75,"JSON stores real slow strength")
	room.player._enemy_slow_remaining=0
	room.player._enemy_slow_multiplier=1
	check(launch.traversal.restore_checkpoint(saved),"same-session production clear checkpoint restores")
	near(Game.run.hp,hp_before,"resume does not heal landing damage")
	near(room.player._enemy_slow_remaining,remaining,"resume preserves remaining slow duration")
	near(room.player.stat("move_speed",220),speed_before,"resume preserves actual slowed movement stat")
	check(room.enemy_skills.active_effect_count()==0 and room._living_enemy_count()==0,"resume does not regenerate burrow/pool/enemies")
	room.input_blocked=true
	room.player._physics_process(remaining+.01)
	near(room.player._enemy_slow_remaining,0,"restored slow expires normally")
	near(room.player._enemy_slow_multiplier,1,"expired restored slow releases movement penalty")
