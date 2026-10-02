class_name EquipmentClassMigration
extends RefCounted
## One-time value-only migration. Ownership/rolls/receipts are never rewritten.
## Invalid historical class slots become empty; the same items remain in storage.
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const VERSION := 1

static func upgrade_profile(profile: Dictionary) -> Dictionary:
	var result := upgrade_document({"profile":profile, "active_run":null})
	return result.get("profile", {})

static func upgrade_document(document: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	var profile: Variant = result.get("profile")
	if not profile is Dictionary: return {}
	if profile.get("ruleset_version", 1) != 2: return result
	var update_classes: bool = not profile.has("equipment_class_migration")
	if not update_classes and not valid_marker(profile.equipment_class_migration): return {}
	var revision: Variant = profile.get("hero_role_revision", 0)
	if not Instances._integer_in(revision, 0, 1): return {}
	var update_roles: bool = revision == 0
	if not update_classes and not update_roles: return result
	if not profile.get("equipment") is Dictionary or not profile.get("hero_xp") is Dictionary or profile.get("selected_hero") not in Registry.heroes(): return {}
	var removed: Array = [] if update_classes else profile.equipment_class_migration.removed_slots.duplicate(true)
	if not _clean_loadout(profile.get("loadout"), profile.equipment, str(profile.selected_hero), Growth.level_for_xp(int(profile.hero_xp.get(profile.selected_hero, 0))), "camp", removed, update_classes): return {}
	if not profile.get("loadout_presets", {}) is Dictionary: return {}
	for hero: String in profile.get("loadout_presets", {}):
		if hero not in Registry.heroes() or not _clean_loadout(profile.loadout_presets[hero], profile.equipment, hero, Growth.level_for_xp(int(profile.hero_xp.get(hero, 0))), "preset", removed, update_classes): return {}
	for id: String in profile.equipment:
		var item: Variant = profile.equipment[id]
		if not item is Dictionary or not Instances.validate(item).is_empty(): return {}
		if item.location in ["inventory", "equipped"]: item.location = "equipped" if id in profile.loadout.values() else "inventory"
	var active: Variant = result.get("active_run")
	if active is Dictionary and active.get("ruleset_version", 1) == 2 and active.has("expedition"):
		if not _clean_run(active, profile, removed, update_classes, update_roles): return {}
	profile["hero_role_revision"] = 1
	profile["equipment_class_migration"] = {"version":VERSION, "removed_slots":removed}
	return result

static func _clean_loadout(loadout: Variant, equipment: Dictionary, hero: String, level: int, context: String, removed: Array, allow_cleanup: bool = true) -> bool:
	if not loadout is Dictionary or loadout.size() != Registry.slots(2).size(): return false
	for slot: String in Registry.slots(2):
		var id: Variant = loadout.get(slot)
		if not id is String: return false
		if id.is_empty(): continue
		if not equipment.get(id) is Dictionary: return false
		var record: Dictionary = equipment[id]
		if Registry.equipment(str(record.get("template_id", "")), 2).get("slot") != slot: return false
		if Instances.equip_error(record, hero, level) == "CLASS_LOCKED":
			if not allow_cleanup: return false
			# A corrupted non-class constraint must not be disguised as migration.
			if not Instances.can_equip(record, hero, level, true): return false
			removed.append({"hero_id":hero, "slot":slot, "instance_id":id, "context":context})
			loadout[slot] = ""
		elif not Instances.can_equip(record, hero, level): return false
	return true

static func _clean_run(active: Dictionary, profile: Dictionary, removed: Array, update_classes: bool, update_roles: bool) -> bool:
	if not active.get("expedition") is Dictionary: return false
	if not active.get("equipment_snapshot") is Dictionary or not active.get("loadout_snapshot") is Dictionary or not active.expedition.get("runtime") is Dictionary: return false
	var hero := str(active.get("hero_id", ""))
	var level := int(active.get("level", 0))
	var previous: Dictionary = active.loadout_snapshot.duplicate(true)
	var old_stats := Resolver.resolve(hero, level, previous, active.equipment_snapshot, 2, profile.get("talents", {}).get(hero, {}), update_classes, update_roles)
	if old_stats.is_empty(): return false
	if not _clean_loadout(active.loadout_snapshot, active.equipment_snapshot, hero, level, "expedition", removed, update_classes): return false
	# Camp location flags may change; carried value equality remains authoritative.
	for id: String in active.equipment_snapshot:
		if profile.equipment.has(id): active.equipment_snapshot[id].location = profile.equipment[id].location
	if previous == active.loadout_snapshot and not update_roles: return true
	var stats := Resolver.resolve(hero, level, active.loadout_snapshot, active.equipment_snapshot, 2, profile.get("talents", {}).get(hero, {}))
	if stats.is_empty(): return false
	var runtime: Dictionary = active.expedition.runtime
	if runtime.get("mode") == "fresh_entry":
		if not Snapshot.validate(runtime, hero, old_stats, true): return false
		# Fresh checkpoints have no timers/effects yet. Convert to a fully
		# specified empty boundary so new maxima never manufacture healing/mana.
		runtime = _fresh_boundary(runtime)
	var rebound := Snapshot.for_loadout(runtime, previous, active.loadout_snapshot, stats, hero, old_stats)
	if rebound.is_empty(): return false
	active.expedition.runtime = rebound
	return true

static func valid_marker(marker: Variant) -> bool:
	if not marker is Dictionary or marker.size() != 2 or marker.get("version") != VERSION or not marker.get("removed_slots") is Array: return false
	for row: Variant in marker.removed_slots:
		if not row is Dictionary or row.size() != 4 or row.get("hero_id") not in Registry.heroes() or row.get("slot") not in Registry.slots(2) or not row.get("instance_id") is String or row.get("context") not in ["camp", "preset", "expedition"]: return false
	return true

static func _fresh_boundary(fresh: Dictionary) -> Dictionary:
	var result := fresh.duplicate(true)
	result.mode = "safe_boundary"
	var player := {"cooldowns":{}, "passive_count":0, "walk_distance":0.0, "aim_direction":[1.0,0.0], "cast_serial":0}
	for key: String in Snapshot.SKILLS: player.cooldowns[key] = 0.0
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.0
	result["player"] = player
	result["status"] = {"clock":0.0, "shock_cooldown":0.0, "states":{}, "guards":{}, "origins":{}, "slow_remaining":0.0, "slow_multiplier":1.0}
	var effects := {"room_id":"", "room_low_shield_used":false, "room_first_kill_used":false}
	for key: String in Snapshot.EFFECT_MAPS: effects[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: effects[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: effects[key] = 0.0
	effects.delayed_shield_at = -1.0
	var modifiers := {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 0.0
	effects["adapter"] = {"clock":0.0, "movement_time":0.0, "event_serial":0, "modifiers":modifiers, "self_status_sources":{}}
	result["equipment"] = effects
	return Snapshot._json_keys(result)
