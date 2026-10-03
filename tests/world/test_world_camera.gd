extends Node
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
var room: RoomController
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	if not Game.profile_path.contains("test_world_camera"):
		get_tree().quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","interact","attack","dash"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.select_hero("CH02") and Game.start_run(), "isolated world run")
	Game.run.stats = StatResolver.resolve("CH02", 1, {}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.loadout_snapshot.clear()
	room = RoomScene.instantiate()
	room.use_generated_layout = false # Fixed authored collision fixture; generator has its own seeded route checks.
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.release_gate = false
	check(room.ARENA == Rect2(0,0,2800,1800), "actual 2800 by 1800 world")
	check(room.obstructions.size() >= 4, "authored collision geometry loaded")
	check(room.encounter_zones.size() >= 3, "three distributed encounter regions")
	check(room.activated_encounters.size() == 1 and room.enemies.get_child_count() == EnemyProfiles.encounter(room.layout_id,0,room.difficulty).size(), "only nearby encounter wakes on entry")
	check(room.camera.zoom == Vector2(.85,.85), "camera reduces on-screen actor size without combat-scale changes")
	for contact: int in 30:
		room.camera.impact(100.0, Vector2.LEFT if contact % 2 == 0 else Vector2.DOWN, true)
		room.camera._physics_process(.016)
		check(room.camera.offset == Vector2.ZERO, "default camera remains steady through repeated heavy contacts")
	check(room.camera.impact_stats().started == 0, "comfort default prevents all room contact motion")
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	for point: Vector2 in [Vector2(20,20),Vector2(1400,900),Vector2(2780,1780)]:
		room.player.position = point
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await get_tree().process_frame
		var center: Vector2 = room.camera.get_screen_center_position()
		var visible: Rect2 = Rect2(center - viewport_size / room.camera.zoom * .5, viewport_size / room.camera.zoom)
		check(room.camera.render_bounds.grow(.1).encloses(visible), "camera stays inside authored render border at " + str(point))
		var screen_position: Vector2 = room.player.get_global_transform_with_canvas().origin
		check(screen_position.x > 50.0 and screen_position.y > 50.0 and screen_position.x < viewport_size.x-50.0 and screen_position.y < viewport_size.y-50.0, "full hero silhouette stays visible at arena edge")
	for actor in room.enemies.get_children():
		actor.free()
	room.spawn_enabled = false
	var destinations: Array = []
	for zone: Dictionary in room.encounter_zones:
		destinations.append(zone.center)
	destinations.append(room.exit_position)
	var at: Vector2 = room.layout.entry
	for destination: Vector2 in destinations:
		var iterations: int = 0
		while at.distance_to(destination) > 8.0 and iterations < 2000:
			var direction: Vector2 = room.navigation_direction(at, destination, Balance.PLAYER_RADIUS)
			var next: Vector2 = room.move_actor(at, direction * minf(11.0, at.distance_to(destination)), Balance.PLAYER_RADIUS)
			check(room.valid_ground(next, Balance.PLAYER_RADIUS), "route step remains on actual walkable ground")
			if next.distance_to(at) < .001:
				break
			at = next
			iterations += 1
		check(at.distance_to(destination) <= 8.0, "entry connects through encounter sectors and exit")
	var wall: Rect2 = room.obstructions[0]
	var left := Vector2(wall.position.x - 50, wall.get_center().y)
	var right := Vector2(wall.end.x + 50, wall.get_center().y)
	check(room.move_actor(left, right-left, 14).x < wall.position.x, "full-width movement cannot tunnel through cover")
	check(not room.has_line_of_sight(left,right), "cover blocks long-range damage visibility")
	room.player.position = Vector2(1600,900)
	room.player.aim_direction = Vector2.RIGHT
	var near: EnemyActor = room.spawn_enemy(Vector2(2200,900))
	var far: EnemyActor = room.spawn_enemy(Vector2(2350,900))
	check(room.player.fire(Vector2.RIGHT), "ranged attack exists in world coordinates")
	for i in range(40):
		for projectile in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():
				projectile._physics_process(.02)
	check(near.health.current < near.health.maximum, "650px gun hits 600px target after camera resize")
	check(far.health.current == far.health.maximum, "gun does not reach 750px target after camera resize")
	for actor in room.enemies.get_children():
		actor.free()
	room.activated_encounters.clear()
	room.encounter_progress.clear()
	for index in room.encounter_zones.size():
		room.player.position = room.encounter_zones[index].center
		room._update_encounters()
		var expected: Array = EnemyProfiles.encounter(room.layout_id,index,room.difficulty)
		check(not expected.is_empty() and room.enemies.get_child_count() == expected.size() and expected.size() <= 6, "exploring a different sector spawns its exact budgeted catalog encounter")
		var threat: float = 0.0
		for actor in room.enemies.get_children():
			threat += actor.threat_cost
			check(room.valid_ground(actor.position,actor.navigation_radius), "authored encounter body fits actual navigation radius")
		check(threat <= float(expected[0].encounter_budget), "catalog encounter respects its region threat budget")
		for actor in room.enemies.get_children():
			actor.free()
		while int(room.encounter_progress[index].next_wave) < room.encounter_progress[index].plan.waves.size():
			room._update_encounters(3.01)
			for actor in room.enemies.get_children():
				actor.free()
	room.spawn_enabled = true
	room._physics_process(.01)
	check(room.objective_complete, "all three cleared sectors complete the room")
	check(room.navigation_target().kind == "extract", "completion points navigation to real exit")
	room.player.position = room.exit_position
	check(room.nearby_interaction().get("kind", "") == "extract", "large-map extraction uses new world exit")
	room.player.position = Vector2(992,600)
	room.relic_positions["ember"] = Vector2(1038,600)
	room.obstructions.assign([Rect2(1010,570,10,60)])
	Game.run.relics.clear()
	check(room.nearby_interaction().is_empty(), "nearby station is not focused through an actual wall")
	room.interact()
	check(not Game.run.relics.has("ember"), "E cannot pick up a relic through a wall")
	room.obstructions.clear()
	check(room.nearby_interaction().get("id", "") == "ember", "removing obstruction reveals nearby actionable station")
	room.interact()
	check(Game.run.relics.has("ember") and room.nearby_interaction().is_empty(), "completed station loses actionable focus after successful pickup")
	# Synchronous fire/hit checks can leave playback cleanup pending until the
	# next mixer tick. Observe its completion before freeing the room and quitting.
	check(await room.combat_audio.wait_for_cleanup(), "stopped combat playbacks release before immediate test shutdown")
	room.free()
	print("WORLD CAMERA ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
