extends SceneTree
## Entirely synthetic values. This test never opens a player profile.
const Migration = preload("res://scripts/core/numerical_migration.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Rules = preload("res://config/numerical_rules.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	return {"selected_hero":"CH01", "hero_xp":{"CH01":0,"CH02":0,"CH03":0},
		"equipment":{"EQ01":{"level":0},"EQ11":{"level":0},"EQ21":{"level":0},"EQ31":{"level":0},"EQ41":{"level":0},"EQ51":{"level":0}},
		"loadout":{"weapon":"EQ01","head":"EQ11","chest":"EQ21","hands":"EQ31","feet":"EQ41","charm":"EQ51"},
		"permanent_gold":917,"materials":{"forge":8,"race:B03":4},"discoveries":["split","arc"],"equipment_discoveries":["EQ03"],"total_runs":11,
		"branches":{"CH01":{"q":"","ultimate":""},"CH02":{"q":"","ultimate":""},"CH03":{"q":"","ultimate":""}},
		"migration_id":"new_v2", "settings":{"language":"en","reduced_fx":false,"fullscreen":false}, "bosses":[], "tutorial_completed":[],"last_result":{},
		"applied_transactions":{"starter_grant_v1":{"kind":"starter"}}}

func converted_item(profile: Dictionary, template: String) -> Dictionary:
	return profile.equipment[profile.numerical_migration.template_instance_ids[template]]

func runtime_fixture() -> Dictionary:
	var player := {"cooldowns":{"q":2.75,"secondary":1.5,"f":9.1,"ultimate":40.0},"passive_count":3,"walk_distance":44.5,"aim_direction":[1.0,0.0],"cast_serial":9}
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 1.25
	var equipment := {"room_id":"L01","room_low_shield_used":true,"room_first_kill_used":true}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 2.0
	equipment.delayed_shield_at = -1.0
	equipment.heal_history = [{"time":1.0,"amount":0.015}]
	equipment.resource_history = [{"time":1.0,"amount":2.75}]
	equipment.refund_history = [{"time":1.0,"amount":0.35}]
	equipment.cooldowns = {"EQ14":3.75}
	equipment.buffs = {"speed":{"stat":"attack_speed_bonus","amount":0.12,"until":4.25}}
	var modifiers := {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 0.0
	equipment.adapter = {"clock":2.0,"movement_time":0.25,"event_serial":7,"modifiers":modifiers,
		"self_status_sources":{"damage_reduction":{"source":"EQ20","applied_at":1.0,"power":0.25,"H":0.25}}}
	var status := {"clock":2.0,"shock_cooldown":0.625,"origins":{},"slow_remaining":1.125,"slow_multiplier":0.85,
		"states":{"burn":{"remaining":1.75,"tick":0.6,"power":12.55,"H":19.25,"applied_at":1.0},
			"damage_reduction":{"remaining":1.25,"tick":0.0,"power":0.25,"H":0.25,"applied_at":1.0},
			"invulnerable":{"remaining":0.25,"tick":0.0,"power":1.0,"H":1.0,"applied_at":1.0}},
		"guards":{"equipment:EQ14":{"amount":22.75,"remaining":1.875},"hero:passive":{"amount":12.25,"remaining":0.875}}}
	return {"snapshot_version":1,"hero_id":"CH01","mode":"safe_boundary","hp":37.25,"resource":33.3,"player":player,"status":status,"equipment":equipment}

func _initialize() -> void:
	var old := fixture()
	var original := old.duplicate(true)
	var migrated := Migration.migrate_profile(old)
	check(not migrated.is_empty(), "low-level synthetic profile converts")
	if migrated.is_empty(): finish(); return
	check(old == original, "profile conversion never mutates input")
	check(migrated.equipment.size() == old.equipment.size(), "one instance per template, no compensation")
	for key in ["permanent_gold","materials","discoveries","equipment_discoveries","branches","applied_transactions","migration_id","total_runs","last_result","settings"]:
		check(migrated[key] == old[key], "non-numerical assets and audit unchanged: " + key)
	check(migrated.ruleset_version == 2 and migrated.scale_version == 10 and migrated.equipment_instance_version == 1 and migrated.reward_policy_version == 2 and migrated.optional_chest_receipt_version == 2, "frozen profile versions")
	check(migrated.gold_pity == {"B01":0,"B02":0,"B03":0,"B04":0}, "historical kills create no gold pity")
	check(migrated.loadout.size() == 8 and migrated.loadout.legs == "" and migrated.loadout.ring == "", "new slots empty without gifts")
	check(converted_item(migrated,"EQ01").rarity == "green", "generic ownership becomes green")
	check(Instances.main_stats(converted_item(migrated,"EQ01")).attack == 81, "green starter midpoint exact main stat without legacy double addition")
	for item: Dictionary in migrated.equipment.values():
		check(Instances.validate(item).is_empty() and item.item_level == 1, "valid low-level midpoint instance")
		check(item.enhancement_gold_ledger.is_empty() and item.material_ledger.is_empty(), "free ownership has no fabricated payment")
	check(Migration.migrate_profile(migrated) == migrated, "second conversion exact no-op")
	var replay: Dictionary = JSON.parse_string(JSON.stringify(migrated))
	var second := Migration.migrate_profile(replay)
	check(second == replay and Migration.migrate_profile(JSON.parse_string(JSON.stringify(second))) == second, "two JSON reload conversions stable")
	for field in ["equipment_instance_version", "reward_policy_version", "optional_chest_receipt_version"]:
		var mixed := migrated.duplicate(true); mixed[field] = 99
		check(Migration.migrate_profile(mixed).is_empty(), "mismatched repeated profile version rejected " + field)
		mixed = fixture(); mixed[field] = 2
		check(Migration.migrate_profile(mixed).is_empty(), "mixed legacy/new profile version rejected " + field)
	var detached := Migration.migrate_profile(migrated)
	detached.equipment[detached.loadout.weapon].main_rolls.attack = 0
	detached.numerical_migration.original.equipment.EQ01.level = 5
	check(converted_item(migrated,"EQ01").main_rolls.attack == 50 and migrated.numerical_migration.original.equipment.EQ01.level == 0 and old.equipment.EQ01.level == 0, "nested migrated and audit records detached")
	# Every legacy XP value retains its old level; exact floor avoids float drift.
	for xp in range(3601):
		var value := Migration.migrate_xp(xp)
		check(Growth.level_for_xp(value) == Registry.level_for_xp(xp), "no level loss at xp " + str(xp))
	check(Migration.migrate_xp(460) == 531 and Migration.migrate_xp(3600) == 3600 and Migration.migrate_xp(1) == 1, "exact legacy progress fraction and capped maximum")
	old = fixture()
	old.hero_xp = {"CH01":460,"CH02":3600,"CH03":120}
	old.equipment.EQ03 = {"level":5}
	old.equipment.EQ04 = {"level":3}
	old.equipment.EQ02 = {"level":4}
	old.loadout.weapon = "EQ03"
	old.loadout_presets = {"CH03":old.loadout.duplicate(true), "CH01":old.loadout.duplicate(true)}
	old.applied_transactions["paid:z"] = {"kind":"upgrade","item":"EQ03","price":340,"level":5}
	old.applied_transactions["paid:a"] = {"kind":"upgrade","item":"EQ03","price":240,"level":4,"economy_version":1}
	old.applied_transactions["bought"] = {"kind":"purchase","item":"EQ04","price":180,"level":0}
	migrated = Migration.migrate_profile(old)
	check(not migrated.is_empty(), "mixed low/max/multiclass high-N synthetic profile converts")
	if migrated.is_empty(): finish(); return
	var item := converted_item(migrated,"EQ03")
	check(item.item_level == 20 and item.rarity == "purple" and item.enhancement_rank == 5, "highest old hero sets ilvl and high N is retained")
	check(item.power_type == "physical" and converted_item(migrated,"EQ04").power_type == "magic" and converted_item(migrated,"EQ02").power_type == "physical", "active class overrides AP tendency; unreferenced AP falls back magic")
	check(item.legacy_equip_waiver == {"hero_ids":["CH01","CH03"],"type":true,"level":true} and item.legacy.template_id == "EQ03", "restricted waiver retains only actual original references")
	check(Instances.can_equip(item,"CH01",8) and Instances.can_equip(item,"CH03",4) and not Instances.can_equip(item,"CH02",1), "old references keep type+level; new hero gets no waiver")
	check(migrated.loadout.weapon == migrated.loadout_presets.CH03.weapon and migrated.equipment.size() == old.equipment.size(), "multiclass preset shares one stable identity")
	check(item.affix_type_and_quantile == [{"type":"attack","u":50},{"type":"armor_penetration","u":50},{"type":"crit_chance","u":50}], "legal authored tendencies precede stable config fill")
	check(Instances.main_stats(item).attack == 395, "max-level purple +5 midpoint exact main stat")
	var expected_prices := [63,95,142,205,283]
	for index in 5:
		check(item.enhancement_steps[index] == {"g":10,"pity":0,"base_price_peak":expected_prices[index]}, "canonical enhancement price at migrated ilvl rank " + str(index + 1))
	check(item.purchase_baseline_gold == 340, "green canonical frozen resale baseline ceil once")
	check(item.enhancement_gold_ledger.size() == 2 and item.enhancement_gold_ledger[0].amount == 240 and item.enhancement_gold_ledger[1].amount == 340 and item.material_ledger.is_empty(), "only provably paid ranks refunded, free ranks do not invent costs")
	check(converted_item(migrated,"EQ04").enhancement_gold_ledger.is_empty() and converted_item(migrated,"EQ02").enhancement_gold_ledger.is_empty(), "purchase and free high N do not prove upgrade payment")
	check(JSON.parse_string(JSON.stringify(Migration.migrate_profile(JSON.parse_string(JSON.stringify(old))))) == JSON.parse_string(JSON.stringify(migrated)), "migration result stable across source JSON key sorting")
	check(migrated.applied_transactions == old.applied_transactions, "all paid/purchase receipts remain unchanged for audit")
	var mage_selected := old.duplicate(true)
	mage_selected.selected_hero = "CH03"
	mage_selected.branches.CH02 = {"q":"B","ultimate":"A"}
	mage_selected.loadout_presets.CH02 = mage_selected.loadout.duplicate(true)
	mage_selected.loadout_presets.CH02.head = "EQ13" # Known but no longer owned.
	var mage_result := Migration.migrate_profile(mage_selected)
	check(converted_item(mage_result,"EQ03").power_type == "magic" and Instances.can_equip(converted_item(mage_result,"EQ03"),"CH01",8), "active mage preset type wins and prior physical class retains restricted compatibility")
	check(mage_result.branches == mage_selected.branches and mage_result.loadout_presets.CH02.head == "", "real learned branches retained and stale unowned preset creates no item")
	var duplicate_paid := old.duplicate(true)
	duplicate_paid.applied_transactions["duplicate:rank5"] = duplicate_paid.applied_transactions["paid:z"].duplicate(true)
	check(converted_item(Migration.migrate_profile(duplicate_paid),"EQ03").enhancement_gold_ledger.is_empty(), "duplicate rank payment history is ambiguous, never counted twice")

	old.applied_transactions["prior:sale"] = {"kind":"sale","item":"EQ03","items":{"EQ03":{"level":5,"price":225}},"price":225}
	check(converted_item(Migration.migrate_profile(old),"EQ03").enhancement_gold_ledger.is_empty(), "ambiguous sold/reacquired ownership never refunds earlier cycle")
	check(Migration.migrate_profile(old,"migration:numerical_v2",{"id":"ongoing","ruleset_version":1}).is_empty(), "active legacy adventure rejected without conversion")
	var active_original := old.duplicate(true)
	Migration.migrate_profile(old,"migration:numerical_v2",{})
	check(old == active_original, "even empty non-null active receipt keeps profile entirely legacy")
	for mutate in [{"hero_xp":{}},{"hero_xp":{"CH01":-1,"CH02":0,"CH03":0}},{"selected_hero":"CH99"},{"equipment":{}},{"loadout":{}},{"scale_version":10},{"ruleset_version":3},{"applied_transactions":[]},{"numerical_migration":{}},{"loadout_presets":{"CH99":{}}}]:
		var invalid := fixture(); invalid.merge(mutate,true)
		check(Migration.migrate_profile(invalid).is_empty(), "invalid profile rejected " + str(mutate))
	var broken := fixture(); broken.equipment.EQ01.level = 6
	check(Migration.migrate_profile(broken).is_empty(), "unsupported old enhancement rank rejected")
	broken = fixture(); broken.hero_xp.CH01 = NAN
	check(Migration.migrate_profile(broken).is_empty(), "nonfinite profile rejected")
	check(Migration.migrate_profile(fixture(),"drop:forged").is_empty(), "nonmigration event cannot create waivers")
	var runtime: Dictionary = JSON.parse_string(JSON.stringify(runtime_fixture()))
	var runtime_original := runtime.duplicate(true)
	var old_stats := {"max_hp":100.0,"resource_max":100.0}
	var new_stats := {"max_hp":800,"resource_max":1400}
	check(Snapshot.validate(runtime,"CH01",old_stats), "synthetic runtime has real legacy snapshot schema")
	var converted := Migration.migrate_runtime(runtime,old_stats,new_stats)
	check(not converted.is_empty(), "safe injured runtime converts")
	if converted.is_empty(): finish(); return
	check(runtime == runtime_original, "runtime conversion detached")
	check(converted.hp == 298 and converted.resource == 333, "conservative absolute/ratio minimum no refill")
	check(converted.status.guards["equipment:EQ14"].amount == 182 and converted.status.guards["hero:passive"].amount == 98, "shield uses smaller old absolute and new ratio")
	check(converted.status.states.burn.power == 126 and converted.status.states.burn.H == 193, "damage snapshot power/H rounded and scaled once")
	check(converted.status.states.damage_reduction.power == 0.25 and converted.status.states.damage_reduction.H == 0 and converted.status.states.invulnerable.power == 1 and converted.status.states.invulnerable.H == 1, "percentage and flags unscaled, nonpower H integer")
	check(converted.equipment.adapter.self_status_sources.damage_reduction.H == converted.status.states.damage_reduction.H, "status provenance remains matching")
	check(converted.player == runtime.player and converted.status.shock_cooldown == runtime.status.shock_cooldown and converted.status.states.burn.tick == 0.6 and converted.status.states.burn.remaining == 1.75 and converted.status.guards["equipment:EQ14"].remaining == 1.875, "all cooldowns ICD times counts preserved")
	check(converted.equipment.buffs == runtime.equipment.buffs and converted.equipment.cooldowns == runtime.equipment.cooldowns and converted.equipment.refund_history == runtime.equipment.refund_history, "percentage buffs and cooldown-refund seconds unchanged")
	check(converted.equipment.heal_history[0].amount == 12 and converted.equipment.resource_history[0].amount == 28 and converted.equipment.resource_history[0].time == 1.0, "legacy history units converted by their actual domain")
	check(converted.resource_regen_remainder == 0.0 and converted.resource_decay_remainder == 0.0, "legacy has no invented fractional income")
	var runtime_reload: Dictionary = JSON.parse_string(JSON.stringify(converted))
	check(Migration.migrate_runtime(converted,old_stats,new_stats) == converted and Migration.migrate_runtime(runtime_reload,old_stats,new_stats) == runtime_reload and Migration.migrate_runtime(JSON.parse_string(JSON.stringify(runtime_reload)),old_stats,new_stats) == runtime_reload, "runtime reload twice never rescales")
	var higher := Migration.migrate_runtime(runtime,old_stats,{"max_hp":2000,"resource_max":500})
	check(higher.hp == 373 and higher.resource == 167, "opposite cap direction still no refill")
	var zero := runtime.duplicate(true); zero.resource = 0.0
	check(Migration.migrate_runtime(zero,{"max_hp":100.0,"resource_max":0.0},{"max_hp":800,"resource_max":1000}).resource == 0, "zero legacy resource cap cannot create resource")
	var almost_full := runtime.duplicate(true)
	almost_full.hp = 99.99
	almost_full.resource = 99.999
	var kept_deficit := Migration.migrate_runtime(almost_full,old_stats,{"max_hp":1000,"resource_max":1000})
	check(kept_deficit.hp == 999 and kept_deficit.resource == 999, "tiny positive damage/spend never quantizes to full")
	var max_level_stats := {"max_hp":7349,"resource_max":1000}
	var max_level_old := {"max_hp":734.9,"resource_max":100.0}
	almost_full.hp = 734.8999
	var max_level_state := Migration.migrate_runtime(almost_full,max_level_old,max_level_stats)
	check(max_level_state.hp == 7348 and max_level_state.resource == 999, "damaged level-twenty scale boundary retains deficit")
	var already_bad := converted.duplicate(true); already_bad.hp = 298.5
	check(Migration.migrate_runtime(already_bad,old_stats,new_stats).is_empty(), "claimed V2 state with fractional HP rejected")
	already_bad = converted.duplicate(true); already_bad.status.states.burn.power = 126.25
	check(Migration.migrate_runtime(already_bad,old_stats,new_stats).is_empty(), "claimed V2 fractional damage power rejected")
	already_bad = runtime.duplicate(true); already_bad.resource_regen_remainder = 0.4
	check(Migration.migrate_runtime(already_bad,old_stats,new_stats).is_empty(), "legacy snapshot cannot hide an unversioned V2 remainder")

	for mutate in [{"snapshot_version":99},{"scale_version":2},{"scale_version":10},{"ruleset_version":2},{"hp":NAN},{"hp":101.0},{"mode":"combat"},{"mode":"fresh_entry"},{"status":{}},{"equipment":{"adapter":[]}}]:
		var invalid := runtime.duplicate(true); invalid.merge(mutate,true)
		check(Migration.migrate_runtime(invalid,old_stats,new_stats).is_empty(), "invalid/mixed/unsafe runtime rejected " + str(mutate))
	finish()

func finish() -> void:
	for label: String in failures: push_error(label)
	print("Numerical migration checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
