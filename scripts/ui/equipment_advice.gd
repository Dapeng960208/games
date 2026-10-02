extends RefCounted
const Numbers = preload("res://config/numerical_rules.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Abilities = preload("res://scripts/combat/hero_abilities.gd")
## Pure presentation advice from resolved base stats. It never selects equipment,
## performs a transaction, or values conditional affixes as constant damage.
const Registry = preload("res://scripts/data/content_registry.gd")
const Text = preload("res://scripts/ui/strings.gd")
const HEROES := ["CH01", "CH02", "CH03"]
const RATIOS := ["crit_chance", "crit_multiplier", "cooldown_reduction", "damage_bonus", "damage_reduction"]
const COMMON := ["attack", "attack_speed", "crit_chance", "crit_multiplier", "max_hp", "armor", "magic_resist", "move_speed", "cooldown_reduction", "damage_bonus", "damage_reduction", "true_damage_bonus"]

static func _t(zh: String, en: String) -> String:
	return en if Text.locale == "en" else zh

## Stable set_id:threshold tokens for the UI's warning treatment. Counts come
## from StatResolver.sets; no conditional effect is included in base-stat gains.
static func lost_tiers(before: Dictionary, after: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var prior: Dictionary = before.get("sets", {})
	var next: Dictionary = after.get("sets", {})
	var ids: Array = prior.keys()
	ids.sort()
	for id: String in ids:
		for tier: int in [6, 4, 2]:
			if int(prior[id]) >= tier and int(next.get(id, 0)) < tier:
				result.append(id + ":" + str(tier))
	return result

static func summarize(hero_id: String, before: Dictionary, after: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var lost := lost_tiers(before, after)
	if not lost.is_empty():
		var parts := lost[0].split(":")
		var definition: Dictionary = Registry.sets().get(parts[0], {})
		var field := "name_en" if Text.locale == "en" else "name"
		var title := str(definition.get(field, parts[0]))
		var limit := 18 if Text.locale == "en" else 12
		if title.length() > limit: title = title.left(limit - 1) + "…"
		if lost.size() > 1:
			lines.append(_t("失去%s%s件套（共%d档）", "Lose %s %s-piece (%d tiers lost)") % [title, parts[1], lost.size()])
		else:
			lines.append(_t("失去%s%s件套效果", "Lose %s %s-piece effect") % [title, parts[1]])
	var priority: Array = ["skill_power", "max_hp", "armor", "magic_resist", "damage_reduction", "attack_interval", "armor_penetration", "true_damage_bonus", "cooldown_reduction", "move_speed", "crit_chance", "crit_multiplier", "damage_bonus"]
	if hero_id == "CH02":
		priority = ["skill_power", "attack_interval", "crit_chance", "crit_multiplier", "armor_penetration", "move_speed", "max_hp", "armor", "magic_resist", "damage_reduction", "cooldown_reduction", "true_damage_bonus", "damage_bonus"]
	elif hero_id == "CH03":
		priority = ["skill_power", "cooldown_reduction", "magic_penetration", "resource_max", "attack_interval", "max_hp", "armor", "magic_resist", "damage_reduction", "move_speed", "crit_chance", "crit_multiplier", "true_damage_bonus", "damage_bonus"]
	var gains: Array[String] = []
	var costs: Array[String] = []
	for key: String in priority:
		if key == "attack_interval" and (not before.has(key) or not after.has(key)): continue
		var old := _metric(hero_id, key, before)
		var next := _metric(hero_id, key, after)
		var delta := next - old
		if is_equal_approx(old, next): continue
		# Do not claim a gain which rounds to +0.0 in this compact summary.
		var visible_step := 0.001 if key == "attack_interval" or key in RATIOS else 0.1
		if absf(delta) < visible_step * 0.5: continue
		var gain := delta < 0.0 if key == "attack_interval" else delta > 0.0
		var text := _change(hero_id, key, delta, gain, int(after.get("ruleset_version",1)))
		if gain: gains.append(text)
		else: costs.append(text)
	# Reserve one line for each side of a trade, instead of letting several small
	# gains hide a real cost. Priority is explanatory, never a power score.
	if not gains.is_empty(): lines.append(gains.pop_front())
	if not costs.is_empty(): lines.append(costs.pop_front())
	while lines.size() < 3 and not gains.is_empty(): lines.append(gains.pop_front())
	while lines.size() < 3 and not costs.is_empty(): lines.append(costs.pop_front())
	if lines.is_empty(): lines.append(_t("常用基础属性不变，词缀另看", "Core base stats unchanged; check the affix."))
	return lines

static func _metric(hero_id: String, key: String, stats: Dictionary) -> float:
	if key == "skill_power":
		# Mirrors Player.skill_power: AP only scales the Resonator's skill power.
		return float(Abilities.preview_powers(hero_id, stats).skill_H)
	if key == "resource_max": return float(stats.get("resource_max", stats.get("max_mana", 0.0)))
	return float(stats.get(key, 0.0))

static func _change(hero_id: String, key: String, delta: float, gain: bool, version: int = 1) -> String:
	var names := {
		"skill_power":_t("技能威力", "Skill power") if hero_id == "CH03" else _t("攻击", "Attack"),
		"attack_interval":_t("普攻间隔", "Attack interval"), "max_hp":_t("生命上限", "Max health"),
		"armor":_t("护甲", "Armor"), "magic_resist":_t("法术抗性", "Magic resistance"),
		"armor_penetration":_t("物理穿透", "Armor penetration"), "magic_penetration":_t("法术穿透", "Magic penetration"),
		"resource_max":_t("法力上限", "Max mana"), "move_speed":_t("移速", "Move speed"),
		"crit_chance":_t("暴击率", "Critical chance"), "crit_multiplier":_t("暴击倍率", "Critical multiplier"),
		"cooldown_reduction":_t("冷却缩减", "Cooldown reduction"), "true_damage_bonus":_t("真伤附加", "True damage bonus"),
		"damage_bonus":_t("基础增伤", "Base damage bonus"), "damage_reduction":_t("装备减伤", "Equipment reduction")}
	var amount := ("%+d" % int(delta)) if version == 2 and key not in RATIOS and key not in ["attack_interval","move_speed"] else "%+.1f" % delta
	if key == "attack_interval": amount = "%+.3f" % delta + _t("秒", " s")
	elif key in RATIOS: amount = "%+.1f" % (delta * 100.0) + _t("百分点", " pp")
	return (_t("收益：", "Gain: ") if gain else _t("代价：", "Cost: ")) + str(names[key]) + " " + amount

static func _positive(stats: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if float(stats.get(key, 0.0)) > 0.0: return true
	return false

static func is_relevant(item: Dictionary, hero_id: String) -> bool:
	if item.is_empty() or not hero_id in HEROES: return false
	if item.get("instance_record") is Dictionary: return Instances.can_equip(item.instance_record,hero_id,20)
	var allowed: Array = item.get("allowed_heroes", [])
	if not allowed.is_empty() and not allowed.has(hero_id): return false
	if item.has("allowed_heroes") and hero_id not in item.allowed_heroes: return false
	if not str(item.get("hero_id", "")).is_empty() and str(item.hero_id) != hero_id: return false
	var stats: Dictionary = item.get("instance_stats", item.get("base_stats", {}))
	if _positive(stats, COMMON): return true
	if hero_id == "CH03" and _positive(stats, ["ability_power", "magic_penetration", "max_mana"]): return true
	if hero_id != "CH03" and _positive(stats, ["armor_penetration"]): return true
	# Unknown/conditional-only gear stays discoverable. This is a presentation
	# preference, never a rule preventing the player from equipping an item.
	return stats.is_empty() or _positive(stats, ["burn_damage", "corrosion_damage_bonus", "status_duration"])

static func purpose(item: Dictionary, hero_id: String) -> String:
	if not is_relevant(item, hero_id): return _t("其他职业取向，词缀可展开查看", "Other role focus; inspect its affix.")
	var stats: Dictionary = item.get("instance_stats", item.get("base_stats", {}))
	var tags: Array[String] = []
	if hero_id == "CH03" and _positive(stats, ["ability_power", "magic_penetration"]): tags.append(_t("法术输出", "Spell offense"))
	elif hero_id == "CH03" and _positive(stats, ["attack"]): tags.append(_t("技能威力", "Skill power"))
	elif hero_id != "CH03" and _positive(stats, ["attack", "armor_penetration", "true_damage_bonus"]): tags.append(_t("近战输出", "Melee offense") if hero_id == "CH01" else _t("射击输出", "Ranged offense"))
	elif _positive(stats, ["true_damage_bonus"]): tags.append(_t("附加真伤", "Added true damage"))
	if _positive(stats, ["attack_speed", "crit_chance", "crit_multiplier"]): tags.append(_t("普攻连击", "Primary attacks"))
	if _positive(stats, ["max_hp", "armor", "magic_resist", "damage_reduction"]): tags.append(_t("生存防护", "Survival"))
	if _positive(stats, ["cooldown_reduction"]): tags.append(_t("技能周转", "Skill cooldowns"))
	if _positive(stats, ["move_speed"]): tags.append(_t("走位机动", "Mobility"))
	if hero_id == "CH03" and _positive(stats, ["max_mana"]): tags.append(_t("法力储备", "Mana reserve"))
	if _positive(stats, ["damage_bonus"]): tags.append(_t("伤害强化", "Damage bonus"))
	if tags.is_empty(): return _t("条件词缀取向，触发方式见详情", "Affix focus; inspect its trigger.")
	return " · ".join(tags.slice(0, 2))

static func combat_metrics(hero_id: String, stats: Dictionary) -> Dictionary:
	var powers := Abilities.preview_powers(hero_id,stats)
	var denominator := float(Numbers.value("resistance_denominator")) if int(stats.get("ruleset_version",1)) == 2 else 100.0
	var hp := float(stats.get("max_hp",0))
	var reduction := clampf(float(stats.get("equipment_damage_reduction",0)),0,0.99)
	var bonus := 1.0+float(stats.get("damage_bonus",0))
	var normal: Variant = Abilities.packet_amount(bonus,float(powers.basic_H),stats)
	var critical: Variant = Abilities.packet_amount(bonus*float(stats.get("crit_multiplier",1.5)),float(powers.basic_H),stats)
	var expected := lerpf(float(normal),float(critical),float(stats.get("crit_chance",0)))
	var q := Abilities.preview_spec(hero_id,int(stats.get("level",1)),stats,"q")
	return {"physical_ehp":hp*(1.0+float(stats.get("armor",0))/denominator)/(1.0-reduction),"magic_ehp":hp*(1.0+float(stats.get("magic_resist",0))/denominator)/(1.0-reduction),"basic_dps":expected/maxf(0.001,float(stats.get("attack_interval",1))),"q_packet":Abilities.packet_amount(float(q.get("coefficient",0)),float(powers.skill_H),stats)}
