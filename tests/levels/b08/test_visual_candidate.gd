extends Node
const Gate=preload("res://scripts/levels/b08/candidate_gate.gd")
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const Flow=preload("res://scripts/levels/b08/presentation/wind_lane.gd")
var checks:=0
var failures:=0
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 visual candidate: "+label)
func _ready() -> void: run.call_deferred()
func run() -> void:
	if not Gate.enabled() or not OS.get_cmdline_user_args().has("--b08-art-l43"): get_tree().quit(2); return
	var room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	check(is_instance_valid(room.sky_environment),"explicit L43 environment registered")
	if not is_instance_valid(room.sky_environment): get_tree().quit(1); return
	var environment: Node2D=room.sky_environment
	check(environment.textures.size()==8 and environment.layers.size()==6,"eight originals and six clipped exterior layers")
	check(environment.errors.is_empty() and environment.boundary_segments.size()==42,"exact floor boundary and exterior/edge clipping")

	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	var original_zoom := maxf(.85,maxf(viewport_size.x/1624,viewport_size.y/1044))
	check(not environment.background_depth_review and room.camera.zoom.is_equal_approx(Vector2.ONE*original_zoom),"ordinary art candidate retains shared player-camera fitting and original background")
	var depth=preload("res://scripts/levels/b08/presentation/l43_environment.gd").new()
	add_child(depth)
	check(depth.configure("L43",true) and depth.background_depth_review and depth.DISTANT_STRENGTH==.45,"separate distant-depth review is explicitly enabled")
	check(depth.layers==environment.layers and depth.edge_faces==environment.edge_faces and depth.background_rect==environment.background_rect and depth.snapshot==environment.snapshot,"depth review changes no foreground registration, native source, edge, or background rectangle")
	depth.free()
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("asset://b08/rooms/l43/manifest.json")))
	for source: Dictionary in manifest.assets:
		check(FileAccess.get_sha256(AssetCatalog.resolve(source.logical_id))==source.sha256,"native bytes preserved: "+str(source.file))
	var native_actor: Node2D
	for actor: Node2D in room.enemies.get_children():
		if actor.enemy_id=="B08-M01": native_actor=actor
	check(native_actor!=null and native_actor.native_art!=null,"only M01 idle native candidate registered")
	check(native_actor.native_art.world_height==100 and native_actor.navigation_radius==18,"presentation height leaves physical radius unchanged")
	var right: Rect2=native_actor.native_art.bounds()
	var left: Rect2=native_actor.native_art.bounds(true)
	check(left.size==right.size and left.size.x>0 and is_zero_approx(left.position.x+right.position.x+right.size.x),"mirror reflects about true actor foot without negative rectangle extent")
	check(native_actor.native_art.foot==Vector2(637,1127) and native_actor.native_art.body_height==937,"fixed native sole midpoint/anatomical scale")
	check(FileAccess.get_sha256(AssetCatalog.resolve("asset://b08/enemies/m01/idle.png"))==native_actor.native_art.metadata.sha256,"native actor byte hash unchanged")
	check(Geometry.lanes("L43")[0].vane==Geometry.point([840,900]) and not room.valid_ground(Geometry.point([1400,700]),10),"vane and cloud gap unchanged")
	var lane: Dictionary=Geometry.lanes("L43")[0]
	var regular: Array=Flow.marks(lane.rect,Vector2.RIGHT,0,false)
	var later: Array=Flow.marks(lane.rect,Vector2.RIGHT,.5,false)
	var reduced: Array=Flow.marks(lane.rect,Vector2.RIGHT,0,true)
	check(not regular.is_empty() and regular!=later,"normal flow visibly moves")
	check(reduced==Flow.marks(lane.rect,Vector2.RIGHT,5,true) and not reduced.is_empty(),"reduced FX preserves static directional marks")
	var bounded:=true
	var forward:=true
	for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN]:
		for mark: PackedVector2Array in Flow.marks(lane.rect,direction,.3,false):
			for point: Vector2 in mark:
				if not lane.rect.has_point(point): bounded=false
			if Vector2(mark[2]-mark[0]).dot(direction)<=0: forward=false
	check(bounded and forward,"all lane modes clip marks and retain actual direction")
	var original: Dictionary=room.wind.lanes.duplicate(true)
	Flow.marks(lane.rect,Vector2.RIGHT,1,false)
	check(room.wind.lanes==original and room.wind.channel.is_empty(),"drawing does not mutate mechanic state")
	check(Flow.warning_marks(lane,room.wind).is_empty(),"no future-direction warning in steady state")
	check(room.wind.begin_turn(lane.id,"player"),"same real interaction path")
	room.wind.advance(.6)
	check(not room.wind.pending.is_empty() and room.wind.pending.remaining==1.0,"full switch warning remains")
	var pending_before: Dictionary=room.wind.pending.duplicate(true)
	var warning_marks: Array=Flow.warning_marks(lane,room.wind)
	var warnings_bounded := warning_marks.size()==3
	for mark: PackedVector2Array in warning_marks:
		for point: Vector2 in mark:
			if not lane.rect.grow(-4).has_point(point): warnings_bounded=false
		if Vector2(mark[2]-mark[0]).dot(-lane.direction)<=0: warnings_bounded=false
	check(warnings_bounded and room.wind.pending==pending_before,"future warning uses next direction, remains inside lane and never advances state")
	room.wind.advance(.999)
	check(room.wind.direction(lane.id,lane.direction)==lane.direction and not Flow.warning_marks(lane,room.wind).is_empty(),"warning keeps original live direction until full second completes")
	room.wind.advance(.001)
	check(room.wind.direction(lane.id,lane.direction)==-lane.direction and Flow.warning_marks(lane,room.wind).is_empty(),"direction changes only on real transition and warning clears")
	room._open_room("L44")
	check(not is_instance_valid(room.sky_environment),"other room releases L43 environment")
	var others_native:=false
	for actor: Node2D in room.enemies.get_children():
		if actor.native_art!=null: others_native=true
	check(not others_native,"no art identity substitution in L44")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no reward/progression writes")
	check(await room.cleanup_for_exit(),"bounded production audio cleanup")
	room.free()
	await get_tree().process_frame
	print("B08_VISUAL_CANDIDATE checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
