class_name HeroArtFamily
extends RefCounted
## A body replacement is selected as one complete family. An incomplete import
## keeps the established avatar for every state instead of mixing two people.

const ROOT := "asset://heroes/"
const BANKS: Array[String] = ["front", "back"]
static var _families: Dictionary = {}
static var _image_sizes: Dictionary = {}

static func metadata_path(hero: String, kind: String, bank: String = "") -> String:
	var family: Dictionary = load_family(ROOT + hero + "_storybook_family_v1.json")
	if family.is_empty():
		return ""
	var value: Variant = family.assets.get(kind, "")
	if value is Dictionary:
		return str(value.get(bank, ""))
	return str(value) if bank.is_empty() else ""

static func load_family(path: String) -> Dictionary:
	if _families.has(path):
		return _families[path]
	_families[path] = {}
	var family: Dictionary = _read(path)
	if family.is_empty() or family.get("schema_version") != 1 or typeof(family.get("enabled")) != TYPE_BOOL or not family.enabled:
		return {}
	var hero: String = str(family.get("hero_id", ""))
	var assets: Variant = family.get("assets")
	if hero != "CH01" or not assets is Dictionary:
		return {}
	for kind: String in ["actions", "basic", "secondary"]:
		var banks: Variant = assets.get(kind)
		if not banks is Dictionary:
			return {}
		for bank: String in BANKS:
			var document: Dictionary = _read(str(banks.get(bank, "")))
			if not _valid_document(document, hero, kind, bank):
				return {}
	var walk: Dictionary = _read(str(assets.get("walk", "")))
	if walk.is_empty() or str(walk.get("hero_id", "")) != hero or typeof(walk.get("enabled")) != TYPE_BOOL or not walk.enabled:
		return {}
	var walk_banks: Variant = walk.get("banks")
	if not walk_banks is Dictionary:
		return {}
	for bank: String in BANKS:
		var document: Variant = walk_banks.get(bank)
		if not document is Dictionary or not str(document.get("texture","")).begins_with(ROOT + hero + "_storybook_") or not _valid_frames(document, false):
			return {}
		var sequence: Variant = document.get("sequence")
		if not sequence is Array or sequence.size() != 4:
			return {}
		var columns: Variant = document.get("columns",2)
		var rows: Variant = document.get("rows",2)
		if not _integer(columns) or not _integer(rows) or int(columns) < 1 or int(rows) < 1:
			return {}
		var cell_count: int = int(columns) * int(rows)
		var indices: Array[int] = []
		for frame: Dictionary in document.frames:
			var index: Variant = frame.get("index")
			if not _integer(index) or int(index) < 0 or int(index) >= cell_count or indices.has(int(index)):
				return {}
			indices.append(int(index))
		for index: Variant in sequence:
			if not _integer(index) or not indices.has(int(index)):
				return {}
	var cycle: Variant = walk.get("cycle_distance")
	if not _positive(cycle):
		return {}
	_families[path] = family
	return family

static func _read(path: String) -> Dictionary:
	if not path.begins_with(ROOT) or not path.ends_with(".json") or not FileAccess.file_exists(AssetCatalog.resolve(path)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	return parsed if parsed is Dictionary else {}

static func _valid_document(data: Dictionary, hero: String, kind: String, bank: String) -> bool:
	if data.is_empty() or str(data.get("hero_id", "")) != hero or str(data.get("bank", "")) != bank:
		return false
	if not str(data.get("texture","")).begins_with(ROOT + hero + "_storybook_"):
		return false
	if typeof(data.get("enabled")) != TYPE_BOOL or not data.enabled or not _valid_frames(data, true):
		return false
	if kind == "secondary" and str(data.get("slot", "")) != "secondary":
		return false
	if kind == "basic" and str(data.get("slot", "basic")) != "basic":
		return false
	var schema: Variant = data.get("schema_version")
	if not _integer(schema) or int(schema) != (2 if kind == "actions" else 1):
		return false
	var required: Array = ["idle", "windup", "release", "recovery"] if kind == "actions" else ["lift", "loaded", "downswing", "contact", "recoil", "ready"] if kind == "basic" else ["plant", "coil", "drive", "contact", "follow", "ready"]
	if data.frames.size() != required.size():
		return false
	var names: Array[String] = []
	for frame: Dictionary in data.frames:
		names.append(str(frame.get("name", "")))
	for name: String in required:
		if names.count(name) != 1:
			return false
	if kind != "actions":
		var phases: Variant = data.get("phase_frames")
		var weights: Variant = data.get("phase_weights")
		if not phases is Dictionary or not weights is Dictionary or phases.size() != 3 or weights.size() != 3:
			return false
		var expected: Dictionary = {"windup":[required[0],required[1],required[2]],"release":[required[3]],"recovery":[required[4],required[5]]}
		for phase: String in expected:
			var sequence: Variant = phases.get(phase)
			var phase_weights: Variant = weights.get(phase)
			if not sequence is Array or sequence != expected[phase] or not phase_weights is Array or phase_weights.size() != sequence.size():
				return false
			var total: float = 0.0
			for weight: Variant in phase_weights:
				if not _positive(weight):
					return false
				total += float(weight)
			if not _positive(total):
				return false
	return true

static func _valid_frames(data: Dictionary, named: bool) -> bool:
	var texture: String = str(data.get("texture", ""))
	if not texture.begins_with(ROOT) or not texture.ends_with(".png") or (not FileAccess.file_exists(AssetCatalog.resolve(texture)) and not ResourceLoader.exists(AssetCatalog.resolve(texture))):
		return false
	if not _positive(data.get("body_height")):
		return false
	var size: Vector2i = _image_size(texture)
	if size.x <= 0 or size.y <= 0:
		return false
	var facing: Variant = data.get("facing_x",1)
	if not _integer(facing) or int(facing) not in [-1,1]:
		return false
	var frames: Variant = data.get("frames")
	if not frames is Array or frames.is_empty():
		return false
	var regions: Array[Rect2] = []
	for raw_frame: Variant in frames:
		if not raw_frame is Dictionary:
			return false
		var frame: Dictionary = raw_frame
		if named and typeof(frame.get("name")) != TYPE_STRING:
			return false
		if frame.has("body_height") and not _positive(frame.body_height):
			return false
		if not _coordinates(frame.get("region", frame.get("cell")), 4) or not _coordinates(frame.get("foot"), 2):
			return false
		var region: Array = frame.get("region", frame.get("cell"))
		if float(region[0]) < 0.0 or float(region[1]) < 0.0 or not _positive(region[2]) or not _positive(region[3]):
			return false
		var rectangle := Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
		if not Rect2(Vector2.ZERO,Vector2(size)).encloses(rectangle):
			return false
		for previous: Rect2 in regions:
			if previous.intersects(rectangle):
				return false
		regions.append(rectangle)
		for label: String in ["foot","head","grip","muzzle"]:
			var point: Variant = frame.get(label)
			if not _coordinates(point,2) or not rectangle.has_point(Vector2(float(point[0]),float(point[1]))):
				return false
	return true

static func _image_size(path: String) -> Vector2i:
	if not _image_sizes.has(path):
		# Decode once before opting into the family. Existence alone cannot prove
		# that a damaged source or an out-of-bounds atlas is safe to sample.
		var resource: Resource = load(AssetCatalog.resolve(path)) if ResourceLoader.exists(AssetCatalog.resolve(path)) else null
		var source: Image = resource.get_image() if resource is Texture2D else Image.load_from_file(AssetCatalog.resolve(path)) if FileAccess.file_exists(AssetCatalog.resolve(path)) else null
		_image_sizes[path] = source.get_size() if source != null and not source.is_empty() else Vector2i.ZERO
	return _image_sizes[path]

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value))

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0

static func _coordinates(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number: Variant in value:
		if (not number is int and not number is float) or not is_finite(float(number)):
			return false
	return true
