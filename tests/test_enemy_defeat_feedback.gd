extends Node2D

const Feedback = preload("res://scripts/combat/enemy_defeat_feedback.gd")
const EnemyVisualScript = preload("res://scripts/combat/enemy_visual.gd")
var checks: int = 0
var failures: int = 0

class Actor extends Node2D:
	var actor_kind: String = "enemy"
	var static_actor: bool = false
	var rank: String = "normal"
	var body_visual: Node2D
	var body_texture: Texture2D
	var empty_body_texture: Texture2D
	var body_region := Rect2()
	var body_bounds := Rect2(-22,-62,44,80)
	var profile: Dictionary = {"archetype":"skirmisher"}
	var enemy_id: String = ""
	var move_speed: float = 100.0
	var knockback := Vector2.ZERO
	var reaction_remaining: float = 0.0
	var aim_direction := Vector2.LEFT
	var state: StringName = &"chase"
	var state_time: float = 0.0
	var brain: RefCounted
	var material_kind: String = "stone"
	func impact_material() -> String:
		return material_kind

func _ready() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _actor(authored: bool = true) -> Actor:
	var actor := Actor.new()
	actor.position = Vector2(105,123)
	actor.rotation = 0.07
	actor.scale = Vector2(1.1,0.9)
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 96
	actor.body_texture = texture
	actor.body_region = Rect2(4,7,55,81)
	add_child(actor)
	if authored:
		actor.body_visual = EnemyVisualScript.new()
		actor.add_child(actor.body_visual)
		actor.body_visual.configure(actor)
		actor.body_visual.receive_impact(Vector2.RIGHT, 1.1, true)
	return actor

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var feedback = Feedback.new()
	add_child(feedback)
	feedback.set_process(false)
	feedback.reduced_fx_override = 0
	feedback.position = Vector2(-9,4)
	feedback.rotation = -0.04
	var actor := _actor()
	actor.modulate = Color(0.8,0.9,1.0,0.85)
	actor.body_visual.modulate = Color(1.0,0.8,0.7,0.9)
	actor.body_visual.self_modulate = Color(0.9,1.0,0.8,0.95)
	actor.set_meta("enemy_shadow_stealth", true)
	var body_frame: Dictionary = actor.body_visual.body_frame()
	var expected_transform: Transform2D = feedback.global_transform.affine_inverse() * actor.body_visual.global_transform
	var expected_tint: Color = actor.modulate * actor.body_visual.modulate * actor.body_visual.self_modulate
	expected_tint.a *= 0.35
	_check(feedback.capture(actor, Vector2.RIGHT), "captures valid enemy")
	var event: Dictionary = feedback.events[0]
	_check(event.frame.texture == body_frame.texture, "copies actual texture resource")
	_check(event.frame.region == body_frame.region, "copies explicit source region without guessing grid")
	_check(event.frame.bounds == body_frame.bounds, "copies foot-relative bounds")
	_check(event.body.transform.is_equal_approx(expected_transform), "frame zero preserves body, actor and feedback transforms")
	_check(event.body.modulate.is_equal_approx(expected_tint), "inherits body tint and stealth alpha once")
	_check(event.body.material != actor.body_visual.material, "snapshot gets private material")
	_check(event.body.material.shader == actor.body_visual.material.shader, "retains original body shader")
	_check(event.body.get_child_count() == 0, "snapshot does not clone gameplay nodes or UI")
	_check(feedback.z_index <= 2 and event.body.z_index == 0, "body is below danger and hit layers")
	_check(feedback.process_mode == Node.PROCESS_MODE_INHERIT, "inherits pause and room lifecycle")
	var origin_weak: WeakRef = weakref(actor)
	actor.free()
	_check(origin_weak.get_ref() == null, "snapshot holds no actor reference")
	_check(event.body.frame.texture != null, "body survives freed actor")
	feedback.advance(0.1)
	_check(not event.body.transform.is_equal_approx(expected_transform), "normal mode has visible directed collapse")
	_check(event.body.material.get_shader_parameter("impact_mix") == 0.0, "transient impact flash does not linger on corpse")
	_check(event.body.modulate.a > 0.0, "body still visible during collapse")
	var paused_transform: Transform2D = event.body.transform
	var paused_age: float = event.age
	get_tree().paused = true
	feedback.advance(0.3)
	_check(is_equal_approx(event.age, paused_age) and event.body.transform == paused_transform, "explicit advance freezes while paused")
	actor = _actor(false)
	_check(not feedback.capture(actor, Vector2.RIGHT), "paused capture rejected")
	get_tree().paused = false
	feedback.advance(0.2)
	_check(event.body.modulate.a < expected_tint.a, "late body softly fades")
	feedback.advance(0.2)
	_check(feedback.events.is_empty() and feedback.get_child_count() == 0, "expiry releases body immediately")
	_check(feedback.capture(actor, Vector2.LEFT), "enemy without body_visual uses true actor texture")
	_check(feedback.events[0].frame.region == actor.body_region, "fallback source crop retained")
	_check(feedback.events[0].body.transform.is_equal_approx(feedback.global_transform.affine_inverse() * actor.global_transform), "fallback frame origin unchanged")
	feedback.clear_feedback()
	actor.body_texture = null
	_check(feedback.capture(actor, Vector2.ZERO), "missing texture gets geometry fallback")
	_check(feedback.events[0].frame.texture == null, "missing texture not replaced with rectangular bitmap")
	_check(feedback.events[0].direction == Vector2.RIGHT, "zero direction safely resolves")
	feedback.clear_feedback()
	for kind: String in ["objective", "cover", "anchor", "chest"]:
		actor.actor_kind = kind
		_check(not feedback.capture(actor, Vector2.RIGHT), "no corpse for " + kind)
	actor.actor_kind = "enemy"
	actor.static_actor = true
	_check(not feedback.capture(actor, Vector2.RIGHT), "no corpse for static skill actor")
	actor.static_actor = false
	actor.rank = "boss"
	_check(not feedback.capture(actor, Vector2.RIGHT), "boss retains its dedicated presentation")
	actor.rank = "elite"
	_check(feedback.capture(actor, Vector2.RIGHT), "elite ordinary enemy supported")
	feedback.clear_feedback()
	actor.hide()
	_check(not feedback.capture(actor, Vector2.RIGHT), "hidden actor does not appear as new corpse")
	actor.show()
	feedback.reduced_fx_override = 1
	_check(feedback.capture(actor, Vector2.UP), "reduced feedback captures")
	event = feedback.events[0]
	var reduced_transform: Transform2D = event.body.transform
	feedback.advance(0.09)
	_check(event.body.transform == reduced_transform, "reduced mode is static, not drifting or rotating")
	_check(event.body.modulate.a > 0.0 and event.body.modulate.a < 1.0, "reduced mode smoothly fades")
	feedback.advance(0.10)
	_check(feedback.events.is_empty(), "reduced body expires before 0.2 seconds")
	feedback.reduced_fx_override = 0
	for index in 27:
		actor.material_kind = ["stone", "metal", "organic"][index % 3]
		_check(feedback.capture(actor, Vector2.RIGHT), "bounded capture " + str(index))
		_check(feedback.get_child_count() <= Feedback.MAX_BODIES, "same-frame live body cap " + str(index))
	_check(feedback.events.size() == 20 and feedback.culled_events == 7, "overflow discards oldest with exact cap")
	_check(feedback.debug_counts().peak == 20, "debug peak obeys cap")
	for event_item: Dictionary in feedback.events:
		_check(event_item.material in ["stone", "metal", "organic"], "surface material captured")
		for value: Variant in event_item.values():
			_check(value != actor if value is Node else true, "event has no direct actor reference")
	feedback.advance(NAN)
	_check(feedback.events.size() == 20, "nonfinite time does not poison lifetime")
	feedback.clear_feedback()
	_check(feedback.get_child_count() == 0 and feedback.debug_counts().active == 0, "room clear removes all snapshots synchronously")
	actor.body_bounds = Rect2(0,0,-1,20)
	_check(not feedback.capture(actor, Vector2.RIGHT), "malformed body bounds rejected")
	actor.free()
	feedback.free()
	print("Enemy defeat feedback: %d/%d passed" % [checks - failures, checks])
	get_tree().quit(1 if failures > 0 else 0)
