class_name StorybookArt
extends RefCounted
## Dedicated painted UI parts. Region manifests measure the original atlas;
## no concept screenshot is cropped or stretched into a control.

const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const SOURCES := [
	"res://assets/generated/ui/storybook_navigation_v2.regions.json",
	"res://assets/generated/ui/storybook_chrome_v2.regions.json",
	"res://assets/generated/ui/storybook_abilities_v2.regions.json"
]
static var _manifests: Dictionary = {}
static var _textures: Dictionary = {}

static func _manifest(path: String) -> Dictionary:
	if _manifests.has(path): return _manifests[path]
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or not value.get("regions") is Dictionary: return {}
	_manifests[path] = value
	return value

static func texture(id: String) -> Texture2D:
	if _textures.has(id): return _textures[id]
	for path: String in SOURCES:
		var manifest: Dictionary = _manifest(path)
		var regions: Dictionary = manifest.get("regions",{})
		if not regions.has(id): continue
		var raw: Variant = regions[id]
		if raw is Dictionary: raw = raw.get("region",[])
		if not raw is Array or raw.size() != 4: return null
		var atlas: Texture2D = Sampler.sampled(str(manifest.get("texture","")))
		if atlas == null: return null
		var region := Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
		if not region.has_area() or not Rect2(Vector2.ZERO,atlas.get_size()).encloses(region): return null
		var result := AtlasTexture.new()
		result.atlas = atlas
		result.region = region
		result.filter_clip = true
		_textures[id] = result
		return result
	return null

static func paper_box(id: String, destination_margin: float = 12.0) -> StyleBoxTexture:
	var artwork: Texture2D = texture(id)
	if artwork == null: return null
	var box := StyleBoxTexture.new()
	box.texture = artwork
	var source_margin := minf(artwork.get_height() * .16, artwork.get_width() * .07)
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		box.set_texture_margin(edge,source_margin)
		box.set_expand_margin(edge,0)
		box.set_content_margin(edge,destination_margin)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box
