extends Node
## Official local Viewport input, independent of a native OS cursor.
## No gameplay actor/health/resource/timing mutations and no direct aim writes.

var checks := 0
var failures := 0
var stage: SubViewport
var presentation: TextureRect
var app: Node
var samples: Array[Dictionary] = []
var input_count := 0

class InputWitness extends Node2D:
	var observed := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion: observed += 1

func _ready() -> void:
	call_deferred("run_probe")

func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("POINTER_PROBE FAIL: "+label)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func mouse_event(viewport_point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = viewport_point
	event.global_position = viewport_point
	stage.push_input(event,true)

func sample_coordinate(witness: Node2D, world_point: Vector2, label: String) -> void:
	var viewport_point: Vector2 = witness.get_canvas_transform()*world_point
	var before: int = witness.observed
	mouse_event(viewport_point)
	check(witness.observed == before+1,label+" travels through Node._input")
	check(stage.get_mouse_position().distance_to(viewport_point)<.001,label+" updates Viewport local cursor cache")
	check(witness.get_global_mouse_position().distance_to(world_point)<.001,label+" engine CanvasItem world mouse agrees")
	await frames(1)
	check(witness.get_global_mouse_position().distance_to(world_point)<.001,label+" local mouse persists across live physics")
	samples.append({"phase":"coordinate","label":label,"world_requested":[world_point.x,world_point.y],
		"viewport_point":[viewport_point.x,viewport_point.y],"actual_world":[witness.get_global_mouse_position().x,witness.get_global_mouse_position().y],"input_callbacks":witness.observed})

func run_probe() -> void:
	if not Game.profile_path.contains("test_pointer_probe"):
		get_tree().quit(2)
		return
	get_tree().create_timer(35.0).timeout.connect(func(): push_error("Pointer probe timed out"); get_tree().quit(1))
	AudioServer.set_bus_mute(0,true)
	get_viewport().size = Vector2i(1280,720)
	stage = SubViewport.new()
	stage.name = "OfficialLocalInputViewport"
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	# Deliberately not parented to SubViewportContainer: that joins native Window
	# input coordinates. A TextureRect only presents the real rendered texture.
	add_child(stage)
	presentation = TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280,720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	var witness := InputWitness.new()
	stage.add_child(witness)
	for transform: Transform2D in [Transform2D.IDENTITY,Transform2D(Vector2(.85,0),Vector2(0,.85),Vector2(54.4,-405))]:
		stage.canvas_transform = transform
		for point: Vector2 in [Vector2(160,530),Vector2(500,530),Vector2(160,870),Vector2(500,870)]:
			await sample_coordinate(witness,point,"sample "+str(samples.size()))
	witness.free()
	stage.canvas_transform = Transform2D.IDENTITY
	check(Game.new_profile() and Game.select_hero("CH01"),"ordinary isolated CH01 profile")
	app = load("res://scenes/main.tscn").instantiate()
	stage.add_child(app)
	await frames(2)
	check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":41827}),"real ordinary expedition starts")
	await frames(2)
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers",[]):
		if str(offer.get("decision","")).is_empty(): app._choose_expedition_relic(str(offer.offer_id),"skip")
	app._clear_modals()
	var options: Array = app.expedition.next_options()
	check(not options.is_empty(),"first real room available")
	if options.is_empty(): get_tree().quit(1); return
	app._advance_expedition(str(options[0]))
	app._clear_modals()
	await frames(2)
	check(Game.run.level == 1 and not Game.run.demo,"Lv1 without trial boosts")
	var initial_stats: Dictionary = Game.run.stats.duplicate(true)
	var initial_elapsed: float = app.room.elapsed
	for offset: Vector2 in [Vector2(-50,-35),Vector2(70,-35),Vector2(-50,40),Vector2(70,40)]:
		var room: Node2D = app.room
		var requested: Vector2 = room.player.global_position+offset
		var viewport_point: Vector2 = room.get_canvas_transform()*requested
		mouse_event(viewport_point)
		check(room.player.get_global_mouse_position().distance_to(requested)<.001,"production player gets event target through CanvasItem API")
		await frames(2)
		var actual: Vector2 = room.player.get_global_mouse_position()
		var expected: Vector2 = room.player.global_position.direction_to(actual)
		var dot: float = room.player.aim_direction.dot(expected)
		check(dot>.98,"production live physics reads local pointer and changes aim")
		samples.append({"phase":"production","requested_world":[requested.x,requested.y],
			"actual_world":[actual.x,actual.y],"target_error":actual.distance_to(requested),
			"aim_direction":[room.player.aim_direction.x,room.player.aim_direction.y],"aim_dot":dot,
			"room_elapsed":room.elapsed,"hp":Game.run.hp})
	check(app.room.elapsed>initial_elapsed,"real room simulation continued during pointer probe")
	check(Game.run.stats==initial_stats,"production resolved stats unchanged")
	await app.room.combat_audio.wait_for_cleanup()
	Game.finish_run("abandoned")
	await frames(2)
	app.set_process(false)
	await app.music.wait_for_cleanup()
	app.free()
	await frames(2)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var mode: String = "headless" if DisplayServer.get_name()=="headless" else "graphical"
	var output := FileAccess.open("res://artifacts/pointer_probe_"+mode+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"method":"Official standalone SubViewport.push_input local event path; production CanvasItem mouse read and live player physics. Does not certify native OS cursor access.","checks":checks,"failures":failures,"samples":samples},"\t"))
	output.close()
	print("POINTER_PROBE_RESULT checks=",checks," failures=",failures," report=artifacts/pointer_probe_",mode,".json")
	get_tree().quit(0 if failures==0 else 1)
