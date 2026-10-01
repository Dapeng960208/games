extends Node
## S07 integration: production room -> production receivers -> confirmed effects.
## Run as a scene, so Game is the real autoload. Only rendering/room generation
## is omitted; capture subclasses always execute the production combat methods.
## godot --headless --path . res://tests/test_numerical_confirmed_receivers.tscn -- --test-profile=user://test_numerical_confirmed_receivers/profile.json
const Rules = preload("res://config/numerical_rules.gd")
const State = preload("res://scripts/core/run_state.gd")
const Profiles = preload("res://scripts/combat/boss_profiles.gd")
var game: Node
var room: ReceiverRoom
var checks := 0
var failures := 0
var lethal_receivers := 0
var cover_receivers := 0
var acceptance_receivers := 0

class ReceiverRoom extends MineRoom:
	var death_receipts: Array[Dictionary] = []
	func _ready() -> void: pass
	func _draw() -> void: pass
	func enemy_died(enemy: MineEnemy) -> void:
		var before: Dictionary = enemy.last_damage_result.duplicate(true)
		super.enemy_died(enemy)
		death_receipts.append({"target_id":enemy.get_instance_id(), "before":before, "after":enemy.last_damage_result.duplicate(true)})

class ObservedLoadout extends CombatLoadout:
	var events: Array[Dictionary] = []
	func event(event_name: String, extra: Dictionary = {}) -> Dictionary:
		var before_kill_budget: Dictionary = effects.root_usage(str(extra.get("root_event_id", ""))) if event_name == "kill" else {}
		var result: Dictionary = super.event(event_name, extra)
		events.append({"name":event_name, "context":extra.duplicate(true), "result":result.duplicate(true), "before_kill_budget":before_kill_budget})
		return result

class EnemyReceiver extends MineEnemy:
	var receipts: Array[Dictionary] = []
	var status_receipts: Array[Dictionary] = []
	func _ready() -> void:
		health = HealthScript.new()
		add_child(health)
		health.reset(10000, Rules.V2)
		health.depleted.connect(_die)
		status.ruleset_version = Rules.V2
		state = &"idle"
	func _draw() -> void: pass
	func apply_status(id: String, power: float, duration: float = -1.0) -> bool:
		var accepted: bool = super.apply_status(id, power, duration)
		status_receipts.append({"id":id, "power":power, "accepted":accepted})
		return accepted
	func take_damage(amount: float, kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
		var accepted: bool = super.take_damage(amount, kind, direction, context)
		receipts.append({"source":str(kind), "amount":amount, "context":context.duplicate(true), "result":last_damage_result.duplicate(true), "accepted":accepted})
		return accepted

class BossReceiver extends MineBoss:
	var receipts: Array[Dictionary] = []
	var status_receipts: Array[Dictionary] = []
	func _ready() -> void:
		health = HealthScript.new()
		add_child(health)
		_initialize_boss_runtime()
		health.depleted.connect(_die)
		state = &"idle"
	func _draw() -> void: pass
	func apply_status(id: String, power: float, duration: float = -1.0) -> bool:
		var accepted: bool = super.apply_status(id, power, duration)
		status_receipts.append({"id":id, "power":power, "accepted":accepted})
		return accepted
	func take_damage(amount: float, kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
		var accepted: bool = super.take_damage(amount, kind, direction, context)
		receipts.append({"source":str(kind), "amount":amount, "context":context.duplicate(true), "result":last_damage_result.duplicate(true), "accepted":accepted})
		return accepted

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CONFIRMED RECEIVERS: " + label)

func fresh(hero: String = "CH02", weapon: String = "") -> void:
	if is_instance_valid(room): room.free()
	game.run = State.new()
	game.run.hero_id = hero
	game.run.level = 20
	game.run.stats = {"ruleset_version":Rules.V2, "attack":240, "ability_power":0,
		"max_hp":1500, "resource_max":1000, "resource_type":"rage" if hero == "CH01" else "mana" if hero == "CH03" else "energy",
		"loadout":{} if weapon.is_empty() else {"weapon":"receiver-fixture-weapon"},
		"equipment_templates":{} if weapon.is_empty() else {"weapon":weapon},
		"crit_chance":0.0, "crit_multiplier":1.5, "armor":0, "magic_resist":0}
	game.run.max_hp = 1500
	game.run.hp = 1500
	game.run.shield = 0
	game.run.resource = 0
	room = ReceiverRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.geometry_enabled = false
	room.spawn_enabled = false
	for node_name: String in ["Enemies", "Projectiles"]:
		var container := Node2D.new()
		container.name = node_name
		room.add_child(container)
	add_child(room)
	room.player = SalvagerPlayer.new()
	room.player.room = room
	room.player.position = Vector2(1000, 750)
	room.add_child(room.player)
	room.player.abilities.feedback.free()
	room.player.abilities.feedback = null
	room.player.loadout = ObservedLoadout.new()
	room.player.loadout.configure(room.player)
	room.enemy_skills = EnemySkillRuntime.new()
	room.add_child(room.enemy_skills)
	room.enemy_skills.configure(room)
	room.enemy_skills.process_mode = Node.PROCESS_MODE_DISABLED

func receiver(boss: bool = false, offset: Vector2 = Vector2(80, 0)) -> MineEnemy:
	var target: MineEnemy = BossReceiver.new() if boss else EnemyReceiver.new()
	target.room = room
	target.position = room.player.position + offset
	if boss:
		var profile: Dictionary = Profiles.resolve("BO02", 0)
		profile.merge({"ruleset_version":Rules.V2, "max_hp":10000, "armor":0, "magic_resist":0}, true)
		target.configure(profile)
	else:
		target.profile = {"ruleset_version":Rules.V2}
	target.reward_enabled = false
	target.training_ai_disabled = true
	room.enemies.add_child(target)
	return target

func hit(target: MineEnemy, amount: float, root: String, source: StringName = &"secondary", native: String = "", index: int = 0, extra: Dictionary = {}) -> bool:
	var context: Dictionary = {"attack_id":root + ":" + str(index), "root_event_id":root}
	context.merge(extra, true)
	return room.resolve_direct_hit(target, amount, source, native, 0, Vector2.RIGHT, context)

func events_named(event_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in room.player.loadout.events:
		if event.name == event_name: result.append(event)
	return result

func packets(target: MineEnemy, source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for receipt: Dictionary in target.receipts:
		if receipt.source == source: result.append(receipt)
	return result

func integer_receipt(receipt: Dictionary, label: String) -> void:
	for key: String in ["hp_damage", "shield_damage", "status_shield_damage", "auxiliary_shield_damage"]:
		check(receipt[key] is int, label + " integer receipt " + key)

func arm_gunner(target: MineEnemy) -> void:
	check(hit(target, 10, "prepare1", &"primary") and hit(target, 10, "prepare2", &"primary"), "real primaries arm calibration")
	check(room.player.passives.snapshot().current == 2, "two confirmed roots prepare calibration")
	room.player.class_mark_target(target)
	check(target.apply_status("shock", 240), "old shock is accepted")
	target.receipts.clear()
	room.player.loadout.events.clear()

func test_rejected_receivers() -> void:
	for boss: bool in [false, true]:
		for rejection: String in ["immune", "zero", "raw_round_zero", "defense_round_zero"]:
			fresh("CH02", "EQ02")
			var target: MineEnemy = receiver(boss)
			arm_gunner(target)
			room.player.loadout.event("dash", {"event_id":"arm-equipment"})
			var before_window: Dictionary = room.player.loadout.effects.windows.duplicate(true)
			check(before_window.has("EQ02"), "real equipment dash arms first-hit window")
			room.player.loadout.events.clear()
			var amount := 100.0
			if rejection == "immune":
				target.status.apply("invulnerable", 1, 3)
				target.status.grant_guard(1000, 3, "reject-guard", 10000)
			elif rejection == "zero": amount = 0.0
			elif rejection == "raw_round_zero": amount = 0.1
			else:
				amount = 1.0
				target.armor = 100000000
			var hp_before: Variant = target.health.current
			var shield_before: Variant = target.status.shield()
			var label: String = ("boss/" if boss else "enemy/") + rejection
			check(not hit(target, amount, "rejected", &"secondary", "chill"), label + " rejected by actual path")
			check(target.health.current == hp_before and target.status.shield() == shield_before, label + " no HP or shield loss")
			check(room.player.class_marks.has(target.get_instance_id()) and room.player.passives.snapshot().current == 2, label + " hunter and calibration unconsumed")
			check(target.status.has("shock") and target.status.shock_cooldown == 0.0 and not target.status.has("chill"), label + " old shock and native status gated")
			check(room.player.loadout.effects.windows == before_window and not room.player.loadout.effects.cooldowns.has("EQ02"), label + " equipment window and cooldown unconsumed")
			check(events_named("after_hit").is_empty() and events_named("status_applied").is_empty() and room.player.hit_chain.count == 2, label + " no equipment callbacks or chain count")
			check(room.player.loadout.effects.root_usage("rejected").packets == 0, label + " native packet budget unconsumed")
			target.status.states.erase("invulnerable")
			target.armor = 0
			check(hit(target, 100, "rejected", &"secondary", "chill", 1), label + " later valid same-root hit confirms")
			check(not room.player.class_marks.has(target.get_instance_id()) and room.player.passives.snapshot().current == 0, label + " confirmed retry consumes both class bonuses")
			check(not target.status.has("shock") and target.status.has("chill") and packets(target, "shock").size() == 1, label + " old shock once, native accepted")
			check(not room.player.loadout.effects.windows.has("EQ02") and room.player.loadout.effects.cooldowns.has("EQ02"), label + " confirmed retry commits equipment window")

func test_shield_only_confirmations() -> void:
	for boss: bool in [false, true]:
		for auxiliary: bool in [false, true]:
			fresh("CH02", "EQ03")
			var target: MineEnemy = receiver(boss)
			arm_gunner(target)
			# Prep attacks used EQ03. Clear only its expired fixture-era status/ICD;
			# the actual test's reducer and receive callbacks are untouched.
			target.status.states.erase("burn")
			room.player.loadout.effects.cooldowns.clear()
			if auxiliary:
				room.enemy_skills.emit_skill(target, {"kind":"guard", "mode":"socket", "amount":3000, "duration":5.0})
				check(room.enemy_skills.supports.size() == 1 and room.enemy_skills.supports[0].amount == 3000, "native auxiliary guard command creates real integer pool")
			else:
				target.status.grant_guard(3000, 5, "receiver-test", target.health.maximum)
			var hp_before: Variant = target.health.current
			var label: String = ("boss/" if boss else "enemy/") + ("auxiliary" if auxiliary else "status-shield")
			check(hit(target, 100, "shield-only", &"secondary", "shock"), label + " actual shield loss confirms room hit")
			var direct: Dictionary = packets(target, "secondary")[0]
			integer_receipt(direct.result, label)
			check(direct.accepted, label + " production receiver bool confirms legal shield absorption")
			check(direct.result.confirmed and direct.result.hp_damage == 0 and direct.result.shield_damage == 562, label + " exact (100+300+156)*1.01 = 562 shield receipt")
			check(direct.result.auxiliary_shield_damage == (562 if auxiliary else 0) and direct.result.status_shield_damage == (0 if auxiliary else 562), label + " correct independent shield source")
			check(target.health.current == hp_before, label + " direct and shock consume shields without HP")
			check(not room.player.class_marks.has(target.get_instance_id()) and room.player.passives.snapshot().current == 0, label + " shield loss consumes both class bonuses")
			check(target.status.has("shock") and target.status.states.shock.power == 240 and target.status.shock_cooldown == 1.0, label + " old shock consumed before new native snapshot")
			check(target.status.has("burn") and target.status.states.burn.power == 240 and events_named("after_hit").size() == 1, label + " real equipment after-hit and status execute")
			check(hit(target, 100, "shield-only", &"secondary", "shock", 1), label + " second segment confirms")
			check(packets(target, "shock").size() == 1 and packets(target, "secondary")[1].amount == 101, label + " subsequent segment repeats neither class bonus nor old shock")
			var equipment_activations := 0
			for event: Dictionary in events_named("after_hit"):
				for id: String in event.result.get("triggered", []):
					if id.begins_with("EQ03:"): equipment_activations += 1
			check(equipment_activations == 1, label + " equipment activates once per root")
			check(room.player.loadout.effects.root_usage("shield-only").packets == 2, label + " one native and one equipment packet shared across segments")
			check(room.player.passives.snapshot().current == 0 and room.player.passives.snapshot().icd == 2.0, label + " calibration is consumed once per root")
			check(room.player.hit_chain.count == 4, label + " existing chain counts distinct confirmed segments")

func test_true_bonus_roots() -> void:
	fresh("CH03")
	game.run.stats.true_damage_bonus = 17
	var targets: Array[MineEnemy] = [receiver(false), receiver(true, Vector2(100, 20))]
	room.crit_rolls["multi"] = true
	for segment: int in 3:
		for target: MineEnemy in targets:
			check(hit(target, 100, "multi", &"q", "", segment), "multi-target/multi-segment original confirms")
	for target: MineEnemy in targets:
		check(packets(target, "q").size() == 3 and packets(target, "equipment_true").size() == 1, "true bonus once per real root+target")
		var bonus: Dictionary = packets(target, "equipment_true")[0]
		check(bonus.result.hp_damage == 17 and not bonus.context.critical and not bonus.context.equipment_eligible and bonus.context.proc_depth == 1, "true bonus ignores shared crit and cannot recurse")
		room.resolve_derived_hit(target, 20, &"node", Vector2.RIGHT, {"root_event_id":"multi", "critical":true})
		check(packets(target, "equipment_true").size() == 1, "derived contact never re-injects true bonus")
		check(hit(target, 100, "next-root", &"q") and packets(target, "equipment_true").size() == 2, "new original root gets one new true bonus")
	check(room.player.hit_chain.count == 4, "chain counts three original segments plus next-root segment, once per target group")

func test_boss_receive_order() -> void:
	fresh("CH01")
	var target: MineBoss = receiver(true) as MineBoss
	target.armor = 1000
	target.boss_brain.weakpoint = "receiver-test"
	target.boss_brain.weakpoint_time = 2.0
	# A real support command leaves one unit before defense: 5*1.35 - 5 = 1.75.
	# One receiving round gives I(1.75/2)=1; rounding the weakpoint early gives 2.
	room.enemy_skills.emit_skill(target, {"kind":"guard", "mode":"socket", "amount":5, "duration":5.0})
	check(hit(target, 5, "boss-order", &"q"), "boss actual weakpoint/support/defense pipeline confirms")
	var receipt: Dictionary = packets(target, "q")[0].result
	integer_receipt(receipt, "boss ordered receiver")
	check(receipt.hp_damage == 1 and receipt.auxiliary_shield_damage == 5 and receipt.shield_damage == 5, "boss weakpoint precedes auxiliary pool and defense without early rounding")
	check(room.enemy_skills.supports.is_empty(), "actual auxiliary pool depleted and removed")

func test_lethal_confirmations() -> void:
	for boss: bool in [false, true]:
		for full_budget: bool in [false, true]:
			fresh("CH02")
			var target: MineEnemy = receiver(boss)
			arm_gunner(target)
			# Normal enemies award kills. Bosses preserve their own non-rewarding
			# flag: their completion callback and original after-hit still execute.
			target.reward_enabled = not boss
			game.run.stats.loadout = {"head":"lethal-head", "charm":"lethal-charm"}
			game.run.stats.equipment_templates = {"head":"EQ16", "charm":"EQ58"}
			room.player.loadout.configure(room.player)
			check(room.player.loadout.effects.equipped.has("EQ16") and room.player.loadout.effects.equipped.has("EQ58"), "lethal fixture binds real kill/after-hit equipment")
			game.run.hp = 1000
			room.player.grant_guard(10, 5, "lethal-existing")
			target.apply_status("corrosion", 240)
			target.health.current = 7
			room.player.loadout.events.clear()
			var native: Array = ["burn", "chill", "corrosion", "bleed"] if full_budget else ["chill"]
			var label: String = ("boss" if boss else "enemy") + ("/lethal-full-budget" if full_budget else "/lethal")
			check(not hit(target, 0, "lethal-zero", &"secondary", "chill") and room.death_receipts.is_empty() and target.health.current == 7, label + " zero cannot kill a pre-marked low-HP receiver")
			check(hit(target, 100, "lethal", &"secondary", "", 0, {"native_statuses":native}), label + " lethal room hit remains confirmed")
			var direct: Dictionary = packets(target, "secondary")[0]
			integer_receipt(direct.result, label)
			check(direct.accepted and direct.result.confirmed and direct.result.hp_damage == 7 and direct.result.shield_damage == 0, label + " receipt records actual capped HP loss, never overkill")
			check(target.health.dead and target.health.current == 0 and target.is_queued_for_deletion(), label + " real depleted signal reaches production death callback")
			check(room.death_receipts.size() == 1 and room.death_receipts[0].before == direct.result and room.death_receipts[0].after == direct.result, label + " receipt survives synchronous room death callback")
			if boss: check(target.is_complete() and target.completion_snapshot().complete, label + " boss production completion payload is finalized")
			check(not room.player.class_marks.has(target.get_instance_id()) and room.player.passives.snapshot().current == 0 and room.player.passives.snapshot().icd == 2.0, label + " lethal confirmation consumes hunter and calibration")
			check(not target.status.has("shock") and target.status.shock_cooldown == 1.0 and packets(target, "shock").is_empty(), label + " old shock is consumed but cannot damage a dead body")
			check(not target.status.has("chill") and events_named("status_applied").is_empty(), label + " new native statuses do not apply to dead receiver")
			var after: Array[Dictionary] = events_named("after_hit")
			check(after.size() == 1 and after[0].context.confirmed and after[0].context.hp_damage == 7 and after[0].context.equipment_eligible, label + " eligible after-hit receives preserved original receipt")
			check(room.player.hit_chain.count == 3, label + " lethal original contact advances chain exactly once")
			check(room.player.status.guards.has("equipment:EQ58") == not full_budget and game.run.shield == (10 if full_budget else 30), label + " actual after-hit shield is awarded subject to shared budget")
			check(room.player.loadout.effects.cooldowns.has("EQ58") == not full_budget, label + " denied after-hit shield cannot spend equipment cooldown")
			var kills: Array[Dictionary] = events_named("kill")
			check(kills.size() == (0 if boss else 1) and room.telemetry.kills == (0 if boss else 1), label + " real death callback keeps enemy/boss reward policy")
			if not boss:
				check(kills[0].before_kill_budget.packets == native.size(), label + " native reservation precedes synchronous kill equipment budget")
			check(game.run.hp == (1015 if not boss and not full_budget else 1000), label + " native budget controls real 1% kill healing")
			check(room.player.loadout.effects.root_usage("lethal").packets == (4 if full_budget else 2 if boss else 3), label + " native, kill and after-hit share one exact root budget")
			check(not hit(target, 100, "lethal", &"secondary", "", 1) and room.death_receipts.size() == 1 and events_named("after_hit").size() == 1, label + " later segment cannot re-kill or reward dead target")
			lethal_receivers += 1

func test_real_cover_receipts() -> void:
	for boss: bool in [false, true]:
		for mode: String in ["plate_hp", "plate_shield", "plate_reduction", "plate_immune_zero", "plate_immune_remainder", "plate_round_zero"]:
			fresh("CH01", "EQ03")
			var target: MineEnemy = receiver(boss)
			# Production support emission creates the real scene-backed static
			# MineEnemy plate 42 pixels toward the incoming primary attack.
			room.enemy_skills.emit_skill(target, {"kind":"guard", "mode":"cover", "cover_hp":35, "duration":5.0, "direction":Vector2.LEFT, "max_targets":1})
			var label: String = ("boss/" if boss else "enemy/") + mode
			check(room.enemy_skills.supports.size() == 1, label + " real cover support emitted")
			if room.enemy_skills.supports.size() != 1: continue
			var support: Dictionary = room.enemy_skills.supports[0]
			var plate: MineEnemy = support.anchor_ref.get_ref() as MineEnemy
			check(is_instance_valid(plate) and plate.static_actor and plate.actor_kind == "cover" and plate.health.maximum == 350, label + " production cover is a real versioned receiver")
			if not is_instance_valid(plate): continue
			check(plate.position == target.position + Vector2(-42, 0) and support.target_ref.get_ref() == target, label + " support geometry protects the intended receiver")
			if mode == "plate_shield": plate.status.grant_guard(100, 4, "cover-own-guard", plate.health.maximum)
			elif mode == "plate_reduction": plate.status.apply("damage_reduction", 0.5, 4)
			elif mode.begins_with("plate_immune"): plate.status.apply("invulnerable", 1, 4)
			elif mode == "plate_round_zero": plate.armor = 100000000
			var rejected: bool = mode in ["plate_immune_zero", "plate_round_zero"]
			if rejected: target.armor = 100000000
			var expected_plate_hp: int = 100 if mode == "plate_hp" else 50 if mode == "plate_reduction" else 0
			var expected_plate_shield: int = 100 if mode == "plate_shield" else 0
			var expected_aux: int = expected_plate_hp + expected_plate_shield
			var expected_victim_hp: int = 50 if mode == "plate_reduction" else 100 if mode == "plate_immune_remainder" else 0
			check(hit(target, 100, "real-cover", &"primary", "chill") == not rejected, label + " room confirmation follows actual combined losses")
			var receipt: Dictionary = packets(target, "primary")[0]
			integer_receipt(receipt.result, label)
			integer_receipt(plate.last_damage_result, label + "/plate")
			check(plate.health.current == 350 - expected_plate_hp and plate.last_damage_result.hp_damage == expected_plate_hp and plate.last_damage_result.status_shield_damage == expected_plate_shield, label + " plate HP/shield receipt reflects immunity, reduction and integer rounding")
			check(receipt.result.auxiliary_shield_damage == expected_aux and receipt.result.shield_damage == expected_aux and receipt.result.hp_damage == expected_victim_hp, label + " only actual cover loss is subtracted before victim defense")
			check(receipt.accepted == not rejected and target.health.current == 10000 - expected_victim_hp, label + " receiver return and HP match real settlement")
			check(target.status.has("chill") == not rejected and target.status.has("burn") == not rejected, label + " native/equipment status gates use actual cover receipt")
			check(game.run.resource == (0 if rejected else 80) and room.player.break_stacks == (0 if rejected else 1), label + " cover contact awards primary benefits only on real loss")
			check(events_named("after_hit").size() == (0 if rejected else 1) and room.player.loadout.effects.root_usage("real-cover").packets == (0 if rejected else 2), label + " rejected plate cannot fabricate equipment callback or native packet use")
			cover_receivers += 1

func bind_items(templates: Dictionary) -> void:
	var instances: Dictionary = {}
	for slot: String in templates: instances[slot] = "status-fixture-" + slot
	game.run.stats.loadout = instances if game.run.ruleset_version() == Rules.V2 else templates.duplicate()
	game.run.stats.equipment_templates = templates.duplicate()
	room.player.loadout.configure(room.player)
	for id: String in templates.values(): check(room.player.loadout.effects.equipped.has(id), "status acceptance fixture binds " + id)

func status_attempts(target: MineEnemy, id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attempt: Dictionary in target.status_receipts:
		if attempt.id == id: result.append(attempt)
	return result

func check_status_receipt_retry(target: MineEnemy, saved_event: Dictionary, accepted: bool) -> void:
	var context: Dictionary = saved_event.context
	var commands: Array = saved_event.result.statuses
	var root: String = str(context.root_event_id)
	check(commands.size() == 1 and commands[0].effect_id == "EQ50", "retry uses exact emitted EQ50 status command receipt")
	if accepted:
		# Advance the real reducer clock so an erroneous duplicate commit would
		# visibly extend the existing six-second deadline to 6.5 seconds.
		room.player.loadout.tick(0.5)
	else:
		# Leave an actual native packet in this root after rejection. A second
		# erroneous release must not hide behind a clamp of an already-zero count.
		check(hit(target, 10, root, &"primary", "corrosion", 99), "later same-root segment reserves a real native packet")
	var usage: Dictionary = room.player.loadout.effects.root_usage(root)
	var cooldowns: Dictionary = room.player.loadout.effects.cooldowns.duplicate(true)
	check(usage.packets == 1, "receipt retry fixture retains exactly one committed packet")
	var accepted_ids: Array[String] = ["EQ50"]
	var rejected_ids: Array[String] = []
	check(room.player.loadout.effects.settle_status_requests(context, commands, accepted_ids).is_empty(), "duplicate positive status settlement cannot commit again")
	check(room.player.loadout.effects.settle_status_requests(context, commands, rejected_ids).is_empty(), "duplicate negative status settlement cannot refund again")
	check(room.player.loadout.effects.root_usage(root) == usage and room.player.loadout.effects.cooldowns == cooldowns, "duplicate accepted/rejected acknowledgements preserve packet count and ICD deadline")
	var attempts_before: int = target.status_receipts.size()
	var repeated: Dictionary = room.player.loadout.event("after_hit", context)
	check(repeated.statuses.is_empty() and target.status_receipts.size() == attempts_before, "replayed exact after-hit callback cannot emit or apply pending statuses again")
	check(room.player.loadout.effects.root_usage(root) == usage and room.player.loadout.effects.cooldowns == cooldowns, "replayed after-hit preserves settled packet count and ICD")

func test_equipment_status_acceptance() -> void:
	for boss: bool in [false, true]:
		for id: String in ["EQ50", "EQ10"]:
			fresh("CH01")
			bind_items({"feet":"EQ50"} if id == "EQ50" else {"weapon":"EQ10"})
			var target: MineEnemy = receiver(boss)
			var state_id: String = "chill" if id == "EQ50" else "shock"
			target.apply_status(state_id, 500, 5.0)
			if id == "EQ50": target.apply_status("shock", 500, 5.0)
			else: target.status.shock_cooldown = 1.0
			room.player.loadout.event("dash", {"event_id":"reject-status-dash"})
			target.status_receipts.clear()
			room.player.loadout.events.clear()
			var label: String = ("boss/" if boss else "enemy/") + id
			check(hit(target, 100, "reject-equipment-status", &"primary"), label + " confirmed contact attempts equipment status")
			var attempts: Array[Dictionary] = status_attempts(target, state_id)
			check(attempts.size() == 1 and attempts[0].power == 240 and not attempts[0].accepted, label + " real receiver rejects weaker equipment snapshot")
			check(target.status.states[state_id].power == 500 and target.status.states[state_id].remaining == 5.0, label + " rejected snapshot cannot extend stronger old state")
			check(not room.player.loadout.effects.cooldowns.has(id) and room.player.loadout.effects.root_usage("reject-equipment-status").packets == 0, label + " rejected standalone status spends neither ICD nor packet")
			check(events_named("status_applied").is_empty() and events_named("after_hit").size() == 1, label + " confirmed hit remains separate from rejected status acceptance")
			if id == "EQ10":
				check(target.status.has("shock") and target.status.states.shock.power == 500 and packets(target, "shock").is_empty(), label + " shock cooldown protects strong old snapshot during direct contact")
			else:
				check(not target.status.has("shock") and packets(target, "shock").size() == 1, label + " old shock consumption cannot falsely accept rejected chill")
				check_status_receipt_retry(target, events_named("after_hit")[0], false)
			# A new dash/confirmed root at the same clock must work immediately.
			# Equal-power refresh is accepted even without increasing status power.
			target.status.states.erase(state_id)
			target.apply_status(state_id, 240, 1.0)
			if id == "EQ50": target.apply_status("shock", 240, 3.0)
			room.player.loadout.event("dash", {"event_id":"retry-status-dash"})
			target.status_receipts.clear()
			check(hit(target, 100, "retry-equipment-status", &"primary"), label + " freshly primed same-clock retry confirms")
			attempts = status_attempts(target, state_id)
			check(attempts.size() == 1 and attempts[0].accepted and target.status.states[state_id].power == 240 and target.status.states[state_id].remaining == 3.0, label + " equal-power refresh really accepted")
			check(room.player.loadout.effects.cooldowns.get(id, -1.0) == 6.0 and room.player.loadout.effects.root_usage("retry-equipment-status").packets == 1, label + " accepted retry commits one packet and six-second ICD")
			if id == "EQ50": check_status_receipt_retry(target, events_named("after_hit").back(), true)
			acceptance_receivers += 1
		fresh("CH03")
		game.run.stats.merge({"attack":180, "ability_power":280, "relic_levels":{"RL02":2}}, true)
		game.run.relics.append("ember")
		bind_items({"weapon":"EQ03", "charm":"EQ58"})
		room.player.grant_guard(10, 5, "status-acceptance-guard")
		var target: MineEnemy = receiver(boss)
		var label: String = ("boss/" if boss else "enemy/") + "EQ03/native-burn"
		check(hit(target, 100, "native-before-equipment", &"primary", "", 0, {"native_statuses":["burn", "shock", "chill"], "relic_reservations":["relic:ember"]}), label + " real primary confirms native and equipment stage order")
		var burns: Array[Dictionary] = status_attempts(target, "burn")
		check(burns.size() == 2 and burns[0].power == 420 and burns[0].accepted and burns[1].power == 278 and not burns[1].accepted, label + " stronger actual relic burn precedes rejected equipment burn")
		check(target.status.states.burn.power == 420 and target.status.states.burn.H == 420, label + " accepted relic snapshot remains authoritative")
		check(not room.player.loadout.effects.cooldowns.has("EQ03:" + str(target.get_instance_id())), label + " rejected equipment burn does not spend per-target ICD")
		check(game.run.shield == 30 and room.player.status.guards.has("equipment:EQ58") and room.player.loadout.effects.root_usage("native-before-equipment").packets == 4, label + " rejected provisional packet releases before later charm uses fourth slot")
		acceptance_receivers += 1
		fresh("CH01", "EQ06")
		target = receiver(boss)
		target.apply_status("corrosion", 500, 5.0)
		check(hit(target, 100, "bundle-prepare1", &"primary") and hit(target, 100, "bundle-prepare2", &"primary"), "EQ06 two actual contacts arm grouped status")
		target.status_receipts.clear()
		check(hit(target, 100, "mixed-status-bundle", &"primary"), "EQ06 third actual contact confirms")
		var corrosion: Array[Dictionary] = status_attempts(target, "corrosion")
		var grievous: Array[Dictionary] = status_attempts(target, "grievous")
		check(corrosion.size() == 1 and not corrosion[0].accepted and grievous.size() == 1 and grievous[0].accepted, "EQ06 actual grouped status has one rejected and one accepted component")
		check(target.status.states.corrosion.power == 500 and target.status.states.grievous.power == 1, "EQ06 mixed acceptance preserves strong corrosion and accepts grievous")
		check(room.player.loadout.effects.root_usage("mixed-status-bundle").packets == 1 and room.player.loadout.effects.cooldowns.has("EQ06"), "EQ06 any accepted component commits one shared packet")
		acceptance_receivers += 1
	# Legacy retains its original attempted-application consumption contract.
	fresh("CH01")
	game.run.stats.ruleset_version = Rules.LEGACY
	bind_items({"feet":"EQ50"})
	var legacy: MineEnemy = receiver()
	legacy.profile.ruleset_version = Rules.LEGACY
	legacy.health.reset(10000, Rules.LEGACY)
	legacy.status.ruleset_version = Rules.LEGACY
	legacy.apply_status("chill", 500, 5.0)
	legacy.apply_status("shock", 500, 5.0)
	room.player.loadout.event("dash", {"event_id":"legacy-status-dash"})
	check(hit(legacy, 100, "legacy-status", &"primary") and legacy.status.states.chill.power == 500, "legacy confirmed path keeps stronger chill")
	check(room.player.loadout.effects.cooldowns.get("EQ50", -1.0) == 6.0 and room.player.loadout.effects.root_usage("legacy-status").packets == 1, "legacy attempted status still commits original ICD/packet behavior")
	acceptance_receivers += 1

func test_corrosion_and_burn() -> void:
	fresh("CH03")
	game.run.stats.merge({"attack":180, "ability_power":280, "damage_bonus":0.2, "corrosion_damage_bonus":0.3, "burn_damage":0.2}, true)
	var target: MineEnemy = receiver()
	check(hit(target, 100, "new-corrosion", &"q", "corrosion"), "corrosion-adding direct contact confirms")
	check(packets(target, "q")[0].result.hp_damage == 120, "new corrosion cannot retroactively boost its applying hit")
	check(hit(target, 100, "old-corrosion", &"q"), "preexisting corrosion direct contact confirms")
	check(packets(target, "q")[1].result.hp_damage == 159, "prehit corrosion enters B once: I(100*(1+.2+.08+.3)*1.005)=159")
	room.crit_rolls["burn-root"] = true
	room.player.hit_chain.count = 100
	check(hit(target, 100, "burn-root", &"q", "burn"), "critical direct contact applies burn")
	check(target.status.states.burn.power == 451 and target.status.states.burn.H == 376, "burn snapshot applies 20% exactly once to skill H, independent of B/C/K")
	game.run.stats.burn_damage = 1.0
	game.run.stats.attack = 1000
	game.run.stats.ability_power = 1000
	target.tick_statuses(1.0)
	check(packets(target, "burn").size() == 1 and packets(target, "burn")[0].result.hp_damage == 54, "real burn tick keeps committed snapshot after attacker stats change")
	var burn: Dictionary = packets(target, "burn")[0]
	check(not bool(burn.context.get("critical", false)) and not burn.context.equipment_eligible and burn.context.H == 376, "DOT receiver retains H and cannot inherit original crit/eligibility")
	check(room.crit_rolls.size() == 3, "DOT rolls no new critical root")

func test_warrior_confirmed_primaries() -> void:
	fresh("CH01")
	var one: MineEnemy = receiver()
	var two: MineEnemy = receiver(true, Vector2(100, 20))
	one.status.apply("invulnerable", 1, 2)
	check(not hit(one, 100, "blocked-basic", &"primary") and game.run.resource == 0 and room.player.break_stacks == 0, "blocked primary grants no rage or momentum")
	one.status.states.erase("invulnerable")
	for index: int in 3:
		var root: String = "basic" + str(index)
		check(hit(one, 100, root, &"primary") and hit(two, 100, root, &"primary"), "one real primary root may hit two receivers")
		check(game.run.resource == 80 * (index + 1) and room.player.break_stacks == index + 1, "primary reward only once per confirmed root")
		check(game.run.shield == (120 if index == 2 else 0), "three confirmed roots grant integer 8% guard once")
	check(room.player.passives.snapshot().current == 0 and room.player.passives.snapshot().icd == 6.0 and room.player.hit_chain.count == 3, "three-rivets cooldown and root count")
	check(hit(one, 100, "during-cooldown", &"primary") and room.player.passives.snapshot().current == 0 and game.run.shield == 120, "guard cooldown prevents passive accumulation")

func test_player_shock_confirmation() -> void:
	for shield_only: bool in [false, true]:
		fresh("CH01")
		var player: SalvagerPlayer = room.player
		check(player.receive_enemy_status({"id":"shock", "power":240, "duration":3.0}), "player accepts enemy shock")
		for rejection: String in ["immune", "zero", "defense_round_zero"]:
			player.status.states.erase("invulnerable")
			game.run.stats.armor = 0
			var amount := 100.0
			if rejection == "immune": player.status.apply("invulnerable", 1, 2)
			elif rejection == "zero": amount = 0.0
			else:
				amount = 1.0
				game.run.stats.armor = 100000000
			check(not player.receive_damage(amount, player.position - Vector2.RIGHT), "player " + rejection + " rejects original packet")
			check(player.status.has("shock") and player.status.shock_cooldown == 0.0 and game.run.hp == 1500 and player.invulnerable == 0.0 and room.telemetry.player_hits == 0, "player " + rejection + " cannot consume shock or manufacture feedback")
		player.status.states.erase("invulnerable")
		game.run.stats.armor = 0
		if shield_only: player.grant_guard(500, 5, "receive-shield")
		check(player.receive_damage(100, player.position - Vector2.RIGHT), "player actual loss confirms")
		check(not player.status.has("shock") and player.status.shock_cooldown == 1.0 and room.telemetry.player_hits == 1, "player shock consumes exactly once on real loss")
		check(game.run.hp == (1500 if shield_only else 1340) and game.run.shield == (340 if shield_only else 0), "player original100 plus shock60 settle to HP/shield")
		check(game.run.resource == (0 if shield_only else 50), "warrior damage rage requires real HP loss")

func _run() -> void:
	game = get_tree().root.get_node("Game")
	if not str(game.profile_path).contains("test_numerical_confirmed_receivers"):
		push_error("Refusing non-test profile for confirmed receivers")
		get_tree().quit(2)
		return
	test_rejected_receivers()
	test_shield_only_confirmations()
	test_true_bonus_roots()
	test_boss_receive_order()
	test_lethal_confirmations()
	check(lethal_receivers == 4, "all four lethal receiver cases completed")
	test_real_cover_receipts()
	check(cover_receivers == 12, "all twelve actual cover receiver cases completed")
	test_equipment_status_acceptance()
	check(acceptance_receivers == 9, "all nine equipment-status acceptance cases completed")
	test_corrosion_and_burn()
	test_warrior_confirmed_primaries()
	test_player_shock_confirmation()
	if is_instance_valid(room): room.free()
	game.run = null
	print("NUMERICAL CONFIRMED RECEIVERS: %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 and checks > 0 else 1)
