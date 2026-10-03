extends Node2D
## Room-owned scenery only. The supplied gameplay polygon remains authoritative.
const TextureLoader = preload("res://scripts/presentation/world/environment_detail.gd")
const EXTERIOR_SHADER = preload("res://shaders/world/first_room_exterior.gdshader")
const MAX_GROUND_POINTS := 64

var active_room_id := ""
var floor_polygon := PackedVector2Array()
var layer_ids: Array[String] = []
var source_texture_dimensions: Dictionary = {}

func configure(layout: Dictionary, config_path: String) -> bool:
	clear()
	var path := AssetCatalog.resolve(config_path)
	if not FileAccess.file_exists(path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return false
	var config: Dictionary = parsed
	if config.get("schema_version") != 1 or str(config.get("room_id", "")) != str(layout.get("room_id", "")) or str(config.get("biome_id", "")) != str(layout.get("biome_id", "")): return false
	var ground: Variant = layout.get("ground_polygon")
	if not ground is PackedVector2Array or ground.size() < 3 or ground.size() > MAX_GROUND_POINTS: return false
	for point: Vector2 in ground:
		if not point.is_finite(): return false
	if Geometry2D.triangulate_polygon(ground).is_empty(): return false
	if not config.get("background") is Dictionary or not config.get("floor") is Dictionary or not config.get("layers") is Array: return false
	var sources: Dictionary = {}
	var background: Dictionary = _texture_item(config.background, sources)
	var floor_spec: Dictionary = config.floor
	var floor_path: String = str(floor_spec.get("texture", ""))
	var tile_size: Variant = floor_spec.get("tile_world_size")
	if background.is_empty() or not _number(tile_size) or float(tile_size) <= 0.0 or not floor_path.begins_with("asset://"): return false
	var floor_texture := _load_texture(floor_path, sources)
	if floor_texture == null: return false
	var prepared: Array[Dictionary] = []
	var seen: Dictionary = {}
	for value: Variant in config.layers:
		if not value is Dictionary: return false
		var item: Dictionary = _texture_item(value, sources)
		var identity := str(value.get("id", ""))
		var clip := str(value.get("clip", ""))
		var layer_z: Variant = value.get("z_index", -5)
		var opacity: Variant = value.get("opacity", 1.0)
		var alpha_cutoff: Variant = value.get("alpha_cutoff",0.0)
		if item.is_empty() or identity.is_empty() or seen.has(identity) or clip not in ["", "exterior"]: return false
		if not _number(layer_z) or float(layer_z) != float(int(layer_z)) or int(layer_z) < -8 or int(layer_z) > -1 or not _number(opacity) or float(opacity) < 0.0 or float(opacity) > 1.0: return false
		if not _number(alpha_cutoff) or float(alpha_cutoff) < 0.0 or float(alpha_cutoff) > 1.0 or (float(alpha_cutoff) > 0.0 and clip != "exterior"): return false
		seen[identity] = true
		item.merge({"id":identity, "clip":clip, "z_index":int(layer_z), "opacity":float(opacity), "alpha_cutoff":float(alpha_cutoff)})
		prepared.append(item)
	# No visible layer is installed until every referenced source has loaded.
	floor_polygon = ground.duplicate()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var backdrop := _sprite(background, "Background", -9)
	add_child(backdrop)
	var floor_layer := Polygon2D.new()
	floor_layer.name = "Floor"
	floor_layer.z_index = -2
	floor_layer.polygon = floor_polygon
	floor_layer.texture = floor_texture
	floor_layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var uv := PackedVector2Array()
	for point: Vector2 in floor_polygon: uv.append(point / float(tile_size) * floor_texture.get_size())
	floor_layer.uv = uv
	add_child(floor_layer)
	var boundary := Line2D.new()
	boundary.name = "GroundBoundary"
	boundary.z_index = -2
	boundary.points = floor_polygon.duplicate()
	boundary.add_point(floor_polygon[0])
	boundary.width = 2.0
	boundary.default_color = Color("cfad67")
	boundary.antialiased = true
	add_child(boundary)
	for item: Dictionary in prepared:
		var sprite := _sprite(item, str(item.id), int(item.z_index))
		sprite.modulate.a = float(item.opacity)
		if str(item.clip) == "exterior":
			var material := ShaderMaterial.new()
			material.shader = EXTERIOR_SHADER
			material.set_shader_parameter("alpha_cutoff",float(item.alpha_cutoff))
			var points := floor_polygon.duplicate()
			points.resize(MAX_GROUND_POINTS)
			material.set_shader_parameter("ground", points)
			material.set_shader_parameter("ground_count", floor_polygon.size())
			var rect: Rect2 = item.rect
			material.set_shader_parameter("room_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
			material.set_shader_parameter("source_extent", item.region.size)
			sprite.material = material
		add_child(sprite)
		layer_ids.append(str(item.id))
		source_texture_dimensions[str(item.id)] = item.region.size
	source_texture_dimensions["background"] = background.region.size
	source_texture_dimensions["floor"] = floor_texture.get_size()
	active_room_id = str(config.room_id)
	return true

func clear() -> void:
	for child: Node in get_children(): child.free()
	active_room_id = ""
	floor_polygon.clear()
	layer_ids.clear()
	source_texture_dimensions.clear()

func _texture_item(spec: Dictionary, sources: Dictionary) -> Dictionary:
	var texture_path := str(spec.get("texture", ""))
	var rect := _rect(spec.get("rect"))
	if not texture_path.begins_with("asset://") or not rect.has_area(): return {}
	var texture := _load_texture(texture_path, sources)
	if texture == null: return {}
	var full_rect := Rect2(Vector2.ZERO, texture.get_size())
	var region := _rect(spec.region) if spec.has("region") else full_rect
	if not region.has_area() or not full_rect.encloses(region): return {}
	return {"texture":texture, "rect":rect, "region":region}

static func _load_texture(path: String, sources: Dictionary) -> Texture2D:
	if sources.has(path): return sources[path]
	var texture := TextureLoader.load_mip_texture(path)
	if texture != null: sources[path] = texture
	return texture

func _sprite(item: Dictionary, identity: String, layer_z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = identity
	sprite.texture = item.texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = item.region
	sprite.region_filter_clip_enabled = true
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	sprite.z_index = layer_z
	sprite.position = item.rect.position
	sprite.scale = item.rect.size / item.region.size
	return sprite

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _rect(value: Variant) -> Rect2:
	if not value is Array or value.size() != 4: return Rect2()
	for coordinate: Variant in value:
		if not _number(coordinate): return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
