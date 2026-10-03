extends Node
const E = preload("res://scripts/domain/combat/enemy_profiles.gd")
const B = preload("res://scripts/domain/combat/boss_profiles.gd")
const C = preload("res://scripts/domain/world/world_catalog.gd")
const Cal = preload("res://scripts/domain/combat/enemy_calibration.gd")
const N = preload("res://scripts/domain/combat/enemy_numbers.gd")
const S = preload("res://scripts/domain/combat/enemy_species_policy.gd")
const G = preload("res://scripts/domain/combat/shared_enemy_growth.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run_tests")
func run_tests() -> void:
	if not Game.profile_path.contains("test_enemy_species_profiles"): get_tree().quit(2); return
	check(Cal.current().version==14,"default remains archive14")
	check(Cal._species_candidate_enabled(PackedStringArray(["--enemy-species-candidate=15","--test-profile=user://test_species/profile.json"])),"candidate accepts isolated first-four test without changing chapter gate")
	check(not Cal._species_candidate_enabled(PackedStringArray(["--enemy-species-candidate=15","--test-profile=user://test_species/profile.json","--test-profile=user://profile.json"])),"duplicate profile rejects candidate")
	check(not Cal._species_candidate_enabled(PackedStringArray(["--enemy-species-candidate=15","--test-profile=user://test_species/../profile.json"])),"path traversal rejects candidate")
	check(Cal.numerical_version(Cal.archived(15))==4,"explicit archive15 profile v4")
	var records := []
	var boss_chapters := {}
	var archive14 := {}
	var baseline_file := FileAccess.open(AssetCatalog.resolve("res://docs/levels/b06/balance/archive14_b01_b06.csv"),FileAccess.READ)
	baseline_file.get_csv_line()
	while not baseline_file.eof_reached():
		var cells := baseline_file.get_csv_line()
		if cells.size()!=9: continue
		archive14["%s/%s/%s/%s"%[cells[0],cells[2],cells[3],cells[4]]]=[int(cells[5]),int(cells[6]),int(cells[7]),int(cells[8])]
	baseline_file.close()
	for id: String in C.enemy_ids():
		var species := S.definition(id)
		if species.is_empty(): continue
		var chapter := int(species.chapter)
		for level in [5*(chapter-1)+1,5*(chapter-1)+3,5*chapter]:
			for rank: String in ["normal","elite"]:
				for d in range(5):
					var p := E.resolve(id,level,rank,2,d,Cal.archived(15))
					check(not p.is_empty(),id+" admitted")
					if p.is_empty(): continue
					check(p.enemy_species_version==4 and p.primary_role==species.primary_role,id+" schema")
					check(p.ability_power>=0 and p.skill_base_power>=0,id+" integer AP/base")
					check(p.ability_power==0 and p.skill_base_power==0 if p.primary_role!="caster" else p.ability_power>p.damage and p.skill_base_power>0,id+" caster-only AP with low AD")
					check(p.crit_chance==(.35 if p.primary_role=="ranged" else .40 if p.primary_role=="assassin" else .25) and p.crit_multiplier==(2.25 if p.primary_role=="ranged" else 2.5 if p.primary_role=="assassin" else 2.0) and p.crit_policy_version==1,id+" global defaults plus species bonus once")
					var old := E.resolve(id,level,rank,2,d,Cal.archived(14))
					var golden: Array = archive14["%s/%d/%s/%d"%[id,level,rank,d]]
					for field_index in S.FIELDS.size(): check(old[S.FIELDS[field_index]]==golden[field_index],id+" archive14 golden "+S.FIELDS[field_index])
					check(not old.has("enemy_species_version") and not old.has("ability_power"),id+" archive14 schema unchanged")
					check(p.move_speed==old.move_speed and p.recovery_seconds==old.recovery_seconds,id+" behavior not yet changed")
					if chapter<=4:
						var restored: Dictionary = JSON.parse_string(JSON.stringify(p))
						var rebuilt := N.ordinary_profile(restored,d)
						for key: String in ["max_hp","damage","armor","magic_resist","ability_power","skill_base_power","crit_chance","crit_multiplier"]: check(rebuilt[key]==p[key],id+" JSON rebase "+key)
					var row := {"id":id,"chapter":chapter,"level":level,"rank":rank,"difficulty":d}
					for key: String in ["max_hp","damage","armor","magic_resist","ability_power","skill_base_power","crit_chance","crit_multiplier","primary_role"]: row[key]=p[key]
					records.append(row)
		if boss_chapters.has(chapter): continue
		boss_chapters[chapter]=true
		for d in range(5):
			var old := B.resolve("BO%02d"%chapter,d,2,Cal.archived(14))
			var next := B.resolve("BO%02d"%chapter,d,2,Cal.archived(15))
			var row := {"id":"BO%02d"%chapter,"chapter":chapter,"level":5*chapter,"rank":"boss","difficulty":d}
			for key: String in ["max_hp","damage","armor","magic_resist","ability_power","skill_base_power","crit_chance","crit_multiplier","primary_role"]: row[key]=next[key]
			records.append(row)
			check(next.crit_chance==.25 and next.crit_multiplier==2.0 and next.crit_policy_version==1 and next.primary_role=="boss","Boss global crit defaults")
			check(not old.has("crit_policy_version"),"Boss archive14 crit replay untouched")
			for key: String in ["max_hp","damage","armor","magic_resist"]: check(old[key]==next[key],"Boss untouched "+key)
	# Exact user tank multiplier, single-round integer output, no base1.5.
	var raw := {"max_hp":100,"damage":10,"armor":10,"magic_resist":10}
	var tank := S.stats("M08",raw,"tank",1,1,0,"normal")
	check(tank.get("max_hp")==2754 and tank.get("damage")==122 and tank.get("armor")==234 and tank.get("magic_resist")==130,"tank exact base1 HP2 AD1 defenses1.3")
	check(tank.get("ability_power")==0,"tank no AP")
	var output := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if not output.is_empty():
		var file := FileAccess.open(AssetCatalog.resolve(output.path_join("enemy_species_profile_candidate.json")),FileAccess.WRITE)
		file.store_string(JSON.stringify(records,"  "));file.close()
	for failure: String in failures.slice(0,20): printerr("FAIL "+failure)
	print("Species candidate profiles: %d rows, %d checks, %d failures"%[records.size(),checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
