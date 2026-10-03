extends Node
## Controlled actual-room render fixture; no production combat/collision rule changes.
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
	if output.is_empty() or not Game.profile_path.contains("test_b06_environment_final") or DisplayServer.get_name()=="headless": get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	Game.run=null
	if not Game.new_profile() or not Game.start_run({"expedition":true,"biome_id":"B01","seed":26036}): get_tree().quit(2); return
	var rooms: Array = ["L36","BO06"]
	if "--l36-only" in OS.get_cmdline_user_args(): rooms = ["L36"]
	for id: String in rooms: await _room(id)
	var report:=FileAccess.open(AssetCatalog.resolve(output.path_join("environment-final-report.json")),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"framebuffer":[2560,1440],"candidate_only":true,"rooms":results,"visual_acceptance":"pending pixel review"},"\t"))
	Game.run=null
	print("B06_ENVIRONMENT_FINAL checks=",checks," failures=",failures," output=",output)
	get_tree().quit(1 if failures else 0)
func _room(id: String) -> void:
	var start_checks := checks
	var start_failures := failures
	var room=load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	var prepared:Dictionary=room.prepare_expedition_node({"room_id":id,"biome_id":"B06","role":"boss" if id == "BO06" else "branch","difficulty":2,"seed":26036,"node_index":0,"b06_candidate":true})
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
	check(environment.water_layers.size()==(4 if id=="BO06" else 6),id+" exact water layer count")
	for item:Dictionary in environment.exterior:
		var rect:Rect2=item.rect
		var outer:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		for shape:PackedVector2Array in Geometry2D.clip_polygons(outer,ground_before):
			check(Geometry2D.intersect_polygons(shape,ground_before).is_empty(),id+" exterior outside legal floor")
	var definition: Dictionary = Geometry.room(id)
	var views={"center":[1400,900],"northwest":[240,260],"northeast":[2560,260],"southwest":[240,1540],"southeast":[2560,1540],"entry":definition.entry,"exit":definition.exit}
	if id == "L36": views["gate"]=[1310,900]
	if id == "BO06":
		views["gate-west"]=[470,900]; views["gate-east"]=[2330,900]
		views["pillar-west"]=[1050,750]; views["pillar-east"]=[1750,750]
		check(is_instance_valid(room._boss_actor),"BO06 real boss present")
		check(room.b06_mechanics.state.clock_state().phase=="inactive","BO06 P1 tide inactive")
		await _view(room,environment,[1400,900],"bo06-p1-inactive-center.png")
		room._boss_actor.health.current=floorf(float(room._boss_actor.health.maximum)*.65)
		room._boss_actor.boss_brain.tick(room._boss_actor,.016,room.player)
		check(room.b06_mechanics.boss_state.phase()==2,"BO06 production phase transition starts tide")
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
	if id == "L36":
		room.player.position=Geometry.world_point([1400,900])
		check(room.b06_mechanics.interact("drain_dock",room.player,"visual_test_player",func(): return true,func(_a,_b): return true),"L36 real dock drain admitted")
		room.b06_mechanics.tick(.61,false)
		check(not room.b06_mechanics.is_patch_wet("channel_middle") and room.b06_mechanics.is_patch_wet("channel_middle_s"),"L36 drains north middle only")
		await _view(room,environment,[1400,750],"l36-high-drained-center.png")
		_assert_water(room,environment,"L36 drained")
	else:
		var boss: Node2D = room._boss_actor
		room.player.position=Geometry.world_point([1400,1050])
		boss.boss_brain._begin_action(boss,room.player,"dual_cannon")
		check(not boss.boss_brain.current_telegraph().is_empty(),"BO06 real cannon warning available")
		await _view(room,environment,[1400,1050],"bo06-high-cannon-warning.png")
		for side: String in ["west","east"]:
			room.player.position=Geometry.world_point([560,900] if side=="west" else [2240,900])
			check(room.b06_mechanics.interact("drain_"+side,room.player,"visual_test_player",func(): return true,func(_a,_b): return true),"BO06 real drain "+side)
			room.b06_mechanics.tick(.61,false)
			check(not room.b06_mechanics.is_patch_wet("bay_"+side) and room.b06_mechanics.is_patch_wet("bay_"+side+"_s"),"BO06 drain leaves southern patch wet "+side)
		await _view(room,environment,[1400,900],"bo06-high-drained-center.png")
		_assert_water(room,environment,"BO06 drained")
		# Use a real authored claw command at a controlled valid pillar approach.
		var pillar: Vector2 = Geometry.world_point([1050,650])
		boss.position=pillar+Vector2(0,100)
		room.player.position=pillar
		boss.boss_brain._begin_action(boss,room.player,"siege_claw")
		check(str(boss.boss_brain.command.get("action_id",""))=="siege_claw","BO06 real claw command")
		await _view(room,environment,[1050,650],"bo06-drained-pillar-claw-warning.png")
		check(room.b06_mechanics.confirm_boss_claw(boss.boss_brain.command),"BO06 spatial claw receipt admitted at drained pillar")
		check(room.b06_mechanics.boss_state.exposure_remaining()>0,"BO06 exposure window active")
		await _view(room,environment,[1400,900],"bo06-pillar-exposure.png")
		room.b06_mechanics.tick(4.7,false)
		boss.boss_brain.tick(boss,.016,room.player)
		check(not room.b06_mechanics.boss_state.damage_admitted(),"BO06 natural high-end output window active")
		check(boss.boss_brain.current_telegraph().is_empty(),"BO06 output window clears actionable boss warning")
		await _view(room,environment,[1400,900],"bo06-output-window.png")
		room.b06_mechanics.tick(2.51,false)
		check(room.b06_mechanics.boss_state.damage_admitted(),"BO06 output window expires by shared clock")
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
	if is_instance_valid(room._boss_actor): room._boss_actor.body_visual.advance(.016)
	room.enemy_telegraphs.refresh()
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
