extends SceneTree
## Exercise the real first-room failure and required settlement retry routes.
## Only the app's room factory is varied; the room, generator, saves and UI are real.

# A --script SceneTree is parsed before autoload globals are registered. Compile
# this app subclass after _initialize, when main.gd can resolve its real Game
# singleton, rather than eagerly preloading main before the autoload exists.
const FAILURE_APP_SOURCE := '''extends "res://scripts/presentation/app/main.gd"
var fail_room := true
var fail_settlement := false
var storage_failure_path := ""
var factory_calls := 0
var start_document: Dictionary = {}
var room_ready_snapshot: Dictionary = {}
var created_room: WeakRef

func _create_room() -> Node2D:
	factory_calls += 1
	var controller: Node = get_node("/root/Game")
	# The factory runs after start_run commits the real activity receipt.
	start_document = ProfileStore.new(controller.profile_path).load_document()
	var candidate: Node2D = load("res://scenes/gameplay/world/room.tscn").instantiate()
	if fail_room:
		candidate.layout_id = "INVALID_TEST_ROOM"
	created_room = weakref(candidate)
	candidate.ready.connect(func():
		room_ready_snapshot = {
			"configuration_ready":candidate.configuration_ready,
			"configuration_error":candidate.configuration_error,
			"has_player":is_instance_valid(candidate.player),
			"physics_processing":candidate.is_physics_processing(),
			"input_blocked":candidate.input_blocked,
			"spawn_enabled":candidate.spawn_enabled,
			"layout_empty":candidate.layout.is_empty()
		})
	if fail_settlement:
		controller._store.path = storage_failure_path
	return candidate
'''

var checks := 0
var failures := 0
var app: Node
var game: Node
var healthy_path := ""
var blocked_path := ""
var failure_app_script: GDScript
var suite_completed := false

func _initialize() -> void:
	call_deferred("run_checks")
	create_timer(60.0).timeout.connect(func(): push_error("Room failure suite timed out"); quit(1))

func _finalize() -> void:
	# An accidental production quit(0) must not turn a truncated acceptance run
	# into a pass: tools/test.ps1 rejects this diagnostic even on exit code zero.
	if not suite_completed:
		push_error("Room failure suite exited before its completion checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func frames(count: int = 3) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = code
	pressed.physical_keycode = code
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await frames(1)

func document() -> Dictionary:
	# Loading through a separate store leaves the active controller's pending
	# settlement and injected failure path untouched.
	return ProfileStore.new(healthy_path).load_document()

func unchanged_progress(profile: Dictionary) -> Dictionary:
	var result := profile.duplicate(true)
	result.erase("last_result")
	result.erase("total_runs")
	return result

func same_saved_values(left: Dictionary, right: Dictionary) -> bool:
	# JSON loads numbers as floats and drops typed Array metadata. Compare both
	# sides in the actual persistence representation instead of Variant types.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func top_contains_focus() -> bool:
	if app.modals.is_empty():
		return false
	var focus := root.gui_get_focus_owner()
	return is_instance_valid(focus) and app.modals[-1].node.is_ancestor_of(focus)

func return_button() -> Button:
	return app.screen.find_child("RoomLoadReturnCamp", true, false) as Button

func assert_error_page(locale: String, pending: bool, context: String) -> void:
	check(app.route == "room_error", context + ": failed first room stays on its friendly error route")
	check(app.room == null and app.hud == null and app.world.get_child_count() == 0, context + ": no failed room, HUD or active world remains")
	check(app.created_room != null and app.created_room.get_ref() == null, context + ": failed real room is released")
	var message: Label = app.screen.find_child("RoomLoadFailureMessage", true, false) as Label
	var expected := "The room could not be loaded. Return to camp and try again." if locale == "en" else "房间未能加载，请返回营地后重试。"
	check(message != null and message.text == expected and message.text == Words.text("ROOM_LOAD_FAILED_NOTE"), context + ": error page displays the exact localized recovery message")
	var visible_copy := ""
	for control in app.screen.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and (control is Label or control is Button):
			visible_copy += str(control.text).to_lower() + "\n"
	var contains_diagnostics := false
	for forbidden: String in ["invalid_test_room", "configuration", "seed", "generator", "生成器", "种子"]:
		contains_diagnostics = contains_diagnostics or visible_copy.contains(forbidden)
	var raw_error := str(app.room_ready_snapshot.get("configuration_error", "")).to_lower()
	if not raw_error.is_empty():
		contains_diagnostics = contains_diagnostics or visible_copy.contains(raw_error)
	check(not contains_diagnostics, context + ": visible recovery copy exposes no room ID, seed or generator diagnostics")
	var button := return_button()
	check(button != null and button.disabled == pending, context + ": return-to-camp availability matches committed settlement")
	if not pending:
		check(button != null and button.has_focus(), context + ": ready return-to-camp button owns keyboard focus")

func run_checks() -> void:
	AudioServer.set_bus_mute(0, true)
	game = root.get_node("Game")
	if not game.profile_path.contains("test_"):
		push_error("Refusing room failure tests without isolated --test-profile=test_...")
		quit(2)
		return
	failure_app_script = GDScript.new()
	failure_app_script.source_code = FAILURE_APP_SOURCE
	check(failure_app_script.reload() == OK, "compile real app subclass after Game autoload is ready")
	if not failure_app_script.can_instantiate():
		quit(1)
		return
	healthy_path = game.profile_path
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(), "create isolated room-failure profile")
	# Establish meaningful balances using game APIs before the test app subscribes.
	check(game.start_run() and game.add_gold(73), "earn nonzero baseline bank through a real run")
	check(game.grant_hero_xp(45, "room_failure_baseline") and game.equip_relic("arc"), "earn baseline XP and a discovery through real APIs")
	check(not game.finish_run("extracted").is_empty() and game.profile.permanent_gold == 73, "commit baseline rewards before failure experiments")
	var fixture_dir := "user://test_room_failure_" + str(Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_dir)) == OK, "create isolated storage failure fixture directory")
	var blocker := FileAccess.open(AssetCatalog.resolve(fixture_dir + "/regular_file"), FileAccess.WRITE)
	check(blocker != null, "create deterministic storage failure fixture")
	if blocker == null:
		quit(1)
		return
	blocker.store_string("A regular file cannot be used as a profile directory.")
	blocker.close()
	blocked_path = fixture_dir + "/regular_file/profile.json"
	for locale: String in ["zh_CN", "en"]:
		for save_fails: bool in [false, true]:
			await check_first_room_failure(locale, save_fails)
	await check_normal_room_recovery()
	if is_instance_valid(app):
		app.free()
	await frames(2)
	print("ROOM_FAILURE_TEST_RESULT checks=", checks, " failures=", failures)
	suite_completed = true
	quit(1 if failures else 0)

func check_first_room_failure(locale: String, save_fails: bool) -> void:
	if is_instance_valid(app):
		app.free()
		await frames(2)
	game._store.path = healthy_path
	game.set_setting("language", locale)
	check(game.last_error.is_empty(), "persist failure-page locale " + locale)
	var before: Dictionary = game.profile.duplicate(true)
	var before_document := document()
	var label := locale + (" / settlement retry" if save_fails else " / direct settlement")
	app = failure_app_script.new()
	app.fail_settlement = save_fails
	app.storage_failure_path = blocked_path
	root.add_child(app)
	await frames(2)
	app.show_camp()
	await frames(2)
	# The invalid-layout factory targets legacy first-room configuration; the
	# expedition suite separately covers its prepare/apply transition path.
	check(game.start_run(), label + ": start legacy failure fixture through the real run signal")
	await frames(4)
	check(app.factory_calls == 1 and not app.start_document.is_empty(), label + ": real app invokes the room factory once")
	var receipt: Dictionary = app.start_document.get("active_run", {})
	check(not receipt.is_empty() and int(receipt.get("gold", -1)) == 0 and int(app.start_document.revision) == int(before_document.revision) + 1, label + ": zero-gold active receipt was saved before room creation")
	var observed: Dictionary = app.room_ready_snapshot
	check(not observed.is_empty() and not bool(observed.get("configuration_ready", true)) and bool(observed.get("layout_empty", false)), label + ": invalid ID fails real generator and room configuration")
	check(not bool(observed.get("has_player", true)) and not bool(observed.get("physics_processing", true)) and bool(observed.get("input_blocked", false)) and not bool(observed.get("spawn_enabled", true)), label + ": real failed room creates no player and stops simulation")
	assert_error_page(locale, save_fails, label)
	if save_fails:
		await check_required_retry(before, receipt, locale, label)
	else:
		check(game.run == null and app.modals.is_empty() and not paused, label + ": successful abandonment closes the run without a retry modal")
	assert_committed_failure(before, before_document, receipt, label)
	assert_error_page(locale, false, label + " after commit")
	await key(KEY_ENTER)
	await frames(2)
	check(app.route == "camp" and game.run == null and app.modals.is_empty(), label + ": keyboard return opens a usable camp")
	check(app.world.get_child_count() == 0 and app.hud == null, label + ": camp has no failed world or combat HUD")

func check_required_retry(before: Dictionary, receipt: Dictionary, locale: String, label: String) -> void:
	check(game.run != null and not game.last_error.is_empty(), label + ": failed save preserves pending run and reports storage failure")
	check(app.pending_outcome == "abandoned" and app.modals.size() == 1 and app.modals[-1].get("required", false) and paused, label + ": required abandonment retry owns the paused flow")
	check(top_contains_focus(), label + ": required retry owns keyboard focus")
	if game.run == null or app.modals.is_empty():
		return
	var pending_id: String = game.run.id
	var pending_elapsed: float = game.run.elapsed
	check(pending_id == str(receipt.id) and game.run.gold == 0 and game.run.hero_xp_gained == 0, label + ": pending run retains its real empty receipt")
	check(same_saved_values(game.profile, before), label + ": failed settlement changes no bank, XP, discovery, run count or prior result")
	var still_saved := document()
	check(still_saved.active_run is Dictionary and str(still_saved.active_run.id) == pending_id and int(still_saved.revision) == int(app.start_document.revision), label + ": disk retains the acknowledged active receipt without a partial settlement")
	await frames(12)
	check(is_equal_approx(float(game.run.elapsed), pending_elapsed) and game.run.gold == 0, label + ": unavailable world advances neither time nor gold while retry is pending")
	app._pop_modal()
	await key(KEY_ESCAPE)
	check(app.modals.size() == 1 and paused and top_contains_focus(), label + ": Back and Escape cannot dismiss required retry")
	app.show_camp()
	check(app.route == "room_error" and app.modals.size() == 1 and return_button() != null and return_button().disabled, label + ": direct camp navigation cannot bypass uncommitted settlement")
	app._quit()
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await frames(2)
	check(game.run != null and str(game.run.id) == pending_id and app.route == "room_error" and app.modals.size() == 1 and not app.quit_after_result, label + ": Quit and window close cannot bypass required retry")
	check(not game.add_gold(1) and not game.grant_hero_xp(1, "forbidden_failure_reward"), label + ": pending settlement rejects gameplay rewards")
	check(same_saved_values(game.profile, before) and game.run.gold == 0, label + ": blocked routes and rewards preserve the original profile and run")
	game._store.path = healthy_path
	check(top_contains_focus(), label + ": repair retains keyboard focus on the real retry control")
	await key(KEY_ENTER)
	await frames(4)
	check(game.run == null and game.last_error.is_empty() and app.modals.is_empty() and not paused, label + ": one keyboard retry commits settlement and removes the modal")
	assert_error_page(locale, false, label + " after retry")

func assert_committed_failure(before: Dictionary, before_document: Dictionary, receipt: Dictionary, label: String) -> void:
	check(game.run == null and same_saved_values(unchanged_progress(game.profile), unchanged_progress(before)), label + ": abandonment preserves bank, XP and all unrelated progress")
	check(int(game.profile.total_runs) == int(before.total_runs) + 1, label + ": failed room counts as exactly one finished run")
	var result: Dictionary = game.last_result
	check(str(result.get("run_id", "")) == str(receipt.get("id", "")) and str(result.get("outcome", "")) == "abandoned", label + ": committed result belongs to the failed room's receipt")
	check(int(result.get("collected", -1)) == 0 and int(result.get("retained", -1)) == 0 and int(result.get("lost", -1)) == 0 and int(result.get("hero_xp_gained", -1)) == 0 and int(result.get("kills", -1)) == 0 and int(result.get("shots", -1)) == 0, label + ": failed room grants no reward and records no combat")
	var committed := document()
	check(committed.get("active_run") == null and same_saved_values(committed.profile, game.profile), label + ": disk clears active_run in the same committed profile transaction")
	check(int(committed.revision) == int(before_document.revision) + 2, label + ": only start receipt and one settlement increment the save revision")
	var finished_profile: Dictionary = game.profile.duplicate(true)
	game.finish_run("abandoned")
	game.finish_run("extracted")
	check(same_saved_values(game.profile, finished_profile) and int(document().revision) == int(committed.revision), label + ": duplicate finish requests neither repay nor rewrite settlement")
	game.reload_profile()
	check(game.run == null and same_saved_values(game.profile, finished_profile) and int(document().revision) == int(committed.revision), label + ": reload sees no active run and cannot repeat abandonment")

func check_normal_room_recovery() -> void:
	app.fail_room = false
	app.fail_settlement = false
	var bank_before: int = game.profile.permanent_gold
	var xp_before: Dictionary = game.profile.hero_xp.duplicate(true)
	check(game.start_run(), "start legacy normal-room recovery fixture")
	await frames(4)
	check(app.route == "run" and game.run != null and is_instance_valid(app.room) and is_instance_valid(app.hud), "same app can start a normal room and HUD after failed-room recovery")
	if is_instance_valid(app.room):
		app.room.spawn_enabled = false
		check(app.room.configuration_ready and is_instance_valid(app.room.player) and app.room.is_physics_processing() and app.room.player.is_physics_processing(), "recovered normal room configures and runs real player physics")
		check(not app.room_start_failed and app.room.controls_enabled(), "normal retry clears the failure flag and enables real combat controls")
		var start: Vector2 = app.room.player.position
		var movement_action := ""
		var directions := {"move_right":Vector2.RIGHT, "move_down":Vector2.DOWN, "move_left":Vector2.LEFT, "move_up":Vector2.UP}
		for action: String in directions:
			var target: Vector2 = start + Vector2(directions[action]) * 40.0
			if app.room.move_actor(start, target - start, Balance.PLAYER_RADIUS).is_equal_approx(target):
				movement_action = action
				break
		check(not movement_action.is_empty(), "normal recovery provides a clear player movement direction")
		if not movement_action.is_empty():
			Input.action_press(movement_action)
			await frames(5)
			Input.action_release(movement_action)
			check(app.room.player.position.distance_to(start) > 5.0, "normal recovery accepts real keyboard movement")
	check(app.modals.is_empty() and not paused and app.world.get_child_count() == 1, "normal retry restores a single active world without the failure modal")
	check(game.profile.permanent_gold == bank_before and game.profile.hero_xp == xp_before, "starting normal recovery does not grant phantom bank or XP")
	check(not game.finish_run("abandoned").is_empty(), "cleanly settle the recovered normal test run")
	await frames(4)
	check(app.route == "result" and game.run == null and app.room == null, "normal-room completion restores the ordinary result route")
