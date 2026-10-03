extends Node2D
## Short-lived body snapshots only: no AI, health, collisions or actor references.
## Capture before queue_free; room teardown should call clear_feedback().

const MAX_BODIES: int = 20
const BODY_DURATION: float = 0.44
const REDUCED_DURATION: float = 0.18
const Palette = preload("res://scripts/presentation/monsters/enemy_palette.gd")
var events: Array[Dictionary] = []
var accepted_events: int = 0
var culled_events: int = 0
var active_peak: int = 0
var reduced_fx_override: int = -1
var _serial: int = 0

class BodySnapshot extends Node2D:
	var frame: Dictionary = {}
	var fallback_offset := Vector2.ZERO
	var fallback_step: float = 0.0
	var fallback_alternating: bool = false
	func _draw() -> void:
		var texture: Texture2D = frame.get("texture")
		if texture != null:
			var region: Rect2 = frame.region
			if region.has_area():
				draw_texture_rect_region(texture, frame.bounds, region)
			else:
				draw_texture_rect(texture, frame.bounds, false)
			return
		# Same small mechanical body used by EnemyActor/EnemyVisual when art is absent.
		# Never replace missing transparent art with an opaque rectangle.
		draw_set_transform(fallback_offset)
		var colors: Dictionary = frame.get("fallback_colors", Palette.colors_for(""))
		for side: float in [-1.0, 1.0]:
			var step: float = fallback_step * side if fallback_alternating else fallback_step
			draw_polyline(PackedVector2Array([Vector2(side*8,0),Vector2(side*23,-8+step),Vector2(side*29,6+step)]), colors.trim, 4.0, true)
			draw_polyline(PackedVector2Array([Vector2(side*9,5),Vector2(side*21,13-step),Vector2(side*23,21-step)]), colors.shade, 4.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6),Vector2(13,12),Vector2(-12,12)]), colors.primary)
		draw_polyline(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6)]), colors.highlight, 2.0, true)
		draw_line(Vector2(-13,-4),Vector2(14,-4),colors.outline,6.0)
		draw_line(Vector2(-9,-4),Vector2(10,-4),colors.energy,3.0)
		draw_circle(Vector2(0,5),5.0,colors.trim)
		draw_circle(Vector2(0,5),2.0,colors.energy)
		draw_set_transform(Vector2.ZERO)

func _init() -> void:
	name = "EnemyDefeatFeedback"
	z_index = 1
	process_mode = Node.PROCESS_MODE_INHERIT
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(delta: float) -> void:
	advance(delta)

func capture(enemy: Node2D, direction: Vector2) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or _paused():
		return false
	if str(_property(enemy, "actor_kind", "enemy")) != "enemy" or bool(_property(enemy, "static_actor", false)) or str(_property(enemy, "rank", "normal")) == "boss":
		return false
	if not enemy.is_visible_in_tree() or not enemy.global_position.is_finite():
		return false
	var visual: Variant = _property(enemy, "body_visual", null)
	var source: Node2D = visual if is_instance_valid(visual) and visual is Node2D and visual.has_method("body_frame") else enemy
	var frame: Dictionary = source.call("body_frame").duplicate() if source != enemy else {
		"texture":_property(enemy, "body_texture", null),
		"region":_property(enemy, "body_region", Rect2()),
		"bounds":_property(enemy, "body_bounds", Rect2(-29,-21,58,42)),
		"fallback_colors":Palette.colors_for(str(_property(enemy, "enemy_id", "")))}
	if not _valid_frame(frame):
		return false
	var basis: Transform2D = global_transform.affine_inverse() * source.global_transform
	if not basis.is_finite() or absf(basis.determinant()) < 0.0001:
		return false
	var dir: Vector2 = global_transform.basis_xform_inv(direction).normalized() if direction.is_finite() and direction.length_squared() > 0.0001 else Vector2.RIGHT
	var reduced: bool = _reduced()
	var body := BodySnapshot.new()
	body.name = "DefeatedBody"
	body.frame = frame
	body.texture_filter = source.texture_filter
	# Keep a private material; a live enemy's later recoil must not mutate this body.
	if source.material != null:
		body.material = source.material.duplicate()
		if _has_parameter(body.material, "textured_body"):
			(body.material as ShaderMaterial).set_shader_parameter("textured_body", frame.get("texture") != null)
	body.fallback_alternating = source != enemy
	if source != enemy:
		var bounds: Rect2 = _property(enemy, "body_bounds", Rect2(-29,-21,58,42))
		body.fallback_offset = -Vector2(0, bounds.end.y)
		body.fallback_step = sin(float(_property(source, "stride_phase", 0.0))) * 2.5 * float(_property(source, "movement_weight", 0.0))
	else:
		body.fallback_step = sin(float(_property(enemy, "lifetime", 0.0)) * 9.0) * (3.0 if str(_property(enemy, "state", "")) == "chase" else 0.0)
	var tint: Color = _relative_tint(source)
	if bool(enemy.get_meta("enemy_shadow_stealth", false)):
		tint.a *= 0.35
	var debris_material: String = str(enemy.call("impact_material")) if enemy.has_method("impact_material") else "stone"
	if debris_material not in ["stone", "metal", "organic"]:
		debris_material = "stone"
	var actor_bounds: Rect2 = _property(enemy, "body_bounds", Rect2(-29,-21,58,42))
	var foot_y: float = actor_bounds.end.y if frame.get("texture") != null else 21.0
	var pivot: Vector2 = to_local(enemy.global_transform * Vector2(0, foot_y))
	_serial += 1
	var event: Dictionary = {"body":body,"frame":frame,"basis":basis,"at":to_local(enemy.global_position),
		"pivot":pivot,
		"direction":dir,"tint":tint,"material":debris_material,"age":0.0,
		"duration":REDUCED_DURATION if reduced else BODY_DURATION,"reduced":reduced,"serial":_serial,
		"flash":float(_property(source, "flash_strength", 0.0)),"has_flash":_has_flash_parameter(body.material)}
	if events.size() >= MAX_BODIES:
		_dispose(events.pop_front())
		culled_events += 1
	add_child(body)
	events.append(event)
	accepted_events += 1
	active_peak = maxi(active_peak, events.size())
	_update_body(event)
	queue_redraw()
	return true

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _paused():
		return
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		event.age += delta
		if float(event.age) >= float(event.duration):
			_dispose(event)
			events.remove_at(index)
		else:
			_update_body(event)
	queue_redraw()

func clear_feedback() -> void:
	for event in events:
		_dispose(event)
	events.clear()
	queue_redraw()

func debug_counts() -> Dictionary:
	return {"active":events.size(),"accepted":accepted_events,"culled":culled_events,"peak":active_peak,"limit":MAX_BODIES}

func _update_body(event: Dictionary) -> void:
	var body: Node2D = event.body
	var age: float = event.age
	var t: float = clampf(age / float(event.duration), 0.0, 1.0)
	var collapse: float = 1.0 - pow(1.0 - clampf(age / 0.26, 0.0, 1.0), 3.0)
	var basis: Transform2D = event.basis
	var tint: Color = event.tint
	if bool(event.reduced):
		tint.a *= 1.0 - smoothstep(0.0, 1.0, t)
	else:
		var dir: Vector2 = event.direction
		var side: float = -1.0 if dir.x < -0.05 else 1.0
		var at: Vector2 = event.pivot
		# Rotate the visible body about its ground contact, never its crop center.
		var fall := Transform2D(side * 0.48 * collapse, Vector2(1.0, lerpf(1.0, 0.70, collapse)), 0.0,
			at + dir * (12.0 * collapse) + Vector2(0, 4.0 * collapse))
		var origin := Transform2D(0.0, -at)
		basis = fall * origin * basis
		tint.a *= 1.0 - smoothstep(0.12, float(event.duration), age)
		var shade: float = lerpf(1.0, 0.73, collapse)
		tint.r *= shade
		tint.g *= shade
		tint.b *= shade
	body.transform = basis
	body.modulate = tint
	if bool(event.has_flash):
		(body.material as ShaderMaterial).set_shader_parameter("impact_mix", float(event.flash) * maxf(0.0, 1.0 - age / 0.065))

func _draw() -> void:
	for event in events:
		if bool(event.reduced):
			continue
		var age: float = event.age
		var t: float = clampf(age / float(event.duration), 0.0, 1.0)
		var fade: float = pow(1.0 - t, 2.0) * float(event.tint.a)
		var dir: Vector2 = event.direction
		var material_kind: String = event.material
		var color: Color = Color("bda078") if material_kind == "metal" else Color("82906d") if material_kind == "organic" else Color("918575")
		for index in 4:
			var spread: float = (float(index) - 1.5) * 0.48
			var ray := dir.rotated(spread)
			var travel: float = (11.0 + float((int(event.serial) + index * 3) % 7)) * (1.0 - pow(1.0 - t, 2.0))
			var point: Vector2 = event.at + Vector2(0, 10) + ray * travel + Vector2(0, 7.0 * t * t)
			if material_kind == "metal":
				draw_line(point - ray * 2.6, point + ray * 1.2, Color(color, fade * 0.7), 1.2, true)
			else:
				draw_colored_polygon(PackedVector2Array([point - ray * 1.8, point + ray.orthogonal() * 1.2, point + ray * 1.7]), Color(color, fade * 0.65))

func _dispose(event: Dictionary) -> void:
	var body: Node2D = event.get("body")
	if is_instance_valid(body):
		# The hard cap also applies to scene nodes during a same-frame mass kill.
		remove_child(body)
		body.free()

func _paused() -> bool:
	return is_inside_tree() and get_tree().paused

func _reduced() -> bool:
	return reduced_fx_override > 0 if reduced_fx_override >= 0 else bool(Game.profile.get("settings", {}).get("reduced_fx", false))

func _relative_tint(source: CanvasItem) -> Color:
	var tint: Color = source.self_modulate
	var cursor: Node = source
	var stop: Node = get_parent()
	while cursor != null and cursor != stop:
		if cursor is CanvasItem:
			tint *= cursor.modulate
		cursor = cursor.get_parent()
	return tint

func _valid_frame(frame: Dictionary) -> bool:
	if not frame.get("bounds") is Rect2 or not frame.get("region") is Rect2:
		return false
	var bounds: Rect2 = frame.bounds
	var region: Rect2 = frame.region
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area() or not region.position.is_finite() or not region.size.is_finite():
		return false
	var texture: Variant = frame.get("texture")
	if texture != null and not texture is Texture2D:
		return false
	return texture == null or not region.has_area() or Rect2(Vector2.ZERO, texture.get_size()).encloses(region)

func _has_flash_parameter(value: Material) -> bool:
	return _has_parameter(value, "impact_mix")

func _has_parameter(value: Material, parameter_name: String) -> bool:
	if not value is ShaderMaterial or value.shader == null:
		return false
	for uniform: Dictionary in value.shader.get_shader_uniform_list():
		if str(uniform.name) == parameter_name:
			return true
	return false

func _property(object: Object, key: String, fallback: Variant) -> Variant:
	for field: Dictionary in object.get_property_list():
		if str(field.name) == key:
			return object.get(key)
	return fallback
