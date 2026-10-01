extends Node
## Terrain-specific regression plus actual L05/L02 production room captures.
## No threshold here can certify visual quality; root must inspect the PNGs.
const Appearance = preload("res://scripts/world/room_appearance.gd")
const Generator = preload("res://scripts/world/room_generator.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Layouts = preload("res://scripts/world/room_layouts.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TERRAIN_READABILITY: "+message)

func check_geometry() -> void:
	check(str(Catalog.room("L05").name)=="悬曜升台","reported L05 scaffold uses its current themed display name")
	for id: String in ["L02","L05","L12","L18","L22"]:
		var layout: Dictionary = Generator.generate(id,146556)
		var before: Array = layout.obstructions.duplicate(true)
		var recipe: Array = Appearance.recipe(layout,str(layout.biome_id))
		var inside := true
		var triangles := true
		var textured := true
		var relief := true
		var deterministic := true
		var rocks_seen := 0
		for item: Dictionary in recipe:
			if not item.get("static",false): continue
			var palette: Dictionary = Appearance._terrain_palette(item.kind,layout.biome_id)
			if palette.liquid: continue
			var seed_value: int = int(item.index)+str(item.room_id).hash()%101
			var rocks: Array[Dictionary] = Appearance._mineral_obstruction_recipe(item.rect,seed_value)
			deterministic = deterministic and rocks==Appearance._mineral_obstruction_recipe(item.rect,seed_value)
			for rock: Dictionary in rocks:
				rocks_seen += 1
				relief = relief and rock.height>=6 and rock.height<=37
				var top: PackedVector2Array = rock.top
				triangles = triangles and Appearance._terrain_triangle_indices(top).size()==(top.size()-2)*3
				for point: Vector2 in top:
					inside = inside and item.rect.has_point(point) and item.rect.has_point(point+Vector2(0,rock.height))
				for point: Vector2 in rock.source:
					textured = textured and Rect2(0,0,1254,1254).has_point(point)
				for edge: int in range(2,6):
					var next: int = (edge+1)%top.size()
					var side := PackedVector2Array([top[edge],top[next],top[next]+Vector2(0,rock.height),top[edge]+Vector2(0,rock.height)])
					for patch: Dictionary in Appearance._terrain_texture_patches(side):
						triangles = triangles and patch.indices.size()==(patch.polygon.size()-2)*3
		check(layout.obstructions==before,id+" presentation leaves collision and navigation data intact")
		check(inside and relief,id+" raised rock top and foot stay inside blocked footprint")
		check(triangles and textured and deterministic,id+" all rock faces and clipped side textures are deterministic and drawable")
		if id in ["L02","L05"]: check(rocks_seen>=20,id+" entire obstruction receives rock masses, not only edge trim")

func frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func capture_real_rooms() -> void:
	get_window().size = Vector2i(1280,720)
	check(Game.new_profile(),"isolated terrain profile")
	Game.profile.settings["muted"] = true
	var app: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	await frames(2)
	check(Game.start_run(),"actual main scene and live room started")
	var room: Node2D = app.room
	for view: Dictionary in [{"id":"L05","at":Vector2(1848,1075),"label":"user_region"},{"id":"L05","at":Vector2(1030,920),"label":"crossing"},{"id":"L02","at":Vector2(525,790),"label":"mine_bank"}]:
		check(room.load_room_layout(view.id,0,146556),"load actual "+str(view.id))
		check(Layouts.clear_for_actor(room.layout,view.at,24),"capture location is legal for ordinary movement "+str(view.label))
		room.player.position = view.at
		room.camera.follow_target()
		room.camera.force_update_scroll()
		# Keep the normal enemy AI, collisions, objective art, props and HUD live.
		await frames(30)
		await RenderingServer.frame_post_draw
		var target: String = "res://artifacts/terrain_"+str(view.id)+"_"+str(view.label)+".png"
		var screenshot: Image = get_viewport().get_texture().get_image()
		check(screenshot.save_png(target)==OK,"actual gameplay frame saved "+target)
		print("TERRAIN_CAPTURE ",target," camera=",room.camera.get_screen_center_position()," zoom=",room.camera.zoom," live_enemies=",room.enemies.get_child_count())
	app.free()
	await frames(2)

func _run() -> void:
	check_geometry()
	if DisplayServer.get_name()!="headless": await capture_real_rooms()
	print("TERRAIN_READABILITY: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
