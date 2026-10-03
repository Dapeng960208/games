extends "res://tests/test_environment_clarity.gd"
## Candidate-only middle-room source mapping and actual-camera evidence.
const LayoutsB05=preload("res://scripts/world/b05_room_layouts.gd")
const GeometryB05=preload("res://scripts/world/b05_room_geometry.gd")
const HostB05=preload("res://scripts/world/b05_room_mechanisms.gd")
const SOURCE_RECTS=[[0,0,520,528],[504,0,528,528],[1016,0,520,528],[0,504,520,520],[504,504,528,520],[1016,504,520,520]]
const DetailB05=preload("res://scripts/world/environment_detail.gd")
var capture_root:=""
func _run() -> void:
	capture_root=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if capture_root.is_empty() or not Game.profile_path.contains("test_b05_environment_rooms"):
		get_tree().quit(2);return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":27001}),"isolated baseline")
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	for id: String in ["L27","L28","L29"]:
		if not OS.get_cmdline_user_args().has("--room="+id) and OS.get_cmdline_user_args().has("--capture-one"):continue
		await inspect_room(id)
	Game.run=null
	print("B05_ENVIRONMENT_ROOMS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
func inspect_room(id: String) -> void:
	room=load("res://scenes/room.tscn").instantiate()
	room.spawn_enabled=false;room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room);await frames()
	for actor in room.enemies.get_children(): actor.free()
	if is_instance_valid(room.objectives):room.objectives.free()
	room.objectives=null;room.relic_positions.clear()
	if is_instance_valid(room.enemy_props):room.enemy_props.clear();room.enemy_props.hide()
	if is_instance_valid(room._depth_canvas):room._depth_canvas.hide()
	room.layout=LayoutsB05.build(id,27001);room.layout_id=id
	room.expedition_context={"biome_id":"B05","room_id":id,"role":"branch","difficulty":0,"seed":27001}
	room._configure_ground_boundary();room.obstructions.assign(room.layout.obstructions)
	room._configure_world_view()
	var frozen:PackedVector2Array=room.ground_polygon.duplicate()
	room.b05_mechanics=HostB05.new();room.add_child(room.b05_mechanics)
	check(room.b05_mechanics.configure_room(room,GeometryB05.room(id),0),id+" production mechanisms")
	var backdrop=room.get_node("MineBackdrop")
	backdrop.configure_layout(room.layout,true)
	var native=backdrop.environment_chunks.native_detail
	check(is_instance_valid(native) and native.tiles.size()==6,id+" six candidate native tiles")
	var strict:=DetailB05.new()
	check(not strict.configure(id,backdrop.environment_world_rect),id+" candidates stay off without explicit opt-in")
	strict.free()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/world/rooms_2k/"+id+"/manifest.json"))
	for index in range(6):
		var spec:Dictionary=manifest.tiles[index];var tile:Sprite2D=native.tiles[index]
		var frozen_rect_matches:=true
		for component in range(4):frozen_rect_matches=frozen_rect_matches and float(spec.source_rect[component])==float(SOURCE_RECTS[index][component])
		check(frozen_rect_matches,id+" frozen source rectangle "+spec.id)
		var source:=Rect2(spec.source_rect[0],spec.source_rect[1],spec.source_rect[2],spec.source_rect[3])
		var expected:Vector2=backdrop.environment_world_rect.position+source.position/Vector2(1536,1024)*backdrop.environment_world_rect.size
		check(tile.position.is_equal_approx(expected),id+" source origin "+spec.id)
		check((tile.scale*tile.texture.get_size()).is_equal_approx(source.size/Vector2(1536,1024)*backdrop.environment_world_rect.size),id+" independent native dimensions "+spec.id)
		check(tile.material.get_shader_parameter("feather_width")==Vector2(16,24),id+" 16x24 source overlap feather "+spec.id)
		check(FileAccess.get_sha256(spec.texture)==str(spec.get("webp_sha256",spec.generated_png_sha256)),id+" immutable native hash "+spec.id)
	var definition:=GeometryB05.room(id)
	check(GeometryB05.route_is_clear(id,"main_route",definition.main_route_width_world),id+" frozen full-width main route")
	check(GeometryB05.route_is_clear(id,"safe_route",definition.safe_route_width_world),id+" frozen full-width alternate route")
	if id=="L27":
		var v:Array=definition.voids[0]
		check(is_instance_valid(backdrop.b05_fixed_void) and backdrop.b05_fixed_void.world_rect.is_equal_approx(Rect2(GeometryB05.world_point([v[0],v[1]]),GeometryB05.world_point([v[2],v[3]]))),"L27 void exact collision rectangle")
	if DisplayServer.get_name()!="headless":
		var views={"center":Vector2(.5,.5),"southwest":Vector2(.2,.8)}
		if id in ["L26","L29","BO05"]:views["southeast"]=Vector2(.8,.8)
		if id=="L27":views["west_entry"]=Vector2(.16,.5)
		for label:String in views:
			var target:Vector2=room.clamp_actor(Art.environment_point(room.layout.arena,"B05",views[label],id),30)
			if not room.valid_ground(target,30):target=room.move_actor(room.layout.entry,target-room.layout.entry,30)
			check(room.valid_ground(target,30),id+" legal camera actor anchor "+label)
			room.player.position=target
			room.camera.follow_target();room.camera.force_update_scroll()
			await record(id+"_"+label)
	if id=="L29":
		check(room.b05_mechanics._sunleaf_visuals.size()==2,"L29 both leaf visual states loaded")
		for visual:Node2D in room.b05_mechanics._sunleaf_visuals:
			check(visual.states.size()==2 and visual.canvas_size==Vector2(140,140),"L29 unchanged full-canvas state sizing")
		room.set_input_blocked(false);room.release_gate=false
		room.player.position=GeometryB05.world_point([980,720]);room.camera.follow_target();room.camera.force_update_scroll()
		check(room.b05_mechanics.toggle_sunleaf("L29-sunleaf-west",room.player),"L29 production leaf toggle")
		check(room.b05_mechanics._sunleaf_closed["L29-sunleaf-west"] and not room.b05_mechanics._sunleaf_closed["L29-sunleaf-east"],"L29 independently closed west")
		if DisplayServer.get_name()!="headless":await record("L29_sunleaf_closed")
	check(frozen==room.ground_polygon,id+" art leaves frozen geometry unchanged")
	check(await room.combat_audio.wait_for_cleanup(),id+" audio cleanup")
	room.free();await frames()
func record(label:String) -> void:
	var pixels:Image=await capture_pixels()
	check(pixels.get_size()==Vector2i(2560,1440),label+" actual 2K framebuffer")
	check(pixels.save_png(capture_root.path_join(label+".png"))==OK,label+" capture saved")
