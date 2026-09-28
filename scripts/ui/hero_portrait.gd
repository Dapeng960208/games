extends Control
## Original ImageGen hero portraits, preserving alpha and their full composition.
## Hand-drafted geometry remains a development fallback while assets are pending.

var hero_id: String = "CH01"
var hero_data: Dictionary = {}
var generated_texture: Texture2D
const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")

const INK := Color("111b24")
const DARK := Color("263a45")
const STEEL := Color("53717c")
const LIGHT := Color("a2bbc0")
const PAPER := Color("d5ddcf")
const GOLD := Color("e4b66e")
const TEAL := Color("64cfbf")
const ICE := Color("96bbed")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	queue_redraw()

func set_hero(id: String, data: Dictionary = {}) -> void:
	hero_id = id
	hero_data = data
	var path := "res://assets/generated/heroes/"+hero_id+"_portrait_v1.png"
	generated_texture = TextureSampler.sampled(path)
	queue_redraw()

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if generated_texture != null:
		var source_size := generated_texture.get_size()
		var image_scale := minf(size.x/source_size.x,size.y/source_size.y)
		var extent := source_size*image_scale
		draw_texture_rect(generated_texture,Rect2((size-extent)*0.5,extent),false)
		return
	var scale_factor := minf(size.x / 240.0, size.y / 300.0)
	var origin := (size - Vector2(240, 300) * scale_factor) * 0.5
	draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	var identity := _identity()
	var accent: Color = [GOLD, TEAL, ICE][identity]
	_backplate(accent, identity)
	match identity:
		0: _breaker()
		1: _hunter()
		2: _resonator()
	_foreground(accent, identity)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _identity() -> int:
	var resource := str(hero_data.get("resource_type", hero_data.get("resource", ""))).to_lower()
	var key := hero_id.to_lower()
	if key == "ch03" or "reson" in key or "mage" in key or resource == "mana":
		return 2
	if key == "ch02" or "hunt" in key or "ranger" in key or resource == "energy":
		return 1
	return 0

func _poly(coords: Array, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(0, coords.size(), 2):
		points.append(Vector2(float(coords[index]), float(coords[index + 1])))
	draw_colored_polygon(points, color)

func _path(coords: Array, color: Color, width: float = 1.0) -> void:
	var points := PackedVector2Array()
	for index in range(0, coords.size(), 2):
		points.append(Vector2(float(coords[index]), float(coords[index + 1])))
	draw_polyline(points, color, width, true)

func _backplate(accent: Color, identity: int) -> void:
	_poly([24,13, 198,13, 222,37, 222,273, 201,290, 18,290, 18,33], Color("15232c"))
	_poly([25,14, 87,14, 67,290, 19,290, 19,34], Color("1a2b33"))
	_poly([199,14, 221,37, 221,273, 200,289, 161,289], Color("0f1c26"))
	draw_circle(Vector2(119,119), 81, Color(accent,0.035))
	draw_arc(Vector2(119,119), 81, -2.65, 1.3, 56, Color(accent,0.23), 1.0, true)
	draw_arc(Vector2(119,119), 74, 0.12, 1.7, 28, Color(accent,0.12), 1.0, true)
	_path([34,25, 189,25, 210,46, 210,263], Color(accent,0.3))
	_path([31,104, 31,266, 48,279, 181,279], Color(accent,0.16))
	for n in range(7):
		var y := 38 + n * 9
		draw_line(Vector2(24,y), Vector2(29 if n % 3 else 34,y), Color(accent,0.32))
	for n in range(5):
		var x := 77 + n * 22
		draw_line(Vector2(x,275), Vector2(x+12,275), Color(accent,0.24))
	# Three different schematic emblems echo the character's mechanical discipline.
	if identity == 0:
		_path([170,41, 187,41, 187,58, 170,58, 170,41], Color(accent,0.35), 2)
		draw_line(Vector2(178,58),Vector2(178,71),Color(accent,0.35),2)
	elif identity == 1:
		_path([169,43, 187,52, 169,62, 175,52, 169,43], Color(accent,0.35), 1)
	else:
		draw_arc(Vector2(180,53),12,0,TAU,32,Color(accent,0.4),1,true)
		draw_circle(Vector2(180,53),3,Color(accent,0.4))

func _breaker() -> void:
	# Compact square silhouette, offset hydraulic hammer, broad steel shoulders.
	_poly([73,134, 161,125, 180,232, 155,260, 57,259], Color("0b141b"))
	_poly([91,193, 115,195, 109,258, 72,263, 72,251], DARK)
	_poly([123,194, 152,190, 165,249, 158,261, 124,261], DARK)
	_poly([91,207, 108,210, 102,246, 81,249], STEEL)
	_poly([131,207, 148,203, 156,247, 134,248], STEEL)
	_poly([78,247, 105,245, 110,258, 103,268, 61,268, 62,261], INK)
	_poly([131,247, 157,244, 177,258, 177,268, 133,268, 125,261], INK)
	_path([67,261, 102,260], GOLD,2)
	_path([134,261, 168,261], GOLD,2)
	_poly([82,115, 141,105, 164,132, 153,190, 122,208, 86,192, 69,147], DARK)
	_poly([91,116, 136,114, 146,147, 129,178, 95,171, 79,141], STEEL)
	_poly([95,121, 132,119, 135,135, 102,137], LIGHT)
	_poly([102,143, 132,140, 126,161, 104,160], INK)
	_path([107,151, 125,149], GOLD,3)
	_poly([86,171, 147,172, 148,188, 92,193], INK)
	_poly([104,176, 124,175, 124,188, 104,190], GOLD)
	_poly([108,179, 120,178, 120,185, 108,186], DARK)
	_poly([61,114, 88,112, 96,143, 75,156, 50,146, 44,133], INK)
	_poly([62,115, 82,117, 88,138, 72,144, 50,136], STEEL)
	_poly([52,123, 75,122, 81,134, 52,133], LIGHT)
	_poly([57,147, 76,151, 67,186, 48,182, 42,168], DARK)
	_poly([45,163, 64,164, 60,180, 44,177], STEEL)
	_poly([47,182, 62,183, 64,196, 57,204, 43,198, 40,187], GOLD)
	_poly([146,108, 168,118, 178,138, 159,151, 144,138], INK)
	_poly([149,113, 163,120, 171,137, 158,143, 147,133], LIGHT)
	_poly([159,145, 176,139, 190,163, 181,180, 167,172], STEEL)
	_poly([174,164, 189,161, 195,172, 186,183, 176,179], GOLD)
	# Hammer piston shaft, deliberately asymmetric to the body silhouette.
	_path([185,104, 183,239], INK,13)
	_path([185,105, 183,238], LIGHT,7)
	_path([186,183, 185,228], DARK,4)
	for n in range(5):
		draw_line(Vector2(180,193+n*7),Vector2(187,195+n*7),GOLD,2)
	_poly([156,69, 201,65, 219,79, 216,112, 172,118, 153,105], INK)
	_poly([160,72, 199,69, 210,80, 174,85], LIGHT)
	_poly([160,74, 174,86, 172,112, 157,103], STEEL)
	_poly([176,87, 214,81, 211,108, 176,114], DARK)
	_poly([189,87, 201,85, 200,108, 188,110], GOLD)
	_path([179,95, 185,94, 184,104, 178,105], STEEL,2)
	# Face: close-cropped hair, scar, heavy mineral respirator collar.
	_poly([95,62, 121,55, 139,66, 140,92, 125,112, 107,109, 92,91], INK)
	_poly([101,65, 124,62, 134,73, 132,93, 120,104, 107,97, 99,80], Color("b89779"))
	_poly([99,64, 119,55, 135,64, 137,76, 125,71, 109,75, 101,83], Color("46504f"))
	_poly([105,90, 129,88, 125,102, 112,104], DARK)
	_path([105,81, 114,80], INK,2)
	_path([122,79, 131,78], INK,2)
	_path([126,80, 121,91], Color("dfbda0"),1)
	_path([111,97, 122,96], LIGHT,2)
	_poly([89,104, 103,101, 115,113, 134,106, 145,113, 126,129, 104,126], INK)
	_path([91,111, 103,116], GOLD,3)
	for point in [Vector2(58,132),Vector2(78,129),Vector2(153,127),Vector2(145,182),Vector2(90,182)]:
		draw_circle(point,2,LIGHT)

func _hunter() -> void:
	# Long diagonal rifle and narrow coat contrast with the breaker's square mass.
	_poly([109,98, 148,102, 172,244, 143,230, 133,197, 83,242, 86,157], Color("0c151d"))
	_poly([99,163, 118,179, 104,225, 87,258, 69,257, 85,214], DARK)
	_poly([122,173, 143,170, 149,219, 171,245, 155,257, 131,230], DARK)
	_poly([88,225, 100,226, 86,257, 70,261, 61,258, 68,250], STEEL)
	_poly([143,224, 154,230, 172,247, 161,259, 145,254, 152,245], STEEL)
	_poly([65,257, 85,256, 84,265, 52,269, 48,265], INK)
	_poly([159,250, 171,247, 183,260, 181,267, 154,264, 150,258], INK)
	_path([58,265, 78,262], TEAL,2)
	_path([159,260, 176,263], TEAL,2)
	_poly([98,102, 134,97, 150,130, 135,163, 107,173, 92,147], STEEL)
	_poly([102,107, 127,104, 138,127, 118,153, 98,142], Color("3f6168"))
	_poly([115,106, 127,104, 133,116, 123,132, 112,129], LIGHT)
	_poly([96,144, 128,152, 138,143, 139,162, 118,176, 103,169], INK)
	_path([97,120, 131,143], GOLD,4)
	_path([96,122, 128,144], Color("586358"),2)
	_poly([104,153, 119,158, 117,169, 102,164], TEAL)
	_poly([100,168, 113,177, 97,219, 74,235, 84,192], Color("426364"))
	_poly([134,162, 148,143, 160,220, 149,214, 139,190], DARK)
	_path([104,177, 94,202, 82,215], TEAL,1)
	# Scarf follows the same shooting diagonal, but never resembles a cape block.
	_poly([108,98, 98,98, 78,89, 56,89, 38,75, 65,78, 87,74, 109,87], Color("8ac3ad"))
	_poly([109,96, 89,88, 67,87, 39,76, 72,81, 88,80], Color("3d756f"))
	_poly([94,101, 109,101, 110,117, 97,128, 86,121], INK)
	_poly([94,105, 106,105, 103,117, 94,121, 88,117], LIGHT)
	_poly([90,122, 103,124, 94,146, 79,151, 71,141], STEEL)
	_poly([73,136, 87,139, 103,154, 97,166, 77,155, 66,145], LIGHT)
	_poly([130,103, 143,108, 154,136, 143,145, 128,123], DARK)
	_poly([145,134, 155,134, 179,118, 186,127, 167,147, 152,150], STEEL)
	# Precision rail rifle with exposed rail, offset stock and double muzzle fins.
	_poly([62,181, 67,190, 198,99, 195,86, 182,85, 161,105, 142,110, 127,128, 94,146, 92,158], INK)
	_path([81,172, 194,93], LIGHT,7)
	_path([113,148, 183,99], DARK,5)
	_path([132,131, 180,98], TEAL,2)
	_poly([78,166, 98,150, 107,156, 90,173, 76,179, 64,187, 61,179], STEEL)
	_poly([127,135, 138,143, 134,154, 125,156, 119,145], GOLD)
	_poly([176,92, 182,86, 190,88, 199,78, 203,83, 192,96, 190,102, 183,105], STEEL)
	_poly([147,111, 162,100, 167,105, 152,116], GOLD)
	draw_circle(Vector2(161,104),3,TEAL)
	_poly([95,149, 103,146, 111,151, 108,162, 100,165, 93,159], Color("b69d7b"))
	_poly([174,119, 180,115, 187,119, 185,128, 179,132, 173,127], Color("b69d7b"))
	# Angular head, high tie and monocular sight.
	_poly([110,60, 133,59, 145,71, 138,94, 121,106, 108,89], INK)
	_poly([113,67, 131,66, 137,77, 130,95, 121,99, 112,86], Color("bca589"))
	_poly([106,69, 114,56, 137,57, 142,71, 131,74, 123,68, 110,84], Color("202e31"))
	_poly([133,58, 141,52, 147,38, 153,36, 153,54, 143,66], STEEL)
	_path([121,80, 137,76], INK,4)
	_poly([124,76, 136,73, 140,79, 126,83], TEAL)
	_path([128,91, 133,88], INK,1)
	_poly([109,93, 121,100, 133,92, 137,101, 118,112, 102,102], TEAL)

func _resonator() -> void:
	# Open halo, forked robes and floating crystal nodes define the caster.
	draw_arc(Vector2(124,125),77,-2.8,0.7,68,Color(ICE,0.2),7,true)
	draw_arc(Vector2(124,125),77,-2.8,0.7,68,STEEL,2,true)
	draw_arc(Vector2(124,125),68,1.1,3.9,55,Color(ICE,0.2),3,true)
	_path([67,74, 76,64, 88,57], ICE,3)
	_path([184,164, 191,151, 194,137], ICE,3)
	_poly([110,111, 144,111, 152,147, 175,229, 156,255, 129,232, 106,262, 76,239, 103,161], INK)
	_poly([110,137, 122,151, 108,225, 92,245, 82,234, 102,184], STEEL)
	_poly([134,149, 143,136, 156,193, 168,232, 155,245, 140,220], STEEL)
	_poly([119,157, 132,155, 145,237, 133,249, 117,236, 103,247], Color("394966"))
	_poly([104,179, 111,172, 97,233, 92,235], LIGHT)
	_poly([146,179, 151,186, 163,231, 157,230], LIGHT)
	_path([113,189, 108,214, 115,224], ICE,1)
	_path([139,181, 145,215, 138,228], ICE,1)
	_poly([110,239, 119,242, 116,263, 99,269, 96,265], DARK)
	_poly([141,241, 150,239, 159,261, 157,268, 141,265], DARK)
	_path([101,264, 112,261], ICE,2)
	_path([145,260, 155,263], ICE,2)
	_poly([98,110, 116,99, 137,98, 155,114, 146,148, 125,163, 106,150], DARK)
	_poly([108,115, 125,124, 143,111, 141,143, 126,153, 112,143], LIGHT)
	_poly([122,118, 133,115, 138,131, 128,144, 117,134], ICE)
	_poly([126,123, 132,120, 133,131, 127,138, 123,131], Color("e3f4ed"))
	_poly([109,147, 125,156, 145,144, 146,156, 126,169, 108,159], INK)
	_path([115,156, 125,161, 139,153], GOLD,2)
	_poly([99,109, 109,117, 102,145, 91,153, 77,143, 83,123], STEEL)
	_poly([80,132, 94,143, 75,160, 52,152, 46,141, 58,143, 72,145], LIGHT)
	_poly([142,110, 155,111, 170,142, 159,154, 147,143], STEEL)
	_poly([159,145, 169,138, 186,126, 193,128, 186,145, 173,157, 161,156], LIGHT)
	_poly([47,138, 57,139, 57,150, 48,151, 40,141, 38,133, 43,133], Color("b2a591"))
	_poly([184,124, 189,117, 190,105, 195,106, 197,117, 193,129, 185,134], Color("b2a591"))
	# Independently floating resonance stones carry a visible containment frame.
	_crystal(Vector2(43,111), 14, ICE)
	_crystal(Vector2(190,82), 18, ICE)
	_crystal(Vector2(180,216), 8, ICE)
	_path([43,128, 47,137], Color(ICE,0.5),1)
	_path([190,102, 190,108], Color(ICE,0.5),1)
	# Hood and face are constructed as facets with an open, bright eye band.
	_poly([103,64, 119,49, 137,51, 151,74, 149,99, 139,116, 108,114, 98,91], INK)
	_poly([103,69, 120,52, 130,55, 111,82, 112,104, 106,105, 101,90], STEEL)
	_poly([133,55, 146,75, 144,96, 135,109, 132,102, 138,84], Color("394c65"))
	_poly([116,73, 133,73, 138,83, 132,99, 123,105, 114,95, 110,81], Color("a7a899"))
	_poly([111,77, 133,75, 135,83, 112,86], INK)
	_path([115,81, 131,79], ICE,2)
	_path([122,96, 130,93], DARK,1)
	_poly([104,103, 115,103, 124,112, 137,102, 148,100, 141,117, 123,124, 108,116], DARK)
	_path([108,108, 123,119, 142,108], GOLD,2)

func _crystal(at: Vector2, radius: float, color: Color) -> void:
	var p := PackedVector2Array([at+Vector2(0,-radius),at+Vector2(radius*0.55,0),at+Vector2(0,radius),at+Vector2(-radius*0.55,0)])
	draw_colored_polygon(p, color)
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-radius),at,at+Vector2(-radius*0.55,0)]),Color("d7eee7"))
	draw_colored_polygon(PackedVector2Array([at,at+Vector2(radius*0.55,0),at+Vector2(0,radius)]),Color("52729d"))
	draw_arc(at,radius+5,0.35,2.7,16,Color(color,0.35),1,true)
	draw_arc(at,radius+5,3.5,5.8,16,Color(color,0.35),1,true)

func _foreground(accent: Color, identity: int) -> void:
	# Tiny drafting registration marks and platform ground the illustration.
	draw_line(Vector2(40,270),Vector2(195,270),Color(accent,0.25),1,true)
	draw_line(Vector2(57,272),Vector2(177,272),Color(accent,0.1),1,true)
	_path([19,265, 19,289, 45,289], Color(accent,0.6),1)
	_path([204,13, 222,31, 222,50], Color(accent,0.6),1)
	for n in range(3):
		draw_rect(Rect2(33+n*7,281,4,3),accent if n == identity else Color(accent,0.2))
