extends Node
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
const Brain = preload("res://scripts/levels/b09/combat/brain.gd")
const Art = preload("res://scripts/levels/b09/art/actors.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("B09: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b09_candidate"): get_tree().quit(2); return
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"isolated profile")
	var profile_before := JSON.stringify(Game.profile)
	# The test runner isolates APPDATA. The traversal also validates its user:// prefix.
	Game.profile_path="user://test_b09_candidate/fixture.json"
	for d in 5:
		for id: String in Content.data().enemy_ids:
			var p := Skills.profile(id, int(Content.enemy(id).first_level),d)
			check(not p.is_empty() and p.max_hp>0 and p.damage>0,"profile "+id+" D"+str(d))
			var c := Skills.active(p,Vector2(400,400),Vector2(500,400))
			check(c.tell>0 and c.lock>0 and c.cooldown>0 and Skills.freeze(c,p).damage>=0,"frozen command "+id)
			check(not Art.bank(id).is_empty(),"new native identity "+id)
		var boss := Brain.new()
		boss.configure(Skills.boss_profile(d))
		for phase in range(1,4):
			for action: String in boss.available_actions(phase):
				check(not Skills.boss_action(boss.definition,action,Vector2(400,400),Vector2(500,400),phase).is_empty(),"boss gate "+action)
		check(("mirror_verdict" in boss.available_actions(3))==(d==4),"D4 gate")
	check(Skills.boss_profile(0).max_hp==37044 and Skills.boss_profile(0).damage==708,"queen authored D0")
	check(not Art.bank("BO09").is_empty(),"queen original body")
	var room = load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	for actor in room.enemies.get_children(): actor.free()
	var route := Traversal.new()
	check(route.configure(room,4,309) and route.start(),"explicit B09 route")
	var map: Node2D=room.b09_mechanics
	var actor: Node2D=room.spawn_enemy(Vector2(500,500),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,4)})
	check(is_instance_valid(actor) and actor.brain is Brain,"real B09 spawn")
	var hp: float = actor.health.current
	actor.take_damage(20,&"primary",Vector2.RIGHT,{"damage_type":"true","root_event_id":"same"})
	actor.take_damage(20,&"primary",Vector2.RIGHT,{"damage_type":"true","root_event_id":"same"})
	check(actor.get_meta("b09_layers")==1 and actor.health.current<hp,"multihit root breaks one layer")
	actor.set_meta("b09_layers",3)
	map.filter_damage(actor,20,&"burn",{"dot":true})
	map.filter_damage(actor,20,&"burn",{"dot":true})
	check(actor.get_meta("b09_layers")==2,"DOT per-second cap")
	map.tick(1.01)
	map.filter_damage(actor,20,&"burn",{"dot":true})
	check(actor.get_meta("b09_layers")==1,"DOT next second breaks")
	map.tick(7.9)
	check(actor.get_meta("b09_layers")==1,"no early regeneration")
	map.tick(0.11)
	check(actor.get_meta("b09_layers")==2,"eight-second regeneration")
	room.release_gate=false
	room.input_blocked=false
	room.player.position=Content.rect(Content.room("L49").ice_rects[0]).get_center()
	map.movement_velocity(room.player,Vector2.RIGHT,Vector2(220,0),0.1)
	var glide := Vector2.ZERO
	for i in 5: glide+=map.movement_velocity(room.player,Vector2.ZERO,Vector2.ZERO,0.05)*0.05
	check(glide.length()<=40.01 and glide.length()>39,"40px / 0.25s cap")
	check(map.movement_velocity(room.player,Vector2.LEFT,Vector2(-220,0),0.05).x==-220,"new input immediate")
	map.movement_velocity(room.player,Vector2.RIGHT,Vector2(220,0),0.1)
	var slow_frame: Vector2=map.movement_velocity(room.player,Vector2.ZERO,Vector2.ZERO,0.4)*0.4
	check(slow_frame.length()<=40.01 and map.movement_velocity(room.player,Vector2.ZERO,Vector2.ZERO,0.1).is_zero_approx(),"long frame never exceeds glide cap")
	map.movement_velocity(room.player,Vector2.RIGHT,Vector2(220,0),0.1)
	room.player.dash_remaining=0.1
	check(map.movement_velocity(room.player,Vector2.ZERO,Vector2(400,0),0.1)==Vector2(400,0),"dash immediately cancels glide")
	room.player.dash_remaining=0.0
	room.player.position=room.layout.entry
	check(map.movement_velocity(room.player,Vector2.ZERO,Vector2.ZERO,0.05).is_zero_approx(),"rough snow stops")
	var lamp_id: String=map.lamps.keys()[0]
	room.player.position=map.lamps[lamp_id].at
	actor.position=room.player.position+Vector2(30,0)
	actor.set_meta("b09_layers",2)
	check(map.interact(lamp_id,room.player),"lamp channel starts")
	map.tick(0.3)
	check(actor.get_meta("b09_layers")==2,"lamp not instant")
	map.tick(0.31)
	check(actor.get_meta("b09_layers")==1 and not map.interact(lamp_id,room.player),"lamp breaks one, cooldown")
	check(not map.is_ice(map.lamps[lamp_id].at),"warm circle removes marked ice")
	map.lamps[lamp_id].ready=0.0
	check(map.interact(lamp_id,room.player),"second lamp channel starts")
	room.telemetry.player_hits+=1
	map.tick(0.61)
	check(map._pending.is_empty() and map.lamps[lamp_id].ready==0.0,"real damage interrupts lamp without consuming cooldown")
	room.player.invulnerable=9999.0
	map.definition.bridges=Content.room("L53").bridges.duplicate(true)
	for id: String in Content.data().enemy_ids:
		room.enemy_skills.reset_room()
		for enemy in room.enemies.get_children(): enemy.free()
		map.walls.clear()
		map.bridge.clear()
		room.player.position=Vector2(650,500)
		var live: Node2D=room.spawn_enemy(Vector2(550,500),id,int(Content.enemy(id).first_level),{"profile":Skills.profile(id,int(Content.enemy(id).first_level),4)})
		check(is_instance_valid(live),"live actor admission "+id)
		if not is_instance_valid(live): continue
		live.brain._begin_action(live,room.player)
		var warned: Dictionary=live.brain.command.duplicate(true)
		check(not warned.is_empty(),"actual warning "+id)
		for step in 45:
			live.brain.tick(live,0.1,room.player)
			live.position=room.move_actor(live.position,live.velocity*0.1,live.navigation_radius)
			room.enemy_skills.advance(0.1)
			map.tick(0.1)
			live.body_visual.advance(0.1)
		check(live.brain.current_skill().get("phase","")!="telegraph" or live.brain.elapsed>4.0,"bounded live cast "+id)
		check(not live.body_visual.body_frame().is_empty(),"native renderer "+id)
	room.player.invulnerable=0.0
	room.enemy_skills.reset_room()
	for enemy in room.enemies.get_children(): enemy.free()
	map.walls.clear()
	room.player.position=Vector2(650,500)
	Game.run.hp=Game.run.max_hp
	var shield: Node2D=room.spawn_enemy(Vector2(590,500),"B09-M05",41,{"profile":Skills.profile("B09-M05",41,4)})
	shield.state=&"execute"
	var shield_before: float=Game.run.hp
	room.enemy_skills.emit_skill(shield,Skills.active(shield.profile,shield.position,room.player.position))
	check(Game.run.hp<shield_before and map.walls.is_empty(),"shield strike still hits when cover cannot be placed under player")
	shield.free()
	room.enemy_skills.reset_room()
	Game.run.hp=Game.run.max_hp
	room.player.position=Vector2(1100,500)
	var sculptor: Node2D=room.spawn_enemy(Vector2(400,500),"B09-M12",43,{"profile":Skills.profile("B09-M12",43,4)})
	sculptor.state=&"execute"
	room.enemy_skills.emit_skill(sculptor,Skills.active(sculptor.profile,sculptor.position,Vector2(950,500)))
	var shatters := 0
	for wall: Dictionary in map.walls:
		if wall.has("shatter"): shatters+=1
	check(map.walls.size()==2 and shatters==1,"D4 split wall leaves gap and only one shatter packet")
	for enemy in room.enemies.get_children(): enemy.free()
	map.walls.clear()
	room.enemy_skills.reset_room()
	for index in 7:
		check(route.node_index==index,"ordered route")
		check(not route.advance(index),"uncleared exit blocked")
		if room.layout_id=="L51":
			map=room.b09_mechanics
			check(map.request_bridge() and not map.request_bridge(),"single bridge admission")
			var box: Rect2=map.bridge.rect
			var first_bridge_id: String = map.bridge.id
			room.player.position=box.get_center()
			Game.run.hp=Game.run.max_hp
			var before: float = Game.run.hp
			map.tick(2.01)
			check(map.bridge.state=="closed" and room.valid_ground(room.player.position,Balance.PLAYER_RADIUS),"bridge rebounds to legal edge")
			check(before-Game.run.hp<=Game.run.max_hp*0.08+1,"collapse HP cap")
			var after: float = Game.run.hp
			map.tick(0.5)
			check(Game.run.hp==after,"collapse only once")
			map.tick(3.51)
			check(map.bridge.is_empty() and map.request_bridge() and map.bridge.id!=first_bridge_id,"alternate bridge after rebuild")
		if room.layout_id=="BO09":
			room._boss_actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true"})
			await get_tree().process_frame
		else:
			for zone in room.encounter_zones.size():
				room.player.position=room.encounter_zones[zone].center
				for step in 5:
					room._update_encounters(4)
					for enemy in room.enemies.get_children(): enemy.free()
		room._tick_expedition(0)
		check(room.objective_complete and not room.objective_rewarded,"finite clear, economy blocked")
		room.enemy_skills.reset_room()
		for projectile in room.projectiles.get_children(): projectile.free()
		room.player.position=room.exit_position
		check(room.nearby_interaction().get("kind")=="b09_candidate_next","actual B09 exit")
		room.input_blocked=false
		room.release_gate=false
		room.interact()
		check(route.finished if index==6 else route.node_index==index+1,"F advances once")
	check(JSON.stringify(Game.profile)==profile_before,"profile, gold, XP and unlocks unchanged")
	check(route.finished,"all seven rooms complete")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free()
	Game.run=null
	print("B09_CANDIDATE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
