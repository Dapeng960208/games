extends Node
## Focused runtime preservation and genuine GPU evidence for the 28 fixed rooms.
## tools/test.ps1 -Suite room_presentation -SkipImport -Graphical
const Fixed = preload("res://scripts/domain/world/fixed_room_layouts.gd")
const Presentation = preload("res://scripts/presentation/world/room_presentation.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
const OUTPUT := "res://artifacts/room-presentation/"
const WINDOWS := [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(1280,900)]
var checks := 0
var failures := 0
var room: Node2D
var hud: Control
var layer: CanvasLayer
var evidence: Array[Dictionary] = []
var authored_assets: Dictionary = {}
var background_paths: Dictionary = {}
var background_hashes: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(180.0).timeout.connect(func(): push_error("ROOM_PRESENTATION: capture timed out"); get_tree().quit(1))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROOM_PRESENTATION: "+message)

func frames(count: int = 3) -> void:
	for index: int in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func resize_window(extent: Vector2i) -> void:
	get_window().size = extent
	get_window().content_scale_size = extent
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()
	hud.refresh()

func scenery_signature(layout: Dictionary) -> String:
	# Seed, enemy selection, beacon effect and boss order may vary. Painted
	# geometry and interaction anchors are authored independently of that RNG.
	return var_to_str([layout.get("room_presentation",{}), layout.get("decoration_instances",[]),
		layout.get("prop_instances",[]), layout.get("fixed_routes",{}), layout.get("buff_anchors",[]),
		layout.get("fixed_optional_rewards",[]), layout.get("objective_points",[])])

func context(id: String, seed_value: int = 146556) -> Dictionary:
	var blueprint: Dictionary = Fixed.blueprint(id)
	return {"room_id":id, "role":"boss" if id.begins_with("BO") else "branch",
		"biome_id":str(blueprint.biome_id), "node_index":1, "node_count":7,
		"difficulty":0, "seed":seed_value, "phase":"combat", "expedition":true}

func install(id: String) -> bool:
	var prepared: Dictionary = room.prepare_expedition_node(context(id))
	check(bool(prepared.get("valid",false)), id+" prepares through the production room path: "+str(prepared.get("error","")))
	if not bool(prepared.get("valid",false)): return false
	var alternate: Dictionary = room.prepare_expedition_node(context(id,986353))
	check(bool(alternate.get("valid",false)) and scenery_signature(prepared.layout)==scenery_signature(alternate.get("layout",{})), id+" authored scene and functional anchors remain fixed across seeds")
	room.discard_prepared_expedition_node(alternate)
	room.apply_prepared_expedition_node(prepared)
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	# Retain objective actors and the arena boss for the actual screenshots.
	# Ordinary encounter actors are removed to make ground and venues readable.
	for actor: Node in room.enemies.get_children():
		if str(actor.get("actor_kind")) != "objective" and str(actor.get("rank")) != "boss": actor.free()
	var center: Vector2 = room.layout.arena.get_center()+Vector2(0,110)
	if id.begins_with("BO") and is_instance_valid(room._boss_actor):
		# Arena bosses have large northern silhouettes. A real nearby player
		# position keeps their heads clear of the standing top HUD in this view.
		center = room._boss_actor.position+Vector2(-300,-45)
	room.player.position = room.clamp_actor(center,30.0)
	room.player.aim_direction = Vector2.RIGHT
	room.camera.follow_target()
	room.camera.force_update_scroll()
	hud.refresh()
	await frames()
	return true

func preservation_checks(id: String) -> void:
	var blueprint: Dictionary = Fixed.blueprint(id)
	var layout: Dictionary = room.layout
	var design: Dictionary = Presentation.definition(id)
	check(layout.get("fixed_room",{})==blueprint and str(layout.biome_id)==str(blueprint.biome_id), id+" runtime retains the complete original race, encounters, rewards and boss metadata")
	var payloads_preserved: bool = layout.fixed_optional_rewards.size()==blueprint.get("fixed_optional_rewards",[]).size() and layout.fixed_world_entities.size()==blueprint.get("fixed_world_entities",[]).size()
	for field: String in ["fixed_optional_rewards","fixed_world_entities"]:
		for authored: Dictionary in blueprint.get(field,[]):
			var actual: Dictionary = {}
			for item: Dictionary in layout.get(field,[]):
				if str(item.get("id",""))==str(authored.get("id","")): actual = item
			for key: String in authored:
				if key!="position": payloads_preserved = payloads_preserved and actual.get(key)==authored[key]
	check(payloads_preserved, id+" runtime reward and world-entity IDs, assets and payload fields match the original blueprint")
	check(layout.get("room_presentation",{})==design, id+" runtime installs its own room presentation")
	var ground: Node2D = room.get_node("MineBackdrop").ground_composition
	check(is_instance_valid(ground) and ground.visible and ground.design==design and not ground.composition.is_empty(), id+" actual ground composition is present with its own room design")
	var objective_points: Array[Vector2] = []
	if id.begins_with("BO"):
		var installed: Dictionary = room.objectives.elements
		var counters_ok: bool = installed.size()==layout.boss_counterplay.size() and installed.size()==blueprint.get("runtime_counterplays",[]).size()
		for counter: Dictionary in layout.boss_counterplay:
			counters_ok = counters_ok and installed.has(str(counter.id)) and installed[str(counter.id)].position==counter.position
			objective_points.append(counter.position)
		check(counters_ok and is_instance_valid(room._boss_actor) and str(room._boss_actor.boss_id)==id, id+" real boss and every authored arena counterplay remain installed")
	else:
		for item: Dictionary in room.objectives.elements.values():
			if bool(item.get("required",true)): objective_points.append(item.position)
		check(objective_points==layout.objective_points and int(room.objectives.required_count)==int(layout.fixed_objective_count) and objective_points.size()==blueprint.get("objectives",[]).size(), id+" real mission targets retain their authored count and points")
	var beacons: Array[Vector2] = []
	for beacon: Dictionary in room.enemy_props.props: beacons.append(beacon.position)
	check(beacons==layout.buff_anchors, id+" real beacons retain their authored feet")
	var reward_bodies_ok := true
	for reward: Dictionary in layout.fixed_optional_rewards:
		var matching := 0
		for item: Dictionary in room.enemy_props.obstacle_recipes:
			if str(item.get("asset",""))==str(reward.asset) and Vector2(item.position).distance_to(reward.position)<0.5: matching+=1
		var element: Dictionary = room.objectives.elements.get(str(reward.id),{})
		reward_bodies_ok = reward_bodies_ok and matching==1 and bool(element.get("optional_reward",false)) and element.get("position",Vector2.INF)==reward.position
		objective_points.append(reward.position)
	check(reward_bodies_ok, id+" fixed rewards retain one visible original body and a real interaction element")
	var reachable := true
	for point: Vector2 in [layout.exit]+objective_points+beacons:
		var direction: Vector2 = room.navigation_direction(layout.entry,point,30.0)
		reachable = reachable and room.valid_ground(point,30.0) and not direction.is_zero_approx()
	check(reachable, id+" installed navigation reaches the exit, task/counterplay targets, rewards and beacons")
	var venues := 0
	var real_venue_art := true
	for item: Dictionary in room.enemy_props.obstacle_recipes:
		if "venue_group" in item.get("tags",[]):
			venues+=1
			real_venue_art = real_venue_art and authored_assets.has(str(item.asset)) and PropArt.texture_for_asset(str(item.asset))!=null and not Rect2(item.collision_rect).has_area()
	check(venues==6 and real_venue_art, id+" both venue groups use six actual painted, walkable scenery items")

func background_checks(id: String) -> Dictionary:
	var layout: Dictionary = room.layout
	var biome: String = str(layout.biome_id)
	var environment: Dictionary = Art.environment_definition(biome,Art.environment_room_id(layout))
	var expected_path := "asset://world/rooms/"+id+"_environment_v1.png"
	var expected_manifest := "asset://world/rooms/"+id+"_environment_v1.json"
	check(bool(environment.get("room_specific",false)) and environment.get("path","")==expected_path and environment.get("manifest_path","")==expected_manifest, id+" loads its independent full background PNG and own source manifest")
	check(not background_paths.has(str(environment.get("path",""))), id+" owns a different background path")
	background_paths[str(environment.get("path",""))] = id
	var backdrop: Node2D = room.get_node("MineBackdrop")
	var source: Texture2D = backdrop.environment_texture
	check(source!=null and source==environment.get("texture") and str(backdrop.blueprint_room_id)==id and str(backdrop.environment_chunks.environment_id)==id, id+" actual scene and chunk layer select the fixed blueprint background")
	if source==null: return {}
	var metadata: Dictionary = environment.get("metadata",{})
	var dimensions: Array = metadata.get("source_size",[])
	check(dimensions.size()==2 and source.get_size()==Vector2(float(dimensions[0]),float(dimensions[1])) and source.get_width()>=1536 and source.get_height()>=1024, id+" loaded background dimensions match its manifest and preserve full source detail")
	var shared_texture: bool = backdrop.environment_chunks.chunks.size()==6
	for chunk: Sprite2D in backdrop.environment_chunks.chunks:
		shared_texture = shared_texture and chunk.texture==source
	check(shared_texture, id+" all six runtime image regions share this room's own texture")
	var pixels: Image = source.get_image()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(pixels.get_data())
	var fingerprint: String = digest.finish().hex_encode()
	check(not background_hashes.has(fingerprint), id+" actual loaded background pixels differ from every previous room")
	background_hashes[fingerprint] = id
	var painted: Rect2 = Art.environment_world_rect(layout.arena,biome,id)
	check(backdrop.environment_world_rect==painted and room.camera.render_bounds==painted and room.ground_polygon==Art.environment_ground_polygon(layout.arena,biome,id), id+" painting, camera and physical ground use the same room-specific manifest mapping")
	if id.begins_with("BO"):
		var alias: Dictionary = layout.duplicate(false)
		alias.room_id = "L01"
		check(Art.environment_room_id(alias)==id, id+" fixed boss blueprint remains authoritative if the expedition node ID is overridden")
	return {"background":expected_path,"background_size":dimensions,"pixel_sha256":fingerprint,"source_manifest":expected_manifest}

func hud_checks(id: String, locale: String, extent: Vector2i) -> void:
	var bounds := get_viewport().get_visible_rect()
	check(hud.expedition_label.text.replace(" ","").contains("2/7"), id+" fixture's second of seven stations is displayed consistently")
	var contained := true
	for rectangle: Rect2 in hud.coverage_rects(): contained = contained and bounds.grow(0.5).encloses(rectangle)
	check(contained, id+" "+locale+" standing HUD fits "+str(extent))
	check(not hud.location_panel.get_global_rect().intersects(hud.quest_panel.get_global_rect()) and not hud.quest_panel.get_global_rect().intersects(hud.skill_dock.get_global_rect()), id+" "+locale+" room identity and quest remain clear of each other and skills")
	var plate: Control = hud.find_child("RoomIdentityPlate",true,false)
	check(plate!=null and plate.is_visible_in_tree(), id+" actual HUD exposes the unique room identity plate")
	if plate==null: return
	check(bounds.encloses(plate.get_global_rect()), id+" room identity plate fits the viewport")
	check(plate.design==Presentation.definition(id) and plate.layout==room.layout, id+" HUD identity reads the current real room design and routes")
	check(plate.room_caption.text==Presentation.local_caption(Presentation.definition(id),locale=="en") and not plate.room_title.text.is_empty(), id+" "+locale+" room title and purpose use current localized content")
	var text_inside: bool = plate.get_global_rect().encloses(plate.room_title.get_global_rect()) and plate.get_global_rect().encloses(plate.room_caption.get_global_rect())
	check(text_inside and plate.room_caption.get_line_count()<=2, id+" "+locale+" room title and complete purpose fit the room plate: size="+str(plate.size)+" caption="+str(plate.room_caption.get_rect())+" lines="+str(plate.room_caption.get_line_count()))
	# Measure the actual font and painted seal, including the longest boss ID.
	# The full string must fit the emblem column without clipping the last digit.
	var expected_seal := "%02d·%s" % [int(Presentation.definition(id).chapter),id]
	var seal_font: Font = plate.get_theme_font("font","Button")
	var painted_seal: Rect2 = plate.seal_text_rect
	var seal_width: float = seal_font.get_string_size(plate.seal_text,HORIZONTAL_ALIGNMENT_LEFT,-1,plate.seal_font_size).x
	check(plate.seal_text==expected_seal and is_equal_approx(painted_seal.size.x,seal_width) and painted_seal.position.x>=4 and painted_seal.end.x<=48 and painted_seal.end.y<=plate.size.y and is_equal_approx(painted_seal.get_center().x,26), id+" "+locale+" complete chapter seal fits its visible emblem column: text="+plate.seal_text+" bounds="+str(painted_seal))
	check(plate.map_bounds==room.ARENA and plate.ground_polygon==room.ground_polygon, id+" miniature uses the real walkable ground outline")

func player_marker_checks(id: String) -> void:
	var plate: Control = hud.find_child("RoomIdentityPlate",true,false)
	if plate==null: return
	var center: Vector2 = room.player.position
	for point: Vector2 in [room.layout.entry,room.clamp_actor(room.ARENA.end-Vector2(8,8),30.0)]:
		room.player.position = point
		hud.refresh()
		check(plate.has_player and plate.player_position==room.player.global_position and plate._map_rect().grow(-2).has_point(plate.last_map_player_position), id+" actual player marker follows the entry/ground-edge position inside the miniature")
	if id=="L14":
		room.player.position = center
		hud.refresh()
		var before: Vector2 = plate.last_map_player_position
		for step: int in 20:
			room.player.position.x += 1.0
			hud.refresh()
		check(plate.last_map_player_position.distance_to(before)>.3, id+" slow continuous movement eventually redraws the player marker")
	room.player.position = center
	hud.refresh()

func screenshot(filename: String) -> void:
	if DisplayServer.get_name()=="headless": return
	hud.hovered_control = null
	hud.focused_control = null
	hud.last_hover_control = null
	hud.hover_grace = 0.0
	hud.tooltip_panel.hide()
	room.queue_redraw()
	room.player.queue_redraw()
	await frames(2)
	# A window behind another test/editor can stop presenting frames. Submit a
	# genuine GPU draw explicitly instead of waiting indefinitely for that event.
	RenderingServer.force_draw(false)
	var pixels: Image = get_viewport().get_texture().get_image()
	check(not pixels.is_empty() and pixels.save_png(OUTPUT+filename)==OK, "saved real GPU capture "+filename)
	print("ROOM_PRESENTATION_CAPTURE ",filename)

func overview(id: String) -> void:
	await resize_window(Vector2i(1280,900))
	var camera: Camera2D = room.camera
	var prior := {"zoom":camera.zoom,"position":camera.position,"left":camera.limit_left,"top":camera.limit_top,"right":camera.limit_right,"bottom":camera.limit_bottom}
	var painting: Rect2 = Art.environment_world_rect(room.layout.arena,str(room.layout.biome_id),Art.environment_room_id(room.layout)).grow(28)
	var extent: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(extent.x/painting.size.x,extent.y/painting.size.y)
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	camera.zoom = Vector2.ONE*fit
	camera.position = painting.get_center()
	camera.force_update_scroll()
	# A QA overlay makes the real physical edge inspectable against painted
	# water and walls; it is absent from every ordinary center/HUD capture.
	var boundary_probe := Node2D.new()
	boundary_probe.name = "QAActualGroundOutline"
	boundary_probe.z_index = 30
	room.add_child(boundary_probe)
	boundary_probe.draw.connect(func() -> void:
		var outline: PackedVector2Array = room.ground_polygon.duplicate()
		if not outline.is_empty():
			outline.append(outline[0])
			boundary_probe.draw_polyline(outline,Color("15a6bd"),4.0,true)
		for point: Vector2 in room.layout.objective_points+[room.layout.entry,room.layout.exit]:
			boundary_probe.draw_circle(point,7.0,Color("ffe1a0"))
			boundary_probe.draw_arc(point,7.0,0,TAU,16,Color("725539"),2.0,true)
	)
	hud.hide()
	await screenshot(id+"_overview.png")
	boundary_probe.free()
	hud.show()
	camera.zoom = prior.zoom
	camera.position = prior.position
	camera.limit_left = prior.left
	camera.limit_top = prior.top
	camera.limit_right = prior.right
	camera.limit_bottom = prior.bottom
	await resize_window(WINDOWS[0])
	camera.follow_target()
	camera.force_update_scroll()

func _run() -> void:
	if not Game.profile_path.contains("test_room_presentation"):
		push_error("ROOM_PRESENTATION: requires an isolated test profile")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(),"isolated player and run start")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for path: String in PropArt.MANIFESTS:
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
		if source is Dictionary:
			for asset: String in source.get("regions",{}): authored_assets[asset] = true
	Words.set_locale("zh_CN")
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.layout_seed = 146556
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	layer = CanvasLayer.new()
	add_child(layer)
	hud = load(AssetCatalog.resolve("res://scenes/presentation/hud.tscn")).instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	await resize_window(WINDOWS[0])
	var emblems: Dictionary = {}
	var ids: Array = Fixed.room_ids()
	check(ids.size()==28,"24 rooms and four boss arenas each have a presentation")
	var ui_only: bool = "--ui-only" in OS.get_cmdline_user_args()
	var preview_ids: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-rooms="): preview_ids.assign(argument.trim_prefix("--preview-rooms=").split(","))
	for id: String in ([] if ui_only else (preview_ids if not preview_ids.is_empty() else ids)):
		var design: Dictionary = Presentation.definition(id)
		check(not design.is_empty() and str(design.get("biome_id",""))==str(Fixed.blueprint(id).biome_id),id+" has a presentation in its own biome")
		var emblem: String = str(design.get("emblem",""))
		check(not emblem.is_empty() and not emblems.has(emblem),id+" has an independent room emblem")
		emblems[emblem] = true
		if not await install(id): continue
		preservation_checks(id)
		var background: Dictionary = background_checks(id)
		hud_checks(id,"zh_CN",WINDOWS[0])
		player_marker_checks(id)
		await screenshot(id+"_center_zh_CN_1280x720.png")
		await overview(id)
		var record := {"id":id,"biome":str(design.biome_id),"name":str(Fixed.blueprint(id).name),
			"caption":str(design.caption),"caption_en":str(design.caption_en),"emblem":emblem,
			"center":id+"_center_zh_CN_1280x720.png","overview":id+"_overview.png"}
		record.merge(background)
		evidence.append(record)
	# One ordinary room and one boss exercise the compact and expanded text
	# arrangements. All 28 room identities were already exercised above.
	for id: String in (["L14","BO04"] if preview_ids.is_empty() else []):
		for extent: Vector2i in WINDOWS:
			await resize_window(extent)
			for locale: String in ["zh_CN","en"]:
				print("ROOM_PRESENTATION_UI ",id," ",locale," ",extent)
				Words.set_locale(locale)
				# World actor labels are localized when those actors are built.
				# Reinstall under this locale before testing the complete frame.
				if not await install(id): continue
				hud.refresh()
				await frames()
				hud_checks(id,locale,extent)
				await screenshot(id+"_ui_"+locale+"_"+str(extent.x)+"x"+str(extent.y)+".png")
	Words.set_locale("zh_CN")
	# A targeted UI rerun updates its twelve images and separate evidence while
	# retaining the successful full-room manifest and background fingerprints.
	var manifest := FileAccess.open(AssetCatalog.resolve(OUTPUT+("ui-verification.json" if ui_only else "manifest.json")),FileAccess.WRITE)
	if manifest!=null:
		manifest.store_string(JSON.stringify({"checks":checks,"failures":failures,"gpu":DisplayServer.get_name()!="headless","rooms":evidence,"partial":ui_only or not preview_ids.is_empty()},"\t"))
		manifest.close()
	layer.free()
	room.free()
	Game.run = null
	await frames(2)
	print("ROOM_PRESENTATION_RESULT checks=",checks," failures=",failures," rooms=",evidence.size()," gpu=",DisplayServer.get_name()!="headless")
	get_tree().quit(1 if failures else 0)
