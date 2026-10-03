extends SceneTree
## Uses detached real player/status/loadout reducers and a disposable test run.
## Never opens a window, writes the production profile or advances a live room.
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Run = preload("res://scripts/domain/expedition/run_session.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
var Player: Script
var Abilities: Script
var Loadout: Script
var game: Node
var checks: int = 0
var failures: int = 0

class TestRoom extends Node2D:
	var player: Node2D
	var layout_id: String = "L02"
	var expedition_context: Dictionary = {"role":"normal"}
	func targets_in_radius(_at: Vector2, _radius: float) -> Array:
		return []
	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("COMBAT_SNAPSHOT FAIL: " + label)

func _near(value: float, expected: float, label: String) -> void:
	_check(is_equal_approx(value, expected), label)

func _room() -> TestRoom:
	var room := TestRoom.new()
	room.player = Player.new()
	room.player.room = room
	room.player.abilities = Abilities.new()
	room.player.abilities.owner_player = room.player
	room.player.loadout = Loadout.new()
	room.player.loadout.configure(room.player)
	# Detached nodes avoid _ready, drawing, automatic ticks, audio and saves.
	room.add_child(room.player)
	return room

func _fixture(room: TestRoom) -> void:
	var player: Node2D = room.player
	player.position = Vector2(950, 520)
	player.aim_direction = Vector2(0.6, 0.8)
	player.cooldowns = {"q":3.25, "secondary":1.75, "f":7.5, "ultimate":31.0}
	player.dash_cooldown = 0.8
	player.shot_cooldown = 0.12
	player.invulnerable = 0.3
	player.resource_delay = 1.25
	player.combat_time = 3.4
	player.rage_hurt_cooldown = 0.6
	player.passive_count = 3
	player.passive_cooldown = 0.45
	player.walk_distance = 182.0
	player.abilities.cast_serial = 17
	player.status.clock = 20.0
	player.status.shock_cooldown = 0.4
	player.status.apply("burn", 20.0, 2.4)
	player.status.states.burn.tick = 0.6
	player.status.grant_guard(20.0, 3.2, "hero:f", game.run.max_hp)
	player.status.grant_guard(12.0, 1.1, "equipment:EQ27", game.run.max_hp, true)
	player.status.grant_guard(25.0, 9.0, "room_prop:guard", game.run.max_hp)
	player._enemy_status_origins = {"burn":Vector2(900, 600)}
	player._enemy_slow_remaining = 1.6
	player._enemy_slow_multiplier = 0.8
	game.run.hp = 61.25
	game.run.resource = 32.5
	# External shield damage is deliberately not synchronized to status yet.
	game.run.shield = 22.0
	var effects: RefCounted = player.loadout.effects
	effects.clock = 20.0
	effects.cooldowns = {"EQ24":25.0, "S05_6":27.0, "EQ03:829391":23.0, "EQ27:L02":20.0}
	effects.buffs = {"EQ24":{"stat":"damage_reduction_bonus", "amount":0.05, "until":21.8}}
	effects.windows = {"EQ56":22.5}
	effects.rooms = {"L01":true, "L02":true}
	effects.counts = {"EQ32":4, "EQ59":2}
	effects.heal_history.append({"time":19.7, "amount":0.03})
	effects.resource_history.append({"time":17.0, "amount":4.0})
	effects.refund_history.append({"time":19.5, "amount":0.2})
	effects.undamaged_time = 3.2
	effects.eq12_spent_at = 18.2
	effects.movement_time = 1.25
	effects.dash_time = 19.1
	effects.room_id = "L02"
	effects.room_low_shield_used = true
	effects.room_first_kill_used = true
	effects.delayed_shield_at = 20.7
	effects.roots = {"attack:17":{"target":"829391"}}
	effects.deaths = {"829391":true}
	effects.same_target = {"EQ01":{"target":"829391", "count":2, "time":20.0}}
	effects.first_full_targets = {"829391":true}
	effects.shock_targets = {"829391":19.0}
	player.loadout._clock = 20.0
	player.loadout._movement_time = 1.25
	player.loadout._event_serial = 39
	player.loadout._modifiers.damage_reduction_bonus = 0.05
	player.loadout._modifiers.cost_reduction = 0.08
	player.dash_remaining = 0.1
	player.knockback = Vector2(30, 40)
	player.attack_buffer = 0.1
	player.attack_remaining = 0.3
	player.abilities.active = {"pending":"not exported"}

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null:
		push_error("COMBAT_SNAPSHOT requires the project Game autoload")
		quit(2)
		return
	# --script compiles its entry script before autoload singleton identifiers.
	# Load scene-facing scripts only after the project autoload is initialized.
	Player = load(AssetCatalog.resolve("res://scripts/gameplay/characters/hero_actor.gd"))
	Abilities = load(AssetCatalog.resolve("res://scripts/gameplay/characters/hero_abilities.gd"))
	Loadout = load(AssetCatalog.resolve("res://scripts/domain/combat/combat_loadout.gd"))
	if not game.profile_path.contains("test_combat_snapshot"):
		push_error("COMBAT_SNAPSHOT requires an isolated --test-profile path")
		quit(2)
		return
	var previous: Variant = game.run
	game.run = Run.new()
	game.run.hero_id = "CH02"
	game.run.level = 12
	game.run.stats = Resolver.resolve("CH02", 12, {}, {})
	game.run.max_hp = float(game.run.stats.max_hp)
	var source: TestRoom = _room()
	_fixture(source)
	var source_player: Node2D = source.player
	var original_guards: Dictionary = source_player.status.guards.duplicate(true)
	var original_roots: Dictionary = source_player.loadout.effects.roots.duplicate(true)
	var snapshot: Dictionary = Snapshot.capture(source)
	_check(not snapshot.is_empty(), "real actor can export safe boundary")
	if snapshot.is_empty():
		source.free()
		game.run = previous
		quit(1)
		return
	_check(source_player.status.guards == original_guards and source_player.loadout.effects.roots == original_roots, "capture does not normalize or prune live state")
	_near(source_player.dash_remaining, 0.1, "capture does not cancel live dash")
	_check(not source_player.abilities.active.is_empty(), "capture does not cancel live skill")
	_check(snapshot.status.origins.burn is Array and snapshot.player.aim_direction is Array, "vector fields use JSON arrays")
	_check(not snapshot.status.guards.has("room_prop:guard"), "room-local guard is excluded")
	_near(snapshot.status.guards["hero:f"].amount, 17.0, "pending external shield damage applied to copied hero pool")
	_near(snapshot.status.guards["equipment:EQ27"].amount, 9.0, "pending external shield damage applied to copied equipment pool")
	_check(not snapshot.equipment.cooldowns.has("EQ03:829391") and snapshot.equipment.cooldowns.has("EQ24"), "drops per-target ICD and keeps general ICD")
	for key: String in ["roots", "deaths", "same_target", "first_full_targets", "shock_targets"]:
		_check(not snapshot.equipment.has(key), "scene-bound state excluded: " + key)
	var replay: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	_check(Snapshot.validate(replay, "CH02", game.run.stats), "JSON roundtrip validates")
	var target: TestRoom = _room()
	target.player.position = Vector2(310, 400)
	target.player.loadout.effects.roots = {"new_room_attack":{}}
	game.run.hp = 1.0
	game.run.resource = 0.0
	_check(Snapshot.restore(target, replay), "restores real status/loadout/player reducers")
	_near(game.run.hp, 61.25, "absolute HP retained")
	_near(game.run.resource, 32.5, "absolute resource retained")
	_near(game.run.shield, 17.0, "effective hero/equipment guard reconstructed by maximum")
	_check(target.player.position == Vector2(310,400), "new room spawn position retained")
	_check(target.player.cooldowns == source_player.cooldowns, "all skill cooldowns retained")
	for key: String in Snapshot.PLAYER_TIMERS:
		_near(float(target.player.get(key)), float(source_player.get(key)), "timer retained: " + key)
	_check(target.player.passive_count == 3 and is_equal_approx(target.player.walk_distance,182.0), "hero passive count and walking progress retained")
	_check(target.player.abilities.cast_serial == 17 and target.player.abilities.active.is_empty(), "cast sequence kept without pending action")
	_check(target.player.dash_remaining == 0.0 and target.player.knockback == Vector2.ZERO and target.player.attack_remaining == 0.0, "in-progress physical actions cleared")
	_check(target.player._enemy_status_origins.burn == Vector2(900,600), "DOT origin restored without node references")
	_near(target.player.status.states.burn.tick,0.6,"fractional status cadence retained")
	_near(target.player.status.guards["hero:f"].remaining,3.2,"independent guard lifetime retained")
	_near(target.player.status.guards["equipment:EQ27"].remaining,1.1,"weaker guard lifetime retained")
	for key: String in Snapshot.EFFECT_MAPS + Snapshot.EFFECT_HISTORIES:
		_check(target.player.loadout.effects.get(key) == replay.equipment[key], "equipment state retained: " + key)
	for key: String in Snapshot.EFFECT_NUMBERS:
		_near(float(target.player.loadout.effects.get(key)),float(replay.equipment[key]),"equipment clock retained: " + key)
	for key: String in ["roots", "deaths", "same_target", "first_full_targets", "shock_targets"]:
		_check(target.player.loadout.effects.get(key).is_empty(), "destination stale target caches cleared: " + key)
	_check(target.player.loadout._last_position == target.player.position and target.player.loadout._current_speed == 0.0, "room teleport cannot generate equipment walking progress")
	_near(target.player.loadout._clock,20.0,"adapter clock retained")
	_check(target.player.loadout._event_serial == 39,"adapter event counter retained")
	var restored: Dictionary = Snapshot.capture(target)
	_check(JSON.parse_string(JSON.stringify(restored)) == replay,"restore/capture preserves complete canonical JSON boundary")
	# Aliasing must never allow caller edits to change the live reducer.
	replay.equipment.windows.EQ56 = 900.0
	replay.status.guards["hero:f"].amount = 1.0
	_near(target.player.loadout.effects.windows.EQ56,22.5,"restored equipment detached from source dictionaries")
	_near(target.player.status.guards["hero:f"].amount,17.0,"restored status detached from source dictionaries")
	_rejections(target, restored)
	var fresh: Dictionary = {"snapshot_version":1,"mode":"fresh_entry","hero_id":"CH02","hp":game.run.stats.max_hp,"resource":game.run.stats.starting_resource}
	var before_fresh: Dictionary = Snapshot.capture(target)
	_check(Snapshot.restore(target,fresh),"fresh entry accepted")
	_check(Snapshot.capture(target) == before_fresh,"fresh entry never overwrites initialized actor")
	_check(not Snapshot.validate(fresh,"CH02",game.run.stats),"fresh entry needs explicit allowance")
	_room_entries(restored, fresh)
	_new_status_roundtrip()
	# Restore this actor after other fixtures have used the shared disposable run.
	_check(Snapshot.restore(target,restored),"restore target after entry fixtures")
	# Advancing the imported reducer respects remaining deadlines and shared caps.
	var effects: RefCounted = target.player.loadout.effects
	_check(not effects._ready("EQ24"),"imported general ICD is still active")
	effects.advance(1.0,{"moving":false})
	_check(not effects._ready("EQ24"),"new room does not reset cooldown clock")
	_near(float(effects.cooldowns.EQ24)-effects.clock,4.0,"general ICD remaining time advances correctly")
	_check(not effects.resource_history.is_empty(),"five-second resource cap history survives crossing rooms")
	source.free()
	target.free()
	game.run = previous
	print("COMBAT_SNAPSHOT_TESTS checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _new_status_roundtrip() -> void:
	var source: TestRoom = _room()
	_fixture(source)
	var status: RefCounted = source.player.status
	status.apply("bleed", 24.0, 4.2, 30.0)
	status.apply("grievous", 0.0, 2.5)
	status.apply("damage_reduction", 0.12, 4.0)
	status.apply("invulnerable", 0.0, 0.8)
	status.tick(0.25)
	source.player._enemy_status_origins["bleed"] = Vector2(820, 530)
	var before: Dictionary = status.states.duplicate(true)
	var snapshot: Dictionary = Snapshot.capture(source)
	_check(not snapshot.is_empty(), "real new combat states can be captured before they are cleared")
	if snapshot.is_empty():
		source.free()
		return
	_check(status.states == before, "new-state capture does not expire or alter live buffs")
	_near(float(snapshot.status.states.damage_reduction.power), 0.12, "fractional self damage-reduction power is valid")
	_near(float(snapshot.status.states.invulnerable.H), 0.0, "zero-input invulnerability raw power is valid")
	_near(float(snapshot.status.states.invulnerable.power), 1.0, "runtime flag normalization is preserved")
	var replay: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	_check(Snapshot.validate(replay, game.run.hero_id, game.run.stats), "all new statuses survive JSON validation")
	var target: TestRoom = _room()
	_check(Snapshot.restore(target, replay), "new statuses restore into real player reducer")
	_check(target.player.status.states == replay.status.states, "new state powers, clocks and lifetimes roundtrip exactly")
	_check(target.player._enemy_status_origins.bleed == Vector2(820, 530), "bleed origin restores as detached coordinates")
	_near(float(target.player.status.damage_modifiers().damage_reduction), 0.12, "restored self buff still grants twelve percent reduction")
	_check(target.player.status.damage_modifiers().invulnerable, "restored invulnerability remains effective")
	_near(float(target.player.status.healing_multiplier()), 0.6, "restored grievous effect still reduces healing once")
	_check(JSON.parse_string(JSON.stringify(Snapshot.capture(target))) == replay, "new-state restore and recapture is canonical")
	# Flags are presence-based. A version-one producer may serialize zero power;
	# zero must remain legal even though today's apply() normalizes it to one.
	var zero_flag := replay.duplicate(true)
	zero_flag.status.states.invulnerable.power = 0.0
	_check(Snapshot.validate(zero_flag, game.run.hero_id, game.run.stats) and Snapshot.restore(target, zero_flag), "zero-power invulnerability is accepted without a schema migration")
	_check(target.player.status.damage_modifiers().invulnerable, "zero-power invulnerability still behaves as a flag")
	target.player.status.tick(0.55)
	_check(not target.player.status.damage_modifiers().invulnerable, "restored invulnerability expires at its remaining deadline")
	var ticks: Array[Dictionary] = target.player.status.tick(0.2)
	var bleed_ticks := 0
	for tick: Dictionary in ticks:
		if tick.kind == "bleed":
			bleed_ticks += 1
			_near(float(tick.damage), 2.4, "bleed resumes fractional cadence and original damage")
			_near(float(tick.H), 30.0, "bleed keeps its original hit snapshot")
	_check(bleed_ticks == 1, "bleed does not restart or duplicate its first pending tick")
	# Missing new entries are normal for pre-extension version-one checkpoints.
	var legacy := replay.duplicate(true)
	for id: String in ["bleed", "grievous", "damage_reduction", "invulnerable"]:
		legacy.status.states.erase(id)
		legacy.status.origins.erase(id)
	_check(Snapshot.validate(legacy, game.run.hero_id, game.run.stats) and Snapshot.restore(target, legacy), "old four-status-format snapshots remain compatible")
	_check(not target.player.status.has("invulnerable") and target.player.status.has("burn"), "legacy restore clears newer target buffs and restores old DOT state")
	source.free()
	target.free()

func _room_entries(previous: Dictionary, fresh: Dictionary) -> void:
	# This fixture used to patch only effects.equipped. Restore now correctly
	# binds authoritative run gear, so use a real resolved loadout on both sides.
	var saved_loadout: Dictionary = game.run.loadout_snapshot.duplicate(true)
	var saved_equipment: Dictionary = game.run.equipment_snapshot.duplicate(true)
	var saved_stats: Dictionary = game.run.stats.duplicate(true)
	var saved_values: Array = [game.run.max_hp, game.run.hp, game.run.resource, game.run.shield]
	game.run.loadout_snapshot = {"chest":"EQ27", "feet":"EQ42"}
	game.run.equipment_snapshot = {"EQ27":{"level":0}, "EQ42":{"level":0}}
	game.run.stats = Resolver.resolve(game.run.hero_id, game.run.level, game.run.loadout_snapshot, game.run.equipment_snapshot)
	game.run.max_hp = float(game.run.stats.max_hp)
	var current_fresh: Dictionary = fresh.duplicate(true)
	current_fresh.hp = game.run.max_hp
	current_fresh.resource = float(game.run.stats.starting_resource)
	var room: TestRoom = _room()
	room.layout_id = "L03"
	_check(Snapshot.restore_room_entry(room,previous),"new room merges restored timers with entry effects")
	var effects: RefCounted = room.player.loadout.effects
	_check(effects.room_id == "L03" and effects.rooms.has("L03"),"entry records destination room identity")
	_check(not effects.room_low_shield_used and not effects.room_first_kill_used,"new room resets only per-room usage flags")
	_check(room.player.status.guards.has("equipment:EQ27:L03"),"new combat room receives EQ27 source shield")
	_near(room.player.status.guards["equipment:EQ27:L03"].remaining,4.0,"new-room shield gets its own expiry")
	_near(room.player.status.guards["hero:f"].remaining,3.2,"entry keeps prior hero guard lifetime")
	_near(effects.buffs.EQ42.until,23.0,"EQ42 entry buff uses restored equipment clock")
	_near(room.player.loadout._modifiers.move_speed_bonus,0.08,"entry buff appears in cached modifiers")
	_near(room.player.loadout._modifiers.cost_reduction,0.08,"old generic window stays in cached modifiers")
	_near(effects.windows.EQ56,22.5,"entry does not erase an existing skill-cost window")
	_near(effects.delayed_shield_at,20.7,"entry does not erase a pending delayed equipment guard")
	_near(effects.undamaged_time,3.2,"entry does not reset no-damage progress")
	_near(effects.cooldowns.EQ24,25.0,"entry does not reset global ICD")
	# A completed-room snapshot already owns its entry proc and per-room usage.
	effects.room_low_shield_used = true
	effects.room_first_kill_used = true
	room.player.status.guards["equipment:EQ27:L03"].remaining = 1.0
	effects.buffs.EQ42.until = 20.5
	var completed: Dictionary = Snapshot.capture(room)
	_check(not completed.is_empty(),"entry result is a valid checkpoint")
	_check(Snapshot.restore_room_entry(room,completed),"same-room completed checkpoint restores")
	_check(Snapshot.capture(room) == completed,"same-room restore never repeats entry shield, buff or flags")
	var before_fresh: Dictionary = Snapshot.capture(room)
	_check(Snapshot.restore_room_entry(room,current_fresh),"fresh initialized entry is accepted")
	_check(Snapshot.capture(room) == before_fresh,"fresh entry never repeats initialized equipment event")
	# Loading the stored pre-entry snapshot replays the same deterministic merge.
	_check(Snapshot.restore_room_entry(room,previous),"pre-entry checkpoint can be resumed")
	_near(effects.buffs.EQ42.until,23.0,"resumed pre-entry checkpoint reproduces EQ42 expiry")
	room.layout_id = "supply:B01"
	room.expedition_context = {"role":"supply"}
	_check(Snapshot.restore_room_entry(room,previous),"service room boundary restores")
	_check(not room.player.status.guards.has("equipment:EQ27:supply:B01"),"combat-only EQ27 does not proc in a supply room")
	_check(effects.buffs.has("EQ42"),"unvisited-room EQ42 still applies in a supply room")
	room.free()
	game.run.loadout_snapshot = saved_loadout
	game.run.equipment_snapshot = saved_equipment
	game.run.stats = saved_stats
	game.run.max_hp = float(saved_values[0])
	game.run.hp = float(saved_values[1])
	game.run.resource = float(saved_values[2])
	game.run.shield = float(saved_values[3])

func _rejections(room: TestRoom, original: Dictionary) -> void:
	var malformed: Array[Dictionary] = []
	var value: Dictionary = original.duplicate(true)
	value.player.cooldowns.q = -0.1
	malformed.append(value)
	value = original.duplicate(true)
	value.status.guards["hero:f"].amount = 100000.0
	malformed.append(value)
	value = original.duplicate(true)
	value.equipment.clock = NAN
	malformed.append(value)
	value = original.duplicate(true)
	value.equipment.buffs.EQ24.stat = "unknown_stat"
	malformed.append(value)
	value = original.duplicate(true)
	value.equipment.resource_history = [{"time":99.0,"amount":4.0}]
	malformed.append(value)
	value = original.duplicate(true)
	value.equipment.cooldowns["EQ03:old_actor"] = 22.0
	malformed.append(value)
	value = original.duplicate(true)
	value.equipment.adapter.modifiers.erase("damage_bonus")
	malformed.append(value)
	value = original.duplicate(true)
	value.player.aim_direction = Vector2.RIGHT
	malformed.append(value)
	value = original.duplicate(true)
	value.hero_id = "CH01"
	malformed.append(value)
	value = original.duplicate(true)
	value.status.states.burn.erase("tick")
	malformed.append(value)
	value = original.duplicate(true)
	value.status.guards["room_prop:guard"] = {"amount":1.0,"remaining":1.0}
	malformed.append(value)
	value = original.duplicate(true)
	value.hp = 0.0
	malformed.append(value)
	for index: int in malformed.size():
		var before: Dictionary = Snapshot.capture(room)
		_check(not Snapshot.restore(room,malformed[index]),"malformed snapshot rejected #" + str(index))
		_check(Snapshot.capture(room) == before,"rejection is atomic #" + str(index))
