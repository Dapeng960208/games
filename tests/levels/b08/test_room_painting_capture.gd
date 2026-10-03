extends Node
## Three controlled post-draw observations of the independent mother and shared HUD.
var room
var output: String
var captures: Array=[]
var original_hash: String
var profile_existed: bool
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()
func run() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or DisplayServer.get_name()=="headless" or not Game.profile_path.begins_with("user://test_b08_candidate/"):
		get_tree().quit(2); return
	profile_existed=FileAccess.file_exists(Game.profile_path)
	original_hash=FileAccess.get_sha256(Game.profile_path) if profile_existed else ""
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	if not room.painting_ready() or room.candidate_ui==null:
		push_error("Painting or shared HUD unavailable"); get_tree().quit(3); return
	await capture("painting_entry.png","original entry; finite encounter frozen for source/mapping review")
	room.player.position=Vector2(812,340)
	room.player.clear_movement_target()
	await capture("painting_north_bypass.png","original north wind-free path; full radius40 swept route already tested")
	room.player.position=room.layout.entry
	room.candidate_ui.show_backpack()
	await get_tree().process_frame
	await capture("painting_shared_backpack.png","existing read-only backpack and character UI, real modal pause")
	var clean: bool=await room.cleanup_for_exit()
	room.free()
	Game.reload_profile()
	await get_tree().process_frame
	var unchanged: bool=FileAccess.file_exists(Game.profile_path)==profile_existed and (not profile_existed or FileAccess.get_sha256(Game.profile_path)==original_hash)
	var report: Dictionary={"status":"controlled_renderer_review_pending","framebuffer":[2560,1440],"logical_viewport":[1280,720],"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"audio_cleanup":clean,"isolated_profile_unchanged":unchanged,"limits":["Frozen AI and controlled camera targets, not natural combat acceptance","Independent mother only; six native detail repaints not accepted","Derived local hole patch remains slightly softer than the original mother","Shared mini-map shows real anchors, not an inaccurate convex floor fill"]}
	var file:=FileAccess.open(output.path_join("room_painting_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("B08_ROOM_PAINTING_CAPTURE frames=",captures.size()," clean=",clean," profile_unchanged=",unchanged," output=",output)
	get_tree().quit(0 if captures.size()==3 and clean and unchanged else 1)
func capture(name: String, scope: String) -> void:
	room.camera.follow_target(); room.camera.force_update_scroll()
	if room.sky_interactions!=null: room.sky_interactions.sync(1)
	room._floor_canvas.queue_redraw(); room.queue_redraw()
	if room.candidate_ui!=null: room.candidate_ui.hud.refresh()
	await RenderingServer.frame_post_draw
	var img:=get_viewport().get_texture().get_image()
	if img.get_size()!=Vector2i(2560,1440): push_error("Unexpected physical framebuffer: "+str(img.get_size())); return
	var target:=output.path_join(name)
	if img.save_png(target)!=OK: push_error("Could not save framebuffer"); return
	var actors: Array=[]
	for actor: Node2D in room.enemies.get_children():
		actors.append({"id":actor.enemy_id,"foot":actor.position,"radius":actor.navigation_radius,"legal_full_circle":room.valid_ground(actor.position,actor.navigation_radius),"pose":actor.native_art.active_pose if actor.native_art!=null else "runtime_prop"})
	captures.append({"file":name,"sha256":FileAccess.get_sha256(target),"scope":scope,"sample":"same frame_post_draw as PNG","player_foot":room.player.position,"player_legal_full_circle":room.valid_ground(room.player.position,Balance.PLAYER_RADIUS),"camera_center":room.camera.get_screen_center_position(),"zoom":room.camera.zoom,"world_rect":room.painted_mapping.world_rect,"source_pixels":[1536,1024],"source_to_frame_pixel_scale":room.painted_mapping.world_rect.size/Vector2(1536,1024)*room.camera.zoom*2,"source_sha256":room.painted_mapping.definition.metadata.qa.sha256,"actors":actors,"modal_paused":get_tree().paused,"wind_direction":room.wind.direction("lane_0",Vector2.RIGHT),"native_detail_loaded":room.get_node("MineBackdrop").environment_chunks.native_detail!=null})
