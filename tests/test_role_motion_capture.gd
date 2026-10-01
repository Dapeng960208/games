extends "res://tests/test_combat_feedback.gd"
## Real movement, dodge and basic presentation capture. Only initial fixture
## placement and durable enemy HP/AI are controlled; native clocks, collisions,
## committed directions, projectiles and renderer states remain untouched.

const DIRECTIONS := [
	{"name":"NE", "vector":Vector2(1,-1)},
	{"name":"SW", "vector":Vector2(-1,1)},
]
var pointer_world := Vector2.ZERO
var motion_reports: Array[Dictionary] = []
var observing_dash := false
var current_dash: Dictionary = {}
var pending_images: Array[Dictionary] = []

func _physics_process(_delta: float) -> void:
	if not observing_dash or not is_instance_valid(room): return
	current_dash.samples.append({"elapsed":room.player.dash_elapsed,"remaining":room.player.dash_remaining,"position":_point(room.player.position),"dash_direction":_point(room.player.dash_direction),"aim_direction":_point(room.player.aim_direction)})
	if room.player.dash_direction.dot(current_dash.direction) < 0.999:
		current_dash["direction_stayed_committed"] = false

func _aim_input() -> void:
	var aim_at := room.get_canvas_transform()*room.to_global(pointer_world)
	var motion := InputEventMouseMotion.new()
	motion.position = aim_at
	motion.global_position = aim_at
	stage.push_input(motion,true)

func _point(value: Vector2) -> Array:
	return [value.x,value.y]

func _open_motion_stage() -> Vector2:
	# Validate the trajectories this probe actually uses, across the production
	# arena. The older skill fixture's 360px horizontal lane is unrelated here.
	var arena: Rect2 = room.ARENA
	var appearance: GDScript = preload("res://scripts/world/room_appearance.gd")
	var prop_art: GDScript = preload("res://scripts/world/world_prop_art.gd")
	var scenery_bounds: Array[Rect2] = []
	for item: Dictionary in appearance.depth_recipe(room.layout,str(room.layout.get("biome_id","B01")),room.enemy_props.obstacle_recipes):
		if item.get("visual_bounds",Rect2()).has_area(): scenery_bounds.append(item.visual_bounds)
	# Ground inlays are omitted by depth_recipe but can still visually cover a
	# short motion cue. Include their actual authored quads in fixture spacing.
	for item: Dictionary in room.enemy_props.obstacle_recipes:
		if not prop_art.has_authored_asset(str(item.get("asset",""))): continue
		var quad: PackedVector2Array = prop_art.sprite_quad(item)
		if quad.is_empty(): continue
		var bounds := Rect2(quad[0],Vector2.ZERO)
		for point: Vector2 in quad: bounds = bounds.expand(point)
		scenery_bounds.append(bounds)
	var chosen := Vector2.ZERO
	var best_distance := INF
	for y in range(int(arena.position.y)+200,int(arena.end.y)-200,50):
		for x in range(int(arena.position.x)+200,int(arena.end.x)-200,50):
			var candidate := Vector2(x,y)
			var valid: bool = room.valid_ground(candidate,30.0)
			for item: Dictionary in DIRECTIONS:
				var endpoint: Vector2 = candidate+Vector2(item.vector).normalized()*260.0
				valid = valid and room.valid_ground(endpoint,30.0) and room.blocked_fraction(candidate,endpoint,30.0) >= 1.0
				for distance: float in [0.0,80.0,160.0,220.0,260.0]:
					var foot: Vector2 = candidate+Vector2(item.vector).normalized()*distance
					var actor_bounds := Rect2(foot-Vector2(35,115),Vector2(70,135))
					for bounds: Rect2 in scenery_bounds:
						if bounds.intersects(actor_bounds): valid = false
			var center_distance: float = candidate.distance_squared_to(arena.get_center())
			if valid and center_distance < best_distance:
				chosen = candidate
				best_distance = center_distance
	return chosen

func _release_movement() -> void:
	for action: String in ["move_left","move_right","move_up","move_down"]:
		Input.action_release(action)

func _move_input(direction: Vector2) -> void:
	_release_movement()
	Input.action_press("move_right" if direction.x > 0 else "move_left")
	Input.action_press("move_down" if direction.y > 0 else "move_up")

func _aim_at(point: Vector2) -> void:
	pointer_world = point
	_aim_input()
	await get_tree().physics_frame
	await frame()

func _reset_actor() -> void:
	_release_movement()
	Input.action_release("attack")
	while room.player.dash_remaining > 0 or room.player.shot_cooldown > 0 or room.player.abilities.busy(): await frame()
	room.player.clear_movement_target()
	room.player.position = anchor
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frame()
	await frame()

func _capture(phase: String, direction_name: String) -> Dictionary:
	var player: Node2D = room.player
	var feedback: Node = player.get_node("HeroFeedback")
	var pose: Dictionary = feedback.pose_state()
	var motion: Dictionary = feedback.motion_state() if feedback.has_method("motion_state") else {}
	var effect_kinds: Array[String] = []
	for effect: Dictionary in feedback.effects:
		if not effect_kinds.has(str(effect.kind)): effect_kinds.append(str(effect.kind))
	var filename := "role_motion_"+current_hero+"_"+direction_name+"_"+phase+".png"
	# Cache original pixels during the short dodge; PNG compression happens after
	# all native timelines so file IO cannot push a mid-dodge sample past landing.
	var pixels: Image = stage.get_texture().get_image()
	check(pixels != null and pixels.get_size() == stage.size,"native motion framebuffer cached: "+filename)
	pending_images.append({"file":filename,"pixels":pixels})
	var source := str(player.get_meta("hero_visual_source",""))
	check(source.begins_with("res://assets/generated/heroes/"),current_hero+" "+phase+" uses approved authored body source")
	var foot: Vector2 = player.get_meta("hero_foot_local",Vector2(INF,INF))
	var body_transform: Transform2D = player.get_meta("hero_body_transform",Transform2D.IDENTITY)
	check(foot.is_finite() and foot.distance_to(body_transform*Vector2(0,8)) < 0.001,current_hero+" "+phase+" foot metadata follows actual body transform")
	# Existing basic release adds at most 3.1px authored recoil/lean. Movement
	# and dodge pin the feet exactly; the native release translation is retained.
	var foot_tolerance: float = 3.2 if phase.begins_with("basic") else 0.01
	check(foot.is_finite() and foot.distance_to(Vector2(0,8)) < foot_tolerance,current_hero+" "+phase+" retains native foot anchor/recoil contract")
	return {"file":filename,"phase":phase,"room_elapsed":room.elapsed,"position":_point(player.position),"velocity":_point(player.velocity),"aim_direction":_point(player.aim_direction),"presentation_direction":_point(player.get_meta("hero_presentation_direction",Vector2.ZERO)),"dash_elapsed":player.dash_elapsed,"dash_remaining":player.dash_remaining,"body_source":source,"body_phase":player.get_meta("hero_visual_pose",""),"body_bank":player.get_meta("hero_visual_bank",""),"body_frame":player.get_meta("hero_visual_frame",-1),"foot_anchor":_point(foot),"pose_phase":pose.get("phase",""),"pose_direction":_point(pose.get("direction",Vector2.ZERO)),"motion_direction":_point(motion.get("direction",Vector2.ZERO)),"moving":motion.get("moving",false),"dashing":motion.get("dashing",false),"steps":motion.get("steps",0),"native_feedback_kinds":effect_kinds,"projectiles":room.projectiles.get_child_count()}

func _walk_sample(direction: Vector2, direction_name: String) -> Dictionary:
	await _reset_actor()
	await _aim_at(anchor-direction*160)
	var origin: Vector2 = room.player.position
	var started: float = room.elapsed
	var feedback: Node = room.player.get_node("HeroFeedback")
	var steps_before: int = int(feedback.motion_state().steps)
	_move_input(direction)
	await wait_seconds(0.20)
	var frames: Array = [_capture("walk_mid",direction_name)]
	await wait_seconds(0.20)
	frames.append(_capture("walk_end",direction_name))
	_release_movement()
	var travel: Vector2 = room.player.position-origin
	check(travel.length() > 50.0,current_hero+" "+direction_name+" real movement travels on legal ground")
	check(travel.normalized().dot(direction) > 0.99,current_hero+" "+direction_name+" real input movement follows diagonal")
	var shown: Vector2 = room.player.get_meta("hero_presentation_direction",Vector2.ZERO)
	check(shown.dot(direction) > 0.99,current_hero+" walking faces resolved travel while pointer faces opposite")
	check(int(feedback.motion_state().steps) > steps_before,current_hero+" native resolved walking emits footfall cues")
	await get_tree().physics_frame
	return {"kind":"walk","direction":_point(direction),"elapsed":room.elapsed-started,"distance":travel.length(),"resolved_travel":_point(travel),"frames":frames}

func _dash_sample(direction: Vector2, direction_name: String) -> Dictionary:
	await _reset_actor()
	while room.player.dash_cooldown > 0: await frame()
	await _aim_at(anchor+direction*160)
	var origin: Vector2 = room.player.position
	var started: float = room.elapsed
	current_dash = {"direction":direction,"direction_stayed_committed":true,"samples":[]}
	observing_dash = true
	var accepted: bool = room.player.start_dash(direction)
	check(accepted,current_hero+" "+direction_name+" public native dodge accepted")
	await frame()
	var frames: Array = [_capture("dash_depart",direction_name)]
	pointer_world = origin-direction*160
	_aim_input()
	while room.player.dash_elapsed < 0.09 and room.player.dash_remaining > 0: await frame()
	frames.append(_capture("dash_mid_pointer_turned",direction_name))
	check(room.player.dash_remaining > 0,current_hero+" mid-dodge sample is still inside actual native dodge")
	check(room.player.aim_direction.dot(-direction) > 0.98,current_hero+" actual mouse reader turned during dodge")
	check(room.player.dash_direction.dot(direction) > 0.999 and bool(current_dash.direction_stayed_committed),current_hero+" dodge direction stays committed while mouse changes")
	check(room.player.get_meta("hero_presentation_direction",Vector2.ZERO).dot(direction) > 0.99,current_hero+" dodge presentation retains committed direction")
	while room.player.dash_remaining > 0: await frame()
	await wait_seconds(0.04)
	frames.append(_capture("dash_land",direction_name))
	check(frames[-1].native_feedback_kinds.has("dash_land"),current_hero+" native dodge completion emits landing cue")
	observing_dash = false
	var travel: Vector2 = room.player.position-origin
	var expected: float = 110.0 if current_hero == "CH01" else 160.0 if current_hero == "CH02" else 130.0
	check(absf(travel.length()-expected) < 1.0,current_hero+" native dodge distance preserved")
	check(travel.normalized().dot(direction) > 0.99,current_hero+" dodge resolved travel matches committed diagonal")
	var samples: Array = current_dash.samples.duplicate(true)
	current_dash.clear()
	return {"kind":"dash","direction":_point(direction),"distance":travel.length(),"expected_distance":expected,"elapsed":room.elapsed-started,"frames":frames,"physics_samples":samples}

func _basic_sample(direction: Vector2, direction_name: String) -> Dictionary:
	await _reset_actor()
	var target_distance: float = 75.0 if current_hero == "CH01" else 200.0
	target = room.spawn_enemy(anchor+direction*target_distance,"M01",1,{"reward_enabled":false})
	target.training_ai_disabled = true
	target.health.reset(10000.0)
	await wait_seconds(0.55) # Let its native spawn presentation/protection finish.
	await _aim_at(target.position)
	var feedback: Node = room.player.get_node("HeroFeedback")
	var previous_basics: int = feedback.basic_events
	var started: float = room.elapsed
	var committed: Vector2 = room.player.position.direction_to(target.position)
	check(room.player.fire(committed),current_hero+" "+direction_name+" public native basic accepted")
	while feedback.basic_events == previous_basics and room.elapsed-started < 1.0: await frame()
	check(feedback.basic_events > previous_basics,current_hero+" actual basic release observed")
	await frame()
	var frames: Array = [_capture("basic_release",direction_name)]
	# Warrior uses its existing live-aim windup. Turn only after actual release
	# so this observes the committed presentation rather than changing attack aim.
	await _aim_at(room.player.position-committed*160)
	await wait_seconds(0.035)
	frames.append(_capture("basic_pointer_turned",direction_name))
	check(room.player.aim_direction.dot(-committed) > 0.98,current_hero+" native pointer turns after basic release")
	var pose: Dictionary = feedback.pose_state()
	check(pose.get("direction",Vector2.ZERO).dot(committed) > 0.99,current_hero+" basic presentation retains actual released direction")
	check(room.player.get_meta("hero_presentation_direction",Vector2.ZERO).dot(committed) > 0.99,current_hero+" basic body follows committed direction")
	await wait_seconds(0.40)
	var dealt: float = 10000.0-target.health.current
	check(dealt > 0,current_hero+" actual basic damaged the durable production target")
	target.queue_free()
	await frame()
	return {"kind":"basic","direction":_point(committed),"damage":dealt,"elapsed":room.elapsed-started,"frames":frames}

func run_checks() -> void:
	if not Game.profile_path.contains("test_role_motion_capture"):
		push_error("Motion capture requires isolated test_role_motion_capture profile")
		_finish(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	check(graphical,"motion capture has actual graphical renderer")
	if not graphical:
		_finish(2)
		return
	DisplayServer.window_set_size(Vector2i(1280,720))
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280,720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	app = load("res://scenes/main.tscn").instantiate()
	stage.add_child(app)
	await frame()
	await frame()
	for hero: String in ["CH01","CH02","CH03"]:
		current_hero = hero
		check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(),hero+" fresh production-main run")
		Game.set_setting("reduced_fx",false)
		Game.set_setting("language","zh_CN")
		room = app.room
		room.spawn_enabled = false
		check(Game.grant_hero_xp(3600,"motion_visual_"+hero) and Game.run.level == 20,hero+" real XP unlocks level20")
		for enemy in room.enemies.get_children(): enemy.queue_free()
		await frame()
		anchor = _open_motion_stage()
		check(not anchor.is_zero_approx(),hero+" verified actual open room ground")
		if anchor.is_zero_approx():
			_finish(1)
			return
		aim_tracking = true
		var report := {"hero":hero,"samples":[]}
		for item: Dictionary in DIRECTIONS:
			var direction: Vector2 = Vector2(item.vector).normalized()
			report.samples.append(await _walk_sample(direction,str(item.name)))
			report.samples.append(await _dash_sample(direction,str(item.name)))
			report.samples.append(await _basic_sample(direction,str(item.name)))
		motion_reports.append(report)
		aim_tracking = false
		_release_movement()
		Game.finish_run("abandoned")
		await frame()
		await frame()
	for pending: Dictionary in pending_images:
		var status: Error = pending.pixels.save_png("res://artifacts/"+str(pending.file))
		check(status == OK,"original motion framebuffer saved: "+str(pending.file))
		if status == OK: captures += 1
	pending_images.clear()
	var file := FileAccess.open("res://artifacts/role_motion_capture.json",FileAccess.WRITE)
	check(file != null,"actual motion report created")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"graphical":graphical,"audio":"Master safety muted; no subjective listening assessment.","fixture":"Fresh production-main level20 run through real XP per hero. Starter bodies/loadout; actual room geometry retained; random spawning disabled. Actor position resets only between named demonstrations. Movement uses actual diagonal Input actions. Native public start_dash and fire; no manual actor ticks, pose writes or fabricated effects. Dash cooldown recovers naturally. Basic M01 targets have HP10000 and AI/rewards disabled; test enemy placement only. Pointer is dispatched through the actual SubViewport mouse reader and deliberately changes during dodge and after actual basic release. PNGs are original framebuffers.","reports":motion_reports},"\t"))
		file.close()
	print("ROLE_MOTION_CAPTURE_RESULT checks=",checks," failures=",failures," captures=",captures)
	_release_movement()
	_finish(1 if failures else 0)
