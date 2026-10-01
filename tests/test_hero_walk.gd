extends Node
## Walk selection is driven by world distance. The runtime checks use actual
## mapped movement and production collision; -Graphical also checks draw output.
const RoomScene = preload("res://scenes/room.tscn")
const Visual = preload("res://scripts/combat/hero_visual.gd")
const WalkAtlas = preload("res://scripts/combat/hero_walk_atlas.gd")
const ArtFamily = preload("res://scripts/combat/hero_art_family.gd")
const Metrics = preload("res://scripts/combat/presentation_metrics.gd")
const CYCLES: Dictionary = {"CH01":150.0,"CH02":155.0,"CH03":145.0}
const INPUT_ACTIONS: Array[String] = ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]
var room: MineRoom
var motion_observer: Node2D
var checks: int = 0
var failures: int = 0
var graphical: bool = false
var walk_enabled: Dictionary = {}
var separate_bank_fixtures: Array[Dictionary] = []
var capture_candidate: bool = false

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HERO WALK FAIL: "+label)

func same_frame(actual: Dictionary, expected: Dictionary) -> bool:
	return not actual.is_empty() and not expected.is_empty() and actual.get("texture") == expected.get("texture") and actual.get("region") == expected.get("region") and actual.get("phase") == expected.get("phase") and actual.get("bank") == expected.get("bank")

func walk_metadata_path(hero: String) -> String:
	var replacement: String = ArtFamily.metadata_path(hero,"walk")
	return replacement if not replacement.is_empty() else "res://assets/generated/heroes/%s_walk_v1.json" % hero

func check_walk_assets(hero: String) -> void:
	var cycle: float = float(CYCLES[hero])
	var metadata_path: String = walk_metadata_path(hero)
	check(FileAccess.file_exists(metadata_path),hero+" has explicit walk asset metadata")
	if not FileAccess.file_exists(metadata_path):
		walk_enabled[hero] = false
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	check(parsed is Dictionary,hero+" walk metadata parses")
	if not parsed is Dictionary:
		walk_enabled[hero] = false
		return
	var metadata: Dictionary = parsed
	walk_enabled[hero] = bool(metadata.get("enabled",false))
	if not bool(walk_enabled[hero]):
		for bank: String in ["front","back"]:
			check(Visual.walk_frame_info(hero,bank,cycle*.55).is_empty(),hero+" "+bank+" rejects the explicitly disabled candidate")
			check(same_frame(Visual.motion_frame_info(hero,bank,"idle",cycle*.12*.55,true),Visual.action_frame_info(hero,bank,"idle")),hero+" "+bank+" disabled candidate preserves standing fallback")
		print("HERO WALK DISABLED: "+hero+" candidate excluded by metadata; validating fallback only")
		return
	check_walk_bank_frames(hero,metadata)

func check_walk_bank_frames(hero: String, metadata: Dictionary) -> void:
	var cycle: float = float(CYCLES[hero])
	var front_frames: Array[Dictionary] = []
	for bank: String in ["front","back"]:
		var bank_metadata: Dictionary = metadata.banks[bank] if metadata.has("banks") else metadata
		var sequence: Array = bank_metadata.get("sequence",[0,1,2,3,4,5,6,7]) if metadata.has("banks") else metadata.get(bank+"_frames",[0,1,2,3,4,5,6,7] if bank == "front" else [8,9,10,11,12,13,14,15])
		check(sequence.size() in [4,8],hero+" "+bank+" declares its actual four or eight authored frames")
		var count: int = sequence.size()
		var regions: Array[Rect2] = []
		for index in range(count):
			var distance: float = (float(index)+.5)*cycle/float(count)
			var frame: Dictionary = Visual.walk_frame_info(hero,bank,distance)
			var label: String = "%s %s walk %d" % [hero,bank,index]
			check(frame.has_all(["texture","region","bounds","anchors","bank","phase","frame_index","cycle_distance","body_height"]),label+" supplies the complete frame contract")
			if not frame.has_all(["texture","region","bounds","anchors","bank","phase","frame_index","cycle_distance","body_height"]):
				continue
			check(frame.texture is Texture2D and frame.region is Rect2 and frame.bounds is Rect2 and frame.anchors is Dictionary,label+" provides typed render data")
			if not frame.texture is Texture2D or not frame.region is Rect2 or not frame.bounds is Rect2 or not frame.anchors is Dictionary:
				continue
			var region: Rect2 = frame.region
			var bounds: Rect2 = frame.bounds
			check(region.size.x > 0 and region.size.y > 0 and Rect2(Vector2.ZERO,frame.texture.get_size()).encloses(region),label+" samples an existing atlas rectangle")
			check(not regions.has(region),label+" has a distinct authored region")
			regions.append(region)
			check(frame.frame_index is int and int(frame.frame_index) == int(sequence[index]) and int(frame.get("frame_count",0)) == count,label+" selects the authored index and reports its actual frame count")
			check(str(frame.phase) == "walk" and str(frame.bank) == bank,label+" keeps walk and facing identities")
			check(is_equal_approx(float(frame.cycle_distance),cycle),label+" uses the hero's authored world-distance cadence")
			check(frame.anchors.get("foot") == Vector2(0,8) and is_equal_approx(float(frame.body_height),Metrics.HERO_BODY_HEIGHT),label+" retains body height and ground contact")
			if region.size.x > 0 and region.size.y > 0:
				var scale_x: float = bounds.size.x/region.size.x
				var scale_y: float = bounds.size.y/region.size.y
				check(scale_x > 0 and is_equal_approx(scale_x,scale_y),label+" preserves the authored body proportions")
				var authored_height: float = float(bank_metadata.get("body_height",metadata.get("body_height",region.size.y*float(metadata.get("body_height_fraction",.72)))))
				for definition: Dictionary in bank_metadata.get("frames",[]):
					if int(definition.get("index",-1)) == int(frame.frame_index):
						authored_height = float(definition.get("body_height",authored_height))
						break
				check(authored_height > 0 and is_equal_approx(float(frame.get("source_body_height",0)),authored_height) and is_equal_approx(scale_y*authored_height,Metrics.HERO_BODY_HEIGHT),label+" scales by explicit body anatomy rather than weapon width")
			check(same_frame(Visual.walk_frame_info(hero,bank,distance+cycle),frame),label+" repeats after exactly one world-distance cycle")
			check(same_frame(Visual.walk_frame_info(hero,bank,distance+cycle*7.0),frame),label+" keeps cadence after several cycles")
			check(same_frame(Visual.motion_frame_info(hero,bank,"idle",distance*.12,true),frame),label+" converts player stride back to actual world distance")
			if bank == "front":
				front_frames.append(frame)
			elif front_frames.size() > index:
				check(frame.texture != front_frames[index].texture or region != front_frames[index].region,label+" uses separate back-facing art")
		check(regions.size() == count,hero+" "+bank+" exposes every declared walk frame")
		var first: Dictionary = Visual.walk_frame_info(hero,bank,0.0)
		var last: Dictionary = Visual.walk_frame_info(hero,bank,cycle-.001)
		check(count > 0 and int(first.get("frame_index",-1)) == int(sequence[0]) and int(last.get("frame_index",-1)) == int(sequence[count-1]),hero+" "+bank+" covers both ends of the cycle")
		check(same_frame(first,Visual.walk_frame_info(hero,bank,cycle)),hero+" "+bank+" wraps to frame zero at the cycle boundary")

func write_metadata(path: String, metadata: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(metadata))
	file.close()
	return true

func check_approved_fixtures() -> void:
	# Synthetic color cells exercise the raster loader independently of whether
	# generated candidates have passed visual review. They never replace assets.
	var directory: String = Game.profile_path.get_base_dir().path_join("hero_walk_fixtures")
	check(DirAccess.make_dir_recursive_absolute(directory) == OK,"isolated synthetic walk fixture directory exists")
	var atlas_path: String = directory.path_join("test_walk.png")
	var raster: Image = Image.create(128,128,false,Image.FORMAT_RGBA8)
	raster.fill(Color.TRANSPARENT)
	var definitions: Array[Dictionary] = []
	for index in range(16):
		var x: int = index%4*32
		var y: int = floori(float(index)/4.0)*32
		var width: int = 26+(index%3)*2
		raster.fill_rect(Rect2i(x,y,width,32),Color.from_hsv(float(index)/16.0,.7,.9))
		var definition: Dictionary = {"index":index,"region":[x,y,width,32],"foot":[x+13,y+30]}
		if index%3 == 1:
			definition["body_height"] = 26.0
		definitions.append(definition)
	check(raster.save_png(atlas_path) == OK,"synthetic walk fixture writes without touching generated art")
	for hero: String in ["CH01","CH02","CH03"]:
		var metadata: Dictionary = {"texture":atlas_path,"enabled":true,"columns":4,"rows":4,"cycle_distance":CYCLES[hero],"body_height":24.0,"front_frames":[0,1,2,3,4,5,6,7],"back_frames":[8,9,10,11,12,13,14,15],"frames":definitions}
		var approved_path: String = directory.path_join(hero+"_approved.json")
		check(write_metadata(approved_path,metadata),hero+" approved fixture metadata writes")
		var clip: Dictionary = WalkAtlas.load_clip(approved_path)
		check(not clip.is_empty(),hero+" explicit approval enables a valid fixture atlas")
		if clip.is_empty():
			continue
		var sample: Dictionary = WalkAtlas.sample_clip(clip,"front",float(CYCLES[hero])*.55)
		check(int(sample.get("frame_index",-1)) == 4,hero+" approved fixture samples the expected walk frame")
		if not sample.is_empty():
			var fixture_scale: float = Metrics.HERO_BODY_HEIGHT/26.0
			check((sample.bounds.position+Vector2(13,30)*fixture_scale).distance_to(Vector2(0,8)) < .001,hero+" explicit source foot lands at the real ground anchor")
		check(WalkAtlas.sample_clip(clip,"missing",1.0).is_empty(),hero+" missing bank has no fabricated frame")
		check(WalkAtlas.sample_clip(clip,"front",INF).is_empty(),hero+" non-finite movement has no fabricated frame")
		# Inject only the successfully decoded fixture while checking HeroVisual's
		# public selection API, then restore cache before any actual player redraw.
		var asset_key: String = walk_metadata_path(hero)
		var had_clip: bool = WalkAtlas._clips.has(asset_key)
		var old_clip: Dictionary = WalkAtlas._clips.get(asset_key,{})
		WalkAtlas._clips[asset_key] = clip
		check_walk_bank_frames(hero,metadata)
		check_action_priority(hero)
		if had_clip:
			WalkAtlas._clips[asset_key] = old_clip
		else:
			WalkAtlas._clips.erase(asset_key)
		for gate: String in ["disabled","unreviewed","wrong_type"]:
			var rejected: Dictionary = metadata.duplicate(true)
			if gate == "disabled":
				rejected["enabled"] = false
			elif gate == "unreviewed":
				rejected.erase("enabled")
			else:
				rejected["enabled"] = "true"
			var rejected_path: String = directory.path_join(hero+"_"+gate+".json")
			check(write_metadata(rejected_path,rejected),hero+" "+gate+" fixture metadata writes")
			check(WalkAtlas.load_clip(rejected_path).is_empty(),hero+" "+gate+" atlas cannot become production walk art")
		var invalid: Dictionary = metadata.duplicate(true)
		invalid.frames[0].region = [127,127,32,32]
		var invalid_path: String = directory.path_join(hero+"_invalid_region.json")
		check(write_metadata(invalid_path,invalid),hero+" invalid-region fixture metadata writes")
		check(WalkAtlas.load_clip(invalid_path).is_empty(),hero+" out-of-atlas source rectangle is rejected")
	check_separate_bank_fixture(directory,atlas_path,definitions)

func check_separate_bank_fixture(directory: String, atlas_path: String, definitions: Array[Dictionary]) -> void:
	# Reuse the existing tiny fixture and read an existing generated PNG unchanged.
	# These rectangles test loading/registration, not the artistic content of a gait.
	var back_path := "res://assets/generated/heroes/CH01_actions_back_v2.png"
	var metadata: Dictionary = {
		"schema_version":2,"enabled":true,"cycle_distance":150.0,"body_height":24.0,
		"banks":{
			"front":{"texture":atlas_path,"columns":4,"rows":2,"sequence":[0,1,2,3,4,5,6,7],"frames":definitions.slice(0,8)},
			"back":{"texture":back_path,"columns":4,"rows":2,"sequence":[0,1,2,3,4,5,6,7],"body_height":500.0,"frames":[
				{"index":0,"region":[10,20,90,110],"foot":[43,112],"muzzle":[90,40]},
				{"index":1,"body_height":480.0}
			]}
		}
	}
	var path: String = directory.path_join("separate_banks.json")
	check(write_metadata(path,metadata),"v2 separate-bank fixture metadata writes")
	var clip: Dictionary = WalkAtlas.load_clip(path)
	check(not clip.is_empty(),"v2 accepts two original textures with independent local indices")
	if clip.is_empty():
		return
	separate_bank_fixtures.append(clip)
	var front: Dictionary = WalkAtlas.sample_clip(clip,"front",0.0)
	var back: Dictionary = WalkAtlas.sample_clip(clip,"back",0.0)
	check(front.path == atlas_path and back.path == back_path and front.texture.get_size() != back.texture.get_size(),"each bank loads its own source path and dimensions")
	check(front.frame_index == 0 and back.frame_index == 0 and front.region == Rect2(0,0,26,32) and back.region == Rect2(10,20,90,110),"front and back local index zero cannot overwrite each other")
	check(same_frame(front,WalkAtlas.sample_clip(clip,"front",150.0)),"back sampling cannot replace the cached front frame")
	check(is_equal_approx(float(front.source_body_height),24.0) and is_equal_approx(float(back.source_body_height),500.0),"bank anatomy overrides inherit the root value only when absent")
	var back_scale: float = Metrics.HERO_BODY_HEIGHT/500.0
	check((back.bounds.position+Vector2(33,92)*back_scale).distance_to(Vector2(0,8)) < .001,"separate-bank absolute foot registers its nonzero source region")
	check(back.anchors.muzzle.distance_to(Vector2(47,-72)*back_scale+Vector2(0,8)) < .001,"separate-bank attachment anchors use that bank's foot and scale")
	var corrected: Dictionary = WalkAtlas.sample_clip(clip,"back",150.0*1.5/8.0)
	check(is_equal_approx(float(corrected.source_body_height),480.0),"separate-bank frame anatomy correction overrides its bank")
	var last: Dictionary = WalkAtlas.sample_clip(clip,"back",149.99)
	check(last.frame_index == 7 and last.region.end == back.texture.get_size(),"default grid rectangles use the back texture's dimensions")
	var asset_key: String = walk_metadata_path("CH01")
	var had_clip: bool = WalkAtlas._clips.has(asset_key)
	var old_clip: Dictionary = WalkAtlas._clips.get(asset_key,{})
	WalkAtlas._clips[asset_key] = clip
	check_walk_bank_frames("CH01",metadata)
	check_action_priority("CH01")
	var four_metadata: Dictionary = metadata.duplicate(true)
	four_metadata.banks.front.sequence = [0,2,4,6]
	four_metadata.banks.back.sequence = [0,2,4,6]
	var four_path: String = directory.path_join("separate_banks_four_frames.json")
	check(write_metadata(four_path,four_metadata),"four-frame clip declares four frames without duplication")
	var four_clip: Dictionary = WalkAtlas.load_clip(four_path)
	check(not four_clip.is_empty(),"four-frame clip loads through the same production sampler")
	if not four_clip.is_empty():
		separate_bank_fixtures.append(four_clip)
		WalkAtlas._clips[asset_key] = four_clip
		check_walk_bank_frames("CH01",four_metadata)
		check_action_priority("CH01")
	if had_clip:
		WalkAtlas._clips[asset_key] = old_clip
	else:
		WalkAtlas._clips.erase(asset_key)
	for reason: String in ["missing_bank","wrong_bank_type","missing_texture","outside_back","invalid_local_index","disabled","unreviewed"]:
		var invalid: Dictionary = metadata.duplicate(true)
		match reason:
			"missing_bank": invalid.banks.erase("back")
			"wrong_bank_type": invalid.banks.back = []
			"missing_texture": invalid.banks.back.texture = directory.path_join("missing_back.png")
			"outside_back": invalid.banks.back.frames[0].region = [1250,1250,50,50]
			"invalid_local_index": invalid.banks.back.sequence[7] = 8
			"disabled": invalid.enabled = false
			"unreviewed": invalid.erase("enabled")
		var invalid_path: String = directory.path_join("separate_banks_"+reason+".json")
		check(write_metadata(invalid_path,invalid),"v2 "+reason+" fixture writes")
		check(WalkAtlas.load_clip(invalid_path).is_empty(),"v2 "+reason+" rejects the entire clip without partial activation")

func check_separate_bank_movement() -> void:
	if separate_bank_fixtures.is_empty():
		return
	# Exercise collision-resolved travel with an approved fixture even while all
	# production candidates remain disabled. Restore metadata state afterwards.
	var asset_key: String = walk_metadata_path("CH01")
	var had_clip: bool = WalkAtlas._clips.has(asset_key)
	var old_clip: Dictionary = WalkAtlas._clips.get(asset_key,{})
	var was_enabled: bool = bool(walk_enabled.get("CH01",false))
	walk_enabled["CH01"] = true
	for clip: Dictionary in separate_bank_fixtures:
		WalkAtlas._clips[asset_key] = clip
		await check_real_movement("CH01")
	walk_enabled["CH01"] = was_enabled
	if had_clip:
		WalkAtlas._clips[asset_key] = old_clip
	else:
		WalkAtlas._clips.erase(asset_key)

func check_candidate_movement() -> void:
	var metadata_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--walk-review-metadata="):
			metadata_path = argument.trim_prefix("--walk-review-metadata=")
	if metadata_path.is_empty():
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	check(raw is Dictionary,"requested candidate metadata parses without modifying its source")
	if not raw is Dictionary:
		return
	var metadata: Dictionary = raw.duplicate(true)
	var hero: String = str(metadata.get("hero_id","CH01"))
	check(CYCLES.has(hero),"requested candidate identifies a supported hero")
	if not CYCLES.has(hero):
		return
	metadata["enabled"] = true
	var temporary_path: String = Game.profile_path.get_base_dir().path_join("walk_candidate_review.json")
	check(write_metadata(temporary_path,metadata),"candidate approval is confined to the isolated test profile")
	var clip: Dictionary = WalkAtlas.load_clip(temporary_path)
	check(not clip.is_empty(),"requested candidate can be sampled before production approval")
	if clip.is_empty():
		return
	var asset_key: String = walk_metadata_path(hero)
	var had_clip: bool = WalkAtlas._clips.has(asset_key)
	var old_clip: Dictionary = WalkAtlas._clips.get(asset_key,{})
	var was_enabled: bool = bool(walk_enabled.get(hero,false))
	WalkAtlas._clips[asset_key] = clip
	walk_enabled[hero] = true
	check_walk_bank_frames(hero,metadata)
	check_action_priority(hero)
	capture_candidate = true
	await check_real_movement(hero)
	capture_candidate = false
	walk_enabled[hero] = was_enabled
	if had_clip:
		WalkAtlas._clips[asset_key] = old_clip
	else:
		WalkAtlas._clips.erase(asset_key)

func check_action_priority(hero: String) -> void:
	var stride: float = float(CYCLES[hero])*.12*.55
	for bank: String in ["front","back"]:
		var idle: Dictionary = Visual.action_frame_info(hero,bank,"idle")
		check(not idle.is_empty(),hero+" "+bank+" retains its authored standing pose")
		check(same_frame(Visual.motion_frame_info(hero,bank,"idle",stride,false),idle),hero+" "+bank+" stops on action idle rather than a frozen walk pose")
		for walking: bool in [false,true]:
			check(same_frame(Visual.motion_frame_info(hero,bank,"idle",stride,walking,true),idle),hero+" "+bank+" dash suppresses ordinary walking")
			for phase: String in ["windup","release","recovery"]:
				var action: Dictionary = Visual.action_frame_info(hero,bank,phase)
				check(not action.is_empty(),hero+" "+bank+" retains actual "+phase+" art")
				check(same_frame(Visual.motion_frame_info(hero,bank,phase,stride,walking),action),hero+" "+bank+" "+phase+" takes priority over walk")
				check(same_frame(Visual.motion_frame_info(hero,bank,phase,stride,walking,true),action),hero+" "+bank+" "+phase+" retains action priority during dash")

func fresh(hero: String) -> bool:
	for action: String in INPUT_ACTIONS:
		Input.action_release(action)
	if is_instance_valid(room):
		room.free()
	if is_instance_valid(motion_observer):
		motion_observer.free()
	motion_observer = Node2D.new()
	add_child(motion_observer)
	if Game.run != null:
		Game.finish_run("abandoned")
	var started: bool = Game.select_hero(hero) and Game.start_run()
	check(started,hero+" starts a real isolated run")
	if not started:
		return false
	room = RoomScene.instantiate()
	room.run_seed = 41827
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = false
	room.release_gate = false
	room.combat_audio.audible = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	return true

func open_stage() -> Vector2:
	for y in range(500,1401,100):
		for x in range(700,2101,100):
			var candidate := Vector2(x,y)
			if room.valid_ground(candidate,Balance.PLAYER_RADIUS) and room.blocked_fraction(candidate,candidate+Vector2(320,0),Balance.PLAYER_RADIUS) >= 1.0:
				return candidate
	return Vector2.ZERO

func selected_player_frame() -> Dictionary:
	var player: SalvagerPlayer = room.player
	var feedback: Node = player.get_node("HeroFeedback")
	var pose: Dictionary = feedback.pose_state()
	# A separate observer exercises production movement detection headlessly
	# without consuming the renderer's own per-player observation history.
	var walking: bool = Visual._walk_is_moving(motion_observer,player.stride,player.velocity)
	return Visual.motion_frame_info(player.hero_id(),"front",str(pose.phase),player.stride,walking,player.dash_remaining > 0.0 or player.visual_state == "dash")

func render_pose(expected: String, label: String) -> void:
	if not graphical:
		return
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.player.queue_redraw()
	await RenderingServer.frame_post_draw
	check(str(room.player.get_meta("hero_visual_pose","")) == expected,label+" renderer consumes "+expected)
	check(room.player.get_meta("hero_foot_local") == Vector2(0,8),label+" renderer keeps a stable foot anchor")
	var feedback: Node = room.player.get_node("HeroFeedback")
	var pose: Dictionary = feedback.pose_state()
	var aim: Vector2 = pose.get("direction",room.player.aim_direction)
	var bank: String = "back" if aim.y < -.20 else "front"
	check(str(room.player.get_meta("hero_visual_bank","")) == bank,label+" renderer selects the actual aiming bank")
	var expected_frame: int = -1
	if expected == "walk":
		expected_frame = int(Visual.walk_frame_info(room.player.hero_id(),bank,room.player.stride/.12).get("frame_index",-1))
	check(int(room.player.get_meta("hero_visual_frame",-2)) == expected_frame,label+" renderer consumes the selected atlas frame")
	if capture_candidate:
		var capture_path: String = "res://artifacts/walk_candidate_"+label.validate_filename().replace(" ","_")+".png"
		check(get_viewport().get_texture().get_image().save_png(capture_path) == OK,label+" saves an unedited gameplay capture")

func check_real_movement(hero: String) -> void:
	if not fresh(hero):
		return
	var stage: Vector2 = open_stage()
	check(stage != Vector2.ZERO,hero+" generated room has a clear movement lane")
	if stage == Vector2.ZERO:
		return
	var player: SalvagerPlayer = room.player
	player.position = stage
	await render_pose("idle",hero+" initial standing")
	var cycle: float = float(CYCLES[hero])
	var enabled: bool = bool(walk_enabled.get(hero,false))
	var frame_count: int = int(Visual.walk_frame_info(hero,"front",0.0).get("frame_count",8)) if enabled else 8
	var observed: Array[int] = []
	var travelled: float = 0.0
	var initial_stride: float = player.stride
	Input.action_press("move_right")
	check(Input.is_action_pressed("move_right"),hero+" test drives the actual mapped movement action")
	for index in range(frame_count):
		await get_tree().physics_frame
		var before: Vector2 = player.position
		var distance: float = cycle/float(frame_count)*(.5 if index == 0 else 1.0)
		player._physics_process(distance/player.stat("move_speed",220.0))
		var moved: float = player.position.distance_to(before)
		travelled += moved
		check(moved > distance*.95 and room.valid_ground(player.position,Balance.PLAYER_RADIUS),hero+" actual walking moves on valid floor")
		check(absf(player.stride-initial_stride-travelled*.12) < .001,hero+" player stride follows measured world displacement")
		var frame: Dictionary = selected_player_frame()
		check(bool(motion_observer.get_meta("_hero_visual_motion",{}).get("walking",false)),hero+" production observer detects actual movement even when walk art is disabled")
		selected_player_frame()
		check(bool(motion_observer.get_meta("_hero_visual_motion",{}).get("walking",false)),hero+" repeated observation within one physics frame retains walking")
		if enabled:
			check(str(frame.get("phase","")) == "walk" and int(frame.get("clip_frame",-1)) == index,hero+" actual movement advances authored walk frame "+str(index))
		else:
			check(same_frame(frame,Visual.action_frame_info(hero,"front","idle")),hero+" actual movement keeps fallback for the disabled candidate")
		observed.append(int(frame.get("clip_frame",-1)))
		await render_pose("walk" if enabled else "idle",hero+" movement "+str(index))
	Input.action_release("move_right")
	if enabled:
		check(observed == range(frame_count),hero+" an actual traversal displays every declared frame once in order")
	var stopped_position: Vector2 = player.position
	var stopped_stride: float = player.stride
	await get_tree().physics_frame
	player._physics_process(.2)
	check(player.position == stopped_position and is_equal_approx(player.stride,stopped_stride),hero+" releasing movement stops displacement and animation distance")
	check(same_frame(selected_player_frame(),Visual.action_frame_info(hero,"front","idle")),hero+" actual input release returns to standing art")
	check(not bool(motion_observer.get_meta("_hero_visual_motion",{}).get("walking",true)),hero+" production observer clears walking after movement is released")
	await render_pose("idle",hero+" released movement")
	if capture_candidate:
		Input.action_press("move_right")
		var before_attack: Vector2 = player.position
		check(player.fire(player.aim_direction),hero+" candidate test starts an actual basic while moving")
		player._physics_process(.05)
		check(player.position.distance_to(before_attack) > 0.0,hero+" actual attack and walking share the production physics step")
		var feedback: Node = player.get_node("HeroFeedback")
		var initial_phase: String = "windup" if hero == "CH01" else "release"
		check(str(feedback.pose_state().phase) == initial_phase,hero+" actual basic timing overrides walking with "+initial_phase)
		await render_pose(initial_phase,hero+" moving attack "+initial_phase)
		if hero == "CH01":
			player._physics_process(.08)
			check(str(feedback.pose_state().phase) == "release",hero+" actual melee release overrides walking")
			await render_pose("release",hero+" moving attack release")
		player._physics_process(.12)
		check(str(feedback.pose_state().phase) == "recovery",hero+" actual basic recovery overrides walking")
		await render_pose("recovery",hero+" moving attack recovery")
		Input.action_release("move_right")
		player._physics_process(.4)
	await check_wall_contact(hero)
	player.position = stage
	player._physics_process(.01)
	await render_pose("idle",hero+" pre-dash standing")
	check(player.start_dash(Vector2.RIGHT),hero+" actual dash starts")
	player._physics_process(.04)
	check(player.dash_remaining > 0.0 and str(selected_player_frame().get("phase","")) != "walk",hero+" real dash never selects a walking frame")
	await render_pose("idle",hero+" active dash")

func check_wall_contact(hero: String) -> void:
	var player: SalvagerPlayer = room.player
	var wall_found: bool = false
	for wall: Rect2 in room.obstructions:
		var start := Vector2(wall.position.x-Balance.PLAYER_RADIUS-4.0,wall.get_center().y)
		if not room.valid_ground(start,Balance.PLAYER_RADIUS):
			continue
		wall_found = true
		player.position = start
		player.knockback = Vector2.ZERO
		player._physics_process(.01)
		await render_pose("idle",hero+" wall approach")
		var before_stride: float = player.stride
		Input.action_press("move_right")
		player._physics_process(.1)
		var contact: Vector2 = player.position
		check(contact.x > start.x+1.0 and contact.x <= wall.position.x-Balance.PLAYER_RADIUS+.01 and room.valid_ground(contact,Balance.PLAYER_RADIUS),hero+" actual movement reaches a solid wall")
		check(absf(player.stride-before_stride-contact.distance_to(start)*.12) < .001,hero+" collision advances stride only by the reachable distance")
		var contact_stride: float = player.stride
		var contact_frame: Dictionary = Visual.walk_frame_info(hero,"front",contact_stride/.12)
		check(str(selected_player_frame().get("phase","")) == ("walk" if bool(walk_enabled.get(hero,false)) else "idle"),hero+" reaching the wall observes its actual final movement")
		await render_pose("walk" if bool(walk_enabled.get(hero,false)) else "idle",hero+" reaches wall")
		await get_tree().physics_frame
		for index in range(12):
			player._physics_process(1.0/60.0)
			check(player.position.distance_to(contact) < .001 and is_equal_approx(player.stride,contact_stride),hero+" held wall input cannot create phantom walking distance")
			if bool(walk_enabled.get(hero,false)):
				check(same_frame(Visual.walk_frame_info(hero,"front",player.stride/.12),contact_frame),hero+" held wall input cannot cycle walk art without displacement")
			else:
				check(contact_frame.is_empty() and Visual.walk_frame_info(hero,"front",player.stride/.12).is_empty(),hero+" wall input cannot activate a disabled candidate")
		check(same_frame(selected_player_frame(),Visual.action_frame_info(hero,"front","idle")),hero+" production movement observer returns idle while input remains held against a wall")
		check(not bool(motion_observer.get_meta("_hero_visual_motion",{}).get("walking",true)),hero+" production observer clears walking during sustained wall contact")
		await render_pose("idle",hero+" sustained wall contact")
		Input.action_release("move_right")
		player._physics_process(.02)
		check(same_frame(selected_player_frame(),Visual.action_frame_info(hero,"front","idle")),hero+" releasing against a wall uses standing art")
		return
	check(wall_found,hero+" generated room provides a real wall probe")

func run_checks() -> void:
	if not Game.profile_path.contains("test_hero_walk"):
		push_error("Refusing non-test profile; require --test-profile containing test_hero_walk")
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	for action: String in INPUT_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile(),"isolated walk profile")
	check_approved_fixtures()
	for hero: String in ["CH01","CH02","CH03"]:
		check_walk_assets(hero)
		check_action_priority(hero)
		await check_real_movement(hero)
	await check_separate_bank_movement()
	await check_candidate_movement()
	check(Visual.walk_frame_info("MISSING_HERO").is_empty(),"missing hero returns no fabricated walk frame")
	check(Visual.motion_frame_info("MISSING_HERO","front","idle",1.0,true).is_empty(),"missing hero permits the production fallback renderer")
	for action: String in INPUT_ACTIONS:
		Input.action_release(action)
	if is_instance_valid(room):
		room.free()
	if is_instance_valid(motion_observer):
		motion_observer.free()
	print("HERO WALK ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
