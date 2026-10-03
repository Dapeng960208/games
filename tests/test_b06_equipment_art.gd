extends Node
## Actual production codex and workshop; only isolated B06 candidate mode.
const Art = preload("res://scripts/ui/equipment_art.gd")
const Catalog = preload("res://scripts/core/b06_equipment_catalog.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Rules = preload("res://config/numerical_rules.gd")
var checks := 0
var failures := 0
var app: Node
var output := ""
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("B06 ART: "+label)
func _ready() -> void: run.call_deferred()
func frames() -> void:
	for frame in 3: await get_tree().process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440),"native2K viewport")
	check(image.save_png(output.path_join(label+".png"))==OK,"capture "+label)
func run() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b06_equipment_art"):
		get_tree().quit(2); return
	if not Rules.b06_candidate_enabled():
		for id: String in Catalog.equipment_ids(): check(Art.source_path(id).is_empty(),id+" hidden without candidate flag")
		check(int(Rules.value("implemented_chapters"))==4,"production remains four chapters")
		print("B06 art normal-mode isolation: %d checks, %d failures"%[checks,failures])
		get_tree().quit(0 if failures==0 else 1); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Art.B06_MANIFEST_PATH))
	check(not manifest.enabled and not manifest.runtime_quality_gate_passed,"formal art gates remain false")
	var ids: Array=manifest.items.keys(); ids.sort()
	check(ids==Catalog.equipment_ids(),"exact35 catalog mapping")
	var original: Dictionary=Art._read_manifest().duplicate(true)
	var forged: Dictionary=manifest.duplicate(true)
	forged.items.EQ01={"texture":"bad"}
	Art.merge_b06_candidate(original,forged)
	check(original.items.EQ01==Art._read_manifest().items.EQ01,"historical artwork not overwritten")
	for id: String in ids:
		var entry: Dictionary=manifest.items[id]
		var texture:=Art.texture(id)
		check(texture is AtlasTexture,id+" registered actual texture")
		check(FileAccess.get_sha256(entry.texture)==entry.sha256,id+" exact native hash")
		check(Art.region(id)==Rect2(0,0,1254,1254),id+" native canvas retained")
		check(entry.runtime_slot==ContentRegistry.equipment(id,2).slot,id+" exact runtime slot")
		check(texture.atlas.get_size()==Vector2(1254,1254),id+" native source dimensions")
		check(texture.atlas.get_image().has_mipmaps(),id+" sampler mip chain")
	check(Art.texture("B06-UNKNOWN")==null,"unknown does not impersonate owned gear")
	Game.run=null
	check(Game.new_profile(),"isolated fresh profile")
	app=load("res://scenes/main.tscn").instantiate(); add_child(app); await frames()
	for pair: Array in [["CH01","B06-SW"],["CH02","B06-SG"],["CH03","B06-SM"]]:
		var hero: String=pair[0]; var set_id: String=pair[1]
		var value: Dictionary=Game.profile.duplicate(true)
		value.selected_hero=hero
		value.hero_xp[hero]=preload("res://scripts/core/hero_progression.gd").thresholds()[29]
		value.bosses=["BO01","BO02","BO03","BO04","BO05"]
		value.equipment.clear()
		for preset: String in value.loadout_presets:
			for slot: String in ContentRegistry.V2_SLOTS: value.loadout_presets[preset][slot]=""
		for slot: String in ContentRegistry.V2_SLOTS: value.loadout[slot]=""
		var n:=0
		for pool: Array in Catalog.natural_pool(hero).values():
			for id: String in pool:
				var record:=Acquisition.roll_item({"instance_id":"b06art:"+id,"source_event_id":"b06art:fixture:"+hero,"template_id":id,"rarity":"purple","power_type":"magic" if hero=="CH03" else "physical","hero_id":hero,"item_level":30,"source":"drop","location":"inventory"},100+n)
				check(not record.is_empty() and Instances.validate(record).is_empty(),id+" generator-v4 fixture")
				if record.is_empty(): continue
				value.equipment[record.instance_id]=record
				if id.begins_with(set_id+"-"):
					var slot: String=ContentRegistry.equipment(id,2).slot
					value.loadout[slot]=record.instance_id; value.loadout_presets[hero][slot]=record.instance_id
				n+=1
		check(Game._commit_profile(value),"isolated inventory commit "+Game.last_error)
		app.show_workshop("inventory"); await frames()
		var panel: Control=app.screen.find_child("Workshop",true,false)
		for suffix: String in ["head","weapon"]:
			var id:=set_id+"-"+suffix
			panel.selected_item="b06art:"+id; panel._render(); await frames()
			var icon: Control=panel.find_child("CandidateEquipmentArt",true,false)
			check(icon!=null and icon.generated_texture==Art.texture(id),id+" real workshop consumer")
			if icon!=null: check(get_viewport().get_visible_rect().encloses(icon.get_global_rect()),id+" icon inside viewport")
			await capture(hero+"-"+suffix+"-workshop")
		panel.find_child("ReturnCamp",true,false).pressed.emit(); await frames()
		check(app.screen.find_child("Workshop",true,false)==null,"return closes workshop")
	app.show_codex(); await frames()
	var codex: Control=app.screen.find_child("MonsterCodex",true,false)
	codex._set_biome("B06")
	for id: String in ["B06-M10","B06-M14","B06-M18"]:
		codex._show_entry(id); await frames()
		check(codex.selected_id==id,id+" real codex selection")
		await capture(id+"-codex")
	app.show_camp(); await frames()
	check(app.screen.find_child("MonsterCodex",true,false)==null,"codex closes")
	app.set_process(false)
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free()
	check(not JSON.parse_string(FileAccess.get_file_as_string(Art.B06_MANIFEST_PATH)).enabled,"disk gate unchanged")
	print("B06 equipment/codex art: %d checks, %d failures; renderer=%s"%[checks,failures,DisplayServer.get_name()])
	get_tree().quit(0 if failures==0 else 1)
