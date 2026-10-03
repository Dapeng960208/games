extends Node
## Observational bounded candidate encounter, never a natural-play acceptance.
const Launcher = preload("res://scripts/levels/b07/world/candidate_scene.gd")
const Cards = preload("res://scripts/presentation/monsters/enemy_skill_presentation.gd")
const Layout = preload("res://scripts/levels/b07/art/l37_skill_card_layout.gd")
const Review = preload("res://scripts/levels/b07/art/l37_convergence_environment.gd")
const LIMIT := 25.0
const MOVES := [{"from":0.25,"to":2.25,"action":"move_right"}, {"from":4.0,"to":4.6,"action":"move_down"}, {"from":7.0,"to":7.6,"action":"move_up"}]
var launch: Node
var room: Node2D
var output := ""
var elapsed := 0.0
var clock_started := false
var running := false
var finishing := false
var reason := ""
var held := ""
var cohort: Dictionary = {}
var events: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var tracked_shots: Array[Dictionary] = []
var tracked_motions: Array[Dictionary] = []
var capture_busy := false
var capture_requested := ""
var timed_slots := [0.8,9.25,20.0]
var captured_categories: Dictionary = {}
var last_sample := -1.0
var render_trace: Array[Dictionary] = []
var published_batch_checks := 0
var published_batch_issues: Array[Dictionary] = []
var initial: Dictionary = {}
var terminal: Dictionary = {}
var failures: Array[String] = []

func _ready() -> void:
	# Observer runs after default-priority gameplay, without driving it.
	process_physics_priority = 10000
	process_priority = 20000
	RenderingServer.frame_post_draw.connect(_observe_render_frame)
	_run.call_deferred()

func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.begins_with("user://test_b07_candidate/"):
		push_error("Live encounter requires managed output and isolated candidate profile")
		get_tree().quit(2)
		return
	if not ProjectSettings.globalize_path(Game.profile_path).begins_with(output.trim_suffix("/")+"/"):
		push_error("Profile must resolve beneath GAMES_TEST_OUTPUT_DIR (managed XDG_DATA_HOME/APPDATA)")
		get_tree().quit(2)
		return
	if FileAccess.file_exists(Game.profile_path):
		push_error("Use a fresh non-existing isolated profile for this probe")
		get_tree().quit(2)
		return
	if not Review.requested():
		push_error("Live review requires all three B07 art/review flags")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() != "headless" and "--b07-live-render-observe" not in OS.get_cmdline_user_args():
		push_error("Graphical live evidence requires actual _draw instrumentation flag")
		get_tree().quit(2)
		return
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	launch = Launcher.new()
	launch.auto_start = false
	add_child(launch)
	if not launch.start_candidate("CH01",0,true):
		push_error(launch.last_error)
		get_tree().quit(2)
		return
	room = launch.room
	# Normal persisted setting API, confined to the disposable test profile.
	Game.set_setting("auto_attack",true)
	if not bool(Game.profile.settings.get("auto_attack",false)):
		push_error("Could not enable auto-attack in isolated profile")
		get_tree().quit(2)
		return
	for actor: Node2D in room.enemies.get_children():
		cohort[actor.get_instance_id()] = {"enemy_id":actor.enemy_id,"spawn":_xy(actor.position),"first_phases":{},"minimum_player_distance":actor.position.distance_to(room.player.position),"dead_t":null}
	if cohort.is_empty():
		push_error("No initial encounter cohort")
		get_tree().quit(2)
		return
	initial = _state()
	initial["profile_path"] = Game.profile_path
	initial["resolved_profile_path"] = ProjectSettings.globalize_path(Game.profile_path)
	initial["difficulty"] = room.difficulty
	initial["hero_id"] = Game.run.hero_id
	initial["hero_level"] = Game.run.level
	initial["stats"] = _json_value(Game.run.stats)
	initial["equipped"] = _json_value(Game.profile.get("loadout",{}))
	initial["equipment_instances"] = _json_value(Game.profile.get("equipment",{}))
	initial["encounter_progress"] = _json_value(room.encounter_progress)
	clock_started = true
	running = true
	_request_capture("entry")

func _physics_process(delta: float) -> void:
	if clock_started: elapsed += delta
	if not running: return
	_observe_actors()
	_observe_effects(room.enemy_skills.projectiles,tracked_shots,false)
	_observe_effects(room.enemy_skills.motions,tracked_motions,true)
	if elapsed-last_sample >= .1:
		last_sample = elapsed
		var sample := _state()
		trace.append(sample)

	if not timed_slots.is_empty() and elapsed >= float(timed_slots[0]):
		var landmark_time: float = timed_slots.pop_front()
		_request_capture("timed_"+str(landmark_time).replace(".","_"))
	if Game.run == null or Game.run.hp <= 0: reason = "player_death"
	elif _cohort_cleared(): reason = "initial_wave_cleared"
	elif elapsed >= LIMIT: reason = "25_simulation_seconds"
	if not reason.is_empty():
		terminal = _state()
		running = false
		_set_move("")
		_finish.call_deferred()
		return
	var desired := ""
	for move: Dictionary in MOVES:
		if elapsed >= float(move.from) and elapsed < float(move.to): desired = move.action
	_set_move(desired)

func _set_move(action: String) -> void:
	if action == held: return
	if not held.is_empty(): Input.action_release(held)
	held = action
	if not held.is_empty(): Input.action_press(held)
	events.append({"t":elapsed,"kind":"keyboard_move","action":held})

func _observe_actors() -> void:
	for id: int in cohort:
		var entry: Dictionary = cohort[id]
		var actor: Node2D = instance_from_id(id) as Node2D
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.is_alive():
			if entry.dead_t == null:
				entry.dead_t = elapsed
				events.append({"t":elapsed,"kind":"enemy_dead_or_removed","actor_id":id,"enemy_id":entry.enemy_id})
			continue
		entry.minimum_player_distance = minf(float(entry.minimum_player_distance),actor.position.distance_to(room.player.position))
		var phase := str(actor.brain.phase)
		if phase in ["telegraph","locked","execute","recovery"] and not entry.first_phases.has(phase):
			entry.first_phases[phase] = elapsed
			events.append({"t":elapsed,"kind":"first_phase","actor_id":id,"enemy_id":entry.enemy_id,"phase":phase,"player":_xy(room.player.position),"actor":_xy(actor.position),"command":_json_value(actor.brain.current_skill())})
			if phase == "locked": _request_capture("first_locked_"+str(entry.enemy_id))

func _cohort_cleared() -> bool:
	for entry: Dictionary in cohort.values():
		if entry.dead_t == null: return false
	return true

func _observe_effects(active: Array, tracked: Array[Dictionary], motion: bool) -> void:
	var wanted := "B07-M02" if motion else "B07-M03"
	for effect: Dictionary in active:
		var owner_id := int(effect.get("owner_id",0))
		if not cohort.has(owner_id) or cohort[owner_id].enemy_id != wanted: continue
		var known := false
		for item: Dictionary in tracked:
			if is_same(item.ref,effect): known = true
		if known: continue
		tracked.append({"ref":effect,"removed":false,"return_seen":false})
		events.append(_effect_event(effect,"motion_start" if motion else "projectile_going"))
		_request_capture("M02_motion_start" if motion else "M03_outgoing")
	for item: Dictionary in tracked:
		if item.removed: continue
		var effect: Dictionary = item.ref
		var present := false
		for live: Dictionary in active:
			if is_same(live,effect): present = true
		if not motion and present and (bool(effect.get("returning_leg",false)) or int(effect.get("stage",0))>0) and not item.return_seen:
			item.return_seen = true
			events.append(_effect_event(effect,"projectile_return"))
		if present: continue
		item.removed = true
		var event := _effect_event(effect,"motion_removed" if motion else "projectile_removed")
		var owner: Node2D = instance_from_id(int(effect.get("owner_id",0))) as Node2D
		if not is_instance_valid(owner) or not owner.is_alive(): event["reason"] = "owner_dead_or_removed"
		elif motion:
			if float(effect.get("elapsed",0)) >= float(effect.get("duration",1))-.0001 and owner.position.distance_to(Vector2(effect.target)) < 1.0:
				event["reason"] = "completed_landing_at_locked_target"
				event["kind"] = "motion_landing"
			else: event["reason"] = "interrupted_or_collision_no_confirmed_landing"
		elif float(effect.get("distance_left",1)) <= .0001: event["reason"] = "path_distance_exhausted_not_owner_catch"
		elif float(effect.get("remaining",1)) <= .0001: event["reason"] = "lifetime_expired"
		elif int(effect.get("pierce_left",1)) <= 0: event["reason"] = "hit_budget_or_other_removal_ambiguous"
		else: event["reason"] = "wall_or_interception_or_cleanup_not_observable_without_runtime_hook"
		events.append(event)
		_request_capture(str(event.kind))

func _effect_event(effect: Dictionary, kind: String) -> Dictionary:
	var owner: Node2D = instance_from_id(int(effect.get("owner_id",0))) as Node2D
	return {"t":elapsed,"kind":kind,"effect":_json_value(effect),"owner_position":_xy(owner.position) if is_instance_valid(owner) else null,"player":_xy(room.player.position),"owner_player_distance":owner.position.distance_to(room.player.position) if is_instance_valid(owner) else null,"target_player_distance":Vector2(effect.get("target",Vector2.ZERO)).distance_to(room.player.position),"hp":Game.run.hp if Game.run != null else null,"shield":Game.run.shield if Game.run != null else null}

func _state() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: Node2D in room.enemies.get_children():
		actors.append({"id":actor.get_instance_id(),"enemy_id":actor.enemy_id,"position":_xy(actor.position),"phase":str(actor.brain.phase),"alive":actor.is_alive()})
	return {"t":elapsed,"engine_physics_frame":Engine.get_physics_frames(),"room_elapsed":room.elapsed,"player":_xy(room.player.position),"hp":Game.run.hp if Game.run != null else null,"shield":Game.run.shield if Game.run != null else null,"automatic_attack_count":Game.run.shots if Game.run != null else null,"input":held,"actors":actors,"cards":_cards()}

func _cards(rendered: bool = false) -> Dictionary:
	var shown: Array[Dictionary] = []
	var in_viewport := 0
	var bodies: Array = []
	var hud_rects: Array[Dictionary] = []
	for child: Node in launch.get_children():
		if child is CanvasLayer: _hud_rects(child,hud_rects)
	for rect: Rect2 in Layout.body_rects(room): bodies.append(_rect(rect))
	for actor: Node2D in room.enemies.get_children():
		var badge: Node2D = actor.get_node_or_null("EnemySkillBadge")
		if badge == null or not badge.is_visible_in_tree() or not badge.show_detail: continue
		var placement: Dictionary = Layout.placement(badge)
		if rendered and badge.last_detail_draw.is_empty(): continue
		var actual: Rect2 = badge.last_detail_draw.rect if rendered else badge.get_global_transform_with_canvas()*Rect2(placement.get("origin",badge.detail_origin()),Layout.SIZE)
		if actual.intersects(get_viewport().get_visible_rect()): in_viewport += 1
		var intersections: Array = []
		for body: Rect2 in Layout.body_rects(room):
			if actual.intersects(body): intersections.append(_rect(actual.intersection(body)))
		var hud_overlaps: Array[Dictionary] = []
		for hud: Dictionary in hud_rects:
			var bounds := Rect2(hud.rect[0],hud.rect[1],hud.rect[2],hud.rect[3])
			if actual.intersects(bounds): hud_overlaps.append({"path":hud.path,"intersection":_rect(actual.intersection(bounds))})
		shown.append({"actor_id":actor.get_instance_id(),"rect":_rect(actual),"intersects_viewport":actual.intersects(get_viewport().get_visible_rect()),"fully_in_viewport":get_viewport().get_visible_rect().encloses(actual),"body_overlap_rects":intersections,"hud_overlap_rects":hud_overlaps,"placement":_json_value(placement)})
	return {"visible_detail_count":in_viewport,"visible_detail_node_count":shown.size(),"candidate_count":Cards.detail_candidates(room).size(),"candidate_ids":Cards.detail_candidates(room),"published_batch_frame":room.get_meta(Layout.BATCH_META,{}).get("frame",-1),"published_selected_ids":room.get_meta(Layout.BATCH_META,{}).get("selected_ids",[]),"cards":shown,"body_occlusion_rects":bodies,"hud_control_rects":hud_rects,"coordinate_space":"logical viewport; screenshot is scaled to physical window"}

func _hud_rects(node: Node, result: Array[Dictionary]) -> void:
	# Exclude full-screen HUD roots and layout containers. These visible content
	# controls are conservative bounding boxes, not an alpha/pixel occlusion test.
	if node is Control and node.is_visible_in_tree() and (node is Panel or node is PanelContainer or node is BaseButton or node is Label or node is RichTextLabel or node is TextureRect or node is ProgressBar):
		var include: bool = not (node is Label and node.text.is_empty())
		var rect: Rect2 = node.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,node.size)
		if include and rect.has_area(): result.append({"path":str(node.get_path()),"class":node.get_class(),"rect":_rect(rect),"bounds_only":true})
	for child: Node in node.get_children(): _hud_rects(child,result)

func _request_capture(label: String) -> void:
	# Reserve the bounded image budget for live failures, not only early poses.
	if label not in ["entry","M03_outgoing","M02_motion_start","diagnostic_card_selection","diagnostic_hud_overlap","diagnostic_body_overlap"] and not label.begins_with("timed_"): return
	if captured_categories.has(label) or frames.size() >= 7 or not capture_requested.is_empty() or capture_busy: return
	captured_categories[label]=true
	capture_requested = label

func _process(_delta: float) -> void:
	if running and is_instance_valid(room):
		var batch: Dictionary = room.get_meta(Layout.BATCH_META,{})
		var state := _cards()
		published_batch_checks += 1
		var issue: bool = not batch.has("frame") or int(batch.get("frame",-1)) != Engine.get_process_frames() or batch.get("selected_ids",[]) != Cards.detail_candidates(room) or int(state.visible_detail_count) != state.candidate_ids.size()
		for card: Dictionary in state.cards:
			issue = issue or not card.hud_overlap_rects.is_empty() or not card.body_overlap_rects.is_empty()
		if issue: published_batch_issues.append({"t":elapsed,"frame":Engine.get_process_frames(),"batch":_json_value(batch),"cards":state})
	if DisplayServer.get_name() != "headless": return
	if capture_requested.is_empty() or capture_busy or finishing: return
	var label := capture_requested
	capture_requested = ""
	_capture(label)

func _capture(label: String, already_drawn: bool = false) -> void:
	capture_busy = true
	var requested_t := elapsed
	if DisplayServer.get_name() != "headless" and not already_drawn: await RenderingServer.frame_post_draw
	var record := _state()
	if DisplayServer.get_name() != "headless": record["cards"]=_cards(true)
	record["label"] = label
	record["requested_t"] = requested_t
	record["snapshot_t"] = elapsed
	record["file"] = ""
	if DisplayServer.get_name() != "headless":
		var filename := "L37_live_%02d_%s.png" % [frames.size(),label]
		var image := get_viewport().get_texture().get_image()
		if image.save_png(output.path_join(filename)) != OK: failures.append("save "+filename)
		else: record.file = filename
		record["pixel_size"] = [image.get_width(),image.get_height()]
	frames.append(record)
	capture_busy = false

func _observe_render_frame() -> void:
	if not running or not is_instance_valid(room) or DisplayServer.get_name()=="headless": return
	var sample := {"t":elapsed,"process_frame":Engine.get_process_frames(),"cards":_cards(true)}
	render_trace.append(sample)
	var cards: Dictionary = sample.cards
	if int(cards.visible_detail_count) != cards.candidate_ids.size(): _request_capture("diagnostic_card_selection")
	for card: Dictionary in cards.cards:
		if not card.hud_overlap_rects.is_empty(): _request_capture("diagnostic_hud_overlap")
		if not card.body_overlap_rects.is_empty(): _request_capture("diagnostic_body_overlap")
	if not capture_requested.is_empty() and not capture_busy:
		var label := capture_requested
		capture_requested=""
		_capture(label,true)

func _finish() -> void:
	finishing = true
	while capture_busy: await get_tree().process_frame
	if frames.size() < 8: await _capture("terminal_"+reason)
	var terminal_ui := {"checked":false}
	if reason == "player_death":
		var batch: Dictionary=room.get_meta(Layout.BATCH_META,{})
		terminal_ui={"checked":true,"hud_visible":launch.hud.is_visible_in_tree(),"hud_interaction":launch.hud.interaction_enabled,"hud_processing":launch.hud.is_processing(),"input_blocked":room.input_blocked,"outcome":launch.finished_outcome,"cards":_cards(DisplayServer.get_name()!="headless"),"published_batch":_json_value(batch)}
		if terminal_ui.hud_visible or terminal_ui.hud_interaction or terminal_ui.hud_processing or not terminal_ui.input_blocked or terminal_ui.outcome!="death": failures.append("terminal gameplay HUD not retired")
		if terminal_ui.cards.visible_detail_count!=0 or not batch.get("selected_ids",[-1]).is_empty() or not batch.get("placements",{"stale":true}).is_empty(): failures.append("terminal cards not empty")
		for actor: Node in room.enemies.get_children():
			var badge: Node2D=actor.get_node_or_null("EnemySkillBadge")
			if badge!=null and (badge.visible or badge.show_detail or not badge.info.is_empty() or not badge.command.is_empty() or not badge.last_detail_draw.is_empty()): failures.append("terminal retained badge "+str(actor.enemy_id))
	var coverage: Array[Dictionary] = []
	for id: int in cohort:
		var entry: Dictionary = cohort[id].duplicate(true)
		entry["actor_id"] = id
		entry["missing_phases"] = []
		for phase: String in ["telegraph","locked","execute","recovery"]:
			if not entry.first_phases.has(phase): entry.missing_phases.append(phase)
		entry["coverage_limit"] = "enemy_dead_before_unseen_phase" if entry.dead_t != null else reason+"; inspect minimum_player_distance and event commands for range/admission"
		coverage.append(entry)
	var report := {"sample":"scripted_keyboard_real_engine_candidate","natural_human_play":false,"normal_growth_proof":false,"candidate_initialization":"Launcher CH01 difficulty 0 injects Lv31 XP; fresh isolated profile equipment","runtime_frozen":false,"manual_physics_or_fsm_steps":false,"observation_limit":"after-physics polling can miss an effect spawned and removed in the same physics tick; absent events are not proof an effect never existed","duration_limit":LIMIT,"stop_reason":reason,"input_schedule":MOVES,"initial":initial,"terminal":terminal,"last_trace_before_cleanup":trace[-1] if not trace.is_empty() else {},"coverage":coverage,"m03_return_coverage":"not_authored_at_difficulty_0; disc_return requires difficulty>=2; no owner-catch claim","events":events,"trace":trace,"render_trace":render_trace,"published_batch_checks":published_batch_checks,"published_batch_issues":published_batch_issues,"render_evidence":"badge records actual _draw rect; sample only frame_post_draw","frames":frames,"failures":failures,"capture_note":"post_draw waits advance normal engine; use snapshot_t and engine_physics_frame; headless observes same path without image"}
	report["terminal_ui"]=terminal_ui
	var file := FileAccess.open(output.path_join("L37_live_encounter_report.json"),FileAccess.WRITE)
	if file == null: failures.append("report file open")
	else:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("L37 LIVE: ",reason," t=",elapsed," frames=",frames.size()," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _xy(value: Vector2) -> Array: return [value.x,value.y]
func _rect(value: Rect2) -> Array: return [value.position.x,value.position.y,value.size.x,value.size.y]
func _json_value(value: Variant) -> Variant:
	if value is Vector2: return _xy(value)
	if value is Rect2: return _rect(value)
	if value is Color: return value.to_html()
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			if value[key] is Object: continue
			result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_json_value(item))
		return result
	if value is Object: return null
	return value
