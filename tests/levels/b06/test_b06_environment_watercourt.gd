extends Node
## Controlled actual-room render acceptance; no combat/collision mutation.
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
var output := ""
var checks := 0
var failures := 0
var results: Array = []
func _ready() -> void: _capture.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B06 ENVIRONMENT BATCH: "+label)
func _capture() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b06_environment_watercourt") or DisplayServer.get_name()=="headless": get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	Game.run=null
	if not Game.new_profile() or not Game.start_run({"expedition":true,"biome_id":"B01","seed":26034}): get_tree().quit(2); return
	var rooms: Array = ["L34","L35"]
	if "--l34-only" in OS.get_cmdline_user_args(): rooms = ["L34"]
	for id: String in rooms: await _room(id)
	var report:=FileAccess.open(AssetCatalog.resolve(output.path_join("environment-watercourt-report.json")),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"framebuffer":[2560,1440],"candidate_only":true,"rooms":results,"visual_acceptance":"pending pixel review"},"\t"))
	Game.run=null
	print("B06_ENVIRONMENT_WATERCOURT checks=",checks," failures=",failures," output=",output)
	get_tree().quit(1 if failures else 0)
func _room(id: String) -> void:
	var start_checks := checks
	var start_failures := failures
	var room=load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	var prepared:Dictionary=room.prepare_expedition_node({"room_id":id,"biome_id":"B06","role":"branch","difficulty":0,"seed":26034,"node_index":0,"b06_candidate":true})
	check(prepared.get("valid",false),id+" candidate prepares")
	if not prepared.get("valid",false): room.free(); return
	room.apply_prepared_expedition_node(prepared)
	for child in room.get_children():
		if child is CanvasItem and child not in [room.enemies,room.player,room.b06_mechanics,room.enemy_telegraphs,room.enemy_skills,room.interaction_overlay]: child.hide()
	var ground_before:PackedVector2Array=room.ground_polygon.duplicate()
	var environment=preload("res://scripts/levels/b06/world/environment_batch.gd").new()
	room.add_child(environment)
	check(environment.configure(room.layout,room.b06_mechanics),id+" art configures")
	check(Geometry.validate(id).is_empty(),id+" frozen geometry valid")
	check(environment.water_layers.size()==2,id+" exact water layer count")
	for item:Dictionary in environment.exterior:
		var rect:Rect2=item.rect
		var outer:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		for shape:PackedVector2Array in Geometry2D.clip_polygons(outer,ground_before):
			check(Geometry2D.intersect_polygons(shape,ground_before).is_empty(),id+" exterior outside legal floor")
	var definition: Dictionary = Geometry.room(id)
	var views={"center":[1400,900],"northwest":[240,260],"northeast":[2560,260],"southwest":[240,1540],"southeast":[2560,1540],"entry":definition.entry,"exit":definition.exit}
	if id == "L34": views["gate"]=[2110,900]
	if "--contrast-only" in OS.get_cmdline_user_args(): views={"center":[1400,900]}
	for phase: String in ["low","warning","high"]:
		if phase=="warning": room.b06_mechanics.tick(8.1,false)
		if phase=="high": room.b06_mechanics.tick(2.0,false)
		check(room.b06_mechanics.state.clock_state().phase==phase,id+" single clock "+phase)
		for label:String in views:
			await _view(room,environment,views[label],id.to_lower()+"-"+phase+"-"+label+".png")
		_assert_water(room,environment,id+" "+phase)
		var paused_snapshot: Dictionary = room.b06_mechanics.state.snapshot().duplicate(true)
		room.b06_mechanics.tick(5.0,true)
		environment.refresh_water()
		check(room.b06_mechanics.state.snapshot()==paused_snapshot,id+" paused "+phase+" unchanged")
		_assert_water(room,environment,id+" paused "+phase)
		room.b06_mechanics.tick(0.0,false)
		_assert_water(room,environment,id+" resumed "+phase)
		if id == "L35" and phase == "low":
			room.player.position=Geometry.world_point([1400,460])
			var clock_before: Dictionary = room.b06_mechanics.state.snapshot().duplicate(true)
			check(room.b06_mechanics.reveal_next_tide(room.player,func(): return true,func(_a,_b): return true),"L35 real bell preview admitted")
			check(room.b06_mechanics.next_tide_visible(),"L35 bell makes production direction visible")
			check(room.b06_mechanics.state.snapshot()==clock_before,"L35 bell does not advance tide clock")
			await _view(room,environment,[1400,460],"l35-low-bell-preview.png")
			await _view(room,environment,[1400,1000],"l35-low-direction-preview.png")
			_assert_water(room,environment,"L35 bell preview remains dry")
	if id == "L34":
		room.player.position=Geometry.world_point([2200,900])
		check(room.b06_mechanics.interact("drain_east",room.player,"visual_test_player",func(): return true,func(_a,_b): return true),"L34 real gate interaction admitted")
		room.b06_mechanics.tick(.61,false)
		check(not room.b06_mechanics.is_patch_wet("workshop_east") and room.b06_mechanics.is_patch_wet("workshop_west"),"L34 drain affects east only")
		await _view(room,environment,[2110,900],"l34-high-drained-gate.png")
		await _view(room,environment,[1800,1320],"l34-high-drained-east.png")
		_assert_water(room,environment,"L34 drained")
	else:
		check(not room.b06_mechanics.next_tide_visible(),"L35 high clears bell preview")
		check(room.b06_mechanics.is_patch_wet("garden_west") and room.b06_mechanics.is_patch_wet("garden_east"),"L35 both authored high patches")
	check(ground_before==room.ground_polygon,id+" collision unchanged")
	for route: Array in definition.dry_routes:
		for i in range(route.size()-1):
			for sample in 11:
				var point: Vector2=Geometry.world_point(route[i]).lerp(Geometry.world_point(route[i+1]),sample/10.0)
				check(Geometry.patch_at(id,point).is_empty(),id+" dry route sample")
	results.append({"room_id":id,"checks":checks-start_checks,"failures":failures-start_failures,"geometry_unchanged":ground_before==room.ground_polygon})
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
func _view(room: Node2D,environment: Node2D,point:Array,name:String) -> void:
	room.player.position=Geometry.world_point(point)
	room.camera.follow_target(); room.camera.force_update_scroll()
	environment.refresh_water()
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440),"actual 2K framebuffer")
	check(image.save_png(output.path_join(name))==OK,"capture "+name)

func _assert_water(room: Node2D,environment: Node2D,label: String) -> void:
	environment.refresh_water()
	var previous: Vector2 = room.player.position
	for layer: Polygon2D in environment.water_layers:
		var id: String = str(layer.get_meta("patch_id"))
		var center := Vector2.ZERO
		for point: Vector2 in layer.polygon: center += point
		room.player.position = center / layer.polygon.size()
		# Existing production actor lookup applies its authored alternating mask.
		var production_patch: String = room.b06_mechanics.patch_at(room.player)
		if room.b06_mechanics.state.is_wet(id):
			for patch: Dictionary in Geometry.room(environment.room_id).shallow_patches:
				if str(patch.id)==id:
					var direction:=Vector2(float(patch.direction[0]),float(patch.direction[1])).normalized()
					check(room.b06_mechanics.tidal_direction_at(room.player.position)==direction,label+" visual arrow definition matches production direction "+id)
		var expected: bool = production_patch == id and room.b06_mechanics.state.is_wet(id)
		check(room.b06_mechanics.is_patch_wet(id)==expected,label+" query matches actor production mask "+id)
		check(is_equal_approx(float(layer.material.get_shader_parameter("wet_opacity")),.48 if expected else .025),label+" shader matches production wet state "+id)
	room.player.position = previous
