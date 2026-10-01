class_name EnemyCalibration
extends RefCounted
## Archived static chapter/rank calibration. Never keyed by player or loadout.
## Empty/missing snapshots identify every pre-calibration V2 adventure forever.
const Rules = preload("res://config/numerical_rules.gd")
const CHAPTERS := ["B01","B02","B03","B04"]
const RANKS := ["normal","elite","boss"]
const FACTORS := ["hp","attack","skill"]
const ARCHIVES := {
	1: {"B01":{},"B02":{},"B03":{},"B04":{}}
}

static func archived(version: int) -> Dictionary:
	if version == 0: return {}
	if not ARCHIVES.has(version): return {}
	var chapters := {}
	for chapter: String in CHAPTERS:
		var ranks := {}
		for rank: String in RANKS:
			var override: Dictionary = ARCHIVES[version][chapter].get(rank,{})
			ranks[rank] = {"hp":float(override.get("hp",1.0)),"attack":float(override.get("attack",1.0)),"skill":float(override.get("skill",1.0))}
		chapters[chapter] = ranks
	return {"version":version,"chapters":chapters}

static func current() -> Dictionary:
	var snapshot: Variant = Rules.value("enemy_calibration",{})
	return snapshot if snapshot is Dictionary else {"invalid_configuration":true}

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != 2 or not value.has_all(["version","chapters"]): return false
	var version: Variant = value.version
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) < 1 or float(version) > 1000 or version != int(version) or not ARCHIVES.has(int(version)): return false
	if not value.chapters is Dictionary or value.chapters.size() != 4: return false
	var expected := archived(int(version))
	for chapter: String in CHAPTERS:
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
	if not valid(snapshot) or chapter not in range(1,5) or rank not in RANKS or key not in FACTORS: return 0.0
	return float(snapshot.chapters["B%02d" % chapter][rank][key])
