extends Node
const Calibration = preload("res://scripts/combat/enemy_calibration.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/combat/boss_profiles.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const Saves = preload("res://tests/test_numerical_versioned_saves.gd")
var failures: Array[String] = []
var checks := 0
class TestRoom extends MineRoom:
	func _ready() -> void: pass
	func _draw() -> void: pass
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _ready() -> void: call_deferred("run_tests")
func run_tests() -> void:
	if not Game.profile_path.contains("test_enemy_calibration_snapshot"): get_tree().quit(2); return
	Game.run = null
	var current := Calibration.current()
	check(Calibration.valid(current) and current.version == 1,"current archived identity configuration")
	check(Calibration.valid(JSON.parse_string(JSON.stringify(current))),"JSON numeric tokens validate against archive")
	check(Calibration.valid({}) and Calibration.factor({},1,"boss","hp") == 1.0,"missing oldV2 snapshot means permanent identity")
	for invalid: Variant in [null,[],{"version":1}, {"version":999,"chapters":{}}, {"version":INF,"chapters":{}}, {"version":1e30,"chapters":{}}]: check(not Calibration.valid(invalid),"malformed snapshot rejects")
	for factor: Variant in [-1,0,NAN,INF,11,"1",{}]:
		var bad := current.duplicate(true); bad.chapters.B01.boss.hp = factor
		check(not Calibration.valid(bad),"bad/changed factor rejects")
	var unknown := current.duplicate(true); unknown.chapters.B05 = {}
	check(not Calibration.valid(unknown),"unreleased chapter not generated")
	check(Game.new_profile() and Game.start_run({"expedition":true,"seed":960208}),"real current departure")
	if Game.run == null: get_tree().quit(1); return
	check(Game.run.enemy_calibration_snapshot == current and Game.run.receipt().enemy_calibration_snapshot == current,"departure freezes single authoritative snapshot")
	var frozen: Dictionary = Game.run.enemy_calibration_snapshot.duplicate(true)
	Numbers._parameters.enemy_calibration = {"version":999}
	Game.reload_profile()
	check(Game.run != null and Calibration.valid(Game.run.enemy_calibration_snapshot) and int(Game.run.enemy_calibration_snapshot.get("version",0)) == 1,"new global configuration cannot rewrite saved active snapshot")
	var room := TestRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.geometry_enabled = false
	for label: String in ["Enemies","Projectiles"]:
		var container := Node2D.new(); container.name = label; room.add_child(container)
	add_child(room)
	room.difficulty = 4; room.layout_id = "L01"
	var expected := Profiles.resolve("M01",1,"normal",2,4,frozen)
	var actor := room.spawn_enemy(Vector2(600,350),"M01",1,{"reward_enabled":false})
	check(is_instance_valid(actor) and actor.health.maximum == expected.max_hp and Calibration.valid(actor.profile.enemy_calibration_snapshot) and int(actor.profile.enemy_calibration_snapshot.get("version",0)) == 1,"live spawn reads frozen archive despite invalid current config")
	if is_instance_valid(actor): actor.free()
	var plan: Dictionary = room._encounter_plan(0)
	check(not plan.is_empty() and int(plan.waves[0][0].get("enemy_calibration_snapshot",{}).get("version",0)) == 1,"encounter plans share frozen coefficients")
	var boss := MineBoss.new(); boss.room = room
	check(boss.configure_boss("BO01",4,1,2,room.enemy_calibration()),"Boss config uses same snapshot")
	check(boss.profile.max_hp == Bosses.resolve("BO01",4,2,frozen).max_hp,"Boss final integer remains archived")
	boss.free()
	# Remove the new field from a fully valid V2 receipt to simulate S10 saves.
	var old: Dictionary = Game.run.receipt(); old.erase("enemy_calibration_snapshot")
	check(Game._save(Game.profile,old),"valid oldV2 receipt without calibration field saves")
	Game.reload_profile()
	check(Game.run.enemy_calibration_snapshot.is_empty(),"oldV2 restore never substitutes current map")
	actor = room.spawn_enemy(Vector2(600,350),"M01",1,{"reward_enabled":false})
	check(is_instance_valid(actor) and actor.health.maximum == expected.max_hp and actor.profile.enemy_calibration_snapshot.is_empty(),"actual oldV2 actor stays identity")
	if is_instance_valid(actor): actor.free()
	var bad_receipt: Dictionary = Game.run.receipt()
	bad_receipt.enemy_calibration_snapshot = frozen
	bad_receipt.expedition.enemy_calibration_snapshot = {"version":999}
	check(not Game._save(Game.profile,bad_receipt),"conflicting embedded calibration is rejected atomically")
	Game.reload_profile()
	check(Game.run.enemy_calibration_snapshot.is_empty(),"rejected conflict preserves old acknowledged receipt")
	check(not Game.finish_run("abandoned").is_empty(),"old identity run settles")
	check(not Game.start_run(),"new departure rejects unsupported current calibration")
	Numbers._parameters.enemy_calibration = frozen.duplicate(true)
	check(Game.start_run() and Calibration.valid(Game.run.enemy_calibration_snapshot) and int(Game.run.enemy_calibration_snapshot.get("version",0)) == 1,"restored current archive permits new departure")
	Game.finish_run("abandoned")
	room.free()
	await get_tree().process_frame
	print("Enemy calibration snapshot: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
