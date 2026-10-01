extends Button
## Illustrated camp navigation. Text stays in Labels so translated titles fit
## without being baked into the artwork or drawn twice by the native Button.

const ArtLibrary = preload("res://scripts/ui/storybook_art.gd")
const ButtonSkin = preload("res://scripts/ui/button_skin.gd")
const ICON_IDS := ["hero", "skills", "equipment", "shop", "compass", "axe_slash"]
const INK := Color("392843")
const MUTED := Color("806f79")
const PAPER_LIGHT := Color("fff9e8")

var heading := ""
var description := ""
var artwork_index := 0
var accent_color := Color("257f83")
var is_prominent := false
var artwork: Texture2D
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

func _draw() -> void:
	if size.x < 32.0 or size.y < 24.0:
		return
	var active := (is_hovered() or has_focus()) and not disabled
	var depressed := is_pressed() and not disabled
	var state := "disabled" if disabled else ("pressed" if depressed else ("hover" if active else "normal"))
	var offset := Vector2(0, 1) if depressed else Vector2.ZERO
	var surface := Rect2(Vector2(2, 2) + offset, size - Vector2(4, 4))
	# Camp and menu navigation share the generated enamel/scroll components.
	# Their independent illustrations and live titles remain readable at each size.
	var component := "primary" if is_prominent else "secondary"
	ButtonSkin.create(component, state).draw(get_canvas_item(), surface)
	_draw_artwork(offset)
	if has_focus() and not disabled:
		ButtonSkin.create(component, "focus").draw(get_canvas_item(), surface)

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
