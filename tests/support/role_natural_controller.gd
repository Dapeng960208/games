extends "res://tests/support/first_four_natural_controller.gd"
## Uses production requests and visible danger/navigation from the established
## driver. No HP, cooldown, resource, target, damage or completion overrides.
const ROLE_VERSION := "three-role-input-v2"
var coverage: Dictionary = {}
var requested: Array[Dictionary] = []
var passive_death := false
var effects_probe := false

func aim(at: Vector2) -> void:
	var point: Vector2 = room.get_canvas_transform()*room.to_global(at)
	# In a native Window, push_input alone does not move the device-backed
	# pointer read by HeroActor. Warp only this game viewport, using its logical
	# coordinates so native2K/stretch are handled by Godot.
	room.get_viewport().warp_mouse(point)
	super.aim(at)

func attack_target(time: float, target: Node2D, threats: Array[Dictionary], counter: bool) -> void:
	var player: HeroActor = room.player
	if passive_death:
		player.request_move(target.position, false)
		return
	var hero: String = Game.run.hero_id
	var distance := player.position.distance_to(target.position)
	var direction := player.position.direction_to(target.position)
	var desired := 70.0 if hero == "CH01" else 190.0
	var ordered: Array[String] = []
	for slot: String in player.INPUT_SLOTS:
		if not bool(coverage.get(player.skill_id_for_slot(slot), false)):
			ordered.append(slot)
			break # Save native resources for the next unobserved skill.
	if ordered.is_empty():
		for slot: String in PRIORITY: ordered.append(slot)
	for slot: String in ordered:
		var spec: Dictionary = player.skill_definition(slot)
		if player.skill_cooldown(slot) > 0.0 or float(Game.run.resource) < float(spec.cost): continue
		var kind: String = str(spec.get("effect_kind", spec.get("kind", "")))
		if hero == "CH03" and kind in ["guard_burst","moving_pulses","blink_burst"]:
			desired = minf(desired, float(spec.get("radius",100.0))-25.0)
		break
	if not room.has_line_of_sight(player.position,target.position) or distance > desired+8.0:
		navigate_to_reachable(time,target.position,desired,threats)
	elif distance < desired-30.0 and hero != "CH01":
		navigate_to_reachable(time,target.position,desired,threats)
	else: player.clear_movement_target()
	aim_target = weakref(target)
	aim(target.position)
	mode(time,"counter_attack" if counter else "attack",target.position)
	if not direction.is_zero_approx() and absf(player.aim_direction.angle_to(direction)) > .04:
		rejected["pointer_not_settled"] = int(rejected.get("pointer_not_settled",0))+1
		if int(rejected.pointer_not_settled) % 50 == 1:
			print("ROLE_POINTER_DIAGNOSTIC ",JSON.stringify({"actual_aim":str(player.aim_direction),"requested_aim":str(direction),"viewport_mouse":str(room.get_viewport().get_mouse_position()),"ground_mouse":str(room.get_global_mouse_position()),"target":str(target.position),"canvas":str(room.get_canvas_transform())}))
		return
	primary_target = weakref(target)
	if not player.combo_queue.is_empty() or player.dash_remaining > 0.0 or player.abilities.busy(): return
	if hero == "CH02":
		var state: Dictionary = player.class_state_snapshot()
		if bool(state.get("reloading",false)) and bool(state.get("precision_window_active",false)):
			player.request_reload()
		elif not bool(state.get("reloading",false)) and int(state.get("ammo",8)) <= 2:
			player.request_reload()
	for slot: String in ordered:
		var spec: Dictionary = player.skill_definition(slot)
		if not player.skill_is_learned(str(spec.skill_id)) or player.skill_cooldown(slot) > 0.0: continue
		if not skill_reaches(hero,slot,spec,distance,target): continue
		if float(Game.run.resource) < float(spec.cost):
			rejected["resource:"+str(spec.skill_id)] = int(rejected.get("resource:"+str(spec.skill_id),0))+1
			continue
		if str(spec.skill_id) != "CH01_SK10" and not safe_cast_window(threats,float(spec.duration)): continue
		var resource_before: float = float(Game.run.resource)
		if player.request_skill(slot,target.position):
			requested.append({"t":time,"skill_id":str(spec.skill_id),"input_slot":slot,"cast_id":player.abilities.cast_serial,"cost":float(spec.cost),"resource_before":resource_before,"resource_after":float(Game.run.resource),"windup":float(spec.windup),"duration":float(spec.duration),"at":[player.position.x,player.position.y],"target":[target.position.x,target.position.y]})
			return
		rejected[player.last_cast_error] = int(rejected.get(player.last_cast_error,0))+1
	maintain_primary()

func maintain_primary() -> void:
	if passive_death or primary_target == null: return
	var target: Node2D = primary_target.get_ref()
	var player: HeroActor = room.player
	if not is_instance_valid(target) or not target.is_alive() or target.is_queued_for_deletion(): return
	if not player.combo_queue.is_empty() or player.dash_remaining > 0.0 or player.abilities.busy() or player.shot_cooldown > 0.0: return
	if player.position.distance_to(target.position) > player.auto_attack_range()-5.0 or not room.has_line_of_sight(player.position,target.position): return
	var direction := player.position.direction_to(target.position)
	player.request_attack(direction if not direction.is_zero_approx() else player.aim_direction,target)

func skill_reaches(hero: String, _slot: String, spec: Dictionary, distance: float, _target: Node2D = null) -> bool:
	var identity: String = str(spec.skill_id)
	var kind: String = str(spec.get("effect_kind",spec.get("kind","")))
	if kind in ["stone_guard","counter_guard","guard","resonance","tactical_reload","smoke_step"]: return true
	if hero == "CH01":
		var reach: float = float(spec.get("radius",spec.get("range",120.0)))
		if identity == "CH01_SK01": reach += float(spec.get("travel",0.0))
		return distance <= reach-15.0
	if kind in ["guard_burst","moving_pulses","blink_burst"]:
		return distance <= float(spec.get("radius",100.0))-15.0
	return distance <= float(spec.get("range",550.0))-15.0

func step(time: float) -> void:
	if effects_probe and Game.run.hero_id == "CH01" and not bool(coverage.get("CH01_SK10",false)):
		# Legal deliberate tanking: build native rage with basics, then stand
		# still during the one-second stance to receive an actual enemy hit.
		if not room.controls_enabled(): return
		if not room.player.role_kit.export_state().counter.is_empty():
			room.player.clear_movement_target()
			return
		var nearest: Node2D
		for enemy: Node in room.enemies.get_children():
			if enemy is EnemyActor and enemy.is_alive() and enemy.rank == "normal" and enemy.actor_kind != "objective":
				if not is_instance_valid(nearest) or room.player.position.distance_squared_to(enemy.position) < room.player.position.distance_squared_to(nearest.position): nearest = enemy
		if is_instance_valid(nearest): attack_target(time,nearest,visible_threats(),false)
		return
	if not passive_death:
		super.step(time)
		return
	if not room.controls_enabled(): return
	var target: Node2D
	for enemy: Node in room.enemies.get_children():
		if enemy is EnemyActor and enemy.is_alive() and enemy.actor_kind != "objective":
			if not is_instance_valid(target) or room.player.position.distance_squared_to(enemy.position) < room.player.position.distance_squared_to(target.position): target = enemy
	if is_instance_valid(target): room.player.request_move(target.position,false)
