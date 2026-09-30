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
static var _entries: Dictionary = {}
static var _loaded: bool = false

static func entry_for(identity: String) -> Dictionary:
	_ensure_loaded()
	return _entries.get(identity, {}).duplicate()

static func install(actor: Node2D) -> Dictionary:
	var entry: Dictionary = entry_for(str(actor.get("enemy_id")))
	if entry.is_empty() or bool(actor.get("static_actor")):
		return {}
	var old_bounds: Rect2 = actor.get("body_bounds")
	var height: float = maxf(1.0, old_bounds.size.y)
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
