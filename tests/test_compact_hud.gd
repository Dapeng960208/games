extends SceneTree
## Real HUD/input acceptance followed by deterministic engine-rendered screenshots.
## Only an isolated test_ profile is permitted. No player save is read or changed.

const LOGICAL_SIZE := Vector2(1280,720)
const CENTER_CLEAR := Rect2(390,154,590,438)
const HERO_IDS := ["CH01","CH02","CH03"]
const LOCALES := ["zh_CN","en"]
const DIMENSIONS := [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
# Cream expedition ribbons add a quest tracker and skill medallions.
# Their actual bounds, including transparent group padding, leave the central
# combat rectangle unobstructed. Small windows use the native1280canvas stretch.
const COVERAGE_LIMIT := 0.23

var checks := 0
var failures := 0
var captures := 0
var detail_captures: Array[String] = []
var app: Node
var game: Node
var graphical := false
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_checks")
	create_timer(90.0).timeout.connect(func(): push_error("Compact HUD suite timed out"); quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ",description)
	else:
		failures += 1
		push_error("FAIL "+description)

func frames(count: int = 3) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func mouse_move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event,true)

func mouse_button(at: Vector2, index: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = at
	event.global_position = at
	event.pressed = down
	root.push_input(event,true)

func key_event(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	root.push_input(event,true)

func capture(filename: String, expected_size: Vector2i) -> void:
	if not graphical:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(not frame.is_empty() and frame.get_size() == expected_size,"actual rendered size "+filename)
	check(frame.save_png("res://artifacts/"+filename+".png") == OK,"saved "+filename)
	captures += 1

func capture_detail(filename: String) -> void:
	if not graphical:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(not frame.is_empty() and frame.get_size() == Vector2i(1280,720),"actual detail renderer size "+filename)
	check(frame.save_png("res://artifacts/"+filename+".png") == OK,"saved detail preview "+filename)
	detail_captures.append(filename+".png")

func capture_detail_previews(locale: String) -> void:
	if not graphical:
		return
	app.hud.skill_slots[0].grab_focus()
	app.hud._update_tooltip()
	await capture_detail("compact_tooltip_"+locale+"_1280")
	app.show_combat_details("q")
	await frames(2)
	await capture_detail("compact_details_"+locale+"_1280")
	app._pop_modal()
	clear_hud_focus()
	await frames(2)

func run_checks() -> void:
	game = root.get_node("Game")
	graphical = DisplayServer.get_name() != "headless"
	if not game.profile_path.contains("test_"):
		push_error("Refusing HUD tests without isolated --test-profile=test_...")
		quit(2)
		return
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(),"create isolated HUD profile")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	check(game.select_hero("CH02"),"select ranged hero for live input checks")
	# This HUD fixture exercises one legacy room; expedition departure has its own suite.
	check(game.start_run(),"start legacy room for live HUD input")
	await frames(4)
	check(app.hud != null and app.room != null,"real game route creates compact HUD")
	if app.hud == null or app.room == null:
		quit(1)
		return
	app.room.spawn_enabled = false
	await check_live_input()
	game.finish_run("extracted")
	await frames()
	for hero_id in HERO_IDS:
		# A new isolated profile makes every visual hero use genuine level-three
		# stats and unlocks, independent of the level-20 functional test above.
		check(game.new_profile() and game.select_hero(hero_id),"fresh visual profile "+hero_id)
		app.show_camp()
		check(game.start_run(),"start legacy room for HUD visual fixture "+hero_id)
		await frames()
		check(game.grant_hero_xp(ContentRegistry.XP_THRESHOLDS[2],"compact_hud_visual_"+hero_id),"earn level-three visual fixture "+hero_id)
		freeze_visual_fixture()
		for locale in LOCALES:
			Words.set_locale(locale)
			app.hud.refresh()
			for dimensions in DIMENSIONS:
				root.size = dimensions
				await frames()
				clear_hud_focus()
				app.hud.refresh()
				app.room.player.queue_redraw()
				await frames(2)
				if graphical:
					check(str(app.room.player.get_meta("hero_visual_source","")).contains(hero_id),"rendered hero artwork belongs to "+hero_id+" / "+locale+" / "+str(dimensions.x))
				check_visual_state(hero_id,locale,dimensions)
				var filename: String = "compact_hud_"+hero_id+"_"+locale+"_"+str(dimensions.x)
				record_measurement(hero_id,locale,dimensions,filename)
				await capture(filename,dimensions)
				if hero_id == "CH02" and dimensions.x == 1280:
					await capture_detail_previews(locale)
		game.finish_run("extracted")
		await frames()
	root.size = Vector2i(1280,720)
	check(measurements.size() == HERO_IDS.size()*LOCALES.size()*DIMENSIONS.size(),"all 3 heroes x 2 locales x 4 resolutions measured")
	if graphical:
		check(captures == HERO_IDS.size()*LOCALES.size()*DIMENSIONS.size(),"all 24 actual renderer screenshots saved")
		check(detail_captures.size() == 4,"both locales have tooltip and paused details screenshots")
	var report := {"logical_viewport":[1280,720],"coverage_limit":COVERAGE_LIMIT,"central_clear_rect":rect_data(CENTER_CLEAR),"graphics":graphical,"captures":captures,"detail_captures":detail_captures,"fixture":"Level 3 is earned through grant_hero_xp; HP, shield, resource, gold and relics use game APIs. Only Q cooldown (3.5 s) is injected after world/player/enemy physics stop for deterministic screenshot state. Transient acquisition notices are cleared before measuring the standing HUD.","measurements":measurements}
	var file := FileAccess.open("res://artifacts/compact_hud_coverage.json",FileAccess.WRITE)
	check(file != null,"coverage report can be written")
	report["checks"] = checks
	report["failures"] = failures
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	app.set_process(false)
	await app.music.wait_for_cleanup()
	app.free()
	await frames(8)
	print("COMPACT_HUD_TEST_RESULT checks=",checks," failures=",failures," captures=",captures," graphics=",graphical)
	quit(1 if failures else 0)

func check_live_input() -> void:
	var hud: Control = app.hud
	var room: Node2D = app.room
	var cell: Button = hud.skill_slots[0]
	var center: Vector2 = cell.get_global_rect().get_center()
	check(game.run.level == 1 and not hud.skill_info("q").locked and hud.skill_info("secondary").locked,"new hero starts with Q and retains the level-two secondary gate")
	cell.grab_focus()
	hud._update_tooltip()
	var info: Dictionary = hud.skill_info("q")
	check(hud.tooltip_panel.visible and hud.tooltip_body.text.contains(info.summary) and hud.tooltip_body.text.contains(info.state),"keyboard focus exposes final cost, cooldown and current state")
	cell.release_focus()
	mouse_move(center)
	await frames(2)
	hud._update_tooltip()
	check(hud.tooltip_panel.visible and hud.tooltip_title.text == info.name,"real pointer hover exposes the skill tooltip")
	# Slow pointer travel must remain on touching source/tooltip surfaces;
	# neither keyboard focus nor a grace-period jump may keep this path alive.
	var tip_bounds: Rect2 = hud.tooltip_panel.get_global_rect()
	var source_bounds: Rect2 = cell.get_global_rect()
	check(not cell.has_focus() and is_equal_approx(tip_bounds.end.y,source_bounds.position.y),"bottom skill tooltip directly touches the unfocused source edge")
	var pointer_y: float = center.y
	var target_y: float = tip_bounds.get_center().y
	var trajectory_visible := true
	var crossed_source_edge := false
	while pointer_y > target_y:
		pointer_y = maxf(target_y,pointer_y-2.0)
		mouse_move(Vector2(center.x,pointer_y))
		await frames(1)
		trajectory_visible = trajectory_visible and hud.tooltip_panel.visible and hud.focused_control == null
		crossed_source_edge = crossed_source_edge or pointer_y < source_bounds.position.y
	check(trajectory_visible and crossed_source_edge,"two-pixel-per-frame pointer travel crosses the skill/tooltip edge without hiding")
	await create_timer(0.3).timeout
	await frames(1)
	check(hud.tooltip_panel.visible and hud.hovered_control == hud.tooltip_panel and hud.focused_control == null and hud.hover_grace <= 0.0,"slow tooltip access remains usable after all hover grace expires")
	var trajectory_shots: int = game.run.shots
	mouse_button(tip_bounds.get_center(),MOUSE_BUTTON_LEFT,true)
	Input.action_press("attack")
	check(paused and app.modals.size() == 1,"clicking the reached tooltip opens paused details immediately")
	await frames(2)
	check(game.run.shots == trajectory_shots,"tooltip surface click cannot leak weapon fire")
	mouse_button(tip_bounds.get_center(),MOUSE_BUTTON_LEFT,false)
	Input.action_release("attack")
	app._pop_modal()
	mouse_move(Vector2(640,360))
	await create_timer(0.25).timeout
	await frames(2)
	cell.grab_focus()
	hud._update_tooltip()
	check(hud.tooltip_panel.visible,"keyboard focus still opens tooltip after hover grace expires")
	key_event(KEY_E,true)
	hud._update_tooltip()
	check(not cell.has_focus() and hud.focused_control == null and not hud.tooltip_panel.visible,"E gameplay interaction dismisses a keyboard-only tooltip")
	key_event(KEY_E,false)
	mouse_move(center)
	await frames(2)
	hud._update_tooltip()
	check(game.grant_hero_xp(3600,"compact_hud_live_unlocks"),"unlock abilities through real XP API")
	game.restore_resource(1000)
	hud.refresh()
	var effective: Dictionary = room.player.skill_definition("q")
	info = hud.skill_info("q")
	var expected_summary := Words.text("HUD_FINAL_COST",{"cost":snappedf(float(effective.cost),0.1),"resource":MineStyle.content_text(ContentRegistry.hero("CH02"),"resource_name"),"cooldown":snappedf(float(effective.cooldown),0.1)})
	check(not info.locked and info.summary == expected_summary,"tooltip resolves upgraded combat cost and cooldown")
	room.player.cooldowns.q = 3.25
	hud._update_tooltip()
	info = hud.skill_info("q")
	check(info.cooldown == 3.25 and hud.tooltip_body.text.contains(info.state),"tooltip states actual remaining cooldown")
	room.player.cooldowns.q = 0.0
	check(game.try_spend_resource(game.run.resource),"empty resource through spending API")
	hud._update_tooltip()
	info = hud.skill_info("q")
	check(info.insufficient and hud.tooltip_body.text.contains(info.state),"tooltip explains the exact resource shortfall")
	game.restore_resource(1000)
	var shots_before: int = game.run.shots
	var secondary_before: float = room.player.cooldowns.secondary
	mouse_button(center,MOUSE_BUTTON_RIGHT,true)
	var blocked_on_press: bool = room.pointer_input_blocked
	Input.action_press("skill_secondary")
	await frames(3)
	# Headless pointer polling may return the OS cursor rather than the pushed
	# viewport event; the held-button release gate must still prevent casting.
	check(blocked_on_press and not room.pointer_controls_enabled() and room.player.cooldowns.secondary == secondary_before,"right click over HUD cannot cast secondary ability")
	check(game.run.shots == shots_before and app.modals.is_empty(),"HUD right click leaks neither weapon fire nor an unwanted modal")
	mouse_button(center,MOUSE_BUTTON_RIGHT,false)
	Input.action_release("skill_secondary")
	await frames(2)
	mouse_button(center,MOUSE_BUTTON_LEFT,true)
	# Model a physical button held through closing details as well as GUI dispatch.
	Input.action_press("attack")
	check(paused and app.modals.size() == 1,"HUD mouse press opens paused details synchronously")
	await frames(3)
	check(game.run.shots == shots_before,"pressing the skill control cannot attack")
	var excluded := true
	for button in hud.find_children("*","BaseButton",true,false):
		excluded = excluded and button.focus_mode == Control.FOCUS_NONE
	check(excluded,"all background HUD buttons leave modal focus order")
	check(root.gui_get_focus_owner() != null and app.modals[-1].node.is_ancestor_of(root.gui_get_focus_owner()),"combat details owns keyboard focus")
	check(app.modals[-1].node.find_child("SkillDetailsBody",true,false) != null,"paused details contains complete skill text")
	app._pop_modal()
	mouse_move(Vector2(640,360))
	await frames(8)
	check(not paused and game.run.shots == shots_before,"closing details while attack is held cannot leak a shot")
	mouse_button(Vector2(640,360),MOUSE_BUTTON_LEFT,false)
	Input.action_release("attack")
	clear_hud_focus()
	await frames(3)
	Input.action_press("attack")
	await frames(ceili(float(game.run.stats.attack_interval)*Engine.physics_ticks_per_second)+8)
	Input.action_release("attack")
	check(game.run.shots > shots_before,"fresh attack works after pointer/modal release guards clear")
	await frames(2)
	cell.grab_focus()
	key_event(KEY_TAB,true)
	check(paused and app.modals.size() == 1,"Tab opens paused details before GUI focus traversal")
	key_event(KEY_TAB,false)
	app._pop_modal()
	clear_hud_focus()
	await frames(2)
	var progression_center: Vector2 = hud.progression_button.get_global_rect().get_center()
	mouse_move(progression_center)
	await frames(2)
	check(hud.tooltip_panel.visible and hud.active_detail_slot == "progression","status header opens the progression tooltip")
	var progression_shots: int = game.run.shots
	mouse_button(progression_center,MOUSE_BUTTON_LEFT,true)
	Input.action_press("attack")
	check(paused and app.modals.size() == 1 and app.modals[-1].node.find_child("CharacterDossier",true,false) != null,"status header press opens the character dossier synchronously")
	await frames(2)
	check(game.run.shots == progression_shots,"pressing the progression target cannot leak weapon fire")
	mouse_button(progression_center,MOUSE_BUTTON_LEFT,false)
	Input.action_release("attack")
	app._pop_modal()
	clear_hud_focus()
	await frames(2)

func clear_hud_focus() -> void:
	var focus := root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	mouse_move(Vector2(640,360))
	app.hud.hovered_control = null
	app.hud.focused_control = null
	app.hud.last_hover_control = null
	app.hud.hover_grace = 0.0
	app.hud._update_tooltip()

func freeze_visual_fixture() -> void:
	# Only freeze after live input assertions, so snapshot determinism cannot
	# accidentally make the no-attack/modal checks pass without active combat.
	var room: Node2D = app.room
	room.set_physics_process(false)
	room.set_process(false)
	room.player.set_physics_process(false)
	room.player.set_process(false)
	for enemy in room.enemies.get_children():
		enemy.set_physics_process(false)
		enemy.set_process(false)
	room.gold_drops.clear()
	game.damage_player(37.0)
	check(is_equal_approx(game.add_shield(19.0),19.0),"fixture shield granted through game API")
	if game.run.resource > 37.0:
		game.try_spend_resource(game.run.resource-37.0)
	else:
		game.restore_resource(37.0-game.run.resource)
	check(game.add_gold(117),"fixture gold earned through game API")
	for relic in ["split","ember","arc"]:
		check(game.equip_relic(relic),"fixture relic acquired through game API "+relic)
	room.player.cooldowns.q = 3.5
	app.hud.refresh()
	app.hud.notifications.clear()
	app.hud.toast_remaining = 0.0
	clear_hud_focus()
	var relic_chip: Control = app.hud.relic_row.get_child(0)
	relic_chip.grab_focus()
	app.hud._update_tooltip()
	check(app.hud.tooltip_panel.visible and is_equal_approx(app.hud.tooltip_panel.get_global_rect().position.y,relic_chip.get_global_rect().end.y),"top relic tooltip directly touches the source lower edge")
	clear_hud_focus()

func check_visual_state(hero_id: String, locale: String, dimensions: Vector2i) -> void:
	var hud: Control = app.hud
	var label := hero_id+" / "+locale+" / "+str(dimensions.x)
	check(hud.health_bar.max_value == game.run.max_hp and absf(hud.health_bar.value-game.run.hp) <= maxf(hud.health_bar.step,0.001) and hud.health_label.text.contains(str(ceili(game.run.hp))),"actual HP values "+label)
	check(hud.resource_bar.value == 37 and hud.resource_bar.max_value == game.run.stats.resource_max and hud.resource_kind == ContentRegistry.hero(hero_id).resource_type,"actual single resource "+label)
	check(hud.shield_bar.visible and hud.shield_bar.value == 19,"actual shield strip "+label)
	check(hud.health_bar.size.y <= 20 and hud.resource_bar.size.y <= 9,"thin bars stay compact "+label)
	check(hud.quest_progress.text.contains(str(int(hud.objective_bar.value))) and not hud.quest_reward.text.is_empty(),"quest separates actual progress from completion reward "+label)
	check(hud.skill_slots.size() == 5 and hud.skill_info("q").cooldown == 3.5 and hud.skill_info("secondary").ready and hud.skill_info("ultimate").locked,"cooldown, ready and level-lock states coexist "+label)
	check(hud.skill_slots[4].key == Words.text("HUD_DASH_KEY"),"dash key updates to the active locale "+label)
	check(hud.gold_label.text.contains("117") and not hud.retained_label.visible,"wallet uses one line with retention in details "+label)
	check(hud.region_label.text.contains(Words.text("ROOM_"+app.room.layout_id)),"actual room name is localized "+label)
	check(hud.hint_label.visible == (not app.room.interaction_hint().is_empty()),"interaction hint appears only for a real interaction "+label)
	check(not hud.tooltip_panel.visible,"standing HUD does not leave a tooltip over combat "+label)
	var valid_targets := true
	for button in hud.find_children("*","BaseButton",true,false):
		valid_targets = valid_targets and button.size.x >= 44 and button.size.y >= 44
	check(valid_targets,"all HUD pointer targets are at least 44 px "+label)
	var legible := true
	for text_label in hud.find_children("*","Label",true,false):
		if text_label.is_visible_in_tree():
			legible = legible and text_label.get_theme_font_size("font_size") >= 16
	for button in hud.skill_slots:
		legible = legible and button.get_theme_font_size("font_size") >= 16
	check(legible,"standing text and skill keys stay at least 16 px "+label)
	var generated_controls: Array[Control] = []
	for index in range(4):
		generated_controls.append(hud.skill_slots[index])
	for icon in hud.find_children("Icon_*","Control",true,false):
		generated_controls.append(icon)
	var mipmaps_ready := true
	for control in generated_controls:
		var texture: Texture2D = control.get("generated_texture") as Texture2D
		var sampler_texture: Texture2D = texture.atlas if texture is AtlasTexture else texture
		var artwork: Image = sampler_texture.get_image() if sampler_texture != null else null
		mipmaps_ready = mipmaps_ready and artwork != null and artwork.has_mipmaps() and control.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	check(mipmaps_ready,"generated active-skill and instrument textures use mipmapped sampling "+label)

func actual_backplates() -> Array[Rect2]:
	var hud: Control = app.hud
	var result: Array[Rect2] = [hud.status_panel.get_global_rect(),hud.location_panel.get_global_rect(),hud.quest_panel.get_global_rect(),hud.gold_label.get_global_rect(),hud.details_button.get_global_rect()]
	if is_instance_valid(hud.circuit_panel) and hud.circuit_panel.visible:
		result.append(hud.circuit_panel.get_global_rect())
	for button in hud.skill_slots:
		result.append(button.get_global_rect())
	for button in hud.relic_row.get_children():
		if button is BaseButton and button.is_visible_in_tree() and not button.is_queued_for_deletion():
			result.append(button.get_global_rect())
	return result

func record_measurement(hero_id: String, locale: String, dimensions: Vector2i, filename: String) -> void:
	var groups: Array[Rect2] = app.hud.coverage_rects()
	var painted := actual_backplates()
	var group_area := union_area(groups)
	var painted_area := union_area(painted)
	var logical_area := LOGICAL_SIZE.x*LOGICAL_SIZE.y
	var central_clear := true
	var inside := true
	for bounds in groups:
		central_clear = central_clear and not bounds.intersects(CENTER_CLEAR)
		inside = inside and Rect2(Vector2.ZERO,LOGICAL_SIZE).encloses(bounds)
	check(group_area/logical_area <= COVERAGE_LIMIT,"group bounding HUD footprint is within 23 percent "+filename)
	check(painted_area <= group_area and painted_area/logical_area <= COVERAGE_LIMIT,"actual backplates include the circuit and exclude transparent group padding "+filename)
	check(central_clear and inside,"standing HUD stays inside viewport and outside central combat "+filename)
	var group_data: Array[Dictionary] = []
	var painted_data: Array[Dictionary] = []
	for bounds in groups:
		group_data.append(rect_data(bounds))
	for bounds in painted:
		painted_data.append(rect_data(bounds))
	measurements.append({"hero":hero_id,"locale":locale,"window":[dimensions.x,dimensions.y],"screenshot":filename+".png" if graphical else "","group_bounding_rects":group_data,"group_union_area":group_area,"group_fraction":group_area/logical_area,"actual_backplate_rects":painted_data,"actual_backplate_union_area":painted_area,"actual_backplate_fraction":painted_area/logical_area,"transparent_group_padding":group_area-painted_area,"center_clear":central_clear,"fixture_level":game.run.level})

func rect_data(bounds: Rect2) -> Dictionary:
	return {"x":bounds.position.x,"y":bounds.position.y,"width":bounds.size.x,"height":bounds.size.y}

func union_area(rectangles: Array[Rect2]) -> float:
	# Sweep distinct x boundaries and merge y intervals; overlapping controls
	# must not be double-counted in either coverage number.
	var edges: Array[float] = []
	for bounds in rectangles:
		if not edges.has(bounds.position.x): edges.append(bounds.position.x)
		if not edges.has(bounds.end.x): edges.append(bounds.end.x)
	edges.sort()
	var result := 0.0
	for index in range(edges.size()-1):
		var left := edges[index]
		var right := edges[index+1]
		var intervals: Array[Vector2] = []
		for bounds in rectangles:
			if bounds.position.x < right and bounds.end.x > left:
				intervals.append(Vector2(bounds.position.y,bounds.end.y))
		intervals.sort_custom(func(a: Vector2,b: Vector2): return a.x < b.x)
		var height := 0.0
		var end := -INF
		for interval in intervals:
			if interval.x > end:
				height += interval.y-interval.x
			elif interval.y > end:
				height += interval.y-end
			end = maxf(end,interval.y)
		result += (right-left)*height
	return result
