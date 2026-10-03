extends RefCounted
## Versioned, player-independent Boss numerical curve. V1 is an immutable
## replay baseline; V2 repairs both early and late chapter regressions.
## This module owns only HP, attack and defenses. Geometry, cast cadence,
## phase gates, coefficients, finite summons and counterplay are untouched.
const VERSION := 2
const FIELDS := ["max_hp", "damage", "armor", "magic_resist"]
const HP_D := [100, 140, 200, 280, 400]
const ATTACK_D := [100, 120, 150, 185, 230]
# Frozen authored V1 units, before x13.5 and chapter/difficulty factors.
const V1_HP := [1450, 1620, 1480, 1880, 1000, 1100]
const V1_ATTACK := [20, 18, 19, 21, 24, 26]
const V1_ARMOR := [18, 12, 10, 22, 8, 9]
const V1_MR := [18, 15, 12, 18, 8, 9]
const CHAPTER_HP_FLOOR_PERCENT := 115
const CHAPTER_ATTACK_FLOOR_PERCENT := 108
const CHAPTER_DEFENSE_STEP := 20
const DIFFICULTY_DEFENSE_STEP := 30

static func stats(chapter: int, difficulty: int, version: int = VERSION) -> Dictionary:
	if chapter < 1 or chapter > 6 or difficulty < 0 or difficulty > 4 or version not in [1, VERSION]: return {}
	var original := _v1(chapter, difficulty)
	if version == 1: return original
	var baseline := _v1(1, 0)
	for next_chapter: int in range(2, chapter + 1):
		var authored := _v1(next_chapter, 0)
		baseline = {
			"max_hp":maxi(authored.max_hp, _ratio(baseline.max_hp * CHAPTER_HP_FLOOR_PERCENT, 100)),
			"damage":maxi(authored.damage, _ratio(baseline.damage * CHAPTER_ATTACK_FLOOR_PERCENT, 100)),
			"armor":maxi(authored.armor, baseline.armor + CHAPTER_DEFENSE_STEP),
			"magic_resist":maxi(authored.magic_resist, baseline.magic_resist + CHAPTER_DEFENSE_STEP),
		}
	# D0 rounding is an explicit new policy boundary. Taking the immutable
	# original as a floor also preserves its occasional +1 at other tiers.
	return {
		"max_hp":maxi(original.max_hp, _ratio(baseline.max_hp * HP_D[difficulty], 100)),
		"damage":maxi(original.damage, _ratio(baseline.damage * ATTACK_D[difficulty], 100)),
		"armor":maxi(original.armor, baseline.armor + DIFFICULTY_DEFENSE_STEP * difficulty),
		"magic_resist":maxi(original.magic_resist, baseline.magic_resist + DIFFICULTY_DEFENSE_STEP * difficulty),
	}

static func apply(source: Dictionary, version: int = VERSION) -> Dictionary:
	if version == 1: return source.duplicate(true)
	if version != VERSION or int(source.get("ruleset_version", 0)) != 2 or int(source.get("scale_version", 0)) != 10: return {}
	var id := str(source.get("enemy_id", source.get("boss_id", "")))
	var chapter := int(id.trim_prefix("BO"))
	if id != "BO%02d" % chapter or str(source.get("rank", "")) != "boss": return {}
	var raw_difficulty: Variant = source.get("difficulty", -1)
	if not (raw_difficulty is int or raw_difficulty is float) or not is_finite(float(raw_difficulty)) or raw_difficulty != int(raw_difficulty): return {}
	var values := stats(chapter, int(raw_difficulty), version)
	if values.is_empty() or int(source.get("chapter", chapter)) != chapter: return {}
	var result := source.duplicate(true)
	result.merge(values, true)
	result["boss_progression_version"] = VERSION
	return result

static func _v1(chapter: int, difficulty: int) -> Dictionary:
	var index := chapter - 1
	return {
		"max_hp":_ratio(V1_HP[index] * 135 * 10 * (100 + 12 * index) * HP_D[difficulty], 1000000),
		"damage":_ratio(V1_ATTACK[index] * 135 * 10 * (100 + 8 * index) * ATTACK_D[difficulty], 1000000),
		"armor":(V1_ARMOR[index] + (3 if chapter <= 4 else 2) * difficulty) * 10,
		"magic_resist":(V1_MR[index] + (3 if chapter <= 4 else 2) * difficulty) * 10,
	}

static func _ratio(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	return numerator / denominator + (1 if 2 * (numerator % denominator) >= denominator else 0)
