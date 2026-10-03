extends "res://tests/levels/b05/test_b05_environment_rooms.gd"
## Separate limited source/camera QA for L26,L30 and BO05.
func _run() -> void:
	capture_root=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if capture_root.is_empty() or not Game.profile_path.contains("test_b05_outer_environment"):
		get_tree().quit(2);return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":30001}),"isolated outer-room baseline")
	get_window().content_scale_size=Vector2i(1280,720);get_window().size=Vector2i(2560,1440)
	for id: String in ["L26","L30","BO05"]:
		if not OS.get_cmdline_user_args().has("--room="+id) and OS.get_cmdline_user_args().has("--capture-one"):continue
		await inspect_room(id)
	Game.run=null
	print("B05_OUTER_ENVIRONMENT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
