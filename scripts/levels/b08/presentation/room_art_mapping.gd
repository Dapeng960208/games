extends RefCounted
## Independent L43 painting, circular ground and anchors share WorldArt's transform.
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const Art=preload("res://scripts/infrastructure/assets/world_art.gd")
const Gate=preload("res://scripts/levels/b08/candidate_gate.gd")
const Floor=preload("res://scripts/levels/b08/painted_floor.gd")
var room_id := ""
var arena := Rect2(0,0,1624,1044)
var definition: Dictionary={}
var errors: Array[String]=[]
var world_rect := Rect2()
var floor: RefCounted

static func requested(id: String) -> bool:
	return id=="L43" and Gate.enabled() and OS.get_cmdline_user_args().has("--b08-independent-room-art")

func configure(id: String, world_arena: Rect2) -> bool:
	errors.clear(); floor=null
	if not requested(id): return false
	room_id=id; arena=world_arena
	definition=Art.environment_definition("B08",room_id)
	if definition.is_empty() or not bool(definition.get("room_specific",false)):
		errors.append("Missing independent room painting"); return false
	var metadata: Dictionary=definition.metadata
	if metadata.get("biome_id")!="B08" or metadata.get("room_id")!=id or metadata.get("boundary_kind")!="concave_outer_with_cloud_hole":
		errors.append("Painting identity or boundary contract differs"); return false
	if definition.placement_normalized_rect!=Rect2(.11,.13,.78,.74):
		errors.append("Shared placement differs"); return false
	var source_size: Array=metadata.get("source_size",[])
	if source_size.size()!=2 or Vector2(source_size[0],source_size[1])!=definition.texture.get_size():
		errors.append("Source dimensions differ"); return false
	if FileAccess.get_sha256(AssetCatalog.resolve(str(definition.path)))!=str(metadata.get("qa",{}).get("sha256","")):
		errors.append("Registered painting hash differs"); return false
	world_rect=Art.environment_world_rect(arena,"B08",id)
	var outer:=Art.environment_ground_polygon(arena,"B08",id)
	var holes: Array=[]
	for values: Array in metadata.get("walkable_normalized_holes",[]):
		var ring:=PackedVector2Array()
		for point: Array in values:
			if point.size()!=2: errors.append("Malformed cloud hole"); return false
			ring.append(point_from_source(Vector2(point[0],point[1])))
		holes.append(ring)
	var original_hole:=Rect2(626.4,382.8,371.2,52.2)
	var expected_hole:=PackedVector2Array([original_hole.position,Vector2(original_hole.end.x,original_hole.position.y),original_hole.end,Vector2(original_hole.position.x,original_hole.end.y)])
	if holes.size()!=1 or holes[0].size()!=4: errors.append("Original cloud hole missing")
	else:
		for index in 4:
			if holes[0][index].distance_to(expected_hole[index])>.001: errors.append("Original cloud hole moved")
	var anchors: Dictionary=metadata.get("anchors_normalized",{})
	var expected: Dictionary={"entry":Geometry.point(Geometry.ENTRY[id]),"exit":Geometry.point(Geometry.EXIT[id]),"vane":Geometry.lanes(id)[0].vane,"flag":Vector2(340.4,481.8),"m01":Geometry.point([1150,930]),"m02":Geometry.point([1550,930]),"m03":Geometry.point([1950,950])}
	for key: String in expected:
		var value: Array=anchors.get(key,[])
		if value.size()!=2 or point_from_source(Vector2(value[0],value[1])).distance_to(expected[key])>.001: errors.append("Anchor differs: "+key)
	if not errors.is_empty(): return false
	var candidate:=Floor.new()
	if not candidate.configure(outer,holes,expected.entry):
		errors.append("Invalid painted floor topology"); return false
	for key: String in expected:
		if not candidate.contains(expected[key],18): errors.append("Unsafe full anchor footprint: "+key)
	if not candidate.segment_clear(Vector2(540,340),Vector2(1100,340),40): errors.append("Original 560 wind bypass is blocked")
	if not errors.is_empty(): return false
	floor=candidate
	return true

func point_from_source(normalized: Vector2) -> Vector2:
	return Art.environment_point(arena,"B08",normalized,room_id)

func source_from_world(point: Vector2) -> Vector2:
	return (point-world_rect.position)/world_rect.size
