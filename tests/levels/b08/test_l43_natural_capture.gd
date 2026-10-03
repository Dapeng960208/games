extends Node
## Real AI/physics, scripted public player requests, final-render sampling only.
const Driver=preload("res://tests/levels/b08/l43_scripted_input.gd")
const MAX_CAPTURES := 6
var room: Node2D
var driver=Driver.new()
var output := ""
var captures: Dictionary={}
var journal: Array[Dictionary]=[]
var initial: Dictionary={}
var observed: Dictionary={}
var failures: Array[String]=[]
var started := 0
var last_journal := -1.0
var previous_signature := ""
var saved_auto_attack := false
var trial: RefCounted
var settlement: Dictionary={}

func _ready() -> void: run.call_deferred()
func run() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	var args:=OS.get_cmdline_user_args()
	if output.is_empty() or DisplayServer.get_name()=="headless" or not Game.profile_path.begins_with("user://test_b08_candidate/") or not args.has("--b08-art-convergence") or args.has("--b08-art-edge-joints-review") or args.has("--b08-art-overview-review"):
		get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	add_child(room) # Keep inherited processing: no disabled/frozen room fixture.
	if room.layout_id!="L43" or room.difficulty!=0 or Game.run==null or Game.run.hero_id!="CH01" or not Game.run.demo or room.sky_interactions==null:
		await room.cleanup_for_exit(); room.free(); get_tree().quit(3); return
	trial=Game.run
	Game.run_finished.connect(_finished)
	saved_auto_attack=bool(Game.profile.settings.get("auto_attack",false))
	Game.profile.settings["auto_attack"]=true # Isolated in-memory setting; never save.
	initial={"hero":Game.run.hero_id,"level":Game.run.level,"hp":Game.run.hp,"max_hp":Game.run.max_hp,"stats":Game.run.stats.duplicate(true),"difficulty":room.difficulty,"seed":Game.run.expedition.get("seed",-1),"profile_path":Game.profile_path,"profile_sha256":_profile_hash(),"auto_attack_before":saved_auto_attack,"auto_attack_during":true,"exit":room.exit_position,"authored_wave_count":room._authored_waves.size()}
	var layer:=CanvasLayer.new()
	add_child(layer)
	var label:=Label.new()
	label.position=Vector2(20,680)
	label.text="L43 CANDIDATE | SCRIPTED PLAYER / NORMAL AI | 35s maximum | not human play or balance acceptance"
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",Color("26394d"))
	label.add_theme_color_override("font_outline_color",Color("f5f1e3"))
	label.add_theme_constant_override("outline_size",4)
	layer.add_child(label)
	started=Time.get_ticks_msec()
	var ending := "time_limit_uncleared"
	while true:
		await RenderingServer.frame_post_draw
		var elapsed:=float(Time.get_ticks_msec()-started)/1000.0
		var state:=_snapshot(elapsed) # Same finished draw as the PNG below.
		_observe(state)
		if captures.is_empty(): _capture("entry",state)
		if Game.run!=trial or float(state.hp)<=0: ending="defeated" if trial.hp<=0 else "run_ended"; _capture("terminal_"+ending,state); break
		if room.exit_ready(): ending="encounter_cleared"; _capture("terminal_cleared",state); break
		if elapsed>=Driver.LIMIT_SECONDS: _capture("terminal_time_limit",state); break
		_event_capture(state)
		driver.step(room,elapsed,true)
	var terminal: Dictionary=captures.values().back().state if not captures.is_empty() else {}
	var clean: bool=await room.cleanup_for_exit()
	var persisted_unchanged: bool=initial.profile_sha256==_profile_hash()
	if Game.run==trial: Game.reload_profile() # Restore existing demo backup; no save.
	Game.run_finished.disconnect(_finished)
	room.free()
	await get_tree().process_frame
	var report:=FileAccess.open(output.path_join("l43_natural_report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"scripted_player_normal_ai_pending_pixel_review","ending":ending,"initial":initial,"terminal":terminal,"settlement":settlement,"captures":captures,"journal":journal,"observed":observed,"requests":driver.requests,"framebuffer":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"audio_cleanup":clean,"persisted_profile_unchanged":persisted_unchanged,"failures":failures,"limits":["Scripted public player input, not human play", "Wall-clock ceiling can end before 35 simulated seconds on software rendering", "Lv20 diagnostic CH01 against B08 content; death is not a balance conclusion", "Only naturally reached states count; absent poses/interactions remain unverified", "Single D0 L43 sample; no other-room or full-animation acceptance"]},"\t"))
	print("B08_L43_NATURAL ending=",ending," frames=",captures.size()," clean=",clean," persisted_unchanged=",persisted_unchanged," failures=",failures.size()," output=",output)
	get_tree().quit(0 if clean and persisted_unchanged and failures.is_empty() else 1)

func _profile_hash() -> String:
	return FileAccess.get_sha256(Game.profile_path) if FileAccess.file_exists(Game.profile_path) else "absent"
func _finished(result: Dictionary) -> void: settlement=result.duplicate(true)
func _snapshot(elapsed: float) -> Dictionary:
	var art=room.sky_interactions
	var state: Dictionary={"wall_seconds":elapsed,"simulation_seconds":room.elapsed,"sample":"RenderingServer.frame_post_draw","draw_frame":Engine.get_frames_drawn(),"physics_frame":Engine.get_physics_frames(),"stage":driver.stage,"hp":trial.hp,"max_hp":trial.max_hp,"player_foot":room.player.position,"player_visual":room.player.visual_state,"player_cooldowns":room.player.cooldowns.duplicate(),"camera_zoom":room.camera.zoom,"camera_center":room.camera.get_screen_center_position(),"room_processing":room.is_physics_processing(),"player_processing":room.player.is_physics_processing(),"exit_ready":room.exit_ready(),"warnings":room.warnings.size(),"feathers":room.feathers.size(),"channel":room.wind.channel.duplicate(true),"pending":room.wind.pending.duplicate(true),"wind_direction":room.wind.direction(art.lane.id,art.lane.direction),"flag_broken":art.flag_broken,"flag_alpha":art.flag_body.modulate.a,"vane_alpha":art.vane_body.modulate.a,"suppression_remaining":maxf(0,room.wind.suppressed_until-room.wind.now),"actors":{}}
	for actor: Node2D in room.enemies.get_children():
		if actor.static_actor:
			state["flag_hp"]=actor.health.current
			continue
		var pose:=str(actor.native_art.active_pose) if actor.native_art!=null else "debug"
		state.actors[actor.enemy_id]={"foot":actor.position,"alive":actor.is_alive(),"hp":actor.health.current,"phase":actor.brain.phase,"pose":pose,"action":str(actor.brain.action.get("kind","")),"mirrored":actor.aim_direction.x<-.1,"processing":actor.is_physics_processing(),"legal_foot":room.valid_ground(actor.position,actor.navigation_radius),"body_region":actor.body_region,"body_bounds":actor.body_bounds}
	return state
func _observe(state: Dictionary) -> void:
	var signature: Array=[state.stage,state.hp,state.flag_broken,not state.channel.is_empty(),not state.pending.is_empty(),state.wind_direction,state.exit_ready]
	for id: String in state.actors:
		var actor: Dictionary=state.actors[id]
		var key:=id+":"+str(actor.phase)+":"+str(actor.pose)
		observed[key]=int(observed.get(key,0))+1
		signature.append(key)
		if not actor.legal_foot and not failures.has("illegal_foot:"+id): failures.append("illegal_foot:"+id)
	if not room.valid_ground(room.player.position,18) and not failures.has("illegal_player_foot"): failures.append("illegal_player_foot")
	if not state.camera_zoom.is_equal_approx(Vector2(.85,.85)) and not failures.has("camera_changed"): failures.append("camera_changed")
	var value:=str(signature)
	if journal.size()<512 and (value!=previous_signature or float(state.wall_seconds)-last_journal>=.5):
		journal.append(state)
		last_journal=float(state.wall_seconds)
		previous_signature=value
func _event_capture(state: Dictionary) -> void:
	if captures.size()>=MAX_CAPTURES-1: return # Reserve a terminal actual frame.
	if not state.pending.is_empty() and not captures.has("wind_warning"):
		_capture("wind_warning",state); return
	if state.flag_broken and not captures.has("flag_broken"):
		_capture("flag_broken",state); return
	for actor: Dictionary in state.actors.values():
		if actor.phase=="warning" and not captures.has("enemy_warning"):
			_capture("enemy_warning",state); return
		if actor.pose=="release" and not captures.has("enemy_release"):
			_capture("enemy_release",state); return
func _capture(kind: String, state: Dictionary) -> void:
	if captures.size()>=MAX_CAPTURES: return
	var image:=get_viewport().get_texture().get_image()
	var file:=kind+".png"
	if image.get_size()!=Vector2i(2560,1440) or image.save_png(output.path_join(file))!=OK:
		failures.append("capture_failed:"+kind); return
	captures[kind]={"file":file,"sha256":FileAccess.get_sha256(output.path_join(file)),"state":state}
