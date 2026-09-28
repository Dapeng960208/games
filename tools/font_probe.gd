extends SceneTree
func _initialize() -> void:
	var font := load("res://assets/fonts/NotoSansSC.ttf") as FontFile
	print("AXES ", font.get_supported_variation_list())
	print("THEME_FONT ",MineStyle.make_theme().default_font)
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	print("WEIGHT_TAG ",tag)
	quit()
