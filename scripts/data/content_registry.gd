class_name ContentRegistry
extends RefCounted
const Progression = preload("res://scripts/core/hero_progression.gd")
const Rules = preload("res://config/numerical_rules.gd")
## Immutable-by-copy static definitions. Combat state and ownership never live here.

const SLOTS: Array[String] = ["weapon", "head", "chest", "hands", "feet", "charm"]
const V2_SLOTS: Array[String] = ["weapon", "head", "chest", "hands", "legs", "feet", "ring", "charm"]
const XP_THRESHOLDS: Array[int] = [0, 30, 70, 120, 170, 230, 290, 360, 630, 900, 1170, 1440, 1710, 1980, 2250, 2520, 2790, 3060, 3330, 3600]
const UPGRADE_COSTS: Array[int] = [60, 100, 160, 240, 340]
const STAT_KEYS: Array[String] = ["attack", "ability_power", "max_hp", "max_mana", "armor", "magic_resist", "armor_penetration", "magic_penetration", "crit_multiplier", "true_damage_bonus", "attack_speed", "move_speed", "crit_chance", "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration"]

static var _heroes: Dictionary = _read_json("res://data/heroes.json")
static var _equipment: Dictionary = _read_json("res://data/equipment.json")
static var _sets: Dictionary = _read_json("res://data/sets.json")
static var _equipment_v2: Dictionary = {}

static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
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
	return catalog.get(id, {}).duplicate(true)

static func equipment_ids(ruleset: int = 1) -> Array:
	var catalog := _v2_equipment() if ruleset == 2 else _equipment
	var ids := catalog.keys()
	ids.sort()
	return ids

static func sets(ruleset: int = 1) -> Dictionary:
	# Fourteen eight-piece sets still use the same 2/4/6 thresholds.
	var result := _sets.duplicate(true)
	if ruleset == 2:
		var materials: Dictionary = Rules.value("shop_set_races", {})
		for set_id: String in materials:
			if result.has(set_id): result[set_id]["race_id"] = str(materials[set_id])
	return result

static func set_item_ids(set_id: String, ruleset: int = 1) -> Array[String]:
	var result: Array[String] = []
	if not _sets.has(set_id): return result
	for slot: String in slots(ruleset):
		for id: String in equipment_ids(ruleset):
			var item := equipment(id, ruleset)
			if str(item.get("set_id", "")) == set_id and str(item.get("slot", "")) == slot:
				result.append(id)
	return result

## Deterministic overlay, never edits the legacy JSON or duplicates fixed effects.
## Original flat stats are audit/tendency data only, not another main-stat layer.
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
			item["race_id"] = str(Rules.value("shop_set_races", {}).get(str(item.get("set_id", "")), ""))
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
				source["race_id"] = str(Rules.value("shop_set_races", {}).get(set_id, ""))
			source.erase("combat_passive")
			source.erase("original_name")
			_equipment_v2[id] = source
	return _equipment_v2

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
	if equipment_ids(2).size() != 124: errors.append("Expected 124 version-two templates.")
	if slots(2).size() != 8: errors.append("Expected eight version-two slots.")
	var general_count := 0
	for number in range(1, 125):
		var id := "EQ%02d" % number
		var item := equipment(id, 2)
		_check_required(item, ["id", "name", "slot", "set_id", "price", "base_stats", "affix_tendencies", "main_coefficient", "unlock_boss"], id, errors)
		if item.is_empty(): continue
		if item.get("id") != id or item.get("slot") not in slots(2): errors.append(id + ": invalid version-two identity/slot.")
		if not item.get("base_stats") is Dictionary or not item.base_stats.is_empty(): errors.append(id + ": legacy attributes must not contribute twice.")
		var is_general := str(item.get("set_id", "")).is_empty()
		if is_general: general_count += 1
		var coefficient := float(Rules.value("starter_template_multiplier")) if is_general else 1.0
		if not _finite_number(item.get("main_coefficient")) or not is_equal_approx(float(item.get("main_coefficient", 0)), coefficient): errors.append(id + ": invalid main coefficient.")
		if number <= 96:
			var old := equipment(id)
			for field in ["name", "race_id", "drop_origin", "shop_only", "price", "unlock_boss", "affix_id", "affix_text", "combat_passive"]:
				if item.get(field) != old.get(field): errors.append(id + ": changed legacy identity/effect " + field)
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
					if item.get(field) != old.get(field): errors.append(id + ": new piece does not inherit " + field)
	if general_count != 12: errors.append("Expected twelve reduced-coefficient general templates.")
	for set_id: String in sets(2):
		var pieces := set_item_ids(set_id, 2)
		if pieces.size() != 8: errors.append(set_id + ": expected eight pieces.")
		for slot: String in slots(2):
			var count := 0
			for id: String in pieces:
				if equipment(id, 2).slot == slot: count += 1
			if count != 1: errors.append(set_id + ": expected one " + slot + " piece.")
		var thresholds: Dictionary = _sets[set_id].get("thresholds", {})
		if thresholds.size() != 3 or not thresholds.has_all(["2", "4", "6"]): errors.append(set_id + ": only 2/4/6 thresholds are allowed.")
	return errors
