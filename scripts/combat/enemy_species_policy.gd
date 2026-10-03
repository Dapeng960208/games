extends RefCounted
## Archive15 opt-in species profile. Archive0–14 code and default remain intact.
## User's base1 and exact tank rule; remaining role anchors are a candidate.
## This module does not resolve critical rolls, cast speed or evasive movement.
const VERSION := 4
const Crit = preload("res://scripts/combat/crit_policy.gd")
const Growth = preload("res://scripts/combat/shared_enemy_growth.gd")
const DATA_PATH := "res://data/enemy_species_policy_v4.json"
const FIELDS := ["max_hp","damage","armor","magic_resist"]
static var _species: Dictionary = {}

static func definition(id: String) -> Dictionary:
	if _species.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not parsed is Dictionary or parsed.get("numerical_version") != VERSION or parsed.get("base_multiplier") != 1.0 or not parsed.get("enemies") is Dictionary: return {}
		_species = parsed.enemies
	return _species.get(id,{}).duplicate(true)

static func stats(id: String, raw: Dictionary, archetype: String, level: int, chapter: int, difficulty: int, rank: String) -> Dictionary:
	var species := definition(id)
	if species.is_empty() or int(species.get("chapter",0)) != chapter or not Growth.ROLES.has(archetype): return {}
	if level < 1 or level > 60 or chapter < 1 or chapter > 7 or difficulty not in range(5) or rank not in ["normal","elite"]: return {}
	for key: String in FIELDS:
		var value: Variant = raw.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0: return {}
	var percentages: Variant = species.get("specialization_percent")
	if not percentages is Dictionary: return {}
	for key: String in FIELDS:
		if not _finite_range(percentages.get(key),1.0,500.0): return {}
	var primary := str(species.get("primary_role",""))
	if primary not in ["tank","warrior","caster","ranged","assassin","support"]: return {}
	var ap_percent: Variant = species.get("ability_power_percent_of_base_attack")
	var spell_ratio: Variant = species.get("skill_base_attack_budget_ratio")
	if not _finite_range(ap_percent,0.0,500.0) or not _finite_range(spell_ratio,0.0,1.0): return {}
	if primary != "caster" and (float(ap_percent)!=0.0 or float(spell_ratio)!=0.0): return {}
	if primary == "tank":
		for key: String in FIELDS:
			if float(percentages[key]) != float({"max_hp":200,"damage":100,"armor":130,"magic_resist":130}[key]): return {}
	if not _finite_range(species.get("crit_chance_bonus"),0.0,1.0) or not _finite_range(species.get("crit_multiplier_bonus"),0.0,2.0): return {}
	var role: Array = Growth.ROLES[archetype]
	var elite := rank == "elite"
	var tier := 4 if level >= 15 else 3 if level >= 10 else 2 if level >= 5 else 1
	var defense_growth := Growth.DEFENSE_PER_LEVEL*(level-1)+Growth.DEFENSE_PER_CHAPTER*(chapter-1)+Growth.DEFENSE_PER_DIFFICULTY*difficulty
	# Every amount below is unrounded. Never divide the archive14 integer stats
	# by 1.5, nor derive AP/spell base from the caster's reduced rounded AD.
	var hp: float = float(raw.max_hp)*role[0]*(1.0+Growth.HP_PER_LEVEL*(level-1))*(1.2 if elite else 1.0)*1.35*10.0*(1.0+Growth.HP_PER_CHAPTER*(chapter-1))*Growth.HP_D[difficulty]
	var attack: float = minf(16.9,maxf(role[2],float(raw.damage)*role[1]))*(1.0+Growth.ATTACK_PER_LEVEL*(level-1))*(1.12 if elite else 1.0)*1.35*10.0*(1.0+Growth.ATTACK_PER_CHAPTER*(chapter-1))*Growth.ATTACK_D[difficulty]
	var armor: float = (minf(24.0,float(raw.armor)*role[3]+role[4]+(tier-1)*role[5])+defense_growth)*10.0
	var resist: float = (minf(32.0,float(raw.magic_resist)+(tier-1)*role[6]+(4.0 if elite else 0.0))+defense_growth)*10.0
	return {"max_hp":_integer(hp*float(percentages.max_hp)/100.0),"damage":_integer(attack*float(percentages.damage)/100.0),
		"armor":_integer(armor*float(percentages.armor)/100.0),"magic_resist":_integer(resist*float(percentages.magic_resist)/100.0),
		"ability_power":_integer(attack*float(ap_percent)/100.0),"skill_base_power":_integer(attack*float(spell_ratio)),
		"crit_policy_version":1,
		"species_crit_chance_bonus":float(species.crit_chance_bonus),"species_crit_multiplier_bonus":float(species.crit_multiplier_bonus),
		"crit_chance":minf(Crit.MAX_CHANCE,Crit.DEFAULT_CHANCE+float(species.crit_chance_bonus)),
		"crit_multiplier":minf(Crit.MAX_MULTIPLIER,Crit.DEFAULT_MULTIPLIER+float(species.crit_multiplier_bonus)),
		"primary_role":primary,"secondary_role":str(species.get("secondary_role","")),
		"enemy_species_version":VERSION,"enemy_growth_version":VERSION,"monster_role_policy_version":VERSION,
		"monster_role_specialization":primary}

static func stamp_boss(source: Dictionary) -> Dictionary:
	if source.is_empty(): return {}
	var result := source.duplicate(true)
	result.merge({"enemy_species_version":VERSION,"crit_policy_version":1,"primary_role":"boss",
		"ability_power":0,"skill_base_power":0,"crit_chance":Crit.DEFAULT_CHANCE,"crit_multiplier":Crit.DEFAULT_MULTIPLIER},true)
	return result

static func _integer(value: float) -> int:
	return int(floor(value+0.5))

static func _finite_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum
