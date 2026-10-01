extends Node
const Fixtures = preload("res://tests/test_numerical_instance_storage.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	if not Game.profile_path.contains("test_numerical_acquisition_ui"):
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"isolated profile")
	var value: Dictionary = Fixtures.fixture_profile()
	value.hero_xp.CH01 = 3600
	value.permanent_gold = 100000
	value.bosses = ["BO01","BO02","BO03","BO04"]
	value.materials = {"forge":1000,"race:B01":1000,"race:B02":1000,"race:B03":1000,"race:B04":1000,"core:B01":100,"core:B02":100,"core:B03":100,"core:B04":100}
	check(Game._commit_profile(value),"V2 fixture")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	app.show_workshop("shop")
	await get_tree().process_frame
	var panel: Control = app.screen.find_child("Workshop",true,false)
	check(panel != null,"actual workshop")
	check(not app.screen.find_child("StorageCapacityHint",true,false).text.contains("4095"),"V2 capacity never shows legacy transaction count cap")
	panel.shop_sets = false
	panel.selected_item = "EQ01"
	panel._render()
	check(panel.find_child("CreationRarity",true,false).item_count == 2,"shop white/green choices")
	check(panel.find_child("CreationPowerType",true,false).item_count == 2,"both selectable types")
	check(panel.find_child("CreationItemLevel",true,false).max_value == 20,"hero-level ceiling")
	var count: int = Game.profile.equipment.size()
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	check(Game.profile.equipment.size() == count+1,"actual purchase button independent record")
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	check(Game.profile.equipment.size() == count+2,"repeat purchase retains duplicate")
	var before: Dictionary = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	var nonce: String = panel.creation_transaction_id
	check(Game.profile == before and not nonce.is_empty(),"failed save no debit and preserves transaction")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	check(Game.profile.equipment.size() == count+3 and panel.creation_transaction_id.is_empty(),"retry commits exactly once")
	panel._switch_page("craft")
	check(panel.find_child("CreationRarity",true,false).item_count == 3,"craft three rarities")
	panel.creation_rarity = "gold"
	panel.creation_power_type = "magic"
	panel._render()
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	check(Game.profile.equipment.size() == count+4,"gold crafting from actual button")
	var found := false
	for record: Dictionary in Game.profile.equipment.values():
		if record.rarity == "gold" and record.power_type == "magic" and record.enhancement_rank == 0: found = true
	check(found,"craft selected type starts at zero")
	Game.reload_profile()
	check(Game.profile.equipment.size() == count+4,"purchases/craft survive reload")
	panel._switch_page("shop")
	panel.shop_sets = true
	panel.selected_set = "S02"
	panel.creation_power_type = "physical"
	panel.creation_rarity = "white"
	panel._render()
	var includes: Array[Node] = panel.find_children("CreationInclude_*","CheckBox",true,false)
	check(includes.size() == 8,"eight-slot missing selection")
	var omit: CheckBox = includes[0]
	omit.toggled.emit(false)
	check(panel.creation_omitted.size() == 1,"explicit selected subset excludes a piece")
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	check(Game.profile.equipment.size() == count+11,"batch buys exactly selected seven")
	check(panel.find_children("CreationInclude_*","CheckBox",true,false).size() == 1,"remaining missing piece stays selectable")
	app.show_camp()
	app._start_run()
	check(Game.run == null and app.find_child("DepartureWishDialog",true,false) != null,"wish dialog before departure")
	var wish: OptionButton = app.find_child("DepartureWishSlot",true,false)
	check(wish.item_count == 9,"none plus eight wish slots")
	wish.item_selected.emit(8)
	app.find_child("CancelWishDeparture",true,false).pressed.emit()
	check(Game.run == null and app.modals.is_empty(),"cancel starts no run and dismisses dialog")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("Numerical acquisition UI: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
