extends RefCounted
## Initial real combat slice: M01/M02/M03 and the BO08 six gated actions.
## The rest of the catalog stays authored-only and is not silently spawned.
const IMPLEMENTED := ["B08-M01","B08-M02","B08-M03","BO08"]
var profile: Dictionary = {}
var phase := "emerging"
var remaining := 0.8
var cooldown := 0.0
var action: Dictionary = {}
var cycle := 0
var weak_until := 0.0
var clock := 0.0
var escorts := 0
var transit := false
var transit_time := 0.0
var _counter := false
var _patrol_points: Array = []
var _patrol_index := 0

func configure(value: Dictionary) -> void: profile = value.duplicate(true)
func on_damaged(_actor: Node2D, _context: Dictionary) -> void: pass
func current_telegraph() -> Dictionary: return {} # B08 renderer reads exact frozen action below.
func interrupt(actor: Node2D) -> void:
	actor.room.release_warning(str(actor.get_instance_id()))
	actor.room.wind.release_dive(str(actor.get_instance_id()))
	phase = "recovery"
	remaining = 1.1
	action.clear()
	transit = false

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	clock += delta
	cooldown = maxf(0,cooldown-delta)
	remaining = maxf(0,remaining-delta)
	actor.velocity = Vector2.ZERO
	if not is_instance_valid(victim) or (victim==actor.room.player and (Game.run==null or Game.run.hp<=0)) or (victim!=actor.room.player and not victim.is_alive()): interrupt(actor); return
	if phase in ["emerging","recovery"]:
		if remaining <= 0: phase = "chase"
	elif phase == "chase":
		var distance: float = actor.position.distance_to(victim.position)
		if cooldown>0 or distance>330 or not actor.room.on_screen(actor.position) or not actor.room.has_line_of_sight(actor.position,victim.position):
			if distance>85: actor.velocity = actor.room.navigation_direction(actor.position,victim.position,actor.navigation_radius)*actor.move_speed
		else: _begin(actor,victim)
	elif phase == "warning":
		if actor.position.distance_to(action.origin)>30: interrupt(actor)
		elif remaining<=0: _release(actor)
	elif phase == "transit":
		transit_time += delta
		var target: Vector2 = action.target
		var distance: float = actor.position.distance_to(target)
		if distance<=12:
			_land(actor)
		elif transit_time>=3.0:
			interrupt(actor)
		else:
			actor.velocity = actor.room.navigation_direction(actor.position,target,actor.navigation_radius)*420.0
	elif phase == "patrol_wait":
		if remaining<=0:
			action.target = _patrol_points[_patrol_index]
			_start_transit()
	actor.state = StringName(phase)
	actor.aim_direction = actor.position.direction_to(action.get("target",victim.position))

func _begin(actor: Node2D, victim: Node2D) -> void:
	var id := str(profile.enemy_id)
	var kind := "arrow" if id=="B08-M01" else "dive" if id=="B08-M02" else "flank"
	var boss := id=="BO08"
	var ratio: float = actor.health.current/actor.health.maximum
	if boss:
		var available: Array = ["thrust","dive"]
		if int(profile.difficulty)>=1 and ratio<=0.70: available.append("sweep")
		if int(profile.difficulty)>=2: available.append("fan")
		if int(profile.difficulty)>=3 and escorts<2: available.append("escort")
		if int(profile.difficulty)>=4: available.append("patrol")
		kind = ["dive","fan","return"][cycle%3] if ratio<=0.35 and int(profile.difficulty)>=2 else available[cycle%available.size()]
	var owner := str(actor.get_instance_id())
	if not actor.room.admit_warning(owner): return
	if kind in ["dive","patrol"] and not actor.room.wind.admit_dive(owner):
		actor.room.release_warning(owner)
		return
	var target: Vector2 = actor.room.clamp_actor(victim.position,actor.navigation_radius)
	if kind=="flank": target = actor.room.clamp_actor(victim.position+actor.position.direction_to(victim.position).orthogonal()*120,actor.navigation_radius)
	if kind=="return": target = actor.room.clamp_actor(Vector2(1400,780)*0.58,actor.navigation_radius)
	var tell := 1.4 if boss and kind=="dive" else 1.6 if kind=="patrol" else 1.3 if kind in ["fan","escort"] else 1.1 if kind in ["thrust","dive"] else .9
	action = {"kind":kind,"origin":actor.position,"target":target,"radius":95.0 if boss else 75.0,"coefficient":1.2 if boss else 1.15,"duration":tell,"damage_factor":1.0}
	if kind=="patrol":
		_patrol_points = [target,actor.room.clamp_actor(target+Vector2(180,100),actor.navigation_radius),actor.room.clamp_actor(target+Vector2(-140,160),actor.navigation_radius)]
		_patrol_index = 0
		action["points"] = _patrol_points.duplicate()
	phase = "warning"
	remaining = tell
	cycle += 1

func _release(actor: Node2D) -> void:
	var kind := str(action.kind)
	var active_damage := kind not in ["escort","return"]
	action.damage_factor = actor.room.wind.consume_tailwind(str(actor.get_instance_id()),true,active_damage)
	cooldown = {"arrow":7.0,"dive":11.0 if profile.enemy_id=="BO08" else 9.0,"flank":7.0,"thrust":7.0,"sweep":15.0,"fan":17.0,"escort":20.0,"patrol":24.0,"return":3.0}[kind]
	if kind in ["dive","flank","patrol","return"]:
		_counter = profile.enemy_id=="BO08" and kind in ["dive","patrol"] and actor.room.wind.consume_boss_counter()
		_start_transit()
		return
	actor.room.release_warning(str(actor.get_instance_id()))
	if kind=="arrow": actor.room.fire_feather(actor,action,1.0,320)
	elif kind=="thrust": actor.room.hit_line(actor,action,1.15,230,42)
	elif kind=="sweep": actor.room.hit_line(actor,action,.75,440,90,50)
	elif kind=="fan": actor.room.fire_fan(actor,action)
	elif kind=="escort":
		actor.room.spawn_escorts(actor)
		escorts += 1
	phase = "recovery"
	remaining = 1.3

func _start_transit() -> void:
	phase = "transit"
	transit = true
	transit_time = 0

func _land(actor: Node2D) -> void:
	var kind := str(action.kind)
	# Landing uses the actual clipped footpoint, matching shadow and hit proxy.
	var landed: Dictionary = action.duplicate(true)
	landed.target = actor.position
	var lane: Dictionary = actor.room.lane_at(actor.position)
	if not lane.is_empty(): actor.room.wind.grant_tailwind(str(actor.get_instance_id()),lane.id,true,actor.position.distance_to(action.origin))
	# The scout's separate post-reposition stab is its next active damage event.
	if kind=="flank":
		landed.damage_factor = actor.room.wind.consume_tailwind(str(actor.get_instance_id()),true,true)
		actor.room.hit_circle(actor,landed,.85,85)
	elif kind in ["dive","patrol"]: actor.room.hit_circle(actor,landed,.65 if kind=="patrol" else float(action.coefficient),float(action.radius))
	transit = false
	if kind=="patrol" and _patrol_index<2:
		_patrol_index += 1
		phase = "patrol_wait"
		remaining = 1.1
		return
	actor.room.release_warning(str(actor.get_instance_id()))
	actor.room.wind.release_dive(str(actor.get_instance_id()))
	phase = "recovery"
	remaining = 2.2 if kind=="patrol" else 1.5 if profile.enemy_id=="BO08" else 1.1
	if _counter:
		remaining += 1.5
		weak_until = clock+4
		_counter = false
