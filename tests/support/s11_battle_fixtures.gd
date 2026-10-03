extends RefCounted
## Frozen S11 value fixtures. No RNG, battle commands, profile access or writes.
## Owning these legal items is assumed; this is not a crafting/unlock simulation.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")

const VERSION := "s11-boss-fixtures-v1"
const SPECIFICATION := "docs/system/balance/boss_difficulty_calibration.md"
const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const SAMPLES: Array[String] = ["G2", "P5", "G0", "mixed", "green", "white", "lowG2"]
const SLOTS: Array[String] = ["weapon", "head", "chest", "hands", "legs", "feet", "ring", "charm"]
const SEEDS: Array[int] = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010]
const OFFENSIVE_SLOTS: Array[String] = ["weapon", "hands", "ring", "charm"]
const SETS_BY_CHAPTER := {
	1: {"CH01":"S01", "CH02":"S02", "CH03":"S01"},
	2: {"CH01":"S04", "CH02":"S03", "CH03":"S03"},
	3: {"CH01":"S06", "CH02":"S05", "CH03":"S05"},
	4: {"CH01":"S07", "CH02":"S07", "CH03":"S07"},
}
# Template order is SLOTS, including the production overlay's legs and rings.
const SET_TEMPLATES := {
	"S01":["EQ03", "EQ13", "EQ23", "EQ33", "EQ97", "EQ43", "EQ98", "EQ53"],
	"S02":["EQ04", "EQ14", "EQ24", "EQ34", "EQ99", "EQ44", "EQ100", "EQ54"],
	"S03":["EQ05", "EQ15", "EQ25", "EQ35", "EQ101", "EQ45", "EQ102", "EQ55"],
	"S04":["EQ06", "EQ16", "EQ26", "EQ36", "EQ103", "EQ46", "EQ104", "EQ56"],
	"S05":["EQ07", "EQ17", "EQ27", "EQ37", "EQ105", "EQ47", "EQ106", "EQ57"],
	"S06":["EQ08", "EQ18", "EQ28", "EQ38", "EQ107", "EQ48", "EQ108", "EQ58"],
	"S07":["EQ09", "EQ19", "EQ29", "EQ39", "EQ109", "EQ49", "EQ110", "EQ59"],
}
const ALLOCATIONS := {
	1: {"mastery":4},
	2: {"mastery":5, "precision":4},
	3: {"mastery":5, "precision":5, "agility":4},
	4: {"mastery":5, "precision":5, "agility":5, "dexterity":4},
}
const SAMPLE_DEFINITIONS := {
	"G2":{"rarity":"gold", "rank":2, "quantile":50, "gain":10},
	"P5":{"rarity":"purple", "rank":5, "quantile":50, "gain":10},
	"G0":{"rarity":"gold", "rank":0, "quantile":50, "gain":10},
	"mixed":{"rarity":"gold", "rank":2, "quantile":50, "gain":10},
	"green":{"rarity":"green", "rank":3, "quantile":50, "gain":10},
	"white":{"rarity":"white", "rank":5, "quantile":50, "gain":10},
	"lowG2":{"rarity":"gold", "rank":2, "quantile":25, "gain":8},
}
const AFFIX_COUNTS := {"white":0, "green":2, "purple":3, "gold":4}

## Descriptors only: building them consumes no battle seed or global RNG state.
static func cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chapter in range(1, 5):
		for hero_id: String in HEROES:
			for sample: String in SAMPLES:
				result.append({"chapter":chapter, "hero_id":hero_id, "sample":sample,
					"group_id":"B%02d/%s" % [chapter, hero_id],
					"case_id":"B%02d/%s/%s" % [chapter, hero_id, sample],
					"boss_id":"BO%02d" % chapter, "level":5 * chapter, "item_level":5 * chapter})
	return result

## All instances and metadata are new value trees on each invocation. Invalid
## requests or changed frozen template/affix contracts fail closed with {}.
static func build(chapter: int, hero_id: String, sample: String) -> Dictionary:
	if chapter not in SETS_BY_CHAPTER or hero_id not in HEROES or sample not in SAMPLES: return {}
	var level := 5 * chapter
	if level > Progression.level_cap() or Progression.rank_cap() != 5: return {}
	if Registry.slots(Rules.V2) != SLOTS: return {}
	var talents: Dictionary = ALLOCATIONS[chapter].duplicate(true)
	if not Progression.valid_talents(talents, level) or Progression.available_points(talents, level) != 0: return {}
	var branches: Dictionary = {"q":"B", "ultimate":"A"} if chapter == 4 else {"q":"", "ultimate":""}
	var power_type := "magic" if hero_id == "CH03" else "physical"
	var case_id := "B%02d/%s/%s" % [chapter, hero_id, sample]
	var group_id := "B%02d/%s" % [chapter, hero_id]
	var owned := {}
	var loadout := {}
	var equipment_manifest: Array[Dictionary] = []
	var sample_definition: Dictionary = SAMPLE_DEFINITIONS[sample]
	for index in SLOTS.size():
		var slot: String = SLOTS[index]
		var set_id: String = SETS_BY_CHAPTER[chapter][hero_id]
		if chapter == 4 and hero_id != "CH01" and slot in ["weapon", "ring"]: set_id = "S03"
		var template_id: String = SET_TEMPLATES[set_id][index]
		var template := Registry.equipment(template_id, Rules.V2)
		if template.get("slot") != slot or template.get("set_id") != set_id: return {}
		var rarity: String = str(sample_definition.rarity)
		var rank: int = int(sample_definition.rank)
		if sample == "mixed" and slot in ["weapon", "ring"]:
			rarity = "purple"
			rank = 5
		var filtering := _affix_filter(template_id, slot, power_type, int(AFFIX_COUNTS[rarity]))
		if filtering.is_empty(): return {}
		var rolls := {}
		for key: String in Instances.main_keys(template_id, power_type): rolls[key] = int(sample_definition.quantile)
		var affixes: Array[Dictionary] = []
		for affix_type: String in filtering.selected: affixes.append({"type":affix_type, "u":int(sample_definition.quantile)})
		var steps: Array[Dictionary] = []
		for step in rank:
			# Canonical acquired/pre-enhanced baseline, not proof of any payment.
			steps.append({"g":int(sample_definition.gain), "pity":0,
				"base_price_peak":Economy.enhancement_price(step + 1, level)})
		var instance_id := "s11:%s:%s" % [case_id, slot]
		var item := Instances.create({"instance_id":instance_id, "template_id":template_id,
			"source_event_id":"s11:fixture:%s:%s" % [case_id, slot], "item_level":level,
			"rarity":rarity, "power_type":power_type, "main_rolls":rolls,
			"affix_type_and_quantile":affixes, "enhancement_rank":rank,
			"enhancement_steps":steps, "location":"equipped",
			"purchase_baseline_gold":Economy.purchase_baseline_price(template_id, rarity, level)})
		if item.is_empty() or not Instances.can_equip(item, hero_id, level): return {}
		owned[instance_id] = item
		loadout[slot] = instance_id
		equipment_manifest.append({"slot":slot, "template_id":template_id, "set_id":set_id,
			"instance_id":instance_id, "rarity":rarity, "enhancement_rank":rank,
			"item_level":level, "power_type":power_type, "main_rolls":rolls.duplicate(true),
			"affix_type_and_quantile":affixes.duplicate(true), "enhancement_steps":steps.duplicate(true),
			"affix_filtering":filtering, "main_stats":Instances.main_stats(item),
			"affix_stats":Instances.affix_stats(item), "template_affix_id":str(template.get("affix_id", ""))})
	var stats := Resolver.resolve(hero_id, level, loadout, owned, Rules.V2, talents)
	if stats.is_empty() or stats.loadout.size() != 8 or int(stats.talent_points_available) != 0: return {}
	stats["branches"] = branches.duplicate(true)
	var cap_accounting := _cap_accounting(stats, hero_id)
	var manifest := {"fixture_version":VERSION, "specification":SPECIFICATION,
		"case_id":case_id, "group_id":group_id, "chapter":chapter, "boss_id":"BO%02d" % chapter,
		"hero_id":hero_id, "sample":sample, "level":level, "item_level":level,
		"ruleset_version":Rules.V2, "versions":Rules.versions(), "seeds":SEEDS.duplicate(),
		"parameters_sha256":FileAccess.get_file_as_string(AssetCatalog.resolve(Rules.PARAMETERS_PATH)).sha256_text(),
		"talents":talents.duplicate(true), "talent_rank_cap":Progression.rank_cap(),
		"talent_points_spent":level - 1, "branches":branches.duplicate(true),
		"set_counts":stats.sets.duplicate(true), "equipment":equipment_manifest,
		"uncapped_equipment_contribution":stats.uncapped_equipment_contribution.duplicate(true),
		"equipment_contribution":stats.equipment_contribution.duplicate(true),
		"cap_accounting":cap_accounting, "cap_losses":_positive_losses(cap_accounting),
		"cap_accounting_scope":"Permanent entry stats only; conditional effects must be recorded during combat.",
		"acquisition_assumption":"Already owned legal instances; pre-enhancement does not imply manual forging unlocks."}
	return {"chapter":chapter, "hero_id":hero_id, "sample":sample, "case_id":case_id,
		"group_id":group_id, "boss_id":"BO%02d" % chapter, "level":level, "item_level":level,
		"owned":owned, "loadout":loadout, "talents":talents, "branches":branches,
		"stats":stats, "manifest":manifest}

static func _affix_filter(template_id: String, slot: String, power_type: String, count: int) -> Dictionary:
	var main := "ability_power" if power_type == "magic" else "attack"
	var penetration := "magic_penetration" if power_type == "magic" else "armor_penetration"
	var candidates: Array[String] = []
	if slot in OFFENSIVE_SLOTS:
		candidates.assign([main, "damage_bonus", "crit_chance", "attack_speed", "crit_multiplier", penetration, "resource_gain_bonus", "max_hp"])
	else:
		candidates.assign(["max_hp", "armor", "magic_resist", "hp_ratio", "damage_reduction", "cooldown_reduction", "move_speed"])
	var legal_pool := Instances.legal_affixes(template_id, power_type)
	var filtered: Array[String] = []
	var rejected: Array[String] = []
	for candidate: String in candidates:
		if candidate in legal_pool and candidate not in filtered: filtered.append(candidate)
		else: rejected.append(candidate)
	if filtered.size() < 4: return {}
	var frozen_gold: Array[String] = []
	if slot in OFFENSIVE_SLOTS:
		frozen_gold.assign([main, "damage_bonus", "crit_chance", "attack_speed"])
	else:
		frozen_gold.assign(["max_hp", "armor", "magic_resist", "damage_reduction" if slot == "feet" else "hp_ratio"])
	if filtered.slice(0, 4) != frozen_gold: return {}
	return {"ordered_candidates":candidates, "legal_pool":legal_pool,
		"legal_candidates":filtered, "rejected_candidates":rejected,
		"selected":filtered.slice(0, count), "legal_not_selected":filtered.slice(count),
		"frozen_gold_core":frozen_gold, "affix_count":count}

## Both stages are visible: equipment-only caps, then base/talent/shared caps.
## Losses are attributed once at each stage, with an aggregate bucket loss.
static func _cap_accounting(stats: Dictionary, hero_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Dictionary = stats.uncapped_equipment_contribution
	var applied: Dictionary = stats.equipment_contribution
	var caps: Dictionary = Rules.value("caps")
	var hero := Registry.hero(hero_id)
	var base: Dictionary = stats.hero_base
	for key: String in ["crit_chance", "crit_multiplier", "attack_speed", "move_speed", "cooldown_reduction", "damage_bonus", "damage_reduction", "status_duration", "burn_damage", "corrosion_damage_bonus", "resource_gain_bonus", "hp_ratio"]:
		var cap_key := "equipment_damage_reduction" if key == "damage_reduction" else key
		var resolved_key := "attack_speed_bonus" if key == "attack_speed" else "move_speed_bonus" if key == "move_speed" else key
		var base_amount := 0.0
		var talent_amount := 0.0
		match key:
			"crit_chance":
				base_amount = float(hero.get("crit_chance", 0.05))
				talent_amount = float(base.talent_crit_chance)
			"crit_multiplier": base_amount = float(hero.get("crit_multiplier", 1.5))
			"attack_speed": talent_amount = float(base.talent_attack_speed)
			"cooldown_reduction": talent_amount = float(base.talent_cooldown_reduction)
		var equipment_raw := float(raw.get(key, 0.0))
		var equipment_applied := float(applied.get(key, 0.0))
		var effective := float(stats.get(resolved_key, 0.0))
		var equipment_loss := maxf(0.0, equipment_raw - equipment_applied)
		var combined_loss := maxf(0.0, equipment_applied + base_amount + talent_amount - effective)
		result.append({"stat":key, "cap":float(caps[cap_key]), "equipment_raw":equipment_raw,
			"equipment_applied":equipment_applied, "base":base_amount, "talents":talent_amount,
			"effective":effective, "equipment_cap_loss":equipment_loss,
			"combined_cap_loss":combined_loss, "total_cap_loss":equipment_loss + combined_loss})
	return result

static func _positive_losses(accounting: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in accounting:
		if float(row.total_cap_loss) > 0.000000001: result.append(row.duplicate(true))
	return result
