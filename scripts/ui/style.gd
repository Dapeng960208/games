class_name MineStyle
extends RefCounted

const BG := Color("0d131a")
const PANEL := Color("17232c")
const RAISED := Color("20333d")
const INK := Color("f1eadc")
const MUTED := Color("b2bbc4")
const AMBER := Color("e6aa4a")
const CYAN := Color("67c7d5")
const RED := Color("e46b69")
const GREEN := Color("80b69a")
const COPPER := Color("826345")

static func box(color: Color, border: Color = COPPER, width: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.border_color = border
	b.set_border_width_all(width)
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 12
	b.content_margin_bottom = 12
	return b

static func make_theme() -> Theme:
	var result := Theme.new()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):450.0}
		result.set_font("font","Label",font)
		result.set_font("font","Button",font)
		result.default_font = font
	else:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
		result.default_font = system_font
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", AMBER)
	result.set_color("font_pressed_color", "Button", BG)
	result.set_color("font_focus_color", "Button", AMBER)
	result.set_color("font_disabled_color", "Button", Color("67717a"))
	result.set_stylebox("normal", "Button", box(PANEL))
	result.set_stylebox("hover", "Button", box(RAISED, AMBER))
	result.set_stylebox("pressed", "Button", box(AMBER, AMBER))
	result.set_stylebox("disabled", "Button", box(Color("141d24"), Color("354047")))
	result.set_stylebox("focus", "Button", box(Color(0,0,0,0), CYAN, 2))
	result.set_stylebox("panel", "Panel", box(PANEL))
	result.set_stylebox("panel", "PanelContainer", box(PANEL))
	result.set_stylebox("panel", "TooltipPanel", box(PANEL,CYAN))
	result.set_color("font_color", "TooltipLabel", INK)
	return result

static func label(parent: Node, key: String, at: Vector2, extent: Vector2, size_px: int = 18, color: Color = INK, values: Dictionary = {}) -> Label:
	var node := Label.new()
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.text = Words.text(key, values)
	node.add_theme_font_size_override("font_size", size_px)
	node.add_theme_color_override("font_color", color)
	node.position = at
	node.size = extent
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func button(parent: Node, key: String, at: Vector2, extent: Vector2, callback: Callable) -> Button:
	var node := Button.new()
	node.set_script(load("res://scripts/ui/mine_button.gd"))
	node.text = Words.text(key)
	node.position = at
	node.size = extent
	node.custom_minimum_size = Vector2(44,44)
	if key in ["START","CONFIRM_EXTRACT","RETURN_CAMP","CONTINUE","CONFIRM_NEW","RESUME"]:
		node.add_theme_stylebox_override("normal",box(Color("342b21"),Color("b58b50")))
		node.add_theme_stylebox_override("hover",box(Color("4b3925"),AMBER))
		node.add_theme_color_override("font_color",Color("f1ca8b"))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

static func panel(parent: Node, at: Vector2, extent: Vector2) -> Panel:
	var node := Panel.new()
	node.set_script(load("res://scripts/ui/metal_panel.gd"))
	node.position = at
	node.size = extent
	parent.add_child(node)
	return node
