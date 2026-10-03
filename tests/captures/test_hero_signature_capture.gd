extends Node
## Graphical-only native-speed proof for the two approved six-pose skills.
## No animation/physics clocks, pose states or damage callbacks are fabricated.
## tools/test.ps1 -Suite hero_signature_capture -Graphical -SkipImport

const Atlas = preload("res://scripts/presentation/characters/hero_skill_atlas.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const OUTPUT := "res://artifacts/hero_signature_capture"
var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var victim: Node2D
var hero := ""
var slot := ""
var bank := ""
var expected_source := ""
var metadata_path := ""
var clip: Dictionary = {}
var tracking := ""
var start_tick := 0
var start_wall := 0
var start_elapsed := 0.0
var samples: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var rendered_frames: Dictionary = {}
var flight_capture: Dictionary = {}
var records: Array[Dictionary] = []
var expected_frames: Array[String] = []

func _ready() -> void:
	call_deferred("run_capture")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HERO_SIGNATURE_CAPTURE FAIL: " + description)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func aim(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = room.get_canvas_transform() * room.to_global(at)
	event.global_position = event.position
	stage.push_input(event, true)

func elapsed_snapshot() -> Dictionary:
	return {"physics_tick": Engine.get_physics_frames() - start_tick,
		"physics_seconds": snappedf(room.elapsed - start_elapsed, .00001),
		"wall_seconds": (Time.get_ticks_msec() - start_wall) / 1000.0}

func nodes_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for deployment: Node2D in get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.room == room and deployment.kind == "node":
			result.append({"instance_id": deployment.get_instance_id(), "alive": deployment.is_alive(),
				"active": deployment.is_active(), "charge": deployment.resonance_charge,
				"position": [deployment.position.x, deployment.position.y], "age": deployment.elapsed})
	return result

func projectiles_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for projectile: Node2D in room.projectiles.get_children():
		if projectile.is_queued_for_deletion(): continue
		var shown: Vector2 = projectile.visual_position()
		var visible_direction: Vector2 = projectile.visual_direction()
		result.append({"instance_id": projectile.get_instance_id(), "source": str(projectile.source),
			"physical_position": [projectile.position.x, projectile.position.y],
			"visual_position": [shown.x, shown.y],
			"visual_direction": [visible_direction.x, visible_direction.y],
			"visual_scale": projectile.visual_draw_scale(), "visual_trail_fraction": projectile.visual_trail_fraction(),
			"visual_path": projectile.visual_path_snapshot(), "distance_left": projectile.distance_left})
	return result

func on_damage(amount: float) -> void:
	if tracking.is_empty(): return
	var event: Dictionary = elapsed_snapshot()
	event.merge({"mode": tracking, "amount": amount, "hp_after": victim.health.current,
		"source": str(victim.last_damage_context.get("skill_slot", victim.last_damage_context.get("damage_source", ""))),
		"damage_source": str(victim.last_damage_context.get("damage_source", "")),
		"attack_id": str(victim.last_damage_context.get("attack_id", ""))})
	damage_events.append(event)

func after_draw() -> void:
	if tracking.is_empty() or not is_instance_valid(room): return
	var player: Node2D = room.player
	var index: int = int(player.get_meta("hero_visual_frame", -1))
	var source: String = str(player.get_meta("hero_visual_source", ""))
	var sample: Dictionary = elapsed_snapshot()
	sample.merge({"mode": tracking, "render_frame": Engine.get_frames_drawn(),
		"source": source, "frame_index": index, "bank": str(player.get_meta("hero_visual_bank", "")),
		"pose": str(player.get_meta("hero_visual_pose", "")),
		"pose_state": player.get_node("HeroFeedback").pose_state(),
		"actual_foot_local": player.get_meta("hero_foot_local", Vector2.INF),
		"target_hp": victim.health.current, "resource": Game.run.resource,
		"cooldown": float(player.cooldowns.get(slot, 0)), "hitstop": player.visual_hitstop,
		"ability_busy": player.abilities.busy(), "nodes": nodes_snapshot(), "projectiles": projectiles_snapshot()})
	samples.append(sample)
	if tracking == "signature" and source == expected_source and str(sample.bank) == bank and index >= 0 and index < 6:
		if not rendered_frames.has(index):
			# Only the first real rendered occurrence is read back. Keep pixels in
			# memory; PNG compression waits until the automatic sequence is over.
			rendered_frames[index] = {"image": stage.get_texture().get_image(), "sample": sample.duplicate(true)}
	elif tracking == "basic" and flight_capture.is_empty():
		for projectile: Dictionary in sample.projectiles:
			if projectile.source != "primary": continue
			var at := Vector2(projectile.physical_position[0], projectile.physical_position[1])
			if at.distance_to(player.position) >= 60.0 and at.distance_to(victim.position) > 35.0:
				flight_capture = {"image": stage.get_texture().get_image(), "sample": sample.duplicate(true)}
				break

func approved_clip() -> bool:
	metadata_path = "asset://heroes/%s_%s_%s_v1.json" % [hero, slot, bank]
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(metadata_path))) if FileAccess.file_exists(AssetCatalog.resolve(metadata_path)) else null
	var enabled: bool = metadata is Dictionary and typeof(metadata.get("enabled")) == TYPE_BOOL and metadata.enabled
	check(enabled, hero + " " + bank + " metadata is explicitly enabled")
	if not enabled:
		records.append({"hero": hero, "slot": slot, "bank": bank, "metadata": metadata_path,
			"status": "failed_missing_or_disabled", "captured_frame_count": 0,
			"missing_frame_indices": [0, 1, 2, 3, 4, 5]})
		return false
	expected_source = str(metadata.texture)
	clip = Atlas.load_clip(metadata_path)
	check(not clip.is_empty(), hero + " " + bank + " approved metadata loads six real poses")
	if clip.is_empty():
		records.append({"hero": hero, "slot": slot, "bank": bank, "metadata": metadata_path,
			"status": "failed_invalid_enabled_metadata", "missing_frame_indices": [0, 1, 2, 3, 4, 5]})
		return false
	expected_frames.clear()
	for item: Dictionary in metadata.frames: expected_frames.append(str(item.name))
	for frame: Dictionary in clip.frames.values():
		check(is_equal_approx(float(frame.body_height), 88.0) and frame.anchors.foot == Vector2(0, 8), hero + " " + bank + " authored anatomy is 88 world units with fixed foot")
	return true

func fixture() -> void:
	check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(), hero + " " + bank + " isolated run")
	Game.run.level = 8
	Game.run.stats = Resolver.resolve(hero, 8, {}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.relics.clear()
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	stage.add_child(room)
	for child: Node in room.enemies.get_children(): child.free()
	room.player.position = Vector2(1400, 900)
	room.release_gate = false
	room.input_blocked = false
	room.combat_audio.audible = false
	var direction := Vector2(1.0, .7 if bank == "front" else -.7).normalized()
	victim = room.spawn_enemy(room.player.position + direction * (360.0 if hero == "CH02" else 175.0), "M01", 8, {"reward_enabled": false})
	victim.health.reset(10000.0)
	victim.training_ai_disabled = true
	victim.state = &"chase"
	victim.health.damaged.connect(on_damage)
	await frames(2)
	aim(victim.position)
	await frames(2)
	await RenderingServer.frame_post_draw
	check(room.player.aim_direction.dot(direction) > .99, hero + " " + bank + " production player reads local pointer")
	check(room.player.is_physics_processing() and room.player.can_process() and Engine.time_scale == 1.0, hero + " " + bank + " uses automatic unscaled physics")
	check(room.camera.zoom.is_equal_approx(Vector2(.85, .85)), hero + " " + bank + " normal camera zoom .85")

func wait_idle(timeout_seconds: float = 2.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while room.player.abilities.busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not room.player.abilities.busy()

func prepare_node() -> Dictionary:
	var direction: Vector2 = room.player.position.direction_to(victim.position)
	var node_at: Vector2 = room.player.position + direction * 100.0
	check(room.player.cast_skill("secondary", node_at), bank + " real secondary starts node deployment")
	check(await wait_idle(), bank + " node deployment completes through automatic physics")
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		var state: Array[Dictionary] = nodes_snapshot()
		if state.size() == 1 and state[0].active: break
		await get_tree().process_frame
	var before_q: Array[Dictionary] = nodes_snapshot()
	check(before_q.size() == 1 and before_q[0].active and before_q[0].charge == 0, bank + " one uncharged real node becomes active")
	aim(victim.position)
	await frames(1)
	check(room.player.cast_skill("q", victim.position), bank + " real Q begins charging shot")
	check(await wait_idle(), bank + " Q timeline completes naturally")
	deadline = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		var state: Array[Dictionary] = nodes_snapshot()
		if state.size() == 1 and int(state[0].charge) > 0 and room.projectiles.get_child_count() == 0: break
		await get_tree().process_frame
	var after_q: Array[Dictionary] = nodes_snapshot()
	check(after_q.size() == 1 and int(after_q[0].charge) > 0, bank + " actual Q flight charged the real node")
	return {"before_q": before_q, "after_q": after_q, "resource": Game.run.resource,
		"target_hp": victim.health.current, "release_events": room.player.get_node("HeroFeedback").release_events.duplicate(true)}

func begin_observation(mode: String) -> void:
	samples.clear()
	damage_events.clear()
	rendered_frames.clear()
	flight_capture.clear()
	start_tick = Engine.get_physics_frames()
	start_wall = Time.get_ticks_msec()
	start_elapsed = room.elapsed
	tracking = mode

func wait_native(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while room.elapsed - start_elapsed < seconds and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	tracking = ""

func record_signature(preparation: Dictionary) -> void:
	var feedback_node: Node = room.player.get_node("HeroFeedback")
	var release_start: int = feedback_node.release_events.size()
	var resource_before: float = Game.run.resource
	var hp_before: float = victim.health.current
	var nodes_before: Array[Dictionary] = nodes_snapshot()
	begin_observation("signature")
	var committed: bool = room.player.cast_skill(slot, victim.position)
	check(committed, hero + " " + bank + " signature cast commits through public API")
	var resource_committed: float = Game.run.resource
	var cooldown_committed: float = float(room.player.cooldowns[slot])
	await wait_native(1.25)
	var final_releases: Array = feedback_node.release_events.slice(release_start)
	var matching_releases := 0
	for event: Dictionary in final_releases:
		if str(event.slot) == slot: matching_releases += 1
	check(matching_releases == 1, hero + " " + bank + " releases exactly once")
	check(victim.health.current < hp_before, hero + " " + bank + " actual skill contact damages real enemy")
	check(not room.player.abilities.busy(), hero + " " + bank + " real skill naturally finishes recovery")
	if hero == "CH02":
		var projectile_hits := 0
		for hit: Dictionary in damage_events:
			if str(hit.source) == "secondary": projectile_hits += 1
		check(projectile_hits == 1, bank + " one real secondary projectile collision confirms one hit")
	if hero == "CH03":
		var detonation_hits := 0
		for hit: Dictionary in damage_events:
			if str(hit.source) == "node_detonation": detonation_hits += 1
		check(nodes_before.size() == 1 and nodes_snapshot().is_empty() and detonation_hits > 0, bank + " F really consumes the charged node and applies detonation damage")
	var missing: Array[int] = []
	var files: Array[String] = []
	var captured_samples: Array[Dictionary] = []
	for index in 6:
		if not rendered_frames.has(index):
			missing.append(index)
			continue
		var filename: String = "%s_%s_%s_%02d_%s.png" % [hero, slot, bank, index, expected_frames[index]]
		var bitmap: Image = rendered_frames[index].image
		check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png(OUTPUT.path_join(filename)) == OK, "save normal-speed first real frame " + filename)
		files.append(filename)
		captured_samples.append(rendered_frames[index].sample)
	check(not rendered_frames.is_empty(), hero + " " + bank + " renderer consumed enabled signature source rather than fallback")
	# Short poses missed by real native rendering are recorded, never reconstructed.
	var record: Dictionary = {"hero": hero, "slot": slot, "bank": bank, "metadata": metadata_path,
		"expected_source": expected_source, "status": "complete" if missing.is_empty() else "partial_native_sampling",
		"captured_frame_count": rendered_frames.size(), "missing_frame_indices": missing, "files": files,
		"captured_samples": captured_samples, "all_render_samples": samples.duplicate(true),
		"preparation": preparation, "world_before": {"nodes": nodes_before, "target_hp": hp_before},
		"world_after": {"nodes": nodes_snapshot(), "target_hp": victim.health.current, "projectiles": projectiles_snapshot()},
		"matching_release_count": matching_releases, "release_events": final_releases,
		"actual_damage": damage_events.duplicate(true), "resource_before": resource_before,
		"resource_after_commit": resource_committed, "resource_final": Game.run.resource,
		"cooldown_after_commit": cooldown_committed, "cooldown_final": room.player.cooldowns[slot],
		"world_body_height": 88.0, "camera_zoom": [room.camera.zoom.x, room.camera.zoom.y],
		"stats": Game.run.stats.duplicate(true), "elapsed": elapsed_snapshot()}
	records.append(record)
	print("HERO_SIGNATURE_NATIVE hero=", hero, " slot=", slot, " bank=", bank, " frames=", rendered_frames.size(), " missing=", missing, " releases=", matching_releases)
	rendered_frames.clear()

func record_basic_flight() -> void:
	aim(victim.position)
	await frames(2)
	var before_events: int = room.player.get_node("HeroFeedback").basic_events
	var hp_before: float = victim.health.current
	begin_observation("basic")
	check(room.player.fire(room.player.position.direction_to(victim.position)), hero + " " + bank + " normal basic fires through public API")
	await wait_native(.9)
	check(room.player.get_node("HeroFeedback").basic_events == before_events + 1 and victim.health.current < hp_before, hero + " " + bank + " actual basic projectile hits once fired")
	var filename := ""
	if not flight_capture.is_empty():
		filename = "%s_basic_%s_flight.png" % [hero, bank]
		var bitmap: Image = flight_capture.image
		check(bitmap.save_png(OUTPUT.path_join(filename)) == OK, "save actual basic projectile flight " + filename)
	records.append({"hero": hero, "slot": "basic", "bank": bank, "status": "captured" if not flight_capture.is_empty() else "no_native_flight_frame",
		"file": filename, "captured_sample": flight_capture.get("sample", {}), "all_render_samples": samples.duplicate(true),
		"actual_damage": damage_events.duplicate(true), "hp_before": hp_before, "hp_after": victim.health.current})
	flight_capture.clear()

func run_capture() -> void:
	if not str(Game.profile_path).contains("test_hero_signature_capture"):
		push_error("Refusing non-isolated hero signature profile")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Hero signature capture needs graphical rendering; headless cannot certify native rendered poses")
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(90).timeout.connect(func(): push_error("Hero signature capture timed out"); get_tree().quit(1))
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280, 720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	RenderingServer.frame_post_draw.connect(after_draw)
	for next_hero: String in ["CH02", "CH03"]:
		hero = next_hero
		slot = "secondary" if hero == "CH02" else "f"
		for next_bank: String in ["front", "back"]:
			bank = next_bank
			if not approved_clip(): continue
			await fixture()
			var preparation: Dictionary = {}
			if hero == "CH03": preparation = await prepare_node()
			aim(victim.position)
			await frames(2)
			await record_signature(preparation)
			await record_basic_flight()
			await room.combat_audio.wait_for_cleanup()
			room.free()
			Game.finish_run("abandoned")
			await frames(1)
	RenderingServer.frame_post_draw.disconnect(after_draw)
	var output := FileAccess.open(AssetCatalog.resolve(OUTPUT.path_join("native_capture.json")), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures,
		"method": "Native automatic physics and actual render frames, speed 1.0. Real room/player/skills, local SubViewport pointer, real 10000HP M01 Lv8 with AI disabled. Hero Lv8 no equipment/crit/relics, resource initialized once to100 before preparation; no timed resource refill or cooldown reset. No random spawning/geometry. CH03 secondary deploys an active node, actual Q charges it, then F detonates it. Per-render hero source/frame/pose and world state are recorded. First occurrence of each six-pose frame is read to memory; all PNG compression happens after the sequence. Missing short frames are explicitly listed and never fabricated. Missing/disabled/invalid manifests fail rather than accepting legacy fallback. Optional ordinary basic projectile flight uses the same native pipeline; physical and display positions are both reported.",
		"records": records}, "\t"))
	output.close()
	print("HERO_SIGNATURE_CAPTURE_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
