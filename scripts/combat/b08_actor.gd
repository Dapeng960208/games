extends "res://scripts/combat/enemy.gd"
## Debug wing silhouette; deliberately does not borrow another species' art.
const SkyBrain = preload("res://scripts/combat/b08_brain.gd")
func _ready() -> void:
	super._ready()
	if is_instance_valid(body_visual): body_visual.free()
	body_visual = null
	body_texture = null
	if static_actor: brain = null; return
	brain = SkyBrain.new()
	brain.configure(profile)
func _finish_motion(delta: float) -> void:
	velocity *= room.wind_multiplier(position,velocity)
	super._finish_motion(delta)
func take_damage(amount: float, kind: StringName = &"primary", from_direction: Vector2 = Vector2.ZERO, context: Dictionary = {}) -> bool:
	if brain != null and brain.clock<brain.weak_until: amount *= 1.15
	return super.take_damage(amount,kind,from_direction,context)
func _exit_tree() -> void:
	if is_instance_valid(room):
		room.release_warning(str(get_instance_id()))
		room.wind.release_dive(str(get_instance_id()))
	super._exit_tree()
func _draw() -> void:
	if not is_alive(): return
	if static_actor:
		draw_line(Vector2.ZERO,Vector2(0,-60),Color("886237"),4)
		draw_colored_polygon(PackedVector2Array([Vector2(0,-60),Vector2(38,-47),Vector2(0,-34)]),Color("d2a442"))
		return
	var boss := enemy_id=="BO08"
	var scale_value := 1.6 if boss else 1.0
	var flight: bool = brain!=null and brain.transit and str(brain.action.get("kind","")) in ["dive","patrol"]
	var lift := 22.0 if flight else 0.0
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale_value)
	draw_set_transform(Vector2(0,-lift),0,Vector2.ONE*scale_value)
	var tint := Color("f0d48b") if boss else Color("e3edf5")
	draw_colored_polygon(PackedVector2Array([Vector2(-9,-12),Vector2(-48,-32),Vector2(-34,-9),Vector2(-16,0)]),tint)
	draw_colored_polygon(PackedVector2Array([Vector2(9,-12),Vector2(48,-32),Vector2(34,-9),Vector2(16,0)]),tint)
	draw_line(Vector2(-10,-12),Vector2(-44,-30),Color("537fa1"),2)
	draw_line(Vector2(10,-12),Vector2(44,-30),Color("537fa1"),2)
	draw_circle(Vector2(0,-17),12,Color("42688b"))
	draw_circle(Vector2(0,-33),8,Color("e9bf8d"))
	if enemy_id=="B08-M01": draw_arc(Vector2(20,-15),21,-1.2,1.2,16,Color("e6bd61"),3)
	else: draw_line(Vector2(13,4),Vector2(20,-57),Color("e6bd61"),3)
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(-26,-66*scale_value-lift),Vector2(26,-66*scale_value-lift),Color("233345"),5)
	draw_line(Vector2(-26,-66*scale_value-lift),Vector2(-26+52*health.current/health.maximum,-66*scale_value-lift),Color("7dcaa0"),3)
