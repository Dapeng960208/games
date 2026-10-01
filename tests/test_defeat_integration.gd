extends Node
## Actual Game -> MineRoom -> MineEnemy damage/death, with isolated save data.
## Graphical mode additionally captures three genuine enemy materials at 15/120/320 ms.

const RoomScene = preload("res://scenes/room.tscn")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
var room: Node2D
var checks: int = 0
var failures: int = 0
var cues: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DEFEAT INTEGRATION: " + description)

func fixture(reduced: bool = false) -> void:
	get_tree().paused = false
	if is_instance_valid(room):
		room.free()
	Game.profile.settings["reduced_fx"] = reduced
	Game.profile.settings["muted"] = false
	Game.profile.settings["sfx_muted"] = false
	Game.profile.settings["master_volume"] = 1.0
	Game.profile.settings["sfx_volume"] = 0.85
	Game.run.hero_id = "CH01"
	Game.run.level = 8
	Game.run.stats = Resolver.resolve("CH01", 8, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.stats["true_damage_bonus"] = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.enemy_skills.reset_room()
	room.player.position = Vector2(1200,800)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	room.combat_audio.set_process(false)
	room.defeat_feedback.set_process(false)
	room.impact_feedback.set_process(false)
	room.gold_drops.clear()
	room.camera.set_physics_process(false)
	cues.clear()
	room.combat_audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))

func target(id: String = "M01", options: Dictionary = {}, offset: Vector2 = Vector2(100,0)) -> MineEnemy:
	var actor: MineEnemy = room.spawn_enemy(room.player.position + offset, id, 1, options)
	check(is_instance_valid(actor), id + " real enemy spawned")
	if is_instance_valid(actor):
		actor.health.reset(10.0)
		actor.training_ai_disabled = true
		actor.state = &"chase"
	return actor

func kill(actor: MineEnemy, direction: Vector2 = Vector2.RIGHT) -> void:
	room.resolve_direct_hit(actor, 10000.0, &"primary", "", 0.0, direction,
		{"damage_type":"true","equipment_eligible":false,"original_basic":false})

func owns_physics(node: Node) -> bool:
	if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D:
		return true
	for child: Node in node.get_children():
		if owns_physics(child):
			return true
	return false

func played(stream: AudioStream) -> bool:
	for voice: AudioStreamPlayer in room.combat_audio._players:
		if voice.stream == stream:
			return true
	return false

func _run() -> void:
	if not str(Game.profile_path).contains("test_defeat_integration"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "real isolated run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	await test_direct_death()
	test_materials_and_dot()
	test_summons_and_exclusions()
	test_crowd_and_lifecycle()
	test_legacy_layout_reload()
	test_reduced_and_pause()
	if DisplayServer.get_name() != "headless":
		await capture_deaths()
	get_tree().paused = false
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("DEFEAT INTEGRATION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func test_direct_death() -> void:
	fixture()
	var actor: MineEnemy = target()
	var source_frame: Dictionary = actor.body_visual.body_frame()
	var source_transform: Transform2D = actor.body_visual.global_transform
	room.enemy_skills.emit_skill(actor, {"kind":"projectile","delay":0.5,"speed":300.0,"target":room.player.position})
	check(room.enemy_skills.active_effect_count() > 0, "real delayed enemy attack exists before death")
	var before_kills: int = Game.run.kills
	var before_gold: int = Game.run.gold
	var actor_ref: WeakRef = weakref(actor)
	kill(actor, Vector2(0.8,0.6))
	check(not actor.is_alive() and actor.is_queued_for_deletion(), "death is immediate and actor queued for release")
	check(Game.run.kills == before_kills + 1 and int(room.telemetry.kills) == 1, "real death counts once immediately")
	check(room.enemy_skills.active_effect_count() == 0, "death cancels real delayed enemy attack immediately")
	check(room.gold_drops.size() == 1 and int(room.gold_drops[0].amount) == Balance.GOLD_PER_ENEMY, "death creates one normal gold drop immediately")
	check(room.defeat_feedback.events.size() == 1, "death creates one detached body")
	var event: Dictionary = room.defeat_feedback.events[0]
	var body: Node2D = event.body
	check(event.frame.texture == source_frame.texture and event.frame.texture != null and event.frame.region == source_frame.region and event.frame.bounds == source_frame.bounds, "real current enemy frame copied exactly")
	check(body.global_transform.is_equal_approx(source_transform), "body starts at exact visible actor frame transform")
	check(not owns_physics(room.defeat_feedback), "detached presentation contains no collision object or shape")
	check(cues.count("defeat") == 1 and cues.count("impact") == 1, "real lethal basic gives separate kill and confirmed contact cues")
	kill(actor)
	actor.tick_statuses(2.0)
	check(Game.run.kills == before_kills + 1 and room.defeat_feedback.events.size() == 1 and room.gold_drops.size() == 1, "damage after death cannot duplicate corpse or rewards")
	room.player.position = actor.position
	room._update_gold(0.01)
	check(Game.run.gold == before_gold + Balance.GOLD_PER_ENEMY and room.gold_drops.is_empty(), "gold remains collectible before visual body expires")
	var through: Vector2 = room.move_actor(actor.position - Vector2(35,0), Vector2(70,0), 10.0)
	check(through.is_equal_approx(actor.position + Vector2(35,0)), "player movement can cross detached body immediately")
	await get_tree().process_frame
	await get_tree().process_frame
	check(actor_ref.get_ref() == null and is_instance_valid(body), "actor actually freed next frame while body remains")
	room.defeat_feedback.advance(0.5)
	check(not is_instance_valid(body) and room.defeat_feedback.events.is_empty(), "body expires independently after actor release")

func test_materials_and_dot() -> void:
	for pair: Array in [["M01","metal"],["M10","organic"],["M31","stone"]]:
		fixture()
		var actor: MineEnemy = target(pair[0])
		kill(actor)
		check(room.defeat_feedback.events[0].material == pair[1], pair[0] + " actual body uses expected death material")
		check(played(room.combat_audio.stream_for("", "defeat", 0, pair[1])), pair[0] + " plays matching material Foley")
	fixture()
	var burning: MineEnemy = target("M10")
	var before_kills: int = Game.run.kills
	burning.apply_status("burn", 1000.0, 2.0)
	burning.tick_statuses(1.01)
	check(not burning.is_alive() and Game.run.kills == before_kills + 1, "real burn tick kills normally")
	check(room.defeat_feedback.events.size() == 1 and cues.count("defeat") == 1, "periodic death gets body and death Foley")
	check(room.impact_feedback.accepted_events == 0 and not cues.has("impact") and not cues.has("heavy"), "periodic death invents no direct-hit flash or impact cue")
	check(room.camera.impact_stats().started == 0 and is_zero_approx(room.player.visual_hitstop), "periodic death invents no hit pause or camera kick")

func test_summons_and_exclusions() -> void:
	fixture()
	var caster: MineEnemy = target("M10", {}, Vector2(200,0))
	var summon: MineEnemy = room.spawn_enemy_summon(caster, "M01", room.player.position + Vector2(60,60))
	check(is_instance_valid(summon) and not summon.reward_enabled, "real summon spawns without reward eligibility")
	if is_instance_valid(summon):
		summon.health.reset(10.0)
		summon.state = &"chase"
		var before_kills: int = Game.run.kills
		kill(summon)
		check(room.defeat_feedback.events.size() == 1 and cues.has("defeat"), "true summon kill has visual and audio finish")
		check(Game.run.kills == before_kills and room.gold_drops.is_empty(), "summon death adds no farming rewards")
	for kind: String in ["objective","cover"]:
		fixture()
		var actor: MineEnemy = target("", {"actor_kind":kind,"static_actor":true,"reward_enabled":false})
		kill(actor)
		check(not actor.is_alive() and room.defeat_feedback.events.is_empty() and not cues.has("defeat"), kind + " break does not receive monster corpse or death cue")
	fixture()
	var boss: MineEnemy = target("M31")
	boss.rank = "boss"
	kill(boss)
	check(not boss.is_alive() and room.defeat_feedback.events.is_empty() and not cues.has("defeat"), "boss rank leaves dedicated boss exit presentation intact")

func test_crowd_and_lifecycle() -> void:
	fixture()
	for index in 26:
		var actor: MineEnemy = target("M01", {}, Vector2(60 + (index % 5) * 45, (index / 5) * 45))
		kill(actor)
		check(room.defeat_feedback.events.size() <= 20 and room.defeat_feedback.get_child_count() <= 20, "same-frame mass kill stays bounded " + str(index))
	check(room.defeat_feedback.events.size() == 20 and room.defeat_feedback.culled_events == 6, "mass kill cap replaces oldest bodies")
	check(cues.count("defeat") == 1, "simultaneous kill Foley coalesces instead of stacking 26 voices")
	var detached_ref: WeakRef = weakref(room.defeat_feedback.events[0].body)
	var layer_ref: WeakRef = weakref(room.defeat_feedback)
	room.free()
	check(detached_ref.get_ref() == null and layer_ref.get_ref() == null, "room teardown releases layer and all bodies")
	room = null

func test_legacy_layout_reload() -> void:
	fixture()
	var actor: MineEnemy = target()
	kill(actor)
	var event: Dictionary = room.defeat_feedback.events[0]
	var body_ref: WeakRef = weakref(event.body)
	var old_layout: String = room.layout_id
	check(not room.load_room_layout("INVALID_DEFEAT_TEST_LAYOUT", 0, 41827), "invalid legacy candidate fails before commit")
	check(room.layout_id == old_layout and room.defeat_feedback.events.size() == 1 and body_ref.get_ref() == event.body, "failed legacy reload preserves existing death body")
	check(room.load_room_layout("L02", 0, 41827), "real legacy room reload commits valid layout")
	check(room.layout_id == "L02" and room.defeat_feedback.events.is_empty() and room.defeat_feedback.get_child_count() == 0 and body_ref.get_ref() == null, "successful legacy reload clears and releases previous death body")

func test_reduced_and_pause() -> void:
	fixture(true)
	var actor: MineEnemy = target()
	kill(actor)
	var event: Dictionary = room.defeat_feedback.events[0]
	var original: Transform2D = event.body.transform
	check(bool(event.reduced), "real reduced-effects setting reaches death layer")
	room.defeat_feedback.advance(0.07)
	check(event.body.transform == original and event.body.modulate.a < 1.0, "reduced body fades without movement")
	var age: float = event.age
	get_tree().paused = true
	room.defeat_feedback.advance(1.0)
	check(is_equal_approx(event.age, age) and room.defeat_feedback.events.size() == 1, "pause freezes body lifetime")
	room.combat_audio.advance(1.0)
	check(room.combat_audio.active_voice_count() == 0, "pause stops death audio pool")
	get_tree().paused = false
	room.defeat_feedback.advance(0.12)
	check(room.defeat_feedback.events.is_empty(), "reduced body disappears within 0.2 seconds after resume")

func capture_deaths() -> void:
	fixture()
	room.player.position = Vector2(1400,900)
	room.camera.follow_target()
	room.camera.zoom = Vector2(1.7,1.7)
	room.camera.force_update_scroll()
	var targets: Array[MineEnemy] = []
	for index in 3:
		var actor: MineEnemy = target(["M01","M10","M31"][index], {}, Vector2(100,(index - 1) * 115))
		targets.append(actor)
		room.resolve_direct_hit(actor, 2.0, &"secondary", "", 0.0, Vector2.RIGHT,
			{"damage_type":"true","equipment_eligible":false,"original_basic":false})
	await RenderingServer.frame_post_draw
	for actor: MineEnemy in targets:
		kill(actor)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var previous_ms: int = 0
	for time_ms: int in [15,120,320]:
		var delta: float = float(time_ms - previous_ms) / 1000.0
		previous_ms = time_ms
		room.defeat_feedback.advance(delta)
		room.impact_feedback.advance(delta)
		room.player.get_node("HeroFeedback").advance(delta)
		room.player.queue_redraw()
		room.queue_redraw()
		await RenderingServer.frame_post_draw
		var frame: Image = get_viewport().get_texture().get_image()
		var path: String = "res://artifacts/enemy_defeat_materials_%dms.png" % time_ms
		check(frame.save_png(path) == OK, "saves actual three-material death frame at %d ms" % time_ms)
