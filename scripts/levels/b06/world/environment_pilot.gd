extends Node2D
## L31 candidate art only. Never owns geometry, tide time, collision or progression.
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
const FirstRoomEnvironment = preload("res://scripts/presentation/world/first_room_environment.gd")
const ROOT := "asset://b06_l31_environment_pilot/"
const LAYER_CONFIG := "asset://levels/b06/rooms/l31/first_room_layers.json"
var tide: Node2D
var scenery: Node2D
var floor_texture: Texture2D
var water_texture: Texture2D
var inlay_texture: Texture2D
var floor_polygon := PackedVector2Array()
var definition: Dictionary = {}
var exterior: Array[Dictionary] = []
var water_layers: Array[Polygon2D] = []
# Frozen source-placement contract, with floor overscan on all four sides.
var source_rect := Rect2(-1624.0*.11/.78,-1044.0*.13/.74,1624.0/.78,1044.0/.74)
func configure(layout: Dictionary, tide_runtime: Node2D) -> bool:
	if str(layout.get("room_id","")) != "L31" or not bool(layout.get("b06_candidate",false)) or not is_instance_valid(tide_runtime) or tide_runtime.room_id != "L31": return false
	var layered := FileAccess.file_exists(AssetCatalog.resolve(LAYER_CONFIG))
	var required: Array[String] = ["L31-water-v1.png"]
	if not layered:
		required.append_array(["L31-floor-tile-v2.png","L31-shell-inlay-v1.png","L31-north-skyline-v1.png","L31-south-facade-v1.png","L31-east-facade-v1.png","L31-west-facade-v1.png"])
	for file: String in required:
		if not ResourceLoader.exists(AssetCatalog.resolve(ROOT+file)) or not load(AssetCatalog.resolve(ROOT+file)) is Texture2D: return false
	if not ResourceLoader.exists(AssetCatalog.resolve("res://shaders/levels/b06/shallow_water.gdshader")): return false
	water_texture = load(AssetCatalog.resolve(ROOT+"L31-water-v1.png"))
	if water_texture == null: return false
	if layered:
		var candidate := FirstRoomEnvironment.new()
		if not candidate.configure(layout, LAYER_CONFIG):
			candidate.free()
			return false
		scenery = candidate
		scenery.name = "FirstRoomScenery"
		add_child(scenery)
	else:
		floor_texture = load(AssetCatalog.resolve(ROOT+"L31-floor-tile-v2.png"))
		inlay_texture = load(AssetCatalog.resolve(ROOT+"L31-shell-inlay-v1.png"))
		if floor_texture == null or inlay_texture == null: return false
	definition = Geometry.room("L31")
	floor_polygon = layout.get("ground_polygon", Geometry.polygon("L31"))
	tide = tide_runtime
	tide.native_water_visual = true
	tide.queue_redraw()
	z_index = 0 if layered else -2
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if not layered:
		exterior = [
			{"texture":load(AssetCatalog.resolve(ROOT+"L31-north-skyline-v1.png")),"rect":Rect2(104.4,-352.73,1415.2,471.73)},
			{"texture":load(AssetCatalog.resolve(ROOT+"L31-south-facade-v1.png")),"rect":Rect2(104.4,849.73,1415.2,471.73)},
			{"texture":load(AssetCatalog.resolve(ROOT+"L31-east-facade-v1.png")),"rect":Rect2(1497.0,116.0,270.67,812.0)},
			{"texture":load(AssetCatalog.resolve(ROOT+"L31-west-facade-v1.png")),"rect":Rect2(-119.0,116.0,270.67,812.0)}
		]
	for patch: Dictionary in definition.shallow_patches:
		var layer := Polygon2D.new()
		layer.z_index = -1 if layered else 0
		layer.polygon = Geometry.points(patch.polygon)
		layer.texture = water_texture
		var uv := PackedVector2Array()
		for point in layer.polygon: uv.append((point-source_rect.position)/source_rect.size*Vector2(water_texture.get_size()))
		layer.uv = uv
		var material := ShaderMaterial.new()
		material.shader = load(AssetCatalog.resolve("res://shaders/levels/b06/shallow_water.gdshader"))
		var bounds := Rect2(layer.polygon[0],Vector2.ZERO)
		for point in layer.polygon: bounds = bounds.expand(point)
		material.set_shader_parameter("patch_rect",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
		layer.material = material
		layer.set_meta("patch_id",str(patch.id))
		add_child(layer)
		water_layers.append(layer)
	refresh_water()
	queue_redraw()
	return true
func _exit_tree() -> void:
	if is_instance_valid(tide): tide.native_water_visual=false; tide.queue_redraw()
func _process(_delta: float) -> void:
	refresh_water() # Pure visual reads of the single room-owned tide state.
func refresh_water() -> void:
	if not is_instance_valid(tide): return
	for layer in water_layers:
		var wet: bool = tide.is_patch_wet(str(layer.get_meta("patch_id")))
		layer.material.set_shader_parameter("wet_opacity",.48 if wet else .025)
	queue_redraw()
func _draw() -> void:
	if definition.is_empty() or not is_instance_valid(tide): return
	if is_instance_valid(scenery): return
	# Full exterior overscan; one unmirrored continuous source, no tile joins.
	draw_texture_rect(water_texture,source_rect,false)
	for item: Dictionary in exterior: _draw_exterior(item.texture,item.rect)
	var floor_uv := PackedVector2Array()
	for point in floor_polygon: floor_uv.append(point/104.5)
	draw_polygon(floor_polygon,PackedColorArray([Color.WHITE]),floor_uv,floor_texture)
	# Flush native mosaic: no elevation, collision, glow or gameplay identity.
	draw_texture_rect(inlay_texture,Rect2(687,397,250,250),false)
	# Thin boundary edge is an honest collision-boundary cue, not fabricated art.
	var edge := floor_polygon.duplicate(); edge.append(edge[0])
	draw_polyline(edge,Color("cfad67"),3.0,true)
func _draw_exterior(texture: Texture2D, rect: Rect2) -> void:
	var outer := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	# Explicit difference guarantees NO architecture pixels on legal floor.
	for shape: PackedVector2Array in Geometry2D.clip_polygons(outer,floor_polygon):
		var uv := PackedVector2Array()
		for point in shape: uv.append((point-rect.position)/rect.size)
		draw_polygon(shape,PackedColorArray([Color.WHITE]),uv,texture)
