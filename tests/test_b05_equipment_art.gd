extends Node
## Real production workshop at 2560x1440. Candidate activation and Lv25 are
## in-memory fixture injection only; neither release JSON nor real saves change.
const Art = preload("res://scripts/ui/equipment_art.gd")
const Icon = preload("res://scripts/ui/equipment_icon.gd")
const Catalog = preload("res://scripts/core/b05_equipment_catalog.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const Native = preload("res://scripts/core/numerical_profile.gd")
const Creation = preload("res://scripts/ui/instance_acquisition_panel.gd")
var checks := 0
var failures: Array[String] = []
var captures: Array = []
var measurements: Array = []
var candidate: Dictionary
var app: Node
var folder := ""
var shop_only := false
var ui_fixes := false
var percentage_cells := 0
var original_parameters: Dictionary
var original_manifest: Dictionary
func _ready() -> void:
	call_deferred("run_checks")
	get_tree().create_timer(210).timeout.connect(func(): push_error("B05 art capture timed out"); get_tree().quit(1))
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames() -> void:
	for i in 3: await get_tree().process_frame
func art_contract() -> void:
	candidate = JSON.parse_string(FileAccess.get_file_as_string(Art.B05_MANIFEST_PATH))
	check(candidate.enabled == false,"disk art candidate remains disabled pending review")
	original_manifest = Art._read_manifest().duplicate(true)
	check(Art.ids().size() == 96,"disabled candidate preserves historical96 artwork")
	var old := original_manifest.duplicate(true)
	Art.merge_b05_manifest(old,candidate)
	check(old == original_manifest,"disabled addition leaves complete base byte-equivalent")
	var test := candidate.duplicate(true)
	test.enabled = true
	test.items.EQ01 = {"texture":"invalid-overwrite"}
	test.slot_fallbacks = {"legs":{"texture":"invalid-fallback"}}
	Art.merge_b05_manifest(old,test)
	check(old.items.EQ01 == original_manifest.items.EQ01,"legacy ID cannot be replaced by B05 manifest")
	check(old.slot_fallbacks == original_manifest.slot_fallbacks,"all old slot fallbacks preserved")
	var first: Dictionary = old.items["B05-U01"].duplicate(true)
	test.items["B05-U01"].texture = "invalid-repeat"
	Art.merge_b05_manifest(old,test)
	check(old.items["B05-U01"] == first,"repeat merge preserves existing entry")
	var invalid := original_manifest.duplicate(true)
	Art.merge_b05_manifest(invalid,null)
	Art.merge_b05_manifest(invalid,{"enabled":true,"chapter_id":"B06","items":candidate.items})
	Art.merge_b05_manifest(invalid,{"enabled":true,"chapter_id":"B05","items":[]})
	check(invalid == original_manifest,"missing and malformed additions preserve fallback")
	candidate.enabled = true
	Art._manifest = original_manifest.duplicate(true)
	Art.merge_b05_manifest(Art._manifest,candidate)
	check(Art.ids().size() == 131,"fixture adds exactly35 B05 textures to96 legacy textures")
	var expected := Catalog.equipment_ids()
	var actual: Array = candidate.items.keys(); actual.sort()
	check(actual == expected,"manifest exact35 catalog IDs")
	for id: String in expected:
		var entry: Dictionary = candidate.items[id]
		var texture := Art.texture(id)
		check(texture != null and texture == Art.texture(id),id+" real cached texture")
		check(FileAccess.get_sha256(entry.texture) == entry.sha256,id+" native PNG exact hash")
		var source := Image.new()
		check(source.load_png_from_buffer(FileAccess.get_file_as_bytes(entry.texture)) == OK,id+" native PNG decodes")
		check(source.get_size() == Vector2i(entry.region[2],entry.region[3]),id+" region matches native pixels")
		check(entry.runtime_slot == ContentRegistry.equipment(id,2).slot,id+" runtime slot identity")
		check(mini(entry.native_foreground_pixels[0],entry.native_foreground_pixels[1]) >= 377,id+" native effective density")
		if texture != null:
			var sampled: Image = (texture as AtlasTexture).atlas.get_image()
			check(sampled.has_mipmaps(),id+" real sampler creates mip chain")
			check(sampled.get_pixel(0,0).a == 0.0 and sampled.get_pixel(source.get_width()-1,source.get_height()-1).a == 0.0,id+" alpha corners survive sampling")
	for slot: String in ContentRegistry.V2_SLOTS:
		check(Art.slot_texture(slot) != null if original_manifest.slot_fallbacks.has(slot) else Art.fallback_texture(slot) != null,slot+" original slot/empty-frame fallback still available")
	check(Art.texture("B05-UNKNOWN") == null,"unknown B05 does not impersonate an owned item")
func preview_contract() -> void:
	var before: Dictionary = Game.profile.duplicate(true)
	for id: String in Catalog.equipment_ids():
		for power: String in ["physical","magic"]:
			if not Catalog.supports_power(id,power): continue
			for rarity: String in ["white","green","purple","gold"]:
				# Cross-class browsing is legal; the read-only preview selects a
				# valid policy hero without weakening the owned-instance validator.
				var request := {"hero_id":"CH03" if power == "physical" else "CH01","power_type":power,"rarity":rarity,"item_level":25}
				var low := Creation._main_range(id,request,0)
				var high := Creation._main_range(id,request,100)
				var keys := Instances.main_keys(id,power)
				check(low.keys() == keys and high.keys() == keys,id+power+rarity+" preview endpoints include every main stat")
				for key: String in keys:
					check(float(low.get(key,0)) > 0 and float(high.get(key,0)) >= float(low.get(key,0)),id+power+rarity+" nonempty ordered endpoint "+key)
				check(low == Creation._main_range(id,request,0),id+power+rarity+" repeated preview deterministic")
	check(Game.profile == before,"all35 template preview calculations do not mutate inventory/profile")
	check(not Creation._main_range("EQ01",{"hero_id":"CH01","power_type":"physical","rarity":"white","item_level":20},0).is_empty(),"original EQ preview remains available")
func seed_profile(hero: String, set_id: String) -> void:
	var value := Native.fresh(ProfileStore.fresh_profile())
	value.selected_hero = hero
	value.hero_xp = {"CH01":6200,"CH02":6200,"CH03":6200}
	value.permanent_gold = 100000
	value.bosses = ["BO01","BO02","BO03","BO04"]
	value.materials = {"forge":1000,"race:B05":1000,"core:B05":100}
	value.equipment.clear()
	for preset: String in value.loadout_presets:
		for slot: String in ContentRegistry.V2_SLOTS: value.loadout_presets[preset][slot] = ""
	for slot: String in ContentRegistry.V2_SLOTS: value.loadout[slot] = ""
	var count := 0
	for ids: Array in Catalog.natural_pool(hero).values():
		for id: String in ids:
			var record := Acquisition.roll_item({"instance_id":"b05art:"+id,"source_event_id":"b05art:fixture:"+hero,"template_id":id,"rarity":"purple","power_type":"magic" if hero == "CH03" else "physical","hero_id":hero,"item_level":25,"source":"drop","location":"inventory"},100+count)
			check(not record.is_empty() and Instances.validate(record).is_empty(),"legal v3 fixture "+hero+id)
			if record.is_empty(): continue
			value.equipment[record.instance_id] = record
			if id.begins_with(set_id+"-"):
				var slot: String = ContentRegistry.equipment(id,2).slot
				value.loadout[slot] = record.instance_id
				value.loadout_presets[hero][slot] = record.instance_id
			count += 1
	check(count == 19,"strict19 natural inventory "+hero)
	check(Game._commit_profile(value),"isolated Lv25 profile commits "+hero+" "+Game.last_error)
func inspect_icon(owner: Node, node_name: String, id: String, expected_physical: Vector2) -> void:
	var icon: Control = owner.find_child(node_name,true,false)
	check(icon != null,"actual UI icon "+node_name)
	if icon == null: return
	check(icon.generated_texture == Art.texture(id) and icon.equipment_data.id == id,"actual consumer exact B05 art "+id)
	var transform := icon.get_viewport_transform() * icon.get_global_transform()
	var physical := Rect2(transform * Vector2.ZERO, Vector2(transform.x.length()*icon.size.x,transform.y.length()*icon.size.y))
	check(physical.size.is_equal_approx(expected_physical),"actual2K physical size "+node_name+" "+str(physical.size))
	check(Rect2(Vector2.ZERO,Vector2(2560,1440)).encloses(physical),"actual icon inside screen "+node_name)
	measurements.append({"hero":Game.profile.selected_hero,"locale":Words.locale,"node":node_name,"template_id":id,"physical_rect":[physical.position.x,physical.position.y,physical.size.x,physical.size.y]})
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560,1440),"true2K rendered pixels "+label)
	var path := folder.path_join(label+".png")
	check(pixels.save_png(path) == OK,"capture "+label)
	captures.append({"file":path.get_file(),"sha256":FileAccess.get_sha256(path),"width":pixels.get_width(),"height":pixels.get_height()})
func workshop(hero: String, set_id: String, unique_id: String) -> void:
	seed_profile(hero,set_id)
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		var prefix := hero+"-"+locale
		var panel: Control
		if ui_fixes:
			app.show_workshop("inventory"); await frames()
			panel = app.screen.find_child("Workshop",true,false)
			panel.selected_item = "b05art:"+set_id+"-head"
			panel._render(); await frames()
			inspect_icon(panel,"CandidateEquipmentArt",set_id+"-head",Vector2(232,232))
			var hint: Label = panel.find_child("EquipmentActionHint",true,false)
			var primary: Control = panel.find_child("PrimaryAction",true,false)
			check(hint != null and primary != null,prefix+" stable hint/action nodes")
			if hint != null and primary != null:
				check(hint.get_global_rect().end.y < primary.get_global_rect().position.y,prefix+" hint bottom strictly above action")
				check(hint.get_line_count() <= 2 and not hint.tooltip_text.is_empty(),prefix+" readable two-line hint with full tooltip")
			for label: Label in panel.find_children("*","Label",true,false):
				if label.tooltip_text.contains("pp ="):
					percentage_cells += 1
					check(label.text.contains(" pp") and not label.text.contains("百分点"),prefix+" compact percentage-point cell")
			await capture(prefix+"-inventory-detail-fixed")
		if not shop_only:
			app.show_workshop("inventory"); await frames()
			panel = app.screen.find_child("Workshop",true,false)
			panel.selected_item = "b05art:"+set_id+"-head"
			panel._render(); await frames()
			check(panel._filtered_equipment().size() == 19,prefix+" actual inventory19")
			inspect_icon(panel,"CandidateEquipmentArt",set_id+"-head",Vector2(232,232))
			inspect_icon(panel,"CatalogEquipmentArt_"+set_id+"-head",set_id+"-head",Vector2(156,156))
			inspect_icon(panel,"FittedEquipmentArt_head",set_id+"-head",Vector2(96,96))
			await capture(prefix+"-inventory-detail")
			panel.selected_item = "b05art:"+set_id+"-weapon"; panel._render(); await frames()
			var row: Control = panel.find_child("Item_b05art_"+set_id+"-weapon",true,false)
			check(row != null,prefix+" real selectable weapon row")
			if row != null: panel.item_list.ensure_control_visible(row)
			await frames()
			inspect_icon(panel,"CandidateEquipmentArt",set_id+"-weapon",Vector2(232,232))
			await capture(prefix+"-inventory-weapon")
			app.show_workshop("upgrade"); await frames()
			panel = app.screen.find_child("Workshop",true,false)
			panel.selected_item = "b05art:"+set_id+"-weapon"; panel._render(); await frames()
			inspect_icon(panel,"ForgeEquipmentArt",set_id+"-weapon",Vector2(260,260))
			check(panel.action_button != null,prefix+" production forge action remains accessible")
			await capture(prefix+"-forge")
		app.show_workshop("shop"); await frames()
		panel = app.screen.find_child("Workshop",true,false)
		panel.shop_sets = false
		var templates: Array = [set_id+"-weapon"] if shop_only else [set_id+"-weapon",unique_id]
		for template: String in templates:
			panel.selected_item = template; panel.creation_level = 25; panel._render(); await frames()
			inspect_icon(panel,"CreationPreviewArt_"+template,template,Vector2(296,280))
			check(panel.find_child("CreationItemLevel",true,false).value == 25,prefix+" actual Lv25 preview")
			await capture(prefix+"-shop-"+template)
		# Dismissal and re-entry use the production navigation callback.
		panel.find_child("ReturnCamp",true,false).pressed.emit(); await frames()
		check(app.screen.find_child("Workshop",true,false) == null,prefix+" return closes workshop")
func run_checks() -> void:
	ui_fixes = "--b05-art-ui-fixes" in OS.get_cmdline_user_args()
	shop_only = "--b05-art-shop-only" in OS.get_cmdline_user_args() or ui_fixes
	if not Game.profile_path.get_file().begins_with("test_b05_equipment_art"):
		push_error("Refusing B05 art check without isolated test_b05_equipment_art profile"); get_tree().quit(2); return
	folder = ProjectSettings.globalize_path(Game.profile_path).get_base_dir().path_join("b05-art-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	original_parameters = Numbers.parameters().duplicate(true)
	check(int(original_parameters.implemented_chapters) == 4,"production chapter release gate still4")
	art_contract()
	Numbers._parameters.implemented_chapters = 5
	preview_contract()
	Game.run = null
	check(Game.new_profile(),"isolated profile only")
	app = load("res://scenes/main.tscn").instantiate(); add_child(app); await frames()
	await workshop("CH01","B05-SW","B05-U01")
	await workshop("CH02","B05-SG","B05-U02")
	await workshop("CH03","B05-SM","B05-U03")
	if ui_fixes: check(percentage_cells > 0,"actual fixed inventory pages exercise percentage-point cells")
	app.set_process(false)
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free(); await frames()
	Numbers._parameters = original_parameters
	Art._manifest = original_manifest
	for id: String in Art._textures.keys():
		if id.begins_with("B05-"): Art._textures.erase(id)
	check(JSON.parse_string(FileAccess.get_file_as_string(Art.B05_MANIFEST_PATH)).enabled == false,"disk candidate still disabled after all UI actions")
	var report := {"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"captures":captures,"measurements":measurements,"candidate_gate":"pending human pixel review","shop_only":shop_only,"ui_fixes":ui_fixes,"profile_path":Game.profile_path,"production_chapter":Numbers.value("implemented_chapters")}
	var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("B05 EQUIPMENT ART: ",checks," checks; failures=",failures,"; captures=",captures.size(),"; renderer=",DisplayServer.get_name())
	get_tree().quit(0 if failures.is_empty() else 1)
