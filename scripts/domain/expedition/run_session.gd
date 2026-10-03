class_name RunSession
extends RefCounted
## Transient expedition data. The persisted receipt settles an interrupted run;
## it is deliberately not a room checkpoint or a promise of resume support.

const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")

var id: String = ""
# Demo state deliberately never enters a persisted receipt.
var demo: bool = false
# Local session measurements; never serialized.
var backpack_opens: int = 0
var loadout_changes: int = 0
var gold: int = 0
# Keep legacy floats while explicit V2 snapshots expose integer combat state.
var hp: Variant = Balance.PLAYER_HP:
	get:
		return Rules.integer(float(hp)) if ruleset_version() == Rules.V2 else float(hp)
	set(value):
		hp = Rules.integer(float(value)) if ruleset_version() == Rules.V2 else float(value)
var max_hp: Variant = Balance.PLAYER_HP:
	get:
		return Rules.integer(float(max_hp)) if ruleset_version() == Rules.V2 else float(max_hp)
	set(value):
		max_hp = Rules.integer(float(value)) if ruleset_version() == Rules.V2 else float(value)
var hero_id: String = "CH01"
var level: int = 1
var stats: Dictionary = {}:
	set(value):
		stats = preload("res://scripts/domain/combat/crit_policy.gd").apply_player(value, enemy_calibration_snapshot)
# Set before resolving restored stats; never infer an old adventure from global defaults.
var frozen_versions: Dictionary = {}
var enemy_calibration_snapshot: Dictionary = {}
var resource: Variant = 0.0:
	get:
		return Rules.integer(float(resource)) if ruleset_version() == Rules.V2 else float(resource)
	set(value):
		resource = Rules.integer(float(value)) if ruleset_version() == Rules.V2 else float(value)
var shield: Variant = 0.0:
	get:
		return Rules.integer(float(shield)) if ruleset_version() == Rules.V2 else float(shield)
	set(value):
		shield = Rules.integer(float(value)) if ruleset_version() == Rules.V2 else float(value)
# Fractional time accumulation survives checkpoints without becoming spendable resource.
# Keep these on the run so replacing a room/player cannot reset frame progress.
var resource_regen_remainder: float = 0.0
var resource_decay_remainder: float = 0.0
var hero_xp_gained: int = 0
var completed_reward_ids: Array[String] = []
var boss_defeats: Array[String] = []
var loadout_snapshot: Dictionary = {}
var equipment_snapshot: Dictionary = {}
var branches_snapshot: Dictionary = {}
var skill_loadout_snapshot: Array[String] = []
var skill_branches_snapshot: Dictionary = {}
var relics: Array[String] = []
var shots: int = 0
var kills: int = 0
var elapsed: float = 0.0
var expedition: Dictionary = {}
var committed_receipt: Dictionary = {}
var staged_xp: Dictionary = {}
var staged_loot_requests: Dictionary = {}
var pending_research_materials: Dictionary = {}
var staged_tutorial: bool = false

func ruleset_version() -> int:
	return int(frozen_versions.get("ruleset_version", stats.get("ruleset_version", Rules.LEGACY)))

func receipt() -> Dictionary:
	# Settings and incidental saves must never persist a partial combat room.
	if not expedition.is_empty() and not committed_receipt.is_empty():
		return committed_receipt.duplicate(true)
	return live_receipt()

func live_receipt() -> Dictionary:
	var value: Dictionary = {
		"id": id, "gold": gold, "discoveries": relics.duplicate(),
		"shots": shots, "kills": kills, "elapsed": elapsed,
		"hero_id": hero_id, "level": level, "hero_xp_gained": hero_xp_gained,
		"completed_reward_ids": completed_reward_ids.duplicate(),
		"boss_defeats": boss_defeats.duplicate(), "rules_version": 1,
	}
	if not skill_loadout_snapshot.is_empty():
		value["skill_loadout_snapshot"] = skill_loadout_snapshot.duplicate()
		value["skill_branches_snapshot"] = skill_branches_snapshot.duplicate(true)
		value["role_combat_version"] = 2
	if not frozen_versions.is_empty(): value.merge(frozen_versions, true)
	if ruleset_version() == Rules.V2 and not enemy_calibration_snapshot.is_empty(): value["enemy_calibration_snapshot"] = enemy_calibration_snapshot.duplicate(true)
	if ruleset_version() == Rules.V2 and expedition.is_empty(): value["pending_research_materials"] = pending_research_materials.duplicate(true)
	if not expedition.is_empty():
		value["expedition"] = expedition.duplicate(true)
		value["loadout_snapshot"] = loadout_snapshot.duplicate(true)
		value["equipment_snapshot"] = equipment_snapshot.duplicate(true)
		value["branches_snapshot"] = branches_snapshot.duplicate(true)
	return value
