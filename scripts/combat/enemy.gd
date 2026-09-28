class_name MineEnemy
extends CharacterBody2D

const HealthScript = preload("res://scripts/combat/health.gd")
var room: Node2D
var health: CombatHealth
var state: StringName = &"emerging"
var state_time: float = Balance.ENEMY_SPAWN_GRACE
var aim_direction := Vector2.LEFT
var knockback := Vector2.ZERO
var hurt_flash: float = 0.0
var burn_remaining: float = 0.0
var burn_tick: float = 0.0
var lifetime: float = 0.0
var body_texture: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/characters/rust_mite.png"):
		body_texture = load("res://assets/characters/rust_mite.png")
	health = HealthScript.new()
	add_child(health)
	health.reset(Balance.ENEMY_HP)
	health.depleted.connect(_die)

func is_alive() -> bool:
	return health != null and not health.dead

func _physics_process(delta: float) -> void:
	if not is_alive() or Game.run == null:
		return
	lifetime += delta
	hurt_flash = maxf(0.0, hurt_flash - delta)
	tick_burn(delta)
	if not is_alive():
		return
	var offset: Vector2 = room.player.position - position
	var distance := offset.length()
	state_time -= delta
	velocity = Vector2.ZERO
	match state:
		&"emerging":
			if state_time <= 0.0:
				state = &"chase"
		&"chase":
			if distance > 0.1:
				aim_direction = offset / distance
			if distance <= Balance.ENEMY_RANGE + Balance.PLAYER_RADIUS:
				state = &"windup"
				state_time = Balance.ENEMY_WINDUP
			else:
				velocity = aim_direction * Balance.ENEMY_SPEED + _separation()
		&"windup":
			if state_time <= 0.0:
				state = &"recovery"
				state_time = Balance.ENEMY_RECOVERY
				room.add_slash(position, aim_direction)
				if distance <= Balance.ENEMY_RANGE + Balance.PLAYER_RADIUS and offset.normalized().dot(aim_direction) > 0.35:
					room.player.receive_damage(Balance.ENEMY_DAMAGE, position)
		&"recovery":
			if state_time <= 0.0:
				state = &"chase"
	velocity += knockback
	knockback = knockback.move_toward(Vector2.ZERO, Balance.ENEMY_KNOCKBACK_DECAY * delta)
	position += velocity * delta
	position = room.clamp_actor(position, Balance.ENEMY_RADIUS)
	queue_redraw()

func _separation() -> Vector2:
	var force := Vector2.ZERO
	for other in room.enemies.get_children():
		if other == self or not other.is_alive():
			continue
		var offset: Vector2 = position - other.position
		var distance := offset.length()
		if distance > 0.01 and distance < Balance.ENEMY_SEPARATION_DISTANCE:
			force += offset / distance * (Balance.ENEMY_SEPARATION_DISTANCE - distance) * Balance.ENEMY_SEPARATION_STRENGTH
	return force.limit_length(Balance.ENEMY_SPEED * Balance.ENEMY_SEPARATION_SPEED_RATIO)

func take_damage(amount: float, kind: StringName, from_direction := Vector2.ZERO) -> bool:
	if not is_alive() or Game.run == null:
		return false
	if kind == &"primary" or kind == &"child":
		knockback += from_direction * Balance.ENEMY_KNOCKBACK
	hurt_flash = 0.1
	room.add_damage_text(position - Vector2(0, 65 if body_texture != null else 26), amount, kind)
	return health.damage(amount)

func apply_burn() -> void:
	if not is_alive():
		return
	if burn_remaining <= 0.0:
		burn_tick = 0.0
	burn_remaining = Balance.EMBER_DURATION
	queue_redraw()

func tick_burn(delta: float) -> void:
	if burn_remaining <= 0.0:
		return
	var active_delta := minf(delta, burn_remaining)
	burn_remaining = maxf(0.0, burn_remaining - delta)
	burn_tick += active_delta
	while burn_tick + 0.00001 >= 1.0 and is_alive():
		burn_tick = maxf(0.0, burn_tick - 1.0)
		room.telemetry["burn_ticks"] += 1
		take_damage(Balance.EMBER_DPS, &"burn")

func _die() -> void:
	room.enemy_died(self)
	queue_free()

func _draw() -> void:
	if health == null:
		return
	var reduced: bool = Game.profile.get("settings", {}).get("reduced_fx", false)
	if state == &"emerging":
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 24, Color(0.9, 0.42, 0.41, 0.65), 2.0, true)
		draw_line(Vector2(-5,-30), Vector2(5,-30), Color("e46b69"), 2.0)
	if state == &"windup":
		var progress := 1.0 - state_time / Balance.ENEMY_WINDUP
		var fan := PackedVector2Array([Vector2.ZERO])
		for i in range(13):
			fan.append(aim_direction.rotated(-1.15 + float(i) / 12.0 * 2.3) * (Balance.ENEMY_RANGE + 8.0))
		draw_colored_polygon(fan, Color(0.89, 0.28, 0.24, 0.13 + progress * 0.15))
		draw_polyline(fan, Color(0.95, 0.44, 0.40, 0.85), 1.5, true)
		draw_arc(Vector2.ZERO, 42 if body_texture != null else 25, -PI / 2, -PI / 2 + TAU * progress, 24, Color("f1b466"), 3, true)
	draw_set_transform(Vector2(0,10), 0.0, Vector2(1,0.5))
	draw_circle(Vector2.ZERO, 22.0, Color(0.02, 0.03, 0.04, 0.6))
	draw_set_transform(Vector2.ZERO)
	if body_texture != null:
		draw_arc(Vector2.ZERO,Balance.ENEMY_RADIUS,0,TAU,24,Color(0.89,0.42,0.41,0.25),1.0,true)
		draw_texture_rect(body_texture,Rect2(-43,-48,86,86),false)
	else:
		_draw_fallback_body()
	if state == &"windup":
		var marker_y := -70.0 if body_texture != null else -35.0
		draw_line(Vector2(0,marker_y), Vector2(0,marker_y+8), Color("fff0cf"), 3)
		draw_circle(Vector2(0,marker_y+13), 1.8, Color("fff0cf"))
	if burn_remaining > 0.0:
		for i in range(3):
			var base := Vector2(-10 + i * 10, -34 if body_texture != null else -17)
			var flicker := 3.0 * sin(lifetime * 14 + i)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-4,0),base+Vector2(1,-14-flicker),base+Vector2(5,0)]),Color("e6aa4a"))
	if hurt_flash > 0.0 and not reduced:
		draw_circle(Vector2(0,-3),17.0,Color(1.0,0.93,0.8,0.5))
	if health.current < health.maximum:
		var bar_y := -53 if body_texture != null else -40
		draw_rect(Rect2(-18,bar_y,36,4),Color("0d131a"))
		draw_rect(Rect2(-18,bar_y,36 * health.current / health.maximum,4),Color("e46b69"))

func _draw_fallback_body() -> void:
	var walk := sin(lifetime * 9.0) * (3.0 if state == &"chase" else 0.0)
	for side in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([Vector2(side*8,0),Vector2(side*23,-8+walk),Vector2(side*29,6+walk)]), Color("75614e"), 4.0, true)
		draw_polyline(PackedVector2Array([Vector2(side*9,5),Vector2(side*21,13-walk),Vector2(side*23,21-walk)]), Color("4c5c63"), 4.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6),Vector2(13,12),Vector2(-12,12)]), Color("43505a"))
	draw_polyline(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6)]), Color("917458"), 2.0, true)
	draw_line(Vector2(-13,-4),Vector2(14,-4),Color("19252c"),6.0)
	draw_line(Vector2(-9,-4),Vector2(10,-4),Color("e99663"),3.0)
	draw_circle(Vector2(0,5),5.0,Color("a07447"))
	draw_circle(Vector2(0,5),2.0,Color("f4cf80"))
