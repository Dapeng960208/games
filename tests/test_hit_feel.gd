extends SceneTree
## Real room contact pipeline, isolated profile and silent real audio scheduler.
## Run via tools/test.ps1 -Suite hit_feel -SkipImport -SkipRestart.

var game: Node
var room: Node2D
var room_scene: PackedScene
var resolver: Script
var checks: int = 0
var failures: int = 0
var contact_serial: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HIT FEEL FAIL: " + description)

func fixture(hero: String = "CH01", reduced: bool = false) -> void:
	paused = false
	if is_instance_valid(room):
		room.free()
	game.profile.settings["reduced_fx"] = reduced
	game.profile.settings["camera_shake"] = true # This suite verifies explicitly enabled contact motion.
	game.profile.settings["muted"] = false
	game.profile.settings["sfx_muted"] = false
	game.profile.settings["master_volume"] = 1.0
	game.profile.settings["sfx_volume"] = 0.85
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = resolver.resolve(hero, 8, {}, {})
	game.run.stats["crit_chance"] = 0.0
	game.run.stats["true_damage_bonus"] = 0.0
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430, 350)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	room.combat_audio.set_process(false)
	room.impact_feedback.set_process(false)
	room.camera.set_physics_process(false)
	room.impact_feedback.clear_feedback()

func dummy(id: String = "M01", offset: Vector2 = Vector2(60, 0)) -> Node2D:
	var target: Node2D = room.spawn_enemy(room.player.position + offset, id)
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	return target

func hit(target: Node2D, source: StringName = &"primary", critical: bool = false) -> void:
	contact_serial += 1
	var key: String = "hit-feel:" + str(contact_serial)
	if critical:
		room.crit_rolls[key] = true
	room.resolve_direct_hit(target, 50.0, source, "", 0.0, Vector2.RIGHT,
		{"attack_id":key, "root_event_id":key, "equipment_eligible":false})

func contact_events() -> Array:
	var result: Array = []
	for event: Dictionary in room.impact_feedback.events:
		if event.kind == "hit":
			result.append(event)
	return result

func snapshot() -> Dictionary:
	return {"feedback":room.player.get_node("HeroFeedback").impact_events,
		"vfx":room.impact_feedback.accepted_events,
		"audio":room.combat_audio.accepted_events,
		"camera":room.camera.impact_stats().started,
		"stop":room.player.visual_hitstop}

func same_contact(before: Dictionary) -> bool:
	return snapshot() == before

func settle(target: Node2D = null) -> void:
	room.elapsed += 1.0
	room.player.visual_hitstop = 0.0
	room.camera._physics_process(1.0)
	room.combat_audio.advance(1.0)
	room.impact_feedback.advance(1.0)
	if is_instance_valid(target):
		for _step in 4:
			target.body_visual.advance(0.1)

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_hit_feel"):
		push_error("Refusing non-test profile; use test_hit_feel in profile path")
		quit(2)
		return
	room_scene = load("res://scenes/room.tscn")
	resolver = load("res://scripts/combat/stat_resolver.gd")
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated real run starts")
	if game.run == null:
		quit(1)
		return
	_test_hero_material_contacts()
	_test_camera_comfort()
	_test_miss_and_immunity()
	_test_shield_and_critical()
	_test_cleave_and_periodic_damage()
	_test_deployed_contacts()
	_test_contact_priority()
	_test_gunner_finisher()
	_test_reduced_and_pause()
	_test_bounds_and_cleanup()
	if DisplayServer.get_name() != "headless":
		await _capture_hero_contacts()
	paused = false
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("HIT FEEL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_camera_comfort() -> void:
	fixture("CH01")
	game.profile.settings.camera_shake = false
	game.changed.emit()
	var target: Node2D = dummy()
	var health_before: float = target.health.current
	for contact: int in 24:
		hit(target, &"secondary")
		room.camera._physics_process(.016)
		check(room.camera.offset == Vector2.ZERO and room.camera.impact_stats().started == 0, "comfort setting keeps real repeated heavy hits from moving the world")
		settle(target)
	check(target.health.current < health_before and room.combat_audio.accepted_events == 24, "comfort setting preserves actual damage and material hit sound")

func _test_hero_material_contacts() -> void:
	var pauses: Dictionary = {}
	var heroes: Array[String] = ["CH01", "CH02", "CH03"]
	var monsters: Array[String] = ["M01", "M10", "M31"]
	var materials: Array[String] = ["metal", "organic", "stone"]
	for index in heroes.size():
		fixture(heroes[index])
		var target: Node2D = dummy(monsters[index])
		var before: float = target.health.current
		if heroes[index] == "CH01":
			room.player.fire(Vector2.RIGHT)
			room.player._tick_attack(0.5)
		else:
			room.player.fire(Vector2.RIGHT)
			var projectile: Node2D = room.projectiles.get_child(0)
			room.resolve_weapon_hit(projectile, target)
		var events: Array = contact_events()
		check(target.health.current < before and events.size() == 1 and room.player.get_node("HeroFeedback").impact_events == 1, heroes[index] + " real basic damage confirms one contact")
		check(events.size() == 1 and str(events[0].material) == materials[index] and str(events[0].hero_id) == heroes[index] and Vector2(events[0].at).y < target.position.y - 8.0, heroes[index] + " contact carries real enemy material and body position")
		var expected: AudioStreamWAV = room.combat_audio.stream_for(heroes[index], "impact", 0, materials[index])
		var material_played: bool = false
		for voice: AudioStreamPlayer in room.combat_audio._players:
			material_played = material_played or voice.stream == expected
		check(material_played and target.body_visual.flash_strength > 0.0 and room.camera.impact_stats().started == 1, heroes[index] + " confirmed contact reaches material audio, body recoil and one camera pulse")
		pauses[heroes[index]] = room.player.visual_hitstop
		settle(target)
		hit(target, &"secondary")
		var heavy: Array = contact_events()
		check(heavy.size() == 1 and bool(heavy[0].heavy) and room.player.visual_hitstop > float(pauses[heroes[index]]) and float(target.body_visual._impact_duration) > 0.18, heroes[index] + " heavy hit has longer recovery and presentation pause")
	check(float(pauses.CH01) > float(pauses.CH03) and float(pauses.CH03) > float(pauses.CH02) and float(pauses.CH02) > 0.0, "hammer, crystal and gun basic contacts have distinct pause weights")

func _test_miss_and_immunity() -> void:
	fixture()
	var target: Node2D = dummy()
	room.player.aim_direction = Vector2.LEFT
	room.player.fire(Vector2.LEFT)
	var before: Dictionary = snapshot()
	room.player._tick_attack(0.5)
	check(same_contact(before), "a real hammer swing into empty space adds no contact audio, camera, flash or hit pause")
	check(target.health.current == target.health.maximum and contact_events().is_empty(), "whiff leaves enemy health and world contact layer untouched")
	settle(target)
	target.apply_status("invulnerable", 1.0, 3.0)
	before = snapshot()
	hit(target, &"secondary")
	check(same_contact(before) and target.health.current == target.health.maximum, "immune target consumes no health and produces no contact feedback")
	check(target.body_visual.flash_strength == 0.0 and float(target.body_visual._impact_duration) == 0.0, "immune target never enters the confirmed body reaction")

func _test_shield_and_critical() -> void:
	fixture("CH02")
	var target: Node2D = dummy()
	target.status.grant_guard(100.0, 5.0, "test", target.health.maximum)
	var before: float = target.health.current
	hit(target)
	check(target.health.current == before and target.status.shield() < 100.0, "real shield absorbs damage while health stays unchanged")
	check(contact_events().size() == 1 and room.combat_audio.accepted_events == 1 and target.body_visual.flash_strength > 0.0, "shield contact still has audio, a body reaction and a visible impact")
	settle(target)
	hit(target, &"primary", true)
	var events: Array = contact_events()
	check(events.size() == 1 and bool(events[0].critical) and bool(events[0].heavy), "committed critical roll upgrades the original contact to heavy")
	check(room.player.visual_hitstop > 0.03 and room.camera.impact_stats().strength > 0.65, "critical contact increases gun pause and camera weight")

func _test_cleave_and_periodic_damage() -> void:
	fixture()
	var victims: Array = [dummy("M01", Vector2(65,-25)), dummy("M10", Vector2(85,0)), dummy("M31", Vector2(65,25))]
	room.strike_area(room.player.position, 150.0, 50.0, &"secondary", "", 0.0, Vector2.RIGHT, 160.0)
	var all_reacted: bool = true
	for target: Node2D in victims:
		all_reacted = all_reacted and target.health.current < target.health.maximum and target.body_visual.flash_strength > 0.0
	check(all_reacted and contact_events().size() == 3, "real three-target cleave gives every damaged body its own reaction and contact point")
	check(room.combat_audio.accepted_events == 1 and room.camera.impact_stats().started == 1, "one simultaneous cleave yields only one accepted impact sound and camera pulse")
	check(room.player.get_node("HeroFeedback").impact_events == 3 and room.player.visual_hitstop <= 0.085, "per-target animation callbacks do not accumulate hit pause")
	var target: Node2D = victims[0]
	settle(target)
	var before: Dictionary = snapshot()
	var health_before: float = target.health.current
	target.apply_status("burn", 50.0, 3.0)
	target.tick_statuses(1.0)
	check(target.health.current < health_before and same_contact(before), "actual burn tick damages but does not retrigger contact audio, camera or animation callbacks")
	check(contact_events().is_empty() and target.body_visual.flash_strength == 0.0, "periodic damage retains a number without a confirmed hit burst or body flash")

func _test_reduced_and_pause() -> void:
	fixture("CH03", true)
	var target: Node2D = dummy("M31")
	hit(target, &"f")
	var events: Array = contact_events()
	check(events.size() == 1 and bool(events[0].reduced) and bool(events[0].heavy) and room.combat_audio.accepted_events == 1, "reduced effects preserves a crystal detonation contact mark and sound")
	check(room.camera.impact_stats().started == 0 and room.camera.offset == Vector2.ZERO and room.player.visual_hitstop == 0.0, "reduced effects eliminates screen kick and visual hit pause")
	check(target.body_visual.flash_strength == 0.0 and target.body_visual.body_offset.length() < 6.0, "reduced effects uses restrained body recoil without bright flashing")
	var event_age: float = float(events[0].age)
	var recoil_age: float = target.body_visual._impact_elapsed
	paused = true
	room.impact_feedback.advance(0.2)
	target.body_visual.advance(0.2)
	room.camera._physics_process(0.2)
	room.combat_audio.advance(0.2)
	check(float(contact_events()[0].age) == event_age and target.body_visual._impact_elapsed == recoil_age, "pause freezes impact age and body recovery")
	check(room.combat_audio.active_voice_count() == 0 and not room.combat_audio.impact("CH03", true, "stone"), "paused audio stops existing voices and refuses new contact sound")
	paused = false
	settle(target)
	check(room.impact_feedback.events.is_empty(), "contact marks and damage numbers expire cleanly after resume")

func _test_deployed_contacts() -> void:
	fixture("CH03")
	var target: Node2D = dummy("M01", Vector2(110, 0))
	var started: bool = room.player.cast_skill("secondary", room.player.position + Vector2(40, 0))
	room.player.abilities.tick(0.5)
	var nodes: Array = []
	for deployment: Node2D in get_nodes_in_group("hero_deployments"):
		if deployment.room == room and deployment.kind == "node" and deployment.is_alive():
			nodes.append(deployment)
	check(started and nodes.size() == 1, "real resonator secondary creates the node used by the contact test")
	if nodes.size() != 1:
		return
	var node_cues: Array[String] = []
	room.combat_audio.cue_played.connect(func(cue: String) -> void: node_cues.append(cue))
	nodes[0].advance(1.56)
	check(node_cues == ["node_fire"], "actual node emission sounds once before its bolt has confirmed any contact")
	for projectile: Node in room.projectiles.get_children():
		if not projectile.is_queued_for_deletion():
			projectile._physics_process(0.15)
	var events: Array = contact_events()
	check(target.health.current < target.health.maximum and events.size() == 1 and str(events[0].source) == "node" and str(events[0].material) == "metal" and target.body_visual.flash_strength > 0.0, "actual node projectile collision carries metal contact and body reaction")
	check(node_cues == ["node_fire", "passive_impact"], "node firing sound and actual collision confirmation are separate accepted cues")
	var context: Dictionary = target.last_damage_context
	check(str(context.get("damage_source", "")) == "node" and not bool(context.get("equipment_eligible", true)) and not bool(context.get("original_basic", true)) and int(context.get("proc_depth", 0)) >= 1, "node contact preserves derived attribution and cannot trigger original-hit equipment")
	check(room.player.visual_hitstop == 0.0 and room.camera.impact_stats().started == 0, "automatic node fire does not pause the player or kick the camera")
	fixture("CH03")
	target = dummy("M31")
	started = room.player.cast_skill("ultimate", target.position)
	room.player.abilities.tick(0.81)
	var field: Node2D
	for deployment: Node2D in get_nodes_in_group("hero_deployments"):
		if deployment.room == room and deployment.kind == "field":
			field = deployment
	settle(target)
	var before: Dictionary = snapshot()
	var health_before: float = target.health.current
	var field_cues: Array[String] = []
	room.combat_audio.cue_played.connect(func(cue: String) -> void: field_cues.append(cue))
	if is_instance_valid(field):
		field.advance(1.0)
	events = contact_events()
	context = target.last_damage_context
	check(started and is_instance_valid(field) and target.health.current < health_before and events.size() == 1 and str(events[0].source) == "field" and str(context.get("damage_source", "")) == "field" and not bool(context.get("equipment_eligible", true)) and int(context.get("proc_depth", 0)) >= 1 and room.camera.impact_stats().started == before.camera and room.player.visual_hitstop == 0.0, "real resonance field tick confirms a derived contact without repeated player pause or camera kick")
	check(field_cues.count("field_pulse") == 1 and field_cues.count("passive_impact") == 1 and field_cues.size() == 2, "field pulse and actual passive hit confirmation both sound once; neither can substitute for the other")

func _test_contact_priority() -> void:
	fixture("CH03")
	var target: Node2D = dummy()
	room.resolve_derived_hit(target, 12.0, &"field", Vector2.RIGHT)
	var passive: Dictionary = contact_events().back().duplicate()
	var passive_recoil: float = target.body_visual._impact_strength
	hit(target)
	var direct: Dictionary = contact_events().back()
	check(bool(passive.passive) and not bool(direct.passive) and float(passive.radius) < float(direct.radius) and float(passive.duration) < float(direct.duration), "background field confirmation has a smaller, shorter mark than direct player contact")
	check(room.combat_audio.accepted_events == 2 and target.body_visual._impact_strength > passive_recoil, "direct basic hit after same-frame field retains its own sound and stronger body reaction")
	settle(target)
	hit(target)
	var light_pause: float = room.player.visual_hitstop
	room.elapsed += .01
	room.camera._physics_process(.01)
	room.combat_audio.advance(.01)
	target.body_visual.advance(.01)
	hit(target, &"secondary")
	var camera_state: Dictionary = room.camera.impact_stats()
	check(room.player.visual_hitstop > light_pause and camera_state.started == 2 and camera_state.boosted == 1 and is_equal_approx(float(camera_state.elapsed), .01), "light then heavy upgrades the existing camera pulse without restarting its clock")
	var heavy_strength: float = target.body_visual._impact_strength
	var heavy_pause: float = room.player.visual_hitstop
	var audio_before: int = room.combat_audio.accepted_events
	target.body_visual.advance(.02)
	var body_clock_before_passive: float = target.body_visual._impact_elapsed
	room.resolve_derived_hit(target, 12.0, &"node", Vector2.LEFT)
	check(target.body_visual._impact_heavy and target.body_visual._impact_strength == heavy_strength and is_equal_approx(float(target.body_visual._impact_elapsed), body_clock_before_passive), "a following passive node cannot erase the heavy reaction or restart its body clock")
	check(room.combat_audio.accepted_events == audio_before and room.player.visual_hitstop == heavy_pause, "passive tick during direct confirmation is suppressed without extra player pause")
	hit(target)
	check(target.body_visual._impact_heavy and room.camera.impact_stats() == camera_state and room.player.visual_hitstop == heavy_pause, "heavy then light preserves the stronger body and camera feedback without stacking")
	for _step in 3:
		target.body_visual.advance(.10)
	room.resolve_derived_hit(target, 12.0, &"node", Vector2.LEFT)
	check(not target.body_visual._impact_heavy and is_equal_approx(float(target.body_visual._impact_strength), .28), "after recovery, later passive contact can show its restrained reaction")

func _test_gunner_finisher() -> void:
	fixture("CH02")
	var target: Node2D = dummy("M01", Vector2(120, 0))
	check(room.player.cast_skill("ultimate", target.position), "real gunner ultimate starts for finisher contact check")
	var tiers: Array[bool] = []
	var damage: Array[float] = []
	for step: float in [.25, .24, .24, .24]:
		room.combat_audio.advance(step)
		room.elapsed += step
		room.camera._physics_process(step)
		room.player.abilities.tick(step)
		for projectile: Node2D in room.projectiles.get_children():
			if projectile.consumed: continue
			var before: float = target.health.current
			# Advance the actual projectile through a target; do not inject a contact tier.
			projectile._physics_process(.12)
			if target.health.current < before:
				tiers.append(bool(contact_events().back().heavy))
				damage.append(before - target.health.current)
	check(tiers == [false, false, false, true], "four real R projectile collisions retain light-light-light-heavy contact rhythm")
	check(damage.size() == 4 and is_equal_approx(damage[0], damage[3]), "finisher presentation tier does not change existing damage values")

func _test_bounds_and_cleanup() -> void:
	fixture()
	var target: Node2D = dummy()
	for index in 45:
		hit(target, &"primary")
	check(room.impact_feedback.events.size() <= 32 and room.impact_feedback.culled_events > 0 and room.impact_feedback.active_peak <= 32, "repeated real contacts keep visual layer bounded while culling old numbers")
	check(room.combat_audio.accepted_events == 1 and room.camera.impact_stats().started == 1 and room.combat_audio.active_voice_count() <= 8, "same-cluster pressure cannot expand audio voices or camera pulses")
	room.impact_feedback.clear_feedback()
	check(room.impact_feedback.events.is_empty(), "room transition cleanup removes all contact and damage overlays")
	var layer_ref: WeakRef = weakref(room.impact_feedback)
	var body_ref: WeakRef = weakref(target.body_visual)
	room.free()
	check(layer_ref.get_ref() == null and body_ref.get_ref() == null, "room teardown releases the contact layer and enemy body presentation")

func _capture_hero_contacts() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var heroes: Array[String] = ["CH01", "CH02", "CH03"]
	var monsters: Array[String] = ["M01", "M10", "M31"]
	for index in heroes.size():
		fixture(heroes[index])
		room.player.position = Vector2(1400, 900)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		room.input_blocked = true
		var target: Node2D = dummy(monsters[index], Vector2(80, 15))
		room.player.aim_direction = (target.position - room.player.position).normalized()
		var slot: String = "f" if heroes[index] == "CH03" else "secondary"
		var started: bool = room.player.cast_skill(slot, target.position)
		var elapsed: float = 0.0
		while room.impact_feedback.accepted_events == 0 and elapsed < 1.0:
			room.player.abilities.tick(0.005)
			room.player.get_node("HeroFeedback").advance(0.005)
			for projectile: Node in room.projectiles.get_children():
				if not projectile.is_queued_for_deletion():
					projectile._physics_process(0.005)
			elapsed += 0.005
		check(started and target.health.current < target.health.maximum and room.impact_feedback.accepted_events > 0, heroes[index] + " screenshot is from a real heavy skill damaging a real monster profile")
		for time_ms: int in [15, 90]:
			var delta: float = 0.015 if time_ms == 15 else 0.075
			room.player.visual_hitstop = maxf(0.0, room.player.visual_hitstop - delta)
			room.player.abilities.tick(delta)
			room.player.get_node("HeroFeedback").advance(delta)
			room.impact_feedback.advance(delta)
			target.body_visual.advance(delta)
			room.camera._physics_process(delta)
			room.camera.force_update_scroll()
			room.player.queue_redraw()
			target.queue_redraw()
			room.queue_redraw()
			await RenderingServer.frame_post_draw
			var frame: Image = root.get_texture().get_image()
			var path: String = "res://artifacts/hit_feel_%s_%dms.png" % [heroes[index], time_ms]
			check(frame.save_png(path) == OK, heroes[index] + " saves the real contact frame at " + str(time_ms) + " ms")
