extends Node
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const Art=preload("res://scripts/levels/b08/presentation/enemy_art.gd")
const Capture=preload("res://tests/levels/b08/test_l43_capture.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 L43 integration: "+label)
func _ready() -> void: run.call_deferred()
func run() -> void:
	if not OS.get_cmdline_user_args().has("--b08-art-convergence"): get_tree().quit(2); return
	var packed=load("res://scenes/gameplay/world/b08_candidate.tscn")
	if packed==null: get_tree().quit(3); return
	var room=packed.instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	check(Game.profile_path.begins_with("user://test_b08_candidate/"),"isolated profile path")
	check(room.sky_environment!=null and room.sky_environment.convergence,"explicit converged environment loaded")
	if room.sky_environment==null: room.free(); get_tree().quit(1); return
	var environment=room.sky_environment
	check(environment.textures.size()==10 and environment.layers.size()==9,"eight preserved plus two native sources and three south fascia registrations")
	check(environment.errors.is_empty() and environment.boundary_segments.size()==42,"exact legal-ground clipping retained")
	check(environment.material_tile_width==256 and Geometry.floors("L43").size()==6,"material density does not replace topology")
	check(not room.valid_ground(Geometry.point([1400,700]),10),"central cloud gap remains void")
	check(room.exit_position==Geometry.point([2410,960]) and Geometry.lanes("L43")[0].vane==Geometry.point([840,900]),"exit and vane stay fixed")
	var actors: Dictionary={}
	for actor: Node2D in room.enemies.get_children():
		if actor.enemy_id in ["B08-M01","B08-M02","B08-M03"]: actors[actor.enemy_id]=actor
	check(actors.size()==3,"actual first encounter identities")
	check(room.valid_ground(Geometry.point(Capture.STAGED_PLAYER),Balance.PLAYER_RADIUS),"capture player keeps full legal footprint")
	for id: String in Capture.STAGED_ACTORS:
		check(room.valid_ground(Geometry.point(Capture.STAGED_ACTORS[id]),actors[id].navigation_radius),"capture actor keeps full legal footprint "+id)
	var unique_hashes: Dictionary={}
	for id: String in actors:
		var actor: Node2D=actors[id]
		var art=actor.native_art
		check(art!=null and art.convergence and art.frames.size()==4,id+" native pose source loaded")
		if art==null: continue
		check(actor.navigation_radius==18 and art.world_height==(112 if id=="B08-M02" else 100),id+" visual adult scale leaves navigation radius unchanged")
		for pose: String in ["idle","warning","release","recovery"]:
			art.set_pose(pose)
			var frame: Dictionary=art.frames[pose]
			var key: String="asset://b08/enemies/"+id.trim_prefix("B08-").to_lower()+"/"+str(frame.file)
			unique_hashes[key]=frame.source_sha256
			var right: Rect2=art.bounds()
			var left: Rect2=art.bounds(true)
			check(right.size.x>0 and right.size==left.size and is_zero_approx(left.position.x+right.position.x+right.size.x),id+"/"+pose+" reflects around registered foot")
			check(is_zero_approx((right.position+(art.foot-art.region.position)*art.source_scale).length()),id+"/"+pose+" source foot maps to physical origin")
		art.set_pose("idle")
	for key: String in unique_hashes:
		check(FileAccess.get_sha256(AssetCatalog.resolve(key))==unique_hashes[key],"native source hash "+key)
	check(actors["B08-M01"].native_art.frames.idle.foot==[637.0,1127.0],"original M01 foot retained")
	check(actors["B08-M02"].native_art.frames.warning.world_per_source_pixel==actors["B08-M02"].native_art.frames.recovery.world_per_source_pixel,"M02 crouch not enlarged by alpha box")
	check(actors["B08-M03"].native_art.frames.warning.world_per_source_pixel==actors["B08-M03"].native_art.frames.release.world_per_source_pixel,"M03 action scale constant through lunge")
	var archer=actors["B08-M01"]
	archer.brain._begin(archer,room.player)
	archer.native_art.advance(0,archer.brain.phase,archer.brain.action)
	check(archer.native_art.active_pose=="warning" and archer.brain.remaining==.9,"actual frozen arrow warning selects drawn bow")
	var lock_point: Vector2=archer.brain.action.target
	archer.brain._release(archer)
	archer.native_art.advance(0,archer.brain.phase,archer.brain.action)
	check(archer.native_art.active_pose=="release" and room.feathers.size()==1,"real projectile release selects empty-bow keypose")
	var shot: Dictionary=room.feathers[0]
	check(shot.position==archer.position and shot.direction.is_equal_approx(archer.position.direction_to(lock_point)) and shot.remaining==320,"visual arrow leaves origin target and range unchanged")
	check(room.sky_projectile_art!=null and room.sky_projectile_art.bounds().end.x==6,"native arrow registered over original projectile proxy")
	archer.native_art.advance(.17,archer.brain.phase,archer.brain.action)
	check(archer.native_art.active_pose=="recovery","short presentation release returns to recovery")
	var diver=actors["B08-M02"]
	diver.brain._begin(diver,room.player)
	diver.brain._release(diver)
	diver.native_art.advance(0,diver.brain.phase,diver.brain.action)
	check(diver.native_art.active_pose=="release" and diver.brain.transit,"actual dive uses folded-wing frame")
	diver.brain._land(diver)
	diver.native_art.advance(0,diver.brain.phase,diver.brain.action)
	check(diver.native_art.active_pose=="recovery" and not diver.brain.transit and diver.brain.remaining==1.1,"landing immediately grounds crouch with full existing recovery")
	var scout=actors["B08-M03"]
	scout.brain._begin(scout,room.player)
	scout.brain._release(scout)
	scout.native_art.advance(0,scout.brain.phase,scout.brain.action)
	check(scout.native_art.active_pose=="idle","flank travel never mislabels stab as locomotion")
	scout.brain._land(scout)
	scout.native_art.advance(0,scout.brain.phase,scout.brain.action)
	check(scout.native_art.active_pose=="release","actual post-reposition stab selects stab keypose")
	scout.brain.interrupt(scout)
	scout.native_art.advance(0,scout.brain.phase,scout.brain.action)
	check(scout.native_art.active_pose=="idle","cancelled action cannot display false release")
	check_launch_cue(room,archer)
	room._open_room("L44")
	check(room.sky_environment==null and room.sky_projectile_art==null,"leaving L43 releases new visuals")
	var native_elsewhere:=false
	for actor: Node2D in room.enemies.get_children():
		if actor.native_art!=null: native_elsewhere=true
	check(not native_elsewhere,"no unreviewed other-room art activation")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no reward or campaign mutation")
	check(await room.cleanup_for_exit(),"bounded audio cleanup")
	room.free()
	await get_tree().process_frame
	print("B08_L43_INTEGRATION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
func check_launch_cue(room: Node2D, archer: Node2D) -> void:
	var art=room.sky_projectile_art
	var saved_position: Vector2=archer.position
	var saved_aim: Vector2=archer.aim_direction
	var saved_player: Vector2=room.player.position
	room.feathers.clear()
	room.player.position=Geometry.point([380,960])
	for mirrored: bool in [false,true]:
		archer.position=Geometry.point([1400,1030])
		archer.aim_direction=Vector2.LEFT if mirrored else Vector2.RIGHT
		var action: Dictionary=archer.brain.action.duplicate(true)
		action.target=archer.position+archer.aim_direction*250
		var serial: int=room.shot_serial
		room.fire_feather(archer,action,1.0,320)
		var shot: Dictionary=room.feathers[-1]
		var offset:=Vector2(-287 if mirrored else 287,-336.5)/5.5
		check(shot.has("visual_launch") and Vector2(shot.visual_launch.outlet).is_equal_approx(archer.position+offset),"release-specific bow anchor and mirrored foot "+str(mirrored))
		check(art.launch_strength(shot)==1 and shot.position==archer.position,"cue starts without displacing the hit proxy")
		var frozen: Dictionary=shot.visual_launch.duplicate(true)
		archer.position+=Vector2(15,0); archer.aim_direction=-archer.aim_direction
		archer.native_art.set_pose("recovery")
		check(shot.visual_launch==frozen,"movement turn and recovery cannot drag the frozen bow cue")
		archer.position-=Vector2(15,0); archer.aim_direction=-archer.aim_direction
		room.sky_projectile_art=null
		room.shot_serial=serial # Compare the same deterministic critical seed.
		room.fire_feather(archer,action,1.0,320)
		room.sky_projectile_art=art
		var control: Dictionary=room.feathers[-1]
		room._tick_feathers(.07)
		check(is_equal_approx(art.launch_strength(shot),.5),"source cue fades using real 320 per second travel")
		check(shot.position==control.position and shot.direction==control.direction and shot.remaining==control.remaining and shot.packet==control.packet,"presentation leaves actual travel range and damage packet equal to no-art control")
		room._tick_feathers(.08)
		check(art.launch_strength(shot)==0 and shot.position==control.position,"cue ends at .14 seconds; both shots continue on the unchanged ground ray")
		room.feathers.clear()
	archer.position=Geometry.point([500,580]); archer.aim_direction=Vector2.RIGHT
	var edge_action: Dictionary=archer.brain.action.duplicate(true)
	edge_action.target=archer.position+Vector2(200,0)
	room.fire_feather(archer,edge_action,1.0,320)
	check(not room.feathers[0].has("visual_launch"),"bow cue outside legal floor is omitted without moving the shot")
	check(art.launch_strength(room.feathers[0])==0,"missing cue retains original ground feather fallback")
	room.feathers.clear()
	archer.position=saved_position; archer.aim_direction=saved_aim
	room.player.position=saved_player
