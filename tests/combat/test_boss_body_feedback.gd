extends Node
## Real BossActor -> RoomController direct hit/death acceptance. All four final boss
## portraits are used at their production size; no fake texture or body state.
## Graphical mode saves actual normal/reduced/fallback contact frames and proves
## the boss parent does not secretly retain a second static body behind recoil.

const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const BossScript = preload("res://scripts/gameplay/bosses/boss_actor.gd")
const Profiles = preload("res://scripts/domain/combat/boss_profiles.gd")
const IDS: Array[String] = ["BO01", "BO02", "BO03", "BO04"]
const OUTPUT := "res://artifacts/boss_body_feedback"
var room: Node2D
var checks: int = 0
var failures: int = 0
var completions: Array[Dictionary] = []
var captures: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BOSS BODY FEEDBACK: " + label)

func _run() -> void:
	if not str(Game.profile_path).contains("test_boss_body_feedback"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated real run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	Game.profile.settings["reduced_fx"] = false
	_fixture()
	for id: String in IDS:
		await _check_boss(id)
	await _check_reduced_and_fallback()
	_check_reconfigure()
	if DisplayServer.get_name() != "headless":
		var path: String = ProjectSettings.globalize_path(OUTPUT.path_join("capture.json"))
		var output := FileAccess.open(AssetCatalog.resolve(path), FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify({"kind":"real boss presentation fixture; AI disabled; not balance QA", "captures":captures}, "\t"))
			output.close()
		else: check(false, "capture metadata saves")
	get_tree().paused = false
	await room.combat_audio.wait_for_cleanup()
	room.free()
	print("BOSS BODY FEEDBACK: %d/%d passed" % [checks - failures, checks])
	get_tree().quit(1 if failures else 0)

func _fixture() -> void:
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.enemy_skills.reset_room()
	room.obstructions.clear()
	room.gold_drops.clear()
	room.player.position = Vector2(1200, 800)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	room.combat_audio.set_process(false)
	room.defeat_feedback.set_process(false)
	room.impact_feedback.set_process(false)
	room.camera.set_physics_process(false)
	room.camera.position = Vector2(1260, 770)
	room.camera.reset_smoothing()
	room.camera.force_update_scroll()

func _spawn(id: String, missing_art: bool = false) -> BossActor:
	var boss: BossActor = BossScript.new()
	boss.room = room
	boss.position = room.player.position + Vector2(160, 0)
	if missing_art:
		var profile: Dictionary = Profiles.resolve(id, 0)
		profile["visual_asset"] = "res://artifacts/boss_body_feedback/missing_portrait.png"
		boss.configure(profile)
	else:
		check(boss.configure_boss(id, 0, 5039), id + " real profile configures")
	room.enemies.add_child(boss)
	boss.training_ai_disabled = true
	boss.state = &"chase"
	boss.state_time = 0.0
	boss.aim_direction = Vector2.LEFT
	boss.body_visual.advance(0.001)
	return boss

func _check_boss(id: String) -> void:
	room.defeat_feedback.clear_feedback()
	room.impact_feedback.clear_feedback()
	completions.clear()
	var boss := _spawn(id)
	var body: Node2D = boss.body_visual
	var frame: Dictionary = body.body_frame()
	var visual_count: int = 0
	for child: Node in boss.get_children():
		if child.has_method("body_frame"): visual_count += 1
	check(visual_count == 1 and body.get_parent() == boss and body.show_behind_parent, id + " owns one shared body behind arena markers")
	check(boss.body_texture != null and bool(boss.render_state().asset_loaded), id + " original boss asset loads")
	check(str(boss.render_state().asset_path) == AssetCatalog.boss_body(id), id + " selects its final boss portrait")
	check(frame.texture == boss.body_texture and frame.region == boss.body_region and frame.region.has_area(), id + " displayed body is the final transparent crop")
	check(frame.bounds.size.is_equal_approx(boss.body_bounds.size) and frame.bounds.size.y >= 170.0 and frame.bounds.size.y <= 220.0, id + " body retains production boss dimensions")
	check(is_zero_approx(frame.bounds.end.y) and (body.position - body.body_offset).is_equal_approx(Vector2(0, boss.body_bounds.end.y)), id + " final foot registration does not use old ordinary-enemy pivot")
	var contact: Dictionary = boss.impact_anchor(Vector2.RIGHT)
	check(not contact.is_empty(), id + " final portrait alpha supports a real surface contact")
	if not contact.is_empty():
		check(contact.anchor.get_ref() == body and frame.bounds.grow(0.1).has_point(contact.local_offset), id + " surface contact is anchored to current body crop")
	var actor_position: Vector2 = boss.position
	var radius: float = boss.navigation_radius
	var transform_before: Transform2D = body.transform
	await _assert_single_body(boss, id)
	await _capture(id, "idle", boss)
	var hp_before: float = boss.health.current
	room.resolve_direct_hit(boss, 28.0, &"primary", "", 0.0, Vector2.RIGHT,
		{"damage_type":"true", "equipment_eligible":false, "original_basic":false})
	check(boss.health.current < hp_before and boss.is_alive(), id + " real room attack damages living boss")
	check(not body.transform.is_equal_approx(transform_before) and body.flash_strength > 0.0, id + " confirmed damage reaches visible body recoil and flash")
	check(boss.position == actor_position and is_equal_approx(boss.navigation_radius, radius), id + " reaction does not move physics origin or resize collision")
	check(body.body_frame().texture == frame.texture and body.body_frame().bounds == frame.bounds, id + " hit retains boss art size and registered foot-relative crop")
	await _capture(id, "contact", boss)
	for step: int in 4: body.advance(0.1)
	check(is_zero_approx(body.flash_strength), id + " body flash clears after actual presentation time")
	boss.completed.connect(func(boss_id: String, payload: Dictionary) -> void: completions.append({"id":boss_id, "payload":payload}))
	var boss_ref: WeakRef = weakref(boss)
	var gold_before: int = room.gold_drops.size()
	room.resolve_direct_hit(boss, boss.health.maximum * 10.0, &"primary", "", 0.0, Vector2.RIGHT,
		{"damage_type":"true", "equipment_eligible":false, "original_basic":false})
	check(not boss.is_alive() and boss.is_queued_for_deletion() and boss.is_complete(), id + " lethal real damage completes and queues actor cleanup immediately")
	check(completions.size() == 1 and completions[0].id == id and bool(completions[0].payload.complete), id + " boss completion fires once")
	check(room.gold_drops.size() == gold_before, id + " cosmetic death preserves dedicated boss reward path")
	check(room.defeat_feedback.events.is_empty(), id + " existing dedicated boss completion stays outside ordinary corpse path")
	# Boss-specific death choreography is separate work. This verifies immediate
	# cleanup/completion only; it does not claim a death animation was introduced.
	await get_tree().process_frame
	await get_tree().process_frame
	check(boss_ref.get_ref() == null, id + " dead boss and body release without retaining a gameplay actor")

func _check_reduced_and_fallback() -> void:
	for variant: String in ["reduced", "fallback"]:
		Game.profile.settings["reduced_fx"] = variant == "reduced"
		room.impact_feedback.clear_feedback()
		var boss := _spawn("BO01", variant == "fallback")
		var body: Node2D = boss.body_visual
		var bounds: Rect2 = boss.body_bounds
		check(is_zero_approx(body.body_frame().bounds.end.y) and (body.position - body.body_offset).is_equal_approx(Vector2(0, bounds.end.y)), variant + " body registers current ground pivot")
		check((boss.body_texture == null) == (variant == "fallback"), variant + " uses expected real art availability")
		var before: Transform2D = body.transform
		room.resolve_direct_hit(boss, 25.0, &"primary", "", 0.0, Vector2.RIGHT,
			{"damage_type":"true", "equipment_eligible":false, "original_basic":false})
		check(not body.transform.is_equal_approx(before), variant + " confirmed hit reaches shared body")
		if variant == "reduced": check(is_zero_approx(body.flash_strength), "reduced mode preserves silhouette without whitening flash")
		await _assert_single_body(boss, variant)
		await _capture("BO01", variant, boss)
		boss.free()
	Game.profile.settings["reduced_fx"] = false

func _assert_single_body(boss: BossActor, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var body: Node2D = boss.body_visual
	var old_tint: Color = boss.self_modulate
	room.camera.force_update_scroll()
	# Isolate parent draw commands: self_modulate affects only the gameplay
	# actor's bars/markers, while hiding EnemyBody removes all intended body art.
	body.hide()
	boss.self_modulate = Color(old_tint, 0.0)
	await RenderingServer.frame_post_draw
	var baseline: Image = get_viewport().get_texture().get_image()
	boss.self_modulate = old_tint
	await RenderingServer.frame_post_draw
	var parent_only: Image = get_viewport().get_texture().get_image()
	# The upper torso is below the name/bar and above the ground shadow. Bosses
	# are outside weakpoint windows here, so no parent UI should touch this area.
	var bounds: Rect2 = boss.body_bounds
	var local_area := Rect2(bounds.position + bounds.size * Vector2(0.30, 0.27), bounds.size * Vector2(0.40, 0.25))
	var canvas_transform: Transform2D = boss.get_global_transform_with_canvas()
	var start: Vector2 = canvas_transform * local_area.position
	var end: Vector2 = canvas_transform * local_area.end
	var pixels := Rect2i(Vector2i(start.ceil()), Vector2i((end - start).floor()))
	pixels = pixels.intersection(Rect2i(Vector2i.ZERO, baseline.get_size()))
	var changed: int = 0
	for y: int in range(pixels.position.y, pixels.end.y):
		for x: int in range(pixels.position.x, pixels.end.x):
			if not baseline.get_pixel(x, y).is_equal_approx(parent_only.get_pixel(x, y)): changed += 1
	check(pixels.has_area() and changed == 0, label + " actual parent draw contains no second torso bitmap or fallback")
	body.show()
	await RenderingServer.frame_post_draw
	var full: Image = get_viewport().get_texture().get_image()
	var visible_pixels: int = 0
	for y: int in range(pixels.position.y, pixels.end.y):
		for x: int in range(pixels.position.x, pixels.end.x):
			if not full.get_pixel(x, y).is_equal_approx(parent_only.get_pixel(x, y)): visible_pixels += 1
	check(visible_pixels > 16, label + " intended shared body is actually visible in torso region")
	captures.append({"kind":"parent-body separation", "boss":label, "parent_torso_pixels":changed, "visible_body_pixels":visible_pixels})

func _check_reconfigure() -> void:
	var boss := _spawn("BO01")
	var existing: Node2D = boss.body_visual
	check(boss.configure_boss("BO04", 0, 6140), "ready boss accepts new final portrait")
	check(boss.body_visual == existing and existing.body_frame().texture == boss.body_texture, "ready reconfiguration reuses shared body and current art")
	check((existing.position - existing.body_offset).is_equal_approx(Vector2(0, boss.body_bounds.end.y)) and is_zero_approx(existing.body_frame().bounds.end.y), "ready reconfiguration preserves ground pivot")
	check(not boss.impact_anchor(Vector2.LEFT).is_empty(), "ready reconfiguration prepares replacement portrait contact mask")
	boss.free()

func _capture(id: String, stage: String, boss: BossActor) -> void:
	if DisplayServer.get_name() == "headless": return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK, "native screenshot directory")
	room.queue_redraw()
	room.camera.force_update_scroll()
	if is_instance_valid(boss): boss.queue_redraw()
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = OUTPUT.path_join(id + "_" + stage + ".png")
	check(image != null and not image.is_empty() and image.save_png(ProjectSettings.globalize_path(path)) == OK, id + " " + stage + " actual viewport captured")
	captures.append({"boss":id, "stage":stage, "path":path})
