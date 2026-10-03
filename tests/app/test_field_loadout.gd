extends SceneTree
## Detached real reducers only; no scene entry, profile writes or automatic ticks.
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Rules = preload("res://scripts/domain/combat/equipment_effects.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Run = preload("res://scripts/domain/expedition/run_session.gd")
var Player: Script
var Abilities: Script
var Loadout: Script
var game: Node
var checks := 0
var failures := 0

class TestRoom extends Node2D:
	var player: Node2D
	var layout_id := "supply:B01"
	func targets_in_radius(_at: Vector2, _radius: float) -> Array: return []
	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void: pass

func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FIELD_LOADOUT FAIL: " + label)
func _near(value: float, expected: float, label: String) -> void:
	_check(is_equal_approx(value, expected), label)
func _gear(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id: String in ids: result[str(Registry.equipment(id).slot)] = id
	return result
func _set_gear(position: int) -> Dictionary:
	var ids: Array = []
	for index: int in 6: ids.append("EQ%02d" % (position + index * 10))
	return _gear(ids)
func _stats(gear: Dictionary) -> Dictionary:
	var owned: Dictionary = {}
	for id: String in gear.values(): owned[id] = {"level":0}
	return Resolver.resolve("CH03", 12, gear, owned)
func _install(gear: Dictionary) -> void:
	game.run.loadout_snapshot = gear.duplicate(true)
	game.run.stats = _stats(gear)
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = float(game.run.stats.resource_max)
	game.run.shield = 0.0
func _room(gear: Dictionary) -> TestRoom:
	_install(gear)
	var room := TestRoom.new()
	room.player = Player.new()
	room.player.room = room
	room.player.abilities = Abilities.new()
	room.player.abilities.owner_player = room.player
	room.player.loadout = Loadout.new()
	room.player.loadout.configure(room.player)
	room.add_child(room.player)
	return room
func _seed(room: TestRoom) -> Dictionary:
	var actor: Node2D = room.player
	actor.cooldowns = {"q":3.25,"secondary":1.75,"f":7.5,"ultimate":31.0}
	for key: String in Snapshot.PLAYER_TIMERS: actor.set(key, 0.75)
	actor.status.clock = 20.0
	actor.status.apply("burn", 12.0, 2.4)
	actor.status.states.burn.tick = 0.6
	actor.loadout._clock = 20.0
	actor.loadout._movement_time = 1.25
	actor.loadout._event_serial = 39
	var effects: RefCounted = actor.loadout.effects
	effects.clock = 20.0
	effects.cooldowns = {"EQ24":25.0,"S05_6":27.0,"EQ52:supply:B01":20.0}
	effects.rooms = {"L01":true,"supply:B01":true}
	effects.room_id = "supply:B01"
	effects.room_first_kill_used = true
	effects.room_low_shield_used = true
	effects.undamaged_time = 3.2
	effects.eq12_spent_at = 18.2
	effects.movement_time = 1.25
	effects.dash_time = 19.1
	effects.heal_history.append({"time":19.7,"amount":0.02})
	effects.resource_history.append({"time":17.0,"amount":4.0})
	effects.refund_history.append({"time":19.5,"amount":0.2})
	game.run.hp = 23.25
	game.run.resource = 17.5
	return Snapshot.capture(room)
func _convert(snapshot: Dictionary, old: Dictionary, next: Dictionary) -> Dictionary:
	var result: Dictionary = Snapshot.for_loadout(snapshot, old, next, _stats(next), "CH03", _stats(old))
	_check(not result.is_empty(), "valid loadout conversion accepted")
	return result

func _guard(room: TestRoom, valid: bool, label: String) -> bool:
	_check(valid, label)
	if not valid: room.free()
	return valid

func _tiers() -> void:
	for position: int in [7, 8, 9, 5]:
		var old: Dictionary = _set_gear(position)
		var room: TestRoom = _room(old)
		var snapshot: Dictionary = _seed(room)
		if not _guard(room, not snapshot.is_empty(), "tier seed captured"): return
		var set_id: String = "S%02d" % (position - 2)
		_check(int(_stats(old).sets.get(set_id, 0)) == 6, "fixture owns six legal pieces: " + set_id)
		if position == 7:
			snapshot.equipment.buffs["S05_4"] = {"stat":"attack_speed_bonus","amount":0.1,"until":23.0}
			snapshot.equipment.delayed_shield_at = 20.0
			snapshot.status.guards["equipment:S05_6"] = {"amount":8.0,"remaining":2.0}
		elif position == 8: snapshot.equipment.windows = {"S06_4":22.0,"S06_6":25.0}
		elif position == 9: snapshot.equipment.counts["S07_6"] = 2
		else: snapshot.status.guards["equipment:S03_4"] = {"amount":8.0,"remaining":2.0}
		var five: Dictionary = old.duplicate()
		five.charm = "EQ51"
		var result: Dictionary = _convert(snapshot, old, five)
		if not _guard(room, not result.is_empty(), "five-piece conversion returned a snapshot"): return
		if position == 7:
			_check(result.equipment.buffs.has("S05_4") and result.equipment.delayed_shield_at == -1.0 and result.status.guards.is_empty(), "six-to-five retains four-piece buff but cancels due six-piece shield")
		elif position == 8: _check(result.equipment.windows.has("S06_4") and not result.equipment.windows.has("S06_6"), "six-to-five removes only six-piece window")
		elif position == 9: _check(not result.equipment.counts.has("S07_6"), "six-piece hit counter cannot survive lost tier")
		var three: Dictionary = five.duplicate()
		three.hands = "EQ31"
		three.feet = "EQ41"
		result = _convert(snapshot, old, three)
		if not _guard(room, not result.is_empty(), "three-piece conversion returned a snapshot"): return
		_check(result.equipment.buffs.is_empty() and result.equipment.windows.is_empty() and result.equipment.counts.is_empty() and result.status.guards.is_empty(), "six-to-three drops all lost tier benefits: " + set_id)
		room.free()

func _preservation() -> void:
	var old: Dictionary = _gear(["EQ04","EQ14","EQ27","EQ32","EQ44","EQ54"])
	var room: TestRoom = _room(old)
	var snapshot: Dictionary = _seed(room)
	if not _guard(room, not snapshot.is_empty(), "preservation seed captured"): return
	snapshot.equipment.counts["EQ32"] = 4
	snapshot.status.guards["hero:f"] = {"amount":float(_stats(old).max_hp) * 0.5,"remaining":1.2}
	snapshot.status.guards["equipment:EQ27:supply:B01"] = {"amount":8.0,"remaining":2.1}
	var before: Dictionary = snapshot.duplicate(true)
	var next: Dictionary = old.duplicate()
	next.weapon = "EQ01"
	var result: Dictionary = _convert(snapshot, old, next)
	if not _guard(room, not result.is_empty(), "preservation conversion returned a snapshot"): return
	_check(snapshot == before, "conversion leaves every input dictionary unchanged")
	_near(result.hp, 23.25, "absolute HP does not heal on replacement")
	_near(result.resource, 17.5, "absolute mana does not refill on replacement")
	_check(result.player == snapshot.player and result.status.states == snapshot.status.states, "skill CDs, player timers and DOT cadence survive")
	for key: String in Snapshot.EFFECT_NUMBERS + Snapshot.EFFECT_HISTORIES + ["cooldowns","rooms","counts","room_id","room_first_kill_used","room_low_shield_used"]:
		_check(result.equipment[key] == snapshot.equipment[key], "spent budget or clock retained: " + key)
	for key: String in ["clock","movement_time","event_serial"]:
		_check(result.equipment.adapter[key] == snapshot.equipment.adapter[key], "adapter progress retained: " + key)
	_check(result.status.guards == snapshot.status.guards, "retained EQ27 source with colon-bearing room ID keeps lifetime")
	var replay: Dictionary = JSON.parse_string(JSON.stringify(result))
	if not _guard(room, not replay.is_empty(), "JSON roundtrip returned a snapshot"): return
	var replay_again: Dictionary = _convert(replay, next, next)
	if not _guard(room, not replay_again.is_empty(), "same-loadout conversion returned a snapshot"): return
	_check(Snapshot.validate(replay, "CH03", _stats(next)) and replay_again == replay, "JSON roundtrip is valid and same-loadout conversion is stable")
	snapshot.hp = float(_stats(old).max_hp)
	snapshot.resource = float(_stats(old).resource_max)
	result = _convert(snapshot, old, {})
	if not _guard(room, not result.is_empty(), "new-cap conversion returned a snapshot"): return
	_near(result.hp, float(_stats({}).max_hp), "lower HP cap clamps absolute HP")
	_near(result.resource, float(_stats({}).resource_max), "lower mana cap clamps absolute resource")
	_near(result.status.guards["hero:f"].amount, float(_stats({}).max_hp) * 0.5, "hero shield clamps to new cap without restarting expiry")
	_near(result.status.guards["hero:f"].remaining, 1.2, "guard lifetime unchanged by cap reduction")
	room.free()

func _sources() -> void:
	var old: Dictionary = _gear(["EQ20","EQ21"])
	var room: TestRoom = _room(old)
	if not _guard(room, not _seed(room).is_empty(), "source seed captured"): return
	room.player.loadout.event("dash", {"event_id":"source_dash"})
	room.player.loadout.effects.room_low_shield_used = false
	room.player.loadout.event("damaged", {"event_id":"source_damage","enemy_damage":true,"hp_damage":1.0})
	var snapshot: Dictionary = Snapshot.capture(room)
	if not _guard(room, not snapshot.is_empty(), "real equipment self-status capture succeeded"): return
	_check(snapshot.equipment.adapter.self_status_sources.size() == 2, "real adapter records EQ20 and EQ21 status origins")
	var result: Dictionary = _convert(snapshot, old, {})
	if not _guard(room, not result.is_empty(), "self-status removal returned a snapshot"): return
	_check(not result.status.states.has("damage_reduction") and not result.status.states.has("invulnerable"), "removed gear removes only its two owned self buffs")
	_check(result.equipment.room_low_shield_used and result.equipment.room_first_kill_used, "removing EQ21 never replenishes consumed room rewards")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.equipment.adapter.erase("self_status_sources")
	_check(not Snapshot.loadout_source_error(legacy, old, {}).is_empty() and Snapshot.for_loadout(legacy, old, {}, _stats({}), "CH03", _stats(old)).is_empty(), "ambiguous old status provenance rejects removal")
	if not _guard(room, Snapshot.restore(room, legacy), "legacy source snapshot restored"): return
	var legacy_capture: Dictionary = Snapshot.capture(room)
	if not _guard(room, not legacy_capture.is_empty(), "legacy source snapshot recaptured"): return
	_check(not legacy_capture.equipment.adapter.has("self_status_sources"), "legacy restore and recapture cannot invent known origins")
	if not _guard(room, Snapshot.restore(room, snapshot), "restore source-aware fixture after legacy compatibility check"): return
	result = _convert(legacy, old, old)
	if not _guard(room, not result.is_empty(), "legacy snapshot compatible when its source stays equipped"): return
	for id: String in ["damage_reduction","invulnerable"]: legacy.status.states.erase(id)
	_check(Snapshot.loadout_source_error(legacy, old, {}).is_empty(), "expired legacy buffs have no ambiguous source")
	result = _convert(legacy, old, {})
	if not _guard(room, not result.is_empty(), "expired legacy buffs permit unambiguous replacement"): return
	room.player.status.clock += 0.1
	room.player.status.apply("damage_reduction", 0.25, 4.0)
	room.player.status.apply("invulnerable", 1.0, 1.0)
	snapshot = Snapshot.capture(room)
	if not _guard(room, not snapshot.is_empty(), "external overwrite capture succeeded"): return
	_check(snapshot.equipment.adapter.self_status_sources.is_empty(), "later external writes invalidate stale equipment fingerprints")
	result = _convert(snapshot, old, {})
	if not _guard(room, not result.is_empty(), "external overwrite conversion returned a snapshot"): return
	_check(result.status.states == snapshot.status.states, "external same-name statuses survive equipment removal")
	room.free()

func _restore_and_dash() -> void:
	var room: TestRoom = _room({})
	if not _guard(room, not _seed(room).is_empty(), "restore seed captured"): return
	room.player.loadout.event("dash", {"event_id":"unowned_dash"})
	var snapshot: Dictionary = Snapshot.capture(room)
	if not _guard(room, not snapshot.is_empty(), "unowned dash capture succeeded"): return
	_check(snapshot.equipment.windows.has("EQ02"), "real dash creates a latent unequipped window")
	var next: Dictionary = _gear(["EQ02","EQ27","EQ42","EQ52"])
	var result: Dictionary = _convert(snapshot, {}, next)
	if not _guard(room, not result.is_empty(), "restore conversion returned a snapshot"): return
	_check(not result.equipment.windows.has("EQ02"), "new equipment cannot inherit an unowned old dash window")
	_install(next)
	if not _guard(room, Snapshot.restore(room, result), "live adapter restores converted snapshot"): return
	var effects: RefCounted = room.player.loadout.effects
	_check(effects.equipped == Rules.loadout_binding(next).equipped and effects.stats == game.run.stats, "restore immediately rebinds real loadout rules and stats")
	_check(room.player.status.guards.is_empty() and not effects.buffs.has("EQ42"), "restore does not replay EQ27 shield or EQ42 entry buff")
	_check(effects.rooms == snapshot.equipment.rooms and effects.room_first_kill_used and effects.room_low_shield_used, "restore retains room identity and consumed rewards")
	var hp_before: float = game.run.hp
	room.player.loadout.event("kill", {"event_id":"late_kill","target_id":"unique","equipment_eligible":true,"proc_depth":0,"damage_source":"primary"})
	_near(game.run.hp, hp_before, "newly equipped EQ52 cannot reclaim consumed first-kill healing")
	room.player.loadout.event("dash", {"event_id":"new_dash"})
	var hit: Dictionary = effects.handle("before_hit", {"attack_id":"new_hit","target_id":"unique2","equipment_eligible":true,"proc_depth":0,"damage_source":"primary"})
	_near(float(hit.damage_bonus), 0.1, "newly bound EQ02 works on a new dash immediately")
	room.free()

func _confirmed_hit(effects: RefCounted, attack_id: String) -> void:
	var context: Dictionary = {"attack_id":attack_id,"target_id":"burning_target","target_states":["burn"],"applied_states":["burn"],"equipment_eligible":true,"proc_depth":0,"damage_source":"primary"}
	effects.handle("before_hit", context)
	effects.handle("status_applied", context)
	effects.handle("after_hit", context)

func _dash_source_migration() -> void:
	var gear: Dictionary = _gear(["EQ20","EQ30","EQ40","EQ50","EQ60"])
	_check(int(_stats(gear).sets.S08) >= 4, "dash-source fixture has a legal S08 four-piece tier and EQ60")
	for retained: bool in [false, true]:
		var old: Dictionary = gear if retained else {}
		var room: TestRoom = _room(old)
		var snapshot: Dictionary = _seed(room) # Legacy dash_time=19.1; clock=20, no source windows.
		if not _guard(room, not snapshot.is_empty(), "dash-source seed captured"): return
		var result: Dictionary = _convert(snapshot, old, gear)
		if not _guard(room, not result.is_empty(), "dash-source conversion returned a snapshot"): return
		_near(result.equipment.dash_time, 19.1, "dash provenance migration never restarts the shared timer")
		for id: String in ["EQ60","S08_4"]:
			_check(result.equipment.windows.has(id) == retained, "legacy dash qualification requires source on both sides: " + id)
			if retained: _near(result.equipment.windows[id], 22.1 if id == "EQ60" else 21.1, "retained dash qualification keeps its original deadline: " + id)
		_install(gear)
		if not _guard(room, Snapshot.restore(room, result), "dash-source migration restores into real rules"): return
		var effects: RefCounted = room.player.loadout.effects
		_confirmed_hit(effects, "prior_dash_hit")
		for id: String in ["EQ60","S08_4"]:
			_check(effects.buffs.has(id) == retained, "confirmed hit cannot use a newly acquired source's earlier dash: " + id)
		if not retained:
			room.player.loadout.event("dash", {"event_id":"fresh_source_dash"})
			_near(effects.windows.EQ60, 23.0, "fresh dash grants EQ60 its full three-second window")
			_near(effects.windows.S08_4, 22.0, "fresh dash grants S08 four-piece its full two-second window")
			_confirmed_hit(effects, "fresh_dash_hit")
			_check(effects.buffs.has("EQ60") and effects.buffs.has("S08_4"), "new real dash enables both sourced buffs after a confirmed status hit")
		room.free()

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_field_loadout"):
		push_error("FIELD_LOADOUT requires the isolated --test-profile path")
		quit(2)
		return
	Player = load(AssetCatalog.resolve("res://scripts/gameplay/characters/hero_actor.gd"))
	Abilities = load(AssetCatalog.resolve("res://scripts/gameplay/characters/hero_abilities.gd"))
	Loadout = load(AssetCatalog.resolve("res://scripts/domain/combat/combat_loadout.gd"))
	var previous: Variant = game.run
	game.run = Run.new()
	game.run.hero_id = "CH03"
	game.run.level = 12
	_tiers()
	_preservation()
	_sources()
	_restore_and_dash()
	_dash_source_migration()
	game.run = previous
	print("FIELD_LOADOUT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
