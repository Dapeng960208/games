extends Node
## Round-two combat fixes through pure reducers and real player/controller paths.
const Stats = preload("res://scripts/combat/stat_resolver.gd")
const Status = preload("res://scripts/combat/combat_status.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Trail = preload("res://scripts/combat/recent_damage_trail.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const RoomScene = preload("res://scenes/room.tscn")
# Exported by committed pre-fix CombatSnapshot.capture with level20 starter +5,
# full HP260/resource100 and both maximum hero130/equipment91 shield pools.
const LEGACY_CAPACITY_JSON := '''{"equipment":{"adapter":{"clock":0.0,"event_serial":0,"modifiers":{"attack_speed_bonus":0.0,"chill_duration_bonus":0.0,"cost_reduction":0.0,"crit_bonus":0.0,"damage_bonus":0.03,"damage_reduction_bonus":0.0,"knockback_scale":1.0,"move_speed_bonus":0.0,"received_knockback_scale":0.9,"slow_resistance":0.0},"movement_time":0.0,"self_status_sources":{}},"buffs":{},"clock":0.0,"cooldowns":{},"counts":{},"dash_time":-100.0,"delayed_shield_at":-1.0,"eq12_spent_at":0.0,"heal_history":[],"movement_time":0.0,"refund_history":[],"resource_history":[],"room_first_kill_used":false,"room_id":"","room_low_shield_used":false,"rooms":{},"undamaged_time":0.0,"windows":{}},"hero_id":"CH01","hp":260.0,"mode":"safe_boundary","player":{"aim_direction":[1.0,0.0],"cast_serial":0,"combat_time":5.0,"cooldowns":{"f":0.0,"q":0.0,"secondary":0.0,"ultimate":0.0},"dash_cooldown":0.0,"invulnerable":0.0,"passive_cooldown":0.0,"passive_count":0,"rage_hurt_cooldown":0.0,"resource_delay":0.0,"shot_cooldown":0.0,"walk_distance":0.0},"resource":100.0,"snapshot_version":1,"status":{"clock":0.0,"guards":{"equipment:EQ21":{"amount":91.0,"remaining":3.0},"hero:f":{"amount":130.0,"remaining":4.0}},"origins":{},"shock_cooldown":0.0,"slow_multiplier":1.0,"slow_remaining":0.0,"states":{}}}'''
# Likewise exported before the fix for CH03 / EQ04+1: max mana117, not116.5.
const LEGACY_MANA_JSON := '''{"equipment":{"adapter":{"clock":0.0,"event_serial":0,"modifiers":{"attack_speed_bonus":0.0,"chill_duration_bonus":0.0,"cost_reduction":0.0,"crit_bonus":0.0,"damage_bonus":0.0,"damage_reduction_bonus":0.0,"knockback_scale":1.0,"move_speed_bonus":0.0,"received_knockback_scale":1.0,"slow_resistance":0.0},"movement_time":0.0,"self_status_sources":{}},"buffs":{},"clock":0.0,"cooldowns":{},"counts":{},"dash_time":-100.0,"delayed_shield_at":-1.0,"eq12_spent_at":0.0,"heal_history":[],"movement_time":0.0,"refund_history":[],"resource_history":[],"room_first_kill_used":false,"room_id":"","room_low_shield_used":false,"rooms":{},"undamaged_time":0.0,"windows":{}},"hero_id":"CH03","hp":126.0,"mode":"safe_boundary","player":{"aim_direction":[1.0,0.0],"cast_serial":0,"combat_time":5.0,"cooldowns":{"f":0.0,"q":0.0,"secondary":0.0,"ultimate":0.0},"dash_cooldown":0.0,"invulnerable":0.0,"passive_cooldown":0.0,"passive_count":0,"rage_hurt_cooldown":0.0,"resource_delay":0.0,"shot_cooldown":0.0,"walk_distance":0.0},"resource":117.0,"snapshot_version":1,"status":{"clock":0.0,"guards":{"equipment:EQ21":{"amount":44.1,"remaining":3.0},"hero:f":{"amount":63.0,"remaining":4.0}},"origins":{},"shock_cooldown":0.0,"slow_multiplier":1.0,"slow_remaining":0.0,"states":{}}}'''
var checks := 0
var failures := 0
var room: MineRoom
var emitted_result: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AUDIT COMBAT FAIL: " + label)

func near(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual, expected), label + " actual=" + str(actual) + " expected=" + str(expected))

func test_precision_and_purchase() -> void:
	var previous: Dictionary = {}
	for level: int in range(6):
		var stats: Dictionary = Stats.resolve("CH01", 1, {"weapon":"EQ01"}, {"EQ01":{"level":level}})
		near(stats.equipment_contribution.attack, 4.0 * (1.0 + level * 0.1), "exact weapon attack +" + str(level))
		near(stats.armor_penetration, 3.0 * (1.0 + level * 0.1), "exact weapon penetration +" + str(level))
		if not previous.is_empty():
			check(Damage.resolve(stats.attack, "physical", stats, {"armor":30.0}).damage > Damage.resolve(previous.attack, "physical", previous, {"armor":30.0}).damage, "each tier increases real resolved damage")
		previous = stats
	check(Game.new_profile() and Game.start_run(), "isolated starter run")
	check(Game.add_gold(120), "starter earns gold through production transaction")
	check(not Game.finish_run("extracted").is_empty(), "earned gold settles")
	var before: Dictionary = Game.selected_stats()
	near(Game.upgrade_cost("EQ01"), 60.0, "first enhancement keeps historical cost")
	check(Game.upgrade_equipment("EQ01", "audit_first_enhancement"), "first paid enhancement succeeds")
	near(Game.selected_stats().attack - float(before.attack), 0.4, "paid first tier grants actual attack")
	near(Game.selected_stats().armor_penetration - float(before.armor_penetration), 0.3, "paid first tier grants actual penetration")
	near(Game.profile.permanent_gold, 60, "only historical cost charged")
	Game.reload_profile()
	check(Game.equipment_level("EQ01") == 1 and Game.upgrade_equipment("EQ01", "audit_first_enhancement"), "historical tier and receipt survive reload/retry")
	near(Game.profile.permanent_gold, 60, "retry cannot charge twice")

func test_status_merge() -> void:
	for id: String in ["burn", "corrosion", "bleed", "shock", "chill", "damage_reduction", "brace_guard"]:
		var state := Status.new()
		var strong: float = 0.5 if id in ["damage_reduction", "brace_guard"] else 100.0
		var weak: float = strong * 0.2
		check(state.apply(id, strong, 3.0), "strong accepted " + id)
		check(not state.apply(id, weak, 9.0), "same-frame weak rejected " + id)
		state.tick(0.25)
		var prior: Dictionary = state.states[id].duplicate(true)
		check(not state.apply(id, weak, 9.0) and state.states[id] == prior, "cross-frame weak preserves power/time/fingerprint " + id)
		check(state.apply(id, strong, 1.0), "equal accepts refresh " + id)
		near(state.states[id].remaining, 2.75, "short equal never truncates " + id)
		state.tick(0.25)
		check(state.apply(id, strong, 4.0), "equal extends its own snapshot " + id)
		near(state.states[id].remaining, 4.0, "equal refresh duration " + id)
		state.states.clear()
		state.apply(id, weak, 9.0)
		state.tick(0.25)
		check(state.apply(id, strong, 1.0), "strong replaces weaker " + id)
		near(state.states[id].remaining, 1.0, "strong never inherits weaker long timer " + id)
		state.tick(1.0)
		check(not state.has(id), "replaced weak source cannot reappear or stack " + id)
	var dots := Status.new()
	dots.apply("burn", 100.0, 3.0)
	dots.tick(0.75)
	dots.apply("burn", 20.0, 8.0)
	var ticks: Array[Dictionary] = dots.tick(0.25)
	check(ticks.size() == 1, "one family releases one tick after weak refresh")
	near(ticks[0].damage, 12.0, "strongest DoT snapshot retained without stacking")
	dots.tick(2.0)
	check(not dots.has("burn"), "weak refresh cannot extend strong duration")

func test_shared_shields() -> void:
	var state := Status.new()
	state.grant_guard(12.0, 4.0, "hero", 100.0)
	state.grant_guard(5.0, 7.0, "equipment:EQ01", 100.0, true)
	var summary: Dictionary = state.shield_summary()
	near(summary.effective_capacity, 12.0, "overlap is maximum not sum")
	near(summary.coverage_seconds, 7.0, "coverage includes weaker longer source")
	check(summary.rule == "shared_max" and summary.source_count == 2, "UI exposes shared pool rule and active sources")
	near(state.absorb(10.0), 0.0, "ten fully absorbed")
	near(state.guards.hero.amount, 2.0, "strong shield leaves two")
	near(state.guards["equipment:EQ01"].amount, 0.0, "weak overlapping shield depleted simultaneously")
	near(state.shield_summary().total_absorbed, 10.0, "absorbed counts actual damage once")
	state.tick(0.0)
	near(state.shield_summary().source_count, 1, "depleted source not displayed")
	state.tick(1.0)
	state.grant_guard(5.0, 4.0, "equipment:EQ01", 100.0, true)
	near(state.shield(), 5.0, "staggered fresh shield raises effective pool")
	near(state.absorb(8.0), 3.0, "overflow remains health damage")
	near(state.total_absorbed, 15.0, "staggered absorption adds effective amount only")
	state.grant_guard(12.0, 7.0, "hero", 100.0)
	state.grant_guard(5.0, 4.0, "supply:ready:2", 100.0)
	summary = state.shield_summary()
	near(summary.active_coverage_seconds, 7.0, "active shield already has a running timer")
	near(summary.prepared_coverage_seconds, 4.0, "reserve timer displayed separately")
	state.tick(1.0)
	near(state.shield_summary().active_coverage_seconds, 6.0, "active shield timer advances independently")
	near(state.shield_summary().prepared_coverage_seconds, 4.0, "reserve waits for absorption")
	state.absorb(1.0)
	check(not state.shield_summary().prepared, "actual absorption activates reserve timer")

func test_trail_bounds() -> void:
	var trail := Trail.new()
	for index: int in range(40):
		trail.record(1, 1, 100, 100, 1, 0, {"source_id":"M01"}, index * 0.1)
	var summary: Dictionary = trail.summary()
	check(summary.recent_events.size() == Trail.MAX_EVENTS, "recent trail has hard event limit")
	near(summary.total_absorbed, 40, "shield-only hits remain evidence without HP damage")
	summary.recent_events[0].source_id = "mutated"
	check(trail.summary().recent_events[0].source_id == "M01", "UI receives detached values")
	trail.record(2, 2, 2, 0, 0, 0, {"dot":true,"status":"burn","source_name":"x".repeat(500),"key_states":["burn","burn","untrusted"]}, 30)
	summary = trail.summary()
	check(summary.recent_events.size() == 1 and summary.lethal_event.lethal, "old events expire, lethal event retained")
	check(summary.lethal_event.source_name.length() == Trail.TEXT_LIMIT and summary.lethal_event.key_states == ["burn"], "event fields remain bounded and whitelisted")
	trail.record(NAN, 5, 10, 5, 0, 0, {}, 31)
	check(trail.summary().recent_events.size() == 1, "invalid event rejected")
	trail.clear()
	check(trail.summary().recent_events.is_empty() and trail.summary().total_absorbed == 0.0, "new session clears runtime history")

func fixture() -> void:
	if is_instance_valid(room): room.free()
	Game.run.stats = Stats.resolve("CH01", 1, {"head":"EQ20"}, {"EQ20":{"level":0}})
	Game.run.loadout_snapshot = {"head":"EQ20"}
	Game.run.equipment_snapshot = {"EQ20":{"level":0}}
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 0.0
	Game.run.shield = 0.0
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(600,600)
	Game.damage_trail.clear()

func test_live_sources_and_death() -> void:
	check(Game.start_run(), "live audit run starts")
	fixture()
	room.player.loadout.event("dash", {"event_id":"audit_eq20"})
	var original: Dictionary = Snapshot.capture(room)
	check(original.equipment.adapter.self_status_sources.has("damage_reduction"), "equipment owns accepted reduction snapshot")
	room.player.status.tick(0.1)
	room.player.status.apply("damage_reduction", 0.01, 10.0)
	var snapshot: Dictionary = Snapshot.capture(room)
	check(snapshot.equipment.adapter.self_status_sources.has("damage_reduction"), "rejected weak external write retains equipment provenance")
	var removed: Dictionary = Snapshot.for_loadout(snapshot, {"head":"EQ20"}, {}, Stats.resolve("CH01", 1, {}, {}), "CH01", Game.run.stats)
	check(not removed.is_empty() and not removed.status.states.has("damage_reduction"), "unequip removes original winning source")
	room.player.status.apply("damage_reduction", 0.5, 1.0)
	snapshot = Snapshot.capture(room)
	removed = Snapshot.for_loadout(snapshot, {"head":"EQ20"}, {}, Stats.resolve("CH01", 1, {}, {}), "CH01", Game.run.stats)
	check(not removed.is_empty() and removed.status.states.has("damage_reduction"), "strong external replacement survives old source removal")
	room.player.status.states.clear()
	var caster: MineEnemy = room.spawn_enemy(Vector2(650,600), "M01", 1)
	room.player.grant_guard(12.0, 4.0, "hero:test")
	room.player.grant_guard(5.0, 5.0, "equipment:test")
	var command := {"owner":weakref(caster),"owner_id":caster.get_instance_id(),"damage":10.0,"damage_type":"true","action_id":"audit_swing"}
	check(room.enemy_skills._deal(room.player, command, caster.position), "real enemy producer delivers attributed hit")
	var event: Dictionary = Game.damage_trail.summary().recent_events.back()
	check(event.source_id == "M01" and event.attack_id == "audit_swing" and event.kind == "direct", "enemy and attack identity reaches direct evidence")
	near(event.shield_absorbed, 10, "direct shield-only event records absorption")
	near(room.player.shield_summary().total_absorbed, 10, "player shield feedback agrees with controller")
	room.player.shield_summary()
	near(room.player.status.total_absorbed, 10, "repeated HUD reads do not double-count absorption")
	room.player.receive_enemy_status({"id":"burn","power":100.0,"duration":3.0,"source_id":"M10","attack_id":"strong_fire","origin":Vector2(100,100)})
	room.player._physics_process(0.25)
	room.player.receive_enemy_status({"id":"burn","power":20.0,"duration":9.0,"source_id":"M11","attack_id":"weak_fire","origin":Vector2(200,200)})
	room.player._physics_process(0.75)
	event = Game.damage_trail.summary().recent_events.back()
	check(event.kind == "dot" and event.status == "burn" and event.source_id == "M10" and event.attack_id == "strong_fire", "cross-frame weak DOT cannot steal winning attribution")
	check(room.player._enemy_status_origins.burn == Vector2(100,100), "weak DOT cannot steal knockback/source origin")
	room.player.status.states.clear()
	room.player.receive_enemy_status({"id":"shock","power":100.0,"duration":3.0,"source_id":"M04","attack_id":"shock_charge"})
	Game.run.hp = 2.0
	room.player.invulnerable = 0.0
	Game.run_finished.connect(func(value: Dictionary): emitted_result = value.duplicate(true))
	room.player.receive_damage(1.0, caster.position, {"damage_type":"true","source_id":"M01","attack_id":"trigger"})
	check(Game.run == null and not emitted_result.is_empty(), "lethal shock settles synchronously")
	var review: Dictionary = emitted_result.get("death_review", {})
	check(not review.is_empty() and review.lethal_event.kind == "shock", "death identifies charged secondary magic packet")
	check(review.lethal_event.source_id == "M04" and review.lethal_event.attack_id == "shock_charge", "shock death attributed to status caster, not trigger attacker")
	check("shock" in review.lethal_event.key_states, "death retains key pre-hit status")
	check(Game.last_result.get("death_review", {}) == review, "session result retains evidence for reopen")
	check(not JSON.stringify(Game.profile).contains("death_review") and not FileAccess.get_file_as_string(Game.profile_path).contains("death_review"), "death evidence never bloats persistent profile")
	Game.reload_profile()
	check(not Game.last_result.has("death_review") and Game.damage_trail.summary().recent_events.is_empty(), "reload does not invent old runtime evidence")
	check(await room.combat_audio.wait_for_cleanup(), "audio completes before teardown")
	room.free()
	room = null

func test_legacy_capacity_checkpoint() -> void:
	check(Game.start_run(), "legacy checkpoint test starts isolated run")
	fixture()
	var legacy: Dictionary = JSON.parse_string(LEGACY_CAPACITY_JSON)
	var loadout := {"weapon":"EQ01","head":"EQ11","chest":"EQ21","hands":"EQ31","feet":"EQ41","charm":"EQ51"}
	var owned: Dictionary = {}
	for id: String in loadout.values(): owned[id] = {"level":5}
	Game.run.level = 20
	Game.run.loadout_snapshot = loadout
	Game.run.equipment_snapshot = owned
	Game.run.stats = Stats.resolve("CH01", 20, loadout, owned)
	Game.run.max_hp = float(Game.run.stats.max_hp)
	near(Game.run.max_hp, 260, "old HP capacity stays exact")
	check(Snapshot.validate(legacy, "CH01", Game.run.stats), "actual old-schema full-capacity checkpoint remains valid")
	check(Snapshot.restore(room, legacy), "old-schema checkpoint restores through production boundary")
	near(Game.run.hp, 260, "legacy full HP is not rejected or silently clamped")
	near(Game.run.resource, 100, "legacy resource cap preserved")
	near(Game.run.shield, 130, "legacy full hero guard fits preserved max HP")
	near(room.player.status.guards["equipment:EQ21"].amount, 91, "legacy maximum equipment guard remains valid")
	var replay: Dictionary = Snapshot.capture(room)
	check(JSON.parse_string(JSON.stringify(replay)) == legacy, "legacy schema boundary roundtrips without mutation")
	var legacy_mana: Dictionary = JSON.parse_string(LEGACY_MANA_JSON)
	Game.run.hero_id = "CH03"
	Game.run.loadout_snapshot = {"weapon":"EQ04"}
	Game.run.equipment_snapshot = {"EQ04":{"level":1}}
	Game.run.stats = Stats.resolve("CH03", 20, Game.run.loadout_snapshot, Game.run.equipment_snapshot)
	Game.run.max_hp = float(Game.run.stats.max_hp)
	near(Game.run.stats.resource_max, 117.0, "legacy odd-base mana rounding is preserved")
	check(Snapshot.validate(legacy_mana, "CH03", Game.run.stats), "actual legacy full-mana snapshot accepted")
	check(Snapshot.restore(room, legacy_mana), "legacy full-mana snapshot restores")
	near(Game.run.resource, 117.0, "legacy mana is neither rejected nor clamped")
	check(JSON.parse_string(JSON.stringify(Snapshot.capture(room))) == legacy_mana, "legacy mana boundary roundtrips")
	check(not Game.finish_run("abandoned").is_empty(), "legacy fixture cleanup settles")
	check(await room.combat_audio.wait_for_cleanup(), "legacy fixture audio released")
	room.free()
	room = null

func test_live_terminal_packets() -> void:
	for kind: String in ["direct", "dot"]:
		check(Game.start_run(), "fresh terminal " + kind + " run starts")
		fixture()
		Game.run.hp = 1.0
		room.player.grant_guard(5.0, 4.0, "hero:test")
		if kind == "dot":
			room.player.receive_enemy_status({"id":"burn", "power":100.0, "duration":1.0, "source_id":"M10", "attack_id":"last_burn"})
			room.player._physics_process(1.0)
		else:
			room.player.receive_enemy_status({"id":"corrosion", "power":10.0, "duration":3.0})
			room.player.receive_damage(10.0, Vector2.ZERO, {"damage_type":"true", "source_id":"M01", "attack_id":"lethal_swing"})
		check(Game.run == null, kind + " lethal closes actual run")
		var review: Dictionary = Game.last_result.get("death_review", {})
		check(not review.is_empty() and review.lethal_event.kind == kind, kind + " lethal packet classified")
		near(review.lethal_event.hp_loss, 1.0, kind + " overkill reports only actual lost HP")
		near(review.lethal_event.shield_absorbed, 5.0, kind + " lethal preserves actual absorption")
		check(review.lethal_event.source_id == ("M10" if kind == "dot" else "M01"), kind + " lethal source preserved even at effect expiry")
		if kind == "direct": check("corrosion" in review.lethal_event.key_states, "lethal direct retains corrosion armor/vulnerability clue")
		else: check(review.lethal_event.status == "burn", "last-expiry DOT names cause after state expiration")
		check(not JSON.stringify(Game.profile).contains("death_review"), kind + " evidence remains runtime only")
		check(await room.combat_audio.wait_for_cleanup(), kind + " audio released")
		room.free()
		room = null

func _run() -> void:
	if not Game.profile_path.contains("test_audit_combat"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	test_precision_and_purchase()
	test_status_merge()
	test_shared_shields()
	test_trail_bounds()
	await test_live_sources_and_death()
	await test_live_terminal_packets()
	await test_legacy_capacity_checkpoint()
	print("AUDIT COMBAT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
