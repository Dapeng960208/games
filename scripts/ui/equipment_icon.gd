extends Control
## Each live equipment ID owns a new painted 3/4 illustration. The shared atlas
## cache preserves its transparency and keeps a catalogue view inexpensive.

const Art = preload("res://scripts/ui/equipment_art.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
var equipment_data: Dictionary = {}
var generated_texture: Texture2D
var is_empty := true
var rarity_frame: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	queue_redraw()

func set_equipment(data: Dictionary) -> void:
	equipment_data = data
	rarity_frame = null
	if not Inspect.rarity(data).is_empty():
		var tint := Inspect.rarity_color(data)
		rarity_frame = MineStyle.box(MineStyle.PAPER_LIGHT.lerp(tint,.10),tint,2)
	var id := str(data.get("id", ""))
	is_empty = id.is_empty()
	generated_texture = Art.texture(id) if not is_empty else null
	# Individual source PNGs remain a missing-pack fallback in development builds.
	if generated_texture == null and not is_empty:
		generated_texture = Sampler.sampled("res://assets/generated/equipment/" + id + "_v1.png")
	if generated_texture == null and not is_empty:
		generated_texture = Art.slot_texture(str(data.get("slot", "")))
	if generated_texture == null:
		generated_texture = Art.fallback_texture(str(data.get("slot", "")))
	queue_redraw()

func _draw() -> void:
	if generated_texture == null or size.x <= 0 or size.y <= 0: return
	if rarity_frame != null: draw_style_box(rarity_frame,Rect2(Vector2(2,2),size-Vector2(4,4)))
	var source_size := generated_texture.get_size()
	if source_size.x <= 0 or source_size.y <= 0: return
	var image_scale := minf(size.x / source_size.x, size.y / source_size.y)
	var extent := source_size * image_scale
	draw_texture_rect(generated_texture, Rect2((size - extent) * 0.5, extent), false, Color(1, 1, 1, 0.45 if is_empty else 1.0))
