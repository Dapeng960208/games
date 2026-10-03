extends Node2D
## L32–L36/BO06 room-owned art only. Never owns geometry, tide time, collision or progression.
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
const WATER := "asset://b06_l31_environment_pilot/L31-water-v1.png"
var room_id := ""
var inlay_rect := Rect2(687,397,250,250)
var tide: Node2D
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
	room_id = str(layout.get("room_id",""))
	if room_id not in ["L32","L33","L34","L35","L36","BO06"] or not bool(layout.get("b06_candidate",false)) or not is_instance_valid(tide_runtime) or tide_runtime.room_id != room_id: return false
	var root := "asset://b06_"+room_id.to_lower()+"_environment/"
	if not FileAccess.file_exists(AssetCatalog.resolve(root+"manifest.json")): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(root+"manifest.json")))
	if not parsed is Dictionary: return false
	var manifest: Dictionary = parsed
	if not manifest.get("selected") is Dictionary or not manifest.get("placement") is Dictionary: return false
	var selected: Dictionary = manifest.selected
	for key: String in ["floor","inlay","north","south","east","west"]:
		if not selected.get(key) is String: return false
		var path: String = root+str(selected[key])
		if not ResourceLoader.exists(AssetCatalog.resolve(path)) or not load(AssetCatalog.resolve(path)) is Texture2D: return false
	for side: String in ["north","south","east","west"]:
		var rect: Variant = manifest.placement.get(side)
		if not rect is Array or rect.size()!=4: return false
		for coordinate: Variant in rect:
			if not coordinate is float and not coordinate is int: return false
		if float(rect[2])<=0 or float(rect[3])<=0: return false
	if not ResourceLoader.exists(AssetCatalog.resolve(WATER)) or not ResourceLoader.exists(AssetCatalog.resolve("res://shaders/levels/b06/shallow_water.gdshader")): return false
	floor_texture = load(AssetCatalog.resolve(root+str(selected.floor)))
	water_texture = load(AssetCatalog.resolve(WATER))
	inlay_texture = load(AssetCatalog.resolve(root+str(selected.inlay))) if selected.has("inlay") else null
	if floor_texture == null or water_texture == null: return false
	definition = Geometry.room(room_id)
	floor_polygon = Geometry.polygon(room_id)
	inlay_rect = Rect2(700,445,224,224) if room_id == "L32" else Rect2(687,397,250,250)
	if room_id == "L36": inlay_rect = Rect2(722,565,180,180) # Clear the real drain and southern wet patch.
	if room_id == "BO06": inlay_rect = Rect2(687,500,250,250) # Clear pillars and boss spawn.
	tide = tide_runtime
	tide.native_water_visual = true
	tide.queue_redraw()
	z_index = -2
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	exterior = []
	for side: String in ["north","south","east","west"]:
		var values: Array = manifest.placement[side]
		exterior.append({"texture":load(AssetCatalog.resolve(root+str(selected[side]))),"rect":Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))})
	for patch: Dictionary in definition.shallow_patches:
		var layer := Polygon2D.new()
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
	# Full exterior overscan; one unmirrored continuous source, no tile joins.
	draw_texture_rect(water_texture,source_rect,false)
	for item: Dictionary in exterior: _draw_exterior(item.texture,item.rect)
	var floor_uv := PackedVector2Array()
	for point in floor_polygon: floor_uv.append(point/104.5)
	draw_polygon(floor_polygon,PackedColorArray([Color.WHITE]),floor_uv,floor_texture)
	# Flush native mosaic: no elevation, collision, glow or gameplay identity.
	if inlay_texture != null: draw_texture_rect(inlay_texture,inlay_rect,false)
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
