extends Node
## Real GPU L23 AI and primary attacks, with process-local fixture ownership.
const Fixtures = preload("res://tests/test_numerical_instance_storage.gd")
var app: Node
var room: MineRoom
var frame_ms: Array[float] = []
var last_frame := 0
var sampling := false
var phase_label := "standing"
var spike_count := 0
var failures: Array[String] = []
var phase_frames: Dictionary = {"standing":[],"primary":[]}
func _physics_process(_delta: float) -> void:
	if is_instance_valid(room): room.set_pointer_input_blocked(false)
func _process(_delta: float) -> void:
	if is_instance_valid(room): room.set_pointer_input_blocked(false)
	var now := Time.get_ticks_usec()
	if sampling and last_frame > 0:
		var elapsed := (now-last_frame)/1000.0
		frame_ms.append(elapsed)
		phase_frames[phase_label].append(elapsed)
		if elapsed > 80 and spike_count < 12:
			spike_count += 1
			print("LIVE spike phase=",phase_label," frame_ms=",elapsed," cpu_process_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000," cpu_physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	last_frame = now
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); print("FAILED ",label)
func _ready() -> void:
	process_priority = 100
	process_physics_priority = -100
	get_tree().create_timer(85).timeout.connect(func(): print("LIVE timeout"); get_tree().quit(1))
	call_deferred("_run")
func frames(count: int = 3) -> void:
	for index in count: await get_tree().process_frame
func skip_relics() -> void:
	while not app.modals.is_empty():
		var button: Button = app.modals[-1].node.find_child("ConfirmZeroBenefitSkip",true,false)
		if button == null: button = app.modals[-1].node.find_child("SkipExpeditionRelic",true,false)
		if button == null: break
		button.pressed.emit()
		await frames()
func _run() -> void:
	if not Game.profile_path.contains("test_numerical_combat_live"): get_tree().quit(2); return
	check(Game.new_profile(),"isolated profile")
	var profile := Fixtures.fixture_profile()
	var reference := "res://tools/godot/player-reference/test_player_reference.json"
	if FileAccess.file_exists(reference): profile = (JSON.parse_string(FileAccess.get_file_as_string(reference)) as Dictionary).profile
	profile.hero_xp.CH01 = int(preload("res://scripts/core/hero_progression.gd").thresholds()[14])
	profile.bosses = ["BO01","BO02","BO03","BO04"]
	profile.settings.auto_attack = false
	check(Game._commit_profile(profile),"level 15 permanent equipment fixture")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await frames()
	check(Game.start_run({"expedition":true,"biome_id":"B04","difficulty":4,"seed":1735}),"actual B04 expedition starts")
	await frames()
	await skip_relics()
	app._advance_expedition(str(app.expedition.next_options()[0]))
	await frames()
	await skip_relics()
	room = app.room
	var context: Dictionary = room.expedition_context.duplicate(true)
	context.room_id = "L23"
	var prepared := room.prepare_expedition_node(context)
	check(prepared.valid,"real L23 layout prepares")
	room.apply_prepared_expedition_node(prepared)
	room.player.clear_movement_target()
	room.player.position = room.clamp_actor(room.encounter_zones[0].center,30)
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await get_tree().create_timer(2).timeout
	print("LIVE room ",room.layout_id," enemies=",room.enemies.get_child_count()," paused=",get_tree().paused," controls=",room.controls_enabled())
	var probe := Time.get_ticks_usec()
	for index in 2000:
		for property: Dictionary in room.get_property_list():
			if property.name == "enemies": room.get("enemies"); break
	var old_property_usec := Time.get_ticks_usec()-probe
	probe = Time.get_ticks_usec()
	for index in 2000: preload("res://scripts/combat/combat_properties.gd").read(room,"enemies")
	print("LIVE property 2000 queries uncached_ms=",old_property_usec/1000.0," cached_ms=",(Time.get_ticks_usec()-probe)/1000.0)
	var enemy: MineEnemy
	for candidate: MineEnemy in room.enemies.get_children():
		if not candidate.static_actor and candidate.is_alive(): enemy = candidate; break
	check(enemy != null,"natural encounter spawns live AI")
	if enemy != null:
		room.player.position = room.clamp_actor(enemy.position+Vector2(75,0),30)
		var hp: float = Game.run.hp
		last_frame = Time.get_ticks_usec()
		sampling = true
		for second in 10:
			await get_tree().create_timer(1).timeout
			if Game.run == null: break
			print("LIVE idle t=",second+1," hp=",Game.run.hp," shield=",Game.run.shield," invuln=",room.player.invulnerable)
		if Game.run == null: await finish(); return
		check(Game.run.hp < hp,"standing player receives actual natural attacks")
		for other: MineEnemy in room.enemies.get_children():
			if other.is_alive() and not other.static_actor: print("LIVE actor ",other.enemy_id," behavior=",other.profile.get("behavior_id")," state=",other.state," distance=",other.position.distance_to(room.player.position))
		sampling = false
		await screenshot("standing-natural-ai.png")
		await frames()
		phase_label = "primary"
		var kills_before: int = Game.run.kills
		# A real defensive skill allows the primary phase to outlast one target.
		room.player.request_skill("f",room.player.position)
		await get_tree().create_timer(.8).timeout
		last_frame = Time.get_ticks_usec()
		sampling = true
		for index in 18:
			var target: MineEnemy
			for candidate: MineEnemy in room.enemies.get_children():
				if candidate.is_alive() and not candidate.static_actor and room.has_line_of_sight(room.player.position,candidate.position): target = candidate; break
			if target == null or Game.run == null: break
			room.player.position = room.clamp_actor(target.position+Vector2(65,0),30)
			room.set_pointer_input_blocked(false)
			room.player._attack_release_required = false # a fresh manual press
			var start := Time.get_ticks_usec()
			var accepted: bool = room.player.request_attack(room.player.position.direction_to(target.position),target)
			print("LIVE primary index=",index," accepted=",accepted," request_ms=",(Time.get_ticks_usec()-start)/1000.0," target_hp=",target.health.current," primary_hits=",room.telemetry.primary_hits," kills=",Game.run.kills)
			# Player clocks keep the real attack cadence while movement stays still.
			await get_tree().create_timer(.8).timeout
		sampling = false
		if Game.run != null: check(Game.run.kills > kills_before,"natural primary phase kills a live enemy")
		await screenshot("natural-primary-combat.png")
		frame_ms.sort()
		if not frame_ms.is_empty(): print("LIVE frame_ms p50=",frame_ms[frame_ms.size()/2]," p95=",frame_ms[int(frame_ms.size()*.95)]," max=",frame_ms[-1]," frames=",frame_ms.size())
		for phase: String in phase_frames:
			var samples: Array = phase_frames[phase]
			samples.sort()
			if not samples.is_empty(): print("LIVE ",phase," p50=",samples[samples.size()/2]," p95=",samples[int(samples.size()*.95)]," max=",samples[-1]," frames=",samples.size())
	await finish()
func finish() -> void:
	app.queue_free()
	await frames()
	if Game.run != null: Game.finish_run("abandoned")
	print("LIVE failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(Game.profile_path).get_base_dir().path_join("combat-live-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join(label))
