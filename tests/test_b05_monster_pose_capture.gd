extends "res://tests/test_environment_clarity.gd"
## Controlled presentation capture on the actual room/actor/brain/runtime path.
## Only fixture positions, facing, HP and the clock are controlled. Eighteen
## native 2K keyframes plus twelve same-state no-detail silhouette comparisons; no claim of a natural playthrough or hardware performance.
const B05Layouts=preload("res://scripts/world/b05_room_layouts.gd")
const B05Geometry=preload("res://scripts/world/b05_room_geometry.gd")
const B05Mechanisms=preload("res://scripts/world/b05_room_mechanisms.gd")
const B05Profiles=preload("res://scripts/combat/enemy_profiles.gd")
const B05Verge=preload("res://scripts/world/b05_boundary_verge.gd")
var POSE_OUTPUT := ""
const POSE_IDS:=["B05-M01","B05-M02","B05-M04"]
var pose_records: Array[Dictionary]=[]
var landing_only:=false
var focused_ids: Array[String]=[]
var limited_capture:=false
var saved_images:=0
var fixed_camera: Node2D
var camera_position:=Vector2.ZERO
var camera_zoom:=Vector2.ONE
var source_actor: MineEnemy
var support_actor: MineEnemy

func _run() -> void:
	var output_root := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output_root.is_empty() or not output_root.is_absolute_path():
		push_error("Run capture through tools/test_workspace.py")
		get_tree().quit(2)
		return
	POSE_OUTPUT = output_root.path_join("b05-monster-poses") + "/"
	landing_only="--b05-m02-landing-only" in OS.get_cmdline_user_args()
	limited_capture="--b05-limited-capture" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b05-pose-ids="):
			for id: String in argument.trim_prefix("--b05-pose-ids=").split(","):
				if id in preload("res://scripts/combat/b05_enemy_art.gd").IDS: focused_ids.append(id)
	if not Game.profile_path.contains("test_b05_monster_pose_capture") or DisplayServer.get_name()=="headless":
		push_error("B05 pose capture requires graphical display and its isolated test profile")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POSE_OUTPUT))
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":251804}),"isolated production baseline starts")
	Game.profile.settings.camera_shake=false
	Game.profile.settings.automatic_attack=false
	Game.profile.settings.reduced_fx=false
	Game.profile.settings.enemy_skill_paths=true
	Words.set_locale("zh_CN")
	Game.run.max_hp=100000
	Game.run.stats.max_hp=100000
	Game.run.hp=100000
	room=load("res://scenes/room.tscn").instantiate()
	room.spawn_enabled=false
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await frames()
	room.input_blocked=true
	# Runtime deliberately uses PAUSABLE in production; explicitly freeze its
	# automatic clock here so awaited captures cannot advance only projectiles.
	room.enemy_skills.set_physics_process(false)
	room.combat_audio.audible=false
	if is_instance_valid(room.objectives): room.objectives.free()
	room.objectives=null
	room.relic_positions.clear()
	if is_instance_valid(room.enemy_props): room.enemy_props.clear(); room.enemy_props.hide()
	if is_instance_valid(room._depth_canvas): room._depth_canvas.hide()
	for actor in room.enemies.get_children(): actor.free()
	room.layout=B05Layouts.build("L25",251804)
	room.layout_id="L25"
	room.difficulty=0
	room.expedition_context={"biome_id":"B05","room_id":"L25","role":"branch","difficulty":0,"seed":251804,"node_index":1}
	room._configure_ground_boundary()
	room.obstructions.assign(room.layout.obstructions)
	room._configure_world_view()
	room.b05_mechanics=B05Mechanisms.new()
	room.add_child(room.b05_mechanics)
	check(room.b05_mechanics.configure_room(room,B05Geometry.room("L25"),0),"real L25 root mechanism configured")
	var verge:=B05Verge.new();room.add_child(verge)
	check(verge.configure(room.layout,true),"same L25 candidate exterior installed")
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	fixed_camera=Node2D.new();fixed_camera.position=Vector2(790,505);room.add_child(fixed_camera)
	room.camera.target=fixed_camera
	room.camera.follow_target();room.camera.force_update_scroll()
	await frames()
	camera_position=room.camera.position
	camera_zoom=room.camera.zoom
	var capture_ids: Array=["B05-M02"] if landing_only else focused_ids if not focused_ids.is_empty() else POSE_IDS
	for id: String in capture_ids:
		for side: int in [1,-1]: await capture_actor_cycle(id,side)
	check(pose_records.size()==(2 if landing_only else capture_ids.size()*6),"exact requested runtime pose/direction record count")
	var file:=FileAccess.open(POSE_OUTPUT+("capture_m02_landing.json" if landing_only else "capture.json"),FileAccess.WRITE)
	check(file!=null,"capture manifest opens in ignored artifacts")
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"kind":"production MineEnemy/EnemyVisual and real B05 brain/runtime; controlled clock; not natural balance QA","records":pose_records},"\t"))
		file.close()
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	await frames()
	print("B05_MONSTER_POSE_CAPTURE checks=",checks," failures=",failures," frames=",pose_records.size())
	get_tree().quit(1 if failures else 0)

func capture_actor_cycle(id: String, side: int) -> void:
	room.enemy_skills.reset_room()
	for actor: MineEnemy in room.enemies.get_children():
		if actor.actor_kind!="objective": actor.free()
	room.effects.clear()
	if is_instance_valid(room.impact_feedback): room.impact_feedback.clear_feedback()
	if is_instance_valid(room.defeat_feedback): room.defeat_feedback.clear_feedback()
	if is_instance_valid(room.skill_input_feedback): room.skill_input_feedback.clear_feedback()
	room.queue_redraw()
	check(room.impact_feedback.events.is_empty(),"previous case leaves no floating/contact feedback")
	source_actor=null;support_actor=null
	Game.run.hp=100000
	Game.run.shield=0
	room.player.invulnerable=0
	room.player.hurt_flash=0
	room.player.muzzle_flash=0
	room.player.knockback=Vector2.ZERO
	room.player.status.states.clear()
	room.player.status.guards.clear()
	var at:=Vector2(770,300) if id=="B05-M13" else Vector2(770,530)
	if id in ["B05-M15","B05-M18"]:
		var well: Dictionary=room.b05_mechanics.nearest_active_well(at)
		if not well.is_empty(): at=Vector2(well.position)+Vector2(-60,70)
	var aim:=Vector2(float(side),0)
	room.player.position=at+aim*(108 if id=="B05-M01" else 180)
	var profile: Dictionary=B05Profiles.resolve(id,21,"normal",2,0)
	source_actor=room.spawn_enemy(at,id,21,{"profile":profile,"reward_enabled":false,"zone_index":0})
	check(source_actor!=null,id+" true MineEnemy spawns")
	if source_actor==null: return
	if id in ["B05-M04","B05-M08"]:
		support_actor=room.spawn_enemy(at+aim*140+Vector2(0,45),"B05-M01",21,{"profile":B05Profiles.resolve("B05-M01",21,"normal",2,0),"reward_enabled":false,"zone_index":0})
		check(support_actor!=null,"M04 actual wounded ally exists")
		if support_actor!=null:
			support_actor.training_ai_disabled=true
			support_actor.health.current=roundf(float(support_actor.health.maximum)*.5)
			support_actor.state=&"chase"
			support_actor.aim_direction=-aim
			support_actor.body_visual.advance(.02)
	if id=="B05-M08":
		var second=room.spawn_enemy(at-aim*75+Vector2(0,55),"B05-M01",21,{"profile":B05Profiles.resolve("B05-M01",21,"normal",2,0),"reward_enabled":false,"zone_index":0})
		check(second!=null,"M08 second actual support recipient")
		if second!=null: second.training_ai_disabled=true
	# This still pose is the only deliberately paused-AI capture. The next two
	# keyframes are reached by the actual brain and release real runtime packets.
	source_actor.training_ai_disabled=true
	source_actor.state=&"chase"
	source_actor.aim_direction=aim
	source_actor.body_visual.advance(.02)
	room.player.aim_direction=-aim
	room.player.queue_redraw()
	await record_frame(id,"idle",side,{"paused_ai_idle":true})
	source_actor.training_ai_disabled=false
	source_actor.brain.configure(profile)
	source_actor.state=&"emerging"
	check(advance_until(&"telegraph",4.0),id+" real brain reaches telegraph")
	advance_native(.16)
	check(source_actor.brain.phase==&"telegraph",id+" capture is actual live tell")
	await record_frame(id,"telegraph",side,{"waterline":id=="B05-M04"})
	var ally_before: float=float(support_actor.health.current) if is_instance_valid(support_actor) else 0
	var hp_before: float=Game.run.hp
	check(advance_until(&"execute",4.0),id+" real brain releases")
	advance_native(.02 if id=="B05-M16" else .1)
	var lob_visible:=false
	for effect: Dictionary in room.enemy_skills.b05.effects:
		if str(effect.kind)=="lob_visual": lob_visible=true
	check(source_actor.brain.phase==&"execute",id+" actual execute pose")
	if id=="B05-M02": check(lob_visible,"real M02 seed is in flight")
	if id=="B05-M04": check(float(support_actor.health.current)>ally_before,"real M04 channel healed ally")
	await record_frame(id,"execute",side,{"seed_in_flight":lob_visible,"ally_hp_before":ally_before,"ally_hp_after":float(support_actor.health.current) if is_instance_valid(support_actor) else 0})
	advance_native(.5)
	if id in ["B05-M01","B05-M02"]: check(Game.run.hp<hp_before,id+" actual accepted damage after release/flight")
	check(source_actor.body_visual.body_frame().source_family=="storybook_2_5d_v1",id+" native body remains installed")

func advance_until(expected: StringName, maximum: float) -> bool:
	var elapsed:=0.0
	while elapsed<maximum:
		if source_actor.brain.phase==expected: return true
		advance_native(1.0/60.0)
		elapsed+=1.0/60.0
	return source_actor.brain.phase==expected

func advance_native(duration: float) -> void:
	var remaining:=duration
	while remaining>.000001:
		var delta:=minf(1.0/60.0,remaining)
		source_actor._physics_process(delta)
		if is_instance_valid(support_actor): support_actor._physics_process(delta)
		room.enemy_skills.advance(delta)
		room.impact_feedback.advance(delta)
		room.player.hurt_flash=maxf(0,room.player.hurt_flash-delta)
		room.player.invulnerable=maxf(0,room.player.invulnerable-delta)
		room.player.queue_redraw()
		room.b05_mechanics.tick(delta)
		room.enemy_telegraphs.refresh()
		remaining-=delta

func record_frame(id: String, pose: String, side: int, extra: Dictionary) -> void:
	if landing_only and pose!="execute": return
	if id in ["B05-M13","B05-M15","B05-M18"] and pose!="idle":
		check(bool(source_actor.brain.current_skill().get("active",false)),id+" actual signature command admitted")
	var snapshot_hp: float=Game.run.hp
	var snapshot_clock: float=room.enemy_skills._biome_clock
	room.enemy_telegraphs.refresh()
	room.camera.follow_target();room.camera.force_update_scroll()
	check(room.camera.position.is_equal_approx(camera_position) and room.camera.zoom.is_equal_approx(camera_zoom),"fixed camera across capture")
	var save_image: bool=not limited_capture or (pose=="execute" and side>0 and saved_images<4)
	var image: Image=await capture_pixels() if save_image else null
	if image!=null: check(image.get_size()==Vector2i(2560,1440),"actual native2K framebuffer")
	var filename: String=id+"_"+pose+("_right" if side>0 else "_left")+"_2560x1440.png"
	if image!=null:
		check(image.save_png(POSE_OUTPUT+filename)==OK,filename+" saved to ignored artifacts")
		saved_images+=1
	var body: Dictionary=source_actor.body_visual.body_frame()
	var outlet: Dictionary=source_actor.body_visual.b05_visual_outlet()
	check(not outlet.is_empty() and body.texture!=null,"actual selected-frame outlet exists")
	check(str(body.name)==pose or (id=="B05-M04" and pose=="telegraph" and str(body.name)=="execute"),"actual dispatch selects expected native pose")
	var record: Dictionary={"file":filename if image!=null else "","id":id,"pose":pose,"side":side,"actor_position":source_actor.position,"actual_actor_state":str(source_actor.state),"actual_brain_phase":str(source_actor.brain.phase),"body_frame":body.name,"texture":outlet.get("texture_path",""),"bounds":body.bounds,"visual_outlet":outlet.get("position",Vector2.ZERO),"camera_position":room.camera.position,"camera_zoom":room.camera.zoom,"active_command":source_actor.brain.current_skill().get("active",false),"command_kind":source_actor.brain.current_skill().get("kind",""),"connected":room.b05_mechanics.connected(source_actor),"runtime_effects":room.enemy_skills.active_effect_count(),"hp":Game.run.hp}
	# An unchanged simulation snapshot with only the optional detail cards hidden.
	# Essential ground warning, source badge, seed flight and waterline remain on.
	if pose!="idle" and not limited_capture:
		var badges: Array[Dictionary]=[]
		for actor in [source_actor,support_actor]:
			if not is_instance_valid(actor) or not is_instance_valid(actor.body_visual.skill_badge): continue
			var badge: Node2D=actor.body_visual.skill_badge
			badges.append({"node":badge,"show_detail":badge.show_detail})
			badge.show_detail=false;badge.queue_redraw()
		var comparison: Image=await capture_pixels()
		var comparison_name: String=filename.trim_suffix(".png")+"_silhouette.png"
		check(comparison.get_size()==Vector2i(2560,1440) and comparison.save_png(POSE_OUTPUT+comparison_name)==OK,"same-state no-detail silhouette comparison")
		record["silhouette_file"]=comparison_name
		record["feedback_event_count"]=room.impact_feedback.events.size()
		for saved: Dictionary in badges:
			saved.node.show_detail=saved.show_detail;saved.node.queue_redraw()
	check(Game.run.hp==snapshot_hp and is_equal_approx(room.enemy_skills._biome_clock,snapshot_clock),"render waits freeze the whole combat snapshot")
	record["pending_landings"]=[]
	for job: Dictionary in room.enemy_skills.jobs:
		if bool(job.get("b05_landed",false)) and int(job.get("owner_id",0))==source_actor.get_instance_id():
			record.pending_landings.append({"warning_center":job.origin,"locked_target":job.target,"remaining":job.remaining})
	record.merge(extra,true)
	pose_records.append(record)
