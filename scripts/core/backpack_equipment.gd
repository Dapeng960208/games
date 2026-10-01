extends RefCounted
## Owned equipment only. Combat changes remain live until the normal clear
## checkpoint; safe-room changes use the existing atomic expedition receipt.
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Expedition = preload("res://scripts/core/expedition_state.gd")
const Rules = preload("res://scripts/combat/equipment_effects.gd")
const Status = preload("res://scripts/combat/combat_status.gd")

static func available(game: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if game.run == null: return result
	var version: int = game.run.ruleset_version()
	var records: Dictionary = game.run.equipment_snapshot.duplicate(true)
	for id: String in game.profile.get("equipment", {}):
		if not records.has(id): records[id] = game.profile.equipment[id].duplicate(true)
	for id: String in game.run.expedition.get("pending_equipment", {}):
		var pending: Dictionary = game.run.expedition.pending_equipment[id]
		if version == 2:
			if not records.has(id): records[id] = pending.duplicate(true)
			continue
		if int(pending.get("level", 0)) >= int(records.get(id, {}).get("level", 0)):
			records[id] = {"level":int(pending.get("level", 0)),"pending":true}
	var ids: Array = records.keys()
	ids.sort()
	for id: String in ids:
		var item: Dictionary = Registry.equipment(str(records[id].get("template_id", id)) if records[id] is Dictionary else id, version)
		if item.is_empty() or not records[id] is Dictionary: continue
		result.append({"id":id,"slot":str(item.slot),"record":records[id].duplicate(true),"level":int(records[id].get("enhancement_rank", records[id].get("level", 0))),"pending":bool(records[id].get("pending", false)) or str(records[id].get("location", "")) == "pending","equipped":str(game.run.loadout_snapshot.get(item.slot, "")) == id})
	return result

static func preview(game: Node, id: String, slot: String = "") -> Dictionary:
	if game.run == null or game.run.expedition.is_empty(): return {}
	var record: Dictionary = {}
	if not id.is_empty():
		for candidate: Dictionary in available(game):
			if candidate.id == id: record = candidate; break
		if record.is_empty(): return {}
		if not slot.is_empty() and slot != str(record.slot): return {}
		slot = str(record.slot)
	if not slot in Registry.slots(game.run.ruleset_version()): return {}
	var loadout: Dictionary = game.run.loadout_snapshot.duplicate(true)
	var owned: Dictionary = game.run.equipment_snapshot.duplicate(true)
	loadout[slot] = id
	if not id.is_empty():
		owned[id] = record.record.duplicate(true) if game.run.ruleset_version() == 2 else {"level":int(record.level)}
		if game.run.ruleset_version() == 2 and not Instances.can_equip(owned[id], game.run.hero_id, game.run.level): return {}
	var stats: Dictionary = Resolver.resolve(game.run.hero_id, game.run.level, loadout, owned, game.run.ruleset_version(), game.hero_talents(game.run.hero_id))
	if stats.is_empty(): return {}
	for key: String in ["branches", "relic_levels", "temporary_buffs"]:
		stats[key] = game.run.stats.get(key, {}).duplicate(true)
	return {"equipment_id":id,"slot":slot,"level":int(record.get("level", 0)),"pending":bool(record.get("pending", false)),"current_id":str(game.run.loadout_snapshot.get(slot, "")),"current_stats":game.run.stats.duplicate(true),"next_stats":stats,"loadout":loadout,"owned":owned}

static func change(game: Node, id: String, slot: String, runtime: Dictionary, checkpoint: String) -> Dictionary:
	if game.run == null or game.run.hp <= 0.0 or game.run.expedition.is_empty(): return {"success":false,"error":"当前没有可调整的远征配装。"}
	if checkpoint != str(game.run.expedition.checkpoint_id): return {"success":false,"error":"房间已变化，请重新打开背包。"}
	var comparison := preview(game, id, slot)
	if comparison.is_empty(): return {"success":false,"error":"只能穿戴背包中已拥有的装备。"}
	var changed_loadout: bool = comparison.loadout != game.run.loadout_snapshot or comparison.owned != game.run.equipment_snapshot
	var source_error: String = Snapshot.loadout_source_error(runtime, game.run.loadout_snapshot, comparison.loadout, game.run.stats, comparison.next_stats)
	if not source_error.is_empty(): return {"success":false,"error":source_error}
	var adjusted: Dictionary = Snapshot.for_loadout(runtime, game.run.loadout_snapshot, comparison.loadout, comparison.next_stats, game.run.hero_id, game.run.stats)
	if adjusted.is_empty(): return {"success":false,"error":"角色状态无法用于换装，请关闭背包后重试。"}
	var value: Dictionary = game.run.expedition.duplicate(true)
	if bool(comparison.pending):
		var pending: Dictionary = value.pending_equipment[id]
		var drop_id: String = str(pending.get("drop_id", pending.get("source_event_id", "")))
		if value.claimed_drop_ids.has(drop_id): value.claimed_drop_ids[drop_id]["field_decision"] = "equip"
	var receipt: Dictionary = game.run.live_receipt()
	receipt.loadout_snapshot = comparison.loadout.duplicate(true)
	receipt.equipment_snapshot = comparison.owned.duplicate(true)
	var validation_value: Dictionary = value.duplicate(true)
	validation_value.runtime = adjusted.duplicate(true)
	receipt.expedition = validation_value
	if not Expedition.valid(receipt, game.profile): return {"success":false,"error":"装备来源未通过存档校验，换装未生效。"}
	var live_combat: bool = str(value.phase) == "combat"
	if live_combat:
		# Never persist a partial room or replace its authoritative entry checkpoint.
		game.run.loadout_snapshot = comparison.loadout.duplicate(true)
		game.run.equipment_snapshot = comparison.owned.duplicate(true)
		game.run.expedition = value
		game.run.stats = comparison.next_stats.duplicate(true)
		game.run.max_hp = float(comparison.next_stats.max_hp)
		game.run.hp = float(adjusted.hp)
		game.run.resource = float(adjusted.resource)
	else:
		if not game.call("_commit_expedition", value, adjusted, game.profile.duplicate(true), {"loadout_snapshot":comparison.loadout,"equipment_snapshot":comparison.owned}):
			return {"success":false,"error":"存档写入失败，当前装备保持原样。"}
	if changed_loadout: game.run.loadout_changes += 1
	return {"success":true,"persisted":not live_combat,"runtime":adjusted}

static func apply(room: Node, id: String, slot: String, checkpoint: String) -> Dictionary:
	if not is_instance_valid(room) or not is_instance_valid(room.get("player")): return {"success":false,"error":"角色尚未准备完成。"}
	var actor: Node2D = room.get("player")
	var position_before := actor.position
	var aim_before: Vector2 = actor.get("aim_direction")
	# Live weak targets and proc budgets belong to this actor in this room only.
	# This copy is never merged into a persisted receipt or the JSON snapshot.
	var passives: RefCounted = actor.get("passives")
	var passive_state: Dictionary = passives.call("capture_same_room") if passives != null and passives.has_method("capture_same_room") else {}
	var runtime: Dictionary = room.call("expedition_runtime_snapshot")
	var old_loadout: Dictionary = Game.run.loadout_snapshot.duplicate(true)
	var old_stats: Dictionary = Game.run.stats.duplicate(true)
	var effects: RefCounted = actor.get("loadout").get("effects")
	var transient: Dictionary = {}
	for key: String in ["roots", "deaths", "same_target", "first_full_targets", "shock_targets", "cooldowns"]:
		transient[key] = effects.get(key).duplicate(true)
	var old_status: RefCounted = actor.get("status")
	var local_guards: Dictionary = old_status.get("guards").duplicate(true)
	var shield_spent := maxf(0.0,float(old_status.call("shield"))-Game.run.shield)
	Status.activate_prepared_guards(local_guards,shield_spent)
	for source: String in local_guards.keys():
		local_guards[source].amount = maxf(0.0,float(local_guards[source].amount)-shield_spent)
		if float(local_guards[source].amount) <= 0.0 or float(local_guards[source].remaining) <= 0.0: local_guards.erase(source)
	var result := change(Game, id, slot, runtime, checkpoint)
	if not bool(result.get("success", false)): return result
	# Restore only the actor; this never loads a room, resets an enemy or emits entry.
	if not Snapshot.restore(room, result.runtime):
		return {"success":false,"error":"配装已保存，角色恢复失败，请重新进入该房间。"}
	actor.position = position_before
	actor.set("aim_direction", aim_before)
	if not passive_state.is_empty(): result["passive_restored"] = bool(passives.call("restore_same_room",passive_state))
	var previous: Dictionary = Rules.loadout_binding(old_loadout, old_stats)
	var next: Dictionary = Rules.loadout_binding(Game.run.loadout_snapshot, Game.run.stats)
	for key: String in ["roots", "deaths", "first_full_targets", "cooldowns"]:
		# Histories and every target ICD remain consumed when gear is removed/readded.
		effects.set(key, transient[key])
	for root: Dictionary in effects.get("roots").values():
		root.erase("pending_context")
		root.erase("pending_stage")
	var same_target: Dictionary = transient.same_target
	for source: String in same_target.keys():
		if not Rules.source_active(source, previous) or not Rules.source_active(source, next): same_target.erase(source)
	effects.set("same_target", same_target)
	if Rules.source_active("S02_6", previous) and Rules.source_active("S02_6", next): effects.set("shock_targets", transient.shock_targets)
	var status: RefCounted = actor.get("status")
	for source: String in local_guards:
		if source.begins_with("room_prop:"):
			var guard: Dictionary = local_guards[source].duplicate(true)
			guard.amount = minf(float(guard.amount), Game.run.max_hp * 0.5)
			status.get("guards")[source] = guard
	Game.run.shield = float(status.call("shield"))
	actor.get("loadout").call("refresh_modifiers")
	Game.changed.emit()
	return result
