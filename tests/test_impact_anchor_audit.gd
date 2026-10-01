extends "res://tests/test_hit_feel.gd"

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_impact_anchor_audit"):
		quit(2)
		return
	room_scene = load("res://scenes/room.tscn")
	resolver = load("res://scripts/combat/stat_resolver.gd")
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	game.new_profile()
	game.start_run()
	fixture("CH01")
	room.player.position = Vector2(1400,900)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.input_blocked = true
	var target = dummy("M01",Vector2(80,15))
	room.player.aim_direction = (target.position-room.player.position).normalized()
	room.player.cast_skill("secondary",target.position)
	var elapsed: float = 0.0
	while room.impact_feedback.accepted_events == 0 and elapsed < 1.0:
		room.player.abilities.tick(0.005)
		room.player.get_node("HeroFeedback").advance(0.005)
		elapsed += 0.005
	room.player.visual_hitstop = maxf(0.0,room.player.visual_hitstop-.015)
	room.player.abilities.tick(.015)
	room.player.get_node("HeroFeedback").advance(.015)
	room.impact_feedback.advance(.015)
	target.body_visual.advance(.015)
	room.camera._physics_process(.015)
	room.camera.force_update_scroll()
	var hit_event: Dictionary = contact_events()[0]
	var contact: Vector2 = room.impact_feedback.contact_position(hit_event)
	var visual: Node2D = target.body_visual
	var body_frame: Dictionary = visual.body_frame()
	var body_point: Vector2 = visual.to_local(room.to_global(contact))
	var source: Vector2 = body_frame.region.position + (body_point-body_frame.bounds.position)*body_frame.region.size/body_frame.bounds.size
	var texture: Texture2D = body_frame.texture
	var source_image: Image = texture.get_image()
	if source_image.is_compressed(): source_image.decompress()
	var pixel: Vector2i = Vector2i(source)
	var alpha: float = source_image.get_pixelv(pixel).a if Rect2i(Vector2i.ZERO,source_image.get_size()).has_point(pixel) else -1.0
	var body_center: Vector2 = room.to_local(visual.to_global(Vector2(0,-target.body_bounds.size.y*.53)))
	print("ANCHOR_AUDIT ", JSON.stringify({"target_position":str(target.position),"body_bounds":str(target.body_bounds),"contact_room":str(contact),"contact_screen":str(room.get_global_transform_with_canvas()*contact),"body_frame":str(body_frame.name),"source_contact":str(source),"source_alpha":alpha,"animated_body_center_room":str(body_center),"animated_center_screen":str(room.get_global_transform_with_canvas()*body_center),"center_delta_px":contact.distance_to(body_center),"body_visual_transform":str(visual.transform),"contact_event":str(hit_event)}))
	for effect: Dictionary in room.player.get_node("HeroFeedback").effects:
		print("HERO_EFFECT ", effect)
	for effect: Dictionary in room.impact_feedback.events:
		print("CONTACT_EFFECT ", effect)
	await room.combat_audio.wait_for_cleanup()
	room.free()
	quit(0)
