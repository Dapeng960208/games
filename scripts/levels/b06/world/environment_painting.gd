extends Node2D
## Complete room painting and visual tide overlays share the blueprint mapping.
## Geometry, mechanism feet, tide time and progression remain room-owned.
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const WATER := "asset://b06_l31_environment_pilot/L31-water-v1.png"
var room_id := ""
var tide: Node2D
var painting_texture: Texture2D
var water_texture: Texture2D
var floor_polygon := PackedVector2Array()
var definition: Dictionary = {}
var water_layers: Array[Polygon2D] = []
var source_rect := Rect2()
func configure(layout: Dictionary, tide_runtime: Node2D) -> bool:
	room_id = str(layout.get("room_id",""))
	if not bool(layout.get("b06_candidate",false)) or str(layout.get("biome_id",""))!="B06" or not is_instance_valid(tide_runtime) or tide_runtime.room_id!=room_id: return false
	definition=Geometry.room(room_id)
	var painting := Art.environment_definition("B06",room_id)
	if definition.is_empty() or not bool(painting.get("room_specific",false)): return false
	painting_texture=painting.get("texture")
	water_texture=preload("res://scripts/presentation/world/environment_detail.gd").load_mip_texture(WATER)
	if painting_texture==null or water_texture==null: return false
	source_rect=Art.environment_world_rect(layout.arena,"B06",room_id)
	floor_polygon=layout.get("ground_polygon",Geometry.polygon(room_id))
	if floor_polygon.size()<3 or not source_rect.has_area(): return false
	tide=tide_runtime
	tide.native_water_visual=true
	tide.queue_redraw()
	z_index=-2
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for patch: Dictionary in definition.shallow_patches:
		var layer := Polygon2D.new()
		layer.polygon=Geometry.points(patch.polygon)
		layer.texture=water_texture
		var uv := PackedVector2Array()
		for point in layer.polygon: uv.append((point-source_rect.position)/source_rect.size*Vector2(water_texture.get_size()))
		layer.uv=uv
		var material := ShaderMaterial.new()
		material.shader=preload("res://shaders/levels/b06/shallow_water.gdshader")
		var bounds := Rect2(layer.polygon[0],Vector2.ZERO)
		for point in layer.polygon: bounds=bounds.expand(point)
		material.set_shader_parameter("patch_rect",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
		layer.material=material
		layer.set_meta("patch_id",str(patch.id))
		add_child(layer)
		water_layers.append(layer)
	refresh_water()
	queue_redraw()
	return true
func painted_bounds() -> Rect2: return source_rect
func _exit_tree() -> void:
	if is_instance_valid(tide): tide.native_water_visual=false; tide.queue_redraw()
func _process(_delta: float) -> void: refresh_water()
func refresh_water() -> void:
	if not is_instance_valid(tide): return
	for layer in water_layers:
		layer.material.set_shader_parameter("wet_opacity",.48 if tide.is_patch_wet(str(layer.get_meta("patch_id"))) else .025)
func _draw() -> void:
	if painting_texture==null: return
	draw_texture_rect(painting_texture,source_rect,false)
	var edge:=floor_polygon.duplicate();edge.append(edge[0])
	draw_polyline(edge,Color("cfad67"),2.0,true)
