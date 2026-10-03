extends "res://tests/combat/test_boss_tactics.gd"
## Focused production BossBrain + BossActor + EnemySkillRuntime regressions.
## tools/test.ps1 -Suite boss_targeting -SkipImport

func run_checks() -> void:
	var isolated: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-profile=") and arg.contains("test_boss_targeting"):
			isolated = true
	if not isolated:
		push_error("This suite requires an isolated boss_targeting test profile")
		get_tree().quit(1)
		return
	if not Game.has_profile: Game.new_profile()
	check(Game.start_run(), "isolated boss-targeting run starts")
	await ring_target_checks()
	await close_charge_checks()
	await stationary_replay_checks()
	await fault_line_checks()
	Game.finish_run("abandoned")
	print("BOSS TARGETING TESTS: ", checks-failures, "/", checks, " passed")
	get_tree().quit(1 if failures else 0)

func set_phase(sim: Dictionary, value: int) -> void:
	sim.boss.boss_brain.phase = value
	sim.boss.health.current = sim.boss.health.maximum * (1.0 if value == 1 else (0.55 if value == 2 else 0.30))

func only_ready(sim: Dictionary, action: String) -> void:
	# Cooldowns isolate one candidate without forcing the action. The same
	# production selector must reject its safe zone or start its actual tell.
	var brain: BossBrain = sim.boss.boss_brain
	for candidate: String in brain.available_actions():
		brain._action_ready_at[candidate] = brain.elapsed + 100.0
	brain._action_ready_at[action] = 0.0
	brain._begin_action(sim.boss, sim.player)

func lock_existing(sim: Dictionary, action: String) -> Dictionary:
	var brain: BossBrain = sim.boss.boss_brain
	var warning: Dictionary = brain.current_telegraph()
	var initial_health: float = sim.player.health.current
	var initial_casts: int = sim.boss.casts.size()
	check(warning.get("action_id", "") == action and float(warning.get("tell", 0.0)) >= 0.9 and float(warning.get("lock", 0.0)) >= 0.4, action + " retains its full authored tell and dodge lock")
	if warning.is_empty(): return {}
	tick(sim, maxf(0.0, float(brain.state_time) - 0.02))
	check(sim.player.health.current == initial_health and sim.boss.casts.size() == initial_casts and brain.state == &"telegraph", action + " cannot damage or release before the complete warning")
	tick(sim, 0.04)
	var locked: Dictionary = brain.current_telegraph()
	check(bool(locked.get("locked", false)), action + " visibly locks geometry before execution")
	return locked

func release_existing(sim: Dictionary, action: String, locked: Dictionary) -> void:
	var initial_casts: int = sim.boss.casts.size()
	tick(sim, float(sim.boss.boss_brain.state_time) + 0.005)
	check(sim.boss.casts.size() == initial_casts + 1 and geometry(sim.boss.casts.back()) == geometry(locked), action + " releases one attack using exactly its frozen warning geometry")

func runtime_only(sim: Dictionary, duration: float) -> void:
	var remaining: float = duration
	while remaining > 0.00001:
		var step: float = minf(0.02, remaining)
		sim.runtime.advance(step)
		remaining -= step

func ring_target_checks() -> void:
	for spec: Dictionary in [
		{"action":"resonance_ring", "phase":1, "inner_distance":60.0, "hit_distance":220.0},
		{"action":"alternating_ring", "phase":3, "inner_distance":220.0, "hit_distance":400.0},
		{"action":"heart_crack", "phase":3, "inner_distance":60.0, "hit_distance":220.0},
		{"action":"seismic_crown", "phase":3, "inner_distance":130.0, "hit_distance":350.0},
	]:
		var sim: Dictionary = fixture("BO04", 4)
		var action: String = str(spec.action)
		set_phase(sim, int(spec.phase))
		sim.player.position = sim.boss.position + Vector2(float(spec.inner_distance), 0.0)
		only_ready(sim, action)
		check(sim.boss.boss_brain.current_action.is_empty() and sim.boss.boss_brain.current_telegraph().is_empty() and not sim.boss.velocity.is_zero_approx(), action + " naturally repositions instead of casting into its permanent inner safe zone")
		if action == "alternating_ring":
			check(not sim.boss.boss_brain._ring_toggle, "rejecting the next outer ring does not consume its alternation")
		sim.player.position = sim.boss.position + Vector2(float(spec.hit_distance), 0.0)
		only_ready(sim, action)
		check(sim.boss.boss_brain.current_action == action, action + " remains naturally selectable inside its real dangerous annulus")
		var locked: Dictionary = lock_existing(sim, action)
		if not locked.is_empty():
			if action == "alternating_ring":
				check(float(locked.get("inner_radius", 0.0)) == 350.0 and float(locked.get("radius", 0.0)) == 520.0, "alternating selection releases the outer ring it actually inspected")
			var initial_health: float = sim.player.health.current
			release_existing(sim, action, locked)
			check(sim.player.health.current < initial_health and sim.player.hits.size() == 1, action + " selected annulus deals real runtime damage to its warned stationary target")
		sim.room.queue_free()
		await get_tree().process_frame

func close_charge_checks() -> void:
	for action: String in ["sound_blade", "crag_leap"]:
		var sim: Dictionary = fixture("BO04", 4)
		sim.player.position = sim.boss.position + Vector2(60.0, 0.0)
		only_ready(sim, action)
		check(sim.boss.boss_brain.current_action == action, action + " can naturally pressure a close stationary character")
		var locked: Dictionary = lock_existing(sim, action)
		if not locked.is_empty():
			var initial_health: float = sim.player.health.current
			release_existing(sim, action, locked)
			runtime_only(sim, 1.6)
			check(sim.player.health.current < initial_health and not sim.runtime.has_motion(sim.boss), action + " completes its real close-distance motion and damages the warned target")
		sim.room.queue_free()
		await get_tree().process_frame

func finite_target_path(paths: Array, at: Vector2) -> bool:
	for path: Array in paths:
		var length: float = 0.0
		var crosses: bool = false
		for index: int in range(1, path.size()):
			var start: Vector2 = path[index-1]
			var finish: Vector2 = path[index]
			length += start.distance_to(finish)
			crosses = crosses or Geometry2D.get_closest_point_to_segment(at, start, finish).distance_to(at) <= 11.0
		if length > 100.0 and crosses: return true
	return false

func stationary_replay_checks() -> void:
	for spec: Dictionary in [
		{"phase":2, "dodge":false, "break_drums":false},
		{"phase":3, "dodge":true, "break_drums":false},
		{"phase":3, "dodge":false, "break_drums":true},
	]:
		var sim: Dictionary = fixture("BO04", 4)
		set_phase(sim, int(spec.phase))
		# Populate the real history sampler from a stationary target rather than
		# assigning a synthetic executable path to the skill runtime.
		for sample: int in 8:
			sim.boss.boss_brain._sample_victim(sim.player, 0.15)
		sim.boss.boss_brain._begin_action(sim.boss, sim.player, "replay_path")
		var locked: Dictionary = lock_existing(sim, "replay_path")
		if not locked.is_empty():
			var target: Vector2 = sim.player.position
			var paths: Array = locked.get("paths", [])
			check(paths.size() == (2 if int(spec.phase) == 2 else 4) and finite_target_path(paths, target), "stationary replay warns finite travelling paths through the actual target in phase " + str(spec.phase))
			if bool(spec.break_drums):
				var center: String = var_to_str(paths[0])
				var accepted: bool = true
				for lane: int in 3:
					accepted = sim.boss.apply_arena_counter("BO04:edge_bell:" + str(lane)) and accepted
				locked = sim.boss.boss_brain.current_telegraph()
				check(accepted and locked.get("paths", []).size() == 1 and var_to_str(locked.paths[0]) == center and sim.boss.boss_brain.weakpoint_open(), "three broken drums remove side paths while preserving the warned center and earned weakpoint")
			var frozen: String = geometry(locked)
			if bool(spec.dodge): sim.player.position += Vector2(0.0, 250.0)
			tick(sim, 0.02)
			check(geometry(sim.boss.boss_brain.current_telegraph()) == frozen, "replay history stops retargeting once its paths are locked")
			var initial_health: float = sim.player.health.current
			release_existing(sim, "replay_path", locked)
			runtime_only(sim, 1.2)
			check((sim.player.health.current == initial_health and sim.player.hits.is_empty()) if bool(spec.dodge) else (sim.player.health.current < initial_health and not sim.player.hits.is_empty()), "locked replay " + ("allows a real side dodge" if bool(spec.dodge) else "deals actual damage to the stationary target"))
			check(sim.runtime.projectiles.is_empty(), "stationary replay projectiles finish their finite paths")
		sim.room.queue_free()
		await get_tree().process_frame

func fault_line_checks() -> void:
	for dodge: bool in [false, true]:
		var sim: Dictionary = fixture("BO04", 4)
		sim.boss.boss_brain._begin_action(sim.boss, sim.player, "fault_lines")
		var locked: Dictionary = lock_existing(sim, "fault_lines")
		if not locked.is_empty():
			var paths: Array = locked.get("paths", [])
			check(paths.size() == 2 and finite_target_path(paths, sim.player.position), "fault lines visibly threaten the original aim point with a real center stroke")
			if dodge and paths.size() == 2:
				var direction: Vector2 = locked.direction
				var first_side: float = (Vector2(paths[0][0]) - Vector2(locked.origin)).dot(direction.orthogonal())
				var second_side: float = (Vector2(paths[1][0]) - Vector2(locked.origin)).dot(direction.orthogonal())
				sim.player.position += direction.orthogonal() * ((first_side + second_side) * 0.5)
			var frozen: String = geometry(locked)
			tick(sim, 0.02)
			check(geometry(sim.boss.boss_brain.current_telegraph()) == frozen, "fault lines remain frozen when the player moves into their visible side gap")
			var initial_health: float = sim.player.health.current
			release_existing(sim, "fault_lines", locked)
			check((sim.player.health.current == initial_health and sim.player.hits.is_empty()) if dodge else (sim.player.health.current < initial_health and sim.player.hits.size() == 1), "fault lines " + ("allow a real dodge between the locked strokes" if dodge else "deal one real center-line hit to the stationary target"))
		sim.room.queue_free()
		await get_tree().process_frame
