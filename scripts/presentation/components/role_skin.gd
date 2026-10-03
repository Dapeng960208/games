extends RefCounted
## Shared job colors; layout and gameplay state stay with their existing owners.

static func palette(hero_id: String) -> Dictionary:
	var role: Dictionary = {
		"CH01":{"accent":Color("a93b36"),"deep":Color("233b66"),"pale":Color("e0e6ef")},
		"CH02":{"accent":Color("23747e"),"deep":Color("285057"),"pale":Color("f8f3e8")},
		"CH03":{"accent":Color("345e8e"),"deep":Color("21162f"),"pale":Color("e7e9f0"),"border":Color("a8acbc"),"edge":Color("131119")}
	}.get(hero_id,{"accent":Color("258b87"),"deep":Color("344c48"),"pale":Color("e5f0eb")}).duplicate()
	role.merge({"border":Color("b99a5e"),"text":Color("30253a"),"muted":Color("796c64"),"paper":Color("fffaf0")})
	return role

static func panel(parent: Node, hero_id: String, at: Vector2, extent: Vector2) -> Panel:
	var colors := palette(hero_id)
	var result := Panel.new()
	result.position = at
	result.size = extent
	result.add_theme_stylebox_override("panel",GameStyle.box(colors.paper,colors.border,1))
	parent.add_child(result)
	var stripe := ColorRect.new()
	stripe.color = colors.get("edge",colors.accent)
	stripe.position = Vector2(1,14)
	stripe.size = Vector2(4,maxf(0,extent.y-28))
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_child(stripe)
	return result

static func button(node: Button, hero_id: String, selected: bool = false, primary: bool = false) -> void:
	var colors := palette(hero_id)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var fill: Color = colors.accent if primary else colors.pale if selected else colors.paper
		if state == "hover": fill = fill.lightened(0.08)
		if state == "pressed": fill = fill.darkened(0.05)
		if state == "disabled": fill = Color("ece6dc")
		var border: Color = colors.accent if selected or state == "focus" else colors.border
		var box := GameStyle.box(fill,border,3 if state == "focus" else 2 if selected else 1)
		box.set_content_margin_all(6)
		node.add_theme_stylebox_override(state,box)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		node.add_theme_color_override(state,colors.paper if primary else colors.text)
	node.add_theme_color_override("font_disabled_color",colors.muted)
	node.add_theme_font_size_override("font_size",18)
