extends SceneTree
const Numbers = preload("res://scripts/combat/b06_enemy_numbers.gd")
const Content = preload("res://scripts/world/b06_content.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var first: Dictionary = Numbers.ordinary("B06-M01",26,0)
	check(first.max_hp == 4001 and first.damage == 399, "Lv26 frontline golden values: one final rounding")
	check(first.armor == 130 and first.magic_resist == 80, "tier-four role defense before D")
	check(Numbers.boss(0).max_hp == 23760 and Numbers.boss(0).damage == 491, "authored Boss D0 values")
	check(Numbers.boss(4).armor == 170 and Numbers.boss(4).magic_resist == 170, "B06 Boss adds 2D, not legacy 3D")
	check(Numbers.skill_damage(first,110) == 549, "ordinary skill tier applied once")
	check(Numbers.skill_damage(Numbers.boss(0),110) == 540, "boss does not inherit ordinary tier factor")
	check(Numbers.skill_damage(Numbers.boss(0),110,3) == 648, "boss phase applies once")
	for id: String in Content.enemy_ids():
		var previous_hp := 0
		var previous_damage := 0
		for difficulty in range(5):
			var normal: Dictionary = Numbers.ordinary(id,30,difficulty)
			var elite: Dictionary = Numbers.ordinary(id,30,difficulty,"elite")
			check(normal.max_hp > previous_hp and normal.damage > previous_damage, id + " strictly grows with D")
			check(normal.enemy_level == 30, "D never changes chapter level")
			check(elite.max_hp > normal.max_hp and elite.damage > normal.damage, "elite factor once")
			check(normal.recovery_seconds >= 0.45, "recovery floor")
			previous_hp = normal.max_hp
			previous_damage = normal.damage
		for level: int in Numbers.LEVELS:
			for difficulty in range(5):
				var resolved: Dictionary = Numbers.ordinary(id,level,difficulty)
				check(resolved.enemy_level == level and resolved.chapter == 6 and resolved.clan == "sea", "all fixed zone and difficulty identities")
				check(Numbers.skill_damage(resolved,0) == 0, "support/harmless packet remains zero")
				var saved: Dictionary = JSON.parse_string(JSON.stringify(resolved))
				check(Numbers.skill_damage(saved,100) == Numbers.skill_damage(resolved,100), "all profiles survive value serialization")
		var low: Dictionary = Numbers.ordinary(id,26,0)
		var high: Dictionary = Numbers.ordinary(id,30,0)
		check(high.max_hp > low.max_hp and high.damage > low.damage, "fixed B06 level growth")
	check(Numbers.ordinary("M01",26,0).is_empty(), "legacy ID is not rerouted")
	check(Numbers.ordinary("B07-M01",30,0).is_empty(), "future chapter unavailable")
	for level in [0,20,25,27,29,31,60]:
		check(Numbers.ordinary("B06-M01",level,0).is_empty(), "only authored chapter zone levels")
	check(Numbers.ordinary("B06-M01",26,5).is_empty(), "invalid D rejected")
	check(Numbers.ordinary("B06-M01",26,0,"boss").is_empty(), "normal cannot masquerade as boss")
	check(Numbers.skill_damage(first,-1) == -1, "negative coefficient rejected")
	check(Numbers.skill_damage(first,100,4) == -1, "unknown phase rejected")
	var copied: Dictionary = first.duplicate(true)
	copied.damage *= 10
	check(Numbers.skill_damage(copied,100) == -1, "already scaled forged profile rejected")
	copied = first.duplicate(true)
	copied.move_speed += 0.001
	check(Numbers.skill_damage(copied,100) == -1, "material motion change still rejected")
	copied = first.duplicate(true)
	copied.difficulty = 0.5
	check(Numbers.skill_damage(copied,100) == -1, "fractional difficulty rejected")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(first))
	check(Numbers.skill_damage(roundtrip,110) == 549, "JSON profile retains frozen identity")
	print("B06 enemy numbers: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 10: push_error(label)
