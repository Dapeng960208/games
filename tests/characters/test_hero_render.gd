extends Node
## Production main/HUD/camera and actual mapped input. Run with -Graphical.
## Uses isolated profile only; screenshots are engine frames, never mockups.

const Visual = preload("res://scripts/presentation/characters/hero_visual.gd")
var app: Node
var room: RoomController
var render_viewport: SubViewport
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func frames(count: int = 2) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func key_input(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = render_viewport.get_mouse_position()
	event.global_position = event.position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func aim_world(at: Vector2) -> void:
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frames(1)
	var canvas_at: Vector2 = render_viewport.get_canvas_transform() * room.to_global(at)
	var event := InputEventMouseMotion.new()
	event.position = canvas_at
	event.global_position = canvas_at
	# Push a viewport-local event after the frame boundary. Warping the desktop
	# cursor is unrelated to this isolated test window and is overwritten by OS
	# motion when another game window has focus.
	render_viewport.push_input(event, true)
	check(room.player.get_global_mouse_position().distance_to(room.to_global(at)) < .1,
		"viewport mouse event maps to the requested world target")

func clear_actors() -> void:
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	for projectile: Node in room.projectiles.get_children():
		projectile.free()
	room.effects.clear()
	room.gold_drops.clear()

func open_stage() -> Vector2:
	var candidates: Array[Vector2] = [Vector2(1500,1160),Vector2(1500,1050),Vector2(1450,1260),Vector2(1250,1200),Vector2(1700,1150)]
	for y in range(800,1401,100):
		for x in range(900,1901,100):
			candidates.append(Vector2(x,y))
	for candidate: Vector2 in candidates:
		if room.valid_ground(candidate,Balance.PLAYER_RADIUS) and room.blocked_fraction(candidate,candidate+Vector2(290,0),Balance.PLAYER_RADIUS) >= 1.0 and room.blocked_fraction(candidate,candidate+Vector2(0,80),Balance.PLAYER_RADIUS) >= 1.0:
			return candidate
	return Vector2.ZERO

func wall_probe() -> bool:
	for wall: Rect2 in room.obstructions:
		var at := Vector2(wall.position.x-Balance.PLAYER_RADIUS-4.0,wall.get_center().y)
		if not room.valid_ground(at,Balance.PLAYER_RADIUS):
			continue
		room.player.position = at
		room.player.knockback = Vector2.ZERO
		room.release_gate = false
		room.input_blocked = false
		key_input(KEY_D,true)
		room.player._physics_process(0.75)
		key_input(KEY_D,false)
		return room.valid_ground(room.player.position,Balance.PLAYER_RADIUS) and room.player.position.x <= wall.position.x-Balance.PLAYER_RADIUS+0.01 and room.player.position.x > at.x+1.0
	return false

func run_checks() -> void:
	if not Game.profile_path.contains("test_hero_render"):
		push_error("Refusing non-test profile; require --test-profile containing test_hero_render")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Hero render acceptance requires -Graphical to capture the real renderer")
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated render profile created")
	Input.use_accumulated_input = false
	# Keep production camera, HUD and event conversion in an actual rendered
	# viewport without relying on the desktop pointer of the user's Demo window.
	render_viewport = SubViewport.new()
	render_viewport.size = Vector2i(1280,720)
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(render_viewport)
	var display := TextureRect.new()
	display.texture = render_viewport.get_texture()
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	render_viewport.add_child(app)
	await frames(3)
	for hero: String in ["CH01","CH02","CH03"]:
		check(Game.select_hero(hero),hero+" selected through production profile API")
		check(Game.start_run(),hero+" starts through production run API")
		room = app.room
		room.process_mode = Node.PROCESS_MODE_DISABLED
		room.spawn_enabled = false
		room.release_gate = false
		room.input_blocked = false
		clear_actors()
		await frames(2)
		check(app.route == "run" and is_instance_valid(app.hud),hero+" uses production combat route and HUD")
		check(room.player.hero_id() == hero and Game.run.level == 1,hero+" renders its actual unmodified level-one character")
		var source: String = Visual.asset_path(hero)
		var bounds: Rect2 = Visual.asset_bounds(hero)
		check(not source.is_empty() and FileAccess.file_exists(AssetCatalog.resolve(source)),hero+" has an existing generated art source")
		var combat_source: String = "asset://heroes/"+hero+"_combat_v1.png"
		var action: Dictionary = Visual.action_frame_info(hero)
		if not action.is_empty():
			check(source.ends_with("actions_front_v2.png"),hero+" prefers authored action atlas over static fallback")
			check(action.anchors.foot == Vector2(0,8) and is_equal_approx(float(action.body_height),88.0),hero+" action bank keeps fixed body scale and ground contact")
			for bank: String in ["front","back"]:
				var regions: Array = []
				for phase: String in ["idle","windup","release","recovery"]:
					var frame: Dictionary = Visual.action_frame_info(hero,bank,phase)
					check(not frame.is_empty() and not regions.has(frame.get("region",Rect2())),hero+" "+bank+" "+phase+" samples a distinct authored pose")
					regions.append(frame.get("region",Rect2()))
		else:
			check(not FileAccess.file_exists(AssetCatalog.resolve(combat_source)) or source == combat_source,hero+" prefers its dedicated combat asset over portrait fallback")
			check(is_equal_approx(bounds.size.y,88.0) and is_equal_approx(bounds.end.y,8.0),hero+" generated draw bounds keep 88-unit body height and eight-unit foot anchor")
		check(is_equal_approx(room.camera.zoom.y,0.85),hero+" camera retains actual combat scale with atlas replacement")
		var stage: Vector2 = open_stage()
		check(not stage.is_zero_approx(),hero+" has a verified open production floor for movement and attack")
		room.player.position = stage
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await aim_world(stage+Vector2(260,0))
		key_input(KEY_D,true)
		check(Input.is_action_pressed("move_right"),hero+" physical D input resolves through production mapping")
		room.player._physics_process(0.2)
		key_input(KEY_D,false)
		check(room.player.position.x > stage.x+30.0 and room.valid_ground(room.player.position,Balance.PLAYER_RADIUS),hero+" generated character still moves through real controls")
		room.player.position = stage
		await aim_world(stage+Vector2(80,0))
		room.player._physics_process(0.001)
		check(room.player.aim_direction.dot(Vector2.RIGHT)>0.99,hero+" mouse input aims in world space under the camera")
		var target: EnemyActor = room.spawn_enemy(stage+Vector2(80,0))
		target.state = &"chase"
		target.health.reset(500.0)
		var before: float = target.health.current
		var shots: int = Game.run.shots
		mouse_button(true)
		room.player._physics_process(0.01)
		mouse_button(false)
		check(Game.run.shots == shots+1,hero+" real left mouse input starts one basic attack")
		if hero != "CH01":
			check(room.projectiles.get_child_count()>0,hero+" still launches its real projectile with generated art")
		room.player._physics_process(0.12)
		for projectile: Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():
				projectile._physics_process(0.25)
		check(target.health.current < before,hero+" real basic attack damages the target")
		check(wall_probe(),hero+" sprite replacement preserves physical wall collision")
		room.player.position = stage
		room.player.knockback = Vector2.ZERO
		room.player._physics_process(0.75)
		room.player.velocity = Vector2.ZERO
		target.position = stage+Vector2(210,0)
		room.effects.clear()
		await aim_world(stage+Vector2(260,0))
		room.player._physics_process(0.001)
		room.player.queue_redraw()
		room.queue_redraw()
		await capture(hero,bounds,source)
		if hero == "CH03":
			for id: String in ["burn", "shock", "chill", "corrosion"]:
				target.apply_status(id,0.0,3.0)
			target.hurt_flash = 0.0
			target.queue_redraw()
			await capture(hero,bounds,source,"states")
		var result: Dictionary = Game.finish_run("extracted")
		check(not result.is_empty() and Game.run == null,hero+" settles through production finish API")
		await frames(3)
	print("HERO RENDER ACCEPTANCE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func capture(hero: String, bounds: Rect2, source: String, suffix: String = "generated") -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var visible: Image = render_viewport.get_texture().get_image()
	check(str(room.player.get_meta("hero_visual_source","")) == source,hero+" actual draw path consumed the selected generated asset")
	check(not visible.is_empty() and visible.get_width() >= 1280 and visible.get_height() >= 720,hero+" produced a complete production frame")
	var path: String = "res://artifacts/combat_"+hero+"_"+suffix+".png"
	check(visible.save_png(path) == OK,hero+" saved actual rendered screenshot")
	var transform: Transform2D = room.player.get_global_transform_with_canvas()
	var first: Vector2 = transform * bounds.position
	var last: Vector2 = transform * bounds.end
	var rectangle := Rect2(first,last-first).abs().grow(3.0)
	room.player.hide()
	await frames(2)
	await RenderingServer.frame_post_draw
	var background: Image = render_viewport.get_texture().get_image()
	room.player.show()
	var changed: int = 0
	for y in range(maxi(0,int(rectangle.position.y)),mini(visible.get_height(),int(ceil(rectangle.end.y)))):
		for x in range(maxi(0,int(rectangle.position.x)),mini(visible.get_width(),int(ceil(rectangle.end.x)))):
			var a: Color = visible.get_pixel(x,y)
			var b: Color = background.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.04:
				changed += 1
	check(changed>150,hero+" visibly draws generated character pixels inside its world-space bounds")
