extends Node
## Real player rejection/buffer signals drive production world notice and HUD.
## Isolated Lv8 presentation fixture; not progression or balance acceptance.
## tools/test.ps1 -Suite skill_input_ui -SkipImport -SkipRestart [-Graphical]

const RESOLVER = preload("res://scripts/combat/stat_resolver.gd")
const CENTER := Rect2(390, 154, 590, 438)
var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var hud: Control
var hud_layer: CanvasLayer
var graphical := false
var captures: Array[Dictionary] = []
var records: Array[Dictionary] = []
var feedback: Array[Dictionary] = []
var order: Array[String] = []
var original_coverage: Array[Rect2] = []

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SKILL_INPUT_UI FAIL: " + description)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	stage.push_input(event, true)

func aim(at: Vector2) -> void:
	pointer(room.get_canvas_transform() * room.to_global(at))

func on_feedback(slot: String, reason: String, details: Dictionary) -> void:
	feedback.append({"slot": slot, "reason": reason, "details": details.duplicate(true), "room_elapsed": room.elapsed})
	order.append(reason)

func on_training_damage(_amount: float) -> void:
	order.append("damage")

func fixture(hero: String, locale: String) -> void:
	check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(), hero + " isolated profile/run")
	Words.set_locale(locale)
	Game.run.level = 8
	Game.run.stats = RESOLVER.resolve(hero, 8, {}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	stage.add_child(room)
	for child: Node in room.enemies.get_children(): child.free()
	room.player.position = Vector2(1100, 850)
	room.release_gate = false
	room.input_blocked = false
	room.player.resource_delay = 100.0
	room.combat_audio.audible = false
	room.player.skill_input_feedback.connect(on_feedback)
	hud_layer = CanvasLayer.new()
	stage.add_child(hud_layer)
	hud = load("res://scripts/ui/hud.gd").new()
	hud.room = room
	hud_layer.add_child(hud)
	hud.size = Vector2(1280, 720)
	await frames(2)
	aim(room.player.position + Vector2(180, 0))
	await frames(2)
	feedback.clear()
	order.clear()
	original_coverage = hud.coverage_rects()
	check(room.controls_enabled() and room.pointer_controls_enabled(), hero + " genuine combat controls enabled")
	check(hud._skill_feedback_actor == room.player, hero + " HUD bound to real player")

func cleanup() -> void:
	get_tree().paused = false
	await room.combat_audio.wait_for_cleanup()
	hud_layer.free()
	room.free()
	Game.finish_run("abandoned")
	await frames(1)

func clear_focus() -> void:
	var focused: Control = stage.gui_get_focus_owner()
	if focused != null: focused.release_focus()
	hud.hovered_control = null
	hud.focused_control = null
	hud.last_hover_control = null
	hud.hover_grace = 0.0
	pointer(Vector2(640, 360))
	hud._update_tooltip()

func check_footprint(context: String) -> void:
	var bounds: Array[Rect2] = hud.coverage_rects()
	check(bounds == original_coverage, context + " does not enlarge permanent HUD")
	var clear := true
	for box: Rect2 in bounds: clear = clear and not box.intersects(CENTER)
	check(clear and hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.skill_dock.mouse_filter == Control.MOUSE_FILTER_IGNORE, context + " standing instruments leave central combat clear")
	check(not hud._pointer_over_instruments(Vector2(640, 360)), context + " center pointer stays outside instrument hit areas")

func check_notice_fit(context: String) -> void:
	var layer: Node2D = room.skill_input_feedback
	var width: float = layer._font.get_string_size(layer.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var text_origin: Vector2 = room.get_canvas_transform() * (room.player.position + Vector2(-width * .5, -87))
	var text_end: Vector2 = room.get_canvas_transform() * (room.player.position + Vector2(width * .5, -87))
	check(width > 0 and text_origin.x >= 8 and text_end.x <= 1272 and text_origin.y >= 30, context + " localized world notice fits visible viewport")
	records.append({"case": context, "notice": layer.notice, "notice_width_world": width,
		"screen_left": text_origin.x, "screen_right": text_end.x, "reason": layer.reason,
		"details": layer.details.duplicate(true), "skill_info": hud.skill_info("secondary")})

func focus_slot(index: int, context: String) -> void:
	var cell: Button = hud.skill_slots[index]
	cell.grab_focus()
	hud._update_tooltip()
	var slot: String = ["q", "secondary", "f", "ultimate", "dash"][index]
	var info: Dictionary = hud.skill_info(slot)
	check(cell.has_focus() and hud.tooltip_panel.visible and hud.tooltip_body.text.contains(str(info.state)), context + " keyboard focus exposes actual current state")
	var label: Label = hud.tooltip_body
	var measured: Vector2 = label.get_theme_font("font").get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, label.size.x, label.get_theme_font_size("font_size"))
	check(measured.y <= label.size.y + 1 and Rect2(0, 0, 1280, 720).encloses(hud.tooltip_panel.get_global_rect()), context + " localized focus tooltip fits")

func capture(name: String) -> void:
	if not graphical: return
	await RenderingServer.frame_post_draw
	var bitmap: Image = stage.get_texture().get_image()
	var path: String = "skill_input_" + name + ".png"
	check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png("res://artifacts/" + path) == OK, "actual GPU capture " + name)
	captures.append({"path": path, "notice": room.skill_input_feedback.notice,
		"remaining": room.skill_input_feedback.remaining, "secondary": hud.skill_info("secondary")})

func rejection_checks(locale: String) -> void:
	await fixture("CH03", locale)
	var player: Node2D = room.player
	var notice: Node2D = room.skill_input_feedback
	var target: Vector2 = player.position + Vector2(160, 0)
	for _index in 12: hud.refresh()
	var connection_count := 0
	for connection: Dictionary in player.get_signal_connection_list("skill_input_feedback"):
		var callback: Callable = connection.callable
		if callback.get_object() == hud: connection_count += 1
	check(connection_count == 1, locale + " repeated HUD refresh binds once")
	hud.room = null
	hud.refresh()
	check(not player.is_connected("skill_input_feedback", hud._on_skill_input_feedback), locale + " HUD unbinds previous actor")
	hud.room = room
	hud.refresh()
	check(player.is_connected("skill_input_feedback", hud._on_skill_input_feedback), locale + " HUD rebinds current actor")
	Game.run.resource = 5.0
	var before_audio: int = room.combat_audio.accepted_events
	check(not player.cast_skill("secondary", target), locale + " real cast rejects insufficient resource")
	hud.refresh()
	check(notice.reason == "resource" and notice.notice.contains("25") and feedback.back().reason == "resource", locale + " real rejection provides exact missing 25")
	check(hud.skill_info("secondary").insufficient and hud.skill_slots[1].input_reason == "resource" and hud.skill_slots[1].input_flash > 0, locale + " insufficient slot state and feedback flash")
	check(Game.run.resource == 5 and player.cooldowns.secondary == 0 and not player.abilities.busy() and room.combat_audio.accepted_events == before_audio, locale + " failed cast does not spend or emit preparation")
	check_notice_fit(locale + " resource")
	focus_slot(1, locale + " resource")
	await capture(locale + "_resource_focus")
	clear_focus()
	check_footprint(locale + " rejection")
	Game.run.resource = 100.0
	var distant: Vector2 = player.position + Vector2(330, 0)
	check(not player.request_skill("secondary", distant), locale + " real input rejects target outside 220 range")
	hud.refresh()
	check(notice.reason == "invalid_ground" and str(notice.details.cause) == "out_of_range" and notice.details.range == 220.0 and notice.details.target == distant, locale + " range-ring and X marker use actual rejected target")
	check(notice.notice.contains("Out of range" if locale == "en" else "超出施法范围"), locale + " range reason is localized")
	check_notice_fit(locale + " out of range")
	await capture(locale + "_range")
	room.obstructions.assign([Rect2(player.position + Vector2(125, -30), Vector2(70, 60))])
	check(not player.cast_skill("secondary", target), locale + " real geometry blocks ground cast")
	check(str(notice.details.get("cause", "")) == "blocked_ground" and notice.notice.contains("Target blocked" if locale == "en" else "落点被阻挡"), locale + " blocker rejection has distinct explanation")
	check_notice_fit(locale + " blocked")
	room.obstructions.clear()
	check(player.cast_skill("secondary", target), locale + " legal ground cast succeeds")
	hud.refresh()
	check(notice.notice.is_empty() and notice.remaining == 0, locale + " accepted cast clears world warning")
	check(hud.skill_info("secondary").casting and hud.skill_info("q").busy and not hud.skill_info("q").ready, locale + " actual active timeline drives casting/busy")
	await frames(3)
	hud.refresh()
	check(float(hud.skill_info("secondary").cast_progress) > 0 and float(hud.skill_info("secondary").cast_progress) < 1, locale + " live physics advances HUD cast progress")
	await capture(locale + "_casting")
	await frames(32)
	hud.refresh()
	check(not hud.skill_info("secondary").casting and hud.skill_info("secondary").cooldown > 0 and hud.skill_info("q").ready, locale + " normal cooldown and other ready slots return after cast")
	Game.run.resource = 0.0
	check(not player.request_skill("q", target) and not notice.notice.is_empty(), locale + " live rejection shown before input block")
	room.set_input_blocked(true)
	check(notice.notice.is_empty() and notice.remaining == 0, locale + " input block immediately clears world feedback")
	room.set_input_blocked(false)
	await frames(30)
	check(not player.request_skill("q", target) and not notice.notice.is_empty(), locale + " new real rejection shown before pause")
	get_tree().paused = true
	check(notice.notice.is_empty() and notice.remaining == 0, locale + " pause clears world feedback")
	get_tree().paused = false
	clear_focus()
	hud.refresh()
	check_footprint(locale + " recovered")
	await cleanup()

func buffer_checks(locale: String) -> void:
	await fixture("CH01", locale)
	var player: Node2D = room.player
	var target: Node2D = room.spawn_enemy(player.position + Vector2(70, 0), "M01", 8, {"reward_enabled": false})
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	target.health.damaged.connect(on_training_damage)
	aim(target.position)
	await frames(2)
	check(player.fire(player.position.direction_to(target.position)), locale + " real hammer basic starts")
	check(player.request_skill("secondary", target.position), locale + " real right-click request buffers during basic windup")
	hud.refresh()
	check(player.buffered_skill.slot == "secondary" and hud.skill_info("secondary").queued and not hud.skill_info("secondary").casting, locale + " buffer drives NEXT/接招 slot before strike")
	check(room.skill_input_feedback.reason == "queued" and not room.skill_input_feedback.notice.is_empty(), locale + " buffer emits brief world acknowledgement")
	check(Game.run.resource == 100.0 and player.cooldowns.secondary == 0, locale + " buffer commitment does not spend resource early")
	check_notice_fit(locale + " queued")
	focus_slot(1, locale + " queued")
	await capture(locale + "_queued_focus")
	clear_focus()
	await frames(12)
	hud.refresh()
	var damage_index: int = order.find("damage")
	var accepted_index: int = order.find("accepted")
	check(damage_index >= 0 and accepted_index > damage_index and order.count("accepted") == 1, locale + " actual basic damage precedes exactly one queued skill commitment")
	check(target.health.current < target.health.maximum and player.buffered_skill.is_empty() and player.cooldowns.secondary > 0, locale + " actual target hit and buffer consumed once")
	check(room.skill_input_feedback.notice.is_empty(), locale + " consumed buffered cast clears queued world message")
	check_footprint(locale + " buffered cast")
	records.append({"case": locale + " actual strike then skill", "event_order": order.duplicate(), "feedback": feedback.duplicate(true)})
	await cleanup()

func run_checks() -> void:
	if not str(Game.profile_path).contains("test_skill_input_ui"):
		push_error("Refusing non-isolated skill-input test profile")
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(90).timeout.connect(func(): push_error("Skill input UI timed out"); get_tree().quit(1))
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var presentation := TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280, 720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	for locale: String in ["zh_CN", "en"]:
		await rejection_checks(locale)
		await buffer_checks(locale)
	var report := FileAccess.open("res://artifacts/skill_input_" + ("graphical" if graphical else "headless") + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "graphical": graphical,
		"method": "Real production room, player, abilities, SkillInputFeedback, HUD and skill slots in independent SubViewport. Only isolated test profile. Lv8 no equipment bonuses, manually configured resource and regeneration delay, fixed initial positions, random enemies and initial geometry disabled. One temporary real obstruction tests rejected landing. Buffer test uses real 10000HP M01 with AI disabled. Native physics timeline and actual basic damage; no fake emitted UI signals. Screenshots are unmodified real framebuffers. Normal HUD footprint compared before and after; both Chinese and English focus/standing states checked.",
		"records": records, "captures": captures}, "\t"))
	report.close()
	print("SKILL_INPUT_UI_RESULT checks=", checks, " failures=", failures, " captures=", captures.size())
	get_tree().quit(0 if failures == 0 else 1)
