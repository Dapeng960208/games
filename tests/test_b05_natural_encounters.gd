extends Node
## Real candidate Room/director/Enemy/brain/runtime integration. Controlled positions,
## clocks and lethal test hits; NOT an unaided playthrough or balance acceptance.
const Controller = preload("res://scripts/world/expedition_controller.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Geometry = preload("res://scripts/world/b05_room_geometry.gd")
const Skills = preload("res://scripts/combat/b05_enemy_skills.gd")
var room: MineRoom
var stage: SubViewport
var sample_seed := 54873
var checks := 0
var failures: Array[String] = []
var introduced := {}
var records: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("B05 NATURAL HOST: "+label)
func _ready() -> void: _run.call_deferred()
func actors() -> Array[MineEnemy]:
	var result: Array[MineEnemy] = []
	for actor: MineEnemy in room.enemies.get_children():
		if actor.is_alive() and not actor.is_queued_for_deletion() and actor.actor_kind != "objective": result.append(actor)
	return result
func step(duration: float, advance_room: bool = true) -> void:
	var time := 0.0
	while time < duration-.00001:
		var dt := minf(.025,duration-time)
		room.player._physics_process(dt)
		for actor: MineEnemy in actors(): actor._physics_process(dt)
		room.enemy_skills._physics_process(dt)
		for deployment: Node in get_tree().get_nodes_in_group("hero_deployments"):
			if deployment.room==room and not deployment.is_queued_for_deletion(): deployment._physics_process(dt)
		for shot: Node in room.projectiles.get_children():
			if not shot.is_queued_for_deletion(): shot._physics_process(dt)
		if advance_room: room._physics_process(dt)
		else: room.b05_mechanics.tick(dt)
		time += dt
func install(context: Dictionary) -> bool:
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(),"previous audio cleanup")
		room.free()
	room = load("res://scenes/room.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var prepared: Dictionary = room.prepare_expedition_node(context)
	check(prepared.get("valid",false),"prepare production "+str(context.room_id))
	if not prepared.get("valid",false):
		room.free(); return false
	room.apply_prepared_expedition_node(prepared)
	(stage if is_instance_valid(stage) else self).add_child(room)
	await get_tree().process_frame
	room.combat_audio.audible = false
	room.release_gate = false
	room.pointer_release_gate = false
	check(room.configuration_ready and (str(context.role) in ["entrance","supply"] or is_instance_valid(room.b05_mechanics)),"automatic production host "+str(context.room_id))
	return true
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): sample_seed=int(argument.trim_prefix("--seed="))
	if not Game.profile_path.begins_with("user://test_b05_candidate/natural"):
		get_tree().quit(2); return
	if "--probe-gates" in OS.get_cmdline_user_args():
		var enabled: bool=preload("res://scripts/world/world_catalog.gd").b05_enabled()
		for id: String in ["BO01","BO02","BO03","BO04"]:
			check(not preload("res://scripts/world/boss_layouts.gd").build(id,54873).is_empty(),"original boss layout retained "+id)
		check(preload("res://scripts/world/boss_layouts.gd").build("BO05",54873).is_empty()!=enabled,"BO05 arena candidate gate")
		check(preload("res://scripts/world/boss_layouts.gd").build("BO06",54873).is_empty(),"BO06 remains disabled")
		finish(); return
	if "--probe-classes" in OS.get_cmdline_user_args():
		await class_probes(); finish(); return
	Game.run = null
	check(Game.new_profile() and Game.select_hero("CH02"),"isolated synthetic entrant")
	var profile: Dictionary = Game.profile.duplicate(true)
	profile.bosses = ["BO01","BO02","BO03","BO04"]
	profile.hero_xp.CH02 = Growth.thresholds()[19]
	check(Game._commit_profile(profile) and Game.start_run({"expedition":true,"biome_id":"B05","seed":sample_seed}),"candidate actual route starts")
	if "--probe-boss" in OS.get_cmdline_user_args():
		await boss_probes()
		check(await room.combat_audio.wait_for_cleanup(),"boss probe audio cleanup")
		room.free(); Game.run=null; finish(); return
	if "--probe-admission" in OS.get_cmdline_user_args():
		await admission_probes()
		check(await room.combat_audio.wait_for_cleanup(),"admission audio cleanup")
		room.free(); Game.run=null; finish(); return
	if "--probe-signatures" in OS.get_cmdline_user_args():
		await signature_probes()
		check(await room.combat_audio.wait_for_cleanup(),"probe audio cleanup")
		room.free(); Game.run=null; finish(); return
	var controller = Controller.new(Game)
	if not await install(controller.current_context()): finish(); return
	for index in range(1,Game.run.expedition.route.nodes.size()):
		for offer: Dictionary in Game.expedition_snapshot().relic_offers:
			check(Game.choose_run_relic(offer.offer_id,"skip","",room.expedition_runtime_snapshot()),"skip fixture relic")
		var next: Dictionary = controller.next_node()
		var prepared: Dictionary = room.prepare_expedition_node(controller.candidate(next.room_id))
		check(prepared.get("valid",false),"UI preflight next room "+str(next.room_id))
		if not prepared.get("valid",false): finish(); return
		check(Game.choose_expedition_node(index,next.room_id) and Game.advance_expedition_node(room.expedition_runtime_snapshot()),"enter route node "+str(index))
		prepared.runtime = Game.expedition_snapshot().runtime.duplicate(true)
		room.apply_prepared_expedition_node(prepared)
		await get_tree().process_frame
		room.release_gate = false; room.pointer_release_gate = false
		if next.role == "supply": continue
		if next.role == "boss":
			check(room._boss_actor != null and room._boss_actor.enemy_id == "BO05","actual BO05 spawned")
			# Actual damage/death signals and room settlement, no direct completion API.
			var hit: bool=room._boss_actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats})
			check(hit and room._boss_defeated and room._boss_actor.health.current==0,"actual boss lethal hit and completion signal")
			await get_tree().process_frame
			room._physics_process(.1)
		else:
			await clear_room()
		check(room.objective_complete and room.objective_rewarded,"actual clear and settlement "+room.layout_id+" "+Game.last_error)
		if not room.objective_rewarded: finish(); return
		var receipt: Dictionary = Game.run.receipt()
		room._physics_process(2)
		check(Game.run.receipt() == receipt,"repeat room tick cannot duplicate settlement "+room.layout_id)
		var saved_id: String = Game.run.id
		for repeat in range(2):
			Game.reload_profile()
			check(Game.run != null and Game.run.id == saved_id,"disk reload "+room.layout_id)
			if not await install(controller.current_context()): finish(); return
			check(room.objective_rewarded and actors().is_empty(),"cleared reload cannot respawn paid encounters "+room.layout_id)
	check(introduced.size()==18,"all eighteen species actually spawned across introductions")
	var result: Dictionary = Game.finish_run("extracted")
	check(result.get("outcome")=="extracted" and "BO05" in Game.profile.bosses,"actual route extraction")
	check(Game.finish_run("extracted")==result,"duplicate extraction frozen")
	Game.reload_profile()
	check(Game.run==null and Game.profile.total_runs==1,"extraction persisted once")
	if "--skip-probes" in OS.get_cmdline_user_args():
		check(await room.combat_audio.wait_for_cleanup(),"route audio cleanup")
		room.free(); Game.run=null; finish(); return
	# Separate controlled brain probes do not enter the persisted run above.
	check(Game.start_run({"expedition":true,"biome_id":"B05","seed":sample_seed}),"signature fixture run")
	await signature_probes()
	check(await room.combat_audio.wait_for_cleanup(),"final audio cleanup")
	room.free(); Game.run=null
	finish()
func finish() -> void:
	print("B05_NATURAL_RECORDS ",JSON.stringify(records))
	print("B05_NATURAL_HOST checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
func clear_room() -> void:
	var expected := 2 if room.layout_id=="L25" else 3
	check(room.encounter_zones.size()==expected,"authored finite zone count "+room.layout_id)
	for zone in range(expected):
		room.player.position = room.encounter_zones[zone].center
		room._physics_process(.1)
		var wave: Array[MineEnemy] = actors()
		check(not wave.is_empty() and room.activated_encounters.has(zone),"actual director activates "+room.layout_id+" zone "+str(zone))
		check(wave.size()<=6 and room._room_committed_slots()<=18,"actual zone6 room18 cap")
		var ids: Array = []
		for actor: MineEnemy in wave:
			introduced[actor.enemy_id] = true; ids.append(actor.enemy_id)
			check(actor.enemy_level==room._encounter_plan(zone).enemy_level,"actual room-fixed actor level")
		# Observe each real FSM emerging into movement/warning, then lethal test hits.
		for actor: MineEnemy in wave: actor.brain.tick(actor,.81,room.player)
		for actor: MineEnemy in wave:
			check(actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"actual enemy death "+actor.enemy_id)
		await get_tree().process_frame
		records.append({"room":room.layout_id,"zone":zone,"spawned":ids})
		room._physics_process(.1)
	check(room._encounters_exhausted(),"finite director exhausted "+room.layout_id)
	room._physics_process(.1)
func signature_probes() -> void:
	var context := {"room_id":"L28","biome_id":"B05","role":"branch","difficulty":4,"seed":sample_seed,"node_index":99}
	if not await install(context): return
	room.spawn_enabled=false
	for actor: MineEnemy in actors(): actor.free()
	Game.run.stats.max_hp = 1000000; Game.run.max_hp=1000000; Game.run.hp=1000000
	for point: Vector2 in [Vector2(770,300),Vector2(1400,300),Vector2(2100,600),Geometry.route("L28","main_route")[1]]:
		room.enemy_skills.reset_room()
		for actor: MineEnemy in actors(): actor.free()
		room.player.position=point+Vector2(100,0)
		var actor: MineEnemy=room.spawn_enemy(point,"B05-M10",23,{"profile":Profiles.resolve("B05-M10",23,"normal",2,4),"reward_enabled":false})
		if actor == null: check(false,"M10 spawn"); continue
		var hp_before: float=Game.run.hp
		var sample := {"id":"B05-M10","at":str(point),"ground":room.valid_ground(point,18),"player_ground":room.valid_ground(room.player.position,14),"admitted":false,"released":false,"damage":0}
		for tick in range(160):
			step(.025,false)
			var command: Dictionary=actor.brain.current_skill()
			if command.get("active",false): sample.admitted=true; sample.ability=command.ability_id
			if actor.brain.cycle>0: sample.released=true
		sample.damage=hp_before-Game.run.hp
		sample.final_phase=str(actor.brain.phase)
		records.append(sample)
	var successful := false
	for sample: Dictionary in records:
		if sample.get("id","")=="B05-M10" and sample.ground and sample.player_ground and sample.released: successful=true
	check(successful,"M10 signature releases from legal offroute real brain position")

func class_probes() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		Game.run=null
		check(Game.new_profile() and Game.select_hero(hero),"class fixture "+hero)
		var profile: Dictionary=Game.profile.duplicate(true)
		profile.bosses=["BO01","BO02","BO03","BO04"]
		profile.hero_xp[hero]=Growth.thresholds()[19]
		check(Game._commit_profile(profile) and Game.start_run({"expedition":true,"biome_id":"B05","seed":sample_seed}),"class actual run "+hero)
		if not await install({"room_id":"L25","biome_id":"B05","role":"branch","difficulty":0,"seed":sample_seed,"node_index":99}): return
		for actor: MineEnemy in actors(): actor.free()
		var well=room.b05_mechanics.well_target("L25-root-01")
		var distance := 80.0 if hero=="CH01" else 220.0
		room.player.position=well.position-Vector2(distance,0)
		check(room.valid_ground(room.player.position,14) and room.has_line_of_sight(room.player.position,well.position),"legal attack approach and ray "+hero)
		Game.run.resource=0
		var before: float=well.health.current
		var accepted: bool=room.player.request_attack(Vector2.RIGHT,well)
		step(.7,false)
		check(accepted and well.health.current<before,"actual zero-resource basic damages well "+hero)
		var hp_after: float=well.health.current
		if hero=="CH01":
			room.player.position=well.position-Vector2(220,0)
			room.player.request_attack(Vector2.RIGHT,well)
			step(.7,false)
			check(well.health.current==hp_after,"melee requires physical approach")
		elif hero=="CH02":
			room.player.position=well.position-Vector2(220,0)
			room.player.request_attack(Vector2.UP)
			step(.7,false)
			check(well.health.current==hp_after,"gunner off-axis ray cannot hit well")
		records.append({"hero":hero,"zero_resource_basic_damage":before-hp_after,"distance":distance})
	check(await room.combat_audio.wait_for_cleanup(),"class audio cleanup")
	room.free(); Game.run=null

func admission_probes() -> void:
	for id: String in ["L25","L26","L27","L28","L29","L30"]:
		if not await install({"room_id":id,"biome_id":"B05","role":"branch","difficulty":4,"seed":sample_seed,"node_index":99}): return
		for zone in range(room.encounter_zones.size()):
			room.player.position=room.encounter_zones[zone].center
			room.player.invulnerable=10000
			room._update_encounters(.1)
			var wave: Array[MineEnemy]=actors()
			check(not wave.is_empty(),"authored admission sample wave "+id+":"+str(zone))
			var samples: Dictionary={}
			for actor: MineEnemy in wave:
				samples[actor.get_instance_id()]={"room":id,"zone":zone,"enemy":actor.enemy_id,"at":str(actor.position),"connected":Skills.connected(actor),"signature":false,"basic":false,"releases":0,"denials":0}
			for tick in range(320):
				var previous: Dictionary={}
				for actor: MineEnemy in wave: previous[actor.get_instance_id()]=str(actor.brain.phase)
				step(.025,false)
				for actor: MineEnemy in wave:
					var sample: Dictionary=samples[actor.get_instance_id()]
					var command: Dictionary=actor.brain.current_skill()
					if not command.is_empty(): sample["signature" if command.get("active",false) else "basic"]=true
					if actor.brain.phase==&"recovery" and previous[actor.get_instance_id()]!="recovery" and command.is_empty(): sample.denials+=1
					sample.releases=actor.brain.cycle
			for sample: Dictionary in samples.values(): records.append(sample)
			for actor: MineEnemy in wave: actor.free()
			room.enemy_skills.reset_room()

func boss_probes() -> void:
	if not await install({"room_id":"BO05","biome_id":"B05","role":"boss","difficulty":4,"seed":sample_seed,"node_index":99}): return
	var boss: MineBoss=room._boss_actor
	room.player.position=boss.position+Vector2(150,0)
	room.player.invulnerable=100000
	step(.1,false)
	check(boss.boss_brain.phase==1 and room.b05_mechanics.boss_root_state().active_count==1,"real boss P1 starts one root")
	# Health thresholds are controlled; phase selection and host callbacks are real.
	boss.health.current=floor(boss.health.maximum*.69)
	step(.1,false)
	check(boss.boss_brain.phase==2 and room.b05_mechanics.boss_root_state().active_count==2,"real boss P2 activates two roots")
	var adds: Array[MineEnemy]=[]
	for tick in range(1600):
		step(.025,false)
		for actor: MineEnemy in actors():
			if actor.owner_enemy!=null and actor.owner_enemy.get_ref()==boss and not adds.has(actor): adds.append(actor)
		if not adds.is_empty(): break
	check(adds.size()==2,"natural eligible boss brain releases two transplant adds")
	var prior_kills: int=Game.run.kills
	var prior_gold: int=Game.run.gold
	var prior_loot: Dictionary=Game.run.expedition.loot_events.duplicate(true)
	for actor: MineEnemy in adds:
		check(not actor.reward_enabled,"real transplant add rewards disabled")
		actor.take_damage(10000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats})
	await get_tree().process_frame
	check(Game.run.kills==prior_kills and Game.run.gold==prior_gold and Game.run.expedition.loot_events==prior_loot and Game.run.staged_loot_requests.is_empty(),"actual summoned deaths mint no kill/gold/equipment")
	boss.health.current=floor(boss.health.maximum*.34)
	step(.1,false)
	check(boss.boss_brain.phase==3 and room.b05_mechanics.boss_root_state().active_count==2,"real boss P3 activates rotating pair")
	var before: Array=room.b05_mechanics.boss_root_state().active_positions.duplicate()
	step(6.1,false)
	check(room.b05_mechanics.boss_root_state().active_positions!=before,"real P3 root pair rotates on timer")
	var active_well: Node2D
	for key: String in room.b05_mechanics._targets:
		if room.b05_mechanics.well_is_active(key): active_well=room.b05_mechanics.well_target(key); break
	check(active_well!=null,"active root can be targeted")
	if active_well!=null:
		check(active_well.take_damage(10000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"actual active root destroyed")
		check(boss.boss_brain.weakpoint_open() and boss.get_meta("boss_weakpoint","")=="flower_heart","actual root destruction exposes flower core")
		check(is_equal_approx(boss.boss_brain.incoming_damage_multiplier(),1.15),"exposed core damage contract")
		var landmarks: Dictionary=boss.body_visual.visual_landmarks()
		check(not landmarks.is_empty() and Vector2(landmarks.core_global).is_finite(),"exposed core has registered live visual landmark")
		step(4.1,false)
		check(not boss.boss_brain.weakpoint_open(),"exposure expires after four seconds")
	records.append({"boss":"BO05","phases":[1,2,3],"root_counts":[1,2,2],"summons":adds.size(),"exposure_seconds":4,"visual_scope":"runtime landmark only; no rendered readability claim"})
