extends Node
## Deterministic contact motion, accessibility and pause checks; no GPU required.

const CameraScript = preload("res://scripts/gameplay/world/world_camera.gd")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	if not Game.profile_path.contains("test_directional_hit_camera"):
		get_tree().quit(2)
		return
	Game.profile.settings.reduced_fx = false
	var camera = CameraScript.new()
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera)
	var room := Node2D.new()
	var player := Node2D.new()
	add_child(room)
	room.add_child(player)
	room.position = Vector2(50, 30)
	player.position = Vector2(400, 300)
	camera.configure(room, player, Rect2(0, 0, 2800, 1800))
	check(camera.global_position == player.global_position, "camera still follows world position")
	check(camera.zoom == Vector2(.85, .85), "world zoom retained")
	check(camera.limit_left == -14 and camera.limit_top == -34 and camera.limit_right == 2914 and camera.limit_bottom == 1894, "render margin and global arena limits retained")
	check(not bool(Game.profile.settings.get("camera_shake", false)), "fresh profile defaults to a steady camera")
	for contact: int in 60:
		camera.impact(50.0, Vector2.RIGHT if contact % 2 == 0 else Vector2.DOWN, true)
		player.position += Vector2(3, 2)
		camera._physics_process(.016)
		check(camera.offset == Vector2.ZERO and camera.impact_remaining == 0.0, "default contact burst leaves world offset exactly zero")
		check(camera.global_position == player.global_position, "default camera continues to follow during a contact burst")
	check(camera.impact_stats().started == 0 and camera.impact_stats().peak_offset == 0.0, "default hit burst never starts camera motion")
	Game.profile.settings.erase("camera_shake")
	camera.impact(50.0, Vector2.RIGHT, true)
	check(camera.offset == Vector2.ZERO and camera.impact_stats().started == 0, "older preferences without camera_shake use the comfort default")
	Game.profile.settings.camera_shake = true
	Game.changed.emit()
	for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2(-3, 4)]:
		camera.impact(50.0, direction)
		check(is_equal_approx(camera.offset.length(), 1.85), "light contact bounded below two world pixels")
		check(camera.offset.normalized().is_equal_approx(direction.normalized()), "initial kick follows supplied direction")
		var rebounded: bool = false
		for sample: int in 22:
			camera._physics_process(.005)
			check(absf(camera.offset.cross(direction.normalized())) < .0001, "motion remains on contact axis")
			check(camera.offset.length() <= 1.85001, "motion never overshoots amplitude")
			if camera.offset.dot(direction) < -.00001: rebounded = true
		check(rebounded, "light contact has one shallow counter movement")
		check(camera.offset == Vector2.ZERO and camera.impact_strength == 0.0, "light contact returns exactly to rest by 110ms")
		camera._physics_process(1.0)
	camera.impact(100.0, Vector2.LEFT, true)
	check(is_equal_approx(camera.offset.length(), 3.5), "heavy contact bounded to 3.5 world pixels")
	check(is_equal_approx(camera.impact_remaining, .145), "heavy contact duration 145ms")
	camera._physics_process(.02)
	var before: Dictionary = camera.impact_stats()
	var previous_offset: Vector2 = camera.offset
	for victim: int in 20:
		camera.impact(2.0, Vector2.DOWN, true)
	check(camera.impact_stats().started == before.started, "same-attack crowd does not restart contact")
	check(camera.impact_stats().merged == before.merged + 20, "crowd contacts are accounted as merged")
	check(camera.impact_stats().elapsed == before.elapsed and camera.impact_remaining == before.remaining, "merge does not reset time")
	check(camera.offset == previous_offset, "weaker crowd contacts do not add shake or turn direction")
	camera._physics_process(1.0)
	camera.impact(.7, Vector2.RIGHT)
	camera._physics_process(.015)
	before = camera.impact_stats()
	camera.impact(3.0, Vector2.UP, true)
	check(camera.impact_stats().boosted == before.boosted + 1, "stronger contact can upgrade amplitude inside gate")
	check(camera.impact_strength == 3.0 and camera.impact_stats().elapsed == before.elapsed and camera.impact_remaining == before.remaining, "upgrade preserves original clock")
	check(camera.offset.y == 0.0 and camera.offset.x > 0.0, "upgrade preserves first directional contact")
	camera._physics_process(.045)
	before = camera.impact_stats()
	camera.impact(1.0, Vector2.DOWN)
	check(camera.impact_stats().started == before.started + 1 and camera.offset == Vector2.DOWN, "contact after 55ms can produce a fresh kick")
	player.position += Vector2(80, 60)
	camera._physics_process(.01)
	check(camera.global_position == player.global_position, "following continues independently of contact offset")
	before = camera.impact_stats()
	previous_offset = camera.offset
	get_tree().paused = true
	camera._physics_process(.5)
	camera.impact(3.5, Vector2.LEFT, true)
	check(camera.impact_stats().remaining == before.remaining and camera.offset == previous_offset, "pause freezes impact and ignores new contacts")
	Game.profile.settings.reduced_fx = true
	Game.changed.emit()
	check(camera.offset == Vector2.ZERO and camera.impact_remaining == 0.0 and camera.impact_strength == 0.0, "enabling reduced FX clears residual motion even while paused")
	get_tree().paused = false
	camera.impact(3.5, Vector2.RIGHT, true)
	camera._physics_process(.01)
	check(camera.offset == Vector2.ZERO and camera.impact_remaining == 0.0, "reduced FX rejects contact motion")
	Game.profile.settings.reduced_fx = false
	camera.impact(1.0)
	check(camera.offset == Vector2.UP, "old one-argument API has deterministic fallback direction")
	camera._physics_process(1.0)
	before = camera.impact_stats()
	for invalid_strength: float in [0.0, -1.0, NAN, INF]:
		camera.impact(invalid_strength, Vector2.RIGHT)
	check(camera.impact_stats().started == before.started and camera.offset == Vector2.ZERO, "invalid magnitudes cannot corrupt camera")
	camera.impact(1.0, Vector2(NAN, INF))
	check(camera.offset == Vector2.UP, "invalid direction uses safe fallback")
	camera._physics_process(1.0)
	check(camera.impact_stats().peak_offset <= 3.50001, "all recorded contact offsets remain bounded")
	camera.impact(3.5, Vector2.RIGHT, true)
	Game.profile.settings.camera_shake = false
	get_tree().paused = true
	Game.changed.emit()
	check(camera.offset == Vector2.ZERO and camera.impact_remaining == 0.0 and camera.impact_strength == 0.0, "disabling camera motion clears an active opt-in impact immediately while paused")
	get_tree().paused = false
	camera.impact(3.5, Vector2.RIGHT, true)
	check(camera.offset == Vector2.ZERO, "disabled camera motion rejects later contacts")
	camera.free()
	room.free()
	Game.changed.emit()
	print("DIRECTIONAL HIT CAMERA: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
