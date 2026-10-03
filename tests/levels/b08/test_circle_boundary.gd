extends Node
const Boundary = preload("res://scripts/levels/b08/circle_boundary.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const Geometry = preload("res://scripts/levels/b08/geometry.gd")
const ARENA := Rect2(0,0,1624,1044)
const SOURCE_SIZE := Vector2(1536,1024)
const THIRD_OUTER := [[203,360],[456,360],[457,323],[514,323],[516,234],[1073,234],[1078,360],[1331,360],[1347,644],[951,644],[947,598],[589,598],[586,644],[189,644]]
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B08 circle boundary: "+message)

func _ready() -> void:
	_test_circle()
	_test_invalid()
	_test_segments()
	_test_third_contour()
	print("B08_CIRCLE_BOUNDARY checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)

func _test_circle() -> void:
	var outer := _rectangle(Rect2(-100,-100,200,200))
	check(Boundary.contains(outer,[],Vector2.ZERO,40),"center and complete disk inside outer ring")
	check(not Boundary.contains(outer,[],Vector2(101,0)),"outside center rejected")
	check(Boundary.contains(outer,[],Vector2(100,0)),"zero-radius outer edge is legal")
	check(Boundary.contains(outer,[],Vector2(60,0),40),"outer edge tangency is legal")
	check(Boundary.contains(outer,[],Vector2(60+Boundary.CLEARANCE_EPSILON*0.5,0),40),"outer tangency permits rounding epsilon")
	check(not Boundary.contains(outer,[],Vector2(60+Boundary.CLEARANCE_EPSILON*4,0),40),"outer overlap beyond epsilon rejected")
	var small_hole := _rectangle(Rect2(19,9,2,2))
	check(_nine_samples(outer,[small_hole],Vector2.ZERO,40),"small-hole fixture passes old nine samples")
	check(not Boundary.contains(outer,[small_hole],Vector2.ZERO,40),"disk enclosing an unsampled hole rejected")
	check(not Boundary.contains(outer,[small_hole],Vector2(20,10)),"center inside hole rejected")
	var hole := _rectangle(Rect2(-10,-10,20,20))
	check(Boundary.contains(outer,[hole],Vector2(-30,0),20),"circle tangent to hole is legal")
	check(not Boundary.contains(outer,[hole],Vector2(-29.99,0),20),"circle overlapping hole rejected")
	check(Boundary.contains(outer,[hole],Vector2(-10,0)),"zero-radius hole rim is legal")
	var concave := PackedVector2Array([Vector2(-100,-100),Vector2(100,-100),Vector2(100,20),Vector2(32,13),Vector2(100,60),Vector2(100,100),Vector2(-100,100)])
	check(_nine_samples(concave,[],Vector2.ZERO,40),"concave tip between 45-degree rays passes old nine samples")
	check(not Boundary.contains(concave,[],Vector2.ZERO,40),"whole disk catches concave tip without convexification")
	outer.reverse(); hole.reverse()
	check(Boundary.contains(outer,[hole],Vector2(-30,0),20),"ring winding does not change clearance")
	check(not Boundary.contains(outer,[hole],Vector2.ZERO),"reversed hole is still excluded")

func _test_invalid() -> void:
	var outer := _rectangle(Rect2(0,0,100,100))
	for at: Vector2 in [Vector2(INF,50),Vector2(50,NAN)]:
		check(not Boundary.contains(outer,[],at,1),"non-finite center rejected")
	for radius: float in [-1.0,INF,NAN]:
		check(not Boundary.contains(outer,[],Vector2(50,50),radius),"invalid radius rejected")
	for ring: PackedVector2Array in [PackedVector2Array(),PackedVector2Array([Vector2.ZERO,Vector2.ONE]),PackedVector2Array([Vector2.ZERO,Vector2.ONE,Vector2(2,2)]),PackedVector2Array([Vector2.ZERO,Vector2(INF,0),Vector2(0,100)])]:
		check(not Boundary.contains(ring,[],Vector2(50,50)),"invalid outer ring rejected")
		check(not Boundary.contains(outer,[ring],Vector2(50,50)),"invalid hole ring rejected")
	check(not Boundary.contains(outer,[[]],Vector2(50,50)),"malformed hole type fails closed")
	check(not Boundary.segment_clear(outer,[],Vector2(20,20),Vector2(INF,20),5),"non-finite travel end rejected")
	check(not Boundary.segment_clear(outer,[],Vector2(NAN,20),Vector2(30,20),5),"non-finite travel start rejected")
	check(not Boundary.segment_clear(outer,[],Vector2(20,20),Vector2(30,20),-1),"negative travel radius rejected")

func _test_segments() -> void:
	var outer := _rectangle(Rect2(0,0,100,100))
	var hole := _rectangle(Rect2(49,49,2,2))
	check(Boundary.segment_clear(outer,[],Vector2(20,20),Vector2(80,20),20),"swept circle tangent to outer edge")
	check(Boundary.segment_clear(outer,[hole],Vector2(20,44),Vector2(80,44),5),"swept circle tangent to hole")
	check(not Boundary.segment_clear(outer,[hole],Vector2(20,44.01),Vector2(80,44.01),5),"swept circle hole overlap beyond epsilon")
	check(not Boundary.segment_clear(outer,[hole],Vector2(20,50),Vector2(80,50),5),"legal endpoints cannot jump a small hole")
	check(not Boundary.segment_clear(outer,[hole],Vector2(20,50),Vector2(80,50)),"zero-radius line cannot cross small hole")
	check(Boundary.segment_clear(outer,[hole],Vector2(20,49),Vector2(80,49)),"zero-radius line can follow hole rim")
	check(Boundary.segment_clear(outer,[],Vector2(0,0),Vector2(100,0)),"collinear outer-boundary travel is legal")
	check(Boundary.segment_clear(outer,[hole],Vector2(20,20),Vector2(20,20),5),"stationary legal circle")
	check(not Boundary.segment_clear(outer,[hole],Vector2(50,50),Vector2(50,50)),"stationary hole center rejected")
	var notch := PackedVector2Array([Vector2(0,0),Vector2(50.5,0),Vector2(50.5,51),Vector2(51.5,0),Vector2(100,0),Vector2(100,100),Vector2(0,100)])
	var from := Vector2(48,50)
	var to := Vector2(56,50)
	check(Boundary.contains(notch,[],from,0.1) and Boundary.contains(notch,[],from.lerp(to,0.5),0.1) and Boundary.contains(notch,[],to,0.1),"thin concavity passes 4-unit position samples")
	check(not Boundary.segment_clear(notch,[],from,to,0.1),"continuous clearance catches skipped concavity")
	check(not Boundary.segment_clear(notch,[],from,to),"zero-radius intervals catch skipped concavity")
	check(Boundary.segment_clear(notch,[],Vector2(48,51),Vector2(56,51)),"zero-radius travel tangent to concave vertex")
	check(not Boundary.segment_clear(notch,[],to,from,0.1),"continuous clearance is direction independent")

func _test_third_contour() -> void:
	# Exercise the shared WorldArt mapping without enabling or replacing any
	# runtime art. Preserve cache contents and recency after the isolated fixture.
	var saved_environments: Dictionary = Art._environments.duplicate()
	var saved_recency: Array[String] = Art._environment_recency.duplicate()
	Art._environments["B08:boundary_fixture"] = {"placement_normalized_rect":Rect2(0.11,0.13,0.78,0.74)}
	var outer := PackedVector2Array()
	for point: Array in THIRD_OUTER:
		outer.append(Art.environment_point(ARENA,"B08",Vector2(point[0],point[1])/SOURCE_SIZE,"boundary_fixture"))
	var rejected_painted_hole := PackedVector2Array()
	for point: Vector2 in _rectangle(Rect2(615,407,306,39)):
		rejected_painted_hole.append(Art.environment_point(ARENA,"B08",point/SOURCE_SIZE,"boundary_fixture"))
	Art._environments = saved_environments
	Art._environment_recency = saved_recency
	var restored_hole := _rectangle(Rect2(626.4,382.8,371.2,52.2))
	check(outer[0].distance_to(Vector2(46.141292735,312.582770270))<0.001,"third contour uses unchanged common placement")
	check(Boundary.contains(outer,[restored_hole],Vector2(70,500),18),"painted west extension is legal")
	check(not Boundary.contains(outer,[restored_hole],Vector2(400,722),14),"old south floor outside traced top is rejected")
	check(not Boundary.contains(outer,[restored_hole],Vector2(540,620),40),"known lower concave 40-radius grid corner rejected")
	check(not Boundary.contains(outer,[restored_hole],Vector2(1020,460),40),"known hole-corner 40-radius grid point rejected")
	var from := Vector2(540,340)
	var to := Vector2(1100,340)
	check(is_equal_approx(from.distance_to(to),560),"preserved local bypass is 560 world units")
	check(Boundary.segment_clear(outer,[restored_hole],from,to,40),"entire 560-world radius-40 bypass retains full circular clearance")
	check(Boundary.segment_clear(outer,[restored_hole],to,from,40),"full bypass is traversable both directions")
	check(not Boundary.segment_clear(outer,[rejected_painted_hole],from,to,40),"failed local painting hole cannot preserve radius-40 bypass")
	check(not Boundary.contains(outer,[rejected_painted_hole],Vector2(812,340),40),"failed painting north rim intersects full navigation disk")
	for index in range(15):
		var at := from+Vector2(index*40,0)
		check(Boundary.contains(outer,[restored_hole],at,40),"restored 40-grid bypass footprint "+str(index))
		check(Geometry.lane_at("L43",at).is_empty(),"restored bypass center avoids unchanged wind lane "+str(index))
	check(Boundary.segment_clear(outer,[restored_hole],from,to,42.8),"nominal bypass clearance is 42.8")
	check(not Boundary.segment_clear(outer,[restored_hole],from,to,42.81),"clearance margin is not overstated")
	check(not Boundary.segment_clear(outer,[restored_hole],from,to,45),"restored route is not claimed robust to five-unit erosion")
	for at: Vector2 in [Geometry.point(Geometry.ENTRY.L43),Geometry.point(Geometry.EXIT.L43),Geometry.lanes("L43")[0].vane,Vector2(340.4,481.8)]:
		check(Boundary.contains(outer,[restored_hole],at,18),"unchanged interaction anchor keeps full footprint")

func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func _nine_samples(outer: PackedVector2Array, holes: Array, at: Vector2, radius: float) -> bool:
	for sample in range(9):
		var point := at if sample==8 else at+Vector2.RIGHT.rotated(sample*TAU/8)*radius
		if not Geometry2D.is_point_in_polygon(point,outer): return false
		for hole: PackedVector2Array in holes:
			if Geometry2D.is_point_in_polygon(point,hole): return false
	return true
