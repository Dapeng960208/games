extends Node
## Production room, original images and actual GPU frames in an isolated profile.
const Appearance = preload("res://scripts/world/room_appearance.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Art = preload("res://scripts/world/world_art.gd")
const CAPTURE_ROOMS := ["L01","L02","L07","L09","L14","L21"]
@export var capture_only: bool = false
var app: Node
var room: MineRoom
var checks: int = 0
var failures: int = 0
var render_report: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WORLD_READABILITY: " + label)

func frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _check_terrain_pixels(screenshot: Image, id: String) -> void:
	var transform: Transform2D = room.get_global_transform_with_canvas()
	var samples: Array = []
	for item: Dictionary in room.enemy_props.obstacle_recipes:
		if not bool(item.get("static",false)): continue
		var collision: Rect2 = item.collision_rect
		var inset: Rect2 = collision.grow(-minf(48,minf(collision.size.x,collision.size.y)*0.23))
		var visible: Rect2 = Rect2(transform*inset.position,transform*inset.end-transform*inset.position).intersection(Rect2(8,112,1264,500))
		var count: int = 0
		var dark: int = 0
		var brightness: float = 0.0
		var minimum: float = 1.0
		var maximum: float = 0.0
		for y: int in range(ceili(visible.position.y),floori(visible.end.y),8):
			for x: int in range(ceili(visible.position.x),floori(visible.end.x),8):
				var pixel: Color = screenshot.get_pixel(x,y)
				var luma: float = pixel.r*0.2126+pixel.g*0.7152+pixel.b*0.0722
				count += 1
				brightness += luma
				minimum = minf(minimum,luma)
				maximum = maxf(maximum,luma)
				if luma<0.060: dark += 1
		if count<64: continue
		var dark_ratio: float = float(dark)/count
		var mean: float = brightness/count
		check(dark_ratio<0.35,id+" terrain cannot be an apparently unloaded black block: "+str(item.kind))
		check(mean>0.075 and maximum-minimum>0.035,id+" terrain retains visible depth and surface detail")
		samples.append({"kind":item.kind,"samples":count,"near_black_ratio":dark_ratio,"mean_luminance":mean,"luminance_range":maximum-minimum})
	render_report[id] = samples

func _run() -> void:
	if not Game.profile_path.contains("test_world_readability"):
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280,720)
	check(Game.new_profile(),"isolated profile")
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	check(Game.start_run(),"production run starts")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	var kinds: Dictionary = {}
	var selected_rooms: Array = ["L01"] if capture_only else Catalog.room_ids()
	for id: String in selected_rooms:
		check(room.load_room_layout(id,-1,8441),id+" production room loads")
		check(room.get_node("MineBackdrop").floor_texture != null,id+" original floor image loads")
		check(room.get_node("MineBackdrop").floor_texture==Art.floor_texture_for(room._biome_id()),id+" selected faction floor loads across every region")
		for instance: Dictionary in room.layout.prop_instances:
			check(Sampler.sampled(Appearance._asset_path(instance.asset)) != null,id+" original obstruction image loads: "+str(instance.asset))
		for recipe: Dictionary in room.enemy_props.obstacle_recipes:
			if "non_solid" in recipe.get("tags",[]):
				check(not recipe.collision_rect.has_area() and not room.obstructions.has(recipe.collision_rect),id+" garden decoration creates no invisible collider")
			else:
				check(room.obstructions.has(recipe.collision_rect),id+" solid visual uses its actual collision footprint")
			if bool(recipe.get("static",false)):
				kinds[recipe.kind] = true
				var outline: PackedVector2Array = Appearance._terrain_outline(recipe.collision_rect,29)
				for point: Vector2 in outline:
					var rect: Rect2 = recipe.collision_rect
					check(rect.grow(0.01).has_point(point),id+" visible lip stays inside collision")
					var edge_distance: float = minf(minf(point.x-rect.position.x,rect.end.x-point.x),minf(point.y-rect.position.y,rect.end.y-point.y))
					check(edge_distance<=6.01,id+" lip does not hide an invisible wide collision border")
		room.player.position = Vector2(1400,900)
		room.player.aim_direction = Vector2.RIGHT
		room.camera.follow_target()
		room.camera.force_update_scroll()
		room.queue_redraw()
		room.enemy_props.queue_redraw()
		await frame()
		await frame()
		if DisplayServer.get_name() != "headless":
			var screenshot: Image = get_viewport().get_texture().get_image()
			check(screenshot.get_size()==Vector2i(1280,720),"native 1280x720 capture")
			_check_terrain_pixels(screenshot,id)
			if id in CAPTURE_ROOMS:
				check(screenshot.save_png("res://artifacts/world_readability_"+id+".png")==OK,"saved actual GPU frame "+id)
	if not capture_only:
		check(kinds.size()==Appearance.VOID_KINDS.size(),"all eleven authored terrain styles covered")
	if not render_report.is_empty() and not capture_only:
		var report: FileAccess = FileAccess.open("res://artifacts/world_readability_metrics.json",FileAccess.WRITE)
		report.store_string(JSON.stringify(render_report,"\t"))
	# Freeze the context dispatcher while the audio thread releases voices.
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(),"world readability fixture releases music playback before exit")
	app.free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("WORLD_READABILITY: %d checks; %d failures; original_prop_assets=%d" % [checks,failures,Appearance._art_regions.size()])
	get_tree().quit(0 if failures==0 else 1)
