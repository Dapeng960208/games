extends Node2D
## World-space text must not pass through the prop artwork's color grade.
## This child retains its host's transform/visibility and has no input or tick.
const Style = preload("res://scripts/presentation/components/style.gd")
const INK := Style.INK
const DETAIL := Color("4a6157")
const PAPER := Style.PANEL
var painter: Callable
static var _plate: StyleBoxFlat
static var _font: Font

static func font() -> Font:
	if _font == null:
		_font = ThemeDB.fallback_font
		if ResourceLoader.exists(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf")):
			# This variable font defaults to hairline weight 100. Match the
			# established HUD weight so small world glyphs have opaque strokes.
			var readable := FontVariation.new()
			readable.base_font = load(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf"))
			readable.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
			_font = readable
	return _font

func configure(host: Node2D, draw_labels: Callable) -> void:
	name = "WorldLabels"
	painter = draw_labels
	use_parent_material = false
	var ungraded := CanvasItemMaterial.new()
	ungraded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = ungraded
	host.add_child(self)
	host.draw.connect(queue_redraw)

func _draw() -> void:
	if painter.is_valid():
		painter.call(self)

static func draw_panel(canvas: CanvasItem, bounds: Rect2) -> void:
	if _plate == null:
		_plate = Style.box(PAPER, Style.COPPER, 1)
		_plate.set_corner_radius_all(4)
		_plate.shadow_size = 2
		_plate.shadow_offset = Vector2(0, 1)
	canvas.draw_style_box(_plate, bounds)

static func draw_objective(canvas: CanvasItem, font: Font, at: Vector2, text: String) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var baseline := at + Vector2(-width * .5, 44)
	var bounds := Rect2(baseline - Vector2(6, font.get_ascent(17) + 3), Vector2(width + 12, font.get_height(17) + 6))
	draw_panel(canvas, bounds)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
