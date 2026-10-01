extends Node
## Observational real-AI encounters, not a fair balance comparison or clear test.
## tools/test.ps1 -Suite resonance_playability -Graphical -SkipImport -SkipRestart

const OUTPUT := "res://artifacts/resonance_playability"
const SEED := 41827
const METHOD := "Controlled graphical encounter observation, not natural progression, human playtesting or a fair balance comparison. Real Game.start_demo CH03 Lv8 uses all six standard starter equipment pieces and natural starting resources. Four normal Lv8 enemies retain authored HP, damage, AI and rewards. Only initial positions/composition are fixed; random spawns/obstacle layout are disabled. Public fire/cast_skill, real SubViewport pointer and ordinary movement input only. No stat, HP, resource, cooldown, AI, charge, clock or projectile-hit injection. Automatic 60Hz physics, time scale 1 and normal .85 camera. Player can miss, run out of mana, lose nodes, die or fail to clear. Actual first matching GPU frames are copied to memory and compressed after observation. Baseline uses basic/Q; node_q waits for genuine node activation, Q charge, then tries four-beat basic-hit charging before F (four-second bounded wait, with missing proof reported). node_r adds a short real R full-charge observation and may lack mana for F. This fixture does not assert either strategy is stronger."

var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var hud_layer: CanvasLayer
var hud: Control
var observing := false
var ending := false
var mode := ""
var phase := ""
var phase_started := 0.0
var start_wall := 0
var start_elapsed := 0.0
var start_tick := 0
var watchdog_start := 0
var next_step := 0.0
var next_attempt := 0.0
var end_reason := ""
var aim_target := Vector2.ZERO
var desired_motion := Vector2.ZERO
var initial: Dictionary = {}
var profiles: Dictionary = {}
var samples: Array[Dictionary] = []
var attempts: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var deaths: Array[Dictionary] = []
var node_events: Array[Dictionary] = []
var four_beat_events: Array[Dictionary] = []
var input_feedback: Array[Dictionary] = []
var previous_nodes: Dictionary = {}
var captures: Dictionary = {}
var reports: Array[Dictionary] = []
var cast_hits: Dictionary = {}
var cast_accepts: Dictionary = {}
var max_charge := 0
var f_releases := 0
var previous_release_count := 0
var minimum_resource := INF
var spent_resource := 0.0
var received_damage := 0.0
var previous_player_hp := 0.0
var current_result: Dictionary = {}
var recorder: AudioEffectRecord
var recorder_slot := -1
var audio_cues: Array[Dictionary] = []

func start_recording() -> void:
	if mode == "basic_q": return
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)

func stop_recording() -> Dictionary:
	if recorder == null: return {"status": "not_requested"}
	recorder.set_recording_active(false)
	var recording: AudioStreamWAV = recorder.get_recording()
	AudioServer.remove_bus_effect(0, recorder_slot)
	recorder = null
	check(recording != null and not recording.data.is_empty(), mode + " original Master recording contains PCM")
	if recording == null or recording.data.is_empty(): return {"status": "unavailable", "reason": "No PCM; no unmuted retry"}
	var pcm: PackedByteArray = recording.data
	var peak := 0.0
	var energy := 0.0
	for offset in range(0, pcm.size() - 1, 2):
		var value: float = float(pcm.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value))
		energy += value * value
	var path: String = mode + "_native_mix.wav"
	var saved: Error = recording.save_to_wav(OUTPUT.path_join(path))
	check(saved == OK and peak > .000001 and peak < 1.0, mode + " actual Master mix is saved, non-silent and unclipped")
	return {"status": "saved" if saved == OK else "unavailable", "path": path,
		"duration": recording.get_length(), "mix_rate": recording.mix_rate, "stereo": recording.stereo,
		"peak": peak, "rms": sqrt(energy / maxf(1, pcm.size() / 2.0)),
		"source": "Original room CombatAudio Master-bus PCM before safety mute; standard game SFX mix. This room-only fixture has no MusicDirector. No gain adjustment, normalization, microphone capture or audio editing."}

func on_cue(cue: String) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"cue": cue, "voices": room.combat_audio.active_voice_count()})
	audio_cues.append(event)

func _ready() -> void:
	watchdog_start = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(55.0, true, false, true).timeout.connect(watchdog)
	call_deferred("run_observations")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RESONANCE_PLAYABILITY FAIL: " + label)

func stamp() -> Dictionary:
	return {"wall_seconds": (Time.get_ticks_msec() - start_wall) / 1000.0,
		"physics_seconds": snappedf(room.elapsed - start_elapsed, .00001) if is_instance_valid(room) else 0,
		"physics_tick": Engine.get_physics_frames() - start_tick,
		"render_frame": Engine.get_frames_drawn()}

func movement(direction: Vector2) -> void:
	desired_motion = direction.limit_length(1.0)
	for key: String in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(key): Input.action_release(key)
	if desired_motion.x < 0: Input.action_press("move_left", -desired_motion.x)
	if desired_motion.x > 0: Input.action_press("move_right", desired_motion.x)
	if desired_motion.y < 0: Input.action_press("move_up", -desired_motion.y)
	if desired_motion.y > 0: Input.action_press("move_down", desired_motion.y)

func pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = room.get_canvas_transform() * room.to_global(at)
	event.global_position = event.position
	stage.push_input(event, true)

func living_enemies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for enemy: Node2D in room.enemies.get_children():
		# Natural M06 cover/skill anchors are static objects in this container,
		# not combatants or bot targets. Ordinary summoned enemies remain eligible.
		if enemy.static_actor or enemy.actor_kind in ["objective", "anchor"]: continue
		if enemy.is_alive() and not enemy.is_queued_for_deletion(): result.append(enemy)
	return result

func nearest_enemy() -> Node2D:
	var chosen: Node2D = null
	for enemy: Node2D in living_enemies():
		if chosen == null or room.player.position.distance_squared_to(enemy.position) < room.player.position.distance_squared_to(chosen.position): chosen = enemy
	return chosen

func nodes_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node2D in get_tree().get_nodes_in_group("hero_deployments"):
		if node.room != room or node.kind != "node": continue
		var item := {"id": node.get_instance_id(), "position": [node.position.x, node.position.y],
			"alive": node.is_alive(), "active": node.is_active(), "charge": node.resonance_charge,
			"hp": node.health, "max_hp": node.max_health, "age": node.elapsed, "lifetime": node.lifetime,
			"distance_to_player": room.player.position.distance_to(node.position)}
		if node.has_method("resonance_readout"): item["readout"] = node.resonance_readout()
		result.append(item)
	return result

func snapshot() -> Dictionary:
	var data := stamp()
	var enemies: Array[Dictionary] = []
	for enemy: Node2D in living_enemies():
		enemies.append({"id": enemy.get_instance_id(), "enemy_id": enemy.enemy_id, "level": enemy.enemy_level,
			"hp": enemy.health.current, "max_hp": enemy.health.maximum,
			"position": [enemy.position.x, enemy.position.y], "phase": str(enemy.brain.phase) if enemy.brain != null else "no_brain",
			"telegraph": enemy.brain.current_telegraph() if enemy.brain != null else {}})
	var feedback: Node2D = room.player.get_node("HeroFeedback")
	var effect_kinds: Array[String] = []
	for effect: Dictionary in feedback.effects: effect_kinds.append(str(effect.kind))
	var contacts: Array[Dictionary] = []
	for effect: Dictionary in room.impact_feedback.events:
		if str(effect.kind) == "hit": contacts.append({"source": str(effect.source), "damage": effect.damage, "age": effect.age, "position": effect.at})
	data.merge({"mode": mode, "strategy_phase": phase, "hp": Game.run.hp if Game.run != null else 0,
		"mana": Game.run.resource if Game.run != null else 0,
		"cooldowns": room.player.cooldowns.duplicate(true), "busy": room.player.abilities.busy(),
		"player_position": [room.player.position.x, room.player.position.y],
		"aim_direction": [room.player.aim_direction.x, room.player.aim_direction.y],
		"pointer_world_target": [aim_target.x, aim_target.y], "movement": [desired_motion.x, desired_motion.y],
		"passive_count": room.player.passive_count, "passive_cooldown": room.player.passive_cooldown,
		"class_status": room.player.class_status(),
		"nodes": nodes_snapshot(), "enemies": enemies, "effects": effect_kinds,
		"telemetry": room.telemetry.duplicate(true), "contact_count": contacts.size(), "hit_contacts": contacts,
		"pose": str(room.player.get_meta("hero_visual_pose", ""))})
	return data

func on_damage(amount: float, enemy: Node2D) -> void:
	if not observing: return
	var context: Dictionary = enemy.last_damage_context
	# Direct Q/F/R hits use the shared damage_source="skill" category;
	# the committed skill_slot identifies the actual action/contact source.
	var source: String = str(context.get("skill_slot", context.get("damage_source", "")))
	var event := stamp()
	event.merge({"enemy_instance_id": enemy.get_instance_id(), "enemy_id": enemy.enemy_id,
		"actor_kind": enemy.actor_kind, "static_actor": enemy.static_actor,
		"anchor_kind": str(enemy.get_meta("enemy_skill_anchor_kind", "")),
		"source": source, "skill_slot": str(context.get("skill_slot", "")), "damage_source": str(context.get("damage_source", "")),
		"attack_id": str(context.get("attack_id", "")), "amount": amount, "hp_after": enemy.health.current,
		"passive_count_at_damage": room.player.passive_count, "passive_cooldown_at_damage": room.player.passive_cooldown,
		"position": [enemy.position.x, enemy.position.y]})
	damage_events.append(event)
	cast_hits[source] = int(cast_hits.get(source, 0)) + 1

func on_death(enemy: Node2D) -> void:
	if not observing: return
	if enemy.static_actor or enemy.actor_kind in ["objective", "anchor"]: return
	var event := stamp()
	event.merge({"enemy_instance_id": enemy.get_instance_id(), "enemy_id": enemy.enemy_id,
		"source": str(enemy.last_damage_context.get("damage_source", ""))})
	deaths.append(event)

func observe_actor_ready(enemy: Node2D) -> void:
	# Read-only listeners also cover dynamically spawned weld plates. A bolt
	# aimed at an enemy can really strike the intervening plate and advance the
	# production four-beat passive; these objects remain excluded from bot targets.
	if not is_instance_valid(enemy) or enemy.health == null: return
	var damage_callback := on_damage.bind(enemy)
	var death_callback := on_death.bind(enemy)
	if not enemy.health.damaged.is_connected(damage_callback): enemy.health.damaged.connect(damage_callback)
	if not enemy.health.depleted.is_connected(death_callback): enemy.health.depleted.connect(death_callback)

func observe_actor_entered(actor: Node) -> void:
	if not actor is Node2D or not actor.has_method("is_alive"): return
	if actor.is_node_ready(): observe_actor_ready(actor)
	else: actor.ready.connect(observe_actor_ready.bind(actor), CONNECT_ONE_SHOT)

func on_feedback(slot: String, reason: String, details: Dictionary) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"slot": slot, "reason": reason, "details": details.duplicate(true)})
	input_feedback.append(event)

func on_finished(result: Dictionary) -> void:
	if not observing: return
	current_result = result.duplicate(true)
	if str(result.get("outcome", "")) == "death":
		received_damage += maxf(0, previous_player_hp)
		previous_player_hp = 0

func try_action(slot: String, target: Vector2) -> bool:
	if Game.run == null: return false
	var before_mana: float = Game.run.resource
	var before_cooldown: float = room.player.shot_cooldown if slot == "basic" else float(room.player.cooldowns.get(slot, 0))
	var before_busy: bool = room.player.abilities.busy()
	var accepted: bool = room.player.fire(room.player.aim_direction) if slot == "basic" else room.player.cast_skill(slot, target)
	var event := stamp()
	event.merge({"slot": slot, "accepted": accepted,
		"reason": "accepted" if accepted else "basic_cooldown" if slot == "basic" and before_cooldown > 0 else "busy" if slot == "basic" and before_busy else "basic_unavailable" if slot == "basic" else room.player.last_cast_error,
		"mana_before": before_mana, "mana_after": Game.run.resource,
		"cost_committed": maxf(0, before_mana - Game.run.resource), "cooldown_before": before_cooldown,
		"cooldown_after": room.player.shot_cooldown if slot == "basic" else float(room.player.cooldowns.get(slot, 0)),
		"target": [target.x, target.y], "aim": [room.player.aim_direction.x, room.player.aim_direction.y],
		"nodes_at_request": nodes_snapshot()})
	attempts.append(event)
	spent_resource += float(event.cost_committed)
	if accepted: cast_accepts[slot] = int(cast_accepts.get(slot, 0)) + 1
	return accepted

func change_phase(next: String) -> void:
	phase = next
	phase_started = room.elapsed
	next_attempt = room.elapsed

func bot_step() -> void:
	var enemy: Node2D = nearest_enemy()
	if enemy == null:
		movement(Vector2.ZERO)
		return
	var offset: Vector2 = enemy.position - room.player.position
	# Both policies use identical modest spacing, with no invulnerability/dash bot.
	movement(-offset.normalized() if offset.length() < 105 else offset.normalized() if offset.length() > 245 else Vector2.ZERO)
	if room.elapsed < next_attempt: return
	next_attempt = room.elapsed + .20
	if mode == "basic_q":
		if float(room.player.cooldowns.q) <= 0:
			if try_action("q", enemy.position): return
		try_action("basic", enemy.position)
		return
	var nodes: Array[Dictionary] = nodes_snapshot()
	match phase:
		"deploy":
			if try_action("secondary", aim_target): change_phase("wait_active")
		"wait_active":
			for node: Dictionary in nodes:
				if bool(node.active):
					change_phase("charge_q" if mode == "node_q" else "charge_r")
					return
			if nodes.is_empty() and room.elapsed - phase_started > 1.2: change_phase("deploy")
		"charge_q", "charge_r":
			var slot: String = "q" if phase == "charge_q" else "ultimate"
			if try_action(slot, aim_target): change_phase("wait_charge")
		"wait_charge":
			for node: Dictionary in nodes:
				if int(node.charge) >= (1 if mode == "node_q" else 3):
					change_phase("basic_charge" if mode == "node_q" else "detonate")
					return
			if nodes.is_empty(): change_phase("cooling")
			elif room.elapsed - phase_started > 1.5:
				# A real miss is kept in the report; retry only through normal CD.
				change_phase("charge_q" if mode == "node_q" else "charge_r")
		"basic_charge":
			for node: Dictionary in nodes:
				if int(node.charge) >= 2:
					change_phase("detonate")
					return
			if nodes.is_empty(): change_phase("cooling")
			elif room.elapsed - phase_started >= 4.0: change_phase("detonate")
			else: try_action("basic", enemy.position)
		"detonate":
			if try_action("f", enemy.position): change_phase("cooling")
			elif nodes.is_empty(): change_phase("cooling")
		"cooling":
			if float(room.player.cooldowns.f) <= .8 and float(room.player.cooldowns.secondary) <= 0:
				change_phase("deploy")
			else: try_action("basic", enemy.position)

func _process(_delta: float) -> void:
	if ending: return
	if Time.get_ticks_msec() - watchdog_start >= 55000:
		watchdog()
		return
	if not observing or Game.run == null: return
	var enemy: Node2D = nearest_enemy()
	if enemy == null: return
	aim_target = enemy.position
	if phase == "deploy":
		aim_target = room.player.position + room.player.position.direction_to(enemy.position) * minf(120.0, room.player.position.distance_to(enemy.position))
	elif phase == "charge_r":
		var nodes: Array[Dictionary] = nodes_snapshot()
		if not nodes.is_empty(): aim_target = Vector2(nodes[0].position[0], nodes[0].position[1])
	pointer(aim_target)

func _physics_process(_delta: float) -> void:
	if not observing or Game.run == null: return
	minimum_resource = minf(minimum_resource, Game.run.resource)
	received_damage += maxf(0, previous_player_hp - Game.run.hp)
	previous_player_hp = Game.run.hp
	observe_nodes()
	if room.elapsed >= next_step:
		next_step = room.elapsed + .10
		samples.append(snapshot())
		bot_step()

func observe_nodes() -> void:
	var current: Dictionary = {}
	for node: Dictionary in nodes_snapshot():
		current[node.id] = node
		max_charge = maxi(max_charge, int(node.charge))
		var old: Dictionary = previous_nodes.get(node.id, {})
		if old.is_empty() or old.charge != node.charge or old.active != node.active or old.alive != node.alive or not is_equal_approx(float(old.hp), float(node.hp)):
			var event := stamp()
			event.merge({"change": "created" if old.is_empty() else "state_changed", "before": old.duplicate(true), "after": node.duplicate(true)})
			node_events.append(event)
			if not old.is_empty() and int(node.charge) > int(old.charge) and room.player.passive_count == 0 and room.player.passive_cooldown > 0:
				for hit: Dictionary in damage_events:
					var same_node_charge: bool = int(old.id) == int(node.id) and int(node.charge) == int(old.charge) + 1
					var hit_position := Vector2(hit.position[0], hit.position[1])
					var node_position := Vector2(node.position[0], node.position[1])
					if same_node_charge and hit_position.distance_to(node_position) <= 160.0 and str(hit.source) == "primary" and int(hit.passive_count_at_damage) == 3 and float(hit.passive_cooldown_at_damage) <= 0 and int(event.physics_tick) - int(hit.physics_tick) in [0, 1]:
						four_beat_events.append({"confirmed_primary_hit": hit.duplicate(true), "node_change": event.duplicate(true), "passive_count_after": room.player.passive_count, "passive_cooldown_after": room.player.passive_cooldown})
						break
	for id: int in previous_nodes:
		if not current.has(id):
			var event := stamp()
			event.merge({"change": "removed", "last_observed": previous_nodes[id].duplicate(true), "note": "Removal is observed; death/expiry/detonation is not invented. Correlate F release, node_burst and damage source."})
			node_events.append(event)
	previous_nodes = current
	var releases: Array = room.player.get_node("HeroFeedback").release_events
	for index in range(previous_release_count, releases.size()):
		if str(releases[index].slot) == "f": f_releases += 1
	previous_release_count = releases.size()

func retain_frame(label: String, data: Dictionary) -> void:
	if captures.has(label): return
	captures[label] = {"image": stage.get_texture().get_image(), "sample": data.duplicate(true)}

func after_draw() -> void:
	if not observing or not is_instance_valid(room): return
	var data := snapshot()
	for node: Dictionary in data.nodes:
		if not bool(node.active): continue
		if int(node.charge) == 0: retain_frame("node_active", data)
		if int(node.charge) == 1: retain_frame("charge_1", data)
		if int(node.charge) == 2 and not four_beat_events.is_empty(): retain_frame("four_beat_charge_2", data)
		if int(node.charge) == 3: retain_frame("charge_3", data)
	if "node_burst" in data.effects and int(cast_hits.get("node_detonation", 0)) > 0: retain_frame("f_burst_hit", data)
	if not damage_events.is_empty() and int(data.contact_count) > 0:
		var hit: Dictionary = damage_events.back()
		if float(data.physics_seconds) - float(hit.physics_seconds) <= .20:
			for contact: Dictionary in data.hit_contacts:
				if str(contact.source) != str(hit.source): continue
				if str(hit.source) == "q": retain_frame("q_hit", data)
				if str(hit.source) == "primary": retain_frame("basic_hit", data)

func fixture(next_mode: String) -> bool:
	mode = next_mode
	check(Game.new_profile() and Game.start_demo("CH03", 0), mode + " starts genuine standard Lv8 demo")
	if Game.run == null: return false
	check(Game.run.level == 8 and Game.run.hero_id == "CH03" and Game.run.loadout_snapshot.size() == 6, mode + " standard full starter gear, hero and level")
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	stage.add_child(room)
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.enemies.child_entered_tree.connect(observe_actor_entered)
	room.player.position = Vector2(1400, 900)
	room.release_gate = false
	room.input_blocked = false
	room.combat_audio.audible = mode != "basic_q"
	room.combat_audio.cue_played.connect(on_cue)
	hud_layer = CanvasLayer.new()
	stage.add_child(hud_layer)
	hud = load("res://scripts/ui/hud.gd").new()
	hud.room = room
	hud_layer.add_child(hud)
	hud.size = Vector2(1280, 720)
	profiles.clear()
	for spec: Array in [["M06", Vector2(175, 0)], ["M01", Vector2(245, -85)], ["M01", Vector2(275, 95)], ["M11", Vector2(320, 0)]]:
		var enemy: Node2D = room.spawn_enemy(room.player.position + spec[1], str(spec[0]), 8)
		profiles[enemy.get_instance_id()] = enemy.profile.duplicate(true)
		check(not enemy.training_ai_disabled and not enemy.static_actor and enemy.health.current == float(enemy.profile.max_hp), mode + " natural normal Lv8 " + enemy.enemy_id)
		observe_actor_ready(enemy)
	room.player.skill_input_feedback.connect(on_feedback)
	seed(SEED)
	phase = "baseline" if mode == "basic_q" else "deploy"
	aim_target = room.player.position + Vector2(175 if mode == "basic_q" else 120, 0)
	for _index in 3:
		pointer(aim_target)
		await get_tree().physics_frame
		await get_tree().process_frame
	check(room.player.aim_direction.dot(Vector2.RIGHT) > .99 and room.controls_enabled() and room.pointer_controls_enabled(), mode + " real graphical pointer reaches production player")
	check(Engine.physics_ticks_per_second == 60 and is_equal_approx(Engine.time_scale, 1) and room.camera.zoom == Vector2(.85, .85), mode + " native 60Hz, unscaled time and .85 camera")
	start_wall = Time.get_ticks_msec(); start_elapsed = room.elapsed; start_tick = Engine.get_physics_frames()
	samples = []; attempts = []; damage_events = []; deaths = []; node_events = []; four_beat_events = []; input_feedback = []
	previous_nodes = {}; captures = {}; cast_hits = {}; cast_accepts = {}; current_result = {}
	audio_cues = []
	max_charge = 0; f_releases = 0; previous_release_count = 0
	minimum_resource = Game.run.resource; spent_resource = 0; received_damage = 0; previous_player_hp = Game.run.hp
	phase_started = room.elapsed; next_step = room.elapsed + .10; next_attempt = room.elapsed; end_reason = "time_limit"
	initial = {"stats": Game.run.stats.duplicate(true), "loadout": Game.run.loadout_snapshot.duplicate(true),
		"owned_equipment": Game.run.equipment_snapshot.duplicate(true), "hp": Game.run.hp,
		"resource": Game.run.resource, "profiles": profiles.duplicate(true), "world": snapshot()}
	start_recording()
	observing = true
	return true

func finish_observation() -> void:
	if Game.run != null: observe_nodes()
	observing = false
	movement(Vector2.ZERO)
	var recording: Dictionary = stop_recording()
	check(not attempts.is_empty() and not samples.is_empty(), mode + " records actual actions and automatically advanced states")
	if Game.run != null: check(Game.run.stats == initial.stats and Game.run.loadout_snapshot == initial.loadout, mode + " leaves standard stats and gear untouched")
	for enemy: Node2D in living_enemies():
		check(profiles.get(enemy.get_instance_id(), {}) == enemy.profile and not enemy.training_ai_disabled, mode + " surviving natural enemy profile and AI untouched")
	var missing: Array[String] = []
	var expected: Array = ["q_hit"] if mode == "basic_q" else ["node_active", "charge_1", "four_beat_charge_2", "f_burst_hit"] if mode == "node_q" else ["node_active", "charge_3"]
	for label: String in expected:
		if not captures.has(label): missing.append(label)
	check(missing.is_empty(), mode + " required real evidence captured; missing=" + str(missing))
	var files: Array[Dictionary] = []
	for label: String in captures:
		var path: String = mode + "_" + label + ".png"
		var bitmap: Image = captures[label].image
		check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png(OUTPUT.path_join(path)) == OK, "save actual GPU frame " + path)
		files.append({"path": path, "sample": captures[label].sample})
	var report := {"mode": mode, "end_reason": end_reason,
		"evidence_status": "observed" if missing.is_empty() else "missing_required_evidence",
		"initial": initial, "final": snapshot(), "settled_result": current_result,
		"accepted_actions": cast_accepts, "damage_source_hit_counts": cast_hits, "attempts": attempts,
		"damage_events": damage_events, "enemy_deaths": deaths, "node_events": node_events,
		"four_beat_confirmed_charge_events": four_beat_events,
		"recording": recording, "accepted_audio_cues": audio_cues,
		"input_feedback": input_feedback, "samples": samples, "captures": files, "missing_frames": missing,
		"max_observed_charge": max_charge, "actual_f_releases": f_releases,
		"mana_spent_at_commit": spent_resource, "minimum_mana": minimum_resource,
		"player_damage_observed": received_damage,
		"interpretation": "Observation only: deaths, incomplete clear and failed casts remain evidence. Missing charge or blast frames are not replaced with fabricated frames; evidence checks do not claim enjoyable or balanced gameplay."}
	reports.append(report)
	print("RESONANCE_NATIVE mode=", mode, " end=", end_reason, " max_charge=", max_charge, " accepted=", cast_accepts, " hits=", cast_hits, " deaths=", deaths.size(), " mana_spent=", spent_resource, " missing=", missing)
	captures.clear()

func write_report(timed_out: bool = false) -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var file := FileAccess.open(OUTPUT.path_join("native_observation.json"), FileAccess.WRITE)
	check(file != null, "open native observation report")
	if file == null: return
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "timed_out": timed_out,
		"method": METHOD, "total_wall_seconds": (Time.get_ticks_msec() - watchdog_start) / 1000.0,
		"reports": reports}, "\t"))
	check(file.get_error() == OK, "write native observation report")
	file.close()

func cleanup_immediately() -> void:
	observing = false
	movement(Vector2.ZERO)
	if recorder != null:
		recorder.set_recording_active(false)
		AudioServer.remove_bus_effect(0, recorder_slot)
		recorder = null
	if is_instance_valid(hud_layer): hud_layer.free()
	if is_instance_valid(room): room.free()
	if Game.run != null: Game.finish_run("abandoned")

func watchdog() -> void:
	if ending: return
	ending = true
	failures += 1
	push_error("Resonance observation reached 55-second real-time watchdog; cleanup and quit")
	if observing and is_instance_valid(room):
		reports.append({"mode": mode, "end_reason": "watchdog", "initial": initial, "final": snapshot(),
			"attempts": attempts, "damage_events": damage_events, "node_events": node_events,
			"enemy_deaths": deaths, "samples": samples, "missing_frames": "capture incomplete; no pass claim"})
	cleanup_immediately()
	write_report(true)
	get_tree().quit(1)

func run_observations() -> void:
	if not str(Game.profile_path).contains("test_resonance_playability") or DisplayServer.get_name() == "headless":
		ending = true
		push_error("Resonance playability requires an isolated test_resonance_playability profile and graphical pointer/rendering")
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	for key: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(key): InputMap.add_action(key)
	movement(Vector2.ZERO)
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
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	RenderingServer.frame_post_draw.connect(after_draw)
	Game.run_finished.connect(on_finished)
	for scenario: String in ["basic_q", "node_q", "node_r"]:
		if not await fixture(scenario):
			ending = true
			cleanup_immediately()
			write_report()
			get_tree().quit(1)
			return
		var limit: float = 8.0 if scenario == "node_r" else 14.0
		var local_deadline: int = Time.get_ticks_msec() + int(limit * 1000)
		while not ending and Time.get_ticks_msec() < local_deadline:
			await get_tree().process_frame
			if Game.run == null or Game.run.hp <= 0:
				end_reason = "player_death"
				break
			if living_enemies().is_empty():
				end_reason = "natural_clear"
				break
		if ending: return
		await RenderingServer.frame_post_draw
		finish_observation()
		await room.combat_audio.wait_for_cleanup()
		cleanup_immediately()
		await get_tree().process_frame
	ending = true
	RenderingServer.frame_post_draw.disconnect(after_draw)
	Game.run_finished.disconnect(on_finished)
	write_report()
	print("RESONANCE_PLAYABILITY_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
