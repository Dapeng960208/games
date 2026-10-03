extends "res://scripts/gameplay/monsters/enemy_actor.gd"
## Task objects participate in the exact same melee/projectile hit path as enemies.
## They never grant kill rewards and never run an enemy brain.
var objective_host: Node2D
var objective_id: String = ""
var objective_texture: Texture2D
var objective_region := Rect2()
var objective_label: String = ""
const ObjectiveArt = preload("res://scripts/infrastructure/assets/world_art.gd")
const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
var objective_asset := ""

func _ready() -> void:
	static_actor = true
	reward_enabled = false
	actor_kind = "objective"
	super._ready()
	state = &"idle"
	navigation_radius = 26.0
	var item: Dictionary = objective_host.element(objective_id)
	material = ObjectiveArt.material_for(str(objective_host.definition.get("biome_id", "B01")))
	objective_label = str(item.get("label", ""))
	var asset: String = str(item.get("asset", ""))
	objective_asset = asset
	if not asset.is_empty():
		objective_texture = PropArt.texture_for_asset(asset)
		if objective_texture != null:
			objective_region = PropArt.local_region(asset) if PropArt.has_authored_asset(asset) else ImageBounds._visible_region(objective_texture.get_image())

func take_damage(amount: float, kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
	if not is_alive():
		return false
	if is_instance_valid(objective_host):
		var hit: Dictionary = context.duplicate()
		hit.merge({"damage": amount, "kind": str(kind), "direction": direction}, true)
		objective_host.on_target_hit(objective_id, hit)
	return super.take_damage(amount, kind, direction, context)

func _die() -> void:
	if is_instance_valid(objective_host):
		objective_host.on_target_destroyed(objective_id)
	queue_free()

func _draw() -> void:
	if health == null or health.dead:
		return
	var width: float = 86.0
	# Task machines keep a stable teal contact ring and a cream badge, visually
	# distinct from enemy silhouettes and coral combat warnings.
	draw_arc(Vector2(0,7),32,0,TAU,40,Color("fff1d6"),4.0,true)
	draw_arc(Vector2(0,7),32,0,TAU,40,Color("55b9b3"),1.5,true)
	if objective_texture != null and objective_region.has_area():
		width = minf(130.0, objective_region.size.x / objective_region.size.y * 100.0)
		if PropArt.has_authored_asset(objective_asset): PropArt.draw_asset(self,objective_asset,Vector2.ZERO,Vector2(130,100))
		else: draw_texture_rect_region(objective_texture, Rect2(-width * .5, -83, width, 100), objective_region)
	else:
		draw_arc(Vector2.ZERO, 28, 0, TAU, 32, Color("7bbfbb"), 3, true)
	if hurt_flash > 0:
		draw_arc(Vector2.ZERO, 31, 0, TAU, 32, Color("fff4d6"), 3, true)
	draw_rect(Rect2(-28, -95, 56, 10), Color("f8e6c5"))
	draw_rect(Rect2(-26, -93, 52, 6), Color("b9beb2"))
	draw_rect(Rect2(-26, -93, 52 * health.current / health.maximum, 6), Color("60b8ad"))
	draw_colored_polygon(PackedVector2Array([Vector2(-5,-106),Vector2(0,-112),Vector2(5,-106),Vector2(0,-100)]),Color("5aa9a5"))
