extends RefCounted
## Each body uses native pixels with a single uniform reduction. No stretch or
## pixel enlargement: the ground foot and contact mask share this exact bounds.
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
static var _frames: Dictionary = {}

static func frame(id: String) -> Dictionary:
	if id == "B10-CORE": return props_frame("star_core")
	return _frame(id, Skills.art_id(id), 300.0 if id=="BO10" else 218.0 if Skills.is_boss(id) else 112.0)

static func props_frame(key: String) -> Dictionary:
	var heights := {"stargate":96.0, "star_core":70.0, "survey_spire":140.0, "triune_obelisk":180.0}
	if not heights.has(key): return {}
	return _frame("prop:"+key, "asset://level.b10.decorations."+key, float(heights[key]))

static func _frame(id: String, path: String, height: float) -> Dictionary:
	if _frames.has(id): return _frames[id]
	if not FileAccess.file_exists(AssetCatalog.resolve(path)) and not ResourceLoader.exists(AssetCatalog.resolve(path)): return {}
	var texture: Texture2D = Sampler.sampled(path)
	if texture==null: return {}
	var size := texture.get_size()
	var source := _source_metadata(path)
	var effective_height := float(source.get("effective_body_height_px", size.y))
	var factor := minf(1.0,height/maxf(1.0,effective_height))
	var foot := size*Vector2(.5,.84)
	var point: Array = source.get("actual_foot_px", [])
	if point.size()==2:
		foot = Vector2(float(point[0]),float(point[1]))
	else:
		point = source.get("observed_footpoint_estimate", source.get("foot_point_normalized", []))
		if point.size()==2: foot=size*Vector2(float(point[0]),float(point[1]))
	if not foot.is_finite() or not Rect2(Vector2.ZERO,size).has_point(foot): return {}
	var value := {"texture":texture,"region":Rect2(Vector2.ZERO,size),"bounds":Rect2(-foot*factor,size*factor),"name":"idle","texture_path":path,"full_color":true,"source_family":"b10_bright_handpainted_2_5d","scale":factor,"foot":Vector2.ZERO,"source_foot_px":foot,"native_dimensions":size,"source_metadata":source}
	_frames[id]=value
	return value

static func _source_metadata(path: String) -> Dictionary:
	var resolved := AssetCatalog.resolve(path)
	var directory := resolved.get_base_dir()
	var key := resolved.get_file().get_basename()
	for filename: String in [key+".prompt.provenance.json", key+".provenance.json", "provenance.json", "prompt.provenance.json", "body.provenance.json"]:
		var metadata_path := directory.path_join(filename)
		if not FileAccess.file_exists(metadata_path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if parsed is Dictionary:
			if parsed.get("assets") is Dictionary: return parsed.assets.get(key, {})
			return parsed
	return {}
