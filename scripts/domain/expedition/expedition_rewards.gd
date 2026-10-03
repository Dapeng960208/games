extends RefCounted
## Frozen V2 acquisition receipts. Permanent equipment has no count cap; only
## the carried snapshot and this single expedition's event journal are bounded.
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Rewards = preload("res://scripts/domain/world/room_rewards.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const MAX_EVENTS := 2048
const MATERIAL_KEYS := ["forge","race:B01","race:B02","race:B03","race:B04","race:B05","race:B06","core:B01","core:B02","core:B03","core:B04","core:B05","core:B06"]

static func initialize(value: Dictionary, profile: Dictionary, run_id: String, wish: String = "") -> void:
	value["loot_seed"] = (int(value.seed) ^ (run_id + ":loot:v2").hash()) & 0x7fffffff
	value["wish_slot"] = wish
	value["pity_snapshot"] = profile.get("gold_pity", {}).duplicate(true)
	value["loot_events"] = {}
	value["pending_materials"] = {}
	value["optional_claims"] = {}

static func context(value: Dictionary, run_id: String, hero_id: String, event_id: String, source: String, zone: int = 2, generator_version: int = Acquisition.GENERATOR_VERSION, actor_id: String = "") -> Dictionary:
	var room: String = str(value.route.nodes[int(value.node_index)].room_id)
	var race := Rewards.biome_for_reward(room)
	var result := {"event_id":event_id,"seed":int(value.loot_seed),"source":source,"race_id":race,"difficulty":int(value.difficulty),"challenge_level":Rewards.challenge_level(room, zone),"power_type":"magic" if hero_id == "CH03" else "physical","wish_slot":str(value.wish_slot),"force_gold":source == "boss" and int(value.difficulty) == 4 and int(value.pity_snapshot.get(race, 0)) >= 3}

	if generator_version >= 2: result["hero_id"] = hero_id
	if (generator_version >= 3 and race == "B05") or (generator_version >= 4 and race == "B06"):
		result["room_id"] = room
		if source in ["normal", "elite"] and not actor_id.is_empty(): result["monster_id"] = actor_id
	return result

static func materials(source: String, race: String, difficulty: int) -> Dictionary:
	var base: Array = {"elite":[2,1],"room":[3,1],"boss":[8,4]}.get(source, [])
	if base.is_empty(): return {}
	var factor: float = [1.0,1.25,1.6,2.0,2.5][difficulty]
	var result := {"forge":ceili(int(base[0]) * factor),"race:" + race:ceili(int(base[1]) * factor)}
	if source == "boss": result["core:" + race] = [1,1,2,2,3][difficulty]
	return result

static func add(value: Dictionary, run_id: String, hero_id: String, event_id: String, source: String, zone: int = 2, actor_id: String = "") -> bool:
	if value.loot_events.has(event_id):
		var saved: Dictionary = value.loot_events[event_id].result
		var requested := context(value, run_id, hero_id, event_id, source, zone, int(saved.generator_version), actor_id)
		# Absent optional provenance stays neutral on historical v3 retries.
		for field: String in ["room_id", "monster_id"]:
			if not saved.context.has(field): requested.erase(field)
		return same(saved.context, requested) and value.loot_events[event_id].get("actor_id", "") == actor_id
	if value.loot_events.size() >= MAX_EVENTS: return false
	var request := context(value, run_id, hero_id, event_id, source, zone, Acquisition.GENERATOR_VERSION, actor_id)
	var result := Acquisition.roll_event(request)
	if not bool(result.get("ok", false)): return false
	var count := 0
	for old: Dictionary in value.loot_events.values():
		if int(old.node_index) == int(value.node_index) and old.result.context.source == source and old.grant_items: count += old.result.items.size()
	var cap := 2 if source == "normal" else 1
	var grant := source not in ["normal", "elite"] or count < cap
	var earned := materials(source, str(request.race_id), int(value.difficulty))
	value.loot_events[event_id] = {"node_index":int(value.node_index),"zone_index":zone,"actor_id":actor_id,"ordinal":value.loot_events.size(),"result":result,"grant_items":grant,"materials":earned,"research_materials":{},"gold":0,"tutorial_xp":0}
	for key: String in earned: value.pending_materials[key] = int(value.pending_materials.get(key, 0)) + int(earned[key])
	if grant:
		for item: Dictionary in result.items:
			var id: String = str(item.instance_id)
			if value.pending_equipment.has(id): return false
			value.pending_equipment[id] = item.duplicate(true)
			value.claimed_drop_ids[id] = {"equipment_id":id,"event_id":event_id,"result":"pending","gold":0}
			if not item.template_id in value.equipment_discoveries: value.equipment_discoveries.append(item.template_id)
	return true

static func defer_research(value: Dictionary, event_id: String, earned: Dictionary) -> void:
	value.loot_events[event_id].research_materials = earned.duplicate(true)
	for key: String in earned: value.pending_materials[key] = int(value.pending_materials.get(key, 0)) + int(earned[key])

static func carried(loadout: Dictionary, records: Dictionary) -> Dictionary:
	var result := {}
	for id: String in loadout.values():
		if not id.is_empty() and records.has(id): result[id] = records[id].duplicate(true)
	return result

static func inventory_count(profile: Dictionary) -> int:
	var count := 0
	for item: Dictionary in profile.equipment.values():
		if item.location != "pending": count += 1
	return count

static func bank(profile: Dictionary, value: Dictionary, boss_defeats: Array) -> Array[String]:
	var retained: Array[String] = []
	var count := inventory_count(profile)
	var capacity := int(profile.get("inventory_capacity", 0))
	for id: String in value.pending_equipment:
		if profile.equipment.has(id): continue
		var item: Dictionary = value.pending_equipment[id].duplicate(true)
		item.location = "inventory" if capacity == 0 or count < capacity else "pending"
		if item.location == "inventory": count += 1
		profile.equipment[id] = item
		retained.append(id)
	if not profile.has("materials"): profile.materials = {}
	for key: String in value.pending_materials: profile.materials[key] = int(profile.materials.get(key, 0)) + int(value.pending_materials[key])
	if int(value.difficulty) == 4:
		for event: Dictionary in value.loot_events.values():
			if event.result.context.source != "boss": continue
			var room: String = str(value.route.nodes[int(event.node_index)].room_id)
			if room not in boss_defeats: continue
			var race: String = str(event.result.context.race_id)
			var gold := false
			for item: Dictionary in value.pending_equipment.values():
				if item.rarity == "gold" : gold = true
			if not profile.has("gold_pity"): profile.gold_pity = {"B01":0,"B02":0,"B03":0,"B04":0,"B05":0}
			profile.gold_pity[race] = 0 if gold else mini(3, int(value.pity_snapshot.get(race, 0)) + 1)
	return retained

static func valid(value: Dictionary, receipt: Dictionary, profile: Dictionary) -> bool:
	# S04 empty receipts predate the acquisition journal; they stay resumable.
	if not value.has("loot_events"):
		return value.get("pending_equipment", {}).is_empty() and value.get("claimed_drop_ids", {}).is_empty() and value.get("optional_claims", {}).is_empty()
	if not _number(value.get("loot_seed"), 2147483647) or not value.get("wish_slot") is String or (value.wish_slot != "" and value.wish_slot not in Registry.slots(2)): return false
	if not pity_valid(value.get("pity_snapshot")) or not value.get("loot_events") is Dictionary or value.loot_events.size() > MAX_EVENTS: return false
	if not value.get("pending_equipment") is Dictionary or not value.get("claimed_drop_ids") is Dictionary or not material_map_valid(value.get("pending_materials")): return false
	if not value.get("optional_claims") is Dictionary or not value.get("equipment_discoveries") is Array: return false
	var order: Array = value.loot_events.values()
	for event: Variant in order:
		if not event is Dictionary or not _number(event.get("ordinal"), MAX_EVENTS - 1): return false
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.ordinal) < int(b.ordinal))
	var expected_items := {}
	var expected_materials := {}
	var counts := {}
	var expected_optional := {}
	var earned_gold := 0
	var tutorial_events := 0
	for index in order.size():
		var event: Dictionary = order[index]
		if int(event.ordinal) != index or not _number(event.get("node_index"), int(value.node_index)) or not _number(event.get("zone_index"), 2) or not event.get("grant_items") is bool: return false
		if not event.get("result") is Dictionary or not Acquisition.event_result_valid(event.result): return false
		var result: Dictionary = event.result
		var id: String = str(result.source_event_id)
		if value.loot_events.get(id) != event: return false
		var node: Dictionary = value.route.nodes[int(event.node_index)]
		var room: String = str(node.room_id)
		var source: String = str(result.context.source)
		var prefix: String = str(receipt.id) + ":node:" + str(int(event.node_index)) + ":"
		if not id.begins_with(prefix): return false
		if source in ["normal","elite"]:
			if event.get("tutorial_xp", 0) != 0: return false
			if event.get("gold") != 0: return false
			if not event.get("actor_id") is String or Rewards.Catalog.enemy(event.actor_id).is_empty(): return false
			if not id.begins_with(prefix + "kill:") or id.length() <= (prefix + "kill:").length(): return false
		elif source in ["room","boss"]:
			if id != prefix + "complete" or not value.completion_events.has(id) or int(value.completion_events[id]) != int(event.node_index): return false
			if source != ("boss" if node.role == "boss" else "room"): return false
			var reward := Rewards.v2_completion(room, int(value.difficulty), str(event.get("quality", "")))
			if reward.is_empty() or event.get("gold") != reward.gold: return false
			earned_gold += int(reward.gold)
		elif source == "chest":
			if event.get("tutorial_xp", 0) != 0: return false
			var objective: String = {"L01":"side_crate","L11":"research_2"}.get(room, "")
			if objective.is_empty() or id != prefix + "optional:" + objective or not value.completion_events.values().any(func(n: Variant) -> bool: return int(n) == int(event.node_index)): return false
			var optional := Rewards.v2_optional(room, objective, int(value.difficulty))
			if event.get("gold") != optional.gold: return false
			earned_gold += int(optional.gold)
			expected_optional[id] = {"reward_version":2,"node_index":int(event.node_index),"room_id":room,"objective_id":objective,"gold":int(optional.gold),"event_id":id,"instance_ids":[]}
			for item: Dictionary in result.items: expected_optional[id].instance_ids.append(item.instance_id)
		else: return false
		var frozen := value.duplicate(false)
		frozen.node_index = int(event.node_index)
		var requested := context(frozen, str(receipt.id), str(receipt.hero_id), id, source, int(event.zone_index), int(result.generator_version), str(event.get("actor_id", "")))
		for field: String in ["room_id", "monster_id"]:
			if not result.context.has(field): requested.erase(field)
		if not same(result.context, requested): return false
		var key := str(int(event.node_index)) + ":" + source
		var cap := 2 if source == "normal" else 1
		var grant := source not in ["normal","elite"] or int(counts.get(key, 0)) < cap
		if event.grant_items != grant: return false
		if grant:
			counts[key] = int(counts.get(key, 0)) + result.items.size()
			for item: Dictionary in result.items:
				if expected_items.has(item.instance_id) or profile.equipment.has(item.instance_id): return false
				expected_items[item.instance_id] = item
		var earned := materials(source, str(result.context.race_id), int(value.difficulty))
		if not same(event.get("materials"), earned) or not material_map_valid(event.get("research_materials")): return false
		var research: Dictionary = event.research_materials
		if source not in ["room","boss"] and not research.is_empty(): return false
		if source in ["room","boss"]:
			var progression: Variant = profile.get("progression_receipts", {}).get(id)
			if not progression is Dictionary or progression.get("deferred_materials") != true or not same(progression.get("material_reward"), research): return false
			var tutorial: Variant = event.get("tutorial_xp", 0)
			if not _number(tutorial, 30) or int(tutorial) not in [0,30]: return false
			if int(tutorial) == 30:
				tutorial_events += 1
				if tutorial_events > 1 or receipt.hero_id not in profile.get("tutorial_completed", []): return false
			var xp: int = int(Rewards.v2_completion(room, int(value.difficulty), str(event.get("quality", "full"))).xp) + int(tutorial)
			if progression.get("hero") != receipt.hero_id or progression.get("race") != result.context.race_id or progression.get("amount") != xp: return false
		for bucket: Dictionary in [earned, research]:
			for material: String in bucket: expected_materials[material] = int(expected_materials.get(material, 0)) + int(bucket[material])
	if not same(expected_items, value.pending_equipment) or not same(expected_materials, value.pending_materials) or not same(expected_optional, value.optional_claims): return false
	if int(value.get("gold_earned", 0)) < earned_gold: return false
	if value.claimed_drop_ids.size() != expected_items.size(): return false
	var discoveries: Array = []
	for id: String in expected_items:
		var item: Dictionary = expected_items[id]
		if not item.template_id in discoveries: discoveries.append(item.template_id)
		var claim: Variant = value.claimed_drop_ids.get(id)
		if not claim is Dictionary or claim.get("equipment_id") != id or claim.get("event_id") != item.source_event_id or claim.get("result") != "pending" or claim.get("gold") != 0: return false
		if claim.has("field_decision") and claim.field_decision not in ["keep","equip"]: return false
	if value.equipment_discoveries.size() != discoveries.size(): return false
	for template: String in discoveries:
		if template not in value.equipment_discoveries: return false
	return true

static func material_map_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: Variant in value:
		if key not in MATERIAL_KEYS or not _number(value[key], 1000000000000): return false
	return true

static func pity_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: Variant in value:
		if key not in ["B01","B02","B03","B04","B05","B06"] and not (key=="B09" and preload("res://scripts/infrastructure/content/runtime_rules.gd").b09_candidate_enabled()): return false
		if not _number(value[key],3): return false
	return true

static func _number(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= 0 and value <= maximum

static func same(a: Variant, b: Variant) -> bool:
	return Acquisition._canonical(a) == Acquisition._canonical(b)
