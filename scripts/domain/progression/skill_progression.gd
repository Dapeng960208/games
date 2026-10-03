class_name SkillProgression
extends RefCounted
## Permanent, value-only skill collection. The main profile schema stays at 3.

const VERSION := 1
const ROLE_VERSION := 2
const HERO_IDS := ["CH01", "CH02", "CH03"]
const THRESHOLDS := [0, 20, 60, 140, 300]
const GROUPS := ["SG01", "SG02", "SG03", "SG04", "SG05", "SG06", "SG07", "SG08"]
const MAX_CONFIG_RECEIPTS := 1024
const MAX_CAST := 1000000000

static func skill_ids(hero_id: String) -> Array[String]:
	var result: Array[String] = []
	if hero_id in HERO_IDS:
		for index in range(1, 13): result.append("%s_SK%02d" % [hero_id, index])
	return result

static func starter_ids(hero_id: String) -> Array[String]:
	return skill_ids(hero_id).slice(0, 4)

static func fresh_state(hero_id: String) -> Dictionary:
	var mastery: Dictionary = {}
	for id: String in skill_ids(hero_id): mastery[id] = 0
	return {"learned":starter_ids(hero_id), "loadout":starter_ids(hero_id), "mastery":mastery,
		"branches":{hero_id + "_SK01":"", hero_id + "_SK04":""}, "cast_run_id":"", "cast_cursor":0}

static func fresh_fields() -> Dictionary:
	var state: Dictionary = {}
	for hero_id: String in HERO_IDS: state[hero_id] = fresh_state(hero_id)
	return {"skill_system_version":VERSION, "role_combat_version":ROLE_VERSION, "skill_state":state,
		"skill_unlock_groups":[], "skill_config_receipts":{}}

static func level(xp: int) -> int:
	var rank := 1
	for index in THRESHOLDS.size():
		if xp >= THRESHOLDS[index]: rank = index + 1
	return rank

static func release_xp(base_cooldown: float) -> int:
	return clampi(int(ceilf(base_cooldown / 4.0)), 1, 12)

static func unlock_group(profile: Dictionary, group_id: String) -> Dictionary:
	if group_id not in GROUPS or not valid(profile, true): return {}
	var result := profile.duplicate(true)
	if group_id in result.skill_unlock_groups: return result
	result.skill_unlock_groups.append(group_id)
	for hero_id: String in HERO_IDS:
		result.skill_state[hero_id].learned.append("%s_SK%02d" % [hero_id, GROUPS.find(group_id) + 5])
	return result

static func view(state: Dictionary, skill_id: String) -> Dictionary:
	var xp := int(state.get("mastery", {}).get(skill_id, 0))
	var rank := level(xp)
	var previous := int(THRESHOLDS[rank - 1])
	var next := int(THRESHOLDS[rank]) if rank < 5 else previous
	return {"skill_id":skill_id, "learned":skill_id in state.get("learned", []), "xp":xp,
		"level":rank, "rank":rank, "threshold":previous, "next_threshold":next,
		"progress":1.0 if rank == 5 else float(xp - previous) / float(next - previous),
		"amount_scale":1.0 + 0.05 * (rank - 1), "branch":str(state.get("branches", {}).get(skill_id, ""))}

static func valid_loadout(value: Variant, hero_id: String, learned: Array) -> bool:
	if not value is Array or value.size() != 4: return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not id is String or id not in skill_ids(hero_id) or id not in learned or seen.has(id): return false
		seen[id] = true
	return true

static func valid_branches(value: Variant, hero_id: String, mastery: Dictionary) -> bool:
	if not value is Dictionary or value.size() != 2: return false
	for index in [1, 4]:
		var id := "%s_SK%02d" % [hero_id, index]
		if not value.get(id) in ["", "A", "B"]: return false
		if value[id] != "" and level(int(mastery.get(id, 0))) < (4 if index == 1 else 5): return false
	return true

static func valid_run_skills(receipt: Dictionary, profile: Dictionary) -> bool:
	var fields := ["skill_loadout_snapshot", "skill_branches_snapshot", "role_combat_version"]
	var present := 0
	for field: String in fields:
		if receipt.has(field): present += 1
	if present == 0:
		# A v2 combat body belongs to this subsystem and must carry its frozen
		# configuration; only a fully shaped legacy body may omit these fields.
		var expedition: Variant = receipt.get("expedition", {})
		if not expedition is Dictionary or not expedition.get("runtime", {}) is Dictionary: return false
		return expedition.get("runtime", {}).get("snapshot_version", 1) == 1
	if present != 3 or not _integer(receipt.role_combat_version, ROLE_VERSION) or receipt.role_combat_version != ROLE_VERSION: return false
	var hero_id: String = str(receipt.get("hero_id", ""))
	var state: Dictionary = profile.get("skill_state", {}).get(hero_id, {})
	return not state.is_empty() and valid_loadout(receipt.skill_loadout_snapshot, hero_id, state.learned) and valid_branches(receipt.skill_branches_snapshot, hero_id, state.mastery)

static func valid(profile: Dictionary, required: bool = false) -> bool:
	var fields := ["skill_system_version", "role_combat_version", "skill_state", "skill_unlock_groups", "skill_config_receipts"]
	var present := 0
	for field: String in fields:
		if profile.has(field): present += 1
	if present == 0: return not required
	if present != fields.size() or not _integer(profile.skill_system_version, VERSION) or not _integer(profile.role_combat_version, ROLE_VERSION) or profile.skill_system_version != VERSION or profile.role_combat_version != ROLE_VERSION: return false
	if not profile.skill_state is Dictionary or profile.skill_state.size() != 3: return false
	if not profile.skill_unlock_groups is Array or profile.skill_unlock_groups.size() > 8: return false
	var groups: Dictionary = {}
	for id: Variant in profile.skill_unlock_groups:
		if not id is String or id not in GROUPS or groups.has(id): return false
		groups[id] = true
	for hero_id: String in HERO_IDS:
		var state: Variant = profile.skill_state.get(hero_id)
		if not state is Dictionary or state.size() != 6 or not state.has_all(["learned", "loadout", "mastery", "branches", "cast_run_id", "cast_cursor"]): return false
		if not state.mastery is Dictionary or state.mastery.size() != 12 or not state.learned is Array: return false
		var expected: Array[String] = starter_ids(hero_id)
		for group: String in groups: expected.append("%s_SK%02d" % [hero_id, GROUPS.find(group) + 5])
		if state.learned.size() != expected.size(): return false
		var seen: Dictionary = {}
		for id: Variant in state.learned:
			if not id is String or id not in expected or seen.has(id): return false
			seen[id] = true
		for id: String in skill_ids(hero_id):
			if not _integer(state.mastery.get(id), 300) or (id not in expected and int(state.mastery[id]) != 0): return false
		if not valid_loadout(state.loadout, hero_id, state.learned) or not valid_branches(state.branches, hero_id, state.mastery): return false
		if not state.cast_run_id is String or state.cast_run_id.length() > 80 or not _integer(state.cast_cursor, MAX_CAST): return false
		if state.cast_run_id.is_empty() and int(state.cast_cursor) != 0: return false
	if not profile.skill_config_receipts is Dictionary or profile.skill_config_receipts.size() > MAX_CONFIG_RECEIPTS: return false
	for operation: Variant in profile.skill_config_receipts:
		var row: Variant = profile.skill_config_receipts[operation]
		if not operation is String or operation.is_empty() or operation.length() > 160 or not row is Dictionary or row.size() != 3: return false
		if row.get("hero_id") not in HERO_IDS: return false
		var state: Dictionary = profile.skill_state[row.hero_id]
		if not valid_loadout(row.get("loadout"), row.hero_id, state.learned) or not valid_branches(row.get("branches"), row.hero_id, state.mastery): return false
	return true

## Call only after the existing complete profile/document validator accepted it.
## Absence of every new field identifies a compatible pre-skill-system profile;
## a partially present or unsupported subsystem must never be reset.
static func upgrade_profile(profile: Dictionary) -> Dictionary:
	if not valid(profile): return {}
	if profile.has("skill_system_version"): return profile.duplicate(true)
	var result := profile.duplicate(true)
	result.merge(fresh_fields(), true)
	for hero_id: String in HERO_IDS:
		var hero_level := ContentRegistry.level_for_xp(int(profile.get("hero_xp", {}).get(hero_id, 0)), int(profile.get("ruleset_version", 1)))
		var state: Dictionary = result.skill_state[hero_id]
		for index in range(1, 5):
			if hero_level >= 8 + index * 2: state.mastery["%s_SK%02d" % [hero_id, index]] = THRESHOLDS[1]
		for pair: Array in [["q", 1, 4], ["ultimate", 4, 5]]:
			var choice := str(profile.get("branches", {}).get(hero_id, {}).get(pair[0], ""))
			if choice in ["A", "B"]:
				var id := "%s_SK%02d" % [hero_id, int(pair[1])]
				state.mastery[id] = THRESHOLDS[int(pair[2]) - 1]
				state.branches[id] = choice
	return result

static func _integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= maximum and float(value) == floorf(float(value))
