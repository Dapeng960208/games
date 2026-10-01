class_name RoomAppearance
extends RefCounted
## Warm ruin surfaces and naturally proportioned props share one ground plane.
## Placement and collision belong to RoomLayouts; edge gardens stay harmless.

const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const Art = preload("res://scripts/world/world_art.gd")
const PropArt = preload("res://scripts/world/world_prop_art.gd")
const Identity = preload("res://scripts/world/prop_identity.gd")
const Perimeter = preload("res://scripts/world/perimeter_art.gd")
const VOID_KINDS := ["mine_pit", "gear_gap", "suspended_void", "water_channel", "floating_platform_gap", "ventilation_shaft", "acid_reservoir", "gantry_void", "mirror_pool", "deep_rift", "echo_disc_gap"]
const BRIDGE_GAP_ROOMS := ["L02","L13","L23"]
const TERRAIN_TEXTURE_WORLD_SIZE := 420.0
static var _art_regions: Dictionary = {}
static var _mineral_recipes: Dictionary = {}

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
	for instance: Dictionary in layout.get("decoration_instances", []):
		var item: Dictionary = instance.duplicate(true)
		item["rect"] = Rect2(item.get("position", Vector2.ZERO), Vector2.ZERO)
		item["collision_rect"] = item.rect
		item["index"] = result.size()
		item["biome_id"] = biome_id
		item["room_id"] = room_id
		item["destroyed"] = bool(item.get("destroyed", false))
		item["static"] = false
		var composition: Array = PropArt.composition_for_asset(str(item.get("asset",""))) if "fixed_landmark" in item.get("tags",[]) else []
		if composition.is_empty():
			result.append(item)
		else:
			# A named landmark is a purposeful cluster, assembled from its own
			# faction's art. Every child still sorts at its separate contact foot.
			for part: int in range(composition.size()):
				var child: Dictionary = item.duplicate(true)
				child["id"] = str(item.get("id","landmark"))+":part:"+str(part)
				child["asset"] = str(composition[part])
				var offset := Vector2.ZERO if part==0 else Vector2(-92 if part%2==1 else 92,24)
				child["position"] = Vector2(item.get("position",Vector2.ZERO))+offset
				child["rect"] = Rect2(child.position,Vector2.ZERO)
				child["collision_rect"] = child.rect
				child["visual_size"] = Vector2(220,195) if part==0 else Vector2(126,135)
				result.append(child)
	return Identity.unique_scenery(result,layout,biome_id)

static func draw_floor(_canvas: CanvasItem, _layout: Dictionary, _biome_id: String, _time: float = 0.0) -> void:
	# MineBackdrop owns the continuous limestone courtyard surface.
	pass

static func draw_obstacles(canvas: CanvasItem, recipes: Array, time: float = 0.0) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for item: Dictionary in recipes:
		if bool(item.get("destroyed", false)): continue
		if bool(item.get("static", false)):
			_draw_void(canvas, item, time)
		else:
			_draw_instance(canvas, item)

static func draw_ground_obstacles(canvas: CanvasItem, recipes: Array, time: float = 0.0) -> void:
	# Recessed water and cast shadows belong to the ground. Raised props are
	# submitted by separate depth-sorted nodes, each at its actual contact foot.
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for item: Dictionary in recipes:
		if bool(item.get("destroyed",false)): continue
		var rect: Rect2 = item.get("collision_rect",Rect2())
		if bool(item.get("static",false)):
			if is_recessed_terrain(item):
				var gap: Dictionary = item.duplicate()
				gap["force_recessed"] = true
				_draw_void(canvas,gap,time)
			elif rect.has_area():
				_draw_cast_shadow(canvas,rect,120.0 if int(item.get("index",0))%3==0 else 65.0,str(item.get("biome_id","B01")))
		else:
			if PropArt.is_ground_inlay(str(item.get("asset",""))):
				_draw_ground_inlay(canvas,item)
				continue
			# Painted sprites already contain their local sunlight/shadow. The old
			# rectangular cast-shadow extrusion would stamp dark blocks on the
			# continuous environment, unrelated to these new object silhouettes.
			if PropArt.has_authored_asset(str(item.get("asset",""))): continue
			var height: float = minf(95.0,Vector2(item.get("visual_size",Vector2(60,80))).y*0.55)
			if rect.has_area(): _draw_cast_shadow(canvas,rect,height,str(item.get("biome_id","B01")))

static func depth_recipe(layout: Dictionary, biome_id: String, obstacle_recipes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for original: Dictionary in obstacle_recipes:
		if bool(original.get("destroyed",false)): continue
		if PropArt.is_ground_inlay(str(original.get("asset",""))): continue
		var item: Dictionary = original.duplicate(true)
		var rect: Rect2 = item.get("collision_rect",Rect2())
		if not str(item.get("architecture_key","")).is_empty():
			item["depth_kind"] = "architecture"
			item["architecture"] = str(item.architecture_key)
			item["foot"] = rect.get_center()
			item["art_size"] = Vector2(item.get("visual_size",Vector2(145,270)))
			item["visual_bounds"] = architecture_bounds(item.architecture,item.foot,item.art_size,biome_id)
			item["occludes"] = true
		elif bool(item.get("static",false)):
			if is_recessed_terrain(item): continue
			item["depth_kind"] = "island"
			item["foot"] = Vector2(rect.get_center().x,rect.end.y)
			var index: int = int(item.get("index",0))
			item["architecture"] = "column" if index%3==0 else ("wall_horizontal" if rect.size.x >= rect.size.y else "wall_vertical")
			item["art_size"] = Vector2(minf(170,rect.size.x*0.8),220) if index%3==0 else Vector2(minf(230,rect.size.x*0.92),165)
			item["visual_bounds"] = architecture_bounds(item.architecture,Vector2(item.foot)-Vector2(0,26),item.art_size,biome_id)
			item["occludes"] = true
		else:
			item["depth_kind"] = "prop"
			var fresh: bool = PropArt.has_authored_asset(str(item.get("asset","")))
			var source_path: String = _asset_path(str(item.get("asset",""))) if fresh or not "non_solid" in item.get("tags",[]) else Art.EDGE_PATH
			var source_texture: Texture2D = PropArt.texture_for_asset(str(item.get("asset",""))) if fresh else _texture(source_path)
			if source_texture==null: continue
			var source_size: Vector2 = source_texture.get_size() if fresh else _source_region(source_path,source_texture).size
			var quad: PackedVector2Array = _sprite_quad(item,source_size)
			if quad.size()!=4: continue
			var visual := Rect2(quad[0],Vector2.ZERO)
			for point: Vector2 in quad: visual = visual.expand(point)
			item["foot"] = (rect.get_center() if rect.has_area() else Vector2(item.get("position",Vector2.ZERO))) if fresh else Vector2(visual.get_center().x,visual.end.y)
			item["visual_bounds"] = visual
			item["occludes"] = visual.size.y>105.0
		result.append(item)
	result.append_array(Perimeter.recipes(layout,biome_id,Identity.used_identities(obstacle_recipes)))
	return result

static func is_recessed_terrain(item: Dictionary) -> bool:
	var kind: String = str(item.get("kind",""))
	return kind in ["water_channel","acid_reservoir","mirror_pool"] or (str(item.get("room_id","")) in BRIDGE_GAP_ROOMS and kind in VOID_KINDS)

static func faction_architecture_asset(key: String, biome_id: String) -> String:
	if key=="arch": return "" # The existing exit keeps its open passage.
	match biome_id:
		"B02": return "B02_spore_nest" if key=="column" else "B02_root_barrier"
		"B03": return "B03_transformer" if key=="column" else "B03_pipe_manifold"
		"B04": return "B04_resonance_obelisk" if key=="column" else "B04_crystal_cluster"
	return ""

static func architecture_definition(key: String, biome_id: String = "B01") -> Dictionary:
	var asset: String = faction_architecture_asset(key,biome_id)
	return PropArt.definition_for_asset(asset) if not asset.is_empty() and PropArt.has_authored_asset(asset) else Art.architecture_region(key)

static func architecture_ground(key: String, foot: Vector2, target_size: Vector2, biome_id: String = "B01") -> Rect2:
	var definition: Dictionary = architecture_definition(key,biome_id)
	if definition.is_empty(): return Rect2()
	var scale: float = minf(target_size.x/definition.source.size.x,target_size.y/definition.source.size.y)
	return Rect2(foot+(Vector2(definition.ground.position)-Vector2(definition.foot))*scale,Vector2(definition.ground.size)*scale)

static func architecture_bounds(key: String, foot: Vector2, target_size: Vector2, biome_id: String = "B01") -> Rect2:
	var asset: String = faction_architecture_asset(key,biome_id)
	if not asset.is_empty() and PropArt.has_authored_asset(asset): return PropArt.bounds_at(asset,foot,target_size)
	var definition: Dictionary = Art.architecture_region(key)
	if definition.is_empty(): return Rect2(foot-Vector2(target_size.x*0.5,target_size.y),target_size)
	var region: Rect2 = definition.source
	var scale: float = minf(target_size.x/region.size.x,target_size.y/region.size.y)
	return Rect2(foot-Vector2(definition.foot)*scale,region.size*scale)

static func draw_depth_item(canvas: Node2D, item: Dictionary) -> void:
	# Draw commands use world coordinates while each node sorts at its foot.
	# Translating only the canvas command matrix keeps physics positions intact.
	canvas.draw_set_transform(-canvas.position)
	match str(item.get("depth_kind","")):
		"prop": _draw_instance(canvas,item)
		"island":
			var rect: Rect2 = item.get("collision_rect",Rect2())
			_draw_raised_plinth(canvas,rect,str(item.get("biome_id","B01")))
			_draw_architecture(canvas,str(item.get("architecture","rock_island")),Vector2(item.foot)-Vector2(0,26),item.get("art_size",Vector2(150,180)),str(item.get("biome_id","B01")))
		"architecture": _draw_architecture(canvas,str(item.get("architecture","column")),item.get("foot",Vector2.ZERO),item.get("art_size",Vector2(160,290)),str(item.get("biome_id","B01")))
		"perimeter": Perimeter.draw_item(canvas,item)
	canvas.draw_set_transform(Vector2.ZERO)

static func _draw_cast_shadow(canvas: CanvasItem, rect: Rect2, height: float, biome: String) -> void:
	var colors: Dictionary = Art.palette(biome)
	var drift := Vector2(height*0.45,height*0.31)
	var contour := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end+drift,Vector2(rect.position.x,rect.end.y)+drift])
	canvas.draw_colored_polygon(contour,Color(colors.shadow,0.14))
	_ellipse(canvas,rect.get_center()+Vector2(0,rect.size.y*0.12),rect.size*Vector2(0.54,0.40),Color(colors.shadow,0.13))

static func _draw_ground_inlay(canvas: CanvasItem, item: Dictionary) -> void:
	var foot: Vector2 = item.get("position",Vector2.ZERO)
	var size: Vector2 = item.get("visual_size",Vector2(170,110))
	var colors: Dictionary = Art.palette(str(item.get("biome_id","B04")))
	canvas.draw_set_transform(foot,0,Vector2(1,.70))
	if "woven_mat" in str(item.get("asset","")):
		var rect := Rect2(-size*.36,size*.72)
		canvas.draw_rect(rect,Color("cd8e69"))
		canvas.draw_rect(rect,Color("68568b"),false,3)
		for index: int in range(5):
			var x: float = rect.position.x+rect.size.x*(float(index)+.5)/5
			canvas.draw_line(Vector2(x,rect.position.y),Vector2(x,rect.end.y),Color(colors.stone,.40),2,true)
	else:
		var radius: float = minf(size.x*.42,size.y*.60)
		canvas.draw_arc(Vector2.ZERO,radius,0,TAU,48,Color("786088"),3,true)
		canvas.draw_arc(Vector2.ZERO,radius*.70,0,TAU,40,Color(colors.gold,.82),2,true)
		for index: int in range(8):
			var direction := Vector2.from_angle(index*TAU/8)
			canvas.draw_line(direction*radius*.72,direction*radius*.98,Color("aa704c"),4,true)
	canvas.draw_set_transform(Vector2.ZERO)

static func _draw_raised_plinth(canvas: CanvasItem, rect: Rect2, biome: String) -> void:
	if not rect.has_area(): return
	var colors: Dictionary = Art.palette(biome)
	var lift := Vector2(0,-26.0)
	var top: Rect2 = Rect2(rect.position+lift,rect.size)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(top.position.x,top.end.y),top.end,rect.end,Vector2(rect.position.x,rect.end.y)]),colors.stone_side)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(top.end.x,top.position.y),top.end,rect.end,Vector2(rect.end.x,rect.position.y)]),colors.stone_side.darkened(0.10))
	canvas.draw_rect(top,colors.stone)
	var surface: Dictionary = Art.floor_definition(biome)
	var texture: Texture2D = _texture(str(surface.path))
	if texture!=null: canvas.draw_texture_rect_region(texture,top,surface.source,PropArt.authored_tint(),false,true)
	canvas.draw_line(Vector2(top.position.x,top.end.y),top.end,colors.stone.lightened(0.08),3.0,true)
	canvas.draw_line(Vector2(rect.position.x,rect.end.y),rect.end,Color(colors.seam,0.55),1.8,true)
	for x: float in range(int(rect.position.x+34),int(rect.end.x),46):
		canvas.draw_line(Vector2(x,top.end.y+4),Vector2(x,rect.end.y-2),Color(colors.seam,0.40),1.1,true)

static func _draw_architecture(canvas: CanvasItem, key: String, foot: Vector2, target_size: Vector2, biome: String) -> void:
	var asset: String = faction_architecture_asset(key,biome)
	if not asset.is_empty() and PropArt.has_authored_asset(asset):
		PropArt.draw_asset(canvas,asset,foot,target_size)
		return
	var definition: Dictionary = Art.architecture_region(key)
	var texture: Texture2D = _texture(Art.ARCHITECTURE_PATH)
	if texture==null or definition.is_empty():
		# The raised base remains coherent while freshly authored art imports.
		var colors: Dictionary = Art.palette(biome)
		var width: float = minf(60,target_size.x*0.35)
		canvas.draw_rect(Rect2(foot-Vector2(width*0.5,target_size.y*0.72),Vector2(width,target_size.y*0.72)),colors.stone)
		canvas.draw_rect(Rect2(foot-Vector2(width*0.5+6,10),Vector2(width+12,10)),colors.stone_side)
		return
	var region: Rect2 = definition.source
	var destination: Rect2 = architecture_bounds(key,foot,target_size,biome)
	canvas.draw_texture_rect_region(texture,destination,region,Art.architecture_tint(biome),false,true)

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
	if not str(item.get("architecture_key","")).is_empty():
		var rect: Rect2 = item.get("collision_rect",Rect2())
		_draw_architecture(canvas,str(item.architecture_key),rect.get_center(),item.get("visual_size",Vector2(145,270)),str(item.get("biome_id","B01")))
		return
	var asset: String = str(item.get("asset", ""))
	if asset.is_empty(): return
	var decorative: bool = "non_solid" in item.get("tags", [])
	var fresh: bool = PropArt.has_authored_asset(asset)
	var path: String = _asset_path(asset) if fresh or not decorative else Art.EDGE_PATH
	var texture: Texture2D = PropArt.texture_for_asset(asset) if fresh else _texture(path)
	if texture == null: return
	var source: Rect2 = Rect2(Vector2.ZERO,texture.get_size()) if fresh else _source_region(path,texture)
	if not source.has_area(): return
	var quad: PackedVector2Array = _sprite_quad(item,source.size)
	if quad.size() != 4: return
	var collision: Rect2 = item.get("collision_rect", Rect2())
	# A small contact shadow follows only this prop's footprint. It never fills
	# the gap to another prop; every such real gap remains visibly open ground.
	if collision.has_area():
		var at: Vector2 = collision.get_center()+Vector2(0,collision.size.y*0.08)
		if fresh:
			_ellipse(canvas,at,collision.size*Vector2(0.44,0.25),Color(0.30,0.32,0.28,0.065))
		else:
			_ellipse(canvas,at,collision.size*Vector2(0.56,0.43),Color(0.30,0.37,0.34,0.10))
			_ellipse(canvas,at,collision.size*Vector2(0.43,0.31),Color(0.25,0.30,0.28,0.12))
	# Polygon commands need the parent texture's absolute atlas UVs; passing
	# an AtlasTexture RID with 0..1 UVs would incorrectly draw all six props.
	if fresh:
		var definition: Dictionary = PropArt.definition_for_asset(asset)
		texture = _texture(str(definition.path))
		source = definition.source
	var uv_start: Vector2 = source.position/texture.get_size()
	var uv_end: Vector2 = source.end/texture.get_size()
	var uvs := PackedVector2Array([uv_start,Vector2(uv_end.x,uv_start.y),uv_end,Vector2(uv_start.x,uv_end.y)])
	# Rotating vertex positions leaves the caller's canvas transform untouched.
	# Fresh cream masonry keeps its authored palette; only older machinery
	# needs the image grade on this canvas. Both use the same stable alpha UVs.
	var tint := PropArt.authored_tint() if fresh or decorative else Color.WHITE
	canvas.draw_polygon(quad,PackedColorArray([tint]),uvs,texture)

static func _sprite_quad(item: Dictionary, source_size: Vector2) -> PackedVector2Array:
	if PropArt.has_authored_asset(str(item.get("asset",""))):
		return PropArt.sprite_quad(item)
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
	if "non_solid" in item.get("tags", []):
		var visual: Rect2 = item.get("visual_rect", Rect2(position-bounds*0.5,bounds))
		center = visual.get_center()
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

static func _terrain_palette(kind: String, biome: String) -> Dictionary:
	var colors: Dictionary = Art.palette(biome)
	var result: Dictionary = {"face":colors.stone_side,"rim":colors.stone,"depth":colors.water.darkened(0.12),"texture":Color(colors.accent,0.16),"liquid":false}
	if kind in ["water_channel","acid_reservoir","mirror_pool"]:
		result.liquid = true
		result.depth = colors.water if kind == "water_channel" else Color("94b869")
		result.texture = Color(colors.leaf,0.24)
		if kind == "mirror_pool":
			result.depth = colors.water.lightened(0.08)
			result.texture = Color(colors.accent,0.24)
	return result

static func _terrain_outline(rect: Rect2, seed_value: int, inset: float = 0.0) -> PackedVector2Array:
	# The exposed upper lip remains within six units of the real collision
	# edge. Only the rock below it recedes; no invisible rectangular border.
	var points := PackedVector2Array()
	if not rect.has_area(): return points
	var short_side: float = minf(rect.size.x,rect.size.y)
	for edge: int in range(4):
		var length: float = rect.size.x if edge%2==0 else rect.size.y
		var count: int = maxi(3,ceili(length/58.0))
		for index: int in range(count):
			var along: float = length*float(index)/count
			var depth: float = minf(2.0+_variation(index+edge*37,seed_value)*4.0,short_side*0.08)
			match edge:
				0: points.append(rect.position+Vector2(along,depth))
				1: points.append(Vector2(rect.end.x-depth,rect.position.y+along))
				2: points.append(Vector2(rect.end.x-along,rect.end.y-depth))
				_: points.append(Vector2(rect.position.x+depth,rect.end.y-along))
			# Follow a ray toward the center for each layer. Keeping the same rays
			# prevents adjacent rock faces crossing at a narrow shaft's corners.
			var point: Vector2 = points[points.size()-1]
			var distance: float = minf(inset*(0.58+_variation(index+edge*11,seed_value+29)*0.84),short_side*0.22)
			points[points.size()-1] = point.move_toward(rect.get_center(),distance)
	return points

static func _terrain_layers(rect: Rect2, seed_value: int, liquid: bool = false) -> Dictionary:
	var upper: PackedVector2Array = _terrain_outline(rect,seed_value)
	var lip := PackedVector2Array()
	var lower := PackedVector2Array()
	var limit: float = minf(60.0,minf(rect.size.x,rect.size.y)*0.22)
	for index: int in range(upper.size()):
		# The same ordered rays form every layer. Receding faces cannot cross,
		# even in a narrow shaft; depths are world units, never a stretched UV.
		var depth: float = minf(24.0+36.0*_variation(index,seed_value+53),limit)
		if liquid: depth *= 0.72
		var to_center: Vector2 = upper[index].direction_to(rect.get_center())
		lip.append(upper[index]+to_center*depth*(0.20+0.14*_variation(index,seed_value+19)))
		lower.append(upper[index]+to_center*depth)
	return {"upper":upper,"lip":lip,"lower":lower}

static func _terrain_texture_patches(polygon: PackedVector2Array, reflected: bool = false) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	if polygon.size()<3: return patches
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon: bounds = bounds.expand(point)
	var first := Vector2i(floori(bounds.position.x/TERRAIN_TEXTURE_WORLD_SIZE),floori(bounds.position.y/TERRAIN_TEXTURE_WORLD_SIZE))
	var last := Vector2i(ceili(bounds.end.x/TERRAIN_TEXTURE_WORLD_SIZE)-1,ceili(bounds.end.y/TERRAIN_TEXTURE_WORLD_SIZE)-1)
	for y: int in range(first.y,last.y+1):
		for x: int in range(first.x,last.x+1):
			var origin := Vector2(x,y)*TERRAIN_TEXTURE_WORLD_SIZE
			var tile := Rect2(origin,Vector2.ONE*TERRAIN_TEXTURE_WORLD_SIZE)
			var clip := PackedVector2Array([tile.position,Vector2(tile.end.x,tile.position.y),tile.end,Vector2(tile.position.x,tile.end.y)])
			var pieces: Array[PackedVector2Array] = []
			if first==last:
				pieces.append(polygon)
			else:
				pieces = Geometry2D.intersect_polygons(polygon,clip)
			for piece: PackedVector2Array in pieces:
				if piece.size()<3: continue
				var indices: PackedInt32Array = _terrain_triangle_indices(piece)
				if indices.is_empty():
					push_error("Unable to triangulate clipped terrain: "+str(piece))
					continue
				var uv := PackedVector2Array()
				for point: Vector2 in piece:
					var local: Vector2 = ((point-origin)/TERRAIN_TEXTURE_WORLD_SIZE).clamp(Vector2.ZERO,Vector2.ONE)
					if posmod(x,2)==1: local.x = 1.0-local.x
					if (posmod(y,2)==1)!=reflected: local.y = 1.0-local.y
					uv.append(local)
				patches.append({"polygon":piece,"uv":uv,"indices":indices})
	return patches

static func _terrain_triangle_indices(polygon: PackedVector2Array) -> PackedInt32Array:
	if polygon.size()<3: return PackedInt32Array()
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon: bounds = bounds.expand(point)
	if not bounds.has_area(): return PackedInt32Array()
	# World-coordinate float32 area sums can round a real tile-corner triangle
	# to zero. Triangulate an affine-normalized copy, retaining the exact original
	# positions and UVs for drawing; even subpixel texture fragments are preserved.
	var local := PackedVector2Array()
	for point: Vector2 in polygon: local.append((point-bounds.position)/bounds.size)
	return Geometry2D.triangulate_polygon(local)

static func _draw_terrain_texture(canvas: CanvasItem, polygon: PackedVector2Array, texture: Texture2D, tint: Color, reflected: bool = false) -> void:
	if texture == null: return
	# CanvasItem repeat is shared by all queued draw commands. Explicit mirrored
	# tiles keep UVs in 0..1 without changing the caller's prop sampling state.
	for patch: Dictionary in _terrain_texture_patches(polygon,reflected):
		# Explicit indices avoid draw_polygon re-triangulating distant world points.
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),patch.indices,patch.polygon,PackedColorArray([tint]),patch.uv,PackedInt32Array(),PackedFloat32Array(),texture.get_rid())

static func _draw_void(canvas: CanvasItem, item: Dictionary, time: float) -> void:
	var rect: Rect2 = item.get("collision_rect",item.get("rect",Rect2()))
	if not rect.has_area(): return
	var kind: String = str(item.get("kind","mine_pit"))
	var biome: String = str(item.get("biome_id","B01"))
	var seed_value: int = int(item.get("index",0))+str(item.get("room_id","")).hash()%101
	var colors: Dictionary = _terrain_palette(kind,biome)
	if not bool(colors.liquid) and not bool(item.get("force_recessed",false)):
		_draw_mineral_obstruction(canvas,rect,seed_value,biome)
		return
	var layers: Dictionary = _terrain_layers(rect,seed_value,bool(colors.liquid))
	var upper: PackedVector2Array = layers.upper
	var lip: PackedVector2Array = layers.lip
	var lower: PackedVector2Array = layers.lower
	var texture: Texture2D = _texture(Art.FLOOR_PATH)
	# Bright teal water remains clearly recessed behind a pale stone lip.
	canvas.draw_colored_polygon(upper,colors.depth)
	_draw_terrain_texture(canvas,lower,texture,colors.texture,bool(colors.liquid))
	for index: int in range(upper.size()):
		var next: int = (index+1)%upper.size()
		var wall := PackedVector2Array([upper[index],upper[next],lower[next],lower[index]])
		canvas.draw_colored_polygon(wall,colors.face)
		# The sunlit lip retains subtle stone texture above the teal water.
		_draw_terrain_texture(canvas,wall,texture,Color(colors.face,0.45))
		var upper_shadow := Color(colors.depth,0.02)
		var lower_shadow := Color(colors.depth,0.24)
		canvas.draw_polygon(wall,PackedColorArray([upper_shadow,upper_shadow,lower_shadow,lower_shadow]))
		if index%4==1:
			var crack_start: Vector2 = upper[index].lerp(upper[next],0.34)
			var crack_end: Vector2 = lip[index].lerp(lip[next],0.40)
			canvas.draw_line(crack_start,crack_end,Color(colors.depth,0.26),1.0,true)
	canvas.draw_polyline(upper+PackedVector2Array([upper[0]]),Color(colors.rim,0.88),2.0,true)
	if bool(colors.liquid): _draw_water_surface(canvas,rect,seed_value,time,colors)

static func _mineral_rock_source(index: int) -> PackedVector2Array:
	# Stable irregular contours sample the new limestone texture. The same
	# contour rays preserve the existing visible, collision-aligned footprint.
	match posmod(index,4):
		0: return PackedVector2Array([Vector2(222,126),Vector2(271,175),Vector2(310,244),Vector2(294,279),Vector2(243,271),Vector2(185,230),Vector2(190,174)])
		1: return PackedVector2Array([Vector2(418,338),Vector2(476,351),Vector2(509,391),Vector2(494,452),Vector2(443,493),Vector2(387,465),Vector2(395,394)])
		2: return PackedVector2Array([Vector2(840,565),Vector2(901,577),Vector2(962,617),Vector2(967,678),Vector2(925,726),Vector2(852,693),Vector2(826,632)])
		_: return PackedVector2Array([Vector2(749,1009),Vector2(788,1026),Vector2(840,1061),Vector2(839,1123),Vector2(811,1163),Vector2(751,1152),Vector2(743,1081)])

static func _mineral_obstruction_recipe(rect: Rect2, seed_value: int) -> Array[Dictionary]:
	var key: String = str(rect)+":"+str(seed_value)
	if _mineral_recipes.has(key): return _mineral_recipes[key]
	var rocks: Array[Dictionary] = []
	if not rect.has_area(): return rocks
	var rows: int = maxi(2,ceili(rect.size.y/78.0))
	var columns: int = maxi(2,ceili(rect.size.x/90.0))
	var cell: Vector2 = rect.size/Vector2(columns,rows)
	for row: int in range(rows):
		for column: int in range(columns):
			var index: int = row*columns+column
			var at: Vector2 = rect.position+cell*Vector2(column+0.5,row+0.63)
			# Offset alternate rows so the silhouette reads as loose rubble, not
			# paving blocks aligned to the rectangular navigation footprint.
			var stagger: float = 0.20 if row%2==1 else -0.20
			if column==0 or column==columns-1: stagger = 0.0
			at += cell*Vector2(stagger+(_variation(index,seed_value+43)-0.5)*0.22,(_variation(index,seed_value+61)-0.5)*0.16)
			var edge_distance: float = minf(minf(at.x-rect.position.x,rect.end.x-at.x),minf(at.y-rect.position.y,rect.end.y-at.y))
			var mound: float = clampf(edge_distance/100.0,0.0,1.0)
			var height: float = 6.0+mound*(12.0+_variation(index,seed_value+71)*17.0)
			var half: Vector2 = cell*Vector2(0.77+_variation(index,seed_value+5)*0.15,0.86+_variation(index,seed_value+9)*0.12)
			half.x = minf(half.x,minf(at.x-rect.position.x,rect.end.x-at.x)-2)
			half.y = minf(half.y,minf(at.y-height-rect.position.y,rect.end.y-at.y)-2)
			if half.x<=0 or half.y<=0: continue
			var source: PackedVector2Array = _mineral_rock_source(index+seed_value)
			var source_bounds := Rect2(source[0],Vector2.ZERO)
			for point: Vector2 in source: source_bounds = source_bounds.expand(point)
			var top := PackedVector2Array()
			for point: Vector2 in source:
				var local: Vector2 = (point-source_bounds.position)/source_bounds.size-Vector2.ONE*0.5
				top.append(at-Vector2(0,height)+local*half*2.0)
			rocks.append({"top":top,"source":source,"height":height,"tone":0.92+_variation(index,seed_value+29)*0.20,"index":index})
	# Bound the presentation cache while preserving the current room's recipes.
	if _mineral_recipes.size()>=64: _mineral_recipes.clear()
	_mineral_recipes[key] = rocks
	return rocks

static func _draw_mineral_obstruction(canvas: CanvasItem, rect: Rect2, seed_value: int, biome: String) -> void:
	var rock_texture: Texture2D = _texture(Art.FLOOR_PATH)
	if rock_texture==null: return
	var colors: Dictionary = Art.palette(biome)
	var tint := Color(1.0,1.0,0.99)
	match biome:
		"B02": tint = Color(0.90,1.0,0.90)
		"B03": tint = Color(0.97,0.91,1.0)
		"B04": tint = Color(0.88,0.99,1.0)
	# Overlapping cream stone faces fill the blocked footprint. Their shallow
	# side shadows retain height without the old dark cliff treatment.
	for rock: Dictionary in _mineral_obstruction_recipe(rect,seed_value):
		var top: PackedVector2Array = rock.top
		var drop := Vector2(0,rock.height)
		var shadow := PackedVector2Array()
		for point: Vector2 in top: shadow.append(point+drop)
		canvas.draw_colored_polygon(shadow,Color(colors.stone_side,0.70))
		# The lower/right faces remain narrow and visibly raised.
		for edge: int in range(2,6):
			var next: int = (edge+1)%top.size()
			var face := PackedVector2Array([top[edge],top[next],top[next]+drop,top[edge]+drop])
			# Matching edge UVs keep the limestone grain continuous at each side.
			var a: Vector2 = rock.source[edge]/rock_texture.get_size()
			var b: Vector2 = rock.source[next]/rock_texture.get_size()
			var side_uv := PackedVector2Array([a,b,b+Vector2(0,0.012),a+Vector2(0,0.012)])
			RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),_terrain_triangle_indices(face),face,PackedColorArray([Color(tint*0.82,1.0)]),side_uv,PackedInt32Array(),PackedFloat32Array(),rock_texture.get_rid())
		var uv := PackedVector2Array()
		for point: Vector2 in rock.source: uv.append(point/rock_texture.get_size())
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),_terrain_triangle_indices(top),top,PackedColorArray([Color(tint*float(rock.tone),1.0)]),uv,PackedInt32Array(),PackedFloat32Array(),rock_texture.get_rid())
		# Small disconnected catches of light reveal height without framing the
		# rectangular physics footprint or implying a traversable ledge.
		canvas.draw_line(top[0].lerp(top[1],0.10),top[0].lerp(top[1],0.70),Color(colors.stone,0.85),1.6,true)
		if int(rock.index)%4==0:
			var at: Vector2 = top[4].lerp(top[5],0.5)
			canvas.draw_circle(at,5.0,Color(colors.foliage,0.66))
			canvas.draw_circle(at+Vector2(-4,-2),3.3,colors.leaf)

static func _draw_water_surface(canvas: CanvasItem, rect: Rect2, seed_value: int, time: float, colors: Dictionary) -> void:
	var inner: Rect2 = rect.grow(-minf(66.0,minf(rect.size.x,rect.size.y)*0.29))
	if not inner.has_area(): return
	for index: int in range(maxi(5,int(rect.get_area()/13000.0))):
		var at: Vector2 = inner.position+Vector2(_variation(index,seed_value+33),_variation(index,seed_value+77))*inner.size
		var radius: float = 11+_variation(index,seed_value+11)*21
		var points := PackedVector2Array()
		for step: int in range(13):
			var angle: float = lerpf(-2.8,-0.45,float(step)/12.0)
			points.append(at+Vector2.from_angle(angle)*Vector2(radius,radius*0.3))
		canvas.draw_polyline(points,Color(colors.rim,0.19+sin(time*0.42+index)*0.025),1.3,true)
