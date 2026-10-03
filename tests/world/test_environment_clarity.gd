extends "res://tests/world/test_room_presentation.gd"
## GPU sampling evidence: enlarged edges, continuous joins and the actual L16
## fullscreen path. Uses isolated profiles and keeps source artwork untouched.
const Chunks = preload("res://scripts/presentation/world/environment_chunks.gd")
const CLARITY_OUTPUT := "res://artifacts/environment-clarity/"

func capture_pixels() -> Image:
	await frames(2)
	RenderingServer.force_draw(false)
	return get_viewport().get_texture().get_image()

func save_capture(filename: String) -> void:
	var pixels: Image = await capture_pixels()
	check(not pixels.is_empty() and pixels.get_size() == get_window().size, filename+" renders at the actual window resolution")
	check(pixels.save_png(CLARITY_OUTPUT+filename) == OK, filename+" saved")

func edge_energy(pixels: Image) -> float:
	var energy := 0.0
	var y := pixels.get_height()/2
	for x: int in range(85,125):
		var difference := pixels.get_pixel(x+1,y).r-pixels.get_pixel(x,y).r
		energy += difference*difference
	return energy

func check_joins(viewport: SubViewport, chunks: Node2D, painting: Texture2D, sampling: Material, label: String) -> float:
	chunks.configure(painting,Rect2(5.25,3.375,200.5,110.5),label)
	await capture_pixels()
	var joined := viewport.get_texture().get_image()
	chunks.hide()
	var whole := Sprite2D.new()
	whole.texture = painting
	whole.centered = false
	whole.position = Vector2(5.25,3.375)
	whole.scale = Vector2(200.5,110.5)/painting.get_size()
	whole.material = sampling
	whole.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	viewport.add_child(whole)
	await capture_pixels()
	var reference := viewport.get_texture().get_image()
	var largest_difference := 0.0
	for y: int in range(5,111):
		for x: int in range(7,204):
			var a := joined.get_pixel(x,y)
			var b := reference.get_pixel(x,y)
			largest_difference = maxf(largest_difference,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
	check(largest_difference <= 2.0/255.0,label+" six regions match the whole-image sampler without visible joins")
	whole.free()
	chunks.show()
	return largest_difference

func sampling_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var source := Image.create(64,32,false,Image.FORMAT_RGBA8)
	source.fill(Color.BLACK)
	source.fill_rect(Rect2i(32,0,32,32),Color.WHITE)
	var texture := ImageTexture.create_from_image(source)
	var chunks := Chunks.new()
	viewport.add_child(chunks)
	chunks.configure(texture,Rect2(5.25,3.375,200.5,110.5),"sampling-fixture")
	var sampling: Material = chunks.material
	chunks.material = null
	await capture_pixels()
	var linear := viewport.get_texture().get_image()
	chunks.material = sampling
	await capture_pixels()
	var reconstructed := viewport.get_texture().get_image()
	check(edge_energy(reconstructed) > edge_energy(linear)*1.04,"enlarged high-contrast edge retains more contrast than bilinear sampling")
	# Compare six joined regions with one whole-image sprite using the same
	# texture, transform and sampler. A per-region clamp/UV bug becomes visible.
	for y: int in range(32):
		for x: int in range(64):
			source.set_pixel(x,y,Color.WHITE if (x/3+y/3)%2 else Color.BLACK)
	var enlarged_delta: float = await check_joins(viewport,chunks,ImageTexture.create_from_image(source),sampling,"enlarged checkerboard")
	var painting: Texture2D = Art.environment_texture_for("B03","L16")
	var minified_delta: float = await check_joins(viewport,chunks,painting,sampling,"minified L16")
	print("ENVIRONMENT_CLARITY edge energy linear=",edge_energy(linear)," reconstructed=",edge_energy(reconstructed)," enlarged join delta=",enlarged_delta," minified join delta=",minified_delta)
	viewport.free()

func compare_room(id: String, label: String) -> void:
	if not await install(id): return
	var chunks: Node2D = room.get_node("MineBackdrop").environment_chunks
	var sampling: Material = chunks.material
	check(sampling is ShaderMaterial and sampling.shader == Chunks.SAMPLING_SHADER,id+" production background selects the reconstruction sampler")
	check(chunks.chunks.size() == 6,id+" retains six shared regions")
	var ground_before: PackedVector2Array = room.ground_polygon.duplicate()
	var zoom_before: Vector2 = room.camera.zoom
	chunks.material = null
	await save_capture(id+"_before_"+label+".png")
	chunks.material = sampling
	await save_capture(id+"_after_"+label+".png")
	check(room.camera.zoom == zoom_before and room.ground_polygon == ground_before,id+" sampling preserves camera scale and walkable ground")
	print("ENVIRONMENT_CLARITY ",id," ",label," logical=",get_viewport().get_visible_rect().size," physical=",get_window().size," camera=",room.camera.zoom," image-to-world=",chunks.chunks[0].scale)

func _run() -> void:
	if not Game.profile_path.contains("test_environment_clarity") or DisplayServer.get_name() == "headless":
		push_error("Environment clarity requires GPU rendering and an isolated test profile")
		get_tree().quit(2)
		return
	# The fresh profile unlocks B01; room fixtures still install L16/BO04 directly.
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":146556}),"isolated run starts")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLARITY_OUTPUT))
	Words.set_locale("zh_CN")
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	layer = CanvasLayer.new()
	add_child(layer)
	hud = load(AssetCatalog.resolve("res://scenes/presentation/hud.tscn")).instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	# Match production canvas_items stretching: keep the logical 1280x720
	# canvas while the render target grows to the physical window/fullscreen.
	get_window().content_scale_size = Vector2i(1280,720)
	await sampling_checks()
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		get_window().size = extent
		await frames()
		for id: String in ["L16","BO04"]:
			await compare_room(id,str(extent.x)+"x"+str(extent.y))
	get_window().mode = Window.MODE_FULLSCREEN
	await frames(4)
	await compare_room("L16","fullscreen")
	get_window().mode = Window.MODE_WINDOWED
	check(await room.combat_audio.wait_for_cleanup(),"room audio drains")
	layer.free()
	room.free()
	Game.run = null
	await frames(2)
	print("ENVIRONMENT_CLARITY_RESULT checks=",checks," failures=",failures," gpu=true")
	get_tree().quit(1 if failures else 0)
