extends "res://tests/levels/b05/test_b05_environment_rooms.gd"
## Diagnostic full-room camera; does not change the production camera zoom.
var overview_saved: Dictionary={}
func _run() -> void:
	capture_root=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if capture_root.is_empty() or not Game.profile_path.contains("test_b05_environment_overview"):
		get_tree().quit(2);return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":251001}),"isolated overview baseline")
	get_window().content_scale_size=Vector2i(1280,720);get_window().size=Vector2i(2560,1440)
	for id: String in ["L25","L26","L27","L28","L29","L30","BO05"]:
		await inspect_room(id)
	Game.run=null
	print("B05_ENVIRONMENT_OVERVIEW checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
func record(label: String) -> void:
	var id:=label.split("_")[0]
	if overview_saved.has(id):return
	overview_saved[id]=true
	var bounds:Rect2=room.get_node("MineBackdrop").environment_world_rect
	room.camera.target=null
	room.camera.limit_left=-100000;room.camera.limit_top=-100000
	room.camera.limit_right=100000;room.camera.limit_bottom=100000
	var extent:Vector2=get_viewport().get_visible_rect().size
	room.camera.zoom=Vector2.ONE*minf(extent.x/bounds.size.x,extent.y/bounds.size.y)*.98
	room.camera.global_position=bounds.get_center();room.camera.force_update_scroll()
	var pixels:Image=await capture_pixels()
	check(pixels.get_size()==Vector2i(2560,1440),id+" overview 2K framebuffer")
	check(pixels.save_png(capture_root.path_join(id+"_overview.png"))==OK,id+" overview saved")
