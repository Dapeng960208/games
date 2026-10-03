extends Node
const Launcher = preload("res://scripts/world/b07_candidate_scene.gd")
const Routes = preload("res://scripts/world/route_generator.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Rules = preload("res://config/numerical_rules.gd")
const Calibration = preload("res://scripts/combat/enemy_calibration.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures+=1; push_error("B07 SESSION "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Rules.b07_candidate_enabled() or not Game.profile_path.begins_with("user://test_b07_candidate/"): get_tree().quit(2); return
	check(not Routes.generate_single_biome("B01",27007,[],31).get("valid",false),"published Lv20 route stays protected")
	check(Rules.parameters().implemented_chapters==4 and not WorldCatalog.biomes().has("B07"),"no campaign release")
	for hero: String in ["CH01","CH02","CH03"]:
		var launch := Launcher.new()
		launch.auto_start=false
		launch.process_mode=Node.PROCESS_MODE_DISABLED
		add_child(launch)
		check(launch.start_candidate(hero,0,false),hero+" starts: "+launch.last_error)
		if Game.run==null or not is_instance_valid(launch.room): launch.free(); continue
		var room: Node2D=launch.room
		check(Game.run.level==31 and Game.run.hero_id==hero,hero+" Lv31 correct identity")
		check(Game.run.expedition.is_empty(),"no hidden B01 campaign")
		var original_run: String=Game.run.id
		check(not launch.start_candidate(hero,0,false) and Game.run.id==original_run,"duplicate start cannot replace run")
		check(launch.traversal.checkpoint().is_empty(),"active room cannot masquerade as clear checkpoint")
		for actor in room.enemies.get_children(): actor.free()
		room.enemy_skills.reset_room()
		room.objective_complete=true
		room.objective_rewarded=false
		room._completion_emitted=true
		room.b07_mechanics.state.open_manual_gate(true)
		room.player.loadout.event("room_enter",{"room_id":"L37","unvisited":true,"combat_room":true})
		Game.run.hp=maxi(1,int(Game.run.max_hp)-17)
		Game.run.resource=maxi(0,int(Game.run.stats.resource_max)-11)
		room.player.cooldowns.q=2.25
		room.player.dash_cooldown=1.5
		var saved: Dictionary=JSON.parse_string(JSON.stringify(launch.traversal.checkpoint()))
		check(not saved.is_empty() and saved.version==2,"version2 JSON clear-boundary")
		if saved.is_empty():
			check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
			launch.free(); Game.run=null; continue
		var same_room: String=room.layout_id
		var same_index: int=launch.traversal.node_index
		var hp_before: float=Game.run.hp
		var actor_count: int=room.enemies.get_child_count()
		for corruption: String in ["session","profile","hero_room","calibration","sun"]:
			var bad: Dictionary=saved.duplicate(true)
			match corruption:
				"session": bad.run_id="another-run"
				"profile": bad.profile_path="user://test_b07_candidate/other.json"
				"hero_room": bad.hero.equipment.room_id="L38"
				"calibration": bad.hero.runtime.b07_mechanisms.calibration=Calibration.archived(14)
				"sun": bad.sun.gate_open=false
			check(not launch.traversal.restore_checkpoint(bad),"reject "+corruption)
			check(room.layout_id==same_room and room.enemies.get_child_count()==actor_count and launch.traversal.node_index==same_index and Game.run.hp==hp_before,"atomic "+corruption)
		Game.run.hp=1; room.player.cooldowns.q=0
		check(launch.traversal.restore_checkpoint(saved),"restore clear boundary")
		check(room.layout_id=="L37" and room._living_enemy_count()==0 and room.objective_complete,"restored room no hostile respawn")
		check(Game.run.hp==saved.hero.hp and Game.run.resource==saved.hero.resource and room.player.cooldowns.q==2.25 and room.player.dash_cooldown==1.5,"preserve HP resource cooldowns")
		room.input_blocked=false; room.release_gate=false
		check(room.nearby_interaction().get("kind")=="b07_candidate_next","exit remains accessible after resume")
		room.interact()
		check(launch.traversal.node_index==1 and room.layout_id=="L38","production F advances once")
		check(not launch.traversal.advance(0) and launch.traversal.node_index==1,"stale duplicate advance refused")
		check(Game.run.hp==saved.hero.hp and room.player.cooldowns.q==2.25,"advance preserves survival and cooldowns")
		check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
		launch.free()
		Game.run=null
	print("B07 CANDIDATE SESSION ",checks," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
