class_name EquipmentInstances
extends RefCounted
## Pure value records. Random generation, ownership and transactions live elsewhere.
## Explicit constructors never draw RNG or manufacture historical payment records.
const Rules = preload("res://config/numerical_rules.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const LOCATIONS: Array[String] = ["inventory", "pending", "equipped"]
const REQUIRED: Array[String] = ["instance_id", "template_id", "equipment_instance_version", "ruleset_version", "scale_version", "source_event_id", "item_level", "rarity", "power_type", "main_rolls", "affix_type_and_quantile", "enhancement_rank", "enhancement_steps", "enhancement_reroll_history", "reforge_slot", "enhancement_gold_ledger", "material_ledger", "location", "lock_state"]

## Required input: IDs, item level, rarity/type, and explicit main k / affix u.
## Callers may supply persisted metadata; invalid explicit values are not repaired.
static func create(spec: Dictionary) -> Dictionary:
	var result := spec.duplicate(true)
	var versions := Rules.versions()
	var steps: Variant = result.get("enhancement_steps", [])
	var defaults := {"equipment_instance_version":int(versions.equipment_instance), "ruleset_version":2, "scale_version":int(versions.scale), "enhancement_rank":steps.size() if steps is Array else 0, "enhancement_steps":[], "enhancement_reroll_history":[], "reforge_slot":-1, "enhancement_gold_ledger":[], "material_ledger":[], "location":"inventory", "lock_state":false}
	for key: String in defaults:
		if not result.has(key): result[key] = defaults[key]
	return result if validate(result).is_empty() else {}

static func main_keys(template_id: String, power_type: String) -> Array[String]:
	var result: Array[String] = []
	for key: String in main_bases(template_id, power_type): result.append(key)
	return result

static func main_bases(template_id: String, power_type: String) -> Dictionary:
	if power_type not in ["physical", "magic"]: return {}
	var template := Registry.equipment(template_id, 2)
	var definitions: Dictionary = Rules.value("slots")
	if template.is_empty() or not definitions.has(template.get("slot")): return {}
	var slot: Dictionary = definitions[template.slot]
	return slot.get("shared", slot.get(power_type, {})).duplicate(true)

## Stable configuration order is also the deterministic migration fill order.
static func legal_affixes(template_id: String, power_type: String) -> Array[String]:
	var result: Array[String] = []
	var template := Registry.equipment(template_id, 2)
	if template.is_empty() or power_type not in ["physical", "magic"]: return result
	var definitions: Dictionary = Rules.value("affixes")
	for key: String in definitions:
		var definition: Dictionary = definitions[key]
		if template.slot in definition.slots and str(definition.get("power_type", power_type)) == power_type: result.append(key)
	return result

static func affix_weights(template_id: String, power_type: String) -> Dictionary:
	var result := {}
	var template := Registry.equipment(template_id, 2)
	for key: String in legal_affixes(template_id, power_type):
		result[key] = int(Rules.value("affix_tendency_weight")) if key in template.affix_tendencies else int(Rules.value("affix_default_weight"))
	return result

static func validate(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _value_tree(record):
		errors.append("Instances must contain finite, serializable deep values only.")
		return errors
	for key: String in REQUIRED:
		if not record.has(key): errors.append("Missing instance field: " + key)
	if not errors.is_empty(): return errors
	for key in ["instance_id", "template_id", "source_event_id"]:
		if not _nonempty_string(record[key]): errors.append("Invalid instance identity: " + key)
	var template := Registry.equipment(str(record.template_id), 2)
	if template.is_empty(): errors.append("Unknown equipment template.")
	elif record.has("slot") and record.slot != template.slot: errors.append("Instance slot does not match its template.")
	var versions := Rules.versions()
	for pair in [["ruleset_version", 2], ["equipment_instance_version", int(versions.equipment_instance)], ["scale_version", int(versions.scale)]]:
		if not _integer_in(record[pair[0]], int(pair[1]), int(pair[1])): errors.append("Unsupported instance version: " + str(pair[0]))
	if not _integer_in(record.item_level, 1, Growth.level_cap()): errors.append("Item level is outside the released level cap.")
	var rarities: Dictionary = Rules.value("rarities")
	if not record.rarity is String or not rarities.has(record.rarity): errors.append("Unknown rarity.")
	if not record.power_type is String or record.power_type not in ["physical", "magic"]: errors.append("Unknown power type.")
	var bases := main_bases(str(record.template_id), str(record.power_type))
	var main_roll: Dictionary = Rules.value("main_roll")
	if not record.main_rolls is Dictionary:
		errors.append("Main rolls must be a dictionary.")
	else:
		if record.main_rolls.size() != bases.size(): errors.append("Main rolls must match every main attribute exactly.")
		for key: String in bases:
			if not record.main_rolls.has(key) or not _integer_in(record.main_rolls.get(key), 0, int(main_roll.steps)): errors.append("Missing or illegal main roll: " + key)
		for key: String in record.main_rolls:
			if not bases.has(key): errors.append("Unknown main roll: " + key)
	var legal := legal_affixes(str(record.template_id), str(record.power_type))
	if not record.affix_type_and_quantile is Array:
		errors.append("Affixes must be an array.")
	else:
		if rarities.has(record.rarity) and record.affix_type_and_quantile.size() != int(rarities[record.rarity].affix_count): errors.append("Rarity affix count mismatch.")
		var seen: Dictionary = {}
		for affix: Variant in record.affix_type_and_quantile:
			if not affix is Dictionary or not affix.has_all(["type", "u"]):
				errors.append("Malformed affix record.")
				continue
			if not affix.type is String or affix.type not in legal: errors.append("Illegal affix for this slot/power type.")
			if seen.has(affix.type): errors.append("Duplicate affix type.")
			seen[affix.type] = true
			if not _integer_in(affix.u, 0, int(main_roll.steps)): errors.append("Illegal affix quantile.")
	var maximum := int(Rules.value("enhancement_max"))
	if not _integer_in(record.enhancement_rank, 0, maximum): errors.append("Illegal enhancement rank.")
	if not record.enhancement_steps is Array:
		errors.append("Enhancement steps must be an array.")
	else:
		if record.enhancement_steps.size() != record.enhancement_rank: errors.append("Enhancement rank does not match its step vector.")
		var enhancement: Dictionary = Rules.value("enhancement_random")
		for step: Variant in record.enhancement_steps:
			if not step is Dictionary or not step.has_all(["g", "pity", "base_price_peak"]):
				errors.append("Malformed enhancement step.")
				continue
			if not _integer_in(step.g, 0, int(enhancement.gain_percent_max)) or not enhancement.gain_percent_weights.has(str(int(step.g))): errors.append("Illegal enhancement gain.")
			if not _integer_in(step.pity, 0, int(enhancement.reroll_no_improvement_pity) - 1): errors.append("Illegal enhancement pity counter.")
			if _integer_in(step.g, int(enhancement.gain_percent_max), int(enhancement.gain_percent_max)) and not _integer_in(step.pity, 0, 0): errors.append("Maximum enhancement gain requires a cleared pity counter.")
			if not _nonnegative_integer(step.base_price_peak): errors.append("Illegal canonical enhancement price peak.")
	if not record.enhancement_reroll_history is Array:
		errors.append("Enhancement reroll history must be an array.")
	else:
		for operation: Variant in record.enhancement_reroll_history:
			if not operation is Dictionary or not _integer_in(operation.get("rank"), 1, maximum) or not _nonnegative_integer(operation.get("settled_price_peak")): errors.append("Malformed enhancement reroll history.")
	var affix_count: int = record.affix_type_and_quantile.size() if record.affix_type_and_quantile is Array else 0
	if not _integer_in(record.reforge_slot, -1, affix_count - 1): errors.append("Illegal bound reforge slot.")
	_validate_ledger(record.enhancement_gold_ledger, false, errors)
	_validate_ledger(record.material_ledger, true, errors)
	if not record.location is String or record.location not in LOCATIONS: errors.append("Unknown instance location.")
	if not record.lock_state is bool: errors.append("Lock state must be a boolean.")
	if record.has("purchase_baseline_gold") and not _nonnegative_integer(record.purchase_baseline_gold): errors.append("Invalid frozen purchase baseline.")
	if record.has("forge_revision") and not _integer_in(record.forge_revision, 0, 1000000000000): errors.append("Invalid forge revision.")
	if record.has("pending_reforge") and not record.pending_reforge is Dictionary: errors.append("Invalid pending reforge value.")
	if record.has("legacy_equip_waiver"): _validate_waiver(record, errors)
	return errors

## Flat values use reduced rational factors, then one exact integer half-up.
## Config decimals are parsed separately so x.499999 floating products cannot
## under-round mathematical half points. Percentage results stay fractional.
static func main_stats(record: Dictionary) -> Dictionary:
	if not validate(record).is_empty(): return {}
	return _main_stats(record)

static func _main_stats(record: Dictionary) -> Dictionary:
	var result := {}
	var template := Registry.equipment(str(record.template_id), 2)
	var rarity: Dictionary = Rules.value("rarities")[record.rarity]
	var ranges: Dictionary = Rules.value("main_roll")
	var percentages: Array = Rules.value("percentage_main_keys")
	var level_factor := _add_fraction([1, 1], _multiply_fraction(_fraction(Rules.value("main_item_level_per_level")), [int(record.item_level) - 1, 1]))
	var gain_total := 0
	for step: Dictionary in record.enhancement_steps: gain_total += int(step.g)
	var enhancement: Array[int] = [100 + gain_total, 100]
	var bases := main_bases(str(record.template_id), str(record.power_type))
	for key: String in bases:
		var roll := _interpolate_fraction(ranges.min, ranges.max, int(record.main_rolls[key]), int(ranges.steps))
		var value := _multiply_fraction(_fraction(bases[key]), _fraction(template.main_coefficient))
		value = _multiply_fraction(value, roll)
		if key in percentages:
			value = _multiply_fraction(value, _fraction(rarity.percentage_multiplier))
			result[key] = float(value[0]) / float(value[1])
		else:
			value = _multiply_fraction(_multiply_fraction(_multiply_fraction(value, level_factor), _fraction(rarity.main_multiplier)), enhancement)
			result[key] = _round_fraction(value)
	return result

static func affix_stats(record: Dictionary) -> Dictionary:
	if not validate(record).is_empty(): return {}
	return _affix_stats(record)

static func _affix_stats(record: Dictionary) -> Dictionary:
	var result := {}
	var definitions: Dictionary = Rules.value("affixes")
	var rarity: Dictionary = Rules.value("rarities")[record.rarity]
	var level_factor := _add_fraction([1, 1], _multiply_fraction(_fraction(Rules.value("main_item_level_per_level")), [int(record.item_level) - 1, 1]))
	var quantile_steps := int(Rules.value("main_roll").steps)
	for affix: Dictionary in record.affix_type_and_quantile:
		var definition: Dictionary = definitions[affix.type]
		var value := _interpolate_fraction(definition.min, definition.max, int(affix.u), quantile_steps)
		if definition.scaling == "flat":
			value = _multiply_fraction(_multiply_fraction(value, _fraction(rarity.main_multiplier)), level_factor)
			result[affix.type] = _round_fraction(value)
		else:
			value = _multiply_fraction(value, _fraction(rarity.percentage_multiplier))
			result[affix.type] = float(value[0]) / float(value[1])
	return result

static func stats(record: Dictionary) -> Dictionary:
	if not validate(record).is_empty(): return {}
	var result := {}
	var definitions: Dictionary = Rules.value("affixes")
	for key: String in definitions: result[key] = 0 if definitions[key].scaling == "flat" else 0.0
	for key: String in Registry.STAT_KEYS:
		if not result.has(key): result[key] = 0
	# Both calculations consume the same already-validated value in this call.
	# Public main_stats/affix_stats still validate independent caller inputs.
	for source: Dictionary in [_main_stats(record), _affix_stats(record)]:
		for key: String in source: result[key] += source[key]
	return result

static func can_equip(record: Dictionary, hero_id: String, level: int) -> bool:
	if not validate(record).is_empty() or Registry.hero(hero_id).is_empty() or level < 1 or level > Growth.level_cap(): return false
	var expected_type := "magic" if hero_id == "CH03" else "physical"
	var type_ok: bool = record.power_type == expected_type
	var level_ok: bool = level >= int(record.item_level)
	if record.has("legacy_equip_waiver"):
		var waiver: Dictionary = record.legacy_equip_waiver
		var legacy: Dictionary = record.legacy
		if hero_id in waiver.hero_ids and hero_id in legacy.referenced_heroes:
			type_ok = type_ok or bool(waiver.type)
			level_ok = level_ok or (bool(waiver.level) and hero_id in waiver.get("level_hero_ids", waiver.hero_ids))
	return type_ok and level_ok

static func _validate_waiver(record: Dictionary, errors: Array[String]) -> void:
	var waiver: Variant = record.legacy_equip_waiver
	var legacy: Variant = record.get("legacy")
	if not str(record.source_event_id).begins_with("migration:") or not legacy is Dictionary or legacy.get("template_id") != record.template_id or not legacy.get("referenced_heroes") is Array:
		errors.append("Legacy equip waiver requires matching migration evidence.")
		return
	if not waiver is Dictionary or not waiver.has_all(["hero_ids", "type", "level"]) or not waiver.hero_ids is Array or not waiver.type is bool or not waiver.level is bool:
		errors.append("Malformed legacy equip waiver.")
		return
	if waiver.hero_ids.size() > 3:
		errors.append("Legacy equip waiver has too many heroes.")
		return
	if waiver.has("level_hero_ids"):
		if not waiver.level_hero_ids is Array or waiver.level_hero_ids.size() > waiver.hero_ids.size():
			errors.append("Malformed per-hero level waiver.")
			return
		var levels_seen := {}
		for hero_id: Variant in waiver.level_hero_ids:
			if not hero_id is String or hero_id not in waiver.hero_ids or levels_seen.has(hero_id):
				errors.append("Level waiver must be a unique subset of original hero references.")
			levels_seen[hero_id] = true
		if waiver.level != not waiver.level_hero_ids.is_empty(): errors.append("Level waiver flag must match its eligible hero subset.")
	var seen := {}
	for hero_id: Variant in waiver.hero_ids:
		if not hero_id is String or Registry.hero(str(hero_id)).is_empty() or hero_id not in legacy.referenced_heroes or seen.has(hero_id): errors.append("Legacy equip waiver cannot extend to another hero.")
		seen[hero_id] = true
	for hero_id: Variant in legacy.referenced_heroes:
		if not hero_id is String or Registry.hero(str(hero_id)).is_empty(): errors.append("Unknown hero in legacy migration evidence.")

static func _validate_ledger(ledger: Variant, materials: bool, errors: Array[String]) -> void:
	if not ledger is Array:
		errors.append("Payment ledger must be an array of value records.")
		return
	var seen := {}
	for entry: Variant in ledger:
		if not entry is Dictionary or not _nonempty_string(entry.get("event_id")) or not _nonnegative_integer(entry.get("amount")):
			errors.append("Malformed payment ledger entry.")
			continue
		var identity := str(entry.event_id)
		if materials:
			if not _nonempty_string(entry.get("material_id")) or not _nonempty_string(entry.get("kind")): errors.append("Material ledger must retain material identity and payment kind.")
			identity += ":" + str(entry.get("material_id")) + ":" + str(entry.get("kind"))
		if seen.has(identity): errors.append("Duplicate payment ledger entry.")
		seen[identity] = true

static func _nonempty_string(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _nonnegative_integer(value: Variant) -> bool:
	return _integer_in(value, 0, 9007199254740991)

static func _value_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	if value == null or value is String or value is bool or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		for child: Variant in value:
			if not _value_tree(child, depth + 1): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _value_tree(value[key], depth + 1): return false
		return true
	return false

## Authored numerical config uses finite decimal literals, not precomputed floats.
static func _fraction(number: Variant) -> Array[int]:
	var decimal := str(number)
	var parts := decimal.split(".")
	if parts.size() == 1: return [int(decimal), 1]
	var denominator := 1
	for index in parts[1].length(): denominator *= 10
	var numerator := int(parts[0]) * denominator + int(parts[1])
	return _reduce_fraction([numerator, denominator])

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(1, absi(a))

static func _reduce_fraction(value: Array[int]) -> Array[int]:
	var divisor := _gcd(value[0], value[1])
	@warning_ignore("integer_division")
	return [value[0] / divisor, value[1] / divisor]

static func _multiply_fraction(a: Array[int], b: Array[int]) -> Array[int]:
	# Cross-reduce before multiplication to keep exact products in signed int64.
	var first := _gcd(a[0], b[1])
	var second := _gcd(b[0], a[1])
	@warning_ignore("integer_division")
	return [(a[0] / first) * (b[0] / second), (a[1] / second) * (b[1] / first)]

static func _add_fraction(a: Array[int], b: Array[int]) -> Array[int]:
	var divisor := _gcd(a[1], b[1])
	@warning_ignore("integer_division")
	return _reduce_fraction([a[0] * (b[1] / divisor) + b[0] * (a[1] / divisor), a[1] * (b[1] / divisor)])

static func _interpolate_fraction(minimum: Variant, maximum: Variant, quantile: int, steps: int) -> Array[int]:
	var low := _fraction(minimum)
	var high := _fraction(maximum)
	var difference := _add_fraction(high, [-low[0], low[1]])
	return _add_fraction(low, _multiply_fraction(difference, [quantile, steps]))

static func _round_fraction(value: Array[int]) -> int:
	@warning_ignore("integer_division")
	var whole := value[0] / value[1]
	return whole + (1 if 2 * (value[0] % value[1]) >= value[1] else 0)
