extends Node
## S08 real configure/_ready paths with production factory values; only room
## generation/rendering/AI ticks are omitted, never actor initialization.
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/domain/combat/boss_profiles.gd")
const Target = preload("res://scripts/domain/combat/enemy_numbers.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Hive = preload("res://scripts/levels/shared/first_four_construct_hive.gd")
const Objectives = preload("res://scripts/gameplay/world/room_objectives.gd")
const Difficulty = preload("res://scripts/domain/combat/enemy_difficulty.gd")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
var checks := 0
var failures: Array[String] = []
class ProfileRoom extends RoomController:
	func _ready() -> void: pass
	func _draw() -> void: pass
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	if not Game.profile_path.contains("test_numerical_enemy_actors"):
		get_tree().quit(2)
		return
	Game.run = RunSession.new()
	Game.run.hero_id = "CH01"
	Game.run.level = 1
	Game.run.stats = Resolver.resolve("CH01",1,{}, {},2)
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	var room := ProfileRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.geometry_enabled = false
	room.spawn_enabled = false
	for node_name: String in ["Enemies","Projectiles"]:
		var container := Node2D.new()
		container.name = node_name
		room.add_child(container)
	add_child(room)
	room.player = SalvagerPlayer.new()
	room.player.room = room
	room.add_child(room.player)
	room.enemy_skills = EnemySkillRuntime.new()
	room.add_child(room.enemy_skills)
	room.enemy_skills.configure(room)
	for number in range(1,37):
		var id := "M%02d" % number
		var level: int = Target.encounter_level(Target.chapter_for_id(id),2)
		for rank: String in ["normal","elite"]:
			for difficulty in 5:
				var profile := Profiles.resolve(id,level,rank,2,difficulty)
				var actor := EnemyActor.new()
				actor.room = room
				actor.training_ai_disabled = true
				actor.configure(profile,{"reward_enabled":false})
				room.enemies.add_child(actor)
				check(actor.health.maximum == profile.max_hp and actor.health.maximum is int,"real enemy integer HP initialized "+id+rank)
				check(actor.contact_damage == profile.damage and actor.armor == profile.armor and actor.magic_resist == profile.magic_resist,"real enemy A/defense uses profile once")
				check(actor.status.ruleset_version == 2 and actor.enemy_level == level,"real enemy version/fixed chapter")
				actor.free()
	for id: String in Bosses.ids():
		for difficulty in 5:
			var profile := Bosses.resolve(id,difficulty,2)
			var boss := BossActor.new()
			boss.room = room
			boss.training_ai_disabled = true
			boss.configure(profile)
			room.enemies.add_child(boss)
			check(boss.health.maximum == profile.max_hp and boss.health.maximum is int,"real Boss integer HP initialized")
			check(boss.contact_damage == profile.damage and boss.status.ruleset_version == 2 and boss.enemy_level == Target.chapter_levels(Target.chapter_for_id(id)).boss_level,"real Boss fixed actor values")
			if id == "BO01": check(boss.status.shield() == Numbers.integer(int(profile.max_hp)*.22),"initial Boss shield uses new HP once")
			var before: Dictionary = boss.profile.duplicate(true)
			Game.run.level = 20
			boss.configure(profile)
			check(boss.profile == before and boss.health.maximum == profile.max_hp,"hero level cannot rescale encounter")
			Game.run.level = 1
			boss.free()
	# Exercise the live central spawn seam, including already-scaled encounter
	# profiles and owner summons; actor tests above alone cannot catch double D.
	for chapter in range(1,5):
		room.layout_id = "L%02d" % ((chapter-1)*6+1)
		for difficulty in 5:
			room.difficulty = difficulty
			for zone in 3:
				var plan: Dictionary = room._encounter_plan(zone)
				check(not plan.is_empty(),"real room selects V2 encounter plan")
				var entry: Dictionary = plan.waves[0][0]
				var expected := Profiles.resolve(entry.enemy_id,(chapter-1)*5+[1,3,5][zone],entry.rank,2,difficulty)
				for supplied: bool in [false,true]:
					var options: Dictionary = {"reward_enabled":false,"rank":entry.rank}
					if supplied: options.profile = entry
					var spawned := room.spawn_enemy(Vector2(600,350),entry.enemy_id,expected.enemy_level,options)
					check(is_instance_valid(spawned),"actual spawn succeeds")
					if not is_instance_valid(spawned): continue
					check(spawned.health.maximum == expected.max_hp and spawned.contact_damage == expected.damage and spawned.armor == expected.armor,"central spawn applies each factor once")
					check(spawned.enemy_level == expected.enemy_level and spawned.status.ruleset_version == 2,"central spawn preserves fixed level/version")
					var summon := room.spawn_enemy_summon(spawned,entry.enemy_id,Vector2(680,350))
					check(is_instance_valid(summon),"actual owner summon succeeds")
					if is_instance_valid(summon):
						var summon_expected := Profiles.resolve(entry.enemy_id,expected.enemy_level,"normal",2,difficulty)
						check(summon.health.maximum == summon_expected.max_hp and summon.contact_damage == summon_expected.damage and summon.enemy_level == expected.enemy_level,"summon inherits fixed level with single D")
						check(not summon.reward_enabled and summon.owner_enemy.get_ref() == spawned,"summon no-loot ownership unchanged")
						summon.free()
					spawned.free()
			var live_boss := BossActor.new()
			live_boss.room = room
			check(live_boss.configure_boss("BO%02d" % chapter,difficulty,123,room.enemy_ruleset()),"room-facing Boss configuration accepts V2")
			room.enemies.add_child(live_boss)
			check(live_boss.enemy_level == chapter*5 and live_boss.health.maximum == Bosses.resolve("BO%02d" % chapter,difficulty,2).max_hp,"room-facing Boss uses fixed level and D once")
			live_boss.free()
	var objective_host := Objectives.new()
	objective_host.room = room
	var hive := Hive.new()
	hive.host = objective_host
	room.layout_id = "L07"
	for difficulty in 5:
		room.difficulty = difficulty
		for zone in 3: check(hive._brood_level(zone) == [6,8,10][zone],"actual brood spawn level independent of difficulty")
	Game.run.stats = Resolver.resolve("CH01",1,{}, {},1)
	check(room.enemy_ruleset() == 1,"legacy adventure keeps legacy actor seam")
	room.difficulty = 4
	var old := room.spawn_enemy(Vector2(600,350),"M01",9,{"reward_enabled":false})
	var old_expected := Difficulty.apply(Profiles.resolve("M01",9),4)
	check(old.health.maximum == old_expected.max_hp and old.contact_damage == old_expected.damage and old.status.ruleset_version == 1,"actual old adventure spawn unchanged")
	old.free()
	check(hive._brood_level(1) == 15,"old adventure brood ladder unchanged")
	objective_host.free()
	room.queue_free()
	Game.run = null
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(.2).timeout
	print("Numerical real enemy actors: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
