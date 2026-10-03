extends Node
## Geometry and real-render checks for collision-faithful terrain presentation.
const Appearance = preload("res://scripts/presentation/world/room_appearance.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
var checks := 0
var failures := 0

class TerrainPanel extends Node2D:
	var repeat_preserved := true
	func _draw() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		var biomes: Array[String] = ["B01","B02","B03","B04"]
		var kinds: Array[String] = ["mine_pit","acid_reservoir","gantry_void","mirror_pool"]
		for index: int in range(4):
			var corner := Vector2(24+(index%2)*640,44+floori(index/2.0)*348)
			var backdrop := Rect2(corner,Vector2(594,304))
			var texture: Texture2D = Sampler.sampled("asset://world/"+biomes[index]+"_floor_v1.png")
			var floor_quad := PackedVector2Array([backdrop.position,Vector2(backdrop.end.x,backdrop.position.y),backdrop.end,Vector2(backdrop.position.x,backdrop.end.y)])
			Appearance._draw_terrain_texture(self,floor_quad,texture,Color(0.84,0.84,0.84))
			var pit := Rect2(corner+Vector2(42,35),Vector2(506,226))
			Appearance._draw_void(self,{"rect":pit,"collision_rect":pit,"kind":kinds[index],"biome_id":biomes[index],"index":index,"room_id":"terrain_preview"},1.3)
			repeat_preserved = repeat_preserved and texture_repeat==CanvasItem.TEXTURE_REPEAT_DISABLED
			draw_string(ThemeDB.fallback_font,corner-Vector2(0,12),biomes[index]+"  "+kinds[index],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("cbd5d7"))

class TextureProbe extends Node2D:
	var test_texture: Texture2D
	var reflected := false
	var repeat_preserved := true
	func _draw() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		var quad := PackedVector2Array([Vector2.ZERO,Vector2(840,0),Vector2(840,840),Vector2(0,840)])
		Appearance._draw_terrain_texture(self,quad,test_texture,Color.WHITE,reflected)
		repeat_preserved = texture_repeat==CanvasItem.TEXTURE_REPEAT_DISABLED

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PIT_PRESENTATION: "+label)

func _ready() -> void:
	_run.call_deferred()

func polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(1,polygon.size()-1):
		area += (polygon[index]-polygon[0]).cross(polygon[index+1]-polygon[0])
	return absf(area)*0.5

func geometry_checks() -> void:
	for rect: Rect2 in [Rect2(530,180,720,900),Rect2(-65,37,820,70),Rect2(420,420,48,360),Rect2(0,0,8,8)]:
		for seed_value: int in [0,29]:
			var layers: Dictionary = Appearance._terrain_layers(rect,seed_value)
			check(layers==Appearance._terrain_layers(rect,seed_value),"deterministic terrain layers "+str(rect))
			var inside := true
			var lip_error := 0.0
			var ordered := true
			var triangulates := true
			var depth_ok := true
			var depth_cap: float = minf(60,minf(rect.size.x,rect.size.y)*0.22)
			for key: String in ["upper","lip","lower"]:
				var polygon: PackedVector2Array = layers[key]
				triangulates = triangulates and Geometry2D.triangulate_polygon(polygon).size()==(polygon.size()-2)*3
				for point: Vector2 in polygon: inside = inside and rect.grow(0.001).has_point(point)
			for index: int in range(layers.upper.size()):
				var upper: Vector2 = layers.upper[index]
				var lip: Vector2 = layers.lip[index]
				var lower: Vector2 = layers.lower[index]
				lip_error = maxf(lip_error,minf(minf(upper.x-rect.position.x,rect.end.x-upper.x),minf(upper.y-rect.position.y,rect.end.y-upper.y)))
				ordered = ordered and upper.distance_to(lip)<upper.distance_to(lower) and upper.distance_to(lower)<upper.distance_to(rect.get_center())
				depth_ok = depth_ok and upper.distance_to(lower)<=depth_cap+0.01 and upper.distance_to(lower)>=minf(24,depth_cap)-0.01
				var next: int = (index+1)%layers.upper.size()
				var face := PackedVector2Array([upper,layers.upper[next],layers.lower[next],lower])
				triangulates = triangulates and Geometry2D.triangulate_polygon(face).size()==6
			check(inside and lip_error<=6.01,"entire pit remains inside collision with <=6 lip offset "+str(rect))
			check(ordered and triangulates,"nested rays and cliff polygons do not fold "+str(rect))
			check(depth_ok,"world-unit recess 24–60 capped at 22 percent narrow side "+str(rect))
	var polygon := PackedVector2Array([Vector2(-63,375),Vector2(942,399),Vector2(885,903),Vector2(37,853)])
	var patches: Array[Dictionary] = Appearance._terrain_texture_patches(polygon)
	var total_area := 0.0
	var uv_inside := true
	for patch: Dictionary in patches:
		total_area += polygon_area(patch.polygon)
		for uv: Vector2 in patch.uv: uv_inside = uv_inside and uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1
	check(absf(total_area-polygon_area(polygon))<1,"tile clipping covers original polygon exactly once")
	check(uv_inside and patches.size()>4,"mirrored tile UVs remain in 0..1 across negative and positive world tiles")
	check(Appearance._terrain_texture_patches(PackedVector2Array([Vector2(30,30),Vector2(100,30),Vector2(100,70),Vector2(30,70)])).size()==1,"small facet inside one tile retains typed polygon")
	check(Appearance._terrain_texture_patches(polygon,true)!=patches,"liquid reflection keeps its independent vertical inversion")
	var regression := PackedVector2Array([Vector2(1260.0,1106.561),Vector2(1259.874,1106.557),Vector2(1260.0,1106.087)])
	var regression_patches: Array[Dictionary] = Appearance._terrain_texture_patches(regression)
	check(regression_patches.size()==1 and regression_patches[0].indices.size()==3 and polygon_area(regression_patches[0].polygon)>0.02,"L12 tiny fragment retains its texture and explicit triangle, rather than being discarded")
	for kind: String in ["water_channel","acid_reservoir","mirror_pool"]:
		check(Appearance._terrain_palette(kind,"B01").liquid,"liquid surface preserved "+kind)
	for room_id: String in load(AssetCatalog.resolve("res://scripts/domain/world/world_catalog.gd")).room_ids():
		check_room_texture_patches(room_id,40917)
	check_room_texture_patches("L02",146556)

func check_room_texture_patches(room_id: String, seed_value: int) -> void:
	var layout: Dictionary = load(AssetCatalog.resolve("res://scripts/gameplay/world/room_generator.gd")).generate(room_id,seed_value)
	var valid_clipped := true
	var world_precision_failures := 0
	for item: Dictionary in Appearance.recipe(layout,"B01"):
		if not item.get("static",false): continue
		var layers: Dictionary = Appearance._terrain_layers(item.rect,int(item.index)+str(item.room_id).hash()%101)
		var polygons: Array[PackedVector2Array] = [layers.lower]
		for index: int in range(layers.upper.size()):
			var next: int = (index+1)%layers.upper.size()
			polygons.append(PackedVector2Array([layers.upper[index],layers.upper[next],layers.lower[next],layers.lower[index]]))
		for source: PackedVector2Array in polygons:
			var source_area: float = polygon_area(source)
			var rendered_area := 0.0
			for patch: Dictionary in Appearance._terrain_texture_patches(source):
				if Geometry2D.triangulate_polygon(patch.polygon).is_empty(): world_precision_failures += 1
				var indices: PackedInt32Array = patch.indices
				if indices.size()!=(patch.polygon.size()-2)*3:
					valid_clipped = false
					print("INVALID_CLIP room=",room_id," seed=",seed_value," rect=",item.rect," source=",source," clipped=",patch.polygon," area=",polygon_area(patch.polygon))
				for offset: int in range(0,indices.size(),3):
					var a: Vector2 = patch.polygon[indices[offset]]
					var b: Vector2 = patch.polygon[indices[offset+1]]
					var c: Vector2 = patch.polygon[indices[offset+2]]
					rendered_area += absf((b-a).cross(c-a))*0.5
			valid_clipped = valid_clipped and absf(source_area-rendered_area)<maxf(0.1,source_area*0.00001)
	check(valid_clipped,"actual "+room_id+" world tiles retain triangulatable floor and cliff patches")
	if room_id=="L12": check(world_precision_failures>0,"exact generated L12 tile corner reproduces world-coordinate precision failure, retained by indexed rendering")

func frames(count: int = 2) -> void:
	for _index: int in range(count): await get_tree().process_frame

func graphical_checks() -> void:
	get_window().size = Vector2i(1280,720)
	var panel := TerrainPanel.new()
	add_child(panel)
	await frames()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://artifacts/pit_terrain_comparison.png")==OK,"four biomes rendered")
	check(panel.repeat_preserved,"terrain leaves caller repeat state intact")
	panel.queue_free()
	await frames()
	var probe_view := SubViewport.new()
	probe_view.size = Vector2i(840,840)
	probe_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(probe_view)
	var probe := TextureProbe.new()
	var source := Image.create(16,16,false,Image.FORMAT_RGBA8)
	var source_colors: Array[Color] = [Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW]
	for y: int in range(16):
		for x: int in range(16): source.set_pixel(x,y,source_colors[(1 if x>=8 else 0)+(2 if y>=8 else 0)])
	probe.test_texture = ImageTexture.create_from_image(source)
	probe_view.add_child(probe)
	for reflected: bool in [false,true]:
		probe.reflected = reflected
		probe.queue_redraw()
		await frames()
		await RenderingServer.frame_post_draw
		var capture: Image = probe_view.get_texture().get_image()
		var all_match := true
		for y: int in range(4):
			for x: int in range(4):
				var source_x: int = x if x<2 else 3-x
				var source_y: int = y if y<2 else 3-y
				if reflected: source_y = 1-source_y
				var expected: Color = source_colors[source_x+source_y*2]
				var actual: Color = capture.get_pixel(105+x*210,105+y*210)
				all_match = all_match and Vector3(actual.r,actual.g,actual.b).distance_to(Vector3(expected.r,expected.g,expected.b))<0.025
		check(all_match and probe.repeat_preserved,"GPU samples 2x2 mirrored world tiles, reflected="+str(reflected))
	check(probe_view.get_texture().get_image().save_png("res://artifacts/pit_texture_mirror_probe.png")==OK,"actual mirrored diagnostic render saved")
	probe_view.queue_free()
	await frames()
	check(Game.new_profile(),"isolated real-room profile")
	var app: Node = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	await frames()
	check(Game.start_run(),"real room departure")
	var room: Node2D = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	check(room.load_room_layout("L02",0,146556),"same L02 seed as crowd observation")
	room.player.position = Vector2(525,590)
	room.player.aim_direction = Vector2.RIGHT
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.enemy_props.queue_redraw()
	room.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://artifacts/pit_L02_refined.png")==OK,"real L02 and production camera captured")
	print("PIT_CAPTURE camera=",room.camera.get_screen_center_position()," zoom=",room.camera.zoom," seed=",room.layout_seed)
	app.free()
	await frames()

func _run() -> void:
	geometry_checks()
	if DisplayServer.get_name()!="headless": await graphical_checks()
	print("PIT_PRESENTATION: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
