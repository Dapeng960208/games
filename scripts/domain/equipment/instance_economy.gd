class_name InstanceEconomy
extends RefCounted
## Canonical V2 creation and rank costs. Gold/materials never use combat_scale.
## Round the complete rational product once, including exact integral boundaries.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const History = preload("res://scripts/domain/equipment/economy_history.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const VERSION := 2
const V3 = preload("res://scripts/domain/equipment/equipment_acquisition_v3.gd")
# Validation snapshots only, never a replacement for the live quote configuration.
# Append a new version when economic inputs change; keep these historical rules.
const V1_SET_RACES := ["B01", "B01", "B02", "B02", "B03", "B03", "B04", "B04", "B01", "B02", "B01", "B02", "B03", "B04"]
const V1_GENERAL_RACES := {"EQ01":"B01", "EQ02":"B02", "EQ11":"B03", "EQ12":"B04", "EQ21":"B01", "EQ22":"B02", "EQ31":"B03", "EQ32":"B04", "EQ41":"B01", "EQ42":"B02", "EQ51":"B03", "EQ52":"B04"}
const V1_FORGE := {"green":{"gold":200, "common":12, "race":6, "core":0}, "purple":{"gold":400, "common":24, "race":12, "core":2}, "gold":{"gold":800, "common":48, "race":24, "core":6}}
const RACES := ["B01", "B02", "B03", "B04", "B05", "B06"]

static func purchase_price(template_id: String, rarity: String, item_level: int) -> int:
	var template := Registry.equipment(template_id, 2)
	var multipliers: Dictionary = Rules.value("shop_price_multiplier")
	if template.is_empty() or rarity not in Rules.value("shop_rarities") or not multipliers.has(rarity): return -1
	var ratio := _fraction(multipliers[rarity])
	return scaled_gold(int(template.price), item_level, ratio[0], ratio[1])

## Frozen on every instance when created, including free/pre-enhanced drops.
static func purchase_baseline_price(template_id: String, rarity: String, item_level: int) -> int:
	if not Rules.value("rarities").has(rarity): return -1
	return purchase_price(template_id, "white" if rarity == "white" else "green", item_level)

static func scaled_gold(base_gold: int, item_level: int, numerator: int = 1, denominator: int = 1) -> int:
	if base_gold < 0 or not valid_item_level(item_level) or numerator < 0 or denominator <= 0: return -1
	var increment := _fraction(Rules.value("cost_item_level_per_level"))
	return ceil_ratio(base_gold * numerator * (increment[1] + increment[0] * (item_level - 1)), denominator * increment[1])

static func enhancement_price(rank: int, item_level: int) -> int:
	var costs: Array = Rules.value("enhancement_gold")
	if rank < 1 or rank > costs.size(): return -1
	return scaled_gold(int(costs[rank - 1]), item_level)

static func enhancement_reroll_price(rank: int, item_level: int) -> int:
	var costs: Array = Rules.value("enhancement_gold")
	if rank < 1 or rank > costs.size(): return -1
	var ratio := _fraction(Rules.value("enhancement_random").reroll_gold_fraction)
	return scaled_gold(int(costs[rank - 1]), item_level, ratio[0], ratio[1])

static func enhancement_materials(rank: int, race_id: String, reroll: bool = false) -> Dictionary:
	if rank < 1 or rank > int(Rules.value("enhancement_max")) or race_id not in RACES: return {}
	var common := int(Rules.value("enhancement_common")[rank - 1])
	var race := int(Rules.value("enhancement_race")[rank - 1])
	var core := int(Rules.value("enhancement_core")[rank - 1])
	if reroll:
		var ratio := _fraction(Rules.value("enhancement_random").reroll_material_fraction)
		common = ceil_ratio(common * ratio[0], ratio[1])
		race = ceil_ratio(race * ratio[0], ratio[1])
		core = int(Rules.value("enhancement_random").reroll_core)
	return material_cost(common, race, core, race_id)

static func material_cost(common: int, race: int, core: int, race_id: String) -> Dictionary:
	if race_id not in RACES or mini(common, mini(race, core)) < 0: return {}
	var result := {}
	if common > 0: result["forge"] = common
	if race > 0: result["race:" + race_id] = race
	if core > 0: result["core:" + race_id] = core
	return result

static func crafting_cost(template_id: String, rarity: String, item_level: int) -> Dictionary:
	var template := Registry.equipment(template_id, 2)
	var costs: Dictionary = Rules.value("forge_costs")
	if template.is_empty() or not costs.has(rarity) or not valid_item_level(item_level): return {}
	var race := str(template.get("race_id", ""))
	if race not in RACES: return {}
	var cost: Dictionary = costs[rarity]
	return {"gold":scaled_gold(int(cost.gold), item_level), "materials":material_cost(int(cost.common), int(cost.race), int(cost.core), race)}

static func crafting_unlock_level(rarity: String) -> int:
	var unlocks: Dictionary = Rules.value("forge_unlock_levels", {"green":5, "purple":10, "gold":15})
	return int(unlocks.get(rarity, -1))

static func completion_price(total_purchase_price: int) -> int:
	if total_purchase_price < 0: return -1
	var ratio := _fraction(Rules.value("set_completion_discount", 0.9))
	return ceil_ratio(total_purchase_price * ratio[0], ratio[1])

static func valid_item_level(item_level: int) -> bool:
	return item_level >= 1 and item_level <= Growth.level_cap()

static func ceil_ratio(numerator: int, denominator: int) -> int:
	if numerator < 0 or denominator <= 0: return -1
	@warning_ignore("integer_division")
	return numerator / denominator + (1 if numerator % denominator != 0 else 0)

static func _fraction(number: Variant) -> Array[int]:
	var text := str(number)
	if not text.contains("."): return [int(number), 1]
	var parts := text.split(".")
	var denominator := 1
	for index in parts[1].length(): denominator *= 10
	return [int(parts[0]) * denominator + int(parts[1]), denominator]

## Independent of future catalog/config edits, like the legacy v1 receipt rules.
static func historical_set_items(set_id: String, version: int = VERSION) -> Array:
	if version not in [1, 2]: return []
	if version >= 2 and set_id in ["B05-SW", "B05-SG", "B05-SM", "B05-SU"]:
		var result: Array = []
		for id: String in V3.TEMPLATES:
			if V3.TEMPLATES[id].set_id == set_id: result.append(id)
		return result
	var pieces := History.set_items(set_id, 1)
	if pieces.is_empty(): return []
	var number := int(set_id.substr(1))
	pieces.append("EQ%02d" % (97 + (number - 1) * 2))
	pieces.append("EQ%02d" % (98 + (number - 1) * 2))
	return pieces

static func historical_purchase_baseline(template_id: String, rarity: String, item_level: int, version: int = VERSION) -> int:
	if version not in [1, 2] or rarity not in ["white", "green", "purple", "gold"] or item_level < 1 or item_level > (20 if version == 1 else V3.LEVEL_CAP): return -1
	var price := int(V3.TEMPLATES[template_id].price) if version >= 2 and V3.TEMPLATES.has(template_id) else History.item_price(template_id, 1)
	var number := int(template_id.substr(2))
	if price < 0 and number >= 97 and number <= 124 and template_id == "EQ%02d" % number:
		price = 180 if (number - 97) % 2 == 0 else 160
	if price < 0: return -1
	return ceil_ratio(price * (8 if rarity == "white" else 12) * (100 + 3 * (item_level - 1)), 1000)

static func historical_creation_cost(request: Dictionary, kind: String, version: int = VERSION) -> Dictionary:
	if version not in [1, 2]: return {}
	var level := int(request.get("item_level", 0))
	var rarity := str(request.get("rarity", ""))
	if level < 1 or level > (20 if version == 1 else V3.LEVEL_CAP): return {}
	if kind == "craft":
		if not V1_FORGE.has(rarity): return {}
		var race_id := _historical_race(str(request.get("template_id", "")), version)
		if race_id.is_empty(): return {}
		var cost: Dictionary = V1_FORGE[rarity]
		return {"gold":ceil_ratio(int(cost.gold) * (100 + 3 * (level - 1)), 100), "materials":material_cost(int(cost.common), int(cost.race), int(cost.core), race_id)}
	if kind not in ["purchase", "complete_set"] or rarity not in ["white", "green"]: return {}
	var templates: Array = request.get("template_ids", []) if kind == "complete_set" else [request.get("template_id", "")]
	var total := 0
	for template_id: String in templates:
		var price := historical_purchase_baseline(template_id, rarity, level, version)
		if price < 0: return {}
		total += price
	return {"gold":ceil_ratio(total * 9, 10) if kind == "complete_set" else total, "materials":{}}

static func _historical_race(template_id: String, version: int = VERSION) -> String:
	if version >= 2 and V3.TEMPLATES.has(template_id): return "B05"
	var number := int(template_id.substr(2))
	if number < 1 or number > 124 or template_id != "EQ%02d" % number: return ""
	if number <= 60:
		var offset := (number - 1) % 10
		if offset < 2: return V1_GENERAL_RACES[template_id]
		return V1_SET_RACES[offset - 2]
	if number <= 96:
		@warning_ignore("integer_division")
		return V1_SET_RACES[8 + (number - 61) / 6]
	@warning_ignore("integer_division")
	return V1_SET_RACES[(number - 97) / 2]
