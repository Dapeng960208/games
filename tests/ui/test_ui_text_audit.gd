extends Node
## Screenshot sweep of production UI routes with isolated, explicit UI fixtures.
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Loot = preload("res://scripts/presentation/equipment/loot_pickup_panel.gd")
const Field = preload("res://scripts/presentation/equipment/field_equipment_panel.gd")
var app: Node
var phase := "after"
var records: Array = []
var checks := 0
var failures := 0
var ordinal := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(180).timeout.connect(func(): push_error("UI text capture timed out"); get_tree().quit(1))
	_run.call_deferred()

func frames() -> void:
	for index: int in 3: await get_tree().process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("UI TEXT AUDIT: "+message)

func capture(id: String) -> void:
	await frames()
	ordinal += 1
	var stem := "ui_audit_%s_%02d_%s_%s" % [phase,ordinal,Words.locale,id]
	var controls: Array = []
	for label: Node in app.ui.find_children("*","Label",true,false):
		if not label.is_visible_in_tree() or label.text.is_empty(): continue
		var rect: Rect2 = label.get_global_rect()
		if not rect.intersects(get_viewport().get_visible_rect()): continue
		controls.append({"path":str(label.get_path()),"text":label.text,"font":label.get_theme_font_size("font_size"),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	var workshop: Control = app.ui.find_child("Workshop",true,false)
	if phase == "after":
		for button: Button in app.ui.find_children("*","Button",true,false):
			if not button.is_visible_in_tree() or button.text.is_empty() or button.get_script() != load(AssetCatalog.resolve("res://scripts/presentation/components/game_button.gd")): continue
			var skin := button.get_theme_stylebox("normal")
			var width := button.size.x-skin.content_margin_left-skin.content_margin_right-8
			var font := button.get_theme_font("font")
			for line: String in button.text.split("\n"):
				check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x <= width+1,"translated button caption fits: "+id+" / "+button.name)
		for entry: Dictionary in app.modals:
			var overlay: Control = entry.node
			if not overlay.visible: continue
			var actions: Array[Button] = []
			for button: Button in overlay.find_children("*","Button",true,false):
				if not button.is_visible_in_tree(): continue
				if button.has_meta("paired_action"): actions.append(button)
				var ancestor: Node = button.get_parent()
				var scrolled := false
				while ancestor != overlay and ancestor != null:
					if ancestor is ScrollContainer: scrolled = true; break
					ancestor = ancestor.get_parent()
				if not scrolled:
					check(get_viewport().get_visible_rect().grow(1).encloses(button.get_global_rect()),"modal action fits viewport: "+id+" / "+button.name)
			for scroll: ScrollContainer in overlay.find_children("*","ScrollContainer",true,false):
				if scroll.is_visible_in_tree(): check(get_viewport().get_visible_rect().grow(1).encloses(scroll.get_global_rect()),"modal scroll area fits viewport: "+id+" / "+scroll.name)
			if actions.size() == 2:
				check(actions[0].size.is_equal_approx(actions[1].size),"paired actions have equal width and height: "+id)
				check(is_equal_approx(actions[0].position.y,actions[1].position.y),"paired actions share a baseline: "+id)
	if phase == "after" and workshop != null:
		var heading: Control = workshop.find_child("WorkshopHeading",true,false)
		check(heading != null,"header has its own named title region")
		if heading != null:
			for key: String in ["OpenCharacterStats","ToggleSetShop","ToggleRecycle","Tab_heroes","Tab_shop","ReturnCamp"]:
				var button: Control = workshop.find_child(key,true,false)
				if button != null: check(not heading.get_global_rect().intersects(button.get_global_rect()),"title does not overlap "+key+" / "+Words.locale)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://artifacts/"+stem+".png") == OK,"capture "+id)
	records.append({"step":ordinal,"locale":Words.locale,"screen":id,"file":stem+".png","labels":controls})

func workshop(page: String) -> Control:
	app.show_workshop(page)
	await frames()
	return app.screen.find_child("Workshop",true,false)

func modal_capture(method: String, id: String) -> void:
	app.call(method)
	await capture(id)
	app._clear_modals()
	await frames()

func _camp_pages() -> void:
	app.show_menu(); await capture("menu")
	await modal_capture("_request_new_profile","new_profile_confirm")
	app.show_demo_select(); await capture("hero_trial_select")
	app.show_camp(); await capture("camp")
	app.settings_tab = "general"; await modal_capture("show_settings","settings_general")
	app.settings_tab = "controls"; app.show_settings(); await capture("settings_controls")
	app._begin_control_binding("skill_q"); await capture("binding_capture")
	app._clear_modals(); await frames()
	var panel: Control = await workshop("heroes")
	await capture("hero_dossier")
	for hero: String in ["CH02","CH03"]:
		panel.preview_hero = hero; panel._render(); await capture("hero_dossier_"+hero)
	panel = await workshop("skills"); await capture("skill_growth")
	panel._show_branches(); await capture("skill_branches"); app._clear_modals()
	panel._show_core_actions(ContentRegistry.hero(Game.profile.selected_hero)); await capture("hero_passive"); app._clear_modals()
	panel = await workshop("inventory"); panel.selected_item = "EQ61"; panel._render(); await capture("inventory_stats")
	panel.detail_tab = "compare"; panel.selected_item = "EQ08"; panel._render(); await capture("inventory_compare")
	panel.detail_tab = "set"; panel._render(); await capture("inventory_set")
	panel._show_character_stats(); await capture("camp_character_stats"); app._clear_modals()
	panel.search_query = "no_matching_item"; panel._render(); await capture("inventory_empty_search")
	panel.search_query = ""; panel.inventory_recycle = true; panel.sale_selection = {"EQ08":true,"EQ02":true}; panel._render(); await capture("recycle_selected")
	panel.action_button.pressed.emit(); await capture("recycle_confirm"); app._clear_modals(); await frames()
	panel = await workshop("shop"); await capture("set_shop_effects")
	panel.set_detail_tab = "compare"; panel.selected_set = "S11"; panel._render(); await capture("set_shop_compare")
	panel.shop_sets = false; panel.selected_item = "EQ92"; panel._render(); await capture("individual_shop")
	panel.detail_tab = "compare"; panel._render(); await capture("individual_shop_compare")
	panel = await workshop("upgrade"); panel.selected_item = "EQ61"; panel._render(); await capture("refinement_stats")
	panel.detail_tab = "compare"; panel._render(); await capture("refinement_compare")

func _field_pages() -> void:
	app.show_camp(); app._start_run(); await frames()
	await capture("starting_relic_offer")
	app._clear_modals()
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	app.room.spawn_enabled = false
	app.hud.refresh(); await capture("combat_hud")
	if Words.locale == "en":
		check(app.hud.region_label.text == "Entrance Staging Post","service HUD uses the English room definition")
		check(app.hud.objective_label.text.contains("View route") and not app.hud.objective_label.text.contains("完成"),"English service objectives keep their navigation instruction")
	app._show_trial_brief(); await capture("trial_brief"); app._clear_modals()
	for entry: Array in [["show_pause","pause"],["show_combat_details","combat_skill_details"],["show_attributes","combat_attributes"],["show_backpack","combat_backpack"],["show_relics","relics_empty"],["show_abandon","abandon_confirm"],["show_expedition_exit","save_exit_confirm"],["show_expedition","route_atlas"]]:
		await modal_capture(entry[0],entry[1])
	app.show_backpack(); await frames()
	var backpack: Control = app.ui.find_child("BackpackPanel",true,false)
	backpack.selected_id = "EQ08"; backpack.detail_tab = "compare"; backpack._render(); await capture("backpack_compare")
	backpack.detail_tab = "set"; backpack._render(); await capture("backpack_set")
	backpack.tab = "stats"; backpack._render(); await capture("backpack_attributes"); app._clear_modals()
	# Filled/max-length overlays exercise the live UI without committing a reward.
	var prior_relics: Array = Game.run.relics.duplicate()
	var prior_offers: Dictionary = Game.run.expedition.offers.duplicate(true)
	Game.run.relics = ["RL01","RL02","RL03","RL01","RL02","RL03"]
	await modal_capture("show_relics","relics_full")
	app._show_expedition_relic({"offer_id":"audit_relic","candidates":["RL01","RL02","RL03"]}); await capture("relic_choice"); app._clear_modals()
	Game.run.expedition.offers = {}
	for product: String in ["heal_small","heal_large","shield","amplify","scan","energy"]:
		Game.run.expedition.offers["audit_"+product] = {"kind":"supply","offer_id":"audit_"+product,"product_id":product,"price":65,"decision":""}
	await modal_capture("_show_expedition_supply","supply_shop")
	var popup: Panel = app._push_modal("",Vector2(840,574))
	var loot := Loot.new(); popup.add_child(loot)
	loot.configure([{"equipment_id":"EQ92","drop_id":"audit_drop","level":3},{"equipment_id":"EQ84","drop_id":"audit_drop_2","level":2}])
	await capture("loot_pickup"); app._clear_modals()
	popup = app._push_modal("",Vector2(980,620))
	var field := Field.new(); popup.add_child(field)
	var before: Dictionary = Game.run.stats.duplicate(true)
	var loadout: Dictionary = Game.run.loadout_snapshot.duplicate(true)
	loadout.head = "EQ92"
	var owned: Dictionary = Game.run.equipment_snapshot.duplicate(true); owned.EQ92 = {"level":3}
	field.configure({"slot":"head","current_id":Game.run.loadout_snapshot.head,"equipment_id":"EQ92","level":3,"current_level":0,"current_stats":before,"next_stats":Inspect.Resolver.resolve(Game.run.hero_id,Game.run.level,loadout,owned)})
	await capture("loot_comparison"); app._clear_modals()
	# A finished node reveals the real extraction modal instead of route gating.
	app.expedition = null
	await modal_capture("show_extraction","extraction_confirm")
	app._show_expedition_error(Words.text("STORAGE_WRITE_FAILED"),func(): app._pop_modal()); await capture("expedition_error"); app._clear_modals()
	Game.last_error = "STORAGE_WRITE_FAILED"; await modal_capture("_show_save_error","save_error")
	Game.run.relics = prior_relics
	Game.run.expedition.offers = prior_offers
	Game.last_error = ""
	Game.finish_run("abandoned"); await frames()
	check(Game.run == null,"screenshot fixtures restore before real settlement")
	for outcome: String in ["extracted","death","abandoned"]:
		var retained := ProfileStore.retained_gold(728,outcome)
		app.show_result({"outcome":outcome,"gold":728,"collected":728,"retained":retained,"lost":728-retained,"permanent_gold":Game.profile.permanent_gold,"hero_id":"CH01","hero_xp_gained":125 if outcome == "extracted" else 0,"field_xp_gained":60,"equipment_retained":["EQ92","EQ84","EQ61"] if outcome == "extracted" else []})
		await capture("result_"+outcome)

func _run() -> void:
	if not Game.profile_path.contains("test_ui_text_audit"): get_tree().quit(2); return
	if FileAccess.file_exists(AssetCatalog.resolve("res://artifacts/ui_audit_phase.txt")): phase = FileAccess.get_file_as_string(AssetCatalog.resolve("res://artifacts/ui_audit_phase.txt")).strip_edges()
	check(Game.new_profile(),"isolated visual fixture")
	check(Game.start_run() and Game.add_gold(12000),"real fixture settlement")
	Game.finish_run("extracted")
	for id: String in ["S09"]: check(Game.buy_equipment_set(id),"fixture owns inspected set")
	for id: String in ["EQ08","EQ02"]: check(Game.buy_equipment(id),"fixture owns unused equipment")
	for index: int in 3: check(Game.upgrade_equipment("EQ61"),"fixture actual refinement")
	check(Game.equip_equipment_set("S09"),"fixture six-piece set")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate(); get_tree().root.add_child(app); await frames()
	DisplayServer.window_set_size(Vector2i(1280,720))
	for locale: String in ["zh_CN","en"]:
		Game.profile.settings.language = locale
		Words.set_locale(locale)
		await _camp_pages()
		await _field_pages()
	var report := FileAccess.open(AssetCatalog.resolve("res://artifacts/ui_audit_"+phase+".json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(records,"\t")); report.close()
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free(); await frames()
	print("UI TEXT AUDIT: %d checks, %d failures, %d screens; renderer=%s" % [checks,failures,records.size(),DisplayServer.get_name()])
	get_tree().quit(1 if failures else 0)
