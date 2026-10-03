extends Node
## Isolated candidate integration: synthetic combat boundaries, real transaction
## and reload APIs. This is deliberately not a natural-play/balance claim.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Routes = preload("res://scripts/domain/world/route_generator.gd")
const Enemies = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Rewards = preload("res://scripts/domain/world/room_rewards.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Loot = preload("res://scripts/domain/expedition/expedition_rewards.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func boundary() -> Dictionary:
	var player: Dictionary = {"cooldowns":{},"passive_count":0,"walk_distance":0.0,"aim_direction":[1.0,0.0],"cast_serial":0}
	for key: String in Snapshot.SKILLS: player.cooldowns[key] = 0.0
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.0
	var equipment: Dictionary = {"room_id":"","room_low_shield_used":false,"room_first_kill_used":false}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: equipment[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 0.0
	equipment.dash_time = -100.0
	equipment.delayed_shield_at = -1.0
	var modifiers: Dictionary = {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 1.0 if key.ends_with("_scale") else 0.0
	equipment["adapter"] = {"clock":0.0,"movement_time":0.0,"event_serial":0,"modifiers":modifiers}
	return {"snapshot_version":1,"mode":"safe_boundary","hero_id":Game.run.hero_id,"hp":Game.run.hp,"resource":Game.run.resource,
		"ruleset_version":2,"scale_version":10,"resource_regen_remainder":Game.run.resource_regen_remainder,"resource_decay_remainder":Game.run.resource_decay_remainder,
		"player":player,"equipment":equipment,"status":{"clock":0.0,"shock_cooldown":0.0,"states":{},"guards":{},"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}}

func _ready() -> void:
	for args: PackedStringArray in [PackedStringArray(["--candidate-b05"]),PackedStringArray(["--candidate-b05","--test-profile=user://profile.json"]),PackedStringArray(["--candidate-b05","--test-profile=user://test_b05_candidate/../profile.json"]),PackedStringArray(["--candidate-b05","--test-profile=user://test_b05_candidate/a.json","--test-profile=user://profile.json"])]:
		check(not Rules._candidate_arguments_valid(args),"candidate rejects missing/unsafe/duplicate save flags")
	check(int(Rules.parameters().implemented_chapters) == 4,"shipped gate stays four")
	check(not Catalog.biomes().has("B06"),"B06 remains disabled")
	if not Rules.b05_candidate_enabled():
		check(Catalog.room_ids().size()==24 and Catalog.enemy_ids().size()==54 and Catalog.biomes().size()==4 and Catalog.bosses().size()==4,"strict closed catalog")
		check(not Routes.generate_single_biome("B05",51,[],20).valid and not Routes.generate_single_biome("B01",51,[],21).valid,"strict closed departure")
		finish(); return
	check(Game.profile_path.begins_with("user://test_b05_candidate/"),"isolated candidate save")
	check(Catalog.validate().is_empty(),"candidate catalog validates: "+str(Catalog.validate()))
	check(Catalog.room_ids().size()==30 and Catalog.enemy_ids().size()==72 and Catalog.biomes().size()==5 and Catalog.bosses().size()==5,"30/72/5/5 candidate catalog")
	var seen := {}
	for room_id: String in Catalog.biomes().B05.room_ids:
		for difficulty in range(5):
			var waves := 0
			for zone in range(3):
				var plan := Enemies.encounter_plan(room_id,zone,difficulty,2)
				if room_id == "L25" and zone == 2: check(plan.is_empty(),"L25 no third wave"); continue
				check(not plan.is_empty(),"B05 production plan "+room_id)
				if plan.is_empty(): continue
				check(plan.enemy_level==Catalog.room(room_id).enemy_level and plan.enemy_level==Rewards.challenge_level(room_id,zone),"room-fixed enemy/drop level")
				waves += plan.wave_count
				for wave: Array in plan.waves:
					check(wave.size()<=6 and plan.room_cap==18,"shared six/eighteen capacity")
					for actor: Dictionary in wave:
						if difficulty==0: seen[actor.enemy_id]=true
			check(waves==(2 if room_id=="L25" else 3),"finite room wave count")
	check(seen.size()==18,"all eighteen species naturally planned at D0")
	for version in [1,2]:
		var route := Routes.generate("B04",54873,[],20) if version==1 else Routes.generate_single_biome("B04",54873,[],20)
		check(route.valid,"legacy route contract still valid")
		for node: Dictionary in route.nodes: check(node.biome_id!="B05","old route never silently gains fifth region")
	for level in [20,21,23,25]:
		var route := Routes.generate_single_biome("B05",54873,[],level)
		check(route.nodes[1].room_id=="L25" and route.template_ids.slice(0,6)==["L25","L26","L27","L28","L29","L30"],"ordered teaching introduces all species before repeats")
		check(route.valid and route.nodes.size()==12 and route.nodes[-1].room_id=="BO05","candidate twelve-station departure")
		check(Routes.choose(JSON.parse_string(JSON.stringify(route)),1,route.nodes[1].room_id).valid,"candidate choice survives JSON")
	check(not Routes.generate_single_biome("B06",51,[],25).valid and not Routes.generate_single_biome("B05",51,[],26).valid,"future route blocked")
	for hero: String in ["CH01","CH02","CH03"]: traverse(hero)
	finish()
func traverse(hero: String) -> void:
	check(Game.new_profile() and Game.select_hero(hero),"candidate fresh class "+hero)
	check(not Game.start_run({"expedition":true,"biome_id":"B05","seed":54873}),"BO04 prerequisite enforced")
	var fixture: Dictionary=Game.profile.duplicate(true)
	fixture.bosses=["BO01","BO02","BO03","BO04"]
	fixture.hero_xp[hero]=Growth.thresholds()[24 if hero == "CH03" else 19]
	check(Game._commit_profile(fixture),"synthetic B04-completed profile")
	check(preload("res://scripts/app/expedition_controller.gd").unlocked_biomes(Game.profile).has("B05"),"candidate B05 visible in departure picker")
	check(Game.start_run({"expedition":true,"biome_id":"B05","seed":54873}),"B04 to B05 departure "+Game.last_error)
	if Game.run==null: return
	var route_id: String=Game.run.id
	var visited := {}
	for index in range(1,Game.run.expedition.route.nodes.size()):
		for offer: Dictionary in Game.expedition_snapshot().relic_offers:
			check(Game.choose_run_relic(offer.offer_id,"skip","",boundary()),"resolve relic offer")
		var next: Dictionary=Game.expedition_snapshot().next_node
		check(Game.choose_expedition_node(index,next.room_id) and Game.advance_expedition_node(boundary()),"candidate node entry "+str(index)+" "+Game.last_error)
		if int(Game.run.expedition.node_index)!=index: break
		if next.role=="supply": continue
		visited[next.room_id]=true
		if next.role!="boss":
			var monster: String=Catalog.room(next.room_id).introduced_enemy_ids[0]
			var kill_id := "b05-natural:"+str(index)
			check(Game.record_expedition_kill_reward(kill_id,monster),"natural kill receipt")
			var kills_before: Dictionary=Game.run.receipt()
			check(Game.record_expedition_kill_reward(kill_id,monster) and Game.run.receipt()==kills_before,"natural kill duplicate protection")
			check(Game.record_expedition_kill_reward("b05-summon:"+str(index),monster,false,true) and Game.run.receipt()==kills_before,"summon gives no rewards")
		var event_id: String=route_id+":node:"+str(index)+":complete"
		check(Game.commit_expedition_completion(event_id,boundary()),"canonical room settlement "+Game.last_error)
		var before: Dictionary=Game.run.receipt()
		check(Game.commit_expedition_completion(event_id,boundary()) and Game.run.receipt()==before,"duplicate completion cannot mint loot")
		check(not Game.run.expedition.pending_equipment.is_empty(),"room equipment remains pending")
		Game.reload_profile()
		check(Game.run!=null and Game.run.id==route_id,"candidate checkpoint disk reload "+Game.last_error)
		if Game.run==null:return
	check(visited.size()==7 and visited.has("BO05"),"six rooms and BO05 reached")
	var pending: Array=Game.run.expedition.pending_equipment.keys()
	var result: Dictionary=Game.finish_run("extracted")
	check(result.get("outcome")=="extracted" and "BO05" in Game.profile.bosses,"BO05 extraction banks boss record")
	for id: String in pending: check(Game.profile.equipment.has(id),"extraction banks candidate gear")
	check(Game.finish_run("extracted")==result,"duplicate extraction returns frozen result")
	Game.reload_profile()
	check(Game.run==null and Game.profile.total_runs==1 and "BO05" in Game.profile.bosses,"banked candidate profile reload")
func finish() -> void:
	print("B05 candidate traversal: %d checks; failures=%s" % [checks,failures])
	get_tree().quit(0 if failures.is_empty() else 1)
