extends Panel
## A parchment journal card with restrained copper registration details.

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 44 or size.y < 24:
		return
	draw_line(Vector2(20,3),Vector2(minf(66,size.x-20),3),MineStyle.COPPER,2,true)
	draw_line(Vector2(20,size.y-4),Vector2(minf(44,size.x-20),size.y-4),Color(MineStyle.COPPER,0.55),1,true)
	var mark := Vector2(size.x-17,16)
	draw_polyline(PackedVector2Array([mark+Vector2(-4,0),mark+Vector2(0,-4),mark+Vector2(4,0),mark+Vector2(0,4),mark+Vector2(-4,0)]),Color(MineStyle.COPPER,0.75),1,true)
