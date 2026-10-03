extends Node
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/domain/combat/boss_profiles.gd")
const Calibration = preload("res://scripts/domain/combat/enemy_calibration.gd")
const Policy = preload("res://scripts/domain/combat/monster_role_policy.gd")
const Numerical = preload("res://scripts/domain/combat/enemy_numbers.gd")
const B05 = preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
const B06 = preload("res://scripts/levels/b06/combat/enemy_numbers.gd")
const S05 = preload("res://scripts/levels/b05/combat/enemy_skills.gd")
const S06 = preload("res://scripts/levels/b06/combat/enemy_skills.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
var checks := 0
var count := 0
var actors := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run_tests")
func run_tests() -> void:
	if not Game.profile_path.contains("test_monster_role_policy"): get_tree().quit(2); return
	check(Calibration.valid(Calibration.current()) and Calibration.current().version == 14,"new archive14 default")
	for archive in range(15): check(Calibration.valid(Calibration.archived(archive)),"preserve archive%d"%archive)
	for chapter in range(1,7):
		var ids: Array = []
		if chapter <= 4:
			for number in range(1,55):
				var id := "M%02d"%number
				if Catalog.enemy(id).biome_id == "B%02d"%chapter: ids.append(id)
		else:
			for index in range(1,19): ids.append("B%02d-M%02d"%[chapter,index])
		for id: String in ids:
			for level in [5*(chapter-1)+1,5*(chapter-1)+3,5*chapter]:
				for rank: String in ["normal","elite"]:
					var previous: Dictionary = {}
					for difficulty in 5:
						var old: Dictionary = resolve(id,level,rank,difficulty,Calibration.archived(1))
						var current: Dictionary = resolve(id,level,rank,difficulty,Calibration.archived(13))
						verify(old,current,chapter)
						if not previous.is_empty():
							for key: String in Policy.FIELDS: check(current[key]>previous[key],id+" D monotonic "+key)
						previous = current
						if difficulty in [0,4] and level in [5*(chapter-1)+1,5*chapter]:
							var actor := EnemyActor.new()
							actor.process_mode = Node.PROCESS_MODE_DISABLED
							actor.configure(current,{"static_actor":true,"reward_enabled":false})
							add_child(actor)
							check(actor.health.maximum==current.max_hp and actor.contact_damage==current.damage and actor.armor==current.armor and actor.magic_resist==current.magic_resist,id+" actual actor stats")
							actor.free()
							actors += 1
		for difficulty in 5:
			var boss: Dictionary = Bosses.resolve("BO%02d"%chapter,difficulty,2,Calibration.archived(13))
			check(not boss.is_empty() and not boss.has("monster_role_policy_version") and boss.get("boss_progression_version")==2,"boss separate progression")
	check(Policy.role("support","ranged")=="support" and Policy.role("tank","artillery")=="tank","identity beats geometry")
	check(Policy.role("missing","ranged").is_empty(),"unknown role rejected")
	for message: String in failures.slice(0,30): printerr("FAIL "+message)
	print("Monster role policy: %d configurations, %d actor endpoints, %d checks, %d failures"%[count,actors,checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
func resolve(id: String, level: int, rank: String, difficulty: int, calibration: Dictionary) -> Dictionary:
	if id.begins_with("B05"): return S05.profile(id,level,difficulty,rank,calibration)
	if id.begins_with("B06"): return S06.profile(id,level,difficulty,rank,calibration)
	return Profiles.resolve(id,level,rank,2,difficulty,calibration)
func verify(old: Dictionary, current: Dictionary, chapter: int) -> void:
	count += 1
	var label: String = str(current.get("enemy_id","missing"))
	check(not old.is_empty() and not current.is_empty(),label+" admitted")
	if old.is_empty() or current.is_empty(): return
	var expected := Policy.apply(old,str(old.archetype),str(old.role))
	for key: String in Policy.FIELDS: check(current[key]==expected[key],label+" one base and specialization "+key)
	for key: String in ["move_speed","attack_range","recovery_seconds","attack_parameters"]: check(current.get(key)==old.get(key),label+" unchanged "+key)
	check(not old.has("monster_role_policy_version") and current.monster_role_policy_version==2,label+" immutable old version")
	check(Policy.apply(current,str(current.archetype),str(current.role)).is_empty(),label+" refuses double scale")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(current))
	var old_restored: Dictionary = JSON.parse_string(JSON.stringify(old))
	if chapter >= 5:
		var numbers = B05 if chapter==5 else B06
		var skills = S05 if chapter==5 else S06
		check(numbers.skill_damage(restored,110)==numbers.skill_damage(current,110),label+" current JSON frozen damage")
		check(numbers.skill_damage(old_restored,110)==numbers.skill_damage(old,110),label+" legacy JSON frozen damage")
		var command: Dictionary = skills.freeze_damage(skills.basic(restored,Vector2.ZERO,Vector2(100,0)),restored)
		check(not command.is_empty() and command.damage==numbers.skill_damage(current,100),label+" actual command")
		var forged := restored.duplicate(true); forged.damage+=1
		check(numbers.skill_damage(forged,110)==-1,label+" forged damage rejected")
	else:
		var rebuilt := Numerical.ordinary_profile(restored,int(current.difficulty))
		for key: String in Policy.FIELDS: check(rebuilt.get(key)==current[key],label+" regeneration not compounded "+key)
		var command := Numerical.command({"kind":"melee","damage_multiplier":1.0},restored)
		check(command.damage>0 and Numerical.command(command,restored)==command,label+" command frozen once")
