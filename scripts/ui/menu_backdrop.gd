extends Node2D

var camp := false
var phase := 0.0
var keyart: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/ui/mine_keyart.png"):
		keyart = load("res://assets/ui/mine_keyart.png")

func _process(delta: float) -> void:
	phase += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720), Color("0d131a"))
	if keyart != null:
		draw_texture_rect(keyart,Rect2(0,0,1280,720),false)
		draw_rect(Rect2(0,0,1280,720),Color(0.02,0.035,0.05,0.30 if camp else 0.12))
		for i in range(24):
			var at := Vector2(718+i*19,210+fmod(i*39.7-phase*(4+i%3),480))
			draw_circle(at,0.7,Color(0.7,0.75,0.67,0.1))
		draw_line(Vector2(56,56),Vector2(1224,56),Color(0.55,0.41,0.25,0.55),1)
		draw_line(Vector2(56,665),Vector2(1224,665),Color(0.55,0.41,0.25,0.55),1)
		for p in [Vector2(56,56),Vector2(1224,56),Vector2(56,665),Vector2(1224,665)]:
			draw_circle(p,2,Color("ba925a"))
		return
	# Original geometry: mine ribs, hoist cables, mineral seams and a hanging lantern.
	for i in range(12):
		var x := 480.0 + i * 72.0
		draw_line(Vector2(x,0),Vector2(x-180,720),Color("16232b"),1)
	for i in range(9):
		var y := 70.0 + i * 80
		draw_line(Vector2(600,y),Vector2(1280,y+45),Color("1a2830"),1)
	var center := Vector2(942,334)
	for radius in [222,204,160]:
		draw_arc(center,radius,0,TAU,72,Color("273a40"),2,true)
	for index in range(16):
		var angle := index * TAU / 16
		var direction := Vector2.from_angle(angle)
		draw_line(center+direction*196,center+direction*230,Color("6b5740"),3,true)
	draw_rect(Rect2(770,87,345,466),Color("111d24"))
	draw_rect(Rect2(770,87,345,466),Color("6f5940"),false,2)
	for x in [789,825,1060,1096]:
		draw_line(Vector2(x,89),Vector2(x,550),Color("31434a"),5)
	for y in [111,512,540]:
		draw_line(Vector2(769,y),Vector2(1115,y),Color("786143"),3)
	draw_line(Vector2(942,0),Vector2(942,260),Color("7a684e"),3)
	var glow := 1.0 if Game.profile.get("settings",{}).get("reduced_fx",false) else 0.95 + sin(phase*1.1)*0.05
	for i in range(12,0,-1):
		draw_circle(center,22.0+i*8,Color(0.90,0.55,0.17,0.008*glow))
	draw_line(Vector2(942,259),Vector2(921,277),Color("b88a46"),3)
	draw_line(Vector2(921,277),Vector2(921,302),Color("b88a46"),3)
	draw_line(Vector2(921,302),Vector2(966,302),Color("b88a46"),3)
	draw_line(Vector2(966,302),Vector2(966,277),Color("b88a46"),3)
	draw_rect(Rect2(913,309,61,69),Color("2c3536"))
	draw_rect(Rect2(920,315,46,55),Color("e6aa4a"))
	draw_rect(Rect2(920,315,46,55),Color("edcf7e"),false,2)
	for x in [921,942,965]:
		draw_line(Vector2(x,312),Vector2(x,374),Color("433927"),3)
	draw_rect(Rect2(907,302,73,10),Color("96794e"))
	draw_rect(Rect2(907,377,73,10),Color("96794e"))
	for i in range(7):
		var x := 650.0 + i*91
		var y := 606.0 + sin(i*3)*22
		var points := PackedVector2Array([Vector2(x,y),Vector2(x+7,y-24),Vector2(x+17,y-39),Vector2(x+21,y-7),Vector2(x+32,y+5)])
		draw_colored_polygon(points,Color("30626c"))
		draw_polyline(points,Color("67c7d5"),1,true)
	draw_line(Vector2(744,720),Vector2(869,460),Color("3b4649"),5)
	draw_line(Vector2(1100,720),Vector2(1015,460),Color("3b4649"),5)
	for i in range(6):
		var y := 481+i*42.0
		draw_line(Vector2(862-i*19,y),Vector2(1021+i*13,y),Color("384344"),7)
	draw_rect(Rect2(0,0,650,720),Color(0.05,0.075,0.10,0.86))
	draw_line(Vector2(56,56),Vector2(1224,56),Color("584935"),1)
	draw_line(Vector2(56,665),Vector2(1224,665),Color("584935"),1)
	for p in [Vector2(56,56),Vector2(1224,56),Vector2(56,665),Vector2(1224,665)]:
		draw_circle(p,3,Color("a27e4e"))
