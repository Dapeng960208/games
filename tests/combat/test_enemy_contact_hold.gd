extends SceneTree
## The target's local contact pose holds while world movement and danger clocks
## keep running. Synthetic frames isolate timing/registration, not art quality.

const MotionFixture = preload("res://tests/support/monster_motion_fixture.gd")
const Visual = preload("res://scripts/presentation/monsters/enemy_visual.gd")
var failures: Array[String] = []
var checks: int = 0

class BrainStub:
	extends RefCounted
	var progress: float = 0.0
	func current_telegraph() -> Dictionary:
		return {"progress":progress}

class ActorStub:
	extends Node2D
	var static_actor: bool = false
	var profile: Dictionary = {"archetype":"skirmisher"}
	var enemy_id: String = ""
	var body_bounds := Rect2(-30, -52, 60, 70)
	var body_region := Rect2(0, 0, 8, 16)
	var body_texture: Texture2D
	var empty_body_texture: Texture2D
	var state: StringName = &"idle"
	var state_time: float = 0.0
	var aim_direction := Vector2.RIGHT
	var move_speed: float = 100.0
	var knockback := Vector2.ZERO
	var reaction_remaining: float = 0.0
	var brain: RefCounted = BrainStub.new()
	var pending := Vector2.ZERO
	func has_pending_displacement() -> bool:
		return not pending.is_zero_approx()

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _fixture() -> Array:
	var actor := ActorStub.new()
	var pixels := Image.create(40, 16, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	actor.body_texture = ImageTexture.create_from_image(pixels)
	root.add_child(actor)
	var visual := Visual.new()
	actor.add_child(visual)
	visual.reduced_fx_override = 0
	visual.configure(actor)
	var frames: Array = []
	for index in 5:
		frames.append({"name":str(index),"region":[index * 8, 0, 8, 16],"foot":[index * 8 + 4, 16]})
	var bank: Dictionary = MotionFixture.parse_motion_manifest({"body_height":16,"frames":frames,"clips":{"idle":["0"],"recoil":["1","2","3","4"]}}, Vector2(40,16))
	bank["texture"] = actor.body_texture
	visual.set("_bank", bank)
	return [actor, visual]

func _run() -> void:
	_test_contact_cadence()
	_test_burst_release()
	_test_passive_and_pause()
	_test_pending_displacement()
	if failures.is_empty():
		print("ENEMY CONTACT HOLD PASS: %d checks" % checks)
	quit(0 if failures.is_empty() else 1)

func _test_contact_cadence() -> void:
	for spec: Array in [["CH01",false,.042],["CH01",true,.074],["CH02",false,.015],["CH02",true,.030],["CH03",false,.024],["CH03",true,.038]]:
		var fixture: Array = _fixture()
		var actor: ActorStub = fixture[0]
		var visual: Visual = fixture[1]
		var label: String = "%s %s" % [spec[0], "heavy" if spec[1] else "light"]
		actor.state = &"telegraph"
		actor.state_time = .5
		actor.brain.progress = .2
		visual.advance(.001)
		visual.receive_impact(Vector2.RIGHT, 1.3 if spec[1] else .65, spec[1], spec[0])
		var local_pose: Transform2D = visual.transform
		var first_frame: Dictionary = visual.selected_frame.duplicate(true)
		var contact: Dictionary = visual.contact_anchor(Vector2.RIGHT)
		var surface_before: Vector2 = visual.to_global(contact.local_offset)
		var flash_before: float = visual.flash_strength
		var half: float = float(spec[2]) * .5
		actor.position += Vector2(7, -3)
		actor.state = &"locked"
		actor.state_time = .2
		actor.aim_direction = Vector2.LEFT
		actor.brain.progress = .83
		visual.advance(half)
		_check(visual.transform == local_pose and visual.selected_frame == first_frame, "%s keeps the same local contact pose and authored frame" % label)
		_check(visual.to_global(contact.local_offset).is_equal_approx(surface_before + Vector2(7,-3)), "%s surface contact follows the moving physics root without a second visual path" % label)
		_check(visual.phase == &"locked" and is_equal_approx(visual.phase_progress,.83) and actor.state_time == .2, "%s keeps reading live danger progress without changing its clock" % label)
		_check(visual.facing > 0.0 and visual.flash_strength <= flash_before, "%s holds facing while the material flash continues fading" % label)
		visual.advance(half + .002)
		_check(not visual.transform.is_equal_approx(local_pose) and float(visual.get("_impact_elapsed")) > 0.0, "%s releases at its cadence and consumes leftover frame time" % label)
		for _index in 24:
			visual.advance(.016)
		_check(float(visual.get("_contact_hold_remaining")) == 0.0 and float(visual.get("_impact_elapsed")) == float(visual.get("_impact_duration")), "%s recoil settles completely" % label)
		actor.free()

func _test_burst_release() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	visual.receive_impact(Vector2.RIGHT, .95, false, "CH01")
	visual.advance(.01)
	var remaining: float = visual.get("_contact_hold_remaining")
	visual.receive_impact(Vector2.LEFT, 1.3, true, "CH01")
	_check(visual.body_offset.x < 0.0 and float(visual.get("_contact_hold_remaining")) == remaining, "A heavy upgrade changes the pose without extending the original hold deadline")
	var held_pose: Transform2D = visual.transform
	for _index in 20:
		visual.receive_impact(Vector2.DOWN, .28, false, "CH03")
	_check(visual.transform == held_pose and float(visual.get("_contact_hold_remaining")) == remaining, "Derived ticks cannot rotate, overwrite or refresh a heavy contact hold")
	# Repeated direct heavy hits straddle the hold's release; this observes
	# actual recoil progression, not merely a counter reaching zero.
	for _index in 20:
		visual.receive_impact(Vector2.LEFT, 1.3, true, "CH01")
		visual.advance(.005)
	_check(float(visual.get("_contact_hold_remaining")) == 0.0 and float(visual.get("_impact_elapsed")) > .05 and not visual.transform.is_equal_approx(held_pose), "Dense equal contacts visibly release instead of pinning the body indefinitely")
	visual.advance(.02)
	visual.receive_impact(Vector2.RIGHT, 1.3, true, "CH01")
	_check(float(visual.get("_contact_hold_remaining")) > 0.0 and visual.body_offset.x > 0.0, "A later separate impact may start a new hold after visible recovery")
	actor.free()

func _test_passive_and_pause() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	visual.receive_impact(Vector2.RIGHT, .28, false, "CH03")
	var passive_pose: Transform2D = visual.transform
	visual.advance(.01)
	_check(float(visual.get("_contact_hold_remaining")) == 0.0 and not visual.transform.is_equal_approx(passive_pose), "A derived contact keeps a small flowing reaction without hit stop")
	for _index in 3:
		visual.advance(.1)
	visual.receive_impact(Vector2.RIGHT, 1.3, true, "CH01")
	var ordinary_offset: float = visual.body_offset.length()
	var before: Transform2D = visual.transform
	var remaining: float = visual.get("_contact_hold_remaining")
	paused = true
	visual.advance(.1)
	visual.receive_impact(Vector2.DOWN, 1.5, true, "CH02")
	_check(visual.transform == before and float(visual.get("_contact_hold_remaining")) == remaining, "Pause freezes contact state and ignores incoming presentation events")
	paused = false
	for _index in 4:
		visual.advance(.1)
	visual.reduced_fx_override = 1
	visual.receive_impact(Vector2.RIGHT, 1.3, true, "CH01")
	_check(visual.flash_strength == 0.0 and visual.body_offset.length() < ordinary_offset * .5 and float(visual.get("_contact_hold_remaining")) > 0.0, "Reduced effects preserves contact timing with less deformation and no material flash")
	actor.free()

func _test_pending_displacement() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	actor.state = &"chase"
	actor.pending = Vector2(12,0)
	for _index in 8:
		actor.position += Vector2(1.6,0)
		visual.advance(.016)
	_check(is_zero_approx(visual.stride_phase) and is_zero_approx(visual.movement_weight), "Resolved pending displacement does not create walking footfalls")
	actor.pending = Vector2.ZERO
	actor.position += Vector2(1.6,0)
	visual.advance(.016)
	_check(visual.stride_phase > 0.0 and visual.movement_weight > 0.0, "Voluntary movement resumes its gait once displacement ends")
	actor.free()
