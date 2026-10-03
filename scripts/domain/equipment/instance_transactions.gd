class_name InstanceTransactions
extends RefCounted
## Pure camp transactions. The caller commits profile before revealing receipt.
## Failed saves must retain operation_id/request and the proposed candidate. Quotes
## contain no rolls; caller-supplied seeds/rolls are deliberately not accepted.
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Expedition = preload("res://scripts/app/expedition_controller.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const VERSION := 1 # Ledger envelope remains compatible with mixed historical receipts.
const RECEIPT_VERSION := 4
const MAX_NUMBER := 1_000_000_000_000
const MAX_PROFILE_BYTES := 32 * 1024 * 1024
const KINDS := ["purchase", "craft", "complete_set"]

static func purchase(profile: Dictionary, operation_id: String, request: Dictionary) -> Dictionary:
	return _transact(profile, operation_id, request, "purchase")

static func craft(profile: Dictionary, operation_id: String, request: Dictionary) -> Dictionary:
	return _transact(profile, operation_id, request, "craft")

static func complete_set(profile: Dictionary, operation_id: String, request: Dictionary) -> Dictionary:
	return _transact(profile, operation_id, request, "complete_set")

static func quote_purchase(profile: Dictionary, request: Dictionary) -> Dictionary:
	return _quote(profile, request, "purchase")

static func quote_craft(profile: Dictionary, request: Dictionary) -> Dictionary:
	return _quote(profile, request, "craft")

static func quote_set(profile: Dictionary, request: Dictionary) -> Dictionary:
	return _quote(profile, request, "complete_set")

static func _transact(profile: Dictionary, operation_id: String, request: Dictionary, kind: String) -> Dictionary:
	if not _id(operation_id): return _reject("INVALID_OPERATION_ID")
	var canonical := _request(request, kind)
	if canonical.is_empty(): return _reject("INVALID_REQUEST")
	var error := _profile_error(profile)
	if not error.is_empty(): return _reject(error)
	var ledger: Dictionary = profile.get("instance_transactions", {"version":VERSION, "operations":{}})
	var fingerprint := request_hash(kind, canonical)
	if ledger.operations.has(operation_id):
		var previous: Dictionary = ledger.operations[operation_id]
		if previous.request_hash != fingerprint: return _reject("OPERATION_CONFLICT")
		return {"ok":true, "error":"", "profile":profile.duplicate(true), "receipt":previous.duplicate(true), "replayed":true}
	var quote := _quote(profile, canonical, kind, false)
	if not quote.ok: return quote
	if int(profile.permanent_gold) < int(quote.gold): return _reject("INSUFFICIENT_GOLD")
	var wallet: Dictionary = profile.get("materials", {})
	for material: String in quote.materials:
		if int(wallet.get(material, 0)) < int(quote.materials[material]): return _reject("INSUFFICIENT_MATERIALS")
	var next := profile.duplicate(true)
	var items: Array = []
	var pending: Array[String] = []
	var occupied := 0
	for owned: Dictionary in next.equipment.values():
		if owned.location in ["inventory", "equipped"]: occupied += 1
	var capacity := int(next.get("inventory_capacity", 0))
	for index in quote.template_ids.size():
		var location := "pending" if capacity > 0 and occupied >= capacity else "inventory"
		var item := _create_item(kind, canonical, operation_id, fingerprint, str(quote.template_ids[index]), index, location)
		if item.is_empty(): return _reject("GENERATION_FAILED")
		if next.equipment.has(item.instance_id): return _reject("INSTANCE_ID_CONFLICT")
		next.equipment[item.instance_id] = item.duplicate(true)
		items.append(item)
		if location == "pending": pending.append(item.instance_id)
		else: occupied += 1
		next["equipment_discoveries"] = next.get("equipment_discoveries", [])
		if item.template_id not in next.equipment_discoveries: next.equipment_discoveries.append(item.template_id)
	next.permanent_gold = int(next.permanent_gold) - int(quote.gold)
	next["materials"] = wallet.duplicate(true)
	for material: String in quote.materials: next.materials[material] = int(next.materials.get(material, 0)) - int(quote.materials[material])
	var receipt := {"version":RECEIPT_VERSION, "operation_id":operation_id, "kind":kind, "request":canonical.duplicate(true), "request_hash":fingerprint,
		"gold":int(quote.gold), "materials":quote.materials.duplicate(true), "items":items, "pending_instance_ids":pending}
	receipt["result_hash"] = _receipt_hash(receipt)
	next["instance_transactions"] = ledger.duplicate(true)
	next.instance_transactions.operations[operation_id] = receipt.duplicate(true)
	# No arbitrary 96/124 item or 4096 operation cap. Never evict old IDs, which
	# would reopen replay. The authoritative document writer also checks envelope.
	if JSON.stringify(next).to_utf8_buffer().size() > MAX_PROFILE_BYTES: return _reject("PROFILE_CAPACITY")
	return {"ok":true, "error":"", "profile":next, "receipt":receipt.duplicate(true), "replayed":false}

static func _quote(profile: Dictionary, request: Dictionary, kind: String, check_profile: bool = true) -> Dictionary:
	var canonical := _request(request, kind)
	if canonical.is_empty(): return _reject("INVALID_REQUEST")
	if check_profile:
		var profile_error := _profile_error(profile)
		if not profile_error.is_empty(): return _reject(profile_error)
	if canonical.hero_id != profile.selected_hero: return _reject("HERO_CONTEXT_CHANGED")
	var level := Growth.level_for_xp(int(profile.hero_xp[canonical.hero_id]))
	if int(canonical.item_level) > level: return _reject("ITEM_LEVEL_LOCKED")
	if kind == "craft" and level < Economy.crafting_unlock_level(canonical.rarity): return _reject("CRAFT_LEVEL_LOCKED")
	var templates := _templates(canonical, kind)
	if templates.is_empty(): return _reject("INVALID_TEMPLATES")
	for template_id: String in templates:
		var template := Registry.equipment(template_id, 2)
		if bool(template.get("reward_only", false)): return _reject("REWARD_ONLY_TEMPLATE")
		if str(template.get("race_id", "")) == "B10" and not Expedition.unlocked_biomes(profile).has("B10"): return _reject("TEMPLATE_REGION_LOCKED")
		var allowed: Array = template.get("allowed_heroes", [])
		if allowed.size() == 1 and canonical.power_type != Registry.ClassPolicy.power_type(str(allowed[0])): return _reject("CLASS_POWER_MISMATCH")
		var boss := str(template.get("unlock_boss", ""))
		if not boss.is_empty() and boss not in profile.get("bosses", []): return _reject("TEMPLATE_LOCKED")
		if kind == "complete_set":
			for owned: Dictionary in profile.equipment.values():
				if owned.template_id == template_id and owned.power_type == canonical.power_type: return _reject("SET_PIECE_ALREADY_OWNED")
	var cost := _cost(canonical, kind)
	if cost.is_empty(): return _reject("INVALID_COST")
	var historical_cost := Economy.historical_creation_cost(canonical, kind, RECEIPT_VERSION)
	if historical_cost.is_empty() or cost.gold != historical_cost.gold or not _same_materials(cost.materials, historical_cost.materials): return _reject("ECONOMY_VERSION_MISMATCH")
	var generation_error := Acquisition.current_version_error()
	if not generation_error.is_empty(): return _reject(generation_error)
	var occupied := 0
	for owned: Dictionary in profile.equipment.values():
		if owned.location in ["inventory", "equipped"]: occupied += 1
	var capacity := int(profile.get("inventory_capacity", 0))
	var pending_count := maxi(0, templates.size() - maxi(0, capacity - occupied)) if capacity > 0 else 0
	var result := {"ok":true, "error":"", "gold":int(cost.gold), "materials":cost.materials.duplicate(true), "template_ids":templates,
		"request":canonical.duplicate(true), "set_slot_count":8 if kind == "complete_set" else 0, "pending_count":pending_count}
	if kind == "complete_set":
		result["all_template_ids"] = Registry.set_item_ids(canonical.set_id, 2)
		result["missing_template_ids"] = missing_set_templates(profile, canonical.set_id, canonical.power_type)
	return result

static func missing_set_templates(profile: Dictionary, set_id: String, power_type: String) -> Array[String]:
	var missing: Array[String] = []
	if power_type not in ["physical", "magic"] or not profile.get("equipment") is Dictionary: return missing
	for template_id: String in Registry.set_item_ids(set_id, 2):
		var owned := false
		for item: Variant in profile.equipment.values():
			if item is Dictionary and item.get("template_id") == template_id and item.get("power_type") == power_type: owned = true
		if not owned: missing.append(template_id)
	missing.sort()
	return missing

## Optional absent field is a valid early V2 save. ProfileStore uses this on load;
## legacy applied_transactions is neither rewritten nor read as a V2 ledger.
static func validate_ledger(value: Variant) -> bool:
	if value == null: return true
	if not value is Dictionary or not _integer(value.get("version"), VERSION, VERSION) or not value.get("operations") is Dictionary: return false
	if value.size() != 2: return false
	for operation_id: Variant in value.operations:
		if not _id(operation_id) or not _valid_receipt(operation_id, value.operations[operation_id]): return false
	return true

static func _valid_receipt(operation_id: String, value: Variant) -> bool:
	if not value is Dictionary or value.size() != 10 or not value.has_all(["version", "operation_id", "kind", "request", "request_hash", "gold", "materials", "items", "pending_instance_ids", "result_hash"]): return false
	if not _integer(value.version, 1, RECEIPT_VERSION) or value.operation_id != operation_id or value.kind not in KINDS or not value.request is Dictionary: return false
	var canonical := _request(value.request, value.kind, true, int(value.version))
	if canonical.is_empty() or value.request_hash != request_hash(value.kind, canonical): return false
	if not _integer(value.gold, 0, MAX_NUMBER) or not value.materials is Dictionary or not value.items is Array or not value.pending_instance_ids is Array: return false
	var templates := _templates(canonical, value.kind)
	var cost := Economy.historical_creation_cost(canonical, value.kind, int(value.version))
	if cost.is_empty() or int(value.gold) != int(cost.gold) or not _same_materials(value.materials, cost.materials) or value.items.size() != templates.size(): return false
	var pending: Array[String] = []
	for index in templates.size():
		var item: Variant = value.items[index]
		if not item is Dictionary or not Instances.validate(item).is_empty() or item.location not in ["inventory", "pending"]: return false
		if item.instance_id != _instance_id(operation_id, index) or item.source_event_id != "transaction:" + operation_id: return false
		if item.template_id != templates[index] or item.rarity != canonical.rarity or item.power_type != canonical.power_type or int(item.item_level) != int(canonical.item_level): return false
		if int(item.enhancement_rank) != 0 or not item.enhancement_steps.is_empty() or not item.enhancement_gold_ledger.is_empty() or not item.material_ledger.is_empty() or not item.enhancement_reroll_history.is_empty(): return false
		if item.get("purchase_baseline_gold") != Economy.historical_purchase_baseline(item.template_id, item.rarity, int(item.item_level), int(value.version)): return false
		if item.location == "pending": pending.append(item.instance_id)
	return pending == value.pending_instance_ids and value.result_hash == _receipt_hash(value)

## Numeric JSON round trips turn integers into floats. Canonicalize integral
## numbers before sealing, so a load verifies frozen results without new RNG.
static func _receipt_hash(receipt: Dictionary) -> String:
	var unsigned := receipt.duplicate(true)
	unsigned.erase("result_hash")
	return JSON.stringify(_canonical_values(unsigned), "", true, true).sha256_text()

static func _canonical_values(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_canonical_values(child))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[str(key)] = _canonical_values(value[key])
		return result
	return value

static func _same_materials(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for material: String in expected:
		if not _integer(actual.get(material), int(expected[material]), int(expected[material])): return false
	return true

static func _profile_error(profile: Dictionary) -> String:
	if not _tree(profile) or not _integer(profile.get("ruleset_version"), 2, 2): return "INVALID_PROFILE"
	if not profile.get("selected_hero") in ["CH01", "CH02", "CH03"] or not profile.get("hero_xp") is Dictionary: return "INVALID_PROFILE"
	if not _integer(profile.hero_xp.get(profile.selected_hero), 0, MAX_NUMBER) or not _integer(profile.get("permanent_gold"), 0, MAX_NUMBER): return "INVALID_PROFILE"
	if not profile.get("equipment") is Dictionary or not profile.get("bosses", []) is Array or not profile.get("materials", {}) is Dictionary: return "INVALID_PROFILE"
	if not profile.get("equipment_discoveries", []) is Array or not _integer(profile.get("inventory_capacity", 0), 0, MAX_NUMBER): return "INVALID_PROFILE"
	for id: Variant in profile.equipment:
		var record: Variant = profile.equipment[id]
		if not _id(id) or not record is Dictionary or record.get("instance_id") != id or not Instances.validate(record).is_empty(): return "INVALID_PROFILE"
	for id: Variant in profile.get("materials", {}):
		if not _material_id(id) or not _integer(profile.materials[id], 0, MAX_NUMBER): return "INVALID_PROFILE"
	if not validate_ledger(profile.get("instance_transactions")): return "INVALID_TRANSACTION_LEDGER"
	return ""

static func _request(request: Dictionary, kind: String, historical: bool = false, receipt_version: int = RECEIPT_VERSION) -> Dictionary:
	if kind not in KINDS or not _tree(request): return {}
	var required := ["hero_id", "rarity", "power_type", "item_level", "set_id", "template_ids"] if kind == "complete_set" else ["hero_id", "rarity", "power_type", "item_level", "template_id"]
	if request.size() != required.size() or not request.has_all(required): return {}
	if request.hero_id not in ["CH01", "CH02", "CH03"] or request.power_type not in ["physical", "magic"]: return {}
	if not _integer(request.item_level, 1, (20 if receipt_version == 1 else 25 if receipt_version == 2 else 30 if receipt_version == 3 else 50) if historical else Growth.level_cap()) or not request.rarity is String: return {}
	if kind == "craft":
		if (not Economy.V1_FORGE.has(request.rarity)) if historical else (Economy.crafting_unlock_level(request.rarity) < 0): return {}
	elif request.rarity not in ["white", "green"]: return {}
	var result := {"hero_id":request.hero_id, "rarity":request.rarity, "power_type":request.power_type, "item_level":int(request.item_level)}
	if kind == "complete_set":
		if not request.set_id is String or not request.template_ids is Array or request.template_ids.is_empty() or request.template_ids.size() > 8: return {}
		var all: Array = Economy.historical_set_items(request.set_id, receipt_version) if historical else Registry.set_item_ids(request.set_id, 2)
		if all.size() != 8: return {}
		if not historical:
			var slots := {}
			for template_id: String in all: slots[Registry.equipment(template_id, 2).slot] = true
			if slots.size() != 8: return {}
		var selected: Array[String] = []
		for template_id: Variant in request.template_ids:
			if not template_id is String or template_id not in all or template_id in selected: return {}
			selected.append(template_id)
		selected.sort()
		result["set_id"] = request.set_id
		result["template_ids"] = selected
	else:
		if not request.template_id is String or Registry.equipment(request.template_id, 2).is_empty(): return {}
		result["template_id"] = request.template_id
	return result

static func _templates(request: Dictionary, kind: String) -> Array:
	return request.template_ids.duplicate() if kind == "complete_set" else [request.template_id]

static func _cost(request: Dictionary, kind: String) -> Dictionary:
	if kind == "craft": return Economy.crafting_cost(request.template_id, request.rarity, int(request.item_level))
	var gold := 0
	for template_id: String in _templates(request, kind):
		var price := Economy.purchase_price(template_id, request.rarity, int(request.item_level))
		if price < 0: return {}
		gold += price
	return {"gold":Economy.completion_price(gold) if kind == "complete_set" else gold, "materials":{}}

static func _create_item(kind: String, request: Dictionary, operation_id: String, fingerprint: String, template_id: String, index: int, location: String) -> Dictionary:
	var identity := _instance_id(operation_id, index)
	var seed := (operation_id + ":" + fingerprint).sha256_text().substr(0, 13).hex_to_int()
	return Acquisition.roll_item({"instance_id":identity, "source_event_id":"transaction:" + operation_id, "template_id":template_id,
		"rarity":request.rarity, "power_type":request.power_type, "hero_id":request.hero_id, "item_level":int(request.item_level),
		"source":"craft" if kind == "craft" else "purchase", "location":location}, seed)

static func _instance_id(operation_id: String, index: int) -> String:
	return "instance:tx:" + operation_id.sha256_text().substr(0, 32) + ":" + str(index)

static func request_hash(kind: String, canonical_request: Dictionary) -> String:
	return JSON.stringify([kind, canonical_request], "", true, true).sha256_text()

static func _reject(error: String) -> Dictionary:
	return {"ok":false, "error":error, "profile":{}, "receipt":{}, "replayed":false}

static func _id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 160

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _material_id(value: Variant) -> bool:
	if not value is String: return false
	if value == "forge": return true
	for race: String in Economy.RACES:
		if value == "race:" + race or value == "core:" + race: return true
	return false

static func _tree(value: Variant, depth: int = 0) -> bool:
	if depth > 40: return false
	if value is float: return is_finite(value)
	if value == null or value is bool or value is int or value is String: return true
	if value is Array:
		for child: Variant in value:
			if not _tree(child, depth + 1): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _tree(value[key], depth + 1): return false
		return true
	return false
