extends Button
## Illustrated camp navigation. Text stays in Labels so translated titles fit
## without being baked into the artwork or drawn twice by the native Button.

const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const ArtLibrary = preload("res://scripts/ui/storybook_art.gd")
const ICON_IDS := ["hero", "skills", "equipment", "shop", "compass", "axe_slash"]
const INK := Color("392843")
const MUTED := Color("806f79")
const BRASS := Color("ba9258")
const PAPER := Color("fff2cf")
const PAPER_LIGHT := Color("fff9e8")
const DEEP_TEAL := Color("245d61")

var heading := ""
var description := ""
var artwork_index := 0
var accent_color := Color("257f83")
var is_prominent := false
var artwork: Texture2D
var paper_artwork: Texture2D
var title_label: Label
var subtitle_label: Label

func _init() -> void:
	text = ""
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(40, 40)
	# The entire silhouette is drawn below, including its focus treatment.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _ready() -> void:
	_ensure_labels()
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(_refresh)
	button_up.connect(_refresh)
	resized.connect(_refresh)
	_load_artwork()
	_refresh()

func configure(title: String, subtitle: String, icon_index: int, accent: Color, prominent: bool = false) -> void:
	heading = title
	description = subtitle
	artwork_index = clampi(icon_index, 0, 5)
	accent_color = accent
	is_prominent = prominent
	text = ""
	tooltip_text = title if subtitle.is_empty() else title + " · " + subtitle
	# The camp lays out standard, departure and compact trial cards itself.
	# A small floor keeps this Button usable without overriding those extents.
	custom_minimum_size = Vector2(40, 40)
	_ensure_labels()
	title_label.text = heading
	subtitle_label.text = description
	_load_artwork()
	_refresh()

func _ensure_labels() -> void:
	if title_label != null:
		return
	title_label = Label.new()
	title_label.name = "Title"
	subtitle_label = Label.new()
	subtitle_label.name = "Subtitle"
	for label in [title_label, subtitle_label]:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		add_child(label)
	title_label.text = heading
	subtitle_label.text = description

func _load_artwork() -> void:
	paper_artwork = TextureSampler.sampled("res://assets/generated/ui/storybook_parchment_v1.png")
	artwork = ArtLibrary.texture(ICON_IDS[artwork_index])

func _is_compact() -> bool:
	return not is_prominent and description.is_empty() and size.y < 64.0

func _refresh() -> void:
	if title_label != null:
		_layout_labels()
	queue_redraw()

func _layout_labels() -> void:
	var compact := _is_compact()
	var text_left := 55.0 if compact else (81.0 if is_prominent else 106.0)
	var text_right := 25.0
	var available := maxf(0.0, size.x - text_left - text_right)
	var title_size := 16 if compact else (24 if is_prominent else 22)
	var subtitle_size := 12 if is_prominent else 13
	var has_description := not description.is_empty()
	var title_top := (size.y - 50.0) * 0.5 - 2.0 if is_prominent else (size.y - 57.0) * 0.5
	var title_height := 23.0 if compact else (31.0 if is_prominent else 32.0)
	if not has_description:
		title_top = (size.y - title_height) * 0.5 - 2.0
	title_label.position = Vector2(text_left, title_top)
	title_label.size = Vector2(available, title_height)
	title_label.add_theme_font_size_override("font_size", title_size)
	var title_ink := PAPER_LIGHT if is_prominent else INK
	title_label.add_theme_color_override("font_color", Color(title_ink, 0.52) if disabled else title_ink)
	subtitle_label.visible = has_description
	subtitle_label.position = Vector2(text_left, title_top + (29.0 if is_prominent else 33.0))
	subtitle_label.size = Vector2(available, 19.0 if is_prominent else 22.0)
	subtitle_label.add_theme_font_size_override("font_size", subtitle_size)
	var subtitle_ink := Color("d6e4d8") if is_prominent else MUTED
	subtitle_label.add_theme_color_override("font_color", Color(subtitle_ink, 0.6) if disabled else subtitle_ink)

func _card_polygon(at: Vector2, extent: Vector2, bevel: float) -> PackedVector2Array:
	return PackedVector2Array([
		at + Vector2(bevel, 0),
		at + Vector2(extent.x - bevel * 0.55, 0),
		at + Vector2(extent.x, bevel * 0.55),
		at + Vector2(extent.x, extent.y - bevel),
		at + Vector2(extent.x - bevel, extent.y),
		at + Vector2(bevel * 0.45, extent.y),
		at + Vector2(0, extent.y - bevel * 0.45),
		at + Vector2(0, bevel),
	])

func _outline(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _draw() -> void:
	if size.x < 32.0 or size.y < 24.0:
		return
	var active := (is_hovered() or has_focus()) and not disabled
	var depressed := is_pressed() and not disabled
	var offset := Vector2(0, 1) if depressed else Vector2.ZERO
	var origin := Vector2(4, 3) + offset
	var extent := size - Vector2(8, 10)
	var bevel := 7.0 if _is_compact() else (9.0 if is_prominent else 12.0)
	var silhouette := _card_polygon(origin, extent, bevel)
	# Two quiet shadows let the cut paper sit over the painted camp scene.
	draw_colored_polygon(_card_polygon(origin + Vector2(0, 5), extent, bevel), Color(INK, 0.035))
	draw_colored_polygon(_card_polygon(origin + Vector2(0, 3), extent, bevel), Color(INK, 0.11 if active else 0.075))
	var paper_tint := DEEP_TEAL.lerp(accent_color, 0.1) if is_prominent else PAPER.lerp(accent_color, 0.018)
	if active:
		paper_tint = paper_tint.lightened(0.07) if is_prominent else paper_tint.lerp(PAPER_LIGHT, 0.65)
	if depressed and is_prominent:
		paper_tint = paper_tint.darkened(0.06)
	if disabled:
		paper_tint = paper_tint.lerp(Color("e9ddc6"), 0.55)
	draw_colored_polygon(silhouette, paper_tint)
	if paper_artwork != null:
		# Sample the unframed interior of the painted parchment and clip it to
		# this card's silhouette, retaining paper grain at every card proportion.
		var paper_uvs := PackedVector2Array()
		for point in silhouette:
			var relative := (point - origin) / extent
			paper_uvs.append(Vector2(0.04, 0.08) + relative * Vector2(0.92, 0.84))
		var paper_wash := Color(0.47, 0.7, 0.63, 0.12) if is_prominent else Color(1, 1, 1, 0.5)
		draw_polygon(silhouette, PackedColorArray([paper_wash]), paper_uvs, paper_artwork)
	# The broad light wash and small turned corner give paper a layered finish.
	var light_points := PackedVector2Array([
		origin + Vector2(bevel, 1), origin + Vector2(extent.x - bevel * 0.55, 1),
		origin + Vector2(extent.x - 1, bevel * 0.55), origin + Vector2(extent.x - 1, extent.y * 0.28),
		origin + Vector2(1, extent.y * 0.54), origin + Vector2(1, bevel),
	])
	draw_colored_polygon(light_points, Color("94c4ae", 0.12) if is_prominent else Color(PAPER_LIGHT, 0.6))
	var corner := PackedVector2Array([
		origin + Vector2(extent.x - bevel, extent.y),
		origin + Vector2(extent.x - bevel, extent.y - bevel),
		origin + Vector2(extent.x, extent.y - bevel),
	])
	draw_colored_polygon(corner, Color("c8a469") if is_prominent else Color("dbbf8c"))
	_outline(silhouette, Color(BRASS, 1.0 if is_prominent else (0.86 if active else 0.63)), 1.8 if is_prominent else 1.2)
	var inset := _card_polygon(origin + Vector2(3, 3), extent - Vector2(6, 6), maxf(5.0, bevel - 2.0))
	_outline(inset, Color("c2ddc1", 0.28) if is_prominent else Color(PAPER_LIGHT, 0.78), 1.0)
	# A small enamel ribbon belongs to the card rather than framing every edge.
	var ribbon_width := 36.0 if is_prominent else 45.0
	var ribbon_at := origin + Vector2(extent.x - ribbon_width - 19.0, 0)
	draw_colored_polygon(PackedVector2Array([
		ribbon_at, ribbon_at + Vector2(ribbon_width, 0),
		ribbon_at + Vector2(ribbon_width - 5, 7), ribbon_at + Vector2(4, 7),
	]), Color("e0c385", 0.9) if is_prominent else Color(accent_color, 0.8 if active else 0.6))
	draw_line(origin + Vector2(15, extent.y - 7), origin + Vector2(extent.x - 28, extent.y - 7), Color(BRASS, 0.38 if is_prominent else 0.16), 1.0, true)
	_draw_artwork(offset)
	if active:
		# Clear keyboard focus uses corner brackets, keeping the illustration open.
		var focus_ink := Color("f2d696") if is_prominent else Color(accent_color, 0.95)
		draw_polyline(PackedVector2Array([origin + Vector2(2, 23), origin + Vector2(2, bevel), origin + Vector2(bevel, 2), origin + Vector2(25, 2)]), focus_ink, 2.0, true)
		draw_polyline(PackedVector2Array([origin + Vector2(extent.x - 25, extent.y - 2), origin + Vector2(extent.x - bevel, extent.y - 2), origin + Vector2(extent.x - 2, extent.y - bevel), origin + Vector2(extent.x - 2, extent.y - 23)]), focus_ink, 2.0, true)

func _draw_artwork(offset: Vector2) -> void:
	if artwork == null:
		return
	var source_size := artwork.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var edge := 36.0 if _is_compact() else (58.0 if is_prominent else 76.0)
	var left := 9.0 if _is_compact() else 14.0
	var area := Rect2(Vector2(left, (size.y - edge) * 0.5 - 2.0) + offset, Vector2.ONE * edge)
	var fit := minf(area.size.x / source_size.x, area.size.y / source_size.y)
	var fitted := source_size * fit
	var target := Rect2(area.position + (area.size - fitted) * 0.5, fitted)
	draw_texture_rect(artwork, target, false, Color(1, 1, 1, 0.5 if disabled else 1.0))
