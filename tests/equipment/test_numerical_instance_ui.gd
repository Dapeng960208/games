extends Node
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Game.profile_path.contains("test_numerical_instance_ui"):
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"isolated profile")
	var profile := Game.profile.duplicate(true)
	profile.ruleset_version = 2
	profile.hero_xp.CH01 = 3600
	profile.equipment = {}
	profile.loadout = {}
	# The S10 native profile has starter presets; this replacement fixture
	# must not retain references to the starter instances it just removed.
	profile.loadout_presets = {}
	var weapon_template := ""
	for template: String in ContentRegistry.set_item_ids("S01",2):
		var rolls := {}
		for key: String in Instances.main_keys(template,"physical"): rolls[key] = 50
		var record := Instances.create({"instance_id":"ui-"+template,"template_id":template,"source_event_id":"test:s03-ui", "item_level":20,"rarity":"white","power_type":"physical","main_rolls":rolls,"affix_type_and_quantile":[]})
		check(not record.is_empty(),"construct "+template)
		profile.equipment[record.instance_id] = record
		var slot: String = ContentRegistry.equipment(template,2).slot
		profile.loadout[slot] = record.instance_id
		if slot == "weapon": weapon_template = template
	var stronger: Dictionary = profile.equipment[profile.loadout.weapon].duplicate(true)
	stronger.instance_id = "ui-duplicate-weapon"
	for key: String in stronger.main_rolls: stronger.main_rolls[key] = 100
	profile.equipment[stronger.instance_id] = stronger
	var saved := Game._commit_profile(profile)
	check(saved,"save eight slots and duplicate")
	if not saved:
		print("Numerical instance UI fixture rejected: ", Game.last_error)
		get_tree().quit(1)
		return
	var app: Node = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	await get_tree().process_frame
	app.show_workshop("inventory")
	await get_tree().process_frame
	var panel: Control = app.screen.find_child("Workshop",true,false)
	check(panel != null,"real workshop mounted")
	for slot: String in ContentRegistry.slots(2):
		check(panel.find_child("Slot_"+slot,true,false) != null,"real slot button "+slot)
	check(panel._filtered_equipment().size() == 9,"same-template instances both listed")
	var grid: Node = panel.find_child("EquipmentGrid",true,false)
	check(grid.get_child_count() == 9,"nine distinct item cells")
	var definition := Game.equipment_definition(stronger.instance_id)
	check(definition.id == weapon_template and definition.instance_id == stronger.instance_id,"template artwork identity separate from instance")
	check(Inspect.item_values(definition,0,"CH01").attack == Instances.stats(stronger).attack,"display uses actual instance roll")
	panel.selected_item = stronger.instance_id
	panel._render()
	panel._commit_item()
	await get_tree().process_frame
	check(Game.profile.loadout.weapon == stronger.instance_id,"real inventory action equips selected duplicate")
	check(Game.profile.equipment.size() == 9,"equip does not overwrite duplicate")
	Game.reload_profile()
	check(Game.profile.loadout.weapon == stronger.instance_id and Game.profile.equipment.size() == 9,"reload retains instance selection")
	Game.run = RunSession.new()
	Game.run.hero_id = "CH01"
	Game.run.level = 20
	Game.run.stats = Game.selected_stats()
	Game.run.loadout_snapshot = Game.profile.loadout.duplicate(true)
	Game.run.equipment_snapshot = Game.profile.equipment.duplicate(true)
	var pending := stronger.duplicate(true)
	pending.instance_id = "ui-pending-copy"
	pending.location = "pending"
	Game.run.expedition = {"pending_equipment":{pending.instance_id:pending}}
	check(Game.equipment_definition(pending.instance_id,true).instance_id == pending.instance_id,"unfitted pending instance has UI identity")
	var comparison := preload("res://scripts/gameplay/equipment/backpack_equipment.gd").preview(Game,pending.instance_id,"weapon")
	check(not comparison.is_empty() and comparison.owned[pending.instance_id].main_rolls == pending.main_rolls,"pending preview preserves complete roll record")
	check(Game.profile.equipment.size() == 9,"pending preview never banks or sells item")
	Game.run = null
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("Numerical instance UI: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
