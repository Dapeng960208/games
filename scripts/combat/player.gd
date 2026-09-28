class_name SalvagerPlayer
extends CharacterBody2D

var room: Node2D
var aim_direction := Vector2.RIGHT
var dash_remaining: float = 0.0
var dash_cooldown: float = 0.0
var shot_cooldown: float = 0.0
var invulnerable: float = 0.0
var hurt_flash: float = 0.0
var muzzle_flash: float = 0.0
var dash_direction := Vector2.RIGHT
var knockback := Vector2.ZERO
var stride: float = 0.0
var body_texture: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/characters/salvager.png"):
		body_texture = load("res://assets/characters/salvager.png")

func _physics_process(delta: float) -> void:
	if Game.run == null:
		return
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	var motion := Vector2.ZERO
	if room.controls_enabled():
		motion = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var aim := get_global_mouse_position() - global_position
		if aim.length_squared() > 16.0:
			aim_direction = aim.normalized()
		if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0:
			dash_direction = motion.normalized() if motion.length_squared() > 0.0 else aim_direction
			dash_remaining = Balance.DASH_DURATION
			dash_cooldown = Balance.DASH_COOLDOWN
			room.telemetry["dashes"] += 1
			room.add_ring(global_position, Color("67c7d5"), 34.0, 0.25)
		if Input.is_action_pressed("attack"):
			fire(aim_direction)
	if dash_remaining > 0.0:
		dash_remaining = maxf(0.0, dash_remaining - delta)
		velocity = dash_direction * Balance.DASH_SPEED
	else:
		velocity = motion * Balance.PLAYER_SPEED + knockback
	knockback = knockback.move_toward(Vector2.ZERO, Balance.PLAYER_KNOCKBACK_DECAY * delta)
	position += velocity * delta
	position = room.clamp_actor(position, Balance.PLAYER_RADIUS)
	stride += velocity.length() * delta * 0.04
	queue_redraw()

func fire(direction: Vector2) -> bool:
	if Game.run == null or shot_cooldown > 0.0 or direction.is_zero_approx():
		return false
	if not room.fire_from_player(direction.normalized()):
		return false
	shot_cooldown = Balance.SHOT_INTERVAL
	muzzle_flash = 0.07
	return true

func receive_damage(amount: float, origin: Vector2) -> bool:
	if Game.run == null or invulnerable > 0.0 or dash_remaining > 0.0:
		return false
	invulnerable = Balance.HURT_INVULNERABILITY
	hurt_flash = 0.16
	knockback = (position - origin).normalized() * Balance.PLAYER_KNOCKBACK
	room.telemetry["player_hits"] += 1
	room.add_ring(position, Color("e46b69"), 38.0, 0.28)
	Game.damage_player(amount)
	return true

func _draw() -> void:
	var reduced: bool = Game.profile.get("settings", {}).get("reduced_fx", false)
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1, 0.55))
	draw_circle(Vector2.ZERO, 23.0, Color(0.02, 0.04, 0.06, 0.6))
	draw_set_transform(Vector2.ZERO)
	if dash_remaining > 0.0:
		draw_line(-dash_direction * 46.0, Vector2.ZERO, Color(0.4, 0.8, 0.86, 0.35), 24.0, true)
	if invulnerable > 0.0:
		draw_arc(Vector2.ZERO, 25.0, 0, TAU, 24, Color(0.9, 0.75, 0.5, 0.65), 1.5, true)
	if body_texture != null:
		draw_arc(Vector2.ZERO,Balance.PLAYER_RADIUS,0,TAU,24,Color(0.4,0.78,0.84,0.3),1.0,true)
		draw_texture_rect(body_texture,Rect2(-38,-48,76,76),false)
	else:
		_draw_fallback_body()
	# A warm carried lantern anchors the player silhouette against the cool mine.
	var lantern := Vector2(-19, 6)
	if not reduced:
		draw_circle(lantern, 27.0, Color(0.9, 0.66, 0.29, 0.045))
		draw_circle(lantern, 16.0, Color(0.9, 0.66, 0.29, 0.085))
	if body_texture == null:
		draw_rect(Rect2(lantern - Vector2(5, 7), Vector2(10, 15)), Color("815936"))
		draw_rect(Rect2(lantern - Vector2(3, 4), Vector2(6, 9)), Color("f4c979"))
	draw_set_transform(Vector2(2, 1), aim_direction.angle())
	draw_line(Vector2(0,0), Vector2(25,0), Color("253b44"), 9.0)
	draw_line(Vector2(4,0), Vector2(24,0), Color("bd8748"), 5.0)
	draw_rect(Rect2(20, -4, 10, 8), Color("76c5cf"))
	if muzzle_flash > 0.0:
		draw_colored_polygon(PackedVector2Array([Vector2(30,-5),Vector2(42,0),Vector2(30,5)]), Color("fff0b5"))
	draw_set_transform(Vector2.ZERO)
	if hurt_flash > 0.0 and not reduced:
		draw_circle(Vector2(0,-3), 16.0, Color(0.97, 0.7, 0.64, 0.5))

func _draw_fallback_body() -> void:
	var walk: float = sin(stride) * 3.0
	draw_line(Vector2(-7, 8), Vector2(-8 - walk, 18), Color("0a1118"), 7.0, true)
	draw_line(Vector2(7, 8), Vector2(8 + walk, 18), Color("0a1118"), 7.0, true)
	draw_rect(Rect2(-15, -10, 30, 24), Color("0e181e"))
	draw_rect(Rect2(-16, -8, 8, 19), Color("70573e"))
	draw_colored_polygon(PackedVector2Array([Vector2(-11,-9), Vector2(9,-11), Vector2(14,6), Vector2(6,14), Vector2(-13,9)]), Color("71818a"))
	draw_line(Vector2(-10, 4), Vector2(10, 4), Color("c38c4a"), 3.0)
	draw_circle(Vector2(0, -10), 10.0, Color("ab7947"))
	draw_arc(Vector2(0, -10), 10.0, PI, TAU, 12, Color("dfb172"), 2.0, true)
	draw_rect(Rect2(-8, -9, 16, 6), Color("15232b"))
	draw_line(Vector2(-5, -6), Vector2(5, -6), Color("92dce1"), 2.0)
