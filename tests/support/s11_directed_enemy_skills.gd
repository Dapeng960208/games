extends "res://scripts/combat/enemy_skill_runtime.gd"
## Transparent observation of commands after the production V2 freeze seam.
var executed_commands: Array[Dictionary] = []

func _execute(command: Dictionary) -> void:
	var receipt := command.duplicate(true)
	receipt.erase("owner")
	receipt["observed_room_time"]=room.elapsed
	executed_commands.append(receipt)
	super._execute(command)
