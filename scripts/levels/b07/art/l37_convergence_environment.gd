extends "res://scripts/levels/b07/art/room_environment.gd"
## Opt-in source assembly only. Inherits the existing candidate's floor,
## finite foundation, guardian and painted bounds without changing their WIP.
## The north-follow camera is the existing --b07-midground-trial camera.
const REVIEW_FLAG := "--b07-convergence-review"
const SHARED := "asset://levels/b07/rooms/shared/"
var review_components: Array[Sprite2D] = []
var review_ready := false

static func requested() -> bool:
	var args := OS.get_cmdline_user_args()
	return REVIEW_FLAG in args and "--b07-art-trial" in args and "--b07-midground-trial" in args

func configure(layout: Dictionary) -> bool:
	if not requested(): return false
	if not super.configure(layout):
		push_warning("L37 review base configuration rejected")
		return false
	# The inherited RGB crop is preserved for the old trial, never shown here.
	for layer: Sprite2D in layers:
		if layer.name == "NorthCityCompositionReview": layer.hide()
	# Rooted sources include actual authored cliff support. Only the rock roots
	# can pass behind the fixed terrace; its original floor remains foreground.
	if not _rooted_component("terraced_city_rooted",Rect2(6,9,1133,1353),Vector2(-400,-230),860,"WestTerracedCity"): return false
	if not _rooted_component("terraced_city_rooted",Rect2(6,9,1133,1353),Vector2(1120,-230),860,"EastTerracedCity"): return false
	if not _rooted_component("bridge_rooted",Rect2(36,11,1473,1000),Vector2(-790,170),870,"LowerExteriorBridge"): return false
	if not _rooted_component("sun_mirror_rooted",Rect2(239,7,764,1277),Vector2(730,-195),240,"IndependentSunLandmark"): return false
	review_ready = true
	return true

func _rooted_component(id: String, region: Rect2, top_left: Vector2, width: float, title: String) -> bool:
	var path := "asset://levels/b07/rooms/l37/"+id+"/source_candidate.png"
	var texture := Sampler.load_mip_texture(path)
	if texture == null or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return false
	var factor := width/region.size.x
	var size := region.size*factor
	var sprite := Sprite2D.new()
	sprite.name = title
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.region_filter_clip_enabled = true
	sprite.position = top_left*Geometry.SCALE
	sprite.scale = Vector2.ONE*factor*Geometry.SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.z_index = 1
	var mask := ShaderMaterial.new()
	mask.shader = Clip
	var polygon_uniform := source_polygon.duplicate()
	polygon_uniform.resize(16)
	var full := texture.get_size()
	mask.set_shader_parameter("source_region_uv",Vector4(region.position.x/full.x,region.position.y/full.y,region.size.x/full.x,region.size.y/full.y))
	mask.set_shader_parameter("ground",polygon_uniform)
	mask.set_shader_parameter("ground_count",source_polygon.size())
	mask.set_shader_parameter("scaled_blueprint_size",size)
	mask.set_shader_parameter("blueprint_crop",Vector2.ZERO)
	mask.set_shader_parameter("blueprint_origin",top_left)
	mask.set_shader_parameter("draw_area_size",size)
	mask.set_shader_parameter("exterior",true)
	sprite.material = mask
	add_child(sprite)
	review_components.append(sprite)
	return true
