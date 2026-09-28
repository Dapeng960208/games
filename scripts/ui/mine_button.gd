extends Button

func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	if disabled:
		return
	var active := is_hovered() or has_focus()
	var color := Color("e6aa4a") if active else Color("685842")
	var y := size.y/2
	draw_polyline(PackedVector2Array([Vector2(8,y-4),Vector2(12,y),Vector2(8,y+4)]),color,1.5,true)
	if active:
		draw_line(Vector2(size.x-5,10),Vector2(size.x-5,size.y-10),color,2)
		draw_line(Vector2(2,11),Vector2(2,size.y-11),color,2)

