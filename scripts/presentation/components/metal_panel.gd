extends Panel
## Soft ivory panel with restrained antique-gold ornament at generous sizes.
static var corner: Texture2D
func _ready() -> void:
	resized.connect(queue_redraw)
	if corner == null and ResourceLoader.exists(AssetCatalog.resolve("asset://ui/refactor_v1/decor/panel_corner_tl.png")):
		corner = load(AssetCatalog.resolve("asset://ui/refactor_v1/decor/panel_corner_tl.png"))
func _draw() -> void:
	if size.x < 240 or size.y < 160: return
	if corner != null:
		var edge := minf(42,size.y*0.12)
		draw_texture_rect(corner,Rect2(3,3,edge,edge),false,Color(1,1,1,0.22))
		draw_set_transform(Vector2(size.x-3,size.y-3),PI)
		draw_texture_rect(corner,Rect2(0,0,edge,edge),false,Color(1,1,1,0.18))
		draw_set_transform(Vector2.ZERO)
