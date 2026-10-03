extends RefCounted
## Resolution-independent ivory / enamel controls; labels always remain live.
## State treatment is intentionally restrained so equipment artwork is primary.
static func create(kind: String = "secondary", state: String = "normal") -> StyleBox:
	var skin := StyleBoxFlat.new()
	var selected := kind in ["tab", "selected_card", "selected_socket", "nav_active"]
	var filled := kind in ["primary", "tab"]
	var nav := kind in ["nav", "nav_active"]
	var accent := Color("b65c4d") if kind == "danger" else Color("258b87")
	var background := accent if filled else Color("fffdf7")
	if kind == "danger": background = Color("fcf0e8")
	if kind in ["card", "socket"]: background = Color("faf8f1")
	if selected and not filled: background = Color("edf4eb")
	if nav: background = Color.TRANSPARENT
	var border := accent if selected or filled else Color("dcd3c1")
	if state == "hover":
		background = accent.lightened(0.10) if filled else Color("f1f3e9")
		border = accent
	elif state == "pressed":
		background = accent.darkened(0.10) if filled else Color("e2eeE4")
		border = accent
	elif state == "disabled":
		background = Color("e7e4da") if filled else Color("f3f0e8")
		border = Color("e1dacd")
	skin.bg_color = background
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(8 if kind in ["card","selected_card","socket","selected_socket"] else 18)
	if nav:
		skin.set_border_width_all(0)
		skin.border_width_bottom = 2 if selected else 0
		skin.set_corner_radius_all(0)
	if state == "focus":
		skin.bg_color = Color.TRANSPARENT
		skin.border_color = Color("258b87")
		skin.set_border_width_all(2)
		skin.expand_margin_left = 2
		skin.expand_margin_top = 2
		skin.expand_margin_right = 2
		skin.expand_margin_bottom = 2
	skin.content_margin_left = 16
	skin.content_margin_right = 16
	skin.content_margin_top = 7
	skin.content_margin_bottom = 7
	return skin
