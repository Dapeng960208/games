extends Node
## Verifies the complete regenerated catalogue and the real workshop consumers.
## Run with tools/test.ps1 -Suite equipment_art -SkipRestart; -Graphical adds
## native inventory/shop/upgrade screenshots. Profiles remain isolated.

const Art = preload("res://scripts/ui/equipment_art.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Icon = preload("res://scripts/ui/equipment_icon.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
var app: Node
var checks := 0
var failures := 0
var deadline: Timer
var source_images: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	deadline = Timer.new()
	deadline.one_shot = true
	deadline.wait_time = 90.0
	deadline.timeout.connect(func(): push_error("Equipment art acceptance timed out"); get_tree().quit(1))
	add_child(deadline)
	deadline.start()
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EQUIPMENT ART: " + description)

func frames(count: int = 3) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _source(path: String) -> Image:
	if not source_images.has(path):
		var original := Image.new()
		if original.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK: return null
		source_images[path] = original
	return source_images[path] as Image

func _pixels_preserved(id: String, texture: AtlasTexture, raw: Image) -> void:
	var sampled := texture.atlas.get_image()
	check(sampled != null and not sampled.is_empty(), id + ": imported source exposes image pixels")
	if sampled == null or sampled.is_empty(): return
	check(sampled.get_size() == raw.get_size(), id + ": sampling preserves source dimensions")
	if sampled.get_size() != raw.get_size(): return
	var bounds := texture.region
	var transparent := false
	var visible := false
	var colors: Dictionary = {}
	var unchanged_alpha := true
	# A regular grid detects a blank/misassigned cell and opaque-background
	# regressions without depending on one particular illustration silhouette.
	for row in 24:
		for column in 24:
			var point := Vector2i(bounds.position + bounds.size * Vector2((float(column) + 0.5) / 24.0, (float(row) + 0.5) / 24.0))
			point.x = clampi(point.x, 0, raw.get_width() - 1)
			point.y = clampi(point.y, 0, raw.get_height() - 1)
			var pixel := raw.get_pixelv(point)
			var rendered_pixel := sampled.get_pixelv(point)
			unchanged_alpha = unchanged_alpha and absf(pixel.a - rendered_pixel.a) <= 0.00001
			transparent = transparent or pixel.a <= 0.01
			if pixel.a >= 0.5:
				visible = true
				colors[Vector3i(int(pixel.r * 15), int(pixel.g * 15), int(pixel.b * 15))] = true
	check(transparent and visible, id + ": illustration contains both visible artwork and transparent space")
	check(colors.size() >= 5, id + ": illustration retains colored material/shading detail")
	check(unchanged_alpha, id + ": the runtime sampler preserves the source alpha channel")

func _catalogue() -> bool:
	check(FileAccess.file_exists(Art.MANIFEST_PATH), "activated catalogue manifest exists")
	if not FileAccess.file_exists(Art.MANIFEST_PATH): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Art.MANIFEST_PATH))
	check(parsed is Dictionary and bool(parsed.get("enabled", false)) and parsed.get("items") is Dictionary, "complete manifest is enabled with item records")
	if not parsed is Dictionary or not parsed.get("items") is Dictionary: return false
	var entries: Dictionary = parsed.items
	var shop: Variant = JSON.parse_string(FileAccess.get_file_as_string(Art.SHOP_MANIFEST_PATH))
	if shop is Dictionary and shop.get("items") is Dictionary: entries.merge(shop.items)
	var expected := Registry.equipment_ids()
	check(expected.size() == 96, "real catalogue contains ninety-six equipment definitions")
	check(entries.size() == expected.size() and Art.ids().size() == expected.size(), "manifests and runtime expose all ninety-six entries")
	var region_keys: Dictionary = {}
	var regions_by_source: Dictionary = {}
	var source_slots: Dictionary = {}
	for value in expected:
		var id := str(value)
		var definition := Registry.equipment(id)
		check(entries.has(id), id + ": has its own manifest entry")
		if not entries.has(id): continue
		var entry: Variant = entries[id]
		check(entry is Dictionary and str(entry.get("slot", "")) == str(definition.slot), id + ": art slot matches the actual equipment definition")
		if not entry is Dictionary: continue
		check(str(entry.get("name", "")) == str(definition.name), id + ": manifest keeps the real localized catalogue identity")
		var painted: Texture2D = Art.texture(id)
		check(painted is AtlasTexture, id + ": resolves a new authored atlas illustration")
		if not painted is AtlasTexture: continue
		var atlas := painted as AtlasTexture
		check(atlas == Art.texture(id), id + ": repeated lookups share one cached texture")
		check(atlas.filter_clip and atlas.region == Art.region(id), id + ": filtered atlas uses the exact declared region")
		var path := Art.source_path(id)
		check(path == str(entry.get("texture", "")), id + ": source matches this item's manifest record")
		check(not path.is_empty() and FileAccess.file_exists(path), id + ": declared painted source exists")
		check(path != "res://assets/generated/equipment/" + id + "_v1.png", id + ": regenerated source replaces the previous miniature")
		if path.is_empty() or not FileAccess.file_exists(path): continue
		check(entry.has("set_id") or not source_slots.has(path) or source_slots[path] == str(definition.slot), id + ": category source or explicit six-slot set atlas matches its manifest")
		source_slots[path] = str(definition.slot)
		check(atlas.atlas == Sampler.sampled(path), id + ": crop uses the declared shared source texture")
		var raw := _source(path)
		check(raw != null and not raw.is_empty(), id + ": source PNG is readable")
		if raw == null or raw.is_empty(): continue
		var valid := atlas.region.has_area() and Rect2(Vector2.ZERO, Vector2(raw.get_size())).encloses(atlas.region)
		check(valid, id + ": crop stays within the actual PNG bounds")
		if not valid: continue
		var key := path + ":" + str(atlas.region)
		check(not region_keys.has(key), id + ": owns a distinct source region")
		region_keys[key] = id
		var previous: Array = regions_by_source.get(path, [])
		var overlaps := false
		for other: Rect2 in previous: overlaps = overlaps or other.intersects(atlas.region)
		check(not overlaps, id + ": region cannot sample an adjacent catalogue item")
		previous.append(atlas.region)
		regions_by_source[path] = previous
		_pixels_preserved(id, atlas, raw)
		var consumer := Icon.new()
		consumer.set_equipment(definition)
		check(consumer.generated_texture == painted and not consumer.is_empty, id + ": production icon chooses this exact item illustration")
		consumer.free()
	check(source_slots.size() >= Registry.SLOTS.size(), "all current categories have painted sources, including validated race-specific overrides")
	for slot: String in Registry.SLOTS:
		check(source_slots.values().has(slot), slot + ": current slot has a live painted source; future slots remain outside the catalogue")
	for slot: String in Registry.SLOTS:
		var empty := Icon.new()
		empty.set_equipment({"slot":slot})
		check(empty.is_empty and empty.generated_texture != null and empty.generated_texture == Art.fallback_texture(slot), slot + ": empty slot shows a painted empty frame")
		empty.free()
	check(Art.texture("UNKNOWN_EQUIPMENT") == null, "unknown item does not impersonate a catalogue illustration")
	return failures == 0

func _inspect_workshop(locale: String, page: String) -> void:
	var workshop: Control = app.screen.find_child("Workshop", true, false)
	check(workshop != null, locale + " / " + page + ": actual workshop page exists")
	if workshop == null: return
	var icon_count := 0
	for control: Control in workshop.find_children("*", "Control", true, false):
		if control.get_script() != Icon: continue
		icon_count += 1
		var id := str(control.equipment_data.get("id", ""))
		if id.is_empty(): continue
		check(control.generated_texture == Art.texture(id), locale + " / " + page + ": real workshop consumer shows " + id + " artwork")
		check(control.size.x > 0 and control.size.y > 0, locale + " / " + page + ": equipment illustration has a visible drawing area")
	check(icon_count >= 7, locale + " / " + page + ": equipped slots and item cards render painted gear")
	for name: String in ["CandidateEquipmentArt"]:
		var painted: Control = workshop.find_child(name, true, false)
		check(painted != null and painted.size.x >= 72 and painted.size.y >= 72, locale + " / " + page + ": details present a readable " + name + " illustration")
	check(workshop.action_button != null and workshop.action_button.size.y >= 44, locale + " / " + page + ": action remains accessible alongside art")

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(not image.is_empty(), "native screenshot contains rendered pixels: " + name)
	if image.is_empty(): return
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	check(image.save_png("res://artifacts/equipment_v2_" + name + ".png") == OK, "native screenshot saved: " + name)

func _full_catalogue() -> void:
	Words.set_locale("zh_CN")
	app.show_workshop("shop")
	await frames()
	var workshop: Control = app.screen.find_child("Workshop", true, false)
	workshop.shop_sets = false
	workshop._render()
	await frames()
	var all_button := workshop.find_child("ViewAllEquipment", true, false) as Button
	check(all_button != null and not all_button.disabled, "real shop exposes its full catalogue action")
	if all_button == null: return
	all_button.pressed.emit()
	await frames()
	check(not workshop.available_only and workshop.find_children("Item_*", "Button", true, false).size() == Registry.equipment_ids().size(), "full catalogue action exposes all sixty actual items")
	var row := workshop.find_child("Item_EQ25", true, false) as Button
	check(row != null, "full catalogue includes the real chest candidate EQ25")
	if row == null: return
	row.pressed.emit()
	await frames()
	row = workshop.find_child("Item_EQ25", true, false) as Button
	workshop.item_list.ensure_control_visible(row)
	await frames()
	check(workshop.selected_item == "EQ25" and workshop.item_list.get_global_rect().grow(2.0).encloses(row.get_global_rect()), "real row selection and scroll reveal the inspected chest item")
	check(not Game.profile.equipment.has("EQ25") and workshop.action_button.disabled, "inspecting a locked chest preserves the genuine unowned progression state")
	_inspect_workshop("zh_CN", "shop full catalogue / chest")
	await _capture("shop_fullcatalog_zh_CN_1280")

func _character() -> void:
	check(Game.start_run(), "production run opens the actual character equipment modal")
	if is_instance_valid(app.room): app.room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	for locale: String in ["zh_CN", "en"]:
		Words.set_locale(locale)
		app.show_attributes()
		await frames()
		var dossier: Control = app.modals[-1].node.find_child("CharacterDossier", true, false)
		check(dossier != null, locale + ": character dossier is the actual visible production modal")
		if dossier != null:
			for slot: String in Registry.SLOTS:
				var cell := dossier.find_child("Equipment_" + slot, true, false) as Button
				check(cell != null, locale + ": character modal exposes equipped slot " + slot)
				if cell == null: continue
				var id := str(Game.run.loadout_snapshot.get(slot, ""))
				var found: Array[Control] = []
				for control: Control in cell.find_children("*", "Control", true, false):
					if control.get_script() == Icon: found.append(control)
				check(found.size() == 1, locale + ": equipped character cell contains one painted image")
				if found.size() == 1:
					check(str(found[0].equipment_data.get("id", "")) == id and found[0].generated_texture == Art.texture(id), locale + ": character cell paints the actual equipped " + id)
				cell.pressed.emit()
				var definition := Registry.equipment(id)
				var name_text := str(definition.get("name_en", definition.get("name", ""))) if locale == "en" else str(definition.get("name", ""))
				check(dossier.detail_title.text == name_text, locale + ": equipment action still opens the correct item explanation")
			await _capture("character_" + locale + "_1280")
		app._pop_modal()
		await frames()
	Game.finish_run("extracted")
	await frames()

func _workshop() -> void:
	check(Game.new_profile(), "isolated production profile created")
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	await frames()
	# Real settlement/purchase APIs seed the actual inventory. The fixture
	# neither invents future rarity mechanics nor paints fake item data.
	check(Game.start_run() and Game.add_gold(1000), "production run grants deterministic earned currency")
	Game.finish_run("extracted")
	await frames()
	check(Game.buy_equipment("EQ02", "equipment_art:purchase"), "real shop transaction adds a second weapon")
	for locale: String in ["zh_CN", "en"]:
		Words.set_locale(locale)
		for page: String in ["inventory", "shop", "upgrade"]:
			app.show_workshop(page)
			await frames()
			var workshop: Control = app.screen.find_child("Workshop", true, false)
			if workshop != null:
				workshop.selected_item = "EQ02"
				workshop.shop_sets = false
				workshop._render()
			await frames()
			_inspect_workshop(locale, page)
			await _capture(page + "_" + locale + "_1280")
	await _full_catalogue()
	await _character()
	Words.set_locale("zh_CN")
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(), "production music releases playback resources before exit")
	app.free()
	app = null
	await frames()

func _run() -> void:
	if not Game.profile_path.get_file().begins_with("test_equipment_art"):
		push_error("Refusing equipment art acceptance without isolated test_equipment_art profile")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280,720)
	if _catalogue(): await _workshop()
	deadline.stop()
	source_images.clear()
	print("EQUIPMENT ART: %d checks, %d failures; renderer=%s; all60IDs/sourcealpha/cache/exactID/realworkshop" % [checks, failures, DisplayServer.get_name()])
	get_tree().quit(1 if failures else 0)
