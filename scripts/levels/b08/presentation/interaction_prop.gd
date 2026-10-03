extends "res://scripts/presentation/world/room_depth_sprite.gd"
## Reuse the shared foot-depth and hero-occlusion treatment for native props.
var source: Node2D
var kind := ""
func _draw() -> void:
	if is_instance_valid(source): source.draw_body(self,kind)
