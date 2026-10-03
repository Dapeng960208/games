extends Node2D
## L43 opt-in reference candidate. Original native pixels; immutable gameplay geometry.
const Geometry = preload("res://scripts/levels/b08/geometry.gd")
const ROOT := "asset://b08/rooms/l43/"
var textures: Dictionary = {}
var layers: Array = []
var errors: Array[String] = []
var snapshot: Dictionary = {}
var edge_faces: Array = []
var boundary_segments: Array = []
const DEPTH := Vector2(0,18)
var background_depth_review := false
const DISTANT_STRENGTH := .45
const DISTANT_AIR := Color("b9d6eb")
var background_rect := Rect2(0,0,1624,1044)
func configure(id: String, review_background_depth: bool = false) -> bool:
	if id!="L43" or not textures.is_empty(): return false
	background_depth_review=review_background_depth
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT+"mapping.json")))
	if not parsed is Dictionary:
		errors.append("Invalid mapping JSON"); return false
	var declared: Array[Rect2]=[]
	for values: Array in parsed.get("floor_union_rectangles_xywh",[]): declared.append(Geometry.rect(values))
	if declared!=Geometry.floors(id):
		errors.append("Mapping footprint differs from gameplay floor"); return false
	z_index=-4
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for layer: Dictionary in parsed.layers:
		var file: String=layer.file
		var texture:=preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(ROOT+file)
		if texture==null: errors.append("Missing "+file); continue
		snapshot[file]={"size":texture.get_size(),"sha256":FileAccess.get_sha256(AssetCatalog.resolve(ROOT+file))}
		textures[file]=texture
		if layer.role not in ["background","floor"]:
			register(file,Vector2(layer.source_anchor_pixel[0],layer.source_anchor_pixel[1]),Vector2(layer.blueprint_anchor[0],layer.blueprint_anchor[1]),float(layer.source_to_blueprint_uniform_scale))
	build_edges()
	queue_redraw()
	return errors.is_empty() and textures.size()==8
static func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
func register(file: String, source_anchor: Vector2, blueprint_anchor: Vector2, scale_value: float) -> void:
	if not textures.has(file): return
	var texture: Texture2D=textures[file]
	var rect:=Rect2((blueprint_anchor-source_anchor*scale_value)*.58,texture.get_size()*scale_value*.58)
	var shapes: Array[PackedVector2Array]=[polygon(rect)]
	for floor_rect: Rect2 in Geometry.floors("L43"):
		var next: Array[PackedVector2Array]=[]
		for shape: PackedVector2Array in shapes: next.append_array(Geometry2D.clip_polygons(shape,polygon(floor_rect)))
		shapes=next
	for shape: PackedVector2Array in shapes:
		for floor_rect: Rect2 in Geometry.floors("L43"):
			if not Geometry2D.intersect_polygons(shape,polygon(floor_rect)).is_empty(): errors.append(file+" floor clipping intersection")
	layers.append({"file":file,"rect":rect,"shapes":shapes})

func clipped(shape: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[shape]
	for floor_rect: Rect2 in Geometry.floors("L43"):
		var next: Array[PackedVector2Array]=[]
		for piece: PackedVector2Array in result: next.append_array(Geometry2D.clip_polygons(piece,polygon(floor_rect)))
		result=next
	return result
func build_edges() -> void:
	# Exact rectangle-union boundary, including the central sky opening. No floor mutation.
	var xs: Array[float]=[]
	var ys: Array[float]=[]
	for floor_rect: Rect2 in Geometry.floors("L43"):
		for x: float in [floor_rect.position.x,floor_rect.end.x]:
			if not xs.has(x): xs.append(x)
		for y: float in [floor_rect.position.y,floor_rect.end.y]:
			if not ys.has(y): ys.append(y)
	xs.sort(); ys.sort()
	for x in range(xs.size()-1):
		for y in range(ys.size()-1):
			var center:=Vector2((xs[x]+xs[x+1])*.5,(ys[y]+ys[y+1])*.5)
			if not Geometry.contains("L43",center): continue
			var candidates: Array=[
				[Vector2(xs[x],ys[y]),Vector2(xs[x+1],ys[y]),Vector2.UP],
				[Vector2(xs[x+1],ys[y+1]),Vector2(xs[x],ys[y+1]),Vector2.DOWN],
				[Vector2(xs[x],ys[y+1]),Vector2(xs[x],ys[y]),Vector2.LEFT],
				[Vector2(xs[x+1],ys[y]),Vector2(xs[x+1],ys[y+1]),Vector2.RIGHT]]
			for edge: Array in candidates:
				var a: Vector2=edge[0]
				var b: Vector2=edge[1]
				var normal: Vector2=edge[2]
				if Geometry.contains("L43",a.lerp(b,.5)+normal*.1): continue
				boundary_segments.append([a,b,normal])
				# Constant SCREEN-DOWN extrusion, never push every edge normal out as a wall.
				if absf(a.y-b.y)<.01:
					var wall:=PackedVector2Array([a,b,b+DEPTH,a+DEPTH])
					edge_faces.append({"shapes":clipped(wall),"tint":Color(.60,.65,.70),"kind":"downward_side"})
				# Two-unit external stone cap is a trim, not a second walkable ledge.
				var cap:=PackedVector2Array([a,b,b+normal*2.0,a+normal*2.0])
				edge_faces.append({"shapes":clipped(cap),"tint":Color(.87,.84,.75),"kind":"thin_cap"})
				# Small square/miter joints close corner cracks, still clipped outside legal ground.
				for corner: Vector2 in [a,b]:
					edge_faces.append({"shapes":clipped(polygon(Rect2(corner-Vector2(2,2),Vector2(4,4)))),"tint":Color(.87,.84,.75),"kind":"cap_joint"})
	for face: Dictionary in edge_faces:
		for shape: PackedVector2Array in face.shapes:
			for floor_rect: Rect2 in Geometry.floors("L43"):
				if not Geometry2D.intersect_polygons(shape,polygon(floor_rect)).is_empty(): errors.append("Depth trim intersects legal ground")

func _draw() -> void:
	if not errors.is_empty(): return
	if background_depth_review:
		# Runtime aerial perspective on the distant layer only; native pixels stay untouched.
		draw_rect(background_rect,DISTANT_AIR)
		draw_texture_rect(textures["distant_city.png"],background_rect,false,Color(1,1,1,DISTANT_STRENGTH))
	else: draw_texture_rect(textures["distant_city.png"],background_rect,false)
	for layer: Dictionary in layers:
		for shape: PackedVector2Array in layer.shapes:
			var uv:=PackedVector2Array()
			for point: Vector2 in shape: uv.append((point-layer.rect.position)/layer.rect.size)
			draw_polygon(shape,PackedColorArray([Color.WHITE]),uv,textures[layer.file])
	# Existing native stone sampled as a material on shallow edge geometry.
	# This is an explicitly geometric prototype finish, not a new authored facade image.
	for face: Dictionary in edge_faces:
		for shape: PackedVector2Array in face.shapes:
			var uv:=PackedVector2Array()
			for point: Vector2 in shape: uv.append(point/Vector2(1624,1044))
			draw_polygon(shape,PackedColorArray([face.tint]),uv,textures["floor_surface.png"])
	# Opaque surface is one full composition; never per-rectangle tiled/restarted.
	for floor_rect: Rect2 in Geometry.floors("L43"):
		var shape:=polygon(floor_rect)
		var uv:=PackedVector2Array()
		for point: Vector2 in shape: uv.append(point/Vector2(1624,1044))
		draw_polygon(shape,PackedColorArray([Color.WHITE]),uv,textures["floor_surface.png"])
