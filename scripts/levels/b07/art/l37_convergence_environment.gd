extends "res://scripts/levels/b07/art/room_environment.gd"
## Opt-in fixed courtyard review. Retains the authored floor, guardian and
## painted bounds; oblique exterior support and floor lighting are visual only.
## The north-follow camera is the existing --b07-midground-trial camera.
const REVIEW_FLAG := "--b07-convergence-review"
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
	# Keep all independent city/bridge/sun source candidates on disk, but do
	# not show their unsupported collage in this fixed-courtyard review.
	var original_foundation := foundation
	var review_foundation := preload("res://scripts/levels/b07/art/l37_review_foundation.gd").new()
	add_child(review_foundation)
	review_foundation.z_index=1
	if not review_foundation.configure(original_foundation.texture,source_polygon):
		review_foundation.free()
		return false
	original_foundation.hide()
	foundation=review_foundation
	for layer: Sprite2D in layers:
		if layer.name != "WalkableTerrace": continue
		var original := layer.material as ShaderMaterial
		var shaded := ShaderMaterial.new()
		shaded.shader=preload("res://shaders/levels/b07/l37_review_ground.gdshader")
		for parameter: Dictionary in original.shader.get_shader_uniform_list():
			shaded.set_shader_parameter(parameter.name,original.get_shader_parameter(parameter.name))
		layer.material=shaded
	review_ready = true
	return true
