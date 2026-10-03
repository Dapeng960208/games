extends Node
## Controlled actual-renderer capture; images/logs stay in managed output only.
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
var room: Node2D
var output: String
var captures: Array[String]=[]
var sampling: Dictionary={}
var sampling_by_view: Dictionary={}
var camera_by_view: Dictionary={}
var game: Node
func _ready() -> void: run.call_deferred()
func run() -> void:
	game=get_tree().root.get_node("Game")
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or DisplayServer.get_name()=="headless" or not game.profile_path.begins_with("user://test_b08_candidate/"): get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	if not is_instance_valid(room.sky_environment): get_tree().quit(3); return
	var ui:=CanvasLayer.new()
	room.add_child(ui)
	var label:=Label.new()
	label.position=Vector2(22,16)
	label.add_theme_font_override("font",room.fx_font)
	label.add_theme_font_size_override("font_size",16)
	label.add_theme_color_override("font_color",Color("273949"))
	label.text="B08 L43 candidate / partial art / M01 idle only / remaining actors and props debug"
	var background_depth := OS.get_cmdline_user_args().has("--b08-art-background-depth-review")
	if background_depth: label.text="B08 L43 DEPTH REVIEW / original 0.85 player camera / distant layer 45% / partial art"
	ui.add_child(label)
	room.player.position=Geometry.point([380,960])
	room.camera.follow_target(); room.camera.force_update_scroll()
	await capture("entry_flow.png")
	if not OS.get_cmdline_user_args().has("--b08-capture-entry-only"):
		room.player.position=Geometry.point([1400,460])
		room.camera.follow_target(); room.camera.force_update_scroll()
		await capture("north_flow.png")
		room.wind.advance(.5)
		room._floor_canvas.queue_redraw()
		await capture("north_flow_moved.png")
		game.profile.settings["reduced_fx"]=true
		room._floor_canvas.queue_redraw()
		await capture("north_flow_reduced.png")
		room.wind.begin_turn("lane_0","player")
		room.wind.advance(.6)
		room._floor_canvas.queue_redraw()
		await capture("north_switch_warning.png")
	var clean: bool=await room.cleanup_for_exit()
	var snapshot: Dictionary=room.sky_environment.snapshot.duplicate(true)
	room.free()
	await get_tree().process_frame
	var report:=FileAccess.open(output.path_join("visual_capture_report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"candidate_pending_actual_pixel_review","background_depth_review":background_depth,"distant_source_strength":.45 if background_depth else 1.0,"camera_by_view":camera_by_view,"captures":captures,"actual_framebuffer":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"environment_sources":snapshot,"sampling":sampling,"sampling_by_view":sampling_by_view,"m01_anatomical_source_pixels":937,"m01_world_body_height":100,"hero_body_height_unchanged":112,"audio_cleanup":clean,"remaining":["broad rectangular floor silhouette","north-view depth cropping","complete edge architecture","other actor native bodies","M01 non-idle/back/walk poses","flag/vane/exit native props","natural combat/hardware acceptance"]},"\t"))
	print("B08_VISUAL_CAPTURE frames=",captures.size()," clean=",clean," output=",output)
	get_tree().quit(0 if clean and captures.size()==(1 if OS.get_cmdline_user_args().has("--b08-capture-entry-only") else 5) else 1)
func capture(file: String) -> void:
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	if image.get_size()!=Vector2i(2560,1440) or image.save_png(output.path_join(file))!=OK: push_error("Capture failed "+file); return
	captures.append(file)
	sampling_by_view[file]={}
	var physical_per_world: float=room.camera.zoom.x*float(image.get_width())/get_viewport().get_visible_rect().size.x
	var view_size: Vector2=get_viewport().get_visible_rect().size/room.camera.zoom
	var view:=Rect2(room.camera.get_screen_center_position()-view_size*.5,view_size)
	camera_by_view[file]={"zoom":room.camera.zoom,"world_view":view,"player_world_position":room.player.position}
	var environment: Node2D=room.sky_environment
	var rects: Dictionary={"floor_surface.png":Rect2(0,0,1624,1044),"distant_city.png":Rect2(0,0,1624,1044)}
	for layer: Dictionary in environment.layers: rects[layer.file]=layer.rect
	for name: String in rects:
		var rect: Rect2=rects[name]
		var native: Vector2=environment.snapshot[name].size
		var visible: Vector2=rect.intersection(view).size*physical_per_world
		var previous: Vector2=sampling.get(name,{}).get("max_visible_draw_rect_pixels",Vector2.ZERO)
		sampling_by_view[file][name]={"native_pixels":native,"visible_draw_rect_pixels":visible,"full_draw_rect_pixels":rect.size*physical_per_world,"native_to_display_scale_xy":rect.size*physical_per_world/native}
		sampling[name]={"native_pixels":native,"full_draw_rect_pixels":rect.size*physical_per_world,"max_visible_draw_rect_pixels":previous.max(visible),"native_to_display_scale_xy":rect.size*physical_per_world/native,"bound_scope":"Draw-rectangle bounds; exact floor/exterior masks further reduce visible coverage."}
	sampling["m01_idle"]={"native_canvas_pixels":Vector2(1254,1254),"native_anatomical_height":937,"display_anatomical_height":100*physical_per_world,"native_to_display_scale":100.0/937.0*physical_per_world,"pose_coverage":"idle only; no authored action/walk/back bank"}
