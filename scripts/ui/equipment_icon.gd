extends Control
## Original ImageGen equipment miniatures with alpha preserved and cached textures.
## Hand-drafted slot art is a development fallback until each image is supplied.

var equipment_data: Dictionary = {}
var generated_texture: Texture2D
const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")

const INK := Color("101b22")
const DARK := Color("2e444d")
const STEEL := Color("6e8990")
const LIGHT := Color("bccac4")
const GOLD := Color("dfb36d")
var _accent := GOLD
var _variant: int = 0
var _motif: int = 0
var _family: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	queue_redraw()

func set_equipment(data: Dictionary) -> void:
	equipment_data = data
	var path := "res://assets/generated/equipment/"+str(data.get("id",""))+"_v1.png"
	generated_texture = TextureSampler.sampled(path)
	queue_redraw()

func _poly(coords: Array, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(0, coords.size(), 2):
		points.append(Vector2(float(coords[index]),float(coords[index+1])))
	draw_colored_polygon(points,color)

func _path(coords: Array, color: Color, width: float = 1.0) -> void:
	var points := PackedVector2Array()
	for index in range(0, coords.size(), 2):
		points.append(Vector2(float(coords[index]),float(coords[index+1])))
	draw_polyline(points,color,width,true)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if generated_texture != null:
		var source_size := generated_texture.get_size()
		var image_scale := minf(size.x/source_size.x,size.y/source_size.y)
		var extent := source_size*image_scale
		draw_texture_rect(generated_texture,Rect2((size-extent)*0.5,extent),false)
		return
	var k := minf(size.x/96.0,size.y/96.0)
	draw_set_transform((size-Vector2(96,96)*k)*0.5,0,Vector2.ONE*k)
	var item_id := str(equipment_data.get("id",equipment_data.get("name","unmarked")))
	var set_id := str(equipment_data.get("set_id",equipment_data.get("set","")))
	_family = posmod(int(item_id.trim_prefix("EQ")) - 1,10) if item_id.begins_with("EQ") else posmod(item_id.hash(),10)
	_variant = posmod(item_id.hash(),3)
	_motif = clampi(int(set_id.trim_prefix("S"))-1,0,7) if set_id.begins_with("S") else posmod(item_id.hash(),8)
	_accent = [Color("d89543"),Color("688ec9"),Color("98c8d8"),Color("65ad87"),Color("d8d8c2"),Color("caa74e"),Color("b5a1d7"),Color("91c7c5")][_motif] if not set_id.is_empty() else GOLD
	_poly([9,17, 17,9, 78,9, 87,18, 87,78, 78,87, 18,87, 9,78], Color("14232b"))
	_path([10,35, 10,18, 18,10, 35,10], Color(_accent,0.3))
	_path([61,86, 78,86, 86,78, 86,61], Color(_accent,0.3))
	draw_circle(Vector2(48,48),32,Color(_accent,0.035))
	var slot := str(equipment_data.get("slot",equipment_data.get("type","weapon"))).to_lower()
	match slot:
		"head", "helmet", "helm": _head()
		"chest", "body", "armor": _chest()
		"hands", "gloves", "hand", "glove": _hands()
		"feet", "boots", "foot", "boot": _feet()
		"charm", "amulet", "accessory", "trinket": _charm()
		_: _weapon(item_id)
	_hardware(slot)
	# The set mark is physically engraved into a little metal inventory tag.
	_poly([66,69, 78,69, 82,73, 82,83, 66,83], INK)
	_rune(Vector2(74,76),4.5)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func _weapon(item_id: String) -> void:
	if item_id.begins_with("EQ"):
		_module()
		return
	var category := str(equipment_data.get("weapon_type",equipment_data.get("hero_id",""))).to_lower()
	var name_text := str(equipment_data.get("name","")).to_lower()
	if "ch02" in category or "rifle" in category or "bow" in category or "枪" in name_text or "弩" in name_text:
		_rifle()
	elif "ch03" in category or "staff" in category or "focus" in category or "杖" in name_text or "晶" in name_text or "mage" in item_id.to_lower():
		_focus()
	else:
		_hammer()

func _module() -> void:
	# The game's weapons are universal add-on modules, each with its own outline.
	match _family:
		0: # Square brass locator box and white locating needle.
			_poly([24,30, 61,22, 74,34, 73,63, 35,75, 23,63],INK)
			_poly([27,32, 60,25, 70,35, 36,45],GOLD)
			_poly([28,36, 35,46, 35,69, 27,61],STEEL)
			_poly([39,47, 70,38, 69,61, 39,69],DARK)
			_path([47,58, 60,41, 60,24],LIGHT,3)
			draw_circle(Vector2(48,57),3,GOLD)
		1: # Open twin springs and red copper axle.
			_poly([23,63, 62,18, 76,30, 38,77],INK)
			_path([31,67, 67,26],Color("b17d61"),7)
			for rail in range(2):
				var shift := rail*13.0
				for n in range(6):
					_path([23+shift+n*4,57-n*5, 34+shift+n*4,59-n*5, 27+shift+n*4,52-n*5],LIGHT,2)
			_path([23,65, 38,77],GOLD,5)
			_path([60,18, 76,30],GOLD,5)
		2: # Three black iron petals contain an amber furnace core.
			_poly([48,14, 64,31, 60,43, 81,49, 67,70, 53,64, 33,81, 19,60, 33,45, 29,28],INK)
			_poly([48,18, 58,31, 54,42, 44,39, 36,29],STEEL)
			_poly([62,48, 76,50, 66,65, 55,61],STEEL)
			_poly([37,53, 45,62, 33,74, 24,60],STEEL)
			draw_circle(Vector2(48,48),15,DARK)
			draw_circle(Vector2(48,48),10,_accent)
			_poly([48,36, 53,47, 48,58, 43,48],LIGHT)
		3: # Three-pronged blue rail with floating copper contact points.
			_path([47,74, 47,45],INK,13)
			_path([47,72, 47,45],STEEL,7)
			for n in range(3):
				var x := 27+n*20.0
				_path([47,48, x,37, x,23],INK,9)
				_path([47,48, x,37, x,23],_accent,4)
				draw_circle(Vector2(x,16),3,GOLD)
			_path([36,63, 57,63],GOLD,3)
		4: # Broken white ring holding blue ripple plates.
			draw_arc(Vector2(47,47),27,-0.65,4.3,48,INK,13,true)
			draw_arc(Vector2(47,47),27,-0.65,4.3,48,LIGHT,7,true)
			for n in range(3):
				draw_arc(Vector2(47,47),10+n*5.0,-0.4,2.8,24,_accent,2,true)
			_poly([28,31, 36,22, 42,37],_accent)
		5: # Slanted green vial and copper capillary tube.
			_poly([48,22, 63,29, 60,37, 58,43, 57,70, 40,77, 27,65, 35,42, 44,34],INK)
			_poly([39,43, 54,48, 52,65, 41,70, 33,62],_accent)
			_poly([47,25, 60,31, 55,39, 43,34],GOLD)
			_path([43,46, 37,60],LIGHT,2)
			_path([54,39, 73,44, 70,65, 61,72],GOLD,3)
		6: # Square lock pierced with a white shield aperture.
			draw_arc(Vector2(47,33),14,PI,TAU,24,STEEL,7,true)
			_poly([25,33, 69,33, 75,39, 74,70, 67,77, 27,77, 21,70, 21,40],INK)
			_poly([29,39, 64,39, 69,44, 68,66, 62,71, 29,71, 26,67, 26,43],DARK)
			_poly([37,44, 57,44, 57,57, 47,67, 37,57],_accent)
			_poly([41,47, 53,47, 53,55, 47,61, 41,55],INK)
		7: # Cracked black stone balanced between suspended counterweights.
			_path([23,25, 71,25],STEEL,5)
			_path([29,25, 25,61],GOLD,2)
			_path([65,25, 70,61],GOLD,2)
			_poly([18,56, 32,56, 37,72, 14,72],STEEL)
			_poly([63,56, 77,56, 82,72, 59,72],STEEL)
			_poly([43,30, 57,35, 60,57, 48,68, 35,57, 36,40],INK)
			_path([46,34, 43,43, 51,47, 45,59],_accent,2)
		8: # Off-axis lens and three individually graduated arms.
			for n in range(3):
				var angle := n*TAU/3.0-0.2
				var axis := Vector2.from_angle(angle)
				var tangent := axis.orthogonal()
				draw_line(Vector2(47,47)+axis*15,Vector2(47,47)+axis*34,STEEL,5,true)
				for mark in range(3):
					var at := Vector2(47,47)+axis*(21+mark*5)
					draw_line(at,at+tangent*4,LIGHT,1,true)
			draw_circle(Vector2(47,47),20,INK)
			draw_arc(Vector2(47,47),17,0,TAU,36,GOLD,2,true)
			draw_circle(Vector2(43,43),12,_accent)
			_path([37,42, 44,35],LIGHT,2)
		9: # Thin cyan fin between two sand-white streaming tails.
			_poly([44,24, 63,27, 65,48, 49,58, 40,45],INK)
			_poly([49,24, 60,31, 60,44, 49,51, 44,43],_accent)
			_poly([46,45, 42,66, 26,76, 31,59, 29,48],LIGHT)
			_poly([59,44, 70,56, 68,74, 58,66, 51,54],LIGHT)
			_path([50,19, 50,31],GOLD,3)

func _hammer() -> void:
	_path([29,77, 62,31],INK,12)
	_path([29,77, 62,31],STEEL,7)
	_path([29,77, 43,58],DARK,7)
	for n in range(4):
		draw_line(Vector2(29+n*3,69-n*4),Vector2(35+n*3,72-n*4),_accent,2,true)
	if _variant == 0:
		_poly([34,28, 44,17, 78,42, 71,57, 55,49],INK)
		_poly([36,27, 45,20, 75,42, 67,46],LIGHT)
		_poly([36,30, 66,49, 71,45, 69,54, 56,47],STEEL)
		_path([49,25, 43,34],_accent,5)
		_path([67,37, 61,46],_accent,5)
	elif _variant == 1:
		_poly([42,13, 69,25, 77,45, 62,53, 34,31],INK)
		_poly([43,18, 65,29, 71,43, 61,45, 38,28],STEEL)
		_poly([45,17, 67,27, 63,35, 40,26],LIGHT)
		_poly([61,34, 72,31, 75,43, 66,48],_accent)
	else:
		_poly([39,17, 49,14, 79,36, 80,45, 67,60, 58,55, 31,32],INK)
		_poly([39,20, 46,18, 75,38, 67,45, 34,30],LIGHT)
		_poly([37,34, 64,54, 71,46, 43,26],STEEL)
		_poly([33,31, 39,25, 66,45, 61,50],_accent)
	_rune(Vector2(57,35),4)

func _rifle() -> void:
	_poly([19,69, 32,54, 38,58, 52,41, 73,20, 80,25, 60,47, 53,61, 47,57, 33,72, 25,76],INK)
	_path([30,65, 76,24],STEEL,8)
	_path([35,58, 70,26],LIGHT,3)
	_path([44,56, 72,31],_accent,2)
	_poly([17,71, 27,62, 35,63, 27,76],DARK)
	_poly([41,59, 50,60, 46,70, 40,67],_accent)
	_path([55,33, 62,27, 66,31],GOLD,4)
	if _variant == 1:
		_path([72,20, 82,22, 80,32],_accent,3)
	elif _variant == 2:
		_path([26,63, 21,52, 27,44, 36,46],STEEL,3)
	_rune(Vector2(40,54),3)

func _focus() -> void:
	_path([29,76, 61,32],INK,10)
	_path([29,76, 61,32],STEEL,5)
	_path([30,75, 40,61],_accent,3)
	var radius := 17.0 + _variant * 2.0
	draw_arc(Vector2(61,31),radius,-0.3,4.6,40,INK,8,true)
	draw_arc(Vector2(61,31),radius,-0.3,4.6,40,LIGHT,3,true)
	_poly([60,16, 69,28, 62,46, 53,32],_accent)
	_poly([60,16, 61,31, 53,32],LIGHT)
	_path([42,46, 49,49],GOLD,3)
	_rune(Vector2(61,31),4)

func _head() -> void:
	_poly([24,39, 30,22, 46,16, 64,22, 74,41, 70,66, 58,76, 48,71, 36,76, 25,61],INK)
	_poly([29,39, 35,25, 47,20, 62,27, 68,42, 63,50, 35,49],STEEL)
	_poly([33,29, 45,23, 45,43, 29,42],LIGHT)
	_poly([50,23, 61,29, 65,41, 51,43],DARK)
	_poly([29,46, 46,48, 46,63, 37,70, 28,60],STEEL)
	_poly([50,48, 68,44, 66,63, 58,70, 50,61],STEEL)
	_path([31,46, 45,48, 49,47, 63,44],_accent,3)
	if _variant == 0:
		_poly([44,17, 51,17, 54,36, 46,40, 43,31],_accent)
	elif _variant == 1:
		_poly([25,33, 18,26, 19,45, 28,48],_accent)
		_poly([68,33, 77,25, 77,44, 70,48],_accent)
	else:
		_poly([34,24, 28,15, 42,19, 44,30],_accent)
		_poly([53,26, 61,14, 66,21, 63,32],_accent)
	_rune(Vector2(49,58),5)

func _chest() -> void:
	_poly([30,19, 39,17, 43,26, 54,26, 60,17, 69,22, 81,34, 71,44, 65,42, 64,69, 51,79, 32,71, 29,43, 23,46, 14,34],INK)
	_poly([31,24, 41,31, 53,31, 63,24, 69,34, 61,43, 60,65, 49,71, 36,64, 34,42, 23,36],STEEL)
	_poly([33,27, 42,35, 44,53, 33,48, 31,40, 20,36],LIGHT)
	_poly([52,35, 60,31, 65,36, 58,46, 58,59, 51,63],DARK)
	_path([36,63, 48,69, 60,62],_accent,4)
	if _variant == 0:
		_path([29,27, 62,61],_accent,4)
	elif _variant == 1:
		_poly([16,32, 26,20, 36,24, 31,38, 24,41],_accent)
		_poly([64,22, 74,26, 80,34, 71,40, 63,34],_accent)
	else:
		_poly([39,35, 55,35, 59,50, 49,59, 39,49],_accent)
	_rune(Vector2(48,46),6)

func _hands() -> void:
	_poly([26,18, 48,20, 50,42, 58,34, 67,39, 63,56, 49,70, 27,77, 18,69, 17,51, 23,41],INK)
	_poly([29,22, 44,24, 45,42, 25,45],STEEL)
	_poly([25,49, 45,46, 51,48, 59,40, 62,43, 57,53, 44,66, 28,71, 22,64, 22,54],DARK)
	_poly([28,51, 44,49, 48,55, 43,62, 30,66, 24,61],LIGHT)
	_path([29,28, 43,30],_accent,4)
	_path([27,37, 45,39],_accent,3)
	for n in range(3):
		_path([27+n*6,52, 29+n*6,60],DARK,2)
	if _variant == 1:
		_poly([23,49, 15,46, 17,58, 24,60],_accent)
	elif _variant == 2:
		_poly([28,48, 32,42, 38,47, 42,41, 47,46, 47,51],_accent)
	_rune(Vector2(36,36),4)

func _feet() -> void:
	_poly([33,17, 58,17, 62,28, 56,52, 64,61, 77,65, 80,73, 73,80, 23,79, 18,69, 27,56, 29,29],INK)
	_poly([37,22, 54,22, 56,29, 50,52, 38,58, 30,54, 32,31],STEEL)
	_poly([36,26, 46,26, 42,48, 33,52],LIGHT)
	_poly([29,59, 42,61, 52,56, 60,65, 72,69, 74,74, 26,73, 23,68],STEEL)
	_poly([44,64, 52,60, 60,66, 66,68, 58,72, 42,71],DARK)
	_path([26,77, 72,77],_accent,3)
	if _variant == 0:
		_path([33,35, 51,37],_accent,4)
		_path([30,46, 49,48],_accent,3)
	elif _variant == 1:
		_poly([28,22, 36,25, 31,47, 23,50],_accent)
	else:
		_poly([40,20, 52,20, 50,34, 42,40, 36,33],_accent)
	_rune(Vector2(44,48),4)

func _charm() -> void:
	draw_arc(Vector2(48,34),18,-3.6,0.5,32,STEEL,3,true)
	draw_arc(Vector2(48,34),15,-3.6,0.5,32,LIGHT,1,true)
	_path([32,45, 38,53],STEEL,3)
	_path([63,44, 57,53],STEEL,3)
	if _variant == 0:
		_poly([48,40, 68,58, 49,81, 28,59],INK)
		_poly([48,45, 62,58, 49,74, 34,59],STEEL)
		_poly([48,48, 58,58, 49,69, 40,59],_accent)
	elif _variant == 1:
		draw_circle(Vector2(48,60),21,INK)
		draw_arc(Vector2(48,60),17,0,TAU,40,LIGHT,3,true)
		_poly([48,42, 57,61, 48,77, 39,60],_accent)
	else:
		_poly([33,45, 62,45, 69,55, 64,73, 49,80, 33,72, 27,55],INK)
		_poly([36,49, 59,49, 63,57, 58,69, 49,74, 38,68, 33,56],STEEL)
		_poly([42,49, 54,49, 58,59, 49,70, 39,60],_accent)
	_rune(Vector2(48,59),6)

func _hardware(slot: String) -> void:
	# Each catalogue entry owns a recognisable component, following its design brief.
	# These are silhouette changes and machined details, never palette swaps alone.
	if slot in ["head","helmet","helm"]:
		match _family:
			0:
				_path([25,43, 70,42],LIGHT,5)
				draw_circle(Vector2(43,43),11,GOLD)
				draw_circle(Vector2(43,43),7,INK)
				_path([39,41, 43,37],LIGHT,2)
			1:
				_poly([24,36, 61,32, 76,40, 74,46, 28,44],DARK)
				_path([61,33, 67,18, 78,22],LIGHT,3)
				_path([67,21, 71,23, 70,27, 66,25],DARK,1)
			2:
				_poly([55,26, 58,11, 72,16, 66,35],INK)
				_path([61,15, 69,18],STEEL,3)
				_poly([38,42, 56,40, 58,49, 37,51],_accent)
			3:
				draw_arc(Vector2(48,35),26,-2.9,-0.2,28,GOLD,3,true)
				draw_rect(Rect2(19,39,7,20),_accent)
				draw_rect(Rect2(69,39,7,20),_accent)
			4:
				for n in range(3):
					_poly([28+n*3,46+n*7, 49,39+n*7, 70-n*3,45+n*7, 49,56+n*7],LIGHT)
				_path([36,52, 43,51, 40,55],_accent,2)
				_path([54,51, 61,50, 58,54],_accent,2)
			5:
				draw_circle(Vector2(30,60),9,GOLD)
				draw_circle(Vector2(64,60),9,GOLD)
				draw_circle(Vector2(30,60),6,_accent)
				draw_circle(Vector2(64,60),6,_accent)
				for n in range(3):
					_path([41,56+n*4, 53,56+n*4],GOLD,2)
			6:
				_poly([26,34, 26,21, 34,21, 34,28, 41,28, 41,18, 52,18, 52,27, 60,27, 60,21, 69,21, 69,34],DARK)
				_poly([44,31, 52,31, 48,45],_accent)
			7:
				_poly([20,37, 28,31, 33,48, 27,67, 18,59],DARK)
				_poly([67,40, 76,37, 80,49, 74,61, 66,56],STEEL)
				_path([21,43, 25,47, 21,55],_accent,2)
			8:
				for lens in [Vector3(33,44,9),Vector3(50,42,7),Vector3(63,40,5)]:
					draw_circle(Vector2(lens.x,lens.y),lens.z+2,INK)
					draw_circle(Vector2(lens.x,lens.y),lens.z,_accent)
					draw_line(Vector2(lens.x-2,lens.y),Vector2(lens.x+2,lens.y-4),LIGHT,1,true)
			9:
				_poly([66,32, 82,42, 71,46, 83,57, 67,60, 62,44],_accent)
				_poly([42,29, 52,29, 47,43],LIGHT)
	elif slot in ["chest","body","armor"]:
		match _family:
			0:
				_poly([28,35, 40,37, 39,45, 28,44],GOLD)
				_poly([51,43, 61,41, 61,54, 53,56],Color("ad7b62"))
				_poly([36,57, 46,58, 45,68, 34,64],Color("8f9478"))
			1:
				_path([32,29, 61,66],GOLD,3)
				_path([63,29, 33,64],GOLD,3)
				draw_rect(Rect2(24,49,11,15),DARK)
				draw_rect(Rect2(59,49,11,15),DARK)
			2:
				_poly([29,57, 64,57, 69,76, 27,74],DARK)
				for n in range(5):
					_path([33+n*6,63, 33+n*6,70],_accent,2)
			3:
				_poly([20,28, 29,21, 39,28, 34,41, 20,36],_accent)
				_poly([62,23, 74,29, 75,39, 61,37],_accent)
				_path([39,34, 53,34, 58,46, 55,53],GOLD,2)
			4:
				_poly([28,36, 48,29, 69,35, 62,50, 48,59, 32,49],_accent)
				for n in range(3):
					_path([33,38+n*5, 48,45+n*5, 64,37+n*5],LIGHT,2)
			5:
				_poly([35,35, 57,35, 63,69, 47,76, 32,68],GOLD)
				_path([61,34, 68,43, 65,65, 54,68],_accent,4)
			6:
				draw_rect(Rect2(32,32,30,31),INK)
				draw_rect(Rect2(37,37,20,25),STEEL)
				_path([42,56, 42,43, 51,43, 51,56],_accent,3)
			7:
				_poly([40,30, 59,35, 62,52, 48,65, 35,53],INK)
				_path([38,36, 44,40, 40,48, 48,55],_accent,2)
				for at in [Vector2(32,30),Vector2(64,33),Vector2(33,58),Vector2(65,59)]:
					draw_circle(at,2,_accent)
			8:
				_poly([25,29, 37,32, 32,73, 22,83, 18,62],_accent)
				_poly([60,27, 71,32, 76,54, 62,59],DARK)
				for n in range(6):
					_path([25,43+n*5, 30,42+n*5],LIGHT,1)
			9:
				_poly([27,35, 18,50, 31,63, 35,48],_accent)
				_poly([66,35, 79,50, 66,63, 61,48],_accent)
				_poly([34,64, 45,64, 41,81, 31,74],LIGHT)
				_poly([51,64, 62,63, 67,75, 53,80],LIGHT)
	elif slot in ["hands","gloves","hand","glove"]:
		match _family:
			0:
				draw_rect(Rect2(30,28,15,12),GOLD,false,3)
			1:
				draw_arc(Vector2(35,56),9,0,TAU,24,Color("c39171"),3,true)
				for n in range(8):
					var axis := Vector2.from_angle(n*TAU/8)
					draw_line(Vector2(35,56)+axis*8,Vector2(35,56)+axis*12,GOLD,2,true)
			2:
				for n in range(3):
					_path([27+n*7,51, 25+n*7,68, 30+n*7,73],INK,5)
					_path([29+n*7,52, 28+n*7,63],_accent,1)
			3:
				draw_rect(Rect2(28,25,18,16),_accent)
				_path([33,42, 34,67, 40,70],GOLD,3)
				_path([43,42, 45,62, 51,61],GOLD,3)
			4:
				for n in range(3):
					_poly([25+n*8,53, 29+n*8,45, 33+n*8,54],_accent)
				_path([24,43, 46,42],LIGHT,5)
			5:
				_path([28,24, 22,35, 28,49, 36,52],_accent,4)
				for n in range(3):
					draw_arc(Vector2(29+n*7,57),3,0,TAU,12,GOLD,1,true)
			6:
				for n in range(3):
					draw_rect(Rect2(25+n*7,49,5,7),_accent)
				_path([25,42, 47,42],_accent,4)
			7:
				for n in range(3):
					_poly([23+n*9,48, 28+n*9,44, 31+n*9,49, 29+n*9,58, 23+n*9,57],INK)
				for n in range(4):
					_path([22,25+n*5, 28,28+n*5, 21,31+n*5],_accent,1)
			8:
				for n in range(3):
					_path([27+n*7,50, 29+n*7,64],_accent,4)
					_path([25+n*7,54, 31+n*7,57],LIGHT,1)
			9:
				draw_arc(Vector2(37,32),9,0,TAU,24,_accent,4,true)
				_path([43,38, 58,31, 67,39, 57,52],LIGHT,2)
				_path([57,51, 65,55],_accent,2)
	elif slot in ["feet","boots","foot","boot"]:
		match _family:
			0:
				_path([22,69, 27,77, 72,77, 78,70],GOLD,3)
			1:
				_path([26,79, 74,79],Color("c38c72"),3)
				draw_rect(Rect2(38,42,12,9),LIGHT,false,2)
			2:
				draw_rect(Rect2(17,58,14,19),DARK)
				for n in range(3):
					_path([19,61+n*5, 28,61+n*5],_accent,2)
			3:
				_path([25,82, 74,82],_accent,3)
				draw_arc(Vector2(42,38),14,-0.5,2.9,24,GOLD,3,true)
			4:
				for n in range(3):
					_path([30,28+n*8, 44,34+n*8, 54,27+n*8],LIGHT,3)
				for n in range(5):
					_poly([28+n*9,75, 36+n*9,75, 30+n*9,81],_accent)
			5:
				_poly([47,30, 55,30, 51,49, 44,52],_accent)
				_path([40,32, 36,54, 46,67, 69,69],GOLD,2)
			6:
				_poly([31,21, 59,21, 55,49, 33,51],INK)
				_path([35,48, 40,48, 40,36, 51,36, 51,48],_accent,3)
			7:
				_poly([22,71, 74,71, 78,77, 73,83, 25,81, 18,76],INK)
				_path([23,77, 74,78],STEEL,2)
				_path([33,32, 53,38],_accent,4)
			8:
				for n in range(6):
					_path([39,27+n*6, 44+n%2*3,27+n*6],LIGHT,1)
				_poly([24,68, 32,69, 32,81, 26,81],_accent)
			9:
				_poly([28,46, 16,36, 18,56, 32,65],_accent)
				_poly([32,51, 24,49, 29,61, 36,64],LIGHT)
	elif slot in ["charm","amulet","accessory","trinket"]:
		_charm_signature()

func _charm_signature() -> void:
	match _family:
		0:
			draw_circle(Vector2(48,59),15,GOLD)
			draw_circle(Vector2(48,59),11,DARK)
			_poly([53,46, 51,62, 43,70, 46,55],LIGHT)
			_path([30,44, 26,30, 44,16],Color("ba7869"),2)
		1:
			draw_rect(Rect2(29,43,36,31),GOLD)
			draw_rect(Rect2(32,46,30,25),INK)
			_path([47,45, 47,70],STEEL,2)
			_path([36,51, 41,51, 41,57, 36,62],LIGHT,2)
			_path([53,52, 57,51, 57,64],LIGHT,2)
		2:
			_poly([38,40, 54,39, 64,52, 61,70, 46,77, 31,67, 32,51],INK)
			_path([37,48, 40,43, 54,43],STEEL,3)
			draw_circle(Vector2(47,59),7,_accent)
			draw_circle(Vector2(47,59),3,LIGHT)
		3:
			_poly([31,39, 37,39, 38,60, 47,70, 58,60, 59,40, 65,40, 65,63, 51,78, 43,78, 31,63],GOLD)
			draw_circle(Vector2(48,54),8,_accent)
			_path([48,40, 48,45],LIGHT,1)
		4:
			_poly([48,39, 65,60, 61,74, 49,81, 34,73, 31,60],_accent)
			for n in range(3):
				_path([40,65+n*3, 49,61+n*3, 57,65+n*3],LIGHT,1)
		5:
			_poly([32,41, 62,41, 53,58, 66,77, 30,77, 42,57],GOLD)
			_poly([37,46, 57,46, 47,58],_accent)
			_poly([48,61, 57,73, 38,73],_accent)
			_path([29,43, 24,63, 32,76],STEEL,3)
		6:
			_poly([32,40, 61,40, 66,48, 64,73, 33,77, 28,68],INK)
			_path([47,43, 47,73],_accent,4)
			_path([35,45, 58,45],STEEL,1)
		7:
			_poly([36,42, 58,44, 67,58, 59,76, 41,79, 28,65, 30,52],INK)
			for n in range(3):
				_path([35,51+n*6, 45,48+n*6, 49,55+n*6, 61,53+n*6],_accent,1)
		8:
			_poly([39,37, 52,38, 57,77, 44,79],LIGHT)
			for n in range(7):
				_path([42,42+n*5, 46+n%2*3,42+n*5],DARK,1)
			_poly([61,43, 68,74, 59,66],_accent)
		9:
			_poly([38,40, 54,40, 57,62, 64,66, 30,66, 35,60],LIGHT)
			_poly([37,69, 44,68, 42,82, 34,85],_accent)
			_poly([51,68, 56,68, 62,80, 57,84],_accent)

func _rune(center: Vector2, radius: float) -> void:
	# Eight geometric languages persist across pieces in the same equipment set.
	var r := radius
	var color := LIGHT
	match _motif:
		0:
			draw_rect(Rect2(center-Vector2(r,r),Vector2(r*2,r*2)),color,false,1)
			draw_line(center-Vector2(r,0),center+Vector2(r,0),color,1)
		1:
			draw_polyline(PackedVector2Array([center+Vector2(-r,r),center+Vector2(0,-r),center+Vector2(r,r)]),color,1,true)
			draw_line(center-Vector2(r,0),center+Vector2(r,0),color,1)
		2:
			draw_arc(center,r,0,TAU,20,color,1,true)
			draw_circle(center,1.2,color)
		3:
			draw_line(center-Vector2(r,r),center+Vector2(r,r),color,1)
			draw_line(center+Vector2(-r,r),center+Vector2(r,-r),color,1)
		4:
			draw_polyline(PackedVector2Array([center+Vector2(-r,0),center+Vector2(0,-r),center+Vector2(r,0),center+Vector2(0,r),center+Vector2(-r,0)]),color,1,true)
		5:
			draw_line(center+Vector2(0,-r),center+Vector2(0,r),color,1)
			draw_line(center-Vector2(r,0),center+Vector2(0,r),color,1)
			draw_line(center+Vector2(r,0),center+Vector2(0,r),color,1)
		6:
			draw_arc(center,r,-2.6,2.6,16,color,1,true)
			draw_line(center-Vector2(r,0),center+Vector2(r*0.5,0),color,1)
		_:
			for index in range(3):
				draw_line(center+Vector2(-r,-r+index*r),center+Vector2(r,-r+index*r),color,1)
