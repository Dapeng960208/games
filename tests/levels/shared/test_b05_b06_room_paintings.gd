extends Node
## Real room, camera, actors and HUD. Only time and view positions are controlled.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const HudScene = preload("res://scenes/presentation/hud.tscn")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const G05 = preload("res://scripts/levels/b05/world/room_geometry.gd")
const G06 = preload("res://scripts/levels/b06/world/room_geometry.gd")
const IDS := ["L25","L26","L27","L28","L29","L30","BO05","L31","L32","L33","L34","L35","L36","BO06"]
var checks := 0
var failures := 0
var output := ""
var records: Array[Dictionary] = []
var painting_paths: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ROOM PAINTINGS: "+message)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if not Game.profile_path.contains("test_b05_b06_room_paintings") or output.is_empty() or not FileAccess.file_exists(output.path_join(".managed-test-run.json")) or DisplayServer.get_name()=="headless":
		get_tree().quit(2); return
	get_tree().create_timer(240).timeout.connect(func(): push_error("ROOM PAINTINGS: timeout"); get_tree().quit(1))
	Game.run = null
	if not (Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":560603})):
		get_tree().quit(1); return
	Game.profile.settings["automatic_attack"] = false
	Game.profile.settings["camera_shake"] = false
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	for id: String in ["L01","L07","L13","L19"]+IDS:
		await inspect(id)
	var report := FileAccess.open(output.path_join("room_paintings.json"),FileAccess.WRITE)
	check(report != null,"report opens")
	if report != null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"logical_viewport":[1280,720],"framebuffer":[2560,1440],"scope":"production room presentation and mapping; controlled views; not natural balance or performance","records":records},"\t"))
		report.close()
	Game.run=null
	print("B05_B06_ROOM_PAINTINGS checks=",checks," failures=",failures," output=",output)
	get_tree().quit(1 if failures else 0)
func inspect(id: String) -> void:
	var biome := "B05" if id in IDS.slice(0,7) else "B06"
	if not id in IDS: biome = {"L01":"B01","L07":"B02","L13":"B03","L19":"B04"}[id]
	var room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await frames(2)
	room.combat_audio.audible = false
	var context := {"room_id":id,"biome_id":biome,"role":"boss" if id.begins_with("BO") else "branch","difficulty":2,"seed":560603,"node_index":-603,"b06_progression":biome=="B06","b06_candidate":biome=="B06"}
	var prepared: Dictionary = room.prepare_expedition_node(context)
	check(bool(prepared.get("valid",false)),id+" real room prepares")
	if not bool(prepared.get("valid",false)): room.free(); return
	room.apply_prepared_expedition_node(prepared)
	room.set_input_blocked(true)
	room.spawn_enabled=false
	check(room.configuration_ready and room.configuration_error.is_empty(),id+" real room configured")
	var snapshot := var_to_str([room.ground_polygon,room.obstructions,room.layout.entry,room.exit_position,room.encounter_zones])
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	var hud=HudScene.instantiate()
	hud.room=room
	hud_layer.add_child(hud)
	hud.set_process(false)
	var backdrop=room.get_node("MineBackdrop")
	var definition: Dictionary=Art.environment_definition(biome,id)
	var points: Dictionary={"center":Vector2(.5,.5)}
	if id in IDS: points.merge({"northwest":Vector2(.14,.16),"northeast":Vector2(.86,.16),"southwest":Vector2(.14,.84),"southeast":Vector2(.86,.84)})
	var arena: Rect2=room.layout.arena
	for label: String in points:
		room.player.position=room.clamp_actor(arena.position+arena.size*points[label],15.0)
		room.camera.follow_target(); room.camera.force_update_scroll()
		hud.visible=label=="center"
		await save(id+"_"+label)
	if biome=="B06":
		room.b06_mechanics.tick(10)
		room.player.position=room.clamp_actor(arena.get_center(),15.0)
		room.camera.follow_target();room.camera.force_update_scroll();hud.show()
		room.b06_environment.refresh_water()
		await save(id+"_high_tide")
	check(snapshot==var_to_str([room.ground_polygon,room.obstructions,room.layout.entry,room.exit_position,room.encounter_zones]),id+" rendering leaves gameplay coordinates intact")
	check(room.camera.zoom.x>=.85 and is_equal_approx(room.camera.zoom.x,room.camera.zoom.y),id+" production camera zoom")
	var source := G05.room(id) if biome=="B05" else G06.room(id) if biome=="B06" else {}
	if id in IDS:
		check(room.layout.entry.is_equal_approx(Vector2(source.entry[0],source.entry[1])*.58),id+" entry uses blueprint scale")
		check(room.exit_position.is_equal_approx(Vector2(source.exit[0],source.exit[1])*.58),id+" exit uses blueprint scale")
		check(room.ground_polygon==G05.polygon(id) if biome=="B05" else room.ground_polygon==G06.polygon(id),id+" exact authored passage boundary")
		check(bool(definition.get("room_specific",false)) and not str(definition.get("path","")).is_empty(),id+" independently registered room original")
		check(not painting_paths.has(str(definition.get("path",""))),id+" original is unique to this room")
		painting_paths.append(str(definition.get("path","")))
		var paint_bounds: Rect2=Art.environment_world_rect(arena,biome,id)
		check(room.camera.render_bounds.is_equal_approx(paint_bounds),id+" actual camera uses the original painting bounds")
		var placement: Rect2=definition.placement_normalized_rect
		for point: Array in source.walkable_polygon+source.main_route+[source.entry,source.exit]:
			var blueprint:=Vector2(point[0],point[1])
			var normalized:=placement.position+blueprint/Vector2(2800,1800)*placement.size
			check(Art.environment_point(arena,biome,normalized,id).is_equal_approx(blueprint*.58),id+" painting/ground/route share blueprint coordinates")
		if biome=="B06":
			check(room.b06_environment.source_rect.is_equal_approx(paint_bounds),id+" tide renderer uses the same original mapping")
			var native=preload("res://scripts/levels/b06/art/native_art.gd")
			for gate: Dictionary in source.gates:
				var at:=G06.world_point(gate.position)
				check(room.b06_mechanics._gates[gate.id].is_equal_approx(at),id+" drain interaction and visual foot share world coordinates")
				var frame: Dictionary=room.b06_mechanics._prop_frames.get("drain_gate",{})
				var draw: Dictionary=native.placement(frame,at,92)
				check(not draw.is_empty() and (draw.bounds.position+(frame.foot-frame.region.position)*draw.scale).is_equal_approx(at),id+" source foot projects onto the actual drain")
		else:
			var appearance=preload("res://scripts/presentation/world/room_appearance.gd")
			for cover: Dictionary in appearance.depth_recipe(room.layout,biome,appearance.recipe(room.layout,biome)):
				if str(cover.get("kind",""))!="b05_low_cover" and not str(cover.get("kind","")).begins_with("b05_bridge:"): continue
				check(Vector2(cover.foot).is_equal_approx(cover.collision_rect.get_center()),id+" grounded cover/bridge sorts at its actual contact foot")
				check(cover.visual_bounds.is_equal_approx(appearance.architecture_bounds(cover.architecture,cover.foot,cover.art_size,biome)),id+" cover/bridge art is grounded without a raised plinth offset")
			for index: int in source.root_wells.size():
				var foot: Vector3=room.b05_mechanics._well_footprints[index]
				check(Vector2(foot.x,foot.y).is_equal_approx(G05.world_point(source.root_wells[index].position)),id+" root well collision and visual ground use blueprint mapping")
	records.append({"room_id":id,"biome_id":biome,"texture":definition.get("path",""),"room_specific":definition.get("room_specific",false),"painting_bounds":var_to_str(backdrop.painted_bounds()),"camera_bounds":var_to_str(room.camera.render_bounds),"zoom":room.camera.zoom.x,"ground_vertices":room.ground_polygon.size()})
	check(await room.combat_audio.wait_for_cleanup(),id+" audio drains")
	hud_layer.free(); room.free()
	await frames(2)
func frames(count: int=4) -> void:
	for n in count: await get_tree().process_frame
func save(label: String) -> void:
	await frames()
	# Match the existing first-room fixture: draw even when the window is idle.
	RenderingServer.force_draw(false)
	var pixels:=get_viewport().get_texture().get_image()
	check(pixels.get_size()==Vector2i(2560,1440),label+" native framebuffer")
	check(pixels.save_png(output.path_join(label+"_2560x1440.png"))==OK,label+" capture saved")
