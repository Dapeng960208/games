extends RefCounted
## Render-only mip chains keep detailed original PNGs readable in small UI cells.
## No source file is changed; all consumers share one sampled texture per path.

static var textures: Dictionary = {}

static func sampled(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path] as Texture2D
	var source_texture: Texture2D
	var artwork: Image
	if FileAccess.file_exists(path+".import") or (not FileAccess.file_exists(path) and ResourceLoader.exists(path)):
		var status := ResourceLoader.load_threaded_get_status(path)
		source_texture = ResourceLoader.load_threaded_get(path) as Texture2D if status == ResourceLoader.THREAD_LOAD_LOADED else load(path) as Texture2D
		if source_texture != null:
			# These authored atlases import with mipmaps. Keep their native texture
			# instead of decoding/readback and uploading a duplicate on first open.
			if path.begins_with("res://assets/generated/equipment/storybook_"):
				textures[path] = source_texture
				return source_texture
			artwork = source_texture.get_image()
	# Newly generated images can be previewed before the editor imports them.
	if (artwork == null or artwork.is_empty()) and FileAccess.file_exists(path):
		artwork = Image.load_from_file(path)
	if artwork == null or artwork.is_empty():
		return null
	if artwork.is_compressed() and artwork.decompress() != OK:
		if source_texture != null:
			textures[path] = source_texture
		return source_texture
	if not artwork.has_mipmaps():
		artwork.generate_mipmaps()
	var result := ImageTexture.create_from_image(artwork)
	textures[path] = result
	return result
