class_name HeroProgression
extends RefCounted
## Pure V2 progression. Callers atomically save the returned profile with rewards.
const Numbers = preload("res://config/numerical_rules.gd")
const TALENTS := ["mastery", "precision", "vitality", "resistance", "agility", "dexterity"]

static func level_cap() -> int:
	return mini(60, int(Numbers.value("implemented_chapters")) * int(Numbers.value("chapter_level_step")))

static func thresholds(cap: int = 0) -> Array:
	var limit := level_cap() if cap <= 0 else clampi(cap, 1, 60)
	var result: Array = Numbers.value("xp_thresholds_1_20")
	var future: Dictionary = Numbers.value("xp_after_20")
	while result.size() < limit:
		var level := result.size() + 1
		result.append(int(result.back()) + int(future.first_step) + int(future.step_increment) * (level - 21))
	return result.slice(0, limit)

static func level_for_xp(xp: int, cap: int = 0) -> int:
	var values := thresholds(cap)
	var level := 1
	for index in values.size():
		if xp < int(values[index]): break
		level = index + 1
	return level

static func rank_cap(cap: int = 0) -> int:
	return ceili(float(level_cap() if cap <= 0 else cap) / float(Numbers.value("talent_node_rank_cap_divisor")))

static func valid_talents(talents: Variant, level: int, cap: int = 0) -> bool:
	if not talents is Dictionary: return false
	var spent := 0
	for key: Variant in talents:
		if key not in TALENTS: return false
		var rank: Variant = talents[key]
		if not (rank is int or rank is float) or not is_finite(float(rank)) or rank != int(rank) or int(rank) < 0 or int(rank) > rank_cap(cap): return false
		spent += int(rank)
	return spent <= maxi(0, level - 1)

static func available_points(talents: Dictionary, level: int) -> int:
	var remaining := maxi(0, level - 1)
	for rank: Variant in talents.values(): remaining -= int(rank)
	return maxi(0, remaining)

static func hero_base(definition: Dictionary, level: int, talents: Dictionary = {}, cap: int = 0) -> Dictionary:
	var limit := level_cap() if cap <= 0 else cap
	level = clampi(level, 1, limit)
	if not valid_talents(talents, level, limit): return {}
	var growth: Dictionary = Numbers.value("growth")
	var per_rank: Dictionary = Numbers.value("talent_per_rank")
	var result := definition.duplicate(true)
	var mage := str(definition.get("id", "")) == "CH03"
	for key in ["attack", "ability_power", "max_hp"]:
		var base := float(definition.get(key, 0.0)) * float(Numbers.value("combat_scale"))
		var multiplier := 1.0 + float(growth[key]) * (level - 1)
		if key == ("ability_power" if mage else "attack"):
			multiplier *= 1.0 + int(talents.get("mastery", 0)) * float(per_rank.main_attribute_ratio)
		if key == "max_hp": multiplier *= 1.0 + int(talents.get("vitality", 0)) * float(per_rank.hero_hp_ratio)
		result[key] = Numbers.integer(base * multiplier)
	for key in ["armor", "magic_resist"]:
		result[key] = Numbers.integer(float(definition.get(key, 18.0 if mage else 12.0)) * float(Numbers.value("combat_scale")) + float(growth[key]) * (level - 1) + int(talents.get("resistance", 0)) * float(per_rank.armor_and_magic_resist_flat))
	for key in ["resource_max", "resource_regen", "starting_resource"]:
		result[key] = Numbers.scale(float(definition.get(key, 0)), Numbers.V2)
	result["talent_crit_chance"] = int(talents.get("precision", 0)) * float(per_rank.crit_chance)
	result["talent_attack_speed"] = int(talents.get("agility", 0)) * float(per_rank.attack_speed)
	result["talent_cooldown_reduction"] = int(talents.get("dexterity", 0)) * float(per_rank.cooldown_reduction)
	result["talents"] = talents.duplicate(true)
	result["talent_points_available"] = available_points(talents, level)
	result["level"] = level
	return result

static func award(profile: Dictionary, hero: String, amount: int, event_id: String, race: String) -> Dictionary:
	if hero not in ["CH01", "CH02", "CH03"] or amount < 0 or amount > 3600 or event_id.is_empty(): return {}
	var next := profile.duplicate(true)
	var receipts: Dictionary = next.get("progression_receipts", {})
	if receipts.has(event_id):
		var old: Dictionary = receipts[event_id]
		return {"profile":next,"added":0,"replayed":true} if old.hero == hero and int(old.amount) == amount and old.race == race else {}
	if receipts.size() >= 100000: return {}
	var before := int(next.hero_xp[hero])
	var maximum := int(thresholds().back())
	var added := mini(amount, maxi(0, maximum - before))
	next.hero_xp[hero] = before + added
	var overflow := amount - added
	var research: Dictionary = next.get("research_xp", {})
	var progress := int(research.get(hero, 0)) + overflow
	var interval := int(Numbers.value("research_xp_per_reward"))
	var rewards := int(progress / interval)
	if rewards > 0 and race not in ["B01", "B02", "B03", "B04"]: return {}
	research[hero] = progress % interval
	next["research_xp"] = research
	var materials: Dictionary = next.get("materials", {})
	if rewards > 0:
		var reward: Dictionary = Numbers.value("research_reward")
		materials["forge"] = int(materials.get("forge", 0)) + rewards * int(reward.common_material)
		materials["race:" + race] = int(materials.get("race:" + race, 0)) + rewards * int(reward.race_material)
	next["materials"] = materials
	receipts[event_id] = {"hero":hero,"amount":amount,"race":race}
	next["progression_receipts"] = receipts
	return {"profile":next,"added":added,"research_rewards":rewards,"replayed":false}
