extends StyleBox
## Six purpose-specific painted materials. Captions are rendered by Godot.
const TEXTURE_PATH := "res://assets/generated/ui/workshop_buttons_v5.png"
const MANIFEST_PATH := "res://assets/generated/ui/workshop_buttons_v5.regions.json"
static var atlas: Texture2D
static var regions: Dictionary = {}
var kind := "secondary"
var tint := Color.WHITE
var focus_only := false

static func create(style_kind: String = "secondary", state: String = "normal") -> StyleBox:
	var result := load("res://scripts/ui/button_skin.gd").new() as StyleBox
	result.set("kind",style_kind)
	result.set("focus_only",state == "focus")
	result.set("tint",{"hover":Color(1.09,1.09,1.04),"pressed":Color(.83,.91,.91),"disabled":Color(.82,.82,.78,.84)}.get(state,Color.WHITE))
	result.content_margin_left = {"primary":37,"tab":35,"back":52,"danger":31,"secondary":25,"selector":22}.get(style_kind,14)
	result.content_margin_right = 16
	result.content_margin_top = 7
	result.content_margin_bottom = 7
	return result

static func _load_atlas() -> void:
	if regions.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary: regions = parsed.get("regions",{})
	if atlas == null:
		if ResourceLoader.exists(TEXTURE_PATH): atlas = load(TEXTURE_PATH)
		else:
			var source := Image.load_from_file(TEXTURE_PATH)
			if source != null and not source.is_empty(): atlas = ImageTexture.create_from_image(source)

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _draw(canvas_item: RID, rect: Rect2) -> void:
	_load_atlas()
	if rect.size.x <= 0 or rect.size.y <= 0: return
	if focus_only:
		_draw_focus(canvas_item,rect)
		return
	if atlas == null:
		RenderingServer.canvas_item_add_rect(canvas_item,rect,Color("fff3d7"))
		return
	var component := "card" if kind in ["socket","selected_socket","selected_card"] else "secondary" if kind == "selector" else kind
	_draw_component(canvas_item,rect,component,tint)
	if kind in ["selected_socket","selected_card"]: _draw_selection(canvas_item,rect)

func _draw_component(canvas_item: RID, rect: Rect2, component: String, color: Color) -> void:
	var data: Dictionary = regions.get(component,regions.get("secondary",{}))
	if data.is_empty(): return
	var box: Array = data.rect
	var source := Rect2(box[0],box[1],box[2],box[3])
	var caps: Array = data.caps
	var edges: Array = data.edges
	var scale := minf(rect.size.y,64.0) / source.size.y
	var left := minf(float(caps[0])*scale,rect.size.x*.24)
	var right := minf(float(caps[1])*scale,rect.size.x*.24)
	var top := minf(float(edges[0])*scale,rect.size.y*.25)
	var bottom := minf(float(edges[1])*scale,rect.size.y*.25)
	var sx := [0.0,float(caps[0]),source.size.x-float(caps[1]),source.size.x]
	var sy := [0.0,float(edges[0]),source.size.y-float(edges[1]),source.size.y]
	var dx := [0.0,left,rect.size.x-right,rect.size.x]
	var dy := [0.0,top,rect.size.y-bottom,rect.size.y]
	for row in 3:
		for column in 3:
			var part := Rect2(source.position+Vector2(sx[column],sy[row]),Vector2(sx[column+1]-sx[column],sy[row+1]-sy[row]))
			var destination := Rect2(rect.position+Vector2(dx[column],dy[row]),Vector2(dx[column+1]-dx[column],dy[row+1]-dy[row]))
			atlas.draw_rect_region(canvas_item,destination,part,color,false,true)

func _draw_focus(canvas_item: RID, rect: Rect2) -> void:
	var left := Vector2(rect.position.x+12,rect.end.y-3)
	var right := Vector2(rect.end.x-12,rect.end.y-3)
	RenderingServer.canvas_item_add_line(canvas_item,left,right,Color("257f83"),3.0,true)
	RenderingServer.canvas_item_add_line(canvas_item,left,right,Color("fff0bb"),1.0,true)

func _draw_selection(canvas_item: RID, rect: Rect2) -> void:
	var inset := rect.grow(-3)
	var corners := [inset.position,Vector2(inset.end.x,inset.position.y),inset.end,Vector2(inset.position.x,inset.end.y)]
	for i: int in 4:
		RenderingServer.canvas_item_add_line(canvas_item,corners[i],corners[(i+1)%4],Color("257f83"),2,true)
