extends SceneTree
## Real expedition entry/input UI, followed by isolated legacy settlement fixtures.
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

func enter_first_expedition_combat() -> bool:
	check(app.expedition != null and app.expedition.active() and app.expedition.current_index() == 0,
		"real camp departure starts the expedition entrance")
	if app.expedition == null or not app.expedition.active() or app.modals.is_empty():
		check(false,"expedition entrance presents its required relic decision")
		return false
	var skip: Button = app.modals[-1].node.find_child("SkipExpeditionRelic",true,false) as Button
	check(skip != null and not skip.disabled,"entry relic decision exposes its real skip control")
	if skip == null or skip.disabled:
		return false
	skip.pressed.emit()
	await frames(3)
	check(app.modals.is_empty() and not paused,"entry relic decision returns combat control")
	app.room.player.position = app.room.exit_position
	await frames(2)
	app.room.interact()
	await frames(2)
	check(not app.modals.is_empty(),"entry exit interaction opens the real next-node route modal")
	var options: Array = app.expedition.next_options()
	if app.modals.is_empty() or options.is_empty():
		check(false,"entry route exposes a next combat node")
		return false
	var next_room := str(options[0])
	var choose: Button = app.modals[-1].node.find_child("Choose_"+next_room,true,false) as Button
	check(choose != null and not choose.disabled,"route modal enables the committed next-node choice")
	if choose == null or choose.disabled:
		return false
	choose.pressed.emit()
	await frames(4)
	var ready: bool = app.expedition.current_index() == 1 and app.modals.is_empty() and not paused
	check(ready and app.room.layout_id == next_room,"route choice enters the first combat room with live input")
	return ready

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
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
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
	check(game.select_hero("CH02"), "select the ranged hero for projectile input regression")
	app._start_run()
	await frames(4)
	check(app.route == "run" and app.room != null,"camp departure creates room and HUD")
	var entered_combat: bool = await enter_first_expedition_combat()
	if not entered_combat:
		quit(1)
		return
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
	# Basic attacks start with a fresh press after the dash; presses during a
	# dash are deliberately consumed rather than leaking into its recovery.
	while room.player.dash_timer > 0.0:
		await frames(1)
	Input.action_press("attack")
	await frames(ceili(float(game.run.stats.attack_interval) * Engine.physics_ticks_per_second) + 8)
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
	await frames(ceili(float(game.run.stats.attack_interval) * Engine.physics_ticks_per_second) + 8)
	Input.action_release("attack")
	check(game.run.shots > paused_shots,"fresh press works after release guard")
	# The real expedition input route is covered above. Its first combat node
	# cannot extract; keep the historical exact-value settlement UI checks in
	# their own legacy fixture instead of fabricating expedition completion.
	check(not game.finish_run("abandoned").is_empty(),"settle the expedition input fixture through real abandonment")
	await frames(3)
	var settlement_bank_before: int = game.profile.permanent_gold
	var settlement_runs_before: int = game.profile.total_runs
	app.show_camp()
	check(game.start_run(),"start legacy room for exact-value settlement UI checks")
	await frames(3)
	room = app.room
	# Freeze only for deterministic UI/state screenshots after separately testing real combat.
	room.set_physics_process(false)
	room.set_process(false)
	for enemy in room.enemies.get_children():
		enemy.set_physics_process(false)
	room.gold_drops.clear()
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
	check(app.route == "result" and game.profile.permanent_gold == settlement_bank_before+117,"legacy extraction routes to saved result with 100 percent")
	var receipt: Dictionary = game.last_result
	for _i in range(8):
		game.finish_run("extracted")
	check(game.profile.permanent_gold == settlement_bank_before+117 and game.profile.total_runs == settlement_runs_before+1,"repeated settlement cannot duplicate reward")
	app.show_result(receipt)
	await frames(1)
	check(game.profile.permanent_gold == settlement_bank_before+117,"reopening result does not pay again")
	await capture("result_extracted_1280")
	app.show_camp()
	check(game.start_run(),"start legacy room for exact-value death settlement")
	await frames(2)
	check(game.run != null and game.run.gold == 0 and game.run.relics.is_empty(),"return to camp and fresh departure clear temporary state")
	game.add_gold(119)
	# This fixture verifies death settlement, after the real combat/input route
	# above. A true-damage packet depletes health independently of the hero's
	# separately resolved armor and equipment reduction, including its shield.
	var raw_damage: float = game.run.hp + game.run.shield + 1.0
	game.damage_player(raw_damage,{"damage_type":"true"})
	await frames(3)
	check(app.route == "result" and game.last_result.outcome == "death","health depletion opens death settlement")
	check(game.profile.permanent_gold == settlement_bank_before+176 and game.last_result.retained == 59 and game.last_result.rules_version == 2,"current-rule death retains floor(119*0.5)=59")
	await capture("result_death_1280")
	game.reload_profile()
	check(game.profile.permanent_gold == settlement_bank_before+176 and game.profile.total_runs == settlement_runs_before+2,"reload preserves gold and settlement count")
	check(game.profile.discoveries.size() == 3,"discovery records survive settlement and reload")
	if graphical:
		app.show_camp()
		for size in [Vector2i(1920,1080),Vector2i(2560,1440)]:
			root.size = size
			await frames(3)
			await capture("camp_" + str(size.x))
		root.size = Vector2i(1280,720)
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(),"UI fixture releases music playback before shutdown")
	app.free()
	await frames(3)
	print("UI_TEST_RESULT checks=", checks, " failures=",failures," graphics=",graphical)
	quit(1 if failures else 0)
