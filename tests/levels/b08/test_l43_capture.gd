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
	room.player.position=Geometry.point([380,960])
	room.camera.follow_target(); room.camera.force_update_scroll()
	await capture("entry_identity.png","Actual entry / 0.85 player camera / M01-03 native identities / partial environment")
	# Staged legal footpoints keep all three adult scales readable in one ordinary
	# player-camera view. Real _begin/_release/_land methods supply frozen phases.
	room.player.position=Geometry.point(STAGED_PLAYER)
	for id: String in STAGED_ACTORS: actors[id].position=Geometry.point(STAGED_ACTORS[id])
	room.camera.follow_target(); room.camera.force_update_scroll()
	for id: String in actors:
		actors[id].aim_direction=actors[id].position.direction_to(room.player.position)
	for id: String in ["B08-M01","B08-M02"]:
		var actor: Node2D=actors[id]
		actor.brain._begin(actor,room.player)
		actor.native_art.advance(0,actor.brain.phase,actor.brain.action)
	await capture("locked_warnings.png","Controlled real warning phases / drawn bow + grounded dive windup / keyposes only")
	game.profile.settings["reduced_fx"]=true
	await capture("locked_warnings_reduced.png","Same locked warnings / reduced FX / fixed ground shadows + original warning geometry")
	game.profile.settings["reduced_fx"]=false
	for id: String in ["B08-M01","B08-M02"]:
		var actor: Node2D=actors[id]
		actor.brain._release(actor)
		actor.native_art.advance(0,actor.brain.phase,actor.brain.action)
	room._tick_feathers(.08)
	actors["B08-M02"].brain.tick(actors["B08-M02"],.08,room.player)
	actors["B08-M02"]._finish_motion(.08)
	await capture("release_and_dive.png","Real release/transit states / native feather projectile / folded-wing dive / same hit proxies")
	actors["B08-M01"].native_art.advance(.2,actors["B08-M01"].brain.phase,actors["B08-M01"].brain.action)
	actors["B08-M02"].brain._land(actors["B08-M02"])
	actors["B08-M02"].native_art.advance(0,actors["B08-M02"].brain.phase,actors["B08-M02"].brain.action)
	var scout: Node2D=actors["B08-M03"]
	scout.brain._begin(scout,room.player)
	scout.brain._release(scout)
	scout.brain._land(scout)
	scout.native_art.advance(0,scout.brain.phase,scout.brain.action)
	await capture("landing_and_stab.png","Controlled ground recovery + scout stab / crouch stays lower / no continuous animation claim")
	var clean: bool=await room.cleanup_for_exit()
	var sources: Dictionary=room.sky_environment.snapshot.duplicate(true)
	room.free()
	await get_tree().process_frame
	var report:=FileAccess.open(output.path_join("l43_capture_report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"controlled_actual_renderer_pending_pixel_review","framebuffer":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"views":views,"environment_sources":sources,"audio_cleanup":clean,"hero_world_height_unchanged":112,"limits":["Only three skill keyposes, no walking/back/continuous animation","Staged existing skill phases; not natural combat acceptance","Flag/vane/exit remain debug props in this minimal slice","Broad platform and incomplete side returns remain","Source and clipped floor unchanged by rendering"]},"\t"))
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
	views[file]=record
