extends "res://tests/test_enemy_presentation.gd"
## CPU-only silhouette, transform and class-reaction checks. No live profile or
## collision mutation; synthetic alpha makes the actual surface measurable.

func _run() -> void:
	var fixture: Array = _fixture()
	var actor: ActorStub = fixture[0]
	var visual: Visual = fixture[1]
	var image := Image.create(64, 80, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(15, 66):
		for x in range(17, 46):
			image.set_pixel(x, y, Color.WHITE)
	actor.body_texture = ImageTexture.create_from_image(image)
	actor.body_region = Rect2(0, 0, 64, 80)
	actor.body_bounds = Rect2(-32, -62, 64, 80)
	actor.state = &"idle"
	visual.configure(actor)
	var physics_origin: Vector2 = actor.position
	var original_bounds: Rect2 = actor.body_bounds
	var frame: Dictionary = visual.body_frame()
	var key: int = actor.body_texture.get_instance_id()
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var result: Dictionary = visual.contact_anchor(direction)
		_check(result.get("anchor") is WeakRef and result.anchor.get_ref() == visual, "Contact retains only a weak visual reference")
		var point: Vector2 = result.local_offset
		var mask: BitMap = Visual._contact_masks[key]
		_check(Visual._opaque_contact(mask, frame.region, frame.bounds, point), "Contact lies on a real opaque surface " + str(direction))
		_check(not Visual._opaque_contact(mask, frame.region, frame.bounds, point - direction * 1.1), "Contact is the incoming edge rather than arbitrary torso center " + str(direction))
	var cached_mask: BitMap = Visual._contact_masks[key]
	for index in 30: visual.contact_anchor(Vector2.from_angle(index * 0.3))
	_check(Visual._contact_masks[key] == cached_mask, "Repeated contacts reuse the CPU alpha bitmap without replacing/decoding it")
	visual.scale = Vector2(-1.15, 0.85)
	visual.rotation = 0.14
	visual.position += Vector2(4, -3)
	actor.position = Vector2(90, 60)
	actor.rotation = -0.2
	var result: Dictionary = visual.contact_anchor(Vector2.RIGHT)
	var local_point: Vector2 = result.local_offset
	var global_direction: Vector2 = Vector2.RIGHT
	var local_direction: Vector2 = visual.global_transform.basis_xform_inv(global_direction).normalized()
	_check(Visual._opaque_contact(cached_mask, frame.region, frame.bounds, local_point), "Mirrored rotated recoil contact stays on opaque art")
	_check(not Visual._opaque_contact(cached_mask, frame.region, frame.bounds, local_point - local_direction * 1.1), "Incoming direction is converted through the full visual transform")
	var prior: Vector2 = visual.to_global(local_point)
	visual.position += Vector2(7, -2)
	visual.rotation += 0.08
	_check(visual.to_global(local_point).distance_to(prior) > 1.0, "A persistent visual-local point follows recoil translation and rotation")
	actor.position = physics_origin
	actor.rotation = 0.0
	visual.facing = 1.0
	var poses: Dictionary = {}
	for hero in ["CH01", "CH02", "CH03"]:
		visual.advance(0.4)
		visual.advance(0.4)
		visual.advance(0.4)
		visual.receive_impact(Vector2.RIGHT, 1.0, false, hero)
		poses[hero] = {"offset":visual.body_offset, "scale":visual.body_scale, "duration":visual._impact_duration}
		_check(visual.flash_strength > 0.0 and visual.flash_strength <= 0.60, hero + " keeps texture detail during confirmed flash")
		var initial_flash: float = visual.flash_strength
		visual.advance(0.008)
		_check(is_equal_approx(visual.flash_strength, initial_flash), hero + " contact flash has a short steady readable hold")
		for step in 5: visual.advance(0.1)
		_check(visual.flash_strength == 0.0 and visual.body_offset.length() < 0.001, hero + " finishes without lingering recoil")
	_check(poses.CH01.scale.x < poses.CH02.scale.x and poses.CH01.offset.x > poses.CH02.offset.x, "Hammer compresses more strongly than a narrow gun puncture")
	_check(poses.CH03.scale.x < 1.0 and poses.CH03.scale.y < 1.0, "Crystal contact contracts in both axes rather than copying gun recoil")
	_check(poses.CH02.duration < poses.CH01.duration, "Gun reaction settles earlier than heavy tool impact")
	visual.receive_impact(Vector2.DOWN, 1.0, false, "CH01")
	_check(visual.body_scale.y < 0.94 and visual.body_scale.x > 1.0, "Vertical hammer hit rotates the compression axis")
	visual.reduced_fx_override = 1
	visual.receive_impact(Vector2.DOWN, 1.3, true, "CH01")
	_check(visual.flash_strength == 0.0 and visual.body_offset.length() < 6.0, "Reduced effects keeps a restrained flash-free confirmation")
	_check(actor.position == physics_origin and actor.body_bounds == original_bounds and actor.velocity == Vector2(100, 0), "Anchor sampling and impacts do not mutate physical data")
	Visual._contact_masks.erase(key)
	_check(visual.contact_anchor(Vector2.RIGHT).is_empty() and not Visual._contact_masks.has(key), "A missing prewarmed mask falls back without decoding an image during impact")
	actor.body_texture = null
	_check(visual.contact_anchor(Vector2.RIGHT).is_empty(), "Absent body texture safely falls back to the actor contact")
	actor.free()
	if failures.is_empty(): print("CONTACT SURFACE PASS: %d checks" % checks)
	quit(0 if failures.is_empty() else 1)
