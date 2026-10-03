extends SceneTree
const Layout = preload("res://scripts/levels/b05/world/room_geometry.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var data: Dictionary = Layout.room("L25")
	check(not data.is_empty() and data.geometry_status == "candidate_first_room_terraces_v2", "L25 terrace placement exists")
	check(Layout.room("L24").is_empty() and Layout.room("L31").is_empty(), "only B05 geometry exposed")
	check(Layout.world_point(data.central_dry_ground).is_equal_approx(Vector2(779.52,522)), "central source anchor mapping")
	check(Layout.world_point(data.root_wells[0].position).is_equal_approx(Vector2(1104.32,313.2)), "68/30 root anchor mapping")
	check(Layout.image_point([2800,1800],Vector2i(2800,1800)).is_equal_approx(Vector2(2492,1566)), "placement rect reserves peripheral art")
	check(Layout.image_point([0,0],Vector2i(1000,1000)).is_equal_approx(Vector2(110,130)), "art origin matches production placement")
	check(Layout.image_point([1400,900],Vector2i(2560,1440)) == Vector2(1280,720), "explicit mapping avoids crop")
	check(Layout.route_is_clear("L25","main_route",180), "180-world-pixel full main corridor clear")
	check(Layout.route_is_clear("L25","safe_route",140), "140-world-pixel full safe corridor clear")
	for key in ["root_approach_route","reward_approach_route","beacon_approach_route"]:
		check(Layout.route_is_clear("L25",key,140), key + " swept path reachable")
	check(not Layout.route_is_clear("L25","main_route",500), "oversize corridor correctly rejected")
	check(Layout.hazards_allowed("L25",[]), "empty hazard budget")
	check(not Layout.hazards_allowed("L25",[Layout.polygon("L25")]), "whole floor hazard rejected")
	var north := PackedVector2Array([Vector2(1180,240),Vector2(1280,240),Vector2(1280,340),Vector2(1180,340)])
	check(Layout.hazards_allowed("L25",[north]), "bounded northern danger allowed")
	var crossing := PackedVector2Array([Vector2(400,460),Vector2(600,460),Vector2(600,540),Vector2(400,540)])
	check(not Layout.hazards_allowed("L25",[crossing]), "hazard cannot cut safe route")
	var upper := PackedVector2Array([Vector2(0,0),Vector2(1624,0),Vector2(1624,440),Vector2(0,440)])
	var lower := PackedVector2Array([Vector2(0,604),Vector2(1624,604),Vector2(1624,1044),Vector2(0,1044)])
	check(not Layout.hazards_allowed("L25",[upper,lower]), "30 percent total hazard ceiling outside safe corridor")
	check(not Layout.hazards_allowed("L25",[PackedVector2Array([Vector2(NAN,0),Vector2.ONE,Vector2.RIGHT])]), "invalid hazard rejected")
	data.entry[0] = 999
	check(Layout.room("L25").entry[0] == 320, "layout copy cannot mutate source")
	for room_id: String in ["L26","L27","L28","L29","L30","BO05"]:
		check(not Layout.room(room_id).is_empty(),room_id+" explicit geometry present")
		check(Layout.route_is_clear(room_id,"main_route",180.0),room_id+" full-width main route")
		check(Layout.route_is_clear(room_id,"safe_route",140.0),room_id+" full-width safe route")
	print("B05 room geometry: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
