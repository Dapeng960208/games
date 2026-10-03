extends Node
## Controlled real-room L31 capture, isolated profile and managed output only.
const Geometry = preload("res://scripts/world/b06_room_geometry.gd")
var output := ""
var checks := 0
var failures := 0
func _ready() -> void: _capture.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("L31 PILOT: "+label)
func _capture() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b06_environment_pilot") or DisplayServer.get_name()=="headless": get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	Game.run=null
	if not Game.new_profile() or not Game.start_run({"expedition":true,"biome_id":"B01","seed":26031}): get_tree().quit(2); return
	var room=load("res://scenes/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	var prepared:Dictionary=room.prepare_expedition_node({"room_id":"L31","biome_id":"B06","role":"branch","difficulty":0,"seed":26031,"node_index":0,"b06_candidate":true})
	check(prepared.get("valid",false),"candidate real room prepares")
	if not prepared.get("valid",false): get_tree().quit(1); return
	room.apply_prepared_expedition_node(prepared)
	room.player.position=Geometry.world_point([1400,900])
	room.camera.follow_target(); room.camera.force_update_scroll()
	await _save("l31-before-pilot.png")
	for child in room.get_children():
		if child is CanvasItem and child not in [room.enemies,room.player,room.b06_mechanics,room.enemy_telegraphs,room.enemy_skills,room.interaction_overlay]: child.hide()
	var ground_before:PackedVector2Array=room.ground_polygon.duplicate()
	var environment=preload("res://scripts/world/b06_environment_pilot.gd").new()
	room.add_child(environment)
	check(environment.configure(room.layout,room.b06_mechanics),"L31 pilot configures")
	check(Geometry.validate("L31").is_empty(),"frozen dry corridor valid")
	check(environment.water_layers.size()==2,"two authored water layers")
	for item:Dictionary in environment.exterior:
		var rect:Rect2=item.rect
		var outer:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		for shape:PackedVector2Array in Geometry2D.clip_polygons(outer,ground_before):
			check(Geometry2D.intersect_polygons(shape,ground_before).is_empty(),"exterior architecture stays outside legal floor")
	check(room.b06_mechanics.state.clock_state().phase=="low","single clock begins low")
	var views={"center":[1400,900],"northwest":[240,260],"northeast":[2560,260],"southwest":[240,1540],"southeast":[2560,1540],"entry":[360,900],"exit":[2440,900]}
	for phase in ["low","high"]:
		if phase=="high":
			room.b06_mechanics.tick(12.1,false)
			check(room.b06_mechanics.state.clock_state().phase=="warning","single clock warning")
			room.player.position=Geometry.world_point([1400,900])
			room.camera.follow_target(); room.camera.force_update_scroll()
			environment.refresh_water()
			await _save("l31-warning-center.png")
			room.b06_mechanics.tick(2.0,false)
		check(room.b06_mechanics.state.clock_state().phase==phase,"clock phase "+phase)
		for label:String in views:
			room.player.position=Geometry.world_point(views[label])
			room.camera.follow_target(); room.camera.force_update_scroll()
			environment.refresh_water()
			await _save("l31-"+phase+"-"+label+".png")
	check(ground_before==room.ground_polygon,"art never changes collision")
	for x in range(360,2441,80):
		check(Geometry.patch_at("L31",Geometry.world_point([x,900])).is_empty(),"dry route sample")
	check(Geometry.patch_at("L31",Geometry.world_point([2440,900])).is_empty(),"exit approach dry")
	var report:=FileAccess.open(output.path_join("l31-environment-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"framebuffer":[2560,1440],"native_floor_tile":[1254,1254],"native_water":[1564,1006],"native_facade_long_edge":2172,"native_2k":false,"candidate_only":true,"geometry_unchanged":ground_before==room.ground_polygon,"gate_note":"L31 has no drain gate; entry and exit approach captured","visual_acceptance":"pending pixel review"},"\t"))
	await room.combat_audio.wait_for_cleanup()
	room.free();Game.run=null
	print("B06_ENVIRONMENT_PILOT checks=",checks," failures=",failures," output=",output)
	get_tree().quit(1 if failures else 0)
func _save(name:String) -> void:
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440),"actual2K framebuffer")
	check(image.save_png(output.path_join(name))==OK,"capture "+name)
