class_name SparkProjectile
extends Node2D

const VisualPath = preload("res://scripts/combat/projectile_visual.gd")

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
var _visual_path: Dictionary = {}

func configure_player_visual(muzzle_in_room: Vector2) -> void:
	if source == &"child" or str(options.get("visual_hero","")) not in ["CH02","CH03"]:
		return
	_visual_path = VisualPath.snapshot(room,position,direction,distance_left,pierce_remaining,muzzle_in_room,str(options.get("visual_hero","")) == "CH02")

func visual_position() -> Vector2:
	return VisualPath.position_at(_visual_path,position)

func visual_direction() -> Vector2:
	return VisualPath.direction_at(_visual_path,position,direction)

func visual_path_snapshot() -> Dictionary:
	return _visual_path.duplicate(true)

func visual_draw_scale() -> float:
	return 1.0 if _visual_path.is_empty() else VisualPath.draw_scale(room,visual_position())

func visual_trail_fraction() -> float:
	if _visual_path.is_empty(): return 1.0
	return clampf(visual_position().distance_to(_visual_path.knots[0].point)/28.0,0.0,1.0)

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
		echo_hit_ids = room.node_echo(from.lerp(to, float(index) / samples), float(options.get("echo_reach", 90.0)), float(options.get("echo_damage", 0.0)), "", echo_hit_ids, options)

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
			room.resolve_derived_hit(target, damage, source, direction, options)
		room.add_ring(position, options.get("color", Color("9fdacf")), 18.0, 0.17)
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
		echo_hit_ids = room.node_echo(position, float(options.get("echo_reach", 90.0)), float(options.get("echo_damage", 0.0)), "", echo_hit_ids, options)
	queue_free()

func _draw() -> void:
	var display_offset: Vector2 = visual_position()-position
	var display_angle: float = direction.angle_to(visual_direction())
	var display_scale: float = visual_draw_scale()
	draw_set_transform(display_offset,display_angle,Vector2.ONE*display_scale)
	# Class identity belongs to the projectile that was actually spawned. It is
	# intentionally absent from derived/child shots and cannot affect collision.
	var visual_hero: String = str(options.get("visual_hero", ""))
	if source != &"child" and visual_hero == "CH02":
		_draw_gunner_needle(visual_trail_fraction())
		draw_set_transform(Vector2.ZERO)
		return
	if source != &"child" and (visual_hero == "CH03" or source == &"node"):
		_draw_arcanist_crystal(visual_trail_fraction())
		draw_set_transform(Vector2.ZERO)
		return
	var color: Color = options.get("color", Color("67c7d5") if source == &"child" else Color("f6ce81"))
	if arc_ready:
		color = Color("c4f7ff")
	var width: float = 5.0 if float(options.get("explosion_radius", 0.0)) > 0.0 else 3.5
	draw_line(-direction * 18.0, Vector2.ZERO, Color(color, 0.18), width * 2, true)
	draw_line(-direction * 12.0, direction * 3.0, color, width if source != &"child" else 2.0, true)
	draw_circle(Vector2.ZERO, width, Color("f1eadc"))
	draw_set_transform(Vector2.ZERO)

func _draw_gunner_needle(trail: float = 1.0) -> void:
	var tint := Color("e7b568")
	if arc_ready: tint = Color("b2f4ff")
	var normal := direction.orthogonal()
	var heavy: bool = bool(options.get("heavy", false))
	var rail: bool = source == &"secondary"
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var width: float = 2.0 if rail else 1.8 if heavy else 1.15
	# Keep the whole needle inside VisualPath.DRAW_RADIUS. A rail release has a
	# pair of white conductors; mobile bursts retain a narrow brass tracer.
	if not reduced:
		draw_line(-direction * 28.0 * trail, -direction * 5.0 * trail, Color(tint,.13*trail), 5.0 if heavy else 3.2, true)
	draw_line(-direction * 24.0 * trail, -direction * 8.0 * trail, Color(tint,.72*trail), 1.0, true)
	draw_colored_polygon(PackedVector2Array([direction * 6.0, -direction * 8.0 * trail - normal * width,
		-direction * 16.0 * trail, -direction * 8.0 * trail + normal * width]), Color("fff5da"))
	draw_line(-direction * 9.0 * trail, direction * 3.0, Color("ffffff"), 1.0, true)
	if rail:
		for side in [-1.0,1.0]:
			draw_line(-direction*24.0*trail+normal*side*2.7,-direction*4.0*trail+normal*side*1.8,Color("fff4da",.85*trail),1.2,true)
		if not reduced:
			draw_line(-direction*18.0*trail-normal*4.3,-direction*18.0*trail+normal*4.3,Color(tint,.6*trail),1.0,true)
	if arc_ready and not reduced:
		draw_polyline(PackedVector2Array([-direction * 14.0 * trail - normal * 3.0, -direction * 7.0 * trail + normal * 2.0,
			direction * 2.0 - normal * 2.0]), Color(tint,.85), 1.15, true)

func _draw_arcanist_crystal(trail: float = 1.0) -> void:
	var tint := Color("a5f2ed")
	if arc_ready: tint = Color("b8f6ff")
	var violet := Color("b7a1ec")
	var normal := direction.orthogonal()
	var pulse_spell: bool = source == &"q"
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var radius: float = 8.5 if pulse_spell else 5.8
	# Q carries a runic orbit around its larger core; basic magic remains a
	# faceted bolt. Both have a violet/cyan constellation instead of a rifle wake.
	var pulse: float = sin(remaining * 18.0)
	if not reduced:
		draw_circle(Vector2.ZERO, radius * 1.8, Color(violet,.08))
	for index in (1 if reduced else 3):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var center: Vector2 = -direction * (11.0 + index * 6.0) * trail + normal * side * (4.0 + pulse * 1.2)
		var length: float = 3.8 - index * .6
		var shard_tint: Color = violet if index % 2 == 0 else tint
		draw_colored_polygon(PackedVector2Array([center + direction * length, center + normal * 1.8,
			center - direction * length, center - normal * 1.8]), Color(shard_tint,(.72 - index * .16)*trail))
	var tip: Vector2 = direction * radius
	var heel: Vector2 = -direction * radius * .8
	var upper: Vector2 = normal * radius * .72
	var lower: Vector2 = -upper
	draw_colored_polygon(PackedVector2Array([tip,upper,heel,lower]), Color(violet,.88))
	draw_colored_polygon(PackedVector2Array([tip,upper,Vector2.ZERO]), Color("d7fff6"))
	draw_colored_polygon(PackedVector2Array([heel,lower,Vector2.ZERO]), Color(violet,.8))
	draw_polyline(PackedVector2Array([tip,upper,heel,lower,tip]), Color("bdfaf3"), 1.0, true)
	draw_circle(Vector2.ZERO,1.5,Color("f0fff9"))
	if pulse_spell:
		var orbit: float = remaining*5.0
		draw_arc(Vector2.ZERO,radius+4.5,orbit,orbit+PI*.75,12,Color(tint,.82),1.4,true)
		draw_arc(Vector2.ZERO,radius+4.5,orbit+PI,orbit+PI*1.75,12,Color(violet,.86),1.4,true)
		if not reduced:
			for index in 3:
				var ray: Vector2 = Vector2.from_angle(orbit+index*TAU/3)
				var point: Vector2 = ray*(radius+5.5)
				draw_line(point-ray*2,point+ray*2,Color("f0fff9",.8),1.8,true)
	if arc_ready and not reduced:
		draw_arc(Vector2.ZERO,radius+3.0,direction.angle()-.7,direction.angle()+1.6,10,Color(tint,.85),1.2,true)
