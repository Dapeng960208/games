extends SceneTree
## Run in an isolated project without autoloads. Pure authored-data checks only.
const Catalog = preload("res://scripts/levels/b06/world/content.gd")
var failures: Array = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	check(Catalog.validate().is_empty(), "catalog validation: " + str(Catalog.validate()))
	var data := Catalog.catalog()
	check(not data.is_empty(), "catalog loads")
	if data.is_empty():
		finish()
		return
	check(Catalog.enemy_ids().size() == 18, "18 independent enemies")
	check(Catalog.room_ids().size() == 7, "six rooms and boss arena")
	check(Catalog.enemy("M01").is_empty() and Catalog.enemy("B07-M01").is_empty(), "reject foreign and old IDs")
	check(Catalog.room("L30").is_empty(), "reject other chapter rooms")
	for difficulty in range(5):
		check(Catalog.skills_for_difficulty("B06-M01", difficulty).size() == (1 if difficulty < 2 else 2 if difficulty < 4 else 3), "cumulative difficulty gates")
	check(Catalog.skills_for_difficulty("B06-M01", 5).is_empty(), "reject unsupported difficulty")
	var enemy := Catalog.enemy("B06-M01")
	enemy.raw_stats.max_hp = 1
	check(Catalog.enemy("B06-M01").raw_stats.max_hp == 78, "enemy returns deep copy")
	var room := Catalog.room("BO06")
	room.blueprint_percent_anchors.drains[0][0] = 99
	check(Catalog.room("BO06").blueprint_percent_anchors.drains[0][0] == 20, "room returns deep copy")
	var skills := Catalog.skills_for_difficulty("B06-M01", 4)
	skills[0].parameters.damage_a = 99
	check(Catalog.skills_for_difficulty("B06-M01", 0)[0].parameters.damage_a == 1.1, "skills return deep copy")
	var king := Catalog.boss()
	check(roundi(king.raw_stats.max_hp * 1.35 * 10 * data.progression.chapter_hp_factor) == king.d0_design_stats.max_hp, "boss authored HP arithmetic")
	check(roundi(king.raw_stats.damage * 1.35 * 10 * data.progression.chapter_damage_factor) == king.d0_design_stats.damage, "boss authored damage arithmetic")
	check(king.stat_contract.defense_per_difficulty == 2, "new boss defense is authored 2D")
	check(data.mechanics.tide.period_seconds == 16 and data.mechanics.tide.first_tutorial_low_seconds == 12, "authored fixed tide cycle")
	check(Catalog.room("L31").introduced_enemy_ids == ["B06-M01", "B06-M02", "B06-M03"], "L31 exact introductions")
	check(Catalog.room("L31").wave_count == null and Catalog.room("L36").wave_count == 3, "no invented wave counts")
	check(Catalog.enemy("B06-M13").skills["0"].parameters.warning_seconds == 1.5, "support channel tell retained")
	check(Catalog.enemy("B06-M06").skills["0"].parameters.active_mine_cap == 2, "mine budget not extra species")
	check(Catalog.enemy("B06-M17").unresolved_parameters.has("D2.reverse_damage_a"), "unwritten damage remains unresolved")
	check(king.phases[2].additional_tide_cycles == 0 and king.phases[1].hp_lower_ratio == .4, "boss P3 shares tide")
	var bad := data.duplicate(true)
	bad.biome_id = "B05"
	check(not Catalog.validate_data(bad).is_empty(), "reject foreign catalog")
	bad = data.duplicate(true)
	bad.enemies["B06-M01"].raw_stats.max_hp = -1
	check(not Catalog.validate_data(bad).is_empty(), "reject invalid raw stats")
	bad = data.duplicate(true)
	bad.rooms.L31.introduced_enemy_ids.append("B07-M01")
	check(not Catalog.validate_data(bad).is_empty(), "reject foreign room member")
	bad = data.duplicate(true)
	bad.rooms.L31.blueprint_percent_anchors.root_well = [101, 30]
	check(not Catalog.validate_data(bad).is_empty(), "reject anchor outside blueprint")
	bad = data.duplicate(true)
	bad.boss.skills[2].minimum_difficulty = 0
	check(not Catalog.validate_data(bad).is_empty(), "reject boss unlock corruption")
	bad = data.duplicate(true)
	bad.runtime_enabled = true
	check(not Catalog.validate_data(bad).is_empty(), "catalog cannot enable runtime")
	finish()

func finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("B06 content: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
