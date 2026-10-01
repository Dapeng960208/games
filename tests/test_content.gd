extends SceneTree
## Run: powershell -File tools/test.ps1 -Suite content -SkipRestart
## Pure content/stat checks. The runner isolates the Game autoload profile.

const Registry = preload("res://scripts/data/content_registry.gd")
const Stats = preload("res://scripts/combat/stat_resolver.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _near(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) < 0.00001, description + " (actual %.6f, expected %.6f)" % [actual, expected])

func _loadout(ids: Array) -> Dictionary:
	var result := {}
	for id in ids:
		result[Registry.equipment(id).slot] = id
	return result

func _owned(ids: Array, level: int = 0) -> Dictionary:
	var result := {}
	for id in ids:
		result[id] = {"level": level}
	return result

func _run() -> void:
	var validation: Array[String] = Registry.validate()
	_check(validation.is_empty(), "all content definitions satisfy their schema: " + str(validation))
	_check(Registry.heroes() == ["CH01", "CH02", "CH03"], "three heroes have stable ordered IDs")
	for hero_id: String in Registry.heroes():
		var skills: Dictionary = Registry.hero(hero_id).skills
		_check(skills.q.unlock == 1 and skills.secondary.unlock == 2 and skills.f.unlock == 3 and skills.ultimate.unlock == 4, hero_id + " defines active skills at levels one through four")
	_check(Registry.equipment_ids().size() == 96, "ninety-six permanent equipment definitions")
	_check(Registry.sets().size() == 14, "fourteen sets")
	_check(Registry.hero("missing").is_empty(), "unknown hero is rejected")
	_check(Registry.equipment("missing").is_empty(), "unknown equipment is rejected")
	_check(Stats.resolve("missing", 1, {}, {}).is_empty(), "unknown hero cannot acquire fallback stats")
	var hero_copy: Dictionary = Registry.hero("CH01")
	hero_copy.skills.q.cost = 999
	_check(int(Registry.hero("CH01").skills.q.cost) == 20, "editing nested UI copy cannot change skill cost")
	var equipment_copy: Dictionary = Registry.equipment("EQ01")
	equipment_copy.base_stats.attack = 999
	_near(float(Registry.equipment("EQ01").base_stats.attack), 4.0, "equipment definitions are returned by deep copy")
	var sets_copy: Dictionary = Registry.sets()
	sets_copy.erase("S01")
	_check(Registry.sets().size() == 14, "set definitions are returned by copy")
	_check(Registry.level_for_xp(-1) == 1, "negative XP never creates a level below one")
	for fixture in [[0, 1], [29, 1], [30, 2], [69, 2], [70, 3], [119, 3], [120, 4], [230, 6], [359, 7], [360, 8], [899, 9], [900, 10], [3060, 18], [3330, 19], [3599, 19], [3600, 20], [999999, 20]]:
		_check(Registry.level_for_xp(fixture[0]) == fixture[1], "XP boundary %d -> level %d" % fixture)
	_check(Registry.next_level_xp(1) == 30 and Registry.next_level_xp(8) == 630, "next-level helper returns cumulative XP targets")
	_check(Registry.next_level_xp(20) == 3600 and Registry.next_level_xp(99) == 3600, "max-level target stays at level cap")
	_check(Registry.next_level_xp(-9) == 30, "invalid low level clamps to first target")
	var prices := 0
	var sets_cost := {}
	for id in Registry.equipment_ids():
		var item: Dictionary = Registry.equipment(id)
		prices += int(item.price)
		if not str(item.set_id).is_empty():
			sets_cost[item.set_id] = int(sets_cost.get(item.set_id, 0)) + int(item.price)
	_check(prices == 13560 and prices - 6 * 60 == 13200, "expanded catalog and after-starter purchase budgets match plan")
	for id in sets_cost:
		_check(sets_cost[id] == 900, str(id) + " six-piece purchase budget is 900")
	_check(Registry.equipment("EQ03").unlock_boss == "" and Registry.equipment("EQ08").unlock_boss == "", "starter elemental and impact sets are initially available")
	_check(Registry.equipment("EQ04").unlock_boss == "BO01" and Registry.equipment("EQ07").unlock_boss == "BO01", "first boss unlocks conductor and guard")
	_check(Registry.equipment("EQ05").unlock_boss == "BO02" and Registry.equipment("EQ09").unlock_boss == "BO02", "second boss unlocks frost and precision")
	_check(Registry.equipment("EQ06").unlock_boss == "BO03" and Registry.equipment("EQ10").unlock_boss == "BO03", "third boss unlocks corrosion and mobility")
	var base1: Dictionary = Stats.resolve("CH01", 1, {}, {})
	var max1: Dictionary = Stats.resolve("CH01", 20, {}, {})
	_near(base1.max_hp, 150.0, "bruiser level one HP")
	_near(base1.attack, 27.0, "bruiser level one base attack")
	_near(base1.armor, 20.0, "bruiser level one armor")
	_near(max1.max_hp, 180.0, "bruiser level twenty HP growth cap")
	_near(max1.attack, 29.7, "bruiser level twenty attack growth cap")
	_near(max1.armor, 26.0, "bruiser level twenty armor growth cap")
	_near(max1.attack_interval, 0.50, "growth does not silently add attack speed")
	_near(max1.move_speed, 220.0, "growth does not silently add movement speed")
	_near(max1.starting_resource, 20.0, "rage starts at twenty")
	_near(max1.resource_regen, 0.0, "rage has no natural regeneration")
	for fixture in [["CH02", 132.0, 26.4, 14.0, 18.0], ["CH03", 126.0, 19.8, 12.0, 5.0]]:
		var stats: Dictionary = Stats.resolve(fixture[0], 20, {}, {})
		_near(stats.max_hp, fixture[1], str(fixture[0]) + " level twenty HP")
		_near(stats.attack, fixture[2], str(fixture[0]) + " level twenty attack")
		_near(stats.armor, fixture[3], str(fixture[0]) + " level twenty armor")
		_near(stats.resource_regen, fixture[4], str(fixture[0]) + " distinct natural recovery")
	_near(Stats.resolve("CH01", 99, {}, {}).max_hp, 180.0, "oversized level clamps to twenty")
	_near(Stats.resolve("CH01", -1, {}, {}).max_hp, 150.0, "negative level clamps to one")
	var starter_ids := ["EQ01", "EQ11", "EQ21", "EQ31", "EQ41", "EQ51"]
	var starter: Dictionary = Stats.resolve("CH01", 1, _loadout(starter_ids), _owned(starter_ids))
	_near(starter.max_hp, 203.0, "starter equipment adds 53 HP")
	_near(starter.attack, 33.0, "starter equipment adds six fixed attack")
	_near(starter.move_speed, 226.6, "starter footwear adds three percent movement speed")
	_near(starter.damage_bonus, 0.0, "conditional glove damage does not become unconditional")
	_check(starter.sets.is_empty(), "generic equipment creates no set count")
	var upgraded: Dictionary = Stats.resolve("CH01", 20, _loadout(starter_ids), _owned(starter_ids, 5))
	_near(upgraded.max_hp, 260.0, "plus five raises only equipment HP by fifty percent with per-piece rounding")
	_near(upgraded.attack, 38.7, "plus five raises only equipment attack and adds it once to H")
	_near(upgraded.move_speed, 229.9, "percentage upgrade preserves precision")
	var capped_upgrade: Dictionary = Stats.resolve("CH01", 20, _loadout(starter_ids), _owned(starter_ids, 99))
	_near(capped_upgrade.attack, upgraded.attack, "corrupt over-cap upgrade cannot bypass plus five")
	var unowned: Dictionary = Stats.resolve("CH01", 1, _loadout(starter_ids), {})
	_near(unowned.max_hp, 150.0, "planned but unowned loadout grants no stats")
	_check(unowned.loadout.is_empty(), "invalid loadout entries do not appear equipped")
	var invalid_slot: Dictionary = Stats.resolve("CH01", 1, {"weapon": "EQ21", "head": "EQ21", "chest": "EQ21"}, _owned(["EQ21"]))
	_near(invalid_slot.max_hp, 178.0, "one piece cannot be equipped repeatedly in incorrect slots")
	var split_ids := ["EQ07", "EQ17", "EQ27", "EQ37", "EQ48", "EQ58"]
	var split: Dictionary = Stats.resolve("CH01", 1, _loadout(split_ids), _owned(split_ids))
	_check(split.sets == {"S05": 4, "S06": 2}, "four plus two mixed sets count independently")
	_near(split.damage_bonus, 0.0, "flat true damage is not a percentage bonus")
	_near(split.true_damage_bonus, 2.0, "new charm adds a separate flat true packet")
	_near(split.attack_interval, 0.5, "conditional set attack speed is not always on")
	var full_ids := ["EQ03", "EQ13", "EQ23", "EQ33", "EQ43", "EQ53"]
	var full: Dictionary = Stats.resolve("CH03", 1, _loadout(full_ids), _owned(full_ids))
	_check(full.sets == {"S01": 6}, "six-piece set count")
	_near(full.ability_power, 67.0, "caster furnace gear grants distinct spell power")
	_near(full.damage_bonus, 0.0, "burn and conditional set bonuses do not inflate all direct attacks")
	for count in [2, 3, 4, 5, 6]:
		var ids := full_ids.slice(0, count)
		var stats: Dictionary = Stats.resolve("CH03", 1, _loadout(ids), _owned(ids))
		_check(stats.sets.get("S01", 0) == count, "set counts survive unequipping at threshold %d" % count)
	var caps: Dictionary = Stats.clamp_equipment_contributions({"attack": 200.0, "max_hp": 999.0, "attack_speed": 4.0, "move_speed": 2.0, "crit_chance": 2.0, "cooldown_reduction": 3.0, "damage_bonus": 2.0, "damage_reduction": 2.0, "burn_damage": 8.0, "status_duration": 2.0})
	for fixture in [["attack", 45.0], ["max_hp", 220.0], ["attack_speed", 0.6], ["move_speed", 0.45], ["crit_chance", 0.75], ["cooldown_reduction", 0.3], ["damage_bonus", 0.6], ["damage_reduction", 0.35], ["burn_damage", 0.6], ["status_duration", 0.4]]:
		_near(caps[fixture[0]], fixture[1], str(fixture[0]) + " obeys its documented cap")
	_near(Stats.combined_damage_reduction(26.0, 0.35), 0.484126984127, "armor and equipment reductions combine multiplicatively")
	_near(Stats.combined_damage_reduction(1000.0, 0.9), 1.0 - (100.0 / 1100.0) * 0.35, "universal reduction cap is independent from armor mitigation")
	_near(Stats.combined_damage_reduction(-50.0, -0.1), 0.0, "negative defense never becomes reverse damage amplification")
	print("Content/stat checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
