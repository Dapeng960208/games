class_name EquipmentArt
extends RefCounted
## Original painted 3/4 equipment illustrations, sampled from six category atlases.
## A manifest is activated only after all catalogue entries have real artwork.

const MANIFEST_PATH := "asset://equipment/storybook_equipment_v2.manifest.json"
const SHOP_MANIFEST_PATH := "asset://equipment/storybook_shop_sets_v2.manifest.json"
const B05_MANIFEST_PATH := "asset://equipment/b05_v1/B05-equipment-v1.manifest.json"
const B06_MANIFEST_PATH := "asset://equipment/b06_v1/B06-equipment-v1.manifest.json"
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const Chrome = preload("res://scripts/infrastructure/assets/storybook_art.gd")
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _prefetches: Dictionary = {}
static var _prefetched: Dictionary = {}

static func finish_prefetches() -> void:
	for path: String in _prefetches.keys():
		var status := ResourceLoader.load_threaded_get_status(AssetCatalog.resolve(path))
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_prefetched[path] = ResourceLoader.load_threaded_get(AssetCatalog.resolve(path))
		_prefetches.erase(path)

static func prefetch_owned(records: Dictionary) -> void:
	# Decode imported sheets in Godot's loader while the camp is visible.
	# There is no wait, inventory mutation, or texture readback on this path.
	var paths := {}
	for id: String in records:
		var record: Variant = records[id]
		var template := str(record.get("template_id",id)) if record is Dictionary else id
		var path := source_path(template)
		if not path.is_empty(): paths[path] = true
	for entry: Dictionary in _read_manifest().get("slot_fallbacks",{}).values():
		var path := str(entry.get("texture",""))
		if not path.is_empty(): paths[path] = true
	for path: String in paths:
		if _prefetches.has(path) or ResourceLoader.has_cached(path): continue
		if ResourceLoader.load_threaded_request(AssetCatalog.resolve(path),"Texture2D") == OK: _prefetches[path] = true

static func _read_manifest() -> Dictionary:
	if not _manifest.is_empty(): return _manifest
	if not FileAccess.file_exists(AssetCatalog.resolve(MANIFEST_PATH)): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(MANIFEST_PATH)))
	if not parsed is Dictionary or not bool(parsed.get("enabled", false)) or not parsed.get("items") is Dictionary:
		return {}
	_manifest = parsed
	if FileAccess.file_exists(AssetCatalog.resolve(SHOP_MANIFEST_PATH)):
		var shop: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(SHOP_MANIFEST_PATH)))
		if shop is Dictionary and bool(shop.get("enabled",false)) and shop.get("items") is Dictionary:
			_manifest.items.merge(shop.items,false)
	if FileAccess.file_exists(AssetCatalog.resolve(B05_MANIFEST_PATH)):
		merge_b05_manifest(_manifest, JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(B05_MANIFEST_PATH))))
	if preload("res://scripts/infrastructure/content/runtime_rules.gd").b06_candidate_enabled() and FileAccess.file_exists(AssetCatalog.resolve(B06_MANIFEST_PATH)):
		merge_b06_candidate(_manifest, JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(B06_MANIFEST_PATH))))
	return _manifest

static func merge_b05_manifest(base: Dictionary, candidate: Variant) -> void:
	# The independent art-quality gate does not release a chapter or replace
	# historical artwork. Disabled/missing packs keep the existing slot fallback.
	if not candidate is Dictionary or not bool(candidate.get("enabled", false)): return
	if candidate.get("chapter_id") != "B05" or not candidate.get("items") is Dictionary: return
	if not base.get("items") is Dictionary: return
	for id: String in candidate.items:
		if id.begins_with("B05-") and not base.items.has(id) and candidate.items[id] is Dictionary:
			base.items[id] = candidate.items[id].duplicate(true)

static func merge_b06_candidate(base: Dictionary, candidate: Variant) -> void:
	# Explicit isolated chapter preview only; the disk release gate stays false.
	if not candidate is Dictionary or candidate.get("chapter_id") != "B06": return
	if not bool(candidate.get("candidate_only", false)) or not candidate.get("items") is Dictionary: return
	if not base.get("items") is Dictionary: return
	for id: String in candidate.items:
		if id.begins_with("B06-") and not base.items.has(id) and candidate.items[id] is Dictionary:
			base.items[id] = candidate.items[id].duplicate(true)

static func available() -> bool:
	return not _read_manifest().is_empty()

static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in _read_manifest().get("items", {}): result.append(id)
	result.sort()
	return result

static func source_path(id: String) -> String:
	var entry: Dictionary = _read_manifest().get("items", {}).get(id, {})
	return str(entry.get("texture", ""))

static func region(id: String) -> Rect2:
	var entry: Dictionary = _read_manifest().get("items", {}).get(id, {})
	var value: Variant = entry.get("region", [])
	if not value is Array or value.size() != 4: return Rect2()
	for coordinate: Variant in value:
		if not coordinate is int and not coordinate is float: return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func texture(id: String) -> Texture2D:
	if _textures.has(id): return _textures[id]
	var image := _entry_texture(_read_manifest().get("items", {}).get(id, {}))
	if image != null: _textures[id] = image
	return image

static func slot_texture(slot: String) -> Texture2D:
	var key := "slot:"+slot
	if _textures.has(key): return _textures[key]
	var image := _entry_texture(_read_manifest().get("slot_fallbacks", {}).get(slot, {}))
	if image != null: _textures[key] = image
	return image

static func _entry_texture(entry: Dictionary) -> Texture2D:
	var path := str(entry.get("texture", ""))
	if path.is_empty(): return null
	var source: Texture2D = Sampler.sampled(path)
	if source == null: return null
	var value: Variant = entry.get("region", [])
	if not value is Array or value.size() != 4: return null
	for coordinate: Variant in value:
		if not coordinate is int and not coordinate is float: return null
	var bounds := Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
	if not bounds.has_area() or not Rect2(Vector2.ZERO, source.get_size()).encloses(bounds): return null
	var image := AtlasTexture.new()
	image.atlas = source
	image.region = bounds
	image.filter_clip = true
	return image

static func fallback_texture(_slot: String) -> Texture2D:
	# Empty slots are an empty painted bezel, so they cannot resemble owned gear.
	return Chrome.texture("gold_bezel")
