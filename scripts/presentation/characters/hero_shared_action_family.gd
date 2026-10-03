class_name HeroSharedActionFamily
extends RefCounted
## A complete new identity with eight authored views and eight shared body poses.
## Skill effects retain their own production timelines; this is not a claim of
## twelve separately drawn eight-frame skill clips.

const ROOT := "asset://heroes/"
const HEIGHT := preload("res://scripts/shared/presentation_metrics.gd").HERO_BODY_HEIGHT
const FOOT := Vector2(0,8)
const DIRECTIONS := ["E","SE","S","SW","W","NW","N","NE"]
const POSES := ["idle","walk_left","walk_right","basic_windup","basic_release","basic_recovery","dash","guard_cast"]
const SKILL_ACTIONS := {
	"CH01":["dash","basic","guard_cast","basic","basic","guard_cast","basic","guard_cast","basic","guard_cast","basic","basic"],
	"CH02":["basic","basic","guard_cast","basic","basic","dash","basic","guard_cast","basic","guard_cast","basic","guard_cast"],
	"CH03":["basic","basic","guard_cast","guard_cast","basic","guard_cast","basic","guard_cast","basic","guard_cast","guard_cast","dash"]
}
static var _families: Dictionary = {}
static var _textures: Dictionary = {}

static func load_family(hero: String) -> Dictionary:
	if _families.has(hero): return _families[hero]
	_families[hero] = {}
	if not SKILL_ACTIONS.has(hero): return {}
	var path: String = AssetCatalog.resolve(ROOT+hero.to_lower()+"_action_family.json")
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return {}
	var family: Dictionary = validate_family(data,hero)
	if not family.is_empty(): _families[hero] = family
	return family

## Validation also accepts already decoded textures for isolated source checks.
## Every direction is admitted together, never a mixture with a legacy actor.
static func validate_family(data: Dictionary, hero: String, decoded: Dictionary = {}) -> Dictionary:
	if not SKILL_ACTIONS.has(hero) or data.get("schema_version") != 3 or data.get("hero_id") != hero or typeof(data.get("enabled")) != TYPE_BOOL or typeof(data.get("production_ready")) != TYPE_BOOL or data.get("enabled") != true or data.get("production_ready") != true: return {}
	var directions: Variant = data.get("directions")
	if not directions is Dictionary or directions.size() != DIRECTIONS.size(): return {}
	var result: Dictionary = {}
	var used_regions: Dictionary = {}
	for key: String in DIRECTIONS:
		var group: Variant = directions.get(key)
		if not group is Dictionary or not _positive(group.get("reference_body_height")) or float(group.reference_body_height) < 256.0: return {}
		var sources: Variant = group.get("frames")
		if not sources is Array or sources.size() != POSES.size(): return {}
		var scale_value: float = HEIGHT/float(group.reference_body_height)
		var frames: Dictionary = {}
		for index: int in POSES.size():
			var source: Variant = sources[index]
			if not source is Dictionary or source.get("name") != POSES[index] or not _coordinates(source.get("region"),4) or not _positive(source.get("body_height")): return {}
			var texture_path: String = str(source.get("texture",""))
			if texture_path not in [ROOT+hero.to_lower()+"_poses_"+key.to_lower()+"_a.png",ROOT+hero.to_lower()+"_poses_"+key.to_lower()+"_b.png"]: return {}
			var texture: Texture2D = decoded.get(texture_path) if decoded.has(texture_path) else _texture(texture_path)
			if texture == null or texture.get_width() > 2048 or texture.get_height() > 2048: return {}
			var region := Rect2(float(source.region[0]),float(source.region[1]),float(source.region[2]),float(source.region[3]))
			if not region.has_area() or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return {}
			if not used_regions.has(texture_path): used_regions[texture_path] = []
			for previous: Rect2 in used_regions[texture_path]:
				if previous.intersects(region): return {}
			used_regions[texture_path].append(region)
			for required: String in ["foot","head","grip","muzzle"]:
				if not _coordinates(source.get(required),2) or not region.has_point(Vector2(float(source[required][0]),float(source[required][1]))): return {}
			var foot := Vector2(float(source.foot[0]),float(source.foot[1]))
			var anchors: Dictionary = {"foot":FOOT}
			for anchor: String in ["head","grip","muzzle","left_hand","right_hand","wand","pet"]:
				var raw: Variant = source.get(anchor,source.grip if anchor in ["left_hand","right_hand"] else source.muzzle)
				if not _coordinates(raw,2) or not region.has_point(Vector2(float(raw[0]),float(raw[1]))): return {}
				anchors[anchor] = (Vector2(float(raw[0]),float(raw[1]))-foot)*scale_value+FOOT
			frames[POSES[index]] = {"texture":texture,"path":texture_path,"region":region,"bounds":Rect2((region.position-foot)*scale_value+FOOT,region.size*scale_value),"anchors":anchors,"hero_id":hero,"direction_key":key,"bank":key,"frame_index":DIRECTIONS.find(key)*8+index,"frame_name":POSES[index],"frame_count":8,"body_height":HEIGHT,"source_body_height":float(source.body_height),"source_reference_body_height":float(group.reference_body_height),"facing_x":1,"directional_sequence":true,"articulated_clip":true,"art_family":"shared_action"}
		result[key] = frames
	return {"hero_id":hero,"directions":result}

static func frame_info(hero: String, direction: Vector2, phase: String, progress: float, action: String) -> Dictionary:
	return sample_family(load_family(hero),direction,phase,progress,action)

static func sample_family(family: Dictionary, direction: Vector2, phase: String, progress: float, action: String) -> Dictionary:
	if family.is_empty() or not is_finite(progress): return {}
	var hero: String = str(family.hero_id)
	var category: String = action
	if action.begins_with(hero+"_SK"):
		var index: int = int(action.trim_prefix(hero+"_SK"))-1
		if index < 0 or index >= 12 or action != "%s_SK%02d" % [hero,index+1]: return {}
		category = str(SKILL_ACTIONS[hero][index])
	elif action not in ["idle","walk","dash","basic","reload","guard_cast"]: return {}
	if action == "reload" and hero != "CH02": return {}
	var normalized: float = clampf(progress,0.0,1.0)
	var pose: String = "idle"
	if action == "walk": pose = "walk_left" if normalized < .5 else "walk_right"
	elif action == "dash": pose = "dash"
	elif action == "reload": pose = "guard_cast" if normalized < .85 else "idle"
	elif action == "idle": pose = "idle"
	elif phase in ["windup","release","recovery"]:
		if category == "guard_cast": pose = "guard_cast" if phase == "release" else "basic_"+phase
		elif category == "dash": pose = "dash" if phase == "release" else "basic_"+phase
		else: pose = "basic_"+phase
	else: return {}
	var key: String = "E" if not direction.is_finite() or direction.is_zero_approx() else DIRECTIONS[posmod(roundi(direction.angle()/(PI/4.0)),8)]
	var frame: Dictionary = family.directions[key][pose].duplicate()
	frame.merge({"phase":"walk" if action == "walk" else "dodge" if action == "dash" else phase,"phase_progress":normalized,"action":action,"body_action":category,"clip_frame":POSES.find(pose),"dodge_presentation":action == "dash","basic_sequence":action == "basic","skill_sequence":action not in ["idle","walk","reload"]},true)
	return frame

static func _texture(path: String) -> Texture2D:
	if _textures.has(path): return _textures[path]
	_textures[path] = null
	var resolved: String = AssetCatalog.resolve(path)
	if not FileAccess.file_exists(resolved) and not ResourceLoader.exists(resolved): return null
	var texture: Texture2D = load(resolved) if ResourceLoader.exists(resolved) else null
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(resolved)
	if source == null or source.is_empty(): return null
	if source.is_compressed() and source.decompress() != OK: return null
	if not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	elif texture == null: texture = ImageTexture.create_from_image(source)
	_textures[path] = texture
	return texture

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0

static func _coordinates(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for component: Variant in value:
		if not component is int and not component is float or not is_finite(float(component)): return false
	return true
