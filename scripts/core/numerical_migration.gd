class_name NumericalMigration
extends RefCounted
## Pure, deterministic conversion at camp. No profile reads, writes, RNG, clocks,
## rewards or balance side effects. The caller validates and commits one document.
const Rules = preload("res://config/numerical_rules.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Economy = preload("res://scripts/core/economy_history.gd")
const HEROES := ["CH01", "CH02", "CH03"]
const VERSION := 1
const EVENT := "migration:numerical_v2"
const OLD_XP := [0, 30, 70, 120, 170, 230, 290, 360, 630, 900, 1170, 1440, 1710, 1980, 2250, 2520, 2790, 3060, 3330, 3600]
const POWER_STATES := ["burn", "shock", "chill", "corrosion", "bleed"]

## The active receipt is an explicit guard, not an instruction to abandon it.
## Existing legacy adventures must settle using their entire original ruleset.
## {} means reject/defer; no input value has been modified on either path.
static func migrate_profile(profile: Dictionary, event_id: String = EVENT, active_run: Variant = null) -> Dictionary:
	if active_run != null or not _tree(profile): return {}
	if not _integer(profile.get("ruleset_version", 1), 1, 2): return {}
	if int(profile.get("ruleset_version", 1)) == 2:
		var upgraded: Dictionary = load("res://scripts/core/equipment_class_migration.gd").upgrade_profile(profile)
		return upgraded if _valid_v2(upgraded) else {}
	if not _integer(profile.get("scale_version", 1), 1, 1) or not _valid_old(profile): return {}
	for field in ["equipment_instance_version", "reward_policy_version", "optional_chest_receipt_version"]:
		var legacy_version := 0 if field == "equipment_instance_version" else 1
		if profile.has(field) and not _integer(profile[field], legacy_version, legacy_version): return {}
	if not event_id.begins_with("migration:") or event_id.length() <= 10 or event_id.length() > 120: return {}
	# Existing conversion evidence alongside a legacy version is a mixed/partial
	# transaction, never a reason to generate a second inventory.
	if profile.has("numerical_migration"): return {}
	var next := profile.duplicate(true)
	var original := {}
	for key in ["hero_xp", "equipment", "loadout", "loadout_presets"]:
		if profile.has(key): original[key] = profile[key].duplicate(true)
	var item_level := 1
	for hero: String in HEROES:
		item_level = maxi(item_level, old_level(int(profile.hero_xp[hero])))
		next.hero_xp[hero] = migrate_xp(int(profile.hero_xp[hero]))
	item_level = mini(item_level, Growth.level_cap())
	var identities := {}
	var equipment := {}
	var ids: Array = profile.equipment.keys()
	ids.sort()
	for template_id: String in ids:
		var referenced := _references(profile, template_id)
		var power := _power_type(profile, template_id, referenced)
		var template := Registry.equipment(template_id)
		var rarity := "green" if str(template.get("set_id", "")).is_empty() else "purple"
		var main := {}
		for key: String in Instances.main_keys(template_id, power): main[key] = 50
		var affixes: Array = []
		var legal := Instances.legal_affixes(template_id, power)
		var chosen: Array[String] = []
		# Legal original tendencies retain their authored order; the fallback
		# follows the stable config order, never dictionary ownership order.
		for key: String in template.base_stats:
			if key in legal: chosen.append(key)
		for key: String in legal:
			if key not in chosen: chosen.append(key)
		var count := int(Rules.value("rarities")[rarity].affix_count)
		for index in count: affixes.append({"type":chosen[index], "u":50})
		var rank := int(profile.equipment[template_id].level)
		var steps: Array = []
		for index in rank:
			steps.append({"g":10, "pity":0, "base_price_peak":canonical_step_price(index + 1, item_level)})
		var instance_id := event_id + ":" + template_id
		var spec := {"instance_id":instance_id, "template_id":template_id, "source_event_id":event_id,
			"item_level":item_level, "rarity":rarity, "power_type":power, "main_rolls":main,
			"affix_type_and_quantile":affixes, "enhancement_rank":rank, "enhancement_steps":steps,
			"enhancement_gold_ledger":_paid_enhancements(profile, template_id, rank), "material_ledger":[],
			"purchase_baseline_gold":_green_purchase_baseline(template_id, item_level),
			"location":"equipped" if template_id in profile.loadout.values() else "inventory",
			"legacy":{"template_id":template_id, "referenced_heroes":referenced,
				"owned":profile.equipment[template_id].duplicate(true), "base_stats":template.base_stats.duplicate(true)}}
		if not referenced.is_empty():
			var level_heroes: Array[String] = []
			for hero: String in referenced:
				if old_level(int(profile.hero_xp[hero])) < item_level: level_heroes.append(hero)
			spec["legacy_equip_waiver"] = {"hero_ids":referenced.duplicate(), "type":true, "level":not level_heroes.is_empty(), "level_hero_ids":level_heroes}
		var instance := Instances.create(spec)
		if instance.is_empty(): return {}
		identities[template_id] = instance_id
		equipment[instance_id] = instance
	next.equipment = equipment
	next.loadout = _translate_loadout(profile.loadout, identities)
	if profile.has("loadout_presets"):
		next.loadout_presets = {}
		for hero: String in HEROES:
			if profile.loadout_presets.has(hero): next.loadout_presets[hero] = _translate_loadout(profile.loadout_presets[hero], identities)
	next["ruleset_version"] = 2
	next["scale_version"] = 10
	next["equipment_instance_version"] = int(Rules.versions().equipment_instance)
	next["reward_policy_version"] = int(Rules.versions().reward_policy)
	next["optional_chest_receipt_version"] = int(Rules.versions().optional_chest_receipt)
	for field in ["talents", "research_xp", "materials", "progression_receipts"]:
		if not next.has(field): next[field] = {}
	next["gold_pity"] = {"B01":0, "B02":0, "B03":0, "B04":0}
	next["numerical_migration"] = {"version":VERSION, "event_id":event_id, "original":original, "template_instance_ids":identities}
	next["hero_role_revision"] = 1
	next = load("res://scripts/core/equipment_class_migration.gd").upgrade_profile(next)
	return _json_keys(next) if _valid_v2(next) else {}

static func old_level(xp: int) -> int:
	var level := 1
	for index in OLD_XP.size():
		if xp < OLD_XP[index]: break
		level = index + 1
	return level

static func migrate_xp(xp: int) -> int:
	if xp < 0 or xp > int(OLD_XP.back()): return -1
	var level := old_level(xp)
	var thresholds := Growth.thresholds()
	if level >= thresholds.size(): return int(thresholds.back())
	var before := int(OLD_XP[level - 1])
	var span := int(OLD_XP[level]) - before
	var new_span := int(thresholds[level]) - int(thresholds[level - 1])
	@warning_ignore("integer_division")
	return int(thresholds[level - 1]) + (xp - before) * new_span / span

## Ceil complete canonical price, using exact rational config arithmetic.
static func canonical_step_price(rank: int, item_level: int) -> int:
	var costs: Array = Rules.value("enhancement_gold")
	if rank < 1 or rank > costs.size() or item_level < 1 or item_level > Growth.level_cap(): return -1
	return _cost_ceil(int(costs[rank - 1]), item_level)

static func _cost_ceil(base: int, item_level: int, multiplier: Array[int] = [1, 1]) -> int:
	var factor := Instances._add_fraction([1, 1], Instances._multiply_fraction(Instances._fraction(Rules.value("cost_item_level_per_level")), [item_level - 1, 1]))
	var cost := Instances._multiply_fraction(Instances._multiply_fraction([base, 1], factor), multiplier)
	@warning_ignore("integer_division")
	return cost[0] / cost[1] + (1 if cost[0] % cost[1] else 0)

static func _green_purchase_baseline(template_id: String, item_level: int) -> int:
	return _cost_ceil(int(Registry.equipment(template_id).price), item_level, Instances._fraction(Rules.value("shop_price_multiplier").green))

static func _references(profile: Dictionary, template_id: String) -> Array[String]:
	var result: Array[String] = []
	if template_id in profile.loadout.values(): result.append(str(profile.selected_hero))
	for hero: String in HEROES:
		if template_id in profile.get("loadout_presets", {}).get(hero, {}).values() and hero not in result: result.append(hero)
	return result

static func _power_type(profile: Dictionary, template_id: String, referenced: Array[String]) -> String:
	if not referenced.is_empty():
		var hero := str(profile.selected_hero) if str(profile.selected_hero) in referenced else referenced[0]
		return "magic" if hero == "CH03" else "physical"
	return "magic" if float(Registry.equipment(template_id).base_stats.get("ability_power", 0)) > 0.0 else "physical"

static func _translate_loadout(loadout: Dictionary, identities: Dictionary) -> Dictionary:
	var result := {}
	for slot: String in Registry.slots(2): result[slot] = identities.get(loadout.get(slot, ""), "")
	return result

## JSON writers sort receipt keys, so dictionary iteration cannot establish
## sale/reacquisition chronology. Any historical sale makes ownership ambiguous:
## retain receipts for audit but never refund a previous sold item's investment.
static func _paid_enhancements(profile: Dictionary, template_id: String, rank: int) -> Array:
	var result: Array = []
	var ranks := {}
	var receipts: Dictionary = profile.get("applied_transactions", {})
	for row: Dictionary in receipts.values():
		if row.get("kind") == "sale" and row.get("items", {}).has(template_id): return []
	var events: Array = receipts.keys()
	events.sort()
	for event_id: String in events:
		var row: Dictionary = receipts[event_id]
		if row.get("kind") != "upgrade" or row.get("item") != template_id: continue
		var version := int(row.get("economy_version", 1))
		var paid_rank := int(row.get("level", -1))
		if paid_rank <= 0 or paid_rank > rank or not Economy.supported(version) or not _integer(row.get("price"), 0, 1000000000000) or Economy.upgrade_price(paid_rank, version) != int(row.price): continue
		if ranks.has(paid_rank): return []
		ranks[paid_rank] = true
		result.append({"event_id":event_id, "amount":int(row.price), "kind":"enhancement", "rank":paid_rank, "legacy_economy_version":version})
	return result

static func _valid_old(profile: Dictionary) -> bool:
	if profile.get("selected_hero") not in HEROES or not _xp_valid(profile.get("hero_xp")): return false
	if not profile.get("equipment") is Dictionary or profile.equipment.size() > Registry.equipment_ids().size(): return false
	for id: Variant in profile.equipment:
		if not (id is String or id is StringName) or Registry.equipment(str(id)).is_empty() or not profile.equipment[id] is Dictionary or not _integer(profile.equipment[id].get("level"), 0, Economy.maximum_level(1)): return false
	if not _old_loadout_valid(profile.get("loadout"), profile.equipment, false): return false
	var presets: Variant = profile.get("loadout_presets", {})
	if not presets is Dictionary: return false
	for hero: Variant in presets:
		if hero not in HEROES or not _old_loadout_valid(presets[hero], profile.equipment, true): return false
	var receipts: Variant = profile.get("applied_transactions", {})
	if not receipts is Dictionary: return false
	for event: Variant in receipts:
		if not event is String or event.is_empty() or event.length() > 160 or not receipts[event] is Dictionary: return false
		var row: Dictionary = receipts[event]
		if row.get("kind") == "sale" and not row.get("items") is Dictionary: return false
		if row.get("kind") == "purchase_set" and not row.get("items") is Array: return false
		if row.get("kind") == "upgrade":
			if not _integer(row.get("level"), 1, 5) or not _integer(row.get("economy_version", 1), 1, 1) or not _integer(row.get("price"), 0, 1000000000000): return false
	return true

static func _old_loadout_valid(value: Variant, equipment: Dictionary, preset: bool) -> bool:
	if not value is Dictionary or value.size() != Registry.slots().size(): return false
	for slot: String in Registry.slots():
		var id: Variant = value.get(slot)
		if not id is String: return false
		if preset and id.is_empty(): continue
		if Registry.equipment(id).get("slot") != slot or (not preset and not equipment.has(id)): return false
	return true

static func _valid_v2(profile: Dictionary) -> bool:
	if not _integer(profile.get("ruleset_version"), 2, 2) or not _integer(profile.get("scale_version"), 10, 10): return false
	for pair: Array in [["equipment_instance_version", int(Rules.versions().equipment_instance)], ["reward_policy_version", int(Rules.versions().reward_policy)], ["optional_chest_receipt_version", int(Rules.versions().optional_chest_receipt)]]:
		if not _integer(profile.get(pair[0]), pair[1], pair[1]): return false
	if profile.get("selected_hero") not in HEROES or not _xp_valid(profile.get("hero_xp")) or not profile.get("equipment") is Dictionary: return false
	for id: Variant in profile.equipment:
		if not id is String or not profile.equipment[id] is Dictionary or profile.equipment[id].get("instance_id") != id or not Instances.validate(profile.equipment[id]).is_empty(): return false
	if not _v2_loadout_valid(profile.get("loadout"), profile.equipment, str(profile.selected_hero), Growth.level_for_xp(int(profile.hero_xp[profile.selected_hero]))): return false
	var presets: Variant = profile.get("loadout_presets", {})
	if not presets is Dictionary: return false
	for hero: Variant in presets:
		if hero not in HEROES or not _v2_loadout_valid(presets[hero], profile.equipment, hero, Growth.level_for_xp(int(profile.hero_xp[hero]))): return false
	return true

static func _v2_loadout_valid(value: Variant, equipment: Dictionary, hero: String, level: int) -> bool:
	if not value is Dictionary or value.size() != Registry.slots(2).size(): return false
	for slot: String in Registry.slots(2):
		var id: Variant = value.get(slot)
		if not id is String: return false
		if id.is_empty(): continue
		if not equipment.has(id) or Registry.equipment(str(equipment[id].template_id), 2).slot != slot or not Instances.can_equip(equipment[id], hero, level): return false
	return true

static func _xp_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != HEROES.size(): return false
	for hero: String in HEROES:
		if not _integer(value.get(hero), 0, 3600): return false
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1000000000000.0

static func _tree(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	if value == null or value is String or value is bool: return true
	if value is int or value is float: return is_finite(float(value)) and absf(float(value)) <= 1000000000000.0
	if value is Array:
		for child: Variant in value:
			if not _tree(child, depth + 1): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _tree(value[key], depth + 1): return false
		return true
	return false

## A detached runtime conversion helper, never used inside an active old run.
## It does not infer a fresh actor from a receipt and never invokes event/tick.
## Timers, ICDs, percentages, counters, coordinates and cooldown refunds stay put.
static func migrate_runtime(snapshot: Dictionary, old_stats: Dictionary, new_stats: Dictionary) -> Dictionary:
	if not _tree(snapshot) or not _runtime_valid(snapshot) or not _maxima_valid(old_stats) or not _maxima_valid(new_stats): return {}
	if not _integer(new_stats.max_hp, 1, 1000000000000) or not _integer(new_stats.resource_max, 0, 1000000000000): return {}
	if not _integer(snapshot.get("scale_version", 1), 1, 10): return {}
	var scale := int(snapshot.get("scale_version", 1))
	if scale == 10:
		return snapshot.duplicate(true) if _valid_scaled_runtime(snapshot, new_stats) else {}
	if scale != 1 or not _integer(snapshot.get("ruleset_version", 1), 1, 1): return {}
	for field in ["resource_regen_remainder", "resource_decay_remainder"]:
		if snapshot.has(field): return {}
	if float(snapshot.hp) > float(old_stats.max_hp) or float(snapshot.resource) > float(old_stats.resource_max): return {}
	var result := snapshot.duplicate(true)
	result.hp = conservative_amount(float(snapshot.hp), float(old_stats.max_hp), float(new_stats.max_hp))
	result.resource = conservative_amount(float(snapshot.resource), float(old_stats.resource_max), float(new_stats.resource_max))
	if result.has("shield"): result.shield = conservative_amount(float(result.shield), float(old_stats.max_hp), float(new_stats.max_hp))
	if result.has("status"):
		for id: String in result.status.states:
			if id in POWER_STATES:
				for field: String in ["power", "H"]: result.status.states[id][field] = Rules.integer(float(result.status.states[id][field]) * 10.0)
			else:
				result.status.states[id].H = Rules.integer(float(result.status.states[id].H))
		for source: String in result.status.guards:
			result.status.guards[source].amount = conservative_amount(float(result.status.guards[source].amount), float(old_stats.max_hp), float(new_stats.max_hp))
	if result.has("equipment"):
		# Legacy healing history stores ratios; V2 stores settled healing units.
		for entry: Dictionary in result.equipment.get("heal_history", []): entry.amount = Rules.integer(float(entry.amount) * float(new_stats.max_hp))
		for entry: Dictionary in result.equipment.get("resource_history", []): entry.amount = Rules.integer(float(entry.amount) * 10.0)
		for origin: Dictionary in result.equipment.get("adapter", {}).get("self_status_sources", {}).values(): origin.H = Rules.integer(float(origin.H))
	result["ruleset_version"] = 2
	result["scale_version"] = 10
	result["resource_regen_remainder"] = 0.0
	result["resource_decay_remainder"] = 0.0
	return _json_keys(result)

static func conservative_amount(amount: float, old_maximum: float, new_maximum: float) -> int:
	if not is_finite(amount) or not is_finite(old_maximum) or not is_finite(new_maximum) or amount < 0.0 or old_maximum < 0.0 or new_maximum < 0.0: return -1
	if old_maximum == 0.0: return 0 if amount == 0.0 else -1
	var bounded := minf(amount * 10.0, minf(new_maximum, new_maximum * amount / old_maximum))
	var converted := mini(int(floor(new_maximum)), Rules.integer(bounded))
	# Quantization must not erase the last deficit of a damaged/spent bar.
	if amount < old_maximum and converted >= new_maximum and new_maximum > 0.0:
		converted = maxi(0, int(ceil(new_maximum)) - 1)
	return converted

static func _valid_scaled_runtime(snapshot: Dictionary, stats: Dictionary) -> bool:
	if not _integer(snapshot.get("ruleset_version"), 2, 2) or not _integer(snapshot.hp, 0, int(stats.max_hp)) or not _integer(snapshot.resource, 0, int(stats.resource_max)): return false
	for field in ["resource_regen_remainder", "resource_decay_remainder"]:
		if not _number(snapshot.get(field)) or float(snapshot[field]) >= 1.0: return false
	if snapshot.has("shield") and not _integer(snapshot.shield, 0, 1000000000000): return false
	for id: String in snapshot.status.states:
		var state: Dictionary = snapshot.status.states[id]
		if not _integer(state.H, 0, 1000000000000): return false
		if id in POWER_STATES and not _integer(state.power, 0, 1000000000000): return false
	for guard: Dictionary in snapshot.status.guards.values():
		if not _integer(guard.amount, 0, 1000000000000): return false
	for key in ["heal_history", "resource_history"]:
		for entry: Dictionary in snapshot.equipment.get(key, []):
			if not _integer(entry.amount, 0, 1000000000000): return false
	for origin: Dictionary in snapshot.equipment.get("adapter", {}).get("self_status_sources", {}).values():
		if not _integer(origin.H, 0, 1000000000000): return false
	return true

static func _maxima_valid(stats: Dictionary) -> bool:
	return _number(stats.get("max_hp")) and float(stats.max_hp) > 0.0 and _number(stats.get("resource_max"))

static func _runtime_valid(snapshot: Dictionary) -> bool:
	if not _integer(snapshot.get("snapshot_version"), 1, 1): return false
	if snapshot.get("mode") != "safe_boundary" or snapshot.get("hero_id") not in HEROES or not _number(snapshot.get("hp")) or not _number(snapshot.get("resource")): return false
	if snapshot.has("shield") and not _number(snapshot.shield): return false
	if snapshot.get("mode") == "safe_boundary" and (not snapshot.get("player") is Dictionary or not snapshot.get("status") is Dictionary or not snapshot.get("equipment") is Dictionary): return false
	if snapshot.has("status"):
		if not snapshot.status is Dictionary or not snapshot.status.get("states") is Dictionary or not snapshot.status.get("guards") is Dictionary: return false
		for id: Variant in snapshot.status.states:
			var state: Variant = snapshot.status.states[id]
			if id not in POWER_STATES + ["damage_reduction", "brace_guard", "invulnerable", "grievous"] or not state is Dictionary or not _number(state.get("power")) or not _number(state.get("H")): return false
		for source: Variant in snapshot.status.guards:
			if not snapshot.status.guards[source] is Dictionary or not _number(snapshot.status.guards[source].get("amount")): return false
	if snapshot.has("equipment"):
		if not snapshot.equipment is Dictionary: return false
		var adapter: Variant = snapshot.equipment.get("adapter", {})
		if not adapter is Dictionary or not adapter.get("self_status_sources", {}) is Dictionary: return false
		for origin: Variant in adapter.get("self_status_sources", {}).values():
			if not origin is Dictionary or not _number(origin.get("H")): return false
		for key in ["heal_history", "resource_history"]:
			if not snapshot.equipment.get(key, []) is Array: return false
			for entry: Variant in snapshot.equipment.get(key, []):
				if not entry is Dictionary or not _number(entry.get("amount")): return false
	return true

## Normalize engine-only key names without JSON's lossy numeric reparse.
static func _json_keys(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[str(key)] = _json_keys(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_json_keys(child))
		return result
	return value
