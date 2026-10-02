extends Node
## Genuine GPU evidence from the production boss rooms, actors, HUD and warning
## layer. Only timing, locale and positions are controlled; no draw stubs.
## tools/test.ps1 -Suite boss_skill_ui -Graphical -SkipImport -SkipRestart

const RoomScene = preload("res://scenes/room.tscn")
const Fixed = preload("res://scripts/world/fixed_room_layouts.gd")
const Abilities = preload("res://scripts/combat/boss_ability_catalog.gd")
const Presentation = preload("res://scripts/combat/boss_skill_presentation.gd")
const OUTPUT := "res://artifacts/boss-skill-ui/"
const IDS := ["BO01", "BO02", "BO03", "BO04"]
var room: MineRoom
var hud: Control
var layer: CanvasLayer
var checks := 0
var failures := 0
var captures: Array[String] = []
var rendered: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(90.0).timeout.connect(func(): push_error("BOSS_SKILL_UI timeout"); get_tree().quit(1))
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS_SKILL_UI: "+description)

func frames(count: int = 2) -> void:
	for index: int in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func install(id: String, difficulty: int, locale: String = "zh_CN") -> MineBoss:
	Words.set_locale(locale)
	var prepared := room.prepare_expedition_node({"room_id":id, "role":"boss", "biome_id":Fixed.blueprint(id).biome_id, "node_index":6, "node_count":7, "difficulty":difficulty, "seed":41827, "phase":"combat", "expedition":true})
	check(bool(prepared.get("valid",false)), id+" real boss room prepares")
	if not bool(prepared.get("valid",false)): return null
	room.apply_prepared_expedition_node(prepared)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.set_input_blocked(true)
	room.spawn_enabled = false
	var boss := room._boss_actor as MineBoss
	check(boss != null and boss.boss_id == id and boss.brain == boss.boss_brain, id+" production room installs actual boss and warning brain")
	if boss == null: return null
	room.player.position = room.clamp_actor(boss.position+Vector2(-250,-45),30.0)
	room.player.aim_direction = room.player.position.direction_to(boss.position)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	hud.refresh()
	await frames()
	return boss

func refresh_draw(boss: MineBoss) -> void:
	boss.queue_redraw()
	if is_instance_valid(boss.body_visual): boss.body_visual.advance(.016); boss.body_visual.queue_redraw()
	room.enemy_telegraphs.refresh()
	room.queue_redraw()
	hud.refresh()
	await frames()
	RenderingServer.force_draw(false)

func capture(filename: String, boss: MineBoss) -> void:
	await refresh_draw(boss)
	var pixels := get_viewport().get_texture().get_image()
	check(not pixels.is_empty() and pixels.get_size() == get_window().content_scale_size, filename+" has real GPU pixels at the requested resolution")
	check(pixels.save_png(OUTPUT+filename) == OK, filename+" saves the actual production viewport")
	captures.append(filename)
	print("BOSS_SKILL_UI_CAPTURE ",ProjectSettings.globalize_path(OUTPUT+filename))

func cast_box(_boss: MineBoss) -> Rect2:
	return hud.boss_cast_plate.cast_rect()

func check_draw(boss: MineBoss, action: String, locked: bool) -> void:
	var info := Presentation.readout(boss.boss_brain)
	check(hud.boss_cast_plate.is_visible_in_tree() and hud.boss_cast_plate.info == info,action+" actual visible HUD plate reads the production boss")
	check(info.casting and bool(info.locked) == locked and info.title == Abilities.title(action,Words.locale == "en"),action+" "+Words.locale+" actual localized skill and aiming/lock readout")
	check(get_viewport().get_visible_rect().encloses(cast_box(boss)),action+" "+Words.locale+" full painted cast text fits visible viewport: "+str(cast_box(boss)))
	var clear_of_hud := true
	for rectangle: Rect2 in hud.coverage_rects():
		if not rectangle.is_equal_approx(cast_box(boss)):
			clear_of_hud = clear_of_hud and not rectangle.intersects(cast_box(boss))
	check(clear_of_hud,action+" "+Words.locale+" full cast frame remains readable outside standing HUD")
	var warnings: Array = room.enemy_telegraphs.snapshot()
	check(warnings.size() == 1 and warnings[0].actor_id == boss.get_instance_id() and warnings[0].data.action_id == action and bool(warnings[0].data.locked) == locked, action+" production danger layer draws the same actual skill and state")
	check(is_equal_approx(float(warnings[0].data.release_progress),float(info.progress)),action+" danger timing and cast progress agree")

func check_retired_boss() -> void:
	var boss := await install("BO01",0)
	if boss == null: return
	check(hud.boss_cast_plate.is_visible_in_tree(),"live boss cast plate visible before actor retirement")
	var reference: WeakRef = weakref(boss)
	boss.queue_free()
	hud.refresh()
	check(not hud.boss_cast_plate.visible and hud.boss_cast_plate.info.is_empty(),"queued boss immediately hides and clears its cast plate")
	await frames()
	check(reference.get_ref() == null,"retired production boss is actually freed while its room survives")
	for index: int in 4: hud.refresh()
	check(not hud.boss_cast_plate.visible and hud.boss_cast_plate.info.is_empty(),"repeated HUD refresh safely ignores the room's freed boss reference")
	boss = await install("BO02",0)
	check(boss != null and hud.boss_cast_plate.is_visible_in_tree(),"entering another boss room restores the live cast plate")

func check_attack_actions() -> void:
	for index in IDS.size():
		for locale: String in ["zh_CN","en"]:
			var boss := await install(IDS[index],0,locale)
			var action: String = Presentation.BASIC_ATTACKS[index]
			var origin := boss.position
			boss.boss_brain._begin_action(boss,room.player,action)
			boss.boss_brain.tick(boss,boss.boss_brain.state_time*.5,room.player)
			await refresh_draw(boss)
			check(Presentation.readout(boss.boss_brain).basic and Presentation.readout(boss.boss_brain).stage == "telegraph","baseline attack has windup UI "+action)
			var preparation: Vector2 = boss.body_visual.body_offset
			await capture(boss.boss_id+"_attack_windup_"+locale+".png",boss)
			boss.boss_brain.tick(boss,boss.boss_brain.state_time+.001,room.player)
			boss.boss_brain.tick(boss,boss.boss_brain.state_time+.001,room.player)
			await refresh_draw(boss)
			check(Presentation.readout(boss.boss_brain).stage == "release" and not Presentation.readout(boss.boss_brain).casting,"actual cast starts strike UI and removes aiming warning "+action)
			check(boss.body_visual.body_offset.distance_to(preparation)>4 and boss.position == origin,"release has a distinct local body action without collider movement "+action)
			check(get_viewport().get_visible_rect().encloses(cast_box(boss)),"attack readout fits "+locale)
			await capture(boss.boss_id+"_attack_release_"+locale+".png",boss)
			boss.boss_brain.tick(boss,.26,room.player)
			await refresh_draw(boss)
			check(Presentation.readout(boss.boss_brain).stage == "recovery","actual AI recovery owns settle UI "+action)
			var remaining: float = boss.boss_brain.state_time
			get_tree().paused = true
			await frames()
			check(boss.boss_brain.state_time == remaining,"pausing freezes attack UI clock "+action)
			get_tree().paused = false
			Game.profile.settings.reduced_fx = true
			await refresh_draw(boss)
			check(Presentation.readout(boss.boss_brain).stage == "recovery","reduced effects retain attack stage "+action)
			Game.profile.settings.reduced_fx = false
			boss.boss_brain.stop(boss)
			check(boss.boss_brain.action_presentation().is_empty(),"retirement clears action ornaments "+action)

func _run() -> void:
	if not Game.profile_path.contains("test_boss_skill_ui"):
		get_tree().quit(2)
		return
	check(DisplayServer.get_name() != "headless","suite uses the real GPU renderer")
	check(Game.new_profile() and Game.start_run(),"isolated real run starts")
	AudioServer.set_bus_mute(0,true)
	Game.profile.settings["enemy_skill_paths"] = true
	Game.profile.settings["reduced_fx"] = false
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	layer = CanvasLayer.new()
	add_child(layer)
	hud = load("res://scenes/hud.tscn").instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()
	check(hud.boss_cast_plate.get_canvas() != room.enemy_telegraphs.get_canvas(),"actual cast UI uses a separate screen canvas above world warning lines")
	await check_attack_actions()
	for id: String in IDS:
		var previous_pool := 0
		for difficulty: int in 5:
			var boss := await install(id,difficulty)
			if boss == null: continue
			var info := Presentation.readout(boss.boss_brain)
			check(not info.casting and int(info.unlocked) == difficulty and int(info.difficulty) == difficulty,id+" actual idle UI reports "+str(difficulty)+" difficulty unlocks")
			check(difficulty == 0 or int(info.pool) == previous_pool+1,id+" production skill total grows once at difficulty "+str(difficulty))
			previous_pool = int(info.pool)
			await refresh_draw(boss)
			check(hud.boss_cast_plate.is_visible_in_tree() and hud.boss_cast_plate.info == info,id+" actual idle HUD draws its difficulty skill count")
			if id == "BO01" and difficulty in [0,4]: await capture(id+"_idle_D"+str(difficulty)+"_zh_CN.png",boss)
		var boss := room._boss_actor as MineBoss
		for index: int in 4:
			var action: String = Abilities.UNLOCKS[id][index]
			boss.boss_brain._begin_action(boss,room.player,action)
			boss.boss_brain.tick(boss,float(boss.boss_brain.state_time)*.45,room.player)
			await refresh_draw(boss)
			check_draw(boss,action,false)
			var before := Presentation.readout(boss.boss_brain)
			boss.boss_brain.tick(boss,.05,room.player)
			var after := Presentation.readout(boss.boss_brain)
			check(float(after.progress)>float(before.progress) and float(after.remaining)<float(before.remaining),action+" actual aiming timer and progress advance continuously")
			boss.boss_brain.tick(boss,float(boss.boss_brain.state_time)+.001,room.player)
			boss.boss_brain.tick(boss,.16,room.player)
			await refresh_draw(boss)
			check_draw(boss,action,true)
			rendered.append(action)
			if index == 0: await capture(id+"_"+action+"_locked_zh_CN.png",boss)
			if index == 3:
				var full: Dictionary = room.enemy_telegraphs.snapshot()[0].data
				Game.profile.settings["reduced_fx"] = true
				await refresh_draw(boss)
				check(room.enemy_telegraphs._reduced and room.enemy_telegraphs.snapshot()[0].data == full,action+" reduced effects preserve actual warning geometry and timing")
				check_draw(boss,action,true)
				await capture(id+"_"+action+"_reduced_zh_CN.png",boss)
				Game.profile.settings["reduced_fx"] = false
		boss = await install(id,4,"en")
		if boss == null: continue
		for index: int in 4:
			var action: String = Abilities.UNLOCKS[id][index]
			boss.boss_brain._begin_action(boss,room.player,action)
			boss.boss_brain.tick(boss,.45,room.player)
			await refresh_draw(boss)
			check_draw(boss,action,false)
			if index == 0: await capture(id+"_"+action+"_aiming_en.png",boss)
			boss.boss_brain.tick(boss,float(boss.boss_brain.state_time)+.001,room.player)
			boss.boss_brain.tick(boss,.16,room.player)
			await refresh_draw(boss)
			check_draw(boss,action,true)
			if index == 0: await capture(id+"_"+action+"_locked_en.png",boss)
	# An English cast near the viewport side is still in its real attack range.
	var edge := await install("BO04",4,"en")
	if edge != null:
		room.player.position = room.clamp_actor(edge.position-Vector2(650,0),30.0)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		edge.boss_brain._begin_action(edge,room.player,"boulder_volley")
		edge.boss_brain.tick(edge,.4,room.player)
		await refresh_draw(edge)
		check_draw(edge,"boulder_volley",false)
		await capture("BO04_boulder_volley_edge_en.png",edge)
		for extent: Vector2i in [Vector2i(1920,1080),Vector2i(1280,900)]:
			get_window().size = extent
			get_window().content_scale_size = extent
			await frames()
			room.camera.follow_target()
			room.camera.force_update_scroll()
			await refresh_draw(edge)
			check_draw(edge,"boulder_volley",false)
			await capture("BO04_boulder_volley_edge_en_"+str(extent.x)+"x"+str(extent.y)+".png",edge)
	check(rendered.size() == 16,"all sixteen new skills complete actual aiming and locked GPU draw")
	await check_retired_boss()
	var manifest := FileAccess.open(OUTPUT+"manifest.json",FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"checks":checks,"failures":failures,"gpu":DisplayServer.get_name(),"rendered_actions":rendered,"captures":captures},"\t"))
		manifest.close()
	await room.combat_audio.wait_for_cleanup()
	layer.free()
	room.free()
	Game.run = null
	await frames()
	print("BOSS_SKILL_UI_RESULT checks=",checks," failures=",failures," gpu=",DisplayServer.get_name()," rendered=",rendered.size()," captures=",captures.size())
	get_tree().quit(1 if failures else 0)
