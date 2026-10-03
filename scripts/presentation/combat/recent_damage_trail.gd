class_name RecentDamageTrail
extends RefCounted
## Bounded runtime-only combat explanation. Never include in profile/receipts or
## combat snapshots. Events own scalar copies, never actors or arbitrary context.
const MAX_EVENTS := 12
const WINDOW_SECONDS := 15.0
const TEXT_LIMIT := 96
const KEY_STATES: Array[String] = ["burn", "shock", "chill", "corrosion", "bleed", "grievous", "damage_reduction", "brace_guard", "invulnerable", "slow", "dash"]
var _events: Array[Dictionary] = []
var _total_absorbed: float = 0.0

func clear() -> void:
	_events.clear()
	_total_absorbed = 0.0

func record(raw_amount: float, resolved_amount: float, hp_before: float, hp_after: float, shield_before: float, shield_after: float, context: Dictionary, elapsed: float) -> void:
	for value: float in [raw_amount, resolved_amount, hp_before, hp_after, shield_before, shield_after, elapsed]:
		if not is_finite(value) or value < 0.0:
			return
	var hp_loss: float = maxf(0.0, hp_before - hp_after)
	var absorbed: float = maxf(0.0, shield_before - shield_after)
	if hp_loss <= 0.0 and absorbed <= 0.0:
		return
	var states: Array[String] = []
	var supplied: Variant = context.get("key_states", [])
	if supplied is Array:
		for state: Variant in supplied:
			if state is String and state in KEY_STATES and state not in states:
				states.append(state)
	var event: Dictionary = {
		"elapsed":elapsed,
		"kind":"shock" if str(context.get("damage_event", "")) == "shock" else "dot" if bool(context.get("dot", false)) else "direct",
		"status":_text(context.get("status", "")),
		"damage_type":_text(context.get("damage_type", "physical")),
		"source_id":_text(context.get("source_id", "")),
		"source_name":_text(context.get("source_name", "")),
		"attack_id":_text(context.get("attack_id", "")),
		"raw_damage":raw_amount, "resolved_damage":resolved_amount,
		"hp_loss":hp_loss, "shield_absorbed":absorbed,
		"hp_before":hp_before, "hp_after":hp_after,
		"shield_before":shield_before, "shield_after":shield_after,
		"lethal":hp_before > 0.0 and hp_after <= 0.0, "key_states":states,
	}
	_events.append(event)
	_total_absorbed += absorbed
	_prune(elapsed)

func summary(elapsed: float = -1.0) -> Dictionary:
	if elapsed >= 0.0 and is_finite(elapsed):
		_prune(elapsed)
	var lethal: Dictionary = {}
	for event: Dictionary in _events:
		if bool(event.lethal):
			lethal = event.duplicate(true)
	return {"recent_events":_events.duplicate(true), "lethal_event":lethal, "total_absorbed":_total_absorbed}

func _prune(elapsed: float) -> void:
	while not _events.is_empty() and (_events.size() > MAX_EVENTS or elapsed - float(_events[0].elapsed) > WINDOW_SECONDS):
		_events.pop_front()

static func _text(value: Variant) -> String:
	return str(value).left(TEXT_LIMIT) if value is String or value is StringName else ""
