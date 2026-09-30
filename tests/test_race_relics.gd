extends SceneTree
## Real room hit pipelines plus bounded policy checks; isolated test profile.
const Relics = preload("res://scripts/combat/class_relics.gd")
const Race = preload("res://scripts/combat/race_relics.gd")
var game: Node
var room: Node2D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run_checks")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RACE RELICS FAIL: "+label)

func fixture(hero: String, biome: String, relics: Array, rank: int = 1) -> void:
	if is_instance_valid(room): room.free()
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = load("res://scripts/combat/stat_resolver.gd").resolve(hero,8,{},{})
	game.run.stats.crit_chance = 0.0
	game.run.stats.relic_levels = {"RL01":rank,"RL02":rank,"RL03":rank}
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 50.0
	game.run.shield = 0.0
	game.run.relics.assign(relics)
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	for enemy in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(430,350)
	room.player.aim_direction = Vector2.RIGHT
	room.expedition_context = {"biome_id":biome} if not biome.is_empty() else {}
	room.release_gate = false
	room.input_blocked = false

func target(at: Vector2) -> Node2D:
	var enemy: Node2D = room.spawn_enemy(at)
	enemy.health.reset(10000.0)
	enemy.armor = 0.0
	enemy.magic_resist = 0.0
	enemy.training_ai_disabled = true
	return enemy

func event(id: String, original: bool = true) -> Dictionary:
	return {"root_event_id":id,"attack_id":id,"original_basic":original,"equipment_eligible":original,"proc_depth":0 if original else 1}

func hit(enemy: Node2D, serial: int, prefix: String) -> void:
	game.run.shots = serial
	room.strike_area(room.player.position,110,1,&"primary","",0,Vector2.RIGHT,100,true,event(prefix+str(serial)))

func triplet(hero: String, biome: String, rank: int) -> float:
	fixture(hero,biome,["arc"],rank)
	var enemy := target(Vector2(480,350))
	for index in range(1,4): hit(enemy,index,hero+biome)
	return float(game.run.resource)

func solar_checks() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		for rank in [1,2]:
			var baseline := triplet(hero,"",rank)
			var themed := triplet(hero,"B01",rank)
			check(is_equal_approx(themed,baseline+1),hero+" rank "+str(rank)+" three real original hit roots add exactly one resource")
	fixture("CH01","B01",["arc"])
	var enemy := target(Vector2(480,350))
	for index in range(1,4): hit(enemy,index,"solar:")
	var value: float = game.run.resource
	check(Race.confirmed_original_hit(room,event("solar:3")) == 0 and game.run.resource == value,"duplicate root cannot count or refund twice")
	room.elapsed = 1.0
	for index in range(4,7): Race.confirmed_original_hit(room,event("solar:"+str(index)))
	check(game.run.resource == value,"third hit inside three-second ICD cannot refund")
	room.elapsed = 3.0
	for index in range(7,10): Race.confirmed_original_hit(room,event("solar:"+str(index)))
	check(game.run.resource == value+1,"third root at ICD boundary refunds one")
	var count: int = room.get_meta(Race.STATE_META).hits
	check(Race.confirmed_original_hit(room,event("child",false)) == 0 and int(room.get_meta(Race.STATE_META).hits) == count,"derived packet cannot enter hit counter or proc")
	game.run.relics.clear()
	check(Race.confirmed_original_hit(room,event("unowned")) == 0 and int(room.get_meta(Race.STATE_META).hits) == count,"unowned arc has zero race effect")
	Relics.reset_room(room)
	check(not room.has_meta(Race.STATE_META),"room reset removes hit roots and ICD ownership")

func duration_checks() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		for rank in [1,2]:
			fixture(hero,"B02",["ember"],rank)
			var enemy := target(Vector2(480,350))
			hit(enemy,1,"dot:"+hero+str(rank))
			var state: Dictionary = enemy.status.states.get(Relics.native_status(hero),{})
			check(not state.is_empty() and is_equal_approx(float(state.get("remaining",0)),Relics.native_status_duration(hero,rank)*1.2),hero+" rank "+str(rank)+" real original native DOT gains twenty percent lifetime")
			var power: float = room.player.stat("ability_power",28) if hero == "CH03" else room.player.attack_power()
			check(is_equal_approx(float(state.get("power",0)),Relics.native_status_power(hero,power,rank)),"race lifetime does not alter rank DOT power")
	fixture("CH01","B02",[])
	check(Relics.native_status_duration("CH01",2,room) == 5.0,"unowned ember has baseline duration")
	var enemy := target(Vector2(480,350))
	game.run.relics.assign(["ember"])
	room.resolve_direct_hit(enemy,1,&"secondary","burn",0,Vector2.RIGHT,event("skill",false))
	check(is_equal_approx(enemy.status.states.burn.remaining,3.0),"skill status is not promoted into original relic lifetime bonus")

func guard_checks() -> void:
	for rank in [1,2]:
		fixture("CH01","B03",["arc"],rank)
		var enemy := target(Vector2(480,350))
		game.run.hp = game.run.max_hp*.349
		hit(enemy,3,"guard:"+str(rank))
		var expected: float = game.run.max_hp*.12*(1.5 if rank == 2 else 1.0)*1.2
		check(is_equal_approx(game.run.shield,expected),"rank "+str(rank)+" low-HP original arc shield gains twenty percent")
		hit(enemy,6,"guard:refresh:"+str(rank))
		check(is_equal_approx(game.run.shield,expected),"repeated arc refresh cannot stack the guard amount")
	fixture("CH01","B03",["arc"])
	game.run.hp = game.run.max_hp*.35
	check(Race.guard_multiplier(room) == 1.0,"exactly thirty-five percent HP does not satisfy below threshold")
	game.run.hp = 1
	game.run.relics.clear()
	check(Race.guard_multiplier(room) == 1.0,"unowned arc cannot amplify guard")

func split_checks() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		for rank in [1,2]:
			fixture(hero,"B04",["split"],rank)
			var main := target(Vector2(480,350))
			var extra := target(Vector2(520,365))
			var power: float = room.player.stat("ability_power",28) if hero == "CH03" else room.player.attack_power()
			var coefficient := .4*(1.5 if rank == 2 else 1.0)
			Relics.apply_reserved(room,{"split":coefficient},event("split:"+hero+str(rank)),main.position,main,Vector2.RIGHT)
			if hero == "CH02": room.projectiles.get_child(0).hit(extra)
			check(is_equal_approx(10000-extra.health.current,power*coefficient*1.1),hero+" rank "+str(rank)+" real near split packet gains ten percent")
			check(not bool(extra.last_damage_context.equipment_eligible) and int(extra.last_damage_context.proc_depth) == 1,"themed split remains one non-recursive derived packet")
	fixture("CH01","B04",["split"])
	check(Race.split_multiplier(room,room.player.position+Vector2(160,0)) == 1.1 and Race.split_multiplier(room,room.player.position+Vector2(161,0)) == 1.0,"close-range bonus uses real one-hundred-sixty radius boundary")
	game.run.relics.clear()
	check(Race.split_multiplier(room,room.player.position) == 1.0,"unowned split has zero race bonus")

func display_checks() -> void:
	Words.set_locale("zh_CN")
	for biome: String in ["B01","B02","B03","B04"]:
		for hero: String in ["CH01","CH02","CH03"]:
			for id: String in ["RL01","RL02","RL03"]:
				var info: Dictionary = Relics.display(hero,id,2,biome)
				check(info.name.begins_with(Race.PREFIX[biome]) and info.name.ends_with(" II") and not info.material.is_empty(),"race name/material preserves hero and upgrade identity")
				check(info.texture is AtlasTexture and info.rank == 2 and info.id == id,"race icon uses a real cached atlas while stable relic ID/rank remain intact")
				check(load("res://scripts/ui/equipment_art.gd").source_path(str(info.art_item)) == "res://assets/generated/equipment/storybook_first4_race_gear_v1.png","themed relic uses active canonical race artwork rather than legacy category art")
	Words.set_locale("en")
	var chinese := RegEx.new()
	chinese.compile("[一-龥]")
	for biome: String in ["B01","B02","B03","B04"]:
		var info: Dictionary = Relics.display("CH01","arc" if biome != "B02" else "ember",2,biome)
		check(chinese.search(str(info.name)+str(info.description)) == null,"English race relic publishes translated class mechanic/material/trait")
	Words.set_locale("zh_CN")
	fixture("CH01","",["arc"])
	check(Race.biome_id(room).is_empty() and Relics.display("CH01","arc").name == "回震砧","legacy rooms preserve legacy class display")
	var hud: Control = load("res://scripts/ui/hud.gd").new()
	hud.room = room
	root.add_child(hud)
	room.expedition_context = {"biome_id":"B03"}
	check(hud._relic_info("arc").biome_id == "B03" and hud._relic_info("arc").description.contains("35%"),"live HUD details use actual room biome and published low-HP rule")
	hud.free()

func run_checks() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_race_relics"):
		push_error("Refusing race relic tests without isolated profile")
		quit(2)
		return
	for action in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(game.new_profile() and game.start_run(),"isolated race relic run")
	var gold_before: int = game.run.gold
	solar_checks()
	duration_checks()
	guard_checks()
	split_checks()
	display_checks()
	check(game.run.gold == gold_before,"traits never change gold or rewards")
	room.free()
	game.finish_run("abandoned")
	print("RACE_RELICS_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
