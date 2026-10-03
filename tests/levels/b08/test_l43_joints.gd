extends Node
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
var checks:=0
var failures:=0
func check(value: bool, text: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 edge joints: "+text)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	var environment=room.sky_environment
	check(environment!=null and environment.edge_joint_review,"explicit review gate enables two samples")
	if environment==null: room.free(); get_tree().quit(1); return
	check(environment.textures.size()==12 and environment.layers.size()==11 and environment.errors.is_empty(),"two native sources supplement unchanged environment")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("asset://b08/rooms/l43/edge_joints/manifest.json")))
	var joints: Array=[]
	var arch_index: int=-1
	for i: int in environment.layers.size():
		var layer: Dictionary=environment.layers[i]
		if layer.file=="bridge_arch.png": arch_index=i
		if bool(layer.get("edge_joint",false)): joints.append({"index":i,"layer":layer})
	check(joints.size()==2,"exactly two exterior samples")
	for entry: Dictionary in joints:
		var layer: Dictionary=entry.layer
		check(int(entry.index)<arch_index,"original arch remains in front of support")
		var valid: bool=not layer.shapes.is_empty()
		for shape: PackedVector2Array in layer.shapes:
			for point: Vector2 in shape:
				if point.y<1280*.58-.001: valid=false
			for floor_rect: Rect2 in Geometry.floors("L43"):
				if not Geometry2D.intersect_polygons(shape,environment.polygon(floor_rect)).is_empty(): valid=false
		check(valid,"every visible joint polygon lies below south baseline and outside full floor union")
	for item: Dictionary in data.attachments:
		check(FileAccess.get_sha256(AssetCatalog.resolve("asset://b08/rooms/l43/edge_joints/"+str(item.file)))==item.source_sha256,"native bytes "+str(item.file))
		check(item.blueprint_anchor[1]==1280,"convex corners only, no false concave y1150 return")
	check(not room.valid_ground(Geometry.point([1400,700]),10) and Geometry.floors("L43").size()==6,"original central cloud gap and six-floor topology")
	check(room.exit_position==Geometry.point([2410,960]) and room.sky_interactions.vane_body.position==Geometry.point([840,900]),"exit and vane retain true coordinates")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no progression writes")
	var before: WeakRef=weakref(environment)
	room._open_room("L44")
	check(before.get_ref()==null and room.sky_environment==null,"leaving room releases optional sources")
	check(await room.cleanup_for_exit(),"bounded audio cleanup")
	room.free()
	await get_tree().process_frame
	print("B08_L43_JOINTS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
