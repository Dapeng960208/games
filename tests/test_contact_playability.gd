extends Node
## Real-AI observational combat. No training HP, cooldown reset or damage injection.
## tools/test.ps1 -Suite contact_playability -Graphical -SkipImport -SkipRestart
const OUTPUT := "res://artifacts/contact_playability"
const SEED := 41827
const METHOD := "Controlled normal-AI encounter observation, not natural progression, human playtesting or a fair class-balance comparison. Each hero uses genuine Game.start_demo Lv8 with six ordinary starter pieces, normal HP/resource/CD/damage. Four normal Lv8 actors (M01 twice, M10, M11) retain authored HP, AI, defense, damage and rewards. Only initial positions/composition are fixed; random spawning and obstacle layout disabled. Real local SubViewport pointer and public fire/cast_skill/start_dash plus normal movement inputs. No resource refill, cooldown reset, teleport, HP/damage/AI override, forced hits, manual ticks, time scaling or fabricated telegraphs. Automatic 60Hz; per-physics enemy displacement sampled after ordinary world actors. Hero policy attempts hammer basic buildup/sweep, moving ranger mark/secondary, and node/Q/basic charge/F; commitment alone never counts as successful combo. Natural death, missed attacks, lost nodes, insufficient resources and incomplete clearing are reported. Crowd-contact PNG means actual contact while multiple live enemies are on screen; a separate multi-target flag requires distinct damaged actor IDs. Raw Master room-SFX WAV has no BGM, gain change, normalization, microphone or editing."
var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var hud_layer: CanvasLayer
var hero := ""
var phase := ""
var phase_started := 0.0
var observing := false
var ending := false
var watchdog_start := 0
var start_wall := 0
var start_elapsed := 0.0
var start_tick := 0
var next_step := 0.0
var next_attempt := 0.0
var next_dash := 0.0
var aim_target := Vector2.ZERO
var desired_motion := Vector2.ZERO
var end_reason := "time_limit"
var initial: Dictionary = {}
var actor_profiles: Dictionary = {}
var previous_actors: Dictionary = {}
var previous_nodes: Dictionary = {}
var maximum_steps: Dictionary = {}
var physics_samples: Array[Dictionary] = []
var actor_transitions: Array[Dictionary] = []
var node_events: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var death_events: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var input_feedback: Array[Dictionary] = []
var releases: Array[Dictionary] = []
var audio_cues: Array[Dictionary] = []
var captures: Dictionary = {}
var reports: Array[Dictionary] = []
var result: Dictionary = {}
var release_cursor := 0
var damage_received := 0.0
var last_hp := 0.0
var distance_walked := 0.0
var last_player_position := Vector2.ZERO
var minimum_resource := INF
var recorder: AudioEffectRecord
var recorder_slot := -1

func _ready() -> void:
	watchdog_start = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000 # Observe completed world-actor steps, never tick them.
	get_tree().create_timer(55, true, false, true).timeout.connect(watchdog)
	call_deferred("run_observations")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CONTACT_PLAYABILITY FAIL: " + label)

func stamp() -> Dictionary:
	return {"wall_seconds":(Time.get_ticks_msec() - start_wall) / 1000.0,
		"physics_seconds":snappedf(room.elapsed - start_elapsed, .00001) if is_instance_valid(room) else 0,
		"physics_tick":Engine.get_physics_frames() - start_tick, "render_frame":Engine.get_frames_drawn()}

func movement(direction: Vector2) -> void:
	desired_motion = direction.limit_length(1)
	for key: String in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(key): Input.action_release(key)
	if desired_motion.x < 0: Input.action_press("move_left", -desired_motion.x)
	if desired_motion.x > 0: Input.action_press("move_right", desired_motion.x)
	if desired_motion.y < 0: Input.action_press("move_up", -desired_motion.y)
	if desired_motion.y > 0: Input.action_press("move_down", desired_motion.y)

func pointer(at: Vector2) -> void:
	var mouse := InputEventMouseMotion.new()
	mouse.position = room.get_canvas_transform() * room.to_global(at)
	mouse.global_position = mouse.position
	stage.push_input(mouse, true)

func combatants() -> Array[Node2D]:
	var found: Array[Node2D] = []
	for actor: Node2D in room.enemies.get_children():
		if actor.static_actor or actor.actor_kind in ["objective", "anchor"]: continue
		if actor.is_alive() and not actor.is_queued_for_deletion(): found.append(actor)
	return found

func chosen_enemy() -> Node2D:
	var nearest: Node2D = null
	var marked: Node2D = null
	for actor: Node2D in combatants():
		if nearest == null or room.player.position.distance_squared_to(actor.position) < room.player.position.distance_squared_to(nearest.position): nearest = actor
		if hero == "CH02" and room.player.class_marks.has(actor.get_instance_id()):
			if marked == null or room.player.position.distance_squared_to(actor.position) < room.player.position.distance_squared_to(marked.position): marked = actor
	return marked if marked != null else nearest

func nodes_snapshot() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for node: Node2D in get_tree().get_nodes_in_group("hero_deployments"):
		if node.room == room and node.kind == "node":
			found.append({"id":node.get_instance_id(), "position":node.position, "alive":node.is_alive(),
				"active":node.is_active(), "charge":node.resonance_charge, "hp":node.health, "age":node.elapsed})
	return found

func runtime_for(actor_id: int) -> Dictionary:
	var found: Dictionary = {}
	for group: String in ["jobs", "motions", "projectiles", "hazards", "supports", "visuals"]:
		var entries: Array[Dictionary] = []
		for entry: Dictionary in room.enemy_skills.get(group):
			if int(entry.get("owner_id", -1)) == actor_id:
				entries.append({"kind":str(entry.get("kind", "")), "remaining":entry.get("remaining", 0),
					"origin":entry.get("origin", Vector2.ZERO), "position":entry.get("position", Vector2.ZERO),
					"target":entry.get("target", Vector2.ZERO), "damage":entry.get("damage", 0)})
		found[group] = entries
	return found

func actors_snapshot() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for actor: Node2D in combatants():
		found.append({"id":actor.get_instance_id(), "enemy_id":actor.enemy_id, "level":actor.enemy_level,
			"hp":actor.health.current, "max_hp":actor.health.maximum, "shield":actor.status.shield(),
			"position":actor.position, "velocity":actor.velocity, "knockback":actor.knockback,
			"phase":str(actor.brain.phase) if actor.brain != null else "no_brain",
			"telegraph":actor.brain.current_telegraph() if actor.brain != null else {},
			"runtime":runtime_for(actor.get_instance_id())})
	return found

func snapshot() -> Dictionary:
	var data := stamp()
	var contacts: Array[Dictionary] = []
	for event: Dictionary in room.impact_feedback.events:
		if str(event.get("kind", "")) != "hit": continue
		var copy: Dictionary = event.duplicate(true)
		copy.erase("anchor"); copy.erase("visual_anchor")
		contacts.append(copy)
	var marks: Array[int] = []
	for id: int in room.player.class_marks: marks.append(id)
	data.merge({"hero":hero, "strategy_phase":phase, "hp":Game.run.hp if Game.run != null else 0,
		"resource":Game.run.resource if Game.run != null else null, "position":room.player.position,
		"aim":room.player.aim_direction, "pointer_target":aim_target, "move_input":desired_motion,
		"cooldowns":room.player.cooldowns.duplicate(true), "dash_cooldown":room.player.dash_cooldown,
		"ability_busy":room.player.abilities.busy(), "break_stacks":room.player.break_stacks,
		"walk_readiness":room.player.walk_distance, "marked_enemy_ids":marks,
		"passive_count":room.player.passive_count, "passive_cooldown":room.player.passive_cooldown,
		"pose":room.player.get_meta("hero_visual_pose", ""), "hitstop":room.player.visual_hitstop,
		"actors":actors_snapshot(), "nodes":nodes_snapshot(), "contacts":contacts,
		"danger_layer":room.enemy_telegraphs.snapshot(), "telemetry":room.telemetry.duplicate(true)})
	return data

func watch_actor(actor: Node2D) -> void:
	if not is_instance_valid(actor) or actor.health == null: return
	var damaged := on_damage.bind(actor)
	var died := on_death.bind(actor)
	if not actor.health.damaged.is_connected(damaged): actor.health.damaged.connect(damaged)
	if not actor.health.depleted.is_connected(died): actor.health.depleted.connect(died)
	actor_profiles[actor.get_instance_id()] = actor.profile.duplicate(true)

func actor_entered(actor: Node) -> void:
	if not actor is Node2D or not actor.has_method("is_alive"): return
	if actor.is_node_ready(): watch_actor(actor)
	else: actor.ready.connect(watch_actor.bind(actor), CONNECT_ONE_SHOT)

func on_damage(amount: float, actor: Node2D) -> void:
	if not observing: return
	var context: Dictionary = actor.last_damage_context
	var data := stamp()
	data.merge({"enemy_instance_id":actor.get_instance_id(), "enemy_id":actor.enemy_id,
		"actor_kind":actor.actor_kind, "static_actor":actor.static_actor,
		"source":str(context.get("skill_slot", context.get("damage_source", ""))),
		"damage_source":str(context.get("damage_source", "")), "attack_id":str(context.get("attack_id", "")),
		"root_event_id":str(context.get("root_event_id", "")), "amount":amount, "hp_after":actor.health.current,
		"position":actor.position, "phase":str(actor.brain.phase) if actor.brain != null else "no_brain",
		"passive_count_at_damage":room.player.passive_count, "passive_cooldown_at_damage":room.player.passive_cooldown})
	damage_events.append(data)

func on_death(actor: Node2D) -> void:
	if not observing or actor.static_actor: return
	var data := stamp()
	data.merge({"id":actor.get_instance_id(), "enemy_id":actor.enemy_id, "source":str(actor.last_damage_context.get("skill_slot", actor.last_damage_context.get("damage_source", ""))), "position":actor.position})
	death_events.append(data)

func on_cue(cue: String) -> void:
	if not observing: return
	var data := stamp(); data["cue"] = cue
	audio_cues.append(data)

func on_skill_feedback(slot: String, reason: String, details: Dictionary) -> void:
	if not observing: return
	var data := stamp(); data.merge({"slot":slot, "reason":reason, "details":details.duplicate(true)})
	input_feedback.append(data)

func on_game_changed() -> void:
	if not observing or Game.run == null: return
	damage_received += maxf(0, last_hp - Game.run.hp)
	last_hp = Game.run.hp

func on_finished(next_result: Dictionary) -> void:
	if not observing: return
	result = next_result.duplicate(true)
	if str(next_result.get("outcome", "")) == "death": damage_received += maxf(0, last_hp); last_hp = 0

func attempt(slot: String, enemy: Node2D, dash_direction: Vector2 = Vector2.ZERO) -> bool:
	if Game.run == null: return false
	var before := snapshot()
	var accepted: bool
	if slot == "basic": accepted = room.player.fire(room.player.aim_direction)
	elif slot == "dash": accepted = room.player.start_dash(dash_direction)
	else: accepted = room.player.cast_skill(slot, aim_target)
	var data := stamp()
	data.merge({"slot":slot, "accepted":accepted, "before":before,
		"requested_enemy_id":enemy.get_instance_id() if is_instance_valid(enemy) else 0,
		"requested_target":aim_target, "resource_after":Game.run.resource,
		"reason":"accepted" if accepted else room.player.last_cast_error if slot not in ["basic", "dash"] else "public_action_not_ready"})
	actions.append(data)
	return accepted

func change_phase(next: String) -> void:
	phase = next; phase_started = room.elapsed; next_attempt = room.elapsed

func bot_step() -> void:
	var enemy := chosen_enemy()
	if enemy == null: movement(Vector2.ZERO); return
	var offset: Vector2 = enemy.position - room.player.position
	var direction: Vector2 = offset.normalized()
	var distance: float = offset.length()
	var move := Vector2.ZERO
	if hero == "CH01":
		move = direction if distance > 66 else Vector2.ZERO
	elif hero == "CH02":
		move = direction if distance > 310 else -direction if distance < 145 else direction.orthogonal() * .72
	else:
		move = direction if distance > 220 else -direction if distance < 100 else Vector2.ZERO
	var danger := false
	var late_locked := false
	for actor: Node2D in combatants():
		if actor.brain == null: continue
		var tell: Dictionary = actor.brain.current_telegraph()
		if tell.is_empty(): continue
		var center: Variant = tell.get("target", actor.position)
		if actor.position.distance_to(room.player.position) < 185 or (center is Vector2 and center.distance_to(room.player.position) < 105):
			danger = true
			late_locked = late_locked or (bool(tell.get("locked", false)) and float(tell.get("progress", 0)) > .40)
	if danger: move = direction.orthogonal()
	movement(move)
	if late_locked and room.elapsed >= next_dash and room.player.dash_cooldown <= 0:
		next_dash = room.elapsed + .25
		if attempt("dash", enemy, move.normalized()): return
	if room.elapsed < next_attempt: return
	next_attempt = room.elapsed + .20
	if hero == "CH01":
		if room.player.break_stacks >= 3 and distance <= 112 and float(room.player.cooldowns.secondary) <= 0:
			if attempt("secondary", enemy): return
		if distance <= 103: attempt("basic", enemy)
	elif hero == "CH02":
		if room.player.class_marks.has(enemy.get_instance_id()) and float(room.player.cooldowns.secondary) <= 0:
			if attempt("secondary", enemy): return
		attempt("basic", enemy)
	else:
		var nodes: Array[Dictionary] = nodes_snapshot()
		match phase:
			"deploy":
				if attempt("secondary", enemy): change_phase("wait_active")
				else: attempt("basic", enemy)
			"wait_active":
				for node: Dictionary in nodes:
					if bool(node.active): change_phase("charge_q"); return
				if nodes.is_empty() and room.elapsed - phase_started > 1: change_phase("deploy")
			"charge_q":
				if attempt("q", enemy): change_phase("basic_charge")
				else: attempt("basic", enemy)
			"basic_charge":
				for node: Dictionary in nodes:
					if int(node.charge) >= 2: change_phase("detonate"); return
				if nodes.is_empty(): change_phase("cooling")
				else: attempt("basic", enemy)
			"detonate":
				if attempt("f", enemy): change_phase("cooling")
				elif nodes.is_empty(): change_phase("cooling")
			"cooling":
				if float(room.player.cooldowns.secondary) <= 0 and float(room.player.cooldowns.f) <= .8: change_phase("deploy")
				else: attempt("basic", enemy)

func _process(_delta: float) -> void:
	if ending: return
	if Time.get_ticks_msec() - watchdog_start >= 55000: watchdog(); return
	if not observing or Game.run == null: return
	var enemy := chosen_enemy()
	if enemy == null: return
	aim_target = enemy.position
	if hero == "CH03" and phase == "deploy": aim_target = room.player.position + room.player.position.direction_to(enemy.position) * minf(120, room.player.position.distance_to(enemy.position))
	pointer(aim_target)

func _physics_process(delta: float) -> void:
	# Lethal runtime damage may settle Game.run before this late observer runs.
	# Keep the terminal world step, but never issue another action after settlement.
	if not observing or not is_instance_valid(room): return
	var data := snapshot()
	for actor: Dictionary in data.actors:
		var id: int = int(actor.id)
		if previous_actors.has(id):
			var old: Dictionary = previous_actors[id]
			var displacement: float = Vector2(old.position).distance_to(actor.position)
			actor["step_distance"] = displacement
			actor["step_delta"] = delta
			if displacement > float(maximum_steps.get(id, {}).get("distance", -1)):
				maximum_steps[id] = {"id":id, "enemy_id":actor.enemy_id, "distance":displacement, "delta":delta, "stamp":stamp(), "before":old.duplicate(true), "after":actor.duplicate(true)}
			if str(old.phase) != str(actor.phase): actor_transitions.append({"stamp":stamp(), "id":id, "enemy_id":actor.enemy_id, "from":old.phase, "to":actor.phase, "telegraph":actor.telegraph, "runtime":actor.runtime})
		previous_actors[id] = actor.duplicate(true)
	var current_nodes: Dictionary = {}
	for node: Dictionary in data.nodes:
		current_nodes[node.id] = node
		var old: Dictionary = previous_nodes.get(node.id, {})
		if old.is_empty() or old.charge != node.charge or old.active != node.active or not is_equal_approx(float(old.hp), float(node.hp)):
			node_events.append({"stamp":stamp(), "before":old, "after":node, "passive_count_after":room.player.passive_count, "passive_cooldown_after":room.player.passive_cooldown})
	for id: int in previous_nodes:
		if not current_nodes.has(id): node_events.append({"stamp":stamp(), "removed":previous_nodes[id]})
	previous_nodes = current_nodes
	collect_releases()
	if Game.run != null: minimum_resource = minf(minimum_resource, Game.run.resource)
	distance_walked += room.player.position.distance_to(last_player_position)
	last_player_position = room.player.position
	physics_samples.append(data)
	if Game.run != null and Game.run.hp > 0 and room.elapsed >= next_step:
		next_step = room.elapsed + .10
		bot_step()

func collect_releases() -> void:
	if not is_instance_valid(room): return
	var actual_releases: Array = room.player.get_node("HeroFeedback").release_events
	while release_cursor < actual_releases.size():
		var event: Dictionary = actual_releases[release_cursor].duplicate(true)
		event.merge(stamp()); releases.append(event); release_cursor += 1

func retain_frame(label: String, data: Dictionary) -> void:
	if captures.has(label): return
	captures[label] = {"image":stage.get_texture().get_image(), "sample":data.duplicate(true)}

func after_draw() -> void:
	if not observing or not is_instance_valid(room): return
	var data := snapshot()
	var recent_ids: Array[int] = []
	var recent_sources: Array[String] = []
	for hit: Dictionary in damage_events:
		if float(data.physics_seconds) - float(hit.physics_seconds) > .20 or bool(hit.static_actor): continue
		if not recent_ids.has(int(hit.enemy_instance_id)): recent_ids.append(int(hit.enemy_instance_id))
		if not recent_sources.has(str(hit.source)): recent_sources.append(str(hit.source))
	var matching_contact := false
	for contact: Dictionary in data.contacts:
		matching_contact = matching_contact or str(contact.source) in recent_sources
	data["recent_distinct_damaged_ids"] = recent_ids
	var visible_enemies := 0
	for actor: Dictionary in data.actors:
		var screen: Vector2 = room.get_canvas_transform() * room.to_global(actor.position)
		if Rect2(0, 0, 1280, 720).has_point(screen): visible_enemies += 1
	data["visible_live_enemy_count"] = visible_enemies
	if matching_contact and visible_enemies >= 2: retain_frame("crowd_contact", data)
	if matching_contact and recent_ids.size() >= 2: retain_frame("multi_target_contact", data)
	if matching_contact and not data.danger_layer.is_empty(): retain_frame("contact_and_danger", data)
	if matching_contact and not captures.has("any_contact"): retain_frame("any_contact", data)

func start_recording() -> void:
	recorder = AudioEffectRecord.new(); recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder); recorder.set_recording_active(true)

func stop_recording() -> Dictionary:
	if recorder == null: return {"status":"missing"}
	recorder.set_recording_active(false)
	var recording: AudioStreamWAV = recorder.get_recording()
	AudioServer.remove_bus_effect(0, recorder_slot); recorder = null
	check(recording != null and not recording.data.is_empty(), hero + " real Master recording contains PCM")
	if recording == null or recording.data.is_empty(): return {"status":"missing", "reason":"No PCM; no unmuted retry"}
	var pcm: PackedByteArray = recording.data
	var peak := 0.0; var energy := 0.0; var saturated := 0
	for offset in range(0, pcm.size() - 1, 2):
		var integer: int = pcm.decode_s16(offset)
		if integer == -32768 or integer == 32767: saturated += 1
		var value: float = float(integer) / 32768.0
		peak = maxf(peak, absf(value)); energy += value * value
	var path := hero + "_native_mix.wav"
	var saved: Error = recording.save_to_wav(OUTPUT.path_join(path))
	check(saved == OK and peak > .000001, hero + " saves non-silent original PCM")
	return {"status":"saved" if saved == OK else "failed", "path":path, "duration":recording.get_length(),
		"peak":peak, "rms":sqrt(energy / maxf(1, pcm.size() / 2.0)), "saturated_s16_samples":saturated,
		"mix_rate":recording.mix_rate, "stereo":recording.stereo, "bgm":false}

func fixture(next_hero: String) -> bool:
	hero = next_hero
	check(Game.new_profile() and Game.start_demo(hero, 0), hero + " real standard demo starts")
	if Game.run == null: return false
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false; room.spawn_enabled = false; room.relic_positions = {}
	stage.add_child(room)
	for actor: Node in room.enemies.get_children(): actor.free()
	actor_profiles = {}; previous_actors = {}; previous_nodes = {}; maximum_steps = {}
	room.enemies.child_entered_tree.connect(actor_entered)
	room.player.position = Vector2(1400, 900)
	room.release_gate = false; room.input_blocked = false
	room.player.skill_input_feedback.connect(on_skill_feedback)
	room.combat_audio.cue_played.connect(on_cue)
	for definition: Array in [["M01", Vector2(180, 0)], ["M01", Vector2(230, 0)], ["M10", Vector2(280, -35)], ["M11", Vector2(360, 65)]]:
		var actor: Node2D = room.spawn_enemy(room.player.position + definition[1], str(definition[0]), 8)
		watch_actor(actor)
		check(actor.rank == "normal" and not actor.static_actor and not actor.training_ai_disabled and actor.health.current == float(actor.profile.max_hp), hero + " natural Lv8 " + actor.enemy_id + " HP/AI")
	hud_layer = CanvasLayer.new(); stage.add_child(hud_layer)
	var hud: Control = load("res://scripts/ui/hud.gd").new(); hud.room = room
	hud_layer.add_child(hud); hud.size = Vector2(1280, 720)
	seed(SEED)
	phase = "deploy" if hero == "CH03" else "class_loop"
	physics_samples = []; actor_transitions = []; node_events = []; damage_events = []; death_events = []
	actions = []; input_feedback = []; releases = []; audio_cues = []; captures = {}; result = {}
	release_cursor = 0; damage_received = 0; distance_walked = 0
	last_hp = Game.run.hp; last_player_position = room.player.position; minimum_resource = Game.run.resource
	start_wall = Time.get_ticks_msec(); start_elapsed = room.elapsed; start_tick = Engine.get_physics_frames()
	phase_started = room.elapsed; next_step = room.elapsed + .10; next_attempt = room.elapsed; next_dash = room.elapsed
	end_reason = "time_limit"
	aim_target = room.player.position + Vector2(120 if hero == "CH03" else 180, 0)
	for _index in 3:
		pointer(aim_target)
		await get_tree().physics_frame
		await get_tree().process_frame
	check(room.player.aim_direction.dot(Vector2.RIGHT) > .99 and room.controls_enabled() and room.pointer_controls_enabled(), hero + " real graphical pointer/control route")
	check(Game.run.level == 8 and Game.run.loadout_snapshot.size() == 6 and Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1 and room.camera.zoom == Vector2(.85, .85), hero + " standard Lv8 and native 60Hz/.85")
	initial = {"stats":Game.run.stats.duplicate(true), "loadout":Game.run.loadout_snapshot.duplicate(true),
		"hp":Game.run.hp, "resource":Game.run.resource, "profiles":actor_profiles.duplicate(true), "world":snapshot()}
	start_recording(); observing = true
	return true

func combo_observation() -> Dictionary:
	var accepted: Dictionary = {}; var released: Dictionary = {}; var hit_ids: Dictionary = {}
	var attack_groups: Dictionary = {}
	for action: Dictionary in actions:
		if bool(action.accepted): accepted[action.slot] = int(accepted.get(action.slot, 0)) + 1
	for event: Dictionary in releases: released[event.slot] = int(released.get(event.slot, 0)) + 1
	for hit: Dictionary in damage_events:
		var source: String = str(hit.source)
		if not hit_ids.has(source): hit_ids[source] = []
		if not hit_ids[source].has(int(hit.enemy_instance_id)): hit_ids[source].append(int(hit.enemy_instance_id))
		var key: String = source + ":" + (str(hit.attack_id) if not str(hit.attack_id).is_empty() else "unidentified_packet_tick:" + str(hit.physics_tick))
		if not attack_groups.has(key): attack_groups[key] = {"source":source, "attack_id":hit.attack_id, "enemy_ids":[], "damage":0.0}
		if not attack_groups[key].enemy_ids.has(int(hit.enemy_instance_id)): attack_groups[key].enemy_ids.append(int(hit.enemy_instance_id))
		attack_groups[key].damage += float(hit.amount)
	var components: Dictionary = {}
	if hero == "CH01":
		components = {"secondary_committed_after_real_three_stacks":false, "secondary_released":int(released.get("secondary", 0)) > 0, "secondary_unique_damaged_ids":hit_ids.get("secondary", [])}
		for action: Dictionary in actions:
			if action.slot == "secondary" and bool(action.accepted) and int(action.before.break_stacks) == 3: components.secondary_committed_after_real_three_stacks = true
	elif hero == "CH02":
		components = {"secondary_committed_with_real_mark":false, "secondary_released":int(released.get("secondary", 0)) > 0, "secondary_unique_damaged_ids":hit_ids.get("secondary", []), "marked_target_actually_hit":false}
		for action: Dictionary in actions:
			if action.slot != "secondary" or not bool(action.accepted) or action.before.marked_enemy_ids.is_empty(): continue
			components.secondary_committed_with_real_mark = true
			for hit: Dictionary in damage_events:
				if str(hit.source) == "secondary" and int(hit.enemy_instance_id) in action.before.marked_enemy_ids and float(hit.physics_seconds) >= float(action.physics_seconds) and float(hit.physics_seconds) < float(action.physics_seconds) + 1.5: components.marked_target_actually_hit = true
	else:
		components = {"secondary_released":int(released.get("secondary", 0)) > 0, "q_released":int(released.get("q", 0)) > 0,
			"charged_nodes_observed":false, "basic_then_node_charge_observed":false, "f_released":int(released.get("f", 0)) > 0,
			"detonation_unique_damaged_ids":hit_ids.get("node_detonation", [])}
		for event: Dictionary in node_events:
			if not event.has("after"): continue
			components.charged_nodes_observed = components.charged_nodes_observed or int(event.after.charge) > 0
			if event.before.is_empty() or int(event.before.id) != int(event.after.id) or int(event.after.charge) != int(event.before.charge) + 1: continue
			for hit: Dictionary in damage_events:
				if str(hit.source) == "primary" and Vector2(hit.position).distance_to(event.after.position) <= 160 and int(hit.passive_count_at_damage) == 3 and float(hit.passive_cooldown_at_damage) <= 0 and int(event.stamp.physics_tick) - int(hit.physics_tick) in [0, 1] and int(event.passive_count_after) == 0 and float(event.passive_cooldown_after) > 0: components.basic_then_node_charge_observed = true
	return {"accepted_actions":accepted, "actual_releases":released, "unique_damaged_ids_by_source":hit_ids,
		"attack_groups":attack_groups, "components":components, "interpretation":"Components report separate commitment/release/confirmed-hit facts; no blanket combo-success claim from casting alone."}

func finish_observation() -> void:
	collect_releases()
	observing = false; movement(Vector2.ZERO)
	var recording: Dictionary = stop_recording()
	check(not physics_samples.is_empty() and not actions.is_empty(), hero + " controller executed and recorded genuine physics/actions")
	if Game.run != null: check(Game.run.stats == initial.stats and Game.run.loadout_snapshot == initial.loadout, hero + " player stats/gear remain standard")
	for actor: Node2D in combatants(): check(actor.profile == actor_profiles.get(actor.get_instance_id(), {}) and not actor.training_ai_disabled and actor.health.maximum == float(actor.profile.max_hp), hero + " surviving natural profile/HP/AI unchanged")
	var evidence := "crowd_contact_captured" if captures.has("crowd_contact") else "missing_crowd_contact"
	check(captures.has("crowd_contact"), hero + " actual contact with multiple enemies visible; missing evidence is not fabricated")
	var files: Array[Dictionary] = []
	for label: String in captures:
		var path: String = hero + "_" + label + ".png"
		var bitmap: Image = captures[label].image
		check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png(OUTPUT.path_join(path)) == OK, "save true rendered frame " + path)
		files.append({"path":path, "sample":captures[label].sample})
	reports.append({"hero":hero, "end_reason":end_reason, "evidence_status":evidence,
		"initial":initial, "final":snapshot(), "settled_result":result, "combo":combo_observation(),
		"actions":actions, "skill_input_feedback":input_feedback, "skill_releases":releases,
		"damage_events":damage_events, "deaths":death_events, "node_events":node_events,
		"enemy_state_transitions":actor_transitions, "enemy_maximum_physics_steps":maximum_steps,
		"all_physics_samples":physics_samples, "player_damage_received":damage_received,
		"player_distance_including_dash_knockback":distance_walked, "minimum_resource":minimum_resource,
		"audio_cues":audio_cues, "recording":recording, "captures":files,
		"scope_limit":"Crowd-contact captures are not automatically simultaneous multi-target strikes. Such damage has distinct IDs in the separate recent/contact and attack-group fields. No forced all-clear or complete combo requirement."})
	print("CONTACT_NATIVE hero=", hero, " end=", end_reason, " deaths=", death_events.size(), " damage_received=", damage_received, " evidence=", evidence, " combo=", combo_observation().components)
	captures.clear()

func cleanup() -> void:
	observing = false; movement(Vector2.ZERO)
	if recorder != null:
		recorder.set_recording_active(false); AudioServer.remove_bus_effect(0, recorder_slot); recorder = null
	if is_instance_valid(hud_layer): hud_layer.free()
	if is_instance_valid(room): room.free()
	if Game.run != null: Game.finish_run("abandoned")

func write_report(timed_out: bool = false) -> void:
	var file := FileAccess.open(OUTPUT.path_join("native_observation.json"), FileAccess.WRITE)
	check(file != null, "open contact playability report")
	if file == null: return
	file.store_string(JSON.stringify({"method":METHOD, "checks":checks + 1, "failures":failures,
		"timed_out":timed_out, "reports":reports, "total_wall_seconds":(Time.get_ticks_msec() - watchdog_start) / 1000.0}, "\t"))
	check(file.get_error() == OK, "write contact playability report")
	file.close()

func watchdog() -> void:
	if ending: return
	ending = true; failures += 1
	push_error("Contact playability reached 55-second watchdog; cleanup and quit")
	reports.append({"hero":hero, "end_reason":"watchdog", "actions":actions, "damage_events":damage_events, "partial_physics_samples":physics_samples})
	cleanup(); write_report(true); get_tree().quit(1)

func run_observations() -> void:
	if not str(Game.profile_path).contains("test_contact_playability") or DisplayServer.get_name() == "headless":
		ending = true
		push_error("Contact playability requires graphical renderer and isolated test_contact_playability profile")
		get_tree().quit(2); return
	AudioServer.set_bus_mute(0, true)
	for key: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(key): InputMap.add_action(key)
		Input.action_release(key)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	stage = SubViewport.new(); stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS; stage.handle_input_locally = true
	add_child(stage)
	var display := TextureRect.new(); display.texture = stage.get_texture(); display.size = Vector2(1280, 720)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(display)
	RenderingServer.frame_post_draw.connect(after_draw)
	Game.changed.connect(on_game_changed); Game.run_finished.connect(on_finished)
	for next_hero: String in ["CH01", "CH02", "CH03"]:
		if not await fixture(next_hero):
			ending = true; cleanup(); write_report(); get_tree().quit(1); return
		var deadline: int = Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < deadline and not ending:
			await get_tree().process_frame
			if Game.run == null or Game.run.hp <= 0: end_reason = "player_death"; break
			if combatants().is_empty(): end_reason = "natural_clear"; break
		if ending: return
		await RenderingServer.frame_post_draw
		finish_observation()
		await room.combat_audio.wait_for_cleanup()
		cleanup(); await get_tree().process_frame
	ending = true
	RenderingServer.frame_post_draw.disconnect(after_draw)
	Game.changed.disconnect(on_game_changed); Game.run_finished.disconnect(on_finished)
	write_report()
	print("CONTACT_PLAYABILITY_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
