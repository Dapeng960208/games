extends "res://tests/test_s11_battle_matrix.gd"
const DirectedDriver = preload("res://tests/support/s11_directed_controller.gd")
const DirectedTrail = preload("res://tests/support/s11_directed_damage_trail.gd")
const DirectedSkills = preload("res://tests/support/s11_directed_enemy_skills.gd")
const AbilityCatalog = preload("res://scripts/combat/boss_ability_catalog.gd")
var directed_finished := false
var directed_result: Dictionary = {}

func initialize_directed_scenario() -> void:
	var experiment := arg("experiment","phase_coverage")
	check(experiment in ["phase_coverage","p3_tolerance"],"explicit separate directed experiment")
	check(measurement_protocol.get("experiment")==experiment and measurement_protocol.get("directed_controller_version")==DirectedDriver.DIRECTED_VERSION,"directed policy is pinned")
	config["experiment"]=experiment
	driver=DirectedDriver.new()
	driver.experiment=experiment
	driver.coverage_phase=int(arg("starting-phase","0")) if experiment=="phase_coverage" else 0
	check(int(measurement_protocol.get("starting_phase",0))==int(arg("starting-phase","0")),"directed starting phase is pinned")
	driver.configure(room)
	trail=DirectedTrail.new()
	trail.room_reference=weakref(room)
	Game.damage_trail=trail
	# Still before the first physics frame: no command/effect exists to clear.
	check(room.enemy_skills.active_effect_count()==0,"directed observer binds before any skill effect")
	var native_skill_layer: int = room.enemy_skills.z_index
	room.enemy_skills.set_script(DirectedSkills)
	room.enemy_skills.configure(room)
	room.enemy_skills.z_index=native_skill_layer
	directed_finished=false
	directed_result={}
	fixture["directed_initial_conditions"]={"synthetic":true,"mode":experiment,"initialization_before_clock_and_physics":true,"boss_hp_before":boss.health.current,"player_hp":run_ref.hp,"player_shield":run_ref.shield,"player_resource":run_ref.resource,"policy_version":DirectedDriver.DIRECTED_VERSION}
	var initial_phase: int = 3 if experiment=="p3_tolerance" else driver.coverage_phase
	fixture.directed_initial_conditions["requested_native_phase"]=initial_phase
	if initial_phase>=2:
		var threshold := float(boss.profile.get("phase_thresholds",[.7,.35])[initial_phase-2])
		var initial_hp := floorf(float(boss.health.maximum)*threshold)
		boss.health.damage(float(boss.health.current)-initial_hp)
		var roster_id := str(boss.get_instance_id())
		if room.actor_roster.has(roster_id):
			room.actor_roster[roster_id]["constructed_full_hp"]=room.actor_roster[roster_id].initial_hp
			room.actor_roster[roster_id]["initial_hp"]=initial_hp
			room.actor_roster[roster_id]["synthetic_phase_fixture"]=true
		# Native BossBrain.tick will enter P2 then P3, execute normal phase
		# cleanup and spawn the authored waves. No private phase mutation.
		last_boss_hp=boss.health.current
		boss_max_hp=last_boss_hp
		fixture.directed_initial_conditions.merge({"boss_initial_hp":initial_hp,"boss_maximum_hp":boss.health.maximum,"native_phase_threshold":threshold,"phase_update":"first native physics tick"},true)
	if experiment=="p3_tolerance":
		fixture.directed_initial_conditions["intended_action"]=DirectedDriver.DANGEROUS[boss.boss_id]
		var entry_guards: Dictionary = room.player.status.guards.duplicate(true)
		var entry_shield := float(room.player.status.shield())
		var absorbed_before := float(room.player.status.total_absorbed)
		if entry_shield>0:
			# Supplemental initial condition only. Consume through the native
			# guard API before clock; never emit a fake received-damage event or
			# trigger shield-broken equipment effects. Normal battles keep this
			# same legal EQ27 entry guard unchanged.
			room.player.status.absorb(entry_shield)
			room.player.status.tick_guard(0.0)
			run_ref.shield=room.player.status.shield()
		var pools_empty := true
		for pool: Dictionary in room.player.status.guards.values():
			if float(pool.get("amount",0))!=0.0: pools_empty=false
		fixture.directed_initial_conditions["preclock_entry_guard_consumption"]={"sources_before":entry_guards,"effective_amount_consumed":entry_shield,"sources_after":room.player.status.guards.duplicate(true),"effective_shield_after":run_ref.shield,"native_absorption_counter_setup_increment":float(room.player.status.total_absorbed)-absorbed_before,"received_damage_evidence":false,"no_damage_event_or_midfight_reset":true}
		fixture.directed_initial_conditions.player_shield=run_ref.shield
		check(pools_empty and room.player.status.shield()==0,"all initial guard pools consumed only in declared supplemental fixture")
		check(run_ref.hp==run_ref.max_hp and run_ref.shield==0,"tolerance starts full HP and no existing shield")
		# Explicit single-action initial fixture, using native phase entry and
		# the production windup API's documented arena-fixture argument. This
		# chooses the action only before the clock; real warning/lock/hit follow.
		var authored_entry: Vector2 = room.player.position
		var radius := 350.0 if boss.boss_id=="BO04" else 280.0
		var points: Array[Vector2] = []
		for index in 32: points.append(boss.position+Vector2.from_angle(TAU*float(index)/32.0)*radius)
		points.sort_custom(func(a: Vector2,b: Vector2)->bool: return authored_entry.distance_squared_to(a)<authored_entry.distance_squared_to(b))
		var spawn_found := false
		for point: Vector2 in points:
			if room.valid_ground(point,Balance.PLAYER_RADIUS) and room.has_line_of_sight(boss.position,point):
				room.player.position=point
				spawn_found=true
				break
		check(spawn_found,"single-action fixture has valid initial ground and line of sight")
		boss.boss_brain.tick(boss,.000001,room.player)
		check(boss.boss_brain.phase==3,"native health threshold update enters P3 before action fixture clock")
		boss.boss_brain._begin_action(boss,room.player,DirectedDriver.DANGEROUS[boss.boss_id])
		check(boss.boss_brain.state==&"telegraph" and boss.boss_brain.current_action==DirectedDriver.DANGEROUS[boss.boss_id],"native dangerous-action windup starts, not direct damage")
		fixture.directed_initial_conditions.merge({"single_action_fixture":true,"authored_player_entry":[authored_entry.x,authored_entry.y],"actual_player_initial_position":[room.player.position.x,room.player.position.y],"spawn_reason":"Valid ground within authored dangerous-action reach; fixed before clock, never teleport during combat","phase_update":"native BossBrain.tick with setup delta0.000001 before clock","forced_initial_windup":"BossBrain._begin_action explicit arena-fixture API; once before clock","initial_native_telegraph":boss.boss_brain.current_telegraph()},true)
		fixture.entry_position=[room.player.position.x,room.player.position.y]
		fixture.directed_initial_conditions["native_queued_reinforcements"]=boss.reinforcement_status()
		fixture.directed_initial_conditions["native_setup_delta"]=.000001

func requires_attack_evidence() -> bool:
	return arg("experiment","phase_coverage")!="p3_tolerance" and int(arg("starting-phase","0"))==0

func _physics_process(delta: float) -> void:
	var was_running := running
	super._physics_process(delta)
	if not was_running: return
	if running and config.get("experiment")=="phase_coverage" and driver.coverage_complete:
		directed_finished=true
		running=false
		room.process_mode=Node.PROCESS_MODE_DISABLED
	# Super stops immediately after lethal damage. Classify the preserved real
	# receipt anyway; a lethal intended packet is failed tolerance, not missing.
	if config.get("experiment")!="p3_tolerance" or not is_instance_valid(boss): return
	var target_action: String = DirectedDriver.DANGEROUS[boss.boss_id]
	var matching: Array[Dictionary] = []
	for packet: Dictionary in trail.all_events:
		if packet.get("source_id")==boss.boss_id and packet.get("attack_id")==target_action and not bool(packet.get("dot",false)): matching.append(packet)
	if matching.is_empty(): return
	var packet: Dictionary = matching.front()
	var actual_commands: Array[Dictionary] = []
	for command: Dictionary in room.enemy_skills.executed_commands:
		if str(command.get("action_id",""))==target_action and str(command.get("boss_id",""))==boss.boss_id and int(command.get("enemy_command_version",0))==2 and int(command.get("enemy_skill_phase",0))==3 and float(command.observed_room_time)<=room.elapsed and is_equal_approx(float(command.get("damage",-1)),float(packet.raw)):
			actual_commands.append(command)
	var same_instant: Array[Dictionary] = []
	for other: Dictionary in trail.all_events:
		if is_equal_approx(float(other.t),float(packet.t)): same_instant.append(other)
	var prior_incidental := false
	for other: Dictionary in trail.all_events:
		if float(other.t)<float(packet.t) and float(other.hp_loss)+float(other.shield_absorbed)>0: prior_incidental=true
	var eligible: bool = bool(packet.eligible_full_hp_unshielded_p3) and same_instant.size()==1 and not prior_incidental and not driver.intended_impacts.is_empty() and not actual_commands.is_empty()
	directed_result={"action":target_action,"accepted_packet":packet.duplicate(true),"actual_p3_commands_matching_raw_packet":actual_commands,"same_instant_packets":same_instant.size(),"prior_incidental_hit":prior_incidental,"eligible":eligible,"hp_loss_fraction":float(packet.hp_loss)/float(run_ref.max_hp),"survived":float(packet.hp_after)>0,"within_twenty_percent":float(packet.hp_loss)<=float(run_ref.max_hp)*.2,"passed":eligible and float(packet.hp_after)>0 and float(packet.hp_loss)<=float(run_ref.max_hp)*.2}
	directed_finished=true
	running=false
	room.process_mode=Node.PROCESS_MODE_DISABLED

func finish_record() -> void:
	super.finish_record()
	var row: Dictionary = rows.back()
	row["directed_controller"]=DirectedDriver.DIRECTED_VERSION
	row["baseline_ttk_evidence"]=false
	row["directed_phase_releases"]=driver.phase_releases.duplicate(true)
	row["executed_enemy_commands"]=room.enemy_skills.executed_commands.duplicate(true)
	row["directed_phase_coverage"]={}
	for phase in [1,2,3]:
		var expected: Array = BossBrain.SEQUENCES[str(fixture.boss_id)][phase].duplicate()
		expected.append_array(AbilityCatalog.unlocked(str(fixture.boss_id),int(config.difficulty)))
		var seen: Dictionary = driver.phase_releases.get(str(phase),{})
		var missing: Array[String] = []
		var missing_reasons := {}
		for action: String in expected:
			if not seen.has(action):
				missing.append(action)
				var reason := "not_observed_before_sample_ended"
				if is_instance_valid(boss) and phase==boss.boss_brain.phase and not boss.boss_brain._action_available(boss,action):
					reason="native_prerequisite_unavailable_or_finite_counter_suppressed"
					if action=="grave_recall" and not boss.can_recall_grave(): reason="requires_actual_unsealed_reinforcement_death_receipt_or_remaining_recall_budget"
				missing_reasons[action]=reason
		row.directed_phase_coverage[str(phase)]={"expected_actions":expected,"observed_releases":seen.duplicate(true),"missing_actions":missing,"missing_action_reasons":missing_reasons,"all_actions_released":missing.is_empty()}
	row["intended_impacts"]=driver.intended_impacts.duplicate(true)
	row["tolerance"]=directed_result.duplicate(true)
	if config.experiment=="p3_tolerance": row["outcome"]="directed_packet_lethal" if directed_finished and run_ref.hp<=0 else "directed_packet_observed" if directed_finished else "player_died" if run_ref.hp<=0 else "directed_packet_unobserved"
	else: row["outcome"]="directed_phase_observed" if directed_finished else "directed_boss_defeated" if completed else "player_died" if run_ref.hp<=0 else "directed_time_limit"
