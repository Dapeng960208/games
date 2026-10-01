extends Node
const Fixtures = preload("res://tests/test_numerical_instance_storage.gd")
const Saves = preload("res://tests/test_numerical_versioned_saves.gd")
const Loot = preload("res://scripts/core/expedition_rewards.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Backpack = preload("res://scripts/core/backpack_equipment.gd")
const Rewards = preload("res://scripts/world/room_rewards.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func boundary() -> Dictionary:
	return Saves.runtime(Game.run.hero_id, mini(711, int(Game.run.max_hp)), mini(123, int(Game.run.stats.resource_max)), 2)

func fixture(extra: int = 0) -> Dictionary:
	var value := Fixtures.fixture_profile()
	value.hero_xp.CH01 = 3600
	value.permanent_gold = 100000
	value.bosses = ["BO01","BO02","BO03","BO04"]
	value.materials = {"forge":1000,"race:B01":1000,"race:B02":1000,"race:B03":1000,"race:B04":1000,"core:B01":100,"core:B02":100,"core:B03":100,"core:B04":100}
	for i in extra: value.equipment["large:" + str(i)] = Fixtures.fixture_instance("large:" + str(i), "EQ03")
	return value

func begin(value: Dictionary, difficulty: int = 0) -> bool:
	Game.run = null
	Game._pending_outcome = ""
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	if not Game.new_profile() or not Game._commit_profile(value): return false
	return Game.start_run({"expedition":true,"seed":1735,"difficulty":difficulty,"wish_slot":"weapon"})

func advance() -> bool:
	for offer: Dictionary in Game.expedition_snapshot().relic_offers:
		if not Game.choose_run_relic(str(offer.offer_id), "skip", "", boundary()): return false
	var next: Dictionary = Game.expedition_snapshot().next_node
	return Game.choose_expedition_node(int(next.node_index), str(next.room_id)) and Game.advance_expedition_node(boundary())

func clear_room() -> bool:
	if Game.run.expedition.phase == "safe": return true
	return Game.commit_expedition_completion(Game.run.id + ":node:" + str(int(Game.run.expedition.node_index)) + ":complete", boundary())

func _ready() -> void:
	if not Game.profile_path.contains("test_numerical_acquisition_lifecycle"):
		get_tree().quit(2)
		return
	check(begin(fixture(520)), "large inventory starts without512 cap")
	check(Game.profile.equipment.size() == 528 and Game.run.equipment_snapshot.size() == 8, "only equipped identities carried; permanent inventory intact")
	check(advance(), "enter real combat checkpoint")
	var before: Dictionary = Game.profile.duplicate(true)
	var receipt: Dictionary = Game.run.receipt()
	Game._store.max_document_bytes = 1
	check(not clear_room() and Game.profile == before and Game.run.receipt() == receipt, "failed clear leaves all rewards and XP untouched")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(clear_room(), "room grant commits")
	Game.reload_profile()
	check(Game.run != null and Game.run.expedition.phase == "cleared", "actual disk reload preserves cleared gear/material receipt")
	check(Game.finish_run("death").get("equipment_retained", ["bad"]).is_empty() and Game.profile.equipment.size() == 528 and Loot.same(Game.profile.materials, before.materials), "death banks no large-inventory loot/materials")
	_natural_and_research()
	_extraction_and_chest()
	_transactions()
	_reward_qualities()
	_pity()
	_no_gold_pity_and_compatibility()
	_nonexpedition_research()
	print("Numerical acquisition lifecycle: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func find_trigger(source: String, start: int = 0, template: String = "") -> String:
	for serial in range(start, start + 10000):
		var spawn := source + ":" + str(serial)
		var id: String = Game.run.id + ":node:" + str(int(Game.run.expedition.node_index)) + ":kill:" + spawn
		var context := Loot.context(Game.run.expedition, Game.run.id, Game.run.hero_id, id, source, 0)
		var result := Acquisition.roll_event(context)
		if result.get("triggered", false) and (template.is_empty() or result.items[0].template_id == template): return spawn
	return ""

class EventSink extends RefCounted:
	func event(_kind: String, _context: Dictionary) -> void: pass

func _natural_and_research() -> void:
	var value := fixture()
	value.research_xp = {"CH01":330}
	check(begin(value), "research fixture departure")
	check(advance(), "research fixture enters combat")
	var first := find_trigger("normal")
	var start := int(first.get_slice(":", 1)) + 1
	var first_id: String = Game.run.id + ":node:" + str(int(Game.run.expedition.node_index)) + ":kill:" + first
	var first_result := Acquisition.roll_event(Loot.context(Game.run.expedition, Game.run.id, Game.run.hero_id, first_id, "normal", 0))
	var second := find_trigger("normal", start, str(first_result.items[0].template_id))
	var third := find_trigger("normal", int(second.get_slice(":", 1)) + 1)
	var before: Dictionary = Game.run.receipt()
	Game._store.max_document_bytes = 1
	check(not Game.record_expedition_kill_reward(first, "M01") and Game.run.receipt() == before and Game.run.expedition.pending_equipment.is_empty(), "failed natural save exposes no partial grant")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.record_expedition_kill_reward(first, "M01"), "natural retry commits same frozen identity")
	var one: Dictionary = Game.run.expedition.pending_equipment.duplicate(true)
	check(Game.record_expedition_kill_reward(first, "M01") and Game.run.expedition.pending_equipment == one, "duplicate kill does not grant again")
	Game.reload_profile()
	check(Game.run != null and Game.run.expedition.phase == "combat" and Loot.same(Game.run.expedition.pending_equipment, one), "kill result persists while room entry checkpoint stays authoritative")
	check(Game.record_expedition_kill_reward(first, "M01") and Game.run.expedition.pending_equipment.size() == 1, "same spawned actor cannot reroll after checkpoint restart")
	check(Game.record_expedition_kill_reward(second, "M01") and Game.record_expedition_kill_reward(third, "M01") and Game.run.expedition.pending_equipment.size() == 2, "natural normal cap exactly2 per room")
	var copies: Array = Game.run.expedition.pending_equipment.values()
	check(copies[0].template_id == copies[1].template_id and copies[0].instance_id != copies[1].instance_id and Game.run.gold == 0, "same-template drops retain independent identities and never convert to gold")
	var elite := find_trigger("elite")
	var elite2 := find_trigger("elite", int(elite.get_slice(":", 1)) + 1)
	# Real MineRoom death callback dispatches stable identity to the Game API.
	var room := MineRoom.new()
	room.enemies = Node2D.new()
	room.add_child(room.enemies)
	room.player = load("res://scripts/combat/player.gd").new()
	room.add_child(room.player)
	room.player.loadout = EventSink.new()
	room.expedition_context = {"node_index":int(Game.run.expedition.node_index)}
	var enemy := MineEnemy.new()
	enemy.enemy_id = "M01"
	enemy.rank = "elite"
	enemy.reward_spawn_id = elite
	enemy.zone_index = 0
	room.enemies.add_child(enemy)
	room.enemy_died(enemy)
	check(Game.run.expedition.pending_equipment.size() == 3 and int(Game.run.expedition.pending_materials.forge) == 2, "real room elite death creates one gear and its own material event")
	check(Game.record_expedition_kill_reward(elite2, "M01", true) and Game.run.expedition.pending_equipment.size() == 3 and int(Game.run.expedition.pending_materials.forge) == 4, "elite gear cap1 but each natural elite materials unique")
	var count: int = Game.run.expedition.loot_events.size()
	enemy.reward_enabled = false
	enemy.reward_spawn_id = "summoned"
	room.enemy_died(enemy)
	check(Game.run.expedition.loot_events.size() == count and Game.run.kills == 1, "summon/revival/boss adds bypass gear materials XP coins and corpse rewards")
	room.free()
	var id: String = str(Game.run.expedition.pending_equipment.keys()[0])
	var slot: String = str(ContentRegistry.equipment(Game.run.expedition.pending_equipment[id].template_id, 2).slot)
	var health: int = mini(711, int(Game.run.max_hp))
	var change := Backpack.change(Game, id, slot, boundary(), Game.run.expedition.checkpoint_id)
	check(change.get("success", false) and Game.run.loadout_snapshot[slot] == id and Game.run.equipment_snapshot.size() <= 8, "pending instance equips live with bounded carried snapshot")
	check(Game.run.hp <= health and change.runtime.player.cooldowns.q == 3.25 and change.runtime.equipment.cooldowns.EQ24 == 23.5, "field equip preserves absolute injury skillCD and equipmentICD")
	var materials_before: Dictionary = Game.profile.materials.duplicate(true)
	check(clear_room(), "kill and room rewards checkpoint together")
	var event: String = Game.run.id + ":node:1:complete"
	check(Game.profile.research_xp.CH01 == 0 and Game.profile.materials == materials_before and Game.run.expedition.loot_events[event].research_materials == {"forge":4,"race:B01":1}, "research XP persists but earned materials remain carry-out")
	check(int(Game.run.expedition.pending_materials.forge) == 11 and int(Game.run.expedition.pending_materials["race:B01"]) == 4, "elite room and research material receipts sum independently once")
	var pending: Dictionary = Game.run.expedition.pending_equipment.duplicate(true)
	check(clear_room() and Game.run.expedition.pending_equipment == pending, "duplicate completion does not duplicate gear or materials")
	Game.reload_profile()
	check(Game.run != null and Game.run.loadout_snapshot[slot] == id and Loot.same(Game.run.expedition.pending_equipment, pending), "field equipment and complete rolls survive checkpoint reload")
	var invalid: Dictionary = Game.run.receipt()
	invalid.expedition.pending_materials.forge += 1
	check(not ExpeditionState.valid(invalid, Game.profile), "tampered material total rejected")
	invalid = Game.run.receipt()
	invalid.expedition.loot_events[event].result.items[0].rarity = "gold"
	check(not ExpeditionState.valid(invalid, Game.profile), "tampered random payload rejected")
	check(not Game.finish_run("death").is_empty() and Game.profile.materials == materials_before and Game.profile.equipment.size() == 8 and Game.profile.research_xp.CH01 == 0 and Game.profile.progression_receipts.has(event), "death drops gear and research materials but keeps XP receipt")
	Game.reload_profile()
	check(Game.run == null and Game.profile.equipment.size() == 8 and Game.profile.materials == materials_before, "death settlement remains lost after reload")

func _extraction_and_chest() -> void:
	var value := fixture()
	value.inventory_capacity = 8
	value.research_xp = {"CH01":330}
	check(begin(value), "full-inventory extraction departure")
	var optional_seen := false
	while Game.run != null:
		if not advance(): check(false, "extraction route transition"); break
		if Game.run.expedition.phase == "safe": continue
		check(clear_room(), "canonical room reward")
		var node: Dictionary = Game.run.expedition.route.nodes[int(Game.run.expedition.node_index)]
		var objective: String = {"L01":"side_crate","L11":"research_2"}.get(node.room_id, "")
		if not objective.is_empty():
			var gear_before: int = Game.run.expedition.pending_equipment.size()
			var material_before: Dictionary = Game.run.expedition.pending_materials.duplicate(true)
			var xp_before: Dictionary = Game.profile.hero_xp.duplicate(true)
			var gold_before: int = Game.run.gold
			check(Game.claim_expedition_optional_reward(int(node.node_index), objective, boundary(), Game.run.expedition.checkpoint_id), "optional chest commits")
			check(Game.run.expedition.pending_equipment.size() == gear_before + 1 and Game.run.expedition.pending_materials == material_before and Game.profile.hero_xp == xp_before and Game.run.gold - gold_before == 36, "chest exactly1 gear and gold×2 with noXP or materials")
			check(Game.claim_expedition_optional_reward(int(node.node_index), objective, boundary(), Game.run.expedition.checkpoint_id) and Game.run.expedition.pending_equipment.size() == gear_before + 1, "chest retry never regrants")
			Game.reload_profile()
			check(Game.run != null and Game.run.expedition.optional_claims.size() == 1, "optional receipt survives reload")
			optional_seen = true
		if node.early_extraction:
			var earned: Dictionary = Game.run.expedition.pending_materials.duplicate(true)
			var gear: Dictionary = Game.run.expedition.pending_equipment.duplicate(true)
			var before: Dictionary = Game.profile.duplicate(true)
			Game._store.max_document_bytes = 1
			check(Game.finish_run("extracted").is_empty() and Game.profile == before and Game.run != null, "failed settlement grants neither gear nor materials")
			Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
			check(not Game.finish_run("extracted").is_empty() and Game.profile.equipment.size() == 8 + gear.size(), "extraction banks independent identities without deletion")
			for id: String in gear: check(Game.profile.equipment[id].location == "pending", "full inventory banks unclaimed gear in permanent equipment")
			for key: String in earned: check(int(Game.profile.materials[key]) == int(before.materials.get(key, 0)) + int(earned[key]), "extraction banks each material once " + key)
			var id: String = str(gear.keys()[0])
			check(not Game.claim_pending_equipment(id, "claim:full") and Game.profile.equipment[id].location == "pending", "full bank claim is explicit and does not sell")
			var open := Game.profile.duplicate(true)
			open.inventory_capacity = 0
			check(Game._commit_profile(open) and Game.claim_pending_equipment(id, "claim:free") and Game.claim_pending_equipment(id, "claim:free"), "unbounded capacity explicit claim retries once")
			Game.reload_profile()
			check(Game.run == null and Game.profile.equipment[id].location == "inventory", "banked overflow and claim survive reload")
			break
	check(optional_seen, "route exercised authored optional chest")

func _transactions() -> void:
	check(begin(fixture()), "transaction fixture")
	check(not Game.finish_run("abandoned").is_empty(), "return to camp")
	var request := {"template_id":"EQ03","rarity":"green","power_type":"physical","item_level":5}
	var before: Dictionary = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game.purchase_equipment_v2(request, "purchase:one").get("ok", false) and Game.profile == before, "failed purchase does not debit or expose grant")
	var frozen: Dictionary = Game._pending_instance_transactions["purchase:one"].receipt.duplicate(true)
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	var result := Game.purchase_equipment_v2(request, "purchase:one")
	check(result.get("ok", false) and result.receipt == frozen and Game.profile.equipment.size() == 9, "purchase save retry reuses full frozen receipt")
	var after: Dictionary = Game.profile.duplicate(true)
	check(Game.purchase_equipment_v2(request, "purchase:one").get("replayed", false) and Game.profile == after, "purchase repeats no debit or grant")
	check(Game.purchase_equipment_v2(request, "purchase:two").get("ok", false) and Game.profile.equipment.size() == 10, "same template purchase is independent instance")
	request.rarity = "purple"
	request.item_level = 10
	before = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game.craft_equipment_v2(request, "craft:one").get("ok", false) and Game.profile == before, "failed craft leaves materials wallet and instances untouched")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.craft_equipment_v2(request, "craft:one").get("ok", false), "craft commits")
	after = Game.profile.duplicate(true)
	check(Game.craft_equipment_v2(request, "craft:one").get("replayed", false) and Game.profile == after, "craft receipt idempotent")
	Game.reload_profile()
	check(Game.purchase_equipment_v2({"template_id":"EQ03","rarity":"green","power_type":"physical","item_level":5}, "purchase:one").get("replayed", false) and Game.profile.equipment.size() == 11, "transactions replay after JSON reload")
	check(Game.equip_equipment_set("S01"), "V2 equip8 set uses owned compatible instances")

func complete_boss() -> bool:
	while true:
		if not advance(): return false
		if not clear_room(): return false
		if Game.run.expedition.route.nodes[int(Game.run.expedition.node_index)].role == "boss": return true
	return false

func _pity() -> void:
	var value := fixture()
	value.gold_pity = {"B01":3,"B02":2,"B03":1,"B04":0}
	check(begin(value, 4), "D4 departure freezes per-race pity")
	check(Game.run.expedition.pity_snapshot == value.gold_pity, "pity is frozen at departure")
	check(complete_boss(), "real D4 route reaches boss completion")
	var boss_event: String = Game.run.id + ":node:" + str(int(Game.run.expedition.node_index)) + ":complete"
	var result: Dictionary = Game.run.expedition.loot_events[boss_event].result
	var gold := false
	for item: Dictionary in result.items:
		if item.rarity == "gold": gold = true; check(int(item.enhancement_rank) <= 1, "pity gold respects fresh +0/+1 boundary")
	check(gold and result.items.size() == 4 and result.context.force_gold, "fourth eligible boss grant guaranteed gold with unchanged count")
	Game.reload_profile()
	check(Game.run != null and Loot.same(Game.run.expedition.loot_events[boss_event].result, result), "pity reward frozen across reload")
	check(not Game.finish_run("death").is_empty() and Loot.same(Game.profile.gold_pity, value.gold_pity), "death with generated gold does not change any pity counter")
	check(begin(value, 4) and complete_boss(), "second eligible trip completes")
	Game._store.max_document_bytes = 1
	check(Game.finish_run("extracted").is_empty() and Game.profile.gold_pity == value.gold_pity, "failed bank leaves pity unchanged")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(not Game.finish_run("extracted").is_empty() and Game.profile.gold_pity.B01 == 0 and Game.profile.gold_pity.B02 == 2, "successful gold carryout clears only eligible race once")
	Game.reload_profile()
	check(Game.run == null and Game.profile.gold_pity.B01 == 0, "pity settlement persists on disk")
	check(begin(value, 0) and complete_boss() and not Game.finish_run("extracted").is_empty() and Game.profile.gold_pity == value.gold_pity, "other difficulty boss extraction neither advances nor clears pity")

func _reward_qualities() -> void:
	for room: String in ["L02","L03","L06","L08","L09","L12","L13","L16","L17","L20","L23"]:
		var qualities: Array = Rewards.qualities(room, 2)
		check(qualities.size() > 1, "authored V2 alternate quality retained " + room)
		for quality: String in qualities:
			var reward := Rewards.build(room, quality, "CH01", 1, "fixture", [], [], [], 2, 2)
			check(not reward.is_empty() and reward.source == "room" and reward.quality == quality, "authored quality canonical V2 payload " + room + ":" + quality)
	check(begin(fixture(), 1), "alternate quality real Game fixture")
	var tested := false
	while not tested:
		if not advance(): break
		if Game.run.expedition.phase == "safe": continue
		var room: String = str(Game.run.expedition.route.nodes[int(Game.run.expedition.node_index)].room_id)
		var qualities: Array = Rewards.qualities(room, 2)
		if qualities.size() > 1:
			var id: String = Game.run.id + ":node:" + str(int(Game.run.expedition.node_index)) + ":complete"
			var reward := Rewards.build(room, str(qualities[1]), Game.run.hero_id, int(Game.run.expedition.seed), id, [], [], [], 1, 2)
			var gold: int = Game.run.gold
			var count: int = Game.run.expedition.pending_equipment.size()
			check(Game.commit_expedition_completion(id, boundary(), reward) and Game.run.gold == gold + int(reward.gold) and Game.run.expedition.pending_equipment.size() == count + 1, "real alternate-quality completion keeps authored gold and guaranteed independent gear")
			Game.reload_profile()
			check(Game.run != null and Game.run.expedition.phase == "cleared" and Game.run.expedition.loot_events[id].quality == qualities[1], "alternate completion quality persists with atomic reward")
			tested = true
		elif not clear_room(): break
		if Game.run.expedition.route.nodes[int(Game.run.expedition.node_index)].role == "boss": break
	check(tested, "real route includes alternate objective outcome")

func _freeze_no_gold_seed() -> bool:
	var value: Dictionary = Game.run.expedition.duplicate(true)
	var nodes: Array = value.route.nodes
	# Synthetic fixture search occurs only before any actor or reward. The chosen
	# seed is saved via the real departure checkpoint and thereafter never changes.
	for seed in 3000:
		value.loot_seed = seed
		var no_gold := true
		var indices: Array = [nodes.size() - 1]
		for index in range(1, nodes.size() - 1):
			if nodes[index].role != "supply": indices.append(index)
		for index: int in indices:
			value.node_index = index
			var source := "boss" if nodes[index].role == "boss" else "room"
			var id: String = Game.run.id + ":node:" + str(index) + ":complete"
			var result := Acquisition.roll_event(Loot.context(value, Game.run.id, Game.run.hero_id, id, source))
			for item: Dictionary in result.items:
				if item.rarity == "gold": no_gold = false
			if not no_gold: break
		if no_gold:
			value.node_index = 0
			return Game._commit_expedition(value, boundary(), Game.profile.duplicate(true))
	return false

func _no_gold_pity_and_compatibility() -> void:
	var value := fixture()
	value.hero_xp.CH01 = 0
	value.gold_pity = {"B01":0,"B02":2,"B03":0,"B04":0}
	for trip in 3:
		value.gold_pity.B01 = trip
		check(begin(value, 4) and _freeze_no_gold_seed(), "freeze generated no-gold departure " + str(trip))
		check(complete_boss(), "complete real no-gold Boss trip " + str(trip))
		check(not Game.finish_run("extracted").is_empty() and int(Game.profile.gold_pity.B01) == trip + 1 and Game.profile.gold_pity.B02 == 2, "only eligible successful no-gold Boss carryout increments once " + str(trip))
		Game.reload_profile()
		check(Game.run == null and int(Game.profile.gold_pity.B01) == trip + 1, "no-gold count persists " + str(trip))
	value.gold_pity.B01 = 3
	check(begin(value, 4), "non-Boss eligible-difficulty fixture")
	while advance():
		if not clear_room(): break
		if Game.run.expedition.route.nodes[int(Game.run.expedition.node_index)].early_extraction: break
	check(not Game.finish_run("extracted").is_empty() and Game.profile.gold_pity.B01 == 3, "D4 extraction without Boss neither advances nor clears")
	check(begin(fixture(40)), "compatibility fixture starts")
	var old: Dictionary = Game.run.receipt()
	for key: String in ["loot_seed","wish_slot","pity_snapshot","loot_events","pending_materials"]: old.expedition.erase(key)
	old.equipment_snapshot = Game.profile.equipment.duplicate(true)
	check(Game._save(Game.profile, old), "preS05 V2 whole-inventory receipt remains accepted")
	Game.reload_profile()
	check(Game.run != null and Game.profile.equipment.size() == 48 and Game.run.equipment_snapshot.size() == 8, "old V2 checkpoint safely adopts bounded carried snapshot")

func _nonexpedition_research() -> void:
	for extracted: bool in [false, true]:
		Game.run = null
		check(Game._commit_profile(fixture()) and Game.start_run(), "non-expedition V2 research fixture")
		var before: Dictionary = Game.profile.materials.duplicate(true)
		check(Game.grant_hero_xp(360, "research:non-expedition:" + str(extracted)) and Game.profile.materials == before and Game.run.pending_research_materials == {"forge":4,"race:B01":1}, "non-expedition XP receipt also defers research materials")
		if extracted:
			check(not Game.finish_run("extracted").is_empty() and int(Game.profile.materials.forge) == int(before.forge) + 4, "non-expedition successful carryout banks research")
		else:
			Game.reload_profile()
			check(Game.run == null and Loot.same(Game.profile.materials, before), "non-expedition interrupted/abandoned run loses research materials")
