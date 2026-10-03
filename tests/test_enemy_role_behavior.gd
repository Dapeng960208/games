extends "res://tests/test_enemy_integration.gd"
const Roles = preload("res://scripts/combat/enemy_role_behavior.gd")
const Calibration = preload("res://scripts/combat/enemy_calibration.gd")
const Policy = preload("res://scripts/combat/enemy_species_policy.gd")

class RecordingEnemy extends MineEnemy:
	var releases: Array[Dictionary] = []
	func cast_enemy_skill(command: Dictionary) -> void:
		releases.append(command.duplicate(true))
		super.cast_enemy_skill(command)

func level_for(id: String) -> int:
	return 21 if id.begins_with("B05-") else 26 if id.begins_with("B06-") else 20

func actor_for(id: String = "M03", version: int = 15) -> MineEnemy:
	Game.run.enemy_calibration_snapshot = Calibration.archived(version)
	var p := Profiles.resolve(id,level_for(id),"normal",2,0,Calibration.archived(version))
	var actor: MineEnemy = room.spawn_enemy(Vector2(1100,800),id,level_for(id),{"profile":p,"reward_enabled":false})
	actor.brain.age = 1.0
	actor.brain._set_phase(&"chase",0)
	actor.state = &"chase"
	return actor

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_role_behavior") or not WorldCatalog.b06_enabled():
		get_tree().quit(2); return
	check(Game.new_profile() and Game.start_run(),"isolated run")
	fixture()
	room.combat_audio.audible = false
	var actor := actor_for()
	var origin := actor.position
	var hp: float = Game.run.hp
	for i in 12: actor._physics_process(.025)
	near(actor.position.distance_to(origin),70,"actual MineEnemy moves 70 over .3 seconds")
	near(Game.run.hp,hp,"dodge has no damage")
	check(not actor.status.has("invulnerable"),"dodge adds no invulnerability")
	check(actor.role_behavior.cooldown > 7.6 and not actor.role_reposition_available(),"one shared 8 second CD")
	var end := actor.position
	check(not actor.role_behavior.tick(actor,.1,room.player),"cannot immediately dodge again")
	near(actor.position.distance_to(end),0,"CD prevents displacement")
	actor.role_behavior.cooldown = 0
	actor.position = origin
	actor.role_behavior.tick(actor,.1,room.player)
	var pause_position := actor.position
	var pause_cd: float = actor.role_behavior.cooldown
	get_tree().paused = true
	actor._physics_process(2.0)
	near(actor.position.distance_to(pause_position),0,"pause freezes live movement")
	near(actor.role_behavior.cooldown,pause_cd,"pause freezes cooldown")
	get_tree().paused = false
	actor._physics_process(.2)
	near(actor.position.distance_to(origin),70,"resume consumes remaining action once")
	actor.role_behavior.reset(); actor.position=origin
	actor.role_behavior.tick(actor,.1,room.player)
	actor.reaction_remaining=1
	var interrupted:=actor.position
	check(not actor.role_behavior.tick(actor,.1,room.player),"stagger cancels dodge")
	near(actor.role_behavior.remaining,0,"cancelled remaining action cleared")
	actor.reaction_remaining=0
	check(not actor.role_behavior.tick(actor,.1,room.player),"stagger recovery does not replay cancelled action")
	near(actor.position.distance_to(interrupted),0,"interrupted position stable")
	actor.role_behavior.reset(); actor.position=origin
	actor.state=&"frozen"
	check(not actor.role_behavior.tick(actor,.1,room.player),"frozen actor cannot trigger")
	actor.state=&"chase"
	actor.role_behavior.tick(actor,.1,room.player)
	room.enemy_skills.cancel_owner(actor)
	near(actor.role_behavior.remaining,0,"runtime owner cancellation clears dodge")
	check(not actor.role_behavior.tick(actor,.1,room.player),"cancelled owner action never restarts within CD")
	actor.role_behavior.reset(); actor.position=origin
	actor.role_behavior.tick(actor,.1,room.player)
	room.enemy_skills.reset_room()
	near(actor.role_behavior.remaining,0,"room reset cancels partial movement")
	check(not actor.role_behavior.tick(actor,.1,room.player),"room reset does not rearm old movement")
	actor.role_behavior.reset(); actor.position=origin
	actor.spend_role_reposition()
	check(not actor.role_behavior.tick(actor,.1,room.player),"existing movement shares dodge CD")
	actor.role_behavior.reset(); actor.position=origin
	room.obstructions=[Rect2(1050,830,100,10),Rect2(1050,760,100,10)]
	check(not actor.role_behavior.tick(actor,.3,room.player),"both side walls block entire swept dodge")
	near(actor.position.distance_to(origin),0,"no thin wall crossing")
	room.obstructions.clear()
	room.ground_polygon=PackedVector2Array([Vector2(1000,780),Vector2(1300,780),Vector2(1300,820),Vector2(1000,820)])
	check(not actor.role_behavior.tick(actor,.3,room.player),"narrow main route rejects off-ground dodge")
	room.ground_polygon.clear()
	actor.role_behavior.reset(); actor.position=origin
	room.player.position=Vector2(1400,800)
	check(not actor.role_behavior.tick(actor,.1,room.player),"no distant input prediction")
	room.player.position=Vector2(1200,800)
	for role: String in ["caster","support","tank","warrior","assassin","boss"]:
		actor.profile.primary_role=role
		check(not actor.role_behavior.tick(actor,.3,room.player),role+" never receives inferred ranged dodge")
	actor.free()
	for version in range(15):
		var old := actor_for("M03",version)
		check(not Roles.has_role(old.profile,"ranged") and not old.role_behavior.tick(old,.3,room.player),"archive%d unchanged mobility"%version)
		near(Roles.action_seconds(old.profile,1),1,"archive%d unchanged execute"%version)
		near(Roles.recovery_seconds(old.profile,1),1,"archive%d unchanged recovery"%version)
		old.free()
	for id: String in ["M10","M13","M15","M28","M29","M32","M44","B05-M03","B05-M06","B05-M09","B06-M04","B06-M14"]:
		# Probe actual role catalog below; never assume an ID's combat role.
		var source := Profiles.resolve(id,level_for(id),"normal",2,0,Calibration.archived(15))
		check(Roles.has_role(source,"assassin"),"exact assassin identity "+id)
		if not Roles.has_role(source,"assassin"): continue
		var live:=actor_for(id)
		live.brain._set_phase(&"telegraph",1.0)
		near(live.brain._remaining,1,"assassin keeps full visible tell "+id)
		live.brain._set_phase(&"locked",.4)
		near(live.brain._remaining,.4,"assassin keeps full lock "+id)
		live.brain._set_phase(&"execute",1)
		near(live.brain._remaining,.85,"assassin execute .85 "+id)
		near(Roles.recovery_seconds(source,1),.8,"assassin recovery .8 "+id)
		near(Roles.recovery_seconds(source,1,1.2),1.2,"exposure floor preserved "+id)
		var command: Dictionary={"kind":"charge","duration":1.0,"speed":100.0,"travel_distance":100.0,"count":2,"target":Vector2(100,0)}
		var adjusted:=Roles.action_command(source,command)
		near(adjusted.duration,.85,"charge executes faster "+id)
		check(adjusted.count==command.count and adjusted.target==command.target and adjusted.travel_distance==command.travel_distance,"same hit count and warned geometry "+id)
		live.free()
	for id: String in ["M03","M20","M46","M50","B05-M02","B05-M12","B05-M16","B06-M02","B06-M06","B06-M12","B06-M16"]:
		var ranged:=actor_for(id)
		check(Roles.has_role(ranged.profile,"ranged"),"exact ranged identity "+id)
		check(ranged.role_behavior.tick(ranged,.3,room.player),"every movable ranged identity can evade "+id)
		ranged.free()
	for id: String in ["M10","B05-M03","B06-M04"]:
		var baseline:=first_release(id,false)
		var candidate:=first_release(id,true)
		check(not candidate.is_empty() and candidate==baseline,"actual first cast command/packet topology unchanged "+id)
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	if "--role-capture" in OS.get_cmdline_user_args(): await capture_group()
	room.free(); Game.run=null
	print("ENEMY_ROLE_BEHAVIOR checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func first_release(id: String, candidate: bool) -> Array:
	clear_enemies()
	Game.run.enemy_calibration_snapshot=Calibration.archived(15)
	Game.run.hp=100000; Game.run.max_hp=100000; Game.run.stats.max_hp=100000
	var source:=Profiles.resolve(id,level_for(id),"normal",2,0,Calibration.archived(15))
	if not candidate: source.erase("enemy_species_version")
	var live:=RecordingEnemy.new()
	live.configure(source,{"reward_enabled":false})
	live.room=room; live.position=Vector2(1130,800)
	room.enemies.add_child(live)
	var released:=until(func(): return not live.releases.is_empty(),8)
	check(released,"real assassin releases after complete warning "+id)
	var topology: Array=[]
	for command: Dictionary in live.releases:
		topology.append([command.get("kind",""),command.get("count",1),command.get("ability_id",""),command.get("repeat",1)])
	return topology

func capture_group() -> void:
	fixture("L01")
	room.enemy_skills.set_physics_process(false)
	room.combat_audio.audible=false
	Game.run.enemy_calibration_snapshot=Calibration.archived(15)
	Game.run.hp=100000; Game.run.max_hp=100000; Game.run.stats.max_hp=100000
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	room.player.position=Vector2(800,520)
	var target:=Node2D.new(); room.add_child(target); target.position=room.player.position
	room.camera.target=target; room.camera.follow_target(); room.camera.force_update_scroll()
	var ids: Array[String]=["M03","M20","M46","M50","M10","M15"]
	for i in ids.size():
		var id: String=ids[i]
		var source:=Profiles.resolve(id,20,"normal",2,2,Calibration.archived(15))
		var at:=room.player.position+Vector2.from_angle(TAU*i/ids.size())*125
		var live: MineEnemy=room.spawn_enemy(at,id,20,{"profile":source,"reward_enabled":false})
		live.brain.age=1.0; live.brain._set_phase(&"chase",0); live.state=&"chase"
	for index in 3:
		step(.15 if index==0 else .35)
		for child in room.enemies.get_children(): child.queue_redraw()
		room.queue_redraw(); room.enemy_skills.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels:=get_viewport().get_texture().get_image()
		check(pixels.get_size()==Vector2i(2560,1440),"native 2K mixed-role scene")
		check(pixels.save_png(OS.get_environment("GAMES_TEST_OUTPUT_DIR").path_join("role_group_%d.png"%index))==OK,"save actual mixed-role capture")
