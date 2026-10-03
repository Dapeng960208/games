extends Node
## S07: all frozen skill rows commit, release, travel and settle on real receivers.
## Only unrelated room setup/drawing is omitted; no hit or damage resolver is stubbed.
## godot --headless --path . res://tests/combat/test_numerical_confirmed_casts.tscn -- --test-profile=user://test_numerical_confirmed_casts/profile.json
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const State = preload("res://scripts/domain/expedition/run_session.gd")
var game: Node
var room: CastRoom
var checks := 0
var failures := 0
var catalog_rows := 0
var locked_rows := 0

class CastRoom extends RoomController:
	var capture_releases := false
	var releases: Array[Dictionary] = []
	func _ready() -> void: pass
	func _draw() -> void: pass
	func _release(kind: String, amount: float, context: Dictionary) -> void:
		if capture_releases:
			releases.append({"kind":kind, "amount":amount, "context":context.duplicate(true), "time":float(player.abilities.active.elapsed)})
	func strike_area(at: Vector2, radius: float, amount: float, source: StringName, applied_status: String = "", push: float = 0.0, direction: Vector2 = Vector2.ZERO, arc_degrees: float = 360.0, original: bool = true, context: Dictionary = {}, confirmed_only: bool = false) -> Array:
		_release("strike", amount, context)
		return super.strike_area(at, radius, amount, source, applied_status, push, direction, arc_degrees, original, context, confirmed_only)
	func spawn_ability_projectile(at: Vector2, direction: Vector2, amount: float, options: Dictionary) -> ProjectileActor:
		_release("projectile", amount, options)
		return super.spawn_ability_projectile(at, direction, amount, options)
	func add_deployment(kind: String, at: Vector2, options: Dictionary) -> Node2D:
		_release(kind, float(options.damage), options)
		return super.add_deployment(kind, at, options)

class Receiver extends EnemyActor:
	var receipts: Array[Dictionary] = []
	func _ready() -> void:
		health = HealthScript.new()
		add_child(health)
		health.reset(10000000, Rules.V2)
		status.ruleset_version = Rules.V2
	func _draw() -> void: pass
	func take_damage(amount: float, kind: StringName, from_direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
		var before: Variant = health.current
		var accepted: bool = super.take_damage(amount, kind, from_direction, context)
		var result: Variant = get("last_damage_result")
		receipts.append({"source":str(kind), "amount":amount, "context":context.duplicate(true), "loss":before - health.current, "result":result.duplicate(true) if result is Dictionary else {}, "accepted":accepted})
		return accepted

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CONFIRMED CASTS: " + label)

func same(actual: Variant, expected: Variant) -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		return absf(float(actual) - float(expected)) < 0.000001
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not same(actual[key], expected[key]): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index: int in expected.size():
			if not same(actual[index], expected[index]): return false
		return true
	return actual == expected

func fresh(hero: String, level: int, slot: String = "q", branch: String = "") -> void:
	if is_instance_valid(room): room.free()
	game.run = State.new()
	game.run.hero_id = hero
	game.run.level = level
	var bases: Dictionary = {"CH01":[270, 0, 1500], "CH02":[240, 0, 1100], "CH03":[180, 280, 1050]}
	game.run.stats = {"ruleset_version":Rules.V2, "resource_max":1000, "resource_regen":180 if hero == "CH02" else 50,
		"branches":{slot:branch}, "crit_chance":0.0, "crit_multiplier":1.5,
		"attack":Rules.integer(float(bases[hero][0]) * (1.0 + 0.04 * (level - 1))),
		"ability_power":Rules.integer(float(bases[hero][1]) * (1.0 + 0.05 * (level - 1))),
		"max_hp":Rules.integer(float(bases[hero][2]) * (1.0 + 0.05 * (level - 1)))}
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 1000
	room = CastRoom.new()
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
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	room.add_child(room.player)
	# Feedback owns no combat decisions and is unnecessary in this headless test.
	room.player.abilities.feedback.free()
	room.player.abilities.feedback = null

func dummy(at: Vector2) -> Receiver:
	var target := Receiver.new()
	target.room = room
	target.position = at
	target.profile = {"ruleset_version":Rules.V2}
	target.static_actor = true
	target.reward_enabled = false
	target.training_ai_disabled = true
	room.enemies.add_child(target)
	return target

func tick_cast(delta: float) -> void:
	room.capture_releases = true
	room.player.abilities.tick(delta)
	room.capture_releases = false

func fly() -> void:
	# Native swept collision handles pierce, splash and echoes. No direct hit calls.
	for step: int in 150:
		var moving := false
		for projectile: ProjectileActor in room.projectiles.get_children():
			if not projectile.consumed and not projectile.is_queued_for_deletion():
				moving = true
				projectile._physics_process(0.01)
		if not moving: break

func deployments(kind: String) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child: Node in room.get_children():
		if child is HeroDeployment and child.kind == kind:
			result.append(child)
	return result

func receipt_check(receipt: Dictionary, expected_damage: int, label: String) -> void:
	check(receipt.loss is int and receipt.loss == expected_damage, label + " real integer HP loss: " + str(receipt.loss) + " expected " + str(expected_damage))
	check(bool(receipt.result.get("confirmed", false)) and receipt.result.get("hp_damage", -1) == expected_damage and receipt.result.get("shield_damage", -1) == 0, label + " receiver confirms exact consumed packet")

func row_targets(spec: Dictionary) -> Array[Receiver]:
	var origin: Vector2 = room.player.position
	var targets: Array[Receiver] = []
	var at := origin + Vector2(80, 0)
	if spec.hero == "CH01" and spec.slot == "q": at = origin + Vector2(float(spec.travel) + 30.0, 0)
	if spec.hero == "CH03" and spec.slot == "secondary": at = origin + Vector2(160, 0)
	targets.append(dummy(at))
	var multiple: bool = spec.hero == "CH01" or (spec.hero == "CH02" and (spec.slot == "f" or int(spec.get("pierce", 0)) > 0)) or (spec.hero == "CH03" and spec.slot != "secondary")
	if multiple:
		targets.append(dummy(at + (Vector2(55, 0) if int(spec.get("pierce", 0)) > 0 else Vector2(0, 20))))
	return targets

func commit_row(spec: Dictionary, label: String) -> bool:
	var abilities: HeroAbilities = room.player.abilities
	var target: Vector2 = room.player.position + Vector2(100, 0)
	var native_unlock: int = int(spec.unlock)
	var was_locked: bool = game.run.level < native_unlock
	if was_locked:
		locked_rows += 1
		check(not abilities.try_cast(str(spec.slot), target) and abilities.last_failure == "locked", label + " gameplay unlock remains enforced")
		check(game.run.resource == 1000 and room.player.cooldowns[spec.slot] == 0.0 and abilities.cast_serial == 0, label + " locked cast cannot commit")
		# Frozen tables deliberately include inaccessible low-level coefficients.
		# Change only this in-memory metadata gate, restore immediately; native
		# spec construction, hero level, stats and actual release stay untouched.
		ContentRegistry._heroes[spec.hero].skills[spec.slot].unlock = game.run.level
	var committed: bool = abilities.try_cast(str(spec.slot), target)
	if was_locked: ContentRegistry._heroes[spec.hero].skills[spec.slot].unlock = native_unlock
	check(committed, label + " actual commitment")
	if committed:
		check(game.run.resource == 1000 - int(spec.cost), label + " one exact integer commitment cost")
		check(room.player.cooldowns[spec.slot] == spec.cooldown and room.player.resource_delay == (0.5 if spec.hero == "CH02" else 0.8), label + " authored cooldown and recovery delay")
	return committed

func test_catalog() -> void:
	var text: String = FileAccess.get_file_as_string(AssetCatalog.resolve("res://tests/fixtures/numerical/hero_skill_expectations.md"))
	var body: String = text.split("<!-- TARGET_SKILL_ROWS_START -->")[1].split("<!-- TARGET_SKILL_ROWS_END -->")[0]
	var seen: Dictionary = {}
	for line: String in body.split("\n"):
		if not line.begins_with("| CH0"): continue
		var columns: PackedStringArray = line.trim_prefix("|").trim_suffix("|").split("|")
		var hero: String = columns[0].strip_edges()
		var level: int = int(columns[1])
		var slot: String = columns[2].strip_edges()
		var branch: String = columns[3].strip_edges()
		if branch == "默认": branch = ""
		var frozen: Dictionary = JSON.parse_string(columns[6].strip_edges().xml_unescape())
		var expected: Dictionary = JSON.parse_string(columns[7].strip_edges().xml_unescape())
		var timeline: Array = JSON.parse_string(columns[8].strip_edges().xml_unescape())
		var label: String = "%s/%d/%s/%s" % [hero, level, slot, branch]
		check(not seen.has(label), label + " unique frozen row")
		seen[label] = true
		fresh(hero, level, slot, branch)
		var spec: Dictionary = room.player.abilities.spec(slot)
		var comparable: Dictionary = spec.duplicate(true)
		comparable.erase("momentum_free")
		check(same(comparable, frozen), label + " complete native spec preserves frozen branch/range/time/count")
		check(room.player.skill_power() == expected.skill_H, label + " frozen committed skill H")
		var targets: Array[Receiver] = row_targets(spec)
		if not commit_row(spec, label): continue
		check(same(room.player.abilities.active.events, timeline), label + " committed release timeline")
		var per_event: int = 2 if hero == "CH03" and slot == "ultimate" else 1
		var prior_time := 0.0
		for event: Dictionary in timeline:
			var event_index: int = int(event.index)
			var event_time: float = float(event.time)
			var before_count: int = room.releases.size()
			tick_cast(event_time - prior_time - 0.0001)
			check(room.releases.size() == before_count, label + " no release before event " + str(event_index))
			tick_cast(0.0001)
			prior_time = event_time
			check(room.releases.size() == before_count + per_event, label + " exact native release count at event " + str(event_index))
			for release: Dictionary in room.releases.slice(before_count):
				var wanted: int = int(expected.field_tick_damage) if release.kind == "field" else int(expected.damage_each)
				check(release.amount == wanted and is_equal_approx(release.time, event_time), label + " frozen amount and exact event time on " + str(release.kind))
				check(release.context.power == expected.skill_H, label + " carrier retains committed H")
			fly()
		# Released carriers own their clock after the finite cast ends.
		tick_cast(float(spec.duration) - prior_time + 0.01)
		check(not room.player.abilities.busy() and room.releases.size() == timeline.size() * per_event, label + " finite cast ends without extra releases")
		if hero == "CH02" and slot == "f":
			var grenade: Node2D = deployments("grenade")[0]
			grenade.advance(float(spec.fuse) - 0.0001)
			check(targets[0].receipts.is_empty(), label + " real grenade waits full fuse")
			grenade.advance(0.0001)
			grenade.advance(1.0)
			check(not grenade.alive, label + " grenade explodes and retires once")
		if hero == "CH03" and slot == "secondary":
			var node: Node2D = deployments("node")[0]
			check(node.health is int and node.health == expected.node_health, label + " native node health is scaled once")
			node.advance(1.5499)
			fly()
			check(targets[0].receipts.is_empty(), label + " node respects setup and first-fire delay")
			node.advance(0.0001)
			fly()
		if hero == "CH03" and slot == "ultimate":
			var field: Node2D = deployments("field")[0]
			field.advance(0.9999)
			check(targets[0].receipts.size() == 1, label + " field has no immediate free tick")
			field.advance(0.0001)
			field.advance(float(spec.lifetime) - 1.0)
			field.advance(1.0)
			check(not field.alive and is_equal_approx(field.lifetime, float(spec.lifetime)), label + " field includes final authored tick and retires")
		var derived_node: bool = hero == "CH03" and slot == "secondary"
		var expected_count: int = timeline.size() + (int(expected.field_tick_count) if hero == "CH03" and slot == "ultimate" else 0)
		for target_index: int in targets.size():
			var target: Receiver = targets[target_index]
			check(target.receipts.size() == expected_count, label + " real receiver count target " + str(target_index))
			for hit_index: int in target.receipts.size():
				var receipt: Dictionary = target.receipts[hit_index]
				var derived: bool = derived_node or receipt.source == "field"
				var base: int = int(expected.field_tick_damage) if receipt.source == "field" else int(expected.damage_each)
				if target_index == 1 and int(spec.get("pierce", 0)) > 0: base = Rules.integer(base * float(spec.get("pierce_multiplier", 1.0)))
				var wanted: int = base if derived else Rules.integer(base * (1.0 + hit_index * 0.005))
				receipt_check(receipt, wanted, label + "/target" + str(target_index) + "/hit" + str(hit_index))
				check(not bool(receipt.context.get("critical", false)), label + " zero-crit fixture remains noncritical")
				if derived:
					check(not bool(receipt.context.get("equipment_eligible", true)) and int(receipt.context.get("proc_depth", 0)) >= 1, label + " derived carrier remains ineligible")
				else:
					check(receipt.context.X is int and receipt.context.X == base and receipt.context.H == expected.skill_H, label + " raw frozen X and H survive actual receiver")
					check(receipt.context.root_event_id == "skill:1" and receipt.context.attack_id == "skill:1:" + str(hit_index), label + " all direct contacts preserve root and event IDs")
		check(room.crit_rolls.size() == (0 if derived_node else 1), label + " exactly one direct root roll, none for standalone node")
		check(room.player.hit_chain.count == (0 if derived_node else timeline.size()), label + " combo counts each confirmed release once across all victims")
		check(game.run.resource is int and game.run.resource == 1000 - int(spec.cost), label + " release/tick/impact cannot spend or refund twice")
		check(game.run.shield == int(expected.shield_amount), label + " authored release guard")
		catalog_rows += 1
	check(catalog_rows == 264 and seen.size() == 264, "all 264 frozen rows traversed actual cast and receiver paths")
	check(locked_rows > 0, "frozen inaccessible rows also exercise native unlock rejection")

func forced_cast(hero: String, slot: String, branch: String, offsets: Array[Vector2]) -> Array[Receiver]:
	fresh(hero, 20, slot, branch)
	var targets: Array[Receiver] = []
	for offset: Vector2 in offsets: targets.append(dummy(room.player.position + offset))
	room.crit_rolls["skill:1"] = true
	check(room.player.abilities.try_cast(slot, room.player.position + Vector2(100, 0)), hero + "/" + slot + "/" + branch + " critical fixture commitment")
	var events: Array = room.player.abilities.active.events.duplicate(true)
	var previous := 0.0
	for event: Dictionary in events:
		tick_cast(float(event.time) - previous)
		previous = float(event.time)
		fly()
	tick_cast(2.0)
	for grenade: Node2D in deployments("grenade"): grenade.advance(0.65)
	return targets

func test_shared_critical_carriers() -> void:
	for fixture: Array in [["CH02", "q", "", 3], ["CH02", "ultimate", "A", 4], ["CH01", "ultimate", "B", 2], ["CH02", "f", "", 1], ["CH03", "q", "", 1], ["CH03", "q", "A", 1]]:
		var hero: String = fixture[0]
		var slot: String = fixture[1]
		var branch: String = fixture[2]
		var count: int = int(fixture[3])
		var offsets: Array[Vector2] = [Vector2(80, 0)]
		if not (hero == "CH02" and slot == "q"):
			offsets.append(Vector2(135, 0) if branch == "A" else Vector2(80, 20))
		var targets: Array[Receiver] = forced_cast(hero, slot, branch, offsets)
		var spec: Dictionary = room.player.abilities.spec(slot)
		var base: int = Rules.integer(room.player.skill_power() * float(spec.coefficient))
		for target_index: int in targets.size():
			check(targets[target_index].receipts.size() == count, "critical real carrier count " + str(fixture) + " victim " + str(target_index))
			for index: int in targets[target_index].receipts.size():
				var receipt: Dictionary = targets[target_index].receipts[index]
				var pierced: int = Rules.integer(base * float(spec.get("pierce_multiplier", 1.0))) if target_index == 1 and int(spec.get("pierce", 0)) > 0 else base
				receipt_check(receipt, Rules.integer(pierced * 1.5 * (1.0 + index * 0.005)), "shared critical " + str(fixture))
				check(bool(receipt.context.get("critical", false)) and receipt.context.root_event_id == "skill:1", "shot/wave/pierce/splash/grenade keeps one critical root " + str(fixture))
		check(room.crit_rolls.size() == 1, "one shared root despite multiple native contacts " + str(fixture))
		check(room.player.hit_chain.count == count, "critical root preserves per-release combo count " + str(fixture))

func test_derived_carriers_do_not_crit() -> void:
	# Both exploding and piercing Q really trigger their nearby node echo.
	for branch: String in ["", "A"]:
		fresh("CH03", 20, "q", branch)
		var victim: Receiver = dummy(room.player.position + Vector2(80, 0))
		var node: Node2D = room.add_deployment("node", room.player.position + Vector2(80, 35), {"damage":105, "power":699, "health":500, "health_scale_version":10, "lifetime":14.0, "owner_player":room.player})
		node.advance(0.35)
		room.crit_rolls["skill:1"] = true
		check(room.player.abilities.try_cast("q", victim.position), "Q echo critical commitment " + branch)
		tick_cast(0.5)
		fly()
		var direct := 0
		var echoes := 0
		for receipt: Dictionary in victim.receipts:
			if receipt.source == "q":
				direct += 1
				check(bool(receipt.context.get("critical", false)), "echo parent Q really crits " + branch)
			elif receipt.source == "node_echo":
				echoes += 1
				receipt_check(receipt, Rules.integer(0.35 * 699), "real node echo " + branch)
				check(not bool(receipt.context.get("critical", false)) and not bool(receipt.context.get("equipment_eligible", true)), "echo strips inherited critical eligibility " + branch)
		check(direct == 1 and echoes == 1 and room.crit_rolls.size() == 1, "one direct, one derived echo, one random root " + branch)
		# A later node bolt must not borrow the original Q's critical decision.
		node.advance(1.2)
		fly()
		var bolt: Dictionary = victim.receipts.back()
		check(bolt.source == "node" and not bool(bolt.context.get("critical", false)), "genuine node projectile does not crit " + branch)
		receipt_check(bolt, 105, "real node projectile " + branch)
		check(room.crit_rolls.size() == 1, "node projectile allocates no random root " + branch)
	var offsets: Array[Vector2] = [Vector2(80, 0), Vector2(80, 20)]
	var targets: Array[Receiver] = forced_cast("CH03", "ultimate", "A", offsets)
	var field: Node2D = deployments("field")[0]
	field.advance(7.0)
	for target: Receiver in targets:
		check(target.receipts.size() == 8 and bool(target.receipts[0].context.get("critical", false)), "critical R followed by seven real field ticks")
		for receipt: Dictionary in target.receipts.slice(1):
			receipt_check(receipt, Rules.integer(0.65 * 699), "field after critical R")
			check(receipt.source == "field" and not bool(receipt.context.get("critical", false)), "field does not inherit direct critical flag")
	check(room.crit_rolls.size() == 1, "field never rolls independent critical roots")

func _run() -> void:
	game = get_tree().root.get_node("Game")
	var requested_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="):
			requested_profile = argument.trim_prefix("--test-profile=")
	if not requested_profile.contains("test_numerical_confirmed_casts") or str(game.profile_path) != requested_profile:
		push_error("Refusing non-test profile; pass -- --test-profile=<isolated path containing test_numerical_confirmed_casts>")
		get_tree().quit(2)
		return
	test_catalog()
	test_shared_critical_carriers()
	test_derived_carriers_do_not_crit()
	if is_instance_valid(room): room.free()
	game.run = null
	print("NUMERICAL CONFIRMED CASTS: %d/%d passed; %d frozen real casts, %d native locked-row denials" % [checks - failures, checks, catalog_rows, locked_rows])
	get_tree().quit(0 if failures == 0 else 1)
