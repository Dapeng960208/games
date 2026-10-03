class_name RoomGroundDetails
extends RefCounted
## Authored, shallow floor treatments. Shapes never enter navigation, damage,
## collision or random placement. Normalized recipes preserve the arena scale.
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const Motif = preload("res://scripts/presentation/world/room_motif.gd")
const Presentation = preload("res://scripts/presentation/world/room_presentation.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")

static func _island(items: Array, material: String, at: Vector2, size: Vector2, angle: float = 0.0, profile: int = 0) -> void:
	items.append({"type":"island","material":material,"at":at,"size":size,"angle":angle,"profile":profile})

static func _arc(items: Array, material: String, at: Vector2, size: Vector2, first: float, last: float, width: float) -> void:
	items.append({"type":"arc","material":material,"at":at,"size":size,"first":first,"last":last,"width":width})

static func _ribbon(items: Array, material: String, points: Array, width: float) -> void:
	items.append({"type":"ribbon","material":material,"points":points,"width":width})

static func _recipes(key: String) -> Array:
	var p: Array = []
	# These are different floor plans, rather than seven transformations of one
	# center seal. Curves frame side venues; their open ends leave sight lines.
	match key:
		"sunburst":
			_arc(p,"garden",Vector2(.31,.35),Vector2(.23,.17),155,324,67)
			_island(p,"garden",Vector2(.78,.73),Vector2(.15,.12),-.22,1)
			_ribbon(p,"stone",[Vector2(.20,.45),Vector2(.36,.46),Vector2(.44,.56)],45)
			_island(p,"stone",Vector2(.48,.60),Vector2(.15,.075),0,2)
		"lens_bridge":
			_ribbon(p,"stone",[Vector2(.22,.64),Vector2(.41,.49),Vector2(.59,.46),Vector2(.80,.32)],72)
			_arc(p,"garden",Vector2(.29,.72),Vector2(.18,.13),28,220,48)
			_arc(p,"garden",Vector2(.76,.30),Vector2(.14,.13),185,350,57)
			_island(p,"stone",Vector2(.66,.64),Vector2(.10,.055),-.2,3)
		"season_rings":
			_arc(p,"garden",Vector2(.26,.66),Vector2(.17,.15),140,326,55)
			_arc(p,"garden",Vector2(.67,.30),Vector2(.18,.12),183,346,58)
			_arc(p,"stone",Vector2(.54,.53),Vector2(.20,.16),38,136,43)
			_island(p,"garden",Vector2(.77,.70),Vector2(.10,.09),.3,1)
		"orbit":
			_arc(p,"stone",Vector2(.50,.51),Vector2(.27,.18),188,354,48)
			_arc(p,"garden",Vector2(.46,.52),Vector2(.29,.20),10,117,60)
			_island(p,"stone",Vector2(.28,.71),Vector2(.15,.075),.23,3)
			_island(p,"garden",Vector2(.75,.28),Vector2(.14,.11),-.32,1)
		"lift_tracks":
			_ribbon(p,"stone",[Vector2(.27,.29),Vector2(.36,.41),Vector2(.44,.54),Vector2(.52,.70)],64)
			_ribbon(p,"stone",[Vector2(.44,.25),Vector2(.53,.38),Vector2(.60,.49)],41)
			_arc(p,"garden",Vector2(.73,.72),Vector2(.18,.14),20,207,63)
			_island(p,"garden",Vector2(.24,.29),Vector2(.13,.12),-.35,2)
		"triskelion":
			_arc(p,"garden",Vector2(.30,.73),Vector2(.17,.13),32,235,61)
			_arc(p,"stone",Vector2(.63,.45),Vector2(.23,.15),195,325,50)
			_ribbon(p,"garden",[Vector2(.70,.31),Vector2(.77,.45),Vector2(.76,.56)],51)
			_island(p,"stone",Vector2(.42,.36),Vector2(.12,.065),-.1,1)
		"crown_sun":
			_arc(p,"garden",Vector2(.50,.47),Vector2(.32,.29),205,284,76)
			_arc(p,"garden",Vector2(.50,.47),Vector2(.32,.29),-20,77,76)
			_arc(p,"stone",Vector2(.50,.53),Vector2(.26,.19),16,166,48)
			_island(p,"stone",Vector2(.50,.44),Vector2(.18,.105),0,2)
		"honeycomb":
			_island(p,"leaf",Vector2(.29,.72),Vector2(.18,.12),-.25,1)
			_island(p,"leaf",Vector2(.76,.72),Vector2(.16,.14),.3,1)
			_arc(p,"amber",Vector2(.50,.56),Vector2(.26,.17),185,345,52)
			_ribbon(p,"leaf",[Vector2(.21,.43),Vector2(.31,.37),Vector2(.42,.40)],45)
		"wing":
			_arc(p,"leaf",Vector2(.27,.65),Vector2(.20,.17),115,314,64)
			_arc(p,"leaf",Vector2(.72,.35),Vector2(.18,.16),172,369,50)
			_ribbon(p,"amber",[Vector2(.25,.68),Vector2(.43,.61),Vector2(.63,.39),Vector2(.79,.34)],53)
			_island(p,"leaf",Vector2(.64,.74),Vector2(.13,.08),.4,2)
		"nursery":
			_island(p,"leaf",Vector2(.25,.67),Vector2(.17,.16),-.5,1)
			_island(p,"leaf",Vector2(.74,.71),Vector2(.17,.12),.2,1)
			_island(p,"amber",Vector2(.52,.34),Vector2(.18,.105),0,2)
			_arc(p,"leaf",Vector2(.50,.50),Vector2(.26,.18),207,313,47)
		"wind_rose":
			_arc(p,"leaf",Vector2(.47,.47),Vector2(.27,.22),213,338,69)
			_arc(p,"amber",Vector2(.54,.49),Vector2(.26,.18),14,114,44)
			_island(p,"leaf",Vector2(.28,.71),Vector2(.16,.10),.25,3)
			_ribbon(p,"amber",[Vector2(.54,.34),Vector2(.70,.39),Vector2(.80,.54)],39)
		"weave":
			_island(p,"leaf",Vector2(.31,.28),Vector2(.17,.115),-.22,3)
			_island(p,"leaf",Vector2(.73,.72),Vector2(.16,.12),.14,3)
			_ribbon(p,"amber",[Vector2(.27,.40),Vector2(.41,.49),Vector2(.65,.52),Vector2(.77,.63)],59)
			_arc(p,"leaf",Vector2(.29,.65),Vector2(.16,.12),85,237,46)
		"nectar_channels":
			_ribbon(p,"amber",[Vector2(.26,.31),Vector2(.37,.38),Vector2(.41,.58),Vector2(.52,.70),Vector2(.73,.72)],51)
			_ribbon(p,"leaf",[Vector2(.58,.28),Vector2(.69,.37),Vector2(.74,.50)],63)
			_arc(p,"leaf",Vector2(.24,.33),Vector2(.17,.15),155,310,57)
			_island(p,"leaf",Vector2(.77,.74),Vector2(.14,.12),.6,1)
		"queen_petals":
			_island(p,"leaf",Vector2(.29,.32),Vector2(.19,.14),-.55,1)
			_island(p,"leaf",Vector2(.72,.32),Vector2(.19,.14),.55,1)
			_arc(p,"amber",Vector2(.50,.47),Vector2(.28,.22),20,157,63)
			_island(p,"leaf",Vector2(.27,.76),Vector2(.13,.10),-.3,1)
			_island(p,"leaf",Vector2(.77,.75),Vector2(.13,.10),.35,1)
		"postal_tiles":
			_ribbon(p,"cobble",[Vector2(.21,.29),Vector2(.34,.43),Vector2(.45,.46),Vector2(.70,.62),Vector2(.79,.74)],67)
			_island(p,"cloth",Vector2(.28,.29),Vector2(.14,.095),-.25,3)
			_arc(p,"garden",Vector2(.72,.71),Vector2(.20,.14),5,196,54)
			_island(p,"cobble",Vector2(.69,.31),Vector2(.14,.075),-.1,2)
		"candy_wrappers":
			_arc(p,"cobble",Vector2(.47,.49),Vector2(.27,.16),192,347,65)
			_island(p,"cloth",Vector2(.30,.31),Vector2(.17,.11),.15,3)
			_island(p,"cloth",Vector2(.72,.72),Vector2(.18,.095),-.2,3)
			_arc(p,"garden",Vector2(.27,.67),Vector2(.14,.13),73,243,46)
		"chime_rosette":
			_arc(p,"cobble",Vector2(.51,.49),Vector2(.25,.19),11,171,61)
			_arc(p,"garden",Vector2(.50,.45),Vector2(.33,.22),195,304,50)
			_island(p,"cloth",Vector2(.26,.30),Vector2(.14,.10),.24,2)
			_island(p,"garden",Vector2(.76,.73),Vector2(.15,.11),-.25,1)
		"candle_lane":
			_ribbon(p,"cobble",[Vector2(.29,.28),Vector2(.35,.43),Vector2(.49,.48),Vector2(.65,.58),Vector2(.77,.74)],73)
			_ribbon(p,"cloth",[Vector2(.25,.64),Vector2(.40,.68),Vector2(.49,.65)],42)
			_island(p,"garden",Vector2(.27,.30),Vector2(.15,.12),-.3,1)
			_island(p,"cloth",Vector2(.76,.72),Vector2(.16,.11),.12,3)
		"stitch_cross":
			_ribbon(p,"cobble",[Vector2(.26,.72),Vector2(.42,.59),Vector2(.55,.46),Vector2(.76,.28)],53)
			_ribbon(p,"cloth",[Vector2(.27,.31),Vector2(.39,.39),Vector2(.43,.46)],49)
			_island(p,"cloth",Vector2(.29,.72),Vector2(.15,.095),-.3,3)
			_arc(p,"garden",Vector2(.74,.32),Vector2(.17,.14),182,345,52)
		"moon_dock":
			_arc(p,"cobble",Vector2(.55,.51),Vector2(.27,.23),87,272,70)
			_arc(p,"garden",Vector2(.32,.29),Vector2(.17,.12),174,350,52)
			_ribbon(p,"cloth",[Vector2(.60,.68),Vector2(.72,.73),Vector2(.80,.68)],48)
			_island(p,"cobble",Vector2(.76,.72),Vector2(.16,.10),.15,2)
		"patch_stage":
			_island(p,"cloth",Vector2(.27,.30),Vector2(.19,.125),-.16,3)
			_arc(p,"cobble",Vector2(.52,.46),Vector2(.29,.22),19,161,67)
			_arc(p,"garden",Vector2(.51,.49),Vector2(.34,.27),206,292,57)
			_island(p,"cloth",Vector2(.74,.73),Vector2(.15,.10),.25,2)
		"spiral_drum":
			_arc(p,"sand",Vector2(.38,.60),Vector2(.23,.21),80,286,80)
			_arc(p,"clay",Vector2(.48,.53),Vector2(.24,.15),215,345,45)
			_island(p,"rug",Vector2(.73,.31),Vector2(.17,.10),-.3,3)
			_island(p,"sand",Vector2(.27,.72),Vector2(.15,.11),.2,2)
		"market_rugs":
			_island(p,"rug",Vector2(.29,.30),Vector2(.18,.115),-.22,3)
			_island(p,"rug",Vector2(.73,.73),Vector2(.16,.12),.18,3)
			_ribbon(p,"clay",[Vector2(.24,.44),Vector2(.42,.41),Vector2(.56,.52),Vector2(.76,.57)],69)
			_arc(p,"sand",Vector2(.35,.66),Vector2(.18,.13),90,250,56)
		"arena_net":
			_island(p,"sand",Vector2(.52,.50),Vector2(.26,.19),0,2)
			_arc(p,"clay",Vector2(.52,.47),Vector2(.30,.23),194,326,59)
			_arc(p,"sand",Vector2(.52,.49),Vector2(.32,.26),26,137,71)
			_island(p,"rug",Vector2(.75,.30),Vector2(.14,.085),.3,3)
		"forge_chevron":
			_ribbon(p,"clay",[Vector2(.24,.71),Vector2(.39,.60),Vector2(.57,.44),Vector2(.76,.33)],84)
			_island(p,"sand",Vector2(.29,.73),Vector2(.17,.11),.2,2)
			_island(p,"clay",Vector2(.72,.29),Vector2(.18,.11),-.2,2)
			_arc(p,"garden",Vector2(.29,.33),Vector2(.13,.11),163,327,40)
		"beacon_rays":
			_ribbon(p,"clay",[Vector2(.28,.71),Vector2(.39,.62),Vector2(.46,.44),Vector2(.72,.28)],65)
			_arc(p,"sand",Vector2(.29,.68),Vector2(.20,.17),75,267,64)
			_arc(p,"clay",Vector2(.71,.32),Vector2(.17,.13),178,345,45)
			_island(p,"rug",Vector2(.69,.66),Vector2(.14,.095),-.2,3)
		"trial_triangles":
			_island(p,"sand",Vector2(.28,.31),Vector2(.17,.13),-.4,2)
			_island(p,"sand",Vector2(.72,.70),Vector2(.17,.13),.2,2)
			_arc(p,"clay",Vector2(.52,.45),Vector2(.27,.20),198,343,55)
			_ribbon(p,"rug",[Vector2(.28,.62),Vector2(.37,.67),Vector2(.47,.65)],43)
		"tusk_crown":
			_island(p,"sand",Vector2(.50,.51),Vector2(.28,.21),0,2)
			_arc(p,"clay",Vector2(.50,.48),Vector2(.31,.25),201,336,73)
			_arc(p,"rug",Vector2(.49,.48),Vector2(.33,.27),29,153,52)
			_island(p,"rug",Vector2(.26,.28),Vector2(.15,.10),-.25,3)
	return p

static func _world(arena: Rect2, at: Vector2) -> Vector2:
	return arena.position+at*arena.size

static func _oval(at: Vector2, size: Vector2, angle: float, profile: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i: int in 49:
		var a: float = float(i)*TAU/48
		var irregular: float = 1.0+.035*sin(a*3+.7)+.027*cos(a*5-.3)
		var point := Vector2(cos(a),sin(a))
		match profile:
			1: # One tapered leaf end, not an identical ellipse at every venue.
				point.x *= .87+.20*cos(a)
				point.y *= .80+.22*sin(a*.5)
			2: point *= 1.0+.07*cos(a*4)
			3:
				point.x = signf(point.x)*pow(absf(point.x),.64)
				point.y = signf(point.y)*pow(absf(point.y),.72)
		poly.append(at+(point*size*irregular).rotated(angle))
	return poly

static func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	var curve := Curve2D.new()
	curve.bake_interval = 11.0
	for i: int in points.size():
		var before: Vector2 = points[maxi(0,i-1)]
		var after: Vector2 = points[mini(points.size()-1,i+1)]
		var tangent: Vector2 = (after-before)*.15
		curve.add_point(points[i],-tangent if i>0 else Vector2.ZERO,tangent if i<points.size()-1 else Vector2.ZERO)
	return curve.get_baked_points()

static func _band(points: PackedVector2Array, width: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var other := PackedVector2Array()
	for i: int in points.size():
		var delta: Vector2 = points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
		var n := Vector2(-delta.y,delta.x).normalized()
		var tapered: float = .76+.24*sin(PI*float(i)/maxi(1,points.size()-1))
		poly.append(points[i]+n*width*.5*tapered)
		other.append(points[i]-n*width*.5*tapered)
	other.reverse()
	poly.append_array(other)
	return poly

static func _add_surface(result: Dictionary, poly: PackedVector2Array, material: String, ground: PackedVector2Array, slot: int) -> void:
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(poly,ground):
		if clipped.size()<3: continue
		var bounds := Rect2(clipped[0],Vector2.ZERO)
		for at: Vector2 in clipped: bounds = bounds.expand(at)
		var seam_lines: Array[PackedVector2Array] = []
		# Short broken joints are small enough for the unchanged hero scale.
		if material in ["stone","cobble","clay","amber"]:
			for row: int in range(ceili(bounds.size.y/34.0)):
				for col: int in range(ceili(bounds.size.x/49.0)):
					var at := bounds.position+Vector2((col+.25+.5*(row%2))*49.0,(row+.4)*34.0)
					var a := at-Vector2(11,1)
					var b := at+Vector2(19,2)
					if Geometry2D.is_point_in_polygon(a,clipped) and Geometry2D.is_point_in_polygon(b,clipped):
						seam_lines.append(PackedVector2Array([a,b]))
					var end := at+Vector2(9,19)
					if Geometry2D.is_point_in_polygon(at,clipped) and Geometry2D.is_point_in_polygon(end,clipped):
						seam_lines.append(PackedVector2Array([at+Vector2(9,2),end]))
		result.surfaces.append({"polygon":clipped,"material":material,"bounds":bounds,"slot":slot,"joints":seam_lines})

static func _detail_at(result: Dictionary, at: Vector2, angle: float, style: String, slot: int, ground: PackedVector2Array) -> void:
	if Geometry2D.is_point_in_polygon(at,ground):
		result.details.append({"at":at,"angle":angle,"style":style,"slot":slot})

static func build(layout: Dictionary, design: Dictionary, biome: String, ground: PackedVector2Array) -> Dictionary:
	var result: Dictionary = {"surfaces":[],"details":[],"motifs":[]}
	var arena: Rect2 = layout.arena
	var recipes: Array = _recipes(str(design.emblem))
	var chapter: int = int(design.chapter)
	var slot := 0
	for recipe: Dictionary in recipes:
		var points := PackedVector2Array()
		var poly := PackedVector2Array()
		if str(recipe.type)=="island":
			poly = _oval(_world(arena,recipe.at),Vector2(recipe.size)*arena.size,float(recipe.angle),int(recipe.profile))
			# Sparse little material catches follow the actual curved footprint.
			for i: int in [4,11,19,28,38]:
				var at: Vector2 = poly[i].lerp(_world(arena,recipe.at),.12)
				_detail_at(result,at,(at-_world(arena,recipe.at)).angle()+.6,str(recipe.material),slot+i,ground)
		else:
			if str(recipe.type)=="arc":
				for i: int in 33:
					var a: float = deg_to_rad(lerpf(float(recipe.first),float(recipe.last),float(i)/32))
					points.append(_world(arena,recipe.at)+Vector2(cos(a),sin(a))*Vector2(recipe.size)*arena.size)
			else:
				for at: Vector2 in recipe.points: points.append(_world(arena,at))
				points = _smooth(points)
			poly = _band(points,float(recipe.width))
			for i: int in range(3,points.size()-3,7):
				var delta: Vector2 = (points[i+1]-points[i-1]).normalized()
				var at: Vector2 = points[i]+Vector2(-delta.y,delta.x)*float(recipe.width)*.28
				_detail_at(result,at,delta.angle(),str(recipe.material),slot+i,ground)
		_add_surface(result,poly,str(recipe.material),ground,slot)
		slot += 1
	# The actual authored route gets continuous low-contrast paving. This is
	# decoration only, so it cannot block the real combat corridor.
	for key: String in ["main","side"]:
		var points := PackedVector2Array()
		for at: Vector2 in layout.get("fixed_routes",{}).get(key,[]): points.append(at)
		if points.size()<2: continue
		points = _smooth(points)
		var material: String = {"B01":"stone","B02":"amber","B03":"cobble","B04":"clay"}.get(biome,"stone")
		_add_surface(result,_band(points,float(design.road_width)*(1.0 if key=="main" else .60)),material,ground,slot)
		slot += 1
	# Each venue has a working apron with faction-specific silhouette, paving
	# and small use marks. Its full prop grouping belongs to Presentation.
	for index: int in design.groups.size():
		var group: Dictionary = design.groups[index]
		var at: Vector2 = _world(arena,Vector2(float(group.at[0]),float(group.at[1])))
		var angle: float = float(design.angle)+(index-.5)*.24
		var material: String = {"B01":"stone","B02":"leaf","B03":"cloth","B04":"sand"}.get(biome,"stone")
		var profile: int = 1 if biome=="B02" else (3 if biome=="B03" else (chapter+index)%3)
		var size := Vector2(155+chapter*3,79+index*10)
		_add_surface(result,_oval(at+Vector2(0,17),size,angle,profile),material,ground,slot)
		for detail: int in 3:
			_detail_at(result,at+Vector2((detail-1)*65,68).rotated(angle),angle,material,chapter+index*5+detail,ground)
		# A small apron inset links the room badge to the venue without another
		# arena-sized symbol competing with combat warnings.
		var inset: Vector2 = at+Vector2(0,69).rotated(angle)
		if Geometry2D.is_point_in_polygon(inset,ground):
			result.motifs.append({"at":inset,"angle":angle,"size":Vector2(36,24),"key":str(design.emblem),"alpha":.30})
		slot += 1
	var at := _world(arena,Vector2(float(design.floor_center[0]),float(design.floor_center[1])))
	var radius: float = arena.size.x*float(design.floor_radius)*.36
	var material: String = {"B01":"stone","B02":"amber","B03":"cobble","B04":"clay"}.get(biome,"stone")
	_add_surface(result,_oval(at,Vector2(radius*1.15,radius*.68),float(design.angle),chapter%3),material,ground,slot)
	result.motifs.append({"at":at,"angle":float(design.angle),"size":Vector2(radius*.76,radius*.48),"key":str(design.emblem),"alpha":.25})
	return result

static func _surface_color(material: String, colors: Dictionary) -> Color:
	match material:
		"garden": return Color(Color(colors.leaf).lerp(colors.ground,.40),.48)
		"leaf": return Color(Color(colors.leaf).lerp(colors.ground,.22),.50)
		"cloth": return Color(Color(colors.seam).lerp(colors.stone,.64),.45)
		"rug": return Color(Color(colors.accent).lerp(colors.stone,.65),.54)
		"sand": return Color(Color(colors.ground).lerp(colors.stone,.58),.65)
		"clay": return Color(Color(colors.stone_side).lerp(colors.stone,.65),.65)
		"amber": return Color(Color(colors.gold).lerp(colors.stone,.60),.57)
		"cobble": return Color(Color(colors.seam).lerp(colors.stone,.82),.64)
	return Color(colors.stone,.70)

static func _texture_surface(c: CanvasItem, surface: Dictionary, texture: Texture2D, colors: Dictionary) -> void:
	if texture==null: return
	var poly: PackedVector2Array = surface.polygon
	var uv := PackedVector2Array()
	# World-oriented established limestone grain keeps the small floor detail
	# independent of each terrace's width and curvature.
	var source_start := Vector2(.10+.13*(int(surface.slot)%3),.10+.14*(int(surface.slot)%4))
	var bounds: Rect2 = surface.bounds
	for at: Vector2 in poly: uv.append(source_start+(at-bounds.position)/Vector2(920,820))
	var tint := Color(Color(colors.stone).lerp(Color.WHITE,.78),.23)
	if str(surface.material) in ["garden","leaf"]: tint = Color(colors.leaf,.09)
	elif str(surface.material) in ["cloth","rug"]: tint.a = .09
	c.draw_polygon(poly,PackedColorArray([tint]),uv,texture)

static func draw(c: CanvasItem, composition: Dictionary, biome: String) -> void:
	var colors: Dictionary = Art.palette(biome)
	var ink: Color = Presentation.accent(biome)
	var texture: Texture2D = Sampler.sampled(Art.FLOOR_PATH)
	for surface: Dictionary in composition.surfaces:
		var poly: PackedVector2Array = surface.polygon
		var material: String = str(surface.material)
		c.draw_colored_polygon(poly,_surface_color(material,colors))
		_texture_surface(c,surface,texture,colors)
		# Broken catches of light read as flat material edges. A closed bright
		# circle would compete with target and danger telegraphs.
		for i: int in range(1,poly.size()-2,6):
			c.draw_line(poly[i].lerp(poly[i+1],.12),poly[i+1].lerp(poly[i+2],.40),Color(colors.stone,.35),1.4,true)
		for joint: PackedVector2Array in surface.joints:
			c.draw_polyline(joint,Color(colors.seam,.16),1.0,true)
		if material in ["cloth","rug"]: _draw_sewing(c,poly,colors,int(surface.slot))
	for detail: Dictionary in composition.details: _draw_detail(c,detail,colors,biome)
	for motif: Dictionary in composition.motifs:
		c.draw_set_transform(motif.at,float(motif.angle),motif.size)
		Motif.draw(c,str(motif.key),Color(ink,float(motif.alpha)),Color(colors.gold,float(motif.alpha)+.04))
	c.draw_set_transform(Vector2.ZERO)

static func _draw_sewing(c: CanvasItem, poly: PackedVector2Array, colors: Dictionary, slot: int) -> void:
	var center := Vector2.ZERO
	for at: Vector2 in poly: center+=at
	center /= poly.size()
	for i: int in range(2,poly.size()-2,3):
		var at: Vector2 = poly[i].lerp(center,.10)
		var d: Vector2 = (poly[i+1]-poly[i-1]).normalized()
		var n := Vector2(-d.y,d.x)
		c.draw_line(at-n*3-d*2,at+n*3+d*2,Color(colors.stone,.58),1.4,true)
	for i: int in 3:
		var at := center+Vector2(-28+i*24,9+slot%3*4)
		c.draw_line(at-Vector2(4,3),at+Vector2(4,3),Color(colors.seam,.25),1.2,true)

static func _leaf(c: CanvasItem, at: Vector2, size: Vector2, angle: float, color: Color) -> void:
	var poly := PackedVector2Array()
	for i: int in 17:
		var a: float = float(i)*TAU/16
		poly.append(at+(Vector2(cos(a),sin(a))*(.83+.17*cos(a))*size).rotated(angle))
	c.draw_colored_polygon(poly,color)
	c.draw_line(at-Vector2(size.x*.6,0).rotated(angle),at+Vector2(size.x*.72,0).rotated(angle),Color(color.darkened(.15),color.a*.7),.85,true)

static func _draw_detail(c: CanvasItem, detail: Dictionary, colors: Dictionary, biome: String) -> void:
	var at: Vector2 = detail.at
	var angle: float = float(detail.angle)
	var slot: int = int(detail.slot)
	var style: String = str(detail.style)
	if style in ["garden","leaf"]:
		for i: int in 3:
			var a: float = angle+(i-1)*.66
			var offset := Vector2.from_angle(a)*(6+i*2)
			_leaf(c,at+offset,Vector2(11+slot%3*2,4.5),a,Color(colors.foliage,.39))
		if slot%3==0:
			var flower: Vector2 = at+Vector2(-7,-5)
			for i: int in 4:
				_leaf(c,flower+Vector2.from_angle(i*PI*.5)*3.3,Vector2(3.1,1.8),i*PI*.5,Color(colors.stone,.73))
			c.draw_circle(flower,1.8,Color(colors.gold,.75))
	elif style in ["cloth","rug"]:
		for i: int in 3:
			var offset := Vector2((i-1)*9,0).rotated(angle)
			c.draw_line(at+offset-Vector2(2,3).rotated(angle),at+offset+Vector2(2,3).rotated(angle),Color(colors.seam,.28),1.25,true)
	elif style=="sand":
		for i: int in 3:
			var offset := Vector2((i-1)*9,absf(i-1)*3).rotated(angle)
			c.draw_arc(at+offset,4.0,angle+.2,angle+2.5,8,Color(colors.seam,.24),1.25,true)
	else:
		for i: int in 2:
			var offset := Vector2(i*12-5,(i%2)*7).rotated(angle)
			var chip := PackedVector2Array([at+offset+Vector2(-4,-2),at+offset+Vector2(3,-3),at+offset+Vector2(5,1),at+offset+Vector2(-2,3)])
			c.draw_colored_polygon(chip,Color(colors.stone,.54))
			c.draw_line(chip[2],chip[3],Color(colors.seam,.23),1.0,true)
		if biome=="B02": _leaf(c,at+Vector2(0,-8),Vector2(9,3),angle-.4,Color(colors.gold,.33))
