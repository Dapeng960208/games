extends RefCounted
## Three exact-source render representations only. Source PNGs are never written,
## scaled or cleaned. A transparent runtime canvas keeps every renderer consumer
## in bounds, including alpha contact masks, fallback bodies and death snapshots.
const NATIVE_SIZE := Vector2i(1254,1254)
const CANVAS_SIZE := Vector2i(1280,1280)
const OFFSETS: Dictionary = {
	"res://assets/generated/enemies/variant_hd_v1/M12_variant_05_hd_v1.png": Vector2i(0,0),
	"res://assets/generated/enemies/variant_hd_v1/M12_variant_06_hd_v1.png": Vector2i(6,0),
	"res://assets/generated/enemies/variant_hd_v1/M12_variant_07_hd_v1.png": Vector2i(0,0),
}
static var textures: Dictionary = {}

static func required(identity: String, index: int) -> bool:
	return identity == "M12" and index in [5,6,7]

static func _numbers(raw: Variant, count: int) -> bool:
	if not raw is Array or raw.size() != count: return false
	for value: Variant in raw:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	return true

static func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))

static func parse_layout(identity: String, index: int, replacement: Dictionary, raw: Variant) -> Dictionary:
	if not required(identity,index) or not raw is Dictionary: return {}
	var path: String = str(replacement.get("texture",""))
	if path != "res://assets/generated/enemies/variant_hd_v1/%s_variant_%02d_hd_v1.png" % [identity,index] or not OFFSETS.has(path): return {}
	for key: String in ["native_texture_size","virtual_canvas_size","native_texture_offset","virtual_foot"]:
		if not _numbers(raw.get(key),2): return {}
	for key: String in ["virtual_registration_region","logical_region_in_native_texture_coordinates","safe_native_sample_region","safe_sample_destination_normalized_within_logical_rect"]:
		if not _numbers(raw.get(key),4): return {}
	if not _numbers(replacement.get("region"),4) or not _numbers(replacement.get("foot"),2): return {}
	var native := Vector2(float(raw.native_texture_size[0]),float(raw.native_texture_size[1]))
	var canvas := Vector2(float(raw.virtual_canvas_size[0]),float(raw.virtual_canvas_size[1]))
	var offset := Vector2(float(raw.native_texture_offset[0]),float(raw.native_texture_offset[1]))
	# Exact dimensions/offsets bound memory, prevent cache aliases and disallow
	# fractional resampling or a new candidate silently authorizing padding.
	if native != Vector2(NATIVE_SIZE) or canvas != Vector2(CANVAS_SIZE) or offset != Vector2(OFFSETS[path]): return {}
	var region := _rect(replacement.region)
	var logical := _rect(raw.logical_region_in_native_texture_coordinates)
	var registered := _rect(raw.virtual_registration_region)
	var foot := Vector2(float(replacement.foot[0]),float(replacement.foot[1]))
	var virtual_foot := Vector2(float(raw.virtual_foot[0]),float(raw.virtual_foot[1]))
	if not region.has_area() or not logical.is_equal_approx(region): return {}
	if not registered.is_equal_approx(Rect2(region.position+offset,region.size)) or not virtual_foot.is_equal_approx(foot+offset): return {}
	if not Rect2(Vector2.ZERO,canvas).encloses(registered) or not Rect2(Vector2.ZERO,canvas).encloses(Rect2(offset,native)): return {}
	var sample: Rect2 = region.intersection(Rect2(Vector2.ZERO,native))
	if not sample.has_area() or not _rect(raw.safe_native_sample_region).is_equal_approx(sample): return {}
	var destination := Rect2((sample.position-region.position)/region.size,sample.size/region.size)
	if not _rect(raw.safe_sample_destination_normalized_within_logical_rect).is_equal_approx(destination): return {}
	return {"texture_path":path,"native_size":NATIVE_SIZE,"canvas_size":CANVAS_SIZE,"offset":Vector2i(offset),"region":registered,"foot":virtual_foot,"native_region":region,"native_foot":foot,"sample_region":sample,"sample_destination":destination}

static func native_image(path: String) -> Image:
	if not OFFSETS.has(path): return null
	var artwork: Image
	# Prefer exact PNG pixels when source files are present. Exported builds use
	# lossless imports; the three import records disable alpha-border rewriting.
	if FileAccess.file_exists(path):
		artwork = Image.new()
		if artwork.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK: return null
	if (artwork == null or artwork.is_empty()) and ResourceLoader.exists(path):
		var resource := load(path) as Texture2D
		if resource != null: artwork = resource.get_image()
	if artwork == null or artwork.is_empty(): return null
	if artwork.is_compressed() and artwork.decompress() != OK: return null
	if artwork.get_size() != NATIVE_SIZE or artwork.get_format() != Image.FORMAT_RGBA8: return null
	return artwork

static func sampled(path: String, layout: Dictionary) -> Texture2D:
	if not OFFSETS.has(path) or layout.get("texture_path") != path or layout.get("native_size") != NATIVE_SIZE or layout.get("canvas_size") != CANVAS_SIZE or layout.get("offset") != OFFSETS[path]: return null
	if textures.has(path): return textures[path] as Texture2D
	if textures.size() >= OFFSETS.size(): return null
	var source: Image = native_image(path)
	if source == null: return null
	var canvas := Image.create(CANVAS_SIZE.x,CANVAS_SIZE.y,false,Image.FORMAT_RGBA8)
	canvas.fill(Color(0,0,0,0))
	# Copy RGBA exactly. No blend, resize, alpha fix, edge recolor or sharpening.
	canvas.blit_rect(source,Rect2i(Vector2i.ZERO,NATIVE_SIZE),OFFSETS[path])
	if canvas.generate_mipmaps() != OK: return null
	var texture := ImageTexture.create_from_image(canvas)
	textures[path] = texture
	return texture
