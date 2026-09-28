class_name MineArt
extends RefCounted

static var textures: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if not textures.has(path) and ResourceLoader.exists(path):
		textures[path] = load(path)
	return textures.get(path)

static func relic(parent: Node, id: String, at: Vector2, extent: Vector2, found: bool = true) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture("res://assets/ui/relic_"+id+".png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = at
	art.size = extent
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color.WHITE if found else Color(0.38,0.43,0.46,0.55)
	parent.add_child(art)
	return art
