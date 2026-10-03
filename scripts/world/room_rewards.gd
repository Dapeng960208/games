extends RefCounted
## Pure reward policy. Persistence, duplicate conversion and extraction belong to
## the run controller; this file never grants currency or changes a run.
## In policy 1, callers pass historical discoveries in `owned` to preserve
## first-discovery priority after selling. Pending finds remain excluded too.
## Missing policy versions retain the old ownership-based deterministic rolls.

const Registry = preload("res://scripts/data/content_registry.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const NORMAL_XP := 30
const NORMAL_MASTERY := 180
const CURRENT_POLICY_VERSION := 1

static func build(room_id: String, quality: String, hero_id: String, seed: int, completion_id: String, owned: Array = [], pending: Array = [], bosses: Array = [], difficulty: int = -1, policy_version: int = 0) -> Dictionary:
	if policy_version == 2: return v2_completion(room_id, difficulty, quality) if not completion_id.is_empty() else {}
	if Registry.hero(hero_id).is_empty() or completion_id.is_empty():
		return {}
	if difficulty < -1 or difficulty > 4 or policy_version not in [0, CURRENT_POLICY_VERSION]: return {}
	if policy_version == CURRENT_POLICY_VERSION and difficulty < 0: return {}
	var unlocked: Array = bosses.duplicate()
	if Catalog.bosses().has(room_id):
		if quality != "full": return {}
		if not unlocked.has(room_id): unlocked.append(room_id)
		var reward: Dictionary = _race_reward(room_id, 80, 2, hero_id, seed, completion_id, owned, pending, difficulty, true) if difficulty >= 0 else _reward(80, "offense", 2, hero_id, seed, room_id + ":" + quality, completion_id, owned, pending, unlocked)
		reward.merge({"xp": 80, "mastery": 0, "boss_id": room_id}, true)
		return reward
	for option: Dictionary in _policy_options(room_id, policy_version):
		if str(option.quality) == quality:
			var reward: Dictionary = _race_reward(room_id, int(option.gold), int(option.count) if policy_version == CURRENT_POLICY_VERSION else 1, hero_id, seed, completion_id, owned, pending, difficulty) if difficulty >= 0 else _reward(int(option.gold), str(option.theme), int(option.count), hero_id, seed, room_id + ":" + quality, completion_id, owned, pending, unlocked)
			reward.merge({"xp": NORMAL_XP, "mastery": NORMAL_MASTERY}, true)
			return reward
	return {}

static func optional(room_id: String, objective_id: String, hero_id: String, seed: int, event_id: String, owned: Array = [], pending: Array = [], bosses: Array = [], difficulty: int = -1, policy_version: int = 0) -> Dictionary:
	if policy_version == 2: return v2_optional(room_id, objective_id, difficulty)
	var definition: Dictionary = optional_definition(room_id, objective_id)
	if definition.is_empty() or Registry.hero(hero_id).is_empty() or event_id.is_empty():
		return {}
	if difficulty < -1 or difficulty > 4 or policy_version not in [0, CURRENT_POLICY_VERSION]: return {}
	if policy_version == CURRENT_POLICY_VERSION and difficulty < 0: return {}
	var reward: Dictionary = _race_reward(room_id, int(definition.gold), int(definition.count), hero_id, seed, event_id, owned, pending, difficulty) if difficulty >= 0 else _reward(int(definition.gold), str(definition.theme), int(definition.count), hero_id, seed, room_id + ":" + objective_id, event_id, owned, pending, bosses)
	# Optional finds do not duplicate the room's XP or mastery award.
	reward.merge({"xp": 0, "mastery": 0}, true)
	return reward

static func optional_definition(room_id: String, objective_id: String) -> Dictionary:
	if room_id == "L01" and objective_id == "side_crate":
		return _option("optional", 18, "defense", 1, "清场后侧箱", "After clear: side crate")
	if room_id == "L11" and objective_id == "research_2":
		return _option("optional", 22, "offense", 1, "清场后第3包", "After clear: third package")
	return {}

static func qualities(room_id: String, policy_version: int = 0) -> Array:
	if policy_version == 2:
		if Catalog.bosses().has(room_id): return ["full"]
		var outcomes: Array = []
		for option: Dictionary in _policy_options(room_id, CURRENT_POLICY_VERSION): outcomes.append(option.quality)
		return outcomes
	if policy_version not in [0, CURRENT_POLICY_VERSION]: return []
	if Catalog.bosses().has(room_id): return ["full"]
	var result: Array = []
	for option: Dictionary in _policy_options(room_id, policy_version): result.append(str(option.quality))
	return result

static func preview(room_id: String, hero_id: String, english: bool = false, difficulty: int = -1, policy_version: int = 0) -> String:
	if policy_version == 2:
		var reward := v2_completion(room_id, difficulty)
		if reward.is_empty(): return ""
		var count: int = [2,2,3,3,4][difficulty] if reward.source == "boss" else 1
		return "%d gold · %d independent gear · extract to retain gear and materials" % [reward.gold, count] if english else "%d金币 · %d件独立装备 · 撤离带回装备与材料" % [reward.gold, count]
	if Registry.hero(hero_id).is_empty() or policy_version not in [0, CURRENT_POLICY_VERSION]: return ""
	if policy_version == CURRENT_POLICY_VERSION:
		return _current_preview(room_id, hero_id, english, difficulty)
	if difficulty >= 0 and difficulty <= 4:
		var race := biome_for_reward(room_id)
		if race.is_empty(): return ""
		var biome: Dictionary = Catalog.biomes().get(race, {})
		var title := str(biome.get("name_en" if english else "name", race))
		var boss := Catalog.bosses().has(room_id)
		var count := 2 + int(difficulty / 2) if boss else (2 if difficulty >= 2 else 1)
		var lower := maxi(0, difficulty - 1)
		var upper := lower + (1 if difficulty == 1 else 0)
		if boss and difficulty >= 1:
			lower += 1
			upper += 1
		lower = mini(3, lower)
		upper = mini(3, upper)
		return "%s · %d faction gear · +%d–%d\nExtract to keep gear; duplicates convert to gold" % [title, count, lower, upper] if english else "%s · %d件本族装备 · 强化+%d～%d\n撤离后永久保留，重复装备折算金币" % [title, count, lower, upper]
	var lines: PackedStringArray = []
	if Catalog.bosses().has(room_id):
		lines.append(_preview_line(_option("full", 80, "offense", 2, "击败首领", "Defeat boss"), hero_id, english))
		lines.append("+80 XP · Gear is kept on extraction" if english else "+80经验 · 装备需撤离带回")
		return "\n".join(lines)
	var options: Array = _options(room_id)
	if options.is_empty(): return ""
	for option: Dictionary in options:
		lines.append(_preview_line(option, hero_id, english))
	var extra: Dictionary = optional_definition(room_id, "side_crate" if room_id == "L01" else "research_2")
	if not extra.is_empty(): lines.append(_preview_line(extra, hero_id, english))
	lines.append("+30 XP · +180 mastery · Extract to keep gear" if english else "+30经验 · +180历练 · 装备需撤离带回")
	return "\n".join(lines)

static func biome_for_reward(room_id: String) -> String:
	var definition: Dictionary = Catalog.bosses().get(room_id, {}) if Catalog.bosses().has(room_id) else Catalog.room(room_id)
	return str(definition.get("biome_id", ""))

## Version zero remains the exact historical policy, including its callable
## non-expedition quality branches. Current FirstFour expeditions have only one
## outcome: finish every combat objective and clear the encounter. Do not copy
## obsolete cargo/repair themes or counts into this live policy.
static func _policy_options(room_id: String, policy_version: int) -> Array:
	var options := _options(room_id)
	if (Catalog.b05_enabled() and biome_for_reward(room_id) == "B05") or (Catalog.b06_enabled() and biome_for_reward(room_id)=="B06"):
		return [_option("full",24,"faction",1,"清完有限波次","Clear all finite waves")]
	if policy_version == 0: return options
	var biome := biome_for_reward(room_id)
	var labels: Dictionary = {
		"B01":["全部回路充能并清场", "Charge all conduits and clear enemies"],
		"B02":["摧毁全部育虫巢并清场", "Destroy all brood nests and clear enemies"],
		"B03":["封闭全部墓穴并清场", "Seal all graves and clear enemies"],
		"B04":["拆除全部路障并清场", "Break all barricades and clear enemies"]}
	if not labels.has(biome): return []
	for option: Dictionary in options:
		if option.quality == "full":
			return [_option("full", int(option.gold), "faction", 1, labels[biome][0], labels[biome][1])]
	return []

## Gold, number of draws and enhancement bounds are shared by preview and rolls.
static func _race_terms(gold: int, base_count: int, difficulty: int, boss: bool = false) -> Dictionary:
	var lower := maxi(0, difficulty - 1)
	var upper := lower + (1 if difficulty == 1 else 0)
	if boss and difficulty >= 1:
		lower += 1
		upper += 1
	return {"gold":int(round(float(gold) * (1.0 + 0.25 * difficulty))),
		"count":base_count + (int(difficulty / 2) if boss else (1 if difficulty >= 2 else 0)),
		"lower":mini(3, lower), "upper":mini(3, upper)}

static func _current_preview(room_id: String, hero_id: String, english: bool, difficulty: int) -> String:
	if difficulty < 0 or difficulty > 4: return ""
	var biome := biome_for_reward(room_id)
	var pool := race_equipment_pool(biome, hero_id)
	if pool.is_empty(): return ""
	var boss := Catalog.bosses().has(room_id)
	var options: Array = [_option("full", 80, "faction", 2, "击败首领并清场", "Defeat boss and clear enemies")] if boss else _policy_options(room_id, CURRENT_POLICY_VERSION)
	if options.is_empty(): return ""
	var lines: PackedStringArray = []
	for option: Dictionary in options:
		lines.append(_race_preview_line(option, difficulty, pool.size(), boss, english))
	var extra := optional_definition(room_id, "side_crate" if room_id == "L01" else "research_2")
	if not extra.is_empty():
		extra.label = "清场后园匠晶籽收藏" if room_id == "L01" else "清场后花粉研究宝匣"
		extra.label_en = "After clear: gardener cache" if room_id == "L01" else "After clear: pollen research chest"
		lines.append(_race_preview_line(extra, difficulty, pool.size(), false, english))
	lines.append(("+80 XP" if boss else "+30 XP · +180 mastery") if english else ("+80经验" if boss else "+30经验 · +180历练"))
	lines.append("Extract to keep gear; repeats may convert to gold" if english else "撤离后保留装备；重复装备可能折算金币")
	return "\n".join(lines)

static func _race_preview_line(option: Dictionary, difficulty: int, pool_size: int, boss: bool, english: bool) -> String:
	var terms := _race_terms(int(option.gold), int(option.count), difficulty, boss)
	var count := mini(int(terms.count), pool_size)
	return "%s: %d gold + %d faction gear · +%d–%d" % [str(option.label_en), int(terms.gold), count, int(terms.lower), int(terms.upper)] if english else "%s：%d金币 + %d件本族装备 · 强化+%d～%d" % [str(option.label), int(terms.gold), count, int(terms.lower), int(terms.upper)]

## The prototype preserves the existing equipment IDs and effects. A faction
## drop never falls back to another race, including when every item is owned.
static func race_equipment_pool(biome_id: String, hero_id: String) -> Array:
	if not Catalog.biomes().has(biome_id) or Registry.hero(hero_id).is_empty(): return []
	var result: Array = []
	for id: String in Registry.equipment_ids():
		var item: Dictionary = Registry.equipment(id)
		if bool(item.get("shop_only", false)): continue
		if str(item.get("race_id", "")) == biome_id and _suitable(item, hero_id): result.append(id)
	return result

static func _race_reward(room_id: String, gold: int, base_count: int, hero_id: String, seed: int, event_id: String, owned: Array, pending: Array, difficulty: int, boss: bool = false) -> Dictionary:
	var biome := biome_for_reward(room_id)
	var pool := race_equipment_pool(biome, hero_id)
	if pool.is_empty(): return {}
	var fresh: Array = []
	var repeats: Array = []
	for id: String in pool:
		if owned.has(id) or pending.has(id): repeats.append(id)
		else: fresh.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed ^ (room_id + ":" + hero_id + ":" + str(difficulty)).hash() ^ 0x52414345) & 0x7fffffff
	var terms := _race_terms(gold, base_count, difficulty, boss)
	var count := int(terms.count)
	var drops: Array = []
	for index in mini(count, pool.size()):
		var candidates: Array = fresh if not fresh.is_empty() else repeats
		var id := str(candidates.pop_at(rng.randi_range(0, candidates.size() - 1)))
		var level := int(terms.lower)
		if difficulty == 1: level = rng.randi_range(int(terms.lower), int(terms.upper))
		var prefix := event_id if event_id.length() <= 140 else event_id.left(120) + ":" + str(event_id.hash())
		drops.append({"drop_id":prefix + ":equipment:" + str(index), "equipment_id":id, "drop_level":level})
	return {"gold":int(terms.gold), "equipment":drops, "race_id":biome}

## Pools come from live equipment stats and sets, not a second item catalogue.
## Even an exhausted pool keeps its theme; the transaction converts duplicates.
static func equipment_pool(theme: String, hero_id: String, bosses: Array = []) -> Array:
	if Registry.hero(hero_id).is_empty(): return []
	var result: Array = []
	for id: String in Registry.equipment_ids():
		var item: Dictionary = Registry.equipment(id)
		if bool(item.get("shop_only", false)): continue
		var requirement: String = str(item.get("unlock_boss", ""))
		if not requirement.is_empty() and not bosses.has(requirement): continue
		if not _suitable(item, hero_id): continue
		if _matches_theme(item, theme, hero_id): result.append(id)
	# Early/debug entry into the foundry must still offer useful unlocked gear.
	# Conductor sets unlock behind bosses; fall back within the same class role.
	if result.is_empty() and theme == "conductive":
		return equipment_pool("offense" if hero_id == "CH03" else "mobility", hero_id, bosses)
	return result

static func _suitable(item: Dictionary, hero_id: String) -> bool:
	# Current gear is universal by slot. Respect explicit hero restrictions if a
	# later data revision introduces them; never infer restrictions from its name.
	var allowed: Variant = item.get("allowed_heroes", [])
	if allowed is Array and not allowed.is_empty() and not allowed.has(hero_id): return false
	var owner: String = str(item.get("hero_id", ""))
	if not owner.is_empty() and owner != hero_id: return false
	var stats: Dictionary = item.get("base_stats", {})
	if hero_id != "CH03":
		# Mana contributes nothing to rage/energy, and these two kits scale with AD.
		return not _has_stat(stats, ["ability_power", "max_mana", "magic_penetration"])
	# Physical-only offence has no value to this spell kit. Shared defensive and
	# movement pieces remain eligible without diluting its offensive rewards.
	return not _has_stat(stats, ["attack", "armor_penetration"]) or _has_stat(stats, ["ability_power", "max_hp", "armor", "magic_resist", "move_speed", "damage_reduction"])

static func _matches_theme(item: Dictionary, theme: String, hero_id: String) -> bool:
	var stats: Dictionary = item.get("base_stats", {})
	var set_id: String = str(item.get("set_id", ""))
	match theme:
		"offense":
			if hero_id == "CH03": return _has_stat(stats, ["ability_power", "magic_penetration"])
			if hero_id == "CH01": return _has_stat(stats, ["attack", "true_damage_bonus"])
			return _has_stat(stats, ["attack", "crit_chance", "crit_multiplier", "attack_speed", "armor_penetration"])
		"defense": return str(item.get("slot", "")) in ["head", "chest", "feet", "charm"] and _has_stat(stats, ["armor", "magic_resist", "damage_reduction", "max_hp"])
		"survival": return _has_stat(stats, ["max_hp", "armor", "magic_resist", "damage_reduction"])
		"mobility": return _has_stat(stats, ["move_speed"]) or str(item.get("slot", "")) == "feet" and _has_stat(stats, ["cooldown_reduction"])
		"shield": return set_id == "S05" or _has_stat(stats, ["armor", "damage_reduction"])
		# The corrosion set itself unlocks only after BO03. Fungal rooms instead
		# offer resistance/DR pieces now, not an impossible early set promise.
		"corrosion": return _has_stat(stats, ["magic_resist", "damage_reduction"])
		"conductive": return set_id == "S02" if hero_id == "CH03" else set_id == "S08" and _has_stat(stats, ["move_speed"])
		"thermal": return set_id in ["S01", "S03"]
		"status":
			if hero_id == "CH03": return set_id in ["S01", "S02", "S04", "S08"] and _has_stat(stats, ["ability_power", "magic_penetration", "max_mana"])
			return set_id in ["S03", "S04", "S06", "S07"] and _has_stat(stats, ["attack", "crit_chance", "armor_penetration", "crit_multiplier"])
	return false

static func _has_stat(stats: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if float(stats.get(key, 0.0)) > 0.0: return true
	return false

static func _reward(gold: int, theme: String, count: int, hero_id: String, seed: int, salt: String, event_id: String, owned: Array, pending: Array, bosses: Array) -> Dictionary:
	var pool: Array = equipment_pool(theme, hero_id, bosses)
	var fresh: Array = []
	var repeats: Array = []
	for id: String in pool:
		if owned.has(id) or pending.has(id): repeats.append(id)
		else: fresh.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed ^ (salt + ":" + hero_id).hash() ^ 0x52455744) & 0x7fffffff
	var drops: Array = []
	for index in mini(count, pool.size()):
		var candidates: Array = fresh if not fresh.is_empty() else repeats
		var pick: int = rng.randi_range(0, candidates.size() - 1)
		var id: String = str(candidates.pop_at(pick))
		# Keep IDs bounded for the existing persistence schema, even for callers
		# with unusually long checkpoint IDs. Normal run IDs stay human-readable.
		var prefix: String = event_id if event_id.length() <= 140 else event_id.left(120) + ":" + str(event_id.hash())
		drops.append({"drop_id": prefix + ":equipment:" + str(index), "equipment_id": id})
	return {"gold": gold, "equipment": drops}

static func _option(quality: String, gold: int, theme: String, count: int, label: String, label_en: String) -> Dictionary:
	return {"quality": quality, "gold": gold, "theme": theme, "count": count, "label": label, "label_en": label_en}

static func _preview_line(option: Dictionary, hero_id: String, english: bool) -> String:
	var gear: String = _theme_label(str(option.theme), hero_id, english)
	if english:
		return "%s: %d gold%s" % [str(option.label_en), int(option.gold), " + %d %s" % [int(option.count), gear] if int(option.count) > 0 else " · no gear"]
	return "%s：%d金币%s" % [str(option.label), int(option.gold), " + %d件%s" % [int(option.count), gear] if int(option.count) > 0 else " · 无装备"]

static func _theme_label(theme: String, hero_id: String, english: bool) -> String:
	match theme:
		"offense":
			if english: return {"CH01":"melee gear", "CH02":"gunner gear", "CH03":"spell gear"}.get(hero_id, "class gear")
			return {"CH01":"近战装", "CH02":"射击装", "CH03":"法术装"}.get(hero_id, "职业装")
		"defense": return "armor" if english else "防具"
		"survival": return "survival gear" if english else "生存装"
		"mobility": return "mobility gear" if english else "机动装"
		"shield": return "guard gear" if english else "守护装"
		"corrosion": return "resistance gear" if english else "耐受装"
		"conductive": return ("spell gear" if hero_id == "CH03" else "mobility gear") if english else ("法术装" if hero_id == "CH03" else "机动装")
		"thermal": return "thermal gear" if english else "霜焰装"
		"status": return ("status gear" if hero_id == "CH03" else "combo gear") if english else ("状态装" if hero_id == "CH03" else "连击装")
	return "gear" if english else "装备"

static func _options(room_id: String) -> Array:
	if Catalog.room(room_id).is_empty(): return []
	match room_id:
		"L01": return [_option("full", 12, "offense", 1, "释放三闸", "Release three brakes")]
		"L02": return [_option("full", 18, "defense", 1, "重货完整", "Cargo intact"), _option("reduced", 34, "", 0, "卸货／货损", "Unload / cargo damaged")]
		"L03": return [_option("full", 30, "", 0, "停机取芯", "Stop gears"), _option("mobile", 12, "mobility", 1, "不停机取芯", "Keep gears running")]
		"L04": return [_option("full", 14, "offense", 1, "三匣归位", "Sort three crates")]
		"L05": return [_option("full", 18, "survival", 1, "两座信标供电", "Power both beacons")]
		"L06": return [_option("full", 24, "offense", 2, "稳压取芯", "Stabilize and retrieve"), _option("reduced", 8, "", 0, "紧急切管", "Emergency cut")]
		"L07": return [_option("full", 18, "corrosion", 1, "交付三枚滤芯", "Deliver three filters")]
		"L08": return [_option("full", 18, "mobility", 1, "采齐三株", "Collect three mushrooms"), _option("reduced", 10, "", 0, "两株提前封存", "Seal after two")]
		"L09": return [_option("full", 26, "status", 1, "最多破坏一枚假囊", "Break at most one decoy"), _option("reduced", 12, "", 0, "破坏两枚假囊", "Break two decoys")]
		"L10": return [_option("full", 20, "status", 1, "启动三座风机", "Start three fans")]
		"L11": return [_option("full", 18, "survival", 1, "交付两份研究包", "Deliver two packages")]
		"L12": return [_option("full", 24, "corrosion", 2, "完成两槽反应", "Complete both reactions"), _option("reduced", 10, "", 0, "提前排空", "Emergency drainage")]
		"L13": return [_option("full", 22, "shield", 1, "接头无需修复", "No joint repairs"), _option("repaired", 12, "", 0, "修复后完成", "Complete after repairs")]
		"L14": return [_option("full", 18, "mobility", 1, "点亮三盏灯", "Light three lamps")]
		"L15": return [_option("full", 22, "conductive", 1, "两车归轨", "Dock both carts")]
		"L16": return [_option("full", 24, "thermal", 1, "全程避免过热", "Avoid reactor overheating"), _option("repaired", 12, "", 0, "过热修复后完成", "Complete after repairs")]
		"L17": return [_option("full", 22, "offense", 1, "完整套件交付", "Deliver intact parts"), _option("repaired", 12, "", 0, "破损套件交付", "Deliver damaged parts")]
		"L18": return [_option("full", 24, "offense", 2, "回收三舱", "Recover three cargo pods")]
		"L19": return [_option("full", 20, "offense", 1, "拆除三道共鸣锁", "Release three locks")]
		"L20": return [_option("full", 24, "mobility", 1, "抵达时稳定度≥60", "Arrive at stability 60+"), _option("reduced", 12, "", 0, "稳定度不足60", "Arrive below stability 60")]
		"L21": return [_option("full", 22, "status", 1, "照亮两段铭文", "Illuminate both inscriptions")]
		"L22": return [_option("full", 22, "shield", 1, "装入三段声纹", "Install three sound patterns")]
		"L23": return [_option("full", 24, "offense", 2, "三灯同时就位", "Dock all three lamps"), _option("reduced", 12, "", 0, "两灯提前完成", "Finish with two lamps")]
		"L24": return [_option("full", 26, "status", 2, "完成声纹顺序", "Complete the echo sequence")]
	return []

## V2 gold is scaled exactly once here. Generation and material receipts are
## owned by the atomic expedition transaction, never the visual reward caller.
static func v2_completion(room_id: String, difficulty: int, quality: String = "full") -> Dictionary:
	if difficulty < 0 or difficulty > 4: return {}
	var boss := Catalog.bosses().has(room_id)
	var base := 80 if boss and quality == "full" else -1
	if not boss:
		for option: Dictionary in _policy_options(room_id, CURRENT_POLICY_VERSION):
			if option.quality == quality: base = int(option.gold)
	if base < 0: return {}
	var value := {"gold":ceili(base * 2.0 * (1.0 + .25 * difficulty)),"xp":ceili((80 if boss else 30) * (1.0 + .25 * difficulty)),"mastery":0 if boss else 180,"equipment":[],"quality":quality,"source":"boss" if boss else "room","race_id":biome_for_reward(room_id)}
	if boss: value.boss_id = room_id
	return value

static func v2_optional(room_id: String, objective_id: String, difficulty: int) -> Dictionary:
	var definition := optional_definition(room_id, objective_id)
	if definition.is_empty() or difficulty < 0 or difficulty > 4: return {}
	return {"gold":ceili(int(definition.gold) * 2.0 * (1.0 + .25 * difficulty)),"xp":0,"mastery":0,"equipment":[],"source":"chest","race_id":biome_for_reward(room_id)}

## Fixed chapter/zone challenge, independent of hero level and difficulty.
static func challenge_level(room_id: String, zone_index: int = 2) -> int:
	var race := biome_for_reward(room_id)
	if race.is_empty(): return 0
	if race in ["B05","B06"] and not Catalog.bosses().has(room_id): return int(Catalog.room(room_id).get("enemy_level",0))
	var chapter := int(race.trim_prefix("B"))
	return chapter * 5 if Catalog.bosses().has(room_id) else (chapter - 1) * 5 + [1,3,5][clampi(zone_index,0,2)]
