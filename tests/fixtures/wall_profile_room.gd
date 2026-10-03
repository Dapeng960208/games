extends "res://scripts/gameplay/world/room_controller.gd"
## Timing only: both overrides call the unchanged production implementations.
var navigation_usec: int = 0
var room_usec: int = 0

func navigation_direction(from: Vector2, to: Vector2, radius: float) -> Vector2:
	var started := Time.get_ticks_usec()
	var result: Vector2 = super.navigation_direction(from,to,radius)
	navigation_usec += Time.get_ticks_usec()-started
	return result

func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	super._physics_process(delta)
	room_usec += Time.get_ticks_usec()-started
