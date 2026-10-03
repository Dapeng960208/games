extends Node
## Actual renderer, controlled existing skill phases; not natural-play acceptance.
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const STAGED_PLAYER=[1400,940]
const STAGED_ACTORS={"B08-M01":[1050,1030],"B08-M02":[1720,1080],"B08-M03":[1540,810]}
var room: Node2D
var label: Label
var output: String
var captures: Array[String]=[]
var views: Dictionary={}
var actors: Dictionary={}
var game: Node
func _ready() -> void: run.call_deferred()
func run() -> void:
	game=get_tree().root.get_node("Game")
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or DisplayServer.get_name()=="headless" or not game.profile_path.begins_with("user://test_b08_candidate/") or not OS.get_cmdline_user_args().has("--b08-art-convergence"): get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	if room.sky_environment==null or not room.sky_environment.convergence: get_tree().quit(3); return
	for actor: Node2D in room.enemies.get_children():
		if actor.enemy_id in ["B08-M01","B08-M02","B08-M03"]: actors[actor.enemy_id]=actor
	var ui:=CanvasLayer.new()
	add_child(ui)
	label=Label.new()
	label.position=Vector2(22,16)
	label.add_theme_font_override("font",room.fx_font)
	label.add_theme_font_size_override("font_size",16)
	label.add_theme_color_override("font_color",Color("273949"))
	ui.add_child(label)
	# Existing legal footpoints, normal player camera, and real frozen skills.
	room.player.position=Geometry.point(STAGED_PLAYER)
	for id: String in STAGED_ACTORS: actors[id].position=Geometry.point(STAGED_ACTORS[id])
	room.camera.follow_target(); room.camera.force_update_scroll()
	var archer: Node2D=actors["B08-M01"]
	archer.aim_direction=archer.position.direction_to(room.player.position)
	archer.brain._begin(archer,room.player)
	archer.brain._release(archer)
	archer.native_art.advance(0,archer.brain.phase,archer.brain.action)
	await capture("bow_source_right.png","Right release / frozen bow cue / feather and hit marker remain on physical ground ray")
	room._tick_feathers(.16)
	await capture("bow_ground_flight.png","0.16 seconds after release / source cue ended / unchanged ground feather at 320 world per second")
	room.feathers.clear()
	archer.position=Geometry.point(STAGED_ACTORS["B08-M02"])
	actors["B08-M02"].position=Geometry.point(STAGED_ACTORS["B08-M01"])
	archer.aim_direction=archer.position.direction_to(room.player.position)
	archer.brain._begin(archer,room.player)
	archer.brain._release(archer)
	archer.native_art.advance(0,archer.brain.phase,archer.brain.action)
	game.profile.settings["reduced_fx"]=true
	await capture("bow_source_left_reduced.png","Mirrored release / reduced FX / same physical feather and fixed release-frame outlet")
	game.profile.settings["reduced_fx"]=false
	room.feathers.clear()
	archer.native_art.advance(.2,archer.brain.phase,archer.brain.action)
	var scout: Node2D=actors["B08-M03"]
	scout.aim_direction=scout.position.direction_to(room.player.position)
	scout.brain._begin(scout,room.player)
	scout.native_art.advance(0,scout.brain.phase,scout.brain.action)
	await capture("scout_warning.png","M03 real warning / crouched preparation / unchanged flank destination and duration")
	scout.brain._release(scout)
	scout.brain._land(scout)
	scout.native_art.advance(0,scout.brain.phase,scout.brain.action)
	scout.native_art.advance(.2,scout.brain.phase,scout.brain.action)
	await capture("scout_recovery.png","M03 actual recovery phase / compact crouch / controlled phase proof, not natural combat")
	var clean: bool=await room.cleanup_for_exit()
	var sources: Dictionary=room.sky_environment.snapshot.duplicate(true)
	room.free()
	await get_tree().process_frame
	var report:=FileAccess.open(output.path_join("l43_capture_report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"controlled_actual_renderer_pending_pixel_review","framebuffer":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"views":views,"environment_sources":sources,"audio_cleanup":clean,"hero_world_height_unchanged":112,"limits":["Only three skill keyposes, no walking/back/continuous animation","Staged existing skill phases; not natural combat acceptance","Bow cue links a frozen outlet to the real ground feather; it is not an elevated physical flight", "Flag/vane/exit remain debug props in this minimal slice","Broad platform and incomplete side returns remain","Source and clipped floor unchanged by rendering"]},"\t"))
	print("B08_L43_CAPTURE frames=",captures.size()," clean=",clean," output=",output)
	get_tree().quit(0 if clean and captures.size()==5 else 1)
func capture(file: String,title: String) -> void:
	for actor: Node2D in actors.values():
		if not room.valid_ground(actor.position,actor.navigation_radius):
			push_error("Capture actor outside legal footprint: "+str(actor.enemy_id))
			return
	label.text="B08 L43 CONVERGENCE CANDIDATE | "+title
	room._hud.hide()
	room.queue_redraw(); room._floor_canvas.queue_redraw()
	for actor: Node2D in actors.values(): actor.queue_redraw()
	for _frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	if image.get_size()!=Vector2i(2560,1440) or image.save_png(output.path_join(file))!=OK: push_error("Capture failed "+file); return
	captures.append(file)
	var factor: float=room.camera.zoom.x*float(image.get_width())/get_viewport().get_visible_rect().size.x
	var record: Dictionary={"camera_zoom":room.camera.zoom,"physical_pixels_per_world":factor,"player_position":room.player.position,"reduced_fx":bool(game.profile.settings.get("reduced_fx",false)),"actors":{},"projectiles":room.feathers.size(),"tile_display_pixels":256*factor}
	for id: String in actors:
		var actor: Node2D=actors[id]
		var art=actor.native_art
		var frame: Dictionary=art.frames[art.active_pose]
		var effective:=Vector2(frame.effective_alpha16_size[0],frame.effective_alpha16_size[1])
		record.actors[id]={"phase":actor.brain.phase,"pose":art.active_pose,"file":frame.file,"region":frame.region,"native_foot":art.foot,"physical_position":actor.position,"mirrored":actor.aim_direction.x<-.1,"source_to_world":art.source_scale,"effective_native_pixels":effective,"full_effective_display_pixels":effective*art.source_scale*factor,"nominal_adult_height":art.world_height,"navigation_radius":actor.navigation_radius}
	record["feathers"]=[]
	for shot: Dictionary in room.feathers:
		record.feathers.append({"physical_position":shot.position,"frozen_direction":shot.direction,"remaining":shot.remaining,"visual_launch":shot.get("visual_launch",{}),"launch_strength":room.sky_projectile_art.launch_strength(shot)})
	views[file]=record
