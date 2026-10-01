extends Node
## Real room/brain snapshots and runtime collision. Drawing pixels is a separate
## native GPU review; no fake phases are used to claim real attack timing.
const RoomScene = preload("res://scenes/room.tscn")
const Layer = preload("res://scripts/combat/enemy_telegraphs.gd")
const Boss = preload("res://scripts/combat/boss.gd")
var room: MineRoom
var checks := 0
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ENEMY TELEGRAPHS FAIL: " + label)

func fixture() -> void:
	get_tree().paused = false
	if is_instance_valid(room): room.free()
	Game.run.hero_id = "CH01"
	Game.run.level = 8
	Game.run.stats = StatResolver.resolve("CH01",8,{}, {})
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	room.combat_audio.audible = false
	room.enemy_telegraphs.set_process(false)
	room.obstructions.clear()
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(1100,800)

func enemy(id: String, level: int = 15) -> MineEnemy:
	var actor: MineEnemy = room.spawn_enemy(Vector2(1000,800),id,level)
	check(is_instance_valid(actor), id+" real enemy spawns")
	return actor

func wait_phase(actor: MineEnemy, desired: StringName, limit: int = 650) -> Dictionary:
	for step in limit:
		if actor.state == desired:
			room.enemy_telegraphs.refresh()
			return actor.brain.current_telegraph()
		actor._physics_process(.01)
	check(false, actor.enemy_id+" reaches real "+str(desired))
	return {}

func displayed(actor: MineEnemy) -> Dictionary:
	for entry: Dictionary in room.enemy_telegraphs.snapshot():
		if int(entry.actor_id) == actor.get_instance_id(): return entry.data
	return {}

func geometry(data: Dictionary) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	for key: String in ["progress","release_progress","lock_fraction","duration","locked","phase"]:
		copy.erase(key)
	return copy

func check_layer_and_timing() -> void:
	fixture()
	var actor: MineEnemy = enemy("M01")
	check(room.enemy_telegraphs.z_index==5 and room.enemy_telegraphs.z_index>room.impact_feedback.z_index and room.enemy_telegraphs.z_index>room.enemy_skills.z_index and room.enemy_telegraphs.z_index>actor.z_index, "dedicated tell layer is above actor, contact and released skill layers")
	room.enemy_telegraphs.refresh()
	check(room.enemy_telegraphs.snapshot().is_empty(), "emerging actors have no fake attack tells")
	wait_phase(actor,&"telegraph")
	var previous := -1.0
	var saw_lock := false
	for step in 200:
		var original: Dictionary = actor.brain.current_telegraph()
		if original.is_empty(): break
		room.enemy_telegraphs.refresh()
		var data: Dictionary = displayed(actor)
		var progress: float = float(data.release_progress)
		check(progress+0.00001>=previous, "real windup→lock progress never resets")
		check(geometry(data)==geometry(original) and actor.brain.current_telegraph()==original, "drawing snapshot cannot alter attack geometry or phase clock")
		check(progress<1.0, "progress remains unfinished until real release")
		if bool(data.locked):
			saw_lock = true
			check(progress>=float(data.lock_fraction), "locked tells start beyond the visible lock tick")
		previous = progress
		var revision: int = room.enemy_telegraphs.redraw_revision
		check(not room.enemy_telegraphs.refresh() and room.enemy_telegraphs.redraw_revision==revision, "unchanged data does not request a duplicate redraw")
		actor._physics_process(.01)
	room.enemy_telegraphs.refresh()
	check(saw_lock and previous>.95 and displayed(actor).is_empty(), "one continuous countdown reaches release and clears without lingering")
	for reduced in [false,true]:
		var tracking: Dictionary = Layer.palette(false,reduced)
		var locked: Dictionary = Layer.palette(true,reduced)
		check(tracking.edge!=locked.edge and locked.width>tracking.width, "tracking and locked differ by color and edge weight including reduced FX")
		check(tracking.fill_alpha<=.055 and locked.fill_alpha<=.055 and locked.ink.a>.8, "subtle translucent fill and dark outline avoid opaque danger blocks")
	var source := {"telegraph_seconds":.8,"locked_seconds":.4,"progress":1.0,"locked":false}
	var end_tracking: Dictionary = Layer.presentation_data(source)
	source.locked = true
	source.progress = 0.0
	check(is_equal_approx(end_tracking.release_progress,Layer.presentation_data(source).release_progress), "exact phase transition joins at the same fraction")
	source.progress = 1.0
	check(Layer.presentation_data(source).release_progress==1.0, "exact release endpoint reaches one")

func check_geometry_and_transform() -> void:
	for id: String in ["M31","M36","M05","M21","M33"]:
		fixture()
		var actor: MineEnemy = enemy(id)
		var locked: Dictionary = wait_phase(actor,&"locked")
		if locked.is_empty(): continue
		var shown: Dictionary = displayed(actor)
		check(geometry(shown)==geometry(locked),id+" layer retains complete frozen geometry")
		if id=="M31":
			check(shown.paths.size()==3 and shown.points.size()==3,"refraction still warns three complete bent rays")
		elif id=="M36":
			check(is_equal_approx(float(shown.ring_end)-float(shown.ring_start),TAU-deg_to_rad(50.0)),"ring's 50-degree escape gap survives")
			var safe: Vector2 = shown.origin + shown.direction*float(shown.radius)*.65
			check(not room.enemy_skills.shape_contains(shown,safe,0.0),"displayed escape gap matches real runtime's safe region")
		elif id=="M05":
			check(shown.points.size()==17,"arc roll remains a seventeen-point curve")
		elif id=="M21":
			check(shown.landing_shape=="ring" and shown.points.size()==17,"jump keeps both curved travel and landing ring")
		elif id=="M33":
			check((shown.origin as Vector2).distance_to(actor.position)>1,"offset line keeps its authored shifted origin")
		room.player.position += Vector2(0,170)
		actor._physics_process(.01)
		room.enemy_telegraphs.refresh()
		check(geometry(displayed(actor))==geometry(locked),id+" moving target cannot rotate a locked tell")
		room.position = Vector2(350,-120)
		room.rotation = .31
		room.scale = Vector2(1.4,.7)
		room.enemy_telegraphs.position = Vector2(-33,54)
		room.enemy_telegraphs.rotation = -.2
		room.enemy_telegraphs.scale = Vector2(.8,1.3)
		room.enemy_telegraphs.refresh()
		var matrix: Transform2D = room.telegraph_canvas_transform(room.enemy_telegraphs)
		for point: Vector2 in [shown.origin, shown.target, shown.origin+shown.direction*shown.range]:
			check((room.enemy_telegraphs.global_transform*(matrix*point)).distance_to(room.to_global(point))<.001,id+" room→layer transform keeps points and directions under rotation and nonuniform scale")
		var detached: Array[Dictionary] = room.enemy_telegraphs.snapshot()
		detached[0].data["origin"] = Vector2.ZERO
		check(displayed(actor).origin==locked.origin,"diagnostic snapshot edits never mutate stored tells")

func check_lifecycle_and_obstacles() -> void:
	fixture()
	var actor: MineEnemy = enemy("M05")
	wait_phase(actor,&"locked")
	actor.apply_knockback(Vector2.DOWN,250.0)
	actor._physics_process(.01)
	room.enemy_telegraphs.refresh()
	check(actor.state==&"recovery" and displayed(actor).is_empty(),"real knockback cancellation removes the frozen charge warning")
	fixture()
	actor = enemy("M31")
	var locked: Dictionary = wait_phase(actor,&"locked")
	var paths: Array = locked.paths
	var ray: Array = paths[1]
	var wall_at: Vector2 = (ray[0] as Vector2).lerp(ray[1],.35)
	room.obstructions.assign([Rect2(wall_at-Vector2(9,120),Vector2(18,240))])
	room.enemy_telegraphs.refresh()
	check(geometry(displayed(actor))==geometry(locked),"dynamic wall does not rewrite the frozen attack snapshot")
	check(room.blocked_fraction(ray[0],ray[1],float(locked.radius))<1,"real dynamic wall blocks the underlying shot path")
	# This layer does not introduce warning-path clipping; collision is still
	# resolved against live walls by the unchanged EnemySkillRuntime.
	var hp: float = Game.run.hp
	room.enemy_skills.emit_skill(actor,locked)
	for step in 100: room.enemy_skills.advance(.02)
	check(is_equal_approx(Game.run.hp,hp) and room.enemy_skills.projectiles.is_empty(),"real released projectiles terminate at the newly added wall without damage")
	actor.queue_free()
	room.enemy_telegraphs.refresh()
	check(room.enemy_telegraphs.snapshot().is_empty(),"queued deletion removes tell before node is freed")
	fixture()
	actor = enemy("M36")
	wait_phase(actor,&"locked")
	actor.free()
	room.enemy_telegraphs.refresh()
	check(room.enemy_telegraphs.snapshot().is_empty(),"freeing a caster cannot leave a dangling reference or warning")
	actor = enemy("M01")
	wait_phase(actor,&"telegraph")
	check(room.load_room_layout("L01",0,41827),"real room transition accepts generated layout")
	check(room.enemy_telegraphs.snapshot().is_empty(),"layout transition clears old warnings immediately")

func check_population_and_boss() -> void:
	fixture()
	# Inert objectives precede the combatants, reproducing L11's largest
	# population without scene-dependent objective gameplay side effects.
	for index in 23:
		var target: MineEnemy = room.EnemyScene.instantiate()
		target.room = room
		target.static_actor = true
		target.actor_kind = "objective"
		target.position = Vector2(300+index*30,400)
		room.enemies.add_child(target)
	for index in Balance.MAX_ENEMIES:
		var actor: MineEnemy = enemy("M01")
		wait_phase(actor,&"telegraph")
	room.enemy_telegraphs.refresh()
	check(room.enemies.get_child_count()==41 and room.enemy_telegraphs.snapshot().size()==18,"all eighteen actual threats survive twenty-three earlier inert objectives")
	check(room.spawn_enemy(Vector2(1500,800),"M01")==null,"room's existing live-enemy cap still bounds danger work")
	fixture()
	var boss: MineEnemy = Boss.new()
	boss.room = room
	boss.position = Vector2(1000,800)
	check(boss.configure_boss("BO04",0,41827),"real boss profile configures")
	room.enemies.add_child(boss)
	var locked: Dictionary = wait_phase(boss,&"locked")
	check(not locked.is_empty() and displayed(boss).boss_id=="BO04" and displayed(boss).release_progress>=displayed(boss).lock_fraction,"boss integer phase is collected once with its tell/lock timing")
	check(room.enemy_telegraphs.snapshot().size()==1,"boss contributes one warning through the shared inherited brain")
	for path: String in ["res://scripts/combat/enemy.gd","res://scripts/combat/boss.gd"]:
		check(not FileAccess.get_file_as_string(path).contains("room.draw_enemy_telegraph(self"),"actor renderer has no duplicate warning path: "+path)

func check_pause_and_reduced() -> void:
	fixture()
	var actor: MineEnemy = enemy("M36")
	wait_phase(actor,&"telegraph")
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	room.enemy_telegraphs.set_process(true)
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true
	var before: Dictionary = actor.brain.current_telegraph()
	room.enemy_telegraphs.refresh()
	var drawn: Array[Dictionary] = room.enemy_telegraphs.snapshot()
	var revision: int = room.enemy_telegraphs.redraw_revision
	for index in 4: await get_tree().physics_frame
	check(actor.brain.current_telegraph()==before and room.enemy_telegraphs.snapshot()==drawn and room.enemy_telegraphs.redraw_revision==revision,"actual SceneTree pause freezes AI, continuous progress and redraws")
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	check(actor.brain.current_telegraph()!=before,"resume continues the existing phase")
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.enemy_telegraphs.set_process(false)
	Game.profile.settings.reduced_fx = true
	room.enemy_telegraphs.refresh()
	check(room.enemy_telegraphs.snapshot().size()==1,"reduced FX preserves danger geometry and countdown")
	Game.profile.settings.reduced_fx = false

func run_checks() -> void:
	if not Game.profile_path.contains("test_enemy_telegraphs"):
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(),"isolated fixture starts")
	check_layer_and_timing()
	check_geometry_and_transform()
	check_lifecycle_and_obstacles()
	check_population_and_boss()
	await check_pause_and_reduced()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
	print("ENEMY TELEGRAPHS ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
