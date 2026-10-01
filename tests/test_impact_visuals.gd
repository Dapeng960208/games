extends Node

const Contact = preload("res://scripts/combat/impact_feedback.gd")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Impact visuals: " + label)

func run_checks() -> void:
	if not Game.profile_path.contains("test_impact_visuals"):
		get_tree().quit(2)
		return
	check(Game.new_profile(), "isolated presentation profile")
	var fx = Contact.new()
	add_child(fx)
	fx.set_process(false)
	check(fx.z_index == 3, "contact above actors and below danger telegraphs")
	check(fx.process_mode == Node.PROCESS_MODE_INHERIT, "automatic processing follows room pause and disable state")
	for damage in [0.0, -1.0, NAN, INF]:
		fx.confirm_hit(Vector2.ZERO, Vector2.RIGHT, {"damage":damage})
		fx.add_floating_damage(Vector2.ZERO, damage, &"primary")
	check(fx.events.is_empty() and fx.accepted_events == 0, "immune/invalid amounts produce no confirmed hit or number")
	for hero in ["CH01", "CH02", "CH03"]:
		for material in ["stone", "metal", "organic"]:
			fx.clear_feedback()
			fx.confirm_hit(Vector2(100,100), Vector2(3,4), {"hero_id":hero,"material":material,"damage":14.0})
			check(fx.events.size() == 1, "one confirmed event for " + hero + material)
			check(fx.events[0].hero_id == hero and fx.events[0].material == material, "class and surface retained")
			check(is_equal_approx(fx.events[0].direction.length(), 1.0), "direction normalized")
			check(fx.events[0].radius <= 32.0 and fx.events[0].duration <= 0.28, "light contact compact and short")
	fx.clear_feedback()
	fx.confirm_hit(Vector2.ZERO, Vector2.ZERO, {"damage":30.0,"heavy":true,"critical":true,"killed":true,"hero_id":"invalid","material":"invalid"})
	check(fx.events[0].hero_id == "CH01" and fx.events[0].material == "stone" and fx.events[0].direction == Vector2.RIGHT, "unknown presentation inputs use deterministic fallback")
	check(fx.events[0].radius <= 52.0 and fx.events[0].radius >= 35.0 and fx.events[0].killed, "heavy critical remains local and keeps kill context")
	var age: float = fx.events[0].age
	get_tree().paused = true
	fx.advance(0.2)
	check(fx.events[0].age == age, "explicit advance cannot bypass scene pause")
	get_tree().paused = false
	fx.advance(0.1)
	check(is_equal_approx(fx.events[0].age, 0.1), "unpaused clock advances once")
	fx.advance(0.2)
	check(fx.events.is_empty(), "finished flashes removed")
	var actor := Node2D.new()
	add_child(actor)
	actor.position = Vector2(100, 150)
	var anchor: WeakRef = weakref(actor)
	var offset := Vector2(0, -32)
	fx.confirm_hit(actor.position + offset, Vector2.RIGHT, {"damage":10.0,"anchor":anchor,"anchor_offset":offset})
	var anchored: Dictionary = fx.events[0]
	actor.position.x += 65.0
	check(fx.contact_position(anchored) == actor.position + offset, "same-frame contact sampling follows immediate knockback")
	actor.position.y += 12.0
	fx.advance(0.04)
	check(anchored.at == actor.position + offset, "first 80ms anchor follows actual body position")
	actor.position.x += 5.0
	fx.advance(0.05)
	var detached: Vector2 = anchored.at
	actor.position.x += 30.0
	check(fx.contact_position(anchored) == detached and not anchored.has("anchor"), "debris detaches after 80ms at last sampled point")
	fx.clear_feedback()
	fx.confirm_hit(actor.position + offset, Vector2.RIGHT, {"damage":10.0,"anchor":anchor,"anchor_offset":offset})
	var doomed: Dictionary = fx.events[0]
	var last_point: Vector2 = fx.contact_position(doomed)
	actor.free()
	check(anchor.get_ref() == null, "contact event does not retain actor lifetime")
	fx.advance(0.02)
	check(fx.contact_position(doomed) == last_point and not doomed.has("anchor"), "freed actor safely freezes contact at last valid point")
	fx.clear_feedback()
	var body_parent := Node2D.new()
	add_child(body_parent)
	body_parent.position = Vector2(320, 175)
	body_parent.rotation = 0.2
	var body := Node2D.new()
	body_parent.add_child(body)
	body.position = Vector2(6, -27)
	body.rotation = -0.12
	body.scale = Vector2(-0.85, 1.1)
	var surface := Vector2(12, -15)
	fx.position = Vector2(15, 30)
	fx.confirm_hit(fx.to_local(body.to_global(surface)), Vector2.RIGHT,
		{"damage":10.0,"visual_anchor":weakref(body),"visual_offset":surface})
	var attached: Dictionary = fx.events[0]
	body.position += Vector2(5, 2)
	body.rotation += 0.08
	check(fx.contact_position(attached).is_equal_approx(fx.to_local(body.to_global(surface))), "contact follows mirrored rotated body recoil across different parent transforms")
	get_tree().paused = true
	last_point = attached.at
	body.position += Vector2(8, 4)
	check(fx.contact_position(attached) == last_point, "paused contact does not chase cosmetic body changes")
	get_tree().paused = false
	fx.advance(0.04)
	last_point = attached.at
	body_parent.free()
	check(fx.contact_position(attached) == last_point and not attached.has("visual_anchor"), "freed body retains last surface point without a center fallback jump")
	fx.position = Vector2.ZERO
	fx.clear_feedback()
	fx.confirm_hit(Vector2(17, 42), Vector2.RIGHT, {"damage":10.0})
	fx.advance(0.04)
	check(fx.contact_position(fx.events[0]) == Vector2(17, 42), "unanchored callers retain fixed world contact")
	fx.clear_feedback()
	fx.confirm_hit(Vector2.ZERO, Vector2.RIGHT, {"damage":10.0,"heavy":true})
	var first_radius: float = fx.events[0].radius
	for index in 8:
		fx.confirm_hit(Vector2(index,0), Vector2.RIGHT, {"damage":10.0,"heavy":true})
	check(fx.events.back().radius < first_radius and fx.events.back().density >= 0.58, "clustered cleave reduces overlapping bursts")
	fx.clear_feedback()
	fx.add_floating_damage(Vector2.ZERO, 12.0, &"primary")
	fx.add_floating_damage(Vector2.ZERO, 4.2, &"burn")
	check(fx.events[0].at != fx.events[1].at, "nearby damage numbers use separate positions")
	for index in 100:
		fx.confirm_hit(Vector2(index*100,0), Vector2.RIGHT, {"damage":10.0})
		fx.add_floating_damage(Vector2.ZERO, 12.0, &"primary")
		check(fx.events.size() <= 32, "shared event cap under mass combat")
	check(fx.active_peak <= 32 and fx.culled_events > 0, "visual load is bounded and measured")
	Game.profile.settings.reduced_fx = true
	fx.clear_feedback()
	fx.confirm_hit(Vector2.ZERO, Vector2.RIGHT, {"damage":10.0,"heavy":true})
	fx.add_floating_damage(Vector2.ZERO, 8.0, &"arc")
	check(fx.events[0].reduced and fx.events[0].duration <= 0.12 and fx.events[1].reduced, "reduced FX creates brief static marks and static numbers")
	Game.profile.settings.reduced_fx = false
	fx.clear_feedback()
	fx.confirm_hit(Vector2.ZERO, Vector2.RIGHT, {"damage":10.0,"hero_id":"CH02"})
	var direct: Dictionary = fx.events[0]
	direct.age = 0.033
	check(fx._core_strength(direct, 0.055, 0.07) > 0.45, "gun entry point remains legible through two normal frames")
	var passive: Dictionary = direct.duplicate()
	passive.passive = true
	check(is_equal_approx(fx._core_strength(passive, 0.055, 0.07), fx._core_strength(direct, 0.055, 0.07) * 0.52), "passive contact dims its core as well as its debris")
	direct.age = 0.075
	check(fx._core_strength(direct, 0.055, 0.07) == 0.0, "entry flash ends without an extra pulse")
	var stable_age: float = direct.age
	fx.advance(NAN)
	fx.advance(INF)
	check(direct.age == stable_age, "non-finite deltas cannot poison presentation lifetime")
	fx.clear_feedback()
	check(fx.events.is_empty(), "room transition clears presentation")
	Game.profile.settings.reduced_fx = false
	fx.queue_free()
	await get_tree().process_frame
	print("Impact visuals: %d/%d checks passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
