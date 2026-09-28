extends Panel
## Small original metal joinery, kept outside the readable content area.

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var edge := Color("9b7950")
	var rivet := Color("b88b55")
	for corner in [Vector2(0,0),Vector2(size.x,0),Vector2(0,size.y),size]:
		var toward := Vector2(1 if corner.x == 0 else -1,1 if corner.y == 0 else -1)
		draw_line(corner+Vector2(toward.x*3,toward.y*13),corner+Vector2(toward.x*3,toward.y*3),edge,1)
		draw_line(corner+Vector2(toward.x*3,toward.y*3),corner+Vector2(toward.x*13,toward.y*3),edge,1)
		draw_circle(corner+toward*7,1.5,rivet)
	draw_line(Vector2(24,1),Vector2(minf(88,size.x-24),1),Color("d2a667"),1)

