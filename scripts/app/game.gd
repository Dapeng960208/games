extends Node
## The UI observes this node; it never calculates damage or grants rewards.

signal changed()
signal run_started()
signal run_finished(result: Dictionary)
signal settlement_failed(outcome: String)

var profile: Dictionary = preload("res://scripts/domain/equipment/numerical_profile.gd").fresh(ProfileStore.fresh_profile())
var run: RunSession = null
var last_error: String = ""
var storage_warning: String = ""
var last_loadout_missing: Array[String] = []
var damage_trail = preload("res://scripts/presentation/combat/recent_damage_trail.gd").new()
var _session_result: Dictionary = {}
var has_profile: bool = false
var last_result: Dictionary:
	get:
		if not _demo_result.is_empty(): return _demo_result.duplicate(true)
		if not _session_result.is_empty(): return _session_result.duplicate(true)
		return profile.get("last_result", {}).duplicate(true)

# Tests use isolated paths. Production uses Godot's OS-specific user data folder.
var profile_path := "user://profile.json"
var _store: ProfileStore
var _settling := false
var _pending_outcome: String = ""
var _demo_backup: Dictionary = {}
var _demo_result: Dictionary = {}
const UPGRADE_PRICES := [60, 100, 160, 240, 340]
const Expedition = preload("res://scripts/domain/expedition/expedition_state.gd")
const Damage = preload("res://scripts/domain/combat/damage_resolver.gd")
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const FieldLearning = preload("res://scripts/domain/progression/field_learning.gd")
const RoomRewards = preload("res://scripts/domain/world/room_rewards.gd")
const FieldSnapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Loot = preload("res://scripts/domain/expedition/expedition_rewards.gd")
const Transactions = preload("res://scripts/domain/equipment/instance_transactions.gd")
var _pending_instance_transactions: Dictionary = {}
var _pending_forging_transactions: Dictionary = {}
var _kill_flush_scheduled := false
const EnemyCalibration = preload("res://scripts/domain/combat/enemy_calibration.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")

var _equipment_service = preload("res://scripts/app/services/equipment_service.gd").new(self)
var _progression_service = preload("res://scripts/app/services/progression_service.gd").new(self)
var _expedition_service = preload("res://scripts/app/services/expedition_service.gd").new(self)
var _settings_service = preload("res://scripts/app/services/settings_service.gd").new(self)

func _ready() -> void:
	if OS.has_feature("debug") and profile_path == "user://profile.json":
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--test-profile="):
				profile_path = argument.trim_prefix("--test-profile=")
	reload_profile()
	# Explicit lifecycle cleanup, never triggered by a read-only recycle-bin view.
	if _store != null and not _store.unresolved_error and not _store.cleanup_recycle_bin():
		storage_warning = _store.last_error

func _runtime_ruleset() -> int:
	return Numbers.V2

func _fresh_runtime_profile() -> Dictionary:
	var fresh := ProfileStore.fresh_profile()
	return preload("res://scripts/domain/equipment/numerical_profile.gd").fresh(fresh)

func _process(delta: float) -> void:
	if run != null and run.hp > 0.0 and _pending_outcome.is_empty():
		run.elapsed += delta

func reload_profile() -> void:
	_pending_forging_transactions.clear()
	damage_trail.clear()
	_session_result.clear()
	if not _demo_backup.is_empty():
		# Reloading during a trial discards its sandbox without writing or settling
		# the player's actual profile, including settings-only and unsaved profiles.
		_restore_demo_profile()
		run = null
		_pending_outcome = ""
		_settling = false
		_demo_result.clear()
		changed.emit()
		return
	_demo_result.clear()
	_store = ProfileStore.new(profile_path)
	var document := _store.load_document()
	last_error = _store.last_error
	storage_warning = _store.warning
	has_profile = _store.has_profile
	run = null
	_pending_outcome = ""
	if document.is_empty():
		profile = _fresh_runtime_profile()
		ProfileStore.Controls.install(profile.settings.controls)
		changed.emit()
		return
	profile = document.profile.duplicate(true)
	ProfileStore.Controls.install(profile.settings.get("controls", {}))
	if document.active_run is Dictionary:
		if document.active_run.has("expedition"):
			_restore_expedition(document.active_run)
			if storage_warning != "STORAGE_CLASS_EQUIPMENT_UPDATED": storage_warning = "STORAGE_CHECKPOINT_RECOVERED"
			changed.emit()
			return
		# M1 never resumes a room. A crash/forced quit is one abandonment settlement.
		var receipt: Dictionary = document.active_run
		run = RunSession.new()
		run.frozen_versions = _receipt_versions(receipt)
		run.enemy_calibration_snapshot = receipt.get("enemy_calibration_snapshot",{}).duplicate(true)
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
		run.pending_research_materials = receipt.get("pending_research_materials", {}).duplicate(true)
		run.hp = 0.0
		if not finish_run("abandoned").is_empty():
			storage_warning = "STORAGE_ABANDONED_RECOVERED"
	changed.emit()

func new_profile() -> bool:
	if run != null or (_store != null and _store.unresolved_error):
		return false
	var fresh := _fresh_runtime_profile()
	if fresh.is_empty(): return false
	fresh.settings = profile.get("settings", fresh.settings).duplicate(true)
	if has_profile:
		_store.cleanup_recycle_bin()
		if not _store.recycle_and_replace(fresh):
			last_error = _store.last_error
			return false
	elif not _save(fresh, null):
		return false
	last_error = ""
	profile = fresh
	_pending_forging_transactions.clear()
	_pending_instance_transactions.clear()
	_session_result.clear()
	damage_trail.clear()
	last_loadout_missing.clear()
	_demo_result.clear()
	storage_warning = ""
	has_profile = true
	changed.emit()
	return true

func recycle_entries() -> Array[Dictionary]:
	if _store == null: return []
	var entries := _store.recycle_entries()
	last_error = _store.last_error
	return entries

func delete_profile_to_recycle() -> bool:
	if run != null or not _demo_backup.is_empty() or not has_profile:
		last_error = "STORAGE_RECYCLE_BUSY"
		return false
	_store.cleanup_recycle_bin()
	var blank := _fresh_runtime_profile()
	blank.settings = profile.get("settings", blank.settings).duplicate(true)
	if not _store.recycle_and_replace(blank, false):
		last_error = _store.last_error
		return false
	reload_profile()
	return true

func restore_recycled_profile(entry_id: String) -> bool:
	if run != null or not _demo_backup.is_empty():
		last_error = "STORAGE_RECYCLE_BUSY"
		return false
	_store.cleanup_recycle_bin()
	if not _store.restore_recycled(entry_id):
		last_error = _store.last_error
		return false
	reload_profile()
	return not _store.unresolved_error

func start_run(options: Dictionary = {}) -> bool:
	if run != null or not has_profile:
		return false
	var next := RunSession.new()
	next.demo = not _demo_backup.is_empty()
	next.frozen_versions = Expedition.versions(_profile_ruleset())
	if next.ruleset_version() == Numbers.V2: next.enemy_calibration_snapshot = EnemyCalibration.current()
	next.id = Crypto.new().generate_random_bytes(16).hex_encode()
	next.hero_id = str(profile.selected_hero)
	next.level = hero_level(next.hero_id)
	next.stats = selected_stats()
	if next.stats.is_empty(): return false
	if next.demo: next.stats.starting_resource = float(next.stats.get("resource_max", 0.0))
	next.branches_snapshot = hero_branches(next.hero_id)
	next.stats.branches = next.branches_snapshot.duplicate(true)
	next.loadout_snapshot = profile.loadout.duplicate(true)
	next.equipment_snapshot = Loot.carried(next.loadout_snapshot, profile.equipment) if next.ruleset_version() == Numbers.V2 else profile.equipment.duplicate(true)
	next.max_hp = float(next.stats.get("max_hp", Balance.PLAYER_HP))
	next.hp = next.max_hp
	next.resource = float(next.stats.get("starting_resource", 0.0))
	if bool(options.get("expedition", false)):
		next.expedition = Expedition.fresh(next.id, options, profile, next.stats)
		if next.expedition.is_empty(): return false
		next.stats["relic_levels"] = next.expedition.relic_levels.duplicate(true)
		next.stats["temporary_buffs"] = next.expedition.temporary_buffs.duplicate(true)
	if not _save(profile, next.receipt()):
		return false
	if not next.expedition.is_empty(): next.committed_receipt = next.live_receipt()
	run = next
	damage_trail.clear()
	_session_result.clear()
	_demo_result.clear()
	_pending_outcome = ""
	changed.emit()
	run_started.emit()
	return true

func start_demo(hero_id: String, difficulty: int = 0, branches: Dictionary = {}, preview_branches: bool = false) -> bool:
	# A trial is a complete disposable profile so every existing reward and
	# checkpoint path can run unchanged without touching permanent progression.
	if run != null or _settling or not _pending_outcome.is_empty() or not _demo_backup.is_empty() \
		or not hero_id in ProfileStore.HERO_IDS or difficulty < 0 or difficulty > 4:
		return false
	for key: Variant in branches:
		if key not in ["q", "ultimate"] or branches[key] not in ["", "A", "B"]: return false
	_demo_backup = {"profile":profile.duplicate(true),"has_profile":has_profile,
		"last_error":last_error,"storage_warning":storage_warning}
	var trial := _fresh_runtime_profile()
	trial.settings.merge(profile.get("settings", {}), true)
	trial.selected_hero = hero_id
	trial.hero_xp[hero_id] = int(Progression.thresholds()[19 if preview_branches else 7]) if int(trial.get("ruleset_version",1)) == Numbers.V2 else ContentRegistry.XP_THRESHOLDS[19 if preview_branches else 7]
	if int(trial.get("ruleset_version",1)) == Numbers.V2:
		trial.loadout = trial.loadout_presets[hero_id].duplicate(true)
		for id: String in trial.equipment: trial.equipment[id].location = "equipped" if id in trial.loadout.values() else "inventory"
	if preview_branches:
		for key: String in ["q", "ultimate"]: trial.branches[hero_id][key] = str(branches.get(key, ""))
	profile = trial
	has_profile = true
	last_error = ""
	storage_warning = ""
	if start_run({"expedition":true,"biome_id":"B01","difficulty":difficulty,"seed":randi_range(1, 2147483647)}):
		return true
	_restore_demo_profile()
	return false

func _restore_demo_profile() -> void:
	if _demo_backup.is_empty(): return
	profile = _demo_backup.profile.duplicate(true)
	ProfileStore.Controls.install(profile.settings.get("controls", {}))
	has_profile = bool(_demo_backup.has_profile)
	last_error = str(_demo_backup.last_error)
	storage_warning = str(_demo_backup.storage_warning)
	_demo_backup.clear()

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
	return _equipment_service.equip_relic(id)

func record_kill() -> void:
	if run != null and _pending_outcome.is_empty():
		run.kills += 1
		changed.emit()

func _combat_amount(amount: float) -> Variant:
	return Numbers.amount(amount, run.ruleset_version() if run != null else Numbers.LEGACY)

func resource_cost(amount: float) -> Variant:
	if not is_finite(amount) or amount < 0.0:
		return INF
	if run != null and run.ruleset_version() == Numbers.V2 and amount > 0.0:
		return maxi(int(Numbers.scale(1.0, Numbers.V2)), Numbers.integer(amount))
	return _combat_amount(amount)

func damage_player(amount: float, context: Dictionary = {}) -> Variant:
	if run == null or run.hp <= 0.0 or _settling or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return _combat_amount(0.0)
	var defender := run.stats.duplicate(true)
	# The two stat names describe the same equipment bucket. Status reduction
	# joins it once; armor and magic resistance belong exclusively to Damage.
	defender.damage_reduction = minf(Damage.MAX_REDUCTION,
		_damage_reduction(run.stats.get("equipment_damage_reduction", run.stats.get("damage_reduction", 0.0)))
		+ _damage_reduction(context.get("damage_reduction", 0.0)))
	var attacker: Dictionary = context.get("attacker_stats", {}) if context.get("attacker_stats", {}) is Dictionary else {}
	var resolution_context: Dictionary = context.duplicate()
	resolution_context["ruleset_version"] = run.ruleset_version()
	var resolved: Dictionary = Damage.resolve(amount, str(context.get("damage_type", "physical")), attacker, defender, resolution_context)
	var damage: float = float(_combat_amount(float(resolved.damage)))
	if not is_finite(damage) or damage <= 0.0: return _combat_amount(0.0)
	var hp_before: float = run.hp
	var shield_before: float = run.shield
	var absorbed := minf(run.shield, damage)
	run.shield -= absorbed
	var hp_loss: Variant = _combat_amount(minf(run.hp, damage - absorbed))
	run.hp = maxf(0.0, run.hp - hp_loss)
	var damage_context: Dictionary = context.duplicate(true)
	damage_context["damage_type"] = str(resolved.damage_type)
	damage_trail.record(amount, damage, hp_before, run.hp, shield_before, run.shield, damage_context, run.elapsed)
	changed.emit()
	if run.hp <= 0.0:
		finish_run("death")
	return hp_loss

func _damage_reduction(value: Variant) -> float:
	if not ProfileStore._number(value, ProfileStore.MAX_NUMBER, false): return 0.0
	return clampf(float(value), 0.0, Damage.MAX_REDUCTION)

func heal_player(amount: float, multiplier: float = 1.0) -> Variant:
	if run == null or _settling or not _pending_outcome.is_empty(): return _combat_amount(0.0)
	var added: Variant = _healing_gain(run.hp, run.max_hp, amount, multiplier)
	if added > 0.0:
		run.hp += added
		changed.emit()
	return added

func _healing_gain(hp: float, maximum: float, amount: float, multiplier: float = 1.0) -> Variant:
	if not is_finite(hp) or not is_finite(maximum) or hp <= 0.0 or maximum <= 0.0 \
		or not is_finite(amount) or amount <= 0.0 or not is_finite(multiplier) or multiplier < 0.0 or multiplier > 1.0:
		return _combat_amount(0.0)
	return _combat_amount(minf(float(_combat_amount(maxf(0.0, maximum - hp))), float(_combat_amount(amount * multiplier))))

func try_spend_resource(amount: float) -> bool:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount < 0.0:
		return false
	var cost: Variant = resource_cost(amount)
	if run.resource < cost:
		return false
	run.resource -= cost
	changed.emit()
	return true

func restore_resource(amount: float) -> Variant:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return _combat_amount(0.0)
	var added: Variant = _combat_amount(minf(float(_combat_amount(amount)), maxf(0.0, float(_combat_amount(float(run.stats.get("resource_max", 0.0)))) - run.resource)))
	run.resource += added
	if added > 0.0:
		changed.emit()
	return added

func add_shield(amount: float) -> Variant:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return _combat_amount(0.0)
	var added: Variant = _combat_amount(minf(float(_combat_amount(amount)), maxf(0.0, float(_combat_amount(run.max_hp * 0.5)) - run.shield)))
	run.shield += added
	changed.emit()
	return added

func finish_run(outcome: String) -> Dictionary:
	if _settling or not outcome in ProfileStore.OUTCOMES:
		return {}
	if run == null:
		return last_result
	if outcome == "extracted" and run.hp > 0.0 and not run.expedition.is_empty():
		var current: Dictionary = run.expedition.route.nodes[int(run.expedition.node_index)]
		if run.expedition.phase != "cleared" or (not bool(current.get("early_extraction", false)) and current.role != "boss"): return {}
	if run.id == str(last_result.get("run_id", "")):
		last_error = "STORAGE_DUPLICATE_RUN"
		return {}
	if _pending_outcome.is_empty():
		_pending_outcome = "death" if run.hp <= 0.0 and outcome == "extracted" else outcome
	outcome = _pending_outcome
	if not run.staged_loot_requests.is_empty() and not flush_expedition_kill_rewards():
		settlement_failed.emit(outcome)
		return {}
	_settling = true
	var retained := ProfileStore.retained_gold(run.gold, outcome)
	var next_profile := profile.duplicate(true)
	var retained_equipment: Array[String] = []
	var lost_equipment: Array[String] = []
	# Only genuine combat defeats retain a small amount of uncommitted field
	# practice. Calculate in the detached settlement so failed saves can retry.
	var field_xp: int = FieldLearning.calculate(run, profile, outcome)
	if field_xp > 0:
		next_profile.hero_xp[run.hero_id] = int(next_profile.hero_xp[run.hero_id]) + field_xp
	if not run.expedition.is_empty():
		if not next_profile.has("equipment_discoveries"): next_profile.equipment_discoveries = []
		for eq: String in run.expedition.equipment_discoveries:
			if not eq in next_profile.equipment_discoveries: next_profile.equipment_discoveries.append(eq)
		if run.ruleset_version() == Numbers.V2:
			if outcome == "extracted": retained_equipment = Loot.bank(next_profile, run.expedition, run.boss_defeats)
			else: lost_equipment.assign(run.expedition.pending_equipment.keys())
		for eq: String in run.expedition.pending_equipment:
			if run.ruleset_version() == Numbers.V2: continue
			if outcome == "extracted":
				var drop_level: int = int(run.expedition.pending_equipment[eq].get("level", 0))
				var prior_level: int = int(next_profile.equipment.get(eq, {}).get("level", 0))
				if not next_profile.equipment.has(eq) or drop_level > prior_level:
					if next_profile.equipment.has(eq): next_profile.equipment[eq]["level"] = maxi(prior_level, drop_level)
					else: next_profile.equipment[eq] = {"level":drop_level}
					retained_equipment.append(eq)
			else: lost_equipment.append(eq)
	if run.ruleset_version() == Numbers.V2 and run.expedition.is_empty() and outcome == "extracted":
		if not next_profile.has("materials"): next_profile.materials = {}
		for key: String in run.pending_research_materials: next_profile.materials[key] = int(next_profile.materials.get(key, 0)) + int(run.pending_research_materials[key])
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
		"rules_version": ProfileStore.SETTLEMENT_RULES_VERSION, "wallet_before": int(profile.permanent_gold),
		"wallet_after": next_profile.permanent_gold,
		"hero_id": run.hero_id, "hero_xp_gained": run.hero_xp_gained + field_xp,
		"field_xp_gained": field_xp,
		"equipment_retained":retained_equipment,"equipment_lost":lost_equipment,
	}
	next_profile.last_result = result.duplicate(true)
	# Combat evidence is bounded session data, never a transaction or save field.
	if outcome == "death": result["death_review"] = damage_trail.summary()
	if run.demo:
		# Keep a readable result for the UI, but award nothing to the real profile.
		var wallet: int = int(_demo_backup.profile.permanent_gold)
		result["demo"] = true
		result["demo_xp_gained"] = run.hero_xp_gained
		result["demo_equipment"] = retained_equipment.duplicate()
		result.retained = 0
		result.lost = run.gold
		result.permanent_gold = wallet
		result.wallet_before = wallet
		result.wallet_after = wallet
		result.hero_xp_gained = 0
		result.discoveries = []
		result.equipment_retained = []
		_demo_result = result.duplicate(true)
		_restore_demo_profile()
		run.relics.clear()
		run = null
		_pending_outcome = ""
		_settling = false
		changed.emit()
		run_finished.emit(result.duplicate(true))
		return result
	if not _save(next_profile, null):
		_settling = false
		changed.emit()
		settlement_failed.emit(outcome)
		return {}
	profile = next_profile
	_session_result = result.duplicate(true)
	run.relics.clear()
	run = null
	_pending_outcome = ""
	_settling = false
	changed.emit()
	run_finished.emit(result.duplicate(true))
	return result

func hero_level(id: String = "") -> int:
	return _progression_service.hero_level(id)

func selected_stats() -> Dictionary:
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), profile.loadout, profile.equipment, _profile_ruleset(), hero_talents())
	resolved.branches = hero_branches()
	return preload("res://scripts/domain/combat/crit_policy.gd").apply_player(resolved, run.enemy_calibration_snapshot if run != null else EnemyCalibration.current())

func _run_race() -> String:
	if run != null and not run.expedition.is_empty():
		var node: Dictionary = run.expedition.route.nodes[int(run.expedition.node_index)]
		return str(node.get("biome_id", run.expedition.route.biome_id))
	return str(run.expedition.get("route", {}).get("biome_id", "B01")) if run != null else "B01"

func _profile_ruleset() -> int:
	return int(profile.get("ruleset_version", Numbers.LEGACY))

func hero_talents(hero_id: String = "") -> Dictionary:
	return _progression_service.hero_talents(hero_id)

func set_hero_talents(allocation: Dictionary, hero_id: String = "") -> bool:
	return _progression_service.set_hero_talents(allocation, hero_id)

func allocate_hero_talent(node: String) -> bool:
	return _progression_service.allocate_hero_talent(node)

func hero_branches(hero_id: String = "") -> Dictionary:
	return _progression_service.hero_branches(hero_id)

func set_hero_branch(slot: String, choice: String, hero_id: String = "") -> bool:
	return _progression_service.set_hero_branch(slot, choice, hero_id)

func equipment_definition(identifier: String, run_context: bool = false) -> Dictionary:
	return _equipment_service.equipment_definition(identifier, run_context)

func equipment_slots(run_context: bool = false) -> Array[String]:
	return _equipment_service.equipment_slots(run_context)

func _camp_instance_fits(identifier: String, hero: String) -> bool:
	return _equipment_service._camp_instance_fits(identifier, hero)

func preview_stats(eq_id: String) -> Dictionary:
	return _equipment_service.preview_stats(eq_id)

func preview_upgrade_stats(eq_id: String) -> Dictionary:
	return _equipment_service.preview_upgrade_stats(eq_id)

func hero_loadout(id: String) -> Dictionary:
	return _equipment_service.hero_loadout(id)

func select_hero(id: String) -> bool:
	return _progression_service.select_hero(id)

func equipment_level(eq_id: String) -> int:
	return _equipment_service.equipment_level(eq_id)

func _legacy_equipment_transaction() -> bool:
	return _equipment_service._legacy_equipment_transaction()

func upgrade_cost(eq_id: String) -> int:
	return _equipment_service.upgrade_cost(eq_id)

func upgrade_has_gain(eq_id: String) -> bool:
	return _equipment_service.upgrade_has_gain(eq_id)

func buy_equipment(eq_id: String, transaction_id: String = "") -> bool:
	return _equipment_service.buy_equipment(eq_id, transaction_id)

func equipment_set_quote(set_id: String) -> Dictionary:
	return _equipment_service.equipment_set_quote(set_id)

func buy_equipment_set(set_id: String, transaction_id: String = "") -> bool:
	return _equipment_service.buy_equipment_set(set_id, transaction_id)

func equip_equipment_set(set_id: String) -> bool:
	return _equipment_service.equip_equipment_set(set_id)

func equipment_sell_value(eq_id: String) -> int:
	return _equipment_service.equipment_sell_value(eq_id)

func sell_equipment_items(eq_ids: Array, transaction_id: String = "") -> bool:
	return _equipment_service.sell_equipment_items(eq_ids, transaction_id)

func equip_item(eq_id: String) -> bool:
	return _equipment_service.equip_item(eq_id)

func upgrade_equipment(eq_id: String, transaction_id: String = "") -> bool:
	return _equipment_service.upgrade_equipment(eq_id, transaction_id)

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
	var pending_materials := run.pending_research_materials.duplicate(true)
	var before := int(next_profile.hero_xp[run.hero_id])
	next_profile.hero_xp[run.hero_id] = mini(3600, before + amount)
	var added := int(next_profile.hero_xp[run.hero_id]) - before
	if run.ruleset_version() == Numbers.V2:
		var awarded := Progression.award(profile, run.hero_id, amount, event_id, _run_race(), true)
		if awarded.is_empty(): return false
		next_profile = awarded.profile
		added = int(awarded.added)
		for key: String in awarded.get("material_reward", {}): pending_materials[key] = int(pending_materials.get(key, 0)) + int(awarded.material_reward[key])
	var receipt := run.receipt()
	if run.ruleset_version() == Numbers.V2: receipt["pending_research_materials"] = pending_materials.duplicate(true)
	receipt.completed_reward_ids.append(event_id)
	receipt.hero_xp_gained = run.hero_xp_gained + added
	receipt.level = ContentRegistry.level_for_xp(int(next_profile.hero_xp[run.hero_id]), run.ruleset_version())
	if run.ruleset_version() == Numbers.V2 and receipt.has("equipment_snapshot"):
		receipt.equipment_snapshot = _sync_level_waivers(receipt.equipment_snapshot, next_profile.equipment)
	if not _save(next_profile, receipt):
		return false
	profile = next_profile
	run.completed_reward_ids.append(event_id)
	run.pending_research_materials = pending_materials
	run.hero_xp_gained += added
	run.level = int(receipt.level)
	if run.ruleset_version() == Numbers.V2: run.equipment_snapshot = _sync_level_waivers(run.equipment_snapshot, profile.equipment)
	run.stats = _resolved_live_stats()
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
	if _profile_ruleset() == Numbers.V2:
		var awarded := Progression.award(profile, hero_id, 30, "tutorial:" + hero_id, _run_race())
		if awarded.is_empty(): return false
		next_profile = awarded.profile
		next_profile.tutorial_completed.append(hero_id)
		added = int(awarded.added)
	var receipt: Variant = run.receipt() if run != null else null
	if receipt is Dictionary:
		receipt.hero_xp_gained += added
		receipt.level = ContentRegistry.level_for_xp(int(next_profile.hero_xp[hero_id]), run.ruleset_version())
	if not _save(next_profile, receipt):
		return false
	profile = next_profile
	if run != null:
		run.hero_xp_gained += added
		run.level = int(receipt.level)
		if run.ruleset_version() == Numbers.V2: run.equipment_snapshot = _sync_level_waivers(run.equipment_snapshot, profile.equipment)
		run.stats = _resolved_live_stats()
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
	value["node_count"] = value.route.nodes.size()
	value["departure_level"] = int(value.get("departure_level", value.route.get("departure_level", run.level)))
	value["next_node"] = value.route.nodes[index + 1].duplicate(true) if index + 1 < value.route.nodes.size() else {}
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
	run = RunSession.new()
	run.frozen_versions = _receipt_versions(receipt)
	run.enemy_calibration_snapshot = receipt.get("enemy_calibration_snapshot",{}).duplicate(true)
	run.demo = not _demo_backup.is_empty()
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
	run.equipment_snapshot = Loot.carried(receipt.loadout_snapshot, receipt.equipment_snapshot) if run.ruleset_version() == Numbers.V2 else receipt.equipment_snapshot.duplicate(true)
	run.branches_snapshot = receipt.branches_snapshot.duplicate(true)
	run.expedition = receipt.expedition.duplicate(true)
	if run.ruleset_version() == Numbers.V2: FieldSnapshot._integer_values(run.expedition.runtime)
	var completed: Array[int] = []
	for index in run.expedition.completed_nodes: completed.append(int(index))
	run.expedition.completed_nodes = completed
	var scanned: Array[int] = []
	for index in run.expedition.scan_nodes: scanned.append(int(index))
	run.expedition.scan_nodes = scanned
	run.committed_receipt = receipt.duplicate(true)
	_refresh_expedition_stats()
	_apply_runtime_values(run.expedition.runtime)

func _resolved_live_stats(allocation: Dictionary = {}) -> Dictionary:
	var selected := hero_talents(run.hero_id) if allocation.is_empty() else allocation
	var resolved := StatResolver.resolve(run.hero_id, run.level, run.loadout_snapshot, run.equipment_snapshot, run.ruleset_version(), selected)
	# These timed/earned overlays are not equipment. Recalculating growth must
	# never silently unequip an acquired relic rank or clear an active supply.
	for key in ["relic_levels", "temporary_buffs"]:
		if run.stats.has(key): resolved[key] = run.stats[key].duplicate(true)
	resolved.branches = run.branches_snapshot.duplicate(true)
	return resolved

func _refresh_expedition_stats() -> void:
	run.stats = _resolved_live_stats()
	if run.demo: run.stats.starting_resource = float(run.stats.get("resource_max", 0.0))
	run.stats.branches = run.branches_snapshot.duplicate(true)
	run.stats["relic_levels"] = run.expedition.relic_levels.duplicate(true)
	run.stats["temporary_buffs"] = run.expedition.temporary_buffs.duplicate(true)
	run.max_hp = float(run.stats.max_hp)

func _apply_runtime_values(runtime: Dictionary) -> void:
	run.hp = minf(float(runtime.hp), run.max_hp)
	run.resource = minf(float(runtime.resource), float(run.stats.resource_max))
	run.shield = 0.0
	for guard: Dictionary in runtime.get("status", {}).get("guards", {}).values():
		if float(guard.get("remaining", 0.0)) > 0.0: run.shield = maxf(run.shield, float(guard.get("amount", 0.0)))
	run.shield = minf(run.shield, float(Numbers.amount(run.max_hp * 0.5, run.ruleset_version())))
	run.resource_regen_remainder = float(runtime.get("resource_regen_remainder", 0.0))
	run.resource_decay_remainder = float(runtime.get("resource_decay_remainder", 0.0))

func _commit_expedition(value: Dictionary, runtime: Dictionary, next_profile: Dictionary, changes: Dictionary = {}, keep_live_values: bool = false) -> bool:
	var receipt: Dictionary = run.live_receipt()
	receipt.merge(changes, true)
	value.runtime = runtime.duplicate(true)
	receipt.expedition = value.duplicate(true)
	receipt.gold = int(value.gold_earned) - int(value.gold_spent)
	receipt.level = ContentRegistry.level_for_xp(int(next_profile.hero_xp[run.hero_id]), run.ruleset_version())
	if run.ruleset_version() == Numbers.V2 and receipt.has("equipment_snapshot"):
		receipt.equipment_snapshot = _sync_level_waivers(receipt.equipment_snapshot, next_profile.equipment)
	if not _save(next_profile, receipt): return false
	var live_values: Dictionary = {"hp":run.hp,"resource":run.resource,"shield":run.shield,"resource_regen_remainder":run.resource_regen_remainder,"resource_decay_remainder":run.resource_decay_remainder}
	profile = next_profile
	var session_opens: int = run.backpack_opens
	var session_changes: int = run.loadout_changes
	_restore_expedition(receipt)
	run.backpack_opens = session_opens
	run.loadout_changes = session_changes
	if keep_live_values:
		run.hp = float(live_values.hp)
		run.resource = float(live_values.resource)
		run.shield = float(live_values.shield)
		run.resource_regen_remainder = float(live_values.resource_regen_remainder)
		run.resource_decay_remainder = float(live_values.resource_decay_remainder)
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
	if not _expedition_active(): return false
	if node_index < 1 or node_index >= run.expedition.route.nodes.size(): return false
	if not run.expedition.phase in ["safe", "cleared"] or node_index != int(run.expedition.node_index) + 1: return false
	var key: String = str(node_index)
	if run.expedition.locked_nodes.has(key): return run.expedition.locked_nodes[key] == room_id
	var route: Dictionary = run.expedition.route.duplicate(true)
	if Expedition.Routes.is_template_node(route.nodes[node_index]):
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
	return _expedition_service.advance_expedition_node(runtime_snapshot, expected_checkpoint_id)

func _add_equipment_drop(value: Dictionary, drop_id: String, eq_id: String, drop_level: Variant = 0) -> bool:
	# Instance grants and overflow claims require S05 atomic reward records.
	if (run != null and run.ruleset_version() == Numbers.V2) or _profile_ruleset() == Numbers.V2: return false
	if drop_id.is_empty() or drop_id.length() > 160 or ContentRegistry.equipment(eq_id).is_empty(): return false
	if not Expedition.number(drop_level, Expedition.MAX_EQUIPMENT_LEVEL): return false
	var level: int = int(drop_level)
	if value.claimed_drop_ids.has(drop_id):
		var prior: Dictionary = value.claimed_drop_ids[drop_id]
		return prior.equipment_id == eq_id and int(prior.get("level", 0)) == level
	if value.claimed_drop_ids.size() >= Expedition.MAX_IDS: return false
	if not eq_id in value.equipment_discoveries: value.equipment_discoveries.append(eq_id)
	var owned_level: int = int(profile.equipment.get(eq_id, {}).get("level", 0))
	# Retain the best unsecured copy. Preserve the earlier claim/choice as
	# provenance without silently changing equipment already worn in the field.
	var has_pending: bool = value.pending_equipment.has(eq_id)
	var pending_level: int = int(value.pending_equipment.get(eq_id, {}).get("level", 0))
	if has_pending and level > pending_level:
		var previous: String = str(value.pending_equipment[eq_id].drop_id)
		value.claimed_drop_ids[previous].result = "superseded"
		value.pending_equipment[eq_id] = {"drop_id":drop_id}
		value.claimed_drop_ids[drop_id] = {"equipment_id":eq_id,"result":"pending","gold":0}
	elif has_pending or (profile.equipment.has(eq_id) and level <= owned_level):
		var amount: int = int(int(ContentRegistry.equipment(eq_id).price) / 10)
		value.gold_earned += amount
		value.claimed_drop_ids[drop_id] = {"equipment_id":eq_id,"result":"gold","gold":amount,"economy_version":ProfileStore.ECONOMY_RULES_VERSION}
	else:
		value.pending_equipment[eq_id] = {"drop_id":drop_id}
		value.claimed_drop_ids[drop_id] = {"equipment_id":eq_id,"result":"pending","gold":0}
	# Missing levels in earlier receipts mean +0. Keep their published shape.
	if level > 0:
		value.claimed_drop_ids[drop_id]["level"] = level
		if value.claimed_drop_ids[drop_id].result == "pending": value.pending_equipment[eq_id]["level"] = level
	return true

func collect_expedition_equipment(drop_id: String, equipment_id: String, drop_level: Variant = 0) -> bool:
	if not _expedition_active() or run.expedition.phase != "combat": return false
	var value: Dictionary = run.expedition.duplicate(true)
	if not _add_equipment_drop(value, drop_id, equipment_id, drop_level): return false
	run.expedition = value
	run.gold = int(value.gold_earned) - int(value.gold_spent)
	changed.emit()
	return true

func _field_equipment_drop(drop_id: String) -> Dictionary:
	if run != null and run.ruleset_version() == Numbers.V2:
		if not _expedition_active() or run.expedition.phase != "cleared": return {}
		var claim: Variant = run.expedition.claimed_drop_ids.get(drop_id)
		var item: Variant = run.expedition.pending_equipment.get(drop_id)
		if not claim is Dictionary or not item is Dictionary or claim.get("equipment_id") != drop_id: return {}
		var definition := ContentRegistry.equipment(str(item.template_id), 2)
		if definition.is_empty(): return {}
		var current: String = str(run.loadout_snapshot.get(definition.slot, ""))
		return {"drop_id":drop_id,"equipment_id":drop_id,"level":int(item.enhancement_rank),"item_level":int(item.item_level),"slot":str(definition.slot),"current_id":current,"current_level":int(run.equipment_snapshot.get(current, {}).get("enhancement_rank", 0)),"decision":str(claim.get("field_decision", ""))}
	if not _expedition_active() or run.expedition.phase != "cleared": return {}
	var claim: Variant = run.expedition.claimed_drop_ids.get(drop_id)
	if not claim is Dictionary or claim.get("result") != "pending": return {}
	var id: String = str(claim.get("equipment_id", ""))
	var pending: Variant = run.expedition.pending_equipment.get(id)
	var item: Dictionary = ContentRegistry.equipment(id)
	if item.is_empty() or not pending is Dictionary or pending.get("drop_id") != drop_id: return {}
	var level: int = int(pending.get("level", 0))
	if profile.equipment.has(id) and level <= int(profile.equipment[id].level): return {}
	var current_id: String = str(run.loadout_snapshot.get(item.slot, ""))
	return {"drop_id":drop_id,"equipment_id":id,"level":level,"slot":str(item.slot),"current_id":current_id,"current_level":int(run.equipment_snapshot.get(current_id, {}).get("level", 0)),"decision":str(claim.get("field_decision", ""))}

func pending_field_equipment() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _expedition_active() or run.expedition.phase != "cleared": return result
	for id: String in run.expedition.pending_equipment:
		var drop: Dictionary = _field_equipment_drop(id if run.ruleset_version() == Numbers.V2 else str(run.expedition.pending_equipment[id].drop_id))
		if not drop.is_empty() and drop.decision.is_empty(): result.append(drop)
	return result

func preview_field_equipment(drop_id: String) -> Dictionary:
	return _equipment_service.preview_field_equipment(drop_id)

func choose_field_equipment(drop_id: String, decision: String, runtime_snapshot: Dictionary, expected_checkpoint_id: String) -> bool:
	last_error = ""
	if not _expedition_active() or run.expedition.phase != "cleared" or not decision in ["equip", "keep"]: return false
	if expected_checkpoint_id != str(run.expedition.checkpoint_id): return false
	var drop: Dictionary = _field_equipment_drop(drop_id)
	if drop.is_empty(): return false
	if not drop.decision.is_empty(): return drop.decision == decision
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	var value: Dictionary = run.expedition.duplicate(true)
	value.claimed_drop_ids[drop_id]["field_decision"] = decision
	var changes: Dictionary = {}
	if decision == "equip":
		var preview: Dictionary = preview_field_equipment(drop_id)
		if preview.is_empty(): return false
		var next_loadout: Dictionary = run.loadout_snapshot.duplicate(true)
		var next_equipment: Dictionary = run.equipment_snapshot.duplicate(true)
		next_loadout[drop.slot] = drop.equipment_id
		next_equipment[drop.equipment_id] = run.expedition.pending_equipment[drop.equipment_id].duplicate(true) if run.ruleset_version() == Numbers.V2 else {"level":int(drop.level)}
		if run.ruleset_version() == Numbers.V2: next_equipment = Loot.carried(next_loadout, next_equipment)
		last_error = FieldSnapshot.loadout_source_error(runtime, run.loadout_snapshot, next_loadout)
		if not last_error.is_empty(): return false
		runtime = FieldSnapshot.for_loadout(runtime, run.loadout_snapshot, next_loadout, preview.next_stats, run.hero_id, run.stats)
		if runtime.is_empty() or not Expedition.runtime_valid(runtime, run.hero_id, preview.next_stats): return false
		changes = {"loadout_snapshot":next_loadout,"equipment_snapshot":next_equipment}
	# The decision, adjusted actor state and temporary loadout are one receipt.
	# Pending loot stays unsecured; only the existing extraction settlement owns it.
	return _commit_expedition(value, runtime, profile.duplicate(true), changes)

func claim_expedition_optional_reward(node_index: int, objective_id: String, runtime_snapshot: Dictionary, expected_checkpoint_id: String) -> bool:
	if not _expedition_active() or run.expedition.phase != "cleared": return false
	if node_index != int(run.expedition.node_index) or expected_checkpoint_id != str(run.expedition.checkpoint_id): return false
	var room_id: String = str(run.expedition.route.nodes[node_index].room_id)
	if RoomRewards.optional_definition(room_id, objective_id).is_empty(): return false
	var claim_id: String = run.id + ":node:" + str(node_index) + ":optional:" + objective_id
	var claims: Dictionary = run.expedition.get("optional_claims", {})
	if claims.has(claim_id): return true
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	var bosses: Array = profile.bosses.duplicate()
	for boss: String in run.boss_defeats:
		if not bosses.has(boss): bosses.append(boss)
	var seed: int = (int(run.expedition.seed) + node_index * 104729) & 0x7fffffff
	var rewards: Dictionary = RoomRewards.optional(room_id, objective_id, run.hero_id, seed, claim_id, reward_discovery_ids(), run.expedition.pending_equipment.keys(), bosses, int(run.expedition.difficulty), int(run.expedition.get("reward_policy_version", 0)))
	if rewards.is_empty(): return false
	var value: Dictionary = run.expedition.duplicate(true)
	if run.ruleset_version() == Numbers.V2:
		_ensure_loot_state(value)
		if not Loot.add(value, run.id, run.hero_id, claim_id, "chest"): return false
		value.gold_earned += int(rewards.gold)
		value.loot_events[claim_id].gold = int(rewards.gold)
		var instances: Array = []
		for item: Dictionary in value.loot_events[claim_id].result.items: instances.append(item.instance_id)
		value.optional_claims[claim_id] = {"reward_version":2,"node_index":node_index,"room_id":room_id,"objective_id":objective_id,"gold":int(rewards.gold),"event_id":claim_id,"instance_ids":instances}
		return _commit_expedition(value, runtime, profile.duplicate(true), {}, true)
	var drop_ids: Array[String] = []
	value.gold_earned += int(rewards.gold)
	for drop: Dictionary in rewards.equipment:
		if not _add_equipment_drop(value, str(drop.drop_id), str(drop.equipment_id), drop.get("drop_level", 0)): return false
		drop_ids.append(str(drop.drop_id))
	if not value.has("optional_claims"): value["optional_claims"] = {}
	value.optional_claims[claim_id] = {"reward_version":2,"node_index":node_index,"room_id":room_id,"objective_id":objective_id,"gold":int(rewards.gold),"drop_ids":drop_ids}
	var next_profile: Dictionary = profile.duplicate(true)
	if not next_profile.has("equipment_discoveries"): next_profile.equipment_discoveries = []
	for eq: String in value.equipment_discoveries:
		if not next_profile.equipment_discoveries.has(eq): next_profile.equipment_discoveries.append(eq)
	# Claim identity and the full reward commit together. Do not consume the
	# visible cache before this succeeds, or storage errors would eat its loot.
	return _commit_expedition(value, runtime, next_profile, {}, true)

func commit_expedition_completion(completion_id: String, runtime_snapshot: Dictionary, rewards: Dictionary = {}) -> bool:
	return _expedition_service.commit_expedition_completion(completion_id, runtime_snapshot, rewards)

func choose_run_relic(offer_id: String, choice_id: String, replacement_id: String = "", runtime_snapshot: Dictionary = {}) -> bool:
	return _expedition_service.choose_run_relic(offer_id, choice_id, replacement_id, runtime_snapshot)

func purchase_run_supply(offer_id: String, runtime_snapshot: Dictionary = {}) -> bool:
	return _expedition_service.purchase_run_supply(offer_id, runtime_snapshot)

func prepare_safe_resources(runtime_snapshot: Dictionary = {}, expected_checkpoint_id: String = "") -> bool:
	return _expedition_service.prepare_safe_resources(runtime_snapshot, expected_checkpoint_id)

func reward_discovery_ids() -> Array:
	if run == null: return []
	if int(run.expedition.get("reward_policy_version", 0)) == 0: return run.equipment_snapshot.keys()
	var known: Array = profile.get("equipment_discoveries", []).duplicate()
	for id: String in profile.equipment:
		if not known.has(id): known.append(id)
	for record: Dictionary in profile.applied_transactions.values():
		var ids: Array = []
		if record.get("kind") in ["purchase", "upgrade"]: ids.append(str(record.item))
		elif record.get("kind") == "purchase_set": ids = record.items.duplicate()
		elif record.get("kind") == "sale": ids = record.items.keys()
		for id: String in ids:
			if not known.has(id): known.append(id)
	for id: String in run.expedition.get("equipment_discoveries", []):
		if not known.has(id): known.append(id)
	return known

func _same_transaction(id: String, kind: String, item: String) -> bool:
	var entry: Dictionary = profile.applied_transactions[id]
	return entry.get("kind") == kind and entry.get("item") == item

func _transaction_id(requested: String) -> String:
	if profile.applied_transactions.size() >= ProfileStore.MAX_TRANSACTIONS:
		last_error = "STORAGE_TRANSACTION_CAPACITY"
		return ""
	if requested.length() > 160: return ""
	return requested if not requested.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()

func storage_capacity() -> Dictionary:
	if _store == null: return {}
	return _store.storage_capacity(profile, run.receipt() if run != null else null, has_profile)

func _commit_profile(next_profile: Dictionary) -> bool:
	# Normalize location in the same detached transaction as the active loadout.
	# Pending rewards stay pending; a loadout referencing them still fails validation.
	next_profile = next_profile.duplicate(true)
	if next_profile.get("ruleset_version", Numbers.LEGACY) == Numbers.V2:
		next_profile.equipment = Progression.expire_level_waivers(next_profile.equipment, next_profile.hero_xp)
		var equipped: Array = next_profile.get("loadout", {}).values()
		for id: Variant in next_profile.get("equipment", {}):
			var record: Variant = next_profile.equipment[id]
			if record is Dictionary and record.get("location") in ["inventory", "equipped"]:
				record.location = "equipped" if id in equipped else "inventory"
	if not next_profile.has("loadout_presets"): next_profile.loadout_presets = {}
	next_profile.loadout_presets[str(next_profile.selected_hero)] = next_profile.loadout.duplicate(true)
	if not _save(next_profile, null):
		return false
	profile = next_profile.duplicate(true)
	changed.emit()
	return true

func set_setting(key: String, value: Variant) -> void:
	_settings_service.set_setting(key, value)

func set_control_binding(action: String, binding: Dictionary) -> bool:
	return _settings_service.set_control_binding(action, binding)

func _save(next_profile: Dictionary, active_run: Variant, profile_initialized: bool = true) -> bool:
	if not _demo_backup.is_empty():
		# This gate also covers audio/settings changes and checkpoint callbacks.
		last_error = ""
		return true
	if _store == null:
		_store = ProfileStore.new(profile_path)
	var success := _store.save_document(next_profile, active_run, profile_initialized)
	last_error = _store.last_error
	if success:
		has_profile = profile_initialized
	return success

func _receipt_versions(receipt: Dictionary) -> Dictionary:
	# Missing stamps identify legacy saves, even when production later enables V2.
	var versions: Dictionary = Expedition.versions(int(receipt.get("ruleset_version", 1)))
	for key: String in Expedition.VERSION_FIELDS:
		if receipt.has(key): versions[key] = receipt[key]
		elif receipt.get("expedition", {}).has(key): versions[key] = receipt.expedition[key]
	if not receipt.has("reward_policy_version") and not receipt.get("expedition", {}).has("reward_policy_version"):
		versions.reward_policy_version = 0
	return versions

func _sync_level_waivers(snapshot: Dictionary, equipment: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	for id: Variant in result:
		var item: Variant = result[id]
		var owned: Variant = equipment.get(id)
		if not item is Dictionary or item.get("location") == "pending" or not owned is Dictionary: continue
		if item.get("instance_id") != owned.get("instance_id") or item.get("template_id") != owned.get("template_id"): continue
		if owned.get("legacy_equip_waiver") is Dictionary:
			item["legacy_equip_waiver"] = owned.legacy_equip_waiver.duplicate(true)
	return result

func _ensure_loot_state(value: Dictionary) -> void:
	_expedition_service._ensure_loot_state(value)

func record_expedition_kill_reward(spawn_id: String, enemy_id: String, elite: bool = false, summoned: bool = false, zone_index: int = 0) -> bool:
	return _expedition_service.record_expedition_kill_reward(spawn_id, enemy_id, elite, summoned, zone_index)

func queue_expedition_kill_reward(spawn_id: String, enemy_id: String, elite: bool = false, summoned: bool = false, zone_index: int = 0) -> bool:
	return _expedition_service.queue_expedition_kill_reward(spawn_id, enemy_id, elite, summoned, zone_index)

func _stage_expedition_kill(spawn_id: String, enemy_id: String, elite: bool, summoned: bool, zone_index: int) -> bool:
	return _expedition_service._stage_expedition_kill(spawn_id, enemy_id, elite, summoned, zone_index)

func flush_expedition_kill_rewards() -> bool:
	return _expedition_service.flush_expedition_kill_rewards()

func _instance_request(spec: Dictionary) -> Dictionary:
	return _equipment_service._instance_request(spec)

func quote_equipment_v2(spec: Dictionary) -> Dictionary:
	return _equipment_service.quote_equipment_v2(spec)

func quote_craft_equipment_v2(spec: Dictionary) -> Dictionary:
	return _equipment_service.quote_craft_equipment_v2(spec)

func quote_equipment_set_v2(spec: Dictionary) -> Dictionary:
	return _equipment_service.quote_equipment_set_v2(spec)

func purchase_equipment_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return _equipment_service.purchase_equipment_v2(spec, transaction_id)

func craft_equipment_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return _equipment_service.craft_equipment_v2(spec, transaction_id)

func purchase_equipment_set_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return _equipment_service.purchase_equipment_set_v2(spec, transaction_id)

func _instance_operation(kind: String, spec: Dictionary, transaction_id: String) -> Dictionary:
	return _equipment_service._instance_operation(kind, spec, transaction_id)

func claim_pending_equipment(instance_id: String, transaction_id: String = "") -> bool:
	return _equipment_service.claim_pending_equipment(instance_id, transaction_id)

func _default_set_request(set_id: String) -> Dictionary:
	return _equipment_service._default_set_request(set_id)

func _equip_instance_set(set_id: String) -> bool:
	return _equipment_service._equip_instance_set(set_id)

func _forging_service() -> Script:
	return _equipment_service._forging_service()

func _forging_request(kind: String, spec: Dictionary, frozen: Dictionary = {}) -> Dictionary:
	return _equipment_service._forging_request(kind, spec, frozen)

func _forging_items(kind: String, request: Dictionary) -> Dictionary:
	return _equipment_service._forging_items(kind, request)

func quote_forging_v2(kind: String, spec: Dictionary) -> Dictionary:
	return _equipment_service.quote_forging_v2(kind, spec)

func forge_equipment_v2(kind: String, spec: Dictionary, transaction_id: String) -> Dictionary:
	return _equipment_service.forge_equipment_v2(kind, spec, transaction_id)

func pending_forging_v2() -> Dictionary:
	return _equipment_service.pending_forging_v2()

func cancel_pending_forging_v2(operation_id: String) -> bool:
	return _equipment_service.cancel_pending_forging_v2(operation_id)

func resolve_reforge_v2(instance_id: String, choice: String, transaction_id: String) -> Dictionary:
	return _equipment_service.resolve_reforge_v2(instance_id, choice, transaction_id)

func set_equipment_lock_v2(instance_id: String, locked: bool) -> bool:
	return _equipment_service.set_equipment_lock_v2(instance_id, locked)
