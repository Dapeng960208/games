class_name HeroDirectionalAtlas
extends RefCounted
## Authored eight-way attack bodies. A complete validated family is enabled
## atomically; partial pilots cannot silently masquerade as eight-way coverage.
const ROOT := "asset://heroes/"
const HEIGHT := preload("res://scripts/shared/presentation_metrics.gd").HERO_BODY_HEIGHT
const FOOT := Vector2(0,8)
const DIRECTIONS := ["E","SE","S","SW","W","NW","N","NE"]
const PHASES := ["windup","release","recovery"]
const SharedActionFamily = preload("res://scripts/presentation/characters/hero_shared_action_family.gd")
static var _families: Dictionary = {}
static var _textures: Dictionary = {}
static var _combat_clips: Dictionary = {}

static func direction_key(direction: Vector2) -> String:
	if not direction.is_finite() or direction.is_zero_approx(): return "E"
	return DIRECTIONS[posmod(roundi(direction.angle()/(PI/4.0)),8)]

static func frame_info(hero: String, direction: Vector2, phase: String, progress: float = 0.0, action: String = "basic") -> Dictionary:
	if not is_finite(progress): return {}
	var authored: Dictionary = combat_frame_info(hero,direction,phase,progress,action)
	if not authored.is_empty(): return authored
	if phase not in PHASES: return {}
	var family := load_family(hero)
	if family.is_empty(): return {}
	var frame: Dictionary = family[direction_key(direction)][phase].duplicate(true)
	frame["phase"] = phase
	frame["phase_progress"] = clampf(progress,0,1)
	frame["directional_sequence"] = true
	return frame

## New finite clips share committed phase progress with the combat timeline.
## Each view owns eight authored poses; no body rotation or animation clock can
## advance a skill, make damage, or choose a different target.
static func combat_frame_info(hero: String, direction: Vector2, phase: String, progress: float, action: String) -> Dictionary:
	if not is_finite(progress): return {}
	var clips: Dictionary = load_combat_clips(hero)
	if clips.is_empty(): return SharedActionFamily.frame_info(hero,direction,phase,progress,action)
	if not clips.has(action): return {}
	var clip: Dictionary = clips[action]
	var key: String = direction_key(direction)
	var sequence: Array = clip.directions[key]
	var indices: Array = clip.phases.get(phase,[])
	if action in ["idle","walk","dash","reload"]:
		indices = [0,1,2,3,4,5,6,7]
	if indices.is_empty(): return {}
	var normalized: float = clampf(progress,0.0,1.0)
	var ordinal: int = mini(indices.size()-1,floori(normalized*indices.size()))
	var frame: Dictionary = sequence[int(indices[ordinal])].duplicate(true)
	frame["phase"] = "dodge" if action == "dash" else "walk" if action == "walk" else phase
	frame["phase_progress"] = normalized
	frame["clip_frame"] = int(indices[ordinal])
	frame["action"] = action
	frame["dodge_presentation"] = action == "dash"
	frame["basic_sequence"] = action == "basic"
	return frame

static func load_combat_clips(hero: String) -> Dictionary:
	if _combat_clips.has(hero): return _combat_clips[hero]
	_combat_clips[hero] = {}
	if hero not in ["CH01","CH02","CH03"]: return {}
	var path: String = ROOT+hero.to_lower()+"_combat_clips.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(path)): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	if not data is Dictionary or data.get("schema_version") != 2 or data.get("hero_id") != hero or data.get("enabled") != true or data.get("production_ready") != true or not data.get("clips") is Dictionary: return {}
	var result: Dictionary = {}
	for action: String in data.clips:
		var raw: Variant = data.clips[action]
		if not raw is Dictionary or not raw.get("directions") is Dictionary or raw.directions.size() != 8 or not raw.get("phases") is Dictionary: return {}
		var phases: Dictionary = raw.phases
		if phases.get("windup") != [0,1,2] or phases.get("release") != [3,4] or phases.get("recovery") != [5,6,7]: return {}
		var directions: Dictionary = {}
		for key: String in DIRECTIONS:
			var group: Variant = raw.directions.get(key)
			if not group is Dictionary or not group.get("frames") is Array or group.frames.size() != 8: return {}
			var texture_path: String = str(group.get("texture",raw.get("texture","")))
			if not texture_path.begins_with(ROOT+hero.to_lower()+"_") or not texture_path.ends_with(".png"): return {}
			var texture: Texture2D = _texture(texture_path)
			if texture == null or texture.get_width() > 2048 or texture.get_height() > 2048: return {}
			# One standing reference for the whole directional clip keeps crouched
			# and airborne poses at their authored size instead of enlarging them.
			if not _number(group.get("reference_body_height")) or float(group.reference_body_height) < 448.0: return {}
			var scale_value: float = HEIGHT/float(group.reference_body_height)
			var frames: Array[Dictionary] = []
			for index: int in group.frames.size():
				var source: Variant = group.frames[index]
				if not source is Dictionary or not _coordinates(source.get("region"),4) or not _number(source.get("body_height")) or float(source.body_height) < 448.0: return {}
				var region := Rect2(float(source.region[0]),float(source.region[1]),float(source.region[2]),float(source.region[3]))
				if not region.has_area() or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return {}
				if not _coordinates(source.get("foot"),2): return {}
				var foot := Vector2(float(source.foot[0]),float(source.foot[1]))
				if not region.has_point(foot): return {}
				var anchors: Dictionary = {"foot":FOOT}
				for anchor: String in ["head","grip","muzzle","left_hand","right_hand","wand","pet"]:
					if not _coordinates(source.get(anchor),2): return {}
					var point := Vector2(float(source[anchor][0]),float(source[anchor][1]))
					if not region.has_point(point): return {}
					anchors[anchor] = (point-foot)*scale_value+FOOT
				frames.append({"texture":texture,"path":texture_path,"region":region,"bounds":Rect2((region.position-foot)*scale_value+FOOT,region.size*scale_value),"anchors":anchors,"hero_id":hero,"direction_key":key,"bank":key,"frame_index":DIRECTIONS.find(key)*8+index,"frame_name":str(source.get("name",key+"_"+str(index))),"frame_count":8,"body_height":HEIGHT,"source_body_height":float(source.body_height),"facing_x":1,"directional_sequence":true,"skill_sequence":true,"articulated_clip":true})
			directions[key] = frames
		result[action] = {"directions":directions,"phases":phases.duplicate(true)}
	for required: String in ["idle","walk","dash","basic"]:
		if not result.has(required): return {}
	if hero == "CH02" and not result.has("reload"): return {}
	for index in range(1,13):
		if not result.has("%s_SK%02d" % [hero,index]): return {}
	_combat_clips[hero] = result
	return result

static func load_family(hero: String) -> Dictionary:
	if _families.has(hero): return _families[hero]
	_families[hero] = {}
	if hero not in ["CH01","CH02","CH03"]: return {}
	var path := ROOT+hero+"_directional_v1.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(path)): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("hero_id") != hero or data.get("enabled") != true or not data.get("directions") is Dictionary: return {}
	if data.directions.size() != 8: return {}
	var result := {}
	var used_regions := {}
	for index: int in DIRECTIONS.size():
		var key: String = DIRECTIONS[index]
		var group: Variant = data.directions.get(key)
		if not group is Dictionary or not group.get("frames") is Dictionary or group.frames.size() != 3: return {}
		var frames := {}
		for phase: String in PHASES:
			var source: Variant = group.frames.get(phase)
			if not source is Dictionary: return {}
			var texture_path := str(source.get("texture",""))
			if not texture_path.begins_with(ROOT+hero+"_directional_") or not texture_path.ends_with(".png"): return {}
			var texture := _texture(texture_path)
			if texture == null or not _coordinates(source.get("region"),4): return {}
			var raw: Array = source.region
			var region := Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
			if not region.has_area() or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return {}
			if not used_regions.has(texture_path): used_regions[texture_path] = []
			for previous: Rect2 in used_regions[texture_path]:
				if previous.intersects(region): return {}
			used_regions[texture_path].append(region)
			var height: Variant = source.get("body_height")
			if not _number(height) or float(height)<320.0: return {}
			for anchor: String in ["foot","head","grip","muzzle"]:
				if not _coordinates(source.get(anchor),2): return {}
				if not region.has_point(Vector2(float(source[anchor][0]),float(source[anchor][1]))): return {}
			var axis := Vector2.ZERO
			if source.has("weapon_axis"):
				if not _coordinates(source.weapon_axis,2): return {}
				axis = Vector2(float(source.weapon_axis[0]),float(source.weapon_axis[1]))
			if hero in ["CH02","CH03"] and phase == "release":
				if axis.is_zero_approx() or axis.normalized().dot(Vector2.from_angle(index*PI/4.0))<.95: return {}
			var foot := Vector2(float(source.foot[0]),float(source.foot[1]))
			var scale_value := HEIGHT/float(height)
			var anchors := {"foot":FOOT}
			for anchor: String in ["head","grip","muzzle"]:
				anchors[anchor] = (Vector2(float(source[anchor][0]),float(source[anchor][1]))-foot)*scale_value+FOOT
			frames[phase] = {"texture":texture,"path":texture_path,"region":region,"bounds":Rect2((region.position-foot)*scale_value+FOOT,region.size*scale_value),"anchors":anchors,"bank":key,"direction_key":key,"frame_index":index*3+PHASES.find(phase),"frame_name":key+"_"+phase,"body_height":HEIGHT,"source_body_height":float(height),"facing_x":1,"weapon_axis":axis,"directional_sequence":true,"skill_sequence":true}
		result[key] = frames
	_families[hero] = result
	return result

static func _texture(path: String) -> Texture2D:
	if _textures.has(path): return _textures[path]
	_textures[path] = null
	if not FileAccess.file_exists(AssetCatalog.resolve(path)) and not ResourceLoader.exists(AssetCatalog.resolve(path)): return null
	var texture: Texture2D = load(AssetCatalog.resolve(path)) if ResourceLoader.exists(AssetCatalog.resolve(path)) else null
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(AssetCatalog.resolve(path))
	if source == null or source.is_empty(): return null
	if not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	elif texture == null: texture = ImageTexture.create_from_image(source)
	_textures[path] = texture
	return texture

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _coordinates(value: Variant, size: int) -> bool:
	if not value is Array or value.size()!=size: return false
	for component: Variant in value:
		if not _number(component): return false
	return true
