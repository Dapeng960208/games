extends "res://tests/levels/b08/test_l43_capture.gd"
## Controlled real interactions, six frames, normal player-follow camera.
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
	if room.sky_interactions==null: get_tree().quit(3); return
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
	var art=room.sky_interactions
	room.input_blocked=false; room.release_gate=false
	await capture("props_entry.png","Native L43 interactive props / normal player entry / exit actually locked")
	room.player.position=art.lane.vane
	room.interact(); room.wind.advance(.6)
	room.player.position=art.flag_body.position+Vector2(0,-20)
	game.profile.settings["reduced_fx"]=true
	await capture("props_warning_occlusion.png","Real one-second wind warning / unchanged live direction / flag fades behind hero / reduced FX")
	room.wind.advance(1)
	room.player.position=art.flag_body.position+Vector2(0,30)
	game.profile.settings["reduced_fx"]=false
	await capture("props_reverse.png","Actual reverse wind / pointer mirrored about spindle / flag opacity restored")
	room.player.position=art.lane.vane+Vector2(0,28)
	room.interact(); room.wind.advance(1.6)
	await capture("props_crosswind.png","Actual third wind state / independently painted up pointer / same base and interaction point")
	room._flag.health.current=0; room._flag._die()
	await get_tree().process_frame
	await capture("props_flag_broken.png","Real flag death / matched base foot / original eight-second suppression / no debris collider")
	for actor: Node2D in room.enemies.get_children():
		if not actor.static_actor: actor.health.current=0; actor._die()
	actors.clear()
	await get_tree().process_frame
	room._next_wave=room._authored_waves.size() # Controlled terminal encounter state.
	room.player.position=room.exit_position+Vector2(-85,30)
	await capture("props_exit_ready.png","Controlled cleared-state exit / same physical destination / flat winged waymark")
	var clean: bool=await room.cleanup_for_exit()
	room.free()
	await get_tree().process_frame
	var report:=FileAccess.open(output.path_join("l43_props_report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"controlled_actual_renderer_pending_pixel_review","framebuffer":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"views":views,"audio_cleanup":clean,"limits":["Controlled state fixtures; not natural encounter completion", "Only L43 props; room and other actors remain partial", "Source alpha untouched; spindle seating and broken base fit need pixel review"]},"\t"))
	print("B08_L43_PROPS_CAPTURE frames=",captures.size()," clean=",clean," output=",output)
	get_tree().quit(0 if clean and captures.size()==6 else 1)
func capture(file: String, title: String) -> void:
	room.sky_interactions.sync(1)
	room.camera.follow_target(); room.camera.force_update_scroll()
	await super.capture(file,title)
	if not views.has(file): return
	var art=room.sky_interactions
	var sizes: Dictionary={}
	for kind: String in art.frames:
		var frame: Dictionary=art.frames[kind]
		sizes[kind]={"effective_native_pixels":frame.effective_alpha16_size,"max_display_pixels":Vector2(frame.effective_alpha16_size[0],frame.effective_alpha16_size[1])*float(frame.world_per_source_pixel)*1.7}
	views[file]["interaction"]={"vane_foot":art.vane_body.position,"flag_foot":art.flag_body.position,"vane_alpha":art.vane_body.modulate.a,"flag_alpha":art.flag_body.modulate.a,"flag_broken":art.flag_broken,"exit_ready":room.exit_ready(),"direction":room.wind.direction(art.lane.id,art.lane.direction),"pointer":art.pointer_kind(),"channel":room.wind.channel.duplicate(),"pending":room.wind.pending.duplicate(),"suppression_remaining":maxf(0,room.wind.suppressed_until-room.wind.now),"sources":sizes}
