extends RefCounted
## Initial real combat slice: M01–M06 and the BO08 six gated actions.
## The rest of the catalog stays authored-only and is not silently spawned.
const IMPLEMENTED := ["B08-M01","B08-M02","B08-M03","B08-M04","B08-M05","B08-M06","BO08"]
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
var _basic_cooldown := 0.0

func configure(value: Dictionary) -> void: profile = value.duplicate(true)
func on_damaged(actor: Node2D, context: Dictionary) -> void:
	if profile.enemy_id=="B08-M04" and phase=="warning" and action.get("kind")=="support" and float(context.get("damage",0))>0 and not bool(context.get("dot",false)):
		cooldown = maxf(cooldown,5.5)
		interrupt(actor)
func current_telegraph() -> Dictionary: return {} # B08 renderer reads exact frozen action below.
func on_displacement_committed(actor: Node2D, projected: Vector2) -> void:
	if not actor.is_alive() or not projected.is_finite() or action.is_empty(): return
	# Actor calls this before integrating the accepted push. Keep the existing
	# 30-unit standing tolerance, but stop active travel before its old landing
	# can resolve. Fully wall-blocked pushes never reach this callback.
	var broken_stance: bool=phase=="warning" and projected.distance_to(action.origin)>30
	var broken_travel: bool=phase=="transit" and projected.distance_squared_to(actor.position)>.0001
	if broken_stance or broken_travel:
		interrupt(actor)
		actor.state=StringName(phase)
func interrupt(actor: Node2D) -> void:
	if action.get("kind")=="chime": actor.room.harbor.cancel_chime(actor)
	actor.room.release_warning(str(actor.get_instance_id()))
	actor.room.wind.release_dive(str(actor.get_instance_id()))
	actor.room.harbor.end_reposition(actor,0,false)
	phase = "recovery"
	remaining = 1.1
	action.clear()
	transit = false

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	clock += delta
	cooldown = maxf(0,cooldown-delta)
	_basic_cooldown = maxf(0,_basic_cooldown-delta)
	remaining = maxf(0,remaining-delta)
	actor.velocity = Vector2.ZERO
	if not is_instance_valid(victim) or (victim==actor.room.player and (Game.run==null or Game.run.hp<=0)) or (victim!=actor.room.player and not victim.is_alive()): interrupt(actor); return
	if phase in ["emerging","recovery"]:
		if remaining <= 0: phase = "chase"
	elif phase == "chase":
		var distance: float = actor.position.distance_to(victim.position)
		if (cooldown>0 and (profile.enemy_id!="B08-M04" or _basic_cooldown>0)) or distance>330 or not actor.room.on_screen(actor.position) or not actor.room.has_line_of_sight(actor.position,victim.position):
			if distance>85: actor.velocity = actor.room.navigation_direction(actor.position,victim.position,actor.navigation_radius)*actor.move_speed
		else: _begin(actor,victim)
	elif phase == "warning":
		if action.get("kind")=="chime" and (action.get("bell")==null or not is_instance_valid(action.bell.get_ref()) or not action.bell.get_ref().is_alive()):
			cooldown = maxf(cooldown,4.0)
			interrupt(actor)
		elif actor.position.distance_to(action.origin)>30: interrupt(actor)
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
			actor.velocity = actor.room.navigation_direction(actor.position,target,actor.navigation_radius)*(150.0 if action.kind=="shield" else 420.0)*actor.room.harbor.reposition_multiplier(actor)
	elif phase == "patrol_wait":
		if remaining<=0:
			action.target = _patrol_points[_patrol_index]
			_start_transit()
	actor.state = StringName(phase)
	actor.aim_direction = actor.position.direction_to(action.get("target",victim.position))

func _begin(actor: Node2D, victim: Node2D) -> void:
	var id := str(profile.enemy_id)
	var kind: String = {"B08-M01":"arrow","B08-M02":"dive","B08-M03":"flank","B08-M04":"support","B08-M05":"shield","B08-M06":"chime"}.get(id,"thrust")
	var recipient: Node2D
	if kind=="support":
		recipient = actor.room.harbor.choose_support(actor)
		if cooldown>0 or recipient==null: kind="staff_bolt"
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
	if kind=="support": target = recipient.position
	if kind=="shield": target = actor.room.move_actor(actor.position,actor.position.direction_to(victim.position)*100,actor.navigation_radius)
	if kind=="return": target = actor.room.clamp_actor(Vector2(1400,780)*0.58,actor.navigation_radius)
	var tell := 1.1 if kind=="support" else 1.0 if kind in ["shield","chime"] else .65 if kind=="staff_bolt" else 1.4 if boss and kind=="dive" else 1.6 if kind=="patrol" else 1.3 if kind in ["fan","escort"] else 1.1 if kind in ["thrust","dive"] else .9
	action = {"kind":kind,"origin":actor.position,"target":target,"radius":95.0 if boss else 75.0,"coefficient":1.2 if boss else 1.15,"duration":tell,"damage_factor":1.0}
	if kind=="support": action["recipient"] = weakref(recipient)
	if kind=="chime":
		action["radius"] = 80.0
		action["bell"] = actor.room.harbor.spawn_chime(actor,action)
		if action.bell==null: actor.room.release_warning(owner); action.clear(); return
	if kind=="patrol":
		_patrol_points = [target,actor.room.clamp_actor(target+Vector2(180,100),actor.navigation_radius),actor.room.clamp_actor(target+Vector2(-140,160),actor.navigation_radius)]
		_patrol_index = 0
		action["points"] = _patrol_points.duplicate()
	phase = "warning"
	remaining = tell
	cycle += 1

func _release(actor: Node2D) -> void:
	var kind := str(action.kind)
	var active_damage := kind not in ["escort","return","support","staff_bolt"]
	action.damage_factor = actor.room.wind.consume_tailwind(str(actor.get_instance_id()),true,active_damage)
	if kind=="staff_bolt": _basic_cooldown = float(profile.recovery_seconds)
	else: cooldown = {"support":11.0,"shield":10.0,"chime":8.0,"arrow":7.0,"dive":11.0 if profile.enemy_id=="BO08" else 9.0,"flank":7.0,"thrust":7.0,"sweep":15.0,"fan":17.0,"escort":20.0,"patrol":24.0,"return":3.0}[kind]
	if kind in ["dive","flank","patrol","return","shield"]:
		_counter = profile.enemy_id=="BO08" and kind in ["dive","patrol"] and actor.room.wind.consume_boss_counter()
		actor.room.harbor.begin_reposition(actor)
		_start_transit()
		return
	if kind!="chime": actor.room.release_warning(str(actor.get_instance_id()))
	if kind=="support": actor.room.harbor.grant_support(actor,action.recipient.get_ref())
	elif kind=="chime": actor.room.harbor.release_chime(actor,action)
	elif kind=="staff_bolt":
		action["basic"] = true
		actor.room.fire_feather(actor,action,1.0,200)
	elif kind=="arrow": actor.room.fire_feather(actor,action,1.0,320)
	elif kind=="thrust": actor.room.hit_line(actor,action,1.15,230,42)
	elif kind=="sweep": actor.room.hit_line(actor,action,.75,440,90,50)
	elif kind=="fan": actor.room.fire_fan(actor,action)
	elif kind=="escort":
		actor.room.spawn_escorts(actor)
		escorts += 1
	phase = "recovery"
	remaining = 1.5 if kind=="support" and int(profile.difficulty)>=4 else 1.3

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
	actor.room.harbor.end_reposition(actor,actor.position.distance_to(action.origin),true)
	if kind=="shield":
		landed.origin = actor.position
		landed.target = actor.position+Vector2(action.target-action.origin).normalized()*100
		landed.damage_factor = float(action.damage_factor)*actor.room.wind.consume_tailwind(str(actor.get_instance_id()),true,true)
		actor.room.hit_line(actor,landed,1.0,100,65)
		if int(profile.difficulty)>=2:
			var follow := landed.duplicate(true)
			follow.damage_factor = 1.0 # D4 boon belongs only to the shield strike.
			actor.room.hit_fan(actor,follow,.35,100,55.0)
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
