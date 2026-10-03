extends Node
const Traversal = preload("res://scripts/world/b06_candidate_traversal.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("B06 TRAVERSAL: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b06_candidate_traversal"): get_tree().quit(2); return
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":26008}),"isolated initial profile")
	var initial_profile := JSON.stringify(Game.profile)
	var initial_expedition := JSON.stringify(Game.run.expedition)
	var room = load("res://scenes/room.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await get_tree().process_frame
	var route := Traversal.new()
	check(route.configure(room,0,26008) and route.start(),"explicit candidate session")
	check(route.checkpoint().is_empty(),"live encounter cannot masquerade as clear-boundary save")
	for index in 7:
		check(route.node_index == index,"correct candidate route order")
		check(not route.advance(index),"cannot advance unfinished room")
		if room.layout_id == "BO06":
			room._boss_actor.take_damage(1000000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats})
			await get_tree().process_frame
		else:
			for zone in room.encounter_zones.size():
				room.player.position = room.encounter_zones[zone].center
				for step in 5:
					room._update_encounters(4)
					for actor in room.enemies.get_children(): actor.free()
		room._tick_expedition(0)
		check(room.objective_complete and not room.objective_rewarded,"clear is finite and economy-blocked")
		room.enemy_skills.reset_room()
		for projectile in room.projectiles.get_children(): projectile.free()
		room.player.position = room.exit_position
		var saved := route.checkpoint()
		check(not saved.is_empty(),"clear checkpoint accepted "+route.last_error)
		if not saved.is_empty():
			var json: Dictionary = JSON.parse_string(JSON.stringify(saved))
			check(route.restore_checkpoint(json),"JSON checkpoint roundtrip "+room.layout_id)
			check(typeof(route.node_index) == TYPE_INT,"node identity canonical after JSON")
			var corrupt := json.duplicate(true)
			corrupt.node_index = 1.5
			check(not route.restore_checkpoint(corrupt) and route.node_index == index,"invalid index restore is atomic")
		check(room.nearby_interaction().get("kind") == "b06_candidate_next","real exit interaction selects candidate path")
		room.input_blocked = false
		room.release_gate = false
		room.interact()
		check(route.finished if index == 6 else route.node_index == index+1,"actual F traverses without production transaction")
		check(not route.advance(index),"duplicate old exit cannot advance twice")
	check(route.finished,"seven-room candidate completes")
	check(JSON.stringify(Game.run.expedition) == initial_expedition,"no production expedition mutation")
	check(JSON.stringify(Game.profile) == initial_profile,"no permanent unlock or reward mutation")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free()
	Game.run = null
	print("B06_CANDIDATE_TRAVERSAL checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
