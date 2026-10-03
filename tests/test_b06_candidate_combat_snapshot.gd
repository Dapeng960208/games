extends Node
const Snap = preload("res://scripts/world/b06_candidate_combat_snapshot.gd")
const Skills = preload("res://scripts/combat/b06_enemy_skills.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures+=1; push_error("B06 SNAPSHOT: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b06_candidate_combat_snapshot"): get_tree().quit(2); return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":26009}),"isolated baseline")
	var room=load("res://scenes/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	var snap:=Snap.new()
	for id: String in ["L32","BO06"]:
		var prepared:Dictionary=room.prepare_expedition_node({"room_id":id,"biome_id":"B06","role":"boss" if id=="BO06" else "branch","difficulty":2,"seed":26009,"node_index":1,"b06_candidate":true})
		room.apply_prepared_expedition_node(prepared)
		room.player.loadout.event("room_enter",{"room_id":id,"unvisited":true,"combat_room":true})
		if id=="L32":
			for actor in room.enemies.get_children(): actor.free()
			room.spawn_enemy(Vector2(400,350),"B06-M01",26,{"profile":Skills.profile("B06-M01",26,2),"reward_enabled":false,"reward_spawn_id":"snapshot:fish"})
		var actor:Node2D=room._boss_actor if id=="BO06" else room.enemies.get_child(0)
		room.player.position=actor.position+Vector2(100,0)
		if id=="BO06": actor.brain._begin_action(actor,room.player,"siege_claw")
		else:
			actor.brain.tick(actor,.81,room.player)
			actor.brain.tick(actor,.01,room.player)
		if id=="L32":
			var miner:Node2D=room.spawn_enemy(Vector2(600,350),"B06-M06",26,{"profile":Skills.profile("B06-M06",26,2),"reward_enabled":false,"reward_spawn_id":"snapshot:miner"})
			miner.state = &"execute"
			var mine:Dictionary=Skills.active(miner.profile,miner.position,Vector2(750,400),false,false)
			room.enemy_skills.emit_skill(miner,mine)
			check(not room.enemy_skills.b06.effects.is_empty(),"live mine effect and anchor admitted")
		actor.status.grant_guard_result(100,4,"test_guard",actor.health.maximum)
		room.b06_mechanics.tick(9.5)
		var hp:float=float(actor.health.current)
		var warned:Dictionary=actor.brain.current_telegraph()
		var saved:=snap.capture(room)
		check(not saved.is_empty(),"capture pending warning "+id+" "+snap.last_error)
		if saved.is_empty(): continue
		var json:Dictionary=JSON.parse_string(JSON.stringify(saved))
		actor.health.current=hp-1
		room.b06_mechanics.tick(.4)
		check(snap.restore(room,json),"rebuild hostile actors and command "+id+" "+snap.last_error)
		var restored:Node2D=room._boss_actor if id=="BO06" else room.enemies.get_child(0)
		check(is_instance_valid(restored) and restored!=actor,"new actor instances rebound")
		check(float(restored.health.current)==hp and restored.status.shield()==100,"health and exact guard preserved")
		check(restored.brain.current_telegraph().get("direction")==warned.get("direction"),"frozen warning geometry restored")
		if id=="L32": check(not room.enemy_skills.b06.effects.is_empty(),"active mine and replacement anchor rebound")
		check(room.b06_mechanics.state.clock_state().remaining_seconds==.5 if id=="L32" else room.b06_mechanics.state.clock_state().phase=="inactive","tide restored without skipping warning")
		var corrupt:=json.duplicate(true)
		corrupt.actors[0].hp=-1
		var before:Node2D=restored
		check(not snap.restore(room,corrupt) and is_instance_valid(before),"invalid snapshot leaves original population")
		room.player.abilities.active={"test":true}
		check(snap.capture(room).is_empty(),"unsupported active hero action fails closed")
		room.player.abilities.active.clear()
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B06_CANDIDATE_COMBAT_SNAPSHOT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
