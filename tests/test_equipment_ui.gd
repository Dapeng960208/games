extends SceneTree
## Focused read-only inspection and production screen checks with isolated saves.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
var app: Node
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()
	create_timer(100).timeout.connect(func(): push_error("Equipment UI timeout"); quit(1))

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("EQUIPMENT UI: "+detail)

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func panel() -> Control:
	return app.screen.find_child("Workshop",true,false)

func click(id: String) -> void:
	var target := panel().find_child(id,true,false) as Button
	check(target != null and not target.disabled,"enabled control "+id)
	if target != null and not target.disabled: target.pressed.emit()
	await frames()

func _models() -> void:
	var owned: Dictionary = game.profile.equipment.duplicate(true)
	for id: String in owned: owned[id].level = 3
	for hero: String in ["CH01","CH02","CH03"]:
		var report := Inspect.breakdown(hero,9,game.profile.loadout,owned)
		check(report.total == Resolver.resolve(hero,9,game.profile.loadout,owned),hero+" totals are the production resolver")
		check(float(report.leveled.attack) > float(report.intrinsic.attack) and float(report.total.max_hp) > float(report.leveled.max_hp),hero+" level growth and equipped bonuses remain distinct")
	var item: Dictionary = ContentRegistry.equipment("EQ01")
	check(is_equal_approx(float(Inspect.item_values(item,3,"CH01").attack),5.2),"refinement preserves production fractional attack at +3")
	var base: Dictionary = Inspect.item_values(item,0,"CH01")
	var improved: Dictionary = Inspect.item_values(item,1,"CH01")
	check(is_equal_approx(float(improved.attack)-float(base.attack),0.4) and is_equal_approx(float(improved.armor_penetration)-float(base.armor_penetration),0.3),"first refinement exposes actual +0.4 attack and +0.3 penetration")
	check(Inspect.value("attack",float(improved.attack)-float(base.attack),true) == "+0.4" and Inspect.value("armor_penetration",float(improved.armor_penetration)-float(base.armor_penetration),true) == "+0.3","small paid gains remain visible in the shared formatter")
	check(Inspect.value("move_speed",.035,false,true) == "3.5%" and Inspect.value("move_speed",240) == "240.0","item speed ratios and character speed units differ")
	check(not Inspect.item_values(ContentRegistry.equipment("EQ61"),0,"CH01").has("damage_reduction_bonus"),"shield-dependent reduction is not a permanent item stat")
	owned["EQ61"] = {"level":3}
	var ownership_before := owned.duplicate(true)
	var preview := Inspect.set_preview("S09","CH01",9,game.profile.loadout,owned)
	check(preview.sets.S09 == 6 and preview.loadout.weapon == "EQ61","set preview resolves the real complete six-slot loadout")
	check(owned == ownership_before,"set preview never mutates ownership or refinement")

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/equipment_ui_"+id+".png") == OK,"rendered evidence "+id)

func _prepare_hero_presets() -> void:
	check(game.start_run() and game.add_gold(3000),"earn isolated equipment-preview fixture gold")
	check(not game.finish_run("extracted").is_empty(),"settle preview fixture gold")
	# The catalog fixture already bought S09 and refined its EQ61 weapon.
	check(game.equipment_level("EQ61") == 3 and game.equip_item("EQ61"),"warrior remembers the existing refined weapon without buying it twice")
	check(game.select_hero("CH03") and game.equip_item("EQ01") and game.upgrade_equipment("EQ01","preview-small-refine"),"mage remembers independently refined starter weapon")
	check(game.select_hero("CH01") and game.profile.loadout.weapon == "EQ61" and game.hero_loadout("CH03").weapon == "EQ01","active and preview loadouts differ before opening UI")

func _screens() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	var before: Dictionary = game.profile.duplicate(true)
	var saved := FileAccess.get_file_as_bytes(game.profile_path)
	app.show_workshop("heroes")
	await frames()
	check(panel().find_children("HeroAttribute_*","Label",true,false).size() == 25,"hero dossier exposes all 25 resolved properties")
	await click("Preview_CH03")
	var sheet := panel().find_child("CharacterStatSheet",true,false)
	var actual: Dictionary = sheet.get_meta("breakdown")
	check(actual.hero_id == "CH03" and game.profile == before,"other hero preview uses that hero without changing the active hero")
	check(actual.loadout == game.hero_loadout("CH03") and actual.loadout.weapon == "EQ01" and game.profile.loadout.weapon == "EQ61","production hero screen binds the preview hero preset rather than active gear")
	check(actual.total == Resolver.resolve("CH03",game.hero_level("CH03"),game.hero_loadout("CH03"),game.profile.equipment),"preview sheet totals exactly match the selected hero preset resolver")
	var unrefined: Dictionary = game.profile.equipment.duplicate(true)
	unrefined.EQ01.level = 0
	var old: Dictionary = Resolver.resolve("CH03",game.hero_level("CH03"),game.hero_loadout("CH03"),unrefined)
	check(is_equal_approx(float(actual.total.attack)-float(old.attack),0.4) and is_equal_approx(float(actual.total.armor_penetration)-float(old.armor_penetration),0.3),"actual hero sheet includes the first-refinement fractional gains")
	check(sheet.find_child("HeroAttribute_attack",true,false).text == Inspect.value("attack",actual.total.attack) and sheet.find_child("HeroAttribute_armor_penetration",true,false).text == Inspect.value("armor_penetration",actual.total.armor_penetration),"rendered total labels retain fractional attack and penetration")
	check(FileAccess.get_file_as_bytes(game.profile_path) == saved,"inspection never writes the profile")
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(extent)
			app.show_workshop("heroes")
			await frames()
			check(panel().find_child("HeroStatScroll",true,false).get_global_rect().end.x <= root.get_visible_rect().end.x+1,"attribute sheet fits "+locale+str(extent))
			await capture("hero_"+locale+"_%dx%d" % [extent.x,extent.y])
	app.show_workshop("inventory")
	await frames()
	await click("OpenCharacterStats")
	var modal: Node = app.modals[-1].node
	check(modal.find_children("HeroAttribute_*","Label",true,false).size() == 25,"inventory opens the same complete stat sheet")
	app._pop_modal()
	await frames()
	await _catalogue()
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(extent)
			app.show_workshop("inventory")
			await frames()
			panel().selected_item = "EQ61"; panel()._render()
			await frames()
			check(panel().find_child("EquipmentDetails",true,false).get_global_rect().size.y >= 270,"full numbers have a readable detail area "+locale+str(extent))
			check(root.get_visible_rect().encloses(panel().action_button.get_global_rect()),"inventory action fits "+locale+str(extent))
			await capture("inventory_"+locale+"_%dx%d" % [extent.x,extent.y])
			panel().selected_item = "EQ08"; panel()._render(); await frames()
			await click("EquipmentDetailTab_compare")
			await capture("compare_"+locale+"_%dx%d" % [extent.x,extent.y])
			app.show_workshop("shop")
			await frames()
			panel().selected_set = "S11"; panel()._render(); await frames()
			await click("SetDetailTab_compare")
			await capture("set_"+locale+"_%dx%d" % [extent.x,extent.y])
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free()
	app = null
	await frames()

func _catalogue() -> void:
	Words.set_locale("zh_CN")
	app.show_workshop("shop")
	await frames()
	await click("Set_S09")
	await click("PrimaryAction")
	await create_timer(.35).timeout
	check(game.profile.loadout.weapon == "EQ61" and game.equipment_level("EQ61") == 3,"real set equip preserves the refined weapon")
	var wallet: int = game.profile.permanent_gold
	await click("Set_S10")
	await click("PrimaryAction")
	await create_timer(.35).timeout
	check(game.profile.equipment.has("EQ67") and game.profile.permanent_gold == wallet-810 and game.profile.loadout.weapon == "EQ61","bundle purchase adds missing gear without silently equipping it")
	await click("SetPiece_EQ67")
	check(panel().selected_item == "EQ67" and panel().find_child("ItemStat_attack_speed",true,false) != null,"set piece opens complete real item numbers")
	app.show_workshop("inventory")
	await frames()
	check(panel().slot_filter == "all" and not panel().available_only and panel().find_children("Item_*","Button",true,false).size() == game.profile.equipment.size(),"inventory initially shows all owned gear without hidden class narrowing")
	var search := panel().find_child("EquipmentSearch",true,false) as LineEdit
	search.text = "晨曦"
	search.text_changed.emit("晨曦")
	await frames()
	check(panel().find_children("Item_*","Button",true,false).size() == 6 and root.gui_get_focus_owner() == panel().find_child("EquipmentSearch",true,false),"search filters six matching items and retains typing focus")
	var filter := panel().find_child("EquipmentSlotFilter",true,false) as OptionButton
	filter.item_selected.emit(1)
	await frames()
	check(panel().slot_filter == "weapon" and panel().find_children("Item_*","Button",true,false).size() == 1,"dropdown filters a searched set to its actual weapon")
	await click("Item_EQ61")
	var stat := panel().find_child("ItemStat_attack",true,false)
	check(stat != null and stat.get_meta("values").actual == Inspect.item_values(ContentRegistry.equipment("EQ61"),3,"CH01").attack,"detail uses actual +3 item contribution")
	await click("ViewAllEquipment")
	check(panel().search_query.is_empty() and panel().slot_filter == "all" and panel().find_children("Item_*","Button",true,false).size() == game.profile.equipment.size(),"clear filters restores exactly owned inventory")
	var sort := panel().find_child("EquipmentSort",true,false) as OptionButton
	sort.item_selected.emit(3)
	await frames()
	check(panel()._filtered_equipment()[0] == "EQ61","refinement sorting puts the +3 item first")
	await click("Item_EQ08")
	await click("EquipmentDetailTab_compare")
	check(panel().find_child("SetEffect_S09_6",true,false).get_meta("state") == "将失去","comparison clearly warns about losing an active six-piece effect")
	var comparison := panel().find_child("CompareStat_attack",true,false)
	check(comparison != null and comparison.get_meta("values").preview == game.preview_stats("EQ08").attack,"comparison numbers match the real replacement preview")
	app.show_workshop("upgrade")
	await frames()
	panel().selected_item = "EQ08"; panel().detail_tab = "compare"; panel()._render()
	await frames()
	var advice := panel().find_child("EquipmentAdvice",true,false)
	check(advice.get_meta("before") == game.preview_stats("EQ08") and advice.get_meta("after") == game.preview_upgrade_stats("EQ08"),"unfitted refinement comparison measures only its adjacent levels")

func _run() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_equipment_ui"): quit(2); return
	check(game.new_profile(),"isolated profile")
	check(game.start_run() and game.add_gold(8000),"earn UI fixture currency through real settlement")
	game.finish_run("extracted")
	check(game.buy_equipment_set("S09") and game.buy_equipment("EQ08"),"owned items use real purchase receipts")
	for step: int in 3: check(game.upgrade_equipment("EQ61"),"refine fixture through actual price and rounding")
	_models()
	_prepare_hero_presets()
	await _screens()
	print("EQUIPMENT UI: %d checks, %d failures; renderer=%s" % [checks,failures,DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
