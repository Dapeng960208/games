extends Button

func _ready() -> void:
	# Button's native theme state owns the art and focus treatment. Keeping that
	# path also preserves keyboard, pointer, press/release and disabled behavior.
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
