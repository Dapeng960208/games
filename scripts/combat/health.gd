class_name CombatHealth
extends Node

signal depleted
signal damaged(amount: float)

var maximum: float = 1.0
var current: float = 1.0
var dead: bool = false

func reset(amount: float) -> void:
	maximum = amount
	current = amount
	dead = false

func damage(amount: float) -> bool:
	if dead or amount <= 0.0:
		return false
	current = maxf(0.0, current - amount)
	damaged.emit(amount)
	if current <= 0.0:
		dead = true
		depleted.emit()
	return true
