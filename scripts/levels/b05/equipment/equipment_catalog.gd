class_name B05EquipmentCatalog
extends RefCounted
## Staged B05 contract only. Not a released registry, item generator or effect runtime.
## No registration, profile writes, RNG or acquisition-policy version changes occur here.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const ClassPolicy = preload("res://scripts/domain/equipment/equipment_class_policy.gd")
const PATH := "res://data/levels/b05/equipment.json"
const VERSION := 1
const HEROES := ["CH01", "CH02", "CH03"]
const SLOTS := ["weapon", "head", "chest", "hands", "legs", "feet", "ring", "charm"]
const DESIGN_SLOTS := ["weapon", "head", "chest", "hands", "legs", "feet", "ring", "accessory"]
const SET_HERO := {"B05-SW":"CH01", "B05-SG":"CH02", "B05-SM":"CH03", "B05-SU":""}
# Same slot prices as the released eight-slot catalog (legs inherit chest, ring charm).
const PRICES := {"weapon":180, "head":140, "chest":180, "hands":120, "legs":180, "feet":120, "ring":160, "charm":160}
const EFFECT_CONTRACT := {
	"runtime_implemented":false, "power_basis":"instance_fixed_power_type_ad_or_ap",
	"derived_damage_triggers_extra_damage":false, "count_once_per_cast_id":true,
	"cooldowns_min_seconds":0.0, "reset_ultimate":false,
	"heal_can_crit":false, "shield_can_crit":false, "shield_stack_rule":"replace_with_higher",
	"out_of_combat_clear_seconds":10.0, "clear_temporary_stacks_on_room_change":true,
	"equipment_change_can_heal_refresh_shield_or_reset_cooldown":false
}
static var _data: Dictionary = {}

static func catalog() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(PATH)))
		if not parsed is Dictionary: return {}
		_data = parsed
	return _data.duplicate(true)

static func equipment_ids() -> Array:
	var result: Array = catalog().get("equipment", {}).keys()
	result.sort()
	return result

static func equipment(template_id: String) -> Dictionary:
	return catalog().get("equipment", {}).get(template_id, {}).duplicate(true)

static func sets() -> Dictionary:
	return catalog().get("sets", {}).duplicate(true)

static func allowed_heroes(template_id: String) -> Array:
	return equipment(template_id).get("allowed_heroes", []).duplicate()

static func supports_power(template_id: String, power_type: String) -> bool:
	return power_type in equipment(template_id).get("power_types", [])

## Returns a slot -> IDs map, compatible in shape with the released natural-pool API.
## Invalid heroes fail closed; it never fills holes with another race or class.
static func natural_pool(hero_id: String) -> Dictionary:
	if hero_id not in HEROES: return {}
	var result := {}
	for slot: String in SLOTS: result[slot] = []
	for id: String in equipment_ids():
		var item := equipment(id)
		if hero_id in item.allowed_heroes: result[item.slot].append(id)
	return result

static func main_bases(template_id: String, power_type: String) -> Dictionary:
	if not supports_power(template_id, power_type): return {}
	var slot: Dictionary = Rules.value("slots", {}).get(equipment(template_id).slot, {})
	return slot.get("shared", slot.get(power_type, {})).duplicate(true)

static func legal_affixes(template_id: String, power_type: String) -> Array[String]:
	var result: Array[String] = []
	if not supports_power(template_id, power_type): return result
	var slot: String = equipment(template_id).slot
	var definitions: Dictionary = Rules.value("affixes", {})
	for key: String in definitions:
		var definition: Dictionary = definitions[key]
		if slot in definition.slots and str(definition.get("power_type", power_type)) == power_type:
			result.append(key)
	return result

static func affix_tendencies(template_id: String, power_type: String) -> Array:
	if not supports_power(template_id, power_type): return []
	return equipment(template_id).get("affix_tendencies_by_power", {}).get(power_type, []).duplicate()

static func affix_weights(template_id: String, power_type: String) -> Dictionary:
	var result := {}
	var tendencies := affix_tendencies(template_id, power_type)
	for key: String in legal_affixes(template_id, power_type):
		result[key] = int(Rules.value("affix_tendency_weight")) if key in tendencies else int(Rules.value("affix_default_weight"))
	return result

## A generation-intent value, NOT a playable equipment instance or a drop receipt.
## Natural generation chooses effective power once. Subsequent equip never rewrites it.
static func bind_generation(template_id: String, hero_id: String) -> Dictionary:
	if hero_id not in HEROES or hero_id not in allowed_heroes(template_id): return {}
	var power := ClassPolicy.power_type(hero_id)
	if not supports_power(template_id, power): return {}
	return {"catalog_version":VERSION, "template_id":template_id, "power_type":power}

static func validate_binding(binding: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not binding is Dictionary:
		errors.append("Binding must be a dictionary.")
		return errors
	if not _keys(binding, ["catalog_version", "template_id", "power_type"]):
		errors.append("Binding fields do not match the generation-intent contract.")
		return errors
	if not _integer(binding.catalog_version, VERSION): errors.append("Unsupported catalog version.")
	if not binding.template_id is String or not binding.power_type is String:
		errors.append("Binding identity and power must be strings.")
	elif not supports_power(binding.template_id, binding.power_type):
		errors.append("Unknown template or illegal fixed power type.")
	return errors

static func can_equip(binding: Variant, hero_id: String) -> bool:
	if hero_id not in HEROES or not validate_binding(binding).is_empty(): return false
	return hero_id in allowed_heroes(binding.template_id)

static func validate(candidate: Variant = null) -> Array[String]:
	var errors: Array[String] = []
	var data: Variant = catalog() if candidate == null else candidate
	if not data is Dictionary or not _value_tree(data):
		errors.append("Catalog must contain finite JSON values only.")
		return errors
	if not _keys(data, ["schema_version", "chapter_id", "runtime_enabled", "source_document", "effect_contract", "sets", "equipment"]):
		errors.append("Unexpected catalog fields.")
		return errors
	if not _integer(data.schema_version, VERSION) or data.chapter_id != "B05" or data.runtime_enabled != false or not data.runtime_enabled is bool:
		errors.append("Unsupported version/chapter or premature runtime activation.")
	if not _text(data.source_document): errors.append("Missing source document.")
	if not data.sets is Dictionary or not data.equipment is Dictionary:
		errors.append("Sets and equipment must be dictionaries.")
		return errors
	if not _keys(data.sets, SET_HERO.keys()): errors.append("Expected exactly the four B05 sets.")
	if data.equipment.size() != 35: errors.append("Expected exactly 35 B05 templates.")
	if not data.effect_contract is Dictionary or data.effect_contract != EFFECT_CONTRACT:
		errors.append("Effect lifecycle contract changed without a catalog version.")
	for sid: String in SET_HERO:
		var definition: Variant = data.sets.get(sid)
		if not definition is Dictionary or not _keys(definition, ["id", "name", "name_en", "allowed_heroes", "power_types", "runtime_implemented", "thresholds"]):
			errors.append(sid + ": invalid set fields.")
			continue
		if definition.id != sid or not _text(definition.name) or not _text(definition.name_en): errors.append(sid + ": invalid identity/name.")
		_validate_qualification(definition, sid, sid, errors)
		if definition.runtime_implemented != false or not definition.runtime_implemented is bool: errors.append(sid + ": effect runtime is not implemented.")
		if not definition.thresholds is Dictionary or not _keys(definition.thresholds, ["2", "4", "6"]):
			errors.append(sid + ": only 2/4/6 thresholds are allowed.")
		else:
			for count: String in definition.thresholds:
				_validate_effect(definition.thresholds[count], sid + "/" + count, errors)
		for ds: String in DESIGN_SLOTS:
			if not data.equipment.has(sid + "-" + ds): errors.append(sid + ": missing design slot " + ds)
	for id: Variant in data.equipment:
		var item: Variant = data.equipment[id]
		if not id is String or not item is Dictionary:
			errors.append("Invalid template entry.")
			continue
		var required := ["id", "name", "name_en", "design_slot", "slot", "set_id", "race_id", "allowed_heroes", "power_types", "price", "base_stats", "main_coefficient", "ruleset_version", "unlock_boss", "affix_tendencies_by_power", "unique_effect"]
		var unique_index := ["B05-U01", "B05-U02", "B05-U03"].find(id)
		if unique_index >= 0: required.append("source_preferences")
		if not _keys(item, required):
			errors.append(id + ": unexpected template fields.")
			continue
		if item.id != id or not _text(item.name) or not _text(item.name_en): errors.append(id + ": invalid identity/name.")
		if item.race_id != "B05" or item.unlock_boss != "BO04" or not _integer(item.ruleset_version, 2): errors.append(id + ": invalid chapter/ruleset/unlock.")
		if item.design_slot not in DESIGN_SLOTS or item.slot != ("charm" if item.design_slot == "accessory" else item.design_slot): errors.append(id + ": invalid slot mapping.")
		if not item.slot is String or not _integer(item.price, int(PRICES.get(item.slot, -1))): errors.append(id + ": invalid inherited price.")
		if not item.base_stats is Dictionary or not item.base_stats.is_empty() or not _number(item.main_coefficient) or float(item.main_coefficient) != 1.0: errors.append(id + ": extra main-stat budget.")
		if not item.set_id is String:
			errors.append(id + ": invalid set identity.")
			continue
		var sid: String = item.set_id
		if unique_index >= 0:
			if not sid.is_empty() or item.design_slot != ["feet", "ring", "accessory"][unique_index]: errors.append(id + ": incorrect unique slot/membership.")
			_validate_effect(item.unique_effect, id, errors)
			var sources := [["L26", "B05-M03", "B05-M06"], ["L28", "B05-M04", "B05-M10"], ["L30", "B05-M13", "B05-M18"]]
			if item.source_preferences != sources[unique_index]: errors.append(id + ": invalid source preference.")
		elif not SET_HERO.has(sid) or id != sid + "-" + str(item.design_slot) or item.unique_effect != {}:
			errors.append(id + ": invalid set template or duplicate unique effect.")
		_validate_qualification(item, sid, id, errors)
		_validate_tendencies(item, id, errors)
	# Candidate edits are versioned contracts, not a way to silently alter authored triggers.
	if candidate != null:
		var authored := catalog()
		for key: String in ["equipment", "sets"]:
			if data[key] != authored.get(key): errors.append(key + ": differs from the authored version-one contract.")
	return errors

static func _validate_qualification(item: Dictionary, sid: String, label: String, errors: Array[String]) -> void:
	var hero: String = SET_HERO.get(sid, "")
	var expected: Array = HEROES if hero.is_empty() else [hero]
	var powers: Array = ["physical", "magic"] if hero.is_empty() else [ClassPolicy.power_type(hero)]
	if item.allowed_heroes != expected or item.power_types != powers: errors.append(label + ": invalid full-slot class/power qualification.")

static func _validate_tendencies(item: Dictionary, label: String, errors: Array[String]) -> void:
	if not item.affix_tendencies_by_power is Dictionary or not item.power_types is Array or not _keys(item.affix_tendencies_by_power, item.power_types):
		errors.append(label + ": invalid tendency map.")
		return
	var definitions: Dictionary = Rules.value("affixes", {})
	for power: Variant in item.affix_tendencies_by_power:
		var entries: Variant = item.affix_tendencies_by_power[power]
		if not entries is Array or entries.is_empty():
			errors.append(label + ": missing tendencies.")
			continue
		var seen := {}
		for key: Variant in entries:
			if not key is String or not definitions.has(key):
				errors.append(label + ": unknown affix tendency.")
				continue
			var definition: Dictionary = definitions[key]
			if seen.has(key) or item.slot not in definition.slots or definition.get("power_type", power) != power: errors.append(label + ": illegal slot/power/duplicate tendency.")
			seen[key] = true

static func _validate_effect(effect: Variant, label: String, errors: Array[String]) -> void:
	if not effect is Dictionary or not _keys(effect, ["runtime_implemented", "trigger", "conditions", "parameters"]):
		errors.append(label + ": invalid effect schema.")
		return
	if not effect.runtime_implemented is bool or effect.runtime_implemented != false or not _text(effect.trigger): errors.append(label + ": invalid staged trigger.")
	if not effect.conditions is Array or effect.conditions.is_empty():
		errors.append(label + ": missing effect conditions.")
	else:
		for condition: Variant in effect.conditions:
			if not _text(condition): errors.append(label + ": invalid condition.")
	if not effect.parameters is Dictionary or effect.parameters.is_empty(): errors.append(label + ": missing effect parameters.")
	elif not _value_tree(effect.parameters): errors.append(label + ": nonfinite effect parameters.")

static func _keys(value: Dictionary, expected: Array) -> bool:
	return value.size() == expected.size() and value.has_all(expected)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, expected: int) -> bool:
	return _number(value) and float(value) == float(expected)

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _value_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 16: return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _value_tree(value[key], depth + 1): return false
		return true
	if value is Array:
		for entry: Variant in value:
			if not _value_tree(entry, depth + 1): return false
		return true
	return value is String or value is bool or value == null or _number(value)
