extends RefCounted
## Render-only mip chains keep detailed original PNGs readable in small UI cells.
## No source file is changed; all consumers share one sampled texture per path.

static var textures: Dictionary = {}

static func visible_region(source: Image) -> Rect2:
	# Alpha speckles below the established threshold do not inflate actor bounds.
	# Read source pixels only; resource cleanup never changes the source artwork.
	var rgba: Image = source
	if source.get_format() != Image.FORMAT_RGBA8:
		rgba = source.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = rgba.get_data()
	var width: int = rgba.get_width()
	var minimum := Vector2i(width,rgba.get_height())
	var maximum := Vector2i(-1,-1)
	for y in rgba.get_height():
		for x in width:
			if bytes[(y*width+x)*4+3] > 16:
				minimum = minimum.min(Vector2i(x,y))
				maximum = maximum.max(Vector2i(x,y))
	return Rect2(Vector2(minimum),Vector2(maximum-minimum+Vector2i.ONE)) if maximum.x >= 0 else Rect2()

static func sampled(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path] as Texture2D
	var source_texture: Texture2D
	var artwork: Image
	if FileAccess.file_exists(AssetCatalog.resolve(path+".import")) or (not FileAccess.file_exists(AssetCatalog.resolve(path)) and ResourceLoader.exists(AssetCatalog.resolve(path))):
		var status := ResourceLoader.load_threaded_get_status(AssetCatalog.resolve(path))
		source_texture = ResourceLoader.load_threaded_get(AssetCatalog.resolve(path)) as Texture2D if status == ResourceLoader.THREAD_LOAD_LOADED else load(AssetCatalog.resolve(path)) as Texture2D
		if source_texture != null:
			# These authored atlases import with mipmaps. Keep their native texture
			# instead of decoding/readback and uploading a duplicate on first open.
			if path.begins_with("asset://equipment/storybook_"):
				textures[path] = source_texture
				return source_texture
			artwork = source_texture.get_image()
	# Newly generated images can be previewed before the editor imports them.
	if (artwork == null or artwork.is_empty()) and FileAccess.file_exists(AssetCatalog.resolve(path)):
		artwork = Image.load_from_file(AssetCatalog.resolve(path))
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
