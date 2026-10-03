class_name EnemyArt
extends RefCounted
## Current registered painted bodies and identity-matched variants.
## Retired portraits and incomplete candidate banks are not runtime fallbacks.

const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const VariantHdTexture = preload("res://scripts/presentation/monsters/variant_hd_texture.gd")
const FAMILY: String = "storybook_2_5d_v1"
const MANIFESTS: Array[String] = [
	"asset://enemies/storybook_B01_bodies_v2.regions.json",
	"asset://enemies/storybook_B02_bodies_v2.regions.json",
	"asset://enemies/storybook_B03_bodies_v2.regions.json",
	"asset://enemies/storybook_B04_bodies_v2.regions.json",
]
const VARIANT_MANIFESTS: Array[String] = [
	"asset://enemies/storybook_B01_variants_v1.regions.json",
	"asset://enemies/storybook_B02_variants_v1.regions.json",
	"asset://enemies/storybook_B03_variants_v1.regions.json",
	"asset://enemies/storybook_B04_variants_v1.regions.json",
	"asset://enemies/storybook_B01_reinforcements_v1.regions.json",
	"asset://enemies/storybook_B02_reinforcements_v1.regions.json",
	"asset://enemies/storybook_B03_reinforcements_v1.regions.json",
	"asset://enemies/storybook_B04_reinforcements_v1.regions.json",
	"asset://enemies/storybook_B03_shovels_v1.regions.json",
]
# Individual native HD bodies for appended species; manifests carry the true
# alpha bounds and feet. Missing art never substitutes another new identity.
const EXPANSION_MANIFESTS: Array[String] = [
	"asset://enemies/M37_storybook_body_v1.regions.json",
	"asset://enemies/M38_storybook_body_v1.regions.json",
	"asset://enemies/M39_storybook_body_v1.regions.json",
	"asset://enemies/M40_storybook_body_v1.regions.json",
	"asset://enemies/M41_storybook_body_v1.regions.json",
	"asset://enemies/M42_storybook_body_v1.regions.json",
	"asset://enemies/M43_storybook_body_v1.regions.json",
	"asset://enemies/M44_storybook_body_v1.regions.json",
	"asset://enemies/M45_storybook_body_v1.regions.json",
	"asset://enemies/M46_storybook_body_v1.regions.json",
	"asset://enemies/M47_storybook_body_v1.regions.json",
	"asset://enemies/M48_storybook_body_v1.regions.json",
	"asset://enemies/M49_storybook_body_v1.regions.json",
	"asset://enemies/M50_storybook_body_v1.regions.json",
	"asset://enemies/M51_storybook_body_v1.regions.json",
	"asset://enemies/M52_storybook_body_v1.regions.json",
	"asset://enemies/M53_storybook_body_v1.regions.json",
	"asset://enemies/M54_storybook_body_v1.regions.json",
]
# These are full-body, source-faithful repaints of the current atlas bosses.
# Their combat registration is separate from codex/UI sizing. If a manifest or
# texture is unavailable, the existing matching atlas entry remains the fallback.
const BOSS_MANIFESTS: Array[String] = [
	"asset://enemies/BO01_storybook_body_hd_v1.regions.json",
	"asset://enemies/BO02_storybook_body_hd_v1.regions.json",
	"asset://enemies/BO03_storybook_body_hd_v1.regions.json",
	"asset://enemies/BO04_storybook_body_hd_v1.regions.json",
]
# A bounded, identity-matched sampling upgrade. Resolve the original 599-entry
# cycle first; replacements never add, remove or reorder an appearance.
const VARIANT_HD_MANIFEST: String = "asset://enemies/variant_hd_v1/variant_hd_v1.overrides.json"
const VARIANT_HD_MANIFESTS: Array[String] = [
	VARIANT_HD_MANIFEST,
	"asset://enemies/variant_hd_v1/ruins_v1.overrides.json",
	"asset://enemies/variant_hd_v1/hive_v1.overrides.json",
	"asset://enemies/variant_hd_v1/soft_combat_v1.overrides.json",
]
const VARIANT_HD_INDICES: Dictionary = {"M04": [1], "M06": [0,6,7], "M09": [7], "M12": [0,5,6,7], "M17": [0,1,2,6,7], "M22": [0,5,7], "M23": [0,3], "M34": [0,1,4]}
static var _entries: Dictionary = {}
static var _variants: Dictionary = {}
static var _skill_icons: Dictionary = {}
static var _loaded: Dictionary = {}

static func entry_for(identity: String) -> Dictionary:
	if identity.begins_with("B09-M") or identity == "BO09": return preload("res://scripts/levels/b09/art/actors.gd").entry(identity)
	if identity.begins_with("B06-M"): return preload("res://scripts/levels/b06/art/native_art.gd").entry(identity)
	if identity in preload("res://scripts/levels/b05/art/enemy_art.gd").IDS: return preload("res://scripts/levels/b05/art/enemy_art.gd").entry(identity)
	_ensure_loaded(identity)
	return _entries.get(identity, {}).duplicate()

static func variant_count(identity: String) -> int:
	_ensure_loaded(identity)
	return (_variants.get(identity, []) as Array).size()

static func variant_entry_for(identity: String, index: int) -> Dictionary:
	if identity.begins_with("B09-M") or identity == "BO09": return preload("res://scripts/levels/b09/art/actors.gd").entry(identity)
	if identity.begins_with("B06-M"): return preload("res://scripts/levels/b06/art/native_art.gd").entry(identity)
	if identity in preload("res://scripts/levels/b05/art/enemy_art.gd").IDS: return preload("res://scripts/levels/b05/art/enemy_art.gd").entry(identity)
	_ensure_loaded(identity)
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
	if identity.begins_with("B09-M"):
		var frame: Dictionary = preload("res://scripts/levels/b09/art/actors.gd").frame(identity)
		if frame.is_empty(): return {}
		return {"texture":frame.texture,"texture_path":frame.texture_path,"region":Rect2(Vector2(frame.core)-Vector2(110,110),Vector2(220,220))}
	if identity.begins_with("B06-M"):
		var frame: Dictionary = preload("res://scripts/levels/b06/art/native_art.gd").frame(identity)
		if frame.is_empty(): return {}
		return {"texture":frame.texture,"texture_path":frame.texture_path,"region":Rect2(Vector2(frame.core)-Vector2(150,150),Vector2(300,300))}
	if identity in preload("res://scripts/levels/b05/art/enemy_art.gd").IDS:
		var bank: Dictionary=preload("res://scripts/levels/b05/art/enemy_art.gd").bank(identity)
		if bank.is_empty(): return {}
		var frame: Dictionary=bank.clips.idle[0]
		return {"texture":frame.texture,"texture_path":frame.texture_path,"region":Rect2(Vector2(frame.core)-Vector2(150,150),Vector2(300,300))}
	_ensure_loaded(identity)
	return _skill_icons.get(identity, {}).duplicate()

static func appearance_key(entry: Dictionary) -> String:
	return str(entry.get("texture_path", "")) + ":" + str(entry.get("region", Rect2()))

static func install(actor: Node2D) -> Dictionary:
	var definition: Dictionary = actor.get("profile")
	var entry: Dictionary = variant_entry_for(str(actor.get("enemy_id")), int(definition.get("visual_variant_index", -1)))
	# First-room race additions are encounter body variants. The default entry,
	# codex portrait and skill badge continue using their existing registration.
	if bool(definition.get("first_room_race_variant", false)):
		var identity := str(actor.get("enemy_id"))
		var added: Dictionary = {}
		if identity.begins_with("B05-M"):
			added = preload("res://scripts/levels/b05/art/enemy_art.gd").first_room_entry(identity)
		elif identity.begins_with("B06-M"):
			added = preload("res://scripts/levels/b06/art/native_art.gd").first_room_entry(identity)
		if not added.is_empty(): entry = added
	if entry.is_empty() or bool(actor.get("static_actor")):
		return {}
	var old_bounds: Rect2 = actor.get("body_bounds")
	# Ordinary body registration comes from the current profile, independently
	# of retired portraits or a previously installed presentation scale.
	var ordinary_body: bool = bool(entry.get("individual_body", false)) or str(actor.get("actor_kind")) == "enemy"
	var boss_body: bool = bool(entry.get("combat_body", false))
	var native_height: float = clampf(float(actor.get("navigation_radius")) * 3.8, 66.0, 88.0) if ordinary_body else maxf(1.0, old_bounds.size.y)
	if boss_body:
		# Match the old atlas's final production height without inheriting an
		# already-scaled body on reconfigure. Only presentation reads this scale.
		native_height = clampf(float(actor.get("navigation_radius")) * 3.45, 170.0, 220.0)
	var height: float = native_height * preload("res://scripts/shared/presentation_metrics.gd").ENEMY_BODY_FACTOR
	var foot_y: float = 48.0 if boss_body else 18.0 if ordinary_body else old_bounds.end.y
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
	if bool(entry.get("b05_native_bank",false)) or bool(entry.get("b06_native_bank",false)) or bool(entry.get("b09_native_bank",false)):
		entry["world_reference_height"] = height
		entry["world_foot"] = Vector2(0,foot_y)
	return entry

static func _load_all_for_audit() -> void:
	# Explicit catalogue audits may inspect all entries; gameplay must not turn a
	# single lookup into a preload of unrelated chapters and native HD bodies.
	for path: String in MANIFESTS + EXPANSION_MANIFESTS + BOSS_MANIFESTS:
		if not FileAccess.file_exists(AssetCatalog.resolve(path)): continue
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
		if not manifest is Dictionary or not manifest.get("entries") is Dictionary: continue
		for identity: String in manifest.entries: _ensure_loaded(identity)

static func _ensure_loaded(requested_identity: String) -> void:
	if requested_identity.is_empty(): return
	if _loaded.has(requested_identity): return
	_loaded[requested_identity] = true
	for manifest_path: String in MANIFESTS + EXPANSION_MANIFESTS + BOSS_MANIFESTS:
		if not FileAccess.file_exists(AssetCatalog.resolve(manifest_path)):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(manifest_path)))
		if not raw is Dictionary or not raw.get("entries") is Dictionary:
			continue
		if not raw.entries.has(requested_identity): continue
		if raw.get("source_family", FAMILY) != FAMILY:
			continue
		var texture_path: String = str(raw.get("texture", ""))
		if texture_path.is_empty() or (not FileAccess.file_exists(AssetCatalog.resolve(texture_path)) and not ResourceLoader.exists(AssetCatalog.resolve(texture_path))):
			continue
		var texture: Texture2D = Sampler.sampled(texture_path)
		if texture == null:
			continue
		for identity: String in [requested_identity]:
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
	_load_variants(requested_identity)
	_load_variant_hd_overrides(requested_identity)

static func _load_variants(requested_identity: String = "") -> void:
	var seen: Dictionary = {}
	for manifest_path: String in VARIANT_MANIFESTS:
		if not FileAccess.file_exists(AssetCatalog.resolve(manifest_path)):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(manifest_path)))
		if not raw is Dictionary or not raw.get("entries") is Dictionary or raw.get("source_family", FAMILY) != FAMILY:
			continue
		if not requested_identity.is_empty() and not raw.entries.has(requested_identity): continue
		var texture_path: String = str(raw.get("texture", ""))
		if texture_path.is_empty() or (not FileAccess.file_exists(AssetCatalog.resolve(texture_path)) and not ResourceLoader.exists(AssetCatalog.resolve(texture_path))):
			continue
		var texture: Texture2D = Sampler.sampled(texture_path)
		if texture == null:
			continue
		for identity: String in raw.entries:
			if not requested_identity.is_empty() and identity != requested_identity: continue
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
			if not requested_identity.is_empty() and identity != requested_identity: continue
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

static func _load_variant_hd_overrides(requested_identity: String = "") -> void:
	for manifest_path: String in VARIANT_HD_MANIFESTS:
		if not FileAccess.file_exists(AssetCatalog.resolve(manifest_path)):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(manifest_path)))
		if not raw is Dictionary or raw.get("schema_version") != 1 or raw.get("source_family") != FAMILY or not raw.get("overrides") is Array:
			continue
		for candidate: Variant in raw.overrides:
			if not requested_identity.is_empty() and (not candidate is Dictionary or not candidate.get("source") is Dictionary or str(candidate.source.get("identity", "")) != requested_identity): continue
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
	if texture_path != "asset://enemies/variant_hd_v1/%s_variant_%02d_hd_v1.png" % [identity, int(index)]:
		return {}
	if not FileAccess.file_exists(AssetCatalog.resolve(texture_path)) and not ResourceLoader.exists(AssetCatalog.resolve(texture_path)):
		return {}
	var layout: Dictionary = {}
	var registered: Dictionary = replacement.duplicate(true)
	if VariantHdTexture.required(identity,int(index)):
		layout = VariantHdTexture.parse_layout(identity,int(index),replacement,raw.get("virtual_transparent_layout"))
		if layout.is_empty(): return {}
		registered["region"] = [layout.region.position.x,layout.region.position.y,layout.region.size.x,layout.region.size.y]
		registered["foot"] = [layout.foot.x,layout.foot.y]
	elif raw.has("virtual_transparent_layout"):
		return {}
	var texture: Texture2D = VariantHdTexture.sampled(texture_path,layout) if not layout.is_empty() else Sampler.sampled(texture_path)
	if texture == null:
		return {}
	var parsed := parse_entry(registered, texture.get_size())
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
	if not layout.is_empty(): result["virtual_transparent_layout"] = layout
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
