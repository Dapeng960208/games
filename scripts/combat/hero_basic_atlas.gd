class_name HeroBasicAtlas
extends RefCounted
## Authored basic-attack poses follow committed HeroFeedback phases. This
## sampler owns no clocks and cannot change damage, attack speed or cooldowns.

const BODY_HEIGHT := 88.0
const FOOT := Vector2(0, 8)
const ArtFamily = preload("res://scripts/combat/hero_art_family.gd")
const FRAME_NAMES: Array[String] = ["lift", "loaded", "downswing", "contact", "recoil", "ready"]
const PHASES: Array[String] = ["windup", "release", "recovery"]
static var _clips: Dictionary = {}

static func frame_info(hero: String, bank: String, phase: String, progress: float) -> Dictionary:
	if hero != "CH01" or bank not in ["front", "back"]:
		return {}
	var replacement: String = ArtFamily.metadata_path(hero,"basic",bank)
	var path: String = replacement if not replacement.is_empty() else "res://assets/generated/heroes/%s_basic_%s_v1.json" % [hero, bank]
	var clip: Dictionary = load_clip(path)
	if str(clip.get("bank", "")) != bank:
		return {}
	return sample_clip(clip, phase, progress)

static func sample_clip(clip: Dictionary, phase: String, progress: float) -> Dictionary:
	if clip.is_empty() or not clip.get("phases", {}).has(phase) or not is_finite(progress):
		return {}
	var sequence: Array = clip.phases[phase]
	var weights: Array = clip.weights[phase]
	var total: float = float(clip.weight_totals[phase])
	var position: float = clampf(progress, 0.0, 1.0) * total
	var boundary: float = 0.0
	var selected: int = sequence.size() - 1
	for index in sequence.size():
		boundary += float(weights[index])
		if position < boundary:
			selected = index
			break
	var frame: Dictionary = clip.frames[str(sequence[selected])].duplicate(true)
	frame["phase"] = phase
	frame["clip_frame"] = selected
	frame["phase_progress"] = clampf(progress, 0.0, 1.0)
	frame["basic_sequence"] = true
	return frame

static func load_clip(metadata_path: String) -> Dictionary:
	if _clips.has(metadata_path):
		return _clips[metadata_path]
	# Cache rejected/missing clips too: fallback must not re-open files per draw.
	_clips[metadata_path] = {}
	if not FileAccess.file_exists(metadata_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	if typeof(data.get("enabled")) != TYPE_BOOL or data.enabled != true:
		return {}
	var schema: Variant = data.get("schema_version", data.get("schema", 0))
	if not _number(schema) or float(schema) != 1.0 or str(data.get("hero_id", "")) != "CH01" or str(data.get("bank", "")) not in ["front", "back"]:
		return {}
	var height: Variant = data.get("body_height")
	if not _number(height) or float(height) <= 0.0:
		return {}
	var definitions: Variant = data.get("frames")
	var phases: Variant = data.get("phase_frames")
	var weights: Variant = data.get("phase_weights")
	if not definitions is Array or definitions.size() != FRAME_NAMES.size() or not phases is Dictionary or not weights is Dictionary:
		return {}
	var path: String = str(data.get("texture", ""))
	var texture: Texture2D = _load_texture(path)
	if texture == null:
		return {}
	var frames: Dictionary = {}
	for index in definitions.size():
		var item: Variant = definitions[index]
		if not item is Dictionary or str(item.get("name", "")) not in FRAME_NAMES or frames.has(str(item.name)):
			return {}
		if not _coordinates(item.get("region"), 4):
			return {}
		var region := Rect2(float(item.region[0]), float(item.region[1]), float(item.region[2]), float(item.region[3]))
		if region.size.x <= 0.0 or region.size.y <= 0.0 or not Rect2(Vector2.ZERO, texture.get_size()).encloses(region):
			return {}
		for label: String in ["foot", "head", "grip", "muzzle"]:
			if not _coordinates(item.get(label), 2):
				return {}
		var foot := Vector2(float(item.foot[0]), float(item.foot[1]))
		var scale_value: float = BODY_HEIGHT / float(height)
		var anchors: Dictionary = {"foot":FOOT}
		for label: String in ["head", "grip", "muzzle"]:
			anchors[label] = (Vector2(float(item[label][0]), float(item[label][1])) - foot) * scale_value + FOOT
		frames[str(item.name)] = {"texture":texture, "path":path, "region":region,
			"bounds":Rect2((region.position - foot) * scale_value + FOOT, region.size * scale_value),
			"anchors":anchors, "bank":str(data.bank), "frame_index":index, "frame_name":str(item.name),
			"body_height":BODY_HEIGHT, "source_body_height":float(height), "facing_x":-1 if int(data.get("facing_x",1)) < 0 else 1}
	var weight_totals: Dictionary = {}
	var expected_phases: Dictionary = {"windup":["lift", "loaded", "downswing"], "release":["contact"], "recovery":["recoil", "ready"]}
	for phase: String in PHASES:
		var sequence: Variant = phases.get(phase)
		var phase_weights: Variant = weights.get(phase)
		if not sequence is Array or sequence != expected_phases[phase] or not phase_weights is Array or phase_weights.size() != sequence.size():
			return {}
		var total: float = 0.0
		for index in sequence.size():
			if not frames.has(str(sequence[index])) or not _number(phase_weights[index]) or float(phase_weights[index]) <= 0.0:
				return {}
			total += float(phase_weights[index])
		if not is_finite(total) or total <= 0.0:
			return {}
		weight_totals[phase] = total
	var clip: Dictionary = {"hero_id":str(data.hero_id), "bank":str(data.bank), "frames":frames,
		"phases":phases.duplicate(true), "weights":weights.duplicate(true), "weight_totals":weight_totals}
	_clips[metadata_path] = clip
	return clip

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _coordinates(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for component: Variant in value:
		if not _number(component):
			return false
	return true

static func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or (not ResourceLoader.exists(path) and not FileAccess.file_exists(path)):
		return null
	var resource: Resource = load(path) if ResourceLoader.exists(path) else null
	if resource != null and not resource is Texture2D:
		return null
	var texture: Texture2D = resource as Texture2D
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(path)
	if source == null or source.is_empty():
		return null
	if not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	elif texture == null:
		texture = ImageTexture.create_from_image(source)
	return texture
