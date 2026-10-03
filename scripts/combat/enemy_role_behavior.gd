extends RefCounted
## Explicit archive15 species roles only. No inferred weapon/shape roles.
const ACTION_SCALE := 0.85
const RECOVERY_SCALE := 0.8
const EVADE_DISTANCE := 70.0
const EVADE_SECONDS := 0.3
const EVADE_COOLDOWN := 8.0
const NEAR_DISTANCE := 140.0
var cooldown := 0.0
var remaining := 0.0
var direction := Vector2.ZERO
var side := 1.0

static func has_role(profile: Dictionary, role: String) -> bool:
	return int(profile.get("enemy_species_version",0)) == 4 and str(profile.get("primary_role","")) == role and str(profile.get("rank","normal")) != "boss"

static func action_seconds(profile: Dictionary, seconds: float) -> float:
	return seconds * ACTION_SCALE if has_role(profile,"assassin") else seconds

static func recovery_seconds(profile: Dictionary, seconds: float, exposure: float = 0.0) -> float:
	return maxf(exposure,seconds * RECOVERY_SCALE) if has_role(profile,"assassin") else maxf(exposure,seconds)

static func action_command(profile: Dictionary, source: Dictionary) -> Dictionary:
	if not has_role(profile,"assassin") or str(source.get("kind","")) != "charge": return source
	# Only the already-warned body action speeds up. Do not change projectile
	# lifetime, hazard ticks, hit count, distance, endpoint or admission geometry.
	var command := source.duplicate(true)
	if float(command.get("duration",0)) > 0: command["duration"] = float(command.duration) * ACTION_SCALE
	if float(command.get("speed",0)) > 0: command["speed"] = float(command.speed) / ACTION_SCALE
	return command

func reset() -> void:
	cooldown = 0.0
	remaining = 0.0
	direction = Vector2.ZERO
	side = 1.0

func cancel() -> void:
	remaining = 0.0
	direction = Vector2.ZERO

func spend() -> void:
	cancel()
	cooldown = EVADE_COOLDOWN

func available() -> bool:
	return cooldown <= 0.0 and remaining <= 0.0

func tick(actor: Node2D, delta: float, victim: Node2D) -> bool:
	if not has_role(actor.profile,"ranged"): return false
	if actor.is_inside_tree() and actor.get_tree().paused: return remaining > 0
	if delta <= 0 or not is_finite(delta): return remaining > 0
	cooldown = maxf(0.0,cooldown-delta)
	if not actor.is_alive() or actor.static_actor or actor.training_ai_disabled or actor.reaction_remaining > 0 or actor.has_pending_displacement() or actor.knockback.length_squared() > .01 or actor.state in [&"stun",&"stunned",&"frozen"] or bool(actor.get_meta("enemy_frozen",false)):
		cancel()
		return false
	if actor.has_meta("enemy_skill_motion") or actor.state == &"reposition":
		# Existing locomotion uses this same gate; never chain a free dodge.
		cancel()
		return false
	if remaining > 0 and actor.state != &"chase":
		cancel()
		return false
	if remaining <= 0:
		if not available() or actor.state != &"chase" or not is_instance_valid(victim): return false
		if actor.position.distance_to(victim.position) > NEAR_DISTANCE or not actor.room.has_line_of_sight(actor.position,victim.position): return false
		var tangent: Vector2 = actor.position.direction_to(victim.position).orthogonal()
		if tangent.is_zero_approx(): tangent = Vector2.UP
		var chosen := Vector2.ZERO
		for sign_value: float in [side,-side]:
			var candidate: Vector2 = tangent * sign_value
			var endpoint: Vector2 = actor.position + candidate * EVADE_DISTANCE
			# Check the complete swept route; no wall crossing or teleport, and
			# no geometry edits to make a dodge fit. Both sides blocked: stay.
			if actor.room.blocked_fraction(actor.position,endpoint,actor.navigation_radius) < .999: continue
			if actor.room.move_actor(actor.position,candidate*EVADE_DISTANCE,actor.navigation_radius).distance_to(endpoint) > .5: continue
			chosen = candidate
			break
		if chosen.is_zero_approx(): return false
		direction = chosen
		side *= -1
		remaining = EVADE_SECONDS
		cooldown = EVADE_COOLDOWN
	var step := minf(delta,remaining)
	# Spend only real active time, including the final partial frame.
	actor.position = actor.room.move_actor(actor.position,direction * EVADE_DISTANCE * step/EVADE_SECONDS,actor.navigation_radius)
	actor.velocity = Vector2.ZERO
	remaining = maxf(0.0,remaining-step)
	if remaining < .00001: remaining = 0.0
	return true
