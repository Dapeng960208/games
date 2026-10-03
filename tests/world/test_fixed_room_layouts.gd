extends SceneTree
## One focused check of the approved scene coordinates and actual path geometry.
const Fixed = preload("res://scripts/domain/world/fixed_room_layouts.gd")
const Generator = preload("res://scripts/gameplay/world/room_generator.gd")
const Boss = preload("res://scripts/domain/world/boss_layouts.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
const Boundary = preload("res://scripts/gameplay/world/room_boundary.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func geometry(layout: Dictionary) -> Dictionary:
	var result: Dictionary = layout.duplicate(true)
	for key: String in ["seed", "counterplay_order", "reinforcement_spawns"]: result.erase(key)
	return result

func run_checks() -> void:
	concave_boundary_checks()
	check(Fixed.room_ids().size()==28, "24 combat rooms and four boss arenas have fixed blueprints")
	for id: String in Fixed.room_ids():
		var layout: Dictionary = Boss.build(id, 371) if id.begins_with("BO") else Generator.generate(id, 371)
		var other: Dictionary = Boss.build(id, 986353) if id.begins_with("BO") else Generator.generate(id, 986353)
		check(not layout.is_empty() and bool(layout.get("fixed_layout", false)), id+" uses the fixed layout API")
		if layout.is_empty(): continue
		check(geometry(layout)==geometry(other), id+" scenery, goals, beacons and spawn anchors are unchanged across run seeds")
		var report: Dictionary = Layouts.validate_layout(layout, 30.0)
		check(bool(report.valid), id+" has reachable entry, exit, objectives, encounter spawn anchors and routes: "+str(report.errors))
		check(layout.obstructions.size()<=4 and layout.static_obstructions.is_empty(), id+" has at most four small covers and continuous floor")
		var small_cover := true
		for obstacle: Rect2 in layout.obstructions:
			if obstacle.size.x>120 or obstacle.size.y>75: small_cover = false
		check(small_cover, id+" collision is limited to the visible contact foot")
		check(layout.buff_anchors.size()==3, id+" has exactly three authored beacons")
		for at: Vector2 in layout.buff_anchors:
			check(Layouts.clear_for_actor(layout, at, 35), id+" beacon is on usable ground")
		var non_solid := true
		for decoration: Dictionary in layout.decoration_instances:
			if decoration.collision_rect.has_area() or not "non_solid" in decoration.tags: non_solid = false
		check(non_solid, id+" decorative scenery remains walkable")
		if id.begins_with("BO"):
			var counts := {"BO01":3, "BO02":4, "BO03":4, "BO04":4}
			check(layout.boss_counterplay.size()==int(counts[id]), id+" preserves existing boss counterplay IDs and count")
			check(Boss.validate(layout).is_empty(), id+" boss layout remains compatible")
	await actual_room_checks()
	print("Fixed room layouts: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func concave_boundary_checks() -> void:
	var terrace := PackedVector2Array([Vector2(0,0),Vector2(100,0),Vector2(100,40),Vector2(200,40),Vector2(200,0),Vector2(300,0),Vector2(300,100),Vector2(200,100),Vector2(200,60),Vector2(100,60),Vector2(100,100),Vector2(0,100)])
	check(Boundary.contains(terrace,Vector2(50,50),15),"concave platform contains an actor beyond bridge half-planes")
	check(Boundary.contains(terrace,Vector2(250,50),15),"both concave platforms remain usable")
	check(Boundary.contains(terrace,Vector2(150,50),9) and not Boundary.contains(terrace,Vector2(150,50),11),"bridge tests the complete actor footprint")
	check(not Boundary.contains(terrace,Vector2(150,20),0),"terrace notch is outside ground")
	check(Boundary.clamp_point(terrace,Vector2(50,50),15) == Vector2(50,50),"legal entry is never projected to the bridge")
	check(Boundary.contains(terrace,Boundary.clamp_point(terrace,Vector2(150,20),9),9),"notch projection reaches legal inset")
	check(is_equal_approx(Boundary.clear_fraction(terrace,Vector2(50,50),Vector2(250,50),9),1),"main bridge corridor has full line of sight")
	check(is_equal_approx(Boundary.clear_fraction(terrace,Vector2(50,20),Vector2(250,20),0),.25),"sweep cannot cross a notch and reenter the other platform")
	check(is_equal_approx(Boundary.clear_fraction(terrace,Vector2(50,20),Vector2(250,20),5),.225),"swept radius stops before the notch edge")
	check(is_equal_approx(Boundary.clear_fraction(terrace,Vector2(100,20),Vector2(50,20),0),1),"inward movement from an edge remains clear")

func actual_room_checks() -> void:
	var game: Node = root.get_node("Game")
	if not str(game.get("profile_path")).contains("test_fixed_room_layouts"):
		check(false, "Actual room check requires an isolated profile")
		return
	check(bool(game.call("new_profile")) and bool(game.call("start_run")), "Isolated run starts for actual room preparation")
	var scene: PackedScene = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn"))
	var room: Node2D = scene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	for index: int in 24:
		var id := "L%02d" % (index+1)
		var blueprint: Dictionary = Fixed.blueprint(id)
		var prepared: Dictionary = room.call("prepare_expedition_node", {"room_id":id, "role":"branch", "biome_id":str(blueprint.biome_id),
			"node_index":1, "node_count":6, "difficulty":0, "seed":146556, "phase":"combat", "expedition":true})
		check(bool(prepared.get("valid", false)), id+" actual room prepares: "+str(prepared.get("error", "")))
		if not bool(prepared.get("valid", false)): continue
		room.call("apply_prepared_expedition_node", prepared)
		room.set("spawn_enabled", false)
		var layout: Dictionary = room.get("layout")
		var outline: PackedVector2Array = room.get("ground_polygon")
		check(outline.size()>=3 and room.get("ARENA")==Boundary.bounds(outline), id+" installed navigation bounds follow the painted ground outline")
		var props: Node2D = room.get("enemy_props")
		var installed: Array = props.get("props")
		var beacon_positions: Array[Vector2] = []
		for beacon: Dictionary in installed: beacon_positions.append(beacon.position)
		check(beacon_positions==layout.buff_anchors, id+" actual beacons use the authored positions")
		var objectives: Node2D = room.get("objectives")
		var actual_points: Array[Vector2] = []
		for target: Dictionary in objectives.get("elements").values():
			if bool(target.get("required", true)): actual_points.append(target.position)
		check(int(objectives.get("required_count"))==int(layout.fixed_objective_count) and actual_points==layout.objective_points, id+" actual mission targets match the approved drawing")
		var reachable := true
		for point: Vector2 in [layout.exit]+layout.objective_points+layout.buff_anchors+layout.spawn_points:
			var direction: Vector2 = room.call("navigation_direction", layout.entry, point, 30.0)
			if not bool(room.call("valid_ground", point, 30.0)) or direction.is_zero_approx(): reachable = false
		check(reachable, id+" installed collision/navigation reaches the exit, goals, beacons and enemy spawn anchors")
		if index%6==0 and outline.size()>=3:
			check_edge_sliding(room, outline, id)
	room.free()
	await process_frame
	await process_frame

func check_edge_sliding(room: Node2D, outline: PackedVector2Array, id: String) -> void:
	# Four samples per theme exercise the real clamp and movement along the
	# painted rim, rather than duplicating the boundary algorithm in the test.
	for side: int in 4:
		var edge_index: int = int(float(side)*float(outline.size())/4.0)
		var a: Vector2 = outline[edge_index]
		var b: Vector2 = outline[(edge_index+1)%outline.size()]
		var tangent: Vector2 = a.direction_to(b)
		var inward := Vector2(-tangent.y, tangent.x)
		var start: Vector2 = room.call("clamp_actor", a.lerp(b, .5)-inward*140.0, 18.0)
		var slid: Vector2 = room.call("move_actor", start, tangent*48.0-inward*32.0, 18.0)
		check(Boundary.contains(outline, start, 18.0) and Boundary.contains(outline, slid, 18.0) and (slid-start).dot(tangent)>24.0,
			id+" outward movement clamps safely and preserves sliding along painted edge "+str(side))
