class_name RunState
extends RefCounted
## Transient expedition data. The persisted receipt settles an interrupted run;
## it is deliberately not a room checkpoint or a promise of resume support.

var id: String = ""
var gold: int = 0
var hp: float = Balance.PLAYER_HP
var max_hp: float = Balance.PLAYER_HP
var hero_id: String = "CH01"
var level: int = 1
var stats: Dictionary = {}
var resource: float = 0.0
var shield: float = 0.0
var hero_xp_gained: int = 0
var completed_reward_ids: Array[String] = []
var boss_defeats: Array[String] = []
var loadout_snapshot: Dictionary = {}
var equipment_snapshot: Dictionary = {}
var branches_snapshot: Dictionary = {}
var relics: Array[String] = []
var shots: int = 0
var kills: int = 0
var elapsed: float = 0.0
var expedition: Dictionary = {}
var committed_receipt: Dictionary = {}
var staged_xp: Dictionary = {}
var staged_tutorial: bool = false

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
	if not expedition.is_empty():
		value["expedition"] = expedition.duplicate(true)
		value["loadout_snapshot"] = loadout_snapshot.duplicate(true)
		value["equipment_snapshot"] = equipment_snapshot.duplicate(true)
		value["branches_snapshot"] = branches_snapshot.duplicate(true)
	return value
