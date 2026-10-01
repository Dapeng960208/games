extends Node
## Real mapped input and automatic production physics. Timeline evidence comes
## from actual releases, projectiles, contact damage and resource commitment.

const RoomScene = preload("res://scenes/room.tscn")
const ACTIONS: Array[String] = ["attack", "skill_q", "skill_secondary", "skill_f", "skill_ultimate", "dash"]
var stage: SubViewport
var room: MineRoom
var target: MineEnemy
var hud: Control
var hud_layer: CanvasLayer
var events: Array[Dictionary] = []
var projectiles: Dictionary = {}
var checks := 0
var failures := 0
var mouse_at := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("COMBAT COMBO FAIL: " + label)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func aim(at: Vector2) -> void:
	mouse_at = room.get_canvas_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = mouse_at
	motion.global_position = mouse_at
	stage.push_input(motion, true)

func mapped(action: String, pressed: bool) -> void:
	var source: InputEvent = InputMap.action_get_events(action)[0]
	var event: InputEvent = source.duplicate()
	if event is InputEventMouseButton:
		event.position = mouse_at
		event.global_position = mouse_at
		event.pressed = pressed
	elif event is InputEventKey:
		event.pressed = pressed
		event.echo = false
	Input.parse_input_event(event)

func release_all() -> void:
	for action: String in ACTIONS:
		mapped(action, false)

func press(slot: String) -> void:
	mapped("attack" if slot == "attack" else "skill_" + slot, true)
	await frames()
	mapped("attack" if slot == "attack" else "skill_" + slot, false)

func releases(slot: String) -> int:
	var count := 0
	for event: Dictionary in room.player.get_node("HeroFeedback").release_events:
		if str(event.slot) == slot:
			count += 1
	return count

func observe(slot: String, reason: String, details: Dictionary) -> void:
	events.append({"slot":slot, "reason":reason, "details":details.duplicate(true),
		"frame":Engine.get_physics_frames(), "serial":room.player.abilities.cast_serial,
		"resource":Game.run.resource if Game.run != null else -1.0,
		"shots":int(room.telemetry.shots), "hp":target.health.current if is_instance_valid(target) else 0.0,
		"q_releases":releases("q"), "secondary_releases":releases("secondary"),
		"ultimate_releases":releases("ultimate"), "projectiles":projectiles.duplicate(true)})

func projectile_entered(node: Node) -> void:
	if node is SparkProjectile:
		var slot: String = str(node.source)
		projectiles[slot] = int(projectiles.get(slot, 0)) + 1

func count_reason(reason: String, slot: String = "") -> int:
	var count := 0
	for event: Dictionary in events:
		if str(event.reason) == reason and (slot.is_empty() or str(event.slot) == slot):
			count += 1
	return count

func accepted_slots() -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in events:
		if str(event.reason) == "accepted":
			result.append(str(event.slot))
	return result

func event_for(reason: String, slot: String = "") -> Dictionary:
	for event: Dictionary in events:
		if str(event.reason) == reason and (slot.is_empty() or str(event.slot) == slot):
			return event
	return {}

func cause_count(cause: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if str(event.details.get("cause", "")) == cause:
			count += 1
	return count

func fixture(hero: String = "CH01", level: int = 8, maximum: float = 100.0, branches: Dictionary = {}) -> void:
	get_tree().paused = false
	release_all()
	if is_instance_valid(hud_layer):
		hud_layer.free()
		hud = null
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	Game.run.hero_id = hero
	Game.run.level = level
	Game.run.stats = StatResolver.resolve(hero, level, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.stats["resource_regen"] = 0.0
	Game.run.stats["branches"] = branches.duplicate(true)
	# Long-sequence stress fixtures explicitly enlarge only the resource tank.
	# Canonical costs/cooldowns stay unchanged; separate 100-resource tests prove
	# that queued commands cannot reserve or overspend future resources.
	Game.run.stats["resource_max"] = maximum
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = maximum
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	stage.add_child(room)
	room.set_physics_process(false)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	room.camera.set_physics_process(false)
	room.combat_audio.audible = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430, 350)
	room.player.combat_time = 99.0
	room.player.skill_input_feedback.connect(observe)
	room.projectiles.child_entered_tree.connect(projectile_entered)
	target = room.spawn_enemy(Vector2(490, 350), "M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	target.set_physics_process(false) # A stationary target keeps authored knockback from leaving the strike sector.
	aim(target.position)
	await frames(6)
	events.clear()
	projectiles.clear()
	check(room.player.aim_direction.dot(Vector2.RIGHT) > .99, hero + " mapped pointer sets live aim")

func wait_accepted(slot: String, limit: int = 100) -> bool:
	for _index in limit:
		if count_reason("accepted", slot) > 0:
			return true
		await frames()
	return false

func wait_release(slot: String, count: int = 1, limit: int = 100) -> bool:
	for _index in limit:
		if releases(slot) >= count:
			return true
		await frames()
	return false

func wait_idle(limit: int = 120) -> void:
	for _index in limit:
		if room.player.combo_queue.is_empty() and not room.player.abilities.busy() and room.player.attack_remaining <= 0.0:
			return
		await frames()

func attach_hud(locale: String = "zh_CN") -> void:
	Words.set_locale(locale)
	room.camera.global_position = room.player.global_position
	room.camera.force_update_scroll()
	hud_layer = CanvasLayer.new()
	stage.add_child(hud_layer)
	hud = load("res://scripts/ui/hud.gd").new()
	hud.room = room
	hud_layer.add_child(hud)
	hud.size = Vector2(stage.size)
	aim(target.position)
	await frames(2)
	check(room.controls_enabled() and room.pointer_controls_enabled(), locale + " live HUD leaves centered combat pointer available")
	check(hud._skill_feedback_actor == room.player, locale + " live HUD observes the actual combat actor")

func check_hud_queue(slot: String, position: int, locale: String) -> void:
	hud.refresh()
	var info: Dictionary = hud.skill_info(slot)
	var index: int = hud.SKILLS.find(slot)
	var shown: Dictionary = hud.skill_slots[index].state
	check(bool(info.get("queued", false)) and int(info.get("queue_position", 0)) == position,
		locale + " actual " + slot + " HUD readout has pending combo position " + str(position))
	check(bool(shown.get("queued", false)) and int(shown.get("queue_position", 0)) == position,
		locale + " painted " + slot + " medallion receives that same queue position")
	var step_text: String = "Step %d" % position if locale == "en" else "第%d步" % position
	check(str(info.get("state", "")).contains(step_text) and not bool(info.get("ready", true)),
		locale + " pending skill explains its localized order and stays pending")

func test_live_hud_combo() -> void:
	var old_locale: String = Words.locale
	for locale: String in ["zh_CN", "en"]:
		await fixture()
		await attach_hud(locale)
		await press("attack")
		await press("secondary")
		await press("f")
		check_hud_queue("secondary", 1, locale)
		check_hud_queue("f", 2, locale)
		check(Game.run.resource == 100.0 and room.player.abilities.cast_serial == 0,
			locale + " pending medallions do not fake resource or cooldown commitment")
		check(await wait_accepted("secondary"), locale + " queued right click commits through live HUD input")
		check_hud_queue("f", 1, locale)
		check(hud.skill_info("secondary").casting and not hud.skill_info("secondary").queued,
			locale + " committed right click leaves the queue and displays its active cast")
		room.player.cancel_actions()
		hud.refresh()
		check(not hud.skill_info("f").queued and int(hud.skill_slots[2].state.get("queue_position", -1)) == 0,
			locale + " cancelling clears both readout and painted pending state")
		check(count_reason("accepted", "f") == 0 and room.player.cooldowns.f == 0.0,
			locale + " cleared F has no delayed cast or cooldown")
		await fixture()
		await attach_hud(locale)
		await press("secondary")
		check(await wait_release("secondary"), locale + " recovery-readiness fixture really releases its heavy sweep")
		await frames(6)
		hud.refresh()
		check(room.player.abilities.busy() and room.player.abilities.recovery_chain_ready(),
			locale + " safe recovery window exists before the old action's full duration")
		check(bool(hud.skill_info("q").ready) and not bool(hud.skill_info("q").busy) and bool(hud.skill_slots[0].state.get("ready", false)),
			locale + " Q becomes ready in both the live readout and medallion during safe recovery")
		check(not bool(hud.skill_info("secondary").ready) and float(hud.skill_slots[1].state.get("cooldown", 0)) > 0,
			locale + " safe recovery does not remove the sweep's own committed cooldown")
		await press("q")
		check(count_reason("accepted", "q") == 1 and room.player.abilities.cast_serial == 2,
			locale + " HUD-advertised recovery readiness matches a real mapped Q cast")
		await wait_idle()
	Words.set_locale(old_locale)

func capture_combo_release(name: String, output: Array[Dictionary]) -> void:
	await RenderingServer.frame_post_draw
	hud.refresh()
	var shown: Dictionary = {}
	for slot: String in ["q", "secondary", "f", "ultimate"]:
		var info: Dictionary = hud.skill_info(slot)
		shown[slot] = {"queued":bool(info.queued), "queue_position":int(info.queue_position),
			"casting":bool(info.casting), "ready":bool(info.ready), "cooldown":float(info.cooldown)}
	output.append({"image":stage.get_texture().get_image(), "data":{
		"name":name, "physics_frame":Engine.get_physics_frames(),
		"resource":Game.run.resource, "cast_serial":room.player.abilities.cast_serial,
		"normal_attacks":int(room.telemetry.shots), "target_hp":target.health.current,
		"player_position":[room.player.position.x, room.player.position.y],
		"accepted_slots":accepted_slots(), "skill_states":shown,
		"releases":{"basic":room.player.get_node("HeroFeedback").basic_events,
			"secondary":releases("secondary"), "f":releases("f")}}})

func capture_live_combo() -> void:
	# Opt-in capture adds a separate graphical fixture after normal acceptance.
	# PNG compression and filesystem writes happen only once the combo finishes.
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await fixture()
	await attach_hud()
	var captured: Array[Dictionary] = []
	await press("attack")
	await press("secondary")
	await press("f")
	for _index in 30:
		if room.player.attack_resolved:
			break
		await frames()
	await capture_combo_release("01_basic_contact", captured)
	check(await wait_release("secondary"), "graphical combo releases actual right-click impact")
	await capture_combo_release("02_right_click_contact", captured)
	check(await wait_release("f"), "graphical combo releases its actual F follow-up")
	await capture_combo_release("03_f_contact", captured)
	await wait_idle()
	var path := "res://artifacts/combat_combos"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) == OK,
		"graphical combo capture directory is available")
	var records: Array[Dictionary] = []
	for capture: Dictionary in captured:
		var data: Dictionary = capture.data
		var image: Image = capture.image
		var file_path: String = path.path_join(str(data.name) + ".png")
		check(image.save_png(ProjectSettings.globalize_path(file_path)) == OK, "actual combo frame saved: " + str(data.name))
		data["file"] = file_path
		records.append(data)
	var manifest := FileAccess.open(path.path_join("captures.json"), FileAccess.WRITE)
	check(manifest != null, "actual combo capture timing manifest opens")
	if manifest != null:
		manifest.store_string(JSON.stringify({"fixture":"Production mapped CH01 basic → right click → F; automatic physics; stationary training target",
			"viewport":[stage.size.x, stage.size.y], "captures":records}, "\t"))
		manifest.close()

func test_basic_right_multi() -> void:
	await fixture()
	await press("attack")
	check(not room.player.attack_resolved and int(room.telemetry.shots) == 1, "fresh basic starts one real melee windup")
	await press("secondary")
	await press("f")
	check(count_reason("queued", "secondary") == 1 and count_reason("queued", "f") == 1, "basic accepts deliberate right-click then F presses in order")
	check(room.player.abilities.cast_serial == 0 and target.health.current == 10000.0, "queue does not skip the original committed axe impact")
	check(await wait_accepted("f"), "queued F executes automatically after the right-click skill")
	var sweep: Dictionary = event_for("accepted", "secondary")
	var shove: Dictionary = event_for("accepted", "f")
	check(accepted_slots() == ["attack", "secondary", "f"], "basic → right click → F preserves actual input order")
	check(not sweep.is_empty() and float(sweep.hp) < 10000.0 and int(sweep.shots) == 1, "right click enters only after real basic contact")
	check(not shove.is_empty() and int(shove.secondary_releases) == 1, "F cannot erase the right-click damage event")
	check(is_equal_approx(float(sweep.get("resource", -1)), 70.0) and is_equal_approx(float(shove.get("resource", -1)), 45.0), "right click and F each pay canonical cost exactly once")
	check(room.player.abilities.cast_serial == 2 and count_reason("accepted", "secondary") == 1 and count_reason("accepted", "f") == 1, "two skill presses create exactly two cast serials")
	await wait_idle()
	check(room.player.combo_queue.is_empty() and room.player.buffered_skill.is_empty(), "completed combo leaves no invisible pending action")
	check(int(room.telemetry.shots) == 1 and target.health.current < float(shove.get("hp", 10000)), "released mouse does not auto-repeat; final skill delivers actual damage")
	if not sweep.is_empty() and not shove.is_empty():
		var delay: float = float(int(shove.frame) - int(sweep.frame)) / 60.0
		check(delay >= .24 and delay < .54, "F starts after sweep impact and heavy-contact recovery, before the old full recovery")

func test_right_into_basic() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		await fixture(hero)
		await press("secondary")
		check(await wait_release("secondary"), hero + " right-click release really occurs")
		await press("attack")
		check(await wait_accepted("attack"), hero + " right-click recovery chains into a fresh basic press")
		var basic: Dictionary = event_for("accepted", "attack")
		check(accepted_slots() == ["secondary", "attack"], hero + " right-click → basic commits in order")
		check(int(basic.get("secondary_releases", 0)) == 1 and int(basic.get("shots", 0)) == 1, hero + " basic follows the authored right-click release, once")
		check(room.player.abilities.cast_serial == 1 and is_equal_approx(Game.run.resource, 70.0), hero + " basic costs no skill resource and cannot double-spend right click")
		await wait_idle()
		await frames(15) # A newly released ranged basic must traverse its real collision segment.
		check(int(room.telemetry.shots) == 1 and target.health.current < 10000.0, hero + " reciprocal combo has real output with no held repetition")

func test_melee_three_skills() -> void:
	await fixture("CH01", 20, 200.0, {"q":"B"})
	await press("q")
	await press("secondary")
	await press("ultimate")
	check(count_reason("queued", "secondary") == 1 and count_reason("queued", "ultimate") == 1, "Q → right click → R buffers both follow-ups")
	check(await wait_accepted("ultimate"), "three-skill combo reaches ultimate through live physics")
	check(accepted_slots() == ["q", "secondary", "ultimate"], "all three skill commands preserve press order")
	var sweep: Dictionary = event_for("accepted", "secondary")
	var ultimate: Dictionary = event_for("accepted", "ultimate")
	check(int(sweep.get("q_releases", 0)) == 1 and int(ultimate.get("secondary_releases", 0)) == 1, "each predecessor finishes its authored impact before the next skill")
	check(room.player.abilities.cast_serial == 3 and is_equal_approx(Game.run.resource, 85.0), "enlarged-tank sequencing fixture still spends 15 + 30 + 70 exactly once")
	await wait_idle()
	check(releases("ultimate") == 1 and target.health.current < 10000.0 and room.player.combo_queue.is_empty(), "ultimate executes once and the long sequence ends cleanly")

func test_ranged_basic_into_skills() -> void:
	for hero: String in ["CH02", "CH03"]:
		await fixture(hero)
		await press("attack")
		await press("q")
		if hero == "CH02":
			check(await wait_release("q"), "ranger begins its committed roll burst before the chain window")
		await press("secondary")
		check(count_reason("queued", "secondary") == 1, hero + " right click joins the preceding basic and Q sequence")
		check(await wait_accepted("secondary"), hero + " basic → Q → right click executes through actual input")
		check(accepted_slots() == ["attack", "q", "secondary"], hero + " mixed combo retains the basic and both skills in order")
		var secondary: Dictionary = event_for("accepted", "secondary")
		check(int(secondary.get("q_releases", 0)) == (3 if hero == "CH02" else 1), hero + " right click waits for the entire preceding Q output")
		check(room.player.abilities.cast_serial == 2 and int(room.telemetry.shots) == 1, hero + " mixed combo owns one basic and two distinct skills")
		check(is_equal_approx(Game.run.resource, 45.0 if hero == "CH02" else 52.0), hero + " mixed combo pays canonical Q and right-click costs once")
		await wait_idle()
		await frames(15)
		check(target.health.current < 10000.0 and releases("secondary") == 1, hero + " mixed combo preserves actual projectile contacts and right-click release")

func test_ranger_authored_bursts() -> void:
	for slot: String in ["q", "ultimate"]:
		await fixture("CH02")
		await press(slot)
		check(await wait_release(slot), "ranger " + slot + " first projectile is actually released")
		if slot == "ultimate":
			check(await wait_release(slot, 3), "ranger ultimate reaches third shot before last-window input")
			await frames(5)
		await press("attack")
		check(count_reason("queued", "attack") == 1, "ranger " + slot + " accepts basic in its final commitment window")
		check(await wait_accepted("attack"), "ranger " + slot + " chains into basic without a second press")
		var count: int = 3 if slot == "q" else 4
		var basic: Dictionary = event_for("accepted", "attack")
		check(releases(slot) == count and int(projectiles.get(slot, 0)) == count, "ranger " + slot + " keeps every authored projectile under chaining")
		check(int(basic.get(slot + "_releases", 0)) == count and int(basic.get("projectiles", {}).get(slot, 0)) == count, "ranger basic cannot cut off a future burst event")
		check(room.player.abilities.cast_serial == 1 and int(room.telemetry.shots) == 1, "burst chain adds one basic, without another skill serial")
		await wait_idle()
		await frames(15)
		check(target.health.current < 10000.0 and count_reason("accepted", "attack") == 1, "ranger burst/basic contacts remain real and single-commit")

func test_two_wave_finisher() -> void:
	await fixture("CH01", 20, 100.0, {"ultimate":"B"})
	await press("ultimate")
	check(await wait_release("ultimate"), "two-wave axe finisher releases its first impact")
	await frames(3)
	await press("attack")
	check(count_reason("queued", "attack") == 1, "basic can wait in the finisher's final commitment window")
	check(await wait_accepted("attack"), "two-wave finisher chains into basic automatically")
	var basic: Dictionary = event_for("accepted", "attack")
	check(releases("ultimate") == 2 and int(basic.get("ultimate_releases", 0)) == 2, "chaining retains both authored finisher waves")
	check(room.player.abilities.cast_serial == 1 and is_equal_approx(Game.run.resource, 30.0), "both waves belong to one cast and one 70-resource charge")
	await wait_idle()
	check(target.health.current < 10000.0 and int(room.telemetry.shots) == 1, "finisher and follow-up use the real contact pipeline")

func test_fifo_cap_and_validation() -> void:
	await fixture("CH01", 8, 200.0)
	await press("attack")
	await press("secondary")
	await press("f")
	await press("q")
	await press("ultimate")
	check(room.player.combo_queue.size() <= 3 and cause_count("queue_full") == 1, "fourth follow-up is explicitly rejected by the three-action cap")
	check(await wait_accepted("q"), "three admitted FIFO actions all execute")
	check(accepted_slots() == ["attack", "secondary", "f", "q"] and count_reason("accepted", "ultimate") == 0, "queue cap does not replace or secretly execute earlier inputs")
	check(room.player.abilities.cast_serial == 3 and room.player.cooldowns.ultimate == 0.0, "rejected fourth action never owns an ultimate serial or cooldown")
	await wait_idle()
	await fixture("CH01", 20, 100.0, {"q":"B"})
	await press("q")
	await press("secondary")
	await press("ultimate")
	check(count_reason("queued", "ultimate") == 1, "ultimate fits current resource when first queued")
	await wait_idle()
	check(accepted_slots() == ["q", "secondary"] and count_reason("resource", "ultimate") == 1, "queued ultimate rechecks resources after preceding skill spending")
	check(is_equal_approx(Game.run.resource, 55.0) and room.player.abilities.cast_serial == 2 and room.player.cooldowns.ultimate == 0.0, "canonical resource budget cannot overspend or start a rejected cooldown")
	await fixture("CH01", 1)
	await press("attack")
	await press("secondary")
	check(count_reason("locked", "secondary") == 1 and room.player.combo_queue.is_empty(), "locked right click never enters a combo")
	check(Game.run.resource == 100.0 and room.player.abilities.cast_serial == 0, "locked action commits no resources or cast serial")
	await fixture()
	await press("q")
	await wait_idle()
	await press("q")
	check(count_reason("cooldown", "q") == 1 and room.player.combo_queue.is_empty(), "cooldown failure remains explicit after a completed action")
	await fixture("CH02")
	await press("ultimate")
	await press("q")
	check(cause_count("early_chain") == 1 and room.player.combo_queue.is_empty(), "press before a long burst's final window is explicitly busy")
	check(room.player.abilities.cast_serial == 1 and Game.run.resource == 40.0 and room.player.cooldowns.q == 0.0, "early rejection cannot bypass the committed burst or charge Q")

func test_revalidation_and_expiry() -> void:
	await fixture("CH03")
	await press("q")
	await press("secondary")
	check(count_reason("queued", "secondary") == 1, "valid node target can be queued behind crystal pulse")
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(Vector2(470, 330), Vector2(45, 45))])
	await wait_idle()
	check(count_reason("invalid_ground", "secondary") == 1 and count_reason("accepted", "secondary") == 0, "queued ground skill rejects a surface blocked before commitment")
	check(Game.run.resource == 82.0 and room.player.cooldowns.secondary == 0.0 and room.player.abilities.cast_serial == 1, "invalidated target spends no second skill resource")
	await fixture()
	await press("secondary")
	check(await wait_release("secondary"), "expiry fixture starts from an executed sweep")
	await press("attack")
	check(count_reason("queued", "attack") == 1, "basic waits behind heavy contact recovery")
	# Model an external cooldown increase after input acceptance. No manual
	# action ticking or direct queue edits: automatic physics must expire it.
	room.player.shot_cooldown = 1.0
	await frames(75)
	check(cause_count("buffer_expired") == 1 and count_reason("accepted", "attack") == 0, "expired basic cannot release late after cooldown becomes ready")
	check(room.player.combo_queue.is_empty() and int(room.telemetry.shots) == 0, "expiry drops the whole stale action without hidden attacks")
	await fixture()
	await press("attack")
	check(not room.player.cast_skill("q", target.position) and room.player.combo_queue.is_empty(), "public immediate cast false still has no delayed side effect")
	await frames(30)
	check(room.player.abilities.cast_serial == 0 and room.player.cooldowns.q == 0.0, "failed public cast stays failed after recovery")

func test_cleanup() -> void:
	for mode: String in ["cancel", "dash", "block", "pointer", "pause", "death", "exit"]:
		await fixture()
		mapped("attack", true)
		await frames()
		await press("secondary")
		if mode != "pointer":
			await press("f")
		check(room.player.combo_queue.size() == (1 if mode == "pointer" else 2), mode + " fixture has real pending combo input")
		var saved_player: SalvagerPlayer = room.player
		match mode:
			"cancel": saved_player.cancel_actions()
			"dash":
				mapped("dash", true)
				await frames()
				mapped("dash", false)
			"block": room.set_input_blocked(true)
			"pointer": room.set_pointer_input_blocked(true)
			"pause":
				get_tree().paused = true
				check(saved_player.combo_queue.is_empty(), "pause notification clears queue without player physics")
				get_tree().paused = false
			"death": Game.run.hp = 0.0
			"exit": room.remove_child(saved_player)
		await frames(35)
		check(saved_player.combo_queue.is_empty() and saved_player.buffered_skill.is_empty(), mode + " clears all pending commands")
		check(saved_player.abilities.cast_serial == 0 and saved_player.cooldowns.secondary == 0.0 and saved_player.cooldowns.f == 0.0, mode + " cannot cast or charge after cancellation")
		if mode == "pause":
			check(int(room.telemetry.shots) == 1, "held mouse through pause does not leak an auto-attack on resume")
			release_all()
			await frames(2)
			await press("attack")
			check(int(room.telemetry.shots) == 2, "fresh release and press restores normal attack after pause")
		if mode == "exit":
			saved_player.free()
		release_all()
		if mode == "death": Game.run.hp = Game.run.max_hp

func test_dash_press_release_gate() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		await fixture(hero)
		mapped("dash", true)
		await frames()
		mapped("dash", false)
		await frames(2)
		check(room.player.dash_remaining > 0.0 and int(room.telemetry.dashes) == 1,
			hero + " mapped dodge is active before a new mouse press")
		mapped("attack", true)
		await frames(30)
		check(count_reason("dashing", "attack") == 1,
			hero + " new mouse press during dodge gets one explicit rejection")
		check(room.player.dash_remaining == 0.0 and int(room.telemetry.shots) == 0,
			hero + " holding the rejected press cannot leak an attack after dodge ends")
		check(room.player.combo_queue.is_empty() and room.player.buffered_skill.is_empty() and room.player.attack_buffer == 0.0,
			hero + " rejected dodge press leaves no queued or held retry")
		mapped("attack", false)
		await frames(2)
		await press("attack")
		check(count_reason("accepted", "attack") == 1 and int(room.telemetry.shots) == 1,
			hero + " a genuine release and fresh press restores exactly one basic")
	await fixture()
	mapped("dash", true)
	mapped("attack", true)
	await frames()
	mapped("dash", false)
	check(int(room.telemetry.dashes) == 1 and room.player.dash_remaining > 0.0,
		"simultaneous dodge and mouse press commits the dodge")
	await frames(30)
	check(int(room.telemetry.shots) == 0 and room.player.combo_queue.is_empty() and room.player.attack_buffer == 0.0,
		"same-frame mouse press cannot fire immediately or retry after the dodge")
	mapped("attack", false)
	await frames(2)
	await press("attack")
	check(int(room.telemetry.shots) == 1 and count_reason("accepted", "attack") == 1,
		"same-frame cancellation gate also resets only after a genuine release")
	await fixture()
	check(not Input.is_action_pressed("attack"), "pause-entry fixture has no mouse button held")
	get_tree().paused = true
	mapped("attack", true)
	await frames(2)
	check(Input.is_action_pressed("attack") and int(room.telemetry.shots) == 0,
		"a new mapped mouse press while paused reaches input without running combat")
	get_tree().paused = false
	await frames(30)
	check(int(room.telemetry.shots) == 0 and room.player.combo_queue.is_empty() and room.player.attack_buffer == 0.0,
		"a button first pressed during pause cannot leak an attack after resume")
	mapped("attack", false)
	await frames(2)
	await press("attack")
	check(int(room.telemetry.shots) == 1 and count_reason("accepted", "attack") == 1,
		"release and fresh press restore exactly one attack after a pause-time press")

func run_checks() -> void:
	if not Game.profile_path.contains("test_combat_combos"):
		get_tree().quit(2)
		return
	get_tree().create_timer(100.0).timeout.connect(func(): push_error("Combat combo fixture timeout"); get_tree().quit(1))
	AudioServer.set_bus_mute(0, true)
	var installer: Node = load("res://scripts/ui/main.gd").new()
	installer._install_inputs()
	installer.free()
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.handle_input_locally = true
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(stage)
	check(Game.new_profile() and Game.start_run(), "isolated combo profile starts real production run")
	await test_basic_right_multi()
	await test_right_into_basic()
	await test_melee_three_skills()
	await test_ranged_basic_into_skills()
	await test_ranger_authored_bursts()
	await test_two_wave_finisher()
	await test_fifo_cap_and_validation()
	await test_revalidation_and_expiry()
	await test_cleanup()
	await test_dash_press_release_gate()
	await test_live_hud_combo()
	var capture_requested: bool = OS.get_environment("CODEX_CAPTURE_COMBOS") == "1" or OS.get_cmdline_user_args().has("--capture-combos")
	if capture_requested and DisplayServer.get_name() != "headless":
		await capture_live_combo()
	if is_instance_valid(hud_layer):
		hud_layer.free()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await frames(2)
	print("COMBAT COMBOS ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
