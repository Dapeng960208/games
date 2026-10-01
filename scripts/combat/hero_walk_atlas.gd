class_name HeroWalkAtlas
extends RefCounted
## Read-only raster clip sampling. Distance is world travel, never elapsed time.
## The two authored view banks retain HeroVisual's existing mirror contract.

const BODY_HEIGHT := preload("res://scripts/combat/presentation_metrics.gd").HERO_BODY_HEIGHT
const FOOT := Vector2(0,8)
const ArtFamily = preload("res://scripts/combat/hero_art_family.gd")
static var _clips: Dictionary = {}

static func frame_info(hero: String, bank: String = "front", distance: float = 0.0) -> Dictionary:
	var replacement: String = ArtFamily.metadata_path(hero,"walk")
	var path: String = replacement if not replacement.is_empty() else "res://assets/generated/heroes/%s_walk_v1.json" % hero
	return sample_clip(load_clip(path),bank,distance)

static func sample_clip(clip: Dictionary, bank: String, distance: float) -> Dictionary:
	if clip.is_empty() or not clip.banks.has(bank) or not is_finite(distance):
		return {}
	var sequence: Array = clip.banks[bank]
	var phase: float = fposmod(maxf(0.0,distance),float(clip.cycle_distance))/float(clip.cycle_distance)
	var ordinal: int = mini(sequence.size()-1,int(floor(phase*sequence.size())))
	var frame: Dictionary = sequence[ordinal].duplicate(true)
	frame["bank"] = bank
	frame["clip_frame"] = ordinal
	frame["frame_count"] = sequence.size()
	frame["cycle_distance"] = clip.cycle_distance
	return frame

static func load_clip(metadata_path: String) -> Dictionary:
	if _clips.has(metadata_path):
		return _clips[metadata_path]
	if not FileAccess.file_exists(metadata_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	# Generation candidates can remain documented on disk until visual review
	# accepts them. Rejected clips retain the established action/portrait fallback.
	if typeof(data.get("enabled",false)) != TYPE_BOOL or data.get("enabled",false) != true:
		_clips[metadata_path] = {}
		return {}
	var cycle_distance: float = float(data.get("cycle_distance",150.0))
	if not is_finite(cycle_distance) or cycle_distance <= 0:
		return {}
	var definitions: Dictionary = {}
	if data.has("banks") or int(data.get("schema_version",1)) == 2:
		# V2 keeps each generated image intact. Indices and source coordinates are
		# local to a bank, so front 0 and back 0 never share a decoded frame.
		var raw_banks: Variant = data.get("banks",{})
		if not raw_banks is Dictionary:
			return {}
		for bank: String in ["front","back"]:
			var raw_bank: Variant = raw_banks.get(bank,{})
			if not raw_bank is Dictionary or not raw_bank.has("texture"):
				return {}
			var definition: Dictionary = data.duplicate()
			definition.erase("banks")
			definition.merge(raw_bank,true)
			definition["columns"] = raw_bank.get("columns",4)
			definition["rows"] = raw_bank.get("rows",2)
			definition["sequence"] = raw_bank.get("sequence",[0,1,2,3,4,5,6,7])
			definitions[bank] = definition
	else:
		# Preserve the original single-atlas metadata and its global 0..15 indices.
		for bank: String in ["front","back"]:
			var definition: Dictionary = data.duplicate()
			definition["texture"] = data.get("texture",metadata_path.get_basename()+".png")
			definition["sequence"] = data.get(bank+"_frames",[0,1,2,3,4,5,6,7] if bank == "front" else [8,9,10,11,12,13,14,15])
			definitions[bank] = definition
	var banks: Dictionary = {}
	var textures: Dictionary = {}
	for bank: String in ["front","back"]:
		var frames: Array[Dictionary] = _load_bank(definitions[bank],textures)
		if frames.is_empty():
			return {}
		banks[bank] = frames
	var clip: Dictionary = {"banks":banks,"cycle_distance":cycle_distance}
	_clips[metadata_path] = clip
	return clip

static func _load_texture(path: String, textures: Dictionary) -> Texture2D:
	if textures.has(path):
		return textures[path]
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return null
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(path)
	if source == null or source.is_empty():
		return null
	if not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	elif texture == null:
		texture = ImageTexture.create_from_image(source)
	textures[path] = texture
	return texture

static func _load_bank(data: Dictionary, textures: Dictionary) -> Array[Dictionary]:
	var path: String = str(data.get("texture",""))
	var texture: Texture2D = _load_texture(path,textures)
	if texture == null:
		return []
	var columns: int = int(data.get("columns",4))
	var rows: int = int(data.get("rows",4))
	if columns < 1 or rows < 1:
		return []
	var cell_size: Vector2 = texture.get_size()/Vector2(columns,rows)
	# One anatomy-based scale per clip unless source metadata explicitly provides
	# a measured correction. Weapon width and silhouette bounds never set scale.
	var standard_height: float = float(data.get("body_height",cell_size.y*float(data.get("body_height_fraction",.72))))
	var definitions: Dictionary = {}
	var raw_frames: Variant = data.get("frames",[])
	if not raw_frames is Array:
		return []
	for ordinal in raw_frames.size():
		var item: Variant = raw_frames[ordinal]
		if item is Dictionary:
			definitions[int(item.get("index",ordinal))] = item
	var sequence: Variant = data.get("sequence",[])
	if not sequence is Array or sequence.is_empty():
		return []
	var frames: Array[Dictionary] = []
	for raw_index: Variant in sequence:
		if not raw_index is int and not raw_index is float:
			return []
		var index: int = int(raw_index)
		if index < 0 or index >= columns*rows:
			return []
		var item: Dictionary = definitions.get(index,{})
		var region := Rect2(Vector2(index%columns,floori(float(index)/columns))*cell_size,cell_size)
		if item.has("region") or item.has("cell"):
			var raw: Variant = item.get("region",item.get("cell",[]))
			if not raw is Array or raw.size() != 4:
				return []
			region = Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
		if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region):
			return []
		var height: float = float(item.get("body_height",standard_height))
		if not is_finite(height) or height <= 0:
			return []
		var foot: Vector2
		if item.has("foot"):
			var raw_foot: Variant = item.foot
			if not raw_foot is Array or raw_foot.size() != 2:
				return []
			foot = Vector2(float(raw_foot[0]),float(raw_foot[1]))
		else:
			var normalized: Variant = item.get("foot_normalized",data.get("foot_normalized",[.5,.86]))
			if not normalized is Array or normalized.size() != 2:
				return []
			foot = region.position+region.size*Vector2(float(normalized[0]),float(normalized[1]))
		if not foot.is_finite():
			return []
		var scale_value: float = BODY_HEIGHT/height
		var anchors: Dictionary = {"foot":FOOT}
		for label: String in ["head","grip","muzzle","core","left_hand","right_hand"]:
			var point: Variant = item.get(label,[])
			if point is Array and point.size() == 2:
				anchors[label] = (Vector2(float(point[0]),float(point[1]))-foot)*scale_value+FOOT
		frames.append({"texture":texture,"path":path,"region":region,"bounds":Rect2((region.position-foot)*scale_value+FOOT,region.size*scale_value),"anchors":anchors,"phase":"walk","frame_index":index,"body_height":BODY_HEIGHT,"source_body_height":height,"facing_x":-1 if int(data.get("facing_x",1)) < 0 else 1})
	return frames
