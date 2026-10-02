extends SceneTree
## Focused roster/chapter/spawn acceptance; not S11 balance sampling.
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Numbers = preload("res://scripts/combat/enemy_numerical_v2.gd")
const Difficulty = preload("res://scripts/combat/enemy_difficulty.gd")
const Abilities = preload("res://scripts/combat/enemy_ability_catalog.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	check(Catalog.validate().is_empty(), "catalog validates: " + str(Catalog.validate()))
	check(Catalog.enemy_ids().size() == 54, "54 authored ordinary species")
	for biome_id: String in Catalog.biomes():
		var biome: Dictionary = Catalog.biomes()[biome_id]
		var chapter := int(biome_id.trim_prefix("B"))
		check(biome.enemy_ids.size() == 6 + chapter * 3, biome_id + " progressive roster")
		for d: int in 5:
			var observed: Dictionary = {}
			for room_id: String in biome.room_ids:
				for zone: int in 3:
					var plan := Profiles.encounter_plan(room_id, zone, d, 2)
					check(not plan.is_empty(), room_id + " has a real encounter plan")
					if plan.is_empty(): continue
					check(plan.concurrent_cap == 6 and plan.room_cap == 18, "concurrency remains 6/18")
					for wave: Array in plan.waves:
						for profile: Dictionary in wave:
							observed[profile.enemy_id] = true
							check(profile.biome_id == biome_id and profile.chapter == chapter, "no cross-biome stat or spawn mapping")
			for id: String in biome.enemy_ids:
				check(observed.has(id), "%s naturally represented in %s D%d" % [id,biome_id,d])
	for id: String in Catalog.enemy_ids():
		var chapter := int(str(Catalog.enemy(id).biome_id).trim_prefix("B"))
		check(Numbers.chapter_for_id(id) == chapter, id + " stable ID maps to authored chapter")
		for d: int in 5:
			var legacy := Profiles.resolve(id,chapter*5)
			var profile := Profiles.resolve(id,chapter*5,"normal",2,d)
			check(not profile.is_empty(), id + " numerical profile exists")
			if profile.is_empty(): continue
			check(profile.mechanic_tier == legacy.mechanic_tier, id + " difficulty does not alter level damage tier")
			check(profile.difficulty_mechanics.unlocked.size() == d, id + " exactly D extra skills unlocked")
			check(Numbers.ordinary_profile(profile,d) == profile, id + " numerical apply remains idempotent")
			var low := Difficulty.apply(legacy,d)
			check(low.difficulty_mechanics.unlocked.size() == d, id + " legacy route also unlocks difficulty skills")
			check(Difficulty.apply(low,d) == low, id + " legacy apply remains idempotent")
			for key: String in ["max_hp","damage","armor","magic_resist"]:
				check(profile[key] is int, id + " integer numeric field " + key)
	check(Profiles.resolve("M55",20,"normal",2,4).is_empty(), "unreleased species remains unavailable")
	check(Numbers.chapter_for_id("M00") == 0 and Numbers.chapter_for_id("M055") == 0, "unknown IDs fail closed")
	print("PROGRESSIVE_MONSTER_ROSTER: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
