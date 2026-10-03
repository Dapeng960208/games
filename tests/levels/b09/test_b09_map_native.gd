extends Node
## Real shared scenery, circle movement, click routes and one-bridge closures.
## Controlled fixtures stay disabled and never clear encounters or issue rewards.
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const RADIUS := 14.0
const VOID_SOURCE_POINTS := {
	"L51": [Vector2(768,150),Vector2(768,440),Vector2(768,770)],
	"L54": [Vector2(581,510),Vector2(966,342),Vector2(750,650)]
}
var checks := 0
var failures := 0
var click_reports: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("B09_MAP_NATIVE: "+label)

func _ready() -> void: _run.call_deferred()

func _points(values: Array) -> PackedVector2Array:
	return Content.polygon(values)

func _walk_segment(room: Node2D, from: Vector2, target: Vector2, label: String, click_path: bool = false) -> void:
	check(room.valid_ground(from,RADIUS) and room.valid_ground(target,RADIUS),label+" legal endpoints")
	var swept: float = room.blocked_fraction(from,target,RADIUS)
	# The real click service additionally accepts exact rounded endpoint contact.
	# Keep its existing circle test, then verify actual movement over every step.
	check(swept>=1.0 or (click_path and room.player.click_navigation._segment_clear(from,target,RADIUS)),label+" swept circle route")
	room.player.position = from
	var legal: bool = room.valid_ground(from,RADIUS)
	for step: int in range(ceili(from.distance_to(target)/8.0)+2):
		var offset: Vector2 = target-room.player.position
		if offset.length()<0.01: break
		room.player.position = room.move_actor(room.player.position,offset.limit_length(8.0),RADIUS)
		legal = legal and room.valid_ground(room.player.position,RADIUS)
	check(legal and room.player.position.distance_to(target)<0.03,
		label+" actual movement reaches target; remaining="+str(room.player.position.distance_to(target)))

func _walk(room: Node2D, points: PackedVector2Array, label: String, click_path: bool = false) -> void:
	check(points.size()>=2,label+" authored route exists")
	for index: int in range(1,points.size()):
		_walk_segment(room,points[index-1],points[index],label+" segment "+str(index),click_path)

func _click_route(room: Node2D, label: String) -> int:
	var navigation: RefCounted = room.player.click_navigation
	room.player.position = room.layout.entry
	if room.layout_id in ["L51","L54"]:
		check(room.blocked_fraction(room.player.position,room.exit_position,RADIUS)<1.0,str(room.layout_id)+" "+label+" cache fixture requires a graph rather than a direct segment")
	var builds_before: int = navigation.graph_builds
	var started := Time.get_ticks_usec()
	var accepted: bool = navigation.request(room.player.position,room.exit_position,RADIUS)
	var elapsed_ms := (Time.get_ticks_usec()-started)/1000.0
	var builds_after: int = navigation.graph_builds
	started = Time.get_ticks_usec()
	var repeat_accepted: bool = navigation.request(room.player.position,room.exit_position,RADIUS)
	var repeat_search_ms := (Time.get_ticks_usec()-started)/1000.0
	check(repeat_accepted and not navigation.path.is_empty(),str(room.layout_id)+" "+label+" repeated real click path exists")
	check(navigation.graph_builds==builds_after,str(room.layout_id)+" "+label+" identical geometry reuses the actual visibility graph")
	click_reports.append({"room":room.layout_id,"state":label,"search_ms":elapsed_ms,"repeat_search_ms":repeat_search_ms,"accepted":accepted,"repeat_accepted":repeat_accepted,"points":navigation.path.size(),"obstructions":room.obstructions.size(),"graph_builds_before":builds_before,"graph_builds":builds_after})
	print("B09_MAP_CLICK ",JSON.stringify(click_reports.back()))
	if elapsed_ms>100.0: push_warning("B09 click search exceeds 100 ms: "+str(room.layout_id)+" "+label+" "+str(elapsed_ms)+" ms")
	check(accepted and not navigation.path.is_empty(),str(room.layout_id)+" "+label+" real click path exists")
	if not accepted or not repeat_accepted: return builds_after
	var route := PackedVector2Array([room.player.position])
	route.append_array(navigation.path)
	_walk(room,route,str(room.layout_id)+" "+label+" real click path",true)
	# Exercise the same motion proposal consumed by HeroActor, then move_actor.
	room.player.position = room.layout.entry
	var searches: int = navigation.route_searches
	var legal := true
	for step: int in range(3000):
		if room.player.position.distance_to(room.exit_position)<=3.1: break
		var direction: Vector2 = navigation.motion(room.player.position,8.0,RADIUS,1.0/60.0)
		if direction.is_zero_approx(): break
		room.player.position = room.move_actor(room.player.position,direction*8.0,RADIUS)
		legal = legal and room.valid_ground(room.player.position,RADIUS)
	check(legal and room.player.position.distance_to(room.exit_position)<=3.1,str(room.layout_id)+" "+label+" click motion reaches exit")
	check(navigation.route_searches==searches,str(room.layout_id)+" "+label+" unchanged path does not search each movement frame")
	check(navigation.graph_builds==builds_after,str(room.layout_id)+" "+label+" movement does not rebuild an unchanged graph")
	navigation.cancel()
	return builds_after

func _environment(room: Node2D, id: String) -> WeakRef:
	var base := "res://assets/levels/b09/rooms/"+id.to_lower()+"/"
	var definition: Dictionary = Art.environment_definition("B09",id)
	check(bool(definition.get("room_specific",false)) and definition.get("manifest_path","")=="asset://world/rooms/"+id+"_environment_v1.json",id+" shared WorldArt loads its own room")
	check(AssetCatalog.resolve(str(definition.get("manifest_path",""))).begins_with(base+"background/") and AssetCatalog.resolve(str(definition.get("path",""))).begins_with(base+"background/"),id+" background files use first-four-level structure")
	var backdrop: Node2D = room.get_node("MineBackdrop")
	check(backdrop.visible and room._depth_canvas.visible and room._terrain_canvas.visible,id+" shared scenery pipeline remains visible")
	var destination: Rect2 = Art.environment_world_rect(room.layout.arena,"B09",id)
	check(backdrop.environment_world_rect.is_equal_approx(destination) and backdrop.painted_bounds().is_equal_approx(destination),id+" camera and background share placement")
	check(room.ground_polygon==Art.environment_ground_polygon(room.layout.arena,"B09",id),id+" physical edge uses background placement")
	var chunks: Node2D = backdrop.environment_chunks
	check(chunks.environment_id==id and chunks.chunks.size()==6 and chunks.world_rect.is_equal_approx(destination),id+" six original painting chunks are installed")
	var covered_area := 0.0
	for sprite: Sprite2D in chunks.chunks:
		covered_area += sprite.region_rect.get_area()*sprite.scale.x*sprite.scale.y
		check(sprite.texture==backdrop.environment_texture and not sprite.region_filter_clip_enabled and sprite.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,id+" source chunk shares mother texture and edge sampling")
	check(is_equal_approx(covered_area,destination.get_area()),id+" original chunks cover the complete placement")
	var original: Texture2D = backdrop.environment_texture
	check(original!=null and original.get_image()!=null and original.get_image().has_mipmaps(),id+" background owns actual mipmaps")
	var detail: Node2D = chunks.native_detail
	check(is_instance_valid(detail),id+" approved native detail is actually loaded; mother painting alone cannot pass")
	if not is_instance_valid(detail): return null
	check(detail.active_room_id==id and detail.tiles.size()==6 and detail.resident_bytes>0,id+" current room owns six resident detailed tiles")
	var manifest_path := "asset://world/rooms_2k/"+id+"/manifest.json"
	check(AssetCatalog.resolve(manifest_path)==base+"detail/manifest.json",id+" detail manifest uses first-four-level structure")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(manifest_path)))
	check(bool(manifest.get("approved",false)) and manifest.get("room_id","")==id and manifest.get("tiles",[]).size()==6,id+" native detail pack was approved")
	var identities: Dictionary = {}
	var detail_paths: Dictionary = {}
	for index: int in detail.tiles.size():
		var sprite: Sprite2D = detail.tiles[index]
		var texture: Texture2D = sprite.texture
		check(texture!=null and texture!=original and texture.get_image()!=null and texture.get_image().has_mipmaps(),id+" detail "+str(index)+" independent native texture with mipmaps")
		if texture!=null: identities[texture.get_instance_id()]=true
		var entry: Dictionary = manifest.tiles[index]
		detail_paths[AssetCatalog.resolve(str(entry.texture))]=true
		var region: Array = entry.source_rect
		var source: Vector2 = Vector2(float(manifest.source_size[0]),float(manifest.source_size[1]))
		var source_rect := Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
		var placed := Rect2(sprite.position,sprite.texture.get_size()*sprite.scale)
		var expected := Rect2(destination.position+source_rect.position/source*destination.size,source_rect.size/source*destination.size)
		check(AssetCatalog.resolve(str(entry.texture)).begins_with(base+"detail/") and placed.is_equal_approx(expected),id+" detail "+str(index)+" uses same painting placement")
	check(identities.size()==6 and detail_paths.size()==6,id+" detailed tiles are six distinct files and textures")
	return weakref(detail)

func _void_edges(room: Node2D) -> void:
	for source: Vector2 in VOID_SOURCE_POINTS.get(room.layout_id,[]):
		var point: Vector2 = Art.environment_point(room.layout.arena,"B09",source/Vector2(1536,1024),room.layout_id)
		check(not room.valid_ground(point,RADIUS),str(room.layout_id)+" painted cloud gap blocks feet "+str(source))
		var nearest: Vector2 = room.layout.entry
		for candidate: Vector2 in _points(Content.room(room.layout_id).main_route):
			if candidate.distance_squared_to(point)<nearest.distance_squared_to(point): nearest=candidate
		check(room.blocked_fraction(nearest,point,RADIUS)<1.0,str(room.layout_id)+" cloud gap blocks swept movement "+str(source))
		var moved: Vector2 = room.move_actor(nearest,point-nearest,RADIUS)
		check(room.valid_ground(moved,RADIUS) and moved.distance_to(point)>RADIUS,str(room.layout_id)+" actual movement stops on legal bank "+str(source))

func _bridges(room: Node2D, definition: Dictionary) -> void:
	var map: Node2D = room.b09_mechanics
	if room.layout_id not in ["L51","L54"]: return
	check(definition.bridges.size()==(2 if room.layout_id=="L51" else 4),str(room.layout_id)+" painted parallel bridge count")
	for authored: Dictionary in definition.bridges:
		var label: String = str(room.layout_id)+" "+str(authored.id)
		var intact_builds: int = room.player.click_navigation.graph_builds
		check(map.request_bridge(str(authored.id)) and not map.request_bridge(),label+" only one active warning")
		var box: Rect2 = map.bridge.rect
		check(map.bridge.state=="warning" and is_equal_approx(float(map.bridge.remaining),2.0) and room.valid_ground(box.get_center(),RADIUS),label+" two-second warning still leaves bridge walkable")
		check(map.bridge.get("polygon",PackedVector2Array()).size()>=4,label+" warning follows painted bridge footprint")
		map.tick(1.99)
		check(map.bridge.state=="warning" and room.valid_ground(box.get_center(),RADIUS),label+" warning does not close early")
		room.player.position=box.get_center()
		room.player.invulnerable=0.0
		Game.run.hp=Game.run.max_hp
		var hp_before: float = Game.run.hp
		map.tick(0.02)
		check(map.bridge.state=="closed" and is_equal_approx(float(map.bridge.remaining),4.0) and not room.valid_ground(box.get_center(),RADIUS),label+" real cross-section closes for four seconds")
		check(room.valid_ground(room.player.position,RADIUS) and not box.grow(RADIUS).has_point(room.player.position),label+" standing player rebounds to legal bank")
		var loss: float = hp_before-Game.run.hp
		check(loss>0.0 and loss<=Game.run.max_hp*0.08+0.01,label+" one rebound damage packet stays within eight percent HP")
		var hp_after: float = Game.run.hp
		var landings: Array = authored.get("safe_landings",[])
		check(landings.size()==2,label+" both authored bridgeheads exist")
		for landing: Array in landings: check(room.valid_ground(Content.point(landing),RADIUS),label+" bridgehead remains legal while closed")
		var alternate: PackedVector2Array = _points(authored.get("alternate_route",[]))
		check(not alternate.is_empty() and alternate[0].distance_to(room.layout.entry)<0.01 and alternate[-1].distance_to(room.exit_position)<0.01,label+" alternate joins actual entrance and exit")
		_walk(room,alternate,label+" single-closure alternate")
		var closed_builds: int = _click_route(room,str(authored.id)+" closed")
		check(closed_builds==intact_builds+1,label+" closed bridge invalidates the complete dynamic obstacle graph once")
		map.tick(3.99)
		check(not map.bridge.is_empty() and map.bridge.state=="closed" and Game.run.hp==hp_after,label+" closure is not early and never deals repeated damage")
		map.tick(0.02)
		check(map.bridge.is_empty() and room.valid_ground(box.get_center(),RADIUS),label+" bridge rebuild restores real ground")
		var restored_builds: int = _click_route(room,str(authored.id)+" restored")
		check(restored_builds==closed_builds+1,label+" restored bridge invalidates the complete dynamic obstacle graph once")

func _run() -> void:
	if not Numbers.b09_candidate_enabled() or not Game.profile_path.begins_with("user://test_b09_candidate/"):
		push_error("B09 native map requires the strict candidate flag and isolated user:// profile")
		get_tree().quit(2)
		return
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"isolated candidate starts")
	var profile_before := JSON.stringify(Game.profile)
	var room: Node2D = load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	room.combat_audio.audible=false
	var route := Traversal.new()
	check(route.configure(room,4,309),"candidate traversal admits only isolated context")
	var previous_detail: WeakRef
	for index: int in Content.room_ids().size():
		var id: String = Content.room_ids()[index]
		var started := Time.get_ticks_usec()
		check(route.start() if index==0 else route._install(index),id+" actual room installation")
		print("B09_MAP_INSTALL ",id," ms=",(Time.get_ticks_usec()-started)/1000.0)
		if previous_detail!=null: check(previous_detail.get_ref()==null,id+" previous room detail owner was released")
		for enemy: Node in room.enemies.get_children(): enemy.free()
		room._boss_actor=null
		room.spawn_enabled=false
		previous_detail=_environment(room,id)
		var definition: Dictionary = Content.room(id)
		var anchors: Array = [definition.entry,definition.exit]
		anchors.append_array(definition.encounter_anchors)
		for lamp: Dictionary in definition.lamps: anchors.append(lamp.position)
		if definition.get("boss_spawn") is Array: anchors.append(definition.boss_spawn)
		for anchor: Array in anchors: check(room.valid_ground(Content.point(anchor),RADIUS),id+" actual player clearance at function anchor "+str(anchor))
		_walk(room,_points(definition.main_route),id+" main route")
		if not definition.get("side_route",[]).is_empty(): _walk(room,_points(definition.side_route),id+" side route")
		_void_edges(room)
		var builds_before: int = room.player.click_navigation.graph_builds
		var builds_after: int = _click_route(room,"intact")
		if id in ["L51","L54"]: check(builds_after==builds_before+1,id+" new non-direct room geometry builds one cold graph")
		_bridges(room,definition)
	check(JSON.stringify(Game.profile)==profile_before,"geometry checks do not mutate formal growth, rewards or inventory")
	check(await room.combat_audio.wait_for_cleanup(),"room combat audio cleanup")
	room.free()
	if previous_detail!=null: check(previous_detail.get_ref()==null,"final room detail owner released with room")
	Game.run=null
	print("B09_MAP_NATIVE checks=",checks," failures=",failures," click_searches=",JSON.stringify(click_reports))
	get_tree().quit(1 if failures else 0)
