extends "res://tests/levels/b08/test_l43_props_capture.gd"
## One fixed entry view, optional source assembly off/on. No camera substitution.
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
	var environment=room.sky_environment
	if environment==null or not environment.edge_joint_review: get_tree().quit(3); return
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
	environment.edge_joint_review=false; environment.queue_redraw()
	await capture("joints_off.png","Unchanged entry / optional southern foundation samples OFF / 0.85 player camera")
	environment.edge_joint_review=true; environment.queue_redraw()
	await capture("joints_on.png","Same entry / west broad foundation + east narrow buttress / strict south-baseline clipping")
	var sources: Dictionary=environment.snapshot.duplicate(true)
	var joints: Array=[]
	for layer: Dictionary in environment.layers:
		if bool(layer.get("edge_joint",false)): joints.append({"file":layer.file,"native_draw_rect":layer.rect,"clipped_polygons":layer.shapes})
	var clean: bool=await room.cleanup_for_exit()
	room.free()
	await get_tree().process_frame
	var report:=FileAccess.open(output.path_join("l43_joints_report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"optional_composition_review_not_default","framebuffer":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"views":views,"sources":sources,"joints":joints,"audio_cleanup":clean,"limits":["Two convex foundation samples only, no complete side return", "Broad angled cap is runtime-clipped at the true south baseline", "No new geometry, collision, camera, exit or profile change"]},"\t"))
	print("B08_L43_JOINTS_CAPTURE frames=",captures.size()," clean=",clean," output=",output)
	get_tree().quit(0 if clean and captures.size()==2 else 1)
