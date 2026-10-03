extends Node
## Drives the production objective host and real room movement, not completion flags.
class SpawnNavigationProbe extends RefCounted:
	var inner: RefCounted
	var calls: int = 0
	func direction(from: Vector2, to: Vector2, radius: float, walls: Array[Rect2], arena: Rect2) -> Vector2:
		calls += 1
		return inner.direction(from,to,radius,walls,arena)

const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Objectives = preload("res://scripts/gameplay/world/room_objectives.gd")
const Coordinator = preload("res://scripts/app/expedition_controller.gd")
var room: RoomController
var objectives: Node2D
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ROOM OBJECTIVE FAIL: " + description)

func fixture(id: String, node_role: String = "branch") -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hp = Game.run.max_hp
	room = RoomScene.instantiate()
	room.layout_id = id
	room.run_seed = 40917
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	for enemy in room.enemies.get_children():
		enemy.free()
	if is_instance_valid(room.get("objectives")):
		objectives = room.objectives
	else:
		objectives = Objectives.new()
		room.add_child(objectives)
	objectives.configure(room, room.layout, node_role)
	check(objectives.module != null, id + " loads authored mechanics")
	check(not objectives.is_complete(), id + " does not complete merely by removing enemies")

func interact(id: String) -> bool:
	if not objectives.elements.has(id):
		check(false, "missing interaction " + id)
		return false
	room.player.position = objectives.element(id).position
	return objectives.interact(id, room.player)

func tick(seconds: float) -> void:
	for index in ceili(seconds / .05):
		objectives.tick(.05)

func destroy_expedition_room() -> void:
	if not is_instance_valid(room):
		return
	if is_instance_valid(room.combat_audio):
		await room.combat_audio.wait_for_cleanup()
	room.free()
	room = null
	await get_tree().process_frame

func construct_expedition_room() -> bool:
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var coordinator = Coordinator.new(Game)
	var prepared: Dictionary = room.prepare_expedition_node(coordinator.current_context())
	check(bool(prepared.get("valid", false)), "committed expedition node prepares its real layout")
	if not bool(prepared.get("valid", false)):
		room.free()
		room = null
		return false
	room.apply_prepared_expedition_node(prepared)
	get_tree().root.add_child(room)
	objectives = room.objectives
	check(room.configuration_ready, "real expedition room initializes its actors and objective host")
	return room.configuration_ready

func enter_expedition_room(id: String) -> bool:
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers", []):
		if str(offer.decision).is_empty():
			var skipped: bool = Game.choose_run_relic(str(offer.offer_id), "skip", "", room.expedition_runtime_snapshot())
			check(skipped, "required route offer is resolved through the production decision API")
			if not skipped:
				return false
	var state: Dictionary = Game.expedition_snapshot()
	var selected: bool = Game.choose_expedition_node(int(state.node_index) + 1, id)
	check(selected, "legal expedition route selects " + id)
	if not selected:
		return false
	var entered: bool = Game.advance_expedition_node(room.expedition_runtime_snapshot(), str(state.checkpoint_id))
	check(entered, "real checkpoint commits entry to " + id)
	if not entered:
		return false
	await destroy_expedition_room()
	if not construct_expedition_room():
		return false
	check(room.layout_id == id, "runtime room matches the committed route " + id)
	return room.layout_id == id

func clear_living_combat_actors() -> void:
	for enemy in room.enemies.get_children():
		if enemy.actor_kind != "objective" and enemy.is_alive():
			enemy.take_damage(1000000.0, &"test", Vector2.ZERO, {"damage_type": "true"})
	await get_tree().process_frame
	check(room._living_enemy_count() == 0, "real damage clears every living combat actor")

func prepare_escort_tail_fixture(next_difficulty: int = 0) -> void:
	fixture("L02")
	room.objectives = objectives
	room.expedition_context = {"role": "branch"}
	room.difficulty = next_difficulty
	room.activated_encounters.clear()
	room.encounter_progress.clear()
	# These are schedule fixtures, not natural-play timing evidence. The first
	# two finite plans are already resolved; only the real tail plan is exercised.
	for index in 2:
		var plan: Dictionary = room._encounter_plan(index)
		room.activated_encounters[index] = true
		room.encounter_progress[index] = {"plan": plan, "next_wave": plan.waves.size(), "reinforce_elapsed": 0.0}

func escort_tail_at_second_anchor() -> void:
	objectives.module.route_index = 2
	objectives.element("cargo_cart").position = objectives.module.cart_route[1]
	room.player.position = objectives.element("cargo_cart").position

func check_escort_tail_batch(definitions: Array, label: String) -> void:
	var remaining: Array = definitions.duplicate(true)
	var actors: Array = []
	var safe_distance: float = float(room.encounter_zones[2].get("minimum_player_spawn_distance", 360.0))
	for actor in room.enemies.get_children():
		if not actor.is_alive() or actor.is_queued_for_deletion() or actor.actor_kind == "objective":
			continue
		actors.append(actor)
		check(actor.zone_index == 2, label + " preserves the tail zone identity")
		var match_index: int = remaining.find(actor.profile)
		check(match_index >= 0, label + " preserves the exact authored enemy profile")
		if match_index >= 0:
			remaining.remove_at(match_index)
		check(room.valid_ground(actor.position, actor.navigation_radius), label + " places every body on clear ground")
		check(actor.position.distance_to(room.player.position) + .001 >= safe_distance, label + " keeps the 360-unit player exclusion")
		check(not room.navigation_direction(actor.position, objectives.element("cargo_cart").position, actor.navigation_radius).is_zero_approx(), label + " has a production navigation route back to the escort")
	check(remaining.is_empty() and actors.size() == definitions.size(), label + " spawns the finite batch exactly, without loss or extras")
	var commitment: Dictionary = room._zone_commitments(2)
	check(int(commitment.slots) <= 6 and room._room_committed_slots() <= 18, label + " respects existing zone and room concurrency caps")
	check(float(commitment.threat) <= float(room._encounter_plan(2).concurrent_threat_budget), label + " respects existing threat budget")
	for first in actors.size():
		for second in range(first + 1, actors.size()):
			check(actors[first].position.distance_to(actors[second].position) + .001 >= actors[first].navigation_radius + actors[second].navigation_radius + 6.0, label + " does not overlap spawned bodies")

func consume_escort_tail_reinforcements(plan: Dictionary, label: String) -> int:
	var spawned_count: int = 0
	for index in range(1, plan.waves.size()):
		room._update_encounters(4.0)
		check_escort_tail_batch(plan.waves[index], label + " reinforcement " + str(index))
		spawned_count += room._living_enemy_count()
		await clear_living_combat_actors()
	return spawned_count

func check_escort_encounter_schedule() -> void:
	await destroy_expedition_room()
	prepare_escort_tail_fixture()
	check(objectives.encounter_directive(0).is_empty() and objectives.encounter_directive(1).is_empty(), "escort leaves the first two encounter schedules unchanged")
	var directive: Dictionary = objectives.encounter_directive(2)
	check(not bool(directive.get("ready", true)), "tail directive remains pending before the second escort anchor")
	room.player.position = room.encounter_zones[2].center
	room._update_encounters()
	check(not room.activated_encounters.has(2) and room._living_enemy_count() == 0, "rushing to the old final sector cannot activate the escort tail early")
	escort_tail_at_second_anchor()
	directive = objectives.encounter_directive(2)
	check(bool(directive.get("ready", false)) and Vector2(directive.get("position", Vector2.ZERO)).is_equal_approx(objectives.element("cargo_cart").position), "second escort anchor readies the tail at the actual moving cart")
	check(Vector2(directive.get("destination", Vector2.ZERO)).is_equal_approx(objectives.module.cart_route.back()), "tail staging follows the final authored escort destination")
	check(room.player.position.distance_to(room.encounter_zones[2].center) > float(room.encounter_zones[2].get("activation_distance", 520)), "schedule fixture is outside the former geographic activation radius")
	var prior: Dictionary = room.encounter_progress[1]
	prior.next_wave = int(prior.plan.waves.size()) - 1
	room._update_encounters()
	check(not room.activated_encounters.has(2), "unspent prior finite wave prevents early escort-tail activation")
	prior.next_wave = prior.plan.waves.size()
	var survivor: EnemyActor = room.spawn_enemy(room.layout.entry, "M01", 1, {"zone_index": 1})
	check(is_instance_valid(survivor), "prior-zone living gate uses a real enemy")
	room._update_encounters()
	check(not room.activated_encounters.has(2), "a surviving previous-zone enemy prevents escort-tail activation")
	await clear_living_combat_actors()
	var tail_plan: Dictionary = room._encounter_plan(2)
	room._update_encounters()
	check(room.activated_encounters.has(2), "second escort anchor activates the existing tail beyond the old sector radius")
	check_escort_tail_batch(tail_plan.waves[0], "loaded escort tail")
	var loaded_count: int = room._living_enemy_count()
	await clear_living_combat_actors()
	loaded_count += await consume_escort_tail_reinforcements(tail_plan, "loaded escort")
	check(loaded_count == int(tail_plan.total_count), "loaded escort retains every enemy in its original finite plan")
	for point: Vector2 in [room.layout.entry, room.encounter_zones[2].center, objectives.module.cart_route[1]]:
		room.player.position = point
		room._update_encounters(10.0)
	check(room._living_enemy_count() == 0 and room.activated_encounters.size() == 3 and room._encounters_exhausted(), "departing, backtracking and revisiting cannot duplicate the exhausted Lv1 tail")
	await destroy_expedition_room()
	prepare_escort_tail_fixture(2)
	check(interact("cargo_cart"), "finite multiwave escort fixture unloads through the real interaction")
	escort_tail_at_second_anchor()
	check(bool(objectives.encounter_directive(2).get("ready", false)), "voluntary unloading preserves the second-anchor tail directive")
	tail_plan = room._encounter_plan(2)
	check(tail_plan.waves.size() > 1, "higher-difficulty fixture exercises actual finite reinforcement waves")
	objectives.set_done("cargo_cart")
	objectives.finish("reduced")
	room._expedition_ready = true
	# Prevent any reward transaction in this isolated schedule fixture even if
	# the completion assertion regresses; real checkpoint receipts have own tests.
	room.progress_retry_timer = 1.0
	var spawned_count: int = 0
	for index in tail_plan.waves.size():
		room._tick_expedition(4.0)
		check(room.activated_encounters.has(2) and room.encounter_progress.has(2), "unloaded escort accepts finite tail wave " + str(index))
		check(not room.objective_complete and not room.objective_rewarded, "delivered cargo cannot skip still-pending tail wave " + str(index))
		check_escort_tail_batch(tail_plan.waves[index], "unloaded escort wave " + str(index))
		spawned_count += room._living_enemy_count()
		await clear_living_combat_actors()
	room._update_encounters(30.0)
	check(spawned_count == int(tail_plan.total_count) and room._living_enemy_count() == 0 and room._encounters_exhausted(), "unloaded escort consumes the existing multiwave count exactly once")
	await destroy_expedition_room()
	prepare_escort_tail_fixture()
	room.player.position = Vector2(2500, 1500)
	tick(8)
	check(objectives.blockers.has("collapsed_bridge"), "tail retry fixture closes a real validated alternate bridge")
	escort_tail_at_second_anchor()
	tail_plan = room._encounter_plan(2)
	room._update_encounters()
	var accepted_while_closed: bool = room.activated_encounters.has(2)
	if accepted_while_closed:
		check_escort_tail_batch(tail_plan.waves[0], "temporarily closed bridge tail")
	else:
		check(room._living_enemy_count() == 0 and not room.encounter_progress.has(2), "unplaceable closed-bridge batch remains intact for retry")
	objectives.remove_blocker("collapsed_bridge")
	room._update_encounters()
	check(room.activated_encounters.has(2), "opening the bridge cannot lose a pending finite escort tail")
	check_escort_tail_batch(tail_plan.waves[0], "reopened bridge tail")
	var bridge_count: int = room._living_enemy_count()
	await clear_living_combat_actors()
	bridge_count += await consume_escort_tail_reinforcements(tail_plan, "reopened bridge")
	room._update_encounters(30.0)
	check(bridge_count == int(tail_plan.total_count) and room._living_enemy_count() == 0 and room._encounters_exhausted(), "bridge changes retain the finite plan and do not respawn its consumed tail")
	await destroy_expedition_room()
	prepare_escort_tail_fixture()
	escort_tail_at_second_anchor()
	objectives.set_done("cargo_cart")
	objectives.finish()
	room._expedition_ready = true
	room.progress_retry_timer = 1.0
	var receipt_before: Dictionary = Game.run.live_receipt()
	# Deliberately impossible placement isolates the retry boundary. The valid
	# alternate-bridge case above separately covers playable topology changes.
	var navigation_probe := SpawnNavigationProbe.new()
	navigation_probe.inner = room._navigation_cache
	room._navigation_cache = navigation_probe
	room.obstructions.append(room.ARENA)
	room._tick_expedition(.016)
	check(navigation_probe.calls == 1 and room._encounter_spawn_retry.has(2), "first failed placement scans immediately and starts its retry cooldown")
	check(not room.activated_encounters.has(2) and not room.encounter_progress.has(2) and room._living_enemy_count() == 0, "failed placement never partially spends the finite escort tail")
	check(room._objective_encounters_pending() and not room.objective_complete and not room.objective_rewarded and Game.run.live_receipt() == receipt_before, "delivered cargo cannot commit completion or rewards while tail placement is pending")
	for frame in 99:
		room._tick_expedition(.01)
	check(navigation_probe.calls == 4, "unchanged failed placement runs only four bounded navigation scans during its first second")
	check(not room.activated_encounters.has(2) and not room.encounter_progress.has(2) and room._living_enemy_count() == 0 and Game.run.live_receipt() == receipt_before, "throttled failures never advance a wave, spawn a partial batch, or change rewards")
	room.obstructions.erase(room.ARENA)
	room._tick_expedition(.016)
	check(room.activated_encounters.has(2) and not room.objective_complete and not room._encounter_spawn_retry.has(2), "changed geometry retries immediately without waiting out the failed-placement cooldown")
	check_escort_tail_batch(room._encounter_plan(2).waves[0], "post-delivery placement retry")
	await clear_living_combat_actors()
	room.obstructions.append(room.ARENA)
	var scans_before: int = navigation_probe.calls
	room._update_encounters(2.99)
	check(navigation_probe.calls == scans_before and int(room.encounter_progress[2].next_wave) == 1, "placement retry does not shorten the original three-second reinforcement delay")
	room._update_encounters(.01)
	check(navigation_probe.calls == scans_before+1 and int(room.encounter_progress[2].next_wave) == 1, "eligible reinforcement failure starts its own cooldown without consuming the wave")
	room._update_encounters(.24)
	check(navigation_probe.calls == scans_before+1, "reinforcement failure also suppresses navigation scans inside the quarter-second window")
	room._update_encounters(.01)
	check(navigation_probe.calls == scans_before+2 and int(room.encounter_progress[2].next_wave) == 1, "reinforcement retries at the quarter-second boundary and remains pending on failure")
	room.obstructions.erase(room.ARENA)
	room._update_encounters()
	check(int(room.encounter_progress[2].next_wave) == 2 and not room._encounter_spawn_retry.has(2), "reopened reinforcement placement succeeds immediately without restarting the three-second timer")
	room._navigation_cache = navigation_probe.inner
	room.obstructions.append(room.ARENA)
	check(not room._spawn_encounter_wave(2,room._encounter_plan(2).waves[0]) and not room._encounter_spawn_retry.is_empty(), "legacy room-change fixture contains a real failed-placement cooldown")
	check(room.load_room_layout("L02",0,40917) and room._encounter_spawn_retry.is_empty(), "legacy room layout replacement clears runtime placement cooldowns")
	var next_context: Dictionary = {"room_id":"L03","role":"branch","seed":40917,"difficulty":0,"biome_id":"B01"}
	var prepared: Dictionary = room.prepare_expedition_node(next_context)
	check(bool(prepared.get("valid",false)), "expedition room-change fixture prepares an actual next room")
	room.obstructions.append(room.ARENA)
	check(not room._spawn_encounter_wave(0,room._encounter_plan(0).waves[0]) and not room._encounter_spawn_retry.is_empty(), "expedition room-change fixture contains a real failed-placement cooldown")
	if bool(prepared.get("valid",false)):
		room._install_expedition_layout(prepared)
		check(room._encounter_spawn_retry.is_empty(), "expedition room installation clears runtime placement cooldowns")
	await destroy_expedition_room()

func prepare_winch_expedition() -> bool:
	await destroy_expedition_room()
	check(not Game.finish_run("abandoned").is_empty(), "ordinary fixture run closes before the reward expedition")
	var started: bool = Game.start_run({"expedition": true, "biome_id": "B01", "seed": 41827})
	check(started, "fresh real B01 expedition starts for optional salvage")
	if not started or not construct_expedition_room():
		return false
	if not await enter_expedition_room("L03"):
		return false
	check(interact("gear_stop"), "first route room stops its authored gears")
	check(interact("key_0") and interact("key_1"), "first route room recovers both actual keys")
	await clear_living_combat_actors()
	room._tick_expedition(.016)
	check(room.objective_rewarded and str(Game.run.expedition.phase) == "cleared", "L03 objective and combat clearance commit before route advancement")
	return await enter_expedition_room("L01")

func _run() -> void:
	check(Game.new_profile() and Game.start_run(), "isolated objective run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	fixture("L01", "objective")
	if not await prepare_winch_expedition():
		await destroy_expedition_room()
		print("ROOM_OBJECTIVES_TEST_RESULT checks=%d failures=%d" % [checks, failures])
		get_tree().quit(1)
		return
	if room._living_enemy_count() == 0:
		room.spawn_enemy(room.layout.entry + Vector2(300, 100), "M01", 1)
	check(room._living_enemy_count() > 0, "optional salvage gate is exercised with real living enemies")
	check(not interact("brake_2"), "standard winch teaches numbered order")
	check(interact("brake_0"), "first brake releases actual track hazard")
	check(objectives.hazards.size() == 1 and float(objectives.hazards[0].delay) >= .8, "minecart damage has visible warning")
	check(interact("brake_1") and interact("brake_2") and objectives.is_complete(), "all three releases finish winch objective")
	var receipt_before: Dictionary = Game.run.live_receipt()
	check(not interact("side_crate"), "finished machinery cannot claim optional salvage before combat clearance commits")
	check(not room.objective_rewarded and not bool(objectives.element("side_crate").done) and Game.run.live_receipt() == receipt_before, "early salvage attempt preserves the crate and all rewards")
	await clear_living_combat_actors()
	room._tick_expedition(.016)
	check(room.objective_rewarded and str(Game.run.expedition.phase) == "cleared", "winch room commits actual objective and combat clearance")
	check(interact("side_crate"), "committed cleared winch room grants its retained optional salvage")
	check(bool(objectives.element("side_crate").done) and not interact("side_crate"), "successful salvage is consumed exactly once")
	await destroy_expedition_room()
	check(not Game.finish_run("abandoned").is_empty() and Game.start_run(), "ordinary run resumes for independent authored-mechanic fixtures")
	fixture("L01", "elite_objective")
	room.player.position = objectives.element("brake_2").position
	check(str(objectives.nearby_interaction(room.player.position).get("label", "")) == str(objectives.element("brake_2").label), "ordinary objective keeps its original E label without an override")
	check(interact("brake_2") and interact("brake_0") and interact("brake_1"), "elite permits strategic brake order")
	fixture("L02")
	room.objectives = objectives
	room.expedition_context = {"role": "branch"}
	var original: Vector2 = objectives.element("cargo_cart").position
	room.player.position = original
	var cart_hint: String = room.interaction_hint()
	check(cart_hint.contains("卸货提速") and cart_hint.contains("34 金币") and cart_hint.contains("无装备"), "near-cart E explains the actual unload action and completed-delivery reward tradeoff")
	check(str(objectives.element("cargo_cart").label) == "载货滑车", "interaction action override does not rename the world cart")
	check(str(objectives.navigation_target().title).contains("靠近自动推车"), "active objective title teaches automatic escort before the first segment")
	room.player.position = Vector2(2500, 1500)
	tick(1)
	check(original.is_equal_approx(objectives.element("cargo_cart").position), "escort stops when player leaves")
	tick(7)
	check(objectives.blockers.has("collapsed_bridge"), "one bridge actually closes after its evacuation warning")
	if objectives.blockers.has("collapsed_bridge"):
		var bridge: Rect2 = objectives.blockers.collapsed_bridge
		check(room.obstructions.has(bridge), "temporary collapse changes production collision")
		check(not room.valid_ground(bridge.get_center(), 18), "collapsed surface is not walkable")
	check(interact("cargo_cart"), "unloading trades the completed delivery equipment reward for speed and gold")
	check(not bool(objectives.element("cargo_cart").interactive) and objectives.nearby_interaction(room.player.position).is_empty(), "unloading removes the now-invalid E focus")
	check(not interact("cargo_cart"), "an unloaded cart rejects repeated unload requests")
	check(str(objectives.navigation_target().get("id", "")) == "cargo_cart", "unloaded cart remains the automatic escort navigation target")
	var overlapping_buff: Dictionary = room.enemy_props.props[0]
	overlapping_buff.position = objectives.element("cargo_cart").position
	check(str(room.nearby_interaction().get("id", "")) == str(overlapping_buff.id), "unloaded cart no longer hides a real nearby buff from room E dispatch")
	room.release_gate = false
	room.interact()
	check(bool(overlapping_buff.used) and room.enemy_props.buffs.has(str(overlapping_buff.effect)), "E applies the overlapping buff through the production room interaction")
	var before_resume: Vector2 = objectives.element("cargo_cart").position
	tick(.25)
	check(before_resume.distance_to(objectives.element("cargo_cart").position) > 1.0, "cart keeps automatically moving after its E interaction is disabled")
	var paused_position: Vector2 = objectives.element("cargo_cart").position
	var paused_segment: int = objectives.module.route_index
	room.player.position = Vector2(2500, 1500)
	tick(.25)
	check(paused_position.is_equal_approx(objectives.element("cargo_cart").position) and paused_segment == objectives.module.route_index, "leaving an unloaded cart preserves both its position and completed route segments")
	room.player.position = paused_position
	tick(.25)
	check(paused_position.distance_to(objectives.element("cargo_cart").position) > 1.0, "returning resumes escort without requiring E")
	for frame in 4500:
		room.player.position = objectives.element("cargo_cart").position
		objectives.tick(.05)
		if objectives.is_complete():
			break
	check(objectives.is_complete() and objectives.quality == "reduced", "real cart crosses all three route anchors and completes lighter delivery")
	fixture("L02")
	var damaged_cart: Dictionary = objectives.element("cargo_cart")
	var cargo_attacker: EnemyActor = room.spawn_enemy(damaged_cart.position, "M01", 1)
	check(is_instance_valid(cargo_attacker), "cargo damage uses a real nearby living enemy")
	room.player.position = Vector2(2500, 1500)
	tick(50.1)
	check(float(damaged_cart.cargo_health) <= 0 and objectives.module.unloaded, "sustained actual enemy proximity exhausts heavy cargo")
	check(not bool(damaged_cart.interactive), "automatic cargo loss also removes the invalid unload action")
	room.player.position = damaged_cart.position
	check(objectives.nearby_interaction(room.player.position).is_empty() and not interact("cargo_cart"), "damaged light cart offers no dead E focus or repeated action")
	check(str(objectives.navigation_target().get("id", "")) == "cargo_cart", "cargo loss preserves the current escort navigation target")
	var damaged_position: Vector2 = damaged_cart.position
	tick(.25)
	check(damaged_position.distance_to(damaged_cart.position) > 1.0 and not objectives.is_complete(), "cargo loss still allows proximity movement instead of abandoning or auto-completing the objective")
	objectives.module.route_index = 2
	check(bool(objectives.encounter_directive(2).get("ready", false)), "actual cargo destruction retains the finite escort-tail directive")
	await check_escort_encounter_schedule()
	fixture("L03")
	check(objectives.encounter_directive(2).is_empty(), "other room mechanics retain normal geographic encounter activation")
	room.player.position = objectives.point(0) + Vector2(0, 75)
	var before: Vector2 = room.player.position
	tick(.5)
	check(room.player.position.distance_to(before) > 3, "gear platform changes actual player position safely")
	check(interact("gear_stop"), "optional station stops the actual gear conveyor")
	room.player.position = objectives.point(0) + Vector2(0, 75)
	before = room.player.position
	tick(.5)
	check(room.player.position.is_equal_approx(before), "stopped gears cease forced movement")
	check(interact("key_0") and interact("key_1") and objectives.is_complete(), "both accessible key cores complete objective")
	fixture("L04")
	check(interact("crate_0"), "shape crate can be carried")
	room.player.position = objectives.element("scale_0").position + Vector2(-48, 0)
	tick(.05)
	check(str(objectives.nearby_interaction(room.player.position).get("id", "")) == "scale_0", "E chooses delivery instead of foot-following drop control")
	check(interact("scale_1"), "wrong shape produces a recoverable penalty")
	check(objectives.module.carried == "crate_0" and objectives.completed_count == 0, "wrong shape neither deletes carried item nor resets progress")
	check(interact("scale_0"), "matching shape delivered")
	for index in range(1, 3):
		check(interact("crate_" + str(index)), "pick up shape " + str(index))
		check(interact("scale_" + str(index)), "deliver shape " + str(index))
	check(objectives.is_complete(), "three physical shape deliveries finish sorting")
	fixture("L05")
	room.player.position = objectives.element("beacon_0").position
	tick(4)
	var partial: float = objectives.element("beacon_0").progress
	room.player.position = room.layout.entry
	tick(2)
	check(is_equal_approx(partial, objectives.element("beacon_0").progress), "leaving preserves hold-point progress")
	room.player.position = objectives.element("beacon_0").position
	tick(4.1)
	room.player.position = objectives.element("beacon_1").position
	tick(8.1)
	check(objectives.is_complete(), "two separated real hold zones finish rescue power")
	fixture("L06")
	for index in 3:
		for attempt in 2:
			check(interact("valve_" + str(index)), "adjust coupled pressure control")
	room.player.position = room.layout.entry
	tick(4.2)
	check(objectives.element("furnace_core").active, "all pressure gauges held in band unlock core")
	check(interact("furnace_core") and objectives.is_complete(), "stable core physically recovered")
	fixture("L06")
	check(interact("furnace_cut") and objectives.is_complete() and objectives.quality == "reduced", "emergency cut offers lower reward without a soft lock")
	var at: Vector2 = room.layout.entry
	room.player.position = at
	var hp_before: float = Game.run.hp
	objectives.add_hazard(at, 65, 10, 1, .2)
	tick(.8)
	check(is_equal_approx(hp_before, Game.run.hp), "objective hazard cannot damage during warning")
	tick(.4)
	check(Game.run.hp < hp_before, "objective hazard routes through real player health after warning")
	for index in range(1, 25):
		var id: String = "L%02d" % index
		fixture(id)
		check(objectives.required_count > 0 and objectives.elements.size() > 0, id + " creates actual authored objective elements")
		var solid_count: int = room.layout.get("prop_instances", []).size()
		check(solid_count >= 4 and solid_count <= 8 and not room.layout.get("decoration_instances", []).is_empty(), id + " retains sparse solid scenery and harmless edge decoration")
		check(room.enemy_props.props.size() == 3, id + " retains dispersed buffs")
		var destination: Dictionary = objectives.navigation_target()
		check(destination.has("position") and destination.get("title", "") != "", id + " offers a usable current objective direction")
		for item: Dictionary in objectives.elements.values():
			var asset: String = str(item.get("asset", ""))
			if not asset.is_empty():
				check(objectives.textures.has(asset), id + " task art actually loads " + asset)
		for enemy in room.enemies.get_children():
			if enemy.actor_kind == "objective":
				check(enemy.static_actor and not enemy.reward_enabled, id + " task targets have no enemy brain or kill reward")
		check(room._living_enemy_count() == 0, id + " task targets never block encounter spawn slots")
	fixture("L07")
	check(interact("filter_0"), "real filter can be carried")
	check(objectives.blocks_dash(), "carried filter applies actual dash restriction")
	room.player.position = objectives.element("water_wheel").position + Vector2(-42, 0)
	tick(.05)
	var delivery: Dictionary = objectives.nearby_interaction(room.player.position)
	check(str(delivery.get("id", "")) == "water_wheel", "filter E prompt selects receiver instead of drop item")
	check(objectives.interact(str(delivery.get("id", "")), room.player) and not objectives.blocks_dash(), "E dispatch delivers filter and releases movement restriction")
	if is_instance_valid(room.combat_audio):
		await room.combat_audio.wait_for_cleanup()
	room.free()
	print("ROOM_OBJECTIVES_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
