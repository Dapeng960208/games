extends "res://tests/test_hit_feel.gd"
## Deterministic visual review of real basic projectiles; no retimed video claim.

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_projectile_identity_capture"):
		quit(2)
		return
	room_scene = load("res://scenes/room.tscn")
	resolver = load("res://scripts/combat/stat_resolver.gd")
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	game.new_profile()
	game.start_run()
	for hero: String in ["CH02", "CH03"]:
		fixture(hero)
		room.input_blocked = true
		room.player.position = Vector2(1400, 900)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		dummy("M01", Vector2(400, 0))
		check(room.player.fire(Vector2.RIGHT), hero + " real basic fired")
		var bolt: Node2D = room.projectiles.get_child(0)
		check(bolt.options.get("visual_hero") == hero, hero + " actual shot owns class appearance")
		bolt._physics_process(0.14)
		room.player.queue_redraw()
		room.queue_redraw()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://artifacts/projectile_identity_%s.png" % hero) == OK, hero + " real framebuffer saved")
		await room.combat_audio.wait_for_cleanup()
	if is_instance_valid(room): room.free()
	print("PROJECTILE IDENTITY CAPTURE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
