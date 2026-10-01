extends StyleBox
## Raw hand-painted components, with independently scaled tips and live text.
const TEXTURE_PATH := "res://assets/generated/ui/storybook_buttons_v2.png"
const MANIFEST_PATH := "res://assets/generated/ui/storybook_buttons_v2.regions.json"
static var atlas: Texture2D
static var regions: Dictionary = {}
var kind := "secondary"
var tint := Color.WHITE
var focus_only := false

static func create(style_kind: String = "secondary", state: String = "normal") -> StyleBox:
	var result := load("res://scripts/ui/button_skin.gd").new() as StyleBox
	result.set("kind",style_kind)
	result.set("focus_only",state == "focus")
	result.set("tint",{"hover":Color(1.08,1.08,1.04),"pressed":Color(0.81,0.89,0.89),"disabled":Color(0.67,0.67,0.64,0.72)}.get(state,Color.WHITE))
	result.content_margin_left = 42 if style_kind == "selector" else 22
	result.content_margin_right = 22
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result

static func _load_atlas() -> void:
	if regions.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			regions = parsed.get("regions",{})
	if atlas == null:
		if ResourceLoader.exists(TEXTURE_PATH):
			atlas = load(TEXTURE_PATH)
		else:
			# New art can be previewed before the editor finishes its first import.
			var image := Image.load_from_file(TEXTURE_PATH)
			if image != null and not image.is_empty():
				atlas = ImageTexture.create_from_image(image)

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _draw(canvas_item: RID, rect: Rect2) -> void:
	_load_atlas()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	if focus_only:
		_draw_focus(canvas_item,rect)
		return
	if atlas == null:
		RenderingServer.canvas_item_add_rect(canvas_item,rect,Color("fff3d7"))
		return
	if kind in ["socket","selected_socket"]:
		_draw_socket(canvas_item,rect,kind == "selected_socket")
		return
	if kind in ["card","selected_card"]:
		_draw_card(canvas_item,rect)
		if kind == "selected_card":
			_draw_card_selection(canvas_item,rect)
		return
	_draw_component(canvas_item,rect,kind,tint)

func _draw_component(canvas_item: RID, rect: Rect2, component: String, color: Color) -> void:
	var data: Dictionary = regions.get(component,regions.get("secondary",{}))
	if data.is_empty():
		return
	var box: Array = data.rect
	var source := Rect2(box[0],box[1],box[2],box[3])
	var caps: Array = data.caps
	var edges: Array = data.edges
	var scale := minf(rect.size.y,64.0) / source.size.y
	# Cap sizes never force a narrow icon/key button to grow horizontally.
	var left := minf(float(caps[0])*scale,rect.size.x*0.24)
	var right := minf(float(caps[1])*scale,rect.size.x*0.24)
	var top := minf(float(edges[0])*scale,rect.size.y*0.35)
	var bottom := minf(float(edges[1])*scale,rect.size.y*0.35)
	var sx := [0.0,float(caps[0]),source.size.x-float(caps[1]),source.size.x]
	var sy := [0.0,float(edges[0]),source.size.y-float(edges[1]),source.size.y]
	var dx := [0.0,left,rect.size.x-right,rect.size.x]
	var dy := [0.0,top,rect.size.y-bottom,rect.size.y]
	for row in 3:
		for column in 3:
			var part := Rect2(source.position+Vector2(sx[column],sy[row]),Vector2(sx[column+1]-sx[column],sy[row+1]-sy[row]))
			var destination := Rect2(rect.position+Vector2(dx[column],dy[row]),Vector2(dx[column+1]-dx[column],dy[row+1]-dy[row]))
			atlas.draw_rect_region(canvas_item,destination,part,color,false,true)

func _draw_card(canvas_item: RID, rect: Rect2) -> void:
	# Equipment/relic cards need a large quiet paper face, not stretched end jewels.
	var inset := Rect2(rect.position+Vector2(5,5),rect.size-Vector2(10,10))
	atlas.draw_rect_region(canvas_item,inset,Rect2(280,308,455,85),tint,false,true)
	var ink := Color(0.60,0.43,0.24,0.70) * tint
	for side in [0.0,1.0]:
		var x: float = rect.position.x+5+(rect.size.x-10)*float(side)
		RenderingServer.canvas_item_add_line(canvas_item,Vector2(x,rect.position.y+16),Vector2(x,rect.end.y-16),ink,1.5,true)
	_draw_component(canvas_item,Rect2(rect.position,Vector2(rect.size.x,34)),"secondary",tint)
	_draw_component(canvas_item,Rect2(Vector2(rect.position.x,rect.end.y-24),Vector2(rect.size.x,24)),"secondary",tint)

func _draw_focus(canvas_item: RID, rect: Rect2) -> void:
	# A visible gold underline and two sparks survive every silhouette and palette.
	var left := Vector2(rect.position.x+minf(36,rect.size.x*0.2),rect.end.y-3)
	var right := Vector2(rect.end.x-minf(36,rect.size.x*0.2),rect.end.y-3)
	RenderingServer.canvas_item_add_line(canvas_item,left,right,Color("257f83"),3.0,true)
	RenderingServer.canvas_item_add_line(canvas_item,left,right,Color("ffe8a5"),1.0,true)
	for point in [left,right]:
		RenderingServer.canvas_item_add_circle(canvas_item,point,2.2,Color("fff9d8"))

func _draw_card_selection(canvas_item: RID, rect: Rect2) -> void:
	var teal := Color("257f83")
	var gold := Color("dfb75b")
	# The paper stays pale for child labels; selection lives in the binding trim.
	for side: float in [0.0,1.0]:
		var x: float = rect.position.x+6+(rect.size.x-12)*side
		RenderingServer.canvas_item_add_line(canvas_item,Vector2(x,rect.position.y+31),Vector2(x,rect.end.y-23),teal,2.5,true)
	var mark := rect.position+Vector2(rect.size.x-27,31)
	var flag := PackedVector2Array([mark,mark+Vector2(15,0),mark+Vector2(15,20),mark+Vector2(7.5,15),mark+Vector2(0,20)])
	RenderingServer.canvas_item_add_polygon(canvas_item,flag,PackedColorArray([teal]))
	for index: int in flag.size():
		RenderingServer.canvas_item_add_line(canvas_item,flag[index],flag[(index+1)%flag.size()],gold,1.2,true)

func _draw_socket(canvas_item: RID, rect: Rect2, selected: bool) -> void:
	# Compact equipment mounts have a quiet full face for the icon and its label.
	# Only thin brass binding and eight-pixel enamel studs occupy their perimeter.
	var face := Rect2(rect.position+Vector2(3,3),rect.size-Vector2(6,6))
	atlas.draw_rect_region(canvas_item,face,Rect2(280,308,455,85),tint,false,true)
	var edge := Color("257f83") if selected else Color("c49b60")
	var corners := PackedVector2Array([
		rect.position+Vector2(7,2),Vector2(rect.end.x-7,rect.position.y+2),
		Vector2(rect.end.x-2,rect.position.y+7),rect.end-Vector2(2,7),
		rect.end-Vector2(7,2),Vector2(rect.position.x+7,rect.end.y-2),
		Vector2(rect.position.x+2,rect.end.y-7),rect.position+Vector2(2,7)])
	for index: int in corners.size():
		var next := corners[(index+1)%corners.size()]
		RenderingServer.canvas_item_add_line(canvas_item,corners[index],next,Color("765935")*tint,3.0,true)
		RenderingServer.canvas_item_add_line(canvas_item,corners[index],next,edge*tint,1.4,true)
	for point: Vector2 in [rect.position+Vector2(1,1),Vector2(rect.end.x-9,rect.position.y+1),rect.end-Vector2(9,9),Vector2(rect.position.x+1,rect.end.y-9)]:
		atlas.draw_rect_region(canvas_item,Rect2(point,Vector2(8,8)),Rect2(488,54,52,52),tint,false,true)
	if selected:
		# A small raised corner jewel marks selection without covering item text.
		var point := Vector2(rect.end.x-6,rect.position.y+6)
		RenderingServer.canvas_item_add_circle(canvas_item,point,3.5,Color("ffe5a1"))
		RenderingServer.canvas_item_add_circle(canvas_item,point,2.3,Color("257f83"))
