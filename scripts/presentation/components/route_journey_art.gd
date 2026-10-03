extends Control
## Illustrated route line; symbols keep a consistent UI scale.
const STEP := 109.0
var nodes: Array = []
var current := 0
var completed: Array = []
var finale := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func node_center(index: int) -> Vector2:
	return Vector2(48.0 + index * STEP, 46.0 + (8.0 if index % 2 else -5.0))

func _draw() -> void:
	for index: int in maxi(0, nodes.size() - 1):
		var start := node_center(index)
		var finish := node_center(index + 1)
		var points := PackedVector2Array()
		for sample: int in 25:
			var amount := float(sample) / 24.0
			points.append(start.lerp(finish, amount) + Vector2(0, sin(amount * PI) * (9.0 if index % 2 else -9.0)))
		draw_polyline(points, Color("385d98") if finale else Color("846344"), 5.0, true)
		draw_polyline(points, Color("ddba78"), 2.0, true)
		if completed.has(index): draw_polyline(points, Color("719a75"), 2.0, true)
	var font := get_theme_font("font", "Label")
	var roles: Dictionary = {"entrance":"入口", "branch":"分支", "objective":"目标", "supply":"补给", "elite_objective":"精英", "boss":"首领"}
	if Words.locale == "en": roles = {"entrance":"Entry", "branch":"Branch", "objective":"Objective", "supply":"Supply", "elite_objective":"Elite", "boss":"Boss"}
	for index: int in nodes.size():
		var at := node_center(index)
		var is_current := index == current
		var is_done := completed.has(index)
		var face := Color("3b8587") if is_current else (Color("d9e5c8") if is_done else Color("e5d9c3"))
		if finale: face = Color("315a97") if is_current else (Color("dceaf9") if is_done else Color("f5f9ff"))
		var ink := Color("fff3d0") if is_current else (Color("4e7455") if is_done else Color("8d8090"))
		if is_current: draw_circle(at, 33.0, Color(0.77, 0.60, 0.32, 0.16))
		draw_circle(at + Vector2(0, 2), 28.0, Color(0.28, 0.20, 0.24, 0.12))
		draw_circle(at, 27.0, Color("775331"))
		draw_circle(at, 25.0, Color("e9c98b"))
		draw_circle(at, 22.0, face)
		draw_arc(at, 23.0, PI * 1.1, PI * 1.9, 30, Color("fff3ce"), 1.4, true)
		var role := str(nodes[index].get("role", "branch"))
		draw_role(self, role, at, 14.0, ink)
		var number_at := at + Vector2(21, 20)
		draw_circle(number_at, 10.0, Color("775331"))
		draw_circle(number_at, 8.6, Color("fff1ce"))
		var number := str(index + 1)
		var number_width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, number_at + Vector2(-number_width * .5, 3.7), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GameStyle.INK)
		var label := str(roles.get(role, role))
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(at.x - label_width * .5, 94), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, (Color("315a97") if finale else GameStyle.CYAN) if is_current else GameStyle.MUTED)
		if is_done: draw_polyline(PackedVector2Array([at + Vector2(-6, -30), at + Vector2(-2, -26), at + Vector2(7, -34)]), GameStyle.GREEN, 2.4, true)
		if is_current: draw_colored_polygon(PackedVector2Array([at + Vector2(-4, -39), at + Vector2(4, -39), at + Vector2(0, -32)]), GameStyle.CYAN)

static func draw_role(canvas: CanvasItem, role: String, at: Vector2, radius: float, ink: Color) -> void:
	var r := radius
	match role:
		"entrance":
			canvas.draw_polyline(PackedVector2Array([at+Vector2(-r,r*.8), at+Vector2(-r,-r*.4), at+Vector2(0,-r), at+Vector2(r,-r*.4), at+Vector2(r,r*.8)]), ink, 2.2, true)
			canvas.draw_line(at+Vector2(-r*.4,r*.8), at+Vector2(-r*.4,-r*.25), ink, 2.0, true)
			canvas.draw_line(at+Vector2(r*.4,r*.8), at+Vector2(r*.4,-r*.25), ink, 2.0, true)
		"supply":
			canvas.draw_polyline(PackedVector2Array([at+Vector2(-r*.35,-r), at+Vector2(-r*.35,-r*.35), at+Vector2(-r*.7,r*.4), at+Vector2(-r*.45,r*.85), at+Vector2(r*.45,r*.85), at+Vector2(r*.7,r*.4), at+Vector2(r*.35,-r*.35), at+Vector2(r*.35,-r)]), ink, 2.1, true)
			canvas.draw_line(at+Vector2(-r*.3,0), at+Vector2(r*.3,0), ink, 2.0, true)
			canvas.draw_line(at+Vector2(0,-r*.3), at+Vector2(0,r*.3), ink, 2.0, true)
		"boss":
			canvas.draw_polyline(PackedVector2Array([at+Vector2(-r,-r*.5), at+Vector2(-r*.7,r*.65), at+Vector2(r*.7,r*.65), at+Vector2(r,-r*.5), at+Vector2(r*.45,-r*.05), at+Vector2(0,-r), at+Vector2(-r*.45,-r*.05), at+Vector2(-r,-r*.5)]), ink, 2.2, true)
			canvas.draw_circle(at+Vector2(0,r*.15), 2.0, ink)
		"objective":
			canvas.draw_line(at+Vector2(-r*.65,r), at+Vector2(-r*.65,-r), ink, 2.3, true)
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(-r*.6,-r*.9), at+Vector2(r,-r*.6), at+Vector2(r*.55,0), at+Vector2(-r*.6,-r*.25)]), ink)
		"elite_objective":
			for mirror: float in [-1.0,1.0]:
				canvas.draw_line(at+Vector2(-r*.8*mirror,r*.85), at+Vector2(r*.75*mirror,-r*.8), ink, 2.7, true)
				canvas.draw_line(at+Vector2(-r*.85*mirror,r*.15), at+Vector2(-r*.25*mirror,r*.7), ink, 2.2, true)
		_:
			canvas.draw_arc(at, r*.75, 0, TAU, 30, ink, 1.6, true)
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-r), at+Vector2(r*.33,0), at+Vector2(0,r), at+Vector2(-r*.33,0)]), ink)
			canvas.draw_line(at+Vector2(-r,0), at+Vector2(r,0), ink, 1.0, true)
