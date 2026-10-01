extends Button

func _ready() -> void:
	# Button's native theme state owns the art and focus treatment. Keeping that
	# path also preserves keyboard, pointer, press/release and disabled behavior.
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAW or text.is_empty(): return
	# Update before the next native text shaping pass, not during its draw.
	_fit_caption.call_deferred()

func _fit_caption() -> void:
	if not is_inside_tree() or text.is_empty(): return
	var skin := get_theme_stylebox("normal")
	# Leave extra room for native text outlining and translated glyph bearings.
	var available := maxf(1,size.x-skin.content_margin_left-skin.content_margin_right-12)
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var widest := 0.0
	for line: String in text.split("\n"):
		widest = maxf(widest,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	while font_size > 12 and widest > available:
		font_size -= 1
		widest = 0
		for line: String in text.split("\n"):
			widest = maxf(widest,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	if font_size != get_theme_font_size("font_size"): add_theme_font_size_override("font_size",font_size)
