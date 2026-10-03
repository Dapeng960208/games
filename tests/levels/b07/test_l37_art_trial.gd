extends Node
## Bounded optional graphical capture. Writes only the managed B07 output root.
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
var failures:=0
var capture_size:=Vector2i(1280,720)
func check(ok: bool, label: String) -> void:
	if not ok: failures+=1; push_error("B07 ART TRIAL "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var out:=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if out.is_empty() or not Game.profile_path.begins_with("user://test_b07_candidate/"): get_tree().quit(2); return
	var launch:=Launcher.new()
	launch.auto_start=false
	launch.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(launch)
	check(launch.start_candidate("CH01",0,false),"isolated launcher "+launch.last_error)
	if not is_instance_valid(launch.room): launch.free(); get_tree().quit(1); return
	var room: Node2D=launch.room
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.camera.process_mode=Node.PROCESS_MODE_DISABLED
	room.camera.target=null
	room.combat_audio.audible=false
	var backdrop: Node2D=room.get_node("MineBackdrop")
	if "--b07-art-trial" not in OS.get_cmdline_user_args():
		check(not is_instance_valid(backdrop.b07_art_trial),"trial art remains opt-in")
		check(not room.camera.b07_art_overscan,"ordinary candidate camera remains unchanged")
		check(preload("res://scripts/levels/b07/art/native_art.gd").entry("B07-M01").is_empty(),"unaccepted pilot is not auto-enabled")
		check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
		launch.free(); Game.run=null
		print("B07 ART TRIAL disabled-gate checks, failures=",failures)
		get_tree().quit(1 if failures else 0); return
	var midground_review: bool="--b07-midground-trial" in OS.get_cmdline_user_args()
	check(is_instance_valid(backdrop.b07_art_trial) and backdrop.b07_art_trial.layers.size()==(4 if midground_review else 3),"registered canyon, terrace, guardian and optional review inset")
	if midground_review:
		var review: Sprite2D=backdrop.b07_art_trial.layers.back()
		check(review.texture==backdrop.b07_art_trial.layers[0].texture,"midground reuses original source texture")
		check(review.material.get_shader_parameter("exterior"),"review inset excludes authoritative floor")
		check(backdrop.b07_art_trial.layers[0].region_rect==Rect2(0,380,1552,633),"canyon backdrop excludes duplicate distant city")
		room.camera.configure(room,room.player,room.ARENA,backdrop.painted_bounds())
		check(room.camera.b07_north_review and room.camera.position==room.player.position+Vector2(160,-160),"north review configures real follow bias")
		check(backdrop.b07_art_trial.guardian_plinth.position==Vector2(0,160)*Geometry.SCALE,"decorative support moves with guardian")
	check(is_instance_valid(backdrop.b07_art_trial.foundation) and not backdrop.b07_art_trial.foundation.faces.is_empty(),"authored foundation follows exterior edges")
	check(backdrop.b07_art_trial.foundation.faces.size()==3,"no wall on full vertical west edge")
	check(is_instance_valid(backdrop.b07_art_trial.guardian_plinth),"guardian has separate supported plinth")
	check(room.ground_polygon==Geometry.polygon("L37"),"authoritative floor collision unchanged")
	check(room.layout.obstructions.size()==2,"two authored stone covers retained")
	for actor: Node2D in room.enemies.get_children():
		if actor.enemy_id!="B07-M01": continue
		var body: Dictionary=actor.body_visual.body_frame()
		check(body.get("source_family")=="storybook_2_5d_v1" and body.get("full_color",false),"M01 installs native full-color idle")
		check(actor.body_visual._bank.is_empty(),"idle pilot never borrows an old motion bank")
		check(actor.body_visual._foot==Vector2(0,18),"M01 uses the exact ordinary foot anchor")
		var factor: float=body.bounds.size.y/body.region.size.y
		check(absf(factor*824.5-82.08)<.001,"M01 anatomy82.08 and hero112 stay unchanged")
		check(body.texture.get_size()==Vector2(1254,1254),"original source pixels preserved")
	check(preload("res://scripts/levels/b07/art/native_art.gd").entry("B07-M02").is_empty(),"other species do not borrow M01 art")
	if DisplayServer.get_name()=="headless":
		check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
		launch.free(); Game.run=null
		print("B07 ART TRIAL structural checks, failures=",failures)
		get_tree().quit(1 if failures else 0); return
	RenderingServer.set_default_clear_color(Color("72593a"))
	var label_layer:=CanvasLayer.new()
	add_child(label_layer)
	var label:=Label.new()
	label.text="L37 FLOOR MATERIAL TRIAL | perimeter and actor pilot art / other species pending"
	label.position=Vector2(16,12)
	label.add_theme_color_override("font_color",Color("fff4ca"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	label_layer.add_child(label)
	get_window().content_scale_size=Vector2i(1280,720)
	capture_size=Vector2i(2560,1440) if "--b07-capture-2k" in OS.get_cmdline_user_args() else Vector2i(1280,720)
	get_window().size=capture_size
	await get_tree().process_frame
	# Use the unmodified production entry-follow setup before overview overrides.
	# The Camera2D limits, not a manually centered view, must cover the viewport.
	room.camera.configure(room,room.player,room.ARENA,backdrop.painted_bounds())
	room.camera.follow_target()
	room.camera.force_update_scroll()
	label.text="L37 ENTRY FOLLOW 0.72 | canyon-gate + M01 idle pilots; other art pending"
	if midground_review:
		check(room.camera.zoom.is_equal_approx(Vector2(.72,.72)),"north review preserves actual .72 world zoom")
		label.position.y=680
		label.text="L37 NORTH COMPOSITION REVIEW | actual follow (+160,-160); city crop / floor ratio unaccepted"
	await _capture(out.path_join("L37_canyon_entry_follow.png"))
	var extent: Vector2=get_viewport().get_visible_rect().size/room.camera.zoom
	var actual_view:=Rect2(room.camera.get_screen_center_position()-extent*.5,extent)
	check(backdrop.painted_bounds().grow(1).encloses(actual_view),"production entry view stays inside painted coverage")
	print("B07 entry view=",actual_view," coverage=",backdrop.painted_bounds()," zoom=",room.camera.zoom)
	if "--b07-entry-only" in OS.get_cmdline_user_args():
		check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
		launch.free(); Game.run=null
		print("B07 ENTRY REVIEW captured ",out," failures=",failures)
		get_tree().quit(1 if failures else 0); return
	# A directed real M01 warning at the same actual entry camera/zoom.
	for actor: Node2D in room.enemies.get_children():
		if actor.enemy_id!="B07-M01": continue
		actor.position=room.player.position+Vector2(120,-20)
		actor.brain.configure(actor.profile)
		actor.brain.tick(actor,.81,room.player)
		var tell: Dictionary=actor.brain.current_telegraph()
		if not tell.is_empty(): actor.brain.tick(actor,float(tell.tell)+.01,room.player)
		actor.body_visual.advance(.01)
		actor.queue_redraw()
		break
	var alpha_actor=room.spawn_enemy(Geometry.world_point([160,1100]),"B07-M01",31,{"profile":preload("res://scripts/levels/b07/combat/enemy_skills.gd").profile("B07-M01",31,0),"reward_enabled":false})
	alpha_actor.training_ai_disabled=true
	alpha_actor.aim_direction=Vector2.RIGHT
	alpha_actor.body_visual.advance(.01)
	alpha_actor.queue_redraw()
	room.enemy_telegraphs.refresh()
	label.text="L37 ACTUAL ENTRY 0.72 | directed M01 warning / text readability; pilot art / other species pending"
	await _capture(out.path_join("L37_entry_warning_readability.png"))
	room.camera.target=null
	label.text="L37 COMPOSITION OVERVIEW | canyon-gate trial; perimeter and actor pilot art / other species pending"
	room.camera.position_smoothing_enabled=false
	room.camera.limit_left=-10000; room.camera.limit_right=10000
	room.camera.limit_top=-10000; room.camera.limit_bottom=10000
	room.camera.zoom=Vector2(.4,.4)
	room.camera.position=Vector2(812,406)
	room.camera.force_update_scroll()
	await _capture(out.path_join("L37_canyon_overview.png"))
	room.player.position=Geometry.world_point([980,630])
	room.b07_mechanics.state.mirrors[room.b07_mechanics.state.mirrors.keys()[0]]=1
	room.b07_mechanics.tick(.01)
	label.text="L37 MIRROR / M01 ALPHA DETAIL 0.75 | single idle pilot; other actor pilot art / other species pending"
	room.camera.zoom=Vector2(.75,.75)
	room.camera.position=Vector2(350,550)
	room.camera.force_update_scroll()
	await _capture(out.path_join("L37_canyon_mirror_m01_detail.png"))
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	launch.free(); Game.run=null
	print("B07 ART TRIAL captured ",out," failures=",failures)
	get_tree().quit(1 if failures else 0)
func _capture(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame:=get_viewport().get_texture().get_image()
	check(frame!=null and not frame.is_empty(),"frame readable")
	if frame!=null:
		check(frame.get_size()==capture_size,"actual output resolution "+str(capture_size))
		check(frame.save_png(path)==OK,"write managed PNG")
