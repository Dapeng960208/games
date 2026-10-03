extends Node
## Geometry fixture only: passing does not accept the corresponding artwork.
const Floor=preload("res://scripts/levels/b08/painted_floor.gd")
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const Encounters=preload("res://scripts/levels/b08/encounters.gd")
const Mapping=preload("res://scripts/levels/b08/presentation/room_art_mapping.gd")
const IMPACT="res://docs/levels/b08/rooms/l43_boundary_impact.json"
# Independent golden trace from the approved source-pixel edge inspection.
# Do not derive these expected vertices from the runtime metadata under test.
const REFINED_SOURCE_OUTER=[[203,359.5],[454,359.5],[456.5,322],[510,322],[514.5,232.5],[1074,232.5],[1079.5,359.5],[1332,359.5],[1347.5,643.5],[949,643.5],[947,597.5],[588,597.5],[586,643.5],[187,643.5]]
var checks:=0
var failures:=0

func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 painted floor: "+message)

func _ready() -> void:
	_test_configuration()
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(IMPACT))
	var outer:=PackedVector2Array()
	for point: Array in REFINED_SOURCE_OUTER:
		outer.append((Vector2(point[0],point[1])/Vector2(1536,1024)-Vector2(0.11,0.13))*Vector2(1624,1044)/Vector2(0.78,0.74))
	var floor:=Floor.new()
	check(floor.configure(outer,[_rectangle(Rect2(626.4,382.8,371.2,52.2))],Geometry.point(Geometry.ENTRY.L43)),"pixel-refined third outer plus exact restored hole configures")
	check(floor.outer.size()==14 and floor.holes.size()==1,"authored concavity and single hole retained")
	_test_controller(floor,fixture.restore_original_hole_proposal)
	_test_registered_floor(floor,fixture.restore_original_hole_proposal)
	print("B08_PAINTED_FLOOR checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)

func _test_configuration() -> void:
	var outer:=_rectangle(Rect2(0,0,300,300))
	var hole:=_rectangle(Rect2(140,140,40,40))
	var floor:=Floor.new()
	var openings: Array=[hole]
	check(floor.configure(outer,openings,Vector2(60,60)),"simple floor configures")
	openings.clear(); outer[0]=Vector2(250,250); hole[0]=Vector2(60,60)
	check(floor.outer[0]==Vector2.ZERO and floor.holes.size()==1 and floor.holes[0][0]==Vector2(140,140),"caller mutation cannot alter validated rings")
	outer=_rectangle(Rect2(0,0,300,300)); hole=_rectangle(Rect2(140,140,40,40))
	outer.reverse(); hole.reverse()
	check(floor.configure(outer,[hole],Vector2(60,60)),"reversed ring winding is valid")
	var invalid_rings: Array=[
		PackedVector2Array(),
		PackedVector2Array([Vector2.ZERO,Vector2.ONE,Vector2(2,2)]),
		PackedVector2Array([Vector2.ZERO,Vector2(INF,0),Vector2(0,300)]),
		PackedVector2Array([Vector2.ZERO,Vector2(300,0),Vector2(300,0),Vector2(0,300)]),
		PackedVector2Array([Vector2.ZERO,Vector2(300,0),Vector2(150,0),Vector2(300,300),Vector2(0,300)]),
		PackedVector2Array([Vector2.ZERO,Vector2(300,300),Vector2(0,300),Vector2(250,0)])]
	for ring: PackedVector2Array in invalid_rings:
		check(not floor.configure(ring,[],Vector2(60,60)),"malformed or self-crossing outer rejected")
		check(not floor.configure(outer,[ring],Vector2(60,60)),"malformed or self-crossing hole rejected")
	for holes: Array in [[[]],[_rectangle(Rect2(320,140,40,40))],[_rectangle(Rect2(280,140,40,40))],[_rectangle(Rect2(260,140,40,40))],[hole,_rectangle(Rect2(160,160,40,40))],[hole,_rectangle(Rect2(150,150,10,10))],[hole,_rectangle(Rect2(180,140,40,40))]]:
		check(not floor.configure(outer,holes,Vector2(60,60)),"invalid, outside, touching, overlapping or nested hole rejected")
	check(floor.configure(outer,[hole,_rectangle(Rect2(220,140,20,20))],Vector2(60,60)),"separate interior holes remain supported")
	check(not floor.configure(outer,[hole],Vector2(160,160)) and not floor.contains(Vector2(60,60)),"invalid entry fails closed after successful configuration")
	check(floor.outer.is_empty() and floor.holes.is_empty() and floor.bounds==Rect2(),"failed configure clears stale topology and bounds")

func _test_controller(floor: RefCounted, proposal: Dictionary) -> void:
	# Use production methods and the actual grid without scene startup, actors,
	# profile writes, or enabling candidate art from this geometry fixture.
	var room: Node2D=load("res://scripts/levels/b08/room_controller.gd").new()
	room.layout_id="L43"
	room.painted_mapping=Mapping.new()
	room.painted_mapping.floor=floor
	check(room.painting_ready(),"controller accepts configured painted floor")
	for radius: float in [14.0,18.0,40.0]: _test_motion(room,floor,radius)
	var anchors: Dictionary={"entry":Geometry.point(Geometry.ENTRY.L43),"exit":Geometry.point(Geometry.EXIT.L43),"vane":Geometry.lanes("L43")[0].vane,"flag":Geometry.point(Geometry.ENTRY.L43)+Vector2(120,-75)}
	for spawn: Dictionary in Encounters.waves("L43",0)[0]: anchors[spawn.id.to_lower().replace("b08-","")]=Geometry.point(spawn.at)
	check(anchors.size()==7,"all seven authored anchors are checked")
	for key: String in anchors:
		var expected: Array=proposal.anchors[key].world_xy
		check(anchors[key].distance_to(Vector2(expected[0],expected[1]))<0.001,"fixed anchor unchanged: "+key)
		for radius: float in [14.0,18.0,40.0]:
			check(room.valid_ground(anchors[key],radius) and room.clamp_actor(anchors[key],radius)==anchors[key],"complete anchor footprint and clamp unchanged: "+key+" r"+str(radius))
	var lane: Dictionary=Geometry.lanes("L43")[0]
	check(lane.rect==Rect2(510.4,188.5,667,127.6) and lane.direction==Vector2.RIGHT,"wind rectangle and authored direction unchanged")
	check(room.lane_at(Vector2(812,310)).id==lane.id and room.lane_at(Vector2(812,340)).is_empty(),"wind still triggers on actor center, without radius expansion")
	_test_grid(room,floor,anchors)
	room.free()

func _test_registered_floor(fixture: RefCounted, proposal: Dictionary) -> void:
	# Also load the registered JSON/texture through production AssetCatalog and
	# WorldArt mapping. Requires the isolated independent-room-art launch flags.
	var room: Node2D=load("res://scripts/levels/b08/room_controller.gd").new()
	check(Mapping.requested("L43"),"test launched with isolated L43 independent-art gate")
	check(room.load_room_layout("L43") and room.painting_ready(),"actual controller loads registered painted floor")
	if not room.painting_ready(): room.free(); return
	var floor: RefCounted=room.painted_mapping.floor
	var matches: bool=floor.outer.size()==fixture.outer.size() and floor.holes.size()==1 and floor.holes[0].size()==4
	if matches:
		for index in floor.outer.size(): matches=matches and floor.outer[index].distance_to(fixture.outer[index])<0.001
		for index in 4: matches=matches and floor.holes[0][index].distance_to(fixture.holes[0][index])<0.001
	check(matches,"registered source geometry matches independent pixel-refined contour and exact restored hole")
	check(room.layout.entry==Geometry.point(Geometry.ENTRY.L43) and room.exit_position==Geometry.point(Geometry.EXIT.L43),"real room entry and exit remain fixed")
	var anchors: Dictionary={}
	for key: String in proposal.anchors:
		var expected: Array=proposal.anchors[key].world_xy
		anchors[key]=Vector2(expected[0],expected[1])
		check(room.valid_ground(anchors[key],40),"registered full anchor footprint: "+key)
	_test_grid(room,floor,anchors)
	check(room.blocked_fraction(Vector2(812,340),Vector2(812,500),18)<0.16,"registered room stops line through restored hole")
	check(room.load_room_layout("L44") and not room.painting_ready(),"leaving L43 clears painted floor")
	room.free()

func _test_motion(room: Node2D, floor: RefCounted, radius: float) -> void:
	var from:=Vector2(812,340)
	var to:=Vector2(812,500)
	var contact:=382.8-radius
	var fraction: float=room.blocked_fraction(from,to,radius)
	check(absf(fraction-(contact-from.y)/(to.y-from.y))<0.0001,"first hole contact fraction r"+str(radius))
	check(floor.segment_clear(from,from.lerp(to,fraction),radius) and not floor.segment_clear(from,to,radius),"whole blocked prefix is legal, crossing hole is not r"+str(radius))
	var moved: Vector2=room.move_actor(from,to-from,radius)
	check(room.valid_ground(moved,radius) and moved.y<=contact+0.002 and moved.y>=contact-6.01,"movement stops before hole without tunneling r"+str(radius))
	var clamped: Vector2=room.clamp_actor(Vector2(812,409),radius)
	check(room.valid_ground(clamped,radius) and absf(clamped.distance_to(Vector2(812,409))-(26+radius))<0.02,"hole clamp uses nearest full-circle-safe rim r"+str(radius))
	from=Vector2(812,580); to=Vector2(812,700); contact=639.797191723-radius
	fraction=room.blocked_fraction(from,to,radius)
	check(absf(fraction-(contact-from.y)/(to.y-from.y))<0.0001,"first concave outer contact fraction r"+str(radius))
	moved=room.move_actor(from,to-from,radius)
	check(room.valid_ground(moved,radius) and moved.y<=contact+0.002 and moved.y>=contact-6.01,"movement stays above concave notch r"+str(radius))
	clamped=room.clamp_actor(Vector2(812,680),radius)
	check(room.valid_ground(clamped,radius) and absf(clamped.y-contact)<0.02 and absf(clamped.x-812)<0.001,"outer-notch clamp preserves authored concavity r"+str(radius))
	from=Vector2(400,660); to=Vector2(1200,660)
	fraction=room.blocked_fraction(from,to,radius)
	check(room.valid_ground(from,radius) and room.valid_ground(to,radius) and fraction>0 and fraction<0.5,"legal endpoints cannot hide concave excursion r"+str(radius))
	check(floor.segment_clear(from,from.lerp(to,fraction),radius) and not floor.segment_clear(from,from.lerp(to,fraction)+Vector2(1,0),radius),"blocked fraction finds first concave edge before re-entry r"+str(radius))
	check(room.blocked_fraction(Vector2(812,409),to,radius)==0 and room.move_actor(Vector2(812,409),Vector2(10,0),radius)==Vector2(812,409),"invalid hole start cannot move r"+str(radius))

func _test_grid(room: Node2D, floor: RefCounted, anchors: Dictionary) -> void:
	room._build_navigation()
	var grid: AStarGrid2D=room._grid
	check(grid.region==Rect2i(0,0,42,28) and grid.cell_size==Vector2(40,40) and grid.offset==Vector2(20,20) and grid.diagonal_mode==AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,"actual 42x28 grid keeps 40 cells, 20 offset and no corner cutting")
	var start:=_cell(anchors.entry)
	var free:=0
	var unreachable:=0
	for x in 42:
		for y in 28:
			var cell:=Vector2i(x,y)
			if grid.is_point_solid(cell): continue
			free+=1
			if grid.get_id_path(start,cell).is_empty(): unreachable+=1
	check(free==324 and unreachable==0,"all 324 full-circle grid cells form one entry-connected component")
	check(grid.is_point_solid(Vector2i(13,15)) and grid.is_point_solid(Vector2i(25,11)),"concave-tip and hole-corner false sample passes are blocked")
	for key: String in anchors:
		var path:=grid.get_point_path(start,_cell(anchors[key]))
		var clear: bool=not path.is_empty()
		for index in range(1,path.size()): clear=clear and floor.segment_clear(path[index-1],path[index],40)
		check(clear,"actual navigation path has continuous radius-40 clearance: "+key)
		if key!="entry": check(not room.navigation_direction(anchors.entry,anchors[key],18).is_zero_approx(),"controller navigates to unchanged anchor: "+key)
	var bypass:=grid.get_point_path(Vector2i(13,8),Vector2i(27,8))
	var length:=0.0
	var clear: bool=bypass.size()==15
	for index in bypass.size():
		clear=clear and room.lane_at(bypass[index]).is_empty() and is_equal_approx(bypass[index].y,340)
		if index>0:
			length+=bypass[index-1].distance_to(bypass[index])
			clear=clear and floor.segment_clear(bypass[index-1],bypass[index],40)
	check(clear and is_equal_approx(length,560),"actual grid retains straight 560-world center-wind-free bypass")
	for radius: float in [14.0,18.0,40.0]:
		check(room.blocked_fraction(Vector2(540,340),Vector2(1100,340),radius)==1 and room.move_actor(Vector2(540,340),Vector2(560,0),radius).distance_to(Vector2(1100,340))<0.01,"bypass works through controller movement r"+str(radius))
	check(room.navigation_direction(Vector2(540,340),Vector2(1100,340),40).is_equal_approx(Vector2.RIGHT),"controller follows direct bypass")
	check(floor.segment_clear(Vector2(540,340),Vector2(1100,340),42.8) and not floor.segment_clear(Vector2(540,340),Vector2(1100,340),45),"nominal clearance does not claim five-unit erosion tolerance")

func _cell(point: Vector2) -> Vector2i:
	return Vector2i((point-Vector2(20,20))/40)

func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
