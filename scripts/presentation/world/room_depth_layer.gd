extends Node2D
## Presentation alone: every child has its own world foot and contributes no
## collision. The room's existing obstruction list stays authoritative.

const Appearance = preload("res://scripts/presentation/world/room_appearance.gd")
const DepthSprite = preload("res://scripts/presentation/world/room_depth_sprite.gd")
var generation: int = 0
var recipes: Array[Dictionary] = []

func configure(room: Node2D, layout: Dictionary, biome_id: String, obstacle_recipes: Array) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	y_sort_enabled = true
	z_index = 2
	var backdrop: Node = room.get_node_or_null("MineBackdrop")
	if backdrop!=null and backdrop.has_method("configure_layout"):
		backdrop.configure_layout(layout,preload("res://scripts/infrastructure/content/runtime_rules.gd").chapter_enabled(5))
	recipes = Appearance.depth_recipe(layout, biome_id, obstacle_recipes)
	for item: Dictionary in recipes:
		var sprite := DepthSprite.new()
		sprite.name = str(item.get("id", "RaisedScenery")).replace(":", "_")
		add_child(sprite)
		sprite.configure(room, item)
	generation += 1
