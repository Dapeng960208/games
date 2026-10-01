class_name CombatHealth
extends Node
const Numerical = preload("res://config/numerical_rules.gd")

signal depleted
signal damaged(amount: float)

var ruleset_version: int = Numerical.LEGACY
var maximum: Variant = 1.0:
	set(value): maximum = Numerical.amount(float(value), ruleset_version)
var current: Variant = 1.0:
	set(value): current = Numerical.amount(float(value), ruleset_version)
var dead: bool = false

func reset(amount: float, ruleset: int = Numerical.LEGACY) -> void:
	ruleset_version = ruleset
	maximum = amount
	current = amount
	dead = false

func damage(amount: float) -> bool:
	amount = Numerical.amount(amount, ruleset_version)
	if dead or amount <= 0.0:
		return false
	current = maxf(0.0, current - amount)
	damaged.emit(amount)
	if current <= 0.0:
		dead = true
		depleted.emit()
	return true
