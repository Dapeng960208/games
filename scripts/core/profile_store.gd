class_name ProfileStore
extends RefCounted
## One document commits rewards, discoveries, and active-run clearing together.
## A flushed newer temporary document is a recoverable commit intent.

const SCHEMA_VERSION := 3
const SETTLEMENT_RULES_VERSION := 2
const Expedition = preload("res://scripts/core/expedition_state.gd")
const MAX_NUMBER := 1_000_000_000_000
const RELIC_IDS := ["split", "ember", "arc"]
const OUTCOMES := ["extracted", "death", "abandoned"]
const HERO_IDS := ["CH01", "CH02", "CH03"]
const BOSS_IDS := ["BO01", "BO02", "BO03", "BO04"]
const SLOTS := ["weapon", "head", "chest", "hands", "feet", "charm"]
const STARTER_IDS := ["EQ01", "EQ11", "EQ21", "EQ31", "EQ41", "EQ51"]
const MAX_TRANSACTIONS := 4096 # Bounded purchase/upgrade/recycle receipts; never evict IDs.
const VOLUME_DEFAULTS := {"master_volume":1.0,"music_volume":0.55,"sfx_volume":0.85}
const Controls = preload("res://scripts/core/control_bindings.gd")
const COMBAT_SETTING_DEFAULTS := {"auto_attack": false, "enemy_skill_paths": true}

var path: String
var last_error: String = ""
var warning: String = ""
var has_profile: bool = false
var unresolved_error: bool:
	get:
		return _blocked
var _current: Dictionary = {}
var _blocked: bool = false

func _init(save_path: String = "user://profile.json") -> void:
	path = save_path

static func fresh_profile() -> Dictionary:
	return {
		"permanent_gold": 0, "discoveries": [], "total_runs": 0,
		"last_result": {},
		"settings": {"language": "zh_CN", "reduced_fx": false, "camera_shake": false, "fullscreen": false,
			"auto_attack": false, "enemy_skill_paths": true, "controls": {},
			"master_volume":1.0,"music_volume":0.55,"sfx_volume":0.85},
		"selected_hero": "CH01", "hero_xp": {"CH01": 0, "CH02": 0, "CH03": 0},
		"branches": {"CH01": {"q": "", "ultimate": ""}, "CH02": {"q": "", "ultimate": ""},
			"CH03": {"q": "", "ultimate": ""}},
		"equipment": {"EQ01": {"level": 0}, "EQ11": {"level": 0}, "EQ21": {"level": 0},
			"EQ31": {"level": 0}, "EQ41": {"level": 0}, "EQ51": {"level": 0}},
		"loadout": {"weapon": "EQ01", "head": "EQ11", "chest": "EQ21",
			"hands": "EQ31", "feet": "EQ41", "charm": "EQ51"},
		"bosses": [], "tutorial_completed": [], "migration_id": "new_v2",
		"equipment_discoveries": [],
		"applied_transactions": {"starter_grant_v1": {"kind": "starter"}},
	}

func load_document() -> Dictionary:
	last_error = ""
	warning = ""
	_current = {}
	_blocked = false
	has_profile = false
	var best_path := ""
	# All candidates contain whole transactions; never merge fields across files.
	for candidate: String in [path, path + ".tmp", path + ".bak", path + ".bak.tmp"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			_blocked = true
			last_error = "STORAGE_READ_FAILED"
			continue
		var parser := JSON.new()
		var parsed: Variant = null
		if file.get_length() <= 1_048_576 and parser.parse(file.get_as_text()) == OK:
			parsed = parser.data
		file.close()
		if not _valid_document(parsed):
			# Keep unreadable bytes available for inspection; never silently delete.
			var preserved := candidate + ".corrupt." + str(int(Time.get_unix_time_from_system())) + "_" + str(Time.get_ticks_usec())
			if DirAccess.copy_absolute(candidate, preserved) != OK:
				_blocked = true
				last_error = "STORAGE_PRESERVE_FAILED"
			warning = "STORAGE_CORRUPT_PRESERVED"
			continue
		var document: Dictionary = parsed
		if _current.is_empty() or int(document.revision) > int(_current.revision):
			_current = document.duplicate(true)
			best_path = candidate
	if _blocked:
		return {}
	if _current.is_empty():
		if not warning.is_empty():
			last_error = "STORAGE_NO_VALID_PROFILE"
			_blocked = true
		return {}
	has_profile = bool(_current.get("profile_initialized", true))
	if best_path != path:
		warning = "STORAGE_RECOVERED"
	if int(_current.schema_version) == 1:
		# Keep the original, strictly validated v1 document before the atomic upgrade.
		# Never replace an earlier migration backup, including on a failed retry.
		if not FileAccess.file_exists(path + ".v1.bak"):
			if DirAccess.copy_absolute(best_path, path + ".v1.bak") != OK:
				last_error = "STORAGE_PRESERVE_FAILED"
				_blocked = true
				has_profile = false
				return {}
		var migrated := _migrate_v1(_current)
		var had_active: bool = _current.active_run is Dictionary
		if not save_document(migrated, null):
			_blocked = true
			has_profile = false
			return {}
		warning = "STORAGE_ABANDONED_RECOVERED" if had_active else "STORAGE_MIGRATED"
	elif not _current.profile.has("branches"):
		# Early v2 saves predate talent choices. Normalize the whole document once;
		# retain its active receipt so the controller still performs one abandonment.
		var normalized: Dictionary = _current.profile.duplicate(true)
		normalized.branches = fresh_profile().branches
		if not save_document(normalized, _current.active_run, bool(_current.get("profile_initialized", true))):
			_blocked = true
			has_profile = false
			return {}
	var loaded := _current.duplicate(true)
	# Normalize optional presentation settings in memory only; opening a demo
	# must not rewrite a save just to add the comfort default or volume keys.
	if not loaded.profile.settings.has("camera_shake"): loaded.profile.settings.camera_shake = false
	for key: String in VOLUME_DEFAULTS:
		if not loaded.profile.settings.has(key): loaded.profile.settings[key] = VOLUME_DEFAULTS[key]
	for key: String in COMBAT_SETTING_DEFAULTS:
		if not loaded.profile.settings.has(key): loaded.profile.settings[key] = COMBAT_SETTING_DEFAULTS[key]
	# Fill absent keys without changing any bindings already chosen by the player.
	if not loaded.profile.settings.has("controls"): loaded.profile.settings.controls = {}
	return loaded

func save_document(profile: Dictionary, active_run: Variant = null, profile_initialized: bool = true) -> bool:
	last_error = ""
	if _blocked:
		last_error = "STORAGE_NO_VALID_PROFILE"
		return false
	var document := {
		"schema_version": SCHEMA_VERSION,
		"profile_initialized": profile_initialized,
		"revision": int(_current.get("revision", 0)) + 1,
		"profile": profile.duplicate(true),
		"active_run": active_run.duplicate(true) if active_run is Dictionary else null,
	}
	if not _valid_document(document):
		last_error = "STORAGE_INVALID_DATA"
		return false
	var directory := ProjectSettings.globalize_path(path).get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	# Preserve the last acknowledged whole transaction before replacing a candidate.
	if not _current.is_empty():
		if not _write_document(path + ".bak.tmp", _current):
			return false
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			last_error = "STORAGE_REPLACE_FAILED"
			return false
	if not _write_document(path + ".tmp", document):
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		last_error = "STORAGE_REPLACE_FAILED"
		return false
	_current = document
	has_profile = profile_initialized
	return true

func _write_document(destination: String, document: Dictionary) -> bool:
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	return true

static func _number(value: Variant, maximum: float = MAX_NUMBER, integral: bool = true) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= maximum and (not integral or number == floor(number))

static func _relics(value: Variant) -> bool:
	if not value is Array or value.size() > RELIC_IDS.size():
		return false
	var seen: Array = []
	for id: Variant in value:
		if not id is String or not id in RELIC_IDS or id in seen:
			return false
		seen.append(id)
	return true

static func retained_gold(gold: int, outcome: String, rules_version: int = SETTLEMENT_RULES_VERSION) -> int:
	# Historical receipts never depend on today's tunable Balance constants.
	if rules_version not in [1, 2] or gold < 0 or outcome not in OUTCOMES:
		return -1
	if outcome == "extracted": return gold
	if rules_version == 2 and outcome == "death": return int(gold / 2)
	return int(gold / 5)

static func _migrate_v1(document: Dictionary) -> Dictionary:
	var migrated := fresh_profile()
	for key: String in ["permanent_gold", "discoveries", "total_runs", "last_result", "settings"]:
		migrated[key] = document.profile[key].duplicate(true) if document.profile[key] is Dictionary or document.profile[key] is Array else document.profile[key]
	migrated.migration_id = "profile_v1_to_v2"
	if not migrated.last_result.is_empty():
		migrated.last_result.rules_version = 1
		migrated.last_result.wallet_before = int(migrated.last_result.permanent_gold) - int(migrated.last_result.retained)
		migrated.last_result.wallet_after = int(migrated.last_result.permanent_gold)
	if document.active_run is Dictionary:
		var receipt: Dictionary = document.active_run
		var retained := retained_gold(int(receipt.gold), "abandoned", 1)
		var discoveries: Array = []
		for id: String in receipt.discoveries:
			if not id in migrated.discoveries:
				migrated.discoveries.append(id)
				discoveries.append(id)
		var before := int(migrated.permanent_gold)
		migrated.permanent_gold = before + retained
		migrated.total_runs = int(migrated.total_runs) + 1
		migrated.last_result = {"run_id": receipt.id, "outcome": "abandoned", "collected": receipt.gold,
			"retained": retained, "lost": int(receipt.gold) - retained, "permanent_gold": migrated.permanent_gold,
			"wallet_before": before, "wallet_after": migrated.permanent_gold, "rules_version": 1,
			"discoveries": discoveries, "kills": receipt.kills, "shots": receipt.shots, "elapsed": receipt.elapsed}
	return migrated

static func _valid_receipt(value: Variant, version: int = 1) -> bool:
	if not value is Dictionary:
		return false
	if not value.get("id") is String or value.id.is_empty() or value.id.length() > 80:
		return false
	var valid := _number(value.get("gold")) and _relics(value.get("discoveries")) \
		and _number(value.get("shots")) and _number(value.get("kills")) \
		and _number(value.get("elapsed"), MAX_NUMBER, false)
	if not valid or version == 1:
		return valid
	return value.get("hero_id") in HERO_IDS and _number(value.get("level"), 20) and value.level >= 1 \
		and _number(value.get("hero_xp_gained"), 3600) and value.get("rules_version") == 1 \
		and _unique_ids(value.get("completed_reward_ids"), 512) \
		and _allowed_ids(value.get("boss_defeats"), BOSS_IDS)

static func _valid_result(value: Variant, version: int = 1) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not value.get("run_id") is String or value.run_id.is_empty() or value.run_id.length() > 80:
		return false
	if not value.get("outcome") in OUTCOMES:
		return false
	for key: String in ["collected", "retained", "lost", "permanent_gold", "shots", "kills"]:
		if not _number(value.get(key)):
			return false
	# Missing rules belong to the original format. Never reinterpret an old
	# receipt with the default used for newly settled runs.
	var rules: Variant = value.get("rules_version", 1)
	if not _number(rules, SETTLEMENT_RULES_VERSION) or int(rules) < 1: return false
	if version == 1 and int(rules) != 1: return false
	var expected_retained := retained_gold(int(value.collected), str(value.outcome), int(rules))
	var valid := int(value.retained) == expected_retained and int(value.retained) + int(value.lost) == int(value.collected) \
		and _relics(value.get("discoveries")) and _number(value.get("elapsed"), MAX_NUMBER, false)
	if not valid or version == 1:
		return valid
	if value.has("field_xp_gained"):
		if not _number(value.field_xp_gained, 18): return false
		if int(value.field_xp_gained) > 0 and (int(rules) != 2 or value.outcome != "death"): return false
		if not _number(value.get("hero_xp_gained"), 3600) or int(value.field_xp_gained) > int(value.hero_xp_gained): return false
	if version >= 3:
		for key: String in ["equipment_retained", "equipment_lost"]:
			if value.has(key):
				if not _unique_ids(value[key], ContentRegistry.equipment_ids().size()): return false
				for id: String in value[key]:
					if ContentRegistry.equipment(id).is_empty(): return false
		if value.outcome != "extracted" and not value.get("equipment_retained", []).is_empty(): return false
		if value.outcome == "extracted" and not value.get("equipment_lost", []).is_empty(): return false
	return _number(value.get("wallet_before")) \
		and _number(value.get("wallet_after")) and int(value.wallet_after) == int(value.permanent_gold) \
		and int(value.wallet_before) + int(value.retained) == int(value.wallet_after)

static func _valid_document(value: Variant) -> bool:
	# Godot JSON parses numeric tokens as floats; Array.has is type-sensitive.
	if not value is Dictionary or not _number(value.get("schema_version"), SCHEMA_VERSION) \
		or int(value.schema_version) < 1:
		return false
	var version := int(value.schema_version)
	if value.has("profile_initialized") and not value.profile_initialized is bool:
		return false
	if not _number(value.get("revision")) or not value.get("profile") is Dictionary:
		return false
	var profile: Dictionary = value.profile
	if not _number(profile.get("permanent_gold")) or not _number(profile.get("total_runs")) \
		or not _relics(profile.get("discoveries")) or not _valid_result(profile.get("last_result"), version):
		return false
	var settings: Variant = profile.get("settings")
	if not settings is Dictionary or not settings.get("language") in ["zh_CN", "en"] \
		or not settings.get("reduced_fx") is bool or not settings.get("fullscreen") is bool:
		return false
	if settings.has("camera_shake") and not settings.camera_shake is bool: return false
	for key: String in COMBAT_SETTING_DEFAULTS:
		if settings.has(key) and not settings[key] is bool: return false
	if settings.has("controls") and not Controls.valid_overrides(settings.controls): return false
	for key: String in VOLUME_DEFAULTS:
		if settings.has(key) and not _number(settings[key], 1.0, false): return false
	if not value.has("active_run"):
		return false
	if not profile.last_result.is_empty():
		if version == 1 and int(profile.last_result.permanent_gold) != int(profile.permanent_gold):
			return false
		for id: String in profile.last_result.discoveries:
			if not id in profile.discoveries:
				return false
	if version >= 2 and not _valid_progression(profile):
		return false
	if version >= 2 and not bool(value.get("profile_initialized", true)):
		# A settings-only file must not disguise earned assets or an active run.
		if value.active_run != null or not _settings_only(profile):
			return false
	if value.active_run == null:
		return true
	if not _valid_receipt(value.active_run, version) or value.active_run.id == profile.last_result.get("run_id", ""): return false
	if value.active_run.has("expedition"):
		return version == 3 and Expedition.valid(value.active_run, profile)
	return true

static func _unique_ids(value: Variant, maximum: int = 512) -> bool:
	if not value is Array or value.size() > maximum:
		return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not id is String or id.is_empty() or id.length() > 160 or seen.has(id):
			return false
		seen[id] = true
	return true

static func _allowed_ids(value: Variant, allowed: Array) -> bool:
	if not _unique_ids(value, allowed.size()):
		return false
	for id: String in value:
		if not id in allowed:
			return false
	return true

static func _valid_progression(profile: Dictionary) -> bool:
	if profile.has("equipment_discoveries"):
		if not _unique_ids(profile.equipment_discoveries, ContentRegistry.equipment_ids().size()): return false
		for eq: String in profile.equipment_discoveries:
			if ContentRegistry.equipment(eq).is_empty(): return false
	if not profile.get("selected_hero") in HERO_IDS or not profile.get("hero_xp") is Dictionary:
		return false
	if profile.hero_xp.size() != HERO_IDS.size():
		return false
	for id: String in HERO_IDS:
		if not _number(profile.hero_xp.get(id), 3600):
			return false
	# A missing field is a valid early v2 document and is atomically normalized on load.
	if profile.has("branches") and not _valid_branches(profile.branches, profile.hero_xp):
		return false
	if not profile.get("equipment") is Dictionary or profile.equipment.size() > ContentRegistry.equipment_ids().size() \
		or not profile.get("loadout") is Dictionary or profile.loadout.size() != SLOTS.size():
		return false
	for id: Variant in profile.equipment:
		if not id is String or ContentRegistry.equipment(id).is_empty():
			return false
		var owned: Variant = profile.equipment[id]
		if not owned is Dictionary or not _number(owned.get("level"), Expedition.MAX_EQUIPMENT_LEVEL):
			return false
	for slot: String in SLOTS:
		var id: Variant = profile.loadout.get(slot)
		if not id is String or not profile.equipment.has(id) or ContentRegistry.equipment(id).get("slot") != slot:
			return false
	if not _allowed_ids(profile.get("bosses"), BOSS_IDS) \
		or not _allowed_ids(profile.get("tutorial_completed"), HERO_IDS) \
		or not profile.get("migration_id") in ["new_v2", "profile_v1_to_v2"]:
		return false
	var ledger: Variant = profile.get("applied_transactions")
	if not ledger is Dictionary or ledger.size() > MAX_TRANSACTIONS or not ledger.has("starter_grant_v1"):
		return false
	for id: Variant in ledger:
		if not id is String or id.is_empty() or id.length() > 160 or not ledger[id] is Dictionary:
			return false
		var entry: Dictionary = ledger[id]
		if id == "starter_grant_v1":
			if entry.get("kind") != "starter":
				return false
		elif entry.get("kind") == "purchase_set":
			var pieces := ContentRegistry.set_item_ids(str(entry.get("item", "")))
			if pieces.size() != SLOTS.size() or not _number(entry.get("price")) or not _unique_ids(entry.get("items"), SLOTS.size()) or entry.items.is_empty(): return false
			var paid := 0
			for eq_id: String in entry.items:
				if not eq_id in pieces: return false
				paid += int(ContentRegistry.equipment(eq_id).price) * 9 / 10
			if paid != int(entry.price): return false
		elif entry.get("kind") == "sale":
			if not entry.get("items") is Dictionary or entry.items.is_empty() or entry.items.size() > ContentRegistry.equipment_ids().size() or not _number(entry.get("price")): return false
			var proceeds := 0
			var sold_ids: Array = entry.items.keys()
			sold_ids.sort()
			if entry.get("item") != ",".join(sold_ids): return false
			for eq_id: String in sold_ids:
				var record: Variant = entry.items[eq_id]
				if not record is Dictionary or not _number(record.get("level"), Expedition.MAX_EQUIPMENT_LEVEL): return false
				var worth := equipment_sell_price(eq_id,int(record.level))
				if worth <= 0 or record.get("price") != worth: return false
				proceeds += worth
			if proceeds != int(entry.price): return false
		elif not entry.get("kind") in ["purchase", "upgrade"] or ContentRegistry.equipment(str(entry.get("item", ""))).is_empty() \
			or not _number(entry.get("price")) or not _number(entry.get("level"), Expedition.MAX_EQUIPMENT_LEVEL):
			return false
	return true

static func equipment_sell_price(eq_id: String, level: int) -> int:
	var item := ContentRegistry.equipment(eq_id)
	if item.is_empty() or level < 0 or level > Expedition.MAX_EQUIPMENT_LEVEL: return 0
	var worth := int(item.price) / 4
	for index in range(level): worth += ContentRegistry.UPGRADE_COSTS[index] / 5
	return worth

static func _valid_branches(value: Variant, hero_xp: Dictionary) -> bool:
	if not value is Dictionary or value.size() != HERO_IDS.size():
		return false
	for id: String in HERO_IDS:
		var choices: Variant = value.get(id)
		if not choices is Dictionary or choices.size() != 2:
			return false
		var level := ContentRegistry.level_for_xp(int(hero_xp[id]))
		for slot: String in ["q", "ultimate"]:
			if not choices.get(slot) in ["", "A", "B"]:
				return false
			if choices[slot] != "" and level < (18 if slot == "q" else 20):
				return false
	return true

static func _settings_only(profile: Dictionary) -> bool:
	if not profile.get("equipment_discoveries", []).is_empty(): return false
	if int(profile.permanent_gold) != 0 or int(profile.total_runs) != 0 or not profile.last_result.is_empty() \
		or not profile.discoveries.is_empty() or not profile.bosses.is_empty() or not profile.tutorial_completed.is_empty() \
		or profile.selected_hero != "CH01" or profile.migration_id != "new_v2" \
		or profile.applied_transactions.size() != 1 or profile.equipment.size() != STARTER_IDS.size() \
		or profile.loadout != fresh_profile().loadout:
		return false
	for id: String in HERO_IDS:
		if int(profile.hero_xp[id]) != 0:
			return false
	for id: String in STARTER_IDS:
		if not profile.equipment.has(id) or int(profile.equipment[id].level) != 0:
			return false
	# _valid_branches already excludes nonempty choices at level one.
	return true
