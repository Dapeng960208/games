extends Node
## Focused acceptance for input conflicts, persistence and the actual settings UI.
const Controls = preload("res://scripts/core/control_bindings.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CONTROL SETTINGS FAIL: " + label)

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func run_checks() -> void:
	if not Game.profile_path.contains("test_control_settings"):
		push_error("This suite requires an isolated --test-profile path.")
		get_tree().quit(1)
		return
	check(not Game.profile.settings.auto_attack and Game.profile.settings.enemy_skill_paths, "comfort defaults are explicit")
	Game.set_setting("auto_attack", true)
	Game.set_setting("enemy_skill_paths", false)
	check(Game.set_control_binding("click_move", {"type": "mouse", "code": MOUSE_BUTTON_RIGHT}), "mouse movement can be remapped")
	check(Game.set_control_binding("skill_q", {"type": "key", "code": KEY_T}), "skill can be remapped")
	check(Game.set_control_binding("move_up", {"type": "key", "code": KEY_G}), "directional movement can be remapped")
	check(not Game.set_control_binding("attack", {"type": "key", "code": KEY_T}), "duplicate skill / attack binding is rejected")
	check(not Game.set_control_binding("attack", {"type": "key", "code": KEY_B}), "backpack key is reserved")
	Game.reload_profile()
	check(Game.profile.settings.auto_attack and not Game.profile.settings.enemy_skill_paths, "combat settings survive reload")
	check(InputMap.action_has_event("skill_q", key(KEY_T)), "reloading installs saved bindings immediately")
	check(Controls.label_for("skill_q", Game.profile.settings.controls) == "T", "custom skill survives reload")
	check(Controls.label_for("move_up", Game.profile.settings.controls) == "G", "custom movement survives reload")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	check(InputMap.action_has_event("skill_q", key(KEY_T)), "main installs saved physical keys")
	check(not InputMap.action_has_event("move_up", key(KEY_W)), "W is available to the second skill")
	check(InputMap.action_has_event("skill_secondary", key(KEY_W)) and InputMap.action_has_event("skill_f", key(KEY_E)) and InputMap.action_has_event("skill_ultimate", key(KEY_R)), "remaining skill defaults are W E R")
	check(InputMap.action_has_event("attack", key(KEY_A)) and InputMap.action_has_event("interact", key(KEY_F)), "attack and interaction defaults avoid skills")
	check(not InputMap.has_action("circuit_place") and not InputMap.has_action("circuit_release"), "obsolete C / V inputs are removed")
	main.show_settings()
	check(main.ui.find_child("AutoAttackSetting", true, false) != null and main.ui.find_child("EnemySkillPathsSetting", true, false) != null, "real settings screen exposes both switches")
	main._switch_settings_tab("controls")
	check(main.ui.find_child("Bind_click_move", true, false).text == "鼠标右键", "real binding screen reflects saved mouse movement")
	main._begin_control_binding("attack")
	main._capture_control_binding(key(KEY_T))
	check(main.binding_feedback.text.contains("技能一") and main.pending_binding_action.is_empty(), "capture rejects occupied key with visible feedback")
	main._begin_control_binding("attack")
	main._capture_control_binding(key(KEY_Z))
	check(InputMap.action_has_event("attack", key(KEY_Z)) and Game.profile.settings.controls.attack.code == KEY_Z, "capture applies and persists a free key")
	main._begin_control_binding("attack")
	main._capture_control_binding(key(KEY_ESCAPE))
	check(main.pending_binding_action.is_empty() and Game.profile.settings.controls.attack.code == KEY_Z, "Escape cancels without changing binding")
	main._clear_modals()
	main.set_process(false)
	if is_instance_valid(main.music): await main.music.wait_for_cleanup()
	main.queue_free()
	await get_tree().process_frame
	var legacy := ProfileStore.fresh_profile()
	for setting: String in ["auto_attack", "enemy_skill_paths", "controls"]: legacy.settings.erase(setting)
	legacy.settings.language = "en"
	legacy.settings.music_volume = 0.31
	var legacy_store := ProfileStore.new(Game.profile_path + ".legacy")
	check(legacy_store.save_document(legacy), "previous settings schema remains readable")
	var loaded := legacy_store.load_document()
	check(not loaded.profile.settings.auto_attack and loaded.profile.settings.enemy_skill_paths and loaded.profile.settings.controls.is_empty(), "old saves receive new defaults")
	check(loaded.profile.settings.language == "en" and is_equal_approx(loaded.profile.settings.music_volume, 0.31), "old preferences are preserved")
	check(not FileAccess.get_file_as_string(Game.profile_path + ".legacy").contains("enemy_skill_paths"), "loading old defaults does not rewrite the save")
	print("CONTROL SETTINGS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
