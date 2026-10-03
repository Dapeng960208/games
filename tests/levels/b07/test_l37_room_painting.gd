extends Node
## Focused mapping/navigation verification; capture poses are controlled fixtures.
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Boundary = preload("res://scripts/gameplay/world/room_boundary.gd")
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
var failures := 0
var checks := 0
var report := {"natural_play":false,"navigation":[],"frames":[]}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("L37 ROOM PAINTING: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var out := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if out.is_empty(): get_tree().quit(2); return
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440) if DisplayServer.get_name()!="headless" else Vector2i(1280,720)
	await get_tree().process_frame
	check(not Art.environment_definition("B01","L01").is_empty(),"existing L01 background remains available")
	check(Art.environment_definition("B07","L38").is_empty(),"no false independent L38 room")
	if not Art.b07_room_painting_review_enabled():
		check(Art.environment_definition("B07","L37").is_empty(),"new manifest gated outside review")
		# Deliberately inject cache data: authorization gate must precede lookup.
		Art._environments["B07:L37"] = {"sentinel":true}
		check(Art.environment_definition("B07","L37").is_empty(),"cached review cannot bypass gate")
		Art._environments.erase("B07:L37")
		_finish(out); return
	var launch := Launcher.new()
	launch.auto_start = false
	launch.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(launch)
	check(launch.start_candidate("CH01",0,true),"production candidate launcher")
	if not is_instance_valid(launch.room): launch.free(); _finish(out); return
	var room: Node2D = launch.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.enemy_skills.process_mode = Node.PROCESS_MODE_DISABLED
	room.camera.process_mode = Node.PROCESS_MODE_DISABLED
	room.combat_audio.audible = false
	var backdrop: Node2D = room.get_node("MineBackdrop")
	var definition := Art.environment_definition("B07","L37")
	check(bool(backdrop.b07_room_painting_review_ready),"independent room ready")
	check(not is_instance_valid(backdrop.b07_art_trial),"old trial does not cover new painting")
	check(bool(definition.get("room_specific",false)),"room-specific WorldArt selection")
	var bounds := Art.environment_world_rect(room.layout.arena,"B07","L37")
	check(bounds.is_equal_approx(Rect2(-203,-162.4,2030,4060.0/3.0)),"shared placement mapping")
	check(backdrop.painted_bounds().is_equal_approx(bounds) and room.camera.render_bounds.is_equal_approx(bounds),"background/camera bounds agree")
	check(not room.camera.b07_art_overscan and not room.camera.b07_north_review,"no trial camera mode")
	check(room.camera.zoom.is_equal_approx(Vector2(.85,.85)),"shared .85 camera zoom")
	check(room.camera.position.is_equal_approx(room.player.position),"shared player following without bias")
	check(backdrop.environment_chunks.chunks.size()==6,"six common source partitions")
	for chunk: Sprite2D in backdrop.environment_chunks.chunks:
		check(chunk.texture==backdrop.environment_texture,"chunks share original texture")
	var detail: Node2D = backdrop.environment_chunks.native_detail
	var detail_review: bool = "--b07-native-detail-review" in OS.get_cmdline_user_args()
	if detail_review:
		check(is_instance_valid(detail) and detail.tiles.size()==6,"six real native detail repaints installed")
		if is_instance_valid(detail):
			var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("asset://world/rooms_2k/L37/manifest.json")))
			for i in detail.tiles.size():
				var tile: Sprite2D=detail.tiles[i]
				var entry: Dictionary=raw.tiles[i]
				var rect:=Rect2(float(entry.source_rect[0]),float(entry.source_rect[1]),float(entry.source_rect[2]),float(entry.source_rect[3]))
				check(tile.position.is_equal_approx(bounds.position+rect.position/Vector2(1536,1024)*bounds.size),"detail foot/world mapping")
				check(tile.scale.is_equal_approx(rect.size/Vector2(1536,1024)*bounds.size/tile.texture.get_size()),"detail source rectangle scale")
				check(tile.texture.get_width()/rect.size.x>=2.35 and tile.texture.get_height()/rect.size.y>=2.35,"native detail density")
	else:
		check(not is_instance_valid(detail),"candidate detail remains gated")
	report["detail_tiles"]=detail.tiles.size() if is_instance_valid(detail) else 0
	var mapped := Art.environment_ground_polygon(room.layout.arena,"B07","L37")
	check(mapped.size()==room.ground_polygon.size(),"polygon vertex count")
	for i in mini(mapped.size(),room.ground_polygon.size()):
		check(mapped[i].distance_to(room.ground_polygon[i])<.001,"same polygon transform "+str(i))
	var geometry := Geometry.room("L37")
	check(Geometry.world_point(geometry.entry).is_equal_approx(Vector2(320,900)*.58) and Geometry.world_point(geometry.exit).is_equal_approx(Vector2(2480,900)*.58),"entry/exit unchanged")
	check(Geometry.world_point(geometry.mirrors[0].position).is_equal_approx(Vector2(980,630)*.58) and Geometry.world_point(geometry.altar.position).is_equal_approx(Vector2(1904,630)*.58),"mirror/altar unchanged")
	for id: String in ["L37","L38","L39","L40","L41","L42","BO07"]:
		check(Geometry.validate(id).is_empty(),id+" authored geometry validation")
	var min_clearance := INF
	for route: Array in geometry.safe_routes:
		for at: Vector2 in Geometry.points(route):
			for i in mapped.size():
				var edge: Vector2 = mapped[(i+1)%mapped.size()]-mapped[i]
				min_clearance=minf(min_clearance,edge.cross(at-mapped[i])/edge.length())
	check(min_clearance>=90,"complete convex safe-route corridor keeps 180 world width")
	report["minimum_route_clearance_world"] = min_clearance
	report["safe_route_width_world"] = 180
	var targets: Array[Vector2] = [room.layout.exit,Geometry.world_point(geometry.mirrors[0].position),Geometry.world_point(geometry.altar.position)]
	for gate: Dictionary in geometry.manual_gates: targets.append(Geometry.world_point(gate.position))
	for p: Array in geometry.encounter_anchors: targets.append(Geometry.world_point(p))
	for radius: float in [12.0,14.0,18.0,24.0]:
		for target: Vector2 in targets:
			var at: Vector2 = room.layout.entry
			var steps := 0
			while at.distance_to(target)>5.0 and steps<600:
				var direction: Vector2 = room.navigation_direction(at,target,radius)
				if direction.is_zero_approx(): break
				var next: Vector2 = room.move_actor(at,direction*minf(8,at.distance_to(target)),radius)
				if next.distance_to(at)<.001: break
				at=next; steps+=1
			check(at.distance_to(target)<=5,"navigation reaches target radius="+str(radius)+" target="+str(target))
			report.navigation.append({"radius":radius,"target":[target.x,target.y],"steps":steps,"remaining":at.distance_to(target)})
	# Physical boundary clamp and swept movement retain every registered radius.
	for radius: float in [12.0,14.0,18.0,24.0]:
		for point: Vector2 in mapped:
			check(Boundary.contains(mapped,Boundary.clamp_point(mapped,point,radius),radius),"edge inset radius="+str(radius))
	if DisplayServer.get_name()!="headless":
		var places := {"entry":room.layout.entry,"center":Vector2(1400,1050)*.58,"exit":room.layout.exit}
		for name: String in places:
			room.player.position=places[name]
			room.camera.follow_target(); room.camera.force_update_scroll()
			check(room.valid_ground(room.player.position,14),"controlled capture anchor legal")
			for variant: String in (["original","native"] if detail_review else ["original"]):
				if is_instance_valid(detail): detail.visible=variant=="native"
				var before: Vector2=room.player.position
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				check(room.player.position==before,"capture wait frozen")
				var image:=get_viewport().get_texture().get_image()
				var file: String="L37_painting_"+name+("_"+variant if detail_review else "")+".png"
				check(image.get_size()==Vector2i(2560,1440) and image.save_png(out.path_join(file))==OK,"save 2K "+name)
				report.frames.append({"file":file,"variant":variant,"fixture":"controlled legal player position, frozen combat, shared camera","player":[before.x,before.y]})
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	launch.free(); Game.run=null
	_finish(out)
func _finish(out: String) -> void:
	report["failures"]=failures; report["checks"]=checks
	var file := FileAccess.open(out.path_join("L37_room_painting_report.json" if Art.b07_room_painting_review_enabled() else "L37_room_painting_off_report.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
	print("L37 ROOM PAINTING checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
