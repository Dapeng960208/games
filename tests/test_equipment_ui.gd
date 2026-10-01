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
	check(Inspect.item_values(item,3,"CH01").attack == 5.0,"refinement shows per-item rounded actual attack, not +0 base")
	check(Inspect.value("move_speed",.035,false,true) == "3.5%" and Inspect.value("move_speed",240) == "240.0","item speed ratios and character speed units differ")
	check(not Inspect.item_values(ContentRegistry.equipment("EQ61"),0,"CH01").has("damage_reduction_bonus"),"shield-dependent reduction is not a permanent item stat")
	owned["EQ61"] = {"level":3}
	var preview := Inspect.set_preview("S09","CH01",9,game.profile.loadout,owned)
	check(preview.sets.S09 == 6 and preview.loadout.weapon == "EQ61","set preview resolves the real complete six-slot loadout")
	check(owned.EQ61.level == 3 and not owned.has("EQ62"),"set preview never mutates ownership or refinement")

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/equipment_ui_"+id+".png") == OK,"rendered evidence "+id)

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
	check(sheet.get_meta("breakdown").hero_id == "CH03" and game.profile == before,"other hero preview uses that hero without changing the active hero")
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
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()

func _run() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_equipment_ui"): quit(2); return
	check(game.new_profile(),"isolated profile")
	_models()
	await _screens()
	print("EQUIPMENT UI: %d checks, %d failures; renderer=%s" % [checks,failures,DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
