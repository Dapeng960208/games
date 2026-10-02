extends Node2D
## Owns only this room's native repaint textures. No static image/texture cache:
## changing rooms frees all six textures, rather than retaining 28 room packs.
const SAMPLING = preload("res://shaders/environment_detail.gdshader")
const ROOT := "res://assets/generated/world/rooms_2k/"
var resident_bytes := 0
var active_room_id := ""
var tiles: Array[Sprite2D] = []

static func load_mip_texture(path: String) -> Texture2D:
	var original: Texture2D
	if ResourceLoader.exists(path):
		# Ignore the resource cache: this room node is the residency owner.
		original = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		if original != null and original.has_method("get_image"):
			var imported := original.get_image()
			if imported != null and imported.has_mipmaps(): return original
	var artwork: Image = original.get_image() if original != null else null
	if artwork == null and FileAccess.file_exists(path): artwork = Image.load_from_file(path)
	if artwork == null or artwork.is_empty(): return null
	if artwork.is_compressed() and artwork.decompress() != OK: return null
	if not artwork.has_mipmaps(): artwork.generate_mipmaps()
	return ImageTexture.create_from_image(artwork)

static func rgba_mip_bytes(size: Vector2i) -> int:
	var result := 0
	while true:
		result += size.x * size.y * 4
		if size == Vector2i.ONE: break
		size = Vector2i(maxi(1,size.x/2),maxi(1,size.y/2))
	return result

func clear() -> void:
	for child: Node in get_children(): child.free()
	tiles.clear()
	resident_bytes = 0
	active_room_id = ""

func configure(room_id: String, destination: Rect2, allow_candidate: bool = false) -> bool:
	clear()
	if room_id.is_empty() or not destination.has_area(): return false
	var path := ROOT + room_id + "/manifest.json"
	if not FileAccess.file_exists(path): return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary: return false
	var manifest: Dictionary = raw
	if str(manifest.get("room_id","")) != room_id: return false
	if not bool(manifest.get("approved",false)) and not allow_candidate: return false
	var dimensions: Array = manifest.get("source_size",[])
	var entries: Array = manifest.get("tiles",[])
	if dimensions.size()!=2 or entries.size()!=6: return false
	var source := Vector2(float(dimensions[0]),float(dimensions[1]))
	if source.x<=0.0 or source.y<=0.0: return false
	var feather_values: Array = manifest.get("feather_source_pixels",[16,24])
	if feather_values.size()!=2: return false
	var feather := Vector2(maxf(1,float(feather_values[0])),maxf(1,float(feather_values[1])))
	for entry: Dictionary in entries:
		var region: Array = entry.get("source_rect",[])
		var texture_path := str(entry.get("texture",""))
		if region.size()!=4 or not texture_path.begins_with(ROOT+room_id+"/"):
			clear()
			return false
		var rect := Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
		if not rect.has_area() or not Rect2(Vector2.ZERO,source).encloses(rect):
			clear()
			return false
		var texture := load_mip_texture(texture_path)
		if texture == null:
			clear()
			return false
		var sprite := Sprite2D.new()
		sprite.name = "NativeDetail_"+str(entry.get("id",tiles.size()))
		sprite.texture = texture
		sprite.centered = false
		sprite.position = destination.position+rect.position/source*destination.size
		sprite.scale = rect.size/source*destination.size/texture.get_size()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		var sampling := ShaderMaterial.new()
		sampling.shader = SAMPLING
		sampling.set_shader_parameter("source_size",rect.size)
		sampling.set_shader_parameter("feather_width",feather)
		sampling.set_shader_parameter("feather_edges",Vector4(1 if rect.position.x>0 else 0,1 if rect.position.y>0 else 0,1 if rect.end.x<source.x else 0,1 if rect.end.y<source.y else 0))
		sprite.material = sampling
		add_child(sprite)
		tiles.append(sprite)
		resident_bytes += rgba_mip_bytes(Vector2i(texture.get_size()))
	active_room_id = room_id
	return true
