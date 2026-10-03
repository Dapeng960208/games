extends Node
## Real main scene, room, texture sampler and GPU drawing; no mock canvas.
const Appearance = preload("res://scripts/presentation/world/room_appearance.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
var checks: int = 0
var failures: int = 0
var app: Node
var room: RoomController

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.queue_redraw()
	room.enemy_props.queue_redraw()
	await frame()
	await frame()
	if DisplayServer.get_name() != "headless":
		check(get_viewport().get_texture().get_image().save_png("res://artifacts/"+name+".png")==OK, "saved actual renderer " + name)

func _run() -> void:
	if not Game.profile_path.contains("test_room_props_render"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated real profile")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	check(Game.start_run(),"production run starts")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	var verified_floors: Dictionary = {}
	for id: String in Catalog.room_ids():
		check(room.load_room_layout(id,-1,8441),id+" production seeded load")
		room.player.position = room.enemy_props.props[0].position
		room.queue_redraw()
		room.enemy_props.queue_redraw()
		await frame()
		await frame()
		check(room.enemy_props._supply_textures.size()==3,id+" all generated supply images drew")
		var floor_path: String = "asset://world/"+str(Catalog.room(id).biome_id)+"_floor_v1.png"
		check(Sampler.sampled(floor_path)!=null,id+" actual biome floor loads")
		if not verified_floors.has(floor_path):
			var original: Image = Image.load_from_file(AssetCatalog.resolve(floor_path))
			var drawn: Image = room.get_node("MineBackdrop").floor_texture.get_image()
			if drawn.is_compressed():
				drawn.decompress()
			check(original.get_size()==drawn.get_size() and original.get_pixel(170,113).is_equal_approx(drawn.get_pixel(170,113)),id+" production backdrop uses this biome PNG at native dimensions")
			verified_floors[floor_path] = true
		if id in ["L01","L09","L14","L21"]:
			room.player.position = Vector2(460,890)
			if not room.valid_ground(room.player.position,24):
				room.player.position = room.enemy_props.props[0].position
			await _capture("room_props_"+id)
	check(Appearance._art_regions.size()==12,"all 12 generated obstruction images entered production drawing")
	for path: String in Appearance._art_regions:
		var region: Rect2 = Appearance._art_regions[path]
		check(region.has_area() and region.size.x>100 and region.size.y>100,path+" actual alpha silhouette bounds")
	var placement_report: Dictionary = {}
	for seed_value: int in [8441,9923]:
		room.load_room_layout("L01",-1,seed_value)
		var supply_positions: Array = []
		for index: int in room.enemy_props.props.size():
			var item: Dictionary = room.enemy_props.props[index]
			supply_positions.append([item.position.x,item.position.y])
			room.player.position = item.position+Vector2(100,95)
			if not room.valid_ground(room.player.position,24):
				room.player.position = item.position
			await _capture("room_props_L01_seed_%d_sector_%d" % [seed_value,index+1])
		placement_report[str(seed_value)] = {"supplies":supply_positions,"obstacle_count":room.obstructions.size(),"prop_count":room.layout.prop_instances.size()}
	var report: FileAccess = FileAccess.open(AssetCatalog.resolve("res://artifacts/room_props_seed_placement.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(placement_report,"\t"))
	room.load_room_layout("L01",-1,8441)
	room.player.position = room.enemy_props.props[0].position
	room.release_gate = false
	room.input_blocked = false
	check(room.nearby_interaction().get("kind", "")=="buff","production E selects real device")
	room.interact()
	check(is_equal_approx(room.enemy_props.damage_bonus(),.20),"production E gives actual attack bonus")
	await _capture("room_props_used")
	print("ROOM_PROPS_RENDER: %d checks; %d failures; generated_regions=%d" % [checks,failures,Appearance._art_regions.size()])
	get_tree().quit(0 if failures==0 else 1)
