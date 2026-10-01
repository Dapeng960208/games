extends "res://tests/test_crowd_feedback.gd"
## One ordinary CH01 L02 playthrough; no production or actor-state overrides.
## A standalone SubViewport receives real engine mouse events, not OS cursor input.
## tools/test.ps1 -Suite room_playthrough -SkipImport -SkipRestart [-Graphical]

const PLAYTHROUGH_LIMIT := 180.0
var mode := "follow_objective"
var phases: Array[Dictionary] = []
var interaction_events: Array[Dictionary] = []
var last_phase_key := ""
var completion_time := -1.0
var completion_signals := 0
var completion_receipt: Dictionary = {}
var exit_requested := false
var elapsed_simulation := 0.0
var time_by_activity := {"combat":0.0,"walking":0.0,"escort_waiting":0.0,"blocked_motion":0.0,"idle":0.0,"modal":0.0}
var no_progress_seconds := 0.0
var no_progress_peak := 0.0
var stall_windows: Array[Dictionary] = []
var last_progress_kills := 0
var last_progress_cart := Vector2.ZERO
var last_progress_player := Vector2.ZERO
var last_progress_time := 0.0
var ui_skip_pending := false
var probe_hero := "CH01"
var probe_seed := SEED

func bot_step(tick: int) -> void:
	var room: Node2D = app.room
	var player: Node2D = room.player
	var enemy: Node2D = nearest_enemy()
	var nav: Dictionary = room.navigation_target()
	var objective_finished: bool = room.objectives.is_complete()
	# Defend nearby threats, then return to the actual public objective marker.
	# No search for unactivated encounter zones and no automatic cargo unloading.
	if enemy != null and (objective_finished or player.position.distance_to(enemy.position)<340.0):
		mode = "combat"
		var offset: Vector2 = enemy.position-player.position
		var distance: float = offset.length()
		var direction: Vector2 = offset.normalized()
		var clear: bool = room.has_line_of_sight(player.position,enemy.position)
		var motion := Vector2.ZERO
		var keep_distance: float = 88.0 if probe_hero == "CH01" else clampf(float(Game.run.stats.get("range",500.0))*.55,220.0,320.0)
		if distance>keep_distance or not clear:
			motion = room.navigation_direction(player.position,enemy.position,Balance.PLAYER_RADIUS)
		elif probe_hero != "CH01" and distance<keep_distance*.6:
			motion = room.navigation_direction(player.position,player.position-direction*180.0,Balance.PLAYER_RADIUS)
		movement(motion)
		aim(enemy.position)
		if str(enemy.state) in ["windup","telegraph","lock"] and distance<160.0:
			player.start_dash(direction.orthogonal())
		var cast := false
		if tick%30 == 0:
			for slot: String in ["ultimate","f","secondary","q"]:
				if Game.run.level<int(player.skill_definition(slot).unlock): continue
				if player.cast_skill(slot,enemy.position):
					cast_counts[slot] = int(cast_counts.get(slot,0))+1
					cast = true
					break
				cast_failures[player.last_cast_error] = int(cast_failures.get(player.last_cast_error,0))+1
		var attack_distance: float = 98.0 if probe_hero == "CH01" else float(Game.run.stats.get("range",500.0))*.88
		if clear and not cast and distance<attack_distance:
			if player.fire(direction): fire_successes += 1
	else:
		mode = "follow_objective"
		var destination: Vector2 = nav.get("position",player.position)
		var stop_distance: float = 72.0 if str(nav.get("id","")) == "cargo_cart" else 28.0
		movement(room.navigation_direction(player.position,destination,Balance.PLAYER_RADIUS) if player.position.distance_to(destination)>stop_distance else Vector2.ZERO)
		aim(destination)
		var interaction: Dictionary = room.nearby_interaction()
		if str(interaction.get("kind","")) in ["next","early_extract","extract"] and room.objective_rewarded:
			movement(Vector2.ZERO)
			interaction_events.append({"time":elapsed_simulation,"kind":interaction.kind,"interaction":interaction.duplicate(true),"player_position":xy(player.position)})
			exit_requested = true
			room.interact()

func xy(value: Vector2) -> Array:
	return [snappedf(value.x,.01),snappedf(value.y,.01)]

func snapshot_room() -> Dictionary:
	var result: Dictionary = crowd_snapshot()
	var room: Node2D = app.room
	var nav: Dictionary = room.navigation_target().duplicate(true)
	if nav.has("position"): nav.position = xy(nav.position)
	var cart: Dictionary = room.objectives.element("cargo_cart")
	var module: RefCounted = room.objectives.module
	var expedition: Dictionary = Game.expedition_snapshot()
	result.merge({"simulation_time":snappedf(elapsed_simulation,.01),"bot_mode":mode,"navigation":nav,
		"interaction_hint":room.interaction_hint(),"status":room.objectives.status(),
		"encounters_exhausted":room._encounters_exhausted(),"objective_encounters_pending":room._objective_encounters_pending(),
		"cargo":{"position":xy(cart.position),"distance_to_player":room.player.position.distance_to(cart.position),
			"phase":cart.get("phase",""),"health":cart.cargo_health,"route_index":module.route_index,
			"unloaded":module.unloaded,"progress":cart.get("progress",0.0),"navigation_direction":xy(cart.get("navigation_direction",Vector2.ZERO)),
			"waypoint":xy(module.cart_route[mini(module.route_index,module.cart_route.size()-1)]),"done":cart.done,"bridge_change":module.bridge_change.duplicate(true)},
		"objective_rewarded":room.objective_rewarded,"objective_finished":room.objectives.is_complete(),
		"phase":expedition.get("phase",""),"checkpoint_id":expedition.get("checkpoint_id",""),
		"gold":Game.run.gold,"pending_equipment":expedition.get("pending_equipment",{}).duplicate(true),
		"completion_events":expedition.get("completion_events",{}).duplicate(true),
		"blockers":room.objectives.blockers.duplicate(true),"requested_motion":xy(desired_motion),
		"navigation_cache":{"graph_builds":room._navigation_cache.graph_builds,"route_searches":room._navigation_cache.route_searches,"route_cache_hits":room._navigation_cache.route_cache_hits}})
	return result

func note_phase(sample: Dictionary) -> void:
	var key: String = str(sample.cargo.route_index)+"|"+str(sample.status.text)+"|"+str(sample.navigation.get("kind",""))+"|"+str(sample.navigation.get("id",""))+"|"+str(sample.phase)
	if key==last_phase_key: return
	last_phase_key = key
	var entry: Dictionary = {"time":sample.simulation_time,"status":sample.status,"navigation":sample.navigation,
		"cargo":sample.cargo,"interaction_hint":sample.interaction_hint,"phase":sample.phase,"gold":sample.gold,"kills":sample.kills}
	phases.append(entry)
	print("ROOM_PLAYTHROUGH_PHASE ",JSON.stringify(entry))

func room_completed_observed() -> void:
	completion_signals += 1
	completion_time = elapsed_simulation
	completion_receipt = {"time":elapsed_simulation,"gold":Game.run.gold,"hero_xp":Game.profile.hero_xp[probe_hero],
		"expedition":Game.expedition_snapshot().duplicate(true),"completed_reward_ids":Game.run.completed_reward_ids.duplicate(true)}
	if graphical: capture_frame("completed")

func capture_frame(phase: String, enemy_id: String = "") -> void:
	if not graphical or not observing: return
	pending_captures += 1
	var capture: Dictionary = {"phase":phase,"enemy_id":enemy_id,"time":elapsed_simulation}
	await RenderingServer.frame_post_draw
	if is_instance_valid(app) and is_instance_valid(app.room):
		var filename: String = "room_playthrough_"+probe_hero+"_"+phase+".png"
		var status: Error = stage.get_texture().get_image().save_png("res://artifacts/"+filename)
		check(status==OK,"real playthrough framebuffer "+phase)
		capture["path"] = filename
		screenshot_records.append(capture)
	pending_captures -= 1

func click_real_skip_button(button: Button) -> void:
	# This is a real GUI click on the optional reward decision, not a modal clear
	# or a direct reward/HP write. Its documented 6% heal is a normal game effect.
	ui_skip_pending = true
	interaction_events.append({"time":elapsed_simulation,"kind":"reward_ui_skip","button":button.text,"hp_before":Game.run.hp})
	var target: Vector2 = button.get_global_rect().get_center()
	var mouse := InputEventMouseMotion.new()
	mouse.position = target
	mouse.global_position = target
	stage.push_input(mouse,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = target
		event.global_position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		stage.push_input(event,true)
		await frames(1)
	ui_skip_pending = false

func run_probe() -> void:
	if not Game.profile_path.contains("test_room_playthrough"):
		get_tree().quit(2)
		return
	if not OS.get_environment("MINE_PLAYTHROUGH_HERO").is_empty(): probe_hero = OS.get_environment("MINE_PLAYTHROUGH_HERO")
	if not OS.get_environment("MINE_PLAYTHROUGH_SEED").is_empty(): probe_seed = int(OS.get_environment("MINE_PLAYTHROUGH_SEED"))
	graphical = DisplayServer.get_name()!="headless"
	get_viewport().size = Vector2i(1280,720)
	get_tree().create_timer(240.0).timeout.connect(func(): push_error("Room playthrough exceeded 240 wall seconds"); get_tree().quit(1))
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage = SubViewport.new()
	stage.name = "RoomPlaythroughLocalInputViewport"
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	presentation = TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280,720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	check(Game.new_profile(),"isolated fresh profile")
	check(Game.select_hero(probe_hero),"normal "+probe_hero)
	app = load("res://scenes/main.tscn").instantiate()
	stage.add_child(app)
	await frames(2)
	check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":probe_seed}),"ordinary seeded departure")
	await frames(2)
	# Existing authorized entrance fixture only. The live room below never clears UI.
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers",[]):
		if str(offer.get("decision","")).is_empty(): app._choose_expedition_relic(str(offer.offer_id),"skip")
	app._clear_modals()
	var options: Array = app.expedition.next_options()
	check(not options.is_empty(),"first route option")
	if options.is_empty(): get_tree().quit(1); return
	app._advance_expedition("L02" if options.has("L02") else str(options[0]))
	app._clear_modals()
	await frames(2)
	check(app.expedition.current_index()==1 and app.room.layout_id=="L02","real first L02 escort room")
	check(Game.run.level==1 and not Game.run.demo and Game.run.relics.is_empty(),"ordinary Lv1 starter without boosts")
	current = {"hero":probe_hero,"level":Game.run.level,"route_seed":probe_seed,"room":app.room.layout_id,
		"layout_seed":app.room.layout_seed,"initial_stats":Game.run.stats.duplicate(true),"loadout":Game.run.loadout_snapshot.duplicate(true),
		"initial_expedition":Game.expedition_snapshot().duplicate(true),"initial_hero_xp":Game.profile.hero_xp[probe_hero],"samples":[]}
	previous_hp = Game.run.hp
	last_position = app.room.player.position
	start_elapsed = app.room.elapsed
	observation_wall_start = Time.get_ticks_msec()
	seed(probe_seed)
	app.room.enemies.child_entered_tree.connect(watch_enemy)
	for enemy: Node in app.room.enemies.get_children(): watch_enemy(enemy)
	app.room.combat_audio.connect("cue_played",on_cue)
	app.room.room_completed.connect(room_completed_observed)
	if not await verify_local_pointer(probe_hero):
		await app.room.combat_audio.wait_for_cleanup()
		await app.music.wait_for_cleanup()
		get_tree().quit(1)
		return
	observing = true
	var snapshot: Dictionary = snapshot_room()
	last_progress_cart = app.room.objectives.element("cargo_cart").position
	last_progress_player = app.room.player.position
	var next_sample := 0.0
	var stop_reason := "simulation_time_limit"
	for tick in int(PLAYTHROUGH_LIMIT*90):
		if Game.run==null: stop_reason="run_finished"; break
		if not is_instance_valid(app.room): stop_reason="room_unavailable"; break
		if not app.modals.is_empty():
			movement(Vector2.ZERO)
			if exit_requested:
				stop_reason = "exit_route_ui_opened"
				break
			var button: Node = app.find_child("SkipExpeditionRelic",true,false)
			if app.room.objective_rewarded and button is Button and not ui_skip_pending:
				await click_real_skip_button(button)
			else:
				stop_reason = "unhandled_real_modal"
				break
		elif tick%6==0:
			bot_step(tick)
		await frames(1)
		var delta: float = get_physics_process_delta_time()
		elapsed_simulation += delta
		if Game.run==null or not is_instance_valid(app.room): stop_reason="run_finished"; break
		var moved: float = app.room.player.position.distance_to(last_position)
		travelled += moved
		var activity := "idle"
		if not app.modals.is_empty(): activity="modal"
		elif desired_motion.length()>.1 and moved<.2: activity="blocked_motion"
		elif mode=="combat": activity="combat"
		elif moved>.2: activity="walking"
		elif str(app.room.objectives.element("cargo_cart").get("phase",""))=="推行中": activity="escort_waiting"
		time_by_activity[activity] += delta
		last_position = app.room.player.position
		total_damage += maxf(0.0,previous_hp-Game.run.hp)
		previous_hp = Game.run.hp
		snapshot = snapshot_room()
		if elapsed_simulation>=next_sample:
			current.samples.append(snapshot.duplicate(true))
			note_phase(snapshot)
			var cart_position: Vector2 = app.room.objectives.element("cargo_cart").position
			var progress: bool = actual_deaths>last_progress_kills or cart_position.distance_to(last_progress_cart)>5.0 or app.room.player.position.distance_to(last_progress_player)>10.0 or app.room.objective_rewarded
			if progress:
				if no_progress_seconds>=3.0: stall_windows.append({"end_time":elapsed_simulation,"duration":no_progress_seconds,"ended":true})
				no_progress_seconds = 0.0
			else: no_progress_seconds += elapsed_simulation-last_progress_time
			no_progress_peak = maxf(no_progress_peak,no_progress_seconds)
			last_progress_cart = cart_position
			last_progress_player = app.room.player.position
			last_progress_kills = actual_deaths
			last_progress_time = elapsed_simulation
			next_sample += 1.0
		if elapsed_simulation>=PLAYTHROUGH_LIMIT: break
	if no_progress_seconds>=3.0: stall_windows.append({"end_time":elapsed_simulation,"duration":no_progress_seconds,"ended":false})
	movement(Vector2.ZERO)
	if graphical: capture_frame("final")
	observing = false
	while pending_captures>0: await get_tree().process_frame
	current.merge({"stop_reason":stop_reason,"simulation_seconds":elapsed_simulation,"wall_seconds":(Time.get_ticks_msec()-observation_wall_start)/1000.0,
		"final":snapshot,"phases":phases,"interactions":interaction_events,"completion_time":completion_time,
		"completion_signals":completion_signals,"completion_receipt":completion_receipt,"exit_requested":exit_requested,
		"next_options":app.expedition.next_options() if Game.run!=null else [],"modal_names":[],
		"damage_received":total_damage,"enemy_health_consumed":consumed_health,"damage_callbacks":damage_events,
		"actual_enemy_deaths":actual_deaths,"distance_travelled":travelled,"activity_seconds":time_by_activity,
		"no_progress_peak_seconds":no_progress_peak,"stall_windows":stall_windows,"casts":cast_counts,
		"fire_actions_accepted":fire_successes,"cue_counts":cue_counts,"sfx_voices_peak":voices_peak,
		"defeat_bodies_peak":bodies_peak,"music_gain_range":[music_gain_min if is_finite(music_gain_min) else 0.0,music_gain_max],
		"pointer_input":{"method":"official independent SubViewport.push_input; not native OS pointer","preflight":pointer_preflight,"max_world_error":pointer_max_world_error,"requests":pointer_requests},
		"screenshots":screenshot_records,"result":Game.last_result.duplicate(true) if Game.run==null else {}})
	for modal: Dictionary in app.modals:
		var overlay: Node = modal.get("node")
		if is_instance_valid(overlay):
			for panel: Node in overlay.get_children():
				if panel is Panel: current.modal_names.append(str(panel.name))
	current["exit_ui"] = {"allow_advance":false,"choices":[]}
	var chart: Node = app.find_child("ExpeditionRouteChart",true,false)
	if chart!=null:
		current.exit_ui.allow_advance = chart.allow_advance
		for button: Node in chart.find_children("Choose_*","Button",true,false):
			current.exit_ui.choices.append({"name":button.name,"disabled":button.disabled,"visible":button.is_visible_in_tree()})
	if stop_reason=="exit_route_ui_opened":
		check(bool(snapshot.encounters_exhausted) and not bool(snapshot.objective_encounters_pending),"room cannot open exit before all original finite encounter batches are exhausted")
		check(current.modal_names.has("ExpeditionRouteModal") and current.exit_ui.allow_advance,"real exit opens advancing route UI")
		check(current.exit_ui.choices.any(func(choice: Dictionary): return not choice.disabled and choice.visible),"visible next-room choice is enabled")
	check(voices_peak<=8,"production eight-voice bound")
	check(pointer_max_world_error<.01,"engine mouse events tracked throughout playthrough")
	# Lack of completion is an observation, not an assertion that the game is broken.
	var filename: String = "room_playthrough_"+("graphical" if graphical else "headless")+".json"
	if probe_hero != "CH01" or probe_seed != SEED:
		filename = "room_playthrough_"+probe_hero+"_"+str(probe_seed)+"_"+("graphical" if graphical else "headless")+".json"
	var output := FileAccess.open("res://artifacts/"+filename,FileAccess.WRITE)
	output.store_string(JSON.stringify({"method":"One ordinary %s Lv1 seed%d L02 real main/room/AI, movement actions and public combat actions, local engine mouse events; follow the objective, defend nearby enemies, keep cargo; real optional reward GUI skip click and real exit interaction. No actor/stats/position/resource/objective edits. Observational bot, not human balance acceptance." % [probe_hero,probe_seed],"graphical":graphical,"master_safety_muted":AudioServer.is_bus_mute(0),"report":current},"\t"))
	output.close()
	print("ROOM_PLAYTHROUGH_RESULT ",JSON.stringify({"file":filename,"stop_reason":stop_reason,"time":elapsed_simulation,"completion_time":completion_time,"exit_requested":exit_requested,"kills":actual_deaths,"no_progress_peak":no_progress_peak,"checks":checks,"failures":failures}))
	await app.room.combat_audio.wait_for_cleanup()
	if Game.run!=null: Game.finish_run("abandoned")
	await frames(2)
	app.set_process(false)
	await app.music.wait_for_cleanup()
	app.free()
	await frames(2)
	get_tree().quit(0 if failures==0 else 1)
