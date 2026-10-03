extends RefCounted
## Settings behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func set_setting(key: String, value: Variant) -> void:
	if key == "language" and not value in ["zh_CN", "en"]:
		return
	if key in ["reduced_fx", "fullscreen", "camera_shake", "auto_attack", "enemy_skill_paths"] and not value is bool:
		return
	if key in ProfileStore.VOLUME_DEFAULTS and not ProfileStore._number(value, 1.0, false):
		return
	if key == "controls" and not ProfileStore.Controls.valid_overrides(value):
		return
	if not key in ["language", "reduced_fx", "fullscreen", "camera_shake", "auto_attack", "enemy_skill_paths", "controls"] and not key in ProfileStore.VOLUME_DEFAULTS:
		return
	var next_profile = host.profile.duplicate(true)
	next_profile.settings[key] = value
	if host._save(next_profile, host.run.receipt() if host.run != null else null, host.has_profile):
		host.profile = next_profile
		if key == "controls": ProfileStore.Controls.install(host.profile.settings.controls)
		host.changed.emit()

func set_control_binding(action: String, binding: Dictionary) -> bool:
	if action not in ProfileStore.Controls.EDITABLE_ACTIONS or not ProfileStore.Controls.valid_binding(binding): return false
	var controls: Dictionary = host.profile.get("settings", {}).get("controls", {}).duplicate(true)
	if not ProfileStore.Controls.conflict(action, binding, controls).is_empty(): return false
	controls[action] = binding.duplicate(true)
	host.set_setting("controls", controls)
	return host.last_error.is_empty() and host.profile.settings.get("controls", {}).get(action, {}) == binding
