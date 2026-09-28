extends "res://scripts/combat/enemy.gd"
## Task objects participate in the exact same melee/projectile hit path as enemies.
## They never grant kill rewards and never run an enemy brain.
var objective_host: Node2D
var objective_id: String = ""
var objective_texture: Texture2D
var objective_region := Rect2()
var objective_label: String = ""

func _ready() -> void:
	static_actor = true
	reward_enabled = false
	actor_kind = "objective"
	super._ready()
	state = &"idle"
	navigation_radius = 26.0
	var item: Dictionary = objective_host.element(objective_id)
	objective_label = str(item.get("label", ""))
	var asset: String = str(item.get("asset", ""))
	if not asset.is_empty():
		objective_texture = TextureSampler.sampled("res://assets/generated/props/" + asset + "_v1.png")
		if objective_texture != null:
			objective_region = ImageBounds._visible_region(objective_texture.get_image())

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
	if objective_texture != null and objective_region.has_area():
		width = minf(130.0, objective_region.size.x / objective_region.size.y * 100.0)
		draw_texture_rect_region(objective_texture, Rect2(-width * .5, -83, width, 100), objective_region)
	else:
		draw_arc(Vector2.ZERO, 28, 0, TAU, 32, Color("d9bc75"), 3, true)
	if hurt_flash > 0:
		draw_arc(Vector2.ZERO, 31, 0, TAU, 32, Color("fff4d6"), 3, true)
	draw_rect(Rect2(-25, -92, 50, 4), Color("1a252b"))
	draw_rect(Rect2(-25, -92, 50 * health.current / health.maximum, 4), Color("d9bc75"))
