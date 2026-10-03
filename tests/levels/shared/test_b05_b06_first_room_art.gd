extends Node
## Production first-room presentation fixture. The room owns wave composition,
## spawn positions, scenery and camera. Only simulation time and player views
## are controlled; these frames are not a natural combat or performance sample.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const HudScene = preload("res://scenes/presentation/hud.tscn")
const GeometryB05 = preload("res://scripts/levels/b05/world/room_geometry.gd")
const GeometryB06 = preload("res://scripts/levels/b06/world/room_geometry.gd")
const ArtB05 = preload("res://scripts/levels/b05/art/enemy_art.gd")
const ArtB06 = preload("res://scripts/levels/b06/art/native_art.gd")
const DefaultArt = preload("res://scripts/presentation/monsters/enemy_art.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const ROOM_IDS: Array[String] = ["L25", "L31"]
const FIRST_WAVES := {"L25":["B05-M01","B05-M02"], "L31":["B06-M01","B06-M02","B06-M03"]}
const EXPECTED_ENTRIES := {"L25":Vector2(185.6,522), "L31":Vector2(208.8,522)}
const EXPECTED_EXITS := {"L25":Vector2(1438.4,522), "L31":Vector2(1415.2,522)}
const CENTERS := {"L25":Vector2(779.52,522), "L31":Vector2(812,522)}
const EXTENT := Vector2i(2560,1440)
const CONFIG_IDS := {"b05":"asset://levels/b05/rooms/l25/first_room_layers.json", "b06":"asset://levels/b06/rooms/l31/first_room_layers.json"}
const DEFAULT_TEXTURES := {"B05-M01":"asset://enemies/b05_poses_v1/B05-M01_idle-native.png", "B05-M02":"asset://enemies/b05_poses_v1/B05-M02_idle-native.png", "B05-M04":"asset://enemies/b05_poses_v1/B05-M04_idle-native.png", "B05-M06":"asset://enemies/b05_regenerated_poses_v1/B05-M06_idle-native.png", "B06-M01":"asset://b06_native_v1/enemy/B06-M01_idle-native-v2.png", "B06-M02":"asset://b06_native_v1/enemy/B06-M02_idle-native-v2.png", "B06-M03":"asset://b06_native_v1/enemy/B06-M03_idle-native-v2.png"}
var room: RoomController
var hud: Control
var layer: CanvasLayer
var output := ""
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var art_configs: Dictionary = {}
var extra_actor_records: Array[Dictionary] = []
var alpha_bounds: Dictionary = {}
var scenery_records: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FIRST ROOM ART: " + label)

func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not output.is_absolute_path() or not FileAccess.file_exists(output.path_join(".managed-test-run.json")) or not Game.profile_path.contains("test_b05_b06_first_room_art") or not Rules.b06_candidate_enabled():
		push_error("First-room art requires managed output and its isolated B06 candidate profile")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("First-room art requires an actual graphical renderer")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		for biome: String in ["b05","b06"]:
			if argument.begins_with("--art-config-"+biome+"="):
				art_configs[biome] = argument.get_slice("=",1)
	for biome: String in CONFIG_IDS:
		if not art_configs.has(biome) and FileAccess.file_exists(AssetCatalog.resolve(CONFIG_IDS[biome])):
			art_configs[biome] = CONFIG_IDS[biome]
	get_tree().create_timer(90.0).timeout.connect(func(): push_error("FIRST ROOM ART: capture timed out"); get_tree().quit(1))
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":560606}), "fresh isolated production run")
	if Game.run == null:
		get_tree().quit(1)
		return
	Game.profile.settings["automatic_attack"] = false
	Game.profile.settings["camera_shake"] = false
	var logical := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width",1280)),int(ProjectSettings.get_setting("display/window/size/viewport_height",720)))
	get_window().content_scale_size = logical
	get_window().size = EXTENT
	for id: String in ROOM_IDS:
		await _inspect(id)
	await _inspect_b05_d4()
	var report := FileAccess.open(output.path_join("first_room_art.json"),FileAccess.WRITE)
	check(report != null, "managed capture report opens")
	if report != null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"kind":"production first-room waves and scenery; controlled presentation fixture; not natural combat QA","logical_viewport":[logical.x,logical.y],"framebuffer":[EXTENT.x,EXTENT.y],"renderer":RenderingServer.get_video_adapter_name(),"records":records,"additional_wave_bodies":extra_actor_records},"\t")+"\n")
		report.close()
	Game.run = null
	print("B05_B06_FIRST_ROOM_ART checks=",checks," failures=",failures," captures=",records.size()," output=",output)
	get_tree().quit(1 if failures else 0)

func _inspect(id: String) -> void:
	var biome := "B05" if id == "L25" else "B06"
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await _frames(2)
	room.enemy_skills.set_physics_process(false)
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	room.combat_audio.set_process(false)
	var context := {"room_id":id,"biome_id":biome,"role":"branch","difficulty":0,"seed":560606,"node_index":-506,"b06_candidate":id == "L31"}
	var prepared: Dictionary = room.prepare_expedition_node(context)
	check(bool(prepared.get("valid",false)), id+" prepares through real room path")
	if not bool(prepared.get("valid",false)):
		room.free()
		return
	var authored_ground: PackedVector2Array = prepared.layout.ground_polygon.duplicate()
	room.apply_prepared_expedition_node(prepared)
	room.spawn_enabled = false
	room.set_input_blocked(true)
	room.enemy_skills.set_physics_process(false)
	check(room.configuration_ready and room.configuration_error.is_empty(), id+" production scene loads")
	check(room.player.position.is_equal_approx(EXPECTED_ENTRIES[id]) and room.exit_position.is_equal_approx(EXPECTED_EXITS[id]), id+" original entry and exit")
	check(room.ground_polygon == authored_ground, id+" scenery retains authored walkable polygon")
	var geometry_signature := _geometry_signature()
	_navigation(id)
	room._update_encounters()
	var actors := _actors()
	var actual_ids: Array[String] = []
	for actor: EnemyActor in actors: actual_ids.append(actor.enemy_id)
	actual_ids.sort()
	var expected: Array = FIRST_WAVES[id].duplicate()
	expected.sort()
	check(actual_ids == expected and room.activated_encounters.has(0), id+" exact real first wave")
	var actor_records: Array[Dictionary] = []
	for actor: EnemyActor in actors: actor_records.append(_body(actor,biome))
	if id == "L25":
		check(is_instance_valid(room.b05_mechanics) and room.b05_mechanics._room_id == id, id+" production root host")
		check(room.get_node("MineBackdrop").visible == not is_instance_valid(room.b05_environment), id+" backdrop visibility follows successful replacement")
	else:
		check(is_instance_valid(room.b06_mechanics) and room.b06_mechanics.room_id == id, id+" production tide host")
		check(is_instance_valid(room.b06_environment) and room.b06_environment.visible, id+" production layered environment loaded")
	_layered_config(biome.to_lower(),id)
	layer = CanvasLayer.new()
	add_child(layer)
	hud = HudScene.instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	await _capture(id,"entry",actor_records)
	var center: Vector2 = room.move_actor(room.player.position,Vector2(CENTERS[id])-room.player.position,15.0)
	check(center.is_equal_approx(CENTERS[id]), id+" legal main-route move reaches center")
	room.player.position = center
	await _capture(id,"center",actor_records)
	check(_geometry_signature() == geometry_signature, id+" rendering and camera preserve navigation and exits")
	check(_actors() == actors, id+" captures preserve actual spawn actors")
	_environment_lifecycle(id)
	if id == "L25":
		for actor: EnemyActor in actors:
			check(actor.take_damage(actor.health.maximum*10,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}), actor.enemy_id+" first-wave cleanup uses real damage")
		await _frames(2)
		room._update_encounters()
		var second_ids: Array[String] = []
		for actor: EnemyActor in _actors():
			second_ids.append(actor.enemy_id)
			if actor.enemy_id == "B05-M04": extra_actor_records.append(_body(actor,biome))
		second_ids.sort()
		check(second_ids == ["B05-M01","B05-M02","B05-M04"] and room.activated_encounters.has(1), id+" second wave introduces actual support body")
	check(await room.combat_audio.wait_for_cleanup(), id+" audio cleanup")
	layer.free()
	room.free()
	await _frames(2)

func _actors() -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for actor: EnemyActor in room.enemies.get_children():
		if actor.actor_kind == "enemy" and actor.is_alive(): result.append(actor)
	return result

func _geometry_signature() -> String:
	return var_to_str([room.ground_polygon,room.obstructions,room.layout.entry,room.exit_position,room.layout.get("fixed_routes",{}),room.encounter_zones])

func _navigation(id: String) -> void:
	var definition: Dictionary = GeometryB05.room(id) if id == "L25" else GeometryB06.room(id)
	check(room.valid_ground(EXPECTED_ENTRIES[id],15) and room.valid_ground(EXPECTED_EXITS[id],15), id+" original portals are walkable")
	var at: Vector2 = EXPECTED_ENTRIES[id]
	for point: Array in definition.main_route:
		var destination: Vector2 = GeometryB05.world_point(point) if id == "L25" else GeometryB06.world_point(point)
		at = room.move_actor(at,destination-at,15.0)
		check(at.is_equal_approx(destination), id+" actual navigation traverses authored main route")
	check(at.is_equal_approx(EXPECTED_EXITS[id]), id+" actual navigation reaches unchanged exit")
	if id == "L25":
		check(GeometryB05.route_is_clear(id,"main_route",180) and GeometryB05.route_is_clear(id,"safe_route",140), id+" full-width main and safe corridors")
	else:
		check(GeometryB06.validate(id).is_empty() and GeometryB06.patch_at(id,at).is_empty(), id+" full dry corridor and exit")

func _body(actor: EnemyActor, biome: String) -> Dictionary:
	var id := actor.enemy_id
	var before_position := actor.position
	var before_radius := actor.navigation_radius
	actor.body_visual.advance(.001)
	var body: Dictionary = actor.body_visual.body_frame()
	var variant: bool = bool(actor.profile.get("first_room_race_variant",false))
	var bank: Dictionary = (ArtB05.first_room_bank(id) if variant else ArtB05.bank(id)) if biome == "B05" else (ArtB06.first_room_bank(id) if variant else ArtB06.bank(id))
	var default: Dictionary = DefaultArt.entry_for(id)
	check(str(default.get("texture_path","")) == str(DEFAULT_TEXTURES.get(id,"")), id+" default codex/body registration remains unchanged")
	check(not bank.is_empty() and not actor.body_visual.selected_frame.is_empty(), id+" own native pose bank")
	if bank.is_empty() or actor.body_visual.selected_frame.is_empty(): return {"id":id,"loaded":false}
	var source: Dictionary = actor.body_visual.selected_frame
	var texture: Texture2D = body.get("texture")
	check(texture != null and texture == source.texture and bool(body.get("full_color",false)), id+" real selected full-color body")
	if texture == null: return {"id":id,"loaded":false}
	var path := str(source.get("texture_path",""))
	check(path.begins_with("asset://") and AssetCatalog.resources().has(path.trim_prefix("asset://").to_lower()), id+" source resolved by registered logical ID")
	var expected_frame: Dictionary = bank.clips.idle[0]
	check(texture == expected_frame.texture and source.foot == expected_frame.foot and source.region == expected_frame.region, id+" actual selected body matches its metadata")
	if id != "B05-M06":
		check(variant and path != str(default.texture_path) and path.begins_with("asset://levels/"+biome.to_lower()+"/enemies/"), id+" actual first-room race variant uses its new registered source")
	var original := Image.load_from_file(AssetCatalog.resolve(path))
	check(original != null and not original.is_empty() and texture.get_size() == Vector2(original.get_size()), id+" measured native source dimensions match original PNG")
	var region: Rect2 = source.region
	var foot: Vector2 = source.foot
	check(Rect2(Vector2.ZERO,texture.get_size()).encloses(region) and region.has_point(foot), id+" registered source foot remains within texture")
	var factor: Vector2 = body.bounds.size/region.size
	var mapped_foot: Vector2 = body.bounds.position+(foot-region.position)*factor
	check(mapped_foot.length() < .001, id+" actual drawn frame maps source foot to its pivot")
	check((actor.body_visual.position-actor.body_visual.body_offset).is_equal_approx(Vector2(0,18)), id+" common foot baseline retained")
	check(actor.position == before_position and is_equal_approx(actor.navigation_radius,before_radius), id+" art leaves physical origin and radius unchanged")
	var image: Image = texture.get_image()
	check(image != null and not image.is_empty(), id+" source pixels available")
	var colored := 0
	if image != null:
		if image.is_compressed(): image.decompress()
		for y in range(0,image.get_height(),24):
			for x in range(0,image.get_width(),24):
				var color := image.get_pixel(x,y)
				if color.a > .5 and maxf(color.r,maxf(color.g,color.b))-minf(color.r,minf(color.g,color.b)) > .06: colored += 1
	check(colored > 40, id+" source contains painted color")
	var used := _alpha128_bounds(image,region)
	check(used.has_area() and region.encloses(used), id+" selected frame has measured alpha128 body bounds")
	alpha_bounds[path] = used
	return {"id":id,"first_room_race_variant":variant,"default_texture_id":default.get("texture_path",""),"texture_id":path,"resolved_texture":AssetCatalog.resolve(path),"source_pixels":[texture.get_width(),texture.get_height()],"source_alpha128_bounds":_rect(used),"source_foot":[foot.x,foot.y],"source_region":_rect(region),"source_pose_scale":source.get("source_pose_scale",1.0),"pose":body.name,"display_bounds_world":_rect(body.bounds),"source_to_world":[factor.x,factor.y],"physical_origin":[actor.position.x,actor.position.y],"navigation_radius":actor.navigation_radius,"colored_samples":colored}

func _layered_config(biome: String, id: String) -> void:
	if not art_configs.has(biome): return
	var logical_id := str(art_configs[biome])
	check(logical_id.begins_with("asset://") and AssetCatalog.resources().has(logical_id.trim_prefix("asset://").to_lower()), biome+" selected art config registered")
	var path := AssetCatalog.resolve(logical_id)
	check(FileAccess.file_exists(path), biome+" selected art config readable")
	if not FileAccess.file_exists(path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, biome+" selected art config valid JSON")
	if not parsed is Dictionary: return
	var config: Dictionary = parsed
	var scenery: Node2D = room.b05_environment if id == "L25" else room.b06_environment.scenery if is_instance_valid(room.b06_environment) else null
	check(is_instance_valid(scenery), id+" configured replacement actually installed")
	if not is_instance_valid(scenery): return
	check(scenery.active_room_id == id and scenery.floor_polygon == room.ground_polygon, id+" scenery uses the authoritative gameplay polygon")
	check(not room.get_node("MineBackdrop").visible, id+" fallback hidden after complete source loading")
	var expected_layers: Array[String] = []
	var source_records: Array[Dictionary] = []
	var items: Array = [{"id":"background","texture":config.background.texture},{"id":"floor","texture":config.floor.texture}]
	for item: Dictionary in config.layers:
		expected_layers.append(str(item.id))
		items.append(item)
	check(scenery.layer_ids == expected_layers, id+" all configured layer identities installed in order")
	for item: Dictionary in items:
		var texture_id := str(item.texture)
		check(AssetCatalog.resources().has(texture_id.trim_prefix("asset://").to_lower()), str(item.id)+" layer source registered")
		var pixels := Image.load_from_file(AssetCatalog.resolve(texture_id))
		check(pixels != null and not pixels.is_empty(), str(item.id)+" original layer pixels readable")
		if pixels == null or pixels.is_empty(): continue
		var dimensions := Vector2(pixels.get_size())
		var expected_size: Vector2 = Vector2(item.region[2],item.region[3]) if item.has("region") else dimensions
		check(scenery.source_texture_dimensions.get(str(item.id),Vector2.ZERO) == expected_size, str(item.id)+" renderer source dimensions match actual pixels/region")
		source_records.append({"layer_id":item.id,"texture_id":texture_id,"original_pixels":[pixels.get_width(),pixels.get_height()],"sampled_pixels":[expected_size.x,expected_size.y]})
	scenery_records[id] = {"config":logical_id,"layers":source_records}
	if id == "L31": check(room.b06_mechanics.native_water_visual, id+" native layer keeps the production tide state")

func _alpha128_bounds(image: Image, region: Rect2) -> Rect2:
	if image == null or image.is_empty(): return Rect2()
	if image.is_compressed() and image.decompress() != OK: return Rect2()
	var rgba := image.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8: rgba.convert(Image.FORMAT_RGBA8)
	var bytes := rgba.get_data()
	var scan := Rect2i(region).intersection(Rect2i(Vector2i.ZERO,rgba.get_size()))
	var minimum := scan.end
	var maximum := Vector2i(-1,-1)
	for y in range(scan.position.y,scan.end.y):
		for x in range(scan.position.x,scan.end.x):
			if bytes[(y*rgba.get_width()+x)*4+3] >= 128:
				minimum = minimum.min(Vector2i(x,y))
				maximum = maximum.max(Vector2i(x,y))
	return Rect2(Vector2(minimum),Vector2(maximum-minimum+Vector2i.ONE)) if maximum.x >= 0 else Rect2()

func _environment_lifecycle(id: String) -> void:
	if not art_configs.has("b05" if id == "L25" else "b06"): return
	var before := _geometry_signature()
	if id == "L25":
		room._release_b05_environment()
		check(not is_instance_valid(room.b05_environment) and room.get_node("MineBackdrop").visible, id+" releasing replacement restores fallback visibility")
		room._configure_b05_environment()
		check(is_instance_valid(room.b05_environment) and not room.get_node("MineBackdrop").visible, id+" replacement can reload once")
	else:
		var previous_water: bool = room._b06_previous_native_water
		room._release_b06_environment()
		check(not is_instance_valid(room.b06_environment) and room.get_node("MineBackdrop").visible and room.b06_mechanics.native_water_visual == previous_water, id+" release restores fallback and water ownership")
		room._configure_b06_environment()
		check(is_instance_valid(room.b06_environment) and is_instance_valid(room.b06_environment.scenery) and not room.get_node("MineBackdrop").visible, id+" replacement can reload once")
	check(before == _geometry_signature(), id+" replacement lifecycle leaves collision and exit unchanged")

func _inspect_b05_d4() -> void:
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await _frames(2)
	room.enemy_skills.set_physics_process(false)
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	var prepared: Dictionary = room.prepare_expedition_node({"room_id":"L25","biome_id":"B05","role":"branch","difficulty":4,"seed":560606,"node_index":-507})
	check(bool(prepared.get("valid",false)), "L25 D4 real encounter prepares")
	if bool(prepared.get("valid",false)):
		room.apply_prepared_expedition_node(prepared)
		room.spawn_enabled = false
		room.set_input_blocked(true)
		room.enemy_skills.set_physics_process(false)
		var actual_ids: Array[String] = []
		for actor: EnemyActor in _actors():
			actual_ids.append(actor.enemy_id)
			if actor.enemy_id == "B05-M06": extra_actor_records.append(_body(actor,"B05"))
		actual_ids.sort()
		check(actual_ids == ["B05-M01","B05-M01","B05-M02","B05-M02","B05-M06"], "L25 D4 actual first wave includes original scout")
	check(await room.combat_audio.wait_for_cleanup(), "L25 D4 audio cleanup")
	room.free()
	await _frames(2)

func _capture(id: String, view: String, actor_records: Array[Dictionary]) -> void:
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.queue_redraw()
	room.player.queue_redraw()
	hud.refresh()
	var hp_before: float = Game.run.hp
	var clock_before: float = room.enemy_skills._biome_clock
	await _frames(3)
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty() and image.get_size() == EXTENT, id+" "+view+" actual 2560x1440 framebuffer")
	if image == null or image.is_empty(): return
	var path := output.path_join(id.to_lower()+"_"+view+"_2560x1440.png")
	check(image.save_png(path) == OK, id+" "+view+" original framebuffer saved")
	var displayed: Array[Dictionary] = []
	for actor: EnemyActor in _actors():
		var frame: Dictionary = actor.body_visual.body_frame()
		var selected: Dictionary = actor.body_visual.selected_frame
		var source_region: Rect2 = selected.region
		var factor: Vector2 = frame.bounds.size/source_region.size
		var used: Rect2 = alpha_bounds.get(str(selected.texture_path),source_region)
		var local_used := Rect2(frame.bounds.position+(used.position-source_region.position)*factor,used.size*factor)
		var screen: Rect2 = actor.body_visual.get_global_transform_with_canvas()*local_used
		var physical := screen.size*Vector2(get_window().size)/get_viewport().get_visible_rect().size
		check(screen.intersects(get_viewport().get_visible_rect()), actor.enemy_id+" visible in "+view+" game frame")
		displayed.append({"id":actor.enemy_id,"alpha128_screen_rect_logical":_rect(screen),"display_pixels_physical":[physical.x,physical.y],"native_visible_pixels":[used.size.x,used.size.y],"visible_pixels_to_screen_ratio":[physical.x/used.size.x,physical.y/used.size.y],"physical_origin":[actor.position.x,actor.position.y]})
	check(Game.run.hp == hp_before and is_equal_approx(room.enemy_skills._biome_clock,clock_before), id+" rendering waits keep simulation fixed")
	records.append({"room_id":id,"view":view,"path":path,"framebuffer":[image.get_width(),image.get_height()],"camera_position":[room.camera.position.x,room.camera.position.y],"camera_zoom":[room.camera.zoom.x,room.camera.zoom.y],"player_position":[room.player.position.x,room.player.position.y],"enemy_ids":FIRST_WAVES[id],"actors":actor_records,"displayed":displayed,"scenery":scenery_records.get(id,{})})

func _rect(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame
		await get_tree().physics_frame
