extends "res://tests/test_enemy_integration.gd"
const BossArt=preload("res://scripts/combat/b05_boss_art.gd")
const BossActor=preload("res://scripts/combat/boss.gd")
var records: Array[Dictionary]=[]

func _run() -> void:
	if not Game.profile_path.contains("test_b05_boss_art") or OS.get_environment("GAMES_TEST_OUTPUT_DIR").is_empty():
		get_tree().quit(2); return
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"isolated run")
	fixture()
	room.enemy_skills.set_physics_process(false)
	room.combat_audio.audible=false
	Game.run.hp=100000;Game.run.max_hp=100000;Game.run.stats.max_hp=100000
	var boss: MineBoss=BossActor.new()
	boss.room=room;boss.position=Vector2(1100,800)
	check(boss.configure_boss("BO05",4,251804,2),"real boss factory")
	room.enemies.add_child(boss)
	check(boss.body_visual is BossArt,"BO05-only visual installed")
	var art=boss.body_visual
	check(BossArt.frames().size()==7,"seven original native textures")
	for pose: String in BossArt.frames():
		art.apply_pose(pose)
		var frame: Dictionary=art.body_frame()
		check(frame.texture.get_size()==Vector2(1254,1254),pose+" native dimensions")
		check(frame.region==Rect2(0,0,1254,1254),pose+" full source canvas retained")
		near(frame.bounds.size.y,1254.0*220.0/float(BossArt.frames()[pose].anatomy_height),pose+" fixed anatomy scale")
		var landmarks: Dictionary=art.visual_landmarks()
		var source: Dictionary=BossArt.frames()[pose]
		var local_core: Vector2=art.to_local(landmarks.core_global)
		check(local_core.distance_to(Vector2(36,-493)*220.0/1226.0)<1.0,pose+" registered core consistent")
		check(art.to_local(landmarks.head_global).distance_to(Vector2(36,-694)*220.0/1226.0)<1.5,pose+" bark-face registration stable")
		check(art.to_local(landmarks.foot_global).length()<.001,pose+" pivot fixed")
		for i in range(source.outlets.size()):
			check(art.to_local(landmarks.outlets_global[i]).distance_to((source.outlets[i]-source.foot)*220.0/float(source.anatomy_height))<.001,pose+" outlet same render transform")
		var contact: Dictionary=art.contact_anchor(Vector2.RIGHT)
		check(not contact.is_empty(),pose+" actual alpha contact available")
		var mask: BitMap=art._contact_masks[frame.texture.get_instance_id()]
		check(art._opaque_contact(mask,frame.region,frame.bounds,contact.local_offset),pose+" contact lands on opaque art")
		check(not art._opaque_contact(mask,frame.region,frame.bounds,frame.bounds.position),pose+" transparent canvas corner not contact")
		check(not landmarks.source_gate_passed,"source quality remains explicitly unaccepted")
	# Drive real BossBrain selection/release. No synthetic pose setting for dispatch checks.
	for action: String in preload("res://scripts/combat/b05_enemy_skills.gd").BOSS_ACTIONS:
		boss.boss_brain.phase=3;boss.boss_brain.elapsed=30;boss.boss_brain._action_ready_at.clear()
		boss.boss_brain._last_victim=weakref(room.player)
		boss.boss_brain._begin_action(boss,room.player,action)
		art.advance(.3)
		check(art.pose_name==BossArt.family(action)+"-windup",action+" actual windup dispatch")
		boss.boss_brain.state=&"locked";boss.state=&"locked"
		art.advance(.05)
		check(art.pose_name==BossArt.family(action)+"-windup",action+" locked holds windup")
		boss.boss_brain._execute(boss)
		check(art.pose_name==BossArt.family(action)+"-execute",action+" actual release dispatch")
		art.advance(.05)
		check(art.pose_name.ends_with("execute"),action+" execute survives recovery transition")
		get_tree().paused=true
		var held: float=art._release_remaining
		art.advance(1)
		near(art._release_remaining,held,action+" pause freezes release")
		get_tree().paused=false
		art.advance(.3)
		check(art.pose_name==("root-windup" if action=="three_roots" else "idle"),action+" recovery or repeated-root windup")
		room.enemy_skills.reset_room()
	art.release("three_roots")
	boss.boss_brain.state=&"phase_shift"
	art.advance(.01)
	check(art.pose_name=="idle" and art._release_remaining==0,"phase shift interrupts released art")
	# Direction and hit transforms must carry both landmarks and alpha contacts.
	for side in [-1,1]:
		boss.aim_direction=Vector2(side,0);boss.state=&"recovery";boss.boss_brain.state=&"recovery"
		art.advance(.3);art.release("crown_sweep");art.receive_impact(Vector2(side,0),1,true)
		art.advance(.02)
		var source: Dictionary=BossArt.frames()[art.pose_name]
		var local_core: Vector2=(source.core-source.foot)*220.0/float(source.anatomy_height)
		check(art.visual_landmarks().core_global.distance_to(art.to_global(local_core))<.001,"mirror/recoil carries core")
	check(boss.configure_boss("BO01",0,251804,2),"reconfigure old boss")
	check(not boss.body_visual is BossArt,"old bosses retain original visual")
	check(boss.configure_boss("BO05",0,251804,2),"reconfigure BO05")
	check(boss.body_visual.pose_name=="idle" and boss.body_visual._release_remaining==0,"retry clears pose clock")
	if "--capture" in OS.get_cmdline_user_args(): await capture(boss)
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_BOSS_ART checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func capture(boss: MineBoss) -> void:
	check(DisplayServer.get_name()!="headless","capture requires actual renderer")
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	room.layout=preload("res://scripts/world/b05_room_layouts.gd").build("BO05",251804)
	room.layout_id="BO05"
	room.expedition_context={"biome_id":"B05","room_id":"BO05","role":"boss","difficulty":0}
	room._configure_ground_boundary()
	room._configure_world_view()
	boss.position=Vector2(810,520)
	room.player.position=Vector2(950,520)
	room.enemy_skills.reset_room()
	room.effects.clear()
	var focus:=Node2D.new();focus.position=Vector2(810,470);room.add_child(focus)
	room.camera.target=focus;room.camera.follow_target();room.camera.force_update_scroll()
	for pose: String in ["idle","cast-windup","root-execute"]:
		boss.boss_brain.weakpoint="flower_heart"
		boss.boss_brain.weakpoint_time=4
		boss.body_visual.apply_pose(pose)
		for i in range(3): await get_tree().process_frame
		RenderingServer.force_draw(false)
		var image:=get_viewport().get_texture().get_image()
		check(image.get_size()==Vector2i(2560,1440),"actual 2K viewport")
		var frame: Dictionary=boss.body_visual.body_frame()
		var screen_bounds: Rect2=boss.body_visual.get_global_transform_with_canvas()*Rect2(frame.bounds)
		check(get_viewport().get_visible_rect().encloses(screen_bounds),pose+" full transformed sprite inside viewport")
		check(image.save_png(OS.get_environment("GAMES_TEST_OUTPUT_DIR").path_join("BO05-"+pose+"-2k.png"))==OK,"save frame")
