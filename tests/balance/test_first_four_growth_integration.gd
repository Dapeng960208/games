extends Node
## Integration endpoints, not a natural-play balance verdict. Uses legal native starters.
const Cal = preload("res://scripts/domain/combat/enemy_calibration.gd")
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/domain/combat/boss_profiles.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Saves = preload("res://tests/persistence/test_numerical_versioned_saves.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Damage = preload("res://scripts/domain/combat/damage_resolver.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
class TestRoom extends RoomController:
	func _ready() -> void: pass
	func _draw() -> void: pass
	func add_damage_text(_at: Vector2, _amount: float, _kind: StringName, _context: Dictionary = {}) -> void: pass
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run_tests")
func run_tests() -> void:
	if not Game.profile_path.contains("test_first_four_growth_integration"): get_tree().quit(2); return
	var room := TestRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.geometry_enabled = false
	for label: String in ["Enemies","Projectiles"]:
		var container := Node2D.new(); container.name=label; room.add_child(container)
	add_child(room)
	for hero: String in ["CH01","CH02","CH03"]:
		Game.run=null
		check(Game.new_profile() and Game.select_hero(hero) and Game.start_run({"expedition":true,"seed":960208}),hero+" actual fresh departure")
		if Game.run==null: continue
		check(Cal.valid(Game.run.enemy_calibration_snapshot) and int(Game.run.enemy_calibration_snapshot.version)==14,hero+" default archive14")
		check(Game.run.level==1 and Game.run.hp==Game.run.max_hp and Game.run.max_hp>0,hero+" normal low level HP")
		check(Game.run.resource==Game.run.stats.starting_resource and Game.run.resource>=0,hero+" normal starting resource")
		var equipped := 0
		for id: String in Game.run.loadout_snapshot.values():
			if id.is_empty(): continue
			equipped+=1
			check(Instances.can_equip(Game.run.equipment_snapshot[id],hero,1),hero+" legal starter "+id)
		check(equipped==6 and Game.run.loadout_snapshot.legs=="" and Game.run.loadout_snapshot.ring=="",hero+" six starter items retained")
		Game.run.hp = maxi(1,int(Game.run.max_hp)/2)
		Game.run.resource = maxi(0,int(Game.run.resource)-1)
		var injured_hp: int=Game.run.hp
		var injured_resource: int=Game.run.resource
		check(Game.save_expedition_checkpoint(Saves.runtime(hero,injured_hp,injured_resource,2)),hero+" injured checkpoint saves")
		var before := Game.run.receipt()
		Game.reload_profile()
		check(Game.run!=null and Game.run.receipt()==JSON.parse_string(JSON.stringify(before)),hero+" exact fresh receipt reload")
		check(Game.run.hp==injured_hp and Game.run.resource==injured_resource,hero+" injury and resource preserved exactly")
		rows.append({"hero":hero,"hp":Game.run.hp,"resource":Game.run.resource,"starter_count":equipped})
		check(not Game.finish_run("abandoned").is_empty(),hero+" settle")
	check(Game.start_run({"expedition":true,"seed":960208}),"endpoint run")
	check(Game.save_expedition_checkpoint(Saves.runtime("CH03",1234,321,2)),"endpoint injured checkpoint")
	for hero: String in ["CH01","CH02","CH03"]:
		for chapter in range(1,5):
			for level: int in [(chapter-1)*5+1,chapter*5]:
				var event := {"event_id":"first_four:%s:%d:%d"%[hero,chapter,level],"seed":54873,"source":"room","race_id":"B%02d"%chapter,"difficulty":0,"challenge_level":level,"power_type":"magic" if hero=="CH03" else "physical","hero_id":hero,"wish_slot":"weapon"}
				var result:=Acquisition.roll_event(event)
				check(result.ok and result.items.size()==1,"normal room equipment remains available")
				if result.ok:
					for item: Dictionary in result.items:
						rows.append({"hero":hero,"chapter":chapter,"hero_level":level,"item_level":item.item_level,"template_id":item.template_id,"immediately_equippable":Instances.can_equip(item,hero,level)})
						check(Instances.validate(item).is_empty() and Instances.can_equip(item,hero,maxi(level,int(item.item_level))),"actual legal chapter acquisition "+hero)
	for archive in range(1,15):
		var receipt := Game.run.receipt()
		receipt.enemy_calibration_snapshot=Cal.archived(archive)
		if receipt.expedition.has("enemy_calibration_snapshot"): receipt.expedition.enemy_calibration_snapshot=Cal.archived(archive)
		check(Game._save(Game.profile,receipt),"archive%d receipt accepted"%archive)
		Game.reload_profile()
		check(Cal.valid(Game.run.enemy_calibration_snapshot) and int(Game.run.enemy_calibration_snapshot.version)==archive,"archive%d restored unchanged"%archive)
		check(Game.run.hp==1234 and Game.run.resource==321,"archive%d injured state not upgraded or refilled"%archive)
		for chapter in range(1,5):
			room.layout_id="L%02d"%((chapter-1)*6+1)
			for d: int in [0,4]:
				room.difficulty=d
				for zone: int in [0,2]:
					var plan: Dictionary=room._encounter_plan(zone)
					check(not plan.is_empty(),"actual plan present")
					if plan.is_empty(): continue
					var entry: Dictionary=plan.waves[0][0]
					for rank: String in ["normal","elite"]:
						var level: int=(chapter-1)*5+[1,3,5][zone]
						var expected:=Profiles.resolve(entry.enemy_id,level,rank,2,d,Cal.archived(archive))
						var actor:=room.spawn_enemy(Vector2(600,350),entry.enemy_id,level,{"rank":rank,"reward_enabled":false,"static_actor":true})
						check(is_instance_valid(actor),"actual actor exists")
						if not is_instance_valid(actor): continue
						check(actor.health.maximum==expected.max_hp and actor.contact_damage==expected.damage and actor.armor==expected.armor and actor.magic_resist==expected.magic_resist,"archive%d B%d actor exact"%[archive,chapter])
						check(Cal.valid(actor.profile.enemy_calibration_snapshot) and int(actor.profile.enemy_calibration_snapshot.version)==archive,"actor snapshot unchanged")
						if archive==14:
							for kind: String in ["physical","magic"]:
								var defended:=Damage.resolve(100,kind,{}, {"armor":actor.armor,"magic_resist":actor.magic_resist,"ruleset_version":2})
								check(defended.damage>0 and defended.damage<100,"both actual defenses mitigate "+kind)
								var before_hp: int=actor.health.current
								check(actor.take_damage(100,&"skill",Vector2.ZERO,{"damage_type":kind}),"actual receive "+kind)
								check(before_hp-actor.health.current==defended.damage,"actual receiver uses archived defense "+kind)
							rows.append({"chapter":chapter,"difficulty":d,"level":level,"rank":rank,"enemy":entry.enemy_id,"hp":actor.health.maximum,"attack":actor.contact_damage,"armor":actor.armor,"magic_resist":actor.magic_resist})
						actor.free()
				var boss:=BossActor.new(); boss.room=room
				check(boss.configure_boss("BO%02d"%chapter,d,1,2,room.enemy_calibration()),"actual Boss configure")
				var expected_boss:=Bosses.resolve("BO%02d"%chapter,d,2,Cal.archived(archive))
				for key: String in ["max_hp","damage","armor","magic_resist"]: check(boss.profile[key]==expected_boss[key],"Boss archive replay "+key)
				boss.free()
	Game.finish_run("abandoned")
	room.free()
	var output:=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	var file:=FileAccess.open(AssetCatalog.resolve(output.path_join("first_four_growth.json")),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"  ")); file.close()
	print("First four growth integration: %d checks, %d failures"%[checks,failures.size()])
	for failure: String in failures.slice(0,30): printerr(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
