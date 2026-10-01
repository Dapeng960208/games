class_name ControlBindings
extends RefCounted
## Persist physical keys and mouse buttons instead of relying on a runtime InputMap.

const EDITABLE_ACTIONS := ["click_move", "attack", "skill_q", "skill_secondary", "skill_f", "skill_ultimate", "dash", "interact", "move_up", "move_down", "move_left", "move_right"]
const KEY_DEFAULTS := {
	"skill_q": KEY_Q, "skill_secondary": KEY_W,
	"skill_f": KEY_E, "skill_ultimate": KEY_R, "dash": KEY_SPACE,
	"interact": KEY_F, "move_up": KEY_UP, "move_down": KEY_DOWN,
	"move_left": KEY_LEFT, "move_right": KEY_RIGHT,
	"relic_details": KEY_TAB, "expedition_map": KEY_M, "backpack": KEY_B,
	"pause": KEY_ESCAPE,
}

static func default_bindings() -> Dictionary:
	var bindings := {
		"click_move": {"type": "mouse", "code": MOUSE_BUTTON_RIGHT},
		"attack": {"type": "mouse", "code": MOUSE_BUTTON_LEFT},
	}
	for action: String in KEY_DEFAULTS:
		bindings[action] = {"type": "key", "code": KEY_DEFAULTS[action]}
	return bindings

static func resolve(overrides: Dictionary = {}) -> Dictionary:
	var bindings := default_bindings()
	for action: String in overrides:
		if bindings.has(action) and valid_binding(overrides[action]):
			bindings[action] = overrides[action].duplicate(true)
	# Explicit player bindings predate these mouse defaults. Keep them intact;
	# only move an untouched default that would now overlap a saved custom key.
	# In particular, saved left-click movement keeps the previous A attack.
	for action: String in ["click_move", "attack"]:
		if overrides.has(action) or _occupied(action, bindings[action], bindings).is_empty(): continue
		var candidates: Array = [{"type": "mouse", "code": MOUSE_BUTTON_LEFT}] if action == "click_move" else [{"type": "key", "code": KEY_A}]
		for code: int in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			candidates.append({"type": "mouse", "code": code})
		for code: int in [KEY_G, KEY_H, KEY_J, KEY_K, KEY_L, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P]:
			candidates.append({"type": "key", "code": code})
		for candidate: Dictionary in candidates:
			if _occupied(action, candidate, bindings).is_empty():
				bindings[action] = candidate
				break
	return bindings

static func _occupied(action: String, binding: Dictionary, bindings: Dictionary) -> String:
	for other: String in bindings:
		if other == action: continue
		var existing: Dictionary = bindings[other]
		if existing.type == binding.type and int(existing.code) == int(binding.code): return other
	return ""

static func valid_binding(value: Variant) -> bool:
	if not value is Dictionary or not value.get("type") in ["key", "mouse"]:
		return false
	var code: Variant = value.get("code")
	if typeof(code) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(code)) or float(code) != floor(float(code)):
		return false
	if value.type == "mouse":
		return int(code) in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
	return int(code) > 0 and int(code) <= 0x7fffffff and int(code) not in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

static func conflict(action: String, binding: Dictionary, overrides: Dictionary = {}) -> String:
	return _occupied(action, binding, resolve(overrides))

static func attack_backup_enabled(overrides: Dictionary = {}) -> bool:
	var bindings := resolve(overrides)
	var backup := {"type": "key", "code": KEY_A}
	var primary: Dictionary = bindings.attack
	if primary.type == "key" and int(primary.code) == KEY_A: return false
	return _occupied("attack", backup, bindings).is_empty()

static func valid_overrides(value: Variant) -> bool:
	if not value is Dictionary or value.size() > EDITABLE_ACTIONS.size(): return false
	for action: Variant in value:
		if not action is String or action not in EDITABLE_ACTIONS or not valid_binding(value[action]):
			return false
		if not conflict(action, value[action], value).is_empty(): return false
	return true

static func install(overrides: Dictionary = {}) -> void:
	# The old C / V circuit is now each hero's automatic passive.
	for action: String in ["circuit_place", "circuit_release"]:
		if InputMap.has_action(action): InputMap.erase_action(action)
	var bindings := resolve(overrides)
	for action: String in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var binding: Dictionary = bindings[action]
		var event: InputEvent
		if binding.type == "mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(binding.code)
			event = mouse
		else:
			var key := InputEventKey.new()
			key.physical_keycode = int(binding.code)
			event = key
		InputMap.action_add_event(action, event)
	# A is a convenience alias, never a reservation. A custom action using it
	# disables this alias so every explicit player binding stays unambiguous.
	if attack_backup_enabled(overrides):
		var backup := InputEventKey.new()
		backup.physical_keycode = KEY_A
		InputMap.action_add_event("attack", backup)

static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return {}
		var binding := {"type": "key", "code": event.physical_keycode if event.physical_keycode != 0 else event.keycode}
		return binding if valid_binding(binding) else {}
	if event is InputEventMouseButton and event.pressed:
		var binding := {"type": "mouse", "code": event.button_index}
		return binding if valid_binding(binding) else {}
	return {}

static func label_for(action: String, overrides: Dictionary = {}, language: String = "zh_CN") -> String:
	var binding: Dictionary = resolve(overrides).get(action, {})
	if binding.is_empty(): return "—"
	if binding.type == "mouse":
		var labels: Dictionary = {MOUSE_BUTTON_LEFT: ["鼠标左键", "Left click"], MOUSE_BUTTON_RIGHT: ["鼠标右键", "Right click"], MOUSE_BUTTON_MIDDLE: ["鼠标中键", "Middle click"], MOUSE_BUTTON_XBUTTON1: ["鼠标侧键 1", "Mouse side 1"], MOUSE_BUTTON_XBUTTON2: ["鼠标侧键 2", "Mouse side 2"]}
		return str(labels[int(binding.code)][0 if language == "zh_CN" else 1])
	var code := int(binding.code)
	var names: Dictionary = {KEY_SPACE: ["空格", "Space"], KEY_UP: ["↑", "↑"], KEY_DOWN: ["↓", "↓"], KEY_LEFT: ["←", "←"], KEY_RIGHT: ["→", "→"]}
	if names.has(code): return str(names[code][0 if language == "zh_CN" else 1])
	return OS.get_keycode_string(code)

static func secondary_label(action: String, overrides: Dictionary = {}, language: String = "zh_CN") -> String:
	## Complete HUD label: primary binding plus the available A attack alias.
	var primary := label_for(action, overrides, language)
	if action != "attack": return primary
	if language == "zh_CN": primary = primary.trim_prefix("鼠标")
	return primary + " / A" if attack_backup_enabled(overrides) else primary
