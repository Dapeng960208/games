extends "res://tests/test_combat_feedback.gd"
## Actual GPU framebuffers and normal native clocks; no authored effect ages,
## injected damage or stack writes. A stationary, durable practice recipient.
var chain_frames: Array[Dictionary] = []

func _open_stage() -> Vector2:
	# Search the current generated arena rather than the old fixed room rectangle.
	var arena: Rect2 = room.ARENA
	var chosen := Vector2.ZERO
	var nearest: float = INF
	for y in range(int(arena.position.y)+80,int(arena.end.y)-80,40):
		for x in range(int(arena.position.x)+240,int(arena.end.x)-360,40):
			var candidate := Vector2(x,y)
			if room.valid_ground(candidate,35.0) and room.blocked_fraction(candidate-Vector2(220,0),candidate+Vector2(340,0),35.0) >= 1.0 and room.valid_ground(candidate-Vector2(220,0),35.0) and room.valid_ground(candidate+Vector2(340,0),35.0):
				var distance: float = candidate.distance_squared_to(arena.get_center())
				if distance < nearest:
					chosen = candidate
					nearest = distance
	return chosen

func _aim_input() -> void:
	if not is_instance_valid(target): return
	var aim_at: Vector2 = room.get_canvas_transform()*room.to_global(target.position)
	var motion := InputEventMouseMotion.new()
	motion.position = aim_at
	motion.global_position = aim_at
	stage.push_input(motion,true)

func _save_chain_frame(label: String) -> void:
	var filename: String = "hit_chain_"+current_hero+"_"+label+".png"
	check(stage.get_texture().get_image().save_png("res://artifacts/"+filename) == OK, "native framebuffer " + filename)
	chain_frames.append({"hero":current_hero,"file":filename,"elapsed":room.elapsed,"state":room.player.hit_chain.snapshot(),"native_releases":room.player.get_node("HeroFeedback").basic_events,"hp":target.health.current})
	captures += 1

func run_checks() -> void:
	if not Game.profile_path.contains("test_hit_chain_capture"):
		_finish(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	check(graphical,"actual GPU framebuffer available")
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
	for hero: String in ["CH01","CH02","CH03"]:
		current_hero = hero
		check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(), hero + " production main run")
		Game.set_setting("language","zh_CN")
		Game.set_setting("reduced_fx",false)
		room = app.room
		room.spawn_enabled = false
		check(Game.grant_hero_xp(3600,"chain_capture_"+hero),"level20 via XP API")
		for enemy: Node in room.enemies.get_children(): enemy.queue_free()
		await frame()
		anchor = _open_stage()
		check(not anchor.is_zero_approx(),"legal open ground")
		if anchor.is_zero_approx():
			_finish(1)
			return
		target = room.spawn_enemy(anchor,"M01",1,{"reward_enabled":false})
		target.training_ai_disabled = true
		# A stationary practice recipient uses the native boss knockback immunity.
		# This test-only fixture keeps one hundred contacts on the verified lane.
		target.rank = "boss"
		target.health.reset(100000.0)
		room.player.position = anchor-Vector2(75 if hero == "CH01" else 180,0)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		aim_tracking = true
		await wait_seconds(.55)
		var limit: int = 100 if hero == "CH02" else 10
		for n in range(1,limit+1):
			while room.player.shot_cooldown > 0.0 or room.player.attack_remaining > 0.0: await frame()
			var wanted: float = 75.0 if hero == "CH01" else 180.0
			if room.player.position.distance_to(target.position) > wanted+14:
				Input.action_press("move_right")
				var started: float = room.elapsed
				while room.player.position.distance_to(target.position) > wanted and room.elapsed-started < 2.0: await frame()
				Input.action_release("move_right")
				await frame()
			_aim_input()
			await get_tree().physics_frame
			var feedback: Node = room.player.get_node("HeroFeedback")
			var before: int = feedback.basic_events
			check(room.player.fire(room.player.position.direction_to(target.position)),hero + " native attack " + str(n))
			var started: float = room.elapsed
			while feedback.basic_events == before and room.elapsed-started < 1.0: await frame()
			if n <= 3:
				await frame()
				_save_chain_frame("variant_"+str(n))
			while room.player.hit_chain.count < n and room.elapsed-started < 2.0: await frame()
			check(room.player.hit_chain.count == n, hero + " real confirmed x" + str(n))
			if n in [10,25,50,75,100]:
				await wait_seconds(.035)
				_save_chain_frame("x"+str(n))
				check(int(app.hud.hit_chain_readout.state.count) == n,"HUD reads actual stack count")
		if hero == "CH02":
			Game.set_setting("reduced_fx",true)
			Words.set_locale("en")
			await frame()
			_save_chain_frame("x100_reduced_en")
			check(app.hud.hit_chain_readout.visible,"reduced effects preserves readable x100")
			Game.set_setting("reduced_fx",false)
			Words.set_locale("zh_CN")
		await wait_seconds(4.1)
		check(room.player.hit_chain.count == 0 and not app.hud.hit_chain_readout.visible,"native timeout removes buff and banner")
		aim_tracking = false
		Game.finish_run("abandoned")
		await frame()
	var report := FileAccess.open("res://artifacts/hit_chain_capture.json",FileAccess.WRITE)
	check(report != null,"capture report saved")
	if report != null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"frames":chain_frames,"fixture":"Production main/room/player/projectiles/impacts/HUD. Level20 through XP API, starter loadout, real room geometry retained, random spawns disabled. Initial placements only. One M01 HP100000 with AI/rewards disabled and test boss-rank knockback immunity per hero, retaining its M01 body. Public fire. Cooldowns, physics, damage, buffs, effects and expiry run on normal clocks; no manual ticks or stack writes. Warrior/mage ten actual attacks each; gunner one hundred. Original SubViewport GPU images, no compositing. Master muted during capture."},"\t"))
		report.close()
	print("HIT_CHAIN_CAPTURE_RESULT checks=",checks," failures=",failures," captures=",captures)
	_finish(1 if failures else 0)
