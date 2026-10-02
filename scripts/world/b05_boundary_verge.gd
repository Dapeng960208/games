extends Node2D
## Art-only perimeter overlay. The frozen ground and portal geometry never move.
const Geometry = preload("res://scripts/world/b05_room_geometry.gd")
const WorldArt = preload("res://scripts/world/world_art.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const ShaderSource = preload("res://shaders/b05_boundary_verge.gdshader")
var _texture: Texture2D
var _rect := Rect2()

func configure(layout: Dictionary, allow_candidate: bool = false) -> bool:
	var id := str(layout.get("blueprint_room_id",""))
	var path := "res://assets/generated/world/rooms_2k/%s/verge_material_v1.json" % id
	if not FileAccess.file_exists(path): return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or (not bool(raw.get("approved",false)) and not allow_candidate): return false
	_texture = Sampler.sampled(str(raw.texture))
	if _texture == null: return false
	var definition := Geometry.room(id)
	if definition.is_empty(): return false
	var ground := PackedVector2Array()
	for point: Array in definition.art.walkable_normalized_polygon: ground.append(Vector2(point[0],point[1])*Vector2(1536,1024))
	var floor_points := PackedVector2Array()
	for point: Array in raw.visible_floor_outer_polygon_source_pixels: floor_points.append(Vector2(point[0],point[1]))
	if ground.size()>16 or floor_points.size()>32 or ground.size()<3 or floor_points.size()<3: return false
	var mat := ShaderMaterial.new()
	mat.shader = ShaderSource
	mat.set_shader_parameter("ground_count",ground.size())
	mat.set_shader_parameter("floor_count",floor_points.size())
	ground.resize(16)
	floor_points.resize(32)
	mat.set_shader_parameter("ground",ground)
	mat.set_shader_parameter("painted_floor",floor_points)
	for side: String in ["west","east"]:
		var values: Array = raw.portal_exclusion_rects_source_pixels[side]
		mat.set_shader_parameter("gate_"+side,Vector4(values[0],values[1],values[2],values[3]))
	material = mat
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rect = WorldArt.environment_world_rect(layout.arena,"B05",id)
	z_index = -7
	queue_redraw()
	return true

func _draw() -> void:
	if _texture != null: draw_texture_rect(_texture,_rect,false)
