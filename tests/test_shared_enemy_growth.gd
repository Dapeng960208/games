extends Node
const E = preload("res://scripts/combat/enemy_profiles.gd")
const B = preload("res://scripts/combat/boss_profiles.gd")
const C = preload("res://scripts/world/world_catalog.gd")
const G = preload("res://scripts/combat/shared_enemy_growth.gd")
const Cal = preload("res://scripts/combat/enemy_calibration.gd")
const N = preload("res://scripts/combat/enemy_numerical_v2.gd")
const B05 = preload("res://scripts/combat/b05_enemy_numbers.gd")
const B06 = preload("res://scripts/combat/b06_enemy_numbers.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run_tests")
func run_tests() -> void:
	if not Game.profile_path.contains("test_shared_enemy_growth"): get_tree().quit(2); return
	var rows := []
	for chapter in range(1,7):
		var ids: Array = []
		if chapter<=4:
			for i in range(1,55):
				var id := "M%02d"%i
				if C.enemy(id).biome_id == "B%02d"%chapter: ids.append(id)
		else:
			for i in range(1,19): ids.append("B%02d-M%02d"%[chapter,i])
		for id: String in ids:
			for rank: String in ["normal","elite"]:
				for d in range(5):
					var previous := {}
					for level in [5*(chapter-1)+1,5*(chapter-1)+3,5*chapter]:
						var p := E.resolve(id,level,rank,2,d,Cal.archived(14))
						check(not p.is_empty(),id+" admitted")
						if p.is_empty(): continue
						for key: String in ["max_hp","damage","armor","magic_resist"]:
							if not previous.is_empty(): check(p[key]>previous[key],id+" level "+key)
							if d>0: check(p[key]>E.resolve(id,level,rank,2,d-1,Cal.archived(14))[key],id+" difficulty "+key)
						var actor := MineEnemy.new()
						actor.process_mode = Node.PROCESS_MODE_DISABLED
						actor.configure(p,{"static_actor":true,"reward_enabled":false})
						add_child(actor)
						check(actor.health.maximum==p.max_hp and actor.contact_damage==p.damage and actor.armor==p.armor and actor.magic_resist==p.magic_resist,id+" live actor fields")
						actor.free()
						previous=p
						var restored: Dictionary = JSON.parse_string(JSON.stringify(p))
						if chapter<5:
							var rebuilt := N.ordinary_profile(restored,d)
							for key: String in ["max_hp","damage","armor","magic_resist"]: check(rebuilt[key]==p[key],id+" regenerate "+key)
						else:
							var numbers = B05 if chapter==5 else B06
							check(numbers.skill_damage(restored,100)>0,id+" frozen JSON command")
						if true:
							var row := {"id":id,"chapter":chapter,"level":level,"difficulty":d,"rank":rank}
							for key: String in ["max_hp","damage","armor","magic_resist"]: row[key]=p[key]
							rows.append(row)
		for d in range(5):
			var p := B.resolve("BO%02d"%chapter,d,2,Cal.archived(14))
			var boss_row := {"id":"BO%02d"%chapter,"chapter":chapter,"level":5*chapter,"difficulty":d,"rank":"boss"}
			for key: String in ["max_hp","damage","armor","magic_resist"]: boss_row[key]=p[key]
			rows.append(boss_row)
			var old := B.resolve("BO%02d"%chapter,d,2,Cal.archived(13))
			for key: String in ["max_hp","damage","armor","magic_resist"]:
				check(p[key]==old[key],"Boss independent archived v2 "+key)
				if chapter>1: check(p[key]>B.resolve("BO%02d"%(chapter-1),d,2,Cal.archived(14))[key],"Boss chapter "+key)
				if d>0: check(p[key]>B.resolve("BO%02d"%chapter,d-1,2,Cal.archived(14))[key],"Boss difficulty "+key)
	# Fixed authored raw isolates chapter from roster variation.
	for archetype: String in G.ROLES:
		for rank: String in ["normal","elite"]:
			var raw := {"max_hp":60,"damage":14,"armor":0,"magic_resist":0}
			for chapter in range(2,7):
				var previous := G.stats(raw,archetype,"melee",25,chapter-1,4,rank)
				var next := G.stats(raw,archetype,"melee",25,chapter,4,rank)
				for key: String in ["max_hp","damage","armor","magic_resist"]: check(next[key]>previous[key],"isolated chapter "+key)
	var output := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty(): output = "user://test_b06_candidate/test_shared_enemy_growth"
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("shared_enemy_growth_examples.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  ")); file.close()
	for failure: String in failures.slice(0,20): printerr("FAIL "+failure)
	print("Shared growth: %d checks, %d failures"%[checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
