extends Node
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Saves = preload("res://tests/persistence/test_numerical_versioned_saves.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Loot = preload("res://scripts/domain/expedition/expedition_rewards.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
class FailMigrationStore extends ProfileStore:
	var saves := 0
	func save_document(value: Dictionary, receipt: Variant = null, initialized: bool = true) -> bool:
		saves += 1
		if saves == 2:
			last_error = "STORAGE_WRITE_FAILED"
			return false
		return super.save_document(value,receipt,initialized)
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func boundary(version: int = 2) -> Dictionary:
	return Saves.runtime(Game.run.hero_id,mini(711,int(Game.run.max_hp)),123 if version == 2 else 12.3,version)
func advance() -> bool:
	for offer: Dictionary in Game.expedition_snapshot().relic_offers:
		if not Game.choose_run_relic(offer.offer_id,"skip","",boundary()): return false
	var next: Dictionary = Game.expedition_snapshot().next_node
	return Game.choose_expedition_node(next.node_index,next.room_id) and Game.advance_expedition_node(boundary())
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	if not Game.profile_path.contains("test_numerical_runtime_lifecycle"): get_tree().quit(2); return
	Numbers.parameters()
	check(Numbers.default_ruleset() == 2,"checked-in S10 production activation is enabled")
	Game._test_ruleset_override = 0
	Game.run = null
	check(not Game._isolated_test_path("user://profile.json") and not Game._isolated_test_path("/tmp/mytest_profile.json"),"override refuses normal profile paths")
	for invalid: String in ["user://test_fixture/../profile.json","user://test_fixture/../../profile.json","user://test_fixture\\..\\profile.json","/tmp/test_fixture/./profile.json"]:
		check(not Game._isolated_test_path(invalid),"test override rejects traversal: "+invalid)
	check(Game._isolated_test_path("user://test_fixture/profile.json") and Game._isolated_test_path("/tmp/test_fixture.json"),"explicit isolated file/directory accepted")
	check(Game.new_profile() and Game.profile.ruleset_version == 2,"native new Game profile follows current default")
	var initial: Dictionary = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game.new_profile() and Game.profile == initial,"failed new profile preserves prior save")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.new_profile() and Game.profile == initial,"retry deterministic starter grant no duplicates")
	for hero: String in ["CH02","CH03","CH01"]:
		check(Game.select_hero(hero) and Game.last_loadout_missing.is_empty(),"native hero switch keeps legal starter preset "+hero)
		check(Game.start_run(),"native hero run starts")
		check(Game.run.ruleset_version() == 2 and Game.run.hp is int and Game.run.resource is int,"live starter stats use integer version")
		check(not Game.finish_run("abandoned").is_empty(),"native hero run settles")
	check(Game.start_run(),"current anonymous training route starts")
	var room: RoomController = RoomScene.instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	add_child(room)
	check(room.enemies.get_child_count() == 4,"authored starter wave count retained")
	for enemy: EnemyActor in room.enemies.get_children():
		check(enemy.profile.get("ruleset_version") == 2 and enemy.health.maximum is int and enemy.enemy_id == "M01","anonymous training waves receive current published integer prototype")
	await room.combat_audio.wait_for_cleanup()
	room.free()
	check(not Game.finish_run("abandoned").is_empty(),"training route exits")
	check(Game.start_run({"expedition":true,"seed":1735}),"new V2 expedition departure")
	check(advance(),"actual checkpoint enters first combat")
	check(Game.commit_expedition_completion(Game.run.id+":node:1:complete",boundary()),"completion grants canonical XP and reward")
	check(Game.hero_level() >= 2,"completed room produces real first level")
	get_tree().paused = true
	var hp: Variant = Game.run.hp
	var resource: Variant = Game.run.resource
	check(Game.allocate_hero_talent("mastery") and Game.run.hp <= hp and Game.run.resource == resource,"pause talent allocation cannot refill")
	get_tree().paused = false
	var pending: Dictionary = Game.run.expedition.pending_equipment.duplicate(true)
	Game.reload_profile()
	check(Game.run != null and Game.run.ruleset_version() == 2 and Loot.same(pending,Game.run.expedition.pending_equipment),"reward and growth checkpoint reload")
	check(not Game.finish_run("death").is_empty() and Game.profile.equipment.size() == 12,"death loses pending gear, retains starter identities")
	check(Game.start_run({"expedition":true,"seed":1735}),"next route begins after death")
	for index in 20:
		if not advance(): check(false,"route advance"); break
		if Game.run.expedition.phase == "safe": continue
		check(Game.commit_expedition_completion(Game.run.id+":node:"+str(Game.run.expedition.node_index)+":complete",boundary()),"route settlement")
		var node: Dictionary = Game.expedition_snapshot().node
		if node.early_extraction or node.role == "boss":
			pending = Game.run.expedition.pending_equipment.duplicate(true)
			check(not Game.finish_run("extracted").is_empty() and Game.profile.equipment.size() == 12+pending.size(),"extraction banks real unique rewards")
			break
	if Game.run != null: check(false,"route reaches valid extraction"); Game.finish_run("abandoned")
	# Economy setup is declared synthetic; integration coverage is not S11 earning pace.
	var economy: Dictionary = Game.profile.duplicate(true)
	economy.hero_xp.CH01 = Growth.thresholds()[4]
	economy.permanent_gold = 10000
	economy.materials = {"forge":100,"race:B01":100}
	check(Game._commit_profile(economy),"explicit isolated economic fixture")
	var request := {"template_id":"EQ01","rarity":"green","power_type":"physical","item_level":1}
	var owned_before: int = Game.profile.equipment.size()
	var first: Dictionary = Game.purchase_equipment_v2(request,"runtime:purchase:one")
	var second: Dictionary = Game.purchase_equipment_v2(request,"runtime:purchase:two")
	check(first.ok and second.ok and Game.profile.equipment.size() == owned_before+2,"duplicate template purchases preserve independent instances")
	var copies: Array[String] = []
	for id: String in Game.profile.equipment:
		if not economy.equipment.has(id): copies.append(id)
	check(copies.size() == 2 and copies[0] != copies[1],"new IDs distinct")
	if copies.size() == 2:
		check(Game.equip_item(copies[0]) and Game.upgrade_equipment(copies[0],"runtime:enhance"),"equip and forge instance")
		var frozen: Dictionary = Game.profile.duplicate(true)
		Game.reload_profile()
		check(Loot.same(Game.profile,frozen) and Game.profile.equipment[copies[0]].enhancement_rank == 1 and Game.profile.equipment[copies[1]].enhancement_rank == 0,"reload keeps independent ranks and paid history")
	await _legacy_transition()
	print("Numerical runtime lifecycle: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func _legacy_transition() -> void:
	Numbers._parameters.runtime_enabled = false
	check(Game.new_profile() and not Game.profile.has("ruleset_version"),"isolated historical profile constructed")
	check(Game.start_run({"expedition":true,"seed":1735}),"historical expedition starts")
	var runtime := boundary(1)
	check(Game.save_expedition_checkpoint(runtime),"historical damaged checkpoint")
	Numbers._parameters.runtime_enabled = true
	for index in 2:
		Game.reload_profile()
		check(Game.run != null and Game.run.ruleset_version() == 1 and Game.run.resource == 12.3,"default switch does not mutate active oldrun")
	var failed_store := FailMigrationStore.new(Game.profile_path)
	failed_store.load_document()
	Game._store = failed_store
	check(not Game.finish_run("abandoned").is_empty() and Game.run == null and int(Game.profile.get("ruleset_version",1)) == 1,"migration-only storage failure keeps acknowledged old settlement")
	var finished_runs: int = Game.profile.total_runs
	Game.reload_profile()
	check(Game.profile.ruleset_version == 2 and Game.profile.has("numerical_migration") and Game.profile.total_runs == finished_runs,"load retries camp migration without replaying old settlement")
	var migrated: Dictionary = Game.profile.duplicate(true)
	Game.reload_profile()
	check(Loot.same(Game.profile,migrated) and Game.run == null,"automatic migration idempotent reload")
	check(Game.start_demo("CH03",0,{},false) and Game.run.ruleset_version() == 2 and Game.run.level == 8,"V2 disposable demo uses correct growth and magic preset")
	check(not Game.finish_run("abandoned").is_empty() and Loot.same(Game.profile,migrated),"demo restores permanent camp unchanged")
	await get_tree().process_frame
