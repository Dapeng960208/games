class_name EnemyNumericalV2
extends RefCounted
## Pure S08/S09 numerical seam. No Game/player reads, RNG, scene mutation or
## runtime enablement. Call from an explicit v2 route with a resolved legacy D0
## profile. Existing profile/brain generators remain the source of identity,
## geometry, sequence/counts, elite identity and counterplay timing.
const Catalog = preload("res://scripts/world/world_catalog.gd")
const AbilityCatalog = preload("res://scripts/combat/enemy_ability_catalog.gd")
const Calibration = preload("res://scripts/combat/enemy_calibration.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const BossPolicy = preload("res://scripts/combat/boss_progression_policy.gd")
const Species = preload("res://scripts/combat/enemy_species_policy.gd")
const Growth = preload("res://scripts/combat/shared_enemy_growth.gd")
const RolePolicy = preload("res://scripts/combat/monster_role_policy.gd")
const PROFILE_VERSION := 2
const DAMAGE_KINDS := ["melee", "charge", "projectile", "ground_area", "pull", "counter"]
const PROFILE_FLATS := ["max_hp", "damage", "armor", "magic_resist"]
const BASE_KEYS := ["max_hp", "damage", "armor", "magic_resist", "move_speed", "recovery_seconds"]
const STATUS_RATIOS := {"burn":0.12, "corrosion":0.08, "bleed":0.10, "shock":0.25}

## zone indices are zero-based. Future levels are a formula interface only;
## no future actor ID is accepted by ordinary_profile/boss_profile.
static func chapter_levels(chapter: int, allow_future: bool = false) -> Dictionary:
	var maximum: int = int(Numbers.value("planned_chapters")) if allow_future else int(Numbers.value("implemented_chapters"))
	if chapter < 1 or chapter > maximum: return {}
	var step: int = int(Numbers.value("chapter_level_step"))
	return {"chapter":chapter, "zone_levels":[step * (chapter - 1) + 1, step * (chapter - 1) + 3, step * chapter],
		"boss_level":step * chapter, "released":chapter <= int(Numbers.value("implemented_chapters")),
		"hp_factor":1.0 + float(Numbers.value("chapter_hp_per_step")) * (chapter - 1),
		"damage_factor":1.0 + float(Numbers.value("chapter_damage_per_step")) * (chapter - 1)}

static func encounter_level(chapter: int, zone_index: int, allow_future: bool = false) -> int:
	var levels := chapter_levels(chapter, allow_future)
	return int(levels.zone_levels[zone_index]) if not levels.is_empty() and zone_index >= 0 and zone_index < 3 else 0

static func mechanic_tier(level: int) -> int:
	return 4 if level >= 15 else 3 if level >= 10 else 2 if level >= 5 else 1

static func chapter_for_id(id: String) -> int:
	if id.begins_with("BO"):
		var index := int(id.substr(2))
		return index if index in range(1, 5) and id == "BO%02d" % index else 0
	if id.begins_with("M"):
		# Stable IDs are append-only: later roster additions must use their
		# authored region, never infer a chapter from an obsolete block of nine.
		var definition: Dictionary = Catalog.enemy(id)
		var biome_id := str(definition.get("biome_id", ""))
		var chapter := int(biome_id.trim_prefix("B"))
		return chapter if not definition.is_empty() and biome_id == "B%02d" % chapter and chapter in range(1, 5) else 0
	return 0

## Already resolved elite sources contain HP×1.2, A×1.12 and MR+4. They are
## deliberately not applied here again. Old difficulty_base_stats is accepted
## because it explicitly preserves the same-level, pre-difficulty baseline.
static func ordinary_profile(source: Dictionary, difficulty: int, ruleset: int = Numbers.V2) -> Dictionary:
	return _profile(source, difficulty, false, ruleset)

static func boss_profile(source: Dictionary, difficulty: int, ruleset: int = Numbers.V2) -> Dictionary:
	return _profile(source, difficulty, true, ruleset)

static func _profile(source: Dictionary, difficulty: int, boss: bool, ruleset: int) -> Dictionary:
	if ruleset == Numbers.LEGACY: return source.duplicate(true)
	if ruleset != Numbers.V2 or source.is_empty() or difficulty < 0 or difficulty > 4: return {}
	var id := str(source.get("enemy_id", source.get("boss_id", "")))
	var chapter := chapter_for_id(id)
	if chapter == 0 or id.begins_with("BO") != boss: return {}
	if not boss and str(source.get("rank", "normal")) not in ["normal", "elite"]: return {}
	var base: Dictionary = {}
	if int(source.get("numerical_profile_version", 0)) == PROFILE_VERSION:
		if int(source.get("ruleset_version", 0)) != Numbers.V2 or int(source.get("scale_version", 0)) != 10: return {}
		if not source.get("numerical_legacy_base") is Dictionary: return {}
		base = source.numerical_legacy_base.duplicate(true)
	else:
		# A scaled v2 profile without a base cannot be reconstructed by dividing
		# its rounded integers. Reject rather than silently double-scale it.
		if int(source.get("ruleset_version", Numbers.LEGACY)) != Numbers.LEGACY or int(source.get("scale_version", 1)) != 1: return {}
		var old_base: Variant = source.get("difficulty_base_stats", {})
		if not old_base is Dictionary: return {}
		if int(source.get("difficulty", 0)) != 0 and old_base.is_empty(): return {}
		for key: String in BASE_KEYS:
			base[key] = old_base.get(key, source.get(key, 0.0))
		base["enemy_level"] = source.get("enemy_level", 5 * chapter if boss else 1)
		base["mechanic_tier"] = source.get("mechanic_tier", mechanic_tier(int(base.enemy_level)))
		base["chapter"] = chapter
	for key: String in BASE_KEYS:
		if not _nonnegative(base.get(key)): return {}
	if int(base.get("chapter", 0)) != chapter or int(base.get("enemy_level", 0)) not in range(1, 21): return {}
	var snapshot: Variant = source.get("enemy_calibration_snapshot",Calibration.current())
	if not Calibration.valid(snapshot): return {}
	var result := source.duplicate(true)
	result["enemy_calibration_snapshot"] = snapshot.duplicate(true)
	var calibration_rank := "boss" if boss else str(source.get("rank","normal"))
	var levels := chapter_levels(chapter)
	var calibration: Dictionary = Numbers.value("enemy_baseline_multiplier")
	result["numerical_legacy_base"] = base.duplicate(true)
	result["numerical_profile_version"] = PROFILE_VERSION
	result["ruleset_version"] = Numbers.V2
	result["scale_version"] = 10
	result["chapter"] = chapter
	result["difficulty"] = difficulty
	result["enemy_level"] = int(levels.boss_level) if boss else int(base.enemy_level)
	if not boss: result["mechanic_tier"] = mechanic_tier(int(base.enemy_level))
	result["max_hp"] = _round_product([base.max_hp, calibration.max_hp, Numbers.value("combat_scale"), levels.hp_factor, Numbers.value("difficulty_hp_multipliers")[difficulty], Calibration.factor(snapshot,chapter,calibration_rank,"hp")])
	result["damage"] = _round_product([base.damage, calibration.damage, Numbers.value("combat_scale"), levels.damage_factor, Numbers.value("difficulty_damage_multipliers")[difficulty], Calibration.factor(snapshot,chapter,calibration_rank,"attack")])
	for key: String in ["armor", "magic_resist"]:
		var defense: float = float(base[key])
		if not boss: defense = minf(24.0 if key == "armor" else 32.0, defense)
		result[key] = _round_product([defense + (3 if boss else 2) * difficulty, Numbers.value("combat_scale")])
	# Preserve existing difficulty mobility and recovery, including cap order.
	result["move_speed"] = (float(base.move_speed) if boss else minf(132.0, float(base.move_speed))) * (1.0 + (0.045 if boss else 0.04) * difficulty)
	if not boss:
		var parameters: Dictionary = result.get("attack_parameters", {}).duplicate(true)
		var exposure := maxf(0.45, float(parameters.get("exposure_seconds", 0.45)))
		var recovery := maxf(exposure, float(base.recovery_seconds) / (1.0 + 0.035 * difficulty))
		result["recovery_seconds"] = recovery
		result["attack_cooldown_seconds"] = recovery
		parameters["recovery_seconds"] = recovery
		parameters["recovery"] = recovery
		result["attack_parameters"] = parameters
	# Regenerated exclusively from preserved v1 base: never compound a policy.
	result.erase("monster_role_policy_version")
	result.erase("monster_role_specialization")
	result.erase("enemy_growth_version")
	for key: String in ["species_crit_chance_bonus","species_crit_multiplier_bonus","enemy_species_version","crit_policy_version","ability_power","skill_base_power","crit_chance","crit_multiplier","primary_role","secondary_role"]: result.erase(key)
	if not boss and Calibration.numerical_version(snapshot) == 2:
		result = RolePolicy.apply(result,str(source.get("archetype","")),str(source.get("role","")))
		if result.is_empty(): return {}
	if not boss and Calibration.numerical_version(snapshot) == 3:
		var values := Growth.stats(Growth.raw_legacy(id,Catalog.enemy(id)),str(source.get("archetype","")),str(source.get("role","")),int(base.enemy_level),chapter,difficulty,calibration_rank)
		if values.is_empty(): return {}
		result.merge(values,true)
	if not boss and Calibration.numerical_version(snapshot) == 4:
		var values := Species.stats(id,Growth.raw_legacy(id,Catalog.enemy(id)),str(source.get("archetype","")),int(base.enemy_level),chapter,difficulty,calibration_rank)
		if values.is_empty(): return {}
		result.merge(values,true)
	if boss:
		var final := BossPolicy.apply(result,mini(2,Calibration.numerical_version(snapshot)))
		return Species.stamp_boss(final) if Calibration.numerical_version(snapshot) == 4 else final
	return AbilityCatalog.apply(result, difficulty)

## Phase only strengthens a packet; it never changes actor A. Coefficients and
## extra_damage_multiplier are distinct (e.g. a frozen racial rage bonus).
static func skill_factor(profile: Dictionary, phase: int = 1) -> float:
	var factors := _skill_factors(profile, phase)
	if factors.is_empty(): return 0.0
	return float(factors[0]) * float(factors[1]) * float(factors[2])

static func _skill_factors(profile: Dictionary, phase: int) -> Array:
	if not Numbers.is_v2(profile) or phase < 1 or phase > 3: return []
	var difficulty := int(profile.get("difficulty", -1))
	if difficulty < 0 or difficulty > 4: return []
	if str(profile.get("rank", "")) == "boss" or str(profile.get("enemy_id", "")).begins_with("BO"):
		return [Numbers.value("boss_skill_difficulty_multipliers")[difficulty], Numbers.value("boss_skill_phase_multipliers")[phase - 1], Calibration.factor(profile.get("enemy_calibration_snapshot",{}),chapter_for_id(str(profile.get("enemy_id",""))),"boss","skill")]
	var tier := int(profile.get("mechanic_tier", 0))
	if tier < 1 or tier > 4: return []
	return [Numbers.value("ordinary_skill_tier_multipliers")[tier - 1], Numbers.value("ordinary_skill_difficulty_multipliers")[difficulty], Calibration.factor(profile.get("enemy_calibration_snapshot",{}),chapter_for_id(str(profile.get("enemy_id",""))),str(profile.get("rank","normal")),"skill")]

static func damaging(command: Dictionary) -> bool:
	return str(command.get("kind", "")) in DAMAGE_KINDS and not (str(command.get("kind", "")) == "counter" and not bool(command.get("auto_release", true)))

## Return a fully frozen per-hit/per-projectile/per-tick command. Integration
## must skip its old damage_multiplier/scale step when enemy_command_version=2.
## Existing Brain already folds the war-drum multiplier into damage_multiplier;
## do not also pass that same drum bonus as extra_damage_multiplier.
static func command(source: Dictionary, profile: Dictionary, phase: int = 1, extra_damage_multiplier: float = 1.0) -> Dictionary:
	if not Numbers.is_v2(profile): return source.duplicate(true)
	if int(source.get("enemy_command_version", 0)) == PROFILE_VERSION: return source.duplicate(true)
	var factors := _skill_factors(profile, phase)
	if factors.is_empty() or not _nonnegative(profile.get("damage")) or not _nonnegative(extra_damage_multiplier) or not _nonnegative(source.get("damage_multiplier", 1.0)): return {}
	var result := source.duplicate(true)
	result["ruleset_version"] = Numbers.V2
	result["scale_version"] = 10
	result["enemy_command_version"] = PROFILE_VERSION
	result["enemy_skill_factor"] = skill_factor(profile, phase)
	result["damage"] = _round_product([profile.damage, source.get("damage_multiplier", 1.0), factors[0], factors[1], factors[2], extra_damage_multiplier]) if damaging(source) else 0
	if preload("res://scripts/combat/crit_policy.gd").enabled(profile):
		var power_policy = preload("res://scripts/combat/enemy_power_policy.gd")
		power_policy.stamp(result, profile)
		result["damage"] = Numbers.integer(power_policy.amount(result, profile, float(source.get("damage_multiplier", 1.0))) * float(factors[0]) * float(factors[1]) * float(factors[2]) * extra_damage_multiplier) if damaging(source) else 0
	# Alias inputs represent the same physical endpoint, never two HP pools.
	for key: String in ["anchor_health", "cover_hp", "pod_health"]:
		if source.has(key):
			if not _nonnegative(source[key]): return {}
			var amount := _round_product([source[key], Numbers.value("combat_scale"), factors[0], factors[1], factors[2]])
			result[key] = clampi(amount, 10, 800) if key != "pod_health" else amount
	if result.has("anchor_health") and result.has("cover_hp"): result.cover_hp = result.anchor_health
	if source.has("pod_break_armor_loss"):
		if not _nonnegative(source.pod_break_armor_loss): return {}
		result.pod_break_armor_loss = _round_product([source.pod_break_armor_loss, Numbers.value("combat_scale")])
	if source.get("status") is Dictionary:
		var status: Dictionary = source.status.duplicate(true)
		if STATUS_RATIOS.has(str(status.get("id", ""))):
			if status.has("power") and not _nonnegative(status.power): return {}
			status["power"] = _round_product([status.power, Numbers.value("combat_scale"), factors[0], factors[1], factors[2]]) if status.has("power") else result.damage
		result.status = status
	# Absolute support healing/shields are unit conversion only. Ratio support
	# values remain percentages and are calculated against the actual receiver.
	if source.has("amount") and str(source.get("kind", "")) in ["heal", "guard"] and str(source.get("mode", "")) != "cover":
		if not _nonnegative(source.amount): return {}
		result.amount = _round_product([source.amount, Numbers.value("combat_scale")])
	return result

static func status_tick(status: Dictionary) -> int:
	var id := str(status.get("id", ""))
	return _round_product([status.get("power", 0), STATUS_RATIOS[id]]) if STATUS_RATIOS.has(id) else 0

## Independent support shield pool uses 35%; socket_recharge's CombatStatus
## source uses 50%. Healing uses 15% and missing HP. Counts/charges stay intact.
static func support_amount(command_data: Dictionary, receiver_max_hp: int, receiver_hp: int = -1) -> int:
	if receiver_max_hp <= 0: return 0
	var kind := str(command_data.get("kind", ""))
	var amount := 0
	if kind == "heal":
		amount = int(command_data.amount) if command_data.has("amount") else _round_product([receiver_max_hp, command_data.get("heal_ratio", 0.1)])
		amount = mini(amount, _round_product([receiver_max_hp, 0.15]))
		return mini(amount, maxi(0, receiver_max_hp - receiver_hp)) if receiver_hp >= 0 else amount
	if kind == "guard" and str(command_data.get("mode", "")) != "cover":
		amount = int(command_data.amount) if command_data.has("amount") else _round_product([receiver_max_hp, command_data.get("shield_ratio", 0.0)])
		return mini(amount, _round_product([receiver_max_hp, 0.35]))
	if str(command_data.get("action", "")) == "socket_recharge":
		return _round_product([receiver_max_hp, minf(0.50, float(command_data.get("guard_ratio", command_data.get("shield_ratio", 0.0))))])
	return 0

static func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

## Frozen input/profile decimal literals and approved multiplier factors are
## multiplied as reduced ratios, then half-up rounded once. This avoids binary
## x.499999999999 results changing an authored exact halfway value.
static func _round_product(values: Array) -> int:
	var numerator := 1
	var denominator := 1
	for value: Variant in values:
		if not _nonnegative(value): return 0
		var decimal := str(value)
		var parts := decimal.split(".")
		var divisor := 1
		if parts.size() == 2:
			for index in parts[1].length(): divisor *= 10
		var top := int(parts[0]) * divisor + (int(parts[1]) if parts.size() == 2 else 0)
		var a := _gcd(numerator, divisor)
		var b := _gcd(top, denominator)
		@warning_ignore("integer_division")
		numerator = (numerator / a) * (top / b)
		@warning_ignore("integer_division")
		denominator = (denominator / b) * (divisor / a)
	@warning_ignore("integer_division")
	return numerator / denominator + (1 if 2 * (numerator % denominator) >= denominator else 0)

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remaining := a % b
		a = b
		b = remaining
	return maxi(1, absi(a))
