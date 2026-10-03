extends Node2D
## One non-colliding painted beacon sorts with actors at its ground contact.
var source: Node2D
var item: Dictionary = {}
var draw_method: StringName = &"draw_beacon_body"
const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")

func update_depth(delta: float) -> void:
	if not is_instance_valid(source): return
	var room: Node2D = source.room
	var actor: Node2D = room.get("player") if is_instance_valid(room) else null
	var bounds: Rect2 = PropArt.bounds_at(source.body_art_key(item),Vector2.ZERO,source.body_art_size(item))
	var obscured: bool = is_instance_valid(actor) and actor.position.y < position.y and bounds.grow(10.0).has_point(actor.position-position+Vector2(0,-28))
	modulate.a = move_toward(modulate.a,.56 if obscured else 1.0,maxf(0.0,delta)*6.0)

func _draw() -> void:
	if is_instance_valid(source) and not item.is_empty():
		source.call(draw_method,self,item)
