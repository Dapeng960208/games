extends Node
## Replacement acceptance uses real source art and production movement/casts.
## Graphical runs save native frames; headless runs validate registration only.

const Family = preload("res://scripts/presentation/characters/hero_art_family.gd")
const Visual = preload("res://scripts/presentation/characters/hero_visual.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const OUTPUT := "res://artifacts/hero_storybook_family"
const DIRECTIONS: Dictionary = {"front_right":Vector2(1,.65), "front_left":Vector2(-1,.65), "back_right":Vector2(1,-.65), "back_left":Vector2(-1,-.65)}
signal capture_drawn
var checks := 0
var failures := 0
var stage: SubViewport
var app: Node
var room: RoomController
var records: Array[Dictionary] = []
var pending_images: Dictionary = {}
var graphical := false

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HERO STORYBOOK FAMILY FAIL: " + label)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func registered(frame: Dictionary, label: String) -> void:
	check(not frame.is_empty(), label + " has an authored frame")
	if frame.is_empty():
		return
	check(str(frame.path).contains("CH01_storybook_") or str(frame.path).contains("CH01_directional_"), label + " uses an approved current hero family")
	check(frame.anchors.foot == Vector2(0,8) and is_equal_approx(float(frame.body_height),112.0), label + " retains fixed anatomy and sole origin")
	check(Rect2(Vector2.ZERO,frame.texture.get_size()).encloses(frame.region), label + " samples the complete original atlas")
	check(is_equal_approx(frame.bounds.size.x/frame.region.size.x,frame.bounds.size.y/frame.region.size.y), label + " preserves body proportions")

func check_sources() -> bool:
	var family: Dictionary = Family.load_family("asset://heroes/CH01_storybook_family_v1.json")
	check(not family.is_empty(), "complete enabled CH01 family exists")
	if family.is_empty():
		return false
	for bank: String in ["front","back"]:
		for phase: String in ["idle","windup","release","recovery"]:
			registered(Visual.action_frame_info("CH01",bank,phase), bank + " generic " + phase)
		for index in 4:
			registered(Visual.walk_frame_info("CH01",bank,(float(index)+.5)*150.0/4.0), bank + " gait " + str(index))
		for phase: String in ["windup","release","recovery"]:
			for progress: float in [.05,.40,.75,.99]:
				registered(Visual.basic_frame_info("CH01",bank,phase,progress), bank + " basic " + phase + str(progress))
				for slot: String in ["q","secondary","f","ultimate"]:
					var pose := {"slot":slot,"phase":phase,"progress":progress,"authored_phase_progress":progress}
					registered(Visual.presentation_frame_info("CH01",bank,pose,0.0,false), bank + " " + slot + " " + phase + str(progress))
	registered(Visual.presentation_frame_info("CH01","front",{"slot":"basic","phase":"idle","progress":0.0},0.0,false,true), "dash stable body")
	for hero: String in ["CH02","CH03"]:
		check(Family.metadata_path(hero,"actions","front").is_empty(), hero + " keeps its established authored body")
		check(not Visual.action_frame_info(hero).is_empty(), hero + " established idle still loads")
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(Family.metadata_path("CH01","basic","front"))))
	check(Family._valid_document(valid,"CH01","basic","front"), "family gate accepts the real complete basic atlas")
	var rejected: Dictionary = valid.duplicate(true)
	rejected.frames[0].region[2] = 100000
	check(not Family._valid_document(rejected,"CH01","basic","front"), "family gate rejects a source region beyond the decoded texture")
	rejected = valid.duplicate(true)
	rejected.frames[1].region = rejected.frames[0].region.duplicate()
	check(not Family._valid_document(rejected,"CH01","basic","front"), "family gate rejects overlapping source regions")
	rejected = valid.duplicate(true)
	rejected.phase_weights.release[0] = 0.0
	check(not Family._valid_document(rejected,"CH01","basic","front"), "family gate rejects a clip that cannot sample its release")
	rejected = valid.duplicate(true)
	rejected.slot = "secondary"
	check(not Family._valid_document(rejected,"CH01","basic","front"), "family gate rejects the wrong declared basic identity")
	rejected = valid.duplicate(true)
	rejected.frames[0].muzzle = [100000,0]
	check(not Family._valid_document(rejected,"CH01","basic","front"), "family gate rejects an attachment beyond its frame")
	rejected = valid.duplicate(true)
	rejected.texture = "asset://heroes/CH02_actions_front_v2.png"
	check(not Family._valid_document(rejected,"CH01","basic","front"), "family gate rejects one legacy body accidentally mixed into the replacement")
	return true

func aim(at: Vector2) -> void:
	room.camera.follow_target()
	room.camera.force_update_scroll()
	var event := InputEventMouseMotion.new()
	event.position = stage.get_canvas_transform() * room.to_global(at)
	event.global_position = event.position
	stage.push_input(event,true)

func capture(facing: String, action: String, phase: String) -> void:
	# A minimized acceptance window can suspend presentation indefinitely. The
	# offscreen stage still needs one real renderer draw, with native physics and
	# the committed pose untouched; no synthetic pose or simulation step is used.
	call_deferred("_draw_capture_stage")
	await capture_drawn
	var actor: Node2D = room.player
	var source: String = str(actor.get_meta("hero_visual_source",""))
	check(source.contains("CH01_storybook_") or source.contains("CH01_directional_"), facing + " " + action + " actual draw uses the matching body")
	check(actor.get_meta("hero_foot_local",Vector2.INF) == Vector2(0,8), facing + " " + action + " actual draw keeps the registered foot")
	var image: Image = stage.get_texture().get_image()
	var filename: String = "%s_%s_%s.png" % [facing,action,phase]
	check(image.get_size() == Vector2i(1280,720), "read actual native frame " + filename)
	if action == "walk":
		check(str(actor.get_meta("hero_visual_pose","")) == "walk", facing + " real movement consumes its gait frame")
	pending_images[filename] = image
	var foot_screen: Vector2 = actor.get_global_transform_with_canvas() * Vector2(0,8)
	var crop := Rect2i(Vector2i(foot_screen) - Vector2i(100,155),Vector2i(200,180)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var body_filename: String = filename.trim_suffix(".png") + "_body.png"
	pending_images[body_filename] = image.get_region(crop)
	records.append({"file":filename,"body_crop":body_filename,"facing":facing,"action":action,"phase":phase,"source":source,"draw_pose":str(actor.get_meta("hero_visual_pose","")),"draw_bank":str(actor.get_meta("hero_visual_bank","")),"draw_flip":float(actor.get_meta("hero_visual_flip",0.0)),"frame_index":int(actor.get_meta("hero_visual_frame",-1)),"foot_local":actor.get_meta("hero_foot_local",Vector2.INF),"foot_screen":foot_screen,"body_crop_rect":crop,"position":actor.position,"camera_zoom":room.camera.zoom,"actual_feedback":actor.get_node("HeroFeedback").pose_state()})

func _draw_capture_stage() -> void:
	RenderingServer.force_draw(false)
	capture_drawn.emit()

func flush_captures() -> void:
	# Compression is deliberately outside observed action windows. Short contact
	# poses must not disappear because a preceding screenshot was written to disk.
	for filename: String in pending_images:
		var image: Image = pending_images[filename]
		check(image.save_png(OUTPUT.path_join(filename)) == OK, "save actual native frame " + filename)
	pending_images.clear()

func observe_action(facing: String, slot: String, target: Vector2) -> void:
	var actor: Node2D = room.player
	actor.cancel_actions()
	actor.shot_cooldown = 0.0
	actor.visual_hitstop = 0.0
	actor.visual_remaining = 0.0
	for key: String in actor.cooldowns:
		actor.cooldowns[key] = 0.0
	Game.run.resource = 100.0
	actor.aim_direction = actor.position.direction_to(target)
	aim(target)
	await frames(1)
	var started: bool = actor.fire(actor.aim_direction) if slot == "basic" else actor.cast_skill(slot,target)
	check(started, facing + " " + slot + " commits a real production action")
	if not started:
		return
	var seen: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 1700
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var pose: Dictionary = actor.get_node("HeroFeedback").pose_state()
		var phase: String = str(pose.phase)
		if str(pose.slot) == slot and phase in ["windup","release","recovery"] and not seen.has(phase):
			seen[phase] = true
			await capture(facing,slot,phase)
		if not actor.abilities.busy() and actor.attack_remaining <= 0.0 and phase == "idle":
			break
	check(seen.has("windup") and seen.has("release") and seen.has("recovery"), facing + " " + slot + " naturally renders its complete three-phase sequence")
	flush_captures()

func native_acceptance() -> void:
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var display := TextureRect.new()
	display.texture = stage.get_texture()
	display.size = Vector2(1280,720)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	stage.add_child(app)
	await frames(2)
	check(Game.new_profile() and Game.select_hero("CH01") and Game.start_run(), "isolated production CH01 run starts")
	# This is a body/animation acceptance window, not the separate mapping suite.
	# Desktop clicks/keys must not add real attacks between captured poses. Keep
	# production action names for movement, but detach physical bindings locally.
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action)
	room = app.room
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for child: Node in room.enemies.get_children():
		child.free()
	Game.run.level = 8
	Game.run.stats = Resolver.resolve("CH01",8,{}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	room.player.resource_delay = 1000.0
	room.combat_audio.audible = false
	# Geometry remains real. The deterministic stage uses the cleared central
	# court, and source/frame telemetry comes from production HeroVisual._draw.
	for facing: String in DIRECTIONS:
		var direction: Vector2 = DIRECTIONS[facing].normalized()
		room.player.cancel_actions()
		room.player.position = Vector2(1400,900)
		room.player.velocity = Vector2.ZERO
		room.player.aim_direction = direction
		aim(room.player.position + direction * 250.0)
		await frames(3)
		await capture(facing,"idle","idle")
		var action_x: String = "move_right" if direction.x > 0 else "move_left"
		var action_y: String = "move_down" if direction.y > 0 else "move_up"
		Input.action_press(action_x)
		Input.action_press(action_y)
		await frames(6)
		await capture(facing,"walk","walk")
		Input.action_release(action_x)
		Input.action_release(action_y)
		await frames(2)
		flush_captures()
		for slot: String in ["basic","q","secondary","f","ultimate"]:
			room.player.position = Vector2(1400,900)
			await observe_action(facing,slot,room.player.position + direction * 100.0)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	app.set_process(false)
	check(await room.combat_audio.wait_for_cleanup(), "body capture releases combat audio")
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(), "body capture releases production music")
	app.free()
	await frames(2)
	Game.finish_run("abandoned")

func run_checks() -> void:
	if not str(Game.profile_path).contains("test_hero_storybook_family"):
		push_error("Refusing non-isolated storybook body acceptance profile")
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	get_tree().create_timer(90.0).timeout.connect(func(): push_error("Body family acceptance timed out"); get_tree().quit(1))
	if check_sources() and graphical:
		await native_acceptance()
	var file := FileAccess.open(AssetCatalog.resolve(OUTPUT.path_join("acceptance.json" if graphical else "headless_acceptance.json")),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"graphical":graphical,"method":"Production CH01 body samplers, real main/HUD/room, automatic native physics and actual fire/cast actions. Physical desktop bindings are detached only inside this isolated capture process to prevent unrelated pointer/key input; movement uses the production Input action state. Each capture asks the actual RenderingServer to draw the offscreen viewport, so minimizing the desktop window cannot suspend capture; no extra simulation step, time scale or synthetic pose is used. Four authored facing banks use front/back plus horizontal mirror. Body scale 88 world units; camera .85. Fixture level8 unlocks all slots; cooldown/resource reset only between independent capture trials. PNG frames are actual viewport output, no reconstructed animation frames.","records":records},"\t"))
	file.close()
	print("HERO STORYBOOK FAMILY: %d checks, %d failures, graphical=%s" % [checks,failures,str(graphical)])
	get_tree().quit(0 if failures == 0 else 1)
