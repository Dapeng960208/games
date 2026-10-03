extends Node2D
## Headless-only painted-background sink. Geometry, navigation and combat are
## owned by RoomController and remain intact. Avoid unsupported custom sampler shader.
func configure(_arena: Rect2, _biome: String, _seed: int, _room_id: String) -> void: pass
func configure_layout(_layout: Dictionary) -> void: pass
