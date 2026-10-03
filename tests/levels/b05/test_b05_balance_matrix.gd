extends Node
## Controlled live-scene measurements. Never evidence of human natural play.
## See docs/system/balance/s11_controlled_matrix.md for the frozen input protocol.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const ObservedRoom = preload("res://tests/support/b05_balance_observed_room.gd")
const Trail = preload("res://tests/support/b05_guard_damage_trail.gd")
const Driver = preload("res://tests/support/b05_balance_controller.gd")
const Fixtures = preload("res://tests/support/b05_balance_fixtures.gd")
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
const NativeProfile = preload("res://scripts/domain/equipment/numerical_profile.gd")
var room: RoomController
var stage: SubViewport
var boss: BossActor
var run_ref: RunSession
var driver: RefCounted
var trail: RefCounted
var running := false
var elapsed := 0.0
var started_wall := 0
var setup_wall := 0
var completed := false
var config: Dictionary = {}
var fixture: Dictionary = {}
var phases: Dictionary = {}
var states: Dictionary = {}
var casts: Dictionary = {}
var cast_failures: Dictionary = {}
var events: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var old_phase := 0
var old_action := ""
var old_state := ""
var old_counts: Dictionary = {}
var old_icds: Dictionary = {}
var old_counters: Dictionary = {}
var next_sample := 0.0
var last_boss_hp := 0.0
var last_boss_shield := 0.0
var boss_max_hp := 0.0
var boss_start_shield := 0.0
var resource_empty_seconds := 0.0
var weakpoint_seconds := 0.0
var attackable_seconds := 0.0
var pause_seconds := 0.0
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var output_path := ""
var max_seconds := 180.0
var limit_cases := 0
var probe := false
var timing_mode := "fixed_fps"
var physics_steps := 0
var process_frames := 0
var minimum_physics_delta := INF
var maximum_physics_delta := 0.0
var controlled_room_id := ""
var next_objective_decision := 0.0
var measurement_protocol: Dictionary = {}
var screenshots: Array[Dictionary] = []
var capture_directory := ""
var rendering_metadata: Dictionary = {}
var controller_opportunities := 0
var controller_calls := 0
var mana_ledger: Array[Dictionary] = []
var last_resource_end := 0.0
var last_regen_delay := 0.0
var last_regen_remainder := 0.0
var isolated_actor: EnemyActor

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("S11 MATRIX: "+label)

func arg(key: String, fallback: String = "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--"+key+"="): return value.trim_prefix("--"+key+"=")
	return fallback

func _run() -> void:
	if not Game.profile_path.contains("test_b05_candidate/balance"):
		get_tree().quit(2)
		return
	check(Engine.physics_ticks_per_second == 60 and is_equal_approx(Engine.time_scale,1.0),"native 60 Hz physics at time_scale 1")
	rendering_metadata={"display_server":DisplayServer.get_name(),"graphical_evidence":DisplayServer.get_name()!="headless","hardware_acceleration_assumed":false}
	if DisplayServer.get_name()!="headless":
		for method: String in ["get_current_rendering_method","get_current_rendering_driver_name","get_video_adapter_name","get_video_adapter_vendor","get_video_adapter_type","get_video_adapter_api_version"]:
			if RenderingServer.has_method(method): rendering_metadata[method]=RenderingServer.call(method)
	output_path = arg("output",Game.profile_path.get_base_dir().path_join("s11_matrix.json"))
	max_seconds = float(arg("max-seconds","180"))
	limit_cases = int(arg("limit","0"))
	probe = arg("probe","false") == "true"
	timing_mode = arg("timing-mode","fixed_fps")
	controlled_room_id = arg("room-id","")
	capture_directory=arg("capture-directory","")
	check(capture_directory.is_empty() or DisplayServer.get_name()!="headless","screenshots require actual GPU rendering")
	check(timing_mode in ["fixed_fps","real_time"],"explicit simulation/real-time measurement mode")
	var protocol_file := arg("protocol-file","")
	if not protocol_file.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(protocol_file)))
		if parsed is Dictionary: measurement_protocol=parsed
	check(bool(measurement_protocol.get("protocol_pinned",false)) or probe,"non-probe measurements require a pinned protocol")
	if not measurement_protocol.is_empty():
		check(measurement_protocol.get("schema")=="s11-controlled-matrix-v2" and measurement_protocol.get("controller_version")==Driver.VERSION,"protocol schema and controller match")
		check(measurement_protocol.get("timing_mode")==timing_mode and bool(measurement_protocol.get("probe",false))==probe and float(measurement_protocol.get("max_seconds",0))==max_seconds,"timing/probe/limit match pinned protocol")
		check((measurement_protocol.get("display_mode")=="headless")== (DisplayServer.get_name()=="headless"),"actual display matches pinned protocol")
		check(measurement_protocol.get("capture_policy","none")==("gpu_start_end_outside_combat" if not capture_directory.is_empty() else "none"),"capture policy matches pinned protocol")
	if not failures.is_empty():
		get_tree().quit(1)
		return
	check(Game.new_profile(),"fresh isolated profile available")
	AudioServer.set_bus_mute(0,true)
	for action: String in InputMap.get_actions(): Input.action_release(action)
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.handle_input_locally = true
	add_child(stage)
	if DisplayServer.get_name() != "headless":
		stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var presentation := TextureRect.new()
		presentation.texture = stage.get_texture()
		presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		presentation.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(presentation)
	trail = Trail.new()
	Game.damage_trail = trail
	# Freeze all 27 manifests on disk before any fight begins, independent of pilot filters.
	var manifests: Array = []
	for h: String in Fixtures.HEROES:
		for m: String in Fixtures.MIXES:
			for s: String in ["G2","P5","lowG2"]:
				var frozen: Dictionary = Fixtures.build(5,h,s,m,arg("mage-affix-profile","frozen"),int(arg("hero-level","21")))
				check(not frozen.is_empty(),"legal frozen fixture "+h+"/"+m+"/"+s)
				if not frozen.is_empty(): manifests.append(frozen.manifest)
	var manifest_file := FileAccess.open(AssetCatalog.resolve(arg("manifest-output","/tmp/b05-balance-manifest.json")),FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifests,"\t")); manifest_file.close()
	if not failures.is_empty(): get_tree().quit(1); return
	if arg("freeze-only","false")=="true": get_tree().quit(0); return
	var chapters := arg("chapters","5").split(",")
	var heroes := arg("heroes","CH01,CH02,CH03").split(",")
	var samples := arg("samples","G2,P5,lowG2").split(",")
	var difficulties := arg("difficulties","4").split(",")
	var seeds := arg("seeds","1001,1002,1003,1004,1005,1006,1007,1008,1009,1010").split(",")
	if not measurement_protocol.is_empty():
		var expected: Array[String] = []
		for value in measurement_protocol.seeds: expected.append(str(int(value)))
		check(",".join(expected)==",".join(seeds),"exact ordered seeds match pinned protocol")
	for chapter: String in chapters:
		for hero: String in heroes:
			for sample: String in samples:
				for difficulty: String in difficulties:
					for fight_seed: String in seeds:
						if limit_cases > 0 and rows.size() >= limit_cases: break
						config = {"chapter":int(chapter),"hero_id":hero,"sample":sample,"difficulty":int(difficulty),"seed":int(fight_seed),"mix":arg("mix","class6")}
						if not controlled_room_id.is_empty(): config.merge({"encounter":"room","room_id":controlled_room_id})
						await install()
						if not failures.is_empty(): break
						while running: await get_tree().process_frame
						finish_record()
						if not capture_directory.is_empty():
							await capture_frame("finish")
							rows.back()["screenshots"]=screenshots.duplicate(true)
						_save()
						await cleanup()
					if not failures.is_empty(): break
				if not failures.is_empty(): break
			if not failures.is_empty(): break
		if not failures.is_empty(): break
	await cleanup()
	_save()
	print("B05_BALANCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"fights":rows.size(),"output":output_path,"probe":probe}))
	get_tree().quit(0 if failures.is_empty() else 1)

func install() -> void:
	setup_wall = Time.get_ticks_usec()
	get_tree().paused = true
	fixture = Fixtures.build_naked(int(config.chapter),str(config.hero_id),int(arg("hero-level","21"))) if str(config.sample)=="naked" else Fixtures.build(int(config.chapter),str(config.hero_id),str(config.sample),arg("mix","class6"),arg("mage-affix-profile","frozen"),int(arg("hero-level","21")))
	config["hero_level"] = int(arg("hero-level","21"))
	check(not fixture.is_empty() and fixture.get("errors",[]).is_empty(),"frozen fixture valid "+JSON.stringify(config))
	if fixture.is_empty(): return
	Game.profile = NativeProfile.fresh(ProfileStore.fresh_profile())
	Game.profile.selected_hero = config.hero_id
	Game.profile.hero_xp[config.hero_id] = Progression.thresholds()[int(fixture.level)-1]
	Game.profile.bosses = ["BO01","BO02","BO03","BO04"]
	Game.profile.equipment = fixture.owned.duplicate(true)
	Game.profile.loadout = fixture.loadout.duplicate(true)
	Game.profile.loadout_presets = {config.hero_id:fixture.loadout.duplicate(true)}
	Game.profile.talents = {config.hero_id:fixture.talents.duplicate(true)}
	Game.profile.branches[config.hero_id] = {"q":"","ultimate":""}
	Game.profile.branches[config.hero_id].merge(fixture.branches,true)
	Game.profile.equipment_discoveries = []
	for item: Dictionary in fixture.owned.values(): Game.profile.equipment_discoveries.append(item.template_id)
	Game.profile.settings.auto_attack = false
	Game.profile.settings.camera_shake = false
	if not ProfileStore._valid_progression(Game.profile):
		print("S11_PROFILE_DIAGNOSTIC ",JSON.stringify({"growth":ProfileStore._valid_v2_growth(Game.profile),"equipment":ProfileStore._valid_instance_equipment(Game.profile),"branches":ProfileStore._valid_branches(Game.profile.branches,Game.profile.hero_xp,2),"forging":preload("res://scripts/domain/equipment/instance_forging.gd").validate_profile(Game.profile),"profile":Game.profile}))
	# Ordinary-room completion reads the production expedition reward container.
	# Keep that real container at its entrance checkpoint (never advance it):
	# the controlled room's completion can be observed, while its reward commit
	# is ineligible and cannot change the fixed player level/loadout.
	var start_options := {"expedition":true,"biome_id":"B%02d"%int(config.chapter),"difficulty":int(config.difficulty),"seed":int(config.seed)}
	var started: bool = Game.start_run(start_options)
	check(started,"production start_run accepts fixed legal owned build: "+Game.last_error)
	if Game.run == null: return
	run_ref = Game.run
	if not measurement_protocol.is_empty(): check(JSON.parse_string(JSON.stringify(run_ref.enemy_calibration_snapshot))==measurement_protocol.get("calibration",{}),"frozen runtime calibration matches protocol")
	check(run_ref.ruleset_version()==2 and run_ref.level==int(fixture.level),"real version and chapter level")
	if int(run_ref.enemy_calibration_snapshot.get("version",0)) == 15:
		var gear: Dictionary = run_ref.stats.get("uncapped_equipment_contribution",{})
		var talent_crit: float = float(run_ref.stats.get("hero_base",{}).get("talent_crit_chance",0.0))
		var expected_chance := clampf(0.25 + float(gear.get("crit_chance",0.0)) + talent_crit,0.0,1.0)
		var expected_multiplier := clampf(2.0 + float(gear.get("crit_multiplier",0.0)),1.0,3.0)
		check(int(run_ref.stats.get("crit_policy_version",0)) == 1,"archive15 actual RunSession crit conversion active")
		check(is_equal_approx(float(run_ref.stats.crit_chance),expected_chance) and is_equal_approx(float(run_ref.stats.crit_multiplier),expected_multiplier),"archive15 actual player crit base gear talent and final caps")
		fixture["runtime_crit_audit"]={"snapshot_version":15,"expected_chance":expected_chance,"actual_chance":run_ref.stats.crit_chance,"expected_multiplier":expected_multiplier,"actual_multiplier":run_ref.stats.crit_multiplier,"caps":{"chance":1.0,"multiplier":3.0},"fixture_stats_are_not_runtime_authority":true}

	check(run_ref.relics.is_empty() and not run_ref.demo and run_ref.hp==run_ref.max_hp and run_ref.resource==run_ref.stats.starting_resource,"full HP, normal resource, no relic/demo boosts")
	room = RoomScene.instantiate()
	room.set_script(preload("res://tests/support/b05_single_actor_room.gd") if not arg("single-enemy","").is_empty() else ObservedRoom)
	# The headless raster backend cannot compile the background's visual-only
	# custom sampler shader. The backdrop never owns geometry or combat state.
	# Manual/GPU sessions retain it; all gameplay nodes remain production nodes.
	if DisplayServer.get_name() == "headless": room.get_node("MineBackdrop").set_script(preload("res://tests/support/b05_balance_headless_backdrop.gd"))
	var room_id := controlled_room_id if not controlled_room_id.is_empty() else "BO%02d"%int(config.chapter)
	var prepared := room.prepare_expedition_node({"room_id":room_id,"role":scenario_room_role(),"biome_id":"B%02d"%int(config.chapter),"node_index":1 if not controlled_room_id.is_empty() else 6,"node_count":7,"difficulty":int(config.difficulty),"seed":int(config.seed),"phase":"combat","expedition":true})
	check(bool(prepared.get("valid",false)),"actual production room prepares")
	if not bool(prepared.get("valid",false)): return
	room.apply_prepared_expedition_node(prepared)
	stage.add_child(room)
	trail.player_reference=weakref(room.player)
	boss = room._boss_actor as BossActor
	if controlled_room_id.is_empty():
		check(is_instance_valid(boss) and boss.profile.ruleset_version==2 and boss.enemy_level==int(config.chapter)*5,"actual V2 boss installed")
		if not is_instance_valid(boss): return
		# Production rooms currently request seed0. Controlled fixtures explicitly
		# configure the requested seed before any native physics or fight clock;
		# this preserves full health, normal guard, AI, counterplay and mechanics.
		check(boss.configure_boss(room_id,int(config.difficulty),int(config.seed),2,run_ref.enemy_calibration_snapshot),"production Boss configuration accepts the fixed combat seed")
		check(boss.boss_seed==int(config.seed) and boss.boss_brain._rng.seed==int(config.seed),"private Boss AI seed matches requested seed")
		if arg("boss-test-candidate","") in ["A","B"]:
			var boss_candidate := arg("boss-test-candidate","")
			check(int(config.difficulty)==4 and int(run_ref.enemy_calibration_snapshot.get("version",0))==15,"test candidate restricted to archive15 D4")
			var baseline_profile: Dictionary = boss.profile.duplicate(true)
			var candidate_profile: Dictionary = baseline_profile.duplicate(true)
			var overrides: Dictionary = {"max_hp":177834,"armor":3300,"magic_resist":380,"damage":984} if boss_candidate == "A" else {"max_hp":183169,"armor":3300,"magic_resist":440,"damage":984}
			candidate_profile.merge(overrides,true)
			boss.configure(candidate_profile,{"reward_enabled":false,"actor_kind":"boss","zone_index":-1})
			config["boss_test_candidate"] = boss_candidate
			fixture["boss_test_override"]={"candidate_id":"B05-D4-"+boss_candidate,"test_only":true,"baseline_profile":baseline_profile,"overrides":overrides,"applied_before_physics":true}
			check(boss.health.maximum==int(overrides.max_hp) and boss.health.current==int(overrides.max_hp) and boss.armor==int(overrides.armor) and boss.magic_resist==int(overrides.magic_resist) and boss.contact_damage==int(overrides.damage),"test candidate real actor fields match declared test profile")
			check(boss.boss_seed==int(config.seed) and boss.boss_brain._rng.seed==int(config.seed),"test candidate preserves native Boss seed")

		boss.completed.connect(_boss_completed)
		boss.phase_changed.connect(_phase_changed)
		boss.weakpoint_changed.connect(_weakpoint_changed)
	elif requires_room_objectives():
		check(room.layout_id==controlled_room_id and is_instance_valid(room.objectives),"authored ordinary room and objectives installed")
	var native_skill_layer: int = room.enemy_skills.z_index
	room.enemy_skills.set_script(preload("res://tests/support/s11_directed_enemy_skills.gd"))
	room.enemy_skills.configure(room)
	room.enemy_skills.z_index=native_skill_layer
	room.player.abilities=preload("res://tests/support/b05_balance_observed_abilities.gd").new()
	room.player.abilities.configure(room.player)
	room.player.skill_input_feedback.connect(_skill_feedback)
	driver = Driver.new()
	driver.configure(room)
	elapsed=0; completed=false; phases={}; states={}; casts={}; cast_failures={}; events=[]; snapshots=[]
	old_phase=0; old_action=""; old_state=""; old_counts={}; old_icds={}; old_counters={}; next_sample=0
	resource_empty_seconds=0; weakpoint_seconds=0; attackable_seconds=0; pause_seconds=0
	physics_steps=0; process_frames=0; minimum_physics_delta=INF; maximum_physics_delta=0
	controller_opportunities=0; controller_calls=0
	screenshots=[]
	next_objective_decision=0
	last_boss_hp=boss.health.current if is_instance_valid(boss) else 0; last_boss_shield=boss.status.shield() if is_instance_valid(boss) else 0; boss_max_hp=last_boss_hp; boss_start_shield=last_boss_shield
	fixture["resolved_stats"] = run_ref.stats.duplicate(true)
	fixture["boss_profile"] = boss.profile.duplicate(true) if is_instance_valid(boss) else {}
	fixture["actual_boss_seed"] = boss.boss_seed if is_instance_valid(boss) else null
	fixture["actual_boss_rng_seed"] = boss.boss_brain._rng.seed if is_instance_valid(boss) else null
	fixture["room_context"] = room.expedition_context.duplicate(true)
	fixture["skills"] = {}
	for slot: String in ["q","secondary","f","ultimate"]: fixture.skills[slot] = room.player.skill_definition(slot)
	if str(config.hero_id)=="CH03" and int(run_ref.stats.get("mage_balance_candidate",0))==1:
		var expected_power: Dictionary=preload("res://scripts/gameplay/characters/hero_abilities.gd").preview_powers("CH03",run_ref.stats)
		check(room.player.skill_power()==expected_power.skill_H and room.player.skill_power()>float(run_ref.stats.attack)+float(run_ref.stats.ability_power),"live mage candidate spell H reaches actor without changing AP")
	if str(config.hero_id)=="CH01" and int(run_ref.stats.get("warrior_balance_candidate",0))==1:
		check(room.player.skill_power()==preload("res://scripts/gameplay/characters/hero_abilities.gd").preview_powers("CH01",run_ref.stats).skill_H and room.player.skill_power()>room.player.basic_power(),"live warrior candidate only skill H reaches actor")
	fixture["entry_position"] = [room.player.position.x,room.player.position.y]
	initialize_directed_scenario()
	fixture["setup_wall_seconds"] = float(Time.get_ticks_usec()-setup_wall)/1000000.0
	seed(int(config.seed))
	if not capture_directory.is_empty(): await capture_frame("start")
	if DisplayServer.get_name()!="headless" and timing_mode=="real_time":
		# Rendering readback/PNG encoding blocks the host while the fixture is
		# paused. Drain the next complete physics batch while it is STILL paused,
		# then begin at the following process boundary. Otherwise the screenshot
		# cost can become several immediate catch-up steps inside combat time.
		var flush_started := Time.get_ticks_usec()
		var flush_frame := Engine.get_physics_frames()
		await get_tree().physics_frame
		await get_tree().process_frame
		fixture["preclock_paused_physics_flush"]={"host_seconds":float(Time.get_ticks_usec()-flush_started)/1000000.0,"native_physics_frames":Engine.get_physics_frames()-flush_frame,"remained_paused":get_tree().paused}
		check(get_tree().paused and not running,"graphical startup physics backlog drained before combat clock")
	room.release_gate = false
	room.pointer_release_gate = false
	mana_ledger=[]
	last_resource_end=run_ref.resource
	last_regen_delay=room.player.resource_delay
	last_regen_remainder=run_ref.resource_regen_remainder
	room.recording = true
	started_wall = Time.get_ticks_usec()
	running = true
	get_tree().paused = false
	print("B05_BALANCE_BEGIN ",JSON.stringify(config))

func initialize_directed_scenario() -> void:
	isolated_actor=null
	var enemy_id:=arg("single-enemy","")
	if enemy_id.is_empty():return
	config["experiment"]="controlled_hit_pressure" if arg("hit-pressure","false")=="true" else "single_actor_legal_combat"
	check(controlled_room_id!="","single actor uses explicit ordinary-room geometry")
	check(room._living_enemy_count()==0,"isolated actor fixture starts without ordinary waves")
	var at:=Vector2.INF
	for i in 32:
		var point:=room.player.position+Vector2.from_angle(TAU*float(i)/32)*100.0
		if room.valid_ground(point,22.0) and room.has_line_of_sight(point,room.player.position):at=point;break
	check(at.is_finite(),"one-actor lawful initial ground")
	if not at.is_finite():return
	isolated_actor=room.spawn_enemy(at,enemy_id,25,{"reward_enabled":false,"rank":"normal"})
	check(is_instance_valid(isolated_actor) and isolated_actor.enemy_id==enemy_id,"actual ordinary actor installed")
	if arg("hit-pressure","false")=="true":driver=preload("res://tests/support/b05_tolerance_controller.gd").new()
	else:
		driver=preload("res://tests/support/b05_single_actor_controller.gd").new()
		driver.configure(room)
	fixture["negative_control_scope"]={"synthetic_single_actor":true,"authored_wave_evidence":false,"no_actor_damage_or_health_override":true,"enemy_id":enemy_id,"enemy_level":25,"hit_pressure":arg("hit-pressure","false")=="true","player_initial_position":[room.player.position.x,room.player.position.y],"enemy_initial_position":[at.x,at.y]}


func requires_attack_evidence() -> bool:
	return arg("hit-pressure","false")!="true"

func scenario_room_role() -> String:
	return "normal" if not controlled_room_id.is_empty() else "boss"

func requires_room_objectives() -> bool:
	return true

func scenario_complete() -> bool:
	if not arg("single-enemy","").is_empty():return not is_instance_valid(isolated_actor) or not isolated_actor.is_alive()
	return not controlled_room_id.is_empty() and room.objective_complete

func drives_room_objectives() -> bool:
	return not controlled_room_id.is_empty() and arg("single-enemy","").is_empty()

func capture_frame(label: String) -> void:
	# Start: prepared scene paused, clock not started. Finish: result/host time
	# already recorded and room physics stopped. Never pause an active fight.
	var capture_started := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var pixels := stage.get_texture().get_image()
	var path := capture_directory.path_join("B%02d_%s_%s_D%d_seed%d_%s.png"%[int(config.chapter),str(config.hero_id),str(config.sample),int(config.difficulty),int(config.seed),label])
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var result: int = pixels.save_png(path)
	check(result==OK,"actual GPU viewport screenshot saved: "+label)
	screenshots.append({"kind":label,"path":path,"width":pixels.get_width(),"height":pixels.get_height(),"simulation_seconds":elapsed,"physics_steps":physics_steps,"host_capture_seconds":float(Time.get_ticks_usec()-capture_started)/1000000.0,"outside_combat_interval":true,"normal_production_background":true,"timestamp_utc":Time.get_datetime_string_from_system(true)})

func _physics_process(delta: float) -> void:
	if not running: return
	if get_tree().paused:
		pause_seconds += delta
		return
	if str(config.hero_id)=="CH03":
		var rate: float=room.player.stat("resource_regen",0)*room.player.resource_gain_multiplier()
		var intended: float=floorf(last_regen_remainder+roundf(rate)*maxf(0.0,delta-last_regen_delay)+0.000001)
		var actual: float=float(run_ref.resource)-last_resource_end
		mana_ledger.append({"t":elapsed+delta,"kind":"native_frame_regen","before":last_resource_end,"after":run_ref.resource,"intended":intended,"actual":actual,"overcap":maxf(0,intended-actual),"delay_before":last_regen_delay})
	physics_steps += 1
	minimum_physics_delta = minf(minimum_physics_delta,delta)
	maximum_physics_delta = maxf(maximum_physics_delta,delta)
	elapsed += delta
	room.scan_actors()
	if scenario_complete(): completed=true
	if is_instance_valid(boss):
		last_boss_hp = boss.health.current
		last_boss_shield = boss.status.shield()
		var brain: BossBrain = boss.boss_brain
		var key := str(brain.phase)
		if not phases.has(key): phases[key] = {"seconds":0.0,"casts":{},"entered_at":elapsed}
		phases[key].seconds += delta
		states[str(brain.state)] = float(states.get(str(brain.state),0.0))+delta
		if brain.weakpoint_open(): weakpoint_seconds += delta
		if not bool(boss.status.damage_modifiers().get("invulnerable",false)): attackable_seconds += delta
		if old_phase != brain.phase or old_action != brain.current_action or old_state != str(brain.state):
			events.append({"t":elapsed,"kind":"boss_state","phase":brain.phase,"state":str(brain.state),"action":brain.current_action,"warning":_json_value(brain.current_telegraph())})
			old_phase=brain.phase; old_action=brain.current_action; old_state=str(brain.state)
		var used: Dictionary = brain.tactical_snapshot().actions_used
		for action: String in used:
			var difference := int(used[action])-int(old_counts.get(action,0))
			if difference > 0:
				phases[key].casts[action] = int(phases[key].casts.get(action,0))+difference
				events.append({"t":elapsed,"kind":"boss_release","phase":brain.phase,"action":action,"count":difference,"command":_json_value(brain.command)})
		old_counts=used.duplicate(true)
		var counters: Dictionary = brain.counter_snapshot()
		if counters != old_counters:
			events.append({"t":elapsed,"kind":"arena_counter","state":_json_value(counters)})
			old_counters=counters.duplicate(true)
	if run_ref.resource <= 0: resource_empty_seconds += delta
	var icds: Dictionary = room.player.loadout.effects.cooldowns
	for source: String in icds:
		if float(icds[source]) > float(old_icds.get(source,0))+.001:
			events.append({"t":elapsed,"kind":"equipment_icd_start","source":source,"ready_at":icds[source]})
	old_icds=icds.duplicate(true)
	if elapsed >= next_sample:
		snapshots.append(snapshot())
		next_sample += 1.0
	if completed or run_ref.hp<=0 or Game.run==null or elapsed >= max_seconds:
		running=false
		room.process_mode=Node.PROCESS_MODE_DISABLED
		return
	controller_opportunities+=1
	driver.step(elapsed)
	controller_calls+=1
	if drives_room_objectives(): ordinary_objective_step()
	last_resource_end=run_ref.resource
	last_regen_delay=room.player.resource_delay
	last_regen_remainder=run_ref.resource_regen_remainder

func ordinary_objective_step() -> void:
	if elapsed < next_objective_decision or not room.controls_enabled(): return
	next_objective_decision=elapsed+.1
	if room._living_enemy_count()>0: return
	var warnings: Array[Dictionary] = driver.visible_threats()
	if driver.danger_at(room.player.position,warnings)>0: return
	var destination: Dictionary = room.objectives.navigation_target() if is_instance_valid(room.objectives) and not room.objectives.is_complete() else {}
	var id := str(destination.get("id",""))
	if not id.is_empty():
		var target: Node2D = room.objectives.targets.get(id)
		if is_instance_valid(target) and target.is_alive():
			driver.attack_target(elapsed,target,warnings,true)
			return
	if not destination.has("position"): destination=room.navigation_target()
	if not destination.has("position"): return
	var at: Vector2 = destination.position
	if room.player.position.distance_to(at)>65: driver.navigate_to_reachable(elapsed,at,45.0,warnings)
	else:
		room.player.clear_movement_target()
		room.interact()

func _process(_delta: float) -> void:
	if running and not get_tree().paused: process_frames += 1

func snapshot() -> Dictionary:
	return {"t":elapsed,"hp":run_ref.hp,"shield":run_ref.shield,"resource":run_ref.resource,"boss_hp":0 if completed else last_boss_hp,"boss_shield":last_boss_shield,"phase":old_phase,
		"player_position":[room.player.position.x,room.player.position.y],"cooldowns":room.player.cooldowns.duplicate(true),"hit_chain":room.player.hit_chain.count,
		"break_stacks":room.player.break_stacks,"telemetry":room.telemetry.duplicate(true),"native_boss_ai_elapsed":boss.boss_brain.elapsed if is_instance_valid(boss) else elapsed,
		"active_enemy_hazards":room.enemy_skills.active_effect_count(),"live_enemies":room._living_enemy_count(),"equipment_counts":room.player.loadout.effects.counts.duplicate(true),"objective_complete":room.objective_complete,"objective":room.objectives.status() if is_instance_valid(room.objectives) else {}}

func _boss_completed(_id: String, _payload: Dictionary) -> void:
	completed=true
	last_boss_hp=0
	events.append({"t":room.elapsed,"kind":"boss_completed"})

func _phase_changed(_id: String, phase: int, ratio: float) -> void:
	if not running: return
	var key := str(phase)
	if not phases.has(key): phases[key] = {"seconds":0.0,"casts":{},"entered_at":room.elapsed}
	events.append({"t":room.elapsed,"kind":"phase_entered","phase":phase,"hp_ratio":ratio})

func _weakpoint_changed(_id: String, open: bool, id: String, duration: float) -> void:
	if running: events.append({"t":room.elapsed,"kind":"weakpoint_changed","open":open,"id":id,"duration":duration})

func _skill_feedback(slot: String, reason: String, details: Dictionary) -> void:
	if not running: return
	if reason=="accepted" and str(config.hero_id)=="CH03" and not room.player.abilities.last_commit.is_empty():
		var entry: Dictionary=room.player.abilities.last_commit.duplicate(true)
		entry["kind"]="paid_cast_resource"
		entry["resource_after_equipment"]=run_ref.resource
		entry["effective_equipment_refund"]=float(run_ref.resource)-float(entry.resource_after_class_refund)
		mana_ledger.append(entry)
	if reason == "accepted": casts[slot]=int(casts.get(slot,0))+1
	elif reason != "queued": cast_failures[reason]=int(cast_failures.get(reason,0))+1
	if reason in ["accepted","queued"]: events.append({"t":elapsed,"kind":"player_request","slot":slot,"reason":reason,"details":_json_value(details)})

func finish_record() -> void:
	var incoming_hp := 0.0
	var incoming_shield := 0.0
	for packet: Dictionary in trail.all_events:
		incoming_hp+=float(packet.hp_loss); incoming_shield+=float(packet.shield_absorbed)
	var outgoing := {"boss_hp":0.0,"boss_shield":0.0,"counter_hp":0.0,"other_hp":0.0,"weakpoint_hp_and_shield":0.0,"unknown":0.0}
	for packet: Dictionary in room.packets:
		if packet.kind in ["received","heal","guard"]: continue
		if bool(packet.boss):
			outgoing["boss_shield" if packet.feedback_kind=="shield" else "boss_hp"] += float(packet.amount)
			if bool(packet.weakpoint): outgoing.weakpoint_hp_and_shield+=float(packet.amount)
		elif packet.target_kind == "objective": outgoing.counter_hp+=float(packet.amount)
		elif packet.target_kind == "unknown": outgoing.unknown+=float(packet.amount)
		elif packet.feedback_kind != "shield": outgoing.other_hp+=float(packet.amount)
	if int(run_ref.enemy_calibration_snapshot.get("version",0)) == 15:
		var critical_packets: Array = room.packets.filter(func(packet:Dictionary)->bool: return packet.kind not in ["received","heal","guard"] and bool(packet.get("critical",false)) and float(packet.get("amount",0.0))>0.0)
		fixture.runtime_crit_audit["actual_positive_critical_packets"] = critical_packets.size()
		fixture.runtime_crit_audit["first_actual_critical_packet"] = critical_packets[0].duplicate(true) if not critical_packets.is_empty() else {}
		if requires_attack_evidence(): check(not critical_packets.is_empty(),"archive15 observes at least one actual positive outgoing critical packet")
	var skipped: Array[int] = []
	var skipped_details: Array[Dictionary] = []
	for phase in ([1,2,3] if controlled_room_id.is_empty() else []):
		if not phases.has(str(phase)) or phases[str(phase)].casts.is_empty():
			skipped.append(phase)
			skipped_details.append({"phase":phase,"entered":phases.has(str(phase)),"reason":"output_skipped" if completed else "terminated_before_phase_cast"})
	var outcome := "player_died" if run_ref.hp<=0 else ("boss_defeated" if controlled_room_id.is_empty() else "room_cleared") if completed else "time_limit"
	var won: bool = outcome in ["boss_defeated","room_cleared"]
	check(physics_steps>0,"actual native physics exercised")
	check(controller_calls==controller_opportunities,"controller called at every available input step")
	check(not won or not requires_attack_evidence() or (room.telemetry.shots>0 or config.hero_id=="CH03") or probe or not controlled_room_id.is_empty(),"victory exercises production attack path")
	check(not won or not requires_attack_evidence() or not casts.is_empty() or probe,"victory exercises production skill/input path")
	check(Game.run==null or run_ref.stats==fixture.resolved_stats,"resolved stats untouched in combat")
	check(not is_instance_valid(boss) or not boss.training_ai_disabled,"production AI stays enabled")
	var commands: Array = room.enemy_skills.executed_commands
	if int(config.difficulty)==4 and controlled_room_id.is_empty() and elapsed>6.0:
		check(not commands.is_empty(),"actual enemy skill execution, not dropped commands")
		for command: Dictionary in commands:
			if int(command.get("coefficient",0))>0:check(float(command.get("damage",0))>0,"offensive Boss command has actual positive frozen damage")
	var record := {"configuration":config.duplicate(true),"fixture":fixture.duplicate(true),"outcome":outcome,"probe":probe,"final":snapshot(),
		"simulation_seconds":elapsed,"host_wall_seconds":float(Time.get_ticks_usec()-started_wall)/1000000.0,"pause_seconds":pause_seconds,
		"timing_mode":timing_mode,"display_server":DisplayServer.get_name(),"physics_steps":physics_steps,"process_frames":process_frames,"physics_delta_min":minimum_physics_delta,"physics_delta_max":maximum_physics_delta,
		"hp_fraction":float(run_ref.hp)/float(run_ref.max_hp),"hp_loss":incoming_hp,"shield_absorbed":incoming_shield,
		"effective_player_healing":maxf(0,float(run_ref.hp)-float(run_ref.max_hp)+incoming_hp),
		"effective_boss_healing":maxf(0,(0 if completed else last_boss_hp)-boss_max_hp+float(outgoing.boss_hp)),
		"boss_initial_shield":boss_start_shield,"outgoing":outgoing,"weakpoint_seconds":weakpoint_seconds,"attackable_seconds":attackable_seconds,
		"resource_empty_seconds":resource_empty_seconds,"resource_rejections":driver.rejected.duplicate(true),"casts":casts.duplicate(true),"cast_failures":cast_failures.duplicate(true),
		"phases":phases.duplicate(true),"phase_casts_skipped_by_output_or_termination":skipped,"phase_skip_details":skipped_details,"states":states.duplicate(true),
		"samples":snapshots.duplicate(true),"events":events.duplicate(true),"decisions":driver.decisions.duplicate(true),"projectile_releases":room.releases.duplicate(true),"incoming_packets":trail.all_events.duplicate(true),"outgoing_packets":room.packets.duplicate(true),"mana_ledger":mana_ledger.duplicate(true),"actual_enemy_commands":commands.duplicate(true),"ability_timeline_audit":room.player.abilities.audit.duplicate(true),"direct_audit":room.direct_audit.duplicate(true),"enemy_roster":room.actor_roster.duplicate(true),"rewards_observed":false}
	if not arg("single-enemy","").is_empty():record["outcome"]="player_died" if run_ref.hp<=0 else "single_actor_defeated" if completed else "pressure_observation_timeout"
	record["negative_control"]={"naked":str(config.sample)=="naked","effective_received_hits":trail.all_events.filter(func(p:Dictionary)->bool:return float(p.hp_loss)+float(p.shield_absorbed)>0).size(),"kills":int(room.telemetry.get("kills",0)),"whole_chapter_clear_proven":false}
	record["screenshots"]=screenshots.duplicate(true)
	record["rendering"]=rendering_metadata.duplicate(true)
	record["audio"]={"requested_driver":measurement_protocol.get("requested_audio_driver","engine_default"),"hardware_tested":false,"test_bus_muted":true}
	record["input_diagnostics"]={"normal_offense_expected":requires_attack_evidence(),"controller_opportunities":controller_opportunities,"controller_calls":controller_calls,"controller_never_invoked":controller_calls==0,"accepted_actions":casts.duplicate(true),"actual_shots":room.telemetry.shots,"recorded_decisions":driver.decisions.size(),"zero_offense":room.telemetry.shots==0 and casts.is_empty(),"failed_before_offense":not won and room.telemetry.shots==0 and casts.is_empty()}
	rows.append(record)
	print("B05_BALANCE_FIGHT ",JSON.stringify({"configuration":config,"outcome":outcome,"simulation_seconds":elapsed,"host_wall_seconds":record.host_wall_seconds,"hp_fraction":record.hp_fraction,"phase_skips":skipped}))

func cleanup() -> void:
	if is_instance_valid(room):
		room.recording=false
		await room.combat_audio.wait_for_cleanup()
		room.free()
	if Game.run != null: Game.finish_run("abandoned")
	get_tree().paused=false
	await get_tree().process_frame

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var temporary := output_path+".tmp"
	var file := FileAccess.open(AssetCatalog.resolve(temporary),FileAccess.WRITE)
	check(file!=null,"isolated report written")
	if file!=null:
		file.store_string(JSON.stringify(_json_value({"schema":"s11-controlled-matrix-v2","measurement_protocol":measurement_protocol,"controller":Driver.VERSION,"method":"real production room scene, AI and receivers; controlled input; simulation-elapsed TTK separated from host wall; not human natural gameplay","timing_mode":timing_mode,"display_server":DisplayServer.get_name(),"engine":Engine.get_version_info(),"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"probe":probe,"checks":checks,"failures":failures,"cases":rows}),"\t"))
		file.close()
		check(DirAccess.rename_absolute(temporary,output_path)==OK,"completed report atomically replaces previous checkpoint")

func _json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)]=_json_value(value[key])
		return result
	if value is Array:
		var result := []
		for element in value: result.append(_json_value(element))
		return result
	if value is Vector2: return [value.x,value.y]
	if value is Object: return "<runtime reference omitted>"
	if value is float and not is_finite(value): return str(value)
	return value
