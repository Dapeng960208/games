extends SceneTree
## Deterministic policy tests, independent of profile mutation and UI rendering.
const Rewards = preload("res://scripts/world/room_rewards.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROOM REWARDS FAIL: " + label)

func _run() -> void:
	_branch_economy()
	_pool_affinity()
	_rolls_and_ownership()
	_catalog_and_previews()
	_optional_and_bosses()
	print("ROOM REWARDS TESTS: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func _branch_economy() -> void:
	# These are player-visible bargains, not merely snapshots of helper output.
	var expected: Array = [
		["L01", "full", 12, 1], ["L02", "full", 18, 1], ["L02", "reduced", 34, 0],
		["L03", "full", 30, 0], ["L03", "mobile", 12, 1], ["L04", "full", 14, 1],
		["L05", "full", 18, 1], ["L06", "full", 24, 2], ["L06", "reduced", 8, 0],
	]
	for hero: String in Registry.heroes():
		for row: Array in expected:
			var value: Dictionary = Rewards.build(row[0], row[1], hero, 478, "test-complete")
			_check(value.get("gold") == row[2] and value.get("equipment", []).size() == row[3], "%s %s %s real bargain" % [hero, row[0], row[1]])
			_check(value.get("xp") == 30 and value.get("mastery") == 180, "%s %s skill progress preserved across choices" % [row[0], row[1]])
		var intact: Dictionary = Rewards.build("L02", "full", hero, 12, "escort")
		var unload: Dictionary = Rewards.build("L02", "reduced", hero, 12, "escort")
		_check(int(unload.gold) > int(intact.gold) and unload.equipment.is_empty() and intact.equipment.size() == 1, "unloading trades equipment for usable cash")
		var precision: Dictionary = Rewards.build("L06", "full", hero, 12, "valves")
		var shortcut: Dictionary = Rewards.build("L06", "reduced", hero, 12, "valves")
		_check(int(precision.gold) > int(shortcut.gold) and precision.equipment.size() == 2 and shortcut.equipment.is_empty(), "precision task offers more than token cash difference")

func _pool_affinity() -> void:
	var themes: Array = ["offense", "defense", "survival", "mobility", "shield", "corrosion", "conductive", "thermal", "status"]
	var all_bosses: Array = Catalog.bosses().keys()
	for hero: String in Registry.heroes():
		_check(Rewards.equipment_pool("offense", hero).size() >= 5, hero + " first-run offensive pool supports several fresh finds")
		for theme: String in themes:
			for bosses: Array in [[], all_bosses]:
				var pool: Array = Rewards.equipment_pool(theme, hero, bosses)
				_check(not pool.is_empty(), "%s %s has useful unlocked equipment" % [hero, theme])
				var seen: Dictionary = {}
				for id: String in pool:
					var item: Dictionary = Registry.equipment(id)
					var stats: Dictionary = item.base_stats
					_check(not seen.has(id), "pool has no duplicate weights masquerading as different items")
					seen[id] = true
					_check(str(item.unlock_boss).is_empty() or bosses.has(item.unlock_boss), "boss-locked equipment cannot leak into early rolls")
					if hero != "CH03":
						_check(float(stats.get("ability_power", 0)) == 0 and float(stats.get("max_mana", 0)) == 0 and float(stats.get("magic_penetration", 0)) == 0, "physical role does not waste reward on AP/mana/MP")
					if theme == "offense":
						if hero == "CH03": _check(float(stats.get("ability_power", 0)) > 0 or float(stats.get("magic_penetration", 0)) > 0, "mage offence scales its real spells")
						elif hero == "CH01": _check(float(stats.get("attack", 0)) > 0 or float(stats.get("true_damage_bonus", 0)) > 0, "hammer offence supplies actual contact damage")
						else: _check(float(stats.get("attack", 0)) + float(stats.get("crit_chance", 0)) + float(stats.get("crit_multiplier", 0)) + float(stats.get("attack_speed", 0)) + float(stats.get("armor_penetration", 0)) > 0, "gunner offence supports shooting damage, cadence and penetration")
	_check(Rewards.equipment_pool("offense", "CH01") != Rewards.equipment_pool("offense", "CH02"), "physical classes have distinct offensive pools")
	_check(Rewards.equipment_pool("offense", "CH02") != Rewards.equipment_pool("offense", "CH03"), "gunner and mage never share generic offence pool")
	_check(Rewards.equipment_pool("unknown", "CH01").is_empty(), "unknown theme cannot silently draw all sixty pieces")
	_check(Rewards.equipment_pool("offense", "unknown").is_empty(), "invalid hero has no loot pool")

func _rolls_and_ownership() -> void:
	var pool: Array = Rewards.equipment_pool("offense", "CH01")
	_check(pool.size() > 2, "physical first-run offence has enough alternatives")
	var owned: Array = pool.slice(0, pool.size() - 2)
	var pending: Array = [pool[-2]]
	var input_owned: Array = owned.duplicate()
	var input_pending: Array = pending.duplicate()
	for seed in range(24):
		var reward: Dictionary = Rewards.build("L01", "full", "CH01", seed, "stable", owned, pending)
		_check(str(reward.equipment[0].equipment_id) == str(pool[-1]), "unowned and uncarried item wins over duplicates")
		_check(reward == Rewards.build("L01", "full", "CH01", seed, "stable", owned, pending), "same inputs remain deterministic across retries")
	_check(owned == input_owned and pending == input_pending, "policy never mutates caller ownership arrays")
	var fallback: Dictionary = Rewards.build("L06", "full", "CH01", 2, "all-owned", pool, [])
	_check(fallback.equipment.size() == 2 and fallback.equipment[0].equipment_id != fallback.equipment[1].equipment_id, "exhausted pool retains two distinct items for controller salvage")
	_check(fallback.gold == 24, "policy does not double-pay duplicate salvage")
	var room_differences: int = 0
	var seed_variety: Dictionary = {}
	for seed in range(64):
		var a: Dictionary = Rewards.build("L01", "full", "CH01", seed, "first")
		var b: Dictionary = Rewards.build("L04", "full", "CH01", seed, "second")
		if a.equipment[0].equipment_id != b.equipment[0].equipment_id: room_differences += 1
		seed_variety[a.equipment[0].equipment_id] = true
	_check(room_differences > 20, "different same-pool room choices are independently seeded")
	_check(seed_variety.size() > 2, "different runs can change drops within their intended pool")
	var event_a: Dictionary = Rewards.build("L06", "full", "CH03", 13, "run:a")
	var event_b: Dictionary = Rewards.build("L06", "full", "CH03", 13, "run:b")
	_check(event_a.equipment[0].equipment_id == event_b.equipment[0].equipment_id and event_a.equipment[0].drop_id != event_b.equipment[0].drop_id, "transaction identity never changes a promised deterministic roll")
	var long_event: Dictionary = Rewards.build("L06", "full", "CH03", 13, "x".repeat(160))
	for drop: Dictionary in long_event.equipment: _check(str(drop.drop_id).length() <= 160, "drop IDs fit persistent schema")

func _catalog_and_previews() -> void:
	var expected_quality: Dictionary = {"L02":["full","reduced"], "L03":["full","mobile"], "L06":["full","reduced"], "L08":["full","reduced"], "L09":["full","reduced"], "L12":["full","reduced"], "L13":["full","repaired"], "L16":["full","repaired"], "L17":["full","repaired"], "L20":["full","reduced"], "L23":["full","reduced"]}
	for room: String in Catalog.room_ids():
		_check(Rewards.qualities(room) == expected_quality.get(room, ["full"]), room + " exposes only implemented objective results")
		for hero: String in Registry.heroes():
			for english: bool in [false, true]:
				var preview: String = Rewards.preview(room, hero, english)
				_check(preview.split("\n").size() in [2, 3], room + " preview stays in a readable two/three lines")
				_check(preview.contains("30") and preview.contains("180") and preview.contains("Extract" if english else "撤离"), "preview discloses exact growth and equipment retention condition")
				for quality: String in Rewards.qualities(room):
					var reward: Dictionary = Rewards.build(room, quality, hero, 41, room + ":event")
					_check(not reward.is_empty(), room + " actual valid result generates reward")
					_check(preview.contains(str(reward.gold) + (" gold" if english else "金币")), room + " preview cash agrees with real grant")
					_check(reward.equipment.size() <= 2, "normal room cannot issue an uncontrolled inventory flood")
					if quality == "full" and room != "L03": _check(not reward.equipment.is_empty(), room + " complete objective actually has its promised loot")
					if reward.equipment.size() == 2: _check(reward.equipment[0].equipment_id != reward.equipment[1].equipment_id, "two-item award contains distinct equipment")
					for drop: Dictionary in reward.equipment: _check(not Registry.equipment(drop.equipment_id).is_empty(), "every drop resolves to real core gear")
	_check(Rewards.build("L01", "imaginary", "CH01", 0, "event").is_empty(), "invented quality never becomes free reward")
	_check(Rewards.build("bad", "full", "CH01", 0, "event").is_empty(), "unknown room is rejected")
	_check(Rewards.build("L01", "full", "bad", 0, "event").is_empty(), "unknown hero is rejected")
	_check(Rewards.build("L01", "full", "CH01", 0, "").is_empty(), "blank completion ID is rejected")
	_check(Rewards.preview("bad", "CH01").is_empty(), "unknown preview does not advertise phantom rewards")

func _optional_and_bosses() -> void:
	for hero: String in Registry.heroes():
		var side: Dictionary = Rewards.optional("L01", "side_crate", hero, 17, "side")
		var research: Dictionary = Rewards.optional("L11", "research_2", hero, 17, "research")
		_check(side.gold == 18 and side.equipment.size() == 1 and side.xp == 0 and side.mastery == 0, "side crate gives 18 gold and armor once through caller transaction")
		_check(Rewards.equipment_pool("defense", hero).has(side.equipment[0].equipment_id), "side crate armor fits class and unlocks")
		_check(research.gold == 22 and research.equipment.size() == 1 and research.xp == 0 and research.mastery == 0, "third research package has its own tangible optional reward")
		_check(Rewards.equipment_pool("offense", hero).has(research.equipment[0].equipment_id), "optional package gives class offence")
		_check(Rewards.optional("L01", "side_crate", hero, 17, "side") == side, "optional retry remains deterministic")
		for boss: String in Catalog.bosses():
			var value: Dictionary = Rewards.build(boss, "full", hero, 29, boss + ":complete")
			_check(value.gold == 80 and value.xp == 80 and value.mastery == 0 and value.boss_id == boss, "boss keeps its intended progression and permanent defeat identifier")
			_check(value.equipment.size() == 2 and value.equipment[0].equipment_id != value.equipment[1].equipment_id, "boss grants two distinct class items")
			for drop: Dictionary in value.equipment:
				var item: Dictionary = Registry.equipment(drop.equipment_id)
				_check(str(item.unlock_boss).is_empty() or item.unlock_boss == boss, "boss may unlock own loot without leaking future tiers")
			_check(Rewards.preview(boss, hero).contains("80金币") and Rewards.preview(boss, hero).contains("80经验"), "boss preview matches payload")
	_check(Rewards.optional("L02", "side_crate", "CH01", 0, "event").is_empty(), "only actual optional objects have rewards")
	_check(Rewards.optional("L11", "research_1", "CH01", 0, "event").is_empty(), "mandatory research cannot be claimed as optional")
	_check(Rewards.optional("L01", "side_crate", "CH01", 0, "").is_empty(), "optional reward requires a durable event identity")
	_check(Rewards.build("BO01", "reduced", "CH01", 0, "event").is_empty(), "boss has no invented shortcut payout")
