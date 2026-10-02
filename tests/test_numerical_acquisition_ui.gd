extends Node
const Fixtures = preload("res://tests/test_numerical_instance_storage.gd")
const Art = preload("res://scripts/ui/equipment_art.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(90).timeout.connect(func(): print("Acquisition UI timed out"); get_tree().quit(1))

func frames() -> void:
	for index in 3: await get_tree().process_frame

func check_art(parent: Node, node_name: String, template: String) -> void:
	var icon: Control = parent.find_child(node_name,true,false)
	var definition := ContentRegistry.equipment(template,2)
	var expected := Art.texture(template)
	if expected == null: expected = Art.slot_texture(str(definition.slot))
	check(icon != null and expected != null and not icon.is_empty and icon.equipment_data.id == template and icon.generated_texture == expected,"real template/slot artwork: "+node_name)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(Game.profile_path).get_base_dir().path_join("shop-icon-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png")) == OK,"capture "+label)

func artwork_ui(app: Node) -> void:
	var profile: Dictionary = Game.profile.duplicate(true)
	for template: String in ContentRegistry.set_item_ids("S06",2):
		var item := ContentRegistry.equipment(template,2)
		if item.slot in ["legs","ring"]:
			profile.loadout[item.slot] = ""
			continue
		var record := Fixtures.fixture_instance("old-six-"+template,template)
		profile.equipment[record.instance_id] = record
		profile.loadout[item.slot] = record.instance_id
	check(Game._commit_profile(profile),"six-piece permanent inventory fixture")
	app.show_workshop("shop")
	await frames()
	var panel: Control = app.screen.find_child("Workshop",true,false)
	panel.creation_power_type = "physical"
	panel.shop_sets = true
	for set_id: String in ContentRegistry.sets(2):
		panel.selected_set = set_id
		panel._render()
		await frames()
		var ids := ContentRegistry.set_item_ids(set_id,2)
		check(panel.find_children("CreationPreviewArt_*","Control",true,false).size() == 8,"all eight pieces previewed: "+set_id)
		check_art(panel,"CreationChoiceArt_"+set_id,ids[0])
		for template: String in ids: check_art(panel,"CreationPreviewArt_"+template,template)
	panel.shop_sets = false
	panel._render()
	await frames()
	for template: String in ContentRegistry.equipment_ids(2): check_art(panel,"CreationChoiceArt_"+template,template)
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1920,1080)]:
			get_window().size = extent
			panel.shop_sets = true
			panel.selected_set = "S06"
			panel._render()
			await frames()
			var choices: Array[Node] = panel.find_children("CreationInclude_*","CheckBox",true,false)
			check(choices.size() == 2,"six-piece profile offers legs/ring only: "+locale+str(extent))
			var scroll: Control = panel.find_child("CreationDescription",true,false)
			for choice: Control in choices:
				var template := str(choice.name).trim_prefix("CreationInclude_")
				check(ContentRegistry.equipment(template,2).slot in ["legs","ring"],"missing piece is a new slot")
				check_art(choice,"CreationMissingArt_"+template,template)
				check(scroll.get_global_rect().encloses(choice.get_global_rect()),"both missing-piece cards visible: "+locale+str(extent)+" "+str(scroll.get_global_rect())+" / "+str(choice.get_global_rect()))
			check(not scroll.get_global_rect().intersects(panel.action_button.get_global_rect()),"art/cards avoid purchase action in separate preview/order columns")
			await capture("partial-set-"+locale+"-"+str(extent.x)+"x"+str(extent.y))
		get_window().size = Vector2i(1280,720)
		panel.selected_set = "S09"
		panel._render()
		await frames()
		await capture("full-set-"+locale)
		panel.shop_sets = false
		panel.selected_item = "EQ108"
		panel._render()
		await frames()
		check_art(panel,"CreationPreviewArt_EQ108","EQ108")
		await capture("single-ring-"+locale)
		panel._switch_page("craft")
		panel.selected_item = "EQ107"
		panel._render()
		await frames()
		check_art(panel,"CreationPreviewArt_EQ107","EQ107")
		await capture("craft-legs-"+locale)
		panel._switch_page("shop")
	Words.set_locale("zh_CN")
	panel.shop_sets = true
	panel.selected_set = "S06"
	panel.creation_power_type = "physical"
	panel.creation_rarity = "white"
	panel._render()
	check(panel.find_child("CreationEligibility",true,false).text.contains("所有职业"),"universal item badge reflects real three-class eligibility")
	panel.shop_sets = true
	panel.selected_set = "S01"
	panel.creation_power_type = "physical"
	panel._render()
	check(panel.action_button.disabled and panel.find_child("CreationEligibility",true,false).text.contains("法师"),"mage-exclusive set rejects physical creation with exact badge")
	panel.creation_power_type = "magic"
	panel._render()
	check(not panel.action_button.disabled,"current warrior can buy valid mage gear without auto-equipping")
	panel.selected_set = "S02"
	panel.creation_power_type = "physical"
	panel._render()
	check(not panel.action_button.disabled and panel.find_child("CreationEligibility",true,false).text.contains("所有职业"),"B01 universal set is available to all classes")
	panel.shop_sets = true
	panel.selected_set = "S06"
	panel._render()
	var count: int = Game.profile.equipment.size()
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	check(Game.profile.equipment.size() == count+2,"actual partial-set purchase adds exactly legs and ring")
	Game.reload_profile()
	panel._render()
	check(panel.find_children("CreationInclude_*","CheckBox",true,false).is_empty(),"both new slots survive reload; no pieces still missing")
	panel.action_button.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	Game.reload_profile()
	for slot: String in ["legs","ring"]:
		check(Game.profile.loadout.has(slot),"reload retains eight-slot profile: "+slot+" "+Game.last_error+" "+Game.storage_warning)
		if not Game.profile.loadout.has(slot): return
		var id := str(Game.profile.loadout[slot])
		check(not id.is_empty() and Game.profile.equipment.has(id) and ContentRegistry.equipment(Game.profile.equipment[id].template_id,2).slot == slot,"new slot equips and survives reload: "+slot)
	app.show_workshop("inventory")
	await frames()
	panel = app.screen.find_child("Workshop",true,false)
	for slot: String in ["legs","ring"]: check_art(panel,"FittedEquipmentArt_"+slot,str(Game.profile.equipment[Game.profile.loadout[slot]].template_id))
	await capture("equipped-eight-slots")
func _run() -> void:
	if not Game.profile_path.contains("test_numerical_acquisition_ui"):
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"isolated profile")
	var value: Dictionary = preload("res://scripts/core/numerical_profile.gd").fresh(ProfileStore.fresh_profile())
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
	await artwork_ui(app)
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("Numerical acquisition UI: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
