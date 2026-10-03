extends RefCounted
## One painted coordinate contract; B08's concave union remains authoritative.
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const Art=preload("res://scripts/infrastructure/assets/world_art.gd")
const Gate=preload("res://scripts/levels/b08/candidate_gate.gd")
var room_id := ""
var arena := Rect2(0,0,1624,1044)
var definition: Dictionary={}
var errors: Array[String]=[]
var world_rect := Rect2()

static func requested(id: String) -> bool:
	return id=="L43" and Gate.enabled() and OS.get_cmdline_user_args().has("--b08-independent-room-art")

func configure(id: String, world_arena: Rect2) -> bool:
	if not requested(id): return false
	room_id=id; arena=world_arena
	definition=Art.environment_definition("B08",room_id)
	if definition.is_empty() or not bool(definition.get("room_specific",false)):
		errors.append("Missing independent room painting"); return false
	var metadata: Dictionary=definition.metadata
	if metadata.get("biome_id")!="B08" or metadata.get("room_id")!=id or metadata.get("boundary_kind")!="fixed_rectangle_union":
		errors.append("Painting identity or boundary contract differs"); return false
	world_rect=Art.environment_world_rect(arena,"B08",id)
	var registered: Array[Rect2]=[]
	for values: Array in metadata.get("walkable_normalized_regions",[]):
		if values.size()!=4: errors.append("Malformed floor region"); continue
		var top_left:=point_from_source(Vector2(values[0],values[1]))
		var bottom_right:=point_from_source(Vector2(values[0]+values[2],values[1]+values[3]))
		registered.append(Rect2(top_left,bottom_right-top_left))
	var actual:=Geometry.floors(id)
	if registered.size()!=actual.size(): errors.append("Floor region count differs")
	else:
		for index in actual.size():
			if not registered[index].is_equal_approx(actual[index]): errors.append("Floor boundary differs: "+str(index))
	var anchors: Dictionary=metadata.get("anchors_normalized",{})
	var expected: Dictionary={"entry":Geometry.point(Geometry.ENTRY[id]),"exit":Geometry.point(Geometry.EXIT[id]),"vane":Geometry.lanes(id)[0].vane,"flag":Vector2(340.4,481.8)}
	for key: String in expected:
		var value: Array=anchors.get(key,[])
		if value.size()!=2 or not point_from_source(Vector2(value[0],value[1])).is_equal_approx(expected[key]): errors.append("Anchor differs: "+key)
	return errors.is_empty()

func point_from_source(normalized: Vector2) -> Vector2:
	return Art.environment_point(arena,"B08",normalized,room_id)

func source_from_world(point: Vector2) -> Vector2:
	return (point-world_rect.position)/world_rect.size
