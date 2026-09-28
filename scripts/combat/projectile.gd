class_name SparkProjectile
extends Node2D

var room: Node2D
var direction := Vector2.RIGHT
var damage: float = Balance.SHOT_DAMAGE
var source: StringName = &"primary"
var arc_ready: bool = false
var trigger_budget: int = Balance.TRIGGER_BUDGET
var remaining: float = Balance.PROJECTILE_LIFETIME
var consumed: bool = false
var ignored_enemy: int = 0

func _physics_process(delta: float) -> void:
	if consumed or Game.run == null:
		return
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
		return
	var next := position + direction * Balance.PROJECTILE_SPEED * delta
	var closest: Node2D = null
	var closest_t := 2.0
	var segment := next - position
	# ponytail: bounded linear sweep (100 shots x 18 enemies); spatial grid only if limits rise.
	for target in room.enemies.get_children():
		if not target.is_alive() or target.get_instance_id() == ignored_enemy:
			continue
		var t: float = clampf((target.position - position).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		if (position + segment * t).distance_squared_to(target.position) <= pow(Balance.ENEMY_RADIUS + 4.0, 2) and t < closest_t:
			closest_t = t
			closest = target
	if closest != null:
		position += segment * closest_t
		hit(closest)
		return
	position = next
	if not room.ARENA.grow(24.0).has_point(position):
		queue_free()
	queue_redraw()

func hit(target: Node2D) -> void:
	if consumed or not target.is_alive():
		return
	consumed = true
	room.resolve_weapon_hit(self, target)
	queue_free()

func _draw() -> void:
	var color := Color("67c7d5") if source == &"child" else Color("f6ce81")
	if arc_ready:
		color = Color("c4f7ff")
	draw_line(-direction * 18.0, Vector2.ZERO, Color(color, 0.18), 8.0, true)
	draw_line(-direction * 12.0, direction * 3.0, color, 3.5 if source == &"primary" else 2.0, true)
	draw_circle(Vector2.ZERO, 3.0 if source == &"primary" else 2.0, Color("f1eadc"))
