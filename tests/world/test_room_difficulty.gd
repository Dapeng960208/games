extends SceneTree
## Real camp controls choose difficulty; legacy L01 fixtures verify enemy density.
## Run with tools/test.ps1 -Suite room_difficulty -SkipImport.
## The isolated test_ profile is mandatory; combat stays frozen and silent.

const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const EXPECTED_TOTALS := [28, 32, 37, 40, 44]
const EXPECTED_ZONES := [[9, 9, 10], [10, 10, 12], [12, 12, 13], [13, 13, 14], [14, 14, 16]]
const EXPECTED_LABELS := {
	"zh_CN":["普通", "进阶", "困难", "险境", "极限"],
	"en":["Normal", "Challenging", "Hard", "Severe", "Extreme"]
}

var checks := 0
var failures := 0
var app: Node
var game: Node
var room: Node2D
var original_stats: Dictionary
var run_ids: Array[String] = []
var observations: Array[Dictionary] = []
var captures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")
	create_timer(60.0).timeout.connect(func(): push_error("Room difficulty suite timed out"); quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func frames(count: int = 2) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await frames(1)

func document() -> Dictionary:
	return ProfileStore.new(game.profile_path).load_document()

func choice() -> OptionButton:
	return app.screen.find_child("DepartureDifficulty", true, false) as OptionButton

func count_label() -> Label:
	return app.screen.find_child("DepartureDifficultyHint", true, false) as Label

func assert_camp(locale: String, difficulty: int, context: String) -> void:
	check(app.route == "camp" and game.run == null, context + ": real camp has no active run")
	var select := choice()
	var note := count_label()
	check(select != null and note != null, context + ": visible camp exposes difficulty and enemy-count controls")
	if select == null or note == null:
		return
	check(select.is_visible_in_tree() and select.item_count == 5 and not select.disabled, context + ": five difficulty choices are visible and enabled")
	check(select.focus_mode == Control.FOCUS_ALL and select.size.y >= 44.0, context + ": selector is keyboard-focusable with a 44-pixel target")
	for index in range(5):
		check(select.get_item_text(index) == EXPECTED_LABELS[locale][index] and select.get_item_id(index) == index, context + ": localized option " + str(index) + " matches its difficulty ID")
	check(select.selected == difficulty and int(app.selected_difficulty) == difficulty, context + ": app and rebuilt selector preserve the chosen difficulty")
	var total := 0
	for zone in range(3):
		total += int(Profiles.encounter_plan("L01", zone, difficulty).total_count)
	check(total == EXPECTED_TOTALS[difficulty], context + ": independently expected legacy L01 total matches all three production plans")
	var expected_text: String = ("BASE: %d foes" if locale == "en" else "基础敌群 %d") % EXPECTED_TOTALS[difficulty]
	check(note.text.contains(expected_text), context + ": localized camp preview shows the selected real enemy total")
	check(note.get_line_count() * note.get_line_height() <= note.size.y, context + ": enemy-count copy fits its label height")
	var viewport_bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	check(viewport_bounds.encloses(select.get_global_rect()) and viewport_bounds.encloses(note.get_global_rect()), context + ": selector and count stay within the viewport")
	check(not select.get_global_rect().intersects(note.get_global_rect()), context + ": selector and count have separate readable bounds")
	for sibling in select.get_parent().get_children():
		if sibling is Label and sibling != note:
			check(not sibling.get_global_rect().intersects(select.get_global_rect()), context + ": camp labels do not overlap the difficulty selector")

func select_difficulty(difficulty: int, locale: String) -> void:
	var before := document()
	var disk_bytes := FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path))
	var profile_before: Dictionary = game.profile.duplicate(true)
	var stats_before: Dictionary = game.selected_stats().duplicate(true)
	var select := choice()
	check(select != null, locale + ": real difficulty selector exists before choosing " + str(difficulty))
	if select == null:
		return
	# Real keyboard activation opens the popup, navigates from its selected item,
	# and accepts a choice through OptionButton's native selection connection.
	select.grab_focus()
	await key(KEY_ENTER)
	check(select.get_popup().visible, locale + ": keyboard opens the real difficulty popup")
	for _step in range(5):
		if select.get_popup().get_focused_item() == difficulty:
			break
		await key(KEY_DOWN)
	check(select.get_popup().get_focused_item() == difficulty, locale + ": keyboard focuses the requested difficulty before accepting it")
	await key(KEY_ENTER)
	await frames(1)
	assert_camp(locale, difficulty, locale + " selected D" + str(difficulty))
	var after := document()
	check(after.revision == before.revision and after.schema_version == before.schema_version, locale + ": choosing difficulty does not increment revision or change schema")
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path)) == disk_bytes and after == before and game.profile == profile_before, locale + ": choosing difficulty writes no profile fields or disk bytes")
	check(game.selected_stats() == stats_before and stats_before == original_stats, locale + ": choosing difficulty does not modify hero level, gear, talents or resolved stats")

func run_checks() -> void:
	AudioServer.set_bus_mute(0, true)
	game = root.get_node("Game")
	root.size = Vector2i(1280, 720)
	if not game.profile_path.contains("test_"):
		push_error("Refusing room difficulty tests without isolated --test-profile=test_...")
		quit(2)
		return
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(), "create isolated difficulty profile")
	game.set_setting("language", "zh_CN")
	check(game.last_error.is_empty(), "start with the real Chinese locale setting")
	original_stats = game.selected_stats().duplicate(true)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	root.add_child(app)
	app.show_camp()
	await frames()
	assert_camp("zh_CN", 0, "first camp defaults to Normal")
	for locale: String in ["zh_CN", "en"]:
		if Words.locale != locale:
			await toggle_language(locale)
		for difficulty in range(5):
			await select_difficulty(difficulty, locale)
			if difficulty == 4:
				await capture_camp(locale)
			await depart_and_check(difficulty, locale)
	await toggle_language("zh_CN")
	assert_camp("zh_CN", 4, "language round-trip retains Extreme")
	check(run_ids.size() == 10 and int(game.profile.total_runs) == 10, "ten distinct real runs prove the difficulty is read afresh on every departure")
	check(game.selected_stats() == original_stats, "all difficulty runs preserve the original hero stats")
	check(AudioServer.is_bus_mute(0), "Master remains muted throughout all difficulty runs")
	if is_instance_valid(app):
		app.free()
	await frames()
	print("ROOM_DIFFICULTY_OBSERVATIONS ", JSON.stringify(observations))
	print("ROOM_DIFFICULTY_TEST_RESULT checks=", checks, " failures=", failures, " real_runs=", run_ids.size(), " captures=", captures.size())
	quit(1 if failures else 0)

func capture_camp(locale: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var focused := root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	await frames(2)
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var filename := "camp_difficulty_" + locale + "_1280.png"
	check(screenshot != null and screenshot.get_size() == Vector2i(1280, 720), locale + ": camp screenshot is the real 1280 by 720 viewport")
	if screenshot == null:
		return
	check(screenshot.save_png("res://artifacts/" + filename) == OK, locale + ": save real camp difficulty screenshot")
	captures.append(filename)

func toggle_language(locale: String) -> void:
	var selected_before: int = app.selected_difficulty
	app.show_settings()
	await frames(1)
	# Settings initially focuses its real Language button; Enter invokes the
	# normal setting transaction and camp/modal rebuild.
	await key(KEY_ENTER)
	check(Words.locale == locale and game.profile.settings.language == locale, "real settings keyboard action switches language to " + locale)
	await key(KEY_ESCAPE)
	check(app.modals.is_empty() and not paused, "language settings closes through Escape")
	assert_camp(locale, selected_before, "language rebuild " + locale)

func depart_and_check(difficulty: int, locale: String) -> void:
	var context := locale + " D" + str(difficulty)
	var before := document()
	var depart := app.screen.find_child("Depart", true, false) as Button
	check(depart != null and not depart.disabled, context + ": live departure button is available")
	if depart == null:
		return
	# The camp button now starts an eight-node expedition. Keep this density
	# fixture on legacy L01; the real run signal still lets main apply its selected
	# difficulty. Freeze before any enemy or player physics tick.
	check(game.start_run(), context + ": start the legacy L01 density fixture")
	room = app.room
	check(game.run != null and app.route == "run" and is_instance_valid(room), context + ": real departure starts Game and creates the production room")
	if game.run == null or not is_instance_valid(room):
		return
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.set_input_blocked(true)
	await frames(1)
	check(room.configuration_ready and room.layout_id == "L01" and int(room.difficulty) == difficulty, context + ": initial real room receives the selected difficulty")
	check(not run_ids.has(game.run.id), context + ": departure creates a new run ID")
	run_ids.append(game.run.id)
	check(game.run.stats == original_stats and game.run.level == game.hero_level(), context + ": harder enemies do not scale or rewrite hero stats")
	var started := document()
	check(int(started.revision) == int(before.revision) + 1 and started.active_run is Dictionary, context + ": departure saves exactly one normal active-run receipt")
	check(not started.profile.has("difficulty") and not started.active_run.has("difficulty") and started.schema_version == before.schema_version, context + ": transient difficulty requires no profile or receipt schema field")
	var hp_before: float = game.run.hp
	var zone_counts: Array[int] = []
	var zone_levels: Array[int] = []
	for zone in range(3):
		var plan: Dictionary = room._encounter_plan(zone)
		var expected_level := 1 + zone * 2 + difficulty * 2
		check(plan == Profiles.encounter_plan("L01", zone, difficulty), context + " Z" + str(zone) + ": room uses its selected production encounter plan")
		check(int(plan.total_count) == EXPECTED_ZONES[difficulty][zone], context + " Z" + str(zone) + ": plan has the independent expected density")
		room.player.position = room.encounter_zones[zone].center
		room._update_encounters(0.0)
		check(room.encounter_progress.has(zone), context + " Z" + str(zone) + ": real zone activates")
		if not room.encounter_progress.has(zone):
			continue
		var actual_count := 0
		for batch in range(plan.waves.size()):
			var actors: Array[Node] = room.enemies.get_children()
			check(actors.size() == plan.waves[batch].size() and not actors.is_empty(), context + " Z" + str(zone) + " batch " + str(batch) + ": complete planned batch becomes real enemies")
			for enemy in actors:
				check(enemy.enemy_level == expected_level and int(enemy.profile.enemy_level) == expected_level and int(enemy.profile.difficulty) == difficulty, context + " Z" + str(zone) + ": actual " + str(enemy.enemy_id) + " has the selected enemy level and difficulty")
				check(enemy.zone_index == zone and enemy.owner_enemy == null and enemy.reward_enabled, context + ": cumulative count includes actual natural enemies only")
				actual_count += 1
				# Encounter integration separately tests death/rewards. Remove these
				# frozen real actors so this UI test cannot award XP or change stats.
				enemy.free()
			if batch + 1 < plan.waves.size():
				room._update_encounters(3.0)
		check(actual_count == EXPECTED_ZONES[difficulty][zone], context + " Z" + str(zone) + ": actual cumulative spawns equal the displayed-plan contribution")
		zone_counts.append(actual_count)
		zone_levels.append(expected_level)
	var total := 0
	for count in zone_counts:
		total += count
	check(total == EXPECTED_TOTALS[difficulty] and room._encounters_exhausted(), context + ": all real waves spawn exactly the expected legacy L01 total")
	check(is_equal_approx(game.run.hp, hp_before) and game.run.shots == 0 and game.run.kills == 0 and game.run.hero_xp_gained == 0, context + ": frozen combat introduces no damage, attacks, rewards or hero scaling")
	observations.append({"locale":locale, "difficulty":difficulty, "zone_counts":zone_counts, "zone_levels":zone_levels, "actual_total":total})
	var result: Dictionary = game.finish_run("abandoned")
	check(not result.is_empty() and result.outcome == "abandoned", context + ": normal abandonment finishes the real run")
	await frames()
	check(app.route == "result" and game.run == null and app.room == null, context + ": production result flow releases the room")
	var settled := document()
	check(int(settled.revision) == int(before.revision) + 2 and settled.active_run == null, context + ": only start and settlement write the save")
	# The result page focuses its real Return to Camp button.
	await key(KEY_ENTER)
	await frames(1)
	assert_camp(locale, difficulty, context + " return to camp")
