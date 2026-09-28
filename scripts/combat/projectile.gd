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
var speed: float = Balance.PROJECTILE_SPEED
var distance_left: float = 1200.0
var pierce_remaining: int = 0
var options: Dictionary = {}
var hit_ids: Array[int] = []
var echo_hit_ids: Array = []
var attack_id: int = 0
var critical: bool = false

func _physics_process(delta: float) -> void:
	if consumed or Game.run == null:
		return
	remaining -= delta
	if remaining <= 0.0:
		_finish()
		return
	var distance: float = minf(speed * delta, distance_left)
	var next: Vector2 = position + direction * distance
	var wall_fraction: float = room.blocked_fraction(position, next, 2.0)
	var segment: Vector2 = (next - position) * wall_fraction
	var collisions: Array[Dictionary] = []
	for target in room.enemies.get_children():
		if not target.is_alive() or target.get_instance_id() == ignored_enemy or target.get_instance_id() in hit_ids:
			continue
		var t: float = clampf((target.position - position).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		if (position + segment * t).distance_squared_to(target.position) <= pow(target.navigation_radius + 4.0, 2) and room.has_line_of_sight(position, target.position):
			collisions.append({"target":target,"t":t})
	collisions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	var start: Vector2 = position
	for collision: Dictionary in collisions:
		position = start + segment * float(collision.t)
		_echo_segment(start, position)
		hit(collision.target)
		if consumed:
			return
	position = start + segment
	distance_left = maxf(0.0, distance_left - segment.length())
	_echo_segment(start, position)
	if wall_fraction < 1.0 or distance_left <= 0.0 or not room.ARENA.has_point(position):
		_finish()
	queue_redraw()

func _echo_segment(from: Vector2, to: Vector2) -> void:
	if not bool(options.get("echo_along_path", false)):
		return
	var samples: int = maxi(1, int(ceil(from.distance_to(to) / 30.0)))
	for index in range(samples + 1):
		echo_hit_ids = room.node_echo(from.lerp(to, float(index) / samples), float(options.get("echo_reach", 90.0)), float(options.get("echo_damage", 0.0)), "", echo_hit_ids)

func hit(target: Node2D) -> void:
	if consumed or not target.is_alive() or target.get_instance_id() in hit_ids:
		return
	hit_ids.append(target.get_instance_id())
	if source in [&"primary", &"child"]:
		room.resolve_weapon_hit(self, target)
	elif not options.is_empty():
		if float(options.get("explosion_radius", 0.0)) > 0.0:
			_finish()
			return
		if bool(options.get("original", false)):
			room.resolve_direct_hit(target, damage, source, str(options.get("status", "")), 0.0, direction, options)
		else:
			target.take_damage(damage, source)
		room.add_ring(position, options.get("color", Color("9fdacf")), 18.0, 0.17)
		room.player.hit_feedback(0.055 if bool(options.get("heavy", false)) else 0.03)
	if pierce_remaining > 0:
		pierce_remaining -= 1
		damage *= float(options.get("pierce_multiplier", 1.0))
	else:
		consumed = true
		queue_free()

func _finish() -> void:
	if consumed:
		return
	consumed = true
	var radius: float = float(options.get("explosion_radius", 0.0))
	if radius > 0.0:
		room.strike_area(position, radius, damage, source, str(options.get("status", "")), 0.0, Vector2.ZERO, 360.0, bool(options.get("original", false)), options)
		room.add_ring(position, Color("72c1c7"), radius, 0.22)
		room.node_echo(position, float(options.get("echo_reach", 90.0)), float(options.get("echo_damage", 0.0)))
	queue_free()

func _draw() -> void:
	var color: Color = options.get("color", Color("67c7d5") if source == &"child" else Color("f6ce81"))
	if arc_ready:
		color = Color("c4f7ff")
	var width: float = 5.0 if float(options.get("explosion_radius", 0.0)) > 0.0 else 3.5
	draw_line(-direction * 18.0, Vector2.ZERO, Color(color, 0.18), width * 2, true)
	draw_line(-direction * 12.0, direction * 3.0, color, width if source != &"child" else 2.0, true)
	draw_circle(Vector2.ZERO, width, Color("f1eadc"))
