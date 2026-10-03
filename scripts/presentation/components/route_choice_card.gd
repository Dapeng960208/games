extends Button
## A scene vignette beside live travel notes; no text is baked into art.
const JourneyArt = preload("res://scripts/presentation/components/route_journey_art.gd")
var scene_texture: Texture2D
var landmark_texture: Texture2D
var role := "branch"
var preview_index := 0
var illustration_width := 132.0

func _ready() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var active := not disabled and (is_hovered() or has_focus())
	var color := Color("257f83") if active else Color("ad864d")
	var image_bounds := Rect2(7, 7, illustration_width - 14, maxf(90, size.y - 20))
	var background := Rect2(2, 2, size.x - 4, size.y - 4)
	draw_style_box(_wash(Color(1.0, .975, .90, .94) if active else Color(1.0, .97, .89, .65)), background)
	if active: draw_style_box(_outline(color), background)
	if scene_texture != null:
		var source_size := scene_texture.get_size()
		var crop_width := minf(source_size.y * image_bounds.size.x / image_bounds.size.y, source_size.x)
		var crop_x := clampf(source_size.x * [.13, .68, .34, .52][preview_index % 4] - crop_width * .5, 0.0, source_size.x - crop_width)
		draw_texture_rect_region(scene_texture, image_bounds, Rect2(crop_x, 0, crop_width, source_size.y), Color(1,1,1,.80 if disabled else 1.0))
	else: draw_style_box(_wash(Color("eddbad")), image_bounds)
	for corner: Vector2 in [image_bounds.position, image_bounds.position+Vector2(image_bounds.size.x,0), image_bounds.end, image_bounds.position+Vector2(0,image_bounds.size.y)]:
		var direction := Vector2(1 if corner.x < illustration_width*.5 else -1, 1 if corner.y < size.y*.5 else -1)
		draw_line(corner, corner+Vector2(direction.x*12,0), color, 2.0, true)
		draw_line(corner, corner+Vector2(0,direction.y*12), color, 2.0, true)
	if landmark_texture != null:
		var factor := minf(110.0/landmark_texture.get_width(), 106.0/landmark_texture.get_height())
		var extent := landmark_texture.get_size()*factor
		draw_texture_rect(landmark_texture, Rect2(Vector2(illustration_width*.5-extent.x*.5, size.y*.62-extent.y*.5),extent), false, Color(1,1,1,.83 if disabled else 1.0))
	var medallion := Vector2(illustration_width*.5, 33)
	draw_circle(medallion+Vector2(0,2), 22, Color(0.2,0.15,0.22,.16))
	draw_circle(medallion, 22, Color("b48949"))
	draw_circle(medallion, 19, Color("f4e1b8"))
	JourneyArt.draw_role(self, role, medallion, 11, GameStyle.INK)
	draw_line(Vector2(illustration_width+8, size.y-6), Vector2(size.x-10, size.y-6), Color("d4b786"), 1.0, true)
	if active:
		var arrow := Vector2(size.x-18,21)
		draw_polyline(PackedVector2Array([arrow+Vector2(-5,-5),arrow,arrow+Vector2(-5,5)]), color, 2.0,true)

func _wash(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(7)
	return style

func _outline(color: Color) -> StyleBoxFlat:
	var style := _wash(Color(0,0,0,0))
	style.border_color = Color(color, .65)
	style.set_border_width_all(1)
	return style
