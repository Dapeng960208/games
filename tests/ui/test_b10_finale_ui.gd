extends Node
## Graphical UI integration, not natural combat or balance acceptance.
## Only prior-chapter unlocks/level, actor hits and traversal positions are
## controlled. Main, room completion, loot decisions and extraction are real.

const MainScene = preload("res://scenes/app/main.tscn")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Finale = preload("res://scripts/presentation/components/finale_artwork.gd")
const RING := "B10-EASTER-RING"
var app: Node
var checks := 0
var failures: Array[String] = []
var output := ""
var captures: Array[String] = []
var rooms: Array[Dictionary] = []
var finished_result: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("B10 FINALE UI: " + label)
	return ok

func frames(count: int = 2) -> void:
	for index: int in count:
		await get_tree().process_frame

func press(node_name: String) -> bool:
	var control := app.find_child(node_name, true, false) as Button
	if not check(control != null and not control.disabled, "actual enabled button: " + node_name):
		return false
	control.pressed.emit()
	await frames()
	return true

func capture(file_name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var pixels: Image = get_viewport().get_texture().get_image()
	check(pixels.get_size() == Vector2i(2560,1440), "actual 2K framebuffer: " + file_name)
	var path := output.path_join(file_name + ".png")
	if check(pixels.save_png(path) == OK, "managed graphical screenshot: " + file_name):
		captures.append(path)

func _remember_result(result: Dictionary) -> void:
	finished_result = result.duplicate(true)

func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if not Game.profile_path.contains("test_b10_finale_ui") or output.is_empty() or not FileAccess.file_exists(output.path_join(".managed-test-run.json")) or DisplayServer.get_name() == "headless":
		push_error("B10 FINALE UI requires its managed isolated profile and -Graphical")
		get_tree().quit(2)
		return
	get_tree().create_timer(240.0).timeout.connect(func():
		push_error("B10 FINALE UI: timeout")
		get_tree().quit(1))
	Game.run = null
	if not check(Game.new_profile() and Game.select_hero("CH01"), "fresh managed profile"):
		await finish()
		return
	Game.set_setting("automatic_attack",false)
	Game.set_setting("camera_shake",false)
	Game.run_finished.connect(_remember_result)
	app = MainScene.instantiate()
	app.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(app)
	# Main._ready sets ALWAYS for production pause menus. Disable its automatic
	# updates again; this fixture drives the actual handlers explicitly.
	app.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	Words.set_locale("zh_CN")
	app.selected_biome = "B01"
	app.show_camp()
	await frames()
	check(get_viewport().get_visible_rect().size == Vector2(1280,720), "actual logical UI viewport")
	var picker := app.screen.find_child("DepartureBiome",true,false) as OptionButton
	if not check(picker != null and picker.get_item_metadata(9) == "B10" and picker.is_item_disabled(9), "fresh camp displays a locked chapter 10"):
		await finish()
		return
	var locked_profile: Dictionary = Game.profile.duplicate(true)
	if not await press("OpenFinaleChapter"):
		await finish()
		return
	var preview := app.find_child("FinaleChapterPreview",true,false) as Panel
	var choose := app.find_child("ChooseFinaleChapter",true,false) as Button
	var requirement := app.find_child("FinaleUnlockAndRewardStatus",true,false) as Label
	var painting := app.find_child("FinaleChapterIllustration",true,false) as Control
	check(preview != null and choose != null and choose.disabled, "locked preview cannot open an expedition")
	check(requirement != null and requirement.text.contains("第九章") and requirement.text.contains("尚未领取"), "preview reads the real unlock and unclaimed reward state")
	check(painting != null and painting.get("texture") != null, "registered native final-court illustration is loaded")
	check(Game.profile == locked_profile and not Game.finale_ring_claimed(), "opening the preview does not mutate progression or claim a reward")
	await capture("01_camp_locked_preview")
	app._clear_modals()
	# Explicit setup fixture: prior boss records and a legal level-50 hero are
	# committed before departure. No current-run boss/clear/reward flags are set.
	var setup: Dictionary = Game.profile.duplicate(true)
	setup.bosses = ["BO01","BO02","BO03","BO04","BO05","BO06","BO09"]
	setup.hero_xp.CH01 = int(Growth.thresholds().back())
	if not check(Game._commit_profile(setup), "controlled BO09 prerequisite commits through the real store: " + Game.last_error):
		await finish()
		return
	app.selected_biome = "B10"
	app.selected_difficulty = 4
	app.show_camp()
	await frames()
	picker = app.screen.find_child("DepartureBiome",true,false) as OptionButton
	var departure_heading := app.screen.find_child("DepartureHeading",true,false) as Label
	check(picker != null and picker.selected == 9 and not picker.is_item_disabled(9), "BO09 unlock enables actual B10 selection")
	check(departure_heading != null and departure_heading.text.contains("10") and departure_heading.text.contains("最终章"), "camp departure uses the chapter-10 finale heading")
	check(app.screen.find_child("FinaleDepartureIllustration",true,false) != null and not Game.finale_ring_claimed(), "the selected chapter uses its native banner and remains unclaimed")
	if not await press("Depart") or not await press("ConfirmWishDeparture"):
		await finish()
		return
	if not check(Game.run != null and is_instance_valid(app.room) and not app.room_start_failed and app.route == "run", "real Main departure creates a configured run: " + Game.last_error):
		await finish()
		return
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	check(str(Game.run.expedition.route.biome_id) == "B10" and int(Game.run.expedition.difficulty) == 4 and Game.hero_level("CH01") == 50, "actual departure freezes B10 D4 with legal level 50")
	check(is_instance_valid(app.hud) and app.hud.status_panel.position == Vector2(12,22), "finale reuses the existing profession/combat HUD")
	await resolve_choices()
	app.show_expedition(true)
	await frames()
	var chart: Control = app.find_child("ExpeditionRouteChart",true,false)
	var next: Dictionary = app.expedition.next_node()
	var first_card := app.find_child("Choose_" + str(next.get("room_id","")),true,false) as Button
	check(chart != null and bool(chart.get("finale")) and first_card != null and not first_card.disabled and bool(first_card.get("finale")), "actual departure route and next-room card use the finale theme")
	await capture("02_finale_departure_route")
	var journey_id: String = Game.run.id
	for index: int in range(1,Game.run.expedition.route.nodes.size()):
		await resolve_choices()
		next = app.expedition.next_node()
		if not check(not next.is_empty(), "actual route supplies node " + str(index)):
			await finish()
			return
		app.show_expedition(true)
		await frames()
		if not await press("Choose_" + str(next.room_id)):
			await finish()
			return
		if not check(int(Game.run.expedition.node_index) == index and app.room.layout_id == str(next.room_id), "route-card callback commits and applies " + str(next.room_id) + ": " + Game.last_error):
			await finish()
			return
		app.room.process_mode = Node.PROCESS_MODE_DISABLED
		app._clear_modals()
		if str(next.role) == "supply":
			check(app.room.objective_complete and app.expedition.current_complete(), "real supply stop is safe")
			continue
		if not await clear_actual_room():
			await finish()
			return
	await resolve_choices()
	check(app.room.layout_id == "BO10" and app.expedition.can_extract() and str(Game.run.expedition.phase) == "cleared", "real final boss completion opens legal extraction")
	check("BO10" in Game.run.boss_defeats and Game.run.hp > 0 and "BO10" not in Game.profile.bosses and not Game.finale_ring_claimed(), "boss death is a live run record; permanent completion/reward wait for extraction")
	app.show_expedition(true)
	await frames()
	var route_reward := app.find_child("FinaleRouteRewardStatus",true,false) as Label
	check(route_reward != null and route_reward.text.contains("尚未领取"), "finished route still reads the real unclaimed state")
	if not await extract_through_button():
		await finish()
		return
	check(bool(finished_result.get("final_chapter_completed",false)) and str(finished_result.get("run_id","")) == journey_id, "actual committed result carries this journey's final completion")
	check(Game.run == null and "BO10" in Game.profile.bosses and Game.finale_ring_claimed(), "real successful withdrawal banks completion and the reward")
	var ring_ids: Array[String] = []
	for id: String in Game.profile.equipment:
		if str(Game.profile.equipment[id].template_id) == RING: ring_ids.append(id)
	check(ring_ids.size() == 1 and str(Game.profile.get("finale_ring_claimed","")) == journey_id + ":finale_ring", "first real withdrawal yields one source-backed ring")
	if ring_ids.size() == 1:
		check(ring_ids[0] in finished_result.get("equipment_retained",[]) and str(Game.profile.equipment[ring_ids[0]].source_event_id) == journey_id + ":finale_ring", "first-claim UI derives from the actual retained instance")
	var completion := app.screen.find_child("FinaleCompletionPanel",true,false) as Panel
	var heading := app.screen.find_child("FinaleCompletionHeading",true,false) as Label
	var claim := app.screen.find_child("FinaleRingClaimStatus",true,false) as Label
	check(app.route == "result" and completion != null and heading != null and heading.text.contains("终章完成"), "Main.show_result renders the committed chapter ending")
	check(claim != null and claim.text.contains("首次领取") and claim.text.contains("星冠万象戒"), "ending displays the true first-claim reward state")
	await capture("03_finale_completion")
	Game.reload_profile()
	check(Game.run == null and Game.finale_ring_claimed() and str(Game.profile.get("finale_ring_claimed","")) == journey_id + ":finale_ring", "real disk reload preserves the claimed UI state")
	app.show_camp()
	await frames()
	if await press("OpenFinaleChapter"):
		requirement = app.find_child("FinaleUnlockAndRewardStatus",true,false) as Label
		check(requirement != null and requirement.text.contains("已领取") and not requirement.text.contains("尚未领取"), "reopened preview reads the persisted claim")
	app._clear_modals()
	# Legacy B01 is an existing ordinary, non-expedition production run. This
	# negative UI case does not fabricate a cleared checkpoint or final flag.
	app.selected_biome = "B01"
	app.selected_difficulty = 0
	finished_result.clear()
	if check(Game.start_run({}), "real ordinary B01 run starts after final completion: " + Game.last_error):
		await frames()
		if check(is_instance_valid(app.room) and not app.expedition.active(), "ordinary room is configured without an expedition"):
			app.room.process_mode = Node.PROCESS_MODE_DISABLED
			if await extract_through_button():
				check(not bool(finished_result.get("final_chapter_completed",true)) and Finale.completed(), "another chapter's real withdrawal has false final flag despite the durable BO10 record")
				check(app.route == "result" and app.screen.find_child("FinaleCompletionPanel",true,false) == null, "ordinary withdrawal renders ordinary result instead of replaying the ending")
	await finish()

func resolve_choices() -> void:
	app._clear_modals()
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers",[]):
		if str(offer.get("decision","")).is_empty():
			app._choose_expedition_relic(str(offer.offer_id),"skip")
	for drop: Dictionary in Game.pending_field_equipment():
		app._choose_field_equipment(str(drop.drop_id),"keep",str(Game.expedition_snapshot().get("checkpoint_id","")))
	await frames()
	app._clear_modals()
	await frames(1)

func clear_actual_room() -> bool:
	var room: Node2D = app.room
	var slain: Array[String] = []
	# Advance the actual finite encounter director with controlled positions and
	# hits. No HP refill, stat override, boss receipt or completion is injected.
	for step: int in 48:
		for zone: int in room.encounter_zones.size():
			if not room.activated_encounters.has(zone):
				room.player.position = room.encounter_zones[zone].center
				break
		room._tick_expedition(4.0)
		var actors: Array = []
		for actor in room.enemies.get_children():
			if actor.is_alive() and not actor.is_queued_for_deletion(): actors.append(actor)
		for actor in actors:
			var identity := str(actor.get("boss_id")) if actor.get("boss_id") != null else str(actor.enemy_id)
			slain.append(identity)
			actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats})
		await frames()
		room._tick_expedition(4.0)
		if room.objective_rewarded:
			rooms.append({"room_id":room.layout_id,"node_index":int(Game.run.expedition.node_index),"controlled_actor_hits":slain,"production_clear":true})
			return check(room.objective_complete and app.expedition.current_complete(), "actual room completion receipt: " + room.layout_id)
	return check(false,"actual finite room did not complete: " + room.layout_id + " / " + Game.last_error + " / " + room.configuration_error)

func extract_through_button() -> bool:
	app._clear_modals()
	await frames(1)
	finished_result.clear()
	app.show_extraction()
	await frames()
	var confirm: Button
	if not app.modals.is_empty():
		for node: Node in app.modals.back().find_children("*","Button",true,false):
			var candidate := node as Button
			if candidate != null and candidate.text == Words.text("CONFIRM_EXTRACT"): confirm = candidate
	if not check(confirm != null and not confirm.disabled, "actual legal extraction confirmation exists"):
		return false
	confirm.pressed.emit()
	await frames(5)
	return check(Game.run == null and not finished_result.is_empty() and str(finished_result.get("outcome","")) == "extracted", "actual confirmation commits and emits an extracted result: " + Game.last_error)

func finish() -> void:
	if is_instance_valid(app):
		app._shutdown_started = true
		app.set_process(false)
		app.set_process_input(false)
		app.set_process_unhandled_input(false)
		if is_instance_valid(app.room): await app.room.combat_audio.wait_for_cleanup()
		if is_instance_valid(app.music): check(await app.music.wait_for_cleanup(),"Main music cleanup")
		app.free()
	if Game.run_finished.is_connected(_remember_result): Game.run_finished.disconnect(_remember_result)
	Game.run = null
	var report := FileAccess.open(output.path_join("b10_finale_ui.json"),FileAccess.WRITE)
	if check(report != null,"managed UI acceptance report opens"):
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"logical_viewport":[1280,720],"framebuffer":[2560,1440],"scope":"UI integration with controlled prior BO09/level setup, traversal and actor lethal hits; real Main departure/cards/room clear/loot/extraction/ending; not natural combat, balance or full-role acceptance; ring replay and capacity remain in b10_finale_ring","captures":captures,"rooms":rooms},"\t"))
		report.close()
	print("B10_FINALE_UI checks=",checks," failures=",failures," output=",output)
	get_tree().quit(0 if failures.is_empty() else 1)
