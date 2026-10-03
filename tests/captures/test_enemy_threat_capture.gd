extends Node
## Native-speed AI evidence; no enemy HP/stat/AI/phase/timer changes.
## tools/test.ps1 -Suite enemy_threat_capture -Graphical -SkipImport

const OUTPUT := "res://artifacts/enemy_threat_capture"
var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var focus_enemy: Node2D
var observing := false
var mode := ""
var start_wall := 0
var start_elapsed := 0.0
var action: Dictionary = {}
var captures: Dictionary = {}
var samples: Array[Dictionary] = []
var damages: Array[Dictionary] = []
var reports: Array[Dictionary] = []
var expected_profiles: Dictionary = {}
var saw_execute_after_action := false
var saw_runtime_after_action := false

func _ready() -> void:
	call_deferred("run_capture")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ENEMY_THREAT_CAPTURE FAIL: " + label)

func stamp() -> Dictionary:
	return {"wall_seconds": (Time.get_ticks_msec() - start_wall) / 1000.0,
		"physics_seconds": snappedf(room.elapsed - start_elapsed, .00001),
		"physics_frame": Engine.get_physics_frames(), "render_frame": Engine.get_frames_drawn()}

func aim(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = room.get_canvas_transform() * room.to_global(at)
	event.global_position = event.position
	stage.push_input(event, true)

func runtime_counts(actor_id: int) -> Dictionary:
	var result: Dictionary = {}
	for group: String in ["jobs", "motions", "projectiles", "hazards", "visuals"]:
		var count := 0
		for item: Dictionary in room.enemy_skills.get(group):
			if int(item.get("owner_id", -1)) == actor_id: count += 1
		result[group] = count
	return result

func enemy_state(enemy: Node2D) -> Dictionary:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion(): return {"removed": true}
	return {"instance_id": enemy.get_instance_id(), "enemy_id": enemy.enemy_id,
		"level": enemy.enemy_level, "rank": enemy.rank, "hp": enemy.health.current,
		"max_hp": enemy.health.maximum, "alive": enemy.is_alive(),
		"position": [enemy.position.x, enemy.position.y], "phase": str(enemy.brain.phase),
		"state_time": enemy.state_time, "cycle": enemy.brain.cycle,
		"telegraph": enemy.brain.current_telegraph(), "runtime": runtime_counts(enemy.get_instance_id())}

func snapshot() -> Dictionary:
	var result := stamp()
	var enemies: Array[Dictionary] = []
	for enemy: Node2D in room.enemies.get_children(): enemies.append(enemy_state(enemy))
	var hero_effects: Array[String] = []
	for effect: Dictionary in room.player.get_node("HeroFeedback").effects:
		hero_effects.append(str(effect.kind))
	result.merge({"mode": mode, "player_hp": Game.run.hp if Game.run != null else 0,
		"player_position": [room.player.position.x, room.player.position.y],
		"resource": Game.run.resource if Game.run != null else 0,
		"hero_pose": str(room.player.get_meta("hero_visual_pose", "")),
		"hero_source": str(room.player.get_meta("hero_visual_source", "")),
		"hero_effects": hero_effects, "contact_events": room.impact_feedback.events.size(),
		"danger_layer": room.enemy_telegraphs.snapshot(), "enemies": enemies,
		"focus": enemy_state(focus_enemy)})
	return result

func on_damage(amount: float, enemy: Node2D) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"enemy_id": enemy.enemy_id, "instance_id": enemy.get_instance_id(),
		"amount": amount, "hp_after": enemy.health.current,
		"source": str(enemy.last_damage_context.get("skill_slot", enemy.last_damage_context.get("damage_source", ""))),
		"phase_at_damage": str(enemy.brain.phase), "position": [enemy.position.x, enemy.position.y]})
	damages.append(event)

func _process(_delta: float) -> void:
	if not observing or Game.run == null or not is_instance_valid(focus_enemy) or not focus_enemy.is_alive(): return
	aim(focus_enemy.position)
	if not action.is_empty() or not captures.has("locked"): return
	var tell: Dictionary = focus_enemy.brain.current_telegraph()
	var expected_kind: String = "ground_area" if mode == "independent_ground" else "melee"
	if str(tell.get("kind", "")) != expected_kind or not bool(tell.get("locked", false)) or float(tell.get("progress", 1.0)) > .30: return
	var attack_name: String = "basic" if mode == "crowd" else "f" if mode == "independent_ground" else "secondary"
	action = {"requested_at": stamp(), "action": attack_name, "before": snapshot(),
		"target_position": [focus_enemy.position.x, focus_enemy.position.y],
		"target_hp_before": focus_enemy.health.current, "player_hp_before": Game.run.hp,
		"frozen_origin": tell.get("origin", focus_enemy.position), "locked_progress": tell.get("progress", 0)}
	var accepted: bool = room.player.fire(room.player.position.direction_to(focus_enemy.position)) if attack_name == "basic" else room.player.cast_skill(attack_name, focus_enemy.position)
	action["accepted"] = accepted
	action["resource_after_commit"] = Game.run.resource
	check(accepted, mode + " real public " + attack_name + " accepted in observed lock window")

func save_in_memory(label: String, data: Dictionary) -> void:
	if captures.has(label): return
	# The rendered image is copied now; disk and PNG compression occur only after
	# the observation ends. No pause/freeze or custom time scale is used.
	captures[label] = {"image": stage.get_texture().get_image(), "sample": data.duplicate(true)}

func after_draw() -> void:
	if not observing or not is_instance_valid(room) or Game.run == null: return
	var data := snapshot()
	samples.append(data)
	if not is_instance_valid(focus_enemy) or not focus_enemy.is_alive(): return
	var tell: Dictionary = focus_enemy.brain.current_telegraph()
	var expected_kind: String = "ground_area" if mode == "independent_ground" else "melee"
	if str(tell.get("kind", "")) == expected_kind:
		if str(tell.get("phase", "")) == "telegraph" and float(tell.get("progress", 0)) >= .30:
			save_in_memory("tracking", data)
		if bool(tell.get("locked", false)) and float(tell.get("progress", 0)) >= .025:
			save_in_memory("locked", data)
	if not action.is_empty():
		saw_execute_after_action = saw_execute_after_action or str(focus_enemy.brain.phase) == "execute"
		var active: Dictionary = runtime_counts(focus_enemy.get_instance_id())
		saw_runtime_after_action = saw_runtime_after_action or int(active.hazards) > 0 or int(active.projectiles) > 0 or int(active.motions) > 0
		var before: Array = action.target_position
		var displacement: float = focus_enemy.position.distance_to(Vector2(before[0], before[1]))
		if mode == "melee_cancel" and displacement >= 28.0 and focus_enemy.health.current < float(action.target_hp_before) and str(focus_enemy.brain.phase) == "recovery" and tell.is_empty():
			save_in_memory("pushed_recovery", data)
		if mode == "independent_ground" and displacement >= 28.0:
			if str(focus_enemy.brain.phase) == "locked" and not tell.is_empty(): save_in_memory("pushed_still_locked", data)
			if int(active.hazards) > 0 or str(focus_enemy.brain.phase) == "execute": save_in_memory("ground_still_releases", data)
	if mode == "crowd" and data.danger_layer.size() >= 2 and "swing" in data.hero_effects and int(data.contact_events) > 0:
		save_in_memory("danger_and_real_player_hit", data)

func fixture(next_mode: String) -> bool:
	mode = next_mode
	check(Game.new_profile() and Game.start_demo("CH01", 0), mode + " genuine Lv8 demo starts with normal gear and resources")
	if Game.run == null: return false
	check(Game.run.level == 8 and Game.run.hero_id == "CH01", mode + " real demo is level eight hammer")
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	stage.add_child(room)
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(1400, 900)
	room.release_gate = false
	room.input_blocked = false
	room.combat_audio.audible = false
	check(is_instance_valid(room.get("enemy_telegraphs")) and room.enemy_telegraphs.has_method("snapshot"), mode + " production danger layer exists")
	if not is_instance_valid(room.get("enemy_telegraphs")): return false
	check(room.enemy_telegraphs.z_index == 5 and room.enemy_telegraphs.z_index > room.impact_feedback.z_index and room.enemy_telegraphs.z_index > room.enemy_skills.z_index, mode + " danger layer is above actor/contact/released-skill layers")
	var definitions: Array = []
	match mode:
		"melee_cancel": definitions = [["M01", 20, Vector2(72, 0)]]
		"independent_ground": definitions = [["M11", 8, Vector2(80, 0)]]
		"crowd": definitions = [["M01", 8, Vector2(78, 0)], ["M02", 8, Vector2(190, -110)], ["M11", 8, Vector2(265, 105)]]
	expected_profiles.clear()
	for index in definitions.size():
		var spec: Array = definitions[index]
		var enemy: Node2D = room.spawn_enemy(room.player.position + spec[2], str(spec[0]), int(spec[1]))
		if index == 0: focus_enemy = enemy
		expected_profiles[enemy.get_instance_id()] = enemy.profile.duplicate(true)
		check(enemy.health.maximum == float(enemy.profile.max_hp) and not enemy.training_ai_disabled and enemy.rank == "normal", mode + " " + enemy.enemy_id + " retains natural profile health and active AI")
		enemy.health.damaged.connect(on_damage.bind(enemy))
	seed(41827)
	await get_tree().physics_frame
	await get_tree().process_frame
	aim(focus_enemy.position)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(room.player.aim_direction.dot(room.player.position.direction_to(focus_enemy.position)) > .99 and room.camera.zoom == Vector2(.85, .85) and Engine.time_scale == 1.0, mode + " real local pointer, normal zoom and time scale")
	action = {}; captures = {}; samples = []; damages = []
	saw_execute_after_action = false; saw_runtime_after_action = false
	start_wall = Time.get_ticks_msec(); start_elapsed = room.elapsed
	observing = true
	return true

func validate_progress() -> void:
	var previous: Dictionary = {}
	var transitions := 0
	var monotonic := true
	for sample: Dictionary in samples:
		for entry: Dictionary in sample.danger_layer:
			var data: Dictionary = entry.data
			if int(entry.actor_id) != focus_enemy.get_instance_id(): continue
			var focus: Dictionary = sample.focus
			var key: String = str(focus.get("cycle", -1)) + ":" + str(data.get("stage", -1))
			var progress: float = float(data.get("release_progress", -1))
			if previous.get("key", "") == key:
				monotonic = monotonic and progress + .00001 >= float(previous.progress)
				if not bool(previous.locked) and bool(data.get("locked", false)): transitions += 1
			previous = {"key": key, "progress": progress, "locked": data.get("locked", false)}
	check(monotonic and transitions > 0, mode + " rendered tell-to-lock progress remains continuous without restart")

func finish_observation() -> void:
	observing = false
	check(captures.has("tracking") and captures.has("locked"), mode + " actual tracking and locked render frames captured")
	check(not action.is_empty() and bool(action.get("accepted", false)), mode + " public counter action actually occurred")
	var alive: bool = is_instance_valid(focus_enemy) and focus_enemy.is_alive()
	check(alive, mode + " focus enemy naturally survives capture without HP override")
	if alive:
		validate_progress()
		for enemy: Node2D in room.enemies.get_children():
			if expected_profiles.has(enemy.get_instance_id()):
				check(enemy.profile == expected_profiles[enemy.get_instance_id()] and enemy.health.maximum == float(enemy.profile.max_hp) and not enemy.training_ai_disabled, mode + " immutable authored profile and active AI remain intact " + enemy.enemy_id)
	if mode == "melee_cancel":
		check(captures.has("pushed_recovery") and not saw_execute_after_action and not saw_runtime_after_action, "actual secondary knockback cancels the locked melee instead of releasing at stale origin")
		check(Game.run != null and not action.is_empty() and is_equal_approx(Game.run.hp, float(action.get("player_hp_before", -1))), "cancelled melee did not deal old-origin damage during its former release window")
	elif mode == "independent_ground":
		check(captures.has("pushed_still_locked") and captures.has("ground_still_releases") and saw_runtime_after_action, "actual F knockback leaves the independent locked ground attack committed")
	else:
		check(captures.has("danger_and_real_player_hit"), "multiple actual enemy warnings coexist with a real hammer strike and confirmed contact")
	var files: Array[Dictionary] = []
	for label: String in captures:
		var filename: String = mode + "_" + label + ".png"
		var bitmap: Image = captures[label].image
		check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png(OUTPUT.path_join(filename)) == OK, "save native framebuffer " + filename)
		files.append({"path": filename, "sample": captures[label].sample})
	reports.append({"mode": mode, "status": "observed" if not files.is_empty() else "missing_evidence",
		"stats": Game.run.stats.duplicate(true) if Game.run != null else {}, "profiles": expected_profiles,
		"action": action, "damage_events": damages, "captures": files, "all_render_samples": samples,
		"saw_execute_after_action": saw_execute_after_action, "saw_runtime_after_action": saw_runtime_after_action,
		"focus_final": enemy_state(focus_enemy), "player_hp_final": Game.run.hp if Game.run != null else 0})
	print("ENEMY_THREAT_NATIVE mode=", mode, " captures=", captures.keys(), " action=", action.get("action", "none"), " survived=", alive)
	captures.clear()

func run_capture() -> void:
	if not str(Game.profile_path).contains("test_enemy_threat_capture") or DisplayServer.get_name() == "headless":
		push_error("Enemy threat capture requires graphical renderer and isolated test_enemy_threat_capture profile")
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(90).timeout.connect(func(): push_error("Enemy threat capture timed out"); get_tree().quit(1))
	for name: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(name): InputMap.add_action(name)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var display := TextureRect.new()
	display.texture = stage.get_texture()
	display.size = Vector2(1280, 720)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	RenderingServer.frame_post_draw.connect(after_draw)
	for scenario: String in ["melee_cancel", "independent_ground", "crowd"]:
		if not await fixture(scenario):
			get_tree().quit(1)
			return
		var deadline: int = Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < deadline and Game.run != null:
			await get_tree().process_frame
			if not action.is_empty() and room.elapsed - start_elapsed > float(action.requested_at.physics_seconds) + .85: break
		finish_observation()
		await room.combat_audio.wait_for_cleanup()
		room.free()
		if Game.run != null: Game.finish_run("abandoned")
		await get_tree().process_frame
	RenderingServer.frame_post_draw.disconnect(after_draw)
	var file := FileAccess.open(AssetCatalog.resolve(OUTPUT.path_join("native_capture.json")), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures,
		"method": "Controlled native-speed fixture, not natural progression or balance. Real CH01 Lv8 demo API keeps standard gear, crit, damage, HP and resource rules. Natural normal M01 Lv20 is used to survive the right-click counter (waits past its authored lunge for kind=melee); natural M11 Lv8 receives lower-damage public F for independent ground persistence. Crowd is normal M01/M02/M11 Lv8. Only initial actor positions and fixed spawn composition are configured; random spawning/obstacle layout disabled. No enemy HP/stat/AI/brain phase/timer changes, fake hits, manual ticks, pause or slow motion. Production player reads official standalone SubViewport pointer, camera .85. Rendered brain/layer snapshots and actual damage are recorded. First actual framebuffer per condition kept in memory; PNG compression only after observation ends. Missed conditions or natural deaths fail honestly.",
		"reports": reports}, "\t"))
	file.close()
	print("ENEMY_THREAT_CAPTURE_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
