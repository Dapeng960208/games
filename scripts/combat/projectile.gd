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
			var delivered: Dictionary = options.duplicate(true)
			delivered["attack_delivery"] = "projectile"
			var confirmed: bool = room.resolve_direct_hit(target, damage, source, str(options.get("status", "")), 0.0, direction, delivered)
			var b06_bonus: Dictionary = options.get("b06_r_bonus", {})
			if confirmed and target.is_alive() and str(b06_bonus.get("target_id", "")) == str(target.get_instance_id()):
				var derived: Dictionary = b06_bonus.duplicate(true)
				derived.merge({"damage_source":"equipment", "original_basic":false, "attacker_stats":options.get("attacker_stats", {}), "root_event_id":options.get("root_event_id", "")}, true)
				room.resolve_derived_hit(target, float(b06_bonus.damage), &"equipment", direction, derived)
		else:
			var delivered_child: Dictionary = options.duplicate(true)
			delivered_child["attack_delivery"] = "projectile"
			room.resolve_derived_hit(target, damage, source, direction, delivered_child)
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
	var visual_hero: String = str(options.get("visual_hero", ""))
	if source != &"child" and (visual_hero in ["CH02","CH03"] or source == &"node"):
		_draw_ground_shadow(visual_hero)
	var display_offset: Vector2 = visual_position()-position
	var display_angle: float = direction.angle_to(visual_direction())
	var display_scale: float = visual_draw_scale()
	draw_set_transform(display_offset,display_angle,Vector2.ONE*display_scale)
	# Class identity belongs to the projectile that was actually spawned. It is
	# intentionally absent from derived/child shots and cannot affect collision.
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

func _draw_ground_shadow(hero: String) -> void:
	if bool(Game.profile.get("settings",{}).get("reduced_fx",false)):
		return
	# The small contact shadow stays at the true ground position. The elevated
	# muzzle/body path above it remains frozen and keeps its existing release ray.
	var clearance: float = VisualPath.draw_scale(room,position)
	if clearance <= 0.0:
		return
	var magic: bool = hero == "CH03" or source == &"node"
	var size: float = 7.5 if magic else 6.0
	var shadow := PackedVector2Array()
	for index in 12:
		var angle: float = index*TAU/12.0
		shadow.append(Vector2(cos(angle)*size,sin(angle)*size*.34)*clearance)
	draw_colored_polygon(shadow,Color("655464",.14) if magic else Color("796045",.13))

func _draw_gunner_needle(trail: float = 1.0) -> void:
	var tint := Color("ffc65c")
	var variant: int = int(options.get("basic_variant",0)) if source == &"primary" else 0
	if variant == 1: tint = Color("ffe697")
	elif variant == 2: tint = Color("ff9b43")
	if arc_ready: tint = Color("7feaff")
	var normal := direction.orthogonal()
	var heavy: bool = bool(options.get("heavy", false))
	var rail: bool = source == &"secondary"
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var width: float = 3.5 if rail else 3.2 if heavy else 2.4
	# Keep the whole needle inside VisualPath.DRAW_RADIUS. A rail release has a
	# pair of white conductors; mobile bursts retain a solid brass tracer. The
	# longest tail is 28px with at most a 6.5px stroke, leaving AA room in 32px.
	if not reduced:
		draw_line(-direction * 28.0 * trail, -direction * 5.0 * trail, Color(tint,.32*trail), 6.5 if heavy or rail else 5.5, true)
	draw_line(-direction * 25.0 * trail, -direction * 7.0 * trail, Color("67452e",.82*trail), 3.8, true)
	draw_line(-direction * 25.0 * trail, -direction * 7.0 * trail, Color(tint,.98*trail), 2.0, true)
	var tip: Vector2 = direction*8.0
	var waist: Vector2 = -direction*8.0*trail
	var heel: Vector2 = -direction*18.0*trail
	var lit_side: Vector2 = normal if normal.dot(_display_light()) >= 0.0 else -normal
	var needle := PackedVector2Array([tip,waist-normal*width,heel,waist+normal*width])
	draw_colored_polygon(needle,Color("eda840"))
	# A pale upper plane and warm lower plane give the pin a small solid bevel.
	draw_colored_polygon(PackedVector2Array([tip,waist+lit_side*width,heel]),Color("fff9e5"))
	needle.append(needle[0])
	draw_polyline(needle,Color("69472e",.98),1.7,true)
	draw_line(-direction * 11.0 * trail, direction * 5.0, Color("ffffff"), 1.8, true)
	if variant == 1:
		draw_line(-direction*17*trail-normal*3,-direction*8*trail-normal*3,Color(tint,.95*trail),1.6,true)
	elif variant == 2:
		for along in [10.0,18.0]:
			draw_line(-direction*along*trail-normal*4,-direction*along*trail+normal*4,Color("ffc13b",.95*trail),2.3,true)
	if rail:
		for side in [-1.0,1.0]:
			draw_line(-direction*25.0*trail+normal*side*4.3,-direction*3.0*trail+normal*side*3.6,Color("67452e",.94*trail),4.0,true)
			draw_line(-direction*25.0*trail+normal*side*4.3,-direction*3.0*trail+normal*side*3.6,Color("fff8dc",.98*trail),2.1,true)
		if not reduced:
			for along in [12.0,20.0]:
				draw_line(-direction*along*trail-normal*4.1,-direction*along*trail+normal*4.1,Color(tint,.88*trail),1.4,true)
	if arc_ready and not reduced:
		draw_polyline(PackedVector2Array([-direction * 14.0 * trail - normal * 3.0, -direction * 7.0 * trail + normal * 2.0,
			direction * 2.0 - normal * 2.0]), Color(tint,.98), 1.8, true)

func _draw_arcanist_crystal(trail: float = 1.0) -> void:
	var tint := Color("43eaf2")
	var variant: int = int(options.get("basic_variant",0)) if source == &"primary" else 0
	if arc_ready: tint = Color("88f6ff")
	var violet := Color("b26aff")
	var normal := direction.orthogonal()
	var pulse_spell: bool = source == &"q"
	var reduced: bool = bool(Game.profile.get("settings",{}).get("reduced_fx",false))
	var radius: float = 11.5 if pulse_spell else 8.2
	if variant == 1: radius = 9.2
	# Q carries a runic orbit around its larger core; basic magic remains a
	# faceted bolt. Both have a violet/cyan constellation instead of a rifle wake.
	var pulse: float = sin(remaining * 18.0)
	if not reduced:
		draw_circle(Vector2.ZERO, radius * 1.65, Color(violet,.18))
		draw_circle(Vector2.ZERO, radius * 1.2, Color(tint,.13))
	for index in (1 if reduced else 3):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var center: Vector2 = -direction * (11.0 + index * 6.0) * trail + normal * side * (4.0 + pulse * 1.2)
		var length: float = 4.5 - index * .6
		var shard_tint: Color = violet if index % 2 == 0 else tint
		var shard := PackedVector2Array([center+direction*length,center+normal*2.4,center-direction*length,center-normal*2.4])
		draw_colored_polygon(shard,Color(shard_tint,(.98-index*.13)*trail))
		shard.append(shard[0])
		draw_polyline(shard,Color("573379",(.88-index*.13)*trail),1.4,true)
		if not reduced:
			draw_line(center-direction*length*.45,center+direction*length*.6,Color("f1fffc",(.9-index*.12)*trail),1.3,true)
	var tip: Vector2 = direction * radius
	var heel: Vector2 = -direction * radius * .8
	var upper: Vector2 = normal * radius * .78
	var lower: Vector2 = -upper
	var lit_side: Vector2 = normal if normal.dot(_display_light()) >= 0.0 else -normal
	var lit_point: Vector2 = lit_side*radius*.78
	var shaded_point: Vector2 = -lit_point
	draw_colored_polygon(PackedVector2Array([tip,upper,heel,lower]),Color("39cbd7" if variant == 1 else "df78ee" if variant == 2 else "a662ec"))
	draw_colored_polygon(PackedVector2Array([tip,lit_point,Vector2.ZERO]),Color("ecfffd"))
	draw_colored_polygon(PackedVector2Array([heel,lit_point,Vector2.ZERO]),Color("61e5e9"))
	draw_colored_polygon(PackedVector2Array([tip,shaded_point,Vector2.ZERO]),Color("51d7df" if variant == 1 else "e7a1ff" if variant == 2 else "ab83f9"))
	draw_colored_polygon(PackedVector2Array([heel,shaded_point,Vector2.ZERO]),Color("7942bd"))
	draw_polyline(PackedVector2Array([tip,upper,heel,lower,tip]),Color("513073",.98),2.1,true)
	draw_line(lit_point,tip,Color("f1fffc"),1.8,true)
	draw_line(heel,Vector2.ZERO,Color(tint,.95),1.3,true)
	draw_circle(Vector2.ZERO,2.0,Color("f0fff9"))
	if variant == 2:
		_draw_projected_orbit(radius+5.0,remaining*5.0,PI*1.8,Color("d681ff",.95),2.0)
	if pulse_spell:
		var orbit: float = remaining*5.0
		_draw_projected_orbit(radius+5.5,orbit,PI*.75,Color(tint,.98),2.2)
		_draw_projected_orbit(radius+5.5,orbit+PI,PI*.75,Color(violet,.98),2.2)
		if not reduced:
			for index in 3:
				var angle: float = orbit+index*TAU/3
				var ray: Vector2 = Vector2.from_angle(angle)
				var point: Vector2 = Vector2(cos(angle),sin(angle)*.56).rotated(-direction.angle_to(visual_direction()))*(radius+6.5)
				draw_line(point-ray*2.5,point+ray*2.5,Color("f0fff9",.98),2.2,true)
	if arc_ready and not reduced:
		draw_arc(Vector2.ZERO,radius+3.0,direction.angle()-.7,direction.angle()+1.6,10,Color(tint,.98),1.8,true)

func _display_light() -> Vector2:
	# Undo only the existing display-path rotation to keep upper-left lighting
	# consistent in screen space for all eight committed attack directions.
	return Vector2(-.65,-.75).rotated(-direction.angle_to(visual_direction()))

func _draw_projected_orbit(radius: float, start: float, span: float, tint: Color, width: float) -> void:
	var points := PackedVector2Array()
	var display_rotation: float = direction.angle_to(visual_direction())
	for index in 13:
		var angle: float = start+span*index/12.0
		points.append(Vector2(cos(angle)*radius,sin(angle)*radius*.56).rotated(-display_rotation))
	draw_polyline(points,Color("513073",tint.a*.8),width+1.5,true)
	draw_polyline(points,tint,width,true)
