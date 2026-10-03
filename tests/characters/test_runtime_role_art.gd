extends "res://tests/ui/test_role_natural_ui.gd"
## Runs only after all three complete production families are admitted. The
## gallery samples registered source poses; live observations use native inputs.
## No resource, cooldown, HP, position, damage or completion state is injected.
const SharedArt = preload("res://scripts/presentation/characters/hero_shared_action_family.gd")
var autoplay := false
var observed_frames: Dictionary = {}
var observed_art_releases: Dictionary = {}
var observed_art_projectiles: Dictionary = {}

class FamilyGallery extends Control:
	var family: Dictionary
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("f9f2e0"))
		var font: Font = ThemeDB.fallback_font
		draw_string(font,Vector2(24,28),str(family.hero_id)+" - registered production family: 8 views / 8 shared body poses",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("24384a"))
		for direction_index: int in SharedArt.DIRECTIONS.size():
			var key: String = SharedArt.DIRECTIONS[direction_index]
			draw_string(font,Vector2(113+direction_index*138,56),key,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("24384a"))
			for pose_index: int in SharedArt.POSES.size():
				var pose_name: String = SharedArt.POSES[pose_index]
				if direction_index == 0: draw_string(font,Vector2(5,104+pose_index*75),pose_name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("24384a"))
				var frame: Dictionary = family.directions[key][pose_name]
				draw_set_transform(Vector2(141+direction_index*138,127+pose_index*75),0,Vector2.ONE*.50)
				draw_texture_rect_region(frame.texture,frame.bounds,frame.region)
				draw_set_transform(Vector2.ZERO)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100
	_run.call_deferred()
	get_tree().create_timer(300.0).timeout.connect(func(): push_error("Runtime role art timeout"); get_tree().quit(2))

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory: String = Game.profile_path.get_base_dir()+"/captures"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK,"isolated art screenshot directory")
	var pixels: Image = get_viewport().get_texture().get_image()
	if name_value.contains("-2k-"): check(pixels.get_size() == Vector2i(2560,1440),"actual 2560 by 1440 render pixels")
	check(pixels.save_png(directory+"/"+name_value+".png") == OK,"actual production art capture "+name_value)
	print("ROLE_ART_CAPTURE ",directory+"/"+name_value+".png window=",DisplayServer.window_get_size()," pixels=",pixels.get_size())

func _run() -> void:
	if not Game.profile_path.contains("test_runtime_role_art"): get_tree().quit(2); return
	check(DisplayServer.get_name() != "headless","actual art validation uses the graphical renderer")
	for hero: String in Catalog.HEROES:
		var family: Dictionary = SharedArt.load_family(hero)
		check(not family.is_empty(),hero+" complete registered family is admitted before live testing")
		if family.is_empty(): get_tree().quit(2); return
		for key: String in SharedArt.DIRECTIONS:
			for pose_name: String in SharedArt.POSES:
				var frame: Dictionary = family.directions[key][pose_name]
				check(frame.texture != null and frame.art_family == "shared_action" and str(frame.path).begins_with("asset://heroes/"+hero.to_lower()+"_poses_"+key.to_lower()+"_") and AssetCatalog.resolve(frame.path).ends_with(".png"),hero+" registered PNG identity "+key+"/"+pose_name)
	check(Game.new_profile(),"isolated actual-art profile")
	var setup: Dictionary = Game.profile.duplicate(true)
	setup.settings.auto_attack = false
	setup.settings.camera_shake = false
	check(Game._commit_profile(setup),"fixture input settings only; battle state remains native")
	app = MainScene.instantiate()
	get_tree().root.add_child(app)
	await frames()
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	get_window().position = usable.position+(usable.size-get_window().size)/2
	print("ROLE_ART_DISPLAY screen=",DisplayServer.screen_get_size()," usable=",usable," gameplay_window=",get_window().size)
	for hero: String in Catalog.HEROES:
		await configure(hero,0)
		await _gallery(hero)
		await _live_art(hero)
		if Game.run != null: check(not Game.finish_run("abandoned").is_empty(),hero+" explicitly abandons the art probe; no completion claim")
		await frames()
	var result := {"checks":checks,"failures":failures,"roles":rows,"method":"registered production gallery plus automated native inputs; no human feel or 36-damage-matrix claim"}
	var output := FileAccess.open(Game.profile_path.get_base_dir()+"/runtime_role_art.json",FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(result,"\t")); output.close()
	print("RUNTIME_ROLE_ART_RESULT ",JSON.stringify(result))
	app.queue_free()
	await frames()
	get_tree().quit(0 if failures.is_empty() else 1)

func _gallery(hero: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var gallery := FamilyGallery.new()
	gallery.family = SharedArt.load_family(hero)
	gallery.size = Vector2(1280,720)
	layer.add_child(gallery)
	add_child(layer)
	await frames()
	await capture(hero+"-source-gallery")
	DisplayServer.window_set_size(Vector2i(2560,1440))
	await frames(4)
	await capture(hero+"-2k-source-gallery")
	DisplayServer.window_set_size(Vector2i(1280,720))
	get_window().position = DisplayServer.screen_get_usable_rect().position+(DisplayServer.screen_get_usable_rect().size-get_window().size)/2
	layer.queue_free()
	await frames()

func _wait_native(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0 and Game.run != null:
		await get_tree().physics_frame
		remaining -= 1.0/60.0

func _live_art(hero: String) -> void:
	app._start_run()
	await frames()
	if app.find_child("ConfirmWishDeparture",true,false) != null: check(await click("ConfirmWishDeparture"),"actual departure confirmation")
	await dismiss_offers()
	check(Game.run != null and is_instance_valid(app.room) and app.modals.is_empty(),hero+" real Main creates an unobstructed entrance")
	if Game.run == null or not is_instance_valid(app.room): return
	row = {"hero":hero,"poses":{},"directions":{},"source_paths":{},"frames":[],"guard_release":false,"reload_observed":false,"primary_projectiles":0,"muzzle_samples":[]}
	observed_frames.clear()
	observed_art_releases.clear()
	observed_art_projectiles.clear()
	elapsed = 0.0
	driver = Driver.new()
	driver.configure(app.room)
	active = true
	autoplay = false
	for index: int in 8:
		var direction := Vector2.from_angle(index*PI/4.0)
		driver.aim(app.room.player.position+direction*100.0)
		await frames(3)
		while app.room.player.shot_cooldown > 0.0 or app.room.player.abilities.busy(): await _wait_native(.05)
		check(app.room.player.request_attack(direction),hero+" native primary input accepted for "+SharedArt.DIRECTIONS[index])
		await _wait_native(.85)
	await _wait_native(1.2)
	var player: HeroActor = app.room.player
	var primary_serial: int = player._primary_serial
	var primary_projectiles: int = int(row.primary_projectiles)
	await _wait_native(.6)
	check(player._primary_serial == primary_serial and int(row.primary_projectiles) == primary_projectiles,hero+" released inputs produce no extra autonomous primary cycle")
	if hero in ["CH02","CH03"]: check(primary_projectiles == 8,hero+" eight accepted native basic inputs create exactly eight original projectiles")
	for heading: String in SharedArt.DIRECTIONS: check(row.directions.has(heading),hero+" actual actor renders authored heading "+heading)
	var destination: Vector2 = player.position+Vector2(130,0)
	check(app.room.valid_ground(destination,Balance.PLAYER_RADIUS) and player.request_move(destination,false),hero+" native navigation starts within the entrance")
	await _wait_native(1.6)
	player.clear_movement_target()
	driver.aim(player.position+Vector2(100,0))
	await frames(3)
	check(player.start_dash(Vector2.RIGHT),hero+" native dash input accepted")
	await _wait_native(.5)
	await capture(hero+"-live-entrance")
	check(await advance(),hero+" actual route UI enters native combat for the guard pose")
	if Game.run != null and is_instance_valid(app.room):
		driver.configure(app.room)
		driver.coverage = {}
		for identity: String in Game.run.skill_loadout_snapshot: driver.coverage[identity] = false
		autoplay = true
		var remaining := 60.0
		while remaining > 0.0 and Game.run != null and Game.run.hp > 0.0 and not (bool(row.guard_release) and row.poses.has("guard_cast")):
			await _wait_native(.1)
			remaining -= .1
		autoplay = false
		await capture(hero+"-live-combat")
	active = false
	for pose_name: String in ["walk_left","walk_right","basic_windup","basic_release","basic_recovery","dash","guard_cast"]: check(row.poses.has(pose_name),hero+" actual native action rendered "+pose_name)
	check(bool(row.guard_release),hero+" actual guard-class skill reached a production release")
	if hero == "CH02": check(bool(row.reload_observed),"gunner native eight-shot magazine renders its own reload pose")
	if hero == "CH03": check(is_instance_valid(app.room) and is_instance_valid(app.room.player) and app.room.player.find_children("StarCompanion","Node2D",true,false).size() == 1,"mage has one live companion; its body never falls back to the old engineer")
	rows.append(row.duplicate(true))

func _physics_process(delta: float) -> void:
	if not active or Game.run == null or not is_instance_valid(app.room): return
	elapsed += delta
	var player: HeroActor = app.room.player
	if not is_instance_valid(player): return
	if autoplay: driver.step(elapsed)
	for projectile: Node in app.room.projectiles.get_children():
		if not projectile.has_method("visual_path_snapshot") or str(projectile.get("source")) != "primary" or observed_art_projectiles.has(projectile.get_instance_id()): continue
		observed_art_projectiles[projectile.get_instance_id()] = true
		row.primary_projectiles += 1
		var path: Dictionary = projectile.visual_path_snapshot()
		if row.muzzle_samples.size() < 8 and not path.is_empty(): row.muzzle_samples.append({"t":elapsed,"origin":str(path.get("origin",Vector2.ZERO)),"visual_start":str(path.get("knots",[{}])[0].get("point",Vector2.ZERO)),"direction":str(projectile.direction),"hero_body_muzzle":str(player.get_meta("hero_muzzle_local",Vector2.ZERO))})
	if Game.run.hero_id == "CH02" and bool(player.class_state_view().get("reloading",false)): row.reload_observed = true
	for event: Dictionary in player.abilities.feedback.release_events:
		var key: String = str(event.serial)+":"+str(event.index)
		if observed_art_releases.has(key): continue
		observed_art_releases[key] = true
		var identity: String = str(event.skill_id)
		if driver.coverage.has(identity): driver.coverage[identity] = true
		if identity == Game.run.hero_id+"_SK03": row.guard_release = true

func _process(_delta: float) -> void:
	if not active or Game.run == null or not is_instance_valid(app.room): return
	var player: HeroActor = app.room.player
	if not is_instance_valid(player): return
	var source: String = str(player.get_meta("hero_visual_source",""))
	var index: int = int(player.get_meta("hero_visual_frame",-1))
	var heading: String = str(player.get_meta("hero_directional_key",""))
	if source.is_empty() or index < 0: return
	var key: String = str(player.get_instance_id())+":"+source+":"+str(index)
	if observed_frames.has(key): return
	observed_frames[key] = true
	check(source.begins_with("asset://heroes/"+Game.run.hero_id.to_lower()+"_poses_") and SharedArt.DIRECTIONS.has(heading),Game.run.hero_id+" actual drawn body uses only its complete new PNG family")
	var transform: Transform2D = player.get_meta("hero_body_transform",Transform2D.IDENTITY)
	check(float(player.get_meta("hero_visual_flip",0.0)) == 1.0 and transform.x.is_equal_approx(Vector2.RIGHT) and transform.y.is_equal_approx(Vector2.DOWN) and Vector2(player.get_meta("hero_foot_local",Vector2.INF)).is_equal_approx(Vector2(0,8)),Game.run.hero_id+" actual drawn body has no mirroring, rotation or foot drift")
	var pose_name: String = SharedArt.POSES[posmod(index,8)]
	row.poses[pose_name] = true
	row.directions[heading] = true
	row.source_paths[source] = true
	row.frames.append({"t":elapsed,"source":source,"frame":index,"heading":heading,"pose":pose_name,"muzzle":str(player.get_meta("hero_muzzle_local",Vector2.ZERO)),"foot":str(player.get_meta("hero_foot_local",Vector2.ZERO))})
