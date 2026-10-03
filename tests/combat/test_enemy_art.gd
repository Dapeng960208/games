extends Node
## Actual actors validate the current 54 ordinary bodies and four bosses.
## Headless checks cover foot/contact registration, private flash and snapshots;
## final visual acceptance belongs to the graphical preview.
const Art = preload("res://scripts/presentation/monsters/enemy_art.gd")
const Visual = preload("res://scripts/presentation/monsters/enemy_visual.gd")
const Enemy = preload("res://scripts/gameplay/monsters/enemy_actor.gd")
const Boss = preload("res://scripts/gameplay/bosses/boss_actor.gd")
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const BossProfilesScript = preload("res://scripts/domain/combat/boss_profiles.gd")
const Feedback = preload("res://scripts/presentation/monsters/enemy_defeat_feedback.gd")
const Runtime = preload("res://scripts/gameplay/monsters/enemy_skill_runtime.gd")
const Metrics = preload("res://scripts/shared/presentation_metrics.gd")
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
	func add_damage_text(_at: Vector2, _amount: float, _kind: StringName, _context: Dictionary = {}) -> void:
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

func spawn(identity: String, elite: bool = false) -> EnemyActor:
	var actor: EnemyActor
	if identity.begins_with("BO"):
		actor = Boss.new()
		check(actor.configure_boss(identity, 0, 0, 2), identity + " resolves a real boss profile")
	else:
		actor = Enemy.new()
		actor.configure(Profiles.resolve(identity, 8, "elite" if elite else "normal", 2))
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
	_test_static_metadata()
	for index: int in range(1, 55):
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
	var biome_index: int = int(identity.trim_prefix("BO")) if identity.begins_with("BO") else int(str(Profiles.resolve(identity, 8, "normal", 2).biome_id).trim_prefix("B"))
	check(entry.biome_id == "B%02d" % biome_index and not str(entry.visual_clan).is_empty(), identity + " belongs to its current chapter and registered clan")
	check(FileAccess.file_exists(AssetCatalog.resolve(str(entry.texture_path))) and entry.source_family == Art.FAMILY, identity + " resolves its current registered source")
	var actor: EnemyActor = spawn(identity)
	var expected_radius: float = float(BossProfilesScript.STATS[identity].navigation_radius) if identity.begins_with("BO") else float(Profiles.resolve(identity, 8).navigation_radius)
	var expected_height: float = clampf(expected_radius * 3.45, 170.0, 220.0) if identity.begins_with("BO") else clampf(expected_radius * 3.8, 66.0, 88.0)
	expected_height *= Metrics.ENEMY_BODY_FACTOR
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
	var source_size := Vector2i(1254, 1254) if identity.begins_with("BO") or int(identity.trim_prefix("M")) >= 37 else Vector2i(1983, 793)
	check(source != null and source.get_pixel(0, 0).a < 0.01 and source.get_size() == source_size and Rect2(Vector2.ZERO, Vector2(source.get_size())).encloses(entry.region), identity + " preserves its raw source dimensions, transparency and region")
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
	var installed_bounds: Rect2 = actor.body_bounds
	Art.install(actor)
	check(actor.body_bounds.is_equal_approx(installed_bounds) and is_equal_approx(actor.navigation_radius, expected_radius), identity + " repeated registration preserves body scale and collision radius")
	actor.free()

func _test_static_metadata() -> void:
	var valid: Dictionary = {"region":[0,0,80,100],"foot":[40,100],"source_height":100,"full_color":true}
	check(not Art.parse_entry(valid, Vector2(80,100)).is_empty(), "static metadata accepts a measured foot and source height")
	for key: String in ["foot", "source_height", "region", "full_color"]:
		var broken: Dictionary = valid.duplicate(true)
		broken[key] = {"foot":[40,101],"source_height":98,"region":[0,0,90,100],"full_color":false}[key]
		check(Art.parse_entry(broken, Vector2(80,100)).is_empty(), "invalid static " + key + " is rejected")
	for identity: String in ["m01_motion_v1", "m10_storybook_motion_v1"]:
		check(not FileAccess.file_exists(AssetCatalog.resolve("asset://enemies/" + identity + ".json")), identity + " retired bank is absent")

func _test_private_elite_flash_and_snapshot() -> void:
	var first: EnemyActor = spawn("M01", true)
	var second: EnemyActor = spawn("M10")
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
	var actor: EnemyActor = spawn("M08")
	actor.brain = null
	actor.health.reset(10000.0)
	actor.armor = 100.0
	check(not actor.apply_biome_counter("grave_seal") and not actor.apply_biome_counter("war_drum", NAN), "unsupported or nonfinite counters return false")
	var before: float = actor.health.current
	check(actor.take_damage(100.0, &"equipment", Vector2.ZERO, {"damage_type":"physical"}), "baseline physical packet resolves")
	check(is_equal_approx(before - actor.health.current, 91.0), "current 1000-denominator defense rounds the baseline once")
	actor.status.grant_guard(100.0, 10.0, "fixture", actor.health.maximum)
	var guard: Dictionary = {"owner":weakref(actor),"owner_id":actor.get_instance_id(),"kind":"guard","target_ref":weakref(actor),"remaining":10.0,"amount":100.0,"mode":"guard"}
	room.enemy_skills.supports.append(guard)
	check(actor.apply_biome_counter("solar_conduit") and actor.status.shield() == 0.0 and room.enemy_skills.supports.is_empty(), "solar counter removes both status and actual runtime shields")
	before = actor.health.current
	actor.take_damage(100.0, &"equipment", Vector2.ZERO, {"damage_type":"physical"})
	check(is_equal_approx(before - actor.health.current, 123.0), "solar weakness applies before the current integer boundary")
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
	actor.configure(Profiles.resolve("M08", 8, "normal", 2))
	check(not actor.biome_weakpoint_open(), "reconfigure clears arena openings")
	actor.actor_kind = "objective"
	check(not actor.apply_biome_counter("war_drum"), "objective actors reject combat counters")
	actor.actor_kind = "enemy"
	actor.health.dead = true
	check(not actor.apply_biome_counter("solar_conduit") and not actor.biome_weakpoint_open(), "dead actors reject and hide counter openings")
	actor.free()

func _test_charge_bridge() -> void:
	var actor: EnemyActor = spawn("M02")
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
