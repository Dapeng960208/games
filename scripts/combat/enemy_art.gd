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
# Individual native HD bodies for appended species; manifests carry the true
# alpha bounds and feet. Missing art never substitutes another new identity.
const EXPANSION_MANIFESTS: Array[String] = [
	"res://assets/generated/enemies/M37_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M38_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M39_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M40_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M41_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M42_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M43_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M44_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M45_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M46_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M47_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M48_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M49_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M50_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M51_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M52_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M53_storybook_body_v1.regions.json",
	"res://assets/generated/enemies/M54_storybook_body_v1.regions.json",
]
# These are full-body, source-faithful repaints of the current atlas bosses.
# Their combat registration is separate from codex/UI sizing. If a manifest or
# texture is unavailable, the existing matching atlas entry remains the fallback.
const BOSS_MANIFESTS: Array[String] = [
	"res://assets/generated/enemies/BO01_storybook_body_hd_v1.regions.json",
	"res://assets/generated/enemies/BO02_storybook_body_hd_v1.regions.json",
	"res://assets/generated/enemies/BO03_storybook_body_hd_v1.regions.json",
	"res://assets/generated/enemies/BO04_storybook_body_hd_v1.regions.json",
]
# A bounded, identity-matched sampling upgrade. Resolve the original 599-entry
# cycle first; replacements never add, remove or reorder an appearance.
const VARIANT_HD_MANIFEST: String = "res://assets/generated/enemies/variant_hd_v1/variant_hd_v1.overrides.json"
const VARIANT_HD_INDICES: Dictionary = {"M22": [0], "M34": [0, 1, 4]}
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
	# Appended species have no obsolete Mxx_v1 image to initialize bounds.
	# Register them on the same ordinary-anatomy scale and ground pivot instead
	# of inheriting the rust-mite fallback's 38-pixel foot position.
	var standalone: bool = bool(entry.get("individual_body", false))
	var boss_body: bool = bool(entry.get("combat_body", false))
	var native_height: float = clampf(float(actor.get("navigation_radius")) * 3.8, 66.0, 88.0) if standalone else maxf(1.0, old_bounds.size.y)
	if boss_body:
		# Match the old atlas's final production height without inheriting an
		# already-scaled body on reconfigure. Only presentation reads this scale.
		native_height = clampf(float(actor.get("navigation_radius")) * 3.45, 170.0, 220.0)
	var height: float = native_height * preload("res://scripts/combat/presentation_metrics.gd").ENEMY_BODY_FACTOR
	var foot_y: float = 48.0 if boss_body else 18.0 if standalone else old_bounds.end.y
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
	for manifest_path: String in MANIFESTS + EXPANSION_MANIFESTS + BOSS_MANIFESTS:
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
			if manifest_path in BOSS_MANIFESTS and (not identity.begins_with("BO") or not raw.entries[identity] is Dictionary or str(raw.entries[identity].get("source_identity", "")) != identity):
				continue
			var parsed: Dictionary = parse_entry(raw.entries[identity], texture.get_size())
			if parsed.is_empty():
				continue
			parsed["texture"] = texture
			parsed["texture_path"] = texture_path
			parsed["source_family"] = FAMILY
			parsed["biome_id"] = str(raw.get("biome_id", ""))
			parsed["individual_body"] = manifest_path in EXPANSION_MANIFESTS
			parsed["combat_body"] = manifest_path in BOSS_MANIFESTS
			parsed["visual_clan"] = str(raw.get("visual_clan", ""))
			_entries[identity] = parsed
	_load_variants()
	_load_variant_hd_overrides()

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

static func _load_variant_hd_overrides() -> void:
	if not FileAccess.file_exists(VARIANT_HD_MANIFEST):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(VARIANT_HD_MANIFEST))
	if not raw is Dictionary or raw.get("schema_version") != 1 or raw.get("source_family") != FAMILY or not raw.get("overrides") is Array:
		return
	for candidate: Variant in raw.overrides:
		var entry := _variant_hd_entry(candidate)
		if not entry.is_empty():
			_variants[entry.hd_source.identity][entry.visual_variant_index] = entry

static func _variant_hd_entry(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("source") is Dictionary or not raw.get("replacement") is Dictionary:
		return {}
	var source: Dictionary = raw.source
	var identity: String = str(source.get("identity", ""))
	var index: Variant = source.get("visual_variant_index")
	if not (index is int or index is float) or not is_finite(float(index)) or float(index) != floorf(float(index)):
		return {}
	if not VARIANT_HD_INDICES.has(identity) or not int(index) in VARIANT_HD_INDICES[identity]:
		return {}
	var choices: Array = _variants.get(identity, [])
	if int(index) >= choices.size():
		return {}
	var original: Dictionary = choices[int(index)]
	if str(source.get("variant_id", "")) != str(original.get("variant_id", "")) or str(source.get("texture", "")) != str(original.get("texture_path", "")):
		return {}
	var source_body: Dictionary = source.duplicate(true)
	source_body["full_color"] = true
	var source_entry := parse_entry(source_body, (original.texture as Texture2D).get_size())
	if source_entry.is_empty() or source_entry.region != original.region or source_entry.foot != original.foot or source_entry.source_height != original.source_height:
		return {}
	var replacement: Dictionary = raw.replacement
	if replacement.get("source_identity") != identity or replacement.get("source_variant_id") != original.variant_id or replacement.get("native_redraw") != true:
		return {}
	var texture_path: String = str(replacement.get("texture", ""))
	# Exact reviewed files only; adding a manifest candidate cannot opt in
	# another variant or a canonical-body substitution.
	if texture_path != "res://assets/generated/enemies/variant_hd_v1/%s_variant_%02d_hd_v1.png" % [identity, int(index)]:
		return {}
	if not FileAccess.file_exists(texture_path) and not ResourceLoader.exists(texture_path):
		return {}
	var texture: Texture2D = Sampler.sampled(texture_path)
	if texture == null:
		return {}
	var parsed := parse_entry(replacement, texture.get_size())
	if parsed.is_empty() or parsed.source_height <= original.source_height:
		return {}
	# Normalized body/foot registration must match before accepting native HD
	# pixels. Existing install, animation and collision paths remain unchanged.
	var old_box := Rect2((original.region.position - original.foot) / original.source_height, original.region.size / original.source_height)
	var new_box := Rect2((parsed.region.position - parsed.foot) / parsed.source_height, parsed.region.size / parsed.source_height)
	if not old_box.is_equal_approx(new_box):
		return {}
	var result: Dictionary = original.duplicate(true)
	result["texture"] = texture
	result["texture_path"] = texture_path
	result["region"] = parsed.region
	result["foot"] = parsed.foot
	result["source_height"] = parsed.source_height
	result["hd_variant"] = true
	result["hd_source"] = source.duplicate(true)
	return result

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
