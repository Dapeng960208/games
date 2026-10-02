extends "res://tests/test_environment_clarity.gd"
## Candidate-only art pilot using the production camera, backdrop and actors.
## Never opens B05 in the route catalog or writes an actual player profile.
const B05Layouts = preload("res://scripts/world/b05_room_layouts.gd")
const B05Geometry = preload("res://scripts/world/b05_room_geometry.gd")
const Verge = preload("res://scripts/world/b05_boundary_verge.gd")
const Mechanisms = preload("res://scripts/world/b05_room_mechanisms.gd")
const PILOT_OUTPUT := "res://artifacts/b05-environment-pilot/"
func _run() -> void:
	if not Game.profile_path.contains("test_b05_environment_pilot") or DisplayServer.get_name()=="headless":
		push_error("B05 pilot requires its isolated profile and graphical display")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PILOT_OUTPUT))
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":25001}),"isolated baseline starts")
	Words.set_locale("zh_CN")
	room=load("res://scenes/room.tscn").instantiate()
	room.spawn_enabled=false
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await frames()
	if is_instance_valid(room.objectives): room.objectives.free()
	room.objectives=null
	room.relic_positions.clear()
	if is_instance_valid(room.enemy_props): room.enemy_props.clear(); room.enemy_props.hide()
	if is_instance_valid(room._depth_canvas): room._depth_canvas.hide()
	for actor in room.enemies.get_children(): actor.free()
	room.layout = B05Layouts.build("L25",25001)
	room.layout_id = "L25"
	room.expedition_context={"biome_id":"B05","room_id":"L25","role":"branch","difficulty":0,"seed":25001}
	room._configure_ground_boundary()
	room.obstructions.assign(room.layout.obstructions)
	room._configure_world_view()
	room.player.position=B05Geometry.world_point([1344,900])
	room.b05_mechanics=Mechanisms.new()
	room.add_child(room.b05_mechanics)
	check(room.b05_mechanics.configure_room(room,B05Geometry.room("L25"),0),"production rootwell configures")
	var overlay:=Verge.new()
	room.add_child(overlay)
	check(overlay.configure(room.layout,true),"candidate exterior verge loads")
	var native=preload("res://scripts/world/environment_detail.gd").new()
	var backdrop=room.get_node("MineBackdrop")
	check(native.configure("L25",backdrop.environment_world_rect,true),"six true native detail tiles load")
	backdrop.environment_chunks.add_child(native)
	check(native.tiles.size()==6,"complete six-tile pack")
	layer=CanvasLayer.new();add_child(layer)
	hud=load("res://scenes/hud.tscn").instantiate();hud.room=room;layer.add_child(hud);hud.set_process(false)
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	var ground_before=room.ground_polygon.duplicate()
	var views={"center":Vector2(.5,.5),"northwest":Vector2(.2,.2),"northeast":Vector2(.8,.2),"southwest":Vector2(.2,.8),"southeast":Vector2(.8,.8),"west_portal":Vector2(.2,.5),"east_portal":Vector2(.8,.5)}
	for label: String in views:
		room.player.position=room.clamp_actor(Art.environment_point(room.layout.arena,"B05",views[label],"L25"),30)
		room.camera.follow_target();room.camera.force_update_scroll()
		hud.visible=label=="center"
		for enabled in [false,true]:
			overlay.visible=enabled
			native.visible=enabled
			var image: Image=await capture_pixels()
			check(image.get_size()==Vector2i(2560,1440),"actual 2K framebuffer")
			check(image.save_png(PILOT_OUTPUT+label+("_native" if enabled else "_base")+".png")==OK,"pilot capture")
	Game.profile.settings.reduced_fx=true
	room.player.position=B05Geometry.world_point([1904,720]);room.camera.follow_target();room.camera.force_update_scroll()
	var reduced: Image=await capture_pixels()
	check(reduced.save_png(PILOT_OUTPUT+"reduced_rootwell.png")==OK,"reduced effects rootwell capture")
	check(ground_before==room.ground_polygon,"art overlay leaves frozen ground identical")
	check(B05Geometry.route_is_clear("L25","main_route",180) and B05Geometry.route_is_clear("L25","safe_route",140),"frozen route widths preserved")
	check(await room.combat_audio.wait_for_cleanup(),"audio fixture cleanup")
	layer.free();room.free();Game.run=null
	print("B05_ENVIRONMENT_PILOT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
