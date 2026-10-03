extends Node
## Opt-in local reference test. Input profile is a user-authorized read-only copy.
var app: Node
var room: RoomController
var boss: BossActor
var skills := false
var next_skill_time := 0.0
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(room): return
	room.set_pointer_input_blocked(false)
	if skills and is_instance_valid(boss) and boss.is_alive() and Time.get_ticks_msec()/1000.0 >= next_skill_time and room.player.combo_queue.is_empty():
		next_skill_time = Time.get_ticks_msec()/1000.0+.15
		for slot: String in ["ultimate","secondary","f"]:
			if room.player.cooldowns[slot] <= 0 and room.player.request_skill(slot,boss.position): break
func _ready() -> void:
	process_physics_priority = -100
	skills = OS.get_environment("BOSS_REFERENCE_SKILLS") == "1"
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--reference-skills": skills = true
	get_tree().create_timer(230).timeout.connect(func(): print("REFERENCE timeout"); get_tree().quit(1))
	call_deferred("_run")
func frames() -> void:
	for index in 3: await get_tree().process_frame
func skip_relics() -> void:
	while not app.modals.is_empty():
		var button: Button = app.modals[-1].node.find_child("ConfirmZeroBenefitSkip",true,false)
		if button == null: button = app.modals[-1].node.find_child("SkipExpeditionRelic",true,false)
		if button == null: break
		button.pressed.emit()
		await frames()
func _run() -> void:
	if not Game.profile_path.contains("test_player_boss_balance"): get_tree().quit(2); return
	var reference := "res://tools/godot/player-reference/test_player_reference.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(reference)): print("REFERENCE missing opt-in profile copy"); get_tree().quit(2); return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(reference)))
	Game.new_profile()
	if not Game._commit_profile(source.profile): print("REFERENCE profile invalid ",Game.last_error); get_tree().quit(1); return
	if not ProfileStore._valid_document(source) or not source.active_run is Dictionary: print("REFERENCE active receipt invalid"); get_tree().quit(1); return
	# Retain the saved level, frozen equipment, relic ranks and runtime. Opening
	# a fresh adventure and skipping its relics would change the user's build.
	Game._restore_expedition(source.active_run)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	await frames()
	Game.run_started.emit()
	await frames()
	await skip_relics()
	room = app.room
	var context: Dictionary = room.expedition_context.duplicate(true)
	context.room_id = "BO04"
	context.role = "boss"
	room.apply_prepared_expedition_node(room.prepare_expedition_node(context))
	boss = room._boss_actor
	room.player.position = room.clamp_actor(boss.position+Vector2(-85,0),30)
	room.player.clear_movement_target()
	room.camera.follow_target()
	room.camera.force_update_scroll()
	Game.profile.settings.auto_attack = true
	print("REFERENCE saved D",Game.run.expedition.difficulty," skills=",skills," Lv",Game.run.level," relics=",Game.run.stats.relic_levels," player ",Game.run.stats.max_hp," hp / ",Game.run.stats.attack," attack / ",Game.run.stats.armor," armor; boss ",boss.profile.max_hp," hp / ",boss.profile.damage," attack / ",boss.profile.armor," armor")
	for second in 180:
		room.set_pointer_input_blocked(false)
		await get_tree().create_timer(1).timeout
		if Game.run == null or not is_instance_valid(boss): print("REFERENCE ended t=",second+1," result=",Game.last_result.get("outcome","boss defeated")); break
		if second < 12 or (second+1)%5 == 0 or Game.run.hp <= 0 or not boss.is_alive():
			print("REFERENCE t=",second+1," player_hp=",Game.run.hp," shield=",Game.run.shield," boss_hp=",boss.health.current," boss_phase=",boss.boss_brain.phase," boss_action=",boss.boss_brain.current_action," primary_hits=",room.telemetry.primary_hits," player_hits=",room.telemetry.player_hits," chain=",room.player.hit_chain.count)
		if not boss.is_alive() or Game.run.hp <= 0: break
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(Game.profile_path).get_base_dir()
	get_viewport().get_texture().get_image().save_png(folder.path_join("boss-reference.png"))
	app.queue_free()
	await frames()
	if Game.run != null: Game.finish_run("abandoned")
	get_tree().quit()
