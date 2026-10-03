extends Node2D
## A single raised object sorts at its real contact foot, never at the room's
## origin. A small opacity change keeps the hero visible behind tall masonry.

const Appearance = preload("res://scripts/presentation/world/room_appearance.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
var recipe: Dictionary = {}
var room: Node2D
var occludes: bool = false
var local_visual_bounds := Rect2()

func configure(owner_room: Node2D, item: Dictionary) -> void:
	room = owner_room
	recipe = item
	position = item.get("foot", Vector2.ZERO)
	occludes = bool(item.get("occludes", false))
	var bounds: Rect2 = item.get("visual_bounds", Rect2())
	local_visual_bounds = Rect2(bounds.position-position,bounds.size)
	if str(item.get("depth_kind", "")) == "prop": material = Art.material_for(str(item.get("biome_id", "B01")))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_physics_process(occludes)
	queue_redraw()

func _physics_process(delta: float) -> void:
	var player: Node2D = room.get("player") if is_instance_valid(room) else null
	var hidden: bool = is_instance_valid(player) and player.position.y < position.y and local_visual_bounds.grow(12.0).has_point(to_local(player.global_position)+Vector2(0,-28))
	modulate.a = move_toward(modulate.a, 0.46 if hidden else 1.0, maxf(0.0,delta)*5.5)

func _draw() -> void:
	if not bool(recipe.get("destroyed", false)):
		Appearance.draw_depth_item(self, recipe)
