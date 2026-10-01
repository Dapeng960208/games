extends Node
## Headless contract/integration checks. JSON fixtures stay beside the isolated
## test profile and sample existing PNGs read-only. No GPU or image generation.
## Run with -- --test-profile=<path containing test_hero_skill_atlas>.

const Atlas = preload("res://scripts/combat/hero_skill_atlas.gd")
const ArtFamily = preload("res://scripts/combat/hero_art_family.gd")
const RoomScene = preload("res://scenes/room.tscn")
const GUN_NAMES := ["shoulder","brace","lock","fire","absorb","ready"]
const CORE_NAMES := ["gather","tune","command","contract","release_core","ready"]
const PHASES := ["windup","release","recovery"]
var room: MineRoom
var checks := 0
var failures := 0
var fixture_directory := ""

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HERO SKILL ATLAS FAIL: "+label)

func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"open isolated fixture "+path.get_file())
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true

func write_json(path: String, data: Dictionary) -> bool:
	return write_text(path,JSON.stringify(data))

func fixture_manifest(hero: String, bank: String) -> Dictionary:
	var names: Array = GUN_NAMES if hero == "CH02" else CORE_NAMES
	var frames: Array = []
	for index in names.size():
		# Distinct small rectangles in an existing atlas exercise registration.
		# They are parser fixtures, not claimed to depict these six skill poses.
		var x: int = 64+index*96
		var frame: Dictionary = {"name":names[index],"region":[x,64,80,80],
			"foot":[x+40,136],"head":[x+40,70],"grip":[x+50,108],"muzzle":[x+72,104]}
		if hero == "CH03":
			frame.merge({"core":[x+42,100],"left_hand":[x+20,105],"right_hand":[x+50,108]})
		frames.append(frame)
	return {"schema_version":1,"hero_id":hero,"slot":"secondary" if hero == "CH02" else "f",
		"bank":bank,"enabled":true,"texture":"res://assets/generated/heroes/%s_actions_%s_v2.png" % [hero,bank],
		"body_height":66.0,"frames":frames,
		"phase_frames":{"windup":["shoulder","brace","lock"],"release":["fire"],"recovery":["absorb","ready"]} if hero == "CH02" else
			{"windup":["gather","tune"],"release":["command"],"recovery":["contract","release_core","ready"]},
		"phase_weights":{"windup":[1.0,2.0,1.0],"release":[1.0],"recovery":[3.0,1.0]} if hero == "CH02" else
			{"windup":[1.0,3.0],"release":[1.0],"recovery":[1.0,2.0,1.0]}}

func check_valid_clip(hero: String, bank: String, base: Dictionary) -> Dictionary:
	var prefix: String = hero+"_"+bank
	var path: String = fixture_directory.path_join(prefix+"_valid.json")
	if not write_json(path,base):
		return {}
	var clip: Dictionary = Atlas.load_clip(path)
	check(not clip.is_empty(),prefix+" valid six-frame mapping loads")
	if clip.is_empty():
		return {}
	var names: Array = GUN_NAMES if hero == "CH02" else CORE_NAMES
	for phase: String in PHASES:
		var sequence: Array = base.phase_frames[phase]
		var weights: Array = base.phase_weights[phase]
		var total: float = 0.0
		for weight: float in weights:
			total += weight
		var boundary: float = 0.0
		for ordinal in sequence.size():
			var start: float = boundary/total
			boundary += float(weights[ordinal])
			var end: float = boundary/total
			for progress: float in [start,(start+end)*.5,end-.000001]:
				var sample: Dictionary = Atlas.sample_clip(clip,phase,progress)
				var frame_index: int = names.find(sequence[ordinal])
				check(sample.get("frame_name") == sequence[ordinal] and int(sample.get("frame_index",-1)) == frame_index,prefix+" weighted selection "+phase+" at "+str(progress))
				if sample.is_empty():
					continue
				check(sample.get("hero_id") == hero and sample.get("slot") == base.slot and sample.get("bank") == bank,prefix+" sample retains complete identity")
				check(sample.get("skill_sequence") == true and sample.get("phase") == phase and int(sample.get("clip_frame",-1)) == ordinal and int(sample.get("frame_count",0)) == 6 and int(sample.get("phase_frame_count",0)) == sequence.size(),prefix+" sequence identity and local phase ordinal/counts")
				check(is_equal_approx(float(sample.get("phase_progress",-1.0)),progress),prefix+" sample preserves normalized phase progress")
				check(sample.anchors.foot == Vector2(0,8) and is_equal_approx(float(sample.body_height),88.0),prefix+" stable 88-world-px body and foot")
				check(is_equal_approx(sample.bounds.size.y/sample.region.size.y,88.0/66.0),prefix+" anatomy scale ignores region/weapon bounds")
				check(sample.anchors.muzzle.is_equal_approx(Vector2(32,-32)*(88.0/66.0)+Vector2(0,8)),prefix+" absolute source anchors become foot-relative world anchors")
				if hero == "CH03":
					check(sample.anchors.has("core") and sample.anchors.has("left_hand") and sample.anchors.has("right_hand"),prefix+" caster retains all three extra anchors")
					if sample.anchors.has("core"):
						check(sample.anchors.core.is_equal_approx(Vector2(2,-36)*(88.0/66.0)+Vector2(0,8)),prefix+" core normalization matches body/foot transform")
		for endpoint: float in [-2.0,1.0,4.0]:
			var sample: Dictionary = Atlas.sample_clip(clip,phase,endpoint)
			check(sample.get("frame_name") == (sequence[0] if endpoint < 0.0 else sequence.back()),prefix+" phase clamps without wrapping at "+str(endpoint))
			check(is_equal_approx(float(sample.get("phase_progress",-1.0)),clampf(endpoint,0.0,1.0)),prefix+" clamped progress is published")
	check(Atlas.sample_clip(clip,"idle",0.0).is_empty(),prefix+" no idle sequence is fabricated")
	check(Atlas.sample_clip(clip,"windup",NAN).is_empty() and Atlas.sample_clip(clip,"windup",INF).is_empty(),prefix+" nonfinite progress is rejected")
	check_discovery(hero,bank,base,clip)
	return clip

func check_discovery(hero: String, bank: String, base: Dictionary, clip: Dictionary) -> void:
	var replacement: String = ArtFamily.metadata_path(hero,str(base.slot),bank)
	var key: String = replacement if not replacement.is_empty() else "res://assets/generated/heroes/%s_%s_%s_v1.json" % [hero,base.slot,bank]
	var had_previous: bool = Atlas._clips.has(key)
	var previous: Variant = Atlas._clips.get(key)
	# Inject only the process-local cache; never enable or rewrite production JSON.
	Atlas._clips[key] = clip
	var sample: Dictionary = Atlas.frame_info(hero,base.slot,bank,"release",1.0)
	check(sample.get("frame_name") == ("fire" if hero == "CH02" else "command") and sample.get("hero_id") == hero and sample.get("bank") == bank,hero+" discovery resolves the correct hero/slot/bank path")
	Atlas._clips[key] = {}
	check(Atlas.frame_info(hero,base.slot,bank,"release",.5).is_empty(),hero+" unavailable independent skill art falls back")
	if had_previous:
		Atlas._clips[key] = previous
	else:
		Atlas._clips.erase(key)

func malformed_fixtures(hero: String, base: Dictionary) -> void:
	var modes: Array[String] = ["disabled","missing_enabled","string_enabled","integer_enabled","null_enabled",
		"wrong_schema","string_schema","wrong_hero","wrong_slot","crossed_pair","wrong_bank",
		"zero_height","negative_height","string_height","missing_height","missing_texture","wrong_texture_type",
		"missing_frames","frames_wrong_type","five_frames","seven_frames","frame_wrong_type","unknown_name","duplicate_name",
		"region_short","region_wrong_type","region_string_coordinate","region_negative_origin","region_zero_width","region_negative_height","region_outside",
		"missing_foot","short_foot","string_foot","missing_head","missing_grip","missing_muzzle",
		"missing_phases","phases_wrong_type","phase_missing","phase_wrong_type","phase_wrong_name","phase_wrong_order",
		"missing_weights","weights_wrong_type","weights_missing_phase","weight_wrong_type","weights_short","weight_zero","weight_negative","weight_string","weight_null"]
	if hero == "CH03":
		modes.append_array(["missing_core","missing_left_hand","missing_right_hand","bad_core","bad_left_hand","bad_right_hand"])
	for mode: String in modes:
		var rejected: Dictionary = base.duplicate(true)
		match mode:
			"disabled": rejected.enabled = false
			"missing_enabled": rejected.erase("enabled")
			"string_enabled": rejected.enabled = "true"
			"integer_enabled": rejected.enabled = 1
			"null_enabled": rejected.enabled = null
			"wrong_schema": rejected.schema_version = 2
			"string_schema": rejected.schema_version = "1"
			"wrong_hero": rejected.hero_id = "CH01"
			"wrong_slot": rejected.slot = "ultimate"
			"crossed_pair": rejected.slot = "f" if hero == "CH02" else "secondary"
			"wrong_bank": rejected.bank = "side"
			"zero_height": rejected.body_height = 0
			"negative_height": rejected.body_height = -1
			"string_height": rejected.body_height = "66"
			"missing_height": rejected.erase("body_height")
			"missing_texture": rejected.texture = fixture_directory.path_join("missing.png")
			"wrong_texture_type": rejected.texture = "res://scripts/combat/hero_feedback.gd"
			"missing_frames": rejected.erase("frames")
			"frames_wrong_type": rejected.frames = {}
			"five_frames": rejected.frames.pop_back()
			"seven_frames": rejected.frames.append(rejected.frames[0].duplicate(true))
			"frame_wrong_type": rejected.frames[0] = []
			"unknown_name": rejected.frames[0].name = "other_hero_pose"
			"duplicate_name": rejected.frames[1].name = rejected.frames[0].name
			"region_short": rejected.frames[0].region = [64,64,80]
			"region_wrong_type": rejected.frames[0].region = "64,64,80,80"
			"region_string_coordinate": rejected.frames[0].region = ["64",64,80,80]
			"region_negative_origin": rejected.frames[0].region = [-1,64,80,80]
			"region_zero_width": rejected.frames[0].region = [64,64,0,80]
			"region_negative_height": rejected.frames[0].region = [64,64,80,-1]
			"region_outside": rejected.frames[0].region = [0,0,9000,80]
			"missing_foot": rejected.frames[0].erase("foot")
			"short_foot": rejected.frames[0].foot = [104]
			"string_foot": rejected.frames[0].foot = ["104",136]
			"missing_head": rejected.frames[0].erase("head")
			"missing_grip": rejected.frames[0].erase("grip")
			"missing_muzzle": rejected.frames[0].erase("muzzle")
			"missing_phases": rejected.erase("phase_frames")
			"phases_wrong_type": rejected.phase_frames = []
			"phase_missing": rejected.phase_frames.erase("recovery")
			"phase_wrong_type": rejected.phase_frames.release = "fire"
			"phase_wrong_name": rejected.phase_frames.release = ["not_a_frame"]
			"phase_wrong_order": rejected.phase_frames.windup.reverse()
			"missing_weights": rejected.erase("phase_weights")
			"weights_wrong_type": rejected.phase_weights = []
			"weights_missing_phase": rejected.phase_weights.erase("release")
			"weight_wrong_type": rejected.phase_weights.windup = "1,2,1"
			"weights_short": rejected.phase_weights.windup.pop_back()
			"weight_zero": rejected.phase_weights.windup[0] = 0
			"weight_negative": rejected.phase_weights.windup[0] = -1
			"weight_string": rejected.phase_weights.windup[0] = "1"
			"weight_null": rejected.phase_weights.windup[0] = null
			"missing_core": rejected.frames[0].erase("core")
			"missing_left_hand": rejected.frames[0].erase("left_hand")
			"missing_right_hand": rejected.frames[0].erase("right_hand")
			"bad_core": rejected.frames[0].core = ["106",100]
			"bad_left_hand": rejected.frames[0].left_hand = [84]
			"bad_right_hand": rejected.frames[0].right_hand = null
		var path: String = fixture_directory.path_join(hero+"_"+mode+".json")
		if write_json(path,rejected):
			check(Atlas.load_clip(path).is_empty(),hero+" rejects "+mode)
	# Individually finite JSON weights must not overflow their accumulated total.
	# Avoid an out-of-range JSON literal, which emits an unrelated parser warning.
	var overflow: Dictionary = base.duplicate(true)
	overflow.phase_weights.windup[0] = 1e308
	overflow.phase_weights.windup[1] = 1e308
	var path: String = fixture_directory.path_join(hero+"_overflow_weight_total.json")
	if write_json(path,overflow):
		check(Atlas.load_clip(path).is_empty(),hero+" rejects overflow in the phase weight total")

func metadata_checks() -> void:
	fixture_directory = Game.profile_path.get_base_dir().path_join("hero_skill_atlas_fixtures")
	var created: bool = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_directory)) == OK
	check(created,"isolated metadata fixture directory")
	if not created:
		return
	check(Atlas.load_clip(fixture_directory.path_join("missing.json")).is_empty(),"missing clip has fallback")
	var non_object: String = fixture_directory.path_join("non_object.json")
	if write_text(non_object,"[]"):
		check(Atlas.load_clip(non_object).is_empty(),"non-object JSON is rejected")
	for hero: String in ["CH02","CH03"]:
		for bank: String in ["front","back"]:
			var base: Dictionary = fixture_manifest(hero,bank)
			check_valid_clip(hero,bank,base)
			if bank == "front":
				malformed_fixtures(hero,base)
	for identity: Array in [["CH01","q","front"],["CH02","f","front"],["CH02","ultimate","front"],["CH03","secondary","front"],["CH03","q","front"],["CH03","f","side"]]:
		check(Atlas.frame_info(identity[0],identity[1],identity[2],"windup",.5).is_empty(),"unsupported discovery identity "+str(identity))

func fixture(hero: String) -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hero_id = hero
	Game.run.level = 8
	Game.run.stats = StatResolver.resolve(hero,8,{}, {})
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
	room.input_blocked = true
	room.release_gate = false
	room.combat_audio.audible = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = room.ARENA.get_center()
	room.player.aim_direction = Vector2(1,1).normalized()

func step(duration: float) -> void:
	var remaining: float = duration
	while remaining > .000001:
		var delta: float = minf(.005,remaining)
		room.player._physics_process(delta)
		remaining -= delta

func check_pose_progress(feedback: Node, phase: String, recovery_window: float, label: String) -> void:
	var pose: Dictionary = feedback.pose_state()
	check(pose.get("phase") == phase,label+" selects "+phase)
	check(pose.has("authored_phase_progress"),label+" exposes authored phase progress")
	if not pose.has("authored_phase_progress"):
		return
	var expected: float = float(pose.progress)
	if phase == "recovery":
		expected = clampf((float(feedback._shot_age)-.09)/recovery_window,0.0,1.0)
		check(is_equal_approx(float(pose.progress),clampf(float(feedback._shot_age)/.23,0.0,1.0)),label+" retains old VFX recovery progress")
	elif phase == "release":
		check(is_equal_approx(float(pose.progress),float(feedback._shot_age)/.09),label+" retains old release progress")
	check(is_equal_approx(float(pose.authored_phase_progress),expected),label+" authored sampling matches the committed phase interval")

func feedback_checks() -> void:
	for pair: Array in [["CH02","secondary"],["CH03","f"]]:
		var hero: String = pair[0]
		var slot: String = pair[1]
		var label: String = hero+" "+slot
		fixture(hero)
		var feedback: Node = room.player.get_node("HeroFeedback")
		var target: Vector2 = room.player.position+room.player.aim_direction*200.0
		var committed: bool = room.player.cast_skill(slot,target)
		check(committed,label+" commits through public Player.cast_skill")
		if not committed:
			continue
		var spec: Dictionary = room.player.abilities.active.spec
		var windup: float = float(spec.windup)
		var recovery_window: float = float(spec.duration)-windup-.09
		check(recovery_window > 0.0,label+" real specification has an authored recovery window")
		check_pose_progress(feedback,"windup",recovery_window,label+" first windup")
		step(windup*.4)
		check_pose_progress(feedback,"windup",recovery_window,label+" mid windup")
		check(is_equal_approx(float(feedback.pose_state().progress),float(room.player.abilities.active.elapsed)/windup),label+" old windup follows real active elapsed")
		var waited := 0.0
		while feedback.release_events.is_empty() and waited < float(spec.duration)+.1:
			step(.005)
			waited += .005
		check(feedback.release_events.size() == 1,label+" real timeline commits exactly one release")
		if feedback.release_events.is_empty():
			continue
		check_pose_progress(feedback,"release",recovery_window,label+" committed release")
		step(.04)
		check_pose_progress(feedback,"release",recovery_window,label+" mid release")
		while float(feedback._shot_age) < .095:
			step(.005)
		check_pose_progress(feedback,"recovery",recovery_window,label+" early recovery")
		var early: Dictionary = feedback.pose_state()
		if early.has("authored_phase_progress"):
			check(float(early.authored_phase_progress) < .15 and float(early.progress) > .35,label+" new recovery starts near zero while legacy progress stays unchanged")
		# Inject the public presentation hitstop input after a real committed cast.
		# No enemy is required, so this checks the freeze without relying on damage.
		room.player.visual_hitstop = .05
		var frozen: Dictionary = feedback.pose_state()
		var shot_age: float = float(feedback._shot_age)
		var active_elapsed: float = float(room.player.abilities.active.elapsed)
		step(.01)
		check(feedback.pose_state() == frozen and is_equal_approx(float(feedback._shot_age),shot_age),label+" hitstop freezes both visual progress fields")
		check(not room.player.abilities.active.is_empty() and float(room.player.abilities.active.elapsed) > active_elapsed,label+" real ability time continues through visual hitstop")
		room.player.visual_hitstop = 0.0
		for fraction: float in [.5,1.0]:
			var target_age: float = .09+recovery_window*fraction+(.001 if fraction == 1.0 else 0.0)
			if target_age > float(feedback._shot_age):
				step(target_age-float(feedback._shot_age))
			check_pose_progress(feedback,"recovery",recovery_window,label+" recovery fraction "+str(fraction))
			if fraction == .5:
				check(absf(float(feedback.pose_state().get("authored_phase_progress",-1.0))-.5) < .0001,label+" half of the true recovery interval is exactly the authored midpoint")
		var completed: Dictionary = feedback.pose_state()
		check(is_equal_approx(float(completed.get("authored_phase_progress",-1.0)),1.0),label+" authored recovery reaches one without wrapping")
		check(feedback.release_events.size() == 1,label+" visual progression cannot create an extra release")
		room.player.visual_hitstop = .05
		feedback.pose_state()
		room.player.cancel_actions()
		var cancelled: Dictionary = feedback.pose_state()
		check(cancelled.phase == "idle" and not cancelled.has("authored_phase_progress"),label+" cancel clears authored and cached frozen pose")
		step(.08)
		check(not feedback.pose_state().has("authored_phase_progress"),label+" cancelled authored progress cannot reappear")
	for pair: Array in [["CH02","q"],["CH02","f"],["CH02","ultimate"],["CH03","q"],["CH03","secondary"],["CH03","ultimate"]]:
		fixture(pair[0])
		var feedback: Node = room.player.get_node("HeroFeedback")
		var committed: bool = room.player.cast_skill(pair[1],room.player.position+room.player.aim_direction*200.0)
		check(committed,str(pair)+" unrelated real cast commits")
		if not committed:
			continue
		var windup: float = float(room.player.abilities.active.spec.windup)
		check(not feedback.pose_state().has("authored_phase_progress"),str(pair)+" unrelated windup retains old pose contract")
		step(windup+.02)
		check(not feedback.pose_state().has("authored_phase_progress"),str(pair)+" unrelated release retains old pose contract")
		room.player.cancel_actions()

func run_checks() -> void:
	var requested_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="):
			requested_profile = argument.trim_prefix("--test-profile=")
	if not requested_profile.contains("test_hero_skill_atlas") or Game.profile_path != requested_profile:
		push_error("HERO SKILL ATLAS requires an isolated --test-profile path containing test_hero_skill_atlas")
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var started: bool = Game.new_profile() and Game.start_run()
	check(started,"isolated profile and real run start")
	if started:
		metadata_checks()
		feedback_checks()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(),"combat audio cleanup finishes before exit")
		room.free()
	await get_tree().process_frame
	print("HERO SKILL ATLAS ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
