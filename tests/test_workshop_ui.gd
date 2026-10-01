extends SceneTree
## Exercises real workshop controls and persistence using an isolated test profile.
var checks := 0
var failures := 0
var app: Node
var game: Node

func _initialize() -> void:
	call_deferred("run_checks")
	create_timer(45.0).timeout.connect(func(): push_error("Workshop suite timed out"); quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ",description)
	else:
		failures += 1
		push_error("FAIL "+description)

func frames(count: int = 3) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func workshop() -> Control:
	return app.screen.get_node("Workshop")

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(not frame.is_empty(),"rendered "+name_value)
	frame.save_png("res://artifacts/"+name_value+".png")

func run_checks() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_"):
		push_error("Refusing workshop tests without isolated --test-profile=test_...")
		quit(2)
		return
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(),"create isolated workshop profile")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.show_camp()
	await frames()
	check(app.screen.find_child("Open_heroes",true,false) != null,"camp exposes hero dossiers")
	app.screen.find_child("Open_heroes",true,false).pressed.emit()
	await frames()
	check(app.route == "workshop_heroes","camp hero action opens actual route")
	var original: String = game.profile.selected_hero
	workshop().find_child("Preview_CH02",true,false).pressed.emit()
	await frames()
	check(game.profile.selected_hero == original,"hero preview never changes active hero")
	check(workshop().preview_hero == "CH02","preview shows requested hunter")
	workshop().action_button.pressed.emit()
	await frames()
	check(game.profile.selected_hero == "CH02","select button commits hero change")
	game.reload_profile()
	check(game.profile.selected_hero == "CH02","selected hero survives reload")
	app.show_workshop("shop")
	await frames()
	workshop().selected_item = "EQ02"
	workshop().shop_sets = false
	workshop()._render()
	await frames()
	check(workshop().action_button.disabled,"unaffordable equipment cannot be bought")
	# Seed real earned currency through the same settlement API as a played expedition.
	check(game.start_run() and game.add_gold(1000),"create earned shop balance")
	game.finish_run("extracted")
	await frames()
	app.show_workshop("shop")
	await frames()
	workshop().selected_item = "EQ02"
	workshop().shop_sets = false
	workshop()._render()
	await frames()
	check(not workshop().action_button.disabled,"affordable implemented gear can be purchased")
	var before: int = game.profile.permanent_gold
	workshop().action_button.pressed.emit()
	workshop()._commit_item()
	await create_timer(0.35).timeout
	await frames()
	check(game.profile.equipment.has("EQ02"),"purchase adds selected item to permanent inventory")
	check(game.profile.permanent_gold == before-int(ContentRegistry.equipment("EQ02").price),"purchase charges exactly one catalog price")
	workshop().action_button.pressed.emit()
	await create_timer(0.35).timeout
	await frames()
	check(game.profile.loadout.weapon == "EQ02","owned purchase action equips actual slot")
	app.show_workshop("upgrade")
	await frames()
	workshop().selected_item = "EQ02"
	workshop()._render()
	await frames()
	before = game.profile.permanent_gold
	var cost: int = game.upgrade_cost("EQ02")
	workshop().action_button.pressed.emit()
	workshop()._commit_item()
	await create_timer(0.35).timeout
	await frames()
	check(game.equipment_level("EQ02") == 1 and game.profile.permanent_gold == before-cost,"double click upgrades once and charges once")
	game.reload_profile()
	check(game.equipment_level("EQ02") == 1 and game.profile.loadout.weapon == "EQ02","equipment and refinement persist")
	# A failed transaction must leave a real, focused retry path after the error closes.
	var healthy_path: String = game._store.path
	var blocker_path := "user://test_workshop_blocker_"+str(Time.get_ticks_usec())
	var blocker := FileAccess.open(blocker_path,FileAccess.WRITE)
	check(blocker != null,"create isolated transaction-failure fixture")
	if blocker == null:
		quit(1)
		return
	blocker.store_string("Cannot create a child directory inside this file.")
	blocker.close()
	game._store.path = blocker_path+"/profile.json"
	before = game.profile.permanent_gold
	workshop().action_button.pressed.emit()
	await frames()
	check(game.equipment_level("EQ02") == 1 and game.profile.permanent_gold == before,"failed upgrade leaves level and gold unchanged")
	check(app.modals.size() == 1 and app.modals[-1].node.is_ancestor_of(root.gui_get_focus_owner()),"transaction error owns modal focus")
	app._pop_modal()
	await frames()
	check(not workshop().action_button.disabled,"closing save failure restores a usable retry button")
	game._store.path = healthy_path
	workshop().action_button.pressed.emit()
	await create_timer(0.35).timeout
	await frames()
	check(game.equipment_level("EQ02") == 2,"the same failed upgrade can be retried after storage repair")
	app.show_workshop("skills")
	await frames()
	workshop()._show_branches()
	await frames()
	check(app.modals[-1].node.find_child("Branch_q_A",true,false).disabled,"level 18 branch is disabled before its actual unlock")
	app._pop_modal()
	check(game.start_run(),"start branch progression fixture")
	check(game.grant_hero_xp(3600,"workshop_branch_training"),"earn capped hero XP through progression API")
	game.finish_run("extracted")
	await frames()
	app.show_workshop("skills")
	await frames()
	workshop()._show_branches()
	await frames()
	app.modals[-1].node.find_child("Branch_q_A",true,false).pressed.emit()
	await frames()
	check(game.hero_branches("CH02").q == "A","branch A button changes actual selected hero build")
	check(game.hero_branches("CH01").q == "","branch choice leaves other hero unchanged")
	app.modals[-1].node.find_child("Branch_ultimate_B",true,false).pressed.emit()
	await frames()
	check(game.hero_branches("CH02").ultimate == "B","level 20 branch can be combined with level 18 choice")
	await capture("workshop_branches_zh_CN_1280")
	app._pop_modal()
	game.reload_profile()
	check(game.hero_branches("CH02").q == "A" and game.hero_branches("CH02").ultimate == "B","hero branches survive reload")
	for language in ["zh_CN","en"]:
		Words.set_locale(language)
		for page in ["heroes","skills","inventory","shop","upgrade"]:
			app.show_workshop(page)
			await frames()
			check(root.gui_get_focus_owner() != null,"focus exists on "+language+" "+page)
			await capture("workshop_"+page+"_"+language+"_1280")
			app.show_settings()
			await frames()
			var background_excluded := true
			for control in app.screen.find_children("*","BaseButton",true,false):
				background_excluded = background_excluded and control.focus_mode == Control.FOCUS_NONE
			check(background_excluded,"modal excludes every control on "+language+" "+page)
			app._pop_modal()
			await frames()
		app.show_camp()
		await frames()
		await capture("workshop_camp_"+language+"_1280")
	Words.set_locale("zh_CN")
	app.show_workshop("skills")
	app.show_settings()
	app._toggle_language()
	await frames()
	check(app.route == "workshop_skills" and app.modals.size() == 1,"language rebuild preserves workshop route and modal")
	app._pop_modal()
	app.show_camp()
	# Resource HUD fixtures use the legacy room without a required relic decision.
	check(game.start_run(),"start legacy room for workshop HUD checks")
	await frames()
	check(app.hud != null,"run creates a real HUD")
	if app.hud == null:
		quit(1)
		return
	check(app.hud.health_bar.max_value == game.run.max_hp,"HUD maximum health comes from hero snapshot")
	check(app.hud.region_label.text.contains(Words.text("ROOM_"+app.room.layout_id)),"HUD identifies the actual loaded room")
	game.run.resource = 37
	game.run.shield = 19
	app.hud.refresh()
	check(app.hud.resource_bar.value == 37,"HUD reads actual single hero resource")
	check(app.hud.shield_bar.visible and app.hud.shield_bar.value == 19,"HUD shield strip reflects actual shield")
	check(app.hud.health_bar.size.y <= 20 and app.hud.resource_bar.size.y <= 9,"storybook health and resource bars stay inside the HUD panel")
	var original_position: Vector2 = app.room.player.position
	app.room.player.position = app.room.ARENA.end-Vector2(100,100)
	app.room.camera.follow_target()
	app.room.camera.force_update_scroll()
	app.hud._update_navigation()
	check(app.hud.navigation.visible,"offscreen objective has a visible navigation pointer")
	check(app.hud.navigation.position.x >= 0 and app.hud.navigation.position.x+app.hud.navigation.size.x <= 1280 and app.hud.navigation.position.y >= 154 and app.hud.navigation.position.y+app.hud.navigation.size.y < 600,"navigation pointer stays inside the HUD safe area")
	app.room.player.position = original_position
	app.room.camera.follow_target()
	app.room.camera.force_update_scroll()
	app.hud.refresh()
	await capture("workshop_hud_hunter_1280")
	game.finish_run("extracted")
	await frames()
	for hero_id in ["CH01","CH03"]:
		check(game.select_hero(hero_id),"select "+hero_id+" for resource HUD")
		app.show_camp()
		check(game.start_run(),"start legacy room for "+hero_id+" resource HUD")
		await frames()
		check(app.hud.hero_definition.id == hero_id and app.hud.resource_kind == ContentRegistry.hero(hero_id).resource_type,"HUD uses "+hero_id+" identity and its own resource type")
		check(app.hud.health_bar.max_value == game.run.max_hp,"HUD uses "+hero_id+" real maximum health")
		await capture("workshop_hud_"+hero_id+"_1280")
		game.finish_run("extracted")
		await frames()
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(),"workshop music releases playback resources before exit")
	app.free()
	await frames()
	print("WORKSHOP_UI_TEST_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
