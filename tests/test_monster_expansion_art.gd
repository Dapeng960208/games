extends Node
## Native source/registration checks only; no claim of pixel-level GPU review.
const Art = preload("res://scripts/combat/enemy_art.gd")
const Enemy = preload("res://scripts/combat/enemy.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Fixtures = preload("res://tests/test_enemy_art.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
const Metrics = preload("res://scripts/combat/presentation_metrics.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _ready() -> void: call_deferred("run_checks")

func run_checks() -> void:
	var room := Fixtures.RoomFixture.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.enemies = Node2D.new()
	room.add_child(room.enemies)
	room.enemy_skills = Runtime.new()
	room.add_child(room.enemy_skills)
	room.enemy_skills.configure(room)
	var sources := {}
	for index: int in range(37,55):
		var id := "M%02d" % index
		var entry := Art.entry_for(id)
		check(not entry.is_empty(), id + " owns a loaded painted body")
		if entry.is_empty(): continue
		check(bool(entry.get("individual_body",false)), id + " uses new anatomical registration")
		check(not sources.has(entry.texture_path), id + " does not reuse another species source")
		sources[entry.texture_path] = true
		var source: Image = entry.texture.get_image()
		check(source != null and source.get_width() >= 1200 and source.get_height() >= 1200, id + " retains native HD source")
		check(source != null and source.get_pixel(0,0).a < 0.01, id + " source has transparent corner")
		var actor := Enemy.new()
		var profile := Profiles.resolve(id,20,"normal",2,4)
		actor.configure(profile)
		actor.room = room
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		room.enemies.add_child(actor)
		var expected_height := clampf(actor.navigation_radius*3.8,66.0,88.0)*Metrics.ENEMY_BODY_FACTOR
		check(is_equal_approx(actor.body_bounds.size.y,expected_height) and is_equal_approx(actor.body_bounds.end.y,18.0), id + " shares ordinary height and foot pivot")
		check(is_equal_approx(actor.navigation_radius,float(profile.navigation_radius)), id + " art does not change gameplay collision")
		var frame: Dictionary = actor.body_visual.body_frame()
		check(frame.texture == entry.texture and frame.region == entry.region and bool(frame.full_color), id + " installs exact full-color native source")
		var foot: Vector2 = frame.bounds.position+(entry.foot-entry.region.position)*expected_height/float(entry.source_height)
		check(foot.length() < 0.001, id + " alpha foot maps to ground origin")
		check(actor.body_visual.skill_badge.identity == id, id + " owns independent combat badge")
		for phase: StringName in [&"chase",&"telegraph",&"locked",&"execute",&"recovery"]:
			actor.state = phase
			actor.state_time = 0.3
			actor.body_visual.advance(0.016)
			var next: Dictionary = actor.body_visual.body_frame()
			check(next.texture == entry.texture and next.region == entry.region, id + " keeps identity through " + str(phase))
		actor.free()
	check(sources.size() == 18, "18 independent sources installed")
	room.free()
	print("MONSTER_EXPANSION_ART: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
