extends Node2D
## Original generated floor with procedural industrial fixtures; no decorative collisions.

const DARK := Color("0d131a")
const PANEL := Color("17232c")
const COPPER := Color("b77c46")
const CYAN := Color("67c7d5")
var floor_texture: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/world/mine_floor.png"):
		floor_texture = load("res://assets/world/mine_floor.png")


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), DARK)
	draw_rect(Rect2(32, 94, 1216, 512), Color("1e2b33"))
	draw_rect(Rect2(48, 106, 1184, 488), Color("131e26"))
	if floor_texture != null:
		draw_texture_rect(floor_texture,Rect2(48,106,1184,488),false,Color(0.75,0.75,0.75))
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 41827
		for row in range(8):
			for column in range(20):
				var x := 50.0 + column * 59.0
				var y := 109.0 + row * 60.0
				var shade := rng.randf_range(0.065, 0.09)
				draw_rect(Rect2(x, y, 57, 58), Color(shade, shade + 0.038, shade + 0.066))
				if rng.randf() < 0.22:
					draw_line(Vector2(x + 8, y + 46), Vector2(x + 31, y + 39), Color(0.22, 0.28, 0.3, 0.2), 1)
	# A heavy frame makes the playable limit visible without interior fake obstacles.
	draw_rect(Rect2(46, 104, 1188, 492), Color("35404a"), false, 3)
	draw_line(Vector2(60, 108), Vector2(1220, 108), Color(COPPER, 0.5), 2)
	draw_line(Vector2(60, 592), Vector2(1220, 592), Color(COPPER, 0.4), 2)
	for x in range(76, 1220, 58):
		draw_circle(Vector2(x, 99), 2, COPPER.darkened(0.3))
		draw_circle(Vector2(x, 601), 2, COPPER.darkened(0.3))
	# Disused rail tracks run along the margins, clear of the fighting floor.
	for y in [132.0, 566.0]:
		for x in range(176, 1192, 24):
			draw_line(Vector2(x, y - 9), Vector2(x, y + 9), Color("27343b"), 5)
		draw_line(Vector2(166, y - 5), Vector2(1208, y - 5), Color("455058"), 2)
		draw_line(Vector2(166, y + 5), Vector2(1208, y + 5), Color("455058"), 2)
		draw_line(Vector2(166, y - 4), Vector2(1208, y - 4), Color(COPPER, 0.18), 1)
	_pipe(PackedVector2Array([Vector2(17, 152), Vector2(17, 276), Vector2(34, 291), Vector2(34, 540)]))
	_pipe(PackedVector2Array([Vector2(1262, 144), Vector2(1262, 404), Vector2(1248, 420), Vector2(1248, 564)]))
	for y in [180.0, 302.0, 480.0]:
		_machine(Vector2(28, y), false)
		_machine(Vector2(1252, y + 27), true)
	for x in [236.0, 548.0, 948.0, 1172.0]:
		_lamp(Vector2(x, 113))
		_lamp(Vector2(x - 48, 588))
	for p in [Vector2(63, 147), Vector2(1206, 154), Vector2(78, 565), Vector2(1211, 552)]:
		_crystals(p)
	# Faint worn marks provide scale and an industrial floor pattern.
	for x in [268.0, 1012.0]:
		for y in [278.0, 464.0]:
			draw_arc(Vector2(x, y), 19, 0, TAU, 20, Color(0.27, 0.37, 0.4, 0.12), 1)
			draw_line(Vector2(x - 8, y), Vector2(x + 8, y), Color(0.27, 0.37, 0.4, 0.15), 1)
	# Edge shadows keep the bright player and enemies in the visual foreground.
	for i in range(7):
		var alpha := 0.07 * (1.0 - i / 7.0)
		draw_rect(Rect2(49 + i * 3, 107 + i * 3, 1182 - i * 6, 486 - i * 6), Color(0.0, 0.0, 0.0, alpha), false, 3)


func _pipe(points: PackedVector2Array) -> void:
	draw_polyline(points, Color("070d13"), 13, true)
	draw_polyline(points, COPPER.darkened(0.5), 8, true)
	draw_polyline(points, Color(COPPER, 0.38), 2, true)
	for i in range(1, points.size()):
		var middle := points[i - 1].lerp(points[i], 0.55)
		draw_rect(Rect2(middle - Vector2(7, 4), Vector2(14, 8)), Color("38434a"))
		draw_line(middle + Vector2(-6, -3), middle + Vector2(6, -3), COPPER.darkened(0.2), 1)


func _machine(p: Vector2, right_side: bool) -> void:
	draw_rect(Rect2(p - Vector2(17, 23), Vector2(34, 46)), Color("0b1219"))
	draw_rect(Rect2(p - Vector2(14, 21), Vector2(28, 42)), PANEL)
	draw_rect(Rect2(p - Vector2(14, 21), Vector2(28, 42)), Color("414a50"), false, 1)
	for y in range(-13, 15, 6):
		draw_line(p + Vector2(-8, y), p + Vector2(8, y), Color("080e13"), 2)
	var lamp_x := -10.0 if right_side else 10.0
	draw_circle(p + Vector2(lamp_x, -16), 2, CYAN)
	draw_line(p + Vector2(-12, 18), p + Vector2(12, 18), COPPER.darkened(0.4), 2)


func _lamp(p: Vector2) -> void:
	for radius in [27.0, 18.0, 11.0]:
		draw_circle(p, radius, Color(CYAN, 0.022))
	draw_rect(Rect2(p - Vector2(9, 5), Vector2(18, 10)), Color("080e13"))
	draw_rect(Rect2(p - Vector2(7, 3), Vector2(14, 6)), COPPER.darkened(0.4))
	draw_rect(Rect2(p - Vector2(4, 2), Vector2(8, 4)), CYAN)


func _crystals(p: Vector2) -> void:
	for radius in [29.0, 20.0, 12.0]:
		draw_circle(p, radius, Color(CYAN, 0.023))
	for i in range(3):
		var offset := Vector2((i - 1) * 9.0, abs(i - 1) * 3.0)
		var height: float = 20.0 - absi(i - 1) * 7.0
		var poly := PackedVector2Array([p + offset + Vector2(-4, 4), p + offset + Vector2(-5, -height * 0.5), p + offset + Vector2(0, -height), p + offset + Vector2(5, -height * 0.45), p + offset + Vector2(4, 4)])
		draw_colored_polygon(poly, Color("285560"))
		draw_line(p + offset + Vector2(0, -height), p + offset + Vector2(4, -height * 0.45), CYAN, 1)
		draw_line(p + offset + Vector2(0, -height), p + offset + Vector2(0, 3), Color(CYAN, 0.45), 1)
