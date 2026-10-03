extends Control
## Original ImageGen hero portraits, preserving alpha and their full composition.
## Missing portraits use the current registered idle frame.

var hero_id: String = "CH01"
var hero_data: Dictionary = {}
var generated_texture: Texture2D
var generated_region := Rect2()
const TextureSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const HeroFrames = preload("res://scripts/presentation/characters/hero_visual.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	queue_redraw()

func set_hero(id: String, data: Dictionary = {}) -> void:
	hero_id = id
	hero_data = data
	var path := "asset://heroes/"+hero_id+"_storybook_portrait_v1.png"
	generated_texture = TextureSampler.sampled(path)
	generated_region = Rect2(Vector2.ZERO, generated_texture.get_size()) if generated_texture != null else Rect2()
	# Menu cards use the full portrait; a world sprite is only a missing-art fallback.
	if generated_texture == null:
		var frame: Dictionary = HeroFrames.action_frame_info(hero_id, "front", "idle")
		if not frame.is_empty():
			generated_texture = frame.texture
			generated_region = frame.region
	queue_redraw()

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if generated_texture != null:
		var source_size := generated_region.size
		var image_scale := minf(size.x/source_size.x,size.y/source_size.y)
		var extent := source_size*image_scale
		draw_texture_rect_region(generated_texture,Rect2((size-extent)*0.5,extent),generated_region)
		return
