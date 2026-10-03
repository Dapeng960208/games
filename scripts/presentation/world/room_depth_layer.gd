extends Node2D
## Presentation alone: every child has its own world foot and contributes no
## collision. The room's existing obstruction list stays authoritative.

const Appearance = preload("res://scripts/presentation/world/room_appearance.gd")
const B07Skins = preload("res://scripts/levels/b07/art/l37_prop_skins.gd")
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
		backdrop.configure_layout(layout,preload("res://scripts/infrastructure/content/runtime_rules.gd").b05_candidate_enabled())
	var skins := B07Skins.skin_recipes(room)
	recipes = Appearance.depth_recipe(layout, biome_id, obstacle_recipes)
	if not skins.is_empty():
		recipes = recipes.filter(func(item: Dictionary) -> bool: return not B07Skins.replaces_cover(item,skins))
		recipes.append_array(skins)
	for item: Dictionary in recipes:
		var sprite: Node2D = B07Skins.new() if str(item.get("depth_kind","")) == "b07_review_skin" else DepthSprite.new()
		sprite.name = str(item.get("id", "RaisedScenery")).replace(":", "_")
		add_child(sprite)
		sprite.configure(room, item)
	generation += 1
