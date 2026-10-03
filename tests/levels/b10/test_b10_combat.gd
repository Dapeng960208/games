extends Node
## Deterministic combat contracts. The separate Main/GPU matrix owns natural
## input, room traversal and visual acceptance; these fixtures use isolated data.
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const BossBrain = preload("res://scripts/levels/b10/combat/boss_brain.gd")
const Layouts = preload("res://scripts/levels/b10/world/room_layouts.gd")
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
const Checkpoint = preload("res://scripts/levels/b10/world/combat_checkpoint.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
var checks := 0
var failures: Array[String] = []
var room: Node2D

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if not Game.profile_path.contains("test_b10_combat"):
		printerr("B10 combat requires its isolated test profile")
		get_tree().quit(2)
		return
	_catalog_contract()
	for hero: String in ["CH01","CH02","CH03"]:
		Game.run=null
		check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(),hero+" isolated production kit")
		for room_id: String in ["L55","L56","L57","L58","L59","L60"]:
			await _make_room(room_id)
			_finite_guardian_contract(hero,room_id)
			check(await room.combat_audio.wait_for_cleanup(),"audio releases "+room_id)
			room.free()
		await _make_room("BO10")
		_core_phase_contract(hero)
		check(await room.combat_audio.wait_for_cleanup(),"audio releases final arena")
		room.free()
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"mechanism fixture starts")
	await _make_room("L55")
	_echo_and_partition_contract()
	check(await room.combat_audio.wait_for_cleanup(),"mechanism audio releases")
	room.free()
	Game.run=null
	for failure: String in failures: printerr("B10_COMBAT: "+failure)
	print("B10 combat contracts: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _catalog_contract() -> void:
	check(Skills.enemy_ids().size()==18,"eighteen stable ordinary identities")
	var names: Array=[]
	var themes: Array=[]
	for id: String in Skills.catalog().bosses:
		var p:=Skills.boss_profile(id,4)
		check(p.clan=="dragon" and not names.has(p.name) and not themes.has(p.theme),id+" independent dragon identity")
		names.append(p.name)
		themes.append(p.theme)
		var brain:=BossBrain.new()
		brain.configure(p)
		check(not brain.skill_pool().is_empty(),id+" owns actual executable skills")
		check(brain._phase_for_ratio(.7)==2 and brain._phase_for_ratio(.35)==3,id+" inclusive phase thresholds")
	check(names.size()==7 and Skills.boss_definition("BO10").head_count==1,"six room dragons and one single-headed ancient dragon")
	for index in 18:
		var id:="B10-M%02d"%(index+1)
		var source:=Skills.enemy_definition(id)
		for difficulty in 5:
			var p:=Skills.profile(id,int(source.level),difficulty)
			var skill:=Skills.active(p,Vector2(600,500),Vector2(750,500),true)
			check(p.clan=="dragon" and int(skill.get("coefficient",-1))>=0 and skill.ability_id==id+":active",id+" D"+str(difficulty)+" active identity")
			check(float(skill.tell)+float(skill.lock)>=float(source.tell)*.8-.001,id+" readable warning")
			var packet:=Skills.freeze_damage(skill,p)
			var changed:=p.duplicate(true)
			changed.damage*=100
			check(Skills.freeze_damage(packet,changed)==packet,id+" damage freezes once")
	for id: String in ["L55","L56","L57","L58","L59","L60"]:
		var plan:=Skills.encounter_plan(id,0,4)
		check(plan.waves.size()==3 and plan.total_count==9 and plan.concurrent_cap==3,id+" finite three waves")
	var bent:=Skills.active(Skills.profile("B10-M07",48,4),Vector2(400,400),Vector2(600,400))
	check(bent.followups[0].kind=="charge" and Vector2(bent.target)!=Vector2(bent.followups[0].target),"M07 two different locked segments")
	var chart:=Skills.active(Skills.profile("B10-M08",48,2),Vector2(400,400),Vector2(600,400))
	check(chart.followups[1].kind=="b10_waymark" and chart.followups[1].coefficient==0,"M08 harmless third marker")
	check(Skills.active(Skills.profile("B10-M13",50,4),Vector2(400,400),Vector2(500,400)).followups[0].b10_relock,"M13 second slash owns a new lock")
	for difficulty in 5:
		var p:=Skills.boss_profile("BO10",difficulty)
		var brain:=BossBrain.new()
		brain.configure(p)
		check(("court_guard" in brain.skill_pool())==(difficulty>=3),"finite guard skill starts at D3")
		check(("star_crown" in brain.skill_pool())==(difficulty>=4),"three-star crown starts at D4")
		var crown:=BossBrain.build_action(p,"star_crown",Vector2(500,500),Vector2(700,500),3)
		check(crown.core_index==0 and crown.followups[0].core_index==1 and crown.followups[1].core_index==2,"each crown hit maps to its matching core")

func _make_room(id: String) -> void:
	room=load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	room.enemy_skills.reset_room()
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.layout=Layouts.build(id,1007)
	room.layout_id=id
	room.layout_seed=1007
	room.difficulty=4
	room.expedition_context={"biome_id":"B10","room_id":id,"role":"boss" if id=="BO10" else "branch","node_index":0}
	room._configure_ground_boundary()
	room.encounter_zones=room.layout.get("encounter_zones",[])
	room.encounter_progress.clear()
	room.activated_encounters.clear()
	room._encounter_spawn_retry.clear()
	room._b10_guard_started=false
	room._boss_defeated=false
	room._boss_actor=null
	room.player.position=room.layout.entry
	room.player.loadout.effects.room_id=id
	room.player.invulnerable=99
	room._previous_player_position=room.player.position
	room.release_gate=false
	room.input_blocked=false
	room.objective_rewarded=true # Contract fixture does not settle expedition loot.
	if is_instance_valid(room.objectives): room.objectives.free()
	room.objectives=load("res://scripts/gameplay/world/room_objectives.gd").new()
	room.add_child(room.objectives)
	room.objectives.configure(room,room.layout,str(room.expedition_context.role))
	room._expedition_ready=true
	if id=="BO10":
		var boss:=load("res://scripts/gameplay/bosses/boss_actor.gd").new()
		boss.room=room
		boss.position=room.layout.boss_spawn
		boss.configure(Skills.boss_profile("BO10",4))
		boss.completed.connect(func(_id: String,_payload: Dictionary) -> void: room._boss_defeated=true)
		room.enemies.add_child(boss)
		room._boss_actor=boss
	await get_tree().process_frame

func _finite_guardian_contract(hero: String, id: String) -> void:
	room.player.position=room.encounter_zones[0].center
	room._update_encounters()
	for wave in 3:
		var ordinary: Array=[]
		for actor: Node2D in room.enemies.get_children():
			if actor.enemy_id.begins_with("B10-M") and actor.is_alive(): ordinary.append(actor)
		check(ordinary.size()==3,hero+" "+id+" wave "+str(wave+1)+" has three bodies")
		if wave==0:
			room.enemy_skills.b10.advance(.01)
			var f:=Skills.profile("B10-M01",int(ordinary[0].enemy_level),4)
			check(float(room.enemy_skills.b10.cores[0].health)==roundf(float(f.max_hp)*.6),id+" ordinary cores use regional F HP")
		for actor: Node2D in ordinary: actor.take_damage(float(actor.health.maximum)*100,&"skill",Vector2.RIGHT,{"damage_type":"true","equipment_eligible":false})
		room._tick_expedition(2.0)
		if wave<2: check(not room._b10_guard_started and not room.objective_complete,id+" cannot skip remaining wave")
	check(room._encounters_exhausted() and room._b10_guard_started and is_instance_valid(room._boss_actor),hero+" "+id+" guardian appears after all nine")
	var guardian: Node2D=room._boss_actor
	check(guardian.enemy_id==str(room.layout.dragon_id),id+" correct independent guardian")
	check(room._spawn_b10_guardian() and room._boss_actor==guardian,id+" second spawn call keeps one guardian")
	guardian.boss_brain.tick(guardian,.01,room.player)
	var checkpoint:=Checkpoint.capture(room)
	check(not checkpoint.is_empty() and Checkpoint.validate_checkpoint(JSON.parse_string(JSON.stringify(checkpoint))),id+" JSON checkpoint preserves guardian and finite waves")
	if not checkpoint.is_empty():
		var hp:=float(guardian.health.current)
		check(Checkpoint.restore(room,checkpoint),id+" live guardian checkpoint restores")
		check(room._b10_guard_started and room._encounters_exhausted() and float(room._boss_actor.health.current)==hp,id+" restore keeps HP and consumed waves")
		check(Checkpoint.restore(room,checkpoint),id+" repeated restore remains bounded")
		var boss_count:=0
		for actor: Node2D in room.enemies.get_children():
			if actor.rank=="boss" and actor.is_alive(): boss_count+=1
		check(boss_count==1,id+" repeated restore never doubles guardian")
		var corrupt:=checkpoint.duplicate(true)
		corrupt.room_id="L01"
		check(not Checkpoint.restore(room,corrupt),id+" foreign-room checkpoint rejected before replacement")
		check(room._boss_actor.is_alive(),id+" rejected checkpoint retains live guardian")
		corrupt=checkpoint.duplicate(true)
		corrupt.extension.links=[]
		check(not Checkpoint.restore(room,corrupt) and room._boss_actor.is_alive(),id+" malformed reference map cannot replace live combat")
		corrupt=checkpoint.duplicate(true)
		corrupt.encounters["0"].next_wave=1
		check(not Checkpoint.restore(room,corrupt),id+" guardian state cannot skip unconsumed waves")
	var extension: RefCounted=room.enemy_skills.b10
	for core: Dictionary in extension.cores.duplicate():
		var actor: Node2D=core.actor.get_ref()
		if is_instance_valid(actor): check(actor.take_damage(float(actor.health.maximum)*100,&"skill",Vector2.RIGHT,{"damage_type":"true"}),hero+" independently breaks guardian core")
	room._boss_actor.take_damage(float(room._boss_actor.health.maximum)*100,&"skill",Vector2.RIGHT,{"damage_type":"true"})
	room._tick_expedition(.01)
	check(room._boss_defeated and room.objective_complete,hero+" "+id+" clears after guardian defeat")

func _core_phase_contract(hero: String) -> void:
	var boss: Node2D=room._boss_actor
	var extension: RefCounted=room.enemy_skills.b10
	boss.boss_brain.tick(boss,.01,room.player)
	check(extension.boss_core_count(boss)==1,hero+" P1 one core")
	boss.health.current=roundf(float(boss.health.maximum)*.69)
	boss.boss_brain.tick(boss,.01,room.player)
	check(extension.boss_core_count(boss)==2 and boss.boss_brain.phase==2,hero+" P2 two cores")
	boss.health.current=roundf(float(boss.health.maximum)*.34)
	boss.boss_brain.tick(boss,.01,room.player)
	check(extension.boss_core_count(boss)==3 and is_equal_approx(boss.boss_brain.incoming_damage_multiplier(),.55),hero+" P3 three cores and capped 45% reduction")
	for core: Dictionary in extension.cores.duplicate():
		var actor: Node2D=core.actor.get_ref()
		check(actor.take_damage(float(actor.health.maximum)*100,&"skill",Vector2.RIGHT,{"damage_type":"true","hero_id":hero}),hero+" can damage final core")
	check(boss.boss_brain.weakpoint_open() and boss.boss_brain.weakpoint_time==5.0 and is_equal_approx(boss.boss_brain.incoming_damage_multiplier(),1.15),hero+" first core clear opens five-second chest")
	var checkpoint:=Checkpoint.capture(room)
	check(not checkpoint.is_empty() and Checkpoint.restore(room,checkpoint),hero+" phase/core checkpoint restores")
	check(room._boss_actor.boss_brain.phase==3 and room.enemy_skills.b10.boss_core_count(room._boss_actor)==0,hero+" restore cannot rebuild destroyed cores for free")
	var snapshot:=Snapshot.capture(room)
	check(not snapshot.is_empty() and snapshot.runtime.has("b10_combat"),hero+" production combat snapshot includes strict B10 state")

func _echo_and_partition_contract() -> void:
	var at:=Geometry.world_point(Geometry.room("L55").encounter_anchors[0])
	var p:=Skills.profile("B10-M03",46,4)
	var actor: Node2D=room.spawn_enemy(at,"",46,{"profile":p,"zone_index":-1,"reward_enabled":false})
	actor.state=&"execute"
	var extension: RefCounted=room.enemy_skills.b10
	extension.advance(.01)
	check(extension.connected(actor),"a live core connects its first caster")
	var skill:=extension.constrain(actor,Skills.active(p,at,at+Vector2(40,0),true))
	room.enemy_skills.emit_skill(actor,skill)
	var echoes: Array=[]
	for job: Dictionary in room.enemy_skills.jobs:
		if int(job.get("stage",0))==99: echoes.append(job)
	check(echoes.size()==1 and echoes[0].coefficient==25 and echoes[0].remaining==.9,"exactly one 0.25a delayed echo")
	var before:=room.enemy_skills.jobs.size()
	extension.released(echoes[0])
	check(room.enemy_skills.jobs.size()==before,"derived echo cannot schedule another echo")
	room.enemy_skills.emit_skill(actor,skill)
	check(room.enemy_skills.jobs.size()==before,"ten-second echo gate prevents duplicate same-window scheduling")
	var command:=extension.prepare(actor,skill)
	var source_position:=room.player.position
	var gate: Dictionary=Geometry.room("L55").gates[0]
	room.player.position=Geometry.world_point(gate.position)
	command["source_zone"]=Geometry.zone_at("L55",at)
	command["cast_id"]="partition_contract"
	command["stage"]=0
	check(not extension.allow_hit(room.player,command),"ordinary damage cannot cross the fixed source partition")
	command["b10_cross_gate"]=true
	check(extension.allow_hit(room.player,command) and not extension.allow_hit(room.player,command),"explicit cross-gate cast hits at most once")
	room.player.position=source_position
	var connected_core: Node2D=extension.cores[0].actor.get_ref()
	connected_core.take_damage(float(connected_core.health.maximum)*100,&"skill",Vector2.RIGHT,{"damage_type":"true"})
	check(not extension.connected(actor),"broken core disconnects linked caster")
	check(room.enemy_skills.jobs.all(func(job: Dictionary) -> bool: return not bool(job.get("core_required",false))),"break cancels pending core-dependent echoes")
	extension.advance(7.9)
	check(not extension.connected(actor),"core remains disconnected throughout eight-second window")
	extension.advance(.11)
	check(extension.connected(actor),"ordinary core can reconnect after the full eight seconds")
	var guard:=Skills.active(Skills.profile("B10-M06",46,4),actor.position,room.player.position,true)
	extension.execute(extension.prepare(actor,guard))
	actor.brain.tick(actor,.01,room.player)
	check(actor.brain.phase==&"recovery" and actor.brain.remaining>3.0,"guard holds its full two seconds plus recovery")
	extension.advance(2.01)
	actor.brain.tick(actor,.01,room.player)
	check(actor.brain.phase==&"recovery" and actor.brain.remaining>=1.18,"guard expiry retains 1.2 seconds of vulnerable recovery")
	room.enemy_skills.jobs.clear()
	extension.echo_ready.clear()
	var bent:=extension.constrain(actor,Skills.active(Skills.profile("B10-M07",48,4),actor.position,actor.position+Vector2(200,0),true))
	bent=extension.prepare(actor,bent)
	var bent_cast:=str(bent.cast_id)
	extension.released(bent)
	var bent_echo: Dictionary={}
	for job: Dictionary in room.enemy_skills.jobs:
		if int(job.get("stage",0))==99: bent_echo=job
	check(not bent_echo.is_empty() and not bool(bent_echo.get("b10_swept_cast",true)) and bent_echo.paths[0].size()==3,"bent echo retains both frozen segments with its own receipt")
	room.player.position=actor.position
	bent["cast_id"]="bent_receipt_contract"
	bent_echo["cast_id"]=bent.cast_id
	check(extension.allow_hit(room.player,bent) and extension.allow_hit(room.player,bent_echo),"charge receipt cannot consume its later echo hit")
	bent.cast_id=bent_cast
	extension.motion_finished(bent,false)
	check(room.enemy_skills.jobs.all(func(job: Dictionary) -> bool: return str(job.get("cast_id",""))!=bent_cast),"blocked charge withdraws only its unreleased sequence")
