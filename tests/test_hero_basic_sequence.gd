extends Node
## Read-only production-asset checks plus isolated malformed-metadata fixtures.
## Deterministic boundary checks call real Player physics with small steps.
## A separate graphical recorder uses normal engine physics, without slowdown.

const Visual = preload("res://scripts/combat/hero_visual.gd")
const Atlas = preload("res://scripts/combat/hero_basic_atlas.gd")
const ArtFamily = preload("res://scripts/combat/hero_art_family.gd")
const RoomScene = preload("res://scenes/room.tscn")
var room: MineRoom
var checks := 0
var failures := 0
var fixtures_only := false
var graphical := false

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BASIC SEQUENCE FAIL: " + label)

func basic_metadata_path(bank: String) -> String:
	var replacement: String = ArtFamily.metadata_path("CH01","basic",bank)
	return replacement if not replacement.is_empty() else "res://assets/generated/heroes/CH01_basic_%s_v1.json" % bank

func basic_texture_path(bank: String) -> String:
	var metadata_path: String = basic_metadata_path(bank)
	if not FileAccess.file_exists(metadata_path):
		return ""
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	return str(metadata.get("texture","")) if metadata is Dictionary else ""

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func metadata_fixtures() -> void:
	var directory: String = Game.profile_path.get_base_dir().path_join("basic_sequence_fixtures")
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated metadata fixture directory")
	var path: String = directory.path_join("six_cells.png")
	var raster := Image.create(192, 32, false, Image.FORMAT_RGBA8)
	var definitions: Array[Dictionary] = []
	for index in 6:
		raster.fill_rect(Rect2i(index * 32, 0, 32, 32), Color.from_hsv(index / 6.0, .7, .8))
		definitions.append({"name":Atlas.FRAME_NAMES[index], "region":[index * 32, 0, 32, 32],
			"foot":[index * 32 + 16, 30], "head":[index * 32 + 16, 4],
			"grip":[index * 32 + 20, 18], "muzzle":[index * 32 + 29, 17]})
	check(raster.save_png(path) == OK, "test raster is separate from generated art")
	var base: Dictionary = {"schema_version":1, "hero_id":"CH01", "bank":"front", "enabled":true,
		"texture":path, "body_height":26.0, "frames":definitions,
		"phase_frames":{"windup":["lift","loaded","downswing"], "release":["contact"], "recovery":["recoil","ready"]},
		"phase_weights":{"windup":[.25,.45,.30], "release":[1.0], "recovery":[.55,.45]}}
	var valid_path: String = directory.path_join("valid.json")
	write_json(valid_path, base)
	var clip: Dictionary = Atlas.load_clip(valid_path)
	check(not clip.is_empty(), "explicit valid six-frame clip loads")
	if clip.is_empty(): return
	for sample: Array in [["windup",-.1,"lift",0],["windup",0.0,"lift",0],["windup",.2499,"lift",0],
		["windup",.25,"loaded",1],["windup",.6999,"loaded",1],["windup",.70,"downswing",2],
		["windup",1.0,"downswing",2],["windup",6.0,"downswing",2],["release",0.0,"contact",3],
		["release",1.0,"contact",3],["recovery",0.0,"recoil",4],["recovery",.5499,"recoil",4],
		["recovery",.55,"ready",5],["recovery",1.0,"ready",5],["recovery",6.0,"ready",5]]:
		var frame: Dictionary = Atlas.sample_clip(clip, sample[0], sample[1])
		check(frame.get("frame_name") == sample[2] and int(frame.get("frame_index",-1)) == int(sample[3]), "weighted clamped boundary " + str(sample))
		check(frame.get("phase") == sample[0] and frame.get("basic_sequence") == true, "sample preserves phase with basic identity")
		check(frame.anchors.foot == Vector2(0,8) and frame.body_height == 88.0, "every frame has fixed world anatomy and ground foot")
		check(is_equal_approx(frame.bounds.size.y / frame.region.size.y, 88.0/26.0), "weapon extent never chooses frame scale")
	check(Atlas.sample_clip(clip,"idle",0.0).is_empty() and Atlas.sample_clip(clip,"windup",NAN).is_empty() and Atlas.sample_clip(clip,"windup",INF).is_empty(), "unknown phase and nonfinite progress cannot fabricate frames")
	check(Atlas.load_clip(directory.path_join("missing.json")).is_empty(), "missing metadata has fallback")
	for mode: String in ["disabled","unreviewed","string_enabled","zero_height","missing_frame","duplicate_frame","bad_region","bad_foot","bad_head","unknown_phase_frame","bad_weights","zero_weight","missing_texture","wrong_texture_type","wrong_bank","wrong_hero","wrong_schema"]:
		var rejected: Dictionary = base.duplicate(true)
		match mode:
			"disabled": rejected.enabled = false
			"unreviewed": rejected.erase("enabled")
			"string_enabled": rejected.enabled = "true"
			"zero_height": rejected.body_height = 0
			"missing_frame": rejected.frames.pop_back()
			"duplicate_frame": rejected.frames[1].name = "lift"
			"bad_region": rejected.frames[0].region = [0,0,9000,32]
			"bad_foot": rejected.frames[0].foot = ["16",30]
			"bad_head": rejected.frames[0].erase("head")
			"unknown_phase_frame": rejected.phase_frames.release = ["idle"]
			"bad_weights": rejected.phase_weights.windup = [.25,.75]
			"zero_weight": rejected.phase_weights.windup = [.25,0,.75]
			"missing_texture": rejected.texture = directory.path_join("absent.png")
			"wrong_texture_type": rejected.texture = "res://scripts/combat/hero_feedback.gd"
			"wrong_bank": rejected.bank = "side"
			"wrong_hero": rejected.hero_id = "CH02"
			"wrong_schema": rejected.schema_version = 7
		var rejected_path: String = directory.path_join(mode + ".json")
		write_json(rejected_path,rejected)
		check(Atlas.load_clip(rejected_path).is_empty(), "malformed/unapproved clip falls back: " + mode)
	var production_key: String = basic_metadata_path("front")
	var had_clip: bool = Atlas._clips.has(production_key)
	var previous: Dictionary = Atlas._clips.get(production_key,{})
	Atlas._clips[production_key] = clip
	var pose: Dictionary = {"slot":"basic","phase":"windup","progress":.8}
	check(Visual.presentation_frame_info("CH01","front",pose,18.0,true).get("frame_name") == "downswing", "basic authored pose takes priority over walking")
	pose.slot = "secondary"
	check(not Visual.presentation_frame_info("CH01","front",pose,18.0,true).get("basic_sequence",false), "skill cast keeps legacy action art")
	pose.slot = "basic"
	check(not Visual.presentation_frame_info("CH01","front",pose,18.0,true,true).get("basic_sequence",false), "dash cannot select basic clip")
	pose.phase = "idle"
	check(not Visual.presentation_frame_info("CH01","front",pose,18.0,true).get("basic_sequence",false), "idle keeps normal walk/standing selection")
	check(Visual.basic_frame_info("CH02","front","windup",.5).is_empty(), "unrelated hero cannot reuse hammer clip")
	Atlas._clips[production_key] = {}
	pose.phase = "windup"
	var fallback: Dictionary = Visual.presentation_frame_info("CH01","front",pose,18.0,true)
	check(not fallback.is_empty() and fallback.phase == "windup" and not fallback.get("basic_sequence",false), "unavailable clip preserves original four-phase action fallback")
	if had_clip: Atlas._clips[production_key] = previous
	else: Atlas._clips.erase(production_key)

func check_production_assets() -> void:
	for bank: String in ["front","back"]:
		var texture_path: String = basic_texture_path(bank)
		check(not texture_path.is_empty() and FileAccess.file_exists(texture_path),bank+" active basic metadata identifies an existing source texture")
		var definitions: Array = []
		for sample: Array in [["windup",.1],["windup",.4],["windup",.9],["release",.5],["recovery",.1],["recovery",.8]]:
			var frame: Dictionary = Visual.basic_frame_info("CH01",bank,sample[0],sample[1])
			check(not frame.is_empty(), "approved production " + bank + " " + str(sample) + " exists")
			if frame.is_empty(): continue
			check(frame.path == texture_path and frame.bank == bank, "front/back active assets remain independently registered")
			check(not definitions.has(frame.region), "each production keypose samples a distinct source region")
			definitions.append(frame.region)
			check(frame.anchors.foot == Vector2(0,8) and frame.body_height == 88.0, "production basic preserves world anchor and scale")
			check(is_equal_approx(frame.bounds.size.y/frame.region.size.y * frame.source_body_height,88.0), "production frame uses one fixed source body height")
		check(definitions.size() == 6, bank + " registers all six authored poses")

func fixture(direction: Vector2) -> void:
	if is_instance_valid(room): room.free()
	Game.run.hero_id = "CH01"
	Game.run.level = 8
	Game.run.stats = StatResolver.resolve("CH01",8,{}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true # keeps real physics from consulting the native OS cursor
	room.release_gate = false
	room.combat_audio.audible = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = room.ARENA.get_center()
	room.player.aim_direction = direction
	room.camera.follow_target()
	room.camera.force_update_scroll()

func step(duration: float) -> void:
	var remaining: float = duration
	while remaining > .000001:
		var delta: float = minf(.005,remaining)
		room.player._physics_process(delta)
		remaining -= delta

func current_frame() -> Dictionary:
	var pose: Dictionary = room.player.get_node("HeroFeedback").pose_state()
	var bank: String = "back" if room.player.aim_direction.y < -.2 else "front"
	return Visual.presentation_frame_info("CH01",bank,pose,room.player.stride,false,room.player.dash_remaining > 0.0)

func check_deterministic_timing() -> void:
	for bank: String in ["front","back"]:
		var direction := Vector2(1,1 if bank == "front" else -1).normalized()
		fixture(direction)
		var feedback: Node = room.player.get_node("HeroFeedback")
		var victim: MineEnemy = room.spawn_enemy(room.player.position + direction * 60.0,"M01")
		victim.health.reset(10000.0)
		victim.training_ai_disabled = true
		var interval: float = room.player.stat("attack_interval",.5)
		check(room.player.fire(direction), "real fire starts " + bank + " basic")
		check(current_frame().get("frame_name") == "lift", "committed first windup picks lift")
		step(.04)
		check(current_frame().get("frame_name") == "loaded" and victim.health.current == 10000.0, "loaded anticipation cannot deal early damage")
		step(.055)
		check(current_frame().get("frame_name") == "downswing" and victim.health.current == 10000.0, "downswing still precedes actual 120ms strike")
		step(.03)
		check(feedback.basic_events == 1 and victim.health.current < 10000.0, "real melee hit releases exactly one event")
		check(current_frame().get("frame_name") == "contact", "committed strike selects contact frame")
		check(is_equal_approx(room.player.shot_cooldown,interval-.125), "art selection never changes basic cooldown")
		check(room.player.visual_hitstop > 0.0, "actual damage supplies visual freeze")
		var frozen: Dictionary = feedback.pose_state()
		step(.005)
		check(feedback.pose_state() == frozen and current_frame().get("frame_name") == "contact", "real hitstop freezes contact frame without artificial animation clock")
		if graphical:
			room.player.queue_redraw()
			await RenderingServer.frame_post_draw
			var art: Dictionary = current_frame()
			check(str(room.player.get_meta("hero_visual_source","")) == str(art.path), "renderer consumes new basic source")
			check(room.player.get_meta("hero_grip_local",Vector2.INF).distance_to(art.anchors.grip) < .001, "authored contact receives no old whole-image release translation")
			check(room.player.get_meta("hero_foot_local") == Vector2(0,8), "renderer preserves fixed authored ground contact")
		step(.145)
		check(current_frame().get("frame_name") == "recoil", "real feedback progresses into recoil")
		step(.12)
		check(current_frame().get("frame_name") == "ready", "real feedback reaches ready without wrapping")
		step(.2)
		check(not current_frame().get("basic_sequence",false), "completed basic naturally leaves sequence")
		# A skill may cancel basic recovery immediately after the real hit while
		# hitstop is still active. The basic frozen pose must not mask the cast.
		fixture(direction)
		feedback = room.player.get_node("HeroFeedback")
		victim = room.spawn_enemy(room.player.position+direction*60.0,"M01")
		victim.health.reset(10000.0)
		victim.training_ai_disabled = true
		check(room.player.fire(direction), "real basic starts cancellation fixture")
		step(.125)
		current_frame() # ensure the confirmed basic contact has a cached frozen pose
		check(room.player.visual_hitstop > 0.0 and room.player.cast_skill("secondary",victim.position), "real skill cancels recovery during confirmed hitstop")
		check(feedback.pose_state().slot == "secondary" and not current_frame().get("basic_sequence",false), "cast clears frozen basic art immediately")
		room.player.cancel_actions()
		check(feedback.pose_state().phase == "idle", "cancelled cast returns to idle with no basic residue")
		fixture(direction)
		feedback = room.player.get_node("HeroFeedback")
		check(room.player.fire(direction), "basic starts defensive cancellation fixture")
		step(.04)
		check(room.player.start_dash(direction), "dash cancels committed windup")
		check(not current_frame().get("basic_sequence",false) and feedback.pose_state().phase == "idle", "dash does not retain cancelled basic animation")
		step(.25)
		check(feedback.basic_events == 0 and not current_frame().get("basic_sequence",false), "dash completion cannot resurrect cancelled strike or pose")

func record_native_sequences() -> void:
	# This is intentionally independent of the deterministic boundary fixture.
	# Public fire commits one attack, then the engine advances every actor and
	# camera normally. No manual tick, pose assignment, time_scale or slow motion.
	get_viewport().size = Vector2i(1280,720)
	var directory := "res://artifacts/hero_basic_sequence"
	DirAccess.make_dir_recursive_absolute(directory)
	var records: Array[Dictionary] = []
	for bank: String in ["front","back"]:
		var texture_path: String = basic_texture_path(bank)
		for contact: bool in [false,true]:
			var direction := Vector2(1,1 if bank == "front" else -1).normalized()
			fixture(direction)
			room.process_mode = Node.PROCESS_MODE_PAUSABLE
			var victim: MineEnemy
			if contact:
				victim = room.spawn_enemy(room.player.position+direction*60.0,"M01")
				victim.health.reset(10000.0)
				victim.training_ai_disabled = true
			var mode: String = "hit" if contact else "whiff"
			var captures: Dictionary = {}
			var samples: Array[Dictionary] = []
			# Settle ordinary idle/background rendering before the measured attack.
			await get_tree().physics_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(room.player.is_physics_processing() and room.player.can_process(), bank+" "+mode+" recorder uses normal automatic player physics")
			check(room.camera.zoom.is_equal_approx(Vector2(.85,.85)), "native recorder preserves production camera zoom")
			var first_tick: int = Engine.get_physics_frames()
			var start_msec: int = Time.get_ticks_msec()
			check(room.player.fire(direction), bank+" "+mode+" native attack commits through public fire")
			while Engine.get_physics_frames()-first_tick < ceili(.8*Engine.physics_ticks_per_second) and Time.get_ticks_msec()-start_msec < 4000:
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var tick: int = Engine.get_physics_frames()-first_tick
				var index: int = int(room.player.get_meta("hero_visual_frame",-1))
				var source: String = str(room.player.get_meta("hero_visual_source",""))
				var sample: Dictionary = {"tick":tick,"frame_index":index,"phase":str(room.player.get_meta("hero_visual_pose","")),
					"source":source,"target_hp":victim.health.current if is_instance_valid(victim) else -1.0,
					"hitstop":room.player.visual_hitstop,"shot_cooldown":room.player.shot_cooldown}
				samples.append(sample)
				if source == texture_path and index >= 0 and index < 6 and not captures.has(index):
					# Keep image readbacks in memory during the swing. PNG compression
					# happens afterwards, so disk writes cannot skip its short keyposes.
					captures[index] = {"image":get_viewport().get_texture().get_image(), "sample":sample.duplicate(true)}
			room.process_mode = Node.PROCESS_MODE_DISABLED
			var feedback: Node = room.player.get_node("HeroFeedback")
			check(feedback.basic_events == 1, bank+" "+mode+" automatic loop releases precisely one basic")
			check(victim.health.current < 10000.0 if contact else feedback.impact_events == 0, bank+" "+mode+" has the declared actual damage outcome")
			var missing: Array[int] = []
			var files: Array[String] = []
			for index in 6:
				if not captures.has(index):
					missing.append(index)
					continue
				var filename: String = "%s_%s_%02d_%s.png" % [bank,mode,index,Atlas.FRAME_NAMES[index]]
				var frame: Image = captures[index].image
				check(frame.get_size() == Vector2i(1280,720) and frame.save_png(directory.path_join(filename)) == OK, "save raw normal-speed engine capture "+filename)
				files.append(filename)
			var record: Dictionary = {"bank":bank,"mode":mode,"captured_frame_count":captures.size(),"missing_frame_indices":missing,"files":files,
				"samples":samples,"camera_zoom":[room.camera.zoom.x,room.camera.zoom.y],"world_body_height":88.0,"basic_events":feedback.basic_events,"impact_events":feedback.impact_events}
			records.append(record)
			print("BASIC_NATIVE_CAPTURE bank=",bank," mode=",mode," captured=",captures.size()," missing=",missing)
			captures.clear()
	var file := FileAccess.open(directory.path_join("native_capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"One public Player.fire per front/back whiff/hit; normal automatic engine physics and production renderer/camera .85; stationary training target for hit, input-blocked movement to avoid OS cursor. No manual ticks, pose writes or slow motion. Missing short frames are explicitly reported.","records":records},"\t"))
	file.close()

func run_checks() -> void:
	if not Game.profile_path.contains("test_hero_basic_sequence"):
		get_tree().quit(2)
		return
	fixtures_only = "--fixtures-only" in OS.get_cmdline_user_args()
	graphical = DisplayServer.get_name() != "headless"
	AudioServer.set_bus_mute(0,true)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated basic animation profile starts")
	metadata_fixtures()
	if not fixtures_only:
		check_production_assets()
		await check_deterministic_timing()
		if graphical: await record_native_sequences()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	await get_tree().process_frame
	print("HERO BASIC SEQUENCE ACCEPTANCE: %d checks, %d failures, fixtures_only=%s" % [checks,failures,fixtures_only])
	get_tree().quit(0 if failures == 0 else 1)
