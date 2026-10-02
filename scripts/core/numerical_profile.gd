class_name NumericalProfile
extends RefCounted
## Native V2 initialization. Six original starter templates remain available to
## each hero through legal typed instances; no migration or paid-history waiver.
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Rules = preload("res://config/numerical_rules.gd")
const Economy = preload("res://scripts/core/instance_economy.gd")
const Expedition = preload("res://scripts/core/expedition_state.gd")
const STARTERS := ["EQ01", "EQ11", "EQ21", "EQ31", "EQ41", "EQ51"]
const EVENT := "starter:numerical_v2:v1"

static func fresh(legacy_defaults: Dictionary) -> Dictionary:
	var result := legacy_defaults.duplicate(true)
	result.merge(Expedition.versions(2), true)
	result.equipment = {}
	result.loadout = {}
	result["loadout_presets"] = {}
	var by_type := {}
	for power: String in ["physical", "magic"]:
		var loadout := {}
		for slot: String in Registry.slots(2): loadout[slot] = ""
		for template: String in STARTERS:
			var id := EVENT + ":" + power + ":" + template
			var rolls := {}
			for key: String in Instances.main_keys(template, power): rolls[key] = 50
			var legal := Instances.legal_affixes(template, power)
			var preferred: Array[String] = []
			for key: String in Registry.equipment(template,2).affix_tendencies:
				if key in legal and key not in preferred: preferred.append(key)
			for key: String in legal:
				if key not in preferred: preferred.append(key)
			var affixes: Array = []
			for index in int(Rules.value("rarities").green.affix_count): affixes.append({"type":preferred[index],"u":50})
			var item := Instances.create({"instance_id":id,"template_id":template,"source_event_id":EVENT,
				"item_level":1,"rarity":"green","power_type":power,"main_rolls":rolls,
				"affix_type_and_quantile":affixes,"enhancement_steps":[],
				"purchase_baseline_gold":Economy.purchase_baseline_price(template,"green",1),
				"location":"equipped" if power == "physical" else "inventory"})
			if item.is_empty(): return {}
			result.equipment[id] = item
			loadout[Registry.equipment(template,2).slot] = id
		by_type[power] = loadout
	for hero: String in ["CH01", "CH02", "CH03"]:
		result.loadout_presets[hero] = by_type["magic" if hero == "CH03" else "physical"].duplicate(true)
	result.loadout = result.loadout_presets.CH01.duplicate(true)
	result["talents"] = {}
	result["research_xp"] = {}
	result["materials"] = {}
	result["progression_receipts"] = {}
	result["hero_role_revision"] = 1
	result["equipment_class_migration"] = {"version":1, "removed_slots":[]}
	result["gold_pity"] = {"B01":0,"B02":0,"B03":0,"B04":0}
	return result
