extends RefCounted
## Equipment behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func equip_relic(id: String) -> bool:
	if host.run == null or host.run.hp <= 0.0 or not host._pending_outcome.is_empty() or not id in ProfileStore.RELIC_IDS or id in host.run.relics:
		return false
	if not host.run.expedition.is_empty(): return false # Expedition offers own selection transactions.
	host.run.relics.append(id)
	if not host._save(host.profile, host.run.receipt()):
		host.run.relics.erase(id)
		host.changed.emit()
		return false
	host.changed.emit()
	return true

func equipment_definition(identifier: String, run_context: bool = false) -> Dictionary:
	var in_run: bool = run_context and host.run != null
	var ruleset: int = host.run.ruleset_version() if in_run else host._profile_ruleset()
	var owned: Dictionary = host.run.equipment_snapshot if in_run else host.profile.get("equipment", {})
	var exists = owned.has(identifier)
	var record: Variant = owned.get(identifier)
	if in_run and ruleset == host.Numbers.V2:
		# Resolve this ID in the same precedence order; inspecting one item must
		# not duplicate the entire camp inventory and every pending drop.
		if not exists:
			var camp: Dictionary = host.profile.get("equipment",{})
			var pending: Dictionary = host.run.expedition.get("pending_equipment",{})
			exists = camp.has(identifier) or pending.has(identifier)
			record = camp[identifier] if camp.has(identifier) else pending.get(identifier)
	if ruleset != host.Numbers.V2 or not exists:
		return ContentRegistry.equipment(identifier, ruleset)
	if not record is Dictionary or record.get("instance_id") != identifier: return {}
	var instance_stats = host.Instances.stats(record)
	if instance_stats.is_empty(): return {}
	var definition: Dictionary = ContentRegistry.equipment(str(record.template_id), ruleset)
	if definition.is_empty(): return {}
	definition["instance_id"] = identifier
	definition["instance_record"] = record.duplicate(true)
	definition["instance_stats"] = instance_stats
	return definition

func equipment_slots(run_context: bool = false) -> Array[String]:
	return ContentRegistry.slots(host.run.ruleset_version() if run_context and host.run != null else host._profile_ruleset())

func _camp_instance_fits(identifier: String, hero: String) -> bool:
	var record: Variant = host.profile.get("equipment", {}).get(identifier)
	if not record is Dictionary or record.get("instance_id") != identifier: return false
	# Pending rewards are owned but are not in the usable camp inventory yet.
	if record.get("location") not in ["inventory", "equipped"]: return false
	return host.Instances.can_equip(record, hero, host.hero_level(hero))

func preview_stats(eq_id: String) -> Dictionary:
	var definition = host.equipment_definition(eq_id)
	if definition.is_empty(): return {}
	if host._profile_ruleset() == host.Numbers.V2 and not host._camp_instance_fits(eq_id, str(host.profile.selected_hero)): return {}
	var loadout: Dictionary = host.profile.loadout.duplicate(true)
	var owned: Dictionary = host.profile.equipment.duplicate(true)
	loadout[definition.slot] = eq_id
	if not owned.has(eq_id): owned[eq_id] = {"level": 0}
	var resolved = StatResolver.resolve(str(host.profile.selected_hero), host.hero_level(), loadout, owned, host._profile_ruleset(), host.hero_talents())
	if resolved.is_empty(): return {}
	resolved.branches = host.hero_branches()
	return resolved

func preview_upgrade_stats(eq_id: String) -> Dictionary:
	# S06 must preview a committed roll vector, never fabricate a legacy +1.
	if host._profile_ruleset() == host.Numbers.V2: return {}
	var definition = host.equipment_definition(eq_id)
	if definition.is_empty() or not host.profile.equipment.has(eq_id): return {}
	var loadout: Dictionary = host.profile.loadout.duplicate(true)
	var owned: Dictionary = host.profile.equipment.duplicate(true)
	loadout[definition.slot] = eq_id
	owned[eq_id].level = mini(5, host.equipment_level(eq_id) + 1)
	var resolved = StatResolver.resolve(str(host.profile.selected_hero), host.hero_level(), loadout, owned, host._profile_ruleset(), host.hero_talents())
	resolved.branches = host.hero_branches()
	return resolved

func hero_loadout(id: String) -> Dictionary:
	var desired: Dictionary = host.profile.get("loadout_presets", {}).get(id, host.profile.loadout).duplicate(true)
	for slot: String in host.equipment_slots():
		var item: String = str(desired.get(slot, ""))
		if host._profile_ruleset() == host.Numbers.V2:
			if not item.is_empty() and not host._camp_instance_fits(item, id): desired[slot] = ""
		elif item.is_empty() or not host.profile.equipment.has(item): desired[slot] = str(host.profile.loadout[slot])
	return desired

func equipment_level(eq_id: String) -> int:
	var field: String = "enhancement_rank" if host._profile_ruleset() == host.Numbers.V2 else "level"
	return int(host.profile.get("equipment", {}).get(eq_id, {}).get(field, 0))

func _legacy_equipment_transaction() -> bool:
	if host._profile_ruleset() != host.Numbers.V2: return true
	host.last_error = "NUMERICAL_TRANSACTION_UNAVAILABLE"
	return false

func upgrade_cost(eq_id: String) -> int:
	if host._profile_ruleset() == host.Numbers.V2:
		var quote = host.quote_forging_v2("enhance", {"instance_id":eq_id})
		return int(quote.get("gold", 0)) if bool(quote.get("ok", false)) else 0
	if not host.profile.equipment.has(eq_id) or host.equipment_level(eq_id) >= 5:
		return 0
	return host.UPGRADE_PRICES[host.equipment_level(eq_id)]

func upgrade_has_gain(eq_id: String) -> bool:
	if host._profile_ruleset() == host.Numbers.V2: return bool(host.quote_forging_v2("enhance", {"instance_id":eq_id}).get("ok", false))
	if not host.profile.equipment.has(eq_id) or host.equipment_level(eq_id) >= 5:
		return false
	var item = ContentRegistry.equipment(eq_id)
	var before = host.preview_stats(eq_id)
	if item.is_empty() or before.is_empty():
		return false
	for key: String in item.get("base_stats", {}):
		if float(item.base_stats[key]) <= 0.0:
			continue
		if key == "crit_chance":
			if float(before.crit_chance) < 0.75:
				return true
		elif key == "crit_multiplier":
			if float(before.crit_multiplier) < 2.5:
				return true
		elif not StatResolver.EQUIPMENT_CAPS.has(key) or float(before.equipment_contribution.get(key, 0.0)) < float(StatResolver.EQUIPMENT_CAPS[key]):
			return true
	# Rounding plateaus remain upgradeable; only fully capped contributions block spending.
	return false

func buy_equipment(eq_id: String, transaction_id: String = "") -> bool:
	host.last_error = ""
	if host._profile_ruleset() == host.Numbers.V2:
		return bool(host.purchase_equipment_v2({"template_id":eq_id,"rarity":"white","power_type":"magic" if host.profile.selected_hero == "CH03" else "physical","item_level":host.hero_level()}, transaction_id).get("ok", false))
	if not host._legacy_equipment_transaction(): return false
	if not host._camp_available():
		return false
	if not transaction_id.is_empty() and host.profile.applied_transactions.has(transaction_id):
		return host._same_transaction(transaction_id, "purchase", eq_id)
	var definition = ContentRegistry.equipment(eq_id)
	if definition.is_empty() or host.profile.equipment.has(eq_id):
		return false
	var boss = str(definition.get("unlock_boss", ""))
	if not boss.is_empty() and not boss in host.profile.bosses:
		return false
	var price: Variant = definition.get("price")
	if not ProfileStore._number(price) or int(price) > int(host.profile.permanent_gold):
		return false
	var id = host._transaction_id(transaction_id)
	if id.is_empty():
		return false
	var next_profile = host.profile.duplicate(true)
	next_profile.permanent_gold = int(next_profile.permanent_gold) - int(price)
	next_profile.equipment[eq_id] = {"level": 0}
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION, "kind": "purchase", "item": eq_id, "price": int(price), "level": 0}
	return host._commit_profile(next_profile)

## Quotes only missing pieces. Rounding is per item, so buying a piece first
## cannot change the discount on any other piece or reset its refinement.
func equipment_set_quote(set_id: String) -> Dictionary:
	if host._profile_ruleset() == host.Numbers.V2:
		var request = host._default_set_request(set_id)
		var ids: Array = ContentRegistry.set_item_ids(set_id, 2)
		if ids.size() != 8: return {}
		var quote = host.quote_equipment_set_v2(request) if not request.template_ids.is_empty() else {"ok":true,"gold":0}
		return {"items":ids,"missing":request.template_ids.duplicate(),"owned":8 - request.template_ids.size(),"price":int(quote.get("gold", 0)),"full_price":int(quote.get("gold", 0)),"locked_boss":"" if quote.get("ok", false) else str(quote.get("error", "")),"request":request}
	var ids = ContentRegistry.set_item_ids(set_id)
	if ids.size() != ContentRegistry.SLOTS.size(): return {}
	var missing: Array[String] = []
	var owned_count = 0
	var full_price = 0
	var price = 0
	var locked_boss = ""
	for eq_id: String in ids:
		var item = ContentRegistry.equipment(eq_id)
		if host.profile.equipment.has(eq_id):
			owned_count += 1
			continue
		missing.append(eq_id)
		full_price += int(item.price)
		price += int(item.price) * 9 / 10
		var boss = str(item.get("unlock_boss", ""))
		if not boss.is_empty() and not boss in host.profile.bosses: locked_boss = boss
	return {"items":ids, "missing":missing, "owned":owned_count, "price":price,
		"full_price":full_price, "locked_boss":locked_boss}

func buy_equipment_set(set_id: String, transaction_id: String = "") -> bool:
	host.last_error = ""
	if host._profile_ruleset() == host.Numbers.V2:
		var request = host._default_set_request(set_id)
		var saved: Dictionary = host.profile.get("instance_transactions", {}).get("operations", {}).get(transaction_id, {})
		if not saved.is_empty():
			if saved.get("kind") != "complete_set" or saved.get("request", {}).get("set_id") != set_id: return false
			request = saved.request.duplicate(true)
		return bool(host.purchase_equipment_set_v2(request, transaction_id).get("ok", false))
	if not host._legacy_equipment_transaction(): return false
	if not host._camp_available(): return false
	if not transaction_id.is_empty() and host.profile.applied_transactions.has(transaction_id):
		return host._same_transaction(transaction_id, "purchase_set", set_id)
	var quote = host.equipment_set_quote(set_id)
	if quote.is_empty() or quote.missing.is_empty() or not str(quote.locked_boss).is_empty() \
		or int(quote.price) > int(host.profile.permanent_gold): return false
	var id = host._transaction_id(transaction_id)
	if id.is_empty(): return false
	var next_profile = host.profile.duplicate(true)
	next_profile.permanent_gold = int(next_profile.permanent_gold) - int(quote.price)
	for eq_id: String in quote.missing: next_profile.equipment[eq_id] = {"level":0}
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION,"kind":"purchase_set", "item":set_id,
		"price":int(quote.price), "items":quote.missing.duplicate()}
	return host._commit_profile(next_profile)

func equip_equipment_set(set_id: String) -> bool:
	host.last_error = ""
	if host._profile_ruleset() == host.Numbers.V2: return host._equip_instance_set(set_id)
	if not host._legacy_equipment_transaction(): return false
	if not host._camp_available(): return false
	var ids = ContentRegistry.set_item_ids(set_id)
	if ids.size() != ContentRegistry.SLOTS.size(): return false
	for eq_id: String in ids:
		if not host.profile.equipment.has(eq_id): return false
	var next_profile = host.profile.duplicate(true)
	for eq_id: String in ids:
		next_profile.loadout[ContentRegistry.equipment(eq_id).slot] = eq_id
	if next_profile.loadout == host.profile.loadout: return true
	return host._commit_profile(next_profile)

func equipment_sell_value(eq_id: String) -> int:
	if host._profile_ruleset() == host.Numbers.V2:
		var quote = host.quote_forging_v2("sell", {"instance_id":eq_id})
		return int(quote.get("gold_return", 0)) if bool(quote.get("ok", false)) else 0
	if not host.profile.equipment.has(eq_id): return 0
	return ProfileStore.equipment_sell_price(eq_id,host.equipment_level(eq_id))

func sell_equipment_items(eq_ids: Array, transaction_id: String = "") -> bool:
	host.last_error = ""
	if host._profile_ruleset() == host.Numbers.V2:
		if eq_ids.size() != 1 or not eq_ids[0] is String: return false
		return bool(host.forge_equipment_v2("sell", {"instance_id":eq_ids[0]}, transaction_id).get("ok", false))
	if not host._legacy_equipment_transaction(): return false
	if not host._camp_available() or eq_ids.is_empty() or eq_ids.size() > ContentRegistry.equipment_ids().size(): return false
	var ids: Array[String] = []
	for value: Variant in eq_ids:
		if not value is String or ids.has(value) or ContentRegistry.equipment(value).is_empty(): return false
		ids.append(value)
	ids.sort()
	var signature = ",".join(ids)
	if not transaction_id.is_empty() and host.profile.applied_transactions.has(transaction_id):
		return host._same_transaction(transaction_id,"sale",signature)
	var total = 0
	var records = {}
	for eq_id: String in ids:
		if not host.profile.equipment.has(eq_id) or eq_id in host.profile.loadout.values(): return false
		var price = host.equipment_sell_value(eq_id)
		if price <= 0: return false
		total += price
		records[eq_id] = {"level":host.equipment_level(eq_id),"price":price}
	if not ProfileStore._number(int(host.profile.permanent_gold)+total): return false
	var id = host._transaction_id(transaction_id)
	if id.is_empty(): return false
	var next_profile = host.profile.duplicate(true)
	for eq_id: String in ids:
		next_profile.equipment.erase(eq_id)
		for preset: Dictionary in next_profile.get("loadout_presets", {}).values():
			for slot: String in preset:
				if preset[slot] == eq_id: preset[slot] = ""
	next_profile.permanent_gold = int(next_profile.permanent_gold) + total
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION,"kind":"sale","item":signature,"items":records,"price":total}
	return host._commit_profile(next_profile)

func equip_item(eq_id: String) -> bool:
	host.last_error = ""
	if not host._camp_available() or not host.profile.equipment.has(eq_id):
		return false
	if host._profile_ruleset() == host.Numbers.V2 and not host._camp_instance_fits(eq_id, str(host.profile.selected_hero)):
		host.last_error = host.Instances.equip_error(host.profile.equipment[eq_id], str(host.profile.selected_hero), host.hero_level())
		return false
	var definition = host.equipment_definition(eq_id)
	if definition.is_empty():
		return false
	if host.profile.loadout[definition.slot] == eq_id:
		return true
	var next_profile = host.profile.duplicate(true)
	next_profile.loadout[definition.slot] = eq_id
	return host._commit_profile(next_profile)

func upgrade_equipment(eq_id: String, transaction_id: String = "") -> bool:
	host.last_error = ""
	if host._profile_ruleset() == host.Numbers.V2: return bool(host.forge_equipment_v2("enhance", {"instance_id":eq_id}, transaction_id).get("ok", false))
	if not host._legacy_equipment_transaction(): return false
	if not host._camp_available():
		return false
	if not transaction_id.is_empty() and host.profile.applied_transactions.has(transaction_id):
		return host._same_transaction(transaction_id, "upgrade", eq_id)
	var price = host.upgrade_cost(eq_id)
	if price <= 0 or price > int(host.profile.permanent_gold) or not host.upgrade_has_gain(eq_id):
		return false
	var id = host._transaction_id(transaction_id)
	if id.is_empty():
		return false
	var next_profile = host.profile.duplicate(true)
	next_profile.permanent_gold = int(next_profile.permanent_gold) - price
	next_profile.equipment[eq_id].level = host.equipment_level(eq_id) + 1
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION,"kind": "upgrade", "item": eq_id, "price": price,
		"level": next_profile.equipment[eq_id].level}
	return host._commit_profile(next_profile)

func preview_field_equipment(drop_id: String) -> Dictionary:
	var drop: Dictionary = host._field_equipment_drop(drop_id)
	if drop.is_empty(): return {}
	var next_loadout: Dictionary = host.run.loadout_snapshot.duplicate(true)
	var next_equipment: Dictionary = host.run.equipment_snapshot.duplicate(true)
	next_loadout[drop.slot] = drop.equipment_id
	next_equipment[drop.equipment_id] = host.run.expedition.pending_equipment[drop.equipment_id].duplicate(true) if host.run.ruleset_version() == host.Numbers.V2 else {"level":int(drop.level)}
	if host.run.ruleset_version() == host.Numbers.V2:
		if not host.Instances.can_equip(next_equipment[drop.equipment_id], host.run.hero_id, host.run.level): return {}
		next_equipment = host.Loot.carried(next_loadout, next_equipment)
	var next_stats: Dictionary = StatResolver.resolve(host.run.hero_id, host.run.level, next_loadout, next_equipment, host.run.ruleset_version(), host.hero_talents(host.run.hero_id))
	if next_stats.is_empty(): return {}
	next_stats["branches"] = host.run.branches_snapshot.duplicate(true)
	next_stats["relic_levels"] = host.run.expedition.relic_levels.duplicate(true)
	next_stats["temporary_buffs"] = host.run.expedition.temporary_buffs.duplicate(true)
	drop["current_stats"] = host.run.stats.duplicate(true)
	drop["next_stats"] = next_stats
	return drop

func _instance_request(spec: Dictionary) -> Dictionary:
	var request = spec.duplicate(true)
	if not request.has("hero_id"): request.hero_id = str(host.profile.selected_hero)
	return request

func quote_equipment_v2(spec: Dictionary) -> Dictionary:
	return host.Transactions.quote_purchase(host.profile, host._instance_request(spec)) if host._profile_ruleset() == host.Numbers.V2 else {"ok":false,"error":"ruleset"}

func quote_craft_equipment_v2(spec: Dictionary) -> Dictionary:
	return host.Transactions.quote_craft(host.profile, host._instance_request(spec)) if host._profile_ruleset() == host.Numbers.V2 else {"ok":false,"error":"ruleset"}

func quote_equipment_set_v2(spec: Dictionary) -> Dictionary:
	return host.Transactions.quote_set(host.profile, host._instance_request(spec)) if host._profile_ruleset() == host.Numbers.V2 else {"ok":false,"error":"ruleset"}

func purchase_equipment_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return host._instance_operation("purchase", spec, transaction_id)

func craft_equipment_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return host._instance_operation("craft", spec, transaction_id)

func purchase_equipment_set_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return host._instance_operation("set", spec, transaction_id)

func _instance_operation(kind: String, spec: Dictionary, transaction_id: String) -> Dictionary:
	if host._profile_ruleset() != host.Numbers.V2 or not host._camp_available(): return {"ok":false,"error":"camp_required"}
	var id = transaction_id
	if id.is_empty(): id = Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length() > 160: return {"ok":false,"error":"invalid_operation_id"}
	var request = host._instance_request(spec)
	if host._pending_instance_transactions.has(id):
		var pending: Dictionary = host._pending_instance_transactions[id]
		if pending.kind != kind or not host.Loot.same(pending.request, request): return {"ok":false,"error":"transaction_context_changed"}
	var result: Dictionary
	match kind:
		"purchase": result = host.Transactions.purchase(host.profile, id, request)
		"craft": result = host.Transactions.craft(host.profile, id, request)
		"set": result = host.Transactions.complete_set(host.profile, id, request)
		_: return {"ok":false,"error":"invalid_kind"}
	if not bool(result.get("ok", false)): return result
	host._pending_instance_transactions[id] = {"kind":kind,"request":request,"receipt":result.receipt.duplicate(true)}
	if not bool(result.get("replayed", false)) and not host._commit_profile(result.profile): return {"ok":false,"error":host.last_error,"operation_id":id}
	host._pending_instance_transactions.erase(id)
	return {"ok":true,"error":"","receipt":result.receipt.duplicate(true),"replayed":bool(result.get("replayed", false))}

func claim_pending_equipment(instance_id: String, transaction_id: String = "") -> bool:
	if host._profile_ruleset() != host.Numbers.V2 or not host._camp_available(): return false
	var id = transaction_id if not transaction_id.is_empty() else "claim:" + instance_id
	if id.length() > 160 or not host.profile.equipment.has(instance_id): return false
	var receipts: Dictionary = host.profile.get("pending_claim_receipts", {})
	if receipts.has(id): return receipts[id] == instance_id
	if host.profile.equipment[instance_id].location != "pending": return false
	var capacity = int(host.profile.get("inventory_capacity", 0))
	if capacity > 0 and host.Loot.inventory_count(host.profile) >= capacity:
		host.last_error = "INVENTORY_CAPACITY"
		return false
	var next = host.profile.duplicate(true)
	next.equipment[instance_id].location = "inventory"
	if not next.has("pending_claim_receipts"): next.pending_claim_receipts = {}
	next.pending_claim_receipts[id] = instance_id
	return host._commit_profile(next)

func _default_set_request(set_id: String) -> Dictionary:
	var power = "magic" if host.profile.selected_hero == "CH03" else "physical"
	var missing: Array = []
	for template: String in ContentRegistry.set_item_ids(set_id, 2):
		var owned = false
		for item: Dictionary in host.profile.equipment.values():
			if item.template_id == template and item.power_type == power: owned = true
		if not owned: missing.append(template)
	return {"hero_id":str(host.profile.selected_hero),"set_id":set_id,"template_ids":missing,"rarity":"white","power_type":power,"item_level":host.hero_level()}

func _equip_instance_set(set_id: String) -> bool:
	if not host._camp_available(): return false
	if str(host.profile.selected_hero) not in ContentRegistry.sets(2).get(set_id, {}).get("allowed_heroes", []):
		host.last_error = "CLASS_LOCKED"
		return false
	var templates: Array = ContentRegistry.set_item_ids(set_id, 2)
	if templates.size() != 8: return false
	var ids: Array = host.profile.equipment.keys()
	ids.sort()
	var next = host.profile.duplicate(true)
	for template: String in templates:
		var selected = ""
		for id: String in ids:
			var item: Dictionary = host.profile.equipment[id]
			if item.template_id == template and item.location != "pending" and host.Instances.can_equip(item, str(host.profile.selected_hero), host.hero_level()):
				selected = id
				break
		if selected.is_empty(): return false
		next.loadout[ContentRegistry.equipment(template, 2).slot] = selected
	return host._commit_profile(next)

## V2 camp forging is a detached service transaction. UI previews never roll;
## the receipt is returned only after the candidate profile is durably saved.
func _forging_service() -> Script:
	return load(AssetCatalog.resolve("res://scripts/domain/equipment/instance_forging.gd"))

func _forging_request(kind: String, spec: Dictionary, frozen: Dictionary = {}) -> Dictionary:
	var request = host._instance_request(spec)
	var keys: Dictionary = {"source_revision":"source_instance_id","target_revision":"target_instance_id"} if kind == "inherit" else {"expected_revision":"instance_id"}
	for key: String in keys:
		if request.has(key): continue
		if frozen.has(key): request[key] = frozen[key]
		else:
			var item: Dictionary = host.profile.get("equipment", {}).get(str(request.get(keys[key], "")), {})
			request[key] = int(item.get("forge_revision", 0))
	return request

func _forging_items(kind: String, request: Dictionary) -> Dictionary:
	var result = {}
	var keys: Array = ["source_instance_id", "target_instance_id"] if kind == "inherit" else ["instance_id"]
	for key: String in keys:
		var id = str(request.get(key, ""))
		if host.profile.equipment.has(id): result[id] = host.profile.equipment[id].duplicate(true)
	return result

func quote_forging_v2(kind: String, spec: Dictionary) -> Dictionary:
	if host._profile_ruleset() != host.Numbers.V2 or not host._camp_available(): return {"ok":false,"error":"camp_required"}
	return host._forging_service().quote(host.profile, kind, host._forging_request(kind, spec))

func forge_equipment_v2(kind: String, spec: Dictionary, transaction_id: String) -> Dictionary:
	if host._profile_ruleset() != host.Numbers.V2 or not host._camp_available(): return {"ok":false,"error":"camp_required"}
	var id = transaction_id
	if id.is_empty(): id = "forge:" + Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length() > 160: return {"ok":false,"error":"INVALID_OPERATION_ID"}
	var frozen: Dictionary = host.profile.get("forging_transactions", {}).get("operations", {}).get(id, {}).get("request", {})
	if host._pending_forging_transactions.has(id): frozen = host._pending_forging_transactions[id].request
	elif not host._pending_forging_transactions.is_empty(): return {"ok":false,"error":"PENDING_FORGE_RETRY"}
	var request = host._forging_request(kind, spec, frozen)
	if host._pending_forging_transactions.has(id):
		var previous: Dictionary = host._pending_forging_transactions[id]
		if previous.kind != kind or not host.Loot.same(previous.request, request) or not host.Loot.same(previous.expected_items, host._forging_items(kind, request)): return {"ok":false,"error":"OPERATION_CONFLICT"}
	var result: Dictionary = host._forging_service().transact(host.profile, id, kind, request)
	if not bool(result.get("ok", false)):
		host.last_error = str(result.get("error", ""))
		return result
	if bool(result.get("replayed", false)):
		host._pending_forging_transactions.erase(id)
		return {"ok":true,"error":"","receipt":result.receipt.duplicate(true),"replayed":true}
	host._pending_forging_transactions[id] = {"operation_id":id,"kind":kind,"request":request.duplicate(true),"expected_items":host._forging_items(kind, request)}
	if not host._commit_profile(result.profile): return {"ok":false,"error":host.last_error,"operation_id":id}
	host._pending_forging_transactions.erase(id)
	return {"ok":true,"error":"","receipt":result.receipt.duplicate(true),"replayed":false}

func pending_forging_v2() -> Dictionary:
	if host._pending_forging_transactions.is_empty(): return {}
	return host._pending_forging_transactions.values()[0].duplicate(true)

func cancel_pending_forging_v2(operation_id: String) -> bool:
	if not host._camp_available() or not host._pending_forging_transactions.has(operation_id): return false
	if host.profile.get("forging_transactions", {}).get("operations", {}).has(operation_id): return false
	host._pending_forging_transactions.erase(operation_id)
	return true

func resolve_reforge_v2(instance_id: String, choice: String, transaction_id: String) -> Dictionary:
	var item: Dictionary = host.profile.get("equipment", {}).get(instance_id, {})
	return host.forge_equipment_v2("resolve_reforge", {"instance_id":instance_id,"pending_operation_id":str(item.get("pending_reforge", {}).get("operation_id", "")),"choice":choice}, transaction_id)

func set_equipment_lock_v2(instance_id: String, locked: bool) -> bool:
	if host._profile_ruleset() != host.Numbers.V2 or not host._camp_available() or not host.profile.equipment.has(instance_id): return false
	var item: Dictionary = host.profile.equipment[instance_id]
	if not item.get("pending_reforge", {}).is_empty() or not host._pending_forging_transactions.is_empty():
		host.last_error = "PENDING_FORGE_RETRY"
		return false
	if bool(item.lock_state) == locked: return true
	var next = host.profile.duplicate(true)
	next.equipment[instance_id].lock_state = locked
	next.equipment[instance_id]["forge_revision"] = int(item.get("forge_revision", 0)) + 1
	return host._commit_profile(next)
