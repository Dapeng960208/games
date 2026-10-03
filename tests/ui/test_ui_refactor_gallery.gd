extends Node
## Presentation-only capture of live V2 pages. Does not sample or tune balance.
const Fixtures = preload("res://tests/persistence/test_numerical_instance_storage.gd")
var app: Node
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var dimensions := Vector2i(2560,1440)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
	get_tree().create_timer(180).timeout.connect(func(): push_error("UI gallery timeout"); get_tree().quit(1))
func frames() -> void:
	for i in 3: await get_tree().process_frame
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func capture(id: String) -> void:
	await frames()
	var stem := "%s_%s_%dx%d" % [id,Words.locale,dimensions.x,dimensions.y]
	var viewport := get_viewport().get_visible_rect()
	for node: Node in app.ui.find_children("*","Button",true,false):
		var button := node as Button
		if not button.is_visible_in_tree(): continue
		var ancestor: Node = button.get_parent()
		var scrolling := false
		while ancestor != app.ui and ancestor != null:
			if ancestor is ScrollContainer: scrolling = true; break
			ancestor = ancestor.get_parent()
		if not scrolling: check(viewport.grow(2).encloses(button.get_global_rect()),stem+" button bounds: "+str(button.name))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot := get_viewport().get_texture().get_image()
		check(screenshot.get_size() == dimensions,stem+" native output dimensions")
		check(screenshot.save_png("res://artifacts/refactor/"+stem+".png") == OK,stem+" saved")
	captures.append({"id":id,"locale":Words.locale,"width":dimensions.x,"height":dimensions.y,"file":stem+".png"})
func modal(method: String, id: String) -> void:
	app.call(method)
	await capture(id)
	app._clear_modals()
	await frames()
func _run() -> void:
	if not Game.profile_path.contains("test_ui_refactor"): get_tree().quit(2); return
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--small": dimensions = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/refactor"))
	check(Game.new_profile(),"isolated profile created")
	var profile := Fixtures.fixture_profile()
	profile.permanent_gold = 12000
	profile.hero_xp.CH01 = 3600
	check(Game._commit_profile(profile),"saved V2 eight-slot fixture")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	get_window().size = dimensions
	await frames()
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		Game.profile.settings.language = locale
		app.show_menu(); await capture("menu")
		await modal("_request_new_profile","new_profile_confirmation")
		app.show_camp(); await capture("camp")
		if app.has_method("show_profile"): await modal("show_profile","profile")
		for section: String in ["general","controls"]:
			app.settings_tab = section; await modal("show_settings","settings_"+section)
		app.show_demo_select(); await capture("trial_select")
		app._show_demo_branches("CH01"); await capture("trial_branches")
		app._clear_modals()
		for page: String in ["heroes","skills","inventory","shop","craft","upgrade"]:
			app.show_workshop(page); await capture(page)
			if page == "inventory":
				var panel: Control = app.screen.find_child("Workshop",true,false)
				for tab: String in ["compare","set"]:
					panel.detail_tab = tab; panel._render(); await capture("inventory_"+tab)
				panel.search_query = "no matching item 0000"; panel._render(); await capture("inventory_empty")
			if page == "skills":
				var panel: Control = app.screen.find_child("Workshop",true,false)
				panel._show_branches(); await capture("skill_branches"); app._clear_modals()
		if app.has_method("show_codex"):
			app.show_codex(); await frames()
			check(app.screen.find_child("MonsterCodex",true,false) != null,"codex instantiated")
			check(app.screen.find_children("*","Button",true,false).size() > 10,"codex contains data entries")
			await capture("monster_codex")
		app.show_camp()
		check(Game.start_demo("CH01"),"isolated trial starts")
		await frames()
		app._clear_modals() # Dismiss the real trial briefing before showing the unobscured HUD.
		await frames()
		if is_instance_valid(app.room): app.room.process_mode = Node.PROCESS_MODE_DISABLED
		await capture("gameplay_hud")
		await modal("show_pause","pause")
		await modal("show_backpack","field_inventory")
		await modal("show_attributes","attributes")
		await modal("show_relics","relics")
		await modal("show_combat_details","skill_details")
		await modal("show_abandon","abandon_confirmation")
		Game.finish_run("abandoned")
		await capture("result")
		app.show_menu()
	var report := FileAccess.open(AssetCatalog.resolve("res://artifacts/refactor/report_%dx%d.json" % [dimensions.x,dimensions.y]),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"\t"))
	report.close()
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free(); await frames()
	print("UI REFACTOR GALLERY: %d checks, %d failures, %d captures" % [checks,failures.size(),captures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
