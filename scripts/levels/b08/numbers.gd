extends RefCounted
## Frozen B08 candidate only. No extension of global archive14/15 tables.
const Content = preload("res://scripts/levels/b08/content.gd")
const Growth = preload("res://scripts/domain/combat/shared_enemy_growth.gd")
const Crit = preload("res://scripts/domain/combat/crit_policy.gd")
const ARCHETYPE := {"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}
static func profile(id: String, difficulty: int = 0, rank: String = "normal", level_override: int = 0) -> Dictionary:
	if difficulty not in range(5) or rank not in ["normal","elite","boss"]: return {}
	var boss := id=="BO08"
	var source: Dictionary = Content.catalog().boss if boss else Content.enemy(id)
	if source.is_empty() or (rank=="boss" and not boss): return {}
	if not boss and level_override!=0:
		if level_override not in [36,38,40] or level_override<int(source.level): return {}
		source.level = level_override
	var raw: Dictionary = source.raw if boss else Content.catalog().profiles[source.role]
	var result := {"enemy_id":id,"name":source.name,"biome_id":"B08","chapter":8,"enemy_level":int(source.level),"rank":"boss" if boss else rank,"difficulty":difficulty,"ruleset_version":2,"scale_version":10,"b08_numerical_version":1,"clan":"winged","crit_policy_version":1,"crit_chance":Crit.DEFAULT_CHANCE,"crit_multiplier":Crit.DEFAULT_MULTIPLIER,"ability_power":0,"skill_base_power":0,"attack_range":230.0 if boss else float(raw.attack_range),"navigation_radius":38.0 if boss else 18.0,"move_speed":float(raw.move_speed)*(1+0.04*difficulty),"recovery_seconds":1.3 if boss else float(raw.recovery_seconds),"effective_threat_cost":1.0,"archetype":"boss" if boss else ARCHETYPE[source.role],"role":"boss" if boss else source.role}
	if boss:
		result.merge({"max_hp":_integer(1300*13.5*1.84*Growth.HP_D[difficulty]),"damage":_integer(30*13.5*1.56*Growth.ATTACK_D[difficulty]),"armor":(11+2*difficulty)*10,"magic_resist":(11+2*difficulty)*10})
	else:
		var role: Array = Growth.ROLES[ARCHETYPE[source.role]]
		var level := int(source.level)
		var elite := rank=="elite"
		var tank: bool = source.role=="T"
		var defense := 0.5*(level-1)+7+2*difficulty
		result.merge({
			"max_hp":_integer(float(raw.max_hp)*role[0]*(1+0.055*(level-1))*(1.2 if elite else 1.0)*13.5*1.84*Growth.HP_D[difficulty]*(2.0 if tank else 1.0)),
			"damage":_integer(minf(16.9,maxf(role[2],float(raw.damage)*role[1]))*(1+0.025*(level-1))*(1.12 if elite else 1.0)*13.5*1.56*Growth.ATTACK_D[difficulty]),
			"armor":_integer((minf(24,float(raw.armor)*role[3]+role[4]+3*role[5])+defense)*10*(1.3 if tank else 1.0)),
			"magic_resist":_integer((minf(32,float(raw.magic_resist)+3*role[6]+(4 if elite else 0))+defense)*10*(1.3 if tank else 1.0))})
	return result
static func _integer(value: float) -> int: return int(floor(value+0.5))
