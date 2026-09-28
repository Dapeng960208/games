extends Node
## The UI observes this node; it never calculates damage or grants rewards.

signal changed()
signal run_started()
signal run_finished(result: Dictionary)
signal settlement_failed(outcome: String)

var profile: Dictionary = ProfileStore.fresh_profile()
var run: RunState = null
var last_error: String = ""
var storage_warning: String = ""
var has_profile: bool = false
var last_result: Dictionary:
	get:
		return profile.get("last_result", {}).duplicate(true)

# Tests use isolated paths. Production uses Godot's OS-specific user data folder.
var profile_path := "user://profile.json"
var _store: ProfileStore
var _settling := false
var _pending_outcome: String = ""
const UPGRADE_PRICES := [60, 100, 160, 240, 340]
const Expedition = preload("res://scripts/core/expedition_state.gd")

func _ready() -> void:
	if OS.has_feature("debug") and profile_path == "user://profile.json":
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--test-profile="):
				profile_path = argument.trim_prefix("--test-profile=")
	reload_profile()

func _process(delta: float) -> void:
	if run != null and run.hp > 0.0 and _pending_outcome.is_empty():
		run.elapsed += delta

func reload_profile() -> void:
	_store = ProfileStore.new(profile_path)
	var document := _store.load_document()
	last_error = _store.last_error
	storage_warning = _store.warning
	has_profile = _store.has_profile
	run = null
	_pending_outcome = ""
	if document.is_empty():
		profile = ProfileStore.fresh_profile()
		changed.emit()
		return
	profile = document.profile.duplicate(true)
	if document.active_run is Dictionary:
		if document.active_run.has("expedition"):
			_restore_expedition(document.active_run)
			storage_warning = "STORAGE_CHECKPOINT_RECOVERED"
			changed.emit()
			return
		# M1 never resumes a room. A crash/forced quit is one abandonment settlement.
		var receipt: Dictionary = document.active_run
		run = RunState.new()
		run.id = receipt.id
		run.gold = int(receipt.gold)
		run.relics.assign(receipt.discoveries)
		run.shots = int(receipt.shots)
		run.kills = int(receipt.kills)
		run.elapsed = float(receipt.elapsed)
		run.hero_id = str(receipt.get("hero_id", profile.selected_hero))
		run.level = int(receipt.get("level", hero_level(run.hero_id)))
		run.hero_xp_gained = int(receipt.get("hero_xp_gained", 0))
		run.completed_reward_ids.assign(receipt.get("completed_reward_ids", []))
		run.boss_defeats.assign(receipt.get("boss_defeats", []))
		run.hp = 0.0
		if not finish_run("abandoned").is_empty():
			storage_warning = "STORAGE_ABANDONED_RECOVERED"
	changed.emit()

func new_profile() -> bool:
	if run != null or (_store != null and _store.unresolved_error):
		return false
	var fresh := ProfileStore.fresh_profile()
	fresh.settings = profile.get("settings", fresh.settings).duplicate(true)
	if not _save(fresh, null):
		return false
	profile = fresh
	storage_warning = ""
	has_profile = true
	changed.emit()
	return true

func start_run(options: Dictionary = {}) -> bool:
	if run != null or not has_profile:
		return false
	var next := RunState.new()
	next.id = Crypto.new().generate_random_bytes(16).hex_encode()
	next.hero_id = str(profile.selected_hero)
	next.level = hero_level(next.hero_id)
	next.stats = selected_stats()
	next.branches_snapshot = hero_branches(next.hero_id)
	next.stats.branches = next.branches_snapshot.duplicate(true)
	next.loadout_snapshot = profile.loadout.duplicate(true)
	next.equipment_snapshot = profile.equipment.duplicate(true)
	next.max_hp = float(next.stats.get("max_hp", Balance.PLAYER_HP))
	next.hp = next.max_hp
	next.resource = float(next.stats.get("starting_resource", 0.0))
	if bool(options.get("expedition", false)):
		next.expedition = Expedition.fresh(next.id, options, profile, next.stats)
		if next.expedition.is_empty(): return false
	if not _save(profile, next.receipt()):
		return false
	if not next.expedition.is_empty(): next.committed_receipt = next.live_receipt()
	run = next
	_pending_outcome = ""
	changed.emit()
	run_started.emit()
	return true

func add_gold(amount: int) -> bool:
	if run == null or run.hp <= 0.0 or amount <= 0 or not _pending_outcome.is_empty():
		return false
	if amount > ProfileStore.MAX_NUMBER - run.gold: return false
	if not run.expedition.is_empty() and amount > ProfileStore.MAX_NUMBER - int(run.expedition.gold_earned): return false
	run.gold += amount
	if not run.expedition.is_empty():
		run.expedition.gold_earned += amount
		changed.emit()
		return true
	if not _save(profile, run.receipt()):
		run.gold -= amount
		changed.emit()
		return false
	changed.emit()
	return true

func equip_relic(id: String) -> bool:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not id in ProfileStore.RELIC_IDS or id in run.relics:
		return false
	if not run.expedition.is_empty(): return false # Expedition offers own selection transactions.
	run.relics.append(id)
	if not _save(profile, run.receipt()):
		run.relics.erase(id)
		changed.emit()
		return false
	changed.emit()
	return true

func record_kill() -> void:
	if run != null and _pending_outcome.is_empty():
		run.kills += 1
		changed.emit()

func damage_player(amount: float) -> float:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var armor := maxf(0.0, float(run.stats.get("armor", 0.0)))
	var equipment_dr := clampf(float(run.stats.get("equipment_damage_reduction", 0.0)), 0.0, 0.35)
	var mitigation := minf(0.55, 1.0 - (100.0 / (100.0 + armor)) * (1.0 - equipment_dr))
	var damage := amount * (1.0 - mitigation)
	var absorbed := minf(run.shield, damage)
	run.shield -= absorbed
	var hp_loss := minf(run.hp, damage - absorbed)
	run.hp = maxf(0.0, run.hp - hp_loss)
	changed.emit()
	if run.hp <= 0.0:
		finish_run("death")
	return hp_loss

func try_spend_resource(amount: float) -> bool:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount < 0.0 or run.resource < amount:
		return false
	run.resource -= amount
	changed.emit()
	return true

func restore_resource(amount: float) -> float:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var added := minf(amount, maxf(0.0, float(run.stats.get("resource_max", 0.0)) - run.resource))
	run.resource += added
	if added > 0.0:
		changed.emit()
	return added

func add_shield(amount: float) -> float:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var added := minf(amount, maxf(0.0, run.max_hp * 0.5 - run.shield))
	run.shield += added
	changed.emit()
	return added

func finish_run(outcome: String) -> Dictionary:
	if _settling or not outcome in ProfileStore.OUTCOMES:
		return {}
	if run == null:
		return last_result
	if outcome == "extracted" and run.hp > 0.0 and not run.expedition.is_empty():
		if run.expedition.phase != "cleared" or int(run.expedition.node_index) not in [3, 6, 7]: return {}
	if run.id == str(last_result.get("run_id", "")):
		last_error = "STORAGE_DUPLICATE_RUN"
		return {}
	if _pending_outcome.is_empty():
		_pending_outcome = "death" if run.hp <= 0.0 and outcome == "extracted" else outcome
	outcome = _pending_outcome
	_settling = true
	var retained := ProfileStore.retained_gold(run.gold, outcome)
	var next_profile := profile.duplicate(true)
	var retained_equipment: Array[String] = []
	var lost_equipment: Array[String] = []
	if not run.expedition.is_empty():
		if not next_profile.has("equipment_discoveries"): next_profile.equipment_discoveries = []
		for eq: String in run.expedition.equipment_discoveries:
			if not eq in next_profile.equipment_discoveries: next_profile.equipment_discoveries.append(eq)
		for eq: String in run.expedition.pending_equipment:
			if outcome == "extracted":
				if not next_profile.equipment.has(eq):
					next_profile.equipment[eq] = {"level":0}
					retained_equipment.append(eq)
			else: lost_equipment.append(eq)
	var discoveries: Array = []
	for id: String in run.relics:
		if not id in next_profile.discoveries:
			next_profile.discoveries.append(id)
			discoveries.append(id)
	next_profile.permanent_gold = int(next_profile.permanent_gold) + retained
	next_profile.total_runs = int(next_profile.total_runs) + 1
	if outcome == "extracted":
		for id: String in run.boss_defeats:
			if not id in next_profile.bosses:
				next_profile.bosses.append(id)
	var result := {
		"run_id": run.id, "outcome": outcome, "collected": run.gold,
		"retained": retained, "lost": run.gold - retained,
		"permanent_gold": next_profile.permanent_gold,
		"discoveries": discoveries, "kills": run.kills,
		"shots": run.shots, "elapsed": run.elapsed,
		"rules_version": 1, "wallet_before": int(profile.permanent_gold),
		"wallet_after": next_profile.permanent_gold,
		"hero_id": run.hero_id, "hero_xp_gained": run.hero_xp_gained,
		"equipment_retained":retained_equipment,"equipment_lost":lost_equipment,
	}
	next_profile.last_result = result.duplicate(true)
	if not _save(next_profile, null):
		_settling = false
		changed.emit()
		settlement_failed.emit(outcome)
		return {}
	profile = next_profile
	run.relics.clear()
	run = null
	_pending_outcome = ""
	_settling = false
	changed.emit()
	run_finished.emit(result.duplicate(true))
	return result

func hero_level(id: String = "") -> int:
	var hero_id := str(profile.get("selected_hero", "CH01")) if id.is_empty() else id
	return ContentRegistry.level_for_xp(int(profile.get("hero_xp", {}).get(hero_id, 0)))

func selected_stats() -> Dictionary:
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), profile.loadout, profile.equipment)
	resolved.branches = hero_branches()
	return resolved

func hero_branches(hero_id: String = "") -> Dictionary:
	var id := str(profile.selected_hero) if hero_id.is_empty() else hero_id
	if not id in ProfileStore.HERO_IDS:
		return {}
	return profile.get("branches", {}).get(id, {"q": "", "ultimate": ""}).duplicate(true)

func set_hero_branch(slot: String, choice: String, hero_id: String = "") -> bool:
	last_error = ""
	var id := str(profile.selected_hero) if hero_id.is_empty() else hero_id
	if not _camp_available() or not id in ProfileStore.HERO_IDS or not slot in ["q", "ultimate"] \
		or not choice in ["A", "B", ""] or hero_level(id) < (18 if slot == "q" else 20):
		return false
	if hero_branches(id)[slot] == choice:
		return true
	var next_profile := profile.duplicate(true)
	next_profile.branches[id][slot] = choice
	return _commit_profile(next_profile)

func preview_stats(eq_id: String) -> Dictionary:
	var definition := ContentRegistry.equipment(eq_id)
	if definition.is_empty():
		return {}
	var loadout: Dictionary = profile.loadout.duplicate(true)
	var owned: Dictionary = profile.equipment.duplicate(true)
	loadout[definition.slot] = eq_id
	if not owned.has(eq_id):
		owned[eq_id] = {"level": 0}
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), loadout, owned)
	resolved.branches = hero_branches()
	return resolved

func preview_upgrade_stats(eq_id: String) -> Dictionary:
	var definition := ContentRegistry.equipment(eq_id)
	if definition.is_empty() or not profile.equipment.has(eq_id):
		return {}
	var loadout: Dictionary = profile.loadout.duplicate(true)
	var owned: Dictionary = profile.equipment.duplicate(true)
	loadout[definition.slot] = eq_id
	owned[eq_id].level = mini(5, equipment_level(eq_id) + 1)
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), loadout, owned)
	resolved.branches = hero_branches()
	return resolved

func select_hero(id: String) -> bool:
	last_error = ""
	if not _camp_available() or not id in ProfileStore.HERO_IDS:
		return false
	if profile.selected_hero == id:
		return true
	var next_profile := profile.duplicate(true)
	next_profile.selected_hero = id
	return _commit_profile(next_profile)

func equipment_level(eq_id: String) -> int:
	return int(profile.get("equipment", {}).get(eq_id, {}).get("level", 0))

func upgrade_cost(eq_id: String) -> int:
	if not profile.equipment.has(eq_id) or equipment_level(eq_id) >= 5:
		return 0
	return UPGRADE_PRICES[equipment_level(eq_id)]

func upgrade_has_gain(eq_id: String) -> bool:
	if not profile.equipment.has(eq_id) or equipment_level(eq_id) >= 5:
		return false
	var item := ContentRegistry.equipment(eq_id)
	var before := preview_stats(eq_id)
	if item.is_empty() or before.is_empty():
		return false
	for key: String in item.get("base_stats", {}):
		if float(item.base_stats[key]) <= 0.0:
			continue
		if key == "crit_chance":
			if float(before.crit_chance) < 0.45:
				return true
		elif key == "armor":
			if float(before.damage_reduction) < 0.55:
				return true
		elif not StatResolver.EQUIPMENT_CAPS.has(key) or float(before.equipment_contribution.get(key, 0.0)) < float(StatResolver.EQUIPMENT_CAPS[key]):
			return true
	# Rounding plateaus remain upgradeable; only fully capped contributions block spending.
	return false

func buy_equipment(eq_id: String, transaction_id: String = "") -> bool:
	last_error = ""
	if not _camp_available():
		return false
	if not transaction_id.is_empty() and profile.applied_transactions.has(transaction_id):
		return _same_transaction(transaction_id, "purchase", eq_id)
	var definition := ContentRegistry.equipment(eq_id)
	if definition.is_empty() or profile.equipment.has(eq_id):
		return false
	var boss := str(definition.get("unlock_boss", ""))
	if not boss.is_empty() and not boss in profile.bosses:
		return false
	var price: Variant = definition.get("price")
	if not ProfileStore._number(price) or int(price) > int(profile.permanent_gold):
		return false
	var id := _transaction_id(transaction_id)
	if id.is_empty():
		return false
	var next_profile := profile.duplicate(true)
	next_profile.permanent_gold = int(next_profile.permanent_gold) - int(price)
	next_profile.equipment[eq_id] = {"level": 0}
	next_profile.applied_transactions[id] = {"kind": "purchase", "item": eq_id, "price": int(price), "level": 0}
	return _commit_profile(next_profile)

func equip_item(eq_id: String) -> bool:
	last_error = ""
	if not _camp_available() or not profile.equipment.has(eq_id):
		return false
	var definition := ContentRegistry.equipment(eq_id)
	if definition.is_empty():
		return false
	if profile.loadout[definition.slot] == eq_id:
		return true
	var next_profile := profile.duplicate(true)
	next_profile.loadout[definition.slot] = eq_id
	return _commit_profile(next_profile)

func upgrade_equipment(eq_id: String, transaction_id: String = "") -> bool:
	last_error = ""
	if not _camp_available():
		return false
	if not transaction_id.is_empty() and profile.applied_transactions.has(transaction_id):
		return _same_transaction(transaction_id, "upgrade", eq_id)
	var price := upgrade_cost(eq_id)
	if price <= 0 or price > int(profile.permanent_gold) or not upgrade_has_gain(eq_id):
		return false
	var id := _transaction_id(transaction_id)
	if id.is_empty():
		return false
	var next_profile := profile.duplicate(true)
	next_profile.permanent_gold = int(next_profile.permanent_gold) - price
	next_profile.equipment[eq_id].level = equipment_level(eq_id) + 1
	next_profile.applied_transactions[id] = {"kind": "upgrade", "item": eq_id, "price": price,
		"level": next_profile.equipment[eq_id].level}
	return _commit_profile(next_profile)

func grant_hero_xp(amount: int, event_id: String) -> bool:
	# Call only for completed gameplay objectives/checkpoints. Do not award from HUD.
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or amount <= 0 \
		or amount > 3600 or event_id.is_empty() or event_id.length() > 160:
		return false
	if not run.expedition.is_empty():
		if event_id in run.completed_reward_ids: return true
		if run.staged_xp.has(event_id): return int(run.staged_xp[event_id]) == amount
		if run.staged_xp.size() >= 32: return false
		run.staged_xp[event_id] = amount
		return true
	if event_id in run.completed_reward_ids:
		return true
	if run.completed_reward_ids.size() >= 512:
		return false
	var next_profile := profile.duplicate(true)
	var before := int(next_profile.hero_xp[run.hero_id])
	next_profile.hero_xp[run.hero_id] = mini(3600, before + amount)
	var added := int(next_profile.hero_xp[run.hero_id]) - before
	var receipt := run.receipt()
	receipt.completed_reward_ids.append(event_id)
	receipt.hero_xp_gained = run.hero_xp_gained + added
	receipt.level = ContentRegistry.level_for_xp(int(next_profile.hero_xp[run.hero_id]))
	if not _save(next_profile, receipt):
		return false
	profile = next_profile
	run.completed_reward_ids.append(event_id)
	run.hero_xp_gained += added
	run.level = int(receipt.level)
	run.stats = StatResolver.resolve(run.hero_id, run.level, run.loadout_snapshot, run.equipment_snapshot)
	run.stats.branches = run.branches_snapshot.duplicate(true)
	run.max_hp = float(run.stats.max_hp)
	# Preserve absolute HP/resource and all player-owned cooldowns: leveling is not healing.
	run.hp = minf(run.hp, run.max_hp)
	run.resource = minf(run.resource, float(run.stats.resource_max))
	changed.emit()
	return true

func record_boss_defeat(boss_id: String) -> bool:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not boss_id in ProfileStore.BOSS_IDS:
		return false
	if not run.expedition.is_empty(): return false # Boss completion belongs to one atomic node commit.
	if boss_id in run.boss_defeats:
		return true
	var receipt := run.receipt()
	receipt.boss_defeats.append(boss_id)
	if not _save(profile, receipt):
		return false
	run.boss_defeats.append(boss_id)
	changed.emit()
	return true

func complete_hero_tutorial() -> bool:
	# The combat tutorial calls this after its movement + first-kill milestone.
	# Each hero has an enduring completion flag, independent of per-run room IDs.
	if not has_profile or not _pending_outcome.is_empty() or _settling or (run != null and run.hp <= 0.0):
		return false
	if run != null and not run.expedition.is_empty():
		if run.hero_id in profile.tutorial_completed: return false
		run.staged_tutorial = true
		return true
	var hero_id := run.hero_id if run != null else str(profile.selected_hero)
	if hero_id in profile.tutorial_completed:
		return false
	var next_profile := profile.duplicate(true)
	var before := int(next_profile.hero_xp[hero_id])
	next_profile.hero_xp[hero_id] = mini(3600, before + 30)
	next_profile.tutorial_completed.append(hero_id)
	var added := int(next_profile.hero_xp[hero_id]) - before
	var receipt: Variant = run.receipt() if run != null else null
	if receipt is Dictionary:
		receipt.hero_xp_gained += added
		receipt.level = ContentRegistry.level_for_xp(int(next_profile.hero_xp[hero_id]))
	if not _save(next_profile, receipt):
		return false
	profile = next_profile
	if run != null:
		run.hero_xp_gained += added
		run.level = int(receipt.level)
		run.stats = StatResolver.resolve(run.hero_id, run.level, run.loadout_snapshot, run.equipment_snapshot)
		run.stats.branches = run.branches_snapshot.duplicate(true)
		run.max_hp = float(run.stats.max_hp)
		run.hp = minf(run.hp, run.max_hp)
		run.resource = minf(run.resource, float(run.stats.resource_max))
	changed.emit()
	return true

func _camp_available() -> bool:
	return has_profile and run == null and _pending_outcome.is_empty() and not _settling \
		and (_store == null or not _store.unresolved_error)

func _expedition_active() -> bool:
	return run != null and not run.expedition.is_empty() and run.hp > 0.0 and _pending_outcome.is_empty() and not _settling

func expedition_snapshot() -> Dictionary:
	if run == null or run.expedition.is_empty(): return {}
	var value: Dictionary = run.expedition.duplicate(true)
	var index: int = int(value.node_index)
	value["node"] = value.route.nodes[index].duplicate(true)
	value["next_node"] = value.route.nodes[index + 1].duplicate(true) if index < 7 else {}
	value["selected_next_room_id"] = str(value.locked_nodes.get(str(index + 1), ""))
	if not value.selected_next_room_id.is_empty(): value.next_node.options = [value.selected_next_room_id]
	value["relic_offers"] = []
	value["supply_offers"] = []
	for offer: Dictionary in value.offers.values():
		if offer.kind == "relic" and offer.decision == "": value.relic_offers.append(offer.duplicate(true))
		elif offer.kind == "supply": value.supply_offers.append(offer.duplicate(true))
	value["gold"] = run.gold
	value["hero_id"] = run.hero_id
	value["run_id"] = run.id
	return value

func _restore_expedition(receipt: Dictionary) -> void:
	run = RunState.new()
	run.id = str(receipt.id)
	run.gold = int(receipt.gold)
	run.relics.assign(receipt.discoveries)
	run.shots = int(receipt.shots)
	run.kills = int(receipt.kills)
	run.elapsed = float(receipt.elapsed)
	run.hero_id = str(receipt.hero_id)
	run.level = int(receipt.level)
	run.hero_xp_gained = int(receipt.hero_xp_gained)
	run.completed_reward_ids.assign(receipt.completed_reward_ids)
	run.boss_defeats.assign(receipt.boss_defeats)
	run.loadout_snapshot = receipt.loadout_snapshot.duplicate(true)
	run.equipment_snapshot = receipt.equipment_snapshot.duplicate(true)
	run.branches_snapshot = receipt.branches_snapshot.duplicate(true)
	run.expedition = receipt.expedition.duplicate(true)
	var completed: Array[int] = []
	for index in run.expedition.completed_nodes: completed.append(int(index))
	run.expedition.completed_nodes = completed
	var scanned: Array[int] = []
	for index in run.expedition.scan_nodes: scanned.append(int(index))
	run.expedition.scan_nodes = scanned
	run.committed_receipt = receipt.duplicate(true)
	_refresh_expedition_stats()
	_apply_runtime_values(run.expedition.runtime)

func _refresh_expedition_stats() -> void:
	run.stats = StatResolver.resolve(run.hero_id, run.level, run.loadout_snapshot, run.equipment_snapshot)
	run.stats.branches = run.branches_snapshot.duplicate(true)
	run.stats["relic_levels"] = run.expedition.relic_levels.duplicate(true)
	run.stats["temporary_buffs"] = run.expedition.temporary_buffs.duplicate(true)
	run.max_hp = float(run.stats.max_hp)

func _apply_runtime_values(runtime: Dictionary) -> void:
	run.hp = float(runtime.hp)
	run.resource = float(runtime.resource)
	run.shield = 0.0
	for guard: Dictionary in runtime.get("status", {}).get("guards", {}).values():
		if float(guard.get("remaining", 0.0)) > 0.0: run.shield = maxf(run.shield, float(guard.get("amount", 0.0)))
	run.shield = minf(run.shield, run.max_hp * 0.5)

func _commit_expedition(value: Dictionary, runtime: Dictionary, next_profile: Dictionary, changes: Dictionary = {}, keep_live_values: bool = false) -> bool:
	var receipt: Dictionary = run.live_receipt()
	receipt.merge(changes, true)
	value.runtime = runtime.duplicate(true)
	receipt.expedition = value.duplicate(true)
	receipt.gold = int(value.gold_earned) - int(value.gold_spent)
	receipt.level = ContentRegistry.level_for_xp(int(next_profile.hero_xp[run.hero_id]))
	if not _save(next_profile, receipt): return false
	var live_values: Dictionary = {"hp":run.hp,"resource":run.resource,"shield":run.shield}
	profile = next_profile
	_restore_expedition(receipt)
	if keep_live_values:
		run.hp = float(live_values.hp)
		run.resource = float(live_values.resource)
		run.shield = float(live_values.shield)
	changed.emit()
	return true

func _safe_runtime(runtime: Dictionary) -> Dictionary:
	if runtime.is_empty():
		# Only the untouched initial entrance has an authoritative default state.
		if int(run.expedition.node_index) == 0 and run.expedition.runtime.get("mode") == "fresh_entry":
			return run.expedition.runtime.duplicate(true)
		return {}
	return runtime.duplicate(true) if Expedition.runtime_valid(runtime, run.hero_id, run.stats) else {}

func save_expedition_checkpoint(runtime_snapshot: Dictionary) -> bool:
	if not _expedition_active() or not run.expedition.phase in ["safe", "cleared"]: return false
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty(): return false
	return _commit_expedition(run.expedition.duplicate(true), runtime, profile.duplicate(true))

func choose_expedition_node(node_index: int, room_id: String) -> bool:
	if node_index < 1 or node_index > 7: return false
	if not _expedition_active() or not run.expedition.phase in ["safe", "cleared"] or node_index != int(run.expedition.node_index) + 1: return false
	var key: String = str(node_index)
	if run.expedition.locked_nodes.has(key): return run.expedition.locked_nodes[key] == room_id
	var route: Dictionary = run.expedition.route.duplicate(true)
	if node_index in Expedition.Routes.COMBAT_NODES:
		route = Expedition.Routes.choose(route, node_index, room_id)
		if not bool(route.get("valid", false)): return false
		route.erase("candidate_paths")
	elif route.nodes[node_index].room_id != room_id: return false
	var value: Dictionary = run.expedition.duplicate(true)
	value.route = route
	value.locked_nodes[key] = room_id
	# A choice transaction cannot capture incidental room mutations.
	return _commit_expedition(value, run.expedition.runtime, profile.duplicate(true), {}, true)

func advance_expedition_node(runtime_snapshot: Dictionary = {}, expected_checkpoint_id: String = "") -> bool:
	if not _expedition_active() or not run.expedition.phase in ["safe", "cleared"]: return false
	if not expected_checkpoint_id.is_empty() and expected_checkpoint_id != str(run.expedition.checkpoint_id): return false
	var previous: int = int(run.expedition.node_index)
	if previous >= 7: return false
	for offer: Dictionary in run.expedition.offers.values():
		if bool(offer.get("required", false)) and offer.decision == "": return false
	var index: int = previous + 1
	var value: Dictionary = run.expedition.duplicate(true)
	if index in Expedition.Routes.COMBAT_NODES and not value.locked_nodes.has(str(index)):
		if value.route.nodes[index].options.size() != 1: return false
		value.locked_nodes[str(index)] = value.route.nodes[index].room_id
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	if not previous in value.completed_nodes: value.completed_nodes.append(previous)
	value.node_index = index
	value.phase = "safe" if index == 4 else "combat"
	value.checkpoint_id = run.id + ":entry:" + str(index)
	value.room_entry_gold = run.gold
	value.room_entry_kills = run.kills
	value.room_entry_shots = run.shots
	if index == 4: Expedition.add_supply_offers(value, run.id)
	if index != 4 and value.temporary_buffs.has("amplify"):
		var buff: Dictionary = value.temporary_buffs.amplify
		if int(buff.get("remaining_rooms", 0)) <= 0: value.temporary_buffs.erase("amplify")
	if index != 4 and value.temporary_buffs.has("pending_supply_shield"):
		# The purchased four seconds begin in combat, never during the safe walk.
		runtime.status.guards["supply:entry:" + str(index)] = {"amount":run.max_hp * 0.15,"remaining":4.0}
		value.temporary_buffs.erase("pending_supply_shield")
	return _commit_expedition(value, runtime, profile.duplicate(true))

func _add_equipment_drop(value: Dictionary, drop_id: String, eq_id: String) -> bool:
	if drop_id.is_empty() or drop_id.length() > 160 or ContentRegistry.equipment(eq_id).is_empty(): return false
	if value.claimed_drop_ids.has(drop_id): return value.claimed_drop_ids[drop_id].equipment_id == eq_id
	if value.claimed_drop_ids.size() >= Expedition.MAX_IDS: return false
	if not eq_id in value.equipment_discoveries: value.equipment_discoveries.append(eq_id)
	if profile.equipment.has(eq_id) or value.pending_equipment.has(eq_id):
		var amount: int = int(int(ContentRegistry.equipment(eq_id).price) / 10)
		value.gold_earned += amount
		value.claimed_drop_ids[drop_id] = {"equipment_id":eq_id,"result":"gold","gold":amount}
	else:
		value.pending_equipment[eq_id] = {"drop_id":drop_id}
		value.claimed_drop_ids[drop_id] = {"equipment_id":eq_id,"result":"pending","gold":0}
	return true

func collect_expedition_equipment(drop_id: String, equipment_id: String) -> bool:
	if not _expedition_active() or run.expedition.phase != "combat": return false
	var value: Dictionary = run.expedition.duplicate(true)
	if not _add_equipment_drop(value, drop_id, equipment_id): return false
	run.expedition = value
	run.gold = int(value.gold_earned) - int(value.gold_spent)
	changed.emit()
	return true

func commit_expedition_completion(completion_id: String, runtime_snapshot: Dictionary, rewards: Dictionary = {}) -> bool:
	if not _expedition_active() or completion_id.is_empty() or completion_id.length() > 160: return false
	if run.expedition.completion_events.has(completion_id): return true
	if run.expedition.phase != "combat": return false
	var index: int = int(run.expedition.node_index)
	if index in run.expedition.completed_nodes: return false
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	for key in ["gold", "xp", "mastery"]:
		if not Expedition.number(rewards.get(key, 0), 10000 if key == "gold" else 900): return false
	var drops: Variant = rewards.get("equipment", [])
	if not drops is Array or drops.size() > 8: return false
	var value: Dictionary = run.expedition.duplicate(true)
	value.gold_earned += int(rewards.get("gold", 0))
	for drop: Variant in drops:
		if not drop is Dictionary or not _add_equipment_drop(value, str(drop.get("drop_id", "")), str(drop.get("equipment_id", ""))): return false
	var next_profile: Dictionary = profile.duplicate(true)
	var xp: int = int(rewards.get("xp", 30))
	# Existing room XP callbacks stage IDs, never create a second award when the
	# completion payload supplies the authoritative total for that same room.
	if not rewards.has("xp"):
		xp = 0
		for amount: int in run.staged_xp.values(): xp += amount
		if xp == 0: xp = 30
	var completed_rewards: Array = run.completed_reward_ids.duplicate()
	if completed_rewards.size() + run.staged_xp.size() + 1 > 512: return false
	for id: String in run.staged_xp:
		if not id in completed_rewards: completed_rewards.append(id)
	if not completion_id in completed_rewards: completed_rewards.append(completion_id)
	if run.staged_tutorial and not run.hero_id in next_profile.tutorial_completed:
		next_profile.tutorial_completed.append(run.hero_id)
		xp += 30
	var previous_xp: int = int(next_profile.hero_xp[run.hero_id])
	next_profile.hero_xp[run.hero_id] = mini(3600, previous_xp + xp)
	var added: int = int(next_profile.hero_xp[run.hero_id]) - previous_xp
	var bosses: Array = run.boss_defeats.duplicate()
	var boss: String = str(rewards.get("boss_id", ""))
	if index == 7:
		var expected: String = str(value.route.nodes[index].room_id)
		if not boss.is_empty() and boss != expected: return false
		if not expected in bosses: bosses.append(expected)
	elif not boss.is_empty(): return false
	value.completed_nodes.append(index)
	value.completion_events[completion_id] = index
	value.phase = "cleared"
	value.checkpoint_id = run.id + ":cleared:" + str(index)
	value.mastery = mini(900, int(value.mastery) + int(rewards.get("mastery", 180)))
	var rank: int = 1
	for threshold: int in Expedition.MASTERY_THRESHOLDS:
		if int(value.mastery) >= threshold: rank += 1
	rank = mini(6, rank - 1)
	for new_rank in range(int(value.mastery_rank) + 1, rank + 1): Expedition.add_relic_offer(value, run.id, new_rank)
	value.mastery_rank = rank
	if value.temporary_buffs.has("amplify"):
		value.temporary_buffs.amplify.remaining_rooms = maxi(0, int(value.temporary_buffs.amplify.remaining_rooms) - 1)
	if not next_profile.has("equipment_discoveries"): next_profile.equipment_discoveries = []
	for eq: String in value.equipment_discoveries:
		if not eq in next_profile.equipment_discoveries: next_profile.equipment_discoveries.append(eq)
	return _commit_expedition(value, runtime, next_profile, {"hero_xp_gained":run.hero_xp_gained + added,"completed_reward_ids":completed_rewards,"boss_defeats":bosses})

func choose_run_relic(offer_id: String, choice_id: String, replacement_id: String = "", runtime_snapshot: Dictionary = {}) -> bool:
	if not _expedition_active() or not run.expedition.phase in ["safe", "cleared"] or not run.expedition.offers.has(offer_id): return false
	var offer: Dictionary = run.expedition.offers[offer_id]
	if offer.kind != "relic": return false
	if offer.decision != "": return offer.decision == choice_id and str(offer.get("replacement_id", "")) == replacement_id
	if choice_id != "skip" and not choice_id in offer.candidates: return false
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty(): return false
	var value: Dictionary = run.expedition.duplicate(true)
	if choice_id == "skip": runtime.hp = minf(run.max_hp, float(runtime.hp) + run.max_hp * 0.06)
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
		if Expedition.LEGACY_RELICS.has(id): legacy.append(Expedition.LEGACY_RELICS[id])
	return _commit_expedition(value, runtime, profile.duplicate(true), {"discoveries":legacy})

func purchase_run_supply(offer_id: String, runtime_snapshot: Dictionary = {}) -> bool:
	if not _expedition_active() or int(run.expedition.node_index) != 4 or run.expedition.phase != "safe" or not run.expedition.offers.has(offer_id): return false
	var offer: Dictionary = run.expedition.offers[offer_id]
	if offer.kind != "supply": return false
	if offer.decision == "purchased": return true
	var price: int = int(offer.price)
	if run.gold < price: return false
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	var value: Dictionary = run.expedition.duplicate(true)
	var product: String = str(offer.product_id)
	match product:
		"heal_small", "heal_large":
			if float(runtime.hp) >= run.max_hp: return false
			for other: Dictionary in value.offers.values():
				if other.get("product_id", "") in ["heal_small", "heal_large"] and other.decision == "purchased": return false
			runtime.hp = minf(run.max_hp, float(runtime.hp) + run.max_hp * (0.15 if product == "heal_small" else 0.35))
		"shield":
			if value.temporary_buffs.has("pending_supply_shield"): return false
			value.temporary_buffs["pending_supply_shield"] = {"hp_ratio":0.15,"duration":4.0}
		"mana", "energy":
			if str(run.stats.resource_type) != product or float(runtime.resource) >= float(run.stats.resource_max): return false
			runtime.resource = minf(float(run.stats.resource_max), float(runtime.resource) + float(run.stats.resource_max) * (0.30 if product == "mana" else 0.20))
		"amplify":
			if value.temporary_buffs.has("amplify"): return false
			value.temporary_buffs["amplify"] = {"damage_bonus":0.08,"remaining_rooms":2}
		"scan":
			var added: bool = false
			for index in range(5, 7):
				if not index in value.scan_nodes:
					value.scan_nodes.append(index)
					added = true
			if not added: return false
		_: return false
	value.gold_spent += price
	value.offers[offer_id].decision = "purchased"
	value.purchased_offer_ids.append(offer_id)
	return _commit_expedition(value, runtime, profile.duplicate(true))

func _same_transaction(id: String, kind: String, item: String) -> bool:
	var entry: Dictionary = profile.applied_transactions[id]
	return entry.get("kind") == kind and entry.get("item") == item

func _transaction_id(requested: String) -> String:
	if requested.length() > 160 or profile.applied_transactions.size() >= ProfileStore.MAX_TRANSACTIONS:
		return ""
	return requested if not requested.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()

func _commit_profile(next_profile: Dictionary) -> bool:
	if not _save(next_profile, null):
		return false
	profile = next_profile
	changed.emit()
	return true

func set_setting(key: String, value: Variant) -> void:
	if key == "language" and not value in ["zh_CN", "en"]:
		return
	if key in ["reduced_fx", "fullscreen"] and not value is bool:
		return
	if not key in ["language", "reduced_fx", "fullscreen"]:
		return
	var next_profile := profile.duplicate(true)
	next_profile.settings[key] = value
	if _save(next_profile, run.receipt() if run != null else null, has_profile):
		profile = next_profile
		changed.emit()

func _save(next_profile: Dictionary, active_run: Variant, profile_initialized: bool = true) -> bool:
	if _store == null:
		_store = ProfileStore.new(profile_path)
	var success := _store.save_document(next_profile, active_run, profile_initialized)
	last_error = _store.last_error
	if success:
		has_profile = profile_initialized
	return success
