extends RefCounted
## Frozen, deterministic input controller. Reads only visible targets/tells and
## current character resources. Executes the same requests as production input.
const VERSION := "s11-controller-v8"
const PRIORITY := ["f", "ultimate", "secondary", "q"] # E, R, W, Q
var room: MineRoom
var next_decision := 0.0
var decisions: Array[Dictionary] = []
var rejected: Dictionary = {}
var last_mode := ""
var aim_target: WeakRef
var primary_target: WeakRef

func configure(value: MineRoom) -> void:
	room = value
	assert(DisplayServer.get_name() != "headless" or room.get_viewport() is SubViewport,"Headless input must use an isolated SubViewport with handle_input_locally=true; root Window may overwrite the virtual pointer")
	next_decision = 0.0
	decisions.clear()
	rejected.clear()
	last_mode = ""
	aim_target = null
	primary_target = null

func step(time: float) -> void:
	# Player physics updates aim from the viewport pointer every frame, and
	# skill windups read that value again. A direct aim assignment at 10 Hz is
	# therefore insufficient and would redirect real releases to a stale cursor.
	if aim_target != null:
		var current: Node2D = aim_target.get_ref()
		if is_instance_valid(current): aim(current.position)
	if not room.controls_enabled() or not room.pointer_controls_enabled():
		primary_target = null
		return
	if time < next_decision:
		maintain_primary()
		return
	next_decision = time + .1
	primary_target = null
	var player: SalvagerPlayer = room.player
	var boss: Node2D = room._boss_actor if is_instance_valid(room._boss_actor) else null
	var threats := visible_threats()
	var danger := danger_at(player.position, threats)
	if danger > 0:
		var escape := safest_destination(threats, boss)
		player.request_move(escape, false)
		# Only locked/current ground danger triggers the legal dash. This may
		# interrupt an in-progress skill; only delivered packets count as damage.
		if imminent_at(player.position, threats) and player.dash_remaining <= 0:
			player.start_dash(player.position.direction_to(escape))
		mode(time,"dodge",escape)
		return
	var counter := counter_target(boss)
	if not counter.is_empty():
		var at: Vector2 = counter.position
		if bool(counter.get("interactive",false)):
			if player.position.distance_to(at) <= 85.0 and room.has_line_of_sight(player.position,at):
				room.interact()
			else: navigate_to_reachable(time,at,65.0,threats)
			mode(time,"counter_interact",at)
			return
		var actor: Node2D = counter.get("actor")
		if is_instance_valid(actor):
			attack_target(time,actor,threats,true)
			return
	var target := boss
	if not is_instance_valid(target):
		for enemy in room.enemies.get_children():
			if enemy is MineEnemy and enemy.is_alive() and not enemy.is_queued_for_deletion() and enemy.actor_kind != "objective":
				if not is_instance_valid(target) or player.position.distance_squared_to(enemy.position) < player.position.distance_squared_to(target.position): target = enemy
	if is_instance_valid(target): attack_target(time,target,threats,false)

func counter_target(boss: Node2D) -> Dictionary:
	if not is_instance_valid(room.objectives) or not is_instance_valid(boss): return {}
	var best: Dictionary = {}
	var nearest := INF
	for item: Dictionary in room.objectives.elements.values():
		if bool(item.get("done",false)) or bool(item.get("destroyed",false)) or not bool(item.get("active",true)): continue
		# Recurring solar devices are required only while the actual Boss guard
		# is active. Other finite arena mechanisms are cleared once naturally.
		if str(item.get("thematic_counter","")) == "solar_conduit" and boss.status.shield() <= 0: continue
		if float(item.get("counter_cooldown",0)) > 0: continue
		var candidate := item.duplicate()
		if bool(item.get("breakable",false)):
			var actor: Node2D = room.objectives.targets.get(str(item.id))
			if not is_instance_valid(actor) or not actor.is_alive(): continue
			candidate["actor"] = actor
		elif not bool(item.get("interactive",false)): continue
		var distance: float = room.player.position.distance_squared_to(item.position)
		if distance < nearest:
			nearest = distance
			best = candidate
	return best

func attack_target(time: float, target: Node2D, threats: Array[Dictionary], counter: bool) -> void:
	var player: SalvagerPlayer = room.player
	var distance := player.position.distance_to(target.position)
	var direction := player.position.direction_to(target.position)
	var hero: String = Game.run.hero_id
	# All ranged builds operate inside ordinary boss threat reach; they close
	# further for E/R only when ready and legal. No permanent safe-edge firing.
	var desired := 72.0 if hero == "CH01" else 230.0
	if hero == "CH03" and not counter:
		for slot: String in PRIORITY:
			var ready := player.skill_definition(slot)
			if Game.run.level < int(ready.unlock) or player.cooldowns[slot] > 0 or float(Game.run.resource) < float(ready.cost): continue
			var reach := float(ready.get("radius",0)) if slot == "f" else float(ready.get("range",ready.get("radius",0)))
			if slot == "f" and distance > reach-12.0 and connected_node_reaches(target):
				desired = distance # The real remote detonation already reaches.
			else:
				desired = minf(115.0 if slot == "f" else desired,reach-20.0)
			break
	if not room.has_line_of_sight(player.position,target.position) or distance > desired+8:
		navigate_to_reachable(time,target.position,desired,threats)
	elif distance < desired-30 and hero != "CH01":
		var away: Vector2 = room.clamp_actor(target.position-direction*desired,Balance.PLAYER_RADIUS)
		if danger_at(away,threats) == 0: navigate_to_reachable(time,target.position,desired,threats)
	else: player.clear_movement_target()
	aim_target = weakref(target)
	aim(target.position)
	mode(time,"counter_attack" if counter else "attack",target.position)
	# The native input/physics path consumes this new pointer before committing
	# a directional action. No direct writes to the player's aim are required.
	if not direction.is_zero_approx() and absf(player.aim_direction.angle_to(direction)) > .04: return
	primary_target = weakref(target)
	if not player.combo_queue.is_empty() or player.dash_remaining > 0: return
	# Wait for a complete active ability. The controller never replaces an
	# unfinished multi-shot cast with a new skill or claims cancelled damage.
	if player.abilities.busy(): return
	if not counter:
		for slot: String in PRIORITY:
			var spec := player.skill_definition(slot)
			if Game.run.level < int(spec.unlock) or player.cooldowns[slot] > 0: continue
			if not skill_reaches(hero,slot,spec,distance,target): continue
			if float(Game.run.resource) < float(spec.cost):
				rejected["resource:"+slot] = int(rejected.get("resource:"+slot,0))+1
				continue
			if not safe_cast_window(threats,float(spec.duration)): continue
			var cast_point := target.position
			if hero == "CH03" and slot == "f" and distance > float(spec.radius)-12.0 and connected_node_reaches(target):
				decisions.append({"t":time,"mode":"remote_node_detonation","destination":[cast_point.x,cast_point.y],"player_target_distance":distance,"body_radius":spec.radius})
			if hero == "CH03" and slot == "secondary":
				var placement := node_placement(target,spec,threats)
				if placement.is_empty():
					rejected["no_safe_node_placement"] = int(rejected.get("no_safe_node_placement",0))+1
					continue
				cast_point = placement.position
				aim(cast_point)
				decisions.append({"t":time,"mode":"node_placement","destination":[cast_point.x,cast_point.y],"target_distance":cast_point.distance_to(target.position),"visible_danger":placement.danger,"observed_velocity":[target.velocity.x,target.velocity.y],"first_shot_prediction":[placement.predicted.x,placement.predicted.y],"prediction_seconds":1.55})
			if player.request_skill(slot,cast_point): return
			rejected[player.last_cast_error] = int(rejected.get(player.last_cast_error,0))+1
	maintain_primary()

func maintain_primary() -> void:
	# Holding primary is polled by production physics, not tactical reaction
	# cadence. Quantizing .418 s G2 and .500 s P5 cooldowns onto 0.1 s decisions
	# would erase the fourth affix's real attack-speed benefit.
	if primary_target == null: return
	var target: Node2D = primary_target.get_ref()
	var player: SalvagerPlayer = room.player
	if not is_instance_valid(target) or not target.is_alive() or target.is_queued_for_deletion(): return
	if not player.combo_queue.is_empty() or player.dash_remaining > 0 or player.abilities.busy() or player.shot_cooldown > 0: return
	if player.position.distance_to(target.position) > player.auto_attack_range()-5 or not room.has_line_of_sight(player.position,target.position): return
	var direction := player.position.direction_to(target.position)
	player.request_attack(direction if not direction.is_zero_approx() else player.aim_direction,target)

func navigate_to_reachable(time: float, at: Vector2, desired: float, threats: Array[Dictionary]) -> bool:
	var player: SalvagerPlayer = room.player
	if player.dash_remaining>0: return false
	var direction := player.position.direction_to(at)
	var preferred := at-direction*desired
	var existing: Vector2 = player.click_navigation.goal
	if player.click_navigation.is_active() and existing.is_finite() and existing.distance_to(at)<=desired+25 and room.has_line_of_sight(existing,at) and danger_at(existing,threats)==0:
		return true
	if room.valid_ground(preferred,Balance.PLAYER_RADIUS) and room.has_line_of_sight(preferred,at) and danger_at(preferred,threats)==0 and player.request_move(preferred,false):
		return true
	rejected["movement_goal_rejected"] = int(rejected.get("movement_goal_rejected",0))+1
	var candidates: Array[Dictionary] = []
	for radius: float in [desired,maxf(35.0,desired*.65),desired*1.25]:
		for index in 16:
			var point := at-direction.rotated(TAU*float(index)/16.0)*radius
			if not room.valid_ground(point,Balance.PLAYER_RADIUS) or not room.has_line_of_sight(point,at) or danger_at(point,threats)>0: continue
			candidates.append({"point":point,"score":player.position.distance_squared_to(point)+pow(radius-desired,2)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return float(a.score)<float(b.score))
	for candidate: Dictionary in candidates:
		if player.request_move(candidate.point,false):
			decisions.append({"t":time,"mode":"visible_approach","destination":[candidate.point.x,candidate.point.y],"target":[at.x,at.y]})
			return true
	# ClickNavigation's visibility graph can reject a goal around a concave
	# painted boundary. Use the production navigation cache for a legal nearby
	# waypoint, then submit that point as a normal movement request.
	var navigation: Vector2 = room.navigation_direction(player.position,at,Balance.PLAYER_RADIUS)
	var waypoint: Vector2 = room.move_actor(player.position,navigation*80.0,Balance.PLAYER_RADIUS)
	if waypoint.distance_to(player.position)>8.0 and danger_at(waypoint,threats)==0 and player.request_move(waypoint,false):
		decisions.append({"t":time,"mode":"navigation_waypoint","destination":[waypoint.x,waypoint.y],"target":[at.x,at.y]})
		return true
	rejected["no_reachable_approach"] = int(rejected.get("no_reachable_approach",0))+1
	return false

func aim(at: Vector2) -> void:
	var point: Vector2 = room.get_canvas_transform()*room.to_global(at)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	room.get_viewport().push_input(motion,true)

func node_placement(target: Node2D, spec: Dictionary, threats: Array[Dictionary]) -> Dictionary:
	# Uniform ground-placement rule for every chapter/rarity. Stay inside the
	# crystal's actual attack range, outside the enemy's body, and away from
	# current visible hazards and the direct enemy-to-player firing line.
	# This uses current geometry only, never future AI choices or hidden state.
	var player: SalvagerPlayer = room.player
	var reach := float(spec.get("radius",160.0))
	var best: Dictionary = {}
	var best_score := INF
	var toward_player := target.position.direction_to(player.position)
	# 0.35 s setup plus the authored 1.2 s first firing wait. This is linear
	# anticipation of currently visible velocity, not access to future AI state.
	var predicted: Vector2 = room.clamp_actor(target.position+target.velocity*1.55,target.navigation_radius)
	for distance: float in [70.0,90.0,110.0]:
		for index in 16:
			var direction := toward_player.rotated(TAU*float(index)/16.0)
			var candidate := target.position+direction*distance
			if candidate.distance_to(player.position) > float(spec.range)-5: continue
			if not room.valid_ground(candidate,14.0) or not room.has_line_of_sight(player.position,candidate) or not room.has_line_of_sight(candidate,target.position): continue
			if distance < float(target.navigation_radius)+16.0: continue
			var danger := danger_at(candidate,threats)
			if danger > 0: continue
			var lateral := Geometry2D.get_closest_point_to_segment(candidate,target.position,player.position).distance_to(candidate)
			var score := candidate.distance_to(predicted)+distance*.1-lateral*.1+candidate.distance_to(player.position)*.03
			if score < best_score:
				best_score=score
				best={"position":candidate,"danger":danger,"predicted":predicted}
	return best

func skill_reaches(hero: String, slot: String, spec: Dictionary, distance: float, target: Node2D = null) -> bool:
	if hero == "CH01":
		return distance <= (float(spec.get("travel",0))+float(spec.get("radius",0))-15 if slot == "q" else float(spec.get("radius",100))-12)
	if hero == "CH03" and slot == "f": return distance <= float(spec.radius)-12 or connected_node_reaches(target)
	return distance <= float(spec.get("range",spec.get("radius",0)))-10

func connected_node_reaches(target: Node2D) -> bool:
	if not is_instance_valid(target): return false
	for node: Node2D in room.player.resonance_nodes():
		if not node.is_active() or node.position.distance_to(room.player.position) > 260.0 or not room.has_line_of_sight(room.player.position,node.position): continue
		var blast_radius := 100.0+20.0*float(node.resonance_charge)
		if node.position.distance_to(target.position) <= blast_radius-12.0 and room.has_line_of_sight(node.position,target.position): return true
	return false

func safe_cast_window(threats: Array[Dictionary], duration: float) -> bool:
	for warning: Dictionary in threats:
		if contains(warning,room.player.position) and float(warning.get("release_in",0)) <= duration+.15: return false
	return true

func visible_threats() -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	for actor in room.enemies.get_children():
		if not actor is MineEnemy or actor.brain == null or not actor.brain.has_method("current_telegraph"): continue
		var warning: Dictionary = actor.brain.current_telegraph()
		if warning.is_empty(): continue
		warning["release_in"] = float(actor.brain.state_time) if actor is MineBoss else float(warning.get("duration",1))*(1.0-float(warning.get("progress",0)))
		warnings.append(warning)
	for hazard: Dictionary in room.enemy_skills.hazards:
		var warning := hazard.duplicate()
		warning["locked"] = true
		warning["release_in"] = 0.0
		warnings.append(warning)
	for projectile: Dictionary in room.enemy_skills.projectiles:
		# Actual visible projectiles, projected only 0.2 seconds ahead.
		var warning := projectile.duplicate()
		warning["shape"] = "circle"
		warning["origin"] = projectile.get("position",projectile.get("origin",Vector2.ZERO))
		warning["radius"] = float(projectile.get("radius",12))+20.0
		warning["locked"] = true
		warning["release_in"] = 0.0
		warnings.append(warning)
	return warnings

func contains(warning: Dictionary, point: Vector2) -> bool:
	if warning.has("paths"):
		for path: Array in warning.paths:
			for index in range(1,path.size()):
				if Geometry2D.get_closest_point_to_segment(point,path[index-1],path[index]).distance_to(point) <= float(warning.get("width",28))*.5+Balance.PLAYER_RADIUS+5: return true
		return false
	if warning.has("targets"):
		for target: Vector2 in warning.targets:
			if target.distance_to(point) <= float(warning.get("radius",60))+Balance.PLAYER_RADIUS+5: return true
		return false
	return room.enemy_skills.shape_contains(warning,point,Balance.PLAYER_RADIUS+5)

func danger_at(point: Vector2, warnings: Array[Dictionary]) -> int:
	var value := 0
	for warning: Dictionary in warnings:
		if contains(warning,point): value += 3 if bool(warning.get("locked",false)) else 1
	return value

func imminent_at(point: Vector2, warnings: Array[Dictionary]) -> bool:
	for warning: Dictionary in warnings:
		if bool(warning.get("locked",false)) and contains(warning,point): return true
	return false

func safest_destination(warnings: Array[Dictionary], boss: Node2D) -> Vector2:
	var from: Vector2 = room.player.position
	var best := from
	var best_score := INF
	for distance: float in [90.0,150.0,230.0]:
		for index in 16:
			var direction := Vector2.from_angle(TAU*float(index)/16.0)
			var candidate: Vector2 = room.move_actor(from,direction*distance,Balance.PLAYER_RADIUS)
			if candidate.distance_to(from) < 20: continue
			var score := float(danger_at(candidate,warnings))*10000.0+candidate.distance_to(from)
			if is_instance_valid(boss): score += absf(candidate.distance_to(boss.position)-(80 if Game.run.hero_id=="CH01" else 230))*.2
			if score < best_score:
				best_score = score
				best = candidate
	return best

func mode(time: float, value: String, destination: Vector2) -> void:
	if value == last_mode: return
	last_mode = value
	decisions.append({"t":time,"mode":value,"destination":[destination.x,destination.y]})
