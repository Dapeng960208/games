extends Node
## Native main/expedition/room integration for an enemy-freeze report. Only
## isolated profile unlocks, player survival and player positions are fixtures;
## room transitions, encounters, AI, attacks and pause use production paths.

const MainScene = preload("res://scenes/app/main.tscn")
var checks: int = 0
var failures: int = 0
var app: Node
var room: RoomController
var actors: Array[EnemyActor] = []
var samples: Array[Dictionary] = []
var result_path: String = ""

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ENEMY LIVE ROOM FAIL: " + label)
	else:
		print("PASS ", label)

func frames(count: int) -> void:
	for _index: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _record(phase: String) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for actor: EnemyActor in actors:
		if not is_instance_valid(actor):
			enemies.append({"valid":false})
			continue
		enemies.append({"valid":true,"id":actor.enemy_id,"level":actor.enemy_level,
			"can_process":actor.can_process(),"physics_processing":actor.is_physics_processing(),
			"lifetime":actor.lifetime,"brain_age":actor.brain.age if actor.brain != null else -1.0,
			"state":str(actor.state),"x":actor.position.x,"y":actor.position.y,
			"static_actor":actor.static_actor,"training_ai_disabled":actor.training_ai_disabled})
	var sample: Dictionary = {"phase":phase,"wall_ticks_ms":Time.get_ticks_msec(),
		"paused":get_tree().paused,"modals":app.modals.size(),"hp":Game.run.hp if Game.run != null else -1.0,
		"room_can_process":room.can_process(),"room_physics_processing":room.is_physics_processing(),
		"room_elapsed":room.elapsed,"player_can_process":room.player.can_process(),
		"player_physics_processing":room.player.is_physics_processing(),
		"player_combat_time":room.player.combat_time,"player_x":room.player.position.x,"player_y":room.player.position.y,
		"input_blocked":room.input_blocked,"release_gate":room.release_gate,"enemies":enemies}
	samples.append(sample)
	return sample

func _observe(phase: String) -> void:
	for _index: int in 12:
		await get_tree().create_timer(0.5).timeout
		_record(phase)

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_live_room"):
		get_tree().quit(2)
		return
	result_path = Game.profile_path.get_base_dir().path_join("enemy_live_room_state.json")
	get_tree().create_timer(60.0).timeout.connect(func(): push_error("ENEMY LIVE ROOM timeout"); get_tree().quit(1))
	check(Game.new_profile(), "fresh isolated profile")
	# B03 requires the two earlier boss clears. This is a profile fixture, never
	# a shortcut around the actual room or durable expedition entry transaction.
	Game.profile.bosses = ["BO01","BO02"]
	app = MainScene.instantiate()
	get_tree().root.add_child(app)
	await frames(2)
	app.selected_biome = "B03"
	app.selected_difficulty = 4
	app.show_camp()
	app._start_run()
	await frames(3)
	check(Game.run != null and app.route == "run" and app.expedition.active(), "real main starts B03 expedition")
	if Game.run == null or not is_instance_valid(app.room):
		await _finish()
		return
	check(not app.modals.is_empty() and app.modals[-1].get("required", false), "actual required entrance relic modal is paused")
	check(get_tree().paused, "entrance modal freezes the real world")
	for offer: Dictionary in app.expedition.snapshot().relic_offers:
		app._choose_expedition_relic(str(offer.offer_id), "skip")
		await frames(2)
	check(app.modals.is_empty() and not get_tree().paused, "actual relic choice clears modal and unpauses")
	check(app.expedition.next_options().has("L15"), "L15 is a legal first B03 route choice")
	app.show_expedition(false)
	check(get_tree().paused and not app.modals.is_empty(), "real route modal pauses before transition")
	var route_choice: Button = app.find_child("Choose_L15", true, false) as Button
	check(route_choice != null and not route_choice.disabled, "real route chart exposes enabled L15 control")
	if route_choice == null or route_choice.disabled:
		await _finish()
		return
	route_choice.pressed.emit()
	await frames(3)
	room = app.room
	check(room.layout_id == "L15" and app.expedition.current_index() == 1, "route control uses production advance and installs L15")
	check(app.modals.is_empty() and not get_tree().paused and room.controls_enabled(), "L15 transition restores real control")
	# Large survival HP lets native attacks continue for both observation windows.
	# AI timing, enemy profiles, hit logic, navigation and process modes remain live.
	Game.run.stats.max_hp = 10000.0
	Game.run.max_hp = 10000.0
	Game.run.hp = 10000.0
	room.player.position = room.encounter_zones[0].center
	await frames(4)
	var center := Vector2.ZERO
	for actor: Node in room.enemies.get_children():
		if actor is EnemyActor and actor.is_alive() and not actor.static_actor:
			actors.append(actor)
			center += actor.position
	check(actors.size() >= 4, "production L15 finite encounter creates a real crowd")
	if actors.is_empty():
		await _finish()
		return
	center /= actors.size()
	room.player.position = room.clamp_actor(center, Balance.PLAYER_RADIUS)
	room.player.clear_movement_target()
	var before: Dictionary = _record("before_native")
	await _observe("native")
	var after: Dictionary = _record("after_native")
	check(float(after.hp) < float(before.hp), "standing amid the real L15 crowd takes damage during six native seconds")
	check(room.can_process() and room.player.can_process(), "room and player can process after real transition")
	for index: int in actors.size():
		var actor: EnemyActor = actors[index]
		check(actor.can_process() and actor.is_physics_processing() and actor.brain.age-float(before.enemies[index].brain_age) >= 6.0,
			actor.enemy_id + " advances native AI throughout first observation")
		check(actor.enemy_level == 17 and not actor.training_ai_disabled and not actor.static_actor,
			actor.enemy_id + " is an active ordinary level-17 encounter actor")
	var map_key := InputEventAction.new()
	map_key.action = "expedition_map"
	map_key.pressed = true
	app._input(map_key)
	check(get_tree().paused and not app.modals.is_empty(), "M opens actual paused route chart during combat")
	var paused_before: Dictionary = _record("paused_before")
	await get_tree().create_timer(1.0).timeout
	var paused_after: Dictionary = _record("paused_after")
	check(is_equal_approx(float(paused_before.hp),float(paused_after.hp)) and is_equal_approx(float(paused_before.room_elapsed),float(paused_after.room_elapsed)),
		"real modal freezes damage and room clock")
	for index: int in actors.size():
		check(is_equal_approx(float(paused_before.enemies[index].brain_age),float(paused_after.enemies[index].brain_age)),
			actors[index].enemy_id + " AI clock freezes while M chart is open")
	app._pop_modal()
	await frames(2)
	check(not get_tree().paused and app.modals.is_empty() and room.controls_enabled(), "closing real M chart resumes world and controls")
	var resumed_before: Dictionary = _record("resumed_before")
	await _observe("resumed_native")
	var resumed_after: Dictionary = _record("resumed_after")
	check(float(resumed_after.hp) < float(resumed_before.hp), "same crowd inflicts real damage for six seconds after M closes")
	for index: int in actors.size():
		check(actors[index].can_process() and actors[index].brain.age-float(resumed_before.enemies[index].brain_age) >= 6.0,
			actors[index].enemy_id + " resumes native AI after actual modal close")
	var movement_start: Vector2 = room.player.position
	var accepted: bool = room.player.request_move(room.clamp_actor(movement_start+Vector2(80,0),Balance.PLAYER_RADIUS),false)
	await get_tree().create_timer(0.5).timeout
	room.player.clear_movement_target()
	check(accepted and room.player.position.distance_to(movement_start) > 5.0, "player accepts and executes real movement after modal resume")
	_record("after_movement")
	await _finish()

func _finish() -> void:
	var file := FileAccess.open(AssetCatalog.resolve(result_path), FileAccess.WRITE)
	check(file != null, "state evidence is writable beside the isolated profile")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples}, "\t"))
		file.close()
	if is_instance_valid(app):
		app._clear_modals()
		if is_instance_valid(app.room) and is_instance_valid(app.room.combat_audio):
			await app.room.combat_audio.wait_for_cleanup()
		app.set_process(false)
		if is_instance_valid(app.music):
			await app.music.wait_for_cleanup()
		app.free()
	print("ENEMY LIVE ROOM RESULT: %d checks, %d failures; state=%s" % [checks,failures,result_path])
	get_tree().quit(0 if failures == 0 else 1)
