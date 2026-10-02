extends SceneTree
## S08 production profile factories; live scene/skill integration is separate.
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/combat/boss_profiles.gd")
const Numbers = preload("res://scripts/combat/enemy_numerical_v2.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	var elites := {}
	for number in range(1,25):
		var room := "L%02d" % number
		var chapter := 1 + int((number-1)/6)
		for difficulty in 5:
			for zone in 3:
				var expected: int = (chapter-1)*5+[1,3,5][zone]
				check(Profiles.encounter_level(room,zone,difficulty,2) == expected,"fixed challenge "+room+":"+str(zone)+":"+str(difficulty))
				var plan := Profiles.encounter_plan(room,zone,difficulty,2)
				check(not plan.is_empty(),"production V2 plan exists")
				if plan.is_empty(): continue
				var count := 0
				for wave: Array in plan.waves:
					check(wave.size() <= Profiles.ZONE_CAP,"finite concurrent natural batch")
					for actor: Dictionary in wave:
						count += 1
						check(actor.enemy_level == expected and actor.ruleset_version == 2 and actor.scale_version == 10,"actual wave carries fixed numerical actor")
						for key: String in ["max_hp","damage","armor","magic_resist"]: check(actor[key] is int,"actual actor integer "+key)
						var source := Profiles.resolve(actor.enemy_id,expected,actor.rank)
						var golden := Numbers.ordinary_profile(source,difficulty)
						for key: String in ["max_hp","damage","armor","magic_resist"]: check(actor[key] == golden[key],"factory applies chapter difficulty calibration once "+key)
						if actor.rank == "elite": elites[actor.enemy_id] = true
				check(count > 0 and count <= 100,"bounded full encounter")
				check(Profiles.encounter_plan(room,zone,difficulty) == Profiles.encounter_plan(room,zone,difficulty,1),"default factory stays legacy")
	check(elites.size() == 18,"18 actual natural elite identities")
	for id: String in Bosses.ids():
		for difficulty in 5:
			var actor := Bosses.resolve(id,difficulty,2)
			var golden := Numbers.boss_profile(Bosses.resolve(id,0),difficulty)
			check(not actor.is_empty() and Bosses.validate(actor).is_empty(),"valid production boss "+id)
			for key: String in ["max_hp","damage","armor","magic_resist","enemy_level"]: check(actor[key] == golden[key] and actor[key] is int,"boss frozen target "+key)
			check(actor.reinforcement_waves == Bosses.resolve(id,difficulty).reinforcement_waves,"boss finite reinforcements unchanged")
	check(Bosses.resolve("BO05",4,2).is_empty(),"future boss remains unimplemented")
	check(Profiles.resolve("M55",20,"normal",2,4).is_empty(),"future monster not fabricated")
	check(Numbers.chapter_levels(12,true).boss_level == 60 and not Numbers.chapter_levels(12,true).released,"future chapter formula only")
	print("Numerical production enemy profiles: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
