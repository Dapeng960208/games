class_name MineArt
extends RefCounted

const TextureSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")

static func texture(path: String) -> Texture2D:
	return TextureSampler.sampled(path)

static func relic(parent: Node, id: String, at: Vector2, extent: Vector2, found: bool = true) -> TextureRect:
	var art := TextureRect.new()
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.texture = texture(ClassRelics.art_path(id))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = at
	art.size = extent
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color.WHITE if found else Color(0.38,0.43,0.46,0.55)
	parent.add_child(art)
	return art
