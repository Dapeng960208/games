extends SceneTree
## Real UI edge checks. Run only with a separate --test-profile containing test_.
## Headless checks verify control/input/state behavior, not screen appearance.

var checks := 0
var failures := 0
var app: Node
var game: Node
var healthy_path: String
var blocked_path: String

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func frames(count: int = 2) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func key(code: Key, shift: bool = false) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = code
	pressed.physical_keycode = code
	pressed.shift_pressed = shift
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await frames(1)

func top_contains_focus() -> bool:
	if app.modals.is_empty():
		return false
	var focus := root.gui_get_focus_owner()
	return is_instance_valid(focus) and app.modals[-1].node.is_ancestor_of(focus)

func run_checks() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_"):
		push_error("Refusing UI edge tests without an isolated --test-profile containing test_")
		quit(2)
		return
	healthy_path = game.profile_path
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(), "create isolated edge-test profile")
	var fixture_dir := "user://test_ui_edges_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_dir))
	var blocker := FileAccess.open(fixture_dir + "/regular_file", FileAccess.WRITE)
	check(blocker != null, "create deterministic storage-failure fixture")
	if blocker == null:
		quit(1)
		return
	blocker.store_string("A regular file cannot be a save directory.")
	blocker.close()
	blocked_path = fixture_dir + "/regular_file/profile.json"
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	await check_focus_and_settings()
	await check_death_failure()
	await check_startup_failure()
	game.reload_profile()
	check(game.profile.permanent_gold == 14 and game.profile.total_runs == 2,
		"both repaired settlements persist exactly once")
	check(game.run == null, "no pending expedition remains after repairs")
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(),"edge-test fixture releases music playback before shutdown")
	app.free()
	await frames(3)
	print("UI_EDGE_TEST_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func check_focus_and_settings() -> void:
	app.show_camp()
	await frames()
	var original_focus := root.gui_get_focus_owner()
	app.show_settings()
	await frames()
	var focus_ids: Dictionary = {}
	for reverse in [false, true]:
		for _i in range(12):
			await key(KEY_TAB, reverse)
			check(top_contains_focus(), "Shift+Tab stays in top modal" if reverse else "Tab stays in top modal")
			if root.gui_get_focus_owner() != null:
				focus_ids[root.gui_get_focus_owner().get_instance_id()] = true
	# Five buttons and the three audio sliders are keyboard controls. Check
	# every control's identity so an extra accidental focus target cannot hide
	# a setting that keyboard users cannot reach.
	var settings_controls: Array[Node] = app.modals[-1].node.find_children("*","BaseButton",true,false)
	settings_controls.append_array(app.modals[-1].node.find_children("*","HSlider",true,false))
	check(focus_ids.size() == settings_controls.size(),"keyboard traversal covers exactly the settings controls")
	for setting_control: Control in settings_controls:
		check(focus_ids.has(setting_control.get_instance_id()),"keyboard traversal reaches setting "+setting_control.name)
	check(app.route == "camp" and app.modals.size() == 1, "keyboard traversal cannot activate a background route")
	await key(KEY_ESCAPE)
	check(app.modals.is_empty() and root.gui_get_focus_owner() == original_focus,
		"Esc restores the original camp focus")
	app.show_settings()
	app._toggle_language()
	await frames()
	check(Words.locale == "en" and game.profile.settings.language == "en", "language setting changes live UI and profile")
	app._toggle_fx()
	await frames()
	app._toggle_fullscreen()
	await frames()
	app._toggle_camera_shake()
	await frames()
	game.reload_profile()
	check(game.profile.settings.reduced_fx and game.profile.settings.fullscreen and game.profile.settings.language == "en" and game.profile.settings.camera_shake,
		"all four settings survive reload")
	for action in ["_toggle_language", "_toggle_fx", "_toggle_fullscreen", "_toggle_camera_shake"]:
		var old_settings: Dictionary = game.profile.settings.duplicate(true)
		var old_language: String = Words.locale
		game._store.path = blocked_path
		app.call(action)
		await frames()
		check(not game.last_error.is_empty() and app.modals.size() == 2,
			"failed setting opens an error above settings: " + action)
		check(not app.modals[-1].get("required", false) and top_contains_focus(),
			"setting error is dismissible and owns keyboard focus: " + action)
		check(game.profile.settings == old_settings and Words.locale == old_language,
			"failed setting does not pretend to apply: " + action)
		await key(KEY_ESCAPE)
		check(app.modals.size() == 1 and top_contains_focus(), "setting error returns to its settings panel")
		game._store.path = healthy_path
	app._toggle_fx()
	await frames()
	check(game.last_error.is_empty() and not game.profile.settings.reduced_fx, "setting retry succeeds after storage repair")
	app._pop_modal()
	await frames()
	app.show_camp()
	await frames()
	var biome_picker: OptionButton = app.screen.find_child("DepartureBiome",true,false)
	check(biome_picker.get_item_text(0) == "Sunlit Ruin Court" and biome_picker.get_item_text(3) == "Redrock Warcamp · Locked",
		"English camp translates unlocked and locked biome names")
	check(biome_picker.item_count == 12,"camp shows the full twelve-region roadmap")
	var todo_entries_disabled := true
	for plan_index in range(4,12):
		todo_entries_disabled = todo_entries_disabled and biome_picker.is_item_disabled(plan_index) and biome_picker.get_item_text(plan_index).ends_with(" · TODO") and str(biome_picker.get_item_metadata(plan_index)).is_empty()
	check(todo_entries_disabled,"all eight TODO regions are informative disabled entries")
	var prior_biome: String = app.selected_biome
	biome_picker.item_selected.emit(4)
	check(app.selected_biome == prior_biome,"TODO selection cannot change the real departure region")
	var difficulty_picker: OptionButton = app.screen.find_child("DepartureDifficulty",true,false)
	difficulty_picker.item_selected.emit(4)
	await frames()
	var difficulty_hint: Label = app.screen.find_child("DepartureDifficultyHint",true,false)
	check(difficulty_hint.text.contains("BASE: 44 foes") and difficulty_hint.text.contains("Enemy Lv.9"),"extreme difficulty shows actual first-biome base enemy count and level after the 40% population update")
	check(difficulty_hint.text.contains("Faction gear 2 / +3") and difficulty_hint.text.contains("Boss 4 / +1 boost, cap +3"),"extreme difficulty shows current gear amount and capped boss enhancement")
	check(difficulty_hint.get_line_count() == 1,"English difficulty details fit in one camp line")
	difficulty_picker.item_selected.emit(1)
	await frames()
	check(difficulty_hint.text.contains("Faction gear 1 / +0–1"),"challenging difficulty shows its actual random enhancement range")
	difficulty_picker.item_selected.emit(0)
	var camp_heading: Label = app.screen.find_child("CampHeading",true,false)
	check(camp_heading.text == "LANTERN WORKSHOP" and camp_heading.get_line_count() == 1,
		"English camp branding stays on one line")
	var camp_settings: Button = app.screen.find_child("CampSettings",true,false)
	check(camp_settings.text == "SETTINGS" and camp_settings.size.x <= 168,
		"English settings action stays inside its compact camp footer")

func check_death_failure() -> void:
	# Settlement retry behavior is independent of expedition entry decisions.
	check(game.start_run(), "start legacy room for death settlement retry")
	await frames()
	check(game.run != null and app.pending_outcome.is_empty(), "new run clears old UI settlement intent")
	check(game.add_gold(19), "collect known death-test scrap")
	game._store.path = blocked_path
	# Settlement retry is independent of separately resolved armor/equipment
	# reduction. Deplete actual health and shield with deterministic true damage.
	var raw_damage: float = game.run.hp + game.run.shield + 1.0
	game.damage_player(raw_damage,{"damage_type":"true"})
	await frames(3)
	check(game.run != null and game.run.hp == 0 and game.profile.permanent_gold == 0,
		"failed death keeps pending run without granting a reward")
	check(app.pending_outcome == "death" and app.modals[-1].get("required", false) and paused,
		"automatic death failure opens required retry and pauses combat")
	var modal_count: int = app.modals.size()
	app._pop_modal()
	await key(KEY_ESCAPE)
	check(app.modals.size() == modal_count and paused, "Back and Esc cannot dismiss failed settlement")
	check(top_contains_focus(), "required retry owns keyboard focus")
	game._store.path = healthy_path
	await key(KEY_ENTER)
	await frames(3)
	check(app.route == "result" and game.run == null and not paused,
		"keyboard retry completes death and opens result")
	check(game.last_result.outcome == "death" and game.last_result.retained == 9 and game.profile.permanent_gold == 9 and game.last_result.rules_version == 2,
		"current-rule death retry retains floor(19*0.5), never full extraction")
	game.finish_run("extracted")
	check(game.profile.permanent_gold == 9 and game.profile.total_runs == 1, "repeated request after repaired death cannot repay")

func check_startup_failure() -> void:
	# Remove UI subscribers before failing settlement, as with an autoload before main._ready.
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(),"previous UI fixture releases playback before startup-recovery reload")
	app.free()
	await frames()
	check(game.start_run() and game.add_gold(29), "prepare activity marker for startup failure")
	game.run.hp = 0
	game._store.path = blocked_path
	check(game.finish_run("abandoned").is_empty(), "startup settlement can fail before a UI subscriber exists")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	check(app.modals.size() == 1 and app.modals[-1].get("required", false) and paused,
		"main startup detects the already-failed autoload settlement")
	check(app.pending_outcome == "abandoned", "startup recovery keeps abandonment intent")
	await key(KEY_ESCAPE)
	check(app.modals.size() == 1 and paused, "startup retry cannot be bypassed into the menu")
	game._store.path = healthy_path
	await key(KEY_ENTER)
	await frames(3)
	check(app.route == "result" and game.run == null and game.last_result.outcome == "abandoned",
		"startup retry opens a committed abandonment result")
	check(game.last_result.retained == 5 and game.profile.permanent_gold == 14,
		"startup retry banks floor(29*0.2) exactly once")
