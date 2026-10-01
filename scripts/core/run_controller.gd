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
var last_loadout_missing: Array[String] = []
var damage_trail = preload("res://scripts/combat/recent_damage_trail.gd").new()
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
const Expedition = preload("res://scripts/core/expedition_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Progression = preload("res://scripts/core/hero_progression.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const FieldLearning = preload("res://scripts/core/field_learning.gd")
const RoomRewards = preload("res://scripts/world/room_rewards.gd")
const FieldSnapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Loot = preload("res://scripts/core/expedition_rewards.gd")
const Transactions = preload("res://scripts/core/instance_transactions.gd")
var _test_ruleset_override: int = 0
var _pending_instance_transactions: Dictionary = {}
var _pending_forging_transactions: Dictionary = {}
const Instances = preload("res://scripts/core/equipment_instances.gd")

func _ready() -> void:
	if OS.has_feature("debug") and profile_path == "user://profile.json":
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--test-profile="):
				profile_path = argument.trim_prefix("--test-profile=")
		# Explicit isolated historical tests can pin their original default. A
		# normal user profile never accepts this debug-only numerical override.
		if _isolated_test_path(profile_path):
			for argument: String in OS.get_cmdline_user_args():
				if argument in ["--test-ruleset=1", "--test-ruleset=2"]:
					_test_ruleset_override = int(argument.get_slice("=",1))
	reload_profile()

func _isolated_test_path(value: String) -> bool:
	if value == "user://profile.json" or value.is_empty(): return false
	var normalized := value.replace("\\", "/")
	for component: String in normalized.split("/"):
		if component.begins_with("test_") and component.length() > 5: return true
	return false

func _runtime_ruleset() -> int:
	return _test_ruleset_override if _test_ruleset_override in [1,2] else Numbers.default_ruleset()

func _fresh_runtime_profile() -> Dictionary:
	var fresh := ProfileStore.fresh_profile()
	return preload("res://scripts/core/numerical_profile.gd").fresh(fresh) if _runtime_ruleset() == Numbers.V2 else fresh

func _migrate_camp_if_enabled() -> bool:
	if _runtime_ruleset() != Numbers.V2 or _profile_ruleset() == Numbers.V2 or not has_profile or run != null: return true
	return migrate_numerical_at_camp()

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
		profile = ProfileStore.fresh_profile()
		ProfileStore.Controls.install(profile.settings.controls)
		changed.emit()
		return
	profile = document.profile.duplicate(true)
	ProfileStore.Controls.install(profile.settings.get("controls", {}))
	if document.active_run is Dictionary:
		if document.active_run.has("expedition"):
			_restore_expedition(document.active_run)
			storage_warning = "STORAGE_CHECKPOINT_RECOVERED"
			changed.emit()
			return
		# M1 never resumes a room. A crash/forced quit is one abandonment settlement.
		var receipt: Dictionary = document.active_run
		run = RunState.new()
		run.frozen_versions = _receipt_versions(receipt)
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
	_migrate_camp_if_enabled()
	changed.emit()

func new_profile() -> bool:
	if run != null or (_store != null and _store.unresolved_error):
		return false
	var fresh := _fresh_runtime_profile()
	if fresh.is_empty(): return false
	fresh.settings = profile.get("settings", fresh.settings).duplicate(true)
	if not _save(fresh, null):
		return false
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

func start_run(options: Dictionary = {}) -> bool:
	if run != null or not has_profile:
		return false
	if not _migrate_camp_if_enabled(): return false
	var next := RunState.new()
	next.demo = not _demo_backup.is_empty()
	next.frozen_versions = Expedition.versions(_profile_ruleset())
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
	_migrate_camp_if_enabled()
	changed.emit()
	run_finished.emit(result.duplicate(true))
	return result

func hero_level(id: String = "") -> int:
	var hero_id := str(profile.get("selected_hero", "CH01")) if id.is_empty() else id
	return ContentRegistry.level_for_xp(int(profile.get("hero_xp", {}).get(hero_id, 0)), _profile_ruleset())

func selected_stats() -> Dictionary:
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), profile.loadout, profile.equipment, _profile_ruleset(), hero_talents())
	resolved.branches = hero_branches()
	return resolved

func _run_race() -> String:
	if run != null and not run.expedition.is_empty():
		var node: Dictionary = run.expedition.route.nodes[int(run.expedition.node_index)]
		return str(node.get("biome_id", run.expedition.route.biome_id))
	return str(run.expedition.get("route", {}).get("biome_id", "B01")) if run != null else "B01"

func _profile_ruleset() -> int:
	return int(profile.get("ruleset_version", Numbers.LEGACY))

func hero_talents(hero_id: String = "") -> Dictionary:
	var id := str(profile.get("selected_hero", "CH01")) if hero_id.is_empty() else hero_id
	return profile.get("talents", {}).get(id, {}).duplicate(true)

func set_hero_talents(allocation: Dictionary, hero_id: String = "") -> bool:
	var id := str(profile.get("selected_hero", "CH01")) if hero_id.is_empty() else hero_id
	if _profile_ruleset() != Numbers.V2 or not _camp_available() or id not in ProfileStore.HERO_IDS or not Progression.valid_talents(allocation, hero_level(id)): return false
	if hero_talents(id) == allocation: return true
	var next := profile.duplicate(true)
	if not next.has("talents"): next["talents"] = {}
	next.talents[id] = allocation.duplicate(true)
	return _commit_profile(next)

func allocate_hero_talent(node: String) -> bool:
	if _profile_ruleset() != Numbers.V2 or node not in Progression.TALENTS: return false
	var id := run.hero_id if run != null else str(profile.selected_hero)
	var allocation := hero_talents(id)
	allocation[node] = int(allocation.get(node, 0)) + 1
	if not Progression.valid_talents(allocation, hero_level(id)): return false
	if run == null: return set_hero_talents(allocation, id)
	if run.ruleset_version() != Numbers.V2 or not get_tree().paused or run.hp <= 0 or run.demo or _settling or not _pending_outcome.is_empty(): return false
	var next := profile.duplicate(true)
	if not next.has("talents"): next["talents"] = {}
	next.talents[id] = allocation
	if not _save(next, run.receipt()): return false
	profile = next
	run.stats = _resolved_live_stats(allocation)
	run.stats.branches = run.branches_snapshot.duplicate(true)
	run.max_hp = run.stats.max_hp
	run.hp = minf(run.hp, run.max_hp)
	run.resource = minf(run.resource, float(run.stats.resource_max))
	changed.emit()
	return true

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

## UI identity bridge: catalog IDs remain template IDs for icon/trait lookup.
## Every returned record is detached from both the saved profile and the catalog.
func equipment_definition(identifier: String, run_context: bool = false) -> Dictionary:
	var in_run: bool = run_context and run != null
	var ruleset: int = run.ruleset_version() if in_run else _profile_ruleset()
	var owned: Dictionary = run.equipment_snapshot.duplicate(true) if in_run else profile.get("equipment", {})
	if in_run and ruleset == Numbers.V2:
		for id: String in profile.get("equipment", {}):
			if not owned.has(id): owned[id] = profile.equipment[id].duplicate(true)
		for id: String in run.expedition.get("pending_equipment", {}):
			if not owned.has(id): owned[id] = run.expedition.pending_equipment[id].duplicate(true)
	if ruleset != Numbers.V2 or not owned.has(identifier):
		return ContentRegistry.equipment(identifier, ruleset)
	var record: Variant = owned[identifier]
	if not record is Dictionary or record.get("instance_id") != identifier or not Instances.validate(record).is_empty(): return {}
	var definition: Dictionary = ContentRegistry.equipment(str(record.template_id), ruleset)
	if definition.is_empty(): return {}
	definition["instance_id"] = identifier
	definition["instance_record"] = record.duplicate(true)
	definition["instance_stats"] = Instances.stats(record)
	return definition

func equipment_slots(run_context: bool = false) -> Array[String]:
	return ContentRegistry.slots(run.ruleset_version() if run_context and run != null else _profile_ruleset())

func _camp_instance_fits(identifier: String, hero: String) -> bool:
	var record: Variant = profile.get("equipment", {}).get(identifier)
	if not record is Dictionary or record.get("instance_id") != identifier: return false
	# Pending rewards are owned but are not in the usable camp inventory yet.
	if record.get("location") not in ["inventory", "equipped"]: return false
	return Instances.can_equip(record, hero, hero_level(hero))

func preview_stats(eq_id: String) -> Dictionary:
	var definition := equipment_definition(eq_id)
	if definition.is_empty(): return {}
	if _profile_ruleset() == Numbers.V2 and not _camp_instance_fits(eq_id, str(profile.selected_hero)): return {}
	var loadout: Dictionary = profile.loadout.duplicate(true)
	var owned: Dictionary = profile.equipment.duplicate(true)
	loadout[definition.slot] = eq_id
	if not owned.has(eq_id): owned[eq_id] = {"level": 0}
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), loadout, owned, _profile_ruleset(), hero_talents())
	if resolved.is_empty(): return {}
	resolved.branches = hero_branches()
	return resolved

func preview_upgrade_stats(eq_id: String) -> Dictionary:
	# S06 must preview a committed roll vector, never fabricate a legacy +1.
	if _profile_ruleset() == Numbers.V2: return {}
	var definition := equipment_definition(eq_id)
	if definition.is_empty() or not profile.equipment.has(eq_id): return {}
	var loadout: Dictionary = profile.loadout.duplicate(true)
	var owned: Dictionary = profile.equipment.duplicate(true)
	loadout[definition.slot] = eq_id
	owned[eq_id].level = mini(5, equipment_level(eq_id) + 1)
	var resolved := StatResolver.resolve(str(profile.selected_hero), hero_level(), loadout, owned, _profile_ruleset(), hero_talents())
	resolved.branches = hero_branches()
	return resolved

func hero_loadout(id: String) -> Dictionary:
	var desired: Dictionary = profile.get("loadout_presets", {}).get(id, profile.loadout).duplicate(true)
	for slot: String in equipment_slots():
		var item: String = str(desired.get(slot, ""))
		if _profile_ruleset() == Numbers.V2:
			if not item.is_empty() and not _camp_instance_fits(item, id): desired[slot] = ""
		elif item.is_empty() or not profile.equipment.has(item): desired[slot] = str(profile.loadout[slot])
	return desired

func select_hero(id: String) -> bool:
	last_error = ""
	last_loadout_missing.clear()
	if not _camp_available() or not id in ProfileStore.HERO_IDS: return false
	if profile.selected_hero == id: return true
	var next_profile := profile.duplicate(true)
	if not next_profile.has("loadout_presets"): next_profile.loadout_presets = {}
	next_profile.loadout_presets[str(profile.selected_hero)] = profile.loadout.duplicate(true)
	var desired: Dictionary = next_profile.loadout_presets.get(id, profile.loadout).duplicate(true)
	var missing: Array[String] = []
	for slot: String in equipment_slots():
		var item: String = str(desired.get(slot, ""))
		if _profile_ruleset() == Numbers.V2:
			# Empty is a real choice; a different class never receives a rerolled
			# copy or silently wears an incompatible instance from the last hero.
			if not item.is_empty() and not _camp_instance_fits(item, id):
				missing.append(slot)
				desired[slot] = ""
		elif item.is_empty() or not next_profile.equipment.has(item):
			missing.append(slot)
			desired[slot] = str(profile.loadout[slot])
	next_profile.selected_hero = id
	next_profile.loadout = desired
	if not _commit_profile(next_profile): return false
	last_loadout_missing = missing
	return true

func equipment_level(eq_id: String) -> int:
	var field: String = "enhancement_rank" if _profile_ruleset() == Numbers.V2 else "level"
	return int(profile.get("equipment", {}).get(eq_id, {}).get(field, 0))

func _legacy_equipment_transaction() -> bool:
	if _profile_ruleset() != Numbers.V2: return true
	last_error = "NUMERICAL_TRANSACTION_UNAVAILABLE"
	return false

func upgrade_cost(eq_id: String) -> int:
	if _profile_ruleset() == Numbers.V2:
		var quote := quote_forging_v2("enhance", {"instance_id":eq_id})
		return int(quote.get("gold", 0)) if bool(quote.get("ok", false)) else 0
	if not profile.equipment.has(eq_id) or equipment_level(eq_id) >= 5:
		return 0
	return UPGRADE_PRICES[equipment_level(eq_id)]

func upgrade_has_gain(eq_id: String) -> bool:
	if _profile_ruleset() == Numbers.V2: return bool(quote_forging_v2("enhance", {"instance_id":eq_id}).get("ok", false))
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
	last_error = ""
	if _profile_ruleset() == Numbers.V2:
		return bool(purchase_equipment_v2({"template_id":eq_id,"rarity":"white","power_type":"magic" if profile.selected_hero == "CH03" else "physical","item_level":hero_level()}, transaction_id).get("ok", false))
	if not _legacy_equipment_transaction(): return false
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
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION, "kind": "purchase", "item": eq_id, "price": int(price), "level": 0}
	return _commit_profile(next_profile)

## Quotes only missing pieces. Rounding is per item, so buying a piece first
## cannot change the discount on any other piece or reset its refinement.
func equipment_set_quote(set_id: String) -> Dictionary:
	if _profile_ruleset() == Numbers.V2:
		var request := _default_set_request(set_id)
		var ids: Array = ContentRegistry.set_item_ids(set_id, 2)
		if ids.size() != 8: return {}
		var quote := quote_equipment_set_v2(request) if not request.template_ids.is_empty() else {"ok":true,"gold":0}
		return {"items":ids,"missing":request.template_ids.duplicate(),"owned":8 - request.template_ids.size(),"price":int(quote.get("gold", 0)),"full_price":int(quote.get("gold", 0)),"locked_boss":"" if quote.get("ok", false) else str(quote.get("error", "")),"request":request}
	var ids := ContentRegistry.set_item_ids(set_id)
	if ids.size() != ContentRegistry.SLOTS.size(): return {}
	var missing: Array[String] = []
	var owned_count := 0
	var full_price := 0
	var price := 0
	var locked_boss := ""
	for eq_id: String in ids:
		var item := ContentRegistry.equipment(eq_id)
		if profile.equipment.has(eq_id):
			owned_count += 1
			continue
		missing.append(eq_id)
		full_price += int(item.price)
		price += int(item.price) * 9 / 10
		var boss := str(item.get("unlock_boss", ""))
		if not boss.is_empty() and not boss in profile.bosses: locked_boss = boss
	return {"items":ids, "missing":missing, "owned":owned_count, "price":price,
		"full_price":full_price, "locked_boss":locked_boss}

func buy_equipment_set(set_id: String, transaction_id: String = "") -> bool:
	last_error = ""
	if _profile_ruleset() == Numbers.V2:
		var request := _default_set_request(set_id)
		var saved: Dictionary = profile.get("instance_transactions", {}).get("operations", {}).get(transaction_id, {})
		if not saved.is_empty():
			if saved.get("kind") != "complete_set" or saved.get("request", {}).get("set_id") != set_id: return false
			request = saved.request.duplicate(true)
		return bool(purchase_equipment_set_v2(request, transaction_id).get("ok", false))
	if not _legacy_equipment_transaction(): return false
	if not _camp_available(): return false
	if not transaction_id.is_empty() and profile.applied_transactions.has(transaction_id):
		return _same_transaction(transaction_id, "purchase_set", set_id)
	var quote := equipment_set_quote(set_id)
	if quote.is_empty() or quote.missing.is_empty() or not str(quote.locked_boss).is_empty() \
		or int(quote.price) > int(profile.permanent_gold): return false
	var id := _transaction_id(transaction_id)
	if id.is_empty(): return false
	var next_profile := profile.duplicate(true)
	next_profile.permanent_gold = int(next_profile.permanent_gold) - int(quote.price)
	for eq_id: String in quote.missing: next_profile.equipment[eq_id] = {"level":0}
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION,"kind":"purchase_set", "item":set_id,
		"price":int(quote.price), "items":quote.missing.duplicate()}
	return _commit_profile(next_profile)

func equip_equipment_set(set_id: String) -> bool:
	last_error = ""
	if _profile_ruleset() == Numbers.V2: return _equip_instance_set(set_id)
	if not _legacy_equipment_transaction(): return false
	if not _camp_available(): return false
	var ids := ContentRegistry.set_item_ids(set_id)
	if ids.size() != ContentRegistry.SLOTS.size(): return false
	for eq_id: String in ids:
		if not profile.equipment.has(eq_id): return false
	var next_profile := profile.duplicate(true)
	for eq_id: String in ids:
		next_profile.loadout[ContentRegistry.equipment(eq_id).slot] = eq_id
	if next_profile.loadout == profile.loadout: return true
	return _commit_profile(next_profile)

func equipment_sell_value(eq_id: String) -> int:
	if _profile_ruleset() == Numbers.V2:
		var quote := quote_forging_v2("sell", {"instance_id":eq_id})
		return int(quote.get("gold_return", 0)) if bool(quote.get("ok", false)) else 0
	if not profile.equipment.has(eq_id): return 0
	return ProfileStore.equipment_sell_price(eq_id,equipment_level(eq_id))

func sell_equipment_items(eq_ids: Array, transaction_id: String = "") -> bool:
	last_error = ""
	if _profile_ruleset() == Numbers.V2:
		if eq_ids.size() != 1 or not eq_ids[0] is String: return false
		return bool(forge_equipment_v2("sell", {"instance_id":eq_ids[0]}, transaction_id).get("ok", false))
	if not _legacy_equipment_transaction(): return false
	if not _camp_available() or eq_ids.is_empty() or eq_ids.size() > ContentRegistry.equipment_ids().size(): return false
	var ids: Array[String] = []
	for value: Variant in eq_ids:
		if not value is String or ids.has(value) or ContentRegistry.equipment(value).is_empty(): return false
		ids.append(value)
	ids.sort()
	var signature := ",".join(ids)
	if not transaction_id.is_empty() and profile.applied_transactions.has(transaction_id):
		return _same_transaction(transaction_id,"sale",signature)
	var total := 0
	var records := {}
	for eq_id: String in ids:
		if not profile.equipment.has(eq_id) or eq_id in profile.loadout.values(): return false
		var price := equipment_sell_value(eq_id)
		if price <= 0: return false
		total += price
		records[eq_id] = {"level":equipment_level(eq_id),"price":price}
	if not ProfileStore._number(int(profile.permanent_gold)+total): return false
	var id := _transaction_id(transaction_id)
	if id.is_empty(): return false
	var next_profile := profile.duplicate(true)
	for eq_id: String in ids:
		next_profile.equipment.erase(eq_id)
		for preset: Dictionary in next_profile.get("loadout_presets", {}).values():
			for slot: String in preset:
				if preset[slot] == eq_id: preset[slot] = ""
	next_profile.permanent_gold = int(next_profile.permanent_gold) + total
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION,"kind":"sale","item":signature,"items":records,"price":total}
	return _commit_profile(next_profile)

func equip_item(eq_id: String) -> bool:
	last_error = ""
	if not _camp_available() or not profile.equipment.has(eq_id):
		return false
	if _profile_ruleset() == Numbers.V2 and not _camp_instance_fits(eq_id, str(profile.selected_hero)): return false
	var definition := equipment_definition(eq_id)
	if definition.is_empty():
		return false
	if profile.loadout[definition.slot] == eq_id:
		return true
	var next_profile := profile.duplicate(true)
	next_profile.loadout[definition.slot] = eq_id
	return _commit_profile(next_profile)

func upgrade_equipment(eq_id: String, transaction_id: String = "") -> bool:
	last_error = ""
	if _profile_ruleset() == Numbers.V2: return bool(forge_equipment_v2("enhance", {"instance_id":eq_id}, transaction_id).get("ok", false))
	if not _legacy_equipment_transaction(): return false
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
	next_profile.applied_transactions[id] = {"economy_version":ProfileStore.ECONOMY_RULES_VERSION,"kind": "upgrade", "item": eq_id, "price": price,
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
	run = RunState.new()
	run.frozen_versions = _receipt_versions(receipt)
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
	if not _expedition_active() or not run.expedition.phase in ["safe", "cleared"]: return false
	if not expected_checkpoint_id.is_empty() and expected_checkpoint_id != str(run.expedition.checkpoint_id): return false
	var previous: int = int(run.expedition.node_index)
	if previous + 1 >= run.expedition.route.nodes.size(): return false
	for offer: Dictionary in run.expedition.offers.values():
		if bool(offer.get("required", false)) and offer.decision == "": return false
	var index: int = previous + 1
	var value: Dictionary = run.expedition.duplicate(true)
	if Expedition.Routes.is_template_node(value.route.nodes[index]) and not value.locked_nodes.has(str(index)):
		if value.route.nodes[index].options.size() != 1: return false
		value.locked_nodes[str(index)] = value.route.nodes[index].room_id
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	if not previous in value.completed_nodes: value.completed_nodes.append(previous)
	value.node_index = index
	var role: String = str(value.route.nodes[index].role)
	value.phase = "safe" if role == "supply" else "combat"
	value.checkpoint_id = run.id + ":entry:" + str(index)
	value.room_entry_gold = run.gold
	value.room_entry_kills = run.kills
	value.room_entry_shots = run.shots
	if role == "supply": Expedition.add_supply_offers(value, run.id)
	if role != "supply" and value.temporary_buffs.has("amplify"):
		var buff: Dictionary = value.temporary_buffs.amplify
		if int(buff.get("remaining_rooms", 0)) <= 0: value.temporary_buffs.erase("amplify")
	# Bought protection belongs to one combat room, including an unused reserve.
	# Checkpoint saves preserve it; only a committed room transition removes it.
	for source: String in runtime.status.guards.keys():
		if source.begins_with("supply:"): runtime.status.guards.erase(source)
	if role != "supply" and value.temporary_buffs.has("pending_supply_shield"):
		# Start the four-second countdown on actual absorption, not room entry.
		runtime.status.guards["supply:ready:" + str(index)] = {"amount":Numbers.amount(run.max_hp * 0.15, run.ruleset_version()),"remaining":4.0}
		value.temporary_buffs.erase("pending_supply_shield")
	return _commit_expedition(value, runtime, profile.duplicate(true))

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
	var drop: Dictionary = _field_equipment_drop(drop_id)
	if drop.is_empty(): return {}
	var next_loadout: Dictionary = run.loadout_snapshot.duplicate(true)
	var next_equipment: Dictionary = run.equipment_snapshot.duplicate(true)
	next_loadout[drop.slot] = drop.equipment_id
	next_equipment[drop.equipment_id] = run.expedition.pending_equipment[drop.equipment_id].duplicate(true) if run.ruleset_version() == Numbers.V2 else {"level":int(drop.level)}
	if run.ruleset_version() == Numbers.V2:
		if not Instances.can_equip(next_equipment[drop.equipment_id], run.hero_id, run.level): return {}
		next_equipment = Loot.carried(next_loadout, next_equipment)
	var next_stats: Dictionary = StatResolver.resolve(run.hero_id, run.level, next_loadout, next_equipment, run.ruleset_version(), hero_talents(run.hero_id))
	if next_stats.is_empty(): return {}
	next_stats["branches"] = run.branches_snapshot.duplicate(true)
	next_stats["relic_levels"] = run.expedition.relic_levels.duplicate(true)
	next_stats["temporary_buffs"] = run.expedition.temporary_buffs.duplicate(true)
	drop["current_stats"] = run.stats.duplicate(true)
	drop["next_stats"] = next_stats
	return drop

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
	if not _expedition_active() or completion_id.is_empty() or completion_id.length() > 160: return false
	if run.expedition.completion_events.has(completion_id): return true
	if run.expedition.phase != "combat": return false
	var index: int = int(run.expedition.node_index)
	if run.ruleset_version() == Numbers.V2:
		if completion_id != run.id + ":node:" + str(index) + ":complete": return false
		var expected := RoomRewards.v2_completion(str(run.expedition.route.nodes[index].room_id), int(run.expedition.difficulty), str(rewards.get("quality", "full")))
		if expected.is_empty() or (not rewards.is_empty() and rewards != expected): return false
		rewards = expected
	if index in run.expedition.completed_nodes: return false
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	for key in ["gold", "xp", "mastery"]:
		if not Expedition.number(rewards.get(key, 0), 10000 if key == "gold" else 900): return false
	var drops: Variant = rewards.get("equipment", [])
	if not drops is Array or drops.size() > 8: return false
	var value: Dictionary = run.expedition.duplicate(true)
	value.gold_earned += int(rewards.get("gold", 0))
	if run.ruleset_version() == Numbers.V2:
		_ensure_loot_state(value)
		for request: Dictionary in run.staged_loot_requests.values():
			if not Loot.add(value, run.id, run.hero_id, request.event_id, request.source, int(request.zone_index), str(request.actor_id)): return false
		if not Loot.add(value, run.id, run.hero_id, completion_id, str(rewards.source)): return false
		value.loot_events[completion_id]["quality"] = str(rewards.quality)
		value.loot_events[completion_id].gold = int(rewards.gold)
	for drop: Variant in drops:
		if not drop is Dictionary or not _add_equipment_drop(value, str(drop.get("drop_id", "")), str(drop.get("equipment_id", "")), drop.get("drop_level", 0)): return false
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
		if run.ruleset_version() == Numbers.V2: value.loot_events[completion_id]["tutorial_xp"] = 30
	var previous_xp: int = int(next_profile.hero_xp[run.hero_id])
	next_profile.hero_xp[run.hero_id] = mini(3600, previous_xp + xp)
	var added: int = int(next_profile.hero_xp[run.hero_id]) - previous_xp
	if run.ruleset_version() == Numbers.V2:
		var award_input := next_profile.duplicate(true)
		award_input.hero_xp[run.hero_id] = previous_xp
		var awarded := Progression.award(award_input, run.hero_id, xp, completion_id, _run_race(), true)
		if awarded.is_empty(): return false
		next_profile = awarded.profile
		added = int(awarded.added)
		Loot.defer_research(value, completion_id, awarded.get("material_reward", {}))
	var bosses: Array = run.boss_defeats.duplicate()
	var boss: String = str(rewards.get("boss_id", ""))
	if value.route.nodes[index].role == "boss":
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
	# These safe-boundary heals use the same bounded calculation as combat heals,
	# but must stay in the proposed snapshot until its transaction commits.
	if choice_id == "skip": runtime.hp = _combat_amount(float(runtime.hp) + float(_healing_gain(float(runtime.hp), run.max_hp, run.max_hp * 0.06)))
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
	if not _expedition_active() or run.expedition.phase != "safe" or not run.expedition.offers.has(offer_id): return false
	if run.expedition.route.nodes[int(run.expedition.node_index)].role != "supply": return false
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
			runtime.hp = _combat_amount(float(runtime.hp) + float(_healing_gain(float(runtime.hp), run.max_hp, run.max_hp * (0.15 if product == "heal_small" else 0.35))))
		"shield":
			if value.temporary_buffs.has("pending_supply_shield"): return false
			value.temporary_buffs["pending_supply_shield"] = {"hp_ratio":0.15,"duration":4.0}
		"mana", "energy":
			if str(run.stats.resource_type) != product or float(runtime.resource) >= float(run.stats.resource_max): return false
			runtime.resource = _combat_amount(minf(float(run.stats.resource_max), float(runtime.resource) + float(_combat_amount(float(run.stats.resource_max) * (0.30 if product == "mana" else 0.20)))))
		"amplify":
			if value.temporary_buffs.has("amplify"): return false
			value.temporary_buffs["amplify"] = {"damage_bonus":0.08,"remaining_rooms":2}
		"scan":
			var added: bool = false
			for index: int in Expedition.Routes.scan_indices(value.route):
				if not index in value.scan_nodes:
					value.scan_nodes.append(index)
					added = true
			if not added: return false
		_: return false
	value.gold_spent += price
	value.offers[offer_id].decision = "purchased"
	value.purchased_offer_ids.append(offer_id)
	return _commit_expedition(value, runtime, profile.duplicate(true))

func prepare_safe_resources(runtime_snapshot: Dictionary = {}, expected_checkpoint_id: String = "") -> bool:
	# Resource recovery is a combat pacing rule, not a paid safe-room delay.
	if not _expedition_active() or run.expedition.phase != "safe": return false
	if run.expedition.route.nodes[int(run.expedition.node_index)].role != "supply": return false
	if not expected_checkpoint_id.is_empty() and expected_checkpoint_id != str(run.expedition.checkpoint_id): return false
	if str(run.stats.resource_type) not in ["mana", "energy"]: return false
	var runtime: Dictionary = _safe_runtime(runtime_snapshot)
	if runtime.is_empty() or runtime.get("mode") != "safe_boundary": return false
	if float(runtime.resource) >= float(run.stats.resource_max): return true
	runtime.resource = _combat_amount(float(run.stats.resource_max))
	return _commit_expedition(run.expedition.duplicate(true), runtime, profile.duplicate(true))

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
	if key == "language" and not value in ["zh_CN", "en"]:
		return
	if key in ["reduced_fx", "fullscreen", "camera_shake", "auto_attack", "enemy_skill_paths"] and not value is bool:
		return
	if key in ProfileStore.VOLUME_DEFAULTS and not ProfileStore._number(value, 1.0, false):
		return
	if key == "controls" and not ProfileStore.Controls.valid_overrides(value):
		return
	if not key in ["language", "reduced_fx", "fullscreen", "camera_shake", "auto_attack", "enemy_skill_paths", "controls"] and not key in ProfileStore.VOLUME_DEFAULTS:
		return
	var next_profile := profile.duplicate(true)
	next_profile.settings[key] = value
	if _save(next_profile, run.receipt() if run != null else null, has_profile):
		profile = next_profile
		if key == "controls": ProfileStore.Controls.install(profile.settings.controls)
		changed.emit()

func set_control_binding(action: String, binding: Dictionary) -> bool:
	if action not in ProfileStore.Controls.EDITABLE_ACTIONS or not ProfileStore.Controls.valid_binding(binding): return false
	var controls: Dictionary = profile.get("settings", {}).get("controls", {}).duplicate(true)
	if not ProfileStore.Controls.conflict(action, binding, controls).is_empty(): return false
	controls[action] = binding.duplicate(true)
	set_setting("controls", controls)
	return last_error.is_empty() and profile.settings.get("controls", {}).get(action, {}) == binding

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

## Atomic camp conversion used by the current production default.
## Saves the detached migration in one whole-document transaction at camp only.
func migrate_numerical_at_camp(event_id: String = "migration:numerical_v2") -> bool:
	if not _camp_available() or not has_profile or not _demo_backup.is_empty(): return false
	var migration: Script = load("res://scripts/core/numerical_migration.gd")
	var next: Dictionary = migration.migrate_profile(profile, event_id, null)
	if next.is_empty(): return false
	if next == profile: return true
	return _commit_profile(next)

## Expiry changes eligibility metadata only; pending/future instances and all
## combat rolls stay frozen. Caller writes this with the XP/profile transaction.
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
	if not value.has("loot_events"):
		Loot.initialize(value, {"gold_pity":{}}, run.id)

## Natural actor IDs come from a deterministic zone/wave/spawn position. The
## commit retains the entry runtime, never a partially fought room snapshot.
func record_expedition_kill_reward(spawn_id: String, enemy_id: String, elite: bool = false, summoned: bool = false, zone_index: int = 0) -> bool:
	if not _expedition_active() or run.ruleset_version() != Numbers.V2 or run.expedition.phase != "combat": return false
	if summoned: return true
	if spawn_id.is_empty() or spawn_id.length() > 80 or Expedition.Catalog.enemy(enemy_id).is_empty() or zone_index < 0 or zone_index > 2: return false
	var id := run.id + ":node:" + str(int(run.expedition.node_index)) + ":kill:" + spawn_id
	var source := "elite" if elite else "normal"
	var value := run.expedition.duplicate(true)
	_ensure_loot_state(value)
	if value.loot_events.has(id): return value.loot_events[id].result.context.source == source and int(value.loot_events[id].zone_index) == zone_index and value.loot_events[id].get("actor_id", "") == enemy_id
	run.staged_loot_requests[id] = {"event_id":id,"source":source,"zone_index":zone_index,"actor_id":enemy_id}
	for request: Dictionary in run.staged_loot_requests.values():
		if not Loot.add(value, run.id, run.hero_id, request.event_id, request.source, int(request.zone_index), str(request.actor_id)): return false
	var receipt := run.receipt()
	for key: String in ["loot_seed","wish_slot","pity_snapshot","loot_events","pending_materials","pending_equipment","claimed_drop_ids","equipment_discoveries","optional_claims"]:
		receipt.expedition[key] = value[key].duplicate(true) if value[key] is Dictionary or value[key] is Array else value[key]
	# Field decisions can reference a live loadout that is intentionally not in
	# the entry snapshot. The items remain pending and safe to recover there.
	if not _save(profile, receipt): return false
	run.expedition = value
	run.committed_receipt = receipt.duplicate(true)
	run.staged_loot_requests.clear()
	changed.emit()
	return true

func _instance_request(spec: Dictionary) -> Dictionary:
	var request := spec.duplicate(true)
	if not request.has("hero_id"): request.hero_id = str(profile.selected_hero)
	return request

func quote_equipment_v2(spec: Dictionary) -> Dictionary:
	return Transactions.quote_purchase(profile, _instance_request(spec)) if _profile_ruleset() == Numbers.V2 else {"ok":false,"error":"ruleset"}

func quote_craft_equipment_v2(spec: Dictionary) -> Dictionary:
	return Transactions.quote_craft(profile, _instance_request(spec)) if _profile_ruleset() == Numbers.V2 else {"ok":false,"error":"ruleset"}

func quote_equipment_set_v2(spec: Dictionary) -> Dictionary:
	return Transactions.quote_set(profile, _instance_request(spec)) if _profile_ruleset() == Numbers.V2 else {"ok":false,"error":"ruleset"}

func purchase_equipment_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return _instance_operation("purchase", spec, transaction_id)

func craft_equipment_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return _instance_operation("craft", spec, transaction_id)

func purchase_equipment_set_v2(spec: Dictionary, transaction_id: String) -> Dictionary:
	return _instance_operation("set", spec, transaction_id)

func _instance_operation(kind: String, spec: Dictionary, transaction_id: String) -> Dictionary:
	if _profile_ruleset() != Numbers.V2 or not _camp_available(): return {"ok":false,"error":"camp_required"}
	var id := transaction_id
	if id.is_empty(): id = Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length() > 160: return {"ok":false,"error":"invalid_operation_id"}
	var request := _instance_request(spec)
	if _pending_instance_transactions.has(id):
		var pending: Dictionary = _pending_instance_transactions[id]
		if pending.kind != kind or not Loot.same(pending.request, request): return {"ok":false,"error":"transaction_context_changed"}
	var result: Dictionary
	match kind:
		"purchase": result = Transactions.purchase(profile, id, request)
		"craft": result = Transactions.craft(profile, id, request)
		"set": result = Transactions.complete_set(profile, id, request)
		_: return {"ok":false,"error":"invalid_kind"}
	if not bool(result.get("ok", false)): return result
	_pending_instance_transactions[id] = {"kind":kind,"request":request,"receipt":result.receipt.duplicate(true)}
	if not bool(result.get("replayed", false)) and not _commit_profile(result.profile): return {"ok":false,"error":last_error,"operation_id":id}
	_pending_instance_transactions.erase(id)
	return {"ok":true,"error":"","receipt":result.receipt.duplicate(true),"replayed":bool(result.get("replayed", false))}

func claim_pending_equipment(instance_id: String, transaction_id: String = "") -> bool:
	if _profile_ruleset() != Numbers.V2 or not _camp_available(): return false
	var id := transaction_id if not transaction_id.is_empty() else "claim:" + instance_id
	if id.length() > 160 or not profile.equipment.has(instance_id): return false
	var receipts: Dictionary = profile.get("pending_claim_receipts", {})
	if receipts.has(id): return receipts[id] == instance_id
	if profile.equipment[instance_id].location != "pending": return false
	var capacity := int(profile.get("inventory_capacity", 0))
	if capacity > 0 and Loot.inventory_count(profile) >= capacity:
		last_error = "INVENTORY_CAPACITY"
		return false
	var next := profile.duplicate(true)
	next.equipment[instance_id].location = "inventory"
	if not next.has("pending_claim_receipts"): next.pending_claim_receipts = {}
	next.pending_claim_receipts[id] = instance_id
	return _commit_profile(next)

func _default_set_request(set_id: String) -> Dictionary:
	var power := "magic" if profile.selected_hero == "CH03" else "physical"
	var missing: Array = []
	for template: String in ContentRegistry.set_item_ids(set_id, 2):
		var owned := false
		for item: Dictionary in profile.equipment.values():
			if item.template_id == template and item.power_type == power: owned = true
		if not owned: missing.append(template)
	return {"hero_id":str(profile.selected_hero),"set_id":set_id,"template_ids":missing,"rarity":"white","power_type":power,"item_level":hero_level()}

func _equip_instance_set(set_id: String) -> bool:
	if not _camp_available(): return false
	var templates: Array = ContentRegistry.set_item_ids(set_id, 2)
	if templates.size() != 8: return false
	var ids: Array = profile.equipment.keys()
	ids.sort()
	var next := profile.duplicate(true)
	for template: String in templates:
		var selected := ""
		for id: String in ids:
			var item: Dictionary = profile.equipment[id]
			if item.template_id == template and item.location != "pending" and Instances.can_equip(item, str(profile.selected_hero), hero_level()):
				selected = id
				break
		if selected.is_empty(): return false
		next.loadout[ContentRegistry.equipment(template, 2).slot] = selected
	return _commit_profile(next)

## V2 camp forging is a detached service transaction. UI previews never roll;
## the receipt is returned only after the candidate profile is durably saved.
func _forging_service() -> Script:
	return load("res://scripts/core/instance_forging.gd")

func _forging_request(kind: String, spec: Dictionary, frozen: Dictionary = {}) -> Dictionary:
	var request := _instance_request(spec)
	var keys: Dictionary = {"source_revision":"source_instance_id","target_revision":"target_instance_id"} if kind == "inherit" else {"expected_revision":"instance_id"}
	for key: String in keys:
		if request.has(key): continue
		if frozen.has(key): request[key] = frozen[key]
		else:
			var item: Dictionary = profile.get("equipment", {}).get(str(request.get(keys[key], "")), {})
			request[key] = int(item.get("forge_revision", 0))
	return request

func _forging_items(kind: String, request: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = ["source_instance_id", "target_instance_id"] if kind == "inherit" else ["instance_id"]
	for key: String in keys:
		var id := str(request.get(key, ""))
		if profile.equipment.has(id): result[id] = profile.equipment[id].duplicate(true)
	return result

func quote_forging_v2(kind: String, spec: Dictionary) -> Dictionary:
	if _profile_ruleset() != Numbers.V2 or not _camp_available(): return {"ok":false,"error":"camp_required"}
	return _forging_service().quote(profile, kind, _forging_request(kind, spec))

func forge_equipment_v2(kind: String, spec: Dictionary, transaction_id: String) -> Dictionary:
	if _profile_ruleset() != Numbers.V2 or not _camp_available(): return {"ok":false,"error":"camp_required"}
	var id := transaction_id
	if id.is_empty(): id = "forge:" + Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length() > 160: return {"ok":false,"error":"INVALID_OPERATION_ID"}
	var frozen: Dictionary = profile.get("forging_transactions", {}).get("operations", {}).get(id, {}).get("request", {})
	if _pending_forging_transactions.has(id): frozen = _pending_forging_transactions[id].request
	elif not _pending_forging_transactions.is_empty(): return {"ok":false,"error":"PENDING_FORGE_RETRY"}
	var request := _forging_request(kind, spec, frozen)
	if _pending_forging_transactions.has(id):
		var previous: Dictionary = _pending_forging_transactions[id]
		if previous.kind != kind or not Loot.same(previous.request, request) or not Loot.same(previous.expected_items, _forging_items(kind, request)): return {"ok":false,"error":"OPERATION_CONFLICT"}
	var result: Dictionary = _forging_service().transact(profile, id, kind, request)
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", ""))
		return result
	if bool(result.get("replayed", false)):
		_pending_forging_transactions.erase(id)
		return {"ok":true,"error":"","receipt":result.receipt.duplicate(true),"replayed":true}
	_pending_forging_transactions[id] = {"operation_id":id,"kind":kind,"request":request.duplicate(true),"expected_items":_forging_items(kind, request)}
	if not _commit_profile(result.profile): return {"ok":false,"error":last_error,"operation_id":id}
	_pending_forging_transactions.erase(id)
	return {"ok":true,"error":"","receipt":result.receipt.duplicate(true),"replayed":false}

func pending_forging_v2() -> Dictionary:
	if _pending_forging_transactions.is_empty(): return {}
	return _pending_forging_transactions.values()[0].duplicate(true)

func cancel_pending_forging_v2(operation_id: String) -> bool:
	if not _camp_available() or not _pending_forging_transactions.has(operation_id): return false
	if profile.get("forging_transactions", {}).get("operations", {}).has(operation_id): return false
	_pending_forging_transactions.erase(operation_id)
	return true

func resolve_reforge_v2(instance_id: String, choice: String, transaction_id: String) -> Dictionary:
	var item: Dictionary = profile.get("equipment", {}).get(instance_id, {})
	return forge_equipment_v2("resolve_reforge", {"instance_id":instance_id,"pending_operation_id":str(item.get("pending_reforge", {}).get("operation_id", "")),"choice":choice}, transaction_id)

func set_equipment_lock_v2(instance_id: String, locked: bool) -> bool:
	if _profile_ruleset() != Numbers.V2 or not _camp_available() or not profile.equipment.has(instance_id): return false
	var item: Dictionary = profile.equipment[instance_id]
	if not item.get("pending_reforge", {}).is_empty() or not _pending_forging_transactions.is_empty():
		last_error = "PENDING_FORGE_RETRY"
		return false
	if bool(item.lock_state) == locked: return true
	var next := profile.duplicate(true)
	next.equipment[instance_id].lock_state = locked
	next.equipment[instance_id]["forge_revision"] = int(item.get("forge_revision", 0)) + 1
	return _commit_profile(next)
