extends RefCounted
## Encounters behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func spawn_enemy(at: Vector2, id: String = "", level: int = 1, options: Dictionary = {}) -> EnemyActor:
	if host._living_enemy_count() >= Balance.MAX_ENEMIES:
		return null
	var resolved: Dictionary = {}
	if not id.is_empty():
		resolved = options.get("profile", host.EnemyProfilesScript.resolve(id, level, str(options.get("rank","normal")), host.enemy_ruleset(), host.difficulty, host.enemy_calibration())).duplicate(true)
		if resolved.is_empty():
			return null
	elif options.has("profile"):
		resolved = options.profile.duplicate(true)
	elif host.enemy_ruleset() == host.Numerical.V2:
		# The original M1/trial waves have no authored identity. Use the first
		# published prototype so an enabled V2 player never faces legacy units.
		resolved = host.EnemyProfilesScript.resolve("M01",maxi(1,host.EnemyProfilesScript.encounter_level(host.layout_id,0,host.difficulty,2)),"normal",2,host.difficulty,host.enemy_calibration())
	# All ordinary spawn paths share the room difficulty, including objective
	# adds and boss reinforcements. Encounter plans have already applied this;
	# the preserved base prevents compounding their bonuses on spawn.
	if host.enemy_ruleset() == host.Numerical.V2:
		if not str(resolved.get("enemy_id", "")).is_empty() and (int(resolved.get("ruleset_version", 1)) == 1 or resolved.has("numerical_legacy_base")):
			resolved["enemy_calibration_snapshot"] = host.enemy_calibration()
			resolved = host.EnemyNumericalV2Script.ordinary_profile(resolved, host.difficulty)
			if resolved.is_empty(): return null
	else:
		resolved = host.EnemyDifficultyScript.apply(resolved, host.difficulty)
	var zone: int = int(options.get("zone_index", resolved.get("zone_index", -1)))
	if zone >= 0 and host._zone_actor_count(zone) >= 6:
		return null
	var enemy: EnemyActor = host.EnemyScene.instantiate()
	enemy.room = host
	if bool(host.layout.get("b07_candidate",false)) or (bool(host.layout.get("b06_candidate",false)) and not bool(host.expedition_context.get("b06_progression",false))):
		options = options.duplicate(true)
		options["reward_enabled"] = false
	enemy.configure(resolved, options)
	var radius: float = enemy.navigation_radius
	enemy.position = host.clamp_actor(at, radius)
	if not host.valid_ground(enemy.position, radius):
		for step in range(1, 40):
			var found: bool = false
			for side in range(12):
				var candidate: Vector2 = at + Vector2.RIGHT.rotated(side * TAU / 12.0) * step * 12.0
				if host.valid_ground(candidate, radius):
					enemy.position = candidate
					found = true
					break
			if found:
				break
	if not host.valid_ground(enemy.position, radius):
		enemy.free()
		return null
	if enemy.reward_enabled and enemy.reward_spawn_id.is_empty():
		enemy.reward_spawn_id = "natural:" + str(host._natural_spawn_serial)
		host._natural_spawn_serial += 1
	host._assign_enemy_appearance(enemy)
	host.enemies.add_child(enemy)
	if is_instance_valid(host.b06_mechanics) and enemy.enemy_id.begins_with("B06-M"):
		var stable_id: String = enemy.reward_spawn_id
		if stable_id.is_empty():
			stable_id = "b06:spawn:"+str(host._natural_spawn_serial)
			host._natural_spawn_serial += 1
		host.b06_mechanics.register_actor(stable_id,enemy)
	if is_instance_valid(host.b05_mechanics) and enemy.enemy_id.begins_with("B05-M"):
		var stable_id: String = enemy.reward_spawn_id
		if stable_id.is_empty():
			stable_id = "b05:spawn:"+str(host._natural_spawn_serial)
			host._natural_spawn_serial += 1
		host.b05_mechanics.register_plant(stable_id,enemy)
	enemy.z_index = 0
	return enemy

func spawn_enemy_summon(caster: Node2D, id: String, at: Vector2) -> EnemyActor:
	if not is_instance_valid(caster) or not caster.is_alive():
		return null
	var children: int = 0
	for actor in host.enemies.get_children():
		if actor.owner_enemy != null and actor.owner_enemy.get_ref() == caster and actor.actor_kind == "enemy" and actor.is_alive() and not actor.is_queued_for_deletion():
			children += 1
	if children >= 2:
		return null
	var resolved: Dictionary = preload("res://scripts/levels/b06/combat/enemy_skills.gd").profile(id,caster.enemy_level,host.difficulty,"normal",host.enemy_calibration()) if bool(host.layout.get("b06_candidate",false)) and id.begins_with("B06-M") else host.EnemyProfilesScript.resolve(id, caster.enemy_level, "normal", host.enemy_ruleset(), host.difficulty, host.enemy_calibration())
	if host.enemy_ruleset() != host.Numerical.V2: resolved = host.EnemyDifficultyScript.apply(resolved, host.difficulty)
	if resolved.is_empty():
		return null
	var budget: float = float(caster.profile.get("encounter_budget",18.0))
	if not host._can_allocate_enemy_child(caster,float(resolved.effective_threat_cost),budget,true):
		return null
	return host.spawn_enemy(at,id,caster.enemy_level,{"owner":caster,"reward_enabled":false,"zone_index":caster.zone_index,"profile":resolved})

func spawn_enemy_skill_anchor(caster: Node2D, at: Vector2, health_amount: float, anchor_kind: String = "") -> EnemyActor:
	if not is_instance_valid(caster) or not caster.is_alive() or not host.valid_ground(at,10.0):
		return null
	if not host._can_allocate_enemy_child(caster,1.0,float(caster.profile.get("encounter_budget",18.0)),anchor_kind == "summon_pod"):
		return null
	var anchor_version: int = int(caster.profile.get("ruleset_version", host.Numerical.LEGACY))
	var anchor_profile: Dictionary = {"ruleset_version":anchor_version, "max_hp":host.Numerical.amount(maxf(host.Numerical.scale(1.0, anchor_version),health_amount), anchor_version),"navigation_radius":10.0,"effective_threat_cost":1.0}
	var anchor: EnemyActor = host.spawn_enemy(at,"",1,{"profile":anchor_profile,"owner":caster,"reward_enabled":false,"zone_index":caster.zone_index,"actor_kind":"hazard_endpoint","static_actor":true})
	if is_instance_valid(anchor):
		anchor.set_meta("enemy_skill_anchor_kind",anchor_kind)
	return anchor

func _spawn_wave() -> void:
	host.wave += 1
	var entrances = [Vector2(1150,190),Vector2(1145,510),Vector2(760,540),Vector2(680,145)]
	for i in range(mini(Balance.WAVE_BASE_COUNT + host.wave / Balance.WAVE_GROWTH_EVERY, Balance.WAVE_MAX_COUNT)):
		var at: Vector2 = entrances[(host.wave + i) % entrances.size()] + Vector2(i * 30,0)
		if at.distance_to(host.player.position) < Balance.ENEMY_SPAWN_SAFE_DISTANCE:
			at = Vector2(1150,360) if host.player.position.x < 650 else Vector2(400,500)
		host.spawn_enemy(at)

func enemy_died(enemy: EnemyActor) -> void:
	if is_instance_valid(host.objectives) and host.objectives.has_method("notify_enemy_death"):
		host.objectives.notify_enemy_death(enemy)
	if enemy.owner_enemy != null:
		var summoner: Object = enemy.owner_enemy.get_ref()
		if is_instance_valid(summoner) and summoner.has_method("notify_reinforcement_death"):
			summoner.notify_reinforcement_death(enemy)
	# Capture before loot return/cancellation can change the last visible body.
	# The detached snapshot has no collision; death and rewards stay immediate.
	if Game.run != null and is_instance_valid(host.defeat_feedback) and host.defeat_feedback.capture(enemy, host.global_transform.basis_xform(enemy.last_damage_direction)):
		if is_instance_valid(host.combat_audio): host.combat_audio.defeat(enemy.impact_material())
	if is_instance_valid(host.enemy_props):
		host.enemy_props.return_stolen(enemy)
	if is_instance_valid(host.enemy_skills):
		host.enemy_skills.cancel_owner(enemy)
	for child in host.enemies.get_children():
		if child.owner_enemy != null and child.owner_enemy.get_ref() == enemy:
			child.queue_free()
	if Game.run == null:
		return
	if not enemy.reward_enabled:
		return
	host.enemy_corpses.append({"at":enemy.position,"remaining":18.0,"zone":enemy.zone_index})
	if host.enemy_corpses.size() > 48:
		host.enemy_corpses.pop_front()
	if Game.run.ruleset_version() == 2 and not host.expedition_context.is_empty():
		Game.queue_expedition_kill_reward(enemy.reward_spawn_id, enemy.enemy_id, enemy.rank == "elite", false, clampi(enemy.zone_index, 0, 2))
	host.telemetry["kills"] += 1
	Game.record_kill()
	var context: Dictionary = enemy.last_damage_context.duplicate()
	context["target"] = enemy
	if not context.has("attack_id"):
		context["attack_id"] = "death:" + str(enemy.get_instance_id())
		context["root_event_id"] = context.attack_id
	if host.Numerical.is_v2(Game.run.stats) and bool(enemy.last_damage_result.get("confirmed", false)):
		# Death callbacks run inside the receiver. Preserve native/relic priority
		# before kill equipment uses this confirmed root's shared packet budget.
		host._commit_numerical_native(context)
	host.player.loadout.event("kill", context)
	var amount: int = Balance.GOLD_PER_ENEMY
	if not host.expedition_context.is_empty():
		amount = mini(2,maxi(0,36-host._node_loot_spawned))
		host._node_loot_spawned += amount
	if amount > 0: host.gold_drops.append({"at":enemy.position,"amount":amount,"age":0.0})
	if enemy.rank == "boss": host.add_ring(enemy.position, Color("e6aa4a"), 35.0, 0.35)

func _living_enemy_count() -> int:
	var count: int = 0
	for enemy in host.enemies.get_children():
		if enemy.actor_kind != "objective" and enemy.is_alive() and not enemy.is_queued_for_deletion():
			count += 1
	return count

func _encounters_exhausted() -> bool:
	if host.activated_encounters.size() != host.encounter_zones.size():
		return false
	for index in host.encounter_progress:
		var progress: Dictionary = host.encounter_progress[index]
		if int(progress.next_wave) < progress.plan.waves.size():
			return false
	return true

func _encounter_plan(index: int) -> Dictionary:
	if bool(host.layout.get("b07_candidate",false)): return preload("res://scripts/levels/b07/world/candidate.gd").encounter_plan(host.layout_id,index,host.difficulty,host.enemy_calibration())
	if bool(host.layout.get("b06_candidate",false)): return preload("res://scripts/levels/b06/world/candidate.gd").encounter_plan(host.layout_id,index,host.difficulty)
	return host.EnemyProfilesScript.encounter_plan(host.layout_id,index,host.difficulty,host.enemy_ruleset(),host.enemy_calibration())

func _spawn_encounter_wave(index: int, definitions: Array) -> bool:
	if host._encounter_spawn_retry.has(index):
		return false
	var zone: Dictionary = host.encounter_zones[index]
	var spawns: Array = zone.get("spawn_points",[])
	var directive: Dictionary = host.objectives.encounter_directive(index) if is_instance_valid(host.objectives) else {}
	var escorted_spawns: Array[Vector2] = []
	if not directive.is_empty():
		escorted_spawns = host._escort_spawn_candidates(directive, definitions)
	var planned: Array[Vector2] = []
	var planned_radii: Array[float] = []
	var accepted: Array[EnemyActor] = []
	for spawn_index in definitions.size():
		var definition: Dictionary = definitions[spawn_index]
		var at: Vector2 = spawns[spawn_index%spawns.size()] if not spawns.is_empty() else zone.center
		var radius: float = float(definition.navigation_radius)
		var safe_distance: float = float(zone.get("minimum_player_spawn_distance",360.0))
		var valid: bool = host._encounter_spawn_clear(at,radius,safe_distance,planned,planned_radii)
		if not directive.is_empty():
			# Prefer connected ground along the remaining escort leg, while keeping
			# the same minimum distance and collision/spacing checks as every wave.
			for candidate: Vector2 in escorted_spawns:
				var spread: bool = true
				for previous: Vector2 in planned:
					if previous.distance_to(candidate) < float(zone.get("radius",300.0))*.5:
						spread = false
						break
				if not spread:
					continue
				if host._encounter_spawn_clear(candidate,radius,safe_distance,planned,planned_radii):
					at = candidate
					valid = true
					break
		if not valid:
			valid = false
			for ring in range(4):
				for turn in range(48):
					var candidate: Vector2 = host.player.position+Vector2.RIGHT.rotated(turn*TAU/48.0)*(safe_distance+ring*55.0)
					if host._encounter_spawn_clear(candidate,radius,safe_distance,planned,planned_radii):
						at = candidate
						valid = true
						break
				if valid:
					break
		if not valid:
			host._encounter_spawn_retry[index] = {"remaining":0.25,"geometry":hash(host.obstructions)}
			return false
		planned.append(at)
		planned_radii.append(radius)
	for spawn_index in definitions.size():
		var definition: Dictionary = definitions[spawn_index]
		var spawned: EnemyActor = host.spawn_enemy(planned[spawn_index],str(definition.enemy_id),int(definition.enemy_level),{"profile":definition,"zone_index":index,"reward_spawn_id":"zone:%d:wave:%d:spawn:%d" % [index, int(definition.get("wave_index", 0)), spawn_index]})
		if spawned == null:
			# Placement and budget are checked before the batch. If an invalid
			# definition still fails, keep the pending wave intact for retry.
			for actor in accepted:
				actor.queue_free()
			host._encounter_spawn_retry[index] = {"remaining":0.25,"geometry":hash(host.obstructions)}
			return false
		accepted.append(spawned)
	host.add_ring(planned[0] if not directive.is_empty() and not planned.is_empty() else zone.center,Color("d8b580"),95.0,.6)
	return true

func _encounter_spawn_clear(at: Vector2, radius: float, safe_distance: float, planned: Array[Vector2], radii: Array[float]) -> bool:
	if not host.valid_ground(at,radius) or at.distance_to(host.player.position)+.001 < safe_distance:
		return false
	for index in planned.size():
		if planned[index].distance_to(at) < radius+radii[index]+6.0:
			return false
	for actor in host.enemies.get_children():
		if actor.is_alive() and not actor.is_queued_for_deletion() and actor.position.distance_to(at) < radius+actor.navigation_radius+6.0:
			return false
	return true
