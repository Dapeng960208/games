extends SceneTree
const Rewards = preload("res://scripts/world/room_rewards.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FIRST FOUR LOOT: " + label)

func _run() -> void:
	var ids: Array = Registry.equipment_ids()
	check(ids.size() == 60, "stable existing catalogue retained")
	for biome: String in ["B01", "B02", "B03", "B04"]:
		var own: Array = []
		for id: String in ids:
			if Registry.equipment(id).get("race_id") == biome: own.append(id)
		check(own.size() == 15, "each implemented faction owns fifteen gear templates")
		var rooms: Array = Catalog.biomes()[biome].room_ids.duplicate()
		rooms.append(Catalog.biomes()[biome].boss_id)
		for hero: String in ["CH01", "CH02", "CH03"]:
			check(not Rewards.race_equipment_pool(biome, hero).is_empty(), "all classes have faction drops")
			for room_id: String in rooms:
				for difficulty in 5:
					var previous_count := 0
					for seed_value in 8:
						var reward: Dictionary = Rewards.build(room_id, "full", hero, seed_value, "faction:test", [], [], [], difficulty)
						check(not reward.is_empty(), "every current task and boss has real completion loot")
						if reward.is_empty(): continue
						check(reward == Rewards.build(room_id, "full", hero, seed_value, "faction:test", [], [], [], difficulty), "retry cannot reroll loot")
						var drops: Array = reward.equipment
						check(drops.size() >= 1 and drops.size() <= 4, "reward count stays bounded")
						var unique: Dictionary = {}
						for drop: Dictionary in drops:
							var item: Dictionary = Registry.equipment(drop.equipment_id)
							check(item.get("race_id") == biome, "a level never drops another race")
							check(not unique.has(drop.equipment_id), "single payout has no duplicate template")
							unique[drop.equipment_id] = true
							check(int(drop.drop_level) >= 0 and int(drop.drop_level) <= 3, "prototype pre-enhancement bounds")
							if difficulty == 0: check(int(drop.drop_level) == 0, "ordinary remains unenhanced")
							if difficulty == 4: check(int(drop.drop_level) == 3, "extreme grants real +3 gear")
							check(str(drop.drop_id).length() <= 160, "transaction IDs fit save bounds")
						if difficulty > 0:
							var normal: Dictionary = Rewards.build(room_id, "full", hero, seed_value, "faction:test", [], [], [], 0)
							check(drops.size() >= normal.equipment.size(), "harder difficulty never reduces completion item count")
							check(int(reward.gold) >= int(normal.gold), "harder difficulty increases completion gold")
						previous_count = drops.size()
					check(previous_count > 0, "all seeded rolls produce faction gear")
			var exhausted: Dictionary = Rewards.build(rooms[0], "full", hero, 10, "owned:test", ids, [], [], 4)
			check(not exhausted.equipment.is_empty(), "exhausted collection still has faction loot for duplicate handling")
			for drop: Dictionary in exhausted.equipment:
				check(Registry.equipment(drop.equipment_id).get("race_id") == biome, "exhausted pool never falls back to another faction")
	check(Rewards.build("L01", "full", "CH01", 1, "bad", [], [], [], 5).is_empty(), "unsupported difficulty rejected")
	check(Rewards.build("B05", "full", "CH01", 1, "bad", [], [], [], 0).is_empty(), "TODO region cannot award free loot")
	check(Rewards.race_equipment_pool("B12", "CH01").is_empty(), "planned dragon region has no invented runtime drop pool")
	print("FIRST FOUR LOOT ", checks - failures, "/", checks)
	quit(1 if failures else 0)
