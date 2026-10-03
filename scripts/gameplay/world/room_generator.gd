class_name RoomGenerator
extends RefCounted
## Compatibility entry point for authored fixed rooms. The run seed is kept
## for drops, encounters and beacon effects; scenery never changes by seed.

const FixedLayouts = preload("res://scripts/domain/world/fixed_room_layouts.gd")

static func generate(room_id: String, seed_value: int) -> Dictionary:
	if preload("res://scripts/levels/b05/world/room_geometry.gd").room(room_id).size() > 0:
		return preload("res://scripts/levels/b05/world/room_layouts.gd").build(room_id,seed_value)
	return FixedLayouts.build(room_id, seed_value)

static func _generate_with_budget(room_id: String, seed_value: int, _random_budget: int) -> Dictionary:
	# Legacy tool callers may pass a placement budget. Fixed rooms need no RNG
	# and no exhaustion fallback: coordinates come directly from the design.
	return generate(room_id, seed_value)
