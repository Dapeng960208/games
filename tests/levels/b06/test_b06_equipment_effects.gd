extends SceneTree
## Pure focused B06 reducer contract. No scenes, profile IO, fake DPS or balance claims.
const Effects = preload("res://scripts/domain/combat/equipment_effects.gd")
const B06 = preload("res://scripts/levels/b06/combat/equipment_effects.gd")
var checks: int = 0
var failures: int = 0
var serial: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func near(value: float, expected: float, label: String) -> void:
	check(is_equal_approx(value, expected), label + " actual=" + str(value))

func ctx(extra: Dictionary = {}) -> Dictionary:
	serial += 1
	var id: String = "b06:" + str(serial)
	var value: Dictionary = {"event_id":id, "attack_id":id, "root_event_id":id, "target_id":"one", "target_alive":true,
		"hp":500, "max_hp":1000, "resource":100, "resource_max":1000, "resource_type":"rage", "H":100, "X":300,
		"equipment_eligible":true, "original_basic":false, "damage_source":"skill", "proc_depth":0, "confirmed":true,
		"paid_cost":100, "cast_success":true, "combat_active":true, "skill_slot":"secondary", "slot":"secondary", "target_states":[],
		"remaining_cooldowns":{"F":4.0, "R":8.0}, "b06_wave_targets":["one", "two", "three", "four"], "b06_shared_power_type":"physical"}
	value.merge(extra, true)
	if extra.has("skill_slot") and not extra.has("slot"): value.slot = extra.skill_slot
	return value

func fx(set_id: String = "", pieces: int = 6, unique: String = "") -> RefCounted:
	var value: RefCounted = Effects.new()
	value.stats = {"ruleset_version":2, "hero_id":"CH01", "attack":100, "ability_power":200, "max_hp":1000, "resource_max":1000}
	value.resource_type = "rage"
	if not set_id.is_empty(): value.set_counts[set_id] = pieces
	if not unique.is_empty(): value.equipped[unique] = true
	return value

func hit(value: RefCounted, extra: Dictionary = {}) -> Dictionary:
	return value.handle("after_hit", ctx(extra))

func _initialize() -> void:
	_warrior()
	_gunner()
	_mage()
	_shared()
	_uniques()
	_thresholds_and_lifecycle()
	print("B06 EQUIPMENT EFFECTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _warrior() -> void:
	var value: RefCounted = fx("B06-SW")
	near(value.passive_modifiers(ctx({"e_shield_active":true})).received_displacement_reduction, 0.25, "SW2 only live E shield")
	near(value.passive_modifiers(ctx({"shield":999, "e_shield_active":false})).received_displacement_reduction, 0.0, "SW2 unrelated shield does not qualify")
	var e_cast: Dictionary = ctx({"skill_slot":"f"})
	value.handle("skill_cast", e_cast)
	value.handle("after_hit", ctx({"confirmed":false}))
	var w: Dictionary = ctx({"hp_damage":0, "shield_absorbed":20})
	var out: Dictionary = value.handle("after_hit", w)
	near(out.resource_restore, 15, "SW4 confirmed shield-only paid W refund15 percent")
	near(value.handle("after_hit", w).resource_restore, 0, "SW4 duplicate receipt suppressed")
	w.target_id = "two"
	near(value.handle("after_hit", w).resource_restore, 0, "SW4 AoE cast returns once")
	value.handle("skill_cast", ctx({"skill_slot":"f"}))
	near(hit(value).resource_restore, 0, "SW4 ICD8")
	value = fx("B06-SW")
	value.handle("skill_cast", ctx({"skill_slot":"f"}))
	near(hit(value, {"paid_cost":0}).resource_restore, 0, "SW4 free W refund zero")
	value.handle("skill_cast", ctx({"skill_slot":"f"}))
	value.advance(4.0, ctx())
	near(hit(value).resource_restore, 0, "SW4 four second window ends exactly")
	value = fx("B06-SW")
	value.handle("damaged", ctx({"shield_absorbed":0, "e_shield_absorbed":0}))
	check(hit(value).bonus_hits.is_empty(), "SW6 zero absorption cannot arm")
	value.handle("damaged", ctx({"shield_absorbed":10}))
	check(value.handle("skill_cast", ctx({"skill_slot":"q"})).bonus_hits.is_empty(), "SW6 cast payment does not count as hit")
	check(hit(value, {"confirmed":false, "skill_slot":"q"}).bonus_hits.is_empty(), "SW6 miss preserves token")
	check(hit(value, {"proc_depth":1, "skill_slot":"q"}).bonus_hits.is_empty(), "SW6 derived damage cannot consume")
	out = hit(value, {"skill_slot":"q", "attacker_stats":{"attack":150, "ability_power":999}})
	check(out.bonus_hits.size() == 1 and out.bonus_hits[0].target_ids.size() == 3, "SW6 bounded three target wave")
	near(out.bonus_hits[0].damage, 60, "SW6 frozen attacker AD times .40")
	check(not out.bonus_hits[0].equipment_eligible and out.bonus_hits[0].proc_depth == 1 and not out.bonus_hits[0].critical, "SW6 derived nonrecursive noncrit flags")
	check(hit(value).bonus_hits.is_empty(), "SW6 one counter token")
	value.handle("damaged", ctx({"shield_absorbed":10}))
	check(not value._window("B06-SW_6:counter"), "SW6 absorption during ICD cannot arm")
	value = fx("B06-SW")
	value.handle("damaged", ctx({"shield_absorbed":10}))
	value.advance(6.0, ctx())
	check(hit(value).bonus_hits.is_empty(), "SW6 token expires at6 seconds")

func _gunner() -> void:
	var value: RefCounted = fx("B06-SG")
	var w: Dictionary = ctx()
	near(value.handle("before_hit", w).damage_bonus, 0.08, "SG2 W main target gets8 percent")
	near(value.handle("before_hit", ctx({"skill_slot":"q"})).damage_bonus, 0, "SG2 not Q")
	near(value.handle("before_hit", ctx({"proc_depth":1})).damage_bonus, 0, "SG2 no derived bonus")
	value.handle("after_hit", w)
	w.target_id = "two"
	near(value.handle("before_hit", w).damage_bonus, 0, "SG2 penetration target not main")
	var out: Dictionary = value.handle("after_hit", w)
	check(out.has("b06_tide_mark") and out.b06_tide_mark.target_id == "one", "SG6 two actual enemies mark main target")
	near(out.b06_tide_mark.duration, 6, "SG6 six second mark")
	check(not value.handle("after_hit", w).has("b06_tide_mark"), "SG6 repeated target cannot create extra mark")
	value = fx("B06-SG")
	value.handle("gunner_q_completed", ctx({"actual_distance":0.0}))
	check(hit(value, {"hunter_marked":true}).cooldown_refunds.is_empty(), "SG4 blocked Q cannot arm")
	value.handle("gunner_q_completed", ctx({"actual_distance":0.01}))
	check(hit(value, {"hunter_marked":false}).cooldown_refunds.is_empty(), "SG4 unmarked W preserves window")
	out = hit(value, {"hunter_marked":true})
	check(out.cooldown_refunds.size() == 1 and out.cooldown_refunds[0].slot == "F", "SG4 only E refund")
	near(out.cooldown_refunds[0].seconds, 1, "SG4 real movement need not reach B05 100px")
	value.handle("gunner_q_completed", ctx({"actual_distance":100.0}))
	check(hit(value, {"hunter_marked":true}).cooldown_refunds.is_empty(), "SG4 seven second ICD")
	value = fx("B06-SG")
	value.handle("gunner_q_completed", ctx({"actual_distance":10.0}))
	out = hit(value, {"hunter_marked":true, "remaining_cooldowns":{"F":0.25}})
	near(out.cooldown_refunds[0].seconds, 0.25, "SG4 refund cannot make cooldown negative")
	value = fx("B06-SG")
	check(not value.handle("gunner_r_shot", ctx({"r_shot_ordinal":1, "b06_tide_marked":false})).has("b06_r_bonus"), "SG6 R without tide mark gets no supplement")
	var shot: Dictionary = ctx({"skill_slot":"ultimate", "r_shot_ordinal":1, "b06_tide_marked":true})
	out = value.handle("gunner_r_shot", shot)
	check(out.has("b06_r_bonus") and out.b06_r_bonus.target_id == "one" and out.bonus_hits.is_empty(), "SG6 first fired shot binds projectile-only supplement")
	near(out.b06_r_bonus.damage, 12, "SG6 .12AD per fired round")
	check(not value.handle("gunner_r_shot", shot).has("b06_r_bonus"), "SG6 same receipt no double shot")
	for ordinal: int in [2, 3, 4]:
		var next: Dictionary = ctx({"root_event_id":shot.root_event_id, "skill_slot":"ultimate", "r_shot_ordinal":ordinal, "b06_tide_marked":false, "target_id":"other"})
		out = value.handle("gunner_r_shot", next)
		check(out.has("b06_r_bonus") == (ordinal <= 3), "SG6 exact emitted ordinal " + str(ordinal))
		if ordinal <= 3: check(out.b06_r_bonus.target_id == "one", "SG6 no mid-R retarget")
	check(not value.handle("gunner_r_shot", ctx({"r_shot_ordinal":1, "b06_tide_marked":true})).has("b06_r_bonus"), "SG6 once per R with12 second ICD")
	value = fx("B06-SG")
	check(not value.handle("gunner_r_shot", ctx({"r_shot_ordinal":2, "b06_tide_marked":true})).has("b06_r_bonus"), "SG6 later ordinal cannot invent cancelled first shot")
	w = ctx()
	value.handle("after_hit", w)
	var repeat: Dictionary = w.duplicate(true)
	repeat.attack_id += ":another"
	check(not value.handle("after_hit", repeat).has("b06_tide_mark"), "SG6 two receipts same enemy not penetration")
	repeat.target_id = "two"
	repeat.confirmed = false
	check(not value.handle("after_hit", repeat).has("b06_tide_mark"), "SG6 rejected second target not penetration")

func _mage() -> void:
	var value: RefCounted = fx("B06-SM")
	value.resource_type = "mana"
	near(value.passive_modifiers(ctx({"immediate_w_burst":true})).immediate_w_radius_scale, 1.10, "SM2 immediate radius10 percent")
	near(value.passive_modifiers(ctx()).get("immediate_w_radius_scale", 1.0), 1.0, "SM2 lingering radius unchanged")
	value.handle("skill_cast", ctx({"skill_slot":"f"}))
	near(value.handle("before_hit", ctx({"immediate_w_burst":true})).damage_bonus, 0, "SM4 E cast alone cannot arm")
	hit(value, {"skill_slot":"f"})
	near(value.handle("before_hit", ctx()).damage_bonus, 0, "SM4 persistent node cannot benefit")
	var w: Dictionary = ctx({"immediate_w_burst":true})
	near(value.handle("before_hit", w).damage_bonus, 0.12, "SM4 initial W preview buff")
	near(value.handle("before_hit", w).damage_bonus, 0.12, "SM4 repeated preview does not consume")
	value.handle("after_hit", w)
	w.target_id = "two"
	near(value.handle("before_hit", w).damage_bonus, 0.12, "SM4 one original burst buffs multiple targets")
	near(value.handle("before_hit", ctx({"immediate_w_burst":true})).damage_bonus, 0, "SM4 subsequent W not buffed")
	hit(value, {"skill_slot":"f"})
	check(not value._window("B06-SM_4:burst"), "SM4 eight second ICD")
	value = fx("B06-SM")
	hit(value, {"skill_slot":"f"})
	value.advance(6.0, ctx())
	near(value.handle("before_hit", ctx({"immediate_w_burst":true})).damage_bonus, 0, "SM4 six second window")
	value = fx("B06-SM")
	value.resource_type = "mana"
	for extra: Dictionary in [{"paid_cost":0}, {"cast_success":false}, {"combat_active":false}, {"proc_depth":1}]:
		extra["skill_slot"] = "q"
		extra["resource_type"] = "mana"
		value.handle("skill_cast", ctx(extra))
	check(int(value.counts.get("B06-SM_6:q", 0)) == 0, "SM6 excludes free failed outside-combat derived Q")
	var q: Dictionary = ctx({"skill_slot":"q", "resource_type":"mana"})
	value.handle("skill_cast", q)
	value.handle("skill_cast", q)
	hit(value, {"root_event_id":q.root_event_id, "skill_slot":"q", "target_id":"two"})
	check(int(value.counts.get("B06-SM_6:q", 0)) == 1, "SM6 paid Q once per cast not per target")
	for index: int in 2: value.handle("skill_cast", ctx({"skill_slot":"q", "resource_type":"mana"}))
	w = ctx({"immediate_w_burst":true, "burst_position":Vector2(20, 40)})
	var out: Dictionary = value.handle("mage_w_burst_completed", w)
	check(out.has("b06_ring") and out.bonus_hits.is_empty(), "SM6 schedules ring without node prerequisite")
	near(out.b06_ring.delay, 0.8, "SM6 ring delayed .8")
	near(out.b06_ring.radius, 110, "SM6 ring radius110")
	near(out.b06_ring.damage, 90, "SM6 frozen .45AP")
	check(out.b06_ring.burst_position == Vector2(20, 40), "SM6 committed burst center")
	check(not value.handle("mage_w_burst_completed", w).has("b06_ring"), "SM6 schedule once per W")
	var due: Dictionary = ctx({"root_event_id":w.root_event_id, "b06_ring_targets":["one", "two", "three", "four", "five"], "attacker_stats":{"ability_power":9999}, "ring_damage":99999})
	out = value.handle("b06_ring_due", due)
	check(out.bonus_hits.size() == 1 and out.bonus_hits[0].target_ids.size() == 4, "SM6 bounded four-target release")
	near(out.bonus_hits[0].damage, 90, "SM6 release cannot replace frozen power")
	check(value.handle("b06_ring_due", ctx({"root_event_id":w.root_event_id,"b06_ring_targets":["one"]})).bonus_hits.is_empty(), "SM6 release once even different receipt")
	check(value.handle("b06_ring_due", ctx({"b06_ring_targets":["one"]})).bonus_hits.is_empty(), "SM6 derived release cannot create independent budget")

func _shared() -> void:
	var value: RefCounted = fx("B06-SU")
	near(value.passive_modifiers(ctx()).received_displacement_reduction, 0.20, "SU2 all-class displacement20 percent")
	check(value.handle("room_enter", ctx({"room_id":"L31"})).shields.is_empty(), "SU4 no room-entry shield")
	check(value.advance(6.0, ctx()).shields.is_empty(), "SU4 first half period no shield")
	near(value.cooldowns[B06.PERIOD_KEY], 6, "SU4 half period recorded")
	value.advance(60.0, ctx({"combat_active":false}))
	near(value.cooldowns[B06.PERIOD_KEY], 6, "SU4 noncombat cannot accrue")
	value.set_counts.clear()
	value.advance(20.0, ctx())
	value.set_counts["B06-SU"] = 6
	near(value.cooldowns[B06.PERIOD_KEY], 6, "SU4 unequip/re-equip does not restart cadence")
	var out: Dictionary = value.advance(6.0, ctx())
	check(out.shields.size() == 1 and out.shields[0].source == "B06-SU_4", "SU4 one source shield on twelfth combat second")
	near(out.shields[0].ratio, 0.06, "SU4 maxHP6 percent")
	near(out.shields[0].duration, 4, "SU4 four second lifetime")
	near(value.cooldowns[B06.PERIOD_KEY], 12, "SU4 next period12")
	check(value.advance(0.0, ctx()).shields.is_empty(), "SU4 zero time cannot replay shield")
	value.handle("shield_source_ended", ctx({"source":"B06-SU_4", "cause":"unequipped"}))
	check(hit(value).bonus_hits.is_empty(), "SU6 unequip removal does not arm")
	value.handle("shield_source_ended", ctx({"source":"hero_f", "cause":"absorbed"}))
	check(hit(value).bonus_hits.is_empty(), "SU6 other shield source does not arm")
	value.handle("shield_source_ended", ctx({"source":"equipment:B06-SU_4", "cause":"expired"}))
	check(hit(value, {"proc_depth":1}).bonus_hits.is_empty(), "SU6 only original direct hits")
	check(hit(value, {"b06_shared_power_type":""}).bonus_hits.is_empty() and value._window("B06-SU_6:ended"), "SU6 unresolved mixed orientation preserves token")
	out = hit(value)
	check(out.bonus_hits.size() == 1 and out.bonus_hits[0].target_ids == ["one"], "SU6 single target after natural expiry")
	near(out.bonus_hits[0].damage, 25, "SU6 physical fixed instance uses AD")
	near(out.move_speed_bonus, 0.08, "SU6 movement8 percent")
	value.advance(3.0, ctx())
	near(value.passive_modifiers(ctx()).move_speed_bonus, 0, "SU6 movement expires at3 seconds")
	for hero: String in ["CH01", "CH02", "CH03"]:
		value = fx("B06-SU")
		value.stats.hero_id = hero
		value.handle("shield_source_ended", ctx({"source":"B06-SU_4", "cause":"absorbed"}))
		out = hit(value, {"b06_shared_power_type":"magic"})
		near(out.bonus_hits[0].damage, 50, "SU6 fixed magical shared instance on " + hero)
		check(out.bonus_hits[0].damage_type == "magic", "SU6 fixed magic type on " + hero)
	value = fx("B06-SU")
	value.handle("shield_source_ended", ctx({"source":"B06-SU_4", "cause":"expired"}))
	value.advance(6.0, ctx())
	check(hit(value).bonus_hits.is_empty(), "SU6 six second consumption window")

func _uniques() -> void:
	var value: RefCounted = fx("", 0, "B06-U01")
	var out: Dictionary = value.passive_modifiers(ctx())
	near(out.terrain_slow_reduction, 0.20, "U01 terrain slow magnitude reduction")
	near(1.0 - 0.15 * (1.0 - out.terrain_slow_reduction), 0.88, "U01 .85 becomes .88")
	near(out.received_displacement_reduction, 0, "U01 leaves tide displacement unchanged")
	value = fx("", 0, "B06-U02")
	out = value.handle("damaged", ctx({"shield_absorbed":0}))
	near(out.get("received_healing_bonus", 0.0), 0, "U02 no buff without absorption")
	out = value.handle("damaged", ctx({"shield_absorbed":1}))
	near(out.received_healing_bonus, 0.08, "U02 absorption grants received-healing8 percent")
	value.advance(4.0, ctx())
	near(value.passive_modifiers(ctx()).get("received_healing_bonus", 0.0), 0, "U02 four second window")
	out = value.handle("damaged", ctx({"shield_absorbed":1}))
	near(out.get("received_healing_bonus", 0.0), 0, "U02 twelve second ICD")
	value = fx("", 0, "B06-U03")
	check(value.handle("combat_mechanism_completed", ctx({"completed":false})).shields.is_empty(), "U03 interrupted interaction does not trigger")
	check(value.handle("combat_mechanism_completed", ctx({"completed":true, "combat_active":false})).shields.is_empty(), "U03 outside-combat interaction does not trigger")
	var interaction: Dictionary = ctx({"completed":true})
	out = value.handle("combat_mechanism_completed", interaction)
	check(out.shields.size() == 1 and out.shields[0].source == "B06-U03", "U03 completed mechanism one source shield")
	near(out.shields[0].ratio, 0.04, "U03 maxHP4 percent")
	near(out.shields[0].duration, 3, "U03 shield lasts3 seconds")
	check(value.handle("combat_mechanism_completed", interaction).shields.is_empty(), "U03 repeated receipt ignored")
	check(value.handle("combat_mechanism_completed", ctx({"completed":true})).shields.is_empty(), "U03 fifteen second ICD")

func _thresholds_and_lifecycle() -> void:
	for pieces: int in [1, 2, 3, 4, 5, 6, 8]:
		var tier: String = " at pieces=" + str(pieces)
		var warrior: RefCounted = fx("B06-SW", pieces)
		near(warrior.passive_modifiers(ctx({"e_shield_active":true})).received_displacement_reduction, 0.25 if pieces >= 2 else 0.0, "SW2 gate" + tier)
		warrior.handle("skill_cast", ctx({"skill_slot":"f"}))
		near(hit(warrior).resource_restore, 15 if pieces >= 4 else 0, "SW4 gate" + tier)
		warrior.handle("damaged", ctx({"shield_absorbed":10}))
		check(not hit(warrior, {"skill_slot":"q"}).bonus_hits.is_empty() == (pieces >= 6), "SW6 gate" + tier)
		var gunner: RefCounted = fx("B06-SG", pieces)
		near(gunner.handle("before_hit", ctx()).damage_bonus, 0.08 if pieces >= 2 else 0.0, "SG2 gate" + tier)
		gunner.handle("gunner_q_completed", ctx({"actual_distance":1.0}))
		check(not hit(gunner, {"hunter_marked":true}).cooldown_refunds.is_empty() == (pieces >= 4), "SG4 gate" + tier)
		check(gunner.handle("gunner_r_shot", ctx({"r_shot_ordinal":1,"b06_tide_marked":true})).has("b06_r_bonus") == (pieces >= 6), "SG6 gate" + tier)
		var mage: RefCounted = fx("B06-SM", pieces)
		near(mage.passive_modifiers(ctx({"immediate_w_burst":true})).immediate_w_radius_scale, 1.10 if pieces >= 2 else 1.0, "SM2 gate" + tier)
		hit(mage, {"skill_slot":"f"})
		near(mage.handle("before_hit", ctx({"immediate_w_burst":true})).damage_bonus, 0.12 if pieces >= 4 else 0.0, "SM4 gate" + tier)
		for index: int in 3: mage.handle("skill_cast", ctx({"skill_slot":"q"}))
		check(mage.handle("mage_w_burst_completed", ctx()).has("b06_ring") == (pieces >= 6), "SM6 gate" + tier)
		var shared: RefCounted = fx("B06-SU", pieces)
		near(shared.passive_modifiers(ctx()).received_displacement_reduction, 0.20 if pieces >= 2 else 0.0, "SU2 gate" + tier)
		check(not shared.advance(12.0, ctx()).shields.is_empty() == (pieces >= 4), "SU4 gate" + tier)
		shared.handle("shield_source_ended", ctx({"source":"B06-SU_4","cause":"expired"}))
		check(not hit(shared).bonus_hits.is_empty() == (pieces >= 6), "SU6 gate" + tier)
	for sid: String in ["B06-SW", "B06-SG", "B06-SM"]:
		for split: Array in [[4,4], [6,2], [2,6]]:
			var value: RefCounted = fx(sid, split[0])
			value.set_counts["B06-SU"] = split[1]
			var expected: float = 0.45 if sid == "B06-SW" else 0.20
			near(value.passive_modifiers(ctx({"e_shield_active":true})).received_displacement_reduction, expected, sid + " mixed " + str(split))
	var value: RefCounted = fx("B06-SW")
	value.set_counts["B06-SU"] = 2
	var out: Dictionary = value._empty()
	out["received_displacement_reduction"] = 0.30
	B06.modifiers(value, ctx({"e_shield_active":true}), out)
	near(out.received_displacement_reduction, 0.50, "same-family combined displacement cap50 percent")
	value = fx("B06-SM")
	value.resource_type = "mana"
	value.handle("skill_cast", ctx({"skill_slot":"q", "resource_type":"mana"}))
	value.advance(0.1, ctx())
	value.advance(10.0, ctx({"combat_active":false}))
	check(not value.counts.has("B06-SM_6:q"), "out of combat ten seconds clears temporary stacks")
	value = fx("B06-SW")
	value.handle("damaged", ctx({"shield_absorbed":10}))
	value.handle("room_enter", ctx({"room_id":"L32"}))
	check(not value._window("B06-SW_6:counter"), "room transition clears counter token")
	value = fx("B06-SU")
	value.advance(5.0, ctx())
	var snapshot: Dictionary = {"clock":value.clock, "cooldowns":value.cooldowns.duplicate(true)}
	var restored: RefCounted = fx("B06-SU")
	restored.clock = snapshot.clock
	restored.cooldowns = snapshot.cooldowns
	check(restored.advance(6.0, ctx()).shields.is_empty(), "safe scalar restore does not reset period")
	check(restored.advance(1.0, ctx()).shields.size() == 1, "restored period releases after remaining7")
