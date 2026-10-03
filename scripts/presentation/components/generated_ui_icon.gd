extends Control
## Small generated HUD ornament; the HUD's text remains the readable label.

const TextureSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
var icon_key := ""
var fallback_text := ""
var generated_texture: Texture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()

func configure(key: String, fallback: String = "") -> void:
	icon_key = key
	fallback_text = fallback
	name = "Icon_"+key
	var path := "asset://ui/"+key+"_v1.png"
	generated_texture = TextureSampler.sampled(path)
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if generated_texture != null:
		var source_size := generated_texture.get_size()
		var image_scale := minf(size.x/source_size.x,size.y/source_size.y)
		var extent := source_size*image_scale
		draw_texture_rect(generated_texture,Rect2((size-extent)*0.5,extent),false)
	elif not fallback_text.is_empty():
		# A compact paper badge keeps missing-art labels readable on every HUD panel.
		var badge := Rect2(Vector2.ONE * 2.0, (size - Vector2.ONE * 4.0).max(Vector2.ZERO))
		draw_rect(badge,Color("fff3d7"))
		draw_rect(badge,Color("392843"),false,1.0)
		var font := get_theme_font("font","Label")
		var font_size := clampi(int(size.y * 0.5),10,18)
		var text_size := font.get_string_size(fallback_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		while text_size.x > maxf(0.0,size.x-8.0) and font_size > 8:
			font_size -= 1
			text_size = font.get_string_size(fallback_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		var at := Vector2((size.x-text_size.x)*0.5,(size.y-font.get_height(font_size))*0.5+font.get_ascent(font_size))
		draw_string(font,at,fallback_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("392843"))
