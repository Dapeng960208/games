extends SceneTree
## Entire finite encounter plans use real body texture/region identities.
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Art = preload("res://scripts/presentation/monsters/enemy_art.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENEMY VARIANT BUDGET FAIL: " + label)

func _initialize() -> void:
	seed(41827)
	var expected_roll: int = randi()
	seed(41827)
	for serial: int in 20:
		Art.variant_index_for("M01", serial, "L01", 41827)
	check(randi() == expected_roll, "appearance allocation never consumes gameplay RNG")
	var worst: float = 0.0
	var worst_case: Dictionary = {}
	var cases: int = 0
	for identity: String in Catalog.enemy_ids():
		var keys: Dictionary = {}
		var count: int = Art.variant_count(identity)
		check(count >= (7 if int(identity.trim_prefix("M")) > 27 else 8), identity + " retains its painted role variants")
		for index: int in count:
			var entry: Dictionary = Art.variant_entry_for(identity, index)
			var key: String = Art.appearance_key(entry)
			check(not entry.is_empty() and not keys.has(key), identity + " true texture/region " + str(index) + " is unique")
			keys[key] = true
		check(not Art.skill_icon_for(identity).is_empty(), identity + " has its own measured skill illustration")
	for id: String in Catalog.room_ids():
		for difficulty: int in 5:
			var counts: Dictionary = {}
			var appearances: Dictionary = {}
			var total: int = 0
			for zone: int in 3:
				for wave: Array in Profiles.encounter_plan(id, zone, difficulty).get("waves", []):
					for member: Dictionary in wave:
						var identity: String = str(member.enemy_id)
						var serial: int = int(counts.get(identity, 0))
						var index: int = Art.variant_index_for(identity, serial, id, 41827)
						var entry: Dictionary = Art.variant_entry_for(identity, index)
						appearances[Art.appearance_key(entry)] = true
						counts[identity] = serial + 1
						total += 1
			cases += 1
			var repeat: float = float(total - appearances.size()) / maxf(1.0, total)
			check(total > 0 and repeat < .3, "%s D%d cumulative all waves %.4f repeats" % [id, difficulty, repeat])
			if worst_case.is_empty() or repeat > worst:
				worst = repeat
				worst_case = {"room":id, "difficulty":difficulty, "total":total, "distinct":appearances.size(), "repeat":repeat, "counts":counts}
	check(cases == 120, "24 ordinary rooms times five difficulties are covered")
	print("ENEMY VARIANT BUDGET: %d checks, %d failures; cases=%d worst=%s" % [checks, failures, cases, JSON.stringify(worst_case)])
	quit(0 if failures == 0 else 1)
