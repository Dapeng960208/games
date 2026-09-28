class_name ExpeditionState
extends RefCounted
## Bounded JSON-only checkpoint format. Runtime snapshots are exported by actors;
## this layer never invents an in-progress actor state from a settlement receipt.
const Registry = preload("res://scripts/data/content_registry.gd")
const Routes = preload("res://scripts/world/route_generator.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const FORMAT := 1
const MAX_IDS := 512
const RELICS: Array[String] = ["RL01","RL02","RL03","RL04","RL05","RL06","RL07","RL08","RL09","RL10","RL11","RL12"]
const ACTIVE_RELICS: Array[String] = ["RL01","RL02","RL03"]
const LEGACY_RELICS := {"RL01":"split","RL02":"ember","RL03":"arc"}
const MASTERY_THRESHOLDS := [0,100,240,420,640,900]
const SUPPLIES := {
	"heal_small":{"label":"快速止血","price":20},"shield":{"label":"应急护盾","price":40},
	"heal_large":{"label":"修整服务","price":60},"amplify":{"label":"便携增幅","price":60},
	"scan":{"label":"勘探扫描","price":20},"mana":{"label":"法力补剂","price":40},"energy":{"label":"能量补剂","price":20}}

static func number(value: Variant, maximum: float = 1000000000000.0, integral: bool = true) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= maximum and (not integral or float(value) == floorf(float(value)))

static func ids(value: Variant, maximum: int = MAX_IDS) -> bool:
	if not value is Array or value.size() > maximum: return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not id is String or id.is_empty() or id.length() > 160 or seen.has(id): return false
		seen[id] = true
	return true

static func json_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value == null or value is bool: return true
	if value is int or value is float: return is_finite(float(value)) and absf(float(value)) <= 1000000000000.0
	if value is String: return value.length() <= 256
	if value is Array:
		if value.size() > MAX_IDS: return false
		for entry: Variant in value:
			if not json_tree(entry, depth + 1): return false
		return true
	if value is Dictionary:
		if value.size() > MAX_IDS: return false
		for key: Variant in value:
			if not key is String or key.length() > 160 or not json_tree(value[key], depth + 1): return false
		return true
	return false

static func fresh(run_id: String, options: Dictionary, profile: Dictionary, stats: Dictionary) -> Dictionary:
	var biome: String = str(options.get("biome_id", "B01"))
	if not number(options.get("difficulty", 0), 4): return {}
	var difficulty: int = int(options.get("difficulty", 0))
	if not Catalog.biomes().has(biome) or difficulty < 0 or difficulty > 4: return {}
	var required: String = {"B01":"","B02":"BO01","B03":"BO02","B04":"BO03"}.get(biome, "invalid")
	if not required.is_empty() and not required in profile.bosses: return {}
	var seed_value: int = 960208 if int(profile.total_runs) == 0 else randi_range(1, 2147483647)
	if options.has("seed"):
		if not number(options.seed, 2147483647): return {}
		seed_value = int(options.seed)
	var route: Dictionary = Routes.generate(biome, seed_value)
	if not bool(route.get("valid", false)): return {}
	route.erase("candidate_paths")
	var initial: Dictionary = {"snapshot_version":1,"mode":"fresh_entry","hero_id":str(stats.hero_id),"hp":float(stats.max_hp),"resource":float(stats.starting_resource)}
	var value: Dictionary = {"format_version":FORMAT,"recovery_mode":"checkpoint","content_version":Catalog.content_version(),"seed":seed_value,"difficulty":difficulty,
		"route":route,"node_index":0,"phase":"safe","completed_nodes":[],"locked_nodes":{},"completion_events":{},
		"runtime":initial,"checkpoint_id":run_id + ":entry:0","pending_equipment":{},"claimed_drop_ids":{},"equipment_discoveries":[],
		"gold_earned":0,"gold_spent":0,"offers":{},"relic_levels":{},"mastery":0,"mastery_rank":1,"purchased_offer_ids":[],
		"temporary_buffs":{},"scan_nodes":[],"room_entry_gold":0,"room_entry_kills":0,"room_entry_shots":0}
	add_relic_offer(value, run_id, 1)
	return value

static func add_relic_offer(value: Dictionary, run_id: String, rank: int) -> void:
	var id: String = "relic:" + run_id + ":" + str(rank)
	if value.offers.has(id): return
	var candidates: Array[String] = []
	var random := RandomNumberGenerator.new()
	random.seed = int(value.seed) + rank * 7919
	var pool: Array[String] = []
	for relic: String in ACTIVE_RELICS:
		if int(value.relic_levels.get(relic, 0)) < 2: pool.append(relic)
	while not pool.is_empty() and candidates.size() < 3:
		var pick: int = random.randi_range(0, pool.size() - 1)
		candidates.append(pool[pick])
		pool.remove_at(pick)
	value.offers[id] = {"offer_id":id,"kind":"relic","label":"历练遗物 · " + str(rank),"candidates":candidates,"decision":"","required":true,"rank":rank}

static func add_supply_offers(value: Dictionary, run_id: String) -> void:
	for product: String in SUPPLIES:
		var id: String = "supply:" + run_id + ":4:" + product
		if value.offers.has(id): continue
		value.offers[id] = {"offer_id":id,"kind":"supply","product_id":product,"label":SUPPLIES[product].label,"price":SUPPLIES[product].price,"decision":"","required":false,"node_index":4}

static func runtime_valid(value: Variant, hero_id: String, stats: Dictionary, fresh_allowed: bool = false) -> bool:
	if not value is Dictionary or not json_tree(value) or JSON.stringify(value).length() > 180000: return false
	if value.get("snapshot_version") != 1 or value.get("hero_id") != hero_id: return false
	if not number(value.get("hp"), float(stats.max_hp), false) or float(value.hp) <= 0.0 or not number(value.get("resource"), float(stats.resource_max), false): return false
	if value.get("mode") == "fresh_entry": return Snapshot.validate(value, hero_id, stats, fresh_allowed)
	if value.get("mode") != "safe_boundary": return false
	for key in ["player", "status", "equipment"]:
		if not value.get(key) is Dictionary: return false
	var player: Dictionary = value.player
	if not player.get("cooldowns") is Dictionary: return false
	for key in ["q", "secondary", "f", "ultimate"]:
		if not number(player.cooldowns.get(key), 300.0, false): return false
	for key in ["dash_cooldown", "shot_cooldown"]:
		if not number(player.get(key), 300.0, false): return false
	if not value.status.get("guards") is Dictionary or not value.status.get("states") is Dictionary: return false
	return Snapshot.validate(value, hero_id, stats, fresh_allowed)

static func valid(receipt: Dictionary, profile: Dictionary) -> bool:
	var value: Variant = receipt.get("expedition")
	if not value is Dictionary or not json_tree(value): return false
	if value.get("format_version") != FORMAT or value.get("recovery_mode") != "checkpoint" or value.get("content_version") != Catalog.content_version(): return false
	if not number(value.get("seed"), 2147483647) or not number(value.get("difficulty"), 4) or not number(value.get("node_index"), 7): return false
	if not value.get("phase") in ["safe", "combat", "cleared"]: return false
	var route: Variant = value.get("route")
	if not route is Dictionary or not route.get("nodes") is Array or route.nodes.size() != 8 or not Catalog.biomes().has(route.get("biome_id")): return false
	if int(route.get("seed", -1)) != int(value.seed) or route.get("content_version") != value.content_version: return false
	var seen_templates: Dictionary = {}
	for index in range(8):
		var node: Variant = route.nodes[index]
		if not node is Dictionary or int(node.get("node_index", -1)) != index or node.get("role") != Routes.NODE_ROLES[index]: return false
		if not node.get("room_id") is String or not node.get("options") is Array: return false
		if index in Routes.COMBAT_NODES:
			if not node.room_id in Catalog.biomes()[route.biome_id].room_ids or seen_templates.has(node.room_id): return false
			seen_templates[node.room_id] = true
			if not ids(node.options, 6) or not node.room_id in node.options: return false
			for option in node.options:
				if not option in Catalog.biomes()[route.biome_id].room_ids: return false
		elif index == 7 and node.room_id != Catalog.biomes()[route.biome_id].boss_id: return false
		elif index in [0, 4] and node.room_id != "service_" + Routes.NODE_ROLES[index]: return false
	if not value.get("completed_nodes") is Array or value.completed_nodes.size() > 8: return false
	var completed: Dictionary = {}
	for index: Variant in value.completed_nodes:
		if not number(index, 7) or completed.has(int(index)) or int(index) > int(value.node_index): return false
		completed[int(index)] = true
	for index in range(int(value.node_index)):
		if not completed.has(index): return false
	if value.phase == "cleared" and not completed.has(int(value.node_index)): return false
	if value.phase == "safe" and int(value.node_index) not in [0, 4]: return false
	if value.phase == "combat" and (int(value.node_index) not in [1,2,3,5,6,7] or completed.has(int(value.node_index))): return false
	var expected_checkpoint: String = str(receipt.id) + (":cleared:" if value.phase == "cleared" else ":entry:") + str(int(value.node_index))
	if value.get("checkpoint_id") != expected_checkpoint: return false
	if not value.get("locked_nodes") is Dictionary or value.locked_nodes.size() > 7 or not value.get("completion_events") is Dictionary or value.completion_events.size() > 8: return false
	for key: Variant in value.locked_nodes:
		if not str(key).is_valid_int() or int(key) < 1 or int(key) > mini(7, int(value.node_index) + 1) or value.locked_nodes[key] != route.nodes[int(key)].room_id: return false
	var completed_combat: Dictionary = {}
	for key: Variant in value.completion_events:
		if not key is String or key.is_empty() or key.length() > 160 or not number(value.completion_events[key], 7) or not completed.has(int(value.completion_events[key])): return false
		if not key in receipt.completed_reward_ids: return false
		var index: int = int(value.completion_events[key])
		if index not in [1,2,3,5,6,7] or completed_combat.has(index): return false
		completed_combat[index] = true
	for index: int in completed:
		if index in [1,2,3,5,6,7] and not completed_combat.has(index): return false
	if not value.get("pending_equipment") is Dictionary or value.pending_equipment.size() > 60 or not value.get("claimed_drop_ids") is Dictionary or value.claimed_drop_ids.size() > MAX_IDS: return false
	if not ids(value.get("equipment_discoveries"), 60): return false
	for eq: String in value.equipment_discoveries:
		if Registry.equipment(eq).is_empty(): return false
	for eq: Variant in value.pending_equipment:
		if not eq is String or Registry.equipment(eq).is_empty() or profile.equipment.has(eq) or not value.pending_equipment[eq] is Dictionary: return false
		var drop: Variant = value.pending_equipment[eq].get("drop_id")
		if not drop is String or not value.claimed_drop_ids.has(drop) or value.claimed_drop_ids[drop].get("equipment_id") != eq: return false
	for drop: Variant in value.claimed_drop_ids:
		if not drop is String or drop.is_empty() or drop.length() > 160 or not value.claimed_drop_ids[drop] is Dictionary: return false
		var record: Dictionary = value.claimed_drop_ids[drop]
		if Registry.equipment(str(record.get("equipment_id", ""))).is_empty() or not record.get("result") in ["pending", "gold"] or not number(record.get("gold"), 1000): return false
		var eq: String = str(record.equipment_id)
		if not eq in value.equipment_discoveries: return false
		if record.result == "pending":
			if int(record.gold) != 0 or not value.pending_equipment.has(eq) or value.pending_equipment[eq].drop_id != drop: return false
		elif int(record.gold) != int(int(Registry.equipment(eq).price) / 10) or (not profile.equipment.has(eq) and not value.pending_equipment.has(eq)): return false
	if not value.get("offers") is Dictionary or value.offers.size() > 32 or not ids(value.get("purchased_offer_ids"), 16): return false
	for offer_id: Variant in value.offers:
		var offer: Variant = value.offers[offer_id]
		if not offer_id is String or offer_id.is_empty() or offer_id.length() > 160 or not offer is Dictionary or offer.get("offer_id") != offer_id or not offer.get("decision") is String: return false
		if offer.get("kind") == "relic":
			if not ids(offer.get("candidates"), 3) or not number(offer.get("rank"), 6) or int(offer.rank) < 1: return false
			if offer_id != "relic:" + str(receipt.id) + ":" + str(int(offer.rank)) or offer.get("required") != true: return false
			for id in offer.candidates:
				if not id in RELICS: return false
			if not offer.decision in ["", "skip"] and not offer.decision in offer.candidates: return false
		elif offer.get("kind") == "supply":
			if not SUPPLIES.has(offer.get("product_id")) or offer.get("price") != SUPPLIES[offer.product_id].price or not offer.decision in ["", "purchased"]: return false
			if offer_id != "supply:" + str(receipt.id) + ":4:" + str(offer.product_id) or int(value.node_index) < 4 or offer.get("node_index") != 4 or offer.get("required") != false: return false
			if (offer.decision == "purchased") != (offer_id in value.purchased_offer_ids): return false
		else: return false
	for id: String in value.purchased_offer_ids:
		if not value.offers.has(id) or value.offers[id].get("decision") != "purchased": return false
	if not value.get("relic_levels") is Dictionary or value.relic_levels.size() > 4: return false
	for id: Variant in value.relic_levels:
		if not id in RELICS or not number(value.relic_levels[id], 2) or int(value.relic_levels[id]) < 1: return false
	if not number(value.get("mastery"), 900) or not number(value.get("mastery_rank"), 6) or int(value.mastery_rank) < 1: return false
	var expected_rank: int = 0
	for threshold: int in MASTERY_THRESHOLDS:
		if int(value.mastery) >= threshold: expected_rank += 1
	if int(value.mastery_rank) != expected_rank: return false
	var expected_relics: Dictionary = {}
	for rank in range(1, expected_rank + 1):
		var id: String = "relic:" + str(receipt.id) + ":" + str(rank)
		if not value.offers.has(id): return false
		var offer: Dictionary = value.offers[id]
		var choice: String = str(offer.decision)
		if choice in ["", "skip"]: continue
		var replace: String = str(offer.get("replacement_id", ""))
		if not replace.is_empty():
			if not expected_relics.has(replace) or expected_relics.has(choice) or expected_relics.size() < 4: return false
			expected_relics.erase(replace)
		expected_relics[choice] = int(expected_relics.get(choice, 0)) + 1
		if expected_relics.size() > 4 or int(expected_relics[choice]) > 2: return false
	if value.relic_levels.size() != expected_relics.size(): return false
	for id: String in expected_relics:
		if int(value.relic_levels.get(id, 0)) != int(expected_relics[id]): return false
	var expected_offers: int = expected_rank + (SUPPLIES.size() if int(value.node_index) >= 4 else 0)
	if value.offers.size() != expected_offers: return false
	for key in ["gold_earned","gold_spent","room_entry_gold","room_entry_kills","room_entry_shots"]:
		if not number(value.get(key)): return false
	if int(value.gold_spent) > int(value.gold_earned) or int(receipt.gold) != int(value.gold_earned) - int(value.gold_spent): return false
	var spent: int = 0
	for id: String in value.purchased_offer_ids: spent += int(value.offers[id].price)
	if spent != int(value.gold_spent): return false
	if not value.get("temporary_buffs") is Dictionary or value.temporary_buffs.size() > 8 or not value.get("scan_nodes") is Array or value.scan_nodes.size() > 8: return false
	for key: Variant in value.temporary_buffs:
		var buff: Variant = value.temporary_buffs[key]
		if not buff is Dictionary: return false
		if key == "amplify":
			if buff.size() != 2 or buff.get("damage_bonus") != 0.08 or not number(buff.get("remaining_rooms"), 2): return false
			if not ("supply:" + str(receipt.id) + ":4:amplify") in value.purchased_offer_ids: return false
		elif key == "pending_supply_shield":
			if int(value.node_index) != 4 or buff.size() != 2 or buff.get("hp_ratio") != 0.15 or buff.get("duration") != 4.0: return false
			if not ("supply:" + str(receipt.id) + ":4:shield") in value.purchased_offer_ids: return false
		else: return false
	var scanned: Dictionary = {}
	for index: Variant in value.scan_nodes:
		if not number(index, 6) or int(index) not in [5,6] or scanned.has(int(index)) or int(value.node_index) < 4: return false
		scanned[int(index)] = true
	if not scanned.is_empty() and (scanned.size() != 2 or not ("supply:" + str(receipt.id) + ":4:scan") in value.purchased_offer_ids): return false
	if not receipt.get("loadout_snapshot") is Dictionary or not receipt.get("equipment_snapshot") is Dictionary or receipt.equipment_snapshot.size() > 60 or receipt.loadout_snapshot.size() != 6: return false
	for eq: Variant in receipt.equipment_snapshot:
		if Registry.equipment(str(eq)).is_empty() or not receipt.equipment_snapshot[eq] is Dictionary or not number(receipt.equipment_snapshot[eq].get("level"), 5): return false
	for slot in Registry.SLOTS:
		var eq: String = str(receipt.loadout_snapshot.get(slot, ""))
		if not receipt.equipment_snapshot.has(eq) or Registry.equipment(eq).get("slot") != slot: return false
	if not receipt.get("branches_snapshot") is Dictionary or receipt.branches_snapshot.size() != 2: return false
	for key in ["q","ultimate"]:
		if not receipt.branches_snapshot.get(key) in ["","A","B"]: return false
	if int(receipt.level) != Registry.level_for_xp(int(profile.hero_xp[receipt.hero_id])): return false
	var resolved: Dictionary = Resolver.resolve(receipt.hero_id, int(receipt.level), receipt.loadout_snapshot, receipt.equipment_snapshot)
	return runtime_valid(value.get("runtime"), receipt.hero_id, resolved, int(value.node_index) == 0 and value.completed_nodes.is_empty())
