extends Node
## Production map selection and native four-faction composition evidence.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const Props = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
const Appearance = preload("res://scripts/presentation/world/room_appearance.gd")
const FLOOR_TILE := Vector2(426,340.8)
const SAMPLES := {"B01":"L05","B02":"L09","B03":"L14","B04":"L21"}
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WORLD_FACTIONS: "+label)

func _ready() -> void:
	call_deferred("_run")

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw

func check_native_floor(room: RoomController, screenshot: Image, biome: String) -> void:
	var backdrop: Node2D = room.get_node("MineBackdrop")
	var transform: Transform2D = backdrop.get_global_transform_with_canvas()
	var palette: Color = Art.palette(biome).ground
	var sampled: int = 0
	for y: int in range(ceili(room.layout.arena.size.y/FLOOR_TILE.y)):
		for x: int in range(ceili(room.layout.arena.size.x/FLOOR_TILE.x)):
			var at: Vector2 = Vector2(room.layout.arena.position)+(Vector2(x,y)+Vector2(.5,.5))*FLOOR_TILE
			var screen: Vector2 = transform*at
			if not Rect2(30,30,1220,660).has_point(screen): continue
			if room.obstructions.any(func(rect: Rect2) -> bool: return rect.grow(20).has_point(at)): continue
			var detail: float = 0.0
			for offset: Vector2i in [Vector2i(-8,-8),Vector2i(8,-8),Vector2i(-8,8),Vector2i(8,8)]:
				var pixel: Color = screenshot.get_pixelv(Vector2i(screen)+offset)
				detail = maxf(detail,absf(pixel.r-palette.r)+absf(pixel.g-palette.g)+absf(pixel.b-palette.b))
			check(detail>.02,biome+" native floor covers tile parity "+str(Vector2i(x%2,y%2)))
			sampled += 1
	check(sampled>=3,biome+" native floor coverage samples visible unobstructed tiles")

func _run() -> void:
	if not Game.profile_path.contains("test_world_factions"):
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280,720)
	check(Game.new_profile() and Game.start_run(),"isolated production run")
	var room: RoomController = RoomScene.instantiate()
	room.run_seed = 1
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	var surfaces: Array = []
	for biome: String in SAMPLES:
		check(room.load_room_layout(SAMPLES[biome],0,1),biome+" production map loads")
		for actor: Node in room.enemies.get_children(): actor.free()
		check(room._biome_id()==biome,biome+" production identity selects its own art")
		var definition: Dictionary = Art.floor_definition(biome)
		var identity: String = str(definition.path)+str(definition.source)
		check(not surfaces.has(identity),biome+" has a distinct original painted surface")
		surfaces.append(identity)
		check(room.get_node("MineBackdrop").floor_texture==Art.floor_texture_for(biome),biome+" uses selected floor in production")
		var originals: Array = room.obstructions.duplicate()
		room._refresh_terrain_canvas()
		check(room.obstructions==originals,biome+" artwork never changes physical routes")
		if biome!="B01":
			var asset: String = Appearance.faction_architecture_asset("column",biome)
			check(Props.has_authored_asset(asset),biome+" raised landmark uses its faction's actual art")
			check(Appearance.architecture_definition("column",biome)==Props.definition_for_asset(asset),biome+" landmark UVs follow authored regional body")
		for entity: Dictionary in room.layout.prop_instances:
			check(Props.has_authored_asset(str(entity.asset)),biome+" every old map machine resolves to fresh regional art")
		room.player.position = Vector2(1040,820)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await frames()
		if DisplayServer.get_name()!="headless":
			var screenshot: Image = get_viewport().get_texture().get_image()
			check_native_floor(room,screenshot,biome)
			check(screenshot.get_size()==Vector2i(1280,720),biome+" native render size")
			check(screenshot.save_png("res://artifacts/world_factions_"+biome+"_center.png")==OK,biome+" center native capture saved")
			room.player.position = Vector2(540,310)
			room.camera.follow_target()
			room.camera.force_update_scroll()
			await frames()
			check(get_viewport().get_texture().get_image().save_png("res://artifacts/world_factions_"+biome+"_edge.png")==OK,biome+" raised boundary native capture saved")
	if is_instance_valid(room.combat_audio): await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
	print("WORLD_FACTIONS checks=%d failures=%d renderer=%s" % [checks,failures,DisplayServer.get_name()])
	get_tree().quit(0 if failures==0 else 1)
