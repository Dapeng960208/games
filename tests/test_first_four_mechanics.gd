extends Node
## One focused acceptance of the actual prepared expedition objective path.
const RoomScene = preload("res://scenes/room.tscn")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const FirstFour = preload("res://scripts/world/first_four_objectives.gd")
const GraveOrc = preload("res://scripts/world/first_four_grave_orc.gd")
const Layouts = preload("res://scripts/world/room_layouts.gd")
const BossLayouts = preload("res://scripts/world/boss_layouts.gd")
const Quests = preload("res://scripts/ui/quest_localization.gd")
var checks := 0
var failures := 0
var room: MineRoom

func _ready() -> void:
	call_deferred("run_checks")
	get_tree().create_timer(60.0).timeout.connect(func(): push_error("First-four acceptance timed out"); get_tree().quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+description)

func fixture(id: String) -> void:
	if not is_instance_valid(room):
		room = RoomScene.instantiate()
		room.process_mode = Node.PROCESS_MODE_DISABLED
		get_tree().root.add_child(room)
	var definition: Dictionary = Catalog.room(id)
	var prepared: Dictionary = room.prepare_expedition_node({"room_id":id,"role":"branch","biome_id":definition.biome_id,"node_index":1,"node_count":6,"difficulty":0,"seed":146556,"phase":"combat","expedition":true})
	check(bool(prepared.get("valid",false)),id+" actual expedition layout prepares")
	if not bool(prepared.get("valid",false)): return
	room.apply_prepared_expedition_node(prepared)
	room.spawn_enabled = false
	room.set_input_blocked(false)
	room.release_gate = false
	for actor: Node in room.enemies.get_children():
		if str(actor.get("actor_kind"))!="objective": actor.free()
	room.player.position = room.layout.entry

func actor(id: String, at: Vector2) -> MineEnemy:
	var result: MineEnemy = room.spawn_enemy(at,id,1,{"reward_enabled":false,"zone_index":-1})
	check(is_instance_valid(result),id+" actual enemy allocates")
	return result

func kill(enemy: MineEnemy) -> void:
	enemy.take_damage(1000000.0,&"primary",Vector2.RIGHT,{"damage_type":"true"})

func run_checks() -> void:
	AudioServer.set_bus_mute(0,true)
	if not Game.profile_path.contains("test_first_four_mechanics"):
		push_error("First-four acceptance requires isolated profile")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(),"isolated real player run starts")
	for index: int in range(1,25):
		var id: String = "L%02d" % index
		fixture(id)
		check(room.layout.static_obstructions.is_empty() and room.layout.static_obstruction_kinds.is_empty(),id+" removes old rectangular terrain from art and collision")
		check(room.obstructions==room.layout.obstructions and room.obstructions.size()==room.layout.prop_instances.size(),id+" only visible small props block movement")
		var host: Node2D = room.objectives
		var count: int = int(Catalog.room(id).expedition_objective_count)
		check(host.module.get_script()==FirstFour and host.required_count==count and host.elements.size()==count and host.status().rules=="first_four_combat_v1" and not host.finished,id+" uses new objectives and actual count")
		var safe := true
		var points: Array[Vector2] = []
		for item: Dictionary in host.elements.values():
			safe = safe and Layouts.clear_for_actor(room.layout,item.position,35.0)
			for previous: Vector2 in points: safe = safe and previous.distance_to(item.position)>=180.0
			points.append(item.position)
			for danger: Dictionary in room.layout.get("hazard_zones",[]): safe = safe and not danger.get("rect",Rect2()).grow(64.0).has_point(item.position)
		check(safe,id+" objectives have distinct clear feet outside danger routes")
	for id: String in ["BO01","BO02","BO03","BO04"]:
		var arena: Dictionary = BossLayouts.build(id,146556)
		check(arena.obstructions.is_empty() and arena.static_obstructions.is_empty() and arena.static_obstruction_kinds.is_empty(),id+" removes rectangular boss pools and pits")
	await _test_open_ground()
	_test_conduits()
	_test_nests()
	_test_graves()
	_test_barricades()
	Words.set_locale("en")
	check(room.objectives.status().text==room.objectives.status().text_en and Quests.action_for_status(room.objectives.status(),true)==room.objectives.status().text_en,"actual objective status uses complete native English")
	Words.set_locale("zh")
	room.expedition_context = {}
	room.objectives.configure(room,room.layout,"branch")
	check(room.objectives.module.get_script()!=FirstFour and room.objectives.status().rules=="legacy_non_expedition","historical fixture remains explicitly legacy")
	check(await room.combat_audio.wait_for_cleanup(),"focused room audio cleans up")
	room.free()
	Game.finish_run("abandoned")
	await get_tree().process_frame
	print("FIRST FOUR MECHANICS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _test_open_ground() -> void:
	fixture("L02")
	# This crosses the exact former 709 x 775 pit in the supplied screenshot.
	var from := Vector2(600,900)
	var to := Vector2(1300,900)
	check(room.valid_ground(Vector2(946,941),Balance.PLAYER_RADIUS),"former large pit center is actual walkable ground")
	check(room.move_actor(from,to-from,Balance.PLAYER_RADIUS).is_equal_approx(to),"actor crosses the removed pit without an invisible collider")
	if DisplayServer.get_name()=="headless": return
	get_window().size = Vector2i(1280,720)
	room.player.position = Vector2(946,941)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	for _frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	check(get_viewport().get_texture().get_image().save_png("res://artifacts/open_courtyard_L02.png")==OK,"capture actual continuous courtyard floor")

func _test_conduits() -> void:
	fixture("L01")
	var host: Node2D = room.objectives
	var item: Dictionary = host.element("solar_conduit_0")
	var construct: MineEnemy = actor("M01",item.position+Vector2(70,0))
	construct.status.grant_guard(40.0,20.0,"acceptance_solar",construct.health.maximum)
	room.player.position = item.position
	room.interact()
	host.tick(.8)
	var progress: float = item.progress
	room.player.position += Vector2(130,0)
	host.tick(1.0)
	check(progress>0 and is_equal_approx(item.progress,progress),"actual E conduit charging retains progress when leaving")
	room.player.position = item.position
	get_tree().paused = true
	host.tick(8.0)
	check(is_equal_approx(item.progress,progress),"pause freezes actual objective charging")
	get_tree().paused = false
	host.tick(.8)
	check(item.done and construct.status.shield()==0.0 and construct.biome_counter_status().weakpoint,"charged conduit removes real construct shield and opens weakpoint")
	var last: Dictionary = host.element("solar_conduit_1")
	room.player.position = last.position
	room.interact()
	host.tick(1.6)
	check(host.finished and construct.is_alive() and not room.objective_complete and host.hazards.is_empty(),"conduit completion still requires combat and never damages player")

func _test_nests() -> void:
	fixture("L07")
	var host: Node2D = room.objectives
	host.tick(8.0)
	var adds: Array = host.combat_actors()
	var valid := not adds.is_empty() and adds.size()<=4
	for enemy: MineEnemy in adds: valid = valid and bool(enemy.get_meta("first_four_brood_add",false)) and not enemy.reward_enabled
	check(valid,"actual nests hatch bounded same-clan enemies without rewards")
	for item: Dictionary in host.elements.values(): room.player.original_hit(item.target_actor,1000000.0,&"primary")
	var before: int = host.combat_actors().size()
	host.tick(40.0)
	check(host.finished and host.completed_count==host.required_count and host.combat_actors().size()==before,"actual basic attacks destroy every nest and permanently stop adds")

func _test_graves() -> void:
	fixture("L13")
	var host: Node2D = room.objectives
	var leaf: RefCounted = host.module.leaf
	var grave: Dictionary = host.element("grave_seal_0")
	var far: Vector2 = room.layout.exit
	for candidate: Vector2 in [Vector2(160,160),Vector2(1760,160),Vector2(160,920),Vector2(1760,920)]:
		if leaf._nearest_grave(candidate).is_empty() and room.valid_ground(candidate,24): far=candidate; break
	var far_enemy: MineEnemy = actor("M19",far)
	kill(far_enemy)
	check(leaf.pending.is_empty(),"far-side death cannot revive outside the 320 px grave radius")
	var original: MineEnemy = actor("M19",grave.position+Vector2(70,0))
	kill(original)
	host.notify_enemy_death(original)
	check(leaf.pending.size()==1,"actual death bridge warns once for a nearby eligible enemy")
	var gold: int = Game.run.gold
	var xp: int = Game.run.hero_xp_gained
	host.tick(1.6)
	var revived: MineEnemy
	for enemy: MineEnemy in host.combat_actors():
		if bool(enemy.get_meta("grave_revived",false)): revived=enemy
	check(is_instance_valid(revived) and leaf.revivals==1 and not revived.reward_enabled,"warning creates a real finite revival with rewards disabled")
	if is_instance_valid(revived): kill(revived)
	check(leaf.pending.is_empty() and Game.run.gold==gold and Game.run.hero_xp_gained==xp,"revived enemy cannot revive again or award coins/experience")
	for index: int in 4:
		var next: MineEnemy = actor("M19",grave.position+Vector2(70,0))
		kill(next)
		host.tick(1.6)
	check(leaf.revivals==GraveOrc.MAX_REVIVALS and leaf.pending.is_empty(),"actual room has a permanent four-revival budget")
	for item: Dictionary in host.elements.values():
		room.player.position = item.position
		room.interact()
		host.tick(1.6)
	check(host.completed_count==host.required_count and not host.finished,"sealing graves still requires clearing the street")
	for enemy: MineEnemy in host.combat_actors(): kill(enemy)
	host.tick(.01)
	check(host.finished and leaf.pending.is_empty() and Game.run.gold==gold and Game.run.hero_xp_gained==xp,"all sealed graves plus real enemy clearance completes without reward farming")

func _test_barricades() -> void:
	fixture("L19")
	var host: Node2D = room.objectives
	var item: Dictionary = host.element("war_barricade_0")
	var orc: MineEnemy = actor("M28",item.position+Vector2(100,0))
	var from: Vector2 = item.position-Vector2(140,0)
	var to: Vector2 = item.position+Vector2(140,0)
	get_tree().paused = true
	room.notify_enemy_charge(orc,from,to)
	check(not item.done,"paused charge notification cannot destroy a barricade")
	get_tree().paused = false
	room.notify_enemy_charge(orc,from+Vector2(0,100),to+Vector2(0,100))
	check(not item.done,"charge whose segment misses a barricade cannot destroy it")
	room.notify_enemy_charge(orc,from,to)
	check(item.done and not item.target_actor.is_alive() and orc.biome_counter_status().effective_armor==0.0,"actual room charge bridge destroys target and strips real nearby orc armor")
	var completed: int = host.completed_count
	room.notify_enemy_charge(orc,from,to)
	check(host.completed_count==completed,"duplicate charge receipt cannot complete twice")
	for remaining: Dictionary in host.elements.values():
		if not remaining.done: room.player.original_hit(remaining.target_actor,1000000.0,&"primary")
	check(host.finished and host.completed_count==host.required_count and orc.is_alive(),"ordinary attacks provide real completion fallback while combat remains required")
