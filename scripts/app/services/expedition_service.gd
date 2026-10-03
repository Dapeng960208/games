extends RefCounted
## Expedition behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host
const FINALE_RING_ID := "B10-EASTER-RING"

func _init(context: Node) -> void:
	host = context

func finale_ring_claimed(profile: Dictionary) -> bool:
	if not str(profile.get("finale_ring_claimed", "")).is_empty(): return true
	# Earlier candidate profiles may own the ring before the permanent receipt
	# exists. Discovery also survives selling or dismantling that old instance.
	if FINALE_RING_ID in profile.get("equipment_discoveries", []): return true
	for item: Dictionary in profile.get("equipment", {}).values():
		if item.get("template_id") == FINALE_RING_ID: return true
	return false

func bank_finale_ring(next_profile: Dictionary) -> Dictionary:
	var result := {"ok":true,"retained":[]}
	if finale_ring_claimed(next_profile) or host.run == null or host.run.hp <= 0.0: return result
	var value: Dictionary = host.run.expedition
	if host.run.ruleset_version() != host.Numbers.V2 or value.is_empty() or int(value.difficulty) != 4 or value.phase != "cleared": return result
	var index: int = int(value.node_index)
	var node: Dictionary = value.route.nodes[index]
	var completion: String = host.run.id + ":node:" + str(index) + ":complete"
	if value.route.biome_id != "B10" or index != value.route.nodes.size() - 1 or node.role != "boss" or node.room_id != "BO10": return result
	if "BO10" not in host.run.boss_defeats or index not in value.completed_nodes or value.completion_events.get(completion, -1) != index or completion not in host.run.completed_reward_ids: return result
	# The deterministic item and its forever receipt join the existing detached
	# extraction save. A failed write neither consumes the claim nor rerolls it.
	var source: String = host.run.id + ":finale_ring"
	var item: Dictionary = host.Instances.make_finale_ring(source, host.run.hero_id)
	if item.is_empty() or not host.Instances.validate(item).is_empty() or next_profile.equipment.has(item.instance_id): return {"ok":false,"retained":[]}
	var count: int = host.Loot.inventory_count(next_profile)
	var capacity: int = int(next_profile.get("inventory_capacity", 0))
	item.location = "inventory" if capacity == 0 or count < capacity else "pending"
	next_profile.equipment[item.instance_id] = item
	next_profile["finale_ring_claimed"] = source
	if FINALE_RING_ID not in next_profile.equipment_discoveries: next_profile.equipment_discoveries.append(FINALE_RING_ID)
	result.retained.append(str(item.instance_id))
	return result

func advance_expedition_node(runtime_snapshot: Dictionary = {}, expected_checkpoint_id: String = "") -> bool:
	if not host._expedition_active() or not host.run.expedition.phase in ["safe", "cleared"]: return false
	if not expected_checkpoint_id.is_empty() and expected_checkpoint_id != str(host.run.expedition.checkpoint_id): return false
	var previous: int = int(host.run.expedition.node_index)
	if previous + 1 >= host.run.expedition.route.nodes.size(): return false
	for offer: Dictionary in host.run.expedition.offers.values():
		if bool(offer.get("required", false)) and offer.decision == "": return false
	var index: int = previous + 1
	var value: Dictionary = host.run.expedition.duplicate(true)
	if host.Expedition.Routes.is_template_node(value.route.nodes[index]) and not value.locked_nodes.has(str(index)):
		if value.route.nodes[index].options.size() != 1: return false
		value.locked_nodes[str(index)] = value.route.nodes[index].room_id
	var runtime: Dictionary = host._safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	if not previous in value.completed_nodes: value.completed_nodes.append(previous)
	value.node_index = index
	var role: String = str(value.route.nodes[index].role)
	value.phase = "safe" if role == "supply" else "combat"
	value.checkpoint_id = host.run.id + ":entry:" + str(index)
	value.room_entry_gold = host.run.gold
	value.room_entry_kills = host.run.kills
	value.room_entry_shots = host.run.shots
	if role == "supply": host.Expedition.add_supply_offers(value, host.run.id)
	if role != "supply" and value.temporary_buffs.has("amplify"):
		var buff: Dictionary = value.temporary_buffs.amplify
		if int(buff.get("remaining_rooms", 0)) <= 0: value.temporary_buffs.erase("amplify")
	# Bought protection belongs to one combat room, including an unused reserve.
	# Checkpoint saves preserve it; only a committed room transition removes it.
	for source: String in runtime.status.guards.keys():
		if source.begins_with("supply:"): runtime.status.guards.erase(source)
	if role != "supply" and value.temporary_buffs.has("pending_supply_shield"):
		# Start the four-second countdown on actual absorption, not room entry.
		runtime.status.guards["supply:ready:" + str(index)] = {"amount":host.Numbers.amount(host.run.max_hp * 0.15, host.run.ruleset_version()),"remaining":4.0}
		value.temporary_buffs.erase("pending_supply_shield")
	return host._commit_expedition(value, runtime, host.profile.duplicate(true))

func commit_expedition_completion(completion_id: String, runtime_snapshot: Dictionary, rewards: Dictionary = {}) -> bool:
	if not host._expedition_active() or completion_id.is_empty() or completion_id.length() > 160: return false
	if host.run.expedition.completion_events.has(completion_id): return true
	if host.run.expedition.phase != "combat": return false
	var index: int = int(host.run.expedition.node_index)
	if host.run.ruleset_version() == host.Numbers.V2:
		if completion_id != host.run.id + ":node:" + str(index) + ":complete": return false
		var expected = host.RoomRewards.v2_completion(str(host.run.expedition.route.nodes[index].room_id), int(host.run.expedition.difficulty), str(rewards.get("quality", "full")))
		if expected.is_empty() or (not rewards.is_empty() and rewards != expected): return false
		rewards = expected
	if index in host.run.expedition.completed_nodes: return false
	var runtime: Dictionary = host._safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	for key in ["gold", "xp", "mastery"]:
		if not host.Expedition.number(rewards.get(key, 0), 10000 if key == "gold" else 900): return false
	var drops: Variant = rewards.get("equipment", [])
	if not drops is Array or drops.size() > 8: return false
	var value: Dictionary = host.run.expedition.duplicate(true)
	value.gold_earned += int(rewards.get("gold", 0))
	if host.run.ruleset_version() == host.Numbers.V2:
		host._ensure_loot_state(value)
		for request: Dictionary in host.run.staged_loot_requests.values():
			if not host.Loot.add(value, host.run.id, host.run.hero_id, request.event_id, request.source, int(request.zone_index), str(request.actor_id)): return false
		if not host.Loot.add(value, host.run.id, host.run.hero_id, completion_id, str(rewards.source)): return false
		value.loot_events[completion_id]["quality"] = str(rewards.quality)
		value.loot_events[completion_id].gold = int(rewards.gold)
	for drop: Variant in drops:
		if not drop is Dictionary or not host._add_equipment_drop(value, str(drop.get("drop_id", "")), str(drop.get("equipment_id", "")), drop.get("drop_level", 0)): return false
	var next_profile: Dictionary = host.profile.duplicate(true)
	var xp: int = int(rewards.get("xp", 30))
	# Existing room XP callbacks stage IDs, never create a second award when the
	# completion payload supplies the authoritative total for that same room.
	if not rewards.has("xp"):
		xp = 0
		for amount: int in host.run.staged_xp.values(): xp += amount
		if xp == 0: xp = 30
	var completed_rewards: Array = host.run.completed_reward_ids.duplicate()
	if completed_rewards.size() + host.run.staged_xp.size() + 1 > 512: return false
	for id: String in host.run.staged_xp:
		if not id in completed_rewards: completed_rewards.append(id)
	if not completion_id in completed_rewards: completed_rewards.append(completion_id)
	if host.run.staged_tutorial and not host.run.hero_id in next_profile.tutorial_completed:
		next_profile.tutorial_completed.append(host.run.hero_id)
		xp += 30
		if host.run.ruleset_version() == host.Numbers.V2: value.loot_events[completion_id]["tutorial_xp"] = 30
	var previous_xp: int = int(next_profile.hero_xp[host.run.hero_id])
	next_profile.hero_xp[host.run.hero_id] = mini(3600, previous_xp + xp)
	var added: int = int(next_profile.hero_xp[host.run.hero_id]) - previous_xp
	if host.run.ruleset_version() == host.Numbers.V2:
		var award_input = next_profile.duplicate(true)
		award_input.hero_xp[host.run.hero_id] = previous_xp
		var awarded = host.Progression.award(award_input, host.run.hero_id, xp, completion_id, host._run_race(), true)
		if awarded.is_empty(): return false
		next_profile = awarded.profile
		added = int(awarded.added)
		host.Loot.defer_research(value, completion_id, awarded.get("material_reward", {}))
	var bosses: Array = host.run.boss_defeats.duplicate()
	var boss: String = str(rewards.get("boss_id", ""))
	if value.route.nodes[index].role == "boss":
		var expected: String = str(value.route.nodes[index].room_id)
		if not boss.is_empty() and boss != expected: return false
		if not expected in bosses: bosses.append(expected)
	elif not boss.is_empty(): return false
	value.completed_nodes.append(index)
	value.completion_events[completion_id] = index
	value.phase = "cleared"
	value.checkpoint_id = host.run.id + ":cleared:" + str(index)
	value.mastery = mini(900, int(value.mastery) + int(rewards.get("mastery", 180)))
	var rank: int = 1
	for threshold: int in host.Expedition.MASTERY_THRESHOLDS:
		if int(value.mastery) >= threshold: rank += 1
	rank = mini(6, rank - 1)
	for new_rank in range(int(value.mastery_rank) + 1, rank + 1): host.Expedition.add_relic_offer(value, host.run.id, new_rank)
	value.mastery_rank = rank
	if value.temporary_buffs.has("amplify"):
		value.temporary_buffs.amplify.remaining_rooms = maxi(0, int(value.temporary_buffs.amplify.remaining_rooms) - 1)
	if not next_profile.has("equipment_discoveries"): next_profile.equipment_discoveries = []
	for eq: String in value.equipment_discoveries:
		if not eq in next_profile.equipment_discoveries: next_profile.equipment_discoveries.append(eq)
	var skill_group: String = {"L05":"SG02", "L17":"SG06", "L23":"SG08"}.get(str(value.route.nodes[index].room_id), "")
	if not skill_group.is_empty():
		next_profile = host.SkillGrowth.unlock_group(next_profile, skill_group)
		if next_profile.is_empty(): return false
	return host._commit_expedition(value, runtime, next_profile, {"hero_xp_gained":host.run.hero_xp_gained + added,"completed_reward_ids":completed_rewards,"boss_defeats":bosses})

func choose_run_relic(offer_id: String, choice_id: String, replacement_id: String = "", runtime_snapshot: Dictionary = {}) -> bool:
	if not host._expedition_active() or not host.run.expedition.phase in ["safe", "cleared"] or not host.run.expedition.offers.has(offer_id): return false
	var offer: Dictionary = host.run.expedition.offers[offer_id]
	if offer.kind != "relic": return false
	if offer.decision != "": return offer.decision == choice_id and str(offer.get("replacement_id", "")) == replacement_id
	if choice_id != "skip" and not choice_id in offer.candidates: return false
	var runtime: Dictionary = host._safe_runtime(runtime_snapshot)
	if runtime.is_empty(): return false
	var value: Dictionary = host.run.expedition.duplicate(true)
	# These safe-boundary heals use the same bounded calculation as combat heals,
	# but must stay in the proposed snapshot until its transaction commits.
	if choice_id == "skip": runtime.hp = host._combat_amount(float(runtime.hp) + float(host._healing_gain(float(runtime.hp), host.run.max_hp, host.run.max_hp * 0.06)))
	else:
		if int(value.relic_levels.get(choice_id, 0)) >= 2: return false
		if not value.relic_levels.has(choice_id) and value.relic_levels.size() >= 4:
			if not value.relic_levels.has(replacement_id): return false
			value.relic_levels.erase(replacement_id)
		elif not replacement_id.is_empty(): return false
		value.relic_levels[choice_id] = int(value.relic_levels.get(choice_id, 0)) + 1
	value.offers[offer_id].decision = choice_id
	value.offers[offer_id]["replacement_id"] = replacement_id
	var legacy: Array[String] = []
	for id: String in value.relic_levels:
		if host.Expedition.LEGACY_RELICS.has(id): legacy.append(host.Expedition.LEGACY_RELICS[id])
	return host._commit_expedition(value, runtime, host.profile.duplicate(true), {"discoveries":legacy})

func purchase_run_supply(offer_id: String, runtime_snapshot: Dictionary = {}) -> bool:
	if not host._expedition_active() or host.run.expedition.phase != "safe" or not host.run.expedition.offers.has(offer_id): return false
	if host.run.expedition.route.nodes[int(host.run.expedition.node_index)].role != "supply": return false
	var offer: Dictionary = host.run.expedition.offers[offer_id]
	if offer.kind != "supply": return false
	if offer.decision == "purchased": return true
	var price: int = int(offer.price)
	if host.run.gold < price: return false
	var runtime: Dictionary = host._safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	var value: Dictionary = host.run.expedition.duplicate(true)
	var product: String = str(offer.product_id)
	match product:
		"heal_small", "heal_large":
			if float(runtime.hp) >= host.run.max_hp: return false
			for other: Dictionary in value.offers.values():
				if other.get("product_id", "") in ["heal_small", "heal_large"] and other.decision == "purchased": return false
			runtime.hp = host._combat_amount(float(runtime.hp) + float(host._healing_gain(float(runtime.hp), host.run.max_hp, host.run.max_hp * (0.15 if product == "heal_small" else 0.35))))
		"shield":
			if value.temporary_buffs.has("pending_supply_shield"): return false
			value.temporary_buffs["pending_supply_shield"] = {"hp_ratio":0.15,"duration":4.0}
		"mana", "energy":
			if str(host.run.stats.resource_type) != product or float(runtime.resource) >= float(host.run.stats.resource_max): return false
			runtime.resource = host._combat_amount(minf(float(host.run.stats.resource_max), float(runtime.resource) + float(host._combat_amount(float(host.run.stats.resource_max) * (0.30 if product == "mana" else 0.20)))))
		"amplify":
			if value.temporary_buffs.has("amplify"): return false
			value.temporary_buffs["amplify"] = {"damage_bonus":0.08,"remaining_rooms":2}
		"scan":
			var added: bool = false
			for index: int in host.Expedition.Routes.scan_indices(value.route):
				if not index in value.scan_nodes:
					value.scan_nodes.append(index)
					added = true
			if not added: return false
		_: return false
	value.gold_spent += price
	value.offers[offer_id].decision = "purchased"
	value.purchased_offer_ids.append(offer_id)
	return host._commit_expedition(value, runtime, host.profile.duplicate(true))

func prepare_safe_resources(runtime_snapshot: Dictionary = {}, expected_checkpoint_id: String = "") -> bool:
	# Resource recovery is a combat pacing rule, not a paid safe-room delay.
	if not host._expedition_active() or host.run.expedition.phase != "safe": return false
	if host.run.expedition.route.nodes[int(host.run.expedition.node_index)].role != "supply": return false
	if not expected_checkpoint_id.is_empty() and expected_checkpoint_id != str(host.run.expedition.checkpoint_id): return false
	if str(host.run.stats.resource_type) not in ["mana", "energy"]: return false
	var runtime: Dictionary = host._safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	if float(runtime.resource) >= float(host.run.stats.resource_max): return true
	runtime.resource = host._combat_amount(float(host.run.stats.resource_max))
	return host._commit_expedition(host.run.expedition.duplicate(true), runtime, host.profile.duplicate(true))

func _ensure_loot_state(value: Dictionary) -> void:
	if not value.has("loot_events"):
		host.Loot.initialize(value, {"gold_pity":{}}, host.run.id)

## Natural actor IDs come from a deterministic zone/wave/spawn position. The
## commit retains the entry runtime, never a partially fought room snapshot.
func record_expedition_kill_reward(spawn_id: String, enemy_id: String, elite: bool = false, summoned: bool = false, zone_index: int = 0) -> bool:
	if not host._stage_expedition_kill(spawn_id,enemy_id,elite,summoned,zone_index): return false
	return host.flush_expedition_kill_rewards()

func queue_expedition_kill_reward(spawn_id: String, enemy_id: String, elite: bool = false, summoned: bool = false, zone_index: int = 0) -> bool:
	if not host._stage_expedition_kill(spawn_id,enemy_id,elite,summoned,zone_index): return false
	if not host.run.staged_loot_requests.is_empty() and not host._kill_flush_scheduled:
		host._kill_flush_scheduled = true
		call_deferred("flush_expedition_kill_rewards")
	return true

func _stage_expedition_kill(spawn_id: String, enemy_id: String, elite: bool, summoned: bool, zone_index: int) -> bool:
	if not host._expedition_active() or host.run.ruleset_version() != host.Numbers.V2 or host.run.expedition.phase != "combat": return false
	if summoned: return true
	if spawn_id.is_empty() or spawn_id.length() > 80 or host.Expedition.Catalog.enemy(enemy_id).is_empty() or zone_index < 0 or zone_index > 2: return false
	var id = host.run.id + ":node:" + str(int(host.run.expedition.node_index)) + ":kill:" + spawn_id
	var source = "elite" if elite else "normal"
	if host.run.expedition.loot_events.has(id): return host.run.expedition.loot_events[id].result.context.source == source and int(host.run.expedition.loot_events[id].zone_index) == zone_index and host.run.expedition.loot_events[id].get("actor_id", "") == enemy_id
	var request = {"event_id":id,"source":source,"zone_index":zone_index,"actor_id":enemy_id}
	if host.run.staged_loot_requests.has(id): return host.run.staged_loot_requests[id] == request
	host.run.staged_loot_requests[id] = request
	return true

func flush_expedition_kill_rewards() -> bool:
	# One atomic journal write for a burst of kills, outside damage callbacks.
	# Completion and settlement also drain staged events before changing rooms.
	host._kill_flush_scheduled = false
	if host.run == null or host.run.staged_loot_requests.is_empty(): return true
	if host.run.ruleset_version() != host.Numbers.V2 or host.run.expedition.get("phase") != "combat" or host._settling: return false
	var value = host.run.expedition.duplicate(true)
	host._ensure_loot_state(value)
	for request: Dictionary in host.run.staged_loot_requests.values():
		if not host.Loot.add(value, host.run.id, host.run.hero_id, request.event_id, request.source, int(request.zone_index), str(request.actor_id)): return false
	var receipt = host.run.receipt()
	for key: String in ["loot_seed","wish_slot","pity_snapshot","loot_events","pending_materials","pending_equipment","claimed_drop_ids","equipment_discoveries","optional_claims"]:
		receipt.expedition[key] = value[key].duplicate(true) if value[key] is Dictionary or value[key] is Array else value[key]
	# Field decisions can reference a live loadout that is intentionally not in
	# the entry snapshot. The items remain pending and safe to recover there.
	if not host._save(host.profile, receipt): return false
	host.run.expedition = value
	host.run.committed_receipt = receipt.duplicate(true)
	host.run.staged_loot_requests.clear()
	host.changed.emit()
	return true
