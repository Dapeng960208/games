extends RefCounted
## Frozen B05 numerical contract, not a chapter-release switch. No player reads.
## Resolve from authored IDs each time; never rescale an already resolved actor.
const Content = preload("res://scripts/levels/b05/world/content.gd")
const VERSION := 4
const Species = preload("res://scripts/domain/combat/enemy_species_policy.gd")
const Growth = preload("res://scripts/domain/combat/shared_enemy_growth.gd")
const Calibration = preload("res://scripts/domain/combat/enemy_calibration.gd")
const BossPolicy = preload("res://scripts/domain/combat/boss_progression_policy.gd")
const Policy = preload("res://scripts/domain/combat/monster_role_policy.gd")
const LEVELS := [21, 23, 25]
const HP_D := [100, 140, 200, 280, 400]
const ATTACK_D := [100, 120, 150, 185, 230]
const SKILL_D := [100, 105, 110, 115, 120]
const BOSS_SKILL_D := [100, 106, 112, 120, 130]
# Existing role modifiers frozen from enemy_profiles at PR5's implementation
# baseline: hp%, attack%, minimum attack, speed%, armor%, armor bonus,
# armor/tier, resist/tier, recovery%. F/R share skirmisher numerical identity.
const ROLES := {
	"F":[100,100,0,100,100,0,2,1,100],
	"R":[100,100,0,100,100,0,2,1,100],
	"C":[86,116,0,98,50,0,1,2,112],
	"S":[96,90,0,95,100,0,1,1.5,112],
	"A":[72,120,15,110,25,0,0.5,0.5,100],
	"T":[102,90,0,92,100,8,2,1,118],
}

static func ordinary(enemy_id: String, level: int, difficulty: int, rank: String = "normal", calibration: Variant = null, version: int = 0) -> Dictionary:
	var frozen: Variant = Calibration.current() if calibration == null else calibration
	if not Calibration.valid(frozen): return {}
	if version == 0: version = Calibration.numerical_version(frozen)
	if version not in [1,2,3,4] or level not in LEVELS or difficulty < 0 or difficulty > 4 or rank not in ["normal", "elite"]: return {}
	var attack_factor := Calibration.factor(frozen,5,rank,"attack")
	if attack_factor <= 0: return {}
	var authored: Dictionary = Content.enemy(enemy_id)
	if authored.is_empty() or not ROLES.has(authored.profile): return {}
	var raw: Dictionary = authored.raw_stats
	var role: Array = ROLES[authored.profile]
	var elite: bool = rank == "elite"
	# Each product is rational and rounded once after all factors, not at the
	# level/role/elite/scale/difficulty boundaries. Calibration is frozen at 1.
	var hp := _product([int(raw.max_hp), role[0], 1000 + 55 * (level - 1), 135, 10, 148, HP_D[difficulty], 120 if elite else 100], [100,1000,100,100,100,100])
	var base_attack_hundredths := mini(1690, maxi(int(role[2]) * 100, int(raw.damage) * int(role[1])))
	var attack := _product([base_attack_hundredths, 1000 + 25 * (level - 1), 135, 10, 132, ATTACK_D[difficulty], 112 if elite else 100,int(round(attack_factor*1000))], [100,1000,100,100,100,100,1000])
	var armor: float = minf(24.0, float(raw.armor) * float(role[4]) / 100.0 + float(role[5]) + 3.0 * float(role[6]))
	var resist: float = minf(32.0, float(raw.magic_resist) + 3.0 * float(role[7]) + (4.0 if elite else 0.0))
	var speed: float = minf(132.0, float(raw.move_speed) * float(role[3]) / 100.0 * (1.0 + 0.006 * (level - 1))) * (1.0 + 0.04 * difficulty)
	var recovery: float = float(raw.recovery_seconds) * maxf(1.0, float(role[8]) / 100.0 - (level - 1) * 0.005)
	var result := {"enemy_id":enemy_id, "biome_id":"B05", "chapter":5, "clan":"plant", "actor_kind":"enemy",
		"enemy_level":level, "rank":rank, "difficulty":difficulty, "ruleset_version":2, "scale_version":10,
		"b05_numerical_version":version, "mechanic_tier":4, "max_hp":maxi(1,hp), "damage":attack,
		"armor":int(floor((armor + 2 * difficulty) * 10 + 0.5)), "magic_resist":int(floor((resist + 2 * difficulty) * 10 + 0.5)),
		"move_speed":speed, "attack_range":raw.attack_range, "recovery_seconds":maxf(0.45,recovery / (1.0 + 0.035 * difficulty))}
	if not frozen.is_empty():
		result["enemy_calibration_snapshot"] = frozen.duplicate(true)
		result["attack_calibration"] = attack_factor
	if version == 4:
		var values := Species.stats(enemy_id,raw,{"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[authored.profile],level,5,difficulty,rank)
		if values.is_empty(): return {}
		result.merge(values,true)
		return result
	if version == 3:
		var values := Growth.stats(raw,{"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[authored.profile],authored.profile,level,5,difficulty,rank)
		if values.is_empty(): return {}
		result.merge(values,true)
		return result
	return Policy.apply(result,{"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[authored.profile],authored.profile) if version == 2 else result

static func boss(difficulty: int, calibration: Variant = null, version: int = 0) -> Dictionary:
	var frozen: Variant = Calibration.current() if calibration == null else calibration
	if not Calibration.valid(frozen): return {}
	if version == 0: version = Calibration.numerical_version(frozen)
	if version not in [1,2,3,4] or difficulty < 0 or difficulty > 4: return {}
	var hp_factor := Calibration.factor(frozen,5,"boss","hp")
	var attack_factor := Calibration.factor(frozen,5,"boss","attack")
	if hp_factor <= 0 or attack_factor <= 0: return {}
	var result := {"enemy_id":"BO05", "boss_id":"BO05", "biome_id":"B05", "chapter":5, "actor_kind":"boss",
		"enemy_level":25, "rank":"boss", "difficulty":difficulty, "ruleset_version":2, "scale_version":10,
		"b05_numerical_version":version, "mechanic_tier":4,
		"max_hp":_product([1000,135,10,148,HP_D[difficulty],int(round(hp_factor*1000))], [100,100,100,1000]),
		"damage":_product([24,135,10,132,ATTACK_D[difficulty],int(round(attack_factor*1000))], [100,100,100,1000]),
		"armor":(8 + 2 * difficulty) * 10, "magic_resist":(8 + 2 * difficulty) * 10,
		"move_speed":52.0 * (1.0 + 0.045 * difficulty)}
	if not frozen.is_empty():
		result.merge({"enemy_calibration_snapshot":frozen.duplicate(true),"authored_base_hp":1000,"hp_calibration":hp_factor,"attack_calibration":attack_factor})
	var final := BossPolicy.apply(result,2 if version >= 3 else version)
	return Species.stamp_boss(final) if version == 4 else final

## Coefficients are authored hundredths (e.g. 110 for 1.1a). Support callers
## must not call this damage API for healing, shielding or harmless movement.
static func skill_damage(profile: Dictionary, coefficient_percent: int, phase: int = 1, command_data: Dictionary = {}) -> int:
	if coefficient_percent < 0 or coefficient_percent > 1000 or phase < 1 or phase > 3: return -1
	if not _valid_profile(profile): return -1
	if preload("res://scripts/domain/combat/crit_policy.gd").enabled(profile):
		var power: float = preload("res://scripts/domain/combat/enemy_power_policy.gd").amount(command_data, profile, float(coefficient_percent)/100.0)
		var factor: float = float(BOSS_SKILL_D[int(profile.difficulty)])/100.0 * float([100,110,120][phase-1])/100.0 if profile.rank == "boss" else 1.25 * float(SKILL_D[int(profile.difficulty)])/100.0
		return int(floor(power * factor + 0.5))
	var difficulty: int = int(profile.difficulty)
	if profile.rank == "boss":
		return _product([profile.damage, coefficient_percent, BOSS_SKILL_D[difficulty], [100,110,120][phase - 1]], [100,100,100])
	return _product([profile.damage, coefficient_percent, 125, SKILL_D[difficulty]], [100,100,100])

static func _valid_profile(profile: Dictionary) -> bool:
	if not profile.has_all(["enemy_id","enemy_level","rank","difficulty"]): return false
	for key in ["enemy_level","difficulty"]:
		var value: Variant = profile[key]
		if not (value is int or value is float) or not is_finite(float(value)) or value != int(value): return false
	if not profile.rank is String or not profile.enemy_id is String: return false
	var expected := boss(int(profile.difficulty),profile.get("enemy_calibration_snapshot",{}),int(profile.get("b05_numerical_version",1))) if profile.enemy_id == "BO05" else ordinary(profile.enemy_id,int(profile.enemy_level),int(profile.difficulty),profile.rank,profile.get("enemy_calibration_snapshot",{}),int(profile.get("b05_numerical_version",1)))
	if expected.is_empty(): return false
	for key: String in expected:
		var actual: Variant = profile.get(key)
		var canonical: Variant = expected[key]
		if canonical is int or canonical is float:
			if not (actual is int or actual is float) or not is_finite(float(actual)): return false
		elif typeof(actual) != typeof(canonical): return false
		if actual == canonical: continue
		# Godot's default JSON representation can change only the last binary
		# bit of noncombat motion/timing floats. Match the exact canonical
		# representation; never use an epsilon for combat values or profiles.
		if key in ["move_speed", "recovery_seconds"]:
			var value: Variant = profile.get(key)
			if (value is int or value is float) and is_finite(float(value)) and JSON.stringify(value) == JSON.stringify(expected[key]): continue
		return false
	return true

static func _product(numerators: Array, denominators: Array) -> int:
	# Cancel across factors BEFORE multiplying: archived coefficients add factors
	# large enough to overflow int64 even when the final rational result is small.
	var bottoms:Array=denominators.duplicate()
	var tops:Array=[]
	for value in numerators:
		var top:int=int(value)
		for index in bottoms.size():
			var divisor:=_gcd(top,int(bottoms[index]))
			@warning_ignore("integer_division")
			top=top/divisor
			@warning_ignore("integer_division")
			bottoms[index]=int(bottoms[index])/divisor
		tops.append(top)
	var numerator:=1
	var denominator:=1
	for top:int in tops:numerator*=top
	for bottom:int in bottoms:denominator*=bottom
	@warning_ignore("integer_division")
	return numerator/denominator+(1 if 2*(numerator%denominator)>=denominator else 0)

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(1, a)
