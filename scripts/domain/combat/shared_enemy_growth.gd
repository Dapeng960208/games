extends RefCounted
## Archive14: canonical, player-independent ordinary/elite growth. All four
## attributes are computed from authored raw values, with one final rounding.
const VERSION := 3
const RolePolicy = preload("res://scripts/domain/combat/monster_role_policy.gd")
const HP_D := [1.0,1.4,2.0,2.8,4.0]
const ATTACK_D := [1.0,1.2,1.5,1.85,2.3]
# HP, attack, minimum attack, armor ratio, armor flat, armor/tier, MR/tier.
const ROLES := {
	"skirmisher":[1.0,1.0,0.0,1.0,0.0,2.0,1.0],
	"caster":[0.86,1.16,0.0,0.5,0.0,1.0,2.0],
	"assassin":[0.72,1.20,15.0,0.25,0.0,0.5,0.5],
	"support":[0.96,0.90,0.0,1.0,0.0,1.0,1.5],
	"tank":[1.02,0.90,0.0,1.0,8.0,2.0,1.0],
}
const HP_PER_LEVEL := 0.055
const ATTACK_PER_LEVEL := 0.025
const HP_PER_CHAPTER := 0.12
const ATTACK_PER_CHAPTER := 0.08
const DEFENSE_PER_LEVEL := 0.5
const DEFENSE_PER_CHAPTER := 1.0
const DEFENSE_PER_DIFFICULTY := 2.0
static var _profiles: Dictionary = {}

static func raw_legacy(id: String, catalog_entry: Dictionary) -> Dictionary:
	if _profiles.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://data/monsters/enemy_progression.json")))
		_profiles = data.get("profiles",{})
	var raw: Dictionary = _profiles.get(id,{}).get("base_stats",{}).duplicate(true)
	raw["magic_resist"] = catalog_entry.get("magic_resist",0.0)
	return raw

static func stats(raw: Dictionary, archetype: String, authored_role: String, level: int, chapter: int, difficulty: int, rank: String) -> Dictionary:
	if not ROLES.has(archetype) or level < 1 or level > 60 or chapter < 1 or chapter > 12 or difficulty not in range(5) or rank not in ["normal","elite"]: return {}
	var identity := RolePolicy.role(archetype,authored_role)
	if identity.is_empty(): return {}
	for key: String in ["max_hp","damage","armor","magic_resist"]:
		var value: Variant = raw.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0: return {}
	var role: Array = ROLES[archetype]
	var specialization: Array = RolePolicy.SPECIALIZATION[identity]
	var elite := rank == "elite"
	var tier := 4 if level >= 15 else 3 if level >= 10 else 2 if level >= 5 else 1
	var defense_growth := DEFENSE_PER_LEVEL*(level-1)+DEFENSE_PER_CHAPTER*(chapter-1)+DEFENSE_PER_DIFFICULTY*difficulty
	var values := [
		float(raw.max_hp)*role[0]*(1.0+HP_PER_LEVEL*(level-1))*(1.2 if elite else 1.0)*1.35*10.0*(1.0+HP_PER_CHAPTER*(chapter-1))*HP_D[difficulty],
		minf(16.9,maxf(role[2],float(raw.damage)*role[1]))*(1.0+ATTACK_PER_LEVEL*(level-1))*(1.12 if elite else 1.0)*1.35*10.0*(1.0+ATTACK_PER_CHAPTER*(chapter-1))*ATTACK_D[difficulty],
		(minf(24.0,float(raw.armor)*role[3]+role[4]+(tier-1)*role[5])+defense_growth)*10.0,
		(minf(32.0,float(raw.magic_resist)+(tier-1)*role[6]+(4.0 if elite else 0.0))+defense_growth)*10.0,
	]
	var result := {"monster_role_policy_version":VERSION,"monster_role_specialization":identity,"enemy_growth_version":VERSION}
	for index in RolePolicy.FIELDS.size():
		result[RolePolicy.FIELDS[index]] = int(floor(float(values[index])*1.5*float(specialization[index])/100.0+0.5))
	return result
