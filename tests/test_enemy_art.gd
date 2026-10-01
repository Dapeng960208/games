extends Node
## Actual MineEnemy/MineBoss bodies validate the active forty-creature family.
## Headless checks cover foot/contact registration, private flash and snapshots;
## final visual acceptance belongs to the graphical preview.
const Art = preload("res://scripts/combat/enemy_art.gd")
const Visual = preload("res://scripts/combat/enemy_visual.gd")
const Enemy = preload("res://scripts/combat/enemy.gd")
const Boss = preload("res://scripts/combat/boss.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const BossProfilesScript = preload("res://scripts/combat/boss_profiles.gd")
const Feedback = preload("res://scripts/combat/enemy_defeat_feedback.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
var checks := 0
var failures := 0
var room: Node2D
var images: Dictionary = {}

class RoomFixture extends Node2D:
	var enemy_skills: Node2D
	var enemy_props: Node2D
	var telemetry: Dictionary = {"burn_ticks":0}
	var player: Node2D
	var enemies: Node2D
	var fx_font: Font
	var wall_x: float = INF
	var charges: Array[Dictionary] = []
	func add_damage_text(_at: Vector2, _amount: float, _kind: StringName) -> void:
		pass
	func enemy_died(_enemy: Node2D) -> void:
		pass
	func move_actor(origin: Vector2, delta: Vector2, radius: float) -> Vector2:
		var end: Vector2 = origin + delta
		end.x = minf(end.x, wall_x - radius)
		return end
	func blocked_fraction(origin: Vector2, end: Vector2, radius: float = 0.0) -> float:
		if end.x <= wall_x - radius or end.x <= origin.x:
			return 1.0
		return clampf((wall_x - radius - origin.x) / (end.x - origin.x), 0.0, 1.0)
	func enemy_skill_targets() -> Array:
		return []
	func notify_enemy_charge(caster: Node2D, origin: Vector2, end: Vector2) -> void:
		charges.append({"id":caster.get_instance_id(), "origin":origin, "end":end})

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ENEMY ART FAIL: " + label)

func spawn(identity: String, elite: bool = false) -> MineEnemy:
	var actor: MineEnemy
	if identity.begins_with("BO"):
		actor = Boss.new()
		check(actor.configure_boss(identity), identity + " resolves a real boss profile")
	else:
		actor = Enemy.new()
		actor.configure(Profiles.resolve(identity, 8, "elite" if elite else "normal"))
	actor.room = room
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	room.add_child(actor)
	return actor

func run_checks() -> void:
	if not Game.profile_path.contains("test_enemy_art"):
		push_error("Enemy art acceptance requires its isolated profile")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated real run starts")
	room = RoomFixture.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.enemies = Node2D.new()
	room.add_child(room.enemies)
	room.enemy_skills = Runtime.new()
	room.add_child(room.enemy_skills)
	room.enemy_skills.configure(room)
	_test_parse_and_motion_gates()
	for index: int in range(1, 37):
		_test_body("M%02d" % index)
	for identity: String in BossProfilesScript.ids():
		_test_body(identity)
	_test_private_elite_flash_and_snapshot()
	_test_counters()
	_test_charge_bridge()
	room.free()
	Game.finish_run("abandoned")
	await get_tree().process_frame
	print("ENEMY ART: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _test_body(identity: String) -> void:
	var entry: Dictionary = Art.entry_for(identity)
	check(not entry.is_empty(), identity + " has an active painted body")
	if entry.is_empty():
		return
	var biome_index: int = int(identity.trim_prefix("BO")) if identity.begins_with("BO") else int(ceil(float(int(identity.trim_prefix("M"))) / 9.0))
	check(entry.biome_id == "B%02d" % biome_index and entry.visual_clan == ["晴辉构装", "琥珀虫族", "南瓜僵尸", "赤岩兽人"][biome_index - 1], identity + " belongs to its final canonical clan")
	check(str(entry.texture_path).ends_with("_v2.png") and entry.source_family == Art.FAMILY, identity + " uses the approved replacement source")
	var actor: MineEnemy = spawn(identity)
	var expected_radius: float = float(BossProfilesScript.STATS[identity].navigation_radius) if identity.begins_with("BO") else float(Profiles.resolve(identity, 8).navigation_radius)
	var expected_height: float = clampf(expected_radius * 3.45, 170.0, 220.0) if identity.begins_with("BO") else clampf(expected_radius * 3.8, 66.0, 88.0)
	var foot_y: float = 48.0 if identity.begins_with("BO") else 18.0
	check(is_equal_approx(actor.navigation_radius, expected_radius) and is_equal_approx(actor.body_bounds.size.y, expected_height) and is_equal_approx(actor.body_bounds.end.y, foot_y), identity + " preserves gameplay radius, native height and pivot")
	var visual: EnemyVisual = actor.body_visual
	var frame: Dictionary = visual.body_frame()
	check(visual.asset_mode == "storybook_static" and frame.texture == entry.texture and frame.region == entry.region and frame.full_color and frame.source_family == Art.FAMILY, identity + " installs one complete new static identity")
	var mapped_foot: Vector2 = frame.bounds.position + (entry.foot - entry.region.position) * expected_height / float(entry.source_height)
	check(mapped_foot.length() < 0.001, identity + " source foot maps to the ground pivot")
	check(bool(visual.material.get_shader_parameter("preserve_source_color")) and is_zero_approx(float(visual.material.get_shader_parameter("palette_mix"))) and actor.material == null, identity + " keeps full source colors and isolates the body shader")
	var source_key: String = entry.texture_path
	if not images.has(source_key):
		images[source_key] = entry.texture.get_image()
	var source: Image = images[source_key]
	check(source != null and source.get_pixel(0, 0).a < 0.01 and source.get_size() == Vector2i(1983, 793), identity + " has transparent raw atlas corners and measured dimensions")
	for state: StringName in [&"chase", &"telegraph", &"locked", &"execute", &"recovery"]:
		actor.state = state
		actor.state_time = 0.3
		actor.position += Vector2(2, 0)
		visual.advance(0.016)
		var current: Dictionary = visual.body_frame()
		check(current.texture == frame.texture and current.region == frame.region and visual.asset_mode == "storybook_static", identity + " / " + str(state) + " never returns to an old animated body")
	actor.state = &"idle"
	visual.advance(0.10)
	var surface: Dictionary = actor.impact_anchor(Vector2.RIGHT)
	check(not surface.is_empty() and surface.anchor.get_ref() == visual and frame.bounds.grow(0.01).has_point(surface.local_offset), identity + " provides an actual opaque silhouette contact")
	if identity == "M35":
		check(actor.empty_body_texture == entry.texture and visual.body_frame().texture == entry.texture, "M35 empty/carry states retain the new orc body")
	actor.free()

func _test_parse_and_motion_gates() -> void:
	var valid: Dictionary = {"region":[0,0,80,100],"foot":[40,100],"source_height":100,"full_color":true}
	check(not Art.parse_entry(valid, Vector2(80,100)).is_empty(), "static metadata accepts a measured foot and source height")
	for key: String in ["foot", "source_height", "region", "full_color"]:
		var broken: Dictionary = valid.duplicate(true)
		broken[key] = {"foot":[40,101],"source_height":98,"region":[0,0,90,100],"full_color":false}[key]
		check(Art.parse_entry(broken, Vector2(80,100)).is_empty(), "invalid static " + key + " is rejected")
	var motion: Dictionary = {"source_family":Art.FAMILY,"full_color":true,"enemy_id":"M10","quality_gate_passed":true}
	check(Visual.storybook_motion_approved(motion, "M10"), "reviewed same-creature motion can opt in")
	check(not Visual.storybook_motion_approved(motion, "M01"), "an insect bank cannot animate the new construct M01")
	motion.quality_gate_passed = false
	check(not Visual.storybook_motion_approved(motion, "M10"), "a failed quality gate keeps the new static fallback")
	var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(Art.motion_path("M10")))
	check(candidate is Dictionary and candidate.enemy_id == "M10" and candidate.quality_gate_passed == false and not Visual.storybook_motion_approved(candidate, "M10"), "the actual M10 candidate remains explicitly unapproved")
	if candidate is Dictionary:
		var size: Array = candidate.image_size
		var bank: Dictionary = Visual.parse_motion_manifest(candidate, Vector2(float(size[0]), float(size[1])))
		check(not bank.is_empty() and bank.clips.walk.size() == 8 and bank.clips.recoil.size() == 4 and is_equal_approx(float(bank.clips.execute[0].name), 10.0), "candidate metadata preserves all measured canonical clips for later review")

func _test_private_elite_flash_and_snapshot() -> void:
	var first: MineEnemy = spawn("M01", true)
	var second: MineEnemy = spawn("M10")
	var material: ShaderMaterial = first.body_visual.material
	check(first.rank == "elite" and material != second.body_visual.material, "elites retain rank and own a private flash material")
	first.receive_confirmed_impact(Vector2.RIGHT, 1.0, true)
	check(float(material.get_shader_parameter("impact_mix")) > 0.0 and is_zero_approx(float(second.body_visual.material.get_shader_parameter("impact_mix"))), "a confirmed hit flashes only the contacted enemy")
	first.set_meta("enemy_shadow_stealth", true)
	first.modulate.a = 0.8
	var feedback := Feedback.new()
	room.add_child(feedback)
	feedback.set_process(false)
	feedback.reduced_fx_override = 0
	check(feedback.capture(first, Vector2.RIGHT), "new painted body can be captured before death")
	if not feedback.events.is_empty():
		var event: Dictionary = feedback.events[0]
		var body: Node2D = event.body
		check(body.frame.source_family == Art.FAMILY and body.frame.texture == first.body_texture and body.material != material and bool(body.material.get_shader_parameter("preserve_source_color")), "death keeps the new texture and copies its full-color private material")
		check(is_equal_approx(body.modulate.a, 0.28), "snapshot preserves actor alpha and stealth alpha")
		first.free()
		feedback.advance(0.20)
		check(body.modulate.a < 0.28 and is_zero_approx(float(body.material.get_shader_parameter("impact_mix"))), "snapshot fades and releases flash after its live actor is gone")
		feedback.advance(0.5)
		check(feedback.events.is_empty(), "new-art snapshot retires without a stale actor reference")
	else:
		first.free()
	feedback.free()
	second.free()

func _test_counters() -> void:
	var actor: MineEnemy = spawn("M08")
	actor.brain = null
	actor.health.reset(10000.0)
	actor.armor = 100.0
	check(not actor.apply_biome_counter("grave_seal") and not actor.apply_biome_counter("war_drum", NAN), "unsupported or nonfinite counters return false")
	var before: float = actor.health.current
	check(actor.take_damage(100.0, &"equipment", Vector2.ZERO, {"damage_type":"physical"}), "baseline physical packet resolves")
	check(is_equal_approx(before - actor.health.current, 50.0), "baseline uses actual armor")
	actor.status.grant_guard(100.0, 10.0, "fixture", actor.health.maximum)
	var guard: Dictionary = {"owner":weakref(actor),"owner_id":actor.get_instance_id(),"kind":"guard","target_ref":weakref(actor),"remaining":10.0,"amount":100.0,"mode":"guard"}
	room.enemy_skills.supports.append(guard)
	check(actor.apply_biome_counter("solar_conduit") and actor.status.shield() == 0.0 and room.enemy_skills.supports.is_empty(), "solar counter removes both status and actual runtime shields")
	before = actor.health.current
	actor.take_damage(100.0, &"equipment", Vector2.ZERO, {"damage_type":"physical"})
	check(is_equal_approx(before - actor.health.current, 67.5), "solar weakness affects actual resolved damage once")
	check(actor.apply_biome_counter("war_drum") and actor.effective_armor() == 0.0 and actor.armor == 100.0, "war strips effective defense without replacing base armor")
	before = actor.health.current
	actor.take_damage(100.0, &"equipment", Vector2.ZERO, {"damage_type":"physical"})
	check(is_equal_approx(before - actor.health.current, 135.0), "war armor break and overlapping weakness do not stack multipliers")
	actor.armor = 70.0
	get_tree().paused = true
	var remaining: Dictionary = actor.biome_counter_status().remaining
	actor.tick_statuses(2.0)
	check(actor.biome_counter_status().remaining == remaining and not actor.apply_biome_counter("brood_egg"), "paused counters neither expire nor accept another activation")
	get_tree().paused = false
	actor.tick_statuses(6.0)
	check(not actor.biome_weakpoint_open() and actor.effective_armor() == 70.0, "expiry preserves a natural armor change made during the opening")
	check(actor.apply_biome_counter("brood_egg", 1.0), "brood counter opens a real weak point")
	actor.tick_statuses(0.4)
	actor.apply_biome_counter("brood_egg", 1.0)
	actor.tick_statuses(0.9)
	check(actor.biome_weakpoint_open(), "repeated counters refresh the single window")
	actor.configure(Profiles.resolve("M08", 8))
	check(not actor.biome_weakpoint_open(), "reconfigure clears arena openings")
	actor.actor_kind = "objective"
	check(not actor.apply_biome_counter("war_drum"), "objective actors reject combat counters")
	actor.actor_kind = "enemy"
	actor.health.dead = true
	check(not actor.apply_biome_counter("solar_conduit") and not actor.biome_weakpoint_open(), "dead actors reject and hide counter openings")
	actor.free()

func _test_charge_bridge() -> void:
	var actor: MineEnemy = spawn("M02")
	actor.state = &"execute"
	actor.position = Vector2(20,50)
	var runtime: EnemySkillRuntime = room.enemy_skills
	var command: Dictionary = {"kind":"charge","origin":actor.position,"target":Vector2(220,50),"direction":Vector2.RIGHT,"travel_distance":200.0,"duration":0.4,"radius":18.0}
	runtime.emit_skill(actor, command)
	runtime.advance(0.20)
	check(room.charges.is_empty(), "charge bridge waits for actual travel completion")
	runtime.advance(0.20)
	check(room.charges.size() == 1 and room.charges[0].origin == Vector2(20,50) and room.charges[0].end == actor.position and is_equal_approx(actor.position.x, 220.0), "completed charge forwards the real travelled endpoints once")
	runtime.advance(0.50)
	check(room.charges.size() == 1, "retired charge cannot repeat its counter notification")
	room.wall_x = 140.0
	actor.position = Vector2(20,50)
	command.origin = actor.position
	runtime.emit_skill(actor, command)
	runtime.advance(0.4)
	check(room.charges.size() == 2 and is_equal_approx(room.charges[1].end.x, 140.0 - actor.navigation_radius) and room.charges[1].end.x < 220.0, "wall stop forwards only the reached endpoint")
	room.wall_x = INF
	actor.position = Vector2(20,50)
	command.origin = actor.position
	command.path_mode = "arc"
	command.arc_height = 60.0
	runtime.emit_skill(actor, command)
	runtime.advance(0.4)
	check(room.charges.size() == 2 and not runtime.has_motion(actor), "curved charge does not claim its untravelled endpoint chord")
	command.erase("path_mode")
	command.erase("arc_height")
	actor.position = Vector2(20,50)
	command.origin = actor.position
	runtime.emit_skill(actor, command)
	runtime.advance(0.1)
	runtime.cancel_displaced_motion(actor)
	runtime.advance(0.5)
	check(room.charges.size() == 2 and not runtime.has_motion(actor), "displacement cancellation does not claim an untravelled route")
	actor.free()
