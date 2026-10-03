class_name HeroSkillAtlas
extends RefCounted
## Authored skill clips consume committed HeroFeedback phase progress.
## Sampling owns no clock and cannot release projectiles, detonate nodes or deal damage.

const BODY_HEIGHT := preload("res://scripts/shared/presentation_metrics.gd").HERO_BODY_HEIGHT
const FOOT := Vector2(0, 8)
const ArtFamily = preload("res://scripts/presentation/characters/hero_art_family.gd")
const PHASES: Array[String] = ["windup", "release", "recovery"]
const SKILLS: Dictionary = {
	"CH01:secondary": {
		"frames":["plant", "coil", "drive", "contact", "follow", "ready"],
		"phases":{"windup":["plant", "coil", "drive"], "release":["contact"], "recovery":["follow", "ready"]},
		"anchors":["head", "grip", "muzzle"]
	},
	"CH02:secondary": {
		"frames":["shoulder", "brace", "lock", "fire", "absorb", "ready"],
		"phases":{"windup":["shoulder", "brace", "lock"], "release":["fire"], "recovery":["absorb", "ready"]},
		"anchors":["head", "grip", "muzzle"]
	},
	"CH03:f": {
		"frames":["gather", "tune", "command", "contract", "release_core", "ready"],
		"phases":{"windup":["gather", "tune"], "release":["command"], "recovery":["contract", "release_core", "ready"]},
		"anchors":["head", "grip", "muzzle", "core", "left_hand", "right_hand"]
	}
}
static var _clips: Dictionary = {}

static func frame_info(hero: String, slot: String, bank: String, phase: String, progress: float) -> Dictionary:
	if not SKILLS.has(hero+":"+slot) or bank not in ["front", "back"]:
		return {}
	var replacement: String = ArtFamily.metadata_path(hero,slot,bank)
	if hero == "CH01" and replacement.is_empty(): return {}
	var path: String = replacement if not replacement.is_empty() else "asset://heroes/%s_%s_%s_v1.json" % [hero, slot, bank]
	var clip: Dictionary = load_clip(path)
	if str(clip.get("hero_id", "")) != hero or str(clip.get("slot", "")) != slot or str(clip.get("bank", "")) != bank:
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
	frame["phase_frame_count"] = sequence.size()
	frame["phase_progress"] = clampf(progress, 0.0, 1.0)
	frame["skill_sequence"] = true
	return frame

static func load_clip(metadata_path: String) -> Dictionary:
	if _clips.has(metadata_path):
		return _clips[metadata_path]
	# Missing, disabled and rejected candidates use the established pose fallback.
	# Cache failure as well so the renderer never retries disk access every frame.
	_clips[metadata_path] = {}
	if not FileAccess.file_exists(AssetCatalog.resolve(metadata_path)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(metadata_path)))
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	if typeof(data.get("enabled")) != TYPE_BOOL or data.enabled != true:
		return {}
	var schema: Variant = data.get("schema_version")
	if not _number(schema) or float(schema) != 1.0:
		return {}
	for label: String in ["hero_id", "slot", "bank", "texture"]:
		if typeof(data.get(label)) != TYPE_STRING:
			return {}
	var identity: String = str(data.hero_id)+":"+str(data.slot)
	if not SKILLS.has(identity) or str(data.bank) not in ["front", "back"]:
		return {}
	var contract: Dictionary = SKILLS[identity]
	var height: Variant = data.get("body_height")
	if not _number(height) or float(height) <= 0.0:
		return {}
	var definitions: Variant = data.get("frames")
	var phases: Variant = data.get("phase_frames")
	var weights: Variant = data.get("phase_weights")
	if not definitions is Array or definitions.size() != 6 or not phases is Dictionary or not weights is Dictionary:
		return {}
	if phases.size() != PHASES.size() or weights.size() != PHASES.size():
		return {}
	var weight_totals: Dictionary = {}
	for phase: String in PHASES:
		var sequence: Variant = phases.get(phase)
		var phase_weights: Variant = weights.get(phase)
		if not sequence is Array or sequence != contract.phases[phase] or not phase_weights is Array or phase_weights.size() != sequence.size():
			return {}
		var total: float = 0.0
		for weight: Variant in phase_weights:
			if not _number(weight) or float(weight) <= 0.0:
				return {}
			total += float(weight)
		if not is_finite(total) or total <= 0.0:
			return {}
		weight_totals[phase] = total
	var path: String = str(data.texture)
	var texture: Texture2D = _load_texture(path)
	if texture == null:
		return {}
	var frames: Dictionary = {}
	for index in definitions.size():
		var item: Variant = definitions[index]
		if not item is Dictionary or typeof(item.get("name")) != TYPE_STRING:
			return {}
		var frame_name: String = str(item.name)
		if frame_name not in contract.frames or frames.has(frame_name) or not _coordinates(item.get("region"), 4):
			return {}
		var region := Rect2(float(item.region[0]), float(item.region[1]), float(item.region[2]), float(item.region[3]))
		if region.size.x <= 0.0 or region.size.y <= 0.0 or not Rect2(Vector2.ZERO, texture.get_size()).encloses(region):
			return {}
		if not _coordinates(item.get("foot"), 2):
			return {}
		var foot := Vector2(float(item.foot[0]), float(item.foot[1]))
		# The bank's anatomy scale is shared by every frame, including crouches.
		var scale_value: float = BODY_HEIGHT / float(height)
		var anchors: Dictionary = {"foot":FOOT}
		for label: String in contract.anchors:
			if not _coordinates(item.get(label), 2):
				return {}
			anchors[label] = (Vector2(float(item[label][0]), float(item[label][1])) - foot) * scale_value + FOOT
		frames[frame_name] = {"texture":texture, "path":path, "region":region,
			"bounds":Rect2((region.position - foot) * scale_value + FOOT, region.size * scale_value),
			"anchors":anchors, "hero_id":str(data.hero_id), "slot":str(data.slot), "bank":str(data.bank),
			"frame_index":index, "frame_name":frame_name, "frame_count":6,
			"body_height":BODY_HEIGHT, "source_body_height":float(height), "facing_x":-1 if int(data.get("facing_x",1)) < 0 else 1}
	var clip: Dictionary = {"hero_id":str(data.hero_id), "slot":str(data.slot), "bank":str(data.bank), "frames":frames,
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
	if path.is_empty() or (not ResourceLoader.exists(AssetCatalog.resolve(path)) and not FileAccess.file_exists(AssetCatalog.resolve(path))):
		return null
	var resource: Resource = load(AssetCatalog.resolve(path)) if ResourceLoader.exists(AssetCatalog.resolve(path)) else null
	if resource != null and not resource is Texture2D:
		return null
	var texture: Texture2D = resource as Texture2D
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(AssetCatalog.resolve(path))
	if source == null or source.is_empty():
		return null
	if not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	elif texture == null:
		texture = ImageTexture.create_from_image(source)
	return texture
