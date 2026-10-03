extends RefCounted
## Feedback behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func _add_effect(effect: Dictionary) -> void:
	# Visuals also have a hard cap; combat state never depends on effects surviving.
	if host.effects.size() >= 120:
		host.effects.pop_front()
	host.effects.append(effect)

func add_ring(at: Vector2, color: Color, radius: float, duration: float) -> void:
	host._add_effect({"kind":&"ring","at":at,"color":color,"radius":radius,"remaining":duration,"duration":duration})

func add_slash(at: Vector2, direction: Vector2) -> void:
	host._add_effect({"kind":&"slash","at":at,"direction":direction,"remaining":0.2,"duration":0.2})

func add_damage_text(at: Vector2, amount: float, kind: StringName, context: Dictionary = {}) -> void:
	if Game.profile.get("settings", {}).get("damage_numbers", true):
		if is_instance_valid(host.impact_feedback):
			host.impact_feedback.add_floating_damage(at, amount, kind, context)
		elif amount > 0.0:
			host._add_effect({"kind":&"text","at":at,"amount":amount,"source":kind,"remaining":0.6,"duration":0.6})
