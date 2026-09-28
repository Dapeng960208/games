class_name RoomAppearance
extends RefCounted
## One authored instance draws one naturally proportioned PNG directly on the
## world floor. Placement, spacing and collision belong to RoomLayouts.

const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const VOID_KINDS := ["mine_pit", "gear_gap", "suspended_void", "water_channel", "floating_platform_gap", "ventilation_shaft", "acid_reservoir", "gantry_void", "mirror_pool", "deep_rift", "echo_disc_gap"]
static var _art_regions: Dictionary = {}

static func recipe(layout: Dictionary, biome_id: String) -> Array:
	var result: Array = []
	var room_id: String = str(layout.get("room_id", ""))
	var static_kinds: Array = layout.get("static_obstruction_kinds", [])
	for index: int in range(layout.get("static_obstructions", []).size()):
		var rect: Rect2 = layout.static_obstructions[index]
		var kind: String = str(static_kinds[index]) if index < static_kinds.size() else "mine_pit"
		result.append({"id":room_id+":terrain:"+str(index), "rect":rect, "collision_rect":rect, "kind":kind, "tags":[], "index":index, "biome_id":biome_id, "room_id":room_id, "destroyed":false, "static":true})
	for instance: Dictionary in layout.get("prop_instances", []):
		var item: Dictionary = instance.duplicate(true)
		item["rect"] = item.get("collision_rect", Rect2())
		item["index"] = result.size()
		item["biome_id"] = biome_id
		item["room_id"] = room_id
		item["destroyed"] = bool(item.get("destroyed", false))
		item["static"] = false
		result.append(item)
	return result

static func draw_floor(_canvas: CanvasItem, _layout: Dictionary, _biome_id: String, _time: float = 0.0) -> void:
	# MineBackdrop is the sole ground surface. No plate, grid, outline, repeated
	# tile stamp or rectangular foundation is painted over the original art.
	pass

static func draw_obstacles(canvas: CanvasItem, recipes: Array, time: float = 0.0) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for item: Dictionary in recipes:
		if bool(item.get("destroyed", false)): continue
		if bool(item.get("static", false)):
			_draw_void(canvas, item, time)
		else:
			_draw_instance(canvas, item)

static func _texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path): return null
	return TextureSampler.sampled(path)

static func _asset_path(asset: String) -> String:
	if asset.begins_with("res://"): return asset
	return "res://assets/generated/props/"+asset+"_v1.png"

static func _source_region(path: String, texture: Texture2D) -> Rect2:
	if not _art_regions.has(path):
		var image: Image = texture.get_image()
		var region: Rect2 = Rect2(Vector2.ZERO,texture.get_size())
		if image != null and not image.is_empty(): region = _opaque_region(image)
		_art_regions[path] = region
	return _art_regions[path]

static func _draw_instance(canvas: CanvasItem, item: Dictionary) -> void:
	var asset: String = str(item.get("asset", ""))
	if asset.is_empty(): return
	var texture: Texture2D = _texture(_asset_path(asset))
	if texture == null: return
	var source: Rect2 = _source_region(_asset_path(asset),texture)
	if not source.has_area(): return
	var quad: PackedVector2Array = _sprite_quad(item,source.size)
	if quad.size() != 4: return
	var collision: Rect2 = item.get("collision_rect", Rect2())
	# A small contact shadow follows only this prop's footprint. It never fills
	# the gap to another prop; every such real gap remains visibly open ground.
	if collision.has_area():
		var at: Vector2 = collision.get_center()+Vector2(0,collision.size.y*0.08)
		_ellipse(canvas,at,collision.size*Vector2(0.56,0.43),Color(0.015,0.02,0.022,0.12))
		_ellipse(canvas,at,collision.size*Vector2(0.43,0.31),Color(0.008,0.012,0.015,0.16))
	var uv_start: Vector2 = source.position/texture.get_size()
	var uv_end: Vector2 = source.end/texture.get_size()
	var uvs := PackedVector2Array([uv_start,Vector2(uv_end.x,uv_start.y),uv_end,Vector2(uv_start.x,uv_end.y)])
	# Rotating vertex positions leaves the caller's canvas transform untouched.
	canvas.draw_polygon(quad,PackedColorArray([Color.WHITE]),uvs,texture)

static func _sprite_quad(item: Dictionary, source_size: Vector2) -> PackedVector2Array:
	var bounds: Vector2 = item.get("visual_size", Vector2.ZERO)
	if bounds.x<=0 or bounds.y<=0 or source_size.x<=0 or source_size.y<=0: return PackedVector2Array()
	var rotation: float = float(item.get("rotation",0.0))
	var cosine: float = absf(cos(rotation))
	var sine: float = absf(sin(rotation))
	var rotated_size: Vector2 = Vector2(source_size.x*cosine+source_size.y*sine,source_size.x*sine+source_size.y*cosine)
	var scale: float = minf(bounds.x/rotated_size.x,bounds.y/rotated_size.y)
	var half: Vector2 = source_size*scale*0.5
	var collision: Rect2 = item.get("collision_rect",Rect2())
	var position: Vector2 = item.get("position",collision.get_center())
	var center: Vector2 = Vector2(position.x,collision.end.y-rotated_size.y*scale*0.5)
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
		points.append(center+corner.rotated(rotation))
	return points

static func _ellipse(canvas: CanvasItem, at: Vector2, extent: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(24): points.append(at+Vector2.from_angle(index*TAU/24.0)*extent)
	canvas.draw_colored_polygon(points,color)

static func _opaque_region(image: Image) -> Rect2:
	# Weak generated haze outside the actual silhouette must not shrink the
	# visible prop. This only chooses UVs and never edits the original PNG.
	var minimum := Vector2i(image.get_width(),image.get_height())
	var maximum := Vector2i(-1,-1)
	for y: int in range(0,image.get_height(),2):
		for x: int in range(0,image.get_width(),2):
			if image.get_pixel(x,y).a>=0.2:
				minimum.x = mini(minimum.x,x)
				minimum.y = mini(minimum.y,y)
				maximum.x = maxi(maximum.x,x)
				maximum.y = maxi(maximum.y,y)
	if maximum.x<0: return Rect2(Vector2.ZERO,Vector2(image.get_size()))
	return Rect2(Vector2(minimum),Vector2(maximum-minimum+Vector2i.ONE)).grow(2).intersection(Rect2(Vector2.ZERO,Vector2(image.get_size())))

static func _variation(index: int, salt: int) -> float:
	return fposmod(sin(float(index*127+salt*311))*43758.5453,1.0)

static func _draw_void(canvas: CanvasItem, item: Dictionary, time: float) -> void:
	var rect: Rect2 = item.get("collision_rect",item.get("rect",Rect2()))
	if not rect.has_area(): return
	var kind: String = str(item.get("kind","mine_pit"))
	var seed_value: int = int(item.get("index",0))+str(item.get("room_id","")).hash()%101
	if kind=="mirror_pool":
		_draw_mirror_pool(canvas,rect,seed_value,time)
		return
	var fluid: bool = kind in ["water_channel","acid_reservoir","mirror_pool"]
	var depth: Color = Color("080d12")
	var stone: Color = Color("202726")
	var glint: Color = Color("60716a")
	if kind=="water_channel":
		depth = Color("102322")
		stone = Color("28372b")
	elif kind=="acid_reservoir":
		depth = Color("182919")
		stone = Color("2d3726")
		glint = Color("768553")
	elif kind=="mirror_pool":
		depth = Color("101827")
		stone = Color("2a2b36")
		glint = Color("7a7395")
	elif str(item.get("biome_id",""))=="B04":
		stone = Color("262633")
		glint = Color("6b617d")
	canvas.draw_colored_polygon(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]),depth)
	# Uneven dark strata descend INSIDE the true void. No bright rectangle rim,
	# pedestal or filled platform is placed beneath terrain or independent props.
	for edge: int in range(4):
		var horizontal: bool = edge%2==0
		var length: float = rect.size.x if horizontal else rect.size.y
		var count: int = maxi(2,int(length/42.0))
		for index: int in range(count):
			var from: float = float(index)/count
			var to: float = float(index+1)/count
			var inset: float = 5+_variation(index+edge*37,seed_value)*18
			var a: Vector2
			var b: Vector2
			var inward: Vector2
			match edge:
				0:
					a = rect.position+Vector2(rect.size.x*from,0)
					b = rect.position+Vector2(rect.size.x*to,0)
					inward = Vector2.DOWN
				1:
					a = Vector2(rect.end.x,rect.position.y+rect.size.y*from)
					b = Vector2(rect.end.x,rect.position.y+rect.size.y*to)
					inward = Vector2.LEFT
				2:
					a = Vector2(rect.position.x+rect.size.x*from,rect.end.y)
					b = Vector2(rect.position.x+rect.size.x*to,rect.end.y)
					inward = Vector2.UP
				_:
					a = rect.position+Vector2(0,rect.size.y*from)
					b = rect.position+Vector2(0,rect.size.y*to)
					inward = Vector2.RIGHT
			var tip: Vector2 = a.lerp(b,0.4+_variation(index,edge+seed_value)*0.2)+inward*inset
			canvas.draw_colored_polygon(PackedVector2Array([a,b,b.lerp(tip,0.8),tip]),stone.darkened(_variation(index,seed_value)*0.35))
	var inner: Rect2 = rect.grow(-28)
	if not inner.has_area(): return
	for index: int in range(maxi(4,int(rect.get_area()/19000.0))):
		var at: Vector2 = inner.position+Vector2(_variation(index,seed_value),_variation(index,seed_value+19))*inner.size
		var radius: float = 5+_variation(index,27)*13
		if fluid:
			canvas.draw_arc(at,radius,0.25,2.7,12,Color(glint,0.12+sin(time*0.45+index)*0.025),1.0,true)
			if kind=="acid_reservoir" and index%3==0: canvas.draw_circle(at,radius*0.35,Color(glint,0.1))
		else:
			canvas.draw_line(at,at+Vector2(radius*0.5,radius),Color(stone,0.3),1.0,true)

static func _draw_mirror_pool(canvas: CanvasItem, rect: Rect2, seed_value: int, time: float) -> void:
	var floor_texture: Texture2D = _texture("res://assets/generated/world/B04_floor_v1.png")
	var corners := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	canvas.draw_colored_polygon(corners,Color("1b1822"))
	if floor_texture!=null:
		# Native world-aligned rock continues right up to the lip. Drawing only
		# inside this rect preserves every existing safe causeway and footpath.
		_native_rock_patch(canvas,rect,floor_texture,Color(0.55,0.51,0.61,1.0))
	var water: PackedVector2Array = _pool_outline(rect,seed_value)
	canvas.draw_colored_polygon(water,Color("0c1119"))
	if floor_texture!=null:
		var source_size: Vector2 = Vector2(minf(rect.size.x,floor_texture.get_width()),minf(rect.size.y,floor_texture.get_height()))
		var source_origin: Vector2 = Vector2(_variation(7,seed_value),_variation(19,seed_value))*(floor_texture.get_size()-source_size)
		var reflected_uv := PackedVector2Array()
		for point: Vector2 in water:
			var local: Vector2 = (point-rect.position)/rect.size
			local.y = 1.0-local.y
			reflected_uv.append((source_origin+local*source_size)/floor_texture.get_size())
		# The pool carries a faint, inverted rock reflection rather than a flat
		# navy fill. Runtime UVs/modulation leave the authored PNG unchanged.
		canvas.draw_polygon(water,PackedColorArray([Color(0.48,0.49,0.61,0.72)]),reflected_uv,floor_texture)
	_ellipse(canvas,rect.get_center()+Vector2(8,12),rect.size*Vector2(0.34,0.31),Color(0.004,0.008,0.018,0.16))
	_ellipse(canvas,rect.get_center()+Vector2(-18,3),rect.size*Vector2(0.26,0.24),Color(0.004,0.008,0.018,0.11))
	var lip: PackedVector2Array = water.duplicate()
	lip.append(water[0])
	# Uneven contact shadows give the exposed slate an inward drop. These
	# contours follow the natural shoreline, with no rectangular frame or teeth.
	canvas.draw_polyline(lip,Color(0.015,0.012,0.021,0.58),12.0,true)
	canvas.draw_polyline(lip,Color(0.065,0.059,0.081,0.55),3.0,true)
	for index: int in range(water.size()):
		var a: Vector2 = water[index]
		var b: Vector2 = water[(index+1)%water.size()]
		var inward: Vector2 = (rect.get_center()-a.lerp(b,0.5)).normalized()
		if index%3!=0:
			canvas.draw_line(a.lerp(b,0.12)-inward*3,b.lerp(a,0.25)-inward*3,Color(0.33,0.30,0.36,0.20),1.2,true)
		if index%4==0:
			var at: Vector2 = a.lerp(b,0.45)-inward*7
			canvas.draw_line(at,at-inward*7+(b-a).normalized()*5,Color(0.10,0.075,0.13,0.48),2.0,true)
	var inner: Rect2 = rect.grow(-52)
	if not inner.has_area(): return
	for index: int in range(maxi(4,int(rect.get_area()/18000.0))):
		var at: Vector2 = inner.position+Vector2(_variation(index,seed_value+33),_variation(index,seed_value+77))*inner.size
		var radius: float = 9+_variation(index,seed_value+11)*17
		var phase: float = sin(time*0.42+index*1.7)
		var start: float = -2.7+_variation(index,seed_value)*0.9
		_pool_ripple(canvas,at,radius,start,start+1.7,Color(0.49,0.51,0.61,0.11+phase*0.015))
		if index%3==0:
			_pool_ripple(canvas,at+Vector2(3,2),radius*1.65,start+0.2,start+1.25,Color(0.34,0.37,0.48,0.08))

static func _pool_outline(rect: Rect2, seed_value: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corner: float = minf(36.0,minf(rect.size.x,rect.size.y)*0.15)
	for edge: int in range(4):
		var length: float = rect.size.x if edge%2==0 else rect.size.y
		var distance: float = corner
		var index: int = 0
		var depth: float = 14.0
		while distance<=length-corner:
			depth = lerpf(depth,11+_variation(index+edge*31,seed_value)*17,0.65)
			match edge:
				0: points.append(rect.position+Vector2(distance,depth))
				1: points.append(Vector2(rect.end.x-depth,rect.position.y+distance))
				2: points.append(Vector2(rect.end.x-distance,rect.end.y-depth))
				_: points.append(Vector2(rect.position.x+depth,rect.end.y-distance))
			if is_equal_approx(distance,length-corner): break
			distance = minf(length-corner,distance+28+_variation(index+edge*43,seed_value+51)*41)
			index += 1
	return points

static func _native_rock_patch(canvas: CanvasItem, rect: Rect2, texture: Texture2D, tint: Color) -> void:
	var size: Vector2 = texture.get_size()
	var top: float = rect.position.y
	while top<rect.end.y:
		var row: int = int(floor(top/size.y))
		var bottom: float = minf(rect.end.y,(row+1)*size.y)
		var left: float = rect.position.x
		while left<rect.end.x:
			var col: int = int(floor(left/size.x))
			var right: float = minf(rect.end.x,(col+1)*size.x)
			var start: Vector2 = Vector2(left/size.x-col,top/size.y-row)
			var finish: Vector2 = Vector2(right/size.x-col,bottom/size.y-row)
			if col%2!=0:
				start.x = 1.0-start.x
				finish.x = 1.0-finish.x
			if row%2!=0:
				start.y = 1.0-start.y
				finish.y = 1.0-finish.y
			var quad := PackedVector2Array([Vector2(left,top),Vector2(right,top),Vector2(right,bottom),Vector2(left,bottom)])
			var uv := PackedVector2Array([start,Vector2(finish.x,start.y),finish,Vector2(start.x,finish.y)])
			canvas.draw_polygon(quad,PackedColorArray([tint]),uv,texture)
			left = right
		top = bottom

static func _pool_ripple(canvas: CanvasItem, at: Vector2, radius: float, start: float, end: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(15):
		points.append(at+Vector2.from_angle(lerpf(start,end,float(index)/14.0))*Vector2(radius,radius*0.36))
	canvas.draw_polyline(points,color,1.0,true)
