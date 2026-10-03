extends Node
## Synthetic compatible schema-3 profiles and disposable service transactions.
## A fixture upgrade is not evidence of a natural expedition playthrough.

const Skills = preload("res://scripts/domain/progression/skill_progression.gd")
const Service = preload("res://scripts/app/services/skill_config_service.gd")
const Catalog = preload("res://scripts/domain/combat/skill_catalog.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
var checks := 0
var failures: Array[String] = []
var snapshot_values: Dictionary = {}

class Host extends Node:
	signal changed
	var profile: Dictionary
	var run: RefCounted
	var last_error := ""
	var fail := false
	var writes: Array[Dictionary] = []
	var store: RefCounted
	func _camp_available() -> bool:
		return run == null
	func _save(candidate: Dictionary, receipt: Variant) -> bool:
		writes.append({"profile":candidate.duplicate(true), "receipt":receipt.duplicate(true) if receipt is Dictionary else receipt})
		if fail:
			last_error = "STORAGE_WRITE_FAILED"
			return false
		if store != null:
			var saved: bool = store.save_document(candidate, receipt)
			last_error = store.last_error
			return saved
		return true

func _ready() -> void:
	_run.call_deferred()

func same_values(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("SKILL CONFIG: " + label)

func _run() -> void:
	if not Game.profile_path.contains("test_skill_config_migration"):
		push_error("Use --test-profile containing test_skill_config_migration")
		get_tree().quit(2)
		return
	check(Game.new_profile(), "fresh isolated current-schema profile")
	_migration()
	_validation()
	_service_transactions()
	_checkpoint_growth()
	_disk_failures()
	await _snapshot_migration()
	_whole_receipt_migration()
	print("SKILL CONFIG MIGRATION: %d checks; failures=%s; synthetic fixtures" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _old_profile() -> Dictionary:
	var old: Dictionary = Game.profile.duplicate(true)
	for key: String in ["skill_system_version", "role_combat_version", "skill_state", "skill_unlock_groups", "skill_config_receipts"]:
		old.erase(key)
	return old

func _migration() -> void:
	var old: Dictionary = _old_profile()
	old.selected_hero = "CH03"
	for hero: String in Skills.HERO_IDS:
		old.hero_xp[hero] = int(ProfileStore.Progression.thresholds().back())
		old.branches[hero] = {"q":"A", "ultimate":"B"}
	var document := {"schema_version":3, "revision":1, "profile_initialized":true, "profile":old, "active_run":null}
	check(ProfileStore._valid_document(document), "complete pre-skill schema-3 profile validates before upgrade")
	var migrated: Dictionary = Skills.upgrade_profile(old)
	check(not migrated.is_empty() and Skills.valid(migrated, true), "compatible old profile upgrades into a complete subsystem")
	if migrated.is_empty():
		return
	for key: String in ["selected_hero", "hero_xp", "equipment", "loadout", "bosses", "applied_transactions"]:
		check(migrated[key] == old[key], "migration preserves " + key)
	check(ProfileStore.SCHEMA_VERSION == 3 and ProfileStore.SETTLEMENT_RULES_VERSION == 3, "main schema and settlement versions stay at three")
	for hero: String in Skills.HERO_IDS:
		var state: Dictionary = migrated.skill_state[hero]
		check(state.loadout == Skills.starter_ids(hero) and state.learned.size() == 4, hero + " maps old four slots to the four starter identities")
		check(int(state.mastery[hero + "_SK01"]) == 140 and str(state.branches[hero + "_SK01"]) == "A", hero + " old first branch becomes mastery-four branch A")
		check(int(state.mastery[hero + "_SK04"]) == 300 and str(state.branches[hero + "_SK04"]) == "B", hero + " old ultimate branch becomes mastery-five branch B")
		check(int(state.mastery[hero + "_SK02"]) == 20 and int(state.mastery[hero + "_SK03"]) == 20, hero + " old special perks become mastery two once")
	check(Skills.upgrade_profile(migrated) == migrated, "second upgrade cannot add progress again")
	check(old == document.profile and not old.has("skill_system_version"), "upgrade leaves original accepted fixture unchanged")
	var filename: String = Game.profile_path.get_base_dir() + "/test_old_skill_document.json"
	var file := FileAccess.open(filename, FileAccess.WRITE)
	check(file != null, "isolated old-profile file opens")
	if file != null:
		file.store_string(JSON.stringify(document))
		file.close()
		var store := ProfileStore.new(filename)
		var loaded: Dictionary = store.load_document()
		check(not loaded.is_empty() and Skills.valid(loaded.get("profile", {}), true), "real old schema-three file loads and atomically upgrades")
		if not loaded.is_empty():
			check(same_values(loaded.profile.hero_xp, old.hero_xp) and same_values(loaded.profile.equipment, old.equipment), "old file migration keeps character progress and gear instances")
			var again := ProfileStore.new(filename)
			check(same_values(again.load_document().get("profile", {}), loaded.profile), "migrated file reload is idempotent")

func _validation() -> void:
	var profile: Dictionary = _old_profile()
	profile.merge(Skills.fresh_fields(), true)
	check(Skills.valid(profile, true), "new skill fields validate as a whole")
	var invalid: Dictionary = profile.duplicate(true)
	invalid.skill_state.CH01.loadout[1] = invalid.skill_state.CH01.loadout[0]
	check(not Skills.valid(invalid, true), "duplicate configured skill is rejected")
	invalid = profile.duplicate(true)
	invalid.skill_state.CH01.loadout[1] = "CH02_SK02"
	check(not Skills.valid(invalid, true), "cross-class configured skill is rejected")
	invalid = profile.duplicate(true)
	invalid.skill_state.CH01.loadout[1] = "CH01_SK05"
	check(not Skills.valid(invalid, true), "unlearned skill is rejected")
	invalid = profile.duplicate(true)
	invalid.skill_state.CH01.branches.CH01_SK01 = "A"
	check(not Skills.valid(invalid, true), "branch below mastery threshold is rejected")
	invalid = profile.duplicate(true)
	invalid.skill_state.CH01.mastery.CH01_SK01 = 19.5
	check(not Skills.valid(invalid, true), "fractional mastery is rejected")
	invalid = _old_profile()
	invalid.skill_system_version = 1
	check(Skills.upgrade_profile(invalid).is_empty(), "partial subsystem is not treated as a compatible old profile")
	invalid = profile.duplicate(true)
	invalid.skill_system_version = 999
	check(Skills.upgrade_profile(invalid).is_empty(), "unknown subsystem version is not reset")
	for pair: Array in [[0,1], [19,1], [20,2], [59,2], [60,3], [139,3], [140,4], [299,4], [300,5]]:
		check(Skills.level(int(pair[0])) == int(pair[1]), "mastery boundary " + str(pair[0]))
	for pair: Array in [[2.4,1], [4.0,1], [4.01,2], [32.0,8], [48.0,12], [60.0,12]]:
		check(Skills.release_xp(float(pair[0])) == int(pair[1]), "first-release XP budget " + str(pair[0]))

func _service_transactions() -> void:
	var service: RefCounted = Service.new(Game)
	check(Skills.valid(Game.profile, true), "actual fresh profile includes the complete skill subsystem")
	if not Skills.valid(Game.profile, true):
		return
	var originals: Array[String] = service.get_loadout("CH01")
	var changed: Array[String] = originals.duplicate()
	changed.reverse()
	var before: Dictionary = Game.profile.duplicate(true)
	for invalid: Array in [["CH01_SK01", "CH01_SK01", "CH01_SK03", "CH01_SK04"], ["CH01_SK01", "CH02_SK02", "CH01_SK03", "CH01_SK04"], ["CH01_SK01", "CH01_SK05", "CH01_SK03", "CH01_SK04"], ["CH01_SK01"]]:
		check(not bool(service.apply_skill_config("CH01", invalid, {}, "fixture:invalid:" + str(checks)).ok), "service rejects incomplete, repeated, unlearned or foreign configuration")
	check(Game.profile == before, "invalid requests cannot mutate the profile")
	check(not bool(service.apply_skill_config("CH01", changed, {"CH01_SK01":"A"}, "fixture:locked-branch").ok), "service rejects branch below mastery four")
	var limit: int = Game._store.max_document_bytes
	Game._store.max_document_bytes = 1
	var failed: Dictionary = service.apply_skill_config("CH01", changed, {}, "fixture:config-retry")
	check(not bool(failed.ok) and str(failed.reason) == "STORAGE_CAPACITY_EXCEEDED", "failed atomic config returns storage reason and transaction id")
	check(Game.profile == before and service.pending_operation() == "fixture:config-retry", "failed config preserves memory and the exact retry candidate")
	Game._store.max_document_bytes = limit
	check(not bool(service.apply_skill_config("CH01", originals, {}, "fixture:config-retry").ok), "same operation cannot replace its failed candidate with different slots")
	check(bool(service.apply_skill_config("CH01", changed, {}, "fixture:config-retry").ok), "the same config transaction retries successfully")
	check(service.get_loadout("CH01") == changed, "successful commit changes all four slots together")
	var committed: Dictionary = Game.profile.duplicate(true)
	check(bool(service.apply_skill_config("CH01", changed, {}, "fixture:config-retry").ok) and Game.profile == committed, "repeated config operation is idempotent")
	Game.reload_profile()
	check(service.get_loadout("CH01") == changed and same_values(Game.profile, committed), "config and receipt survive actual save/reload")
	check(Game.start_run(), "isolated expedition state starts")
	if Game.run == null:
		return
	var frozen: Array = Game.run.skill_loadout_snapshot.duplicate()
	var expedition: Dictionary = Game.run.expedition.duplicate(true)
	for phase: String in ["entrance", "combat", "cleared", "supply", "boss", "transition"]:
		Game.run.expedition = {"phase":phase}
		check(not bool(service.apply_skill_config("CH01", originals, {}, "fixture:run-lock:" + phase).ok), "entire expedition blocks configuration during " + phase)
	get_tree().paused = true
	check(not bool(service.apply_skill_config("CH01", originals, {"CH01_SK01":"B"}, "fixture:pause-lock").ok), "pause cannot unlock configuration or branches")
	get_tree().paused = false
	Game.run.expedition = expedition
	check(Game.run.skill_loadout_snapshot == frozen, "rejected edits keep departure snapshot unchanged")
	var id: String = str(frozen[0]) if frozen.size() == 4 else "CH01_SK01"
	var xp_before: int = int(service.get_progress("CH01", id).xp)
	check(not bool(service.record_skill_release(id, 1, false).ok), "preview/out-of-combat release cannot grow mastery")
	check(bool(service.record_skill_release(id, 1, true).ok), "first actual combat release grows permanent mastery")
	var gained: int = Skills.release_xp(float(Catalog.skill(id).base_cooldown))
	check(int(service.get_progress("CH01", id).xp) == mini(300, xp_before + gained), "mastery uses the identity's base cooldown once")
	check(bool(service.record_skill_release(id, 1, true).ok) and int(service.get_progress("CH01", id).xp) == mini(300, xp_before + gained), "multi-hit or repeated callback cannot repeat mastery")
	for group: String in Skills.GROUPS:
		check(bool(service.grant_skill_group(group, "fixture:reward:" + group).ok), "shared reward commits " + group)
		var size: int = Game.profile.skill_unlock_groups.size()
		check(bool(service.grant_skill_group(group, "fixture:repeat:" + group).ok) and Game.profile.skill_unlock_groups.size() == size, "repeat reward is idempotent " + group)
		for hero: String in Skills.HERO_IDS:
			var unlocked: String = "%s_SK%02d" % [hero, Skills.GROUPS.find(group) + 5]
			check(bool(service.get_progress(hero, unlocked).learned), group + " unlocks " + unlocked)
	check(Game.run.skill_loadout_snapshot == frozen and service.get_loadout("CH01") == frozen, "permanent rewards cannot change current expedition's four skills")
	var mastery: Dictionary = Game.profile.skill_state.CH01.mastery.duplicate()
	var learned: Array = Game.profile.skill_state.CH01.learned.duplicate()
	check(not Game.finish_run("death").is_empty(), "isolated death settles")
	Game.reload_profile()
	check(same_values(Game.profile.skill_state.CH01.mastery, mastery) and Game.profile.skill_state.CH01.learned == learned, "death and reload retain skill unlocks and mastery")

func _checkpoint_growth() -> void:
	var host := Host.new()
	host.profile = ProfileStore.NativeProfile.fresh(ProfileStore.fresh_profile())
	host.run = RunSession.new()
	host.run.id = "fixture:checkpoint"
	host.run.hero_id = "CH01"
	host.run.skill_loadout_snapshot = Catalog.starter_ids("CH01")
	host.run.expedition = {"phase":"combat", "live_only":"partial room"}
	host.run.committed_receipt = {"checkpoint":"acknowledged", "gold":17}
	var service: RefCounted = Service.new(host)
	host.fail = true
	check(not bool(service.record_skill_release("CH01_SK01", 1, true).ok), "failed growth keeps a retry intent")
	check(int(host.profile.skill_state.CH01.mastery.CH01_SK01) == 0 and int(host.profile.skill_state.CH01.cast_cursor) == 0, "failed growth does not partially apply mastery or cursor")
	host.run.gold = 999
	host.run.expedition.live_only = "later partial room"
	host.fail = false
	check(bool(service.retry_pending().ok), "growth retries its original transaction")
	check(host.writes.back().receipt == host.run.committed_receipt, "permanent growth save carries the acknowledged checkpoint instead of live room state")
	var xp: int = int(host.profile.skill_state.CH01.mastery.CH01_SK01)
	check(bool(service.record_skill_release("CH01_SK01", 1, true).ok) and int(host.profile.skill_state.CH01.mastery.CH01_SK01) == xp, "checkpoint callback cannot replay a committed cast")
	check(bool(service.record_skill_release("CH01_SK01", 2, true).ok) and int(host.profile.skill_state.CH01.cast_cursor) == 2, "next cast continues after failed growth recovery")
	host.run = null
	host.profile.skill_state.CH01.mastery.CH01_SK01 = 140
	host.fail = true
	var originals: Array[String] = Catalog.starter_ids("CH01")
	check(not bool(service.apply_skill_config("CH01", originals, {"CH01_SK01":"A"}, "fixture:branch-A").ok), "branch configuration can fail as a whole")
	host.fail = false
	var moved: Array[String] = originals.duplicate()
	moved.reverse()
	check(bool(service.apply_skill_config("CH01", moved, {}, "fixture:slots-B").ok) and str(host.profile.skill_state.CH01.branches.CH01_SK01) == "A", "new slot request first recovers prior branch intent and preserves it")
	host.free()

func _disk_failures() -> void:
	for stage: String in ["write", "rename"]:
		var filename: String = Game.profile_path.get_base_dir() + "/test_skill_atomic_" + stage + ".json"
		var host := Host.new()
		host.profile = ProfileStore.NativeProfile.fresh(ProfileStore.fresh_profile())
		host.store = ProfileStore.new(filename)
		check(host.store.save_document(host.profile), stage + " creates an isolated acknowledged document")
		var originals: Array[String] = Catalog.starter_ids("CH01")
		var moved: Array[String] = originals.duplicate()
		moved.reverse()
		var service: RefCounted = Service.new(host)
		var before: Dictionary = host.profile.duplicate(true)
		var bytes := FileAccess.get_file_as_bytes(filename)
		var blocked: String = filename + ".bak.tmp" if stage == "write" else filename
		if stage == "rename":
			var backup := FileAccess.open(filename + ".bak", FileAccess.WRITE)
			backup.store_buffer(bytes)
			backup.close()
			check(DirAccess.remove_absolute(filename) == OK, "isolated primary is moved aside to inject rename failure")
		check(DirAccess.make_dir_absolute(blocked) == OK, stage + " creates an empty blocking directory")
		var operation: String = "fixture:atomic:" + stage
		check(not bool(service.apply_skill_config("CH01", moved, {}, operation).ok), stage + " failure rejects the complete configuration")
		check(host.profile == before and service.has_pending(), stage + " leaves in-memory four slots and receipts unchanged")
		check(DirAccess.remove_absolute(blocked) == OK, stage + " removes only its empty injected directory")
		if stage == "write":
			check(FileAccess.get_file_as_bytes(filename) == bytes, "write failure preserves acknowledged exact bytes")
			check(bool(service.apply_skill_config("CH01", moved, {}, operation).ok), "same failed write intent retries successfully")
		else:
			var pending: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(filename + ".tmp"))
			check(ProfileStore._valid_document(pending) and pending.profile.skill_state.CH01.loadout == moved and pending.profile.skill_config_receipts.has(operation), "flushed rename intent contains all slots and its receipt together")
		var restarted := ProfileStore.new(filename)
		var loaded: Dictionary = restarted.load_document()
		check(not loaded.is_empty() and loaded.profile.skill_state.CH01.loadout == moved and loaded.profile.skill_config_receipts.has(operation), stage + " restart recovers a complete configuration exactly once")
		host.free()

func _snapshot_migration() -> void:
	check(Game.select_hero("CH02") and Game.start_run(), "snapshot fixture starts a gunner run")
	if Game.run == null:
		return
	var room: Node2D = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.geometry_enabled = false
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	var actor: Node2D = room.player
	actor.role_kit.ammo = 2
	actor.role_kit.enhanced_shots = 1
	actor.role_kit.request_reload()
	actor.role_kit.tick(0.3)
	actor.cooldowns["CH02_SK02"] = 3.25
	Game.run.hp -= 10
	var modern: Dictionary = Snapshot.capture(room)
	snapshot_values = modern.duplicate(true)
	check(not modern.is_empty() and Snapshot.validate(modern, "CH02", Game.run.stats), "real actor exports valid version-two combat values")
	if not modern.is_empty():
		var copied: Dictionary = JSON.parse_string(JSON.stringify(modern))
		check(same_values(Snapshot.upgrade(copied, "CH02", Game.run.stats), copied), "version-two upgrade retains spent ammo and partial reload")
		check(int(copied.player.role_state.ammo) == 2 and is_equal_approx(float(copied.player.role_state.reload_elapsed), 0.3), "same-room snapshot records two rounds and partial reload")
		var legacy: Dictionary = copied.duplicate(true)
		legacy.snapshot_version = 1
		legacy.player.erase("role_state")
		legacy.player.cooldowns = {"q":0.0, "secondary":3.25, "f":0.0, "ultimate":0.0}
		check(Snapshot.validate(legacy, "CH02", Game.run.stats), "complete legacy snapshot remains readable")
		var upgraded: Dictionary = Snapshot.upgrade(legacy, "CH02", Game.run.stats)
		if upgraded.is_empty():
			var expected: Dictionary = legacy.duplicate(true)
			expected.snapshot_version = 2
			expected.player.role_state = Snapshot.initial_role_state("CH02")
			expected.player.passive_count = 0
			expected.player.cooldowns = {}
			for id: String in Skills.skill_ids("CH02"):
				expected.player.cooldowns[id] = 0.0
			expected.player.cooldowns.CH02_SK02 = 3.25
			print("SNAPSHOT DIAGNOSTIC player=%s status=%s gear=%s json=%s role=%s" % [Snapshot._player_valid(expected.player, "CH02", 2), Snapshot._status_valid(expected.status, float(Game.run.stats.max_hp), true), Snapshot._equipment_valid(expected.equipment, true), Snapshot._json(expected), load(Catalog.KIT_PATHS.CH02).validate_state(expected.player.role_state)])
		check(not upgraded.is_empty(), "legacy snapshot upgrades without changing main profile version")
		if not upgraded.is_empty():
			check(int(upgraded.player.role_state.ammo) == 8 and int(upgraded.player.role_state.enhanced_shots) == 0, "first legacy gunner migration initializes eight ordinary and zero enhanced rounds")
			check(float(upgraded.player.cooldowns.CH02_SK02) == 3.25 and upgraded.player.cooldowns.size() == 12, "old slot cooldown transfers to its stable identity in a twelve-entry table")
			check(float(upgraded.hp) == float(legacy.hp) and float(upgraded.resource) == float(legacy.resource) and same_values(upgraded.status, legacy.status), "migration retains spent health, resources and limited guards")
		var broken: Dictionary = copied.duplicate(true)
		broken.player.erase("role_state")
		check(not Snapshot.validate(broken, "CH02", Game.run.stats), "version-two missing role state is rejected instead of free refill")
	await room.combat_audio.wait_for_cleanup()
	room.free()
	Game.finish_run("abandoned")

func _whole_receipt_migration() -> void:
	check(Game.start_run({"expedition":true, "biome_id":"B01", "difficulty":0, "seed":41827}), "whole-document migration fixture starts a real chapter entrance")
	if Game.run == null:
		return
	var source: Dictionary = Game._store._current.duplicate(true)
	for phase: String in ["fresh_entry", "safe_boundary"]:
		var old: Dictionary = source.duplicate(true)
		for key: String in Skills.fresh_fields().keys():
			old.profile.erase(key)
		for key: String in ["skill_loadout_snapshot", "skill_branches_snapshot", "role_combat_version"]:
			old.active_run.erase(key)
		old.active_run.expedition.runtime.snapshot_version = 1
		if phase == "safe_boundary":
			# Exported reducers supply an old acknowledged safe boundary; this
			# complete fixture does not pretend to play or clear the entrance.
			if snapshot_values.is_empty():
				continue
			var modern: Dictionary = snapshot_values.duplicate(true)
			modern.snapshot_version = 1
			modern.player.erase("role_state")
			modern.player.cooldowns = {"q":0.0, "secondary":3.25, "f":0.0, "ultimate":0.0}
			old.active_run.expedition.runtime = modern
		check(ProfileStore._valid_document(old), phase + " old complete active expedition document validates")
		var upgraded: Dictionary = ProfileStore.upgrade_skill_document(old)
		check(not upgraded.is_empty() and ProfileStore._valid_document(upgraded), phase + " whole active document upgrades without losing its checkpoint")
		if not upgraded.is_empty():
			check(str(upgraded.profile_id) == str(old.profile_id) and str(upgraded.active_run.id) == str(old.active_run.id), phase + " upgrade preserves profile and expedition identity")
			check(str(upgraded.active_run.expedition.checkpoint_id) == str(old.active_run.expedition.checkpoint_id) and upgraded.active_run.expedition.route == old.active_run.expedition.route, phase + " upgrade retains acknowledged checkpoint and route")
			check(upgraded.active_run.skill_loadout_snapshot == Catalog.starter_ids("CH02") and int(upgraded.active_run.role_combat_version) == 2, phase + " upgrade freezes the four starter identities")
			check(float(upgraded.active_run.expedition.runtime.hp) == float(old.active_run.expedition.runtime.hp) and float(upgraded.active_run.expedition.runtime.resource) == float(old.active_run.expedition.runtime.resource), phase + " upgrade keeps spent runtime health and resources")
			var filename: String = Game.profile_path.get_base_dir() + "/test_old_active_" + phase + ".json"
			var output := FileAccess.open(filename, FileAccess.WRITE)
			output.store_string(JSON.stringify(old))
			output.close()
			var store := ProfileStore.new(filename)
			var loaded: Dictionary = store.load_document()
			check(not loaded.is_empty() and loaded.active_run is Dictionary and int(loaded.active_run.expedition.runtime.snapshot_version) == 2, phase + " real old in-progress file loads an upgraded runtime")
			check(not loaded.is_empty() and str(loaded.active_run.expedition.checkpoint_id) == str(old.active_run.expedition.checkpoint_id), phase + " old-file load does not settle or advance the pending run")
	Game.finish_run("abandoned")
