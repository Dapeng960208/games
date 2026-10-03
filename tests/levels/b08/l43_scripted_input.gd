extends RefCounted
## A scripted player, never an enemy/health/clock fixture.
const LIMIT_SECONDS := 35.0
var stage := "vane"
var next_input := 0.0
var next_interact := 0.0
var next_attack := 0.0
var next_skill := 0.0
var requests: Array[Dictionary] = []

func step(room: Node2D, elapsed: float, alive: bool) -> void:
	if not alive or elapsed >= LIMIT_SECONDS or elapsed < next_input or not room.controls_enabled(): return
	next_input = elapsed + .2
	var lane: Dictionary = room.sky_interactions.lane
	if stage == "vane":
		if room.wind.direction(lane.id,lane.direction) != lane.direction or elapsed >= 8:
			stage = "flag"
		else:
			var point: Vector2 = lane.vane + Vector2(0,-14)
			if room.player.position.distance_to(point) > 5: _move(room,point,elapsed)
			if room.player.position.distance_to(lane.vane) <= 50 and room.wind.channel.is_empty() and room.wind.pending.is_empty() and elapsed >= next_interact:
				room.interact()
				next_interact = elapsed + 1.8
				_record(elapsed,"interact",not room.wind.channel.is_empty())
			return
	var target: Node2D
	if stage == "flag":
		if is_instance_valid(room._flag) and room._flag.is_alive() and elapsed < 18: target = room._flag
		else: stage = "fight"
	if stage == "fight":
		var distance := INF
		for actor: Node2D in room.enemies.get_children():
			if actor.static_actor or not actor.is_alive(): continue
			var candidate: float = room.player.position.distance_squared_to(actor.position)
			if candidate < distance: distance = candidate; target = actor
	if not is_instance_valid(target): return
	_aim(room,target.position)
	if room.player.position.distance_to(target.position) > 80:
		var point: Vector2 = target.position + target.position.direction_to(room.player.position)*70
		_move(room,room.clamp_actor(point,18),elapsed)
	if elapsed >= next_attack and room.player.position.distance_to(target.position) <= 100:
		_record(elapsed,"request_attack",room.player.request_attack(room.player.position.direction_to(target.position),target))
		next_attack = elapsed + 1.0
	# Mouse input is consumed next physics frame. Do not cast using stale aim.
	if elapsed >= next_skill and room.player.position.distance_to(target.position) <= 180 and room.player.aim_direction.dot(room.player.position.direction_to(target.position)) > .9:
		_record(elapsed,"request_skill:q",room.player.request_skill("q",target.position))
		next_skill = elapsed + 2.0

func _move(room: Node2D, point: Vector2, elapsed: float) -> void:
	var accepted: bool=room.player.request_move(point,false)
	if not accepted:
		var direction: Vector2=room.navigation_direction(room.player.position,point,18)
		var waypoint: Vector2=room.move_actor(room.player.position,direction*80,18)
		if waypoint.distance_to(room.player.position)>8: accepted=room.player.request_move(waypoint,false)
	_record(elapsed,"request_move",accepted)
func _aim(room: Node2D, at: Vector2) -> void:
	# Use the established viewport input route, so next physics also sees aim.
	var motion:=InputEventMouseMotion.new()
	motion.position=room.get_canvas_transform()*room.to_global(at)
	motion.global_position=motion.position
	room.get_viewport().push_input(motion,true)
func _record(elapsed: float, kind: String, accepted: bool) -> void:
	if requests.size() < 240: requests.append({"wall_seconds":elapsed,"stage":stage,"request":kind,"accepted":accepted})
