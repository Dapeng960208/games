extends RefCounted
## B06 candidate-only source registry. Native pixels and authored geometry stay
## unchanged. Presentation points must never become damage/collision origins.
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const ROOT := "asset://b06_native_v1/"
static var _manifest: Dictionary = {}
static var _loaded := false

static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT + "manifest.json")))
		if parsed is Dictionary: _manifest = parsed
	return _manifest

static func identities() -> Array:
	return manifest().get("identities", {}).keys()

static func frame(identity: String, pose: String = "idle") -> Dictionary:
	var spec: Dictionary = manifest().get("identities", {}).get(identity, {})
	var source: Dictionary = spec.get("frames", {}).get(pose, {})
	if source.is_empty(): return {}
	var path: String = ROOT + str(source.texture)
	var texture: Texture2D = Sampler.sampled(path)
	if texture == null: return {}
	return {"name":pose,"texture":texture,"texture_path":path,
		"region":Rect2(float(source.region[0]),float(source.region[1]),float(source.region[2]),float(source.region[3])),
		"foot":Vector2(float(source.foot[0]),float(source.foot[1])),
		"core":Vector2(float(source.core_anchor[0]),float(source.core_anchor[1])),
		"outlet":Vector2(float(source.visual_outlet[0]),float(source.visual_outlet[1])),
		"source_pose_scale":float(source.get("source_pose_scale",1.0)),
		"reference_height":float(spec.reference_body_height_px),"candidate_only":true,"runtime_quality_gate_passed":false}

static func entry(identity: String) -> Dictionary:
	if not identity.begins_with("B06-M"): return {}
	var idle := frame(identity)
	if idle.is_empty(): return {}
	var bounds: Array = manifest().identities[identity].frames.idle.alpha128_bounds
	var codex_region := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3])).grow(6.0).intersection(idle.region)
	return {"texture":idle.texture,"texture_path":idle.texture_path,"region":codex_region,"foot":idle.foot,
		"source_height":idle.reference_height,"source_family":"storybook_2_5d_v1","biome_id":"B06","visual_clan":"tidal",
		"individual_body":true,"b06_native_bank":true,"runtime_quality_gate_passed":false}

static func bank(identity: String) -> Dictionary:
	if not identity.begins_with("B06-M"): return {}
	var clips: Dictionary = {}
	for pose: String in ["idle","telegraph","execute"]:
		var value := frame(identity,pose)
		if value.is_empty(): return {}
		clips[pose] = [value]
	clips["locked"] = clips.telegraph
	clips["walk"] = clips.idle
	clips["recovery"] = clips.idle
	return {"clips":clips,"texture":clips.idle[0].texture,"body_height":clips.idle[0].reference_height,
		"source_family":"storybook_2_5d_v1","facing":"right","b06_native_bank":true,"runtime_quality_gate_passed":false}

static func boss_frame(action_id: String, stage: String, exposed: bool = false, defeated: bool = false) -> Dictionary:
	var pose := "idle"
	if defeated: pose = "defeated"
	elif exposed: pose = "exposed"
	elif action_id in ["siege_claw","return_pincer","dual_cannon","shell_bombard","tidal_wall"] and stage in ["telegraph","locked","release","execute"]:
		var family := "melee" if action_id in ["siege_claw","return_pincer"] else "cannon"
		if action_id != "coral_escort": pose = family + ("-execute" if stage in ["release","execute"] else "-telegraph")
	return frame("BO06",pose)

static func prop_frame(identity: String) -> Dictionary:
	if identity not in ["drain_gate","reef_pillar","tide_clock"]: return {}
	return frame(identity)

static func placement(value: Dictionary, ground: Vector2, height: float, mirrored: bool = false) -> Dictionary:
	if value.is_empty() or height <= 0.0: return {}
	var factor: float = height / float(value.reference_height) * float(value.get("source_pose_scale",1.0))
	var foot: Vector2 = value.foot
	var region: Rect2 = value.region
	var core: Vector2 = (Vector2(value.core) - foot) * factor
	var outlet: Vector2 = (Vector2(value.outlet) - foot) * factor
	var offset: Vector2 = (region.position - foot) * factor
	var size: Vector2 = region.size * factor
	if mirrored:
		offset.x = -offset.x
		size.x = -size.x
		core.x = -core.x
		outlet.x = -outlet.x
	return {"bounds":Rect2(ground + offset,size),"core":ground + core,"outlet":ground + outlet,"ground":ground,"scale":factor,"pose":value.name,"texture_path":value.texture_path}

static func draw_frame(canvas: CanvasItem, value: Dictionary, ground: Vector2, height: float, mirrored: bool = false) -> Dictionary:
	var mapped := placement(value,ground,height,mirrored)
	if mapped.is_empty(): return {}
	canvas.draw_texture_rect_region(value.texture,mapped.bounds,value.region)
	return mapped
