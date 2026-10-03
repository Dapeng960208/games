extends RefCounted
## Global material grid clipped to existing floor rectangles; never extends ground.
static func draw(canvas: CanvasItem, texture: Texture2D, floors: Array[Rect2], world_size: Vector2, tile_width: float) -> void:
	if texture==null or tile_width<=0: return
	for x in ceili(world_size.x/tile_width):
		for y in ceili(world_size.y/tile_width):
			var tile:=Rect2(Vector2(x,y)*tile_width,Vector2.ONE*tile_width)
			for floor_rect: Rect2 in floors:
				var part:=tile.intersection(floor_rect)
				if not part.has_area(): continue
				var source:=Rect2((part.position-tile.position)/tile_width*texture.get_size(),part.size/tile_width*texture.get_size())
				canvas.draw_texture_rect_region(texture,part,source)
