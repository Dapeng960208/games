extends "res://tests/test_core_expedition.gd"
## Synthetic safe-boundary helpers only traverse the earlier rooms. After the
## purchase, real Game transactions, Room restore, Player damage and HUD run.
## tools/test.ps1 -Suite supply_guard -SkipImport -SkipRestart

const Status = preload("res://scripts/combat/combat_status.gd")
const Coordinator = preload("res://scripts/world/expedition_controller.gd")
var game: Node
var room: Node2D
var hud: Control
var hud_layer: CanvasLayer
var RoomScene: PackedScene
var HudScene: PackedScene
var ready_source: String
var active_source: String
var entry: Dictionary
var guard_amount: float

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SUPPLY GUARD FAIL: " + label)

func _near(actual: float, expected: float, label: String) -> void:
	_check(is_equal_approx(actual, expected), label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_supply_guard"):
		push_error("Refusing non-test supply guard profile")
		quit(2)
		return
	game.set_process(false)
	create_timer(60.0).timeout.connect(func(): push_error("Supply guard acceptance timed out"); quit(1))
	RoomScene = load("res://scenes/room.tscn")
	HudScene = load("res://scenes/hud.tscn")
	root.size = Vector2i(1280,720)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	_start(game)
	if game.run == null:
		quit(1)
		return
	var supply_index: int = Expedition.Routes.supply_index(game.run.expedition.route)
	for index: int in range(1, supply_index + 1):
		if not _advance(game):
			quit(1)
			return
		if index != supply_index: _complete(game, {"gold":80,"xp":0,"mastery":0})
	var shield_offer: Dictionary = {}
	for offer: Dictionary in game.expedition_snapshot().supply_offers:
		if offer.product_id == "shield": shield_offer = offer
	_check(not shield_offer.is_empty() and int(shield_offer.get("price",0)) == 40, "real supply offers charge forty gold")
	var before_gold: int = game.run.gold
	_check(game.purchase_run_supply(shield_offer.offer_id, _runtime(game)), "purchase through production transaction")
	_check(game.run.gold == before_gold - 40, "purchase debits exactly forty")
	_check(game.run.expedition.temporary_buffs.get("pending_supply_shield",{}) == {"hp_ratio":0.15,"duration":4.0}, "pending product schema is unchanged")
	_check(game.run.shield == 0.0, "safe supply purchase does not activate the next-room shield early")
	_check(game.purchase_run_supply(shield_offer.offer_id, _runtime(game)) and game.run.gold == before_gold - 40, "same purchase retry is idempotent")
	_check(_advance(game), "enter the combat room after supply")
	ready_source = "supply:ready:" + str(game.run.expedition.node_index)
	active_source = "supply:active:" + str(game.run.expedition.node_index)
	guard_amount = game.run.max_hp * 0.15
	entry = game.expedition_snapshot().runtime.duplicate(true)
	_check(entry.status.guards.has(ready_source) and not game.run.expedition.temporary_buffs.has("pending_supply_shield"), "committed entry consumes pending purchase once and carries ready source")
	_near(game.run.shield, guard_amount, "entry grants fifteen percent maximum HP")
	if not _construct_room():
		quit(1)
		return
	_near(room.player.status.guards[ready_source].remaining, 4.0, "real room entry restores the unspent four seconds")
	_check(room.player.status.guards.size() == 1, "fresh room restore does not double the purchased pool")
	_test_ready_and_blocks()
	_test_validation()
	_test_external_capture()
	_test_pool_rules()
	_check(room.restore_expedition_runtime(entry), "restore original paid entry for durable lifecycle")
	# Isolated test fixture: mark this disabled simulation's combat boundary clear
	# through the normal completion transaction, enabling legal checkpoint saves.
	var completion: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	_check(game.commit_expedition_completion(completion, room.expedition_runtime_snapshot(), {}), "commit a safe fixture boundary using the actual actor snapshot")
	await _reload_room("ready")
	_check(room.player.status.guards.has(ready_source) and not room.player.status.guards.has(active_source), "disk reload preserves waiting state")
	_tick(5.2)
	_near(game.run.shield, guard_amount, "loaded reserve survives more than five seconds")
	var standing: Array = hud.coverage_rects()
	_check_hud(true, 4.0)
	await _capture("ready_zh")
	load("res://scripts/ui/strings.gd").set_locale("en")
	hud.refresh()
	await _capture("ready_en")
	load("res://scripts/ui/strings.gd").set_locale("zh_CN")
	hud.refresh()
	var hp_before: float = game.run.hp
	_check(room.player.receive_damage(3.0, room.player.position - Vector2(10,0), {"damage_type":"true"}), "real player damage is accepted")
	_check(not room.player.status.guards.has(ready_source) and room.player.status.guards.has(active_source), "first actual absorption atomically activates the reserve")
	_near(game.run.shield, guard_amount - 3.0, "actual absorbed damage consumes the guard")
	_near(game.run.hp, hp_before, "the absorbed hit leaves health intact")
	_near(room.player.status.guards[active_source].remaining, 4.0, "trigger retains the full four-second duration")
	_tick(1.25)
	_check_hud(false, 2.75)
	await _capture("active_zh")
	var paused_guard: Dictionary = room.player.status.guards.duplicate(true)
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	room.set_physics_process(false)
	paused = true
	room.player._physics_process(7.0)
	for frame: int in 3:
		await physics_frame
		await process_frame
	_check(room.player.status.guards == paused_guard, "paused production player does not advance an active shield")
	paused = false
	for frame: int in 2:
		await physics_frame
		await process_frame
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var remaining_before_reload: float = room.player.status.guards[active_source].remaining
	_check(remaining_before_reload < 2.75 and remaining_before_reload > 2.5, "unpausing real physics resumes the active countdown")
	await _reload_room("active")
	_check(room.player.status.guards.has(active_source) and not room.player.status.guards.has(ready_source), "disk reload cannot rearm an active shield")
	_near(room.player.status.guards[active_source].remaining, remaining_before_reload, "disk reload preserves partially spent time")
	_tick(remaining_before_reload-0.10)
	_check(game.run.shield > 0.0, "active shield survives until its actual deadline")
	_tick(0.11)
	_check(game.run.shield == 0.0 and room.player.status.guards.is_empty(), "four seconds after absorption the reserve expires")
	hud.refresh()
	_check(not hud.buff_chips.has("supply_guard") and not hud.buff_row.visible and hud.active_buff_coverage_rects().is_empty(), "expired reserve removes its temporary HUD chip")
	_check(hud.coverage_rects() == standing, "reserve does not enlarge the permanent HUD footprint")
	await _test_transition_cleanup()
	await _destroy_room()
	print("SUPPLY GUARD: %d/%d passed; purchase/real player/restore/HUD; graphics=%s (controlled UI states, not native-speed combat)" % [checks-failures, checks, DisplayServer.get_name() != "headless"])
	quit(1 if failures else 0)

func _construct_room() -> bool:
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var prepared: Dictionary = room.prepare_expedition_node(Coordinator.new(game).current_context())
	_check(bool(prepared.get("valid",false)), "production coordinator prepares the committed room")
	if not bool(prepared.get("valid",false)): return false
	room.apply_prepared_expedition_node(prepared)
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	room.combat_audio.set_process(false)
	hud = HudScene.instantiate()
	hud.room = room
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	root.add_child(hud_layer)
	hud_layer.add_child(hud)
	hud.refresh()
	return room.configuration_ready

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# Static UI proof after explicit production-state steps. Only the camera is
	# recentered here; this is not presented as normal-clock combat footage.
	room.camera.global_position = room.player.global_position
	room.camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/supply_guard")
	var captured: Image = root.get_texture().get_image()
	_check(captured.get_size() == Vector2i(1280,720) and captured.save_png("res://artifacts/supply_guard/"+label+".png") == OK, "capture actual reserve HUD "+label)

func _destroy_room() -> void:
	if is_instance_valid(hud):
		hud.free()
		hud = null
	if is_instance_valid(hud_layer):
		hud_layer.free()
		hud_layer = null
	if is_instance_valid(room):
		_check(await room.combat_audio.wait_for_cleanup(), "fixture audio cleanup completes")
		room.free()
		room = null
	await process_frame

func _reload_room(label: String) -> void:
	_check(game.save_expedition_checkpoint(room.expedition_runtime_snapshot()), label + " saves through legal checkpoint API")
	var expected: Dictionary = game.expedition_snapshot().runtime.duplicate(true)
	await _destroy_room()
	game.reload_profile()
	_check(game.run != null and _same_json(expected, game.expedition_snapshot().runtime), label + " survives actual profile-store JSON reload")
	_check(_construct_room(), label + " constructs and restores a fresh production room")

func _same_json(a: Variant, b: Variant) -> bool:
	# JSON parses integer-valued fields as floats and rounds decimal tails. Check
	# every key/item and allow only tiny numeric serialization error, not timing drift.
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: String in a:
			if not b.has(key) or not _same_json(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in a.size():
			if not _same_json(a[index], b[index]): return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a)-float(b)) < 0.00000001
	return a == b

func _tick(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed + 0.000001 < seconds:
		var step: float = minf(1.0/60.0, seconds-elapsed)
		room.player._physics_process(step)
		elapsed += step

func _test_ready_and_blocks() -> void:
	var at: Vector2 = room.player.position
	Input.action_press("move_right")
	_tick(6.0)
	Input.action_release("move_right")
	_check(room.player.position.distance_to(at) > 1.0, "six-second wait also executes actual player walking")
	_near(game.run.shield, guard_amount, "walking six seconds preserves full reserve")
	_near(room.player.status.guards[ready_source].remaining, 4.0, "waiting does not count down")
	var origin: Vector2 = room.player.position - Vector2(10,0)
	_check(not room.player.receive_damage(0.0, origin), "zero damage cannot activate reserve")
	room.player.invulnerable = 1.0
	_check(not room.player.receive_damage(10.0, origin), "hurt invulnerability blocks activation")
	room.player.invulnerable = 0.0
	room.player.status.apply("invulnerable", 1.0, 0.1)
	_check(not room.player.receive_damage(10.0, origin), "status invulnerability blocks activation")
	_tick(0.2)
	_check(not room.player.receive_damage(10.0, origin, {"invulnerable":true}), "damage-context immunity blocks activation")
	_check(room.player.status.guards.has(ready_source) and not room.player.status.guards.has(active_source), "all rejected hits leave the reserve waiting")
	_check_hud(true, 4.0)

func _check_hud(prepared: bool, remaining: float) -> void:
	hud.refresh()
	_check(hud.buff_chips.has("supply_guard") and hud.buff_chips.size() == 1, "one live supply chip represents the actual guard")
	if not hud.buff_chips.has("supply_guard"): return
	var chip: Button = hud.buff_chips.supply_guard
	_check(bool(chip.state.prepared) == prepared and is_equal_approx(float(chip.state.remaining), remaining), "HUD ready/countdown branch uses actual guard state")
	_check(chip.remaining_seconds() == ceili(remaining), "active timer readout is rounded from live seconds")
	var info: Dictionary = hud.buff_info("supply_guard")
	_check((str(info.summary).contains("待机") or str(info.summary).contains("Ready")) == prepared, "tooltip differentiates waiting from an active countdown")
	_check(hud.active_buff_coverage_rects().size() == 1 and hud.active_buff_coverage_rects()[0].size == Vector2(40,40) and chip.size == Vector2(44,44), "temporary reserve uses the existing forty-pixel paint and forty-four-pixel target")

func _test_external_capture() -> void:
	_check(room.restore_expedition_runtime(entry), "reset exact paid entry for external-damage branch")
	game.damage_player(2.0, {"damage_type":"true"})
	var live_before: Dictionary = room.player.status.guards.duplicate(true)
	var captured: Dictionary = room.expedition_runtime_snapshot()
	_check(not captured.is_empty() and captured.status.guards.has(active_source), "capture activates copied ready guard after external RunState shield damage")
	_check(room.player.status.guards == live_before, "capture remains read-only for the source status")
	_near(captured.status.guards[active_source].amount, guard_amount-2.0, "external damage is consumed once in captured pool")
	_check(room.restore_expedition_runtime(captured), "external-damage snapshot restores")
	_near(game.run.shield, guard_amount-2.0, "restore does not consume external damage twice")

func _test_pool_rules() -> void:
	_check(room.restore_expedition_runtime(entry), "reset entry for independent skill-guard branch")
	room.player.grant_guard(game.run.max_hp * 0.25, 1.0, "hero:test")
	_near(game.run.shield, game.run.max_hp * 0.25, "multiple shields use maximum pool rather than sum")
	_tick(1.1)
	_check(not room.player.status.guards.has("hero:test") and room.player.status.guards.has(ready_source), "ordinary skill shield expires while reserve stays ready")
	_near(game.run.shield, guard_amount, "expired larger shield reveals intact reserve")
	room.player.grant_guard(game.run.max_hp * 0.25, 1.0, "hero:test")
	room.player.invulnerable = 0.0
	_check(room.player.receive_damage(2.0, room.player.position-Vector2(10,0), {"damage_type":"true"}), "actual hit consumes coexisting guard pools")
	_near(room.player.status.guards[active_source].amount, guard_amount-2.0, "maximum-pool rule consumes and activates the reserve alongside the larger shield")
	_near(game.run.shield, game.run.max_hp*0.25-2.0, "effective shield still equals the greatest remaining pool")
	var legacy: Dictionary = entry.duplicate(true)
	legacy.status.guards = {"supply:entry":{"amount":guard_amount,"remaining":0.4}}
	_check(Snapshot.validate(legacy, game.run.hero_id, game.run.stats) and room.restore_expedition_runtime(legacy), "legacy supply:entry schema still restores")
	_tick(0.41)
	_check(game.run.shield == 0.0, "legacy entry shield keeps its previous elapsed-time behavior")

func _test_validation() -> void:
	_check(Snapshot.validate(entry, game.run.hero_id, game.run.stats), "purchased ready entry validates unchanged v1 schema")
	for suffix: String in ["", "01", "-1", "+1", "1.0", "node"]:
		var invalid: Dictionary = entry.duplicate(true)
		invalid.status.guards = {"supply:ready:"+suffix:{"amount":guard_amount,"remaining":4.0}}
		_check(not Snapshot.validate(invalid, game.run.hero_id, game.run.stats), "reject noncanonical ready node suffix: " + suffix)
	for patch: Dictionary in [{"remaining":3.9},{"remaining":5.0},{"amount":guard_amount+1.0},{"amount":-1.0},{"amount":"12"},{"unexpected":true}]:
		var invalid: Dictionary = entry.duplicate(true)
		invalid.status.guards[ready_source].merge(patch, true)
		_check(not Snapshot.validate(invalid, game.run.hero_id, game.run.stats), "reject malformed or overpowered ready guard " + str(patch))
	var guards_before: Dictionary = room.player.status.guards.duplicate(true)
	var invalid: Dictionary = entry.duplicate(true)
	invalid.status.guards[ready_source].remaining = 2.0
	_check(not room.restore_expedition_runtime(invalid) and room.player.status.guards == guards_before, "invalid restore is rejected atomically")

func _test_transition_cleanup() -> void:
	# Branch from the genuine paid-entry snapshot to prove an UNUSED reserve is
	# removed too; include supported old/active pools to cover the entire prefix.
	var transition: Dictionary = entry.duplicate(true)
	transition.status.guards["supply:entry"] = {"amount":2.0,"remaining":2.0}
	transition.status.guards[active_source] = {"amount":3.0,"remaining":1.0}
	transition.status.guards["hero:test"] = {"amount":5.0,"remaining":2.0}
	_check(room.restore_expedition_runtime(transition), "valid transition fixture includes all three supply source forms")
	var runtime: Dictionary = room.expedition_runtime_snapshot()
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		_check(game.choose_run_relic(offer.offer_id, "skip", "", runtime), "resolve required offer before leaving shield room")
	var next: Dictionary = game.expedition_snapshot().next_node
	_check(not next.is_empty(), "route has a following room for one-room scope test")
	if next.is_empty(): return
	_check(game.choose_expedition_node(int(next.node_index), str(next.room_id)), "select subsequent production room")
	_check(game.advance_expedition_node(runtime), "commit following room with live source pools")
	var sources: Dictionary = game.expedition_snapshot().runtime.status.guards
	_check(sources.keys() == ["hero:test"], "transition removes ready, active and legacy supply pools but retains ordinary shield")
	_check(not game.run.expedition.temporary_buffs.has("pending_supply_shield") and is_equal_approx(game.run.shield, 5.0), "consumed purchase is not awarded again on the following room")
	await _destroy_room()
	_check(_construct_room(), "following room restores committed cleanup")
	hud.refresh()
	_check(not hud.buff_chips.has("supply_guard"), "next room has no stale supply HUD chip")
