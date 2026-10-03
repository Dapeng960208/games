extends SceneTree
## Regression: legal default-precision JSON must preserve the pure numerical
## API as well as the production command path, without accepting altered stats.
const Numbers = preload("res://scripts/combat/b05_enemy_numbers.gd")
const Skills = preload("res://scripts/combat/b05_enemy_skills.gd")
const Content = preload("res://scripts/world/b05_content.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	for id: String in Content.enemy_ids():
		for level: int in Numbers.LEVELS:
			for difficulty in 5:
				for rank: String in ["normal", "elite"]:
					verify(Numbers.ordinary(id, level, difficulty, rank))
	for difficulty in 5: verify(Numbers.boss(difficulty))
	for message: String in failures: printerr("FAIL: "+message)
	print("B05 profile JSON: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func verify(profile: Dictionary) -> void:
	var label := "%s/%s/L%d/D%d" % [profile.enemy_id, profile.rank, profile.enemy_level, profile.difficulty]
	var restored: Dictionary = JSON.parse_string(JSON.stringify(profile))
	var raw := Numbers.skill_damage(profile, 110)
	check(raw > 0, label+" positive original")
	check(Numbers.skill_damage(restored, 110) == raw, label+" direct numerical JSON parity")
	var command := Skills.basic(restored, Vector2.ZERO, Vector2(100, 0))
	var frozen := Skills.freeze_damage(command, restored)
	check(not frozen.is_empty() and frozen.damage == Numbers.skill_damage(profile, 100) and frozen.damage > 0, label+" production frozen command parity")
	for key: String in ["max_hp", "damage", "armor", "magic_resist", "enemy_level", "difficulty", "move_speed", "recovery_seconds"]:
		if not restored.has(key): continue
		var changed := restored.duplicate(true)
		changed[key] = float(changed[key]) + (0.001 if key in ["move_speed", "recovery_seconds"] else 1.0)
		check(Numbers.skill_damage(changed, 110) == -1, label+" reject changed "+key)
	for key: String in ["move_speed", "recovery_seconds"]:
		if not restored.has(key): continue
		for value: Variant in [NAN, INF, "1.0", null]:
			var changed := restored.duplicate(true)
			changed[key] = value
			check(Numbers.skill_damage(changed, 110) == -1, label+" reject invalid "+key)
	var forged := restored.duplicate(true)
	forged.damage = int(forged.damage)+1
	check(Skills.freeze_damage(command, forged).is_empty(), label+" production rejects forged attack")
