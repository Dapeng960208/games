extends SceneTree
const Numbers = preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
const Content = preload("res://scripts/levels/b05/world/content.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var first: Dictionary = legacy_ordinary("B05-M01",21,0)
	check(first.max_hp == 3273 and first.damage == 347, "Lv21 frontline golden values: one final rounding")
	check(first.armor == 130 and first.magic_resist == 80, "tier-four role defense before D")
	check(legacy_boss(0).max_hp == 19980 and legacy_boss(0).damage == 428, "authored Boss D0 values")
	check(legacy_boss(4).armor == 160 and legacy_boss(4).magic_resist == 160, "B05 Boss adds 2D, not legacy 3D")
	check(Numbers.skill_damage(first,110) == 477, "ordinary skill tier applied once")
	check(Numbers.skill_damage(legacy_boss(0),110) == 471, "boss does not inherit ordinary tier factor")
	check(Numbers.skill_damage(legacy_boss(0),110,3) == 565, "boss phase applies once")
	for id: String in Content.enemy_ids():
		var previous_hp := 0
		var previous_damage := 0
		for difficulty in range(5):
			var normal: Dictionary = legacy_ordinary(id,25,difficulty)
			var elite: Dictionary = legacy_ordinary(id,25,difficulty,"elite")
			check(normal.max_hp > previous_hp and normal.damage > previous_damage, id + " strictly grows with D")
			check(normal.enemy_level == 25, "D never changes chapter level")
			check(elite.max_hp > normal.max_hp and elite.damage > normal.damage, "elite factor once")
			check(normal.recovery_seconds >= 0.45, "recovery floor")
			previous_hp = normal.max_hp
			previous_damage = normal.damage
		var low: Dictionary = legacy_ordinary(id,21,0)
		var high: Dictionary = legacy_ordinary(id,25,0)
		check(high.max_hp > low.max_hp and high.damage > low.damage, "fixed B05 level growth")
	check(legacy_ordinary("M01",21,0).is_empty(), "legacy ID is not rerouted")
	check(legacy_ordinary("B06-M01",25,0).is_empty(), "future chapter unavailable")
	for level in [0,20,22,26,60]:
		check(legacy_ordinary("B05-M01",level,0).is_empty(), "only authored chapter zone levels")
	check(legacy_ordinary("B05-M01",21,5).is_empty(), "invalid D rejected")
	check(legacy_ordinary("B05-M01",21,0,"boss").is_empty(), "normal cannot masquerade as boss")
	check(Numbers.skill_damage(first,-1) == -1, "negative coefficient rejected")
	check(Numbers.skill_damage(first,100,4) == -1, "unknown phase rejected")
	var copied: Dictionary = first.duplicate(true)
	copied.damage *= 10
	check(Numbers.skill_damage(copied,100) == -1, "already scaled forged profile rejected")
	copied = first.duplicate(true)
	copied.difficulty = 0.5
	check(Numbers.skill_damage(copied,100) == -1, "fractional difficulty rejected")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(first))
	check(Numbers.skill_damage(roundtrip,110) == 477, "JSON profile retains frozen identity")
	print("B05 enemy numbers: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

# Immutable authored-v1 contract; the new policy has its own regression suite.
func legacy_ordinary(id: String, level: int, difficulty: int, rank: String = "normal") -> Dictionary:
	return Numbers.ordinary(id,level,difficulty,rank,{},1)
func legacy_boss(difficulty: int) -> Dictionary:
	return Numbers.boss(difficulty,{},1)
