class_name MineStyle
extends RefCounted

## Sunlit expedition journal: warm paper, plum ink, teal enamel and copper.
const BG := Color("f5ecd6")
const PANEL := Color("fff3d7")
const RAISED := Color("fff9ea")
const PAPER := PANEL
const PAPER_LIGHT := RAISED
const INK := Color("392843")
const MUTED := Color("766474")
const AMBER := Color("a66a2e")
const CYAN := Color("257f83")
const RED := Color("e6664f")
const GREEN := Color("4b8554")
const COPPER := Color("c49b60")
const TRACK := Color("cbb89e")
static var parchment_texture: Texture2D
const ButtonSkin := preload("res://scripts/ui/button_skin.gd")

static func box(color: Color, border: Color = COPPER, width: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(8)
	b.corner_detail = 6
	b.shadow_color = Color(0.24,0.16,0.22,0.13)
	b.shadow_size = 3 if color.a > 0.9 else 0
	b.shadow_offset = Vector2(0,2)
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b

static func make_theme() -> Theme:
	var result := Theme.new()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
		result.set_font("font","Label",font)
		result.set_font("font","Button",font)
		result.default_font = font
	else:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
		result.default_font = system_font
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("default_color", "RichTextLabel", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_focus_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", Color("9c8b91"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		result.set_stylebox(state,"Button",ButtonSkin.create("secondary",state))
	result.set_stylebox("panel", "Panel", paper_box())
	result.set_stylebox("panel", "PanelContainer", paper_box())
	result.set_stylebox("panel", "TooltipPanel", paper_box())
	for state in ["normal","hover","pressed","disabled","focus"]:
		result.set_stylebox(state,"OptionButton",ButtonSkin.create("selector",state))
	result.set_color("font_color", "OptionButton", INK)
	result.set_color("font_hover_color", "OptionButton", CYAN)
	result.set_color("font_pressed_color", "OptionButton", INK)
	result.set_color("font_disabled_color", "OptionButton", MUTED)
	result.set_stylebox("panel", "PopupMenu", paper_box())
	result.set_stylebox("hover", "PopupMenu", box(RAISED,CYAN,0))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", CYAN)
	result.set_color("font_disabled_color", "PopupMenu", MUTED)
	result.set_stylebox("slider", "HSlider", rail_box(TRACK))
	result.set_stylebox("grabber_area", "HSlider", rail_box(CYAN))
	result.set_stylebox("grabber_area_highlight", "HSlider", rail_box(CYAN.lightened(0.15)))
	result.set_stylebox("scroll", "VScrollBar", rail_box(Color("e6d7b9")))
	result.set_stylebox("grabber", "VScrollBar", rail_box(COPPER))
	result.set_stylebox("grabber_highlight", "VScrollBar", rail_box(AMBER))
	result.set_stylebox("scroll", "HScrollBar", rail_box(Color("e6d7b9")))
	result.set_stylebox("grabber", "HScrollBar", rail_box(COPPER))
	result.set_stylebox("grabber_highlight", "HScrollBar", rail_box(AMBER))
	result.set_color("font_color", "TooltipLabel", INK)
	return result

static func paper_box() -> StyleBox:
	if parchment_texture == null and ResourceLoader.exists("res://assets/generated/ui/storybook_parchment_v1.png"):
		var source: Texture2D = load("res://assets/generated/ui/storybook_parchment_v1.png")
		var source_image := source.get_image()
		if source_image != null:
			if source_image.is_compressed() and source_image.decompress() != OK:
				return box(PANEL)
			# Keep the fine hand-painted edge at sixteen canvas pixels on any card.
			source_image.resize(512,256,Image.INTERPOLATE_LANCZOS)
			parchment_texture = ImageTexture.create_from_image(source_image)
	if parchment_texture == null:
		return box(PANEL)
	var parchment := StyleBoxTexture.new()
	parchment.texture = parchment_texture
	parchment.texture_margin_left = 16
	parchment.texture_margin_right = 16
	parchment.texture_margin_top = 16
	parchment.texture_margin_bottom = 16
	parchment.content_margin_left = 18
	parchment.content_margin_right = 18
	parchment.content_margin_top = 12
	parchment.content_margin_bottom = 12
	return parchment

static func rail_box(color: Color) -> StyleBoxFlat:
	var rail := StyleBoxFlat.new()
	rail.bg_color = color
	rail.set_corner_radius_all(3)
	rail.content_margin_left = 3
	rail.content_margin_right = 3
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	return rail

static func label(parent: Node, key: String, at: Vector2, extent: Vector2, size_px: int = 18, color: Color = INK, values: Dictionary = {}) -> Label:
	var node := Label.new()
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.set_script(load("res://scripts/ui/mine_button.gd"))
	node.text = Words.text(key)
	node.position = at
	node.size = extent
	node.custom_minimum_size = Vector2(44,44)
	button_skin(node,"card" if extent.y > 88 else "secondary")
	if key in ["START","CONFIRM_EXTRACT","CONTINUE","CONFIRM_NEW","RESUME"]:
		primary(node)
	elif key in ["BACK","CANCEL","MAIN_MENU","RETURN_CAMP"]:
		button_skin(node,"back")
	elif key in ["QUIT","ABANDON","CONFIRM_ABANDON"]:
		button_skin(node,"danger")
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

static func primary(node: Button, accent: Color = CYAN) -> void:
	button_skin(node,"danger" if accent.is_equal_approx(RED) else "primary")

static func selected(node: Button, kind: String = "tab") -> void:
	button_skin(node,{"card":"selected_card","socket":"selected_socket"}.get(kind,kind))

static func button_skin(node: Button, kind: String = "secondary") -> void:
	var pale_text := kind in ["primary","danger","tab"]
	for state in ["normal","hover","pressed","disabled","focus"]:
		var skin: StyleBox = ButtonSkin.create(kind,state)
		if node.size.x < 100:
			skin.content_margin_left = 6
			skin.content_margin_right = 6
		if kind in ["card","selected_card"]:
			# Rich cards position child labels/icons themselves. The illustrated trim
			# must not silently add 64 px to their minimum height.
			skin.content_margin_left = 12
			skin.content_margin_right = 12
			skin.content_margin_top = 8
			skin.content_margin_bottom = 8
		elif kind in ["socket","selected_socket"]:
			skin.set_content_margin_all(4)
		node.add_theme_stylebox_override(state,skin)
	for property in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		node.add_theme_color_override(property,PAPER_LIGHT if pale_text else INK)
	node.add_theme_color_override("font_disabled_color",Color("d3c6af") if pale_text else Color("827782"))

static func panel(parent: Node, at: Vector2, extent: Vector2) -> Panel:
	var node := Panel.new()
	node.set_script(load("res://scripts/ui/metal_panel.gd"))
	node.position = at
	node.size = extent
	parent.add_child(node)
	return node

## Content names live beside game data; UI chrome lives in Words.
static func content_text(data: Dictionary, field: String, fallback: String = "") -> String:
	var value: Variant = data.get(field, fallback)
	if value is Dictionary:
		return str(value.get(Words.locale, value.get("en", fallback)))
	if Words.locale == "en":
		return str(data.get(field+"_en",value))
	return str(value)

static func literal(parent: Node, text_value: String, at: Vector2, extent: Vector2, size_px: int = 18, color: Color = INK) -> Label:
	var node := label(parent,"",at,extent,size_px,color)
	node.text = text_value
	return node

static func resource_color(kind: String) -> Color:
	return {"rage":Color("b57835"),"energy":Color("2c8da1"),"mana":Color("8860b7")}.get(kind,CYAN)

static func hero_portrait(parent: Node, id: String, at: Vector2, extent: Vector2) -> Control:
	var portrait := Control.new()
	portrait.set_script(load("res://scripts/ui/hero_portrait.gd"))
	portrait.position = at
	portrait.size = extent
	parent.add_child(portrait)
	portrait.set_hero(id,ContentRegistry.hero(id))
	return portrait

static func equipment_icon(parent: Node, data: Dictionary, at: Vector2, extent: Vector2) -> Control:
	var icon := Control.new()
	icon.set_script(load("res://scripts/ui/equipment_icon.gd"))
	icon.position = at
	icon.size = extent
	parent.add_child(icon)
	icon.set_equipment(data)
	return icon

static func meter(parent: Node, at: Vector2, extent: Vector2, accent: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = at
	bar.size = extent
	bar.show_percentage = false
	bar.add_theme_font_size_override("font_size",1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = TRACK
	background.border_color = Color("ad9170")
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background",background)
	bar.add_theme_stylebox_override("fill",fill)
	parent.add_child(bar)
	bar.size = extent
	return bar
