extends Node
## Exercises the production objective host and B01 module. The room double only
## controls transaction acceptance; it deliberately does not deduplicate claims.
## Persistence/loot atomicity belongs to the separate real-core reward suite.
const Host = preload("res://scripts/gameplay/world/room_objectives.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")

class ClaimRoom extends Node2D:
	var player: Node2D = Node2D.new()
	var enemies: Node2D = Node2D.new()
	var obstructions: Array[Rect2] = []
	var layout: Dictionary = {}
	var combat_audio: Node = null
	var enemy_skills: Node2D = null
	var enemy_props: Node2D = null
	var combat_cleared: bool = false
	var save_succeeds: bool = true
	var sight_clear: bool = true
	var attempts: Array[String] = []
	var receipts: Array[String] = []
	var objective_events: Array[Dictionary] = []
	var navigation_invalidations: int = 0

	func _init() -> void:
		add_child(player)
		add_child(enemies)

	func claim_optional_objective_reward(id: String) -> bool:
		attempts.append(id)
		if not combat_cleared or not save_succeeds:
			return false
		receipts.append(id)
		return true

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return sight_clear

	func on_objective_event(event_name: String, data: Dictionary) -> void:
		objective_events.append({"name": event_name, "data": data.duplicate(true)})

	func invalidate_navigation() -> void:
		navigation_invalidations += 1

	func move_actor(at: Vector2, displacement: Vector2, _radius: float = 18.0) -> Vector2:
		return at + displacement

var room: ClaimRoom
var host: Node2D
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("OPTIONAL OBJECTIVE FAIL: " + description)

func fixture(id: String, cleared: bool = false, claimed: Array = []) -> void:
	if is_instance_valid(room):
		room.free()
	room = ClaimRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.layout = Layouts.build(id)
	room.obstructions.assign(room.layout.obstructions)
	room.player.position = room.layout.entry
	add_child(room)
	host = Host.new()
	room.add_child(host)
	if cleared:
		room.combat_cleared = true
		host.configure_cleared(room, room.layout, "objective", claimed)
	else:
		host.configure(room, room.layout, "objective")

func use(id: String) -> bool:
	if not host.elements.has(id):
		check(false, "test interaction exists: " + id)
		return false
	room.player.position = host.element(id).get("interaction_position", host.element(id).position)
	return host.interact(id, room.player)

func count_events(event_name: String) -> int:
	var count: int = 0
	for entry: Dictionary in room.objective_events:
		if str(entry.name) == event_name:
			count += 1
	return count

func visible_copy() -> String:
	var result: String = str(host.status().text) + " " + str(host.status().optional)
	for item: Dictionary in host.elements.values():
		result += " " + str(item.get("description", ""))
	return result

func assert_cleared_without_mechanics(id: String) -> void:
	check(host.finished and host.is_complete(), id + " remains complete after restoration")
	check(host.completed_count == host.required_count, id + " restores the completed requirement count")
	check(host.quality == "full", id + " restores a completed presentation without replaying a branch")
	check(host.hazards.is_empty(), id + " does not replay combat hazards")
	check(host.blockers.is_empty(), id + " does not recreate temporary collision blockers")
	check(host.targets.is_empty() and room.enemies.get_child_count() == 0, id + " does not spawn attackable objective actors")
	check(count_events("objective_completed") == 0, id + " does not recommit room completion during restoration")
	var initial_position: Vector2 = room.player.position
	var initial_obstructions: Array[Rect2] = room.obstructions.duplicate()
	for frame: int in 30:
		host.tick(0.1)
	check(room.player.position == initial_position, id + " completed mechanisms cannot displace the player")
	check(room.obstructions == initial_obstructions and host.hazards.is_empty(), id + " remains free of restored hazard/collision side effects after ticking")
	check(count_events("objective_completed") == 0, id + " ticking does not emit another completion")

func test_live_and_transaction_retries() -> void:
	fixture("L01")
	check(host.optional_ids() == ["side_crate"], "only the actual optional reward is enumerated")
	check(not host.claim_optional("side_crate"), "reward cannot bypass incomplete required objectives")
	check(not use("side_crate") and room.attempts.is_empty(), "interacting early does not call the reward transaction")
	check(not host.claim_optional("missing") and not host.claim_optional("brake_0"), "unknown and required-object ids cannot be claimed")
	check(room.attempts.is_empty(), "invalid claim ids do not reach the room transaction")
	for index: int in 3:
		check(use("brake_" + str(index)), "real authored brake " + str(index + 1) + " accepts the required order")
	check(host.finished and count_events("objective_completed") == 1, "normal three-brake play emits completion once")
	var completed_before: int = host.completed_count
	var completion_events_before: int = count_events("element_completed")
	check(not use("side_crate"), "objective completion alone cannot claim while combat remains live")
	check(room.attempts.size() == 1 and room.receipts.is_empty(), "live-combat rejection reaches the authoritative room gate")
	check(not host.element("side_crate").done and host.optional_ids().has("side_crate"), "combat rejection preserves the claimable crate")
	check(count_events("optional_salvage") == 0 and count_events("element_completed") == completion_events_before, "rejection emits no cosmetic success or element completion")
	room.combat_cleared = true
	room.save_succeeds = false
	check(not use("side_crate"), "failed persistence is returned to the interaction caller")
	check(room.attempts.size() == 2 and not host.element("side_crate").done, "failed persistence keeps the same crate available for retry")
	check(count_events("optional_salvage") == 0 and room.receipts.is_empty(), "failed persistence does not announce or consume loot")
	room.save_succeeds = true
	check(use("side_crate"), "the same crate succeeds after the room transaction recovers")
	check(room.attempts.size() == 3 and room.receipts == ["side_crate"], "exactly one accepted receipt is delivered")
	check(host.element("side_crate").done and host.optional_ids().is_empty(), "accepted receipt consumes the optional reward")
	check(host.completed_count == completed_before, "optional reward does not inflate the required objective count")
	check(count_events("optional_salvage") == 1 and count_events("objective_completed") == 1, "accepted optional reward emits one salvage event without another room completion")
	check(not use("side_crate") and not host.claim_optional("side_crate"), "interaction and direct claim paths both reject duplicates")
	check(room.attempts.size() == 3 and room.receipts.size() == 1, "host prevents duplicate calls even when the room double would accept them")

func test_distance_and_sight() -> void:
	fixture("L01", true)
	var at: Vector2 = host.element("side_crate").position
	room.player.position = at + Vector2(120, 0)
	check(host.nearby_interaction(room.player.position).is_empty(), "distant crate does not create an E prompt")
	check(not host.interact("side_crate", room.player) and room.attempts.is_empty(), "distant interaction cannot reach the transaction")
	room.player.position = at
	room.sight_clear = false
	check(host.nearby_interaction(at).is_empty(), "crate behind collision has no interaction prompt")
	check(not host.interact("side_crate", room.player) and room.attempts.is_empty(), "blocked sight cannot claim through obstacles")
	room.sight_clear = true
	check(str(host.nearby_interaction(at).get("id", "")) == "side_crate", "near visible crate offers the correct interaction")
	check(host.interact("side_crate", room.player) and room.receipts.size() == 1, "near visible crate routes through the transaction")

func test_cleared_restoration() -> void:
	fixture("L01")
	check(use("brake_0") and not host.hazards.is_empty(), "restoration starts from a real active minecart warning")
	var original_obstacles: Array[Rect2] = room.obstructions.duplicate()
	# Simulate a previously-owned blocker so reset must release it, not merely
	# conceal its drawing. Creation/topology validation is covered elsewhere.
	var old_blocker := Rect2(1200, 700, 40, 40)
	host.blockers["old_session"] = old_blocker
	room.obstructions.append(old_blocker)
	room.objective_events.clear()
	room.combat_cleared = true
	host.configure_cleared(room, room.layout, "objective", [])
	assert_cleared_without_mechanics("L01")
	check(room.obstructions == original_obstacles and room.navigation_invalidations == 1, "restoration removes the previous temporary collision from the room")
	check(host.elements.size() == 1 and host.elements.has("side_crate"), "L01 restores only the unclaimed side crate")
	check(not host.elements.has("brake_0") and not host.elements.has("passing_cart_0"), "restoration does not recreate controls or passing carts")
	check(host.optional_ids() == ["side_crate"], "restored optional reward is enumerated once")
	check(str(host.navigation_target().get("id", "")) == "side_crate", "completed-room navigation can still lead to its unclaimed reward")
	check(use("side_crate") and room.receipts.size() == 1, "restored optional crate remains usable")
	fixture("L01", true, ["side_crate"])
	assert_cleared_without_mechanics("L01 claimed")
	check(host.optional_ids().is_empty() and host.nearby_interaction(room.layout.exit).is_empty(), "saved claimed marker does not restore a fresh reward prompt")
	check(not host.elements.has("side_crate") or bool(host.element("side_crate").done), "saved claimed crate is absent or visibly consumed")
	check(not host.claim_optional("side_crate") and room.attempts.is_empty(), "saved claimed marker prevents duplicate transaction calls")
	fixture("L01", true, ["unknown_legacy_reward"])
	check(host.optional_ids() == ["side_crate"], "unrelated legacy claim id cannot consume the real side crate")
	for index: int in range(2, 25):
		if index == 11:
			continue
		var id: String = "L%02d" % index
		fixture(id, true)
		assert_cleared_without_mechanics(id)
		check(host.optional_ids().is_empty(), id + " does not invent a repeatable optional payout")
		check(host.elements.is_empty(), id + " does not reconstruct completed active mechanisms")
		check(not host.claim_optional("side_crate") and room.attempts.is_empty(), id + " cannot claim the L01-only side crate")

func open_research_nest(index: int) -> void:
	var id: String = "research_nest_%d" % index
	var target: Node2D = host.targets.get(id)
	check(is_instance_valid(target), "research package uses a real attackable nest " + str(index))
	if is_instance_valid(target):
		# Deliver the real health/death callback to the production host; combat
		# targeting and weapon damage are tested by the B02 integration suite.
		target.health.damage(target.health.maximum)
		check(not bool(host.element("research_%d" % index).sealed), "destroying the real nest unseals package " + str(index))

func test_research_optional() -> void:
	fixture("L11")
	check(host.optional_ids().has("research_2"), "L11 identifies its authored third-package optional reward")
	var text: String = str(host.element("research_2").description)
	check(text.contains("22") and text.contains("进攻") and text.contains("撤离"), "third package describes its 22-gold offensive gear and extraction requirement")
	for index: int in 2:
		open_research_nest(index)
		check(use("research_%d" % index), "opened required research package can be recovered")
	check(host.finished and host.completed_count == 2, "two required research packages finish the objective")
	room.combat_cleared = true
	room.player.position = host.element("research_2").position
	check(not host.claim_optional("research_2") and room.attempts.is_empty(), "public optional claim cannot bypass the sealed nest")
	check(not use("research_2") and room.attempts.is_empty(), "sealed research interaction cannot call the room transaction")
	open_research_nest(2)
	room.combat_cleared = false
	check(not use("research_2"), "unsealed optional research still respects the live-combat room gate")
	check(not bool(host.element("research_2").done) and not bool(host.module.state.optional), "live-combat rejection preserves package and module state")
	room.combat_cleared = true
	room.save_succeeds = false
	check(not use("research_2"), "optional research propagates a failed save")
	check(not bool(host.element("research_2").done) and not bool(host.module.state.optional), "failed save leaves the research reward retryable")
	check(count_events("optional_research_recovered") == 0 and room.receipts.is_empty(), "failed research claims emit no success event or receipt")
	room.save_succeeds = true
	check(use("research_2"), "unsealed research can be claimed after persistence recovers")
	check(bool(host.element("research_2").done) and bool(host.module.state.optional), "successful research receipt updates both host and module state")
	check(host.completed_count == 2 and count_events("objective_completed") == 1, "optional research does not repeat or inflate the required completion")
	check(room.receipts == ["research_2"] and count_events("optional_research_recovered") == 1, "optional research reports exactly one accepted receipt")
	var attempts: int = room.attempts.size()
	check(not use("research_2") and not host.claim_optional("research_2") and room.attempts.size() == attempts, "research cannot be collected a second time through either entry point")
	fixture("L11", true)
	assert_cleared_without_mechanics("L11")
	check(host.elements.size() == 1 and host.elements.has("research_2"), "cleared L11 restores only its unclaimed third package")
	check(not bool(host.element("research_2").sealed), "restored third package is unsealed without reconstructing its nest")
	check(host.optional_ids() == ["research_2"], "restored L11 reward remains discoverable")
	check(use("research_2") and room.receipts == ["research_2"], "restored L11 package can deliver its deferred reward")
	fixture("L11", true, ["research_2"])
	assert_cleared_without_mechanics("L11 claimed")
	check(host.elements.is_empty() and host.optional_ids().is_empty(), "claimed research marker restores neither package nor old targets")
	check(not host.claim_optional("research_2") and room.attempts.is_empty(), "claimed research marker prevents another room transaction")

func test_reward_descriptions() -> void:
	fixture("L01")
	var text: String = str(host.element("side_crate").description)
	check(text.contains("18") and text.contains("防具") and text.contains("撤离"), "side crate explains its 18 gold, class armor and extraction requirement")
	fixture("L02")
	text = visible_copy()
	check(text.contains("18") and text.contains("防具") and text.contains("34"), "escort presents distinct intact-cargo equipment and fast-unload gold outcomes")
	check(not text.contains("降低奖励"), "escort no longer mislabels the higher-cash alternative as a flat reward reduction")
	fixture("L03")
	text = visible_copy()
	check(text.contains("30") and text.contains("12") and text.contains("机动"), "gear choice explains the stopped cash outcome versus moving-platform mobility gear")
	fixture("L04")
	text = visible_copy()
	check(text.contains("14") and text.contains("进攻"), "sorting displays its 14-gold offensive gear reward")
	fixture("L05")
	text = visible_copy()
	check(text.contains("18") and (text.contains("生存") or text.contains("防具")), "rescue displays its 18-gold survival reward")
	fixture("L06")
	text = str(host.element("furnace_core").description)
	check(text.contains("24") and text.contains("进攻") and (text.contains("2") or text.contains("两")), "precision core explains the 24-gold two-offensive-item reward")
	text = str(host.element("furnace_cut").description)
	check(text.contains("8") and (text.contains("无装备") or text.contains("不含装备") or text.contains("无装")), "emergency bypass states its 8-gold no-equipment outcome")

func run_checks() -> void:
	if not Game.profile_path.contains("test_optional_objective_runtime"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	var api_probe: Node2D = Host.new()
	var ready_api: bool = api_probe.has_method("configure_cleared") and api_probe.has_method("optional_ids") and api_probe.has_method("claim_optional")
	api_probe.free()
	check(ready_api, "production optional reward/restoration APIs are present")
	if ready_api:
		test_live_and_transaction_retries()
		test_distance_and_sight()
		test_cleared_restoration()
		test_research_optional()
		test_reward_descriptions()
	if is_instance_valid(room):
		room.free()
	print("OPTIONAL_OBJECTIVE_RUNTIME_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
