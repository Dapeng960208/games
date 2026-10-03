extends "res://tests/support/s11_battle_controller.gd"
## Separate synthetic observation policy; never used for calibrated battle TTK.
const DIRECTED_VERSION := "s11-directed-controller-v5"
const DANGEROUS := {"BO01":"eclipse_ring","BO02":"wing_storm","BO03":"grave_burst","BO04":"seismic_crown"}
var experiment := "phase_coverage"
var phase_started: Dictionary = {}
var phase_releases: Dictionary = {}
var previous_counts: Dictionary = {}
var intended_impacts: Array[Dictionary] = []
var coverage_phase := 0
var coverage_complete := false

func step(time: float) -> void:
	var boss: BossActor = room._boss_actor
	if not is_instance_valid(boss): return
	var phase := str(boss.boss_brain.phase)
	if not phase_started.has(phase):
		phase_started[phase]=time
		phase_releases[phase]={}
	var counts: Dictionary = boss.boss_brain.tactical_snapshot().actions_used
	for action: String in counts:
		if int(counts[action])>int(previous_counts.get(action,0)):
			phase_releases[phase][action]=int(phase_releases[phase].get(action,0))+int(counts[action])-int(previous_counts.get(action,0))
	previous_counts=counts.duplicate(true)
	if experiment=="phase_coverage" and coverage_phase>0 and boss.boss_brain.phase==coverage_phase and missing_actions(boss).is_empty():
		coverage_complete=true
		return
	if experiment=="p3_tolerance" and approach_intended_warning(time,boss): return
	super.step(time)

func counter_target(boss: Node2D) -> Dictionary:
	if experiment=="phase_coverage" and coverage_phase>0:
		# Observe finite summon/revival mechanics through actual add deaths.
		# Only primary attacks are used on these live targets; no synthetic
		# corpse registration, added spawn, phase write or direct damage.
		var nearest: EnemyActor
		for actor: Node in room.enemies.get_children():
			if not actor is EnemyActor or actor is BossActor or actor.actor_kind!="enemy" or not actor.is_alive() or actor.is_queued_for_deletion(): continue
			if not is_instance_valid(nearest) or room.player.position.distance_squared_to(actor.position)<room.player.position.distance_squared_to(nearest.position): nearest=actor
		if is_instance_valid(nearest): return {"actor":nearest,"position":nearest.position,"directed_live_add":true}
	# A separately initialized phase sample leaves finite counters available so
	# their suppressible native abilities can actually release. Standard fights
	# retain normal counterplay and its independent actual event evidence.
	return {} if experiment=="p3_tolerance" or coverage_phase>0 else super.counter_target(boss)

func attack_target(time: float, target: Node2D, threats: Array[Dictionary], counter: bool) -> void:
	if counter and experiment!="p3_tolerance":
		super.attack_target(time,target,threats,counter)
		return
	var boss: BossActor = room._boss_actor
	var hold := experiment=="p3_tolerance" or coverage_phase>0
	if not hold:
		var phase := str(boss.boss_brain.phase)
		var missing := missing_actions(boss)
		hold=not missing.is_empty() and time-float(phase_started.get(phase,time))<75.0
	if not hold:
		super.attack_target(time,target,threats,counter)
		return
	primary_target=null
	aim_target=weakref(target)
	aim(target.position)
	# Uniform visible-range cycle exposes close/ranged actions without altering
	# AI weights, cooldowns or target selection. Offense alone is withheld.
	var ranges := [110.0,230.0,350.0]
	var desired: float = ranges[int(time/8.0)%ranges.size()]
	if absf(room.player.position.distance_to(target.position)-desired)>20:
		navigate_to_reachable(time,target.position,desired,threats)
	else: room.player.clear_movement_target()
	mode(time,"directed_hold_offense",target.position)

func missing_actions(boss: BossActor) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = phase_releases.get(str(boss.boss_brain.phase),{})
	for action: String in boss.boss_brain.available_actions():
		if not seen.has(action): result.append(action)
	return result

func approach_intended_warning(time: float,boss: BossActor) -> bool:
	var warning: Dictionary = boss.boss_brain.current_telegraph()
	if warning.is_empty() or str(warning.get("action_id",""))!=DANGEROUS[boss.boss_id] or boss.boss_brain.phase!=3: return false
	primary_target=null
	aim_target=weakref(boss)
	var player: SalvagerPlayer = room.player
	if intended_contains(warning,player.position):
		player.clear_movement_target()
		mode(time,"directed_accept_warning",player.position)
		intended_impacts.append({"t":time,"action":warning.action_id,"locked":warning.get("locked",false),"hp":Game.run.hp,"shield":Game.run.shield,"position":[player.position.x,player.position.y]})
		return true
	var origin: Vector2 = warning.get("origin",boss.position)
	var points: Array[Vector2] = []
	if warning.has("targets"):
		for point: Vector2 in warning.targets: points.append(point)
	for radius: float in [80.0,180.0,280.0,360.0,450.0]:
		for i in 32: points.append(origin+Vector2.from_angle(TAU*float(i)/32.0)*radius)
	points.sort_custom(func(a: Vector2,b: Vector2)->bool: return player.position.distance_squared_to(a)<player.position.distance_squared_to(b))
	for point: Vector2 in points:
		if room.valid_ground(point,Balance.PLAYER_RADIUS) and intended_contains(warning,point) and player.request_move(point,false):
			mode(time,"directed_approach_warning",point)
			return true
	return false

func intended_contains(warning: Dictionary, point: Vector2) -> bool:
	if warning.has("targets"):
		for target: Vector2 in warning.targets:
			if target.distance_to(point)<float(warning.get("radius",60))-5.0: return true
		return false
	return room.enemy_skills.shape_contains(warning,point,0.0)
