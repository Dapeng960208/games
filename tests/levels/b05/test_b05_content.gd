extends SceneTree
## Run in an isolated project without autoloads. Pure authored-data checks only.
const Catalog = preload("res://scripts/levels/b05/world/content.gd")
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
	check(Catalog.enemy("M01").is_empty() and Catalog.enemy("B06-M01").is_empty(), "reject foreign and old IDs")
	check(Catalog.room("L24").is_empty(), "reject other chapter rooms")
	for difficulty in range(5):
		check(Catalog.skills_for_difficulty("B05-M01", difficulty).size() == (1 if difficulty < 2 else 2 if difficulty < 4 else 3), "cumulative difficulty gates")
	check(Catalog.skills_for_difficulty("B05-M01", 5).is_empty(), "reject unsupported difficulty")
	var enemy := Catalog.enemy("B05-M01")
	enemy.raw_stats.max_hp = 1
	check(Catalog.enemy("B05-M01").raw_stats.max_hp == 78, "enemy returns deep copy")
	var room := Catalog.room("BO05")
	room.blueprint_percent_anchors.root_wells[0][0] = 99
	check(Catalog.room("BO05").blueprint_percent_anchors.root_wells[0][0] == 25, "room returns deep copy")
	var skills := Catalog.skills_for_difficulty("B05-M01", 4)
	skills[0].parameters.damage_a = 99
	check(Catalog.skills_for_difficulty("B05-M01", 0)[0].parameters.damage_a == 1.1, "skills return deep copy")
	var king := Catalog.boss()
	check(roundi(king.raw_stats.max_hp * 1.35 * 10 * data.progression.chapter_hp_factor) == king.d0_design_stats.max_hp, "boss authored HP arithmetic")
	check(roundi(king.raw_stats.damage * 1.35 * 10 * data.progression.chapter_damage_factor) == king.d0_design_stats.damage, "boss authored damage arithmetic")
	check(king.stat_contract.defense_per_difficulty == 2, "new boss defense is authored 2D")
	check(data.mechanics.root_network.reconnection_lock_seconds == 12 and data.mechanics.root_network.destroyed_well_respawn_seconds == null, "reconnection lock does not invent respawn")
	check(Catalog.room("L25").introduced_enemy_ids == ["B05-M01", "B05-M02", "B05-M04"], "L25 source introduction exception preserved")
	check(Catalog.room("L25").wave_count == 2 and Catalog.room("L30").wave_count == 3, "only explicit wave counts frozen")
	var bad := data.duplicate(true)
	bad.biome_id = "B06"
	check(not Catalog.validate_data(bad).is_empty(), "reject foreign catalog")
	bad = data.duplicate(true)
	bad.enemies["B05-M01"].raw_stats.max_hp = -1
	check(not Catalog.validate_data(bad).is_empty(), "reject invalid raw stats")
	bad = data.duplicate(true)
	bad.rooms.L25.introduced_enemy_ids.append("B06-M01")
	check(not Catalog.validate_data(bad).is_empty(), "reject foreign room member")
	bad = data.duplicate(true)
	bad.rooms.L25.blueprint_percent_anchors.root_well = [101, 30]
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
	print("B05 content: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
