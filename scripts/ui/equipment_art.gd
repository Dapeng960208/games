class_name EquipmentArt
extends RefCounted
## Original painted 3/4 equipment illustrations, sampled from six category atlases.
## A manifest is activated only after all catalogue entries have real artwork.

const MANIFEST_PATH := "res://assets/generated/equipment/storybook_equipment_v2.manifest.json"
const SHOP_MANIFEST_PATH := "res://assets/generated/equipment/storybook_shop_sets_v2.manifest.json"
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Chrome = preload("res://scripts/ui/storybook_art.gd")
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}

static func _read_manifest() -> Dictionary:
	if not _manifest.is_empty(): return _manifest
	if not FileAccess.file_exists(MANIFEST_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or not bool(parsed.get("enabled", false)) or not parsed.get("items") is Dictionary:
		return {}
	_manifest = parsed
	if FileAccess.file_exists(SHOP_MANIFEST_PATH):
		var shop: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOP_MANIFEST_PATH))
		if shop is Dictionary and bool(shop.get("enabled",false)) and shop.get("items") is Dictionary:
			_manifest.items.merge(shop.items,false)
	return _manifest

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
