class_name EnemyArt
extends RefCounted
## Explicit painted-body regions. Old art remains on disk; valid new artwork
## installs as a complete family, never mixing an old pose into a new body.

const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const FAMILY: String = "storybook_2_5d_v1"
const MANIFESTS: Array[String] = [
	"res://assets/generated/enemies/storybook_B01_bodies_v2.regions.json",
	"res://assets/generated/enemies/storybook_B02_bodies_v2.regions.json",
	"res://assets/generated/enemies/storybook_B03_bodies_v2.regions.json",
	"res://assets/generated/enemies/storybook_B04_bodies_v2.regions.json",
]
const VARIANT_MANIFESTS: Array[String] = [
	"res://assets/generated/enemies/storybook_B01_variants_v1.regions.json",
	"res://assets/generated/enemies/storybook_B02_variants_v1.regions.json",
	"res://assets/generated/enemies/storybook_B03_variants_v1.regions.json",
	"res://assets/generated/enemies/storybook_B04_variants_v1.regions.json",
	"res://assets/generated/enemies/storybook_B01_reinforcements_v1.regions.json",
	"res://assets/generated/enemies/storybook_B02_reinforcements_v1.regions.json",
	"res://assets/generated/enemies/storybook_B03_reinforcements_v1.regions.json",
	"res://assets/generated/enemies/storybook_B04_reinforcements_v1.regions.json",
	"res://assets/generated/enemies/storybook_B03_shovels_v1.regions.json",
]
static var _entries: Dictionary = {}
static var _variants: Dictionary = {}
static var _skill_icons: Dictionary = {}
static var _loaded: bool = false

static func entry_for(identity: String) -> Dictionary:
	_ensure_loaded()
	return _entries.get(identity, {}).duplicate()

static func variant_count(identity: String) -> int:
	_ensure_loaded()
	return (_variants.get(identity, []) as Array).size()

static func variant_entry_for(identity: String, index: int) -> Dictionary:
	_ensure_loaded()
	var choices: Array = _variants.get(identity, [])
	if index < 0 or index >= choices.size():
		return entry_for(identity)
	return (choices[index] as Dictionary).duplicate()

static func variant_index_for(identity: String, serial: int, room_id: String, room_seed: int) -> int:
	var count: int = variant_count(identity)
	if count == 0:
		return -1
	# A private deterministic cycle consumes no gameplay RNG. Entries are
	# deduplicated by their real texture/region before forming this cycle.
	var offset: int = posmod((room_id + ":" + str(room_seed) + ":" + identity).hash(), count)
	return posmod(offset + serial, count)

static func skill_icon_for(identity: String) -> Dictionary:
	_ensure_loaded()
	return _skill_icons.get(identity, {}).duplicate()

static func appearance_key(entry: Dictionary) -> String:
	return str(entry.get("texture_path", "")) + ":" + str(entry.get("region", Rect2()))

static func install(actor: Node2D) -> Dictionary:
	var definition: Dictionary = actor.get("profile")
	var entry: Dictionary = variant_entry_for(str(actor.get("enemy_id")), int(definition.get("visual_variant_index", -1)))
	if entry.is_empty() or bool(actor.get("static_actor")):
		return {}
	var old_bounds: Rect2 = actor.get("body_bounds")
	var height: float = maxf(1.0, old_bounds.size.y) * preload("res://scripts/combat/presentation_metrics.gd").ENEMY_BODY_FACTOR
	var foot_y: float = old_bounds.end.y
	var region: Rect2 = entry.region
	var source_foot: Vector2 = entry.foot
	var factor: float = height / float(entry.source_height)
	var local_bounds := Rect2((region.position - source_foot) * factor + Vector2(0, foot_y), region.size * factor)
	actor.set("body_texture", entry.texture)
	actor.set("body_region", region)
	actor.set("body_bounds", local_bounds)
	if str(actor.get("enemy_id")) == "M35":
		# Carrying a lantern belongs to the prop system. The empty state keeps
		# the same painted creature rather than returning to a coal-era body.
		actor.set("empty_body_texture", entry.texture)
	entry["native_bounds"] = local_bounds
	return entry

static func motion_path(identity: String) -> String:
	return "res://assets/generated/enemies/%s_storybook_motion_v1.json" % identity

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for manifest_path: String in MANIFESTS:
		if not FileAccess.file_exists(manifest_path):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not raw is Dictionary or not raw.get("entries") is Dictionary:
			continue
		if raw.get("source_family", FAMILY) != FAMILY:
			continue
		var texture_path: String = str(raw.get("texture", ""))
		if texture_path.is_empty() or (not FileAccess.file_exists(texture_path) and not ResourceLoader.exists(texture_path)):
			continue
		var texture: Texture2D = Sampler.sampled(texture_path)
		if texture == null:
			continue
		for identity: String in raw.entries:
			var parsed: Dictionary = parse_entry(raw.entries[identity], texture.get_size())
			if parsed.is_empty():
				continue
			parsed["texture"] = texture
			parsed["texture_path"] = texture_path
			parsed["source_family"] = FAMILY
			parsed["biome_id"] = str(raw.get("biome_id", ""))
			parsed["visual_clan"] = str(raw.get("visual_clan", ""))
			_entries[identity] = parsed
	_load_variants()

static func _load_variants() -> void:
	var seen: Dictionary = {}
	for manifest_path: String in VARIANT_MANIFESTS:
		if not FileAccess.file_exists(manifest_path):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not raw is Dictionary or not raw.get("entries") is Dictionary or raw.get("source_family", FAMILY) != FAMILY:
			continue
		var texture_path: String = str(raw.get("texture", ""))
		if texture_path.is_empty() or (not FileAccess.file_exists(texture_path) and not ResourceLoader.exists(texture_path)):
			continue
		var texture: Texture2D = Sampler.sampled(texture_path)
		if texture == null:
			continue
		for identity: String in raw.entries:
			var candidates: Variant = raw.entries[identity]
			if not candidates is Array or not _entries.has(identity):
				continue
			if not _variants.has(identity):
				_variants[identity] = []
			for item: Variant in candidates:
				var parsed: Dictionary = parse_entry(item, texture.get_size())
				if parsed.is_empty():
					continue
				parsed["texture"] = texture
				parsed["texture_path"] = texture_path
				parsed["source_family"] = FAMILY
				parsed["biome_id"] = str(raw.get("biome_id", ""))
				parsed["visual_clan"] = str(_entries[identity].get("visual_clan", ""))
				var key: String = appearance_key(parsed)
				if seen.has(key):
					continue
				seen[key] = true
				parsed["visual_variant_index"] = (_variants[identity] as Array).size()
				_variants[identity].append(parsed)
		var icons: Variant = raw.get("skill_icons", {})
		if not icons is Dictionary:
			continue
		for identity: String in icons:
			var values: Variant = icons[identity]
			if not values is Array or values.size() != 4:
				continue
			var valid: bool = true
			for value: Variant in values:
				if not (value is int or value is float) or not is_finite(float(value)):
					valid = false
			if not valid:
				continue
			var region := Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
			if region.has_area() and Rect2(Vector2.ZERO, texture.get_size()).encloses(region):
				_skill_icons[identity] = {"texture":texture,"texture_path":texture_path,"region":region}

static func parse_entry(raw: Variant, texture_size: Vector2) -> Dictionary:
	if not raw is Dictionary or raw.get("full_color") != true:
		return {}
	var values: Variant = raw.get("region", [])
	var anchor: Variant = raw.get("foot", [])
	var height: Variant = raw.get("source_height", 0)
	if not values is Array or values.size() != 4 or not anchor is Array or anchor.size() != 2:
		return {}
	for value: Variant in values + anchor + [height]:
		if not (value is int or value is float) or not is_finite(float(value)):
			return {}
	if float(height) <= 0.0:
		return {}
	var region := Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	var foot := Vector2(float(anchor[0]), float(anchor[1]))
	if not region.has_area() or not Rect2(Vector2.ZERO, texture_size).encloses(region):
		return {}
	if foot.x < region.position.x or foot.x > region.end.x or foot.y < region.position.y or foot.y > region.end.y:
		return {}
	# Static atlas feet sit at the bottom boundary. This preserves the existing
	# actor pivot; an animated bank instead supplies its own per-pose foot.
	if absf(foot.y - region.end.y) > 0.01 or absf(float(height) - region.size.y) > 0.01:
		return {}
	var result: Dictionary = raw.duplicate(true)
	result["region"] = region
	result["foot"] = foot
	result["source_height"] = float(height)
	return result
