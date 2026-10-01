class_name InstanceForging
extends RefCounted
## Detached, deterministic camp proposals. Commit the returned profile before
## revealing random results. Reforge is paid/frozen first, then explicitly chosen.
## Historical snapshots prove every refundable payment; inheritance moves, never
## copies, ownership. No RNG, clocks, disk access or combat random stream is used.
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Economy = preload("res://scripts/core/instance_economy.gd")
const Creation = preload("res://scripts/core/instance_transactions.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Rules = preload("res://config/numerical_rules.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const Stats = preload("res://scripts/combat/stat_resolver.gd")
const OldEconomy = preload("res://scripts/core/economy_history.gd")
const VERSION := 1
const VALIDATION_CACHE_LIMIT := 2048
static var _validated_receipts: Dictionary = {}
const MAX_NUMBER := 1_000_000_000_000
const MAX_BYTES := 32 * 1024 * 1024
const KINDS := ["enhance", "enhancement_reroll", "inherit", "reforge", "resolve_reforge", "refine", "sell", "dismantle"]
# Append a version when changing these economic inputs; historical receipts must
# not be repriced by future configuration changes.
const GOLD := [40, 60, 90, 130, 180, 240, 310, 390, 480, 580]
const COMMON := [2, 3, 4, 6, 8, 10, 13, 16, 20, 25]
const RACE := [0, 0, 0, 2, 2, 2, 4, 4, 6, 6]
const CORE := [0, 0, 0, 0, 0, 0, 0, 1, 0, 2]
const AFFIX_UNLOCKS := {"reforge":5, "refine":10}
const SALVAGE := {"white":[2, 0], "green":[4, 1], "purple":[7, 2], "gold":[12, 4]}

static func quote(profile: Dictionary, kind: String, request: Dictionary) -> Dictionary:
	var error := validate_profile(profile)
	if not error.is_empty(): return _reject(error)
	var canonical := _request(kind, request)
	if canonical.is_empty(): return _reject("INVALID_REQUEST")
	return _quote(profile, kind, canonical)

static func transact(profile: Dictionary, operation_id: String, kind: String, request: Dictionary) -> Dictionary:
	if not _id(operation_id): return _reject("INVALID_OPERATION_ID")
	var canonical := _request(kind, request)
	if canonical.is_empty(): return _reject("INVALID_REQUEST")
	var error := validate_profile(profile)
	if not error.is_empty(): return _reject(error)
	var ledger: Dictionary = profile.get("forging_transactions", {"version":VERSION, "operations":{}})
	var fingerprint := _hash([kind, canonical])
	if ledger.operations.has(operation_id):
		var saved: Dictionary = ledger.operations[operation_id]
		if saved.request_hash != fingerprint: return _reject("OPERATION_CONFLICT")
		return {"ok":true, "error":"", "profile":profile.duplicate(true), "receipt":saved.duplicate(true), "replayed":true}
	if profile.get("instance_transactions", {}).get("operations", {}).has(operation_id) or profile.get("applied_transactions", {}).has(operation_id) or profile.get("pending_claim_receipts", {}).has(operation_id): return _reject("OPERATION_CONFLICT")
	var preview := _quote(profile, kind, canonical)
	if not preview.ok: return preview
	if int(profile.permanent_gold) < int(preview.gold): return _reject("INSUFFICIENT_GOLD")
	for material: String in preview.materials:
		if int(profile.get("materials", {}).get(material, 0)) < int(preview.materials[material]): return _reject("INSUFFICIENT_MATERIALS")
	var before := _items(profile, canonical)
	var effect := _effect(before, kind, canonical, operation_id, preview)
	var next := profile.duplicate(true)
	for id: String in before:
		if effect.after.has(id): next.equipment[id] = effect.after[id].duplicate(true)
		else:
			next.equipment.erase(id)
			# Inactive presets are references, not ownership or a second payout.
			for preset: Dictionary in next.get("loadout_presets", {}).values():
				for slot: String in preset:
					if preset[slot] == id: preset[slot] = ""
	next.permanent_gold = int(next.permanent_gold) - int(preview.gold) + int(preview.gold_return)
	next["materials"] = next.get("materials", {}).duplicate(true)
	for material: String in preview.materials: next.materials[material] = int(next.materials.get(material, 0)) - int(preview.materials[material])
	for material: String in preview.materials_return: next.materials[material] = int(next.materials.get(material, 0)) + int(preview.materials_return[material])
	if int(next.permanent_gold) > MAX_NUMBER: return _reject("WALLET_CAPACITY")
	for amount: Variant in next.materials.values():
		if int(amount) > MAX_NUMBER: return _reject("WALLET_CAPACITY")
	var receipt := {"version":VERSION, "operation_id":operation_id, "kind":kind, "request":canonical,
		"request_hash":fingerprint, "gold":int(preview.gold), "materials":preview.materials.duplicate(true),
		"gold_return":int(preview.gold_return), "materials_return":preview.materials_return.duplicate(true),
		"before":before, "after":effect.after, "payments":effect.payments, "result":effect.result}
	receipt["result_hash"] = _receipt_hash(receipt)
	next["forging_transactions"] = ledger.duplicate(true)
	next.forging_transactions.operations[operation_id] = receipt.duplicate(true)
	if JSON.stringify(next).to_utf8_buffer().size() > MAX_BYTES: return _reject("PROFILE_CAPACITY")
	return {"ok":true, "error":"", "profile":next, "receipt":receipt.duplicate(true), "replayed":false}

static func manual_cap(level: int) -> int:
	if level >= 20: return 10
	if level >= 15: return 8
	if level >= 10: return 5
	if level >= 5: return 3
	return 0

## Public deterministic ticket mapping is useful for the probability UI/tests.
static func gain_for_ticket(ticket: int) -> int:
	if ticket < 0 or ticket > 99: return -1
	if ticket < 10: return 8
	if ticket < 30: return 9
	if ticket < 70: return 10
	if ticket < 90: return 11
	return 12

static func is_retired(profile: Dictionary, instance_id: String) -> bool:
	for receipt: Dictionary in profile.get("forging_transactions", {}).get("operations", {}).values():
		if receipt.get("kind") in ["sell", "dismantle"] and receipt.get("request", {}).get("instance_id") == instance_id: return true
	return false

static func _quote(profile: Dictionary, kind: String, request: Dictionary) -> Dictionary:
	if request.hero_id != profile.selected_hero: return _reject("HERO_CONTEXT_CHANGED")
	if not _current_version_matches(): return _reject("ECONOMY_VERSION_MISMATCH")
	var items := _items(profile, request)
	if items.size() != (2 if kind == "inherit" else 1): return _reject("INSTANCE_NOT_FOUND")
	var level := Growth.level_for_xp(int(profile.hero_xp[request.hero_id]))
	for id: String in items:
		var item: Dictionary = items[id]
		if item.location == "pending": return _reject("INSTANCE_PENDING")
		if item.lock_state and (kind in ["sell", "dismantle"] or (kind == "inherit" and id == request.source_instance_id)): return _reject("INSTANCE_LOCKED")
		if item.has("pending_reforge") and kind != "resolve_reforge": return _reject("TRANSACTION_PENDING")
		var revision_key := "source_revision" if kind == "inherit" and id == request.source_instance_id else ("target_revision" if kind == "inherit" else "expected_revision")
		if request.has(revision_key) and int(request[revision_key]) != int(item.get("forge_revision", 0)): return _reject("STALE_INSTANCE")
		if kind in ["sell", "dismantle"] and _equipped(profile, id): return _reject("INSTANCE_EQUIPPED")
	var item: Dictionary = items[request.target_instance_id] if kind == "inherit" else items[request.instance_id]
	var rank := int(item.enhancement_rank)
	match kind:
		"enhance":
			if rank >= 10: return _reject("MAX_ENHANCEMENT")
			if rank + 1 > manual_cap(level): return _reject("ENHANCEMENT_LEVEL_LOCKED")
			if not _has_flat_main(item): return _reject("NO_FLAT_MAIN")
		"enhancement_reroll":
			if level < 10: return _reject("REROLL_LEVEL_LOCKED")
			if int(request.rank) > rank: return _reject("RANK_NOT_FOUND")
			if int(request.rank) > manual_cap(level): return _reject("ENHANCEMENT_LEVEL_LOCKED")
			if int(item.enhancement_steps[int(request.rank) - 1].g) >= 12: return _reject("MAX_GAIN")
			if not _has_flat_main(item): return _reject("NO_FLAT_MAIN")
		"inherit":
			var source: Dictionary = items[request.source_instance_id]
			if Acquisition.V1_TEMPLATES[source.template_id].slot != Acquisition.V1_TEMPLATES[item.template_id].slot or source.power_type != item.power_type: return _reject("INCOMPATIBLE_SOURCE")
			if int(source.enhancement_rank) < rank: return _reject("SOURCE_RANK_TOO_LOW")
			if int(source.enhancement_rank) > manual_cap(level): return _reject("ENHANCEMENT_LEVEL_LOCKED")
			if not _has_flat_main(item): return _reject("NO_FLAT_MAIN")
			if _gain_sum(_merged_steps(source, item)) <= _gain_sum(item.enhancement_steps): return _reject("NO_IMPROVEMENT")
		"reforge", "refine":
			if level < int(AFFIX_UNLOCKS[kind]): return _reject("REFORGE_LEVEL_LOCKED" if kind == "reforge" else "REFINE_LEVEL_LOCKED")
			if int(request.affix_index) >= item.affix_type_and_quantile.size(): return _reject("AFFIX_NOT_FOUND")
			if kind == "reforge":
				if int(item.reforge_slot) != -1 and int(item.reforge_slot) != int(request.affix_index): return _reject("REFORGE_SLOT_BOUND")
				if request.affix_type not in Instances.legal_affixes(item.template_id, item.power_type): return _reject("ILLEGAL_AFFIX_TYPE")
				for index in item.affix_type_and_quantile.size():
					if index != int(request.affix_index) and item.affix_type_and_quantile[index].type == request.affix_type: return _reject("DUPLICATE_AFFIX")
			else:
				if int(item.affix_type_and_quantile[int(request.affix_index)].u) >= 100: return _reject("MAX_QUANTILE")
		"resolve_reforge":
			if not item.has("pending_reforge") or item.pending_reforge.operation_id != request.pending_operation_id: return _reject("PENDING_REFORGE_NOT_FOUND")
		"sell":
			if not item.has("purchase_baseline_gold"): return _reject("MISSING_SALE_BASELINE")
	var cost := _cost(items, kind, request)
	if cost.is_empty(): return _reject("INVALID_COST")
	var result := cost.duplicate(true)
	result.merge({"ok":true, "error":"", "request":request.duplicate(true), "before_stats":Instances.stats(item), "before_main_stats":Instances.main_stats(item), "manual_cap":manual_cap(level), "revision":int(item.get("forge_revision", 0))})
	# Quotes never draw a free candidate. Enhancement ranges are explicit bounds.
	if kind == "enhance":
		for gain in [8, 12]:
			var candidate := item.duplicate(true)
			candidate.enhancement_rank += 1
			candidate.enhancement_steps.append({"g":gain, "pity":0, "base_price_peak":_price(rank + 1, int(item.item_level))})
			result["after_stats_min" if gain == 8 else "after_stats_max"] = Instances.stats(candidate)
			result["after_main_stats_min" if gain == 8 else "after_main_stats_max"] = Instances.main_stats(candidate)
	elif kind == "enhancement_reroll":
		result["guaranteed"] = int(item.enhancement_steps[int(request.rank) - 1].pity) == 3
		result["old_gain"] = int(item.enhancement_steps[int(request.rank) - 1].g)
		result["gain_min"] = int(result.old_gain) + 1 if result.guaranteed else int(result.old_gain)
		result["gain_max"] = int(result.gain_min) if result.guaranteed else 12
		for gain in [int(result.gain_min), int(result.gain_max)]:
			var candidate := item.duplicate(true)
			candidate.enhancement_steps[int(request.rank) - 1].g = gain
			candidate.enhancement_steps[int(request.rank) - 1].pity = 0
			result["after_stats_min" if gain == int(result.gain_min) else "after_stats_max"] = Instances.stats(candidate)
		if result.guaranteed:
			result["after_stats"] = result.after_stats_min.duplicate(true)
			result["after_stats_max"] = result.after_stats_min.duplicate(true)
	elif kind in ["inherit", "refine", "resolve_reforge"]:
		var proposed := _effect(items, kind, request, "preview", cost)
		var updated: Dictionary = proposed.after[item.instance_id]
		result["after_stats"] = Instances.stats(updated)
		result["after_main_stats"] = Instances.main_stats(updated)
		if kind == "inherit": result["after_steps"] = updated.enhancement_steps.duplicate(true)
		if kind == "refine":
			var comparison := _effective_comparison(profile, item, updated)
			if comparison.is_empty(): return _reject("INVALID_LOADOUT")
			result.merge(comparison)
			if _equipped(profile, item.instance_id) and not comparison.effective_improvement:
				result.ok = false
				result.error = "NO_EFFECTIVE_IMPROVEMENT"
	return result

static func _cost(items: Dictionary, kind: String, request: Dictionary) -> Dictionary:
	var item: Dictionary = items[request.target_instance_id] if kind == "inherit" else items[request.instance_id]
	var race_id := str(Acquisition.V1_TEMPLATES[item.template_id].race_id)
	var result := {"gold":0, "materials":{}, "gold_return":0, "materials_return":{}, "base_makeup":[], "reroll_makeup":[]}
	var rank := int(item.enhancement_rank) + 1 if kind == "enhance" else int(request.get("rank", 1))
	match kind:
		"enhance", "enhancement_reroll":
			if rank < 1 or rank > 10: return {}
			result.gold = _price(rank, int(item.item_level), kind == "enhancement_reroll")
			result.materials = _rank_materials(rank, race_id, kind == "enhancement_reroll")
		"inherit":
			result.gold = 100
			result.materials = {"forge":8}
			var source: Dictionary = items[request.source_instance_id]
			for index in source.enhancement_steps.size():
				var amount := maxi(0, _price(index + 1, int(item.item_level)) - int(source.enhancement_steps[index].base_price_peak))
				result.base_makeup.append(amount)
				result.gold += amount
			for owner: Dictionary in [item, source]:
				for operation: Dictionary in owner.enhancement_reroll_history:
					var peak := _price(int(operation.rank), int(item.item_level), true)
					var amount := maxi(0, peak - int(operation.settled_price_peak))
					result.reroll_makeup.append({"operation_id":operation.operation_id, "rank":int(operation.rank), "amount":amount, "peak":maxi(peak, int(operation.settled_price_peak))})
					result.gold += amount
		"reforge", "refine":
			result.gold = _scaled(50 if kind == "reforge" else 80, int(item.item_level))
			result.materials = Economy.material_cost(4 if kind == "reforge" else 6, 2, 0, race_id)
		"sell":
			var investment := 0
			for row: Dictionary in item.enhancement_gold_ledger:
				if row.kind in ["enhancement", "enhancement_makeup"]: investment += int(row.amount)
			@warning_ignore("integer_division")
			result.gold_return = int(item.get("purchase_baseline_gold", 0)) / 4 + investment / 5
		"dismantle":
			result.materials_return = Economy.material_cost(SALVAGE[item.rarity][0], SALVAGE[item.rarity][1], 0, race_id)
			var investment := {}
			for row: Dictionary in item.material_ledger:
				if row.kind != "enhancement" or (row.material_id != "forge" and not str(row.material_id).begins_with("race:")): continue
				investment[row.material_id] = int(investment.get(row.material_id, 0)) + int(row.amount)
			for material: String in investment:
				@warning_ignore("integer_division")
				var refund: int = int(investment[material]) / 2
				if refund > 0: result.materials_return[material] = int(result.materials_return.get(material, 0)) + refund
	return result

static func _effect(before: Dictionary, kind: String, request: Dictionary, operation_id: String, cost: Dictionary) -> Dictionary:
	var after := before.duplicate(true)
	var item: Dictionary = after[request.target_instance_id] if kind == "inherit" else after[request.instance_id]
	var payments: Array = []
	var outcome := {}
	match kind:
		"enhance":
			var rank := int(item.enhancement_rank) + 1
			var ticket := _ticket(operation_id, kind, request, before, 100)
			var gain := gain_for_ticket(ticket)
			item.enhancement_rank = rank
			item.enhancement_steps.append({"g":gain, "pity":0, "base_price_peak":_price(rank, int(item.item_level)), "source_operation_id":operation_id})
			_pay(item, payments, operation_id, "enhancement", rank, int(cost.gold), cost.materials)
			outcome = {"rank":rank, "ticket":ticket, "gain":gain}
		"enhancement_reroll":
			var rank := int(request.rank)
			var step: Dictionary = item.enhancement_steps[rank - 1]
			var old_gain := int(step.g)
			var old_pity := int(step.pity)
			var guaranteed := old_pity == 3
			var ticket := -1 if guaranteed else _ticket(operation_id, kind, request, before, 100)
			var candidate := old_gain + 1 if guaranteed else gain_for_ticket(ticket)
			step.g = maxi(old_gain, candidate)
			step.pity = 0 if int(step.g) > old_gain else old_pity + 1
			_pay(item, payments, operation_id, "enhancement_reroll", rank, int(cost.gold), cost.materials)
			outcome = {"rank":rank, "ticket":ticket, "candidate":candidate, "guaranteed":guaranteed, "old_gain":old_gain, "gain":int(step.g), "old_pity":old_pity, "pity":int(step.pity)}
			var history := outcome.duplicate(true)
			history.merge({"operation_id":operation_id, "actual_gold":int(cost.gold), "actual_materials":cost.materials.duplicate(true), "settled_price_peak":_price(rank, int(item.item_level), true), "supplements":[]})
			item.enhancement_reroll_history.append(history)
		"inherit":
			var source: Dictionary = after[request.source_instance_id]
			item.enhancement_steps = _merged_steps(source, item)
			item.enhancement_rank = int(source.enhancement_rank)
			item.enhancement_gold_ledger.append_array(source.enhancement_gold_ledger.duplicate(true))
			item.material_ledger.append_array(source.material_ledger.duplicate(true))
			item.enhancement_reroll_history.append_array(source.enhancement_reroll_history.duplicate(true))
			for index in cost.base_makeup.size():
				if int(cost.base_makeup[index]) > 0: _pay(item, payments, operation_id, "enhancement_makeup", index + 1, int(cost.base_makeup[index]), {}, "base:" + str(index + 1))
			for index in cost.reroll_makeup.size():
				var supplement: Dictionary = cost.reroll_makeup[index]
				var operation: Dictionary = item.enhancement_reroll_history[index]
				operation.settled_price_peak = int(supplement.peak)
				if int(supplement.amount) > 0:
					operation.supplements.append({"operation_id":operation_id, "amount":int(supplement.amount), "settled_price_peak":int(supplement.peak)})
					_pay(item, payments, operation_id, "reroll_makeup", int(operation.rank), int(supplement.amount), {}, "reroll:" + str(index))
			_pay(item, payments, operation_id, "inherit", 0, 100, {"forge":8}, "fee")
			source.enhancement_rank = 0
			source.enhancement_steps = []
			source.enhancement_gold_ledger = []
			source.material_ledger = []
			source.enhancement_reroll_history = []
			outcome = {"base_makeup":cost.base_makeup.duplicate(true), "reroll_makeup":cost.reroll_makeup.duplicate(true)}
		"reforge":
			var index := int(request.affix_index)
			var candidate := {"type":request.affix_type, "u":_ticket(operation_id, kind, request, before, 101)}
			item.reforge_slot = index
			item["pending_reforge"] = {"operation_id":operation_id, "affix_index":index, "old_affix":item.affix_type_and_quantile[index].duplicate(true), "new_affix":candidate}
			_pay(item, payments, operation_id, "reforge", 0, int(cost.gold), cost.materials)
			outcome = item.pending_reforge.duplicate(true)
		"resolve_reforge":
			var pending: Dictionary = item.pending_reforge
			if request.choice == "replace": item.affix_type_and_quantile[int(pending.affix_index)] = pending.new_affix.duplicate(true)
			outcome = {"pending_operation_id":pending.operation_id, "choice":request.choice, "affix":item.affix_type_and_quantile[int(pending.affix_index)].duplicate(true)}
			item.erase("pending_reforge")
		"refine":
			var affix: Dictionary = item.affix_type_and_quantile[int(request.affix_index)]
			outcome = {"old_affix":affix.duplicate(true)}
			affix.u = mini(100, int(affix.u) + 10)
			outcome["new_affix"] = affix.duplicate(true)
			_pay(item, payments, operation_id, "refine", 0, int(cost.gold), cost.materials)
		"sell", "dismantle":
			after.erase(item.instance_id)
			outcome = {"retired_instance_id":item.instance_id}
	for id: String in after: after[id]["forge_revision"] = int(before[id].get("forge_revision", 0)) + 1
	return {"after":after, "payments":payments, "result":outcome}

static func _pay(item: Dictionary, payments: Array, operation_id: String, kind: String, rank: int, gold: int, materials: Dictionary, suffix: String = "payment") -> void:
	var event_id := "forge:" + operation_id.sha256_text().substr(0, 32) + ":" + suffix
	if gold > 0:
		var row := {"event_id":event_id, "operation_id":operation_id, "amount":gold, "kind":kind, "rank":rank}
		item.enhancement_gold_ledger.append(row)
		payments.append({"currency":"gold", "entry":row.duplicate(true)})
	for material: String in materials:
		var row := {"event_id":event_id, "operation_id":operation_id, "amount":int(materials[material]), "kind":kind, "rank":rank, "material_id":material}
		item.material_ledger.append(row)
		payments.append({"currency":material, "entry":row.duplicate(true)})

static func _merged_steps(source: Dictionary, target: Dictionary) -> Array:
	var steps: Array = []
	for index in source.enhancement_steps.size():
		var source_step: Dictionary = source.enhancement_steps[index]
		var target_step: Dictionary = target.enhancement_steps[index] if index < target.enhancement_steps.size() else {}
		var step := source_step.duplicate(true) if target_step.is_empty() or int(source_step.g) > int(target_step.g) else target_step.duplicate(true)
		step.base_price_peak = maxi(_price(index + 1, int(target.item_level)), maxi(int(source_step.base_price_peak), int(target_step.get("base_price_peak", 0))))
		steps.append(step)
	return steps

static func _effective_comparison(profile: Dictionary, before: Dictionary, after: Dictionary) -> Dictionary:
	var level := Growth.level_for_xp(int(profile.hero_xp[profile.selected_hero]))
	var talents: Dictionary = profile.get("talents", {}).get(profile.selected_hero, {})
	var loadout: Dictionary = profile.get("loadout", {})
	var old_stats := Stats.resolve(profile.selected_hero, level, loadout, profile.equipment, 2, talents)
	var owned: Dictionary = profile.equipment.duplicate(true)
	owned[after.instance_id] = after
	var new_stats := Stats.resolve(profile.selected_hero, level, loadout, owned, 2, talents)
	if old_stats.is_empty() or new_stats.is_empty(): return {}
	var index := -1
	for i in before.affix_type_and_quantile.size():
		if before.affix_type_and_quantile[i] != after.affix_type_and_quantile[i]: index = i
	var key: String = after.affix_type_and_quantile[index].type if index >= 0 else ""
	var actual_key: String = {"attack_speed":"attack_speed_bonus", "move_speed":"move_speed_bonus", "damage_reduction":"equipment_damage_reduction"}.get(key, key)
	var improved := float(new_stats.get(actual_key, 0)) > float(old_stats.get(actual_key, 0)) + 0.000000001
	return {"equipped":_equipped(profile, before.instance_id), "current_loadout_before":old_stats, "current_loadout_after":new_stats, "effective_improvement":improved}

static func _items(profile: Dictionary, request: Dictionary) -> Dictionary:
	var items := {}
	for id: String in ([request.source_instance_id, request.target_instance_id] if request.has("source_instance_id") else [request.instance_id]):
		if profile.equipment.has(id): items[id] = profile.equipment[id].duplicate(true)
	return items

static func _equipped(profile: Dictionary, instance_id: String) -> bool:
	return profile.equipment[instance_id].location == "equipped" or instance_id in profile.get("loadout", {}).values()

static func _has_flat_main(item: Dictionary) -> bool:
	for key: String in Instances.main_keys(item.template_id, item.power_type):
		if key not in Rules.value("percentage_main_keys"): return true
	return false

static func _gain_sum(steps: Array) -> int:
	var total := 0
	for step: Dictionary in steps: total += int(step.g)
	return total

static func _price(rank: int, level: int, reroll: bool = false) -> int:
	return Economy.ceil_ratio(int(GOLD[rank - 1]) * (100 + 3 * (level - 1)), 200 if reroll else 100)

static func _canonical_peak(rank: int, amount: int, reroll: bool = false) -> bool:
	for level in range(1, Acquisition.V1_LEVEL_CAP + 1):
		if _price(rank, level, reroll) == amount: return true
	return false

static func _scaled(gold: int, level: int) -> int:
	return Economy.ceil_ratio(gold * (100 + 3 * (level - 1)), 100)

static func _rank_materials(rank: int, race: String, reroll: bool = false) -> Dictionary:
	return Economy.material_cost(Economy.ceil_ratio(COMMON[rank - 1], 2) if reroll else COMMON[rank - 1], Economy.ceil_ratio(RACE[rank - 1], 2) if reroll else RACE[rank - 1], 0 if reroll else CORE[rank - 1], race)

static func _ticket(operation_id: String, kind: String, request: Dictionary, items: Dictionary, modulo: int) -> int:
	return _hash([VERSION, operation_id, kind, request, items]).substr(0, 13).hex_to_int() % modulo

static func _request(kind: String, request: Dictionary) -> Dictionary:
	if kind not in KINDS or not Creation._tree(request): return {}
	var keys := ["hero_id", "source_instance_id", "target_instance_id"] if kind == "inherit" else ["hero_id", "instance_id"]
	match kind:
		"enhancement_reroll": keys.append("rank")
		"reforge": keys.append_array(["affix_index", "affix_type"])
		"refine": keys.append("affix_index")
		"resolve_reforge": keys.append_array(["pending_operation_id", "choice"])
	if not request.has_all(keys): return {}
	var allowed := keys.duplicate()
	allowed.append_array(["source_revision", "target_revision"] if kind == "inherit" else ["expected_revision"])
	for key: String in request:
		if key not in allowed: return {}
	if request.hero_id not in ["CH01", "CH02", "CH03"]: return {}
	for key: String in ["instance_id", "source_instance_id", "target_instance_id", "pending_operation_id"]:
		if request.has(key) and not _id(request[key]): return {}
	if kind == "inherit" and request.source_instance_id == request.target_instance_id: return {}
	if request.has("rank") and not _integer(request.rank, 1, 10): return {}
	if request.has("affix_index") and not _integer(request.affix_index, 0, 3): return {}
	if request.has("affix_type") and not _id(request.affix_type): return {}
	if request.has("choice") and request.choice not in ["keep", "replace"]: return {}
	for key: String in ["expected_revision", "source_revision", "target_revision"]:
		if request.has(key) and not _integer(request[key], 0, MAX_NUMBER): return {}
	return Creation._canonical_values(request)

static func _current_version_matches() -> bool:
	if _hash(Rules.value("affix_operation_unlocks")) != _hash(AFFIX_UNLOCKS): return false
	if not Acquisition.current_version_error().is_empty(): return false
	if _hash(Rules.value("enhancement_unlocks")) != _hash([[1,0],[5,3],[10,5],[15,8],[20,10]]) or int(Rules.value("enhancement_max")) != 10: return false
	var salvage := {}
	for rarity: String in SALVAGE: salvage[rarity] = {"common":SALVAGE[rarity][0], "race":SALVAGE[rarity][1]}
	if _hash(Rules.value("salvage_base")) != _hash(salvage): return false
	if _hash(Rules.value("enhancement_gold")) != _hash(GOLD) or _hash(Rules.value("enhancement_common")) != _hash(COMMON) or _hash(Rules.value("enhancement_race")) != _hash(RACE) or _hash(Rules.value("enhancement_core")) != _hash(CORE): return false
	if not is_equal_approx(float(Rules.value("cost_item_level_per_level")), 0.03) or int(Rules.value("refine_quantile_increment")) != 10: return false
	return _hash(Rules.value("reroll_cost")) == _hash({"gold":50, "common":4, "race":2, "core":0}) and _hash(Rules.value("refine_cost")) == _hash({"gold":80, "common":6, "race":2, "core":0}) and _hash(Rules.value("inherit_cost")) == _hash({"gold":100, "common":8, "race":0, "core":0})

static func _receipt_hash(receipt: Dictionary) -> String:
	var unsigned := receipt.duplicate(true)
	unsigned.erase("result_hash")
	return _hash(unsigned)

static func _hash(value: Variant) -> String:
	return JSON.stringify(Creation._canonical_values(value), "", true, true).sha256_text()

static func _id(value: Variant) -> bool:
	return Creation._id(value)

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return Creation._integer(value, minimum, maximum)

static func _reject(error: String) -> Dictionary:
	return {"ok":false, "error":error, "profile":{}, "receipt":{}, "replayed":false}

## Optional absent ledger supports untouched V2/migrated saves. No operation ID
## eviction: a retired item and its investments can never become spendable again.
static func validate_ledger(value: Variant) -> bool:
	if value == null: return true
	if not value is Dictionary or value.size() != 2 or not _integer(value.get("version"), VERSION, VERSION) or not value.get("operations") is Dictionary: return false
	for operation_id: Variant in value.operations:
		if not _id(operation_id) or not _valid_receipt(operation_id, value.operations[operation_id]): return false
	return true

static func _valid_receipt(operation_id: String, receipt: Variant) -> bool:
	if not receipt is Dictionary or receipt.size() != 14 or not Creation._tree(receipt): return false
	# Content-addressed memoization only; never trust the claimed result_hash.
	# Eviction changes performance, never persisted operation/retirement history.
	var cache_key := _hash([operation_id, receipt])
	if _validated_receipts.has(cache_key): return true
	if not receipt.has_all(["version", "operation_id", "kind", "request", "request_hash", "gold", "materials", "gold_return", "materials_return", "before", "after", "payments", "result", "result_hash"]): return false
	if not _integer(receipt.version, VERSION, VERSION) or receipt.operation_id != operation_id or not receipt.request is Dictionary: return false
	var request := _request(str(receipt.kind), receipt.request)
	if request.is_empty() or receipt.request_hash != _hash([receipt.kind, request]): return false
	if not receipt.before is Dictionary or not receipt.after is Dictionary or not receipt.payments is Array or not receipt.result is Dictionary: return false
	if receipt.before.size() != (2 if receipt.kind == "inherit" else 1): return false
	var ids: Array = [request.source_instance_id, request.target_instance_id] if receipt.kind == "inherit" else [request.instance_id]
	for id: String in ids:
		if not receipt.before.has(id) or not receipt.before[id] is Dictionary or receipt.before[id].get("instance_id") != id or not _item_error(receipt.before[id]).is_empty(): return false
	var item: Dictionary = receipt.before[request.target_instance_id] if receipt.kind == "inherit" else receipt.before[request.instance_id]
	var kind: String = receipt.kind
	if item.has("pending_reforge") != (kind == "resolve_reforge"): return false
	match kind:
		"enhance":
			if int(item.enhancement_rank) >= 10: return false
		"enhancement_reroll":
			if int(request.rank) > int(item.enhancement_rank) or int(item.enhancement_steps[int(request.rank) - 1].g) >= 12: return false
		"inherit":
			var source: Dictionary = receipt.before[request.source_instance_id]
			if source.has("pending_reforge") or int(source.enhancement_rank) < int(item.enhancement_rank): return false
			if Acquisition.V1_TEMPLATES[source.template_id].slot != Acquisition.V1_TEMPLATES[item.template_id].slot or source.power_type != item.power_type: return false
			if _gain_sum(_merged_steps(source, item)) <= _gain_sum(item.enhancement_steps): return false
		"reforge", "refine":
			if int(request.affix_index) >= item.affix_type_and_quantile.size(): return false
			if kind == "refine" and int(item.affix_type_and_quantile[int(request.affix_index)].u) >= 100: return false
			if kind == "reforge":
				if int(item.reforge_slot) not in [-1, int(request.affix_index)] or request.affix_type not in Instances.legal_affixes(item.template_id, item.power_type): return false
				for index in item.affix_type_and_quantile.size():
					if index != int(request.affix_index) and item.affix_type_and_quantile[index].type == request.affix_type: return false
		"resolve_reforge":
			if item.pending_reforge.operation_id != request.pending_operation_id: return false
		"sell":
			if not item.has("purchase_baseline_gold"): return false
	var cost := _cost(receipt.before, kind, request)
	if cost.is_empty(): return false
	for key: String in ["gold", "gold_return"]:
		if not _integer(receipt[key], int(cost[key]), int(cost[key])): return false
	for key: String in ["materials", "materials_return"]:
		if not receipt[key] is Dictionary or not Creation._same_materials(receipt[key], cost[key]): return false
	var effect := _effect(receipt.before, kind, request, operation_id, cost)
	if _hash(receipt.after) != _hash(effect.after) or _hash(receipt.payments) != _hash(effect.payments) or _hash(receipt.result) != _hash(effect.result): return false
	for record: Variant in receipt.after.values():
		if not record is Dictionary or not _item_error(record).is_empty(): return false
	if receipt.result_hash != _receipt_hash(receipt): return false
	if _validated_receipts.size() >= VALIDATION_CACHE_LIMIT: _validated_receipts.clear()
	_validated_receipts[cache_key] = true
	return true

static func _item_error(item: Dictionary) -> String:
	if not Instances.validate(item).is_empty(): return "INVALID_INSTANCE"
	if not _integer(item.get("forge_revision", 0), 0, MAX_NUMBER): return "INVALID_INSTANCE_REVISION"
	for index in item.enhancement_steps.size():
		if int(item.enhancement_steps[index].base_price_peak) < _price(index + 1, int(item.item_level)) or not _canonical_peak(index + 1, int(item.enhancement_steps[index].base_price_peak)): return "INVALID_PRICE_PEAK"
	var seen := {}
	for row: Dictionary in item.enhancement_gold_ledger:
		if not _payment_row_valid(row, false): return "INVALID_PAYMENT_LEDGER"
	for row: Dictionary in item.material_ledger:
		if not _payment_row_valid(row, true): return "INVALID_PAYMENT_LEDGER"
	for history: Dictionary in item.enhancement_reroll_history:
		if not history.has_all(["operation_id", "rank", "ticket", "candidate", "guaranteed", "old_gain", "gain", "old_pity", "pity", "actual_gold", "actual_materials", "settled_price_peak", "supplements"]): return "INVALID_REROLL_HISTORY"
		if not _id(history.operation_id) or seen.has(history.operation_id) or not _integer(history.rank, 1, int(item.enhancement_rank)): return "INVALID_REROLL_HISTORY"
		seen[history.operation_id] = true
		if not _integer(history.settled_price_peak, _price(int(history.rank), int(item.item_level), true), MAX_NUMBER) or not _canonical_peak(int(history.rank), int(history.settled_price_peak), true) or not history.supplements is Array: return "INVALID_REROLL_PEAK"
		if not _integer(history.candidate, 8, 12) or not _integer(history.actual_gold, 1, MAX_NUMBER) or not history.actual_materials is Dictionary: return "INVALID_REROLL_HISTORY"
		if not _integer(history.old_gain, 8, 11) or not _integer(history.gain, int(history.old_gain), 12) or not _integer(history.old_pity, 0, 3) or not _integer(history.pity, 0, 3) or not history.guaranteed is bool: return "INVALID_REROLL_HISTORY"
		if history.guaranteed != (int(history.old_pity) == 3): return "INVALID_REROLL_HISTORY"
		if history.guaranteed:
			if history.ticket != -1 or int(history.candidate) != int(history.old_gain) + 1: return "INVALID_REROLL_HISTORY"
		elif not _integer(history.ticket, 0, 99) or int(history.candidate) != gain_for_ticket(int(history.ticket)): return "INVALID_REROLL_HISTORY"
		if int(history.gain) != maxi(int(history.old_gain), int(history.candidate)) or int(history.pity) != (0 if int(history.gain) > int(history.old_gain) else int(history.old_pity) + 1): return "INVALID_REROLL_HISTORY"
		for supplement: Variant in history.supplements:
			if not supplement is Dictionary or supplement.size() != 3 or not _id(supplement.get("operation_id")) or not _integer(supplement.get("amount"), 1, MAX_NUMBER) or not _integer(supplement.get("settled_price_peak"), 1, MAX_NUMBER): return "INVALID_REROLL_HISTORY"
	if item.has("pending_reforge"):
		var pending: Variant = item.pending_reforge
		if not pending is Dictionary or pending.size() != 4 or not pending.has_all(["operation_id", "affix_index", "old_affix", "new_affix"]): return "INVALID_PENDING_REFORGE"
		if not _id(pending.operation_id) or not _integer(pending.affix_index, 0, item.affix_type_and_quantile.size() - 1) or int(item.reforge_slot) != int(pending.affix_index): return "INVALID_PENDING_REFORGE"
		if pending.old_affix != item.affix_type_and_quantile[int(pending.affix_index)] or not pending.new_affix is Dictionary or pending.new_affix.size() != 2 or not _integer(pending.new_affix.get("u"), 0, 100): return "INVALID_PENDING_REFORGE"
		if pending.new_affix.get("type") not in Instances.legal_affixes(item.template_id, item.power_type): return "INVALID_PENDING_REFORGE"
		for index in item.affix_type_and_quantile.size():
			if index != int(pending.affix_index) and item.affix_type_and_quantile[index].type == pending.new_affix.type: return "INVALID_PENDING_REFORGE"
	return ""

static func _payment_row_valid(row: Dictionary, materials: bool) -> bool:
	if not _id(row.get("event_id")) or not _integer(row.get("amount"), 1, MAX_NUMBER): return false
	if row.get("kind") not in ["enhancement", "enhancement_makeup", "enhancement_reroll", "reroll_makeup", "inherit", "reforge", "refine"]: return false
	if not _integer(row.get("rank"), 0 if row.kind in ["inherit", "reforge", "refine"] else 1, 10): return false
	if row.has("operation_id") and not _id(row.operation_id): return false
	if not row.has("operation_id") and (materials or row.kind != "enhancement" or not _integer(row.get("legacy_economy_version"), 1, OldEconomy.CURRENT_VERSION)): return false
	return not materials or Creation._material_id(row.get("material_id"))

## Returns an error code instead of silently repairing provenance. ProfileStore
## calls this after its own envelope/loadout validation, before accepting a save.
static func validate_profile(profile: Dictionary) -> String:
	for key: String in ["loadout", "loadout_presets", "talents", "applied_transactions", "pending_claim_receipts", "numerical_migration"]:
		if profile.has(key) and not profile[key] is Dictionary: return "INVALID_PROFILE"
	for preset: Variant in profile.get("loadout_presets", {}).values():
		if not preset is Dictionary: return "INVALID_PROFILE"
	if not profile.get("talents", {}).get(profile.get("selected_hero", ""), {}) is Dictionary: return "INVALID_PROFILE"
	var creation_error := Creation._profile_error(profile)
	if not creation_error.is_empty(): return creation_error
	if not validate_ledger(profile.get("forging_transactions")): return "INVALID_FORGING_LEDGER"
	var operations: Dictionary = profile.get("forging_transactions", {}).get("operations", {})
	var proofs := {}
	var retired := {}
	var consumed := {}
	var snapshots := {}
	for operation_id: String in operations:
		var receipt: Dictionary = operations[operation_id]
		if profile.get("instance_transactions", {}).get("operations", {}).has(operation_id) or profile.get("applied_transactions", {}).has(operation_id) or profile.get("pending_claim_receipts", {}).has(operation_id): return "OPERATION_CONFLICT"
		for payment: Dictionary in receipt.payments:
			var key := _payment_key(payment.entry, payment.currency)
			if proofs.has(key): return "DUPLICATE_PAYMENT"
			proofs[key] = payment.entry
		for id: String in receipt.after:
			if not snapshots.has(id): snapshots[id] = []
			snapshots[id].append({"before":receipt.before[id], "after":receipt.after[id]})
		if receipt.kind in ["sell", "dismantle"]:
			var id: String = receipt.request.instance_id
			if retired.has(id): return "DOUBLE_RECYCLING"
			retired[id] = receipt.before[id]
			for row: Dictionary in receipt.before[id].enhancement_gold_ledger: consumed[_payment_key(row, "gold")] = true
			for row: Dictionary in receipt.before[id].material_ledger: consumed[_payment_key(row, row.material_id)] = true
	# Validate both current ownership and archived payments used by past refunds.
	var owners := {}
	var operation_owners := {}
	for id: String in profile.equipment:
		var item: Dictionary = profile.equipment[id]
		var error := _item_error(item)
		if not error.is_empty(): return error
		if retired.has(id): return "RETIRED_INSTANCE_PRESENT"
		for row: Dictionary in item.enhancement_gold_ledger:
			var key := _payment_key(row, "gold")
			if owners.has(key) or consumed.has(key): return "DUPLICATE_PAYMENT_OWNERSHIP"
			owners[key] = id
			var payment_id: String = row.get("operation_id", row.event_id)
			if operation_owners.has(payment_id) and operation_owners[payment_id] != id: return "DUPLICATE_PAYMENT_OWNERSHIP"
			operation_owners[payment_id] = id
		for row: Dictionary in item.material_ledger:
			var key := _payment_key(row, row.material_id)
			if owners.has(key) or consumed.has(key): return "DUPLICATE_PAYMENT_OWNERSHIP"
			owners[key] = id
			var payment_id: String = row.get("operation_id", row.event_id)
			if operation_owners.has(payment_id) and operation_owners[payment_id] != id: return "DUPLICATE_PAYMENT_OWNERSHIP"
			operation_owners[payment_id] = id
		if not _proven_item_payments(profile, item, proofs, operations): return "UNPROVEN_PAYMENT"
	for receipt: Dictionary in operations.values():
		for item: Dictionary in receipt.before.values():
			if not _proven_item_payments(profile, item, proofs, operations): return "UNPROVEN_PAYMENT"
	# Enforce each item's chronological forge state while permitting independent
	# equip/lock changes and their revision increments between forge operations.
	for id: String in snapshots:
		var chain: Array = snapshots[id]
		chain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.after.forge_revision) < int(b.after.forge_revision))
		for index in range(1, chain.size()):
			if int(chain[index].before.get("forge_revision", 0)) < int(chain[index - 1].after.forge_revision) or _forge_state(chain[index].before) != _forge_state(chain[index - 1].after): return "FORGING_HISTORY_CONFLICT"
		var last: Dictionary = chain.back().after
		var current: Dictionary = profile.equipment.get(id, retired.get(id, {}))
		if current.is_empty() or int(current.get("forge_revision", 0)) < int(last.forge_revision) or _forge_state(current) != _forge_state(last): return "FORGING_STATE_CONFLICT"
	return ""

static func _proven_item_payments(profile: Dictionary, item: Dictionary, proofs: Dictionary, operations: Dictionary) -> bool:
	for row: Dictionary in item.enhancement_gold_ledger:
		if row.has("operation_id"):
			if not proofs.has(_payment_key(row, "gold")) or proofs[_payment_key(row, "gold")] != row: return false
		elif not _legacy_payment_proven(profile, row): return false
	for row: Dictionary in item.material_ledger:
		if not proofs.has(_payment_key(row, row.material_id)) or proofs[_payment_key(row, row.material_id)] != row: return false
	for history: Dictionary in item.enhancement_reroll_history:
		if not operations.has(history.operation_id): return false
		var original: Dictionary = operations[history.operation_id]
		if original.kind != "enhancement_reroll": return false
		var base: Dictionary = original.after[original.request.instance_id].enhancement_reroll_history.back()
		var comparison := history.duplicate(true)
		comparison.settled_price_peak = base.settled_price_peak
		comparison.supplements = []
		if comparison != base: return false
		for supplement: Dictionary in history.supplements:
			if not operations.has(supplement.operation_id) or operations[supplement.operation_id].kind != "inherit": return false
			var found := false
			for candidate: Dictionary in operations[supplement.operation_id].result.reroll_makeup:
				if candidate.operation_id == history.operation_id and int(candidate.amount) == int(supplement.amount) and int(candidate.peak) == int(supplement.settled_price_peak): found = true
			if not found: return false
	if item.has("pending_reforge"):
		var operation_id: String = item.pending_reforge.operation_id
		if not operations.has(operation_id) or operations[operation_id].kind != "reforge" or operations[operation_id].result != item.pending_reforge: return false
	return true

static func _legacy_payment_proven(profile: Dictionary, row: Dictionary) -> bool:
	var old: Variant = profile.get("applied_transactions", {}).get(row.event_id)
	var migration: Dictionary = profile.get("numerical_migration", {})
	if not migration.get("original", {}) is Dictionary or not migration.get("original", {}).get("equipment", {}) is Dictionary: return false
	var original: Dictionary = migration.get("original", {}).get("equipment", {})
	if not old is Dictionary or old.get("kind") != "upgrade" or not original.has(old.get("item")) or not original[old.item] is Dictionary: return false
	if not _integer(old.get("economy_version", 1), 1, OldEconomy.CURRENT_VERSION) or not _integer(old.get("level"), 1, 5) or not _integer(old.get("price"), 0, MAX_NUMBER) or not _integer(original[old.item].get("level"), 0, 5): return false
	var version := int(old.get("economy_version", 1))
	if not OldEconomy.supported(version) or int(row.legacy_economy_version) != version or int(row.rank) != int(old.get("level", -1)): return false
	if int(row.rank) > int(original[old.item].get("level", 0)) or int(row.amount) != int(old.get("price", -1)) or int(row.amount) != OldEconomy.upgrade_price(int(row.rank), version): return false
	for receipt: Variant in profile.get("applied_transactions", {}).values():
		if not receipt is Dictionary: return false
		if receipt.get("kind") == "sale":
			if not receipt.get("items", {}) is Dictionary or receipt.get("items", {}).has(old.item): return false
	return true

static func _payment_key(row: Dictionary, currency: String) -> String:
	return _hash([row.event_id, currency])

static func _forge_state(item: Dictionary) -> Dictionary:
	var result := {}
	for key: String in ["instance_id", "template_id", "item_level", "rarity", "power_type", "main_rolls", "purchase_baseline_gold", "source_event_id", "source_kind", "source_metadata", "enhancement_rank", "enhancement_steps", "enhancement_reroll_history", "enhancement_gold_ledger", "material_ledger", "affix_type_and_quantile", "reforge_slot", "pending_reforge"]:
		if item.has(key): result[key] = item[key]
	return result
