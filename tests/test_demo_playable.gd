extends Node
var viewport: SubViewport
var app: Node
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	call_deferred("_run")

func aim(at: Vector2) -> void:
	app.room.camera.follow_target()
	app.room.camera.force_update_scroll()
	await frames(1)
	var mouse := InputEventMouseMotion.new()
	mouse.position = viewport.get_canvas_transform()*app.room.to_global(at)
	viewport.push_input(mouse,true)
	await frames(1)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code,true)
	await frames(2)
	key(code,false)
	await frames(2)

func capture(hero: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	viewport.get_texture().get_image().save_png("res://artifacts/playable_"+hero+"_circuit.png")

func _run() -> void:
	if not Game.profile_path.contains("test_demo_playable"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated player profile created")
	var original: Dictionary = Game.profile.duplicate(true)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for hero: String in ["CH01","CH02","CH03"]:
		app = load("res://scenes/main.tscn").instantiate()
		viewport.add_child(app)
		await frames(3)
		app._start_demo(hero)
		await frames(3)
		app._clear_modals()
		await frames(3)
		check(Game.run != null and Game.run.demo and Game.run.hero_id == hero,hero+" enters actual trial")
		check(is_instance_valid(app.room.circuit_training),hero+" safe practice target exists")
		var hp: float = Game.run.hp
		var gold: int = Game.run.gold
		await aim(Vector2(1220,560))
		await tap(KEY_C)
		await frames(16)
		await aim(Vector2(1220,820))
		await tap(KEY_C)
		check(app.room.circuit.anchors.size()==2,hero+" physical C input places both world anchors")
		# Freeze actor locomotion only; the production trainer and enemy projectile
		# executor remain live and repeatedly emit harmless real shots at the hero.
		var deadline: int = Time.get_ticks_msec()+11000
		while app.room.circuit.charge < 3 and Time.get_ticks_msec()<deadline:
			await frames(10)
		check(app.room.circuit.charge == 3,hero+" three live training shots intercepted")
		check(is_equal_approx(Game.run.hp,hp),hero+" training shots cause no damage")
		await aim(Vector2(1280,650))
		await tap(KEY_Q)
		await frames(20)
		check(float(app.room.player.cooldowns.q)>0.0,hero+" Q via physical keyboard enters its real cooldown")
		var target_hp: float = app.room.circuit_training.target.health.current
		await tap(KEY_V)
		check(app.room.circuit.discharges==1 and app.room.circuit.charge==0,hero+" physical V releases stored energy")
		check(app.room.circuit_training.target.health.current < target_hp,hero+" real charged line blast damages the practice target")
		await capture(hero)
		check(Game.run.gold==gold,hero+" safe practice cannot create gold")
		await app.room.combat_audio.wait_for_cleanup()
		Game.finish_run("abandoned")
		await frames(3)
		check(Game.profile==original,hero+" leaves permanent progression untouched")
		app.set_process(false)
		await app.music.wait_for_cleanup()
		app.free()
		await frames(3)
	viewport.free()
	await frames(8)
	print("PLAYABLE DEMO: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
