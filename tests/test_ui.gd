extends SceneTree
## Runs the real main scene, input actions, modal stack, and rendered viewports.
## Use a dedicated --test-profile path. Screenshots are actual engine frames.

var failures := 0
var checks := 0
var app: Node
var game: Node
var graphical := false

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func capture(filename: String) -> void:
	if not graphical:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty(),"rendered " + filename)
	image.save_png("res://artifacts/" + filename + ".png")

func run_checks() -> void:
	game = root.get_node("Game")
	graphical = DisplayServer.get_name() != "headless"
	if not game.profile_path.contains("test_"):
		push_error("Refusing UI tests without an isolated --test-profile containing test_")
		quit(2)
		return
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(),"create isolated profile")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	check(app.route == "menu","main menu loads")
	await capture("menu_zh_1280")
	app.show_camp()
	await frames(2)
	check(app.route == "camp","camp loads")
	await capture("camp_zh_1280")
	app.show_settings()
	await frames(1)
	for button in app.screen.find_children("*","BaseButton",true,false):
		check(button.focus_mode == Control.FOCUS_NONE,"background button excluded from modal focus")
	app._toggle_language()
	await frames(2)
	check(Words.locale == "en","language actually switches to English")
	await capture("settings_en_1280")
	if graphical:
		app._toggle_fullscreen()
		await frames(2)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,"fullscreen changes actual native window mode")
		app._toggle_fullscreen()
		await frames(2)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED,"windowed mode restores actual native window")
	app._pop_modal()
	await capture("camp_en_1280")
	game.set_setting("language","zh_CN")
	Words.set_locale("zh_CN")
	app.show_camp()
	app._start_run()
	await frames(4)
	check(app.route == "run" and app.room != null,"camp departure creates room and HUD")
	var room: Node2D = app.room
	var start: Vector2 = room.player.position
	Input.action_press("move_right")
	await frames(12)
	Input.action_release("move_right")
	check(room.player.position.x > start.x+20,"WASD input moves the player")
	Input.action_press("dash")
	await frames(1)
	Input.action_release("dash")
	check(room.player.dash_cooldown > 0,"space triggers dash cooldown")
	Input.action_press("attack")
	await frames(20)
	Input.action_release("attack")
	check(game.run.shots > 0,"held attack emits projectiles")
	await capture("combat_zh_1280")
	app.show_pause()
	await frames(2)
	var paused_position: Vector2 = room.player.position
	var paused_elapsed: float = game.run.elapsed
	var paused_enemy: Vector2 = room.enemies.get_child(0).position if room.enemies.get_child_count() else Vector2.ZERO
	var paused_shots: int = game.run.shots
	Input.action_press("move_right")
	Input.action_press("attack")
	Input.action_press("dash")
	await frames(12)
	check(room.player.position == paused_position and game.run.elapsed == paused_elapsed,"pause stops player and run clock")
	check(room.enemies.get_child_count() == 0 or room.enemies.get_child(0).position == paused_enemy,"pause stops enemies")
	check(game.run.shots == paused_shots,"pause stops attacks")
	app.show_relics()
	await frames(2)
	check(app.modals.size() == 2 and paused,"nested relic modal remains paused")
	app._pop_modal()
	await frames(1)
	check(app.modals.size() == 1 and paused,"closing top modal keeps pause underneath")
	app._pop_modal()
	await frames(7)
	check(not paused and game.run.shots == paused_shots,"resume does not leak held fire input")
	Input.action_release("move_right")
	Input.action_release("attack")
	Input.action_release("dash")
	await frames(2)
	Input.action_press("attack")
	await frames(20)
	Input.action_release("attack")
	check(game.run.shots > paused_shots,"fresh press works after release guard")
	# Freeze only for deterministic UI/state screenshots after separately testing real combat.
	for relic in ["split","ember","arc"]:
		game.equip_relic(relic)
	game.add_gold(117)
	await frames(2)
	var chip: Button = app.hud.relic_row.get_child(0)
	var shots_before_chip: int = game.run.shots
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = chip.get_global_rect().get_center()
	root.push_input(mouse,true)
	await frames(2)
	check(paused and app.modals.size() == 1,"relic HUD chip opens paused details on mouse press")
	check(game.run.shots == shots_before_chip,"relic chip click cannot fire weapon")
	await capture("relic_details_zh_1280")
	mouse.pressed = false
	root.push_input(mouse,true)
	app._pop_modal()
	await frames(1)
	app.show_extraction()
	await frames(2)
	await capture("extraction_zh_1280")
	app._settle("extracted")
	await frames(3)
	check(app.route == "result" and game.profile.permanent_gold == 117,"extraction routes to saved result with 100 percent")
	var receipt: Dictionary = game.last_result
	for _i in range(8):
		game.finish_run("extracted")
	check(game.profile.permanent_gold == 117 and game.profile.total_runs == 1,"repeated settlement cannot duplicate reward")
	app.show_result(receipt)
	await frames(1)
	check(game.profile.permanent_gold == 117,"reopening result does not pay again")
	await capture("result_extracted_1280")
	app.show_camp()
	app._start_run()
	await frames(2)
	check(game.run != null and game.run.gold == 0 and game.run.relics.is_empty(),"return to camp and fresh departure clear temporary state")
	game.add_gold(119)
	game.damage_player(1000)
	await frames(3)
	check(app.route == "result" and game.last_result.outcome == "death","health depletion opens death settlement")
	check(game.profile.permanent_gold == 140 and game.last_result.retained == 23,"death retains floor(119*0.2)=23")
	await capture("result_death_1280")
	game.reload_profile()
	check(game.profile.permanent_gold == 140 and game.profile.total_runs == 2,"reload preserves gold and settlement count")
	check(game.profile.discoveries.size() == 3,"discovery records survive settlement and reload")
	if graphical:
		app.show_camp()
		for size in [Vector2i(1920,1080),Vector2i(2560,1440)]:
			root.size = size
			await frames(3)
			await capture("camp_" + str(size.x))
		root.size = Vector2i(1280,720)
	print("UI_TEST_RESULT checks=", checks, " failures=",failures," graphics=",graphical)
	quit(1 if failures else 0)
