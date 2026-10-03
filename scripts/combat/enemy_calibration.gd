class_name EnemyCalibration
extends RefCounted
## Archived static chapter/rank calibration. Never keyed by player or loadout.
## Empty/missing snapshots identify every pre-calibration V2 adventure forever.
const Rules = preload("res://config/numerical_rules.gd")
const CHAPTERS := ["B01","B02","B03","B04"]
const RANKS := ["normal","elite","boss"]
const FACTORS := ["hp","attack","skill"]
const ARCHIVES := {
	1: {"B01":{},"B02":{},"B03":{},"B04":{}},
	# Opt-in B05 durability candidate; baseline archive1 is immutable.
	2: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":4.4}}},
	3: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":9.0,"attack":0.35}}},
	4: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":9.0}}},
	5: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":8.5}}},
	6: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":8.3}}},
	7: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":8.7}}},
	8: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":8.9}}},
	9: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"boss":{"hp":8.2}}},
	10: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"normal":{"attack":1.35},"elite":{"attack":1.35}}},
	# Bounded local-pressure experiment; never selected without explicit isolated flag.
	11: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"normal":{"attack":2.5},"elite":{"attack":2.5}}},
	12: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{"normal":{"attack":3.5},"elite":{"attack":3.5}}},
	13: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{},"B06":{}},
	14: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{},"B06":{}},
	15: {"B01":{},"B02":{},"B03":{},"B04":{},"B05":{},"B06":{}}
}

static func archived(version: int) -> Dictionary:
	if version == 0: return {}
	if not ARCHIVES.has(version): return {}
	var chapters := {}
	for chapter: String in ARCHIVES[version]:
		var ranks := {}
		for rank: String in RANKS:
			var override: Dictionary = ARCHIVES[version][chapter].get(rank,{})
			ranks[rank] = {"hp":float(override.get("hp",1.0)),"attack":float(override.get("attack",1.0)),"skill":float(override.get("skill",1.0))}
		chapters[chapter] = ranks
	return {"version":version,"chapters":chapters}

static func current() -> Dictionary:
	# Explicit debug/test-only species candidate; does not change chapter gates.
	if _species_candidate_enabled(OS.get_cmdline_user_args()): return archived(15)
	if Rules.b05_candidate_enabled():
		for version in [15,14,13]:
			if "--b05-balance-candidate=%d" % version in OS.get_cmdline_user_args(): return archived(version)
	var snapshot: Variant = Rules.value("enemy_calibration",{})
	return snapshot if snapshot is Dictionary else {"invalid_configuration":true}

static func _species_candidate_enabled(args: PackedStringArray) -> bool:
	if not OS.has_feature("debug") or "--enemy-species-candidate=15" not in args: return false
	var paths: Array[String] = []
	for argument: String in args:
		if argument.begins_with("--test-profile="): paths.append(argument.trim_prefix("--test-profile="))
	if paths.size()!=1: return false
	var path := paths[0]
	if not path.begins_with("user://test_") or not path.ends_with(".json") or "\\" in path or ":" in path.trim_prefix("user://"): return false
	for component: String in path.trim_prefix("user://").split("/"):
		if component in ["", ".", ".."]: return false
	return true

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != 2 or not value.has_all(["version","chapters"]): return false
	var version: Variant = value.version
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) < 1 or float(version) > 1000 or version != int(version) or not ARCHIVES.has(int(version)): return false
	var expected := archived(int(version))
	if not value.chapters is Dictionary or value.chapters.size() != expected.chapters.size(): return false
	for chapter: String in expected.chapters:
		var ranks: Variant = value.chapters.get(chapter)
		if not ranks is Dictionary or ranks.size() != 3: return false
		for rank: String in RANKS:
			var factors: Variant = ranks.get(rank)
			if not factors is Dictionary or factors.size() != 3: return false
			for factor: String in FACTORS:
				var amount: Variant = factors.get(factor)
				if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) < .05 or float(amount) > 10.0: return false
				if float(amount) != float(expected.chapters[chapter][rank][factor]): return false
	return true

static func factor(snapshot: Dictionary, chapter: int, rank: String, key: String) -> float:
	if snapshot.is_empty(): return 1.0
	if not valid(snapshot) or chapter not in range(1,13) or rank not in RANKS or key not in FACTORS: return 0.0
	# Old immutable snapshots predate later chapters and retain baseline1.
	if not snapshot.chapters.has("B%02d" % chapter): return 1.0
	return float(snapshot.chapters["B%02d" % chapter][rank][key])

## Archives0–14 are immutable replay; archive15 is an explicitly isolated candidate.
static func numerical_version(snapshot: Variant = null) -> int:
	var value: Variant = current() if snapshot == null else snapshot
	if not valid(value): return 0
	return 4 if int(value.get("version",0)) == 15 else 3 if int(value.get("version",0)) == 14 else 2 if int(value.get("version",0)) == 13 else 1
