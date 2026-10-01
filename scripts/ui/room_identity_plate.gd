class_name RoomIdentityPlate
extends Button
## The seal identifies the authored room; the miniature follows its real
## runtime routes. It never adds destinations or advances objective state.
const Presentation = preload("res://scripts/world/room_presentation.gd")
const Motif = preload("res://scripts/world/room_motif.gd")
const Art = preload("res://scripts/world/world_art.gd")
const Boundary = preload("res://scripts/world/room_boundary.gd")
const INK := Color("392843")
const BRASS := Color("a66a2e")
const PAPER := Color("fff3d7")

var layout: Dictionary = {}
var design: Dictionary = {}
var accent := Color("398f96")
var player_position := Vector2.ZERO
var has_player := false
var last_map_player_position := Vector2(-1000,-1000)
var room_title: Label
var room_caption: Label
var identity_signature := ""
var ground_polygon := PackedVector2Array()
var map_bounds := Rect2(0,0,1624,1044)
var seal_text := ""
var seal_font_size := 9
var seal_text_rect := Rect2()

func _ready() -> void:
	name = "RoomIdentityPlate"
	custom_minimum_size = Vector2(190,58)
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text = ""
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	room_title = Label.new()
	room_title.name = "RoomIdentityTitle"
	room_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	room_title.add_theme_color_override("font_color",INK)
	room_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(room_title)
	room_caption = Label.new()
	room_caption.name = "RoomPurpose"
	room_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	room_caption.add_theme_color_override("font_color",Color("766474"))
	room_caption.add_theme_font_size_override("font_size",12)
	room_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_caption.max_lines_visible = 2
	room_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(room_caption)
	resized.connect(_layout_text)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_layout_text()

func configure(next_layout: Dictionary, title: String) -> void:
	layout = next_layout
	var signature := str(layout.get("blueprint_room_id",layout.get("room_id","")))+":"+Words.locale+":"+title
	if signature == identity_signature: return
	identity_signature = signature
	design = Presentation.for_layout(layout)
	accent = Presentation.accent(str(layout.get("biome_id","")))
	var arena: Rect2 = layout.get("arena",Rect2(0,0,1624,1044))
	ground_polygon = Art.environment_ground_polygon(arena,str(layout.get("biome_id","")),Art.environment_room_id(layout))
	map_bounds = Boundary.bounds(ground_polygon) if ground_polygon.size() >= 3 else arena
	room_title.text = title
	room_caption.text = Presentation.local_caption(design,Words.locale == "en")
	room_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if Words.locale == "en" else TextServer.AUTOWRAP_ARBITRARY
	_layout_text()
	queue_redraw()

func update_player(at: Vector2, available: bool) -> void:
	var map_position := _map_point(at)
	var changed := has_player != available or map_position.distance_squared_to(last_map_player_position) > .09
	player_position = at
	has_player = available
	if changed:
		last_map_player_position = map_position
		queue_redraw()

func _layout_text() -> void:
	if room_title == null: return
	var text_width := maxf(72,(_map_rect().position.x if size.x >= 300 else size.x-8)-61)
	room_title.position = Vector2(53,3)
	room_title.size = Vector2(text_width,22)
	var font := room_title.get_theme_font("font")
	var font_size := 15
	while font_size > 12 and font.get_string_size(room_title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > text_width:
		font_size -= 1
	room_title.add_theme_font_size_override("font_size",font_size)
	room_caption.position = Vector2(53,26)
	room_caption.size = Vector2(text_width,30)
	queue_redraw()

func _map_rect() -> Rect2:
	return Rect2(size.x-98,7,90,44)

func _map_point(at: Vector2) -> Vector2:
	var paper := _map_rect().grow(-4)
	var scale_factor := minf(paper.size.x/maxf(1,map_bounds.size.x),paper.size.y/maxf(1,map_bounds.size.y))
	var extent := map_bounds.size*scale_factor
	return paper.get_center()-extent*.5+(at-map_bounds.position)*scale_factor

static func draw_emblem(canvas: CanvasItem, key: String, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_circle(center+Vector2(0,1),radius,Color("b99b69"))
	canvas.draw_circle(center,radius-1,PAPER)
	canvas.draw_arc(center,radius-1,-PI*.95,-PI*.08,32,Color("ffe1a0"),1.3,true)
	canvas.draw_arc(center,radius-2,0,TAU,40,Color(color,.65),.9,true)
	# A fine engraved symbol gains a one-pixel ink edge at HUD scale. This
	# retains the exact same silhouette as the large world-floor inlay.
	for offset: Vector2 in [Vector2.ZERO,Vector2(-.3,0),Vector2(.3,0),Vector2(0,-.3),Vector2(0,.3)]:
		canvas.draw_set_transform(center+offset,0,Vector2.ONE*(radius*.74))
		Motif.draw(canvas,key,color,BRASS)
	canvas.draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	var paper := MineStyle.paper_box()
	paper.set_content_margin_all(0)
	draw_style_box(paper,Rect2(0,1,size.x,size.y-2))
	draw_line(Vector2(50,9),Vector2(50,size.y-8),Color(accent,.25),1,true)
	draw_emblem(self,str(design.get("emblem","sunburst")),Vector2(26,24),20,accent)
	var chapter := int(design.get("chapter",0))
	var code := str(layout.get("blueprint_room_id",layout.get("room_id","")))
	var font := get_theme_font("font","Button")
	seal_text = "%02d·%s" % [chapter,code] if chapter > 0 else code
	seal_font_size = 9
	var seal_width := font.get_string_size(seal_text,HORIZONTAL_ALIGNMENT_LEFT,-1,seal_font_size).x
	if seal_width > 44:
		seal_font_size = 8
		seal_width = font.get_string_size(seal_text,HORIZONTAL_ALIGNMENT_LEFT,-1,seal_font_size).x
	seal_text_rect = Rect2(26-seal_width*.5,53-font.get_ascent(seal_font_size),seal_width,font.get_height(seal_font_size))
	draw_string(font,Vector2(seal_text_rect.position.x,53),seal_text,HORIZONTAL_ALIGNMENT_LEFT,-1,seal_font_size,INK)
	_draw_map()
	if has_focus() or is_hovered():
		draw_style_box(MineStyle.box(Color.TRANSPARENT,Color(accent,.70),1),Rect2(1,2,size.x-2,size.y-4))

func _draw_map() -> void:
	if size.x < 300: return
	var map := _map_rect()
	draw_style_box(MineStyle.box(Color("f0e6ca"),Color("bcaa85"),1),map)
	if layout.is_empty(): return
	if ground_polygon.size() >= 3:
		var outline := PackedVector2Array()
		for at: Vector2 in ground_polygon: outline.append(_map_point(at))
		draw_colored_polygon(outline,Color("fff3d7"))
		outline.append(outline[0])
		draw_polyline(outline,Color(accent,.28),.8,true)
	var routes: Dictionary = layout.get("fixed_routes",layout.get("reserved_paths",{}))
	for route_key: String in ["side","main"]:
		var path := PackedVector2Array()
		for at: Vector2 in routes.get(route_key,[]): path.append(_map_point(at))
		if path.size() < 2: continue
		var color := Color(accent,.70) if route_key == "side" else BRASS
		draw_polyline(path,color,1.0 if route_key == "side" else 1.8,true)
	for at: Vector2 in layout.get("objective_points",[]):
		var point := _map_point(at)
		draw_colored_polygon(PackedVector2Array([point+Vector2(0,-2.6),point+Vector2(2.6,0),point+Vector2(0,2.6),point+Vector2(-2.6,0)]),accent)
	if layout.has("entry"):
		var point := _map_point(layout.entry)
		draw_circle(point,2.4,PAPER)
		draw_arc(point,2.4,0,TAU,16,INK,1.0,true)
	if layout.has("exit"):
		var point := _map_point(layout.exit)
		draw_rect(Rect2(point-Vector2(2.5,3),Vector2(5,6)),PAPER)
		draw_rect(Rect2(point-Vector2(2.5,3),Vector2(5,6)),BRASS,false,1.0)
	if has_player:
		var point := _map_point(player_position)
		draw_circle(point,3.3,PAPER)
		draw_circle(point,2.3,INK)
