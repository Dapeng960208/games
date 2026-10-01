extends Node
## The production level keeps its physics plane while every raised silhouette
## sorts at its own ground foot. Optional GPU probes verify real draw ordering.
const RoomScene = preload("res://scenes/room.tscn")
const Art = preload("res://scripts/world/world_art.gd")
const Appearance = preload("res://scripts/world/room_appearance.gd")
const DepthSprite = preload("res://scripts/world/room_depth_sprite.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
var checks: int = 0
var failures: int = 0
var room: MineRoom

class SortingProbe extends Node2D:
	var offset := Vector2.ZERO
	func _draw() -> void:
		draw_rect(Rect2(offset-Vector2(12,12),Vector2(24,24)),Color("ff00ff"))

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WORLD_DEPTH: "+label)

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw

func _run() -> void:
	if not Game.profile_path.contains("test_world_depth"):
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280,720)
	check(Game.new_profile() and Game.start_run(),"isolated production run")
	room = RoomScene.instantiate()
	room.run_seed = 64482
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	for actor: Node in room.enemies.get_children(): actor.free()
	check(room.y_sort_enabled and room.enemies.y_sort_enabled and room.enemies.z_index==2,"nested actor depth plane exists")
	check(room.player.z_index==2 and room._depth_canvas.z_index==2 and room._depth_canvas.y_sort_enabled,"player and raised silhouettes share the same depth plane")
	check(room.enemy_telegraphs.z_index>2 and room.enemy_skills.z_index>2 and room.impact_feedback.z_index>2,"warnings and contact confirmation stay readable above raised scenery")
	var architecture: Texture2D = Sampler.sampled(Art.ARCHITECTURE_PATH)
	check(architecture!=null,"original painted architecture loads")
	if architecture!=null:
		var source: Image = architecture.get_image()
		check(source.get_pixel(0,0).a<0.01,"architecture atlas keeps transparent exterior")
		for key: String in ["column","wall_horizontal","wall_vertical","rock_island","stairs","arch"]:
			var definition: Dictionary = Art.architecture_region(key)
			check(not definition.is_empty(),"complete module UVs and base anchor: "+key)
			if definition.is_empty(): continue
			check(Rect2(Vector2.ZERO,architecture.get_size()).encloses(definition.source),"module region remains inside original atlas: "+key)
			check(Rect2(Vector2.ZERO,definition.source.size).has_point(definition.foot),"module ground foot is crop-local: "+key)
	for id: String in Catalog.room_ids():
		check(room.load_room_layout(id,0,64482),"production layout loads: "+id)
		var original: Array[Rect2] = room.obstructions.duplicate()
		var generation: int = room._depth_canvas.generation
		room._refresh_terrain_canvas()
		check(room._depth_canvas.generation==generation,"static depth nodes retain draw lists: "+id)
		check(room.obstructions==original,"height presentation never mutates collision: "+id)
		check(room._terrain_owner_id==room.enemy_props.get_instance_id(),"new room updates both retained canvases immediately: "+id)
		if id in Appearance.BRIDGE_GAP_ROOMS:
			for item: Dictionary in room.enemy_props.obstacle_recipes:
				if not bool(item.get("static",false)): continue
				check(Appearance.is_recessed_terrain(item),"real bridge gaps retain recessed depth: "+id)
				check(not room._depth_canvas.recipes.any(func(raised: Dictionary) -> bool: return str(raised.id)==str(item.id)),"real bridge gaps never become raised islands: "+id)
		for sprite: Node2D in room._depth_canvas.get_children():
			check(sprite.position==Vector2(sprite.recipe.foot),"individual scenery node sorts at its real base: "+id)
			check(sprite.z_index==0,"individual local z shares parent actor plane: "+id)
			if str(sprite.recipe.get("depth_kind",""))=="island":
				check(original.has(sprite.recipe.collision_rect),"raised plinth maps to an existing blocked footprint: "+id)
			elif str(sprite.recipe.get("depth_kind",""))=="architecture":
				var footprint: Rect2 = sprite.recipe.get("collision_rect",Rect2())
				if footprint.has_area():
					check(original.has(footprint),"interior column keeps its budgeted physical footprint: "+id)
				elif not bool(sprite.recipe.get("open_passage",false)):
					check(bool(sprite.recipe.get("non_solid",false)),"perimeter architecture is decorative: "+id)
					var world_ground: Rect2 = Appearance.architecture_ground(str(sprite.recipe.architecture),sprite.recipe.foot,sprite.recipe.art_size,str(sprite.recipe.biome_id))
					check(not room.layout.arena.intersects(world_ground),"decorative stone base stays outside playable boundary: "+id)
				else:
					check(sprite.recipe.foot==room.exit_position and bool(sprite.recipe.non_solid),"painted exit retains its existing open interaction passage: "+id)
	room.load_room_layout("L05",0,64482)
	room.player.position = Vector2(1400,900)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frames()
	if DisplayServer.get_name()!="headless":
		check(get_viewport().get_texture().get_image().save_png("res://artifacts/world_depth_L05_1280.png")==OK,"actual native courtyard capture saved")
		await _gpu_sort_probe()
	if is_instance_valid(room.combat_audio): await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
	print("WORLD_DEPTH checks=%d failures=%d renderer=%s" % [checks,failures,DisplayServer.get_name()])
	get_tree().quit(0 if failures==0 else 1)

func _gpu_sort_probe() -> void:
	room.player.visible = false
	var definition: Dictionary = Art.architecture_region("column")
	var texture: Texture2D = Sampler.sampled(Art.ARCHITECTURE_PATH)
	if texture==null or definition.is_empty(): return
	var size := Vector2(180,340)
	var scale: float = minf(size.x/definition.source.size.x,size.y/definition.source.size.y)
	var source: Image = texture.get_image()
	var local_pixel := Vector2.ZERO
	var found: bool = false
	# Choose real opaque upper stone, above the authored ground foot.
	for y: int in range(20,int(definition.foot.y)-40,8):
		for x: int in range(24,int(definition.source.size.x)-24,8):
			var color: Color = source.get_pixel(int(definition.source.position.x)+x,int(definition.source.position.y)+y)
			if color.a>0.99:
				local_pixel = Vector2(x,y)
				found = true
				break
		if found: break
	check(found,"depth probe samples actual opaque upper stone")
	if not found: return
	var foot := Vector2(1400,1000)
	var actual_point: Vector2 = foot+(local_pixel-Vector2(definition.foot))*scale
	var test_column := DepthSprite.new()
	room._depth_canvas.add_child(test_column)
	test_column.configure(room,{"depth_kind":"architecture","foot":foot,"architecture":"column","art_size":size,"biome_id":"B01","occludes":false})
	var marker := SortingProbe.new()
	marker.z_index = 2
	marker.position = actual_point
	room.add_child(marker)
	var screen: Vector2i = Vector2i(room.get_global_transform_with_canvas()*actual_point)
	await frames()
	var behind: Color = get_viewport().get_texture().get_image().get_pixelv(screen)
	check(behind.g<0.95 and (behind.g>0.04 or behind.b<0.93),"real painted column occludes actor behind its foot")
	marker.position = Vector2(actual_point.x,foot.y+40)
	marker.offset = actual_point-marker.position
	marker.queue_redraw()
	await frames()
	var in_front: Color = get_viewport().get_texture().get_image().get_pixelv(screen)
	check(in_front.r>0.95 and in_front.g<0.05 and in_front.b>0.95,"actor in front of base draws over same painted stone")
	marker.free()
	test_column.free()
