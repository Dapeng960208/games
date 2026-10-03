class_name EnvironmentChunks
extends Node2D
## Six fixed source regions share the original painted image and mip chain.
## Region sampling remains on the full mother texture at every joined edge.

const GRID := Vector2i(3,2)
const SAMPLING_SHADER = preload("res://shaders/world/environment_sampling.gdshader")
const NativeDetail = preload("res://scripts/presentation/world/environment_detail.gd")
var chunks: Array[Sprite2D] = []
var source_regions: Array[Rect2i] = []
var world_rect := Rect2()
var environment_id := ""
var _texture: Texture2D
var native_detail: Node2D

func configure(texture: Texture2D, destination: Rect2, room_id: String = "") -> void:
	if _texture==texture and world_rect==destination and environment_id==room_id and (chunks.size()==GRID.x*GRID.y or (texture==null and chunks.is_empty())): return
	for child: Node in get_children():
		remove_child(child)
		child.free()
	native_detail = null
	chunks.clear()
	source_regions.clear()
	world_rect = destination
	environment_id = room_id
	_texture = texture
	if texture==null or not destination.has_area(): return
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if material == null:
		var sampling := ShaderMaterial.new()
		sampling.shader = SAMPLING_SHADER
		material = sampling
	var native := Vector2i(texture.get_width(),texture.get_height())
	if native.x<=0 or native.y<=0: return
	var shared_scale: Vector2 = destination.size/Vector2(native)
	for row: int in range(GRID.y):
		var y0: int = floori(float(row*native.y)/GRID.y)
		var y1: int = floori(float((row+1)*native.y)/GRID.y)
		for column: int in range(GRID.x):
			var x0: int = floori(float(column*native.x)/GRID.x)
			var x1: int = floori(float((column+1)*native.x)/GRID.x)
			var source := Rect2i(x0,y0,x1-x0,y1-y0)
			var sprite := Sprite2D.new()
			sprite.name = "PaintedChunk_%d_%d" % [row,column]
			sprite.texture = texture
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(source)
			# Neighboring samples are real adjacent pixels of the same image.
			# Clamping each region separately would create a filtered seam.
			sprite.region_filter_clip_enabled = false
			sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			sprite.use_parent_material = true
			sprite.position = destination.position+Vector2(source.position)*shared_scale
			sprite.scale = shared_scale
			add_child(sprite)
			chunks.append(sprite)
			source_regions.append(source)
	# Only individually approved room packs opt in. Missing/candidate packs
	# keep the complete original painting; neither path changes room geometry.
	var detail := NativeDetail.new()
	if detail.configure(room_id,destination):
		add_child(detail)
		native_detail = detail
	else:
		detail.free()

func configure_candidate_detail(allow_candidate: bool) -> void:
	if is_instance_valid(native_detail): native_detail.free()
	native_detail=null
	var detail:=NativeDetail.new()
	if detail.configure(environment_id,world_rect,allow_candidate):
		add_child(detail);native_detail=detail
	else: detail.free()
