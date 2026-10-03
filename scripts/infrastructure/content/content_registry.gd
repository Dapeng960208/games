class_name ContentRegistry
extends RefCounted
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
const ClassPolicy = preload("res://scripts/domain/equipment/equipment_class_policy.gd")
const B05Catalog = preload("res://scripts/levels/b05/equipment/equipment_catalog.gd")
const B10Catalog = preload("res://scripts/levels/b10/equipment/equipment_catalog.gd")
const B09Catalog = preload("res://scripts/levels/b09/equipment/equipment_catalog.gd")
const B06Catalog = preload("res://scripts/levels/b06/equipment/equipment_catalog.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
## Immutable-by-copy static definitions. Combat state and ownership never live here.

const SLOTS: Array[String] = ["weapon", "head", "chest", "hands", "feet", "charm"]
const V2_SLOTS: Array[String] = ["weapon", "head", "chest", "hands", "legs", "feet", "ring", "charm"]
const XP_THRESHOLDS: Array[int] = [0, 30, 70, 120, 170, 230, 290, 360, 630, 900, 1170, 1440, 1710, 1980, 2250, 2520, 2790, 3060, 3330, 3600]
const UPGRADE_COSTS: Array[int] = [60, 100, 160, 240, 340]
const STAT_KEYS: Array[String] = ["attack", "ability_power", "max_hp", "max_mana", "armor", "magic_resist", "armor_penetration", "magic_penetration", "crit_multiplier", "true_damage_bonus", "attack_speed", "move_speed", "crit_chance", "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration"]

const B05_SET_TEXT := {
 "B05-SW":{"2":["铁壁战吼生成护盾量+12%","Ironwall Cry shield amount +12%"],"4":["铁壁战吼护盾实际吸收后，下一次裂地重斩追加0.30P短弧，最多3目标；6秒冷却","After Ironwall Cry absorbs damage, next Earthsplit Cleave adds a 0.30P short arc, up to 3 targets; 6s ICD"],"6":["8秒内裂地重斩三次命中：铁壁战吼冷却-1.5秒，下一次破阵冲锋伤害+10%持续6秒；8秒冷却","Three Earthsplit Cleave hits in 8s reduce Ironwall Cry cooldown by 1.5s and empower next Breach Charge by 10% for 6s; 8s ICD"]},
 "B05-SG":{"2":["持有强化普攻弹时，原始直接伤害+8%","Original direct damage +8% while empowered basic rounds are available"],"4":["持有强化弹时磁轨贯穿有效命中，额外贯穿180距离内一个后方目标，0.35P；每次施法一次","Magnetic Piercer hitting while empowered rounds are available pierces one extra target behind within 180 for 0.35P; once per cast"],"6":["游击撤射实际移动100后，下一次磁轨贯穿主目标伤害+12%持续6秒；6秒冷却","After Skirmish Retreat moves 100, next Magnetic Piercer primary hit +12% for 6s; 6s ICD"]},
 "B05-SM":{"2":["星铃飞弹直接伤害+8%","Starbell Missile direct damage +8%"],"4":["6秒内三次相邻技能身份不同的付费施法且消耗至少60法力，回复60；6秒冷却","Three paid casts with alternating skill identities in 6s spending at least 60 mana restore 60; 6s ICD"],"6":["星灵跃击首次实际释放1秒后，落点星环半径110、0.40P、最多3目标；8秒冷却，每次施法一次","1s after Starspirit Leap's first actual release, a radius-110 ring adds 0.40P to up to 3 targets at its release point; 8s ICD, once per cast"]},
 "B05-SU":{"2":["根缚与减速持续时间-20%，同类合计上限50%","Root and slow durations -20%; combined reduction capped at 50%"],"4":["走出敌方持续危险区且1秒未受该区伤害，获6%生命盾4秒；12秒冷却","Exit a hostile persistent zone and avoid its damage for 1s: 6% HP shield for 4s; 12s ICD"],"6":["三次独立直接伤害后回复3%生命并移速+8%持续3秒；12秒冷却","Three independent direct hits restore 3% HP and grant +8% speed for 3s; 12s ICD"]}
}

const B06_SET_TEXT := {
 "B06-SW":{"2":["铁壁战吼护盾存在时受强制位移距离-25%，同类上限50%","While Ironwall Cry's shield exists, forced movement distance -25%; combined cap 50%"],"4":["铁壁战吼后4秒内首次裂地重斩有效命中，返还该次实际怒气消耗15%；冷却8秒","First Earthsplit Cleave hit within 4s after Ironwall Cry refunds 15% of its actual Rage cost; 8s ICD"],"6":["护盾实承伤后6秒内，下一次破阵冲锋或裂地重斩实命中追加前方120范围0.40P波，最多3目标；冷却8秒","After shield absorption, next Breach Charge or Earthsplit Cleave hit within 6s adds a forward 120-range 0.40P wave, up to 3 targets; 8s ICD"]},
 "B06-SG":{"2":["磁轨贯穿主目标伤害+8%","Magnetic Piercer primary target damage +8%"],"4":["游击撤射真实转位后4秒内，持有强化弹时首次磁轨贯穿命中，震爆榴弹剩余冷却-1秒；冷却7秒","First Magnetic Piercer hit with empowered rounds within 4s after real Skirmish Retreat movement reduces Shock Grenade cooldown by 1s; 7s ICD"],"6":["磁轨贯穿实穿透2敌，保留主目标6秒；下一次火力倾泻实际前3发命中该目标各追加0.12P；冷却12秒","Magnetic Piercer crossing 2 enemies reserves its primary target for 6s; next Firepower Burst's first 3 fired rounds add 0.12P only on that target; 12s ICD"]},
 "B06-SM":{"2":["星灵跃击即时星爆半径+10%","Starspirit Leap's immediate burst radius +10%"],"4":["星环守护实际命中后6秒内，下一次星灵跃击即时伤害+12%；冷却8秒","Starhalo Guard hit empowers the next immediate Starspirit Leap burst by 12% within 6s; 8s ICD"],"6":["3次成功付费星铃飞弹后，下一次星灵跃击0.8秒后追加半径110、0.45P星环，最多4目标；冷却10秒","After 3 paid Starbell Missile casts, next Starspirit Leap adds a radius-110 0.45P ring after 0.8s, up to 4 targets; 10s ICD"]},
 "B06-SU":{"2":["受到强制位移距离-20%，同类上限50%","Forced movement distance -20%; combined cap 50%"],"4":["战斗每12秒获6%生命盾4秒；进房不免费刷新，换装不重置周期","Every 12s in combat: 6% HP shield for 4s; entry and swaps do not reset cadence"],"6":["六件装备取向一致时，本套盾自然消失或击破后6秒内下一次直接命中追加0.25P，移速+8%3秒；冷却12秒","With six pieces sharing one power type, after this set shield expires or breaks: next direct hit within 6s adds 0.25P and +8% speed for 3s; 12s ICD"]}
}
const B06_UNIQUE_TEXT := {
 "B06-U01":["地形减速幅度-20%，同类上限50%；不减潮推距离","Terrain slow magnitude -20%, combined cap 50%; does not reduce tide push"],
 "B06-U02":["自身护盾实承伤后受治疗+8%4秒；冷却12秒","After own shield absorbs damage: received healing +8% for 4s; 12s ICD"],
 "B06-U03":["完成战斗机关交互后获4%生命盾3秒；冷却15秒","Complete a combat mechanism interaction: 4% HP shield for 3s; 15s ICD"]
}

const B10_SET_TEXT := {
 "B10-SW":{"2":["Q直接伤害+8%","Q direct damage +8%"],"4":["4秒内Q→W命中同敌获得星誓，最多2层，持续8秒；每次施法一次","Q then W hitting the same enemy within 4s grants a Star Oath, max 2 for 8s; once per cast"],"6":["E提交消耗星誓：下次W每层伤害+8%、命中获每层3%生命盾4秒；窗口6秒，冷却12秒","E consumes Star Oaths: next W +8% damage and 3% HP shield for 4s per stack; 6s window, 12s ICD"]},
 "B10-SG":{"2":["W主目标伤害+8%","W primary target damage +8%"],"4":["E命中留下6秒彗轨印，下次W命中追加0.30P；冷却8秒","E marks a target for 6s; next W adds 0.30P; 8s ICD"],"6":["8秒内Q真实转位、E与W命中同敌，下次R实发前3弹对其各追加0.18P；窗口6秒，冷却12秒","Real Q movement then E and W hits on one target within 8s: next R first 3 fired rounds add 0.18P against it; 6s window, 12s ICD"]},
 "B10-SM":{"2":["Q直接伤害+8%","Q direct damage +8%"],"4":["8秒内付费施放三种技能且总实耗>80，回复80法力；冷却10秒","Three different paid spells within 8s spending more than 80 mana restore 80; 10s ICD"],"6":["同一三技能事件后，下次Q或R首段追加0.60P星环，最多3目标并共享派生伤害预算；窗口6秒，冷却12秒","After the same three-spell event, next Q or R first segment adds a 0.60P star burst to up to 3 targets within the shared derived-damage budget; 6s window, 12s ICD"]},
 "B10-SU":{"2":["受到远程直接伤害-6%","Ranged direct damage received -6%"],"4":["自身护盾被实际伤害击破后，下个付费技能成本-8%；窗口6秒，冷却12秒","After own shield breaks from real damage: next paid skill costs 8% less; 6s window, 12s ICD"],"6":["10秒内真实移动160、直接命中、技能成功提交，获直接减伤8%及移速8%4秒；冷却12秒","Move 160, land a direct hit and commit a skill within 10s: direct damage reduction and speed +8% for 4s; 12s ICD"]}
}
const B10_UNIQUE_TEXT := {
 "B10-U01":["普通减速结束后下一次闪避剩余冷却-0.5秒；冷却12秒","After an ordinary slow ends: next dash cooldown -0.5s; 12s ICD"],
 "B10-U02":["自己击破敌盾或供能机关后获3%最大生命盾4秒；冷却12秒","Break an enemy shield or power mechanism: 3% max HP shield for 4s; 12s ICD"],
 "B10-U03":["从敌方普通位移恢复后直接减伤6%4秒；冷却15秒","Recover from ordinary enemy forced movement: direct damage received -6% for 4s; 15s ICD"]
}

static var _heroes: Dictionary = _read_json("res://data/characters/heroes.json")
static var _equipment: Dictionary = _read_json("res://data/equipment/equipment.json")
static var _sets: Dictionary = _read_json("res://data/equipment/sets.json")
static var _equipment_v2: Dictionary = {}

static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(AssetCatalog.resolve(path), FileAccess.READ)
	if file == null:
		push_error("Cannot read content definitions: " + path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		push_error("Invalid content JSON: " + path + ": " + parser.get_error_message())
		return {}
	return parser.data

static func hero(id: String) -> Dictionary:
	return _heroes.get(id, {}).duplicate(true)

static func heroes() -> Array:
	var ids := _heroes.keys()
	ids.sort()
	return ids

## Defaults stay frozen to the six-slot catalog for legacy adventures.
static func slots(ruleset: int = 1) -> Array[String]:
	return V2_SLOTS.duplicate() if ruleset == 2 else SLOTS.duplicate()

static func equipment(id: String, ruleset: int = 1) -> Dictionary:
	var catalog := _v2_equipment() if ruleset == 2 else _equipment
	if id.begins_with("B09-") and not Rules.b09_candidate_enabled(): return {}
	if id.begins_with("B10-") and not Rules.chapter_enabled("B10"): return {}
	var result: Dictionary = catalog.get(id, {}).duplicate(true)
	if ruleset == 2 and not result.is_empty():
		result["allowed_heroes"] = ClassPolicy.allowed_heroes(str(result.get("set_id", "")))
		result["class_policy_version"] = ClassPolicy.template_policy_version(id)
	return result

static func equipment_ids(ruleset: int = 1) -> Array:
	var catalog := _v2_equipment() if ruleset == 2 else _equipment
	var ids := catalog.keys()
	# Registration is available for isolated checks before the chapter release gate.
	if ruleset == 2 and int(Rules.value("implemented_chapters", 4)) < 5:
		ids = ids.filter(func(id: String) -> bool: return not id.begins_with("B05-"))
	if ruleset == 2 and int(Rules.value("implemented_chapters",4)) < 6:
		ids = ids.filter(func(id: String) -> bool: return not id.begins_with("B06-"))
	if ruleset == 2 and not Rules.chapter_enabled("B10"):
		ids = ids.filter(func(id: String) -> bool: return not id.begins_with("B10-"))
	if ruleset == 2 and not Rules.b09_candidate_enabled(): ids = ids.filter(func(id: String) -> bool: return not id.begins_with("B09-"))
	ids.sort()
	return ids

static func sets(ruleset: int = 1) -> Dictionary:
	# Fourteen eight-piece sets still use the same 2/4/6 thresholds.
	var result := _sets.duplicate(true)
	if ruleset == 2:
		for set_id: String in result:
			result[set_id]["allowed_heroes"] = ClassPolicy.allowed_heroes(set_id)
			result[set_id]["class_policy_version"] = ClassPolicy.VERSION
			# Versioned set copy keeps frozen legacy adventures and their text intact.
			for threshold: Dictionary in result[set_id].get("thresholds", {}).values():
				for field: String in ["text", "text_en"]:
					var versioned := "text_v2_en" if field == "text_en" else "text_v2"
					if threshold.has(versioned): threshold[field] = threshold[versioned]
		if int(Rules.value("implemented_chapters", 4)) >= 5:
			for set_id: String in B05Catalog.sets(): result[set_id] = _b05_set(set_id)
		if int(Rules.value("implemented_chapters",4)) >= 6:
			for set_id: String in B06Catalog.sets(): result[set_id] = _b06_set(set_id)
		if Rules.chapter_enabled("B10"):
			for set_id: String in B10Catalog.sets(): result[set_id] = _b10_set(set_id)
		if Rules.b09_candidate_enabled():
			for set_id: String in B09Catalog.sets():
				var definition: Dictionary = B09Catalog.sets()[set_id]
				definition.merge({"race_id":"B09", "class_policy_version":4})
				for tier: Dictionary in definition.thresholds.values():
					tier["text"] = " ".join(tier.conditions)
					tier["text_en"] = tier.text
				result[set_id] = definition
		var materials: Dictionary = Rules.value("shop_set_races", {})
		for set_id: String in materials:
			if result.has(set_id): result[set_id]["race_id"] = str(materials[set_id])
	return result

static func set_item_ids(set_id: String, ruleset: int = 1) -> Array[String]:
	var result: Array[String] = []
	if not sets(ruleset).has(set_id): return result
	for slot: String in slots(ruleset):
		for id: String in equipment_ids(ruleset):
			var item := equipment(id, ruleset)
			if str(item.get("set_id", "")) == set_id and str(item.get("slot", "")) == slot:
				result.append(id)
	return result

## Deterministic overlay, never edits the legacy JSON or duplicates fixed effects.
## Original flat stats are audit/tendency data only, not another main-stat layer.
static func _v2_race(item: Dictionary) -> Variant:
	if not item.has("race_id") and bool(item.get("shop_only", false)):
		return Rules.value("shop_set_races", {}).get(str(item.get("set_id", "")), "")
	return item.get("race_id")

static func _v2_equipment() -> Dictionary:
	if not _equipment_v2.is_empty(): return _equipment_v2
	for id: String in _equipment:
		var item: Dictionary = _equipment[id].duplicate(true)
		item["legacy_base_stats"] = item.base_stats.duplicate(true)
		item["affix_tendencies"] = item.base_stats.keys()
		item["base_stats"] = {}
		item["base_stat_text"] = "属性由装备实例决定"
		item["base_stat_text_en"] = "Stats are determined by the equipment instance"
		item["description"] = str(item.get("affix_text", ""))
		item["description_en"] = str(item.get("affix_text_en", ""))
		item["main_coefficient"] = float(Rules.value("starter_template_multiplier")) if str(item.get("set_id", "")).is_empty() else 1.0
		item["ruleset_version"] = 2
		if not item.has("race_id") and bool(item.get("shop_only", false)):
			item["race_id"] = _v2_race(item)
		_equipment_v2[id] = item
	for number in range(1, 15):
		var set_id := "S%02d" % number
		var definition: Dictionary = _sets[set_id]
		for offset in range(2):
			var slot := "legs" if offset == 0 else "ring"
			var source_slot := "chest" if offset == 0 else "charm"
			var source: Dictionary = {}
			for old_id: String in _equipment:
				if _equipment[old_id].get("set_id") == set_id and _equipment[old_id].get("slot") == source_slot:
					source = _equipment[old_id].duplicate(true)
					break
			var id := "EQ%02d" % (97 + (number - 1) * 2 + offset)
			source["id"] = id
			source["slot"] = slot
			source["name"] = str(definition.name) + ("护腿" if offset == 0 else "指环")
			source["name_en"] = str(definition.get("name_en", set_id)) + (" Legguards" if offset == 0 else " Ring")
			source["description"] = "主属性、随机词条与套装计数；无额外固定触发效果"
			source["description_en"] = "Main stats, random affixes and set membership; no additional fixed trigger"
			source["base_stats"] = {}
			source["legacy_base_stats"] = {}
			source["base_stat_text"] = "属性由装备实例决定"
			source["base_stat_text_en"] = "Stats are determined by the equipment instance"
			source["affix_tendencies"] = ["max_hp", "armor", "magic_resist"] if offset == 0 else ["damage_bonus", "crit_chance"]
			source["main_coefficient"] = 1.0
			source["affix_id"] = ""
			source["affix_text"] = ""
			source["affix_text_en"] = ""
			source["ruleset_version"] = 2
			if not source.has("race_id") and bool(source.get("shop_only", false)):
				source["race_id"] = _v2_race(source)
			source.erase("combat_passive")
			source.erase("original_name")
			_equipment_v2[id] = source
	for id: String in B05Catalog.equipment_ids():
		var item := B05Catalog.equipment(id)
		item["drop_origin"] = "B05"
		item["affix_tendencies"] = item.affix_tendencies_by_power[item.power_types[0]].duplicate()
		item["description"] = "繁花树庭装备；共有装备的属性取向在获得时固定，换职业不转换属性"
		item["description_en"] = "Blooming Tree Court gear; shared items keep their acquired power type across classes"
		item["base_stat_text"] = "属性由装备实例决定"
		item["base_stat_text_en"] = "Stats are determined by the equipment instance"
		item["affix_id"] = ""
		item["affix_text"] = ""
		item["affix_text_en"] = ""
		var unique_text := {
			"B05-U01":["实际根缚结束后移速+10%持续2秒；10秒冷却", "After an actual root ends: +10% speed for 2s; 10s ICD"],
			"B05-U02":["实际受到外来治疗后获得2%最大生命盾3秒；12秒冷却，过量治疗不计", "After actual external healing: 2% max HP shield for 3s; 12s ICD; overheal excluded"],
			"B05-U03":["摧毁敌方机关后减伤5%持续4秒；12秒冷却", "Destroy a hostile mechanism: 5% damage reduction for 4s; 12s ICD"]}
		if unique_text.has(id):
			item["affix_text"] = unique_text[id][0]
			item["affix_text_en"] = unique_text[id][1]
		item["runtime_implemented"] = true
		_equipment_v2[id] = item
	for id: String in B06Catalog.equipment_ids():
		var item := B06Catalog.equipment(id)
		item["drop_origin"] = "B06"
		item["class_policy_version"] = 3
		item["affix_tendencies"] = item.affix_tendencies_by_power[item.power_types[0]].duplicate()
		item["description"] = "琉潮珊城装备；共有装备保留获得时的属性取向，换职业不转换属性"
		item["description_en"] = "Tidal Coral City gear; shared items keep their acquired power type across classes"
		item["base_stat_text"] = "属性由装备实例决定"
		item["base_stat_text_en"] = "Stats are determined by the equipment instance"
		item["affix_id"] = ""
		item["affix_text"] = B06_UNIQUE_TEXT.get(id, ["", ""])[0]
		item["affix_text_en"] = B06_UNIQUE_TEXT.get(id, ["", ""])[1]
		item["runtime_implemented"] = true
		if not item.unique_effect.is_empty(): item.unique_effect["runtime_implemented"] = true
		_equipment_v2[id] = item
	for id: String in B10Catalog.equipment_ids():
		var item := B10Catalog.equipment(id)
		item["drop_origin"] = "B10"
		item["class_policy_version"] = ClassPolicy.B10_VERSION
		item["affix_tendencies"] = item.affix_tendencies_by_power[item.power_types[0]].duplicate()
		item["description"] = "星辉龙庭终章装备；共有实例获得时固定物理/魔法取向"
		item["description_en"] = "Star Dragon Court finale gear; shared instances retain their acquired physical or magical orientation"
		item["base_stat_text"] = "属性由装备实例决定"
		item["base_stat_text_en"] = "Stats are determined by the equipment instance"
		item["affix_id"] = ""
		item["affix_text"] = B10_UNIQUE_TEXT.get(id, ["", ""])[0]
		item["affix_text_en"] = B10_UNIQUE_TEXT.get(id, ["", ""])[1]
		item["runtime_implemented"] = true
		_equipment_v2[id] = item
	for id: String in B09Catalog.equipment_ids():
		var item := B09Catalog.equipment(id)
		item.merge({"drop_origin":"B09", "class_policy_version":4, "description":"霜晶王庭候选装备；固定取向、属性与效果由真实装备实例解析", "description_en":"Crystal Court candidate gear; instance stats and combat effects", "base_stat_text":"属性由装备实例决定", "base_stat_text_en":"Stats are determined by the equipment instance", "affix_id":"", "affix_text":"", "affix_text_en":""})
		item["affix_tendencies"] = item.affix_tendencies_by_power[item.power_types[0]].duplicate()
		if not item.unique_effect.is_empty():
			item["affix_text"] = " ".join(item.unique_effect.conditions)
			item["affix_text_en"] = item.affix_text
		_equipment_v2[id] = item
	return _equipment_v2

static func _b10_set(set_id: String) -> Dictionary:
	var result: Dictionary = B10Catalog.sets().get(set_id, {}).duplicate(true)
	if result.is_empty(): return result
	result["race_id"] = "B10"
	result["class_policy_version"] = ClassPolicy.B10_VERSION
	for tier: String in result.thresholds:
		result.thresholds[tier]["name"] = result.name + " " + tier
		result.thresholds[tier]["text"] = B10_SET_TEXT[set_id][tier][0]
		result.thresholds[tier]["text_en"] = B10_SET_TEXT[set_id][tier][1]
	return result

static func _b06_set(set_id: String) -> Dictionary:
	var result: Dictionary = B06Catalog.sets().get(set_id,{}).duplicate(true)
	if result.is_empty(): return result
	result["race_id"] = "B06"
	result["class_policy_version"] = 3
	result["runtime_implemented"] = true
	for tier: String in result.thresholds:
		result.thresholds[tier]["name"] = result.name+" "+tier
		result.thresholds[tier]["text"] = B06_SET_TEXT[set_id][tier][0]
		result.thresholds[tier]["runtime_implemented"] = true
		result.thresholds[tier]["text_en"] = B06_SET_TEXT[set_id][tier][1]
	return result

static func _b05_set(set_id: String) -> Dictionary:
	var result: Dictionary = B05Catalog.sets().get(set_id, {}).duplicate(true)
	if result.is_empty(): return result
	result["race_id"] = "B05"
	result["class_policy_version"] = ClassPolicy.B05_VERSION
	result["runtime_implemented"] = true
	for tier: String in result.thresholds:
		result.thresholds[tier]["runtime_implemented"] = true
		var text: Array = B05_SET_TEXT[set_id][tier]
		result.thresholds[tier]["text"] = text[0]
		result.thresholds[tier]["text_en"] = text[1]
	return result

static func level_for_xp(xp: int, ruleset: int = 1) -> int:
	if ruleset == 2: return Progression.level_for_xp(xp)
	var level := 1
	for index in range(1, XP_THRESHOLDS.size()):
		if xp < XP_THRESHOLDS[index]:
			break
		level = index + 1
	return level

## Cumulative XP target, not XP remaining. Max-level target stays at the cap.
static func next_level_xp(level: int, ruleset: int = 1) -> int:
	if ruleset == 2:
		var values := Progression.thresholds()
		return int(values[clampi(level, 1, values.size() - 1)])
	return XP_THRESHOLDS[clampi(level, 1, XP_THRESHOLDS.size() - 1)]

static func validate(ruleset: int = 1) -> Array[String]:
	if ruleset == 2: return _validate_v2()
	var errors: Array[String] = []
	if _heroes.size() != 3:
		errors.append("Expected exactly three heroes.")
	for hero_number in range(1, 4):
		var id := "CH%02d" % hero_number
		var definition := hero(id)
		_check_required(definition, ["id", "name", "title", "class_name", "resource_type", "resource_name", "color", "max_hp", "armor", "attack", "attack_interval", "range", "move_speed", "resource_max", "resource_regen", "starting_resource", "skills"], id, errors)
		if definition.is_empty():
			continue
		if definition.get("id") != id:
			errors.append(id + ": ID does not match its registry key.")
		if definition.get("resource_type") != ["rage", "energy", "mana"][hero_number - 1]:
			errors.append(id + ": unexpected resource type.")
		for key in ["max_hp", "attack", "attack_interval", "range", "move_speed", "resource_max"]:
			if not _finite_number(definition.get(key)) or float(definition.get(key, 0)) <= 0:
				errors.append(id + ": invalid positive attribute " + key)
		for key in ["armor", "resource_regen", "starting_resource"]:
			if not _finite_number(definition.get(key)) or float(definition.get(key, -1)) < 0:
				errors.append(id + ": invalid nonnegative attribute " + key)
		if float(definition.get("starting_resource", 0)) > float(definition.get("resource_max", 0)):
			errors.append(id + ": initial resource exceeds capacity.")
		var skills: Dictionary = definition.get("skills", {}) if definition.get("skills") is Dictionary else {}
		if skills.size() != 4:
			errors.append(id + ": expected four active skills.")
		var index := 0
		for slot in ["q", "secondary", "f", "ultimate"]:
			var skill: Dictionary = skills.get(slot, {}) if skills.get(slot, {}) is Dictionary else {}
			_check_required(skill, ["name", "unlock", "cost", "cooldown", "description"], id + "/" + slot, errors)
			if int(skill.get("unlock", 0)) != [1, 2, 3, 4][index]:
				errors.append(id + "/" + slot + ": invalid unlock level.")
			if not _finite_number(skill.get("cost")) or float(skill.get("cost", -1)) < 0:
				errors.append(id + "/" + slot + ": invalid resource cost.")
			if not _finite_number(skill.get("cooldown")) or float(skill.get("cooldown", 0)) <= 0:
				errors.append(id + "/" + slot + ": invalid cooldown.")
			index += 1
	if _equipment.size() != 96:
		errors.append("Expected ninety-six equipment definitions.")
	var set_slots: Dictionary = {}
	var price_total := 0
	for number in range(1, 61):
		var id := "EQ%02d" % number
		var definition := equipment(id)
		_check_required(definition, ["id", "name", "description", "slot", "set_id", "price", "base_stats", "affix_id", "affix_text", "unlock_boss"], id, errors)
		if definition.is_empty():
			continue
		if definition.get("id") != id:
			errors.append(id + ": ID does not match its registry key.")
		var slot_index := int((number - 1) / 10)
		var position := (number - 1) % 10
		if definition.get("slot") != SLOTS[slot_index]:
			errors.append(id + ": invalid equipment slot.")
		var set_id := "" if position < 2 else "S%02d" % (position - 1)
		if definition.get("set_id") != set_id:
			errors.append(id + ": incorrect set membership.")
		var expected_price: int = [60, 100][position] if position < 2 else [180, 140, 180, 120, 120, 160][slot_index]
		if not _finite_number(definition.get("price")) or float(definition.get("price", 0)) != expected_price:
			errors.append(id + ": incorrect purchase price.")
		price_total += int(definition.get("price", 0))
		var boss := ""
		if set_id in ["S02", "S05"]:
			boss = "BO01"
		elif set_id in ["S03", "S07"]:
			boss = "BO02"
		elif set_id in ["S04", "S08"]:
			boss = "BO03"
		if definition.get("unlock_boss") != boss:
			errors.append(id + ": incorrect catalog milestone.")
		var stats: Dictionary = definition.get("base_stats", {}) if definition.get("base_stats") is Dictionary else {}
		if stats.is_empty() or stats.size() > 4:
			errors.append(id + ": expected one to four upgradeable base attributes.")
		for key in stats:
			if key not in STAT_KEYS or not _finite_number(stats[key]) or float(stats[key]) <= 0:
				errors.append(id + ": invalid base attribute " + str(key))
		if not set_id.is_empty():
			if not set_slots.has(set_id):
				set_slots[set_id] = []
			set_slots[set_id].append(definition.get("slot"))
	if price_total != 8160:
		errors.append("The complete equipment catalog must cost 8160 gold.")
	for number in range(61, 97):
		var id := "EQ%02d" % number
		var item := equipment(id)
		_check_required(item, ["id", "name", "name_en", "description", "slot", "set_id", "price", "base_stats", "affix_id", "affix_text", "unlock_boss", "combat_passive"], id, errors)
		var slot: String = SLOTS[(number - 61) % 6]
		var set_id := "S%02d" % (9 + (number - 61) / 6)
		if item.get("id") != id or item.get("slot") != slot or item.get("set_id") != set_id:
			errors.append(id + ": invalid new set identity or slot.")
		if not _finite_number(item.get("price")) or int(item.get("price", 0)) != [180,140,180,120,120,160][(number - 61) % 6] or item.get("unlock_boss") != "":
			errors.append(id + ": invalid new shop price or unlock.")
		var stats: Dictionary = item.get("base_stats", {})
		if stats.is_empty() or stats.size() > 4: errors.append(id + ": invalid base attributes.")
		for key: String in stats:
			if not key in STAT_KEYS or not _finite_number(stats[key]) or float(stats[key]) <= 0:
				errors.append(id + ": invalid attribute " + key)
		var passive: Dictionary = item.get("combat_passive", {})
		if not passive.get("condition") in ["shielded", "moving", "resource_half", "full_hp", "injured", "low_hp"] or not passive.get("stat") in ["damage_bonus", "slow_resistance", "damage_reduction_bonus", "attack_speed_bonus", "move_speed_bonus", "crit_bonus"] or not _finite_number(passive.get("amount")) or float(passive.get("amount", 0)) <= 0 or float(passive.get("amount", 1)) > 0.10:
			errors.append(id + ": invalid conditional passive.")
		if not set_slots.has(set_id): set_slots[set_id] = []
		set_slots[set_id].append(slot)
	if _sets.size() != 14:
		errors.append("Expected fourteen sets.")
	for number in range(1, 15):
		var id := "S%02d" % number
		var definition: Dictionary = _sets.get(id, {})
		_check_required(definition, ["id", "name", "thresholds"], id, errors)
		if definition.get("id") != id:
			errors.append(id + ": ID does not match its registry key.")
		var slots: Array = set_slots.get(id, [])
		if slots.size() != 6:
			errors.append(id + ": expected exactly six equipment pieces.")
		for slot in SLOTS:
			if slots.count(slot) != 1:
				errors.append(id + ": expected exactly one " + slot + " piece.")
		var thresholds: Dictionary = definition.get("thresholds", {}) if definition.get("thresholds") is Dictionary else {}
		if thresholds.size() != 3:
			errors.append(id + ": expected two/four/six-piece thresholds.")
		for count in ["2", "4", "6"]:
			var effect: Dictionary = thresholds.get(count, {}) if thresholds.get(count, {}) is Dictionary else {}
			_check_required(effect, ["name", "text"], id + "/" + count, errors)
	return errors

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _check_required(definition: Dictionary, fields: Array, label: String, errors: Array[String]) -> void:
	for field in fields:
		if not definition.has(field):
			errors.append(label + ": missing " + str(field))

static func _validate_v2() -> Array[String]:
	var errors: Array[String] = []
	var b05_released := int(Rules.value("implemented_chapters", 4)) >= 5
	if equipment_ids(2).size() != ((194 if int(Rules.value("implemented_chapters",4))>=6 else 159 if b05_released else 124) + (35 if Rules.b09_candidate_enabled() else 0) + (35 if Rules.chapter_enabled("B10") else 0)): errors.append("Unexpected version-two template count.")
	errors.append_array(B05Catalog.validate())
	errors.append_array(B06Catalog.validate())
	errors.append_array(B10Catalog.validate())
	errors.append_array(B09Catalog.validate())
	if slots(2).size() != 8: errors.append("Expected eight version-two slots.")
	var general_count := 0
	for number in range(1, 125):
		var id := "EQ%02d" % number
		var item := equipment(id, 2)
		_check_required(item, ["id", "name", "slot", "set_id", "price", "base_stats", "affix_tendencies", "main_coefficient", "unlock_boss"], id, errors)
		if item.is_empty(): continue
		if item.get("id") != id or item.get("slot") not in slots(2): errors.append(id + ": invalid version-two identity/slot.")
		if (item.has("race_id") or bool(item.get("shop_only", false))) and item.get("race_id") not in ["B01", "B02", "B03", "B04"]: errors.append(id + ": invalid version-two race.")
		if not item.get("base_stats") is Dictionary or not item.base_stats.is_empty(): errors.append(id + ": legacy attributes must not contribute twice.")
		var is_general := str(item.get("set_id", "")).is_empty()
		if is_general: general_count += 1
		var coefficient := float(Rules.value("starter_template_multiplier")) if is_general else 1.0
		if not _finite_number(item.get("main_coefficient")) or not is_equal_approx(float(item.get("main_coefficient", 0)), coefficient): errors.append(id + ": invalid main coefficient.")
		if number <= 96:
			var old := equipment(id)
			for field in ["name", "race_id", "drop_origin", "shop_only", "price", "unlock_boss", "affix_id", "affix_text", "combat_passive"]:
				var expected: Variant = _v2_race(old) if field == "race_id" else old.get(field)
				if item.get(field) != expected: errors.append(id + ": changed legacy identity/effect " + field)
			if item.get("legacy_base_stats") != old.base_stats or item.get("affix_tendencies") != old.base_stats.keys(): errors.append(id + ": lost legacy stat tendencies.")
		else:
			var set_id := "S%02d" % (1 + int((number - 97) / 2))
			var slot := "legs" if (number - 97) % 2 == 0 else "ring"
			if item.get("set_id") != set_id or item.get("slot") != slot: errors.append(id + ": wrong new set/slot order.")
			if not str(item.get("affix_id", "")).is_empty() or item.has("combat_passive"): errors.append(id + ": new pieces cannot duplicate a fixed trigger.")
			for old_id: String in set_item_ids(set_id):
				var old := equipment(old_id)
				if old.slot != ("chest" if slot == "legs" else "charm"): continue
				for field in ["race_id", "drop_origin", "shop_only", "price", "unlock_boss"]:
					var expected: Variant = _v2_race(old) if field == "race_id" else old.get(field)
					if item.get(field) != expected: errors.append(id + ": new piece does not inherit " + field)
	if general_count != 12: errors.append("Expected twelve reduced-coefficient general templates.")
	for set_id: String in sets(2):
		var pieces := set_item_ids(set_id, 2)
		if pieces.size() != 8: errors.append(set_id + ": expected eight pieces.")
		for slot: String in slots(2):
			var count := 0
			for id: String in pieces:
				if equipment(id, 2).slot == slot: count += 1
			if count != 1: errors.append(set_id + ": expected one " + slot + " piece.")
		var thresholds: Dictionary = sets(2)[set_id].get("thresholds", {})
		if thresholds.size() != 3 or not thresholds.has_all(["2", "4", "6"]): errors.append(set_id + ": only 2/4/6 thresholds are allowed.")
	return errors
