extends Node
## Only generated fixtures and an explicitly isolated profile are used here.
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Migration = preload("res://scripts/core/numerical_migration.gd")
const Fixtures = preload("res://tests/test_numerical_instance_storage.gd")
const Numbers = preload("res://config/numerical_rules.gd")
var checks := 0
var failures: Array[String] = []

class TestRoom extends Node2D:
	var player: Node2D
	var layout_id := "L02"
	var expedition_context := {"role":"normal"}
	func targets_in_radius(_at: Vector2, _radius: float) -> Array: return []
	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

static func runtime(hero: String, hp: float, resource: float, version: int = 1) -> Dictionary:
	var player := {"cooldowns":{},"passive_count":3,"walk_distance":32.25,"aim_direction":[1.0,0.0],"cast_serial":17}
	for key: String in Snapshot.SKILLS: player.cooldowns[key] = 3.25
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.75
	var equipment := {"room_id":"L02","room_low_shield_used":true,"room_first_kill_used":true}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: equipment[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 0.0
	equipment.clock = 20.0
	equipment.cooldowns = {"EQ24":23.5}
	equipment.windows = {"EQ56":22.75}
	equipment.dash_time = -100.0
	equipment.delayed_shield_at = -1.0
	equipment.heal_history = [{"time":19.5,"amount":6 if version == 2 else 0.02}]
	equipment.resource_history = [{"time":18.5,"amount":20 if version == 2 else 2.0}]
	equipment.refund_history = [{"time":19.5,"amount":0.2}]
	var modifiers := {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 1.0 if key.ends_with("_scale") else 0.0
	equipment.adapter = {"clock":20.0,"movement_time":0.25,"event_serial":5,"modifiers":modifiers,"self_status_sources":{}}
	var result := {"snapshot_version":1,"mode":"safe_boundary","hero_id":hero,"hp":hp,"resource":resource,"player":player,"equipment":equipment,
		"status":{"clock":20.0,"shock_cooldown":0.4,"states":{"burn":{"remaining":2.5,"tick":0.25,"power":40 if version == 2 else 4.0,"H":60 if version == 2 else 6.0,"applied_at":19.0},"brace_guard":{"remaining":0.75,"tick":0.0,"power":0.15,"H":0 if version == 2 else 0.15,"applied_at":19.5}},"guards":{"hero:f":{"amount":20 if version == 2 else 2.0,"remaining":2.25}},"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}}
	if version == 2:
		result.merge({"ruleset_version":2,"scale_version":10,"resource_regen_remainder":0.375,"resource_decay_remainder":0.625})
		Snapshot._integer_values(result)
	return Snapshot._json_keys(result)

func _ready() -> void:
	if not Game.profile_path.contains("test_numerical_versioned_saves"):
		get_tree().quit(2)
		return
	var current_default: bool = bool(Numbers.value("runtime_enabled"))
	Numbers._parameters["runtime_enabled"] = false
	check(Numbers.default_ruleset() == 1, "explicit historical fixture begins with old default")
	_legacy_migration()
	_new_expedition()
	_runtime_migration()
	_level_waiver_expiry()
	Numbers._parameters["runtime_enabled"] = current_default
	print("Numerical versioned saves: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _legacy_migration() -> void:
	Game.run = null
	check(Game.new_profile(), "new isolated legacy profile")
	var legacy := Game.profile.duplicate(true)
	legacy.permanent_gold = 777
	legacy.hero_xp = {"CH01":3600,"CH02":333,"CH03":30}
	legacy.branches.CH01 = {"q":"A","ultimate":"B"}
	legacy.equipment.EQ01.level = 5
	legacy.loadout_presets = {"CH01":legacy.loadout.duplicate(true),"CH02":legacy.loadout.duplicate(true)}
	check(Game._commit_profile(legacy), "save generated old assets and presets")
	check(Game.start_run({"expedition":true,"seed":960208}), "old expedition starts")
	if Game.run == null: return
	var boundary := runtime("CH01", 61.25, 32.5)
	check(Game.save_expedition_checkpoint(boundary), "old injured checkpoint saves")
	var receipt: Dictionary = Game.run.receipt()
	# Also cover genuinely pre-stamp persisted receipts.
	for key: String in ExpeditionState.VERSION_FIELDS:
		receipt.erase(key)
		if key != "reward_policy_version": receipt.expedition.erase(key)
	check(Game._save(Game.profile, receipt), "unstamped legacy receipt remains accepted")
	# Simulate a future global switch without editing runtime configuration.
	Numbers._parameters["runtime_enabled"] = true
	for index in 3:
		Game.reload_profile()
		check(Game.run != null and Game.run.ruleset_version() == 1 and Game.run.hp == 61.25 and Game.run.resource == 32.5, "repeated old load stays entirely legacy " + str(index))
		check(not Game.migrate_numerical_at_camp(), "active old adventure cannot migrate " + str(index))
	Numbers._parameters["runtime_enabled"] = false
	check(Game.save_expedition_checkpoint(boundary), "old receipt checkpoints without mixing versions")
	var offer: Dictionary = Game.expedition_snapshot().relic_offers[0]
	check(Game.choose_run_relic(offer.offer_id, "skip", "", boundary), "old offer remains an old-rule decision")
	var next: Dictionary = Game.expedition_snapshot().next_node
	check(Game.choose_expedition_node(int(next.node_index), str(next.room_id)) and Game.advance_expedition_node(boundary), "old expedition advances with original snapshot units")
	check(Game.collect_expedition_equipment("old-pending-drop", "EQ02", 3), "old drop uses its original template receipt")
	check(Game.commit_expedition_completion(Game.run.id + ":node:1:complete", boundary, {"gold":0,"xp":0,"mastery":0}), "old temporary reward is saved once at original scale")
	Game.reload_profile()
	check(Game.run.expedition.pending_equipment.EQ02.level == 3 and Game.run.ruleset_version() == 1, "old pending reward survives restart unchanged")
	var before: Dictionary = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(Game.finish_run("abandoned").is_empty() and Game.run != null and Game.profile == before, "failed old settlement remains atomic")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(not Game.finish_run("abandoned").is_empty() and Game.run == null, "old settlement retries once to camp")
	before = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game.migrate_numerical_at_camp() and Game.profile == before, "failed migration preserves legacy memory and disk")
	check(ProfileStore.new(Game.profile_path).load_document().profile == JSON.parse_string(JSON.stringify(before)), "failed migration leaves acknowledged whole document")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.migrate_numerical_at_camp(), "camp migration commits atomically")
	check(Game.hero_level("CH01") == 20 and Game.hero_level("CH02") == Migration.old_level(333), "levels preserved")
	check(Game.profile.permanent_gold == 777 and Game.profile.equipment.size() == before.equipment.size(), "no gold or gear invented")
	check(not Game.profile.equipment.has("migration:numerical_v2:EQ02") and Game.profile.equipment_discoveries.has("EQ02"), "failed adventure loses temporary gear and retains discovery without migration grant")
	check(Game.profile.branches == before.branches and Game.profile.applied_transactions == before.applied_transactions, "branches and payment receipts retained")
	check(Game.profile.loadout.size() == 8 and Game.profile.loadout.legs == "" and Game.profile.loadout.ring == "", "migration exposes empty new slots without grants")
	var migrated: Dictionary = Game.profile.duplicate(true)
	check(Game.migrate_numerical_at_camp() and Game.profile == migrated, "repeat migration does not generate a second item")
	Game.reload_profile()
	check(Game.profile == JSON.parse_string(JSON.stringify(migrated)) and Game.run == null, "migrated profile survives exact reload")
	for key: String in ["scale_version","equipment_instance_version","reward_policy_version","optional_chest_receipt_version"]:
		var bad := migrated.duplicate(true)
		bad[key] = 99
		check(not ProfileStore._valid_document(Fixtures.document(bad)), "reject profile version mismatch " + key)

func _new_expedition() -> void:
	Game.run = null
	check(Game.new_profile(), "reset isolated generated profile")
	var fixture := Fixtures.fixture_profile()
	fixture.hero_xp.CH01 = 3600
	check(Game._commit_profile(fixture), "explicit V2 eight-instance profile")
	check(Game.start_run({"expedition":true,"seed":1735}), "V2 expedition now starts with full eight-slot receipt")
	if Game.run == null: return
	var stats: Dictionary = Game.run.stats.duplicate(true)
	var rolls: Dictionary = Game.run.equipment_snapshot.duplicate(true)
	var boundary := runtime("CH01", 711, 123, 2)
	check(Game.run.expedition.format_version == 2 and Game.run.receipt().scale_version == 10 and Game.run.expedition.reward_policy_version == 2, "departure freezes distinct format rules scale and reward policy")
	check(Game.save_expedition_checkpoint(boundary), "V2 safe checkpoint saves")
	Game.reload_profile()
	check(Game.run != null and Game.run.ruleset_version() == 2 and Game.run.stats == stats, "restore freezes version before resolving V2 stats")
	check(Game.run.equipment_snapshot == JSON.parse_string(JSON.stringify(rolls)) and Game.run.loadout_snapshot.size() == 8, "all instance identities rolls and eight slots survive reload")
	check(Game.run.hp == 711 and Game.run.resource == 123 and Game.run.shield == 20, "reload does not refill HP shield or resource")
	check(Game.run.resource_regen_remainder == 0.375 and Game.run.resource_decay_remainder == 0.625, "fractional accumulators survive reload")
	check(typeof(Game.run.hp) == TYPE_INT and typeof(Game.run.expedition.runtime.status.guards["hero:f"].amount) == TYPE_INT and typeof(Game.run.expedition.runtime.status.states.burn.H) == TYPE_INT, "JSON floating tokens canonicalize to runtime integers")
	var saved := ProfileStore.new(Game.profile_path).load_document()
	for key: String in ExpeditionState.VERSION_FIELDS:
		var bad := saved.duplicate(true)
		bad.active_run[key] = 99
		check(not ProfileStore._valid_document(bad), "reject receipt version mismatch " + key)
		bad = saved.duplicate(true)
		bad.active_run.expedition[key] = 99
		check(not ProfileStore._valid_document(bad), "reject expedition version mismatch " + key)
	var malformed := saved.duplicate(true)
	malformed.active_run.ruleset_version = {}
	check(not ProfileStore._valid_document(malformed), "malformed receipt version rejects without coercion or script errors")
	var bad := saved.duplicate(true)
	bad.active_run.expedition.runtime.erase("scale_version")
	check(not ProfileStore._valid_document(bad), "V2 snapshot cannot omit scale guard")
	bad = saved.duplicate(true)
	bad.active_run.expedition.runtime.hp = 711.5
	check(not ProfileStore._valid_document(bad), "fractional V2 HP rejected")
	bad = saved.duplicate(true)
	bad.active_run.expedition.runtime.equipment.heal_history[0].amount = 0.03
	check(not ProfileStore._valid_document(bad), "ratio history cannot masquerade as V2 healing units")
	bad = saved.duplicate(true)
	bad.active_run.expedition.runtime.resource_regen_remainder = 1.0
	check(not ProfileStore._valid_document(bad), "whole resource cannot hide in fractional remainder")
	var before: Dictionary = Game.run.receipt()
	Game._store.max_document_bytes = 1
	var changed := boundary.duplicate(true)
	changed.hp = 600
	check(not Game.save_expedition_checkpoint(changed) and Game.run.receipt() == before and Game.run.hp == 711, "failed checkpoint changes neither actor state nor committed receipt")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.save_expedition_checkpoint(changed), "checkpoint retry preserves frozen rolls")
	_actual_actor_restore(changed)
	var offer: Dictionary = Game.expedition_snapshot().relic_offers[0]
	check(Game.choose_run_relic(offer.offer_id, "skip", "", changed), "V2 relic decision commits using its versioned snapshot")
	var next: Dictionary = Game.expedition_snapshot().next_node
	check(Game.choose_expedition_node(int(next.node_index), str(next.room_id)), "V2 freezes next room")
	check(Game.advance_expedition_node(changed), "V2 moves to actual combat checkpoint")
	check(Game.commit_expedition_completion(Game.run.id + ":node:1:complete", changed), "V2 canonical room completion saves instance and material grants")
	Game.reload_profile()
	check(Game.run != null and Game.run.ruleset_version() == 2 and Game.run.expedition.phase == "cleared", "V2 completed checkpoint reload")

func _actual_actor_restore(boundary: Dictionary) -> void:
	var room := TestRoom.new()
	room.player = load("res://scripts/combat/player.gd").new()
	room.player.room = room
	room.player.status = Snapshot.Status.new(2)
	room.player.abilities = load("res://scripts/combat/hero_abilities.gd").new()
	room.player.abilities.owner_player = room.player
	room.player.loadout = load("res://scripts/combat/combat_loadout.gd").new()
	room.player.loadout.configure(room.player)
	room.add_child(room.player)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(boundary))
	check(Snapshot.restore(room, parsed), "real actor restores parsed V2 safe snapshot")
	check(typeof(room.player.status.states.burn.power) == TYPE_INT and typeof(room.player.status.guards["hero:f"].amount) == TYPE_INT, "real actor status pools restore integer types")
	check(room.player.cooldowns.q == 3.25 and room.player.status.shock_cooldown == 0.4 and room.player.loadout.effects.cooldowns.EQ24 == 23.5, "skill CD and equipment/status ICD remain unchanged")
	var captured := Snapshot.capture(room)
	check(not captured.is_empty() and captured.hp == boundary.hp and captured.resource_regen_remainder == 0.375, "real actor capture preserves injury and fractional time")
	check(Game.save_expedition_checkpoint(captured), "real actor capture commits through public checkpoint and strict JSON tree")
	Game.reload_profile()
	check(Game.run.hp == captured.hp and Game.run.resource == captured.resource and Game.run.resource_regen_remainder == 0.375, "real captured checkpoint survives disk reload")
	check(captured.equipment.refund_history[0].amount == 0.2 and typeof(captured.equipment.resource_history[0].amount) == TYPE_INT, "refund seconds remain float while resource history is integer")
	room.free()

func _runtime_migration() -> void:
	var old_stats := {"ruleset_version":1,"max_hp":200.0,"resource_max":100.0}
	var new_stats := {"ruleset_version":2,"max_hp":1500,"resource_max":1000}
	var source := runtime("CH01", 61.25, 32.5)
	check(Snapshot.validate(source, "CH01", old_stats), "legacy injury/status fixture validates")
	var migrated := Migration.migrate_runtime(source, old_stats, new_stats)
	check(Snapshot.validate(migrated, "CH01", new_stats), "converted combat state meets formal V2 schema")
	check(migrated.hp == 459 and migrated.resource == 325 and migrated.status.guards["hero:f"].amount == 15, "conversion uses smaller absolute-scale/proportional survival values")
	check(migrated.status.states.burn.power == 40 and migrated.status.states.burn.H == 60 and migrated.status.states.brace_guard.power == 0.15, "damage snapshots scale while percent states do not")
	check(migrated.equipment.heal_history[0].amount == 30 and migrated.equipment.resource_history[0].amount == 20 and migrated.equipment.refund_history[0].amount == 0.2, "history scales distinguish ratios amounts and seconds")
	check(migrated.player == source.player and migrated.equipment.cooldowns == source.equipment.cooldowns and migrated.status.shock_cooldown == source.status.shock_cooldown, "migration preserves CD ICD and timers")
	check(Migration.migrate_runtime(migrated, old_stats, new_stats) == migrated and source.hp == 61.25, "second runtime migration is unchanged and source untouched")

func _level_waiver_expiry() -> void:
	var old := ProfileStore.fresh_profile()
	old.hero_xp.CH01 = Migration.OLD_XP[4]
	old.loadout_presets = {"CH03":old.loadout.duplicate(true)}
	var migrated := Migration.migrate_profile(old)
	var id: String = migrated.loadout.weapon
	var item: Dictionary = migrated.equipment[id]
	check(item.item_level == 5 and item.legacy_equip_waiver.level_hero_ids == ["CH03"], "migration excludes already-qualified original hero from level bypass")
	check(not Fixtures.Instances.can_equip(item, "CH01", 1) and Fixtures.Instances.can_equip(item, "CH03", 1), "level waiver applies only to still-underleveled original mage")
	var raised: Dictionary = migrated.hero_xp.duplicate(true)
	raised.CH03 = HeroProgression.thresholds()[4]
	var expired := HeroProgression.expire_level_waivers(migrated.equipment, raised)
	check(expired[id].legacy_equip_waiver.level_hero_ids.is_empty() and not expired[id].legacy_equip_waiver.level, "last qualified original hero exhausts level exception")
	check(expired[id].legacy_equip_waiver.type and expired[id].legacy_equip_waiver.hero_ids == item.legacy_equip_waiver.hero_ids and expired[id].legacy == item.legacy, "expiry retains approved type compatibility and exact migration audit")
	check(Fixtures.Instances.can_equip(expired[id], "CH03", 5) and not Fixtures.Instances.can_equip(expired[id], "CH03", 4), "mage may retain original physical item at its level but no longer below it")
	check(item.legacy_equip_waiver.level_hero_ids == ["CH03"] and HeroProgression.expire_level_waivers(expired, raised) == expired, "expiry is detached and idempotent")
	var pending: Dictionary = migrated.equipment.duplicate(true)
	pending[id].location = "pending"
	check(HeroProgression.expire_level_waivers(pending, raised)[id] == pending[id], "pending future items stay unchanged")
	for subset: Variant in [["CH02"], ["CH03", "CH03"], ["CH01", "CH03", "CH02"], {}, [5]]:
		var invalid := item.duplicate(true)
		invalid.legacy_equip_waiver["level_hero_ids"] = subset
		check(not Fixtures.Instances.validate(invalid).is_empty(), "malformed or expanded waiver subset rejected " + str(subset))
	var invalid := item.duplicate(true)
	invalid.legacy_equip_waiver.level = false
	check(not Fixtures.Instances.validate(invalid).is_empty(), "nonempty level subset cannot be disabled inconsistently")
	invalid.legacy_equip_waiver.level = true
	invalid.legacy_equip_waiver.level_hero_ids = []
	check(not Fixtures.Instances.validate(invalid).is_empty(), "empty level subset cannot claim enabled bypass")
	# An earlier persisted waiver has no per-hero subset. Camp transactions
	# normalize that shape atomically, without erasing the original hero audit.
	for record: Dictionary in migrated.equipment.values():
		record.legacy_equip_waiver.erase("level_hero_ids")
		record.legacy_equip_waiver.level = true
	Game.run = null
	check(Game.new_profile() and Game._save(migrated, null), "save earlier-shape migrated fixture")
	Game.reload_profile()
	var before: Dictionary = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game._commit_profile(before) and Game.profile == before and not before.equipment[id].legacy_equip_waiver.has("level_hero_ids"), "failed camp expiry preserves input and live profile")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game._commit_profile(before) and Game.profile.equipment[id].legacy_equip_waiver.level_hero_ids == ["CH03"], "camp retry expires only high hero eligibility")
	var near_level: Dictionary = Game.profile.duplicate(true)
	near_level.hero_xp.CH03 = int(HeroProgression.thresholds()[4]) - 30
	check(Game._commit_profile(near_level), "place mage one canonical room below level-five gate")
	check(Game.select_hero("CH03"), "original low mage retains migrated physical loadout")
	check(Game.start_run({"expedition":true,"seed":1759}), "expiry fixture starts real V2 expedition")
	if Game.run == null: return
	var boundary := runtime("CH03", 250, 123, 2)
	var offer: Dictionary = Game.expedition_snapshot().relic_offers[0]
	check(Game.choose_run_relic(offer.offer_id, "skip", "", boundary), "resolve expiry fixture entrance")
	var next: Dictionary = Game.expedition_snapshot().next_node
	check(Game.choose_expedition_node(int(next.node_index), str(next.room_id)) and Game.advance_expedition_node(boundary), "expiry fixture enters combat")
	var event: String = Game.run.id + ":node:1:complete"
	var amount := int(HeroProgression.thresholds()[4])
	var rewards := {}
	before = Game.profile.duplicate(true)
	var receipt: Dictionary = Game.run.receipt()
	Game._store.max_document_bytes = 1
	check(not Game.commit_expedition_completion(event, boundary, rewards) and Game.profile == before and Game.run.receipt() == receipt, "failed XP checkpoint changes neither profile nor frozen equipment waiver")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.commit_expedition_completion(event, boundary, rewards), "XP checkpoint retries with atomic waiver metadata sync")
	check(Game.hero_level("CH03") == 5 and not Game.profile.equipment[id].legacy_equip_waiver.level and Game.run.equipment_snapshot == Game.profile.equipment, "real level-up prunes final bypass and synchronizes frozen instance snapshot")
	check(Game.run.hp == 250 and Game.run.resource == 123 and Game.run.equipment_snapshot[id].legacy_equip_waiver.type, "expiry does not refill state or remove approved mage type exception")
	var after: Dictionary = Game.profile.duplicate(true)
	check(Game.commit_expedition_completion(event, boundary, rewards) and Game.profile == after, "repeated XP completion cannot mutate expiry or reward twice")
	Game.reload_profile()
	check(Game.run != null and Game.run.level == 5 and Game.run.equipment_snapshot == Game.profile.equipment and Game.run.equipment_snapshot[id].legacy_equip_waiver.level_hero_ids.is_empty(), "atomic expired metadata survives actual expedition disk reload")
	check(Fixtures.Instances.can_equip(Game.profile.equipment[id], "CH03", 5) and not Fixtures.Instances.can_equip(Game.profile.equipment[id], "CH02", 1), "reload retains only original type authority without a new hero level exception")
	Game.run = null
	check(Game._commit_profile(before) and Game.start_run(), "earlier underlevel fixture starts non-expedition XP path")
	var old_snapshot: Dictionary = Game.run.equipment_snapshot.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game.grant_hero_xp(30, "waiver:non-expedition") and Game.run.equipment_snapshot == old_snapshot and Game.hero_level("CH03") == 4, "failed non-expedition XP leaves level waiver and level untouched")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.grant_hero_xp(30, "waiver:non-expedition") and Game.run.level == 5 and not Game.run.equipment_snapshot[id].legacy_equip_waiver.level, "non-expedition XP success synchronizes expired runtime metadata")
	check(Game.run.equipment_snapshot == Game.profile.equipment and Game.run.equipment_snapshot[id].legacy_equip_waiver.type, "normal XP path keeps instance rolls and mage type authority")
