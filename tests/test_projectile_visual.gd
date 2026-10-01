extends Node
## Frozen display paths are compared with the unchanged real projectile solver.
const RoomScene = preload("res://scenes/room.tscn")
const Path = preload("res://scripts/combat/projectile_visual.gd")
var room: MineRoom
var checks := 0
var failures := 0

class PathActor extends Node2D:
	var navigation_radius := 12.0
	var body_bounds := Rect2(-12,-48,24,66)
	func is_alive() -> bool: return true

class ScanRoom extends Node2D:
	var enemies := Node2D.new()
	var ARENA := Rect2(-200,-200,2000,1000)
	var obstructions: Array[Rect2] = []
	func _init() -> void: add_child(enemies)
	func blocked_fraction(_from: Vector2,_to: Vector2,_radius: float=0.0) -> float: return 1.0
	func has_line_of_sight(_from: Vector2,_to: Vector2) -> bool: return true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PROJECTILE VISUAL FAIL: "+label)

func fixture(hero: String = "CH02") -> void:
	get_tree().paused = false
	if is_instance_valid(room): room.free()
	Game.run.hero_id = hero
	Game.run.level = 8
	Game.run.stats = StatResolver.resolve(hero,8,{}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	room.combat_audio.audible = false
	room.obstructions.clear()
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = room.ARENA.get_center()

func dummy(at: Vector2) -> MineEnemy:
	var enemy: MineEnemy = room.spawn_enemy(at,"M01")
	enemy.health.reset(10000.0)
	enemy.training_ai_disabled = true
	return enemy

func fire(direction: Vector2) -> SparkProjectile:
	room.player.aim_direction = direction
	check(room.player.fire(direction), "public hero basic spawns real projectile")
	return room.projectiles.get_child(0) as SparkProjectile

func has_object(value: Variant) -> bool:
	if value is Object: return true
	if value is Dictionary:
		for entry: Variant in value.values():
			if has_object(entry): return true
	if value is Array:
		for entry: Variant in value:
			if has_object(entry): return true
	return false

func check_source_and_bounds() -> void:
	for hero: String in ["CH02","CH03"]:
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			fixture(hero)
			var origin: Vector2 = room.player.position
			var shot: SparkProjectile = fire(direction)
			var expected: Vector2 = origin+HeroVisual.release_muzzle_local(hero,"basic",direction)
			check(shot.position == origin and shot.visual_position().distance_to(expected)<.001, hero+" display starts from release muzzle without moving collision origin "+str(direction))
			check(shot.speed == (950.0 if hero == "CH02" else 720.0), "class movement speed remains unchanged")
			var before: Dictionary = shot.visual_path_snapshot()
			check(not before.is_empty() and not has_object(before), "path contains only frozen values, no actor or weak references")
			check(shot.visual_trail_fraction()==0.0,"newly created projectile has no trail extending backwards through the muzzle")
			room.player.position += Vector2(90,90)
			room.player.aim_direction = -direction
			check(shot.visual_position().distance_to(expected)<.001 and shot.visual_path_snapshot()==before, "moving/turning player cannot drag already fired shot")
			var previous: float = -INF
			var display_end: Vector2 = Path.position_at(before,origin+direction*float(before.stop_distance))
			for index in 41:
				var physical: Vector2 = origin+direction*float(before.stop_distance)*index/40.0
				var visual: Vector2 = Path.position_at(before,physical)
				var projected: float = (visual-origin).dot(direction)
				check(visual.is_finite() and projected+.001>=previous and projected<=(display_end-origin).dot(direction)+.001, "display path remains finite and never flies backwards/past its frozen endpoint")
				previous = projected
			if hero == "CH02":
				check(display_end.distance_to(expected+direction*float(before.stop_distance))<.001, "empty rifle flight keeps muzzle height for its entire range")
			else:
				check(display_end.distance_to(origin+direction*float(before.stop_distance))<.001, "crystal preserves its authored return to the physical plane")
			# A wall closer than the visible barrel clamps the display launch;
			# both the visual terminal and actual physics use wall radius 2.
			fixture(hero)
			origin = room.player.position
			var wall_center: Vector2 = origin+direction*12.0
			var size := Vector2(6,220) if absf(direction.x)>.5 else Vector2(220,6)
			room.obstructions.assign([Rect2(wall_center-size*.5,size)])
			var behind: MineEnemy = dummy(origin+direction*180.0)
			shot = fire(direction)
			var path: Dictionary = shot.visual_path_snapshot()
			check(path.candidate_count==0 and path.stop_distance<12.0, "wall excludes hidden targets from display route")
			previous = -INF
			for index in 11:
				var visual: Vector2 = Path.position_at(path,origin+direction*float(path.stop_distance)*index/10.0)
				var projected: float = (visual-origin).dot(direction)
				check(projected+.001>=previous and projected<=float(path.stop_distance)+.001, "near-wall launch and endpoint remain monotonic")
				previous = projected
			shot._physics_process(.1)
			check(shot.consumed and behind.health.current==10000.0 and room.impact_feedback.accepted_events==0, "actual near wall terminates without fake monster contact")

func check_offset_obstacles() -> void:
	for mode: String in ["side_wall","corner_body"]:
		fixture()
		var origin: Vector2 = room.player.position
		if mode == "side_wall":
			room.obstructions.assign([Rect2(origin+Vector2(45,-45),Vector2(20,37))])
		else:
			room.obstructions.assign([Rect2(origin+Vector2(90,-60),Vector2(45,52))])
			dummy(origin+Vector2(230,0))
		check(room.blocked_fraction(origin,origin+Vector2(600,0),2.0)==1.0,mode+" fixture has unobstructed actual collider ray")
		var path: Dictionary = Path.snapshot(room,origin,Vector2.RIGHT,600.0,0,origin+Vector2(20,-40),true)
		check(path.plane_fallback,mode+" displaced chord would enter wall, so display returns to safe collision plane")
		for index in range(1,path.knots.size()):
			check(room.blocked_fraction(path.knots[index-1].point,path.knots[index].point,2.0)==1.0,mode+" final visual segment does not pass through side obstacle")
		for index in 31:
			var center: Vector2 = Path.position_at(path,origin+Vector2(index*20.0,0))
			var scale: float = Path.draw_scale(room,center)
			# Test the complete enclosing disk, including the head, glow and tail,
			# rather than asserting safety of only the projectile center.
			for ray in 16:
				var edge: Vector2 = center+Vector2.from_angle(ray*TAU/16.0)*Path.DRAW_RADIUS*scale
				check(room.valid_ground(edge,.5),mode+" scaled full visual footprint remains outside obstacle")
	fixture()
	var origin: Vector2 = room.player.position
	room.obstructions.assign([Rect2(origin+Vector2(10,-100),Vector2(15,200))])
	for distance in [0.0,5.0,8.0,9.5]:
		var center: Vector2 = origin+Vector2(distance,0)
		var scale: float = Path.draw_scale(room,center)
		check(center.x+Path.DRAW_RADIUS*scale<=origin.x+10.0-.5,"close-wall head and longest tail fit before the wall")
	var bounded := ScanRoom.new()
	for index in 80:
		var actor := PathActor.new()
		actor.position = Vector2(60+index*12,0)
		bounded.enemies.add_child(actor)
	var path: Dictionary = Path.snapshot(bounded,Vector2.ZERO,Vector2.RIGHT,1200.0,99,Vector2(15,-30))
	check(path.scanned==64 and path.candidate_count==6,"dense actor scans and penetration body points are strictly bounded")
	check(not has_object(path),"bounded candidate sampling retains no temporary actor references")
	var rifle_path: Dictionary = Path.snapshot(bounded,Vector2.ZERO,Vector2.RIGHT,1200.0,99,Vector2(15,-30),true)
	check(rifle_path.scanned==64 and rifle_path.candidate_count==1 and rifle_path.knots.size()==2,"rifle penetration snapshots only its first body and never builds a multi-target polyline")
	bounded.free()

func check_straight_rifle() -> void:
	var bounded := ScanRoom.new()
	var origin := Vector2(300,300)
	# Empty shots include the old 96px transition and their complete range: there
	# can be no hidden late drop to the floor or tangent reversal at the endpoint.
	for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,1).normalized()]:
		var source: Vector2 = origin+direction*20.0+direction.orthogonal()*-45.0
		var path: Dictionary = Path.snapshot(bounded,origin,direction,600.0,4,source,true)
		_check_line(path,origin,direction,source,direction,"empty "+str(direction))
		check(not path.body_locked and not path.plane_fallback,"empty rifle keeps its level muzzle ray")
	var first := PathActor.new()
	first.position = origin+Vector2(210,0)
	bounded.enemies.add_child(first)
	var second := PathActor.new()
	second.position = origin+Vector2(360,11)
	second.body_bounds = Rect2(-12,-100,24,118)
	bounded.enemies.add_child(second)
	var source: Vector2 = origin+Vector2(20,-40)
	var body: Vector2 = first.position+Vector2(0,first.body_bounds.end.y-first.body_bounds.size.y*.53)
	var first_distance: float = 210.0-(first.navigation_radius+4.0)
	var expected_velocity: Vector2 = (body-source)/first_distance
	var path: Dictionary = Path.snapshot(bounded,origin,Vector2.RIGHT,600.0,4,source,true)
	check(path.body_locked and path.candidate_count==1,"first reachable body fixes one rifle direction, independent of later penetration targets")
	check(Path.position_at(path,origin+Vector2.RIGHT*first_distance).distance_to(body)<.001,"frozen rifle line intersects first target surface at the collision entry distance")
	_check_line(path,origin,Vector2.RIGHT,source,expected_velocity,"penetrating")
	var frozen: Dictionary = path.duplicate(true)
	first.position += Vector2(0,200)
	second.position += Vector2(0,-250)
	first.free()
	second.free()
	check(path==frozen and not has_object(path),"target movement or deletion cannot retarget the snapshotted rifle line")
	_check_line(path,origin,Vector2.RIGHT,source,expected_velocity,"after targets move")
	var close := PathActor.new()
	close.position = origin+Vector2(30,0)
	bounded.enemies.add_child(close)
	path = Path.snapshot(bounded,origin,Vector2.RIGHT,600.0,0,source,true)
	check(not path.body_locked,"very close target cannot force a steep rifle shot into the floor")
	_check_line(path,origin,Vector2.RIGHT,source,Vector2.RIGHT,"near target")
	close.position = origin+Vector2(110,0)
	close.body_bounds = Rect2(-12,-500,24,518)
	path = Path.snapshot(bounded,origin,Vector2.RIGHT,600.0,0,source,true)
	check(not path.body_locked,"extreme target body offset cannot swing the rifle away from its aim")
	_check_line(path,origin,Vector2.RIGHT,source,Vector2.RIGHT,"steep body rejected")
	bounded.free()

func _check_line(path: Dictionary, origin: Vector2, physical_direction: Vector2, source: Vector2, velocity: Vector2, label: String) -> void:
	var stop: float = float(path.stop_distance)
	for index in 61:
		var distance: float = stop*index/60.0
		var physical: Vector2 = origin+physical_direction*distance
		var visual: Vector2 = Path.position_at(path,physical)
		check(visual.distance_to(source+velocity*distance)<.002,label+" entire display flight stays on one frozen line")
		check(Path.direction_at(path,physical,physical_direction).distance_to(velocity.normalized())<.001,label+" needle orientation never changes at old blend points or target entries")
	var end: Vector2 = source+velocity*stop
	check(Path.position_at(path,origin+physical_direction*(stop+200.0)).distance_to(end)<.002,label+" overshooting physical step clamps to displayed endpoint without jumping back to ground")
	check(Path.direction_at(path,origin+physical_direction*(stop+200.0),physical_direction).distance_to(velocity.normalized())<.001,label+" endpoint keeps the launch heading")

func trace(hero: String, mode: String, enabled: bool) -> Dictionary:
	fixture(hero)
	var origin: Vector2 = room.player.position
	var target: MineEnemy = dummy(origin+Vector2(210,0))
	var second: MineEnemy
	var shot: SparkProjectile
	if mode == "pierce":
		second = dummy(origin+Vector2(370,0))
		room.player.aim_direction = Vector2.RIGHT
		shot = room.spawn_ability_projectile(origin+Vector2(19,0),Vector2.RIGHT,30.0,
			{"source":"secondary","original":true,"speed":1300.0,"range":780.0,"pierce":1,"pierce_multiplier":.65})
	else:
		shot = fire(Vector2.RIGHT)
	var frozen: Dictionary = shot.visual_path_snapshot()
	check(frozen.candidate_count == (2 if mode == "pierce" and hero != "CH02" else 1), "rifle freezes only its first target; crystal preserves bounded body snapshots")
	if not enabled: shot._visual_path.clear()
	if mode == "move": target.position += Vector2(0,150)
	if mode == "free": target.free()
	if mode == "immune": target.apply_status("invulnerable",1.0,5.0)
	if mode == "kill": target.health.reset(1.0)
	var samples: Array[Dictionary] = []
	for index in 100:
		if shot.consumed: break
		shot._physics_process(.01)
		samples.append({"position":shot.position,"direction":shot.direction,"remaining":shot.remaining,"distance":shot.distance_left,"consumed":shot.consumed,"hits":shot.hit_ids.size()})
		check(shot.direction==Vector2.RIGHT,"actual projectile direction never reflects or follows its presentation path")
		if enabled: check(shot.visual_path_snapshot()==frozen,"flight never updates from moving/dead target")
	var hp: float = target.health.current if is_instance_valid(target) else -1.0
	var second_hp: float = second.health.current if is_instance_valid(second) else -1.0
	if mode in ["move","free","immune"]:
		check(room.impact_feedback.accepted_events==0,"missing/moved/invulnerable targets create no confirmed contact")
	else:
		check(room.impact_feedback.accepted_events==(2 if mode=="pierce" else 1),"only real HP loss produces the expected contact count")
	return {"samples":samples,"hp":hp,"second_hp":second_hp,"contacts":room.impact_feedback.accepted_events}

func check_real_solver() -> void:
	for hero: String in ["CH02","CH03"]:
		for mode: String in ["static","move","free","immune","kill","pierce"]:
			var plain: Dictionary = trace(hero,mode,false)
			var projected: Dictionary = trace(hero,mode,true)
			check(plain==projected,hero+" "+mode+" has identical physical positions, lifetime, range, damage, hit count and confirmed impacts")
	fixture()
	var child: SparkProjectile = room.spawn_projectile(room.player.position,Vector2.RIGHT,8,&"child")
	check(child.visual_path_snapshot().is_empty() and child.visual_position()==child.position,"derived child shots keep existing plane and effects")
	var node: SparkProjectile = room.spawn_ability_projectile(room.player.position,Vector2.RIGHT,8,{"source":"node","original":false})
	check(node.visual_path_snapshot().is_empty(),"stationary node fire does not borrow hero's muzzle")

func check_pause() -> void:
	fixture()
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var shot: SparkProjectile = fire(Vector2.RIGHT)
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().paused = true
	var position: Vector2 = shot.position
	var visual: Vector2 = shot.visual_position()
	var lifetime: float = shot.remaining
	for index in 4: await get_tree().physics_frame
	check(shot.position==position and shot.visual_position()==visual and shot.remaining==lifetime,"real SceneTree pause freezes physics and visible flight together")
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(shot.position!=position and shot.visual_position()!=visual,"resume continues same frozen display path")

func run_checks() -> void:
	if not Game.profile_path.contains("test_projectile_visual"):
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(),"isolated trajectory fixture starts")
	check_source_and_bounds()
	check_offset_obstacles()
	check_straight_rifle()
	check_real_solver()
	await check_pause()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
	print("PROJECTILE VISUAL ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
