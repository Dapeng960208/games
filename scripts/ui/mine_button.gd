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
	var color := MineStyle.CYAN if active else MineStyle.COPPER
	# Fine paper highlights and a single accent avoid heavy metal frames.
	draw_line(Vector2(12,3),Vector2(size.x-12,3),Color(MineStyle.PAPER_LIGHT,0.8),1,true)
	draw_circle(Vector2(9,size.y*0.5),1.3,Color(color,0.7))
	draw_circle(Vector2(size.x-9,size.y*0.5),1.3,Color(color,0.7))
	if active:
		draw_line(Vector2(4,12),Vector2(4,size.y-12),color,2,true)
