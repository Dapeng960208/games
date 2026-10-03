extends Node
## Focused structural checks; graphics run only when explicitly scheduled.
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Review = preload("res://scripts/levels/b07/art/l37_convergence_environment.gd")
const Fx = preload("res://scripts/levels/b07/art/l37_review_fx.gd")
const Skills = preload("res://scripts/levels/b07/combat/enemy_skills.gd")
const Actors = preload("res://scripts/levels/b07/art/actor_review.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("L37 CONVERGENCE: "+label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(1280,720)
	await get_tree().process_frame
	var out := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if out.is_empty() or not Game.profile_path.begins_with("user://test_b07_candidate/"):
		get_tree().quit(2)
		return
	var launch := Launcher.new()
	launch.auto_start = false
	launch.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(launch)
	check(launch.start_candidate("CH01",0,false),"isolated launcher: "+launch.last_error)
	if not is_instance_valid(launch.room):
		launch.free()
		get_tree().quit(1)
		return
	var room: Node2D = launch.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.camera.process_mode = Node.PROCESS_MODE_DISABLED
	room.combat_audio.audible = false
	var backdrop: Node2D = room.get_node("MineBackdrop")
	if Review.requested():
		check(is_instance_valid(backdrop.b07_art_trial) and backdrop.b07_art_trial.get("review_ready") == true,"new review environment installed")
		if is_instance_valid(backdrop.b07_art_trial) and backdrop.b07_art_trial.get("review_ready") == true:
			var art: Node2D = backdrop.b07_art_trial
			check(art.review_components.size() == 4,"two city wings, exterior bridge, independent sun")
			check(not art.get_node("NorthCityCompositionReview").visible,"failed RGB crop not visible")
			for sprite: Sprite2D in art.review_components:
				check(sprite.modulate == Color.WHITE,"native full color: "+sprite.name)
				check(sprite.region_rect.has_area(),"measured source content: "+sprite.name)
	else:
		check(not is_instance_valid(backdrop.b07_art_trial) or backdrop.b07_art_trial.get("review_ready") != true,"new assembly stays opt-in")
	check(room.ground_polygon == Geometry.polygon("L37"),"original walkable polygon")
	check(room.layout.obstructions.size() == 2,"original two collision covers")
	check(room.player.position == Geometry.world_point([320,900]),"actual player entry")
	check(room.exit_position == Geometry.world_point([2480,900]),"actual exit")
	if Review.requested():
		room.camera.configure(room,room.player,room.ARENA,backdrop.painted_bounds())
		check(room.camera.b07_north_review,"existing north-follow camera preserved")
		check(room.camera.position == room.player.position+Vector2(160,-160),"actual player-follow offset")
		check(room.camera.zoom.is_equal_approx(Vector2(.72,.72)),"existing camera scale")
		_check_fx(room)
		_check_actors(room)
	else:
		check(not Fx.enabled(room.enemy_skills),"new effects stay opt-in")
		for actor: Node2D in room.enemies.get_children():
			check(not Actors.enabled_for(actor),"new actor review stays opt-in")
	if DisplayServer.get_name() != "headless" and "--b07-review-capture" in OS.get_cmdline_user_args():
		check(Review.requested(),"capture requires complete review opt-in")
		get_window().content_scale_size = Vector2i(1280,720)
		get_window().size = Vector2i(2560,1440)
		await get_tree().process_frame
		room.camera.configure(room,room.player,room.ARENA,backdrop.painted_bounds())
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		check(image.get_size() == Vector2i(2560,1440),"actual 2K capture")
		check(image.save_png(out.path_join("L37_convergence_entry_follow.png")) == OK,"save scheduled capture")
		var extent: Vector2 = get_viewport().get_visible_rect().size/room.camera.zoom
		print("L37 REVIEW actual view=",Rect2(room.camera.get_screen_center_position()-extent*.5,extent)," zoom=",room.camera.zoom)
		if "--b07-review-actions" in OS.get_cmdline_user_args():
			await _directed_actions(room,out,true)
	elif "--b07-review-actions-check" in OS.get_cmdline_user_args():
		await _directed_actions(room,out,false)
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	launch.free()
	Game.run = null
	print("L37 CONVERGENCE checks, failures=",failures,"; full continuous animations=0; visual acceptance pending")
	get_tree().quit(1 if failures else 0)

func _check_fx(room: Node2D) -> void:
	var runtime: Node2D = room.enemy_skills
	var checked_identities: Array[String] = []
	check(Fx.enabled(runtime),"effects require actual L37 runtime")
	var detached := Node2D.new()
	check(not Fx.enabled(detached),"detached preview cannot enable effects")
	detached.free()
	for actor: Node2D in room.enemies.get_children():
		checked_identities.append(str(actor.enemy_id))
		var command: Dictionary = Skills.active(actor.profile,actor.position,room.player.position,false)
		var untouched := command.duplicate(true)
		check(Fx.effect_spec(runtime,command).is_empty(),"warning never displays release art")
		var visual := command.duplicate(true)
		visual.merge({"color":Color.WHITE,"remaining":.22},true)
		if actor.enemy_id == "B07-M01":
			check(Fx.effect_spec(runtime,visual).get("id","") == "spear_impact","actual spear release mapping")
			var tail := Skills.child(visual,"melee","cone",40,.8)
			tail.merge({"color":Color.WHITE,"remaining":.22},true)
			check(Fx.effect_spec(runtime,tail).is_empty(),"tail has no invented texture")
		elif actor.enemy_id == "B07-M02":
			check(Fx.effect_spec(runtime,visual).get("id","") == "sand_landing","actual landing mapping")
			var ball := Skills.area(command,command.target,50,30,.8)
			ball.merge({"lob":true,"color":Color.WHITE,"remaining":.22},true)
			check(Fx.effect_spec(runtime,ball).get("id","") == "sand_ball","actual ground-area followup mapping")
			check(Fx.projectile_spec(runtime,ball).is_empty(),"sand ball does not invent projectile")
		elif actor.enemy_id == "B07-M03":
			visual.position = actor.position
			var spec := Fx.projectile_spec(runtime,visual)
			check(spec.get("id","") == "sand_disc" and spec.get("position") == actor.position,"disc follows actual shot position")
			check(Fx.projectile_spec(runtime,visual,true).is_empty(),"reduced FX uses procedural fallback")
		check(Fx.effect_spec(runtime,visual,true).is_empty(),"reduced release uses procedural fallback")
		check(command == untouched,"presentation leaves real command unchanged")
	for identity: String in ["B07-M01","B07-M02","B07-M03"]:
		check(identity in checked_identities,"actual initial encounter contains "+identity)

func _check_actors(room: Node2D) -> void:
	var frame_count := 0
	for actor: Node2D in room.enemies.get_children():
		check(Actors.enabled_for(actor),"actual encounter identity is review-enabled")
		var bank: Dictionary = actor.body_visual._bank
		check(bank.get("b07_review_bank",false),"native review bank installed: "+actor.enemy_id)
		if not bank.get("b07_review_bank",false): continue
		check(bank.get("continuous_animation_sets_complete",-1) == 0,"no complete-animation claim")
		check(not bank.clips.has("walk"),"no fabricated walk clip")
		check(actor.body_visual._foot == Vector2.ZERO,"review ground root aligns physical anchor")
		var initial: Dictionary = actor.body_visual.selected_frame
		for pose: String in bank.clips:
			frame_count += 1
			var frame: Dictionary = bank.clips[pose][0]
			actor.body_visual.selected_frame = frame
			var body: Dictionary = actor.body_visual.body_frame()
			var factor: float = body.bounds.size.y/body.region.size.y
			var mapped_root: Vector2 = body.bounds.position+(Vector2(frame.foot)-body.region.position)*factor
			check(mapped_root.is_zero_approx(),"source root maps to origin: "+actor.enemy_id+" "+pose)
			check(body.get("full_color",false),"original body colors: "+pose)
			check(absf(factor*float(bank.body_height)-float(bank.world_reference_height)*float(frame.source_pose_scale))<.001,"anatomy ratio, not pose height: "+pose)
		actor.body_visual.selected_frame = initial
		# Read-only selection contract: inject authored commands into the frozen
		# brain for this check, never execute a cast, then restore its state.
		var saved_command: Dictionary = actor.brain._command
		var saved_phase: StringName = actor.brain.phase
		var authored: Dictionary = Skills.active(actor.profile,actor.position,room.player.position,false)
		actor.brain._command = authored
		for phase: StringName in [&"telegraph",&"locked",&"execute",&"recovery"]:
			actor.brain.phase = phase
			var expected: String = str(authored.ability_id).get_slice(":",1)+":"+("telegraph" if phase == &"locked" else str(phase))
			check(Actors.select_frame(actor,bank).get("name","") == expected,"authored phase selects key pose: "+expected)
		actor.brain._command = {}
		actor.brain.phase = &"chase"
		if actor.enemy_id == "B07-M03":
			var shot := authored.duplicate(true)
			shot.owner_id = actor.get_instance_id()
			room.enemy_skills.projectiles.append(shot)
			check(Actors.select_frame(actor,bank).get("name","") == "returning_disc:recovery","actual disc in flight stays empty-handed")
			room.enemy_skills.projectiles.erase(shot)
		actor.brain._command = saved_command
		actor.brain.phase = saved_phase
		var original_id: String = room.layout_id
		room.layout_id = "L38"
		check(not Actors.enabled_for(actor),"review excluded from another actual room")
		room.layout_id = original_id
	check(frame_count == 14,"exactly fourteen registered discrete key poses")

func _directed_actions(room: Node2D, out: String, capture: bool) -> void:
	# Directed isolated capture, not a natural-play claim. Keep the real player
	# at the original entrance and its real camera. Move only test enemies into
	# legal cast range, then advance their actual FSM and shared runtime.
	var offsets := {"B07-M01":Vector2(140,-60),"B07-M02":Vector2(110,120),"B07-M03":Vector2(210,-90)}
	for actor: Node2D in room.enemies.get_children():
		actor.position = room.player.position+Vector2(offsets[actor.enemy_id])
		actor.brain.configure(actor.profile)
		actor.brain.tick(actor,.81,room.player)
		check(str(actor.brain.phase) == "telegraph","actual FSM entered telegraph: "+actor.enemy_id)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	if capture: await _save_frame(out,"L37_directed_telegraph.png")
	for actor: Node2D in room.enemies.get_children():
		var tell: Dictionary = actor.brain.current_skill()
		actor.brain.tick(actor,float(tell.get("remaining",0))+.01,room.player)
		check(str(actor.brain.phase) == "locked","actual FSM entered lock: "+actor.enemy_id)
		var locked: Dictionary = actor.brain.current_skill()
		actor.brain.tick(actor,float(locked.get("remaining",0))+.01,room.player)
		check(str(actor.brain.phase) == "execute","actual FSM released: "+actor.enemy_id)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	if capture: await _save_frame(out,"L37_directed_execute_start.png")
	room.enemy_skills.advance(.20)
	for actor: Node2D in room.enemies.get_children():
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	if capture: await _save_frame(out,"L37_directed_mid_motion.png")
	room.enemy_skills.advance(.21)
	for actor: Node2D in room.enemies.get_children():
		actor.brain.tick(actor,.42,room.player)
		check(str(actor.brain.phase) == "recovery","actual FSM recovery: "+actor.enemy_id)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
	room.enemy_skills.queue_redraw()
	if capture: await _save_frame(out,"L37_directed_landing_recovery.png")
	print("L37 DIRECTED ACTIONS: real FSM+runtime, moved enemies only; no natural-play or continuous-animation acceptance")

func _save_frame(out: String, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.get_size() == Vector2i(2560,1440),"directed 2K frame")
	check(image.save_png(out.path_join(filename)) == OK,"save directed frame: "+filename)
