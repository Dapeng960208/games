class_name RoomGenerator
extends RefCounted
## Compatibility entry point for authored fixed rooms. The run seed is kept
## for drops, encounters and beacon effects; scenery never changes by seed.

const FixedLayouts = preload("res://scripts/world/fixed_room_layouts.gd")

static func generate(room_id: String, seed_value: int) -> Dictionary:
	return FixedLayouts.build(room_id, seed_value)

static func _generate_with_budget(room_id: String, seed_value: int, _random_budget: int) -> Dictionary:
	# Legacy tool callers may pass a placement budget. Fixed rooms need no RNG
	# and no exhaustion fallback: coordinates come directly from the design.
	return generate(room_id, seed_value)
