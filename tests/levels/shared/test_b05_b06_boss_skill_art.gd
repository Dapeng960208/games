extends Node
## Controlled real BossActor releases, not a natural combat or balance sample.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const HudScene = preload("res://scenes/presentation/hud.tscn")
const Art = preload("res://scripts/presentation/monsters/boss_skill_art.gd")
const Presentation = preload("res://scripts/presentation/monsters/boss_skill_presentation.gd")
const Catalog = preload("res://scripts/domain/combat/boss_ability_catalog.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
var checks := 0
var failures := 0
var output := ""
var room: RoomController
var hud: Control
var records: Array[Dictionary] = []

func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("BOSS SKILL ART: "+label)

func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if not Rules.chapter_enabled(6) or not Game.profile_path.contains("test_b05_b06_boss_skill_art") or output.is_empty() or not FileAccess.file_exists(output.path_join(".managed-test-run.json")) or DisplayServer.get_name() == "headless":
		get_tree().quit(2); return
	get_tree().create_timer(90).timeout.connect(func(): push_error("Boss art timed out"); get_tree().quit(1))
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":560607}),"fresh isolated production run")
	Game.profile.settings.automatic_attack = false
	Game.profile.settings.camera_shake = false
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	for boss_id: String in ["BO05","BO06"]: await _boss(boss_id)
	var file := FileAccess.open(output.path_join("boss_skill_art.json"),FileAccess.WRITE)
	check(file != null,"report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"kind":"production commands; controlled presentation fixture, not natural-play QA","records":records},"\t")+"\n")
		file.close()
	Game.run = null
	print("B05_B06_BOSS_SKILL_ART checks=",checks," failures=",failures," captures=",records.size()," output=",output)
	get_tree().quit(1 if failures else 0)

func _boss(id: String) -> void:
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await get_tree().process_frame
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	var prepared: Dictionary = room.prepare_expedition_node({"biome_id":"B05" if id == "BO05" else "B06","room_id":id,"role":"boss","difficulty":4,"b06_candidate":id == "BO06","node_index":-508})
	check(bool(prepared.get("valid",false)),id+" production arena prepares")
	if not bool(prepared.get("valid",false)): room.free(); return
	room.apply_prepared_expedition_node(prepared)
	room.set_input_blocked(true)
	room.enemy_skills.set_physics_process(false)
	var boss = room._boss_actor
	check(is_instance_valid(boss) and boss.boss_id == id,id+" actual factory body and brain")
	room.player.position = boss.position+Vector2(180,0)
	room.player.status.apply("invulnerable",1,60)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScene.instantiate()
	hud.room = room
	layer.add_child(hud)
	hud.set_process(false)
	var actions: Array = preload("res://scripts/levels/b05/combat/enemy_skills.gd").BOSS_ACTIONS if id == "BO05" else preload("res://scripts/levels/b06/combat/enemy_skills.gd").BOSS_ACTIONS
	var regions: Array[Rect2] = []
	for index: int in actions.size():
		var action: String = actions[index]
		var effect := Art.frame(id,action)
		var icon := Art.frame(id,action,"icon")
		check(not effect.is_empty() and not icon.is_empty(),id+" "+action+" own icon and effect load")
		if effect.is_empty() or icon.is_empty(): continue
		check(effect.region not in regions,id+" "+action+" independent effect cell")
		regions.append(effect.region)
		var size := Art.fitted(effect,Art.MAX_EFFECT_EXTENT)*WorldCamera.WORLD_ZOOM*2.0
		var region: Rect2 = effect.region
		var alpha: Array = effect.alpha128_bounds
		var visible := Vector2(alpha[2],alpha[3])
		var displayed := visible*size/region.size
		check(displayed.x <= visible.x and displayed.y <= visible.y,action+" effective effect pixels cover maximum 2K display")
		check(float(icon.alpha128_bounds[2]) >= 128 and float(icon.alpha128_bounds[3]) >= 128,action+" icon effective pixels exceed twice the largest 64px UI")
		check(Catalog.tier(id,action) == maxi(0,index-1),action+" displayed unlock tier")
		check(Catalog.unlocked(id,4).size() == 4,id+" cumulative four difficulty unlocks")
		boss.boss_brain.phase = 3
		boss.boss_brain.elapsed = 30
		boss.boss_brain._action_ready_at.clear()
		if id == "BO05":
			room.b05_mechanics.boss_phase_changed(3)
			room.b05_mechanics.tick(30.0)
			boss.boss_brain._last_victim = weakref(room.player)
		boss.boss_brain._begin_action(boss,room.player,action)
		var warning: Dictionary = boss.boss_brain.current_telegraph()
		check(str(warning.get("action_id","")) == action and not warning.is_empty(),action+" real warning admitted")
		if warning.is_empty(): continue
		check(str(Presentation.readout(boss.boss_brain).action_id) == action,action+" actual cast icon selects action")
		await _capture(boss,action,"warning",effect,displayed)
		boss.boss_brain.state = &"locked"
		boss.state = &"locked"
		boss.boss_brain._execute(boss)
		boss.body_visual.advance(.01)
		check(int(boss.boss_brain._actions_used.get(action,0)) > 0 or (action == "three_roots" and boss.boss_brain._root_step == 1),action+" real runtime releases")
		await _capture(boss,action,"release",effect,displayed)
		if action == "three_roots":
			for step in 2:
				boss.boss_brain.state = &"locked"
				boss.boss_brain._execute(boss)
			check(int(boss.boss_brain._actions_used.get(action,0)) == 1,"all three roots complete actual sequence")
		if index == 5:
			Game.profile.settings.reduced_fx = true
			if id == "BO05": room.b05_mechanics.tick(30.0)
			boss.boss_brain._action_ready_at.clear()
			boss.boss_brain._begin_action(boss,room.player,action)
			check(not boss.boss_brain.current_telegraph().is_empty(),action+" reduced FX retains warning")
			await _capture(boss,action,"reduced_warning",effect,displayed)
			Game.profile.settings.reduced_fx = false
		room.enemy_skills.reset_room()
	check(await room.combat_audio.wait_for_cleanup(),id+" audio cleanup")
	layer.free()
	room.free()
	await get_tree().process_frame

func _capture(boss: Node2D, action: String, stage: String, effect: Dictionary, displayed: Vector2) -> void:
	var before := var_to_str([boss.boss_brain.command,boss.position,boss.health.current,room.ground_polygon,room.exit_position,Game.run.hp])
	boss.queue_redraw()
	room.enemy_skills.queue_redraw()
	room.queue_redraw()
	hud.refresh()
	var plate := hud.find_child("BossCastPlate",true,false) as Control
	var icon_physical := (plate.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,Vector2(24,24))).size*Vector2(get_window().size)/get_viewport().get_visible_rect().size
	for i in 2: await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	check(image != null and image.get_size() == Vector2i(2560,1440),action+" "+stage+" original 2K framebuffer")
	var path := output.path_join(str(boss.boss_id).to_lower()+"_"+action+"_"+stage+"_2560x1440.png")
	check(image.save_png(path) == OK,action+" "+stage+" saved original")
	check(before == var_to_str([boss.boss_brain.command,boss.position,boss.health.current,room.ground_polygon,room.exit_position,Game.run.hp]),action+" "+stage+" drawing preserves frozen combat")
	records.append({"boss_id":boss.boss_id,"action":action,"stage":stage,"path":path,"native_source_pixels":[effect.texture.get_width(),effect.texture.get_height()],"effect_region":[effect.region.position.x,effect.region.position.y,effect.region.size.x,effect.region.size.y],"alpha128_bounds":effect.alpha128_bounds,"maximum_visible_display_pixels":[displayed.x,displayed.y],"cast_icon_physical_extent":[icon_physical.x,icon_physical.y],"codex_icon_physical_extent":64})
