extends Node
## Inventory rendering and hot-path observations use process-local profiles.
const Fixtures = preload("res://tests/persistence/test_numerical_instance_storage.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
var app: Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAILED ",label)
func _ready() -> void:
	call_deferred("_run")
func frames() -> void:
	for index in 3: await get_tree().process_frame
func _run() -> void:
	if not Game.profile_path.contains("test_inventory_performance"): get_tree().quit(2); return
	Game.new_profile()
	var reference := "res://tools/godot/player-reference/test_player_reference.json"
	var profile := Fixtures.fixture_profile()
	if FileAccess.file_exists(AssetCatalog.resolve(reference)): profile = (JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(reference))) as Dictionary).profile
	check(Game._commit_profile(profile),"isolated reference profile validates")
	print("INVENTORY equipped snapshot Lv",Game.hero_level()," items=",Game.profile.equipment.size())
	var versions := Rules.versions()
	versions.equipment_instance = 999
	check(Rules.versions().equipment_instance != 999,"version API remains detached")
	var begin := Time.get_ticks_usec()
	for index in 1000: Rules.versions()
	print("INVENTORY versions 1000 ms=",(Time.get_ticks_usec()-begin)/1000.0)
	begin = Time.get_ticks_usec()
	for index in 10: Game.selected_stats()
	print("INVENTORY resolve 10 ms=",(Time.get_ticks_usec()-begin)/1000.0)
	var store := ProfileStore.new(Game.profile_path+".benchmark")
	for cycle in 4:
		begin = Time.get_ticks_usec()
		check(store.save_document(Game.profile),"whole reference profile save "+str(cycle))
		print("INVENTORY reference save ",cycle," ms=",(Time.get_ticks_usec()-begin)/1000.0)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	await frames()
	for cycle in 3:
		begin = Time.get_ticks_usec()
		app.show_workshop("inventory")
		print("INVENTORY open ",cycle," build_ms=",(Time.get_ticks_usec()-begin)/1000.0)
		await frames()
		var panel: Control = app.screen.find_child("Workshop",true,false)
		check(panel.find_child("EquipmentGrid",true,false) != null,"actual camp inventory grid")
		begin = Time.get_ticks_usec()
		panel._filtered_equipment()
		print("INVENTORY filter ms=",(Time.get_ticks_usec()-begin)/1000.0)
		begin = Time.get_ticks_usec()
		panel._suggested_equipment()
		print("INVENTORY suggestion ms=",(Time.get_ticks_usec()-begin)/1000.0)
	await _rarities()
	app.queue_free()
	await frames()
	print("INVENTORY checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func _rarities() -> void:
	var profile := Fixtures.fixture_profile()
	profile.hero_xp.CH01 = 3600
	for rarity: String in ["white","green","purple","gold"]:
		var record := Fixtures.fixture_instance("quality:"+rarity,"EQ08",50,"physical",13)
		var affixes: Array = []
		var legal := Instances.legal_affixes("EQ08","physical")
		for index in int(Rules.value("rarities")[rarity].affix_count): affixes.append({"type":legal[index],"u":50})
		record.rarity = rarity
		record.affix_type_and_quantile = affixes
		profile.equipment[record.instance_id] = record
	check(Game._commit_profile(profile),"four rarity same-template fixture")
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		app.show_workshop("inventory")
		await frames()
		var panel: Control = app.screen.find_child("Workshop",true,false)
		for rarity: String in ["white","green","purple","gold"]:
			var cell: Button = panel.find_child("Item_quality_"+rarity,true,false)
			check(cell != null,"same template distinct "+rarity)
			if cell == null: continue
			var badge: Label = cell.find_child("EquipmentRarity",true,false)
			check(badge != null and badge.text.contains(preload("res://scripts/presentation/equipment/equipment_inspection.gd").rarity_name(rarity)),"visible localized rarity "+rarity)
			check(cell.get_meta("rarity","") == rarity,"exact instance rarity "+rarity)
			var icon: Control = cell.find_child("CatalogEquipmentArt_EQ08",true,false)
			check(icon != null and icon.rarity_frame != null,"visible rarity frame "+rarity)
		panel.selected_item = "quality:purple"
		panel._render()
		await frames()
		check(panel.find_child("CandidateRarity",true,false) != null,"detail header rarity")
		check(Game.equip_item("quality:gold"),"equip exact gold instance")
		panel._render()
		check(panel._definition("quality:gold").instance_record.location == "equipped" and panel._definition("quality:purple").instance_record.location == "inventory","render cache refreshes committed instance locations")
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path(Game.profile_path).get_base_dir()
		get_viewport().get_texture().get_image().save_png(directory.path_join("inventory-quality-"+locale+".png"))
