extends Node2D
## A still, sunlit courtyard makes menus readable without camera-like motion.

var camp := false
var keyart: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/generated/ui/refactor_v1/forest_backdrop.png"):
		keyart = load("res://assets/generated/ui/refactor_v1/forest_backdrop.png")
	elif ResourceLoader.exists("res://assets/generated/world/storybook_camp_v1.png"):
		keyart = load("res://assets/generated/world/storybook_camp_v1.png")
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var extent := get_viewport_rect().size
	var frame := Rect2(Vector2.ZERO,extent)
	draw_rect(frame,Color("c4e3d7"))
	if keyart != null:
		var fit := maxf(extent.x/keyart.get_width(),extent.y/keyart.get_height())
		var fitted := keyart.get_size()*fit
		draw_texture_rect(keyart,Rect2((extent-fitted)*0.5,fitted),false)
		draw_rect(frame,Color(0.98,0.98,0.94,0.22))
		return
	draw_set_transform(Vector2.ZERO,0,extent/Vector2(1280,720))
	_draw_courtyard()

func _draw_courtyard() -> void:
	# Broad colour planes echo the map's cream stone and turquoise channels.
	draw_rect(Rect2(0,0,1280,720),Color("cee6d5"))
	draw_rect(Rect2(1080,0,200,720),Color("52b5b5"))
	for i in range(10):
		var y := 90.0+i*66.0
		draw_line(Vector2(1088,y),Vector2(1280,y-10),Color("8ad3c3"),3,true)
	var paving := PackedVector2Array([Vector2(0,175),Vector2(993,102),Vector2(1148,720),Vector2(0,720)])
	draw_colored_polygon(paving,Color("ead9ae"))
	for row in range(7):
		var y := 201.0+row*83.0
		draw_line(Vector2(0,y),Vector2(1080+row*10,y-38),Color("c7b38f"),1,true)
		for column in range(7):
			var x := 80.0+column*165.0+(54.0 if row%2 else 0.0)
			draw_line(Vector2(x,y),Vector2(x+22,y+83),Color("c7b38f"),1,true)
	# Pale ruined colonnades, grouped at the edge of a clear terrace.
	for index in range(4):
		var x := 652.0+index*142.0
		var h := 224.0+index%2*50.0
		draw_rect(Rect2(x+15,61,44,h),Color("a5b9aa"))
		draw_rect(Rect2(x,44,46,h),Color("f4e9c9"))
		draw_rect(Rect2(x-9,39,64,22),Color("fff4d3"))
		draw_rect(Rect2(x-10,44+h,70,21),Color("b8a588"))
		draw_line(Vector2(x+13,67),Vector2(x+13,h+30),Color("d3c4a4"),2,true)
		var banner := PackedVector2Array([Vector2(x+8,89),Vector2(x+38,89),Vector2(x+38,172),Vector2(x+23,189),Vector2(x+8,172)])
		draw_colored_polygon(banner,Color("348b8d"))
		draw_line(Vector2(x+23,102),Vector2(x+23,166),Color("ddb977"),2,true)
		_leaf_cluster(Vector2(x+25,53),index)
	_leaf_cluster(Vector2(1057,616),4)
	_leaf_cluster(Vector2(1219,414),5)
	draw_arc(Vector2(901,455),89,0,TAU,64,Color("c4ad83"),2,true)
	draw_arc(Vector2(901,455),71,0,TAU,64,Color("cfbb94"),1,true)
	for index in range(8):
		var axis := Vector2.from_angle(index*TAU/8.0)
		draw_line(Vector2(901,455)+axis*15,Vector2(901,455)+axis*70,Color("c4ad83"),1,true)
	# Stable ambient foliage avoids drifting particles across text.
	for index in range(8):
		_leaf_cluster(Vector2(702+index*74,690+sin(index*2.3)*19),index+2)
	draw_line(Vector2(56,55),Vector2(1224,55),Color(MineStyle.COPPER,0.55),1,true)
	draw_line(Vector2(56,665),Vector2(1224,665),Color(MineStyle.COPPER,0.55),1,true)

func _leaf_cluster(center: Vector2, seed_index: int) -> void:
	for index in range(11):
		var angle := index*2.4+seed_index*0.8
		var at := center+Vector2.from_angle(angle)*(14.0+index%4*12.0)
		var tone: Color = [Color("487e68"),Color("76a771"),Color("aac477")][index%3]
		draw_circle(at,15.0+index%3*4,tone)
		if index%4 == 0:
			draw_circle(at+Vector2(7,-4),3.4,Color("fff0b4"))
