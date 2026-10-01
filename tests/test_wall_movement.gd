extends Node
const RoomScene = preload("res://scenes/room.tscn")
var room: MineRoom
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var _physics_started: int = 0
var _measuring: bool = false
var _physics_times: Array[int] = []
var _navigation_times: Array[int] = []
var _room_times: Array[int] = []
class FrameEndProbe extends Node:
	var observer: Node
	func _physics_process(_delta: float) -> void:
		observer._record_physics()
func _ready() -> void:
	process_physics_priority=-10000
	var probe := FrameEndProbe.new()
	probe.observer=self
	probe.process_physics_priority=10000
	add_child(probe)
	call_deferred("_run")
func _physics_process(_delta: float) -> void:
	_physics_started=Time.get_ticks_usec()
func _record_physics() -> void:
	if is_instance_valid(room):
		if _measuring:
			_physics_times.append(Time.get_ticks_usec()-_physics_started)
			_navigation_times.append(room.navigation_usec)
			_room_times.append(room.room_usec)
		room.navigation_usec=0
		room.room_usec=0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func stats(values: Array[int]) -> Dictionary:
	values.sort()
	return {"median_usec":values[values.size()/2],"p95_usec":values[mini(values.size()-1,int(values.size()*.95))],"max_usec":values[-1],"samples":values.size()}
func _run() -> void:
	if not Game.profile_path.contains("test_wall_movement"):
		get_tree().quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","interact","attack","dash"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.select_hero("CH02") and Game.start_run(), "isolated movement profile")
	room = RoomScene.instantiate()
	room.set_script(preload("res://tests/fixtures/wall_profile_room.gd"))
	room.run_seed = 960208
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.release_gate = false
	room.spawn_enabled = false
	room._refresh_terrain_canvas()
	var initial_terrain_redraws: int = room.terrain_redraw_count
	for frame: int in 60:
		room._refresh_terrain_canvas()
	check(room.terrain_redraw_count == initial_terrain_redraws, "stationary terrain retains one draw list while camera/player movement continues")
	var wall: Rect2 = room.obstructions[0]
	var radius: float = Balance.PLAYER_RADIUS
	var cases: Array[Dictionary] = [
		{"id":"outer_up","at":Vector2(1400,radius+1),"input":Vector2.UP},
		{"id":"outer_down","at":Vector2(1400,1800-radius-1),"input":Vector2.DOWN},
		{"id":"outer_left","at":Vector2(radius+1,900),"input":Vector2.LEFT},
		{"id":"outer_right","at":Vector2(2800-radius-1,900),"input":Vector2.RIGHT},
		{"id":"prop_up","at":Vector2(wall.get_center().x,wall.end.y+radius+1),"input":Vector2.UP},
		{"id":"prop_down","at":Vector2(wall.get_center().x,wall.position.y-radius-1),"input":Vector2.DOWN},
		{"id":"prop_left","at":Vector2(wall.end.x+radius+1,wall.get_center().y),"input":Vector2.LEFT},
		{"id":"prop_right","at":Vector2(wall.position.x-radius-1,wall.get_center().y),"input":Vector2.RIGHT}]
	for sample: Dictionary in cases:
		var at: Vector2 = sample.at
		check(room.valid_ground(at,radius), sample.id+" valid start")
		var timings: Array[int] = []
		for step in 180:
			var started: int = Time.get_ticks_usec()
			var next: Vector2 = room.move_actor(at,sample.input*255.0/60.0,radius)
			timings.append(Time.get_ticks_usec()-started)
			check(room.valid_ground(next,radius),sample.id+" collision remains solid")
			if step > 1: check(next.distance_to(at)<.001,sample.id+" held input does not jitter")
			at = next
		var record: Dictionary = stats(timings)
		record.merge({"case":sample.id,"final":str(at),"travel":at.distance_to(sample.at)})
		records.append(record)
		print("MOVEMENT_PROFILE ",JSON.stringify(record))
	# Along a flat face diagonal input must keep its free axis, while a corner
	# blocks both axes. These are different from simply stopping head-on.
	var sliding := Vector2(700,radius)
	for step in 180:
		sliding = room.move_actor(sliding,Vector2(1,-1).normalized()*255.0/60.0,radius)
		check(is_equal_approx(sliding.y,radius) and room.valid_ground(sliding,radius),"diagonal outer-wall slide stays solid")
	check(sliding.x>1200,"held diagonal input slides freely along outer wall")
	var corner := Vector2(radius,radius)
	for step in 180:
		corner = room.move_actor(corner,Vector2(-1,-1)*4.0,radius)
		check(corner==Vector2(radius,radius),"outer corner remains stable")
	for obstacle: Rect2 in room.obstructions.slice(0,6):
		for side: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			var edge := obstacle.get_center()+Vector2(side.x*(obstacle.size.x*.5+radius+1),side.y*(obstacle.size.y*.5+radius+1))
			if not room.valid_ground(edge,radius): continue
			for step in 120:
				edge=room.move_actor(edge,-side*4.25,radius)
				check(room.valid_ground(edge,radius),"six independent props block all four approach directions")
	var physical_geometry: Array[Rect2] = room.obstructions.duplicate()
	room.obstructions.assign([Rect2(800,600,240,200)])
	room._refresh_terrain_canvas()
	check(room.terrain_redraw_count == initial_terrain_redraws + 1, "changed collision immediately refreshes the retained terrain canvas")
	# Equal diagonal inputs hit a rounded corner symmetrically, then remain
	# still under sustained contact; the camera must not inherit axis bias.
	for side: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
		var prop_corner := Vector2(800.0 if side.x < 0.0 else 1040.0, 600.0 if side.y < 0.0 else 800.0)
		var approaching: Vector2 = prop_corner + side * 32.0
		for step: int in 30:
			approaching = room.move_actor(approaching, -side * 4.0, radius)
			check(room.valid_ground(approaching, radius), "rounded prop corner contact remains outside solid geometry")
		var contact: Vector2 = approaching
		check(absf(absf(contact.x - prop_corner.x) - absf(contact.y - prop_corner.y)) < 0.01, "diagonal corner contact has no horizontal-first snap")
		for step: int in 90:
			approaching = room.move_actor(approaching, -side * 4.0, radius)
			check(approaching.distance_to(contact) < 0.001, "held diagonal corner input has no subpixel creep or camera jitter")
	var route_start := Vector2(700,700)
	var route_end := Vector2(1150,700)
	var around: Vector2 = room.navigation_direction(route_start,route_end,18)
	check(not around.is_zero_approx() and absf(around.y)>.1,"path routes around an actual wall")
	var build_count: int = room._navigation_cache.graph_builds
	for step in 100:
		room.navigation_direction(route_start,route_end,18)
	check(room._navigation_cache.graph_builds==build_count,"held target does not rebuild a visibility graph per frame")
	room.obstructions[0]=Rect2(800,100,240,200)
	check(room.navigation_direction(route_start,route_end,18)==Vector2.RIGHT,"moved prop invalidates cached route immediately")
	room.obstructions[0]=Rect2(800,600,240,200)
	check(absf(room.navigation_direction(route_start,route_end,18).y)>.1,"replacement obstacle restores collision-aware detour")
	for enemy_radius: float in [18.0,24.0]:
		var chasing:=Vector2(920,550)
		var tight_player:=Vector2(920,814)
		for step in 600:
			var heading: Vector2=room.navigation_direction(chasing,tight_player,enemy_radius)
			chasing=room.move_actor(chasing,heading*2.0,enemy_radius)
			check(room.valid_ground(chasing,enemy_radius),"larger enemy detour toward wall-hugging player stays solid")
			if chasing.distance_to(tight_player)<40.0 and room.has_line_of_sight(chasing,tight_player): break
		check(chasing.distance_to(tight_player)<40.0 and room.has_line_of_sight(chasing,tight_player),"larger enemy can reach attack distance when player hugs cover")
	var rounded_corner:=Vector2(788,588)
	check(room.valid_ground(rounded_corner,14),"round collider corner fixture is physically valid")
	for step in 90:
		var heading: Vector2=room.navigation_direction(rounded_corner,Vector2(700,500),14)
		rounded_corner=room.move_actor(rounded_corner,heading*2.0,14)
		check(room.valid_ground(rounded_corner,14),"rounded-corner recovery never cuts through solid cover")
	check(rounded_corner.distance_to(Vector2(700,500))<4.0,"rounded collider corner escapes conservative navigation box")
	room.obstructions.clear()
	check(room.navigation_direction(route_start,route_end,18)==Vector2.RIGHT,"broken prop invalidates cached route immediately")
	room.obstructions.assign([Rect2(1000,0,50,1751)])
	var boundary_route:=Vector2(950,1770)
	var boundary_goal:=Vector2(1100,1770)
	for step in 300:
		if boundary_route.distance_to(boundary_goal)<3.0: break
		var heading: Vector2=room.navigation_direction(boundary_route,boundary_goal,24)
		boundary_route=room.move_actor(boundary_route,heading*2.0,24)
		check(room.valid_ground(boundary_route,24),"minimum-width arena-edge passage keeps real collision")
	check(boundary_route.distance_to(boundary_goal)<3.0,"navigation margin does not erase a physically open arena-edge passage")
	room.obstructions.assign([Rect2(113,113,30,100)])
	var coarse_target:=Vector2(350,150)
	var before_corner: Vector2=room.navigation_direction(Vector2(77,91),coarse_target,24)
	var after_corner: Vector2=room.navigation_direction(Vector2(93,75),coarse_target,24)
	check(before_corner.x>0 and before_corner.y<0,"coarse steering initially approaches corner")
	check(after_corner.x>0,"5Hz moving objective continues forward after passing a cached corner")
	# Every authored room can be generated for the expedition. The production
	# mover must traverse each generated entry/encounter/exit chain after the
	# pathfinding change, not merely route around one convenient rectangle.
	for room_number: int in range(1,25):
		var generated: Dictionary=RoomGenerator.generate("L%02d"%room_number,960208+room_number)
		check(not generated.is_empty(),"generated expedition room exists for navigation regression")
		room.obstructions.assign(generated.obstructions)
		var destinations: Array[Vector2]=[]
		for zone: Dictionary in generated.encounter_zones: destinations.append(zone.center)
		destinations.append(generated.exit)
		for traversal_radius: float in [14.0,24.0]:
			var travelling: Vector2=generated.entry
			for destination: Vector2 in destinations:
				for step in 2500:
					if travelling.distance_to(destination)<12.0: break
					var heading: Vector2=room.navigation_direction(travelling,destination,traversal_radius)
					var next: Vector2=room.move_actor(travelling,heading*minf(11.0,travelling.distance_to(destination)),traversal_radius)
					check(room.valid_ground(next,traversal_radius),"24 generated expedition routes keep collision")
					if next.distance_squared_to(travelling)<0.000001: break
					travelling=next
				check(travelling.distance_to(destination)<12.0,"L%02d generated encounter/exit route is reachable"%room_number)
	room.obstructions.assign(physical_geometry)
	room._navigation_cache.prepare(room.obstructions,room.ARENA)
	# Production profile brains perform their actual navigation at a blocked
	# target; no AI-disabled flags or reduced enemy counts are used.
	room.player.position = Vector2(wall.get_center().x,wall.end.y+radius+1)
	var blocked_start := Vector2(wall.get_center().x,wall.position.y-32)
	for enemy in room.enemies.get_children():
		enemy.position = blocked_start
		enemy.brain._set_phase(&"chase",0)
		enemy.brain.age = 1.0
	var ai_times: Array[int] = []
	for step in 30:
		var started := Time.get_ticks_usec()
		for enemy in room.enemies.get_children():
			enemy._physics_process(1.0/60.0)
		ai_times.append(Time.get_ticks_usec()-started)
	var ai_record := stats(ai_times)
	ai_record["case"]="production_5_enemy_blocked_chase"
	ai_record["enemies"]=room.enemies.get_child_count()
	records.append(ai_record)
	print("MOVEMENT_PROFILE ",JSON.stringify(ai_record))
	check(int(ai_record.p95_usec)<16000,"five real chasing enemies stay within one 60-Hz CPU frame")
	while room.enemies.get_child_count()<Balance.MAX_ENEMIES:
		var enemy: MineEnemy=room.spawn_enemy(blocked_start,"M01",5)
		check(enemy!=null,"stress actor uses production spawn and real collision")
		if enemy==null: break
		enemy.brain.age=1.0
		enemy.brain._set_phase(&"chase",0)
	ai_times.clear()
	for step in 180:
		var started := Time.get_ticks_usec()
		for enemy in room.enemies.get_children(): enemy._physics_process(1.0/60.0)
		ai_times.append(Time.get_ticks_usec()-started)
		for enemy in room.enemies.get_children(): check(room.valid_ground(enemy.position,enemy.navigation_radius),"18-enemy chase keeps collision")
	var stress_record := stats(ai_times)
	stress_record["case"]="production_18_enemy_blocked_chase"
	stress_record["enemies"]=room.enemies.get_child_count()
	records.append(stress_record)
	print("MOVEMENT_PROFILE ",JSON.stringify(stress_record))
	check(int(stress_record.p95_usec)<16000,"18 real chasing enemies stay within one 60-Hz CPU frame")
	if DisplayServer.get_name()!="headless":
		await _graphical_checks(cases)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var output_path: String="res://artifacts/wall_movement_profile_headless.json" if DisplayServer.get_name()=="headless" else "res://artifacts/wall_movement_profile.json"
	var output := FileAccess.open(output_path,FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"obstructions":room.obstructions.size(),"cases":records},"\t"))
	output.close()
	if is_instance_valid(room.combat_audio): await room.combat_audio.wait_for_cleanup()
	room.free()
	# Let the silent/headless audio server retire stopped playback references.
	await get_tree().process_frame
	await get_tree().process_frame
	Game.run=null
	print("WALL MOVEMENT ",checks-failures,"/",checks)
	get_tree().quit(0 if failures==0 else 1)

func _graphical_checks(cases: Array[Dictionary]) -> void:
	DisplayServer.window_set_title("Movement verification - isolated test profile")
	AudioServer.set_bus_mute(0,true)
	# Full production player, 18 enabled brains, props, enemy skills and world
	# renderer at the normal 1280x720. Extra fixture HP only prevents the long
	# no-attacking measurement from ending the isolated run.
	Game.run.hp=100000.0
	for sample: Dictionary in cases:
		room.player.position=sample.at
		room.player.knockback=Vector2.ZERO
		room.player.cancel_actions()
		var direction: Vector2=sample.input
		var action: String="move_up" if direction==Vector2.UP else "move_down" if direction==Vector2.DOWN else "move_left" if direction==Vector2.LEFT else "move_right"
		Input.action_press(action)
		room.release_gate=false
		room.process_mode=Node.PROCESS_MODE_INHERIT
		var frame_times: Array[int]=[]
		_physics_times.clear()
		_navigation_times.clear()
		_room_times.clear()
		var previous: int=Time.get_ticks_usec()
		for index in 135:
			await get_tree().physics_frame
			await get_tree().process_frame
			var now: int=Time.get_ticks_usec()
			if index>=15:
				_measuring=true
				frame_times.append(now-previous)
			previous=now
			check(room.valid_ground(room.player.position,Balance.PLAYER_RADIUS),sample.id+" actual player input keeps collision with 18 live brains")
		Input.action_release(action)
		room.process_mode=Node.PROCESS_MODE_DISABLED
		_measuring=false
		var record: Dictionary={"case":"graphical_18_enemy_"+sample.id,"frame":stats(frame_times),"physics":stats(_physics_times),"navigation":stats(_navigation_times),"room":stats(_room_times),"hp":Game.run.hp,"enemies":room.enemies.get_child_count(),"viewport":str(get_viewport().get_visible_rect().size)}
		records.append(record)
		print("MOVEMENT_PROFILE ",JSON.stringify(record))
		check(int(record.physics.p95_usec)<16000,sample.id+" real physics P95 stays within 60-Hz frame budget")
		if sample.id=="prop_up":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/wall_movement_graphical.png")
