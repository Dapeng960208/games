extends Node
## Real mapped input and automatic production physics. Timeline evidence comes
## from actual releases, projectiles, contact damage and resource commitment.

const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Growth = preload("res://scripts/domain/progression/skill_progression.gd")
const ACTIONS: Array[String] = ["attack", "skill_q", "skill_secondary", "skill_f", "skill_ultimate", "dash"]
var stage: SubViewport
var room: RoomController
var target: EnemyActor
var hud: Control
var hud_layer: CanvasLayer
var events: Array[Dictionary] = []
var projectiles: Dictionary = {}
var damage_packets: Array[Dictionary] = []
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
	var action: String = slot if slot in ["attack", "dash"] else "skill_" + slot
	mapped(action, true)
	await frames()
	mapped(action, false)

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
		"ultimate_releases":releases("ultimate"), "projectiles":projectiles.duplicate(true),
		"class_state":room.player.class_state_view(), "role_state":room.player.export_role_state(),
		"damage_packets":damage_packets.duplicate(true)})

func projectile_entered(node: Node) -> void:
	if node is ProjectileActor:
		var slot: String = str(node.source)
		projectiles[slot] = int(projectiles.get(slot, 0)) + 1
		# spawn_ability_projectile writes its frozen options after adding the node.
		# Keep immediate source counts for legacy cases, then observe the actual ID.
		call_deferred("observe_projectile_identity", node, room.get_instance_id())

func observe_projectile_identity(node: ProjectileActor, room_id: int) -> void:
	if not is_instance_valid(node) or not is_instance_valid(room) or room.get_instance_id() != room_id:
		return
	var identifier: String = str(node.options.get("skill_id", ""))
	if not identifier.is_empty():
		projectiles[identifier] = int(projectiles.get(identifier, 0)) + 1

func observe_target_damage(amount: float) -> void:
	# EnemyActor records the original receipt before CombatHealth emits damaged;
	# later shock/equipment packets cannot replace this saved contact evidence.
	damage_packets.append({"context":target.last_damage_context.duplicate(true),
		"receipt":target.last_damage_result.duplicate(true), "amount":amount})

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

func fixture(hero: String = "CH01", level: int = 8, maximum: float = 100.0, branches: Dictionary = {}, current_skills: Dictionary = {}) -> void:
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
	var current: bool = not current_skills.is_empty()
	if current:
		Game.run.frozen_versions = Numbers.frozen_versions(Numbers.V2)
		Game.profile.merge(Growth.fresh_fields(), true)
		var selected: Array[String] = []
		selected.assign(current_skills.get("loadout", Growth.starter_ids(hero)))
		for identifier: String in selected:
			var index: int = Growth.skill_ids(hero).find(identifier)
			if index >= 4:
				Game.profile = Growth.unlock_group(Game.profile, Growth.GROUPS[index - 4])
		var choices: Dictionary = {hero + "_SK01":"", hero + "_SK04":""}
		choices.merge(current_skills.get("branches", {}), true)
		var progress: Dictionary = Game.profile.skill_state[hero]
		progress.loadout = selected.duplicate()
		progress.branches = choices.duplicate(true)
		for identifier: String in choices:
			if not str(choices[identifier]).is_empty():
				progress.mastery[identifier] = 140 if identifier.ends_with("SK01") else 300
		Game.run.skill_loadout_snapshot = selected.duplicate()
		Game.run.skill_branches_snapshot = choices.duplicate(true)
		Game.run.loadout_snapshot = {}
		Game.run.resource_regen_remainder = 0.0
		Game.run.resource_decay_remainder = 0.0
		Game.profile.settings["auto_attack"] = false
	Game.run.stats = StatResolver.resolve(hero, level, {}, {}, Numbers.V2) if current else StatResolver.resolve(hero, level, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.stats["resource_regen"] = 0.0
	Game.run.stats["branches"] = branches.duplicate(true)
	# Long-sequence stress fixtures explicitly enlarge only the resource tank.
	# Canonical costs/cooldowns stay unchanged; separate 100-resource tests prove
	# that queued commands cannot reserve or overspend future resources.
	var tank: float = units(maximum) if current else maximum
	Game.run.stats["resource_max"] = tank
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = tank
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
	if current:
		target.health.reset(10000.0, Numbers.V2)
		target.armor = 0.0
		target.magic_resist = 0.0
		target.health.damaged.connect(observe_target_damage)
	else:
		target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	target.set_physics_process(false) # A stationary target keeps authored knockback from leaving the strike sector.
	aim(target.position)
	await frames(6)
	events.clear()
	projectiles.clear()
	damage_packets.clear()
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
	hud = load(AssetCatalog.resolve("res://scripts/presentation/hud/hud.gd")).new()
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
	var manifest := FileAccess.open(AssetCatalog.resolve(path.path_join("captures.json")), FileAccess.WRITE)
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
		var saved_player: HeroActor = room.player
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

func units(amount: float) -> float:
	return float(Numbers.scale(amount, Numbers.V2))

func current_fixture(hero: String, loadout: Array = [], branches: Dictionary = {}) -> void:
	await fixture(hero, 20, 100.0, {}, {
		"loadout":Growth.starter_ids(hero) if loadout.is_empty() else loadout, "branches":branches})
	check(Game.run.ruleset_version() == Numbers.V2 and Growth.valid_loadout(
		Game.run.skill_loadout_snapshot, hero, Game.profile.skill_state[hero].learned),
		hero + " continuity fixture uses learned stable identities and the frozen V2 loadout")

func skill_releases(identifier: String) -> int:
	var count := 0
	for event: Dictionary in room.player.get_node("HeroFeedback").release_events:
		if str(event.get("skill_id", "")) == identifier:
			count += 1
	return count

func released_identities() -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for event: Dictionary in room.player.get_node("HeroFeedback").release_events:
		var serial: int = int(event.serial)
		if not seen.has(serial):
			seen[serial] = true
			result.append(str(event.skill_id))
	return result

func wait_skill_release(identifier: String, count: int = 1, limit: int = 180) -> bool:
	for _index in limit:
		if skill_releases(identifier) >= count:
			return true
		await frames()
	return false

func loadout_event_count(prefix: String) -> int:
	var count := 0
	for root: Dictionary in room.player.loadout.effects.roots.values():
		for key: String in root.seen:
			if key.begins_with(prefix + ":"):
				count += 1
	return count

func test_long_skill_queue_continuity() -> void:
	for long_id: String in ["CH03_SK08", "CH03_SK11"]:
		await current_fixture("CH03", ["CH03_SK01", long_id, "CH03_SK03", "CH03_SK02"])
		var long_cost: float = float(room.player.skill_definition("secondary").cost)
		await press("q")
		await press("secondary")
		await press("f")
		check(count_reason("queued", "secondary") == 1 and count_reason("queued", "f") == 1,
			long_id + " admits deliberate Q, long W, guard E input in FIFO order")
		check(await wait_accepted("secondary"), long_id + " really commits after the Q release")
		check(await wait_skill_release(long_id), long_id + " really begins its finite pulse timeline")
		var long_cast: Dictionary = room.player.abilities.active.duplicate(true)
		await frames(60)
		check(room.player.abilities.busy() and str(room.player.abilities.active.get("skill_id", "")) == long_id
			and room.player.queued_action_position("f") == 1 and count_reason("accepted", "f") == 0,
			long_id + " keeps accepted E pending beyond 0.90 seconds while W still owns future pulses")
		check(cause_count("buffer_expired") == 0 and is_equal_approx(Game.run.resource, units(88.0) - long_cost),
			long_id + " pending E neither expires from total queue age nor reserves its resource")
		check(await wait_skill_release(long_id, 5), long_id + " preserves initial release and all four authored pulses")
		var contacts: Array[Dictionary] = []
		for packet: Dictionary in damage_packets:
			if str(packet.context.get("skill_id", "")) == long_id and int(packet.context.get("cast_id", -1)) == int(long_cast.serial) and int(packet.context.get("proc_depth", -1)) == 0:
				contacts.append(packet)
		check(contacts.size() == 4, long_id + " delivers exactly four original real pulse contacts, separate from derived shock and E")
		for index in contacts.size():
			var packet: Dictionary = contacts[index]
			var context: Dictionary = packet.context
			check(float(context.get("power", -1.0)) == float(long_cast.power) and float(context.get("H", -1.0)) == float(long_cast.power)
				and bool(context.get("equipment_eligible", false)) and not bool(context.get("original_basic", true))
				and str(context.get("attack_id", "")) == "skill:%d:%d" % [int(long_cast.serial), index + 1],
				long_id + " pulse " + str(index + 1) + " retains its frozen power/H, original skill flags and unique authored index")
			check(bool(packet.receipt.get("confirmed", false)) and float(packet.receipt.get("hp_damage", 0.0)) > 0.0
				and float(packet.receipt.get("shield_damage", -1.0)) == 0.0
				and float(packet.amount) == float(packet.receipt.get("hp_damage", -1.0)),
				long_id + " pulse " + str(index + 1) + " really consumes enemy HP through the original receipt")
		check(await wait_accepted("f"), long_id + " automatically starts its admitted E after the final W release")
		var contacts_before_e: int = 0
		for packet: Dictionary in event_for("accepted", "f").get("damage_packets", []):
			if str(packet.context.get("skill_id", "")) == long_id and int(packet.context.get("cast_id", -1)) == int(long_cast.serial) and int(packet.context.get("proc_depth", -1)) == 0 and bool(packet.receipt.get("confirmed", false)):
				contacts_before_e += 1
		check(contacts_before_e == 4, long_id + " admitted E begins only after all four real W contacts have completed")
		check(await wait_skill_release("CH03_SK03"), long_id + " follow-up E produces its actual guard release")
		await wait_idle(180)
		check(accepted_slots() == ["q", "secondary", "f"]
			and released_identities() == ["CH03_SK01", long_id, "CH03_SK03"],
			long_id + " commits and releases exactly the three requested identities in order")
		check(room.player.abilities.cast_serial == 3 and skill_releases("CH03_SK01") == 1
			and skill_releases(long_id) == 5 and skill_releases("CH03_SK03") == 1
			and int(projectiles.get("CH03_SK01", 0)) == 1,
			long_id + " creates one Q projectile, one W cast with four pulses, and one E cast")
		check(is_equal_approx(Game.run.resource, units(68.0) - long_cost) and Game.run.shield > 0.0
			and int(room.player.class_state_view().starlight) == 3 and room.player.combo_queue.is_empty(),
			long_id + " spends each skill once, grants the real shield, and accumulates only three release stacks")

func test_continuity_rejection_and_cancel() -> void:
	var selected: Array = ["CH03_SK01", "CH03_SK08", "CH03_SK03", "CH03_SK02"]
	await current_fixture("CH03", selected)
	await press("secondary")
	await press("f")
	check(cause_count("early_chain") == 1 and room.player.combo_queue.is_empty()
		and count_reason("accepted", "f") == 0 and room.player.skill_cooldown("f") == 0.0,
		"a first input too early in a long W remains explicitly rejected without an E commitment")
	check(is_equal_approx(Game.run.resource, units(72.0)), "early rejection pays only the real 28-Mana W")
	await wait_idle(180)
	check(skill_releases("CH03_SK08") == 5 and skill_releases("CH03_SK03") == 0,
		"early rejection preserves the full W timeline and never turns into a late E")
	await current_fixture("CH03", selected)
	await press("q")
	await press("secondary")
	check(count_reason("queued", "secondary") == 1, "external-cooldown case first admits W into its real Q chain window")
	# A later real cooldown constraint must exhaust the original head budget.
	# No queue timers are changed, and production physics alone drives expiry.
	room.player.cooldowns["CH03_SK08"] = 1.0
	await frames(75)
	check(cause_count("buffer_expired") == 1 and count_reason("accepted", "secondary") == 0
		and room.player.combo_queue.is_empty() and skill_releases("CH03_SK08") == 0,
		"a head blocked by an external cooldown expires once and does not retry when that cooldown clears")
	check(room.player.abilities.cast_serial == 1 and skill_releases("CH03_SK01") == 1
		and is_equal_approx(Game.run.resource, units(88.0)),
		"expired W has no serial, release, or resource payment")
	await current_fixture("CH03", selected)
	await press("q")
	await press("secondary")
	await press("f")
	check(room.player.queued_action_position("f") == 2,
		"external-promotion case accepts E behind queued W before the new constraint exists")
	room.player.cooldowns["CH03_SK03"] = 5.0
	check(await wait_accepted("secondary"), "external-promotion case really promotes E while finite W starts")
	await frames(180)
	check(skill_releases("CH03_SK08") == 5 and cause_count("buffer_expired") == 1
		and room.player.combo_queue.is_empty() and count_reason("accepted", "f") == 0
		and room.player.skill_cooldown("f") > 0.0,
		"promoted E expires after W's finite timeline plus its one window without inheriting the added five-second cooldown")
	await frames(150)
	check(room.player.skill_cooldown("f") == 0.0 and skill_releases("CH03_SK03") == 0
		and room.player.abilities.cast_serial == 2 and is_equal_approx(Game.run.resource, units(60.0)),
		"externally delayed E never releases or pays later after its added cooldown eventually clears")
	await current_fixture("CH03", selected)
	await press("q")
	await press("secondary")
	await press("f")
	await press("ultimate")
	await press("attack")
	check(room.player.combo_queue.size() == 3 and cause_count("queue_full") == 1,
		"long-action admission retains the three-request cap and explicitly rejects a fourth follow-up")
	await wait_idle(240)
	check(accepted_slots() == ["q", "secondary", "f", "ultimate"]
		and count_reason("accepted", "attack") == 0 and int(room.telemetry.shots) == 0
		and room.player.abilities.cast_serial == 4 and room.player.combo_queue.is_empty(),
		"all three admitted long-combo requests retain FIFO order and the rejected fourth never executes")
	await current_fixture("CH03", selected)
	await press("q")
	await press("secondary")
	await press("f")
	check(await wait_accepted("secondary"), "cancel case reaches its real long W with E pending")
	await frames(60)
	check(room.player.queued_action_position("f") == 1, "cancel case still has its promised E after the old global-age limit")
	var released_before: int = skill_releases("CH03_SK08")
	var hp_before: float = target.health.current
	room.player.cancel_actions()
	await frames(180)
	check(room.player.combo_queue.is_empty() and not room.player.abilities.busy()
		and count_reason("accepted", "f") == 0 and skill_releases("CH03_SK03") == 0
		and room.player.skill_cooldown("f") == 0.0,
		"explicit cancellation clears the accepted queue and prevents every delayed E side effect")
	check(skill_releases("CH03_SK08") == released_before and target.health.current == hp_before
		and room.player.abilities.cast_serial == 2 and is_equal_approx(Game.run.resource, units(60.0)),
		"cancelling long W keeps paid casts and prior contacts but drops all future pulse releases")

func test_gunner_completed_recovery() -> void:
	for entry: Dictionary in [
		{"slot":"q", "branch":"", "refill":2, "shots":3, "chain_at":0.40},
		{"slot":"q", "branch":"B", "refill":4, "shots":3, "chain_at":0.40},
		{"slot":"ultimate", "branch":"B", "refill":7, "shots":4, "chain_at":0.99},
	]:
		for next_slot: String in ["attack", "secondary"]:
			var slot: String = str(entry.slot)
			var identifier: String = "CH02_SK01" if slot == "q" else "CH02_SK04"
			var branch_choices: Dictionary = {identifier:str(entry.branch)}
			await current_fixture("CH02", [], branch_choices)
			room.player.role_kit.ammo = 1 # Legal magazine setup; only real creations consume or refill it.
			var spec: Dictionary = room.player.skill_definition(slot)
			var follow_cost: float = 0.0 if next_slot == "attack" else float(room.player.skill_definition(next_slot).cost)
			await press(slot)
			check(await wait_skill_release(identifier, int(entry.shots)),
				identifier + str(entry.branch) + " releases every authored shot before recovery chaining")
			var finished_cast: Dictionary = room.player.abilities.active.duplicate(true)
			check(not finished_cast.is_empty() and room.player.class_state_view().ammo == 1,
				identifier + " skill shots leave the ordinary magazine unchanged before completion")
			await press(next_slot)
			check(count_reason("queued", next_slot) == 1 and await wait_accepted(next_slot),
				identifier + " chains to mapped " + next_slot + " through the actual last release window")
			var committed: Dictionary = event_for("accepted", next_slot)
			var elapsed: float = float(int(committed.get("frame", 0)) - int(event_for("accepted", slot).get("frame", 0))) / float(Engine.physics_ticks_per_second)
			check(elapsed >= float(entry.chain_at) - 1.0 / float(Engine.physics_ticks_per_second) - 0.0001
				and elapsed < float(spec.duration) + 0.0001,
				identifier + " takes the legal recovery window before the old full duration")
			var expected_ammo: int = 1 + int(entry.refill) - (1 if next_slot == "attack" else 0)
			var expected_enhanced: int = (2 if next_slot == "attack" else 3) if slot == "ultimate" else 0
			var state: Dictionary = committed.get("class_state", {})
			check(int(state.get("ammo", -1)) == expected_ammo and int(state.get("enhanced_shots", -1)) == expected_enhanced,
				identifier + str(entry.branch) + " completes its refill before the next real " + next_slot + " creation")
			check(int(committed.get("role_state", {}).get("finished_serial", -1)) == int(finished_cast.get("serial", -2))
				and skill_releases(identifier) == int(entry.shots) and int(projectiles.get(identifier, 0)) == int(entry.shots),
				identifier + " completes exactly its real serial without erasing any skill projectile")
			if next_slot == "secondary":
				check(room.player.abilities.busy() and str(room.player.abilities.active.get("skill_id", "")) == "CH02_SK02"
					and int(room.player.abilities.active.get("serial", 0)) == 2,
					identifier + " old completion leaves the newly committed rail cast and its serial intact")
			else:
				check(int(committed.get("shots", 0)) == 1 and int(committed.get("projectiles", {}).get("primary", 0)) == 1,
					identifier + " old completion leaves the next real basic projectile intact")
			check(room.player.abilities.cast_serial == (1 if next_slot == "attack" else 2)
				and is_equal_approx(Game.run.resource, units(100.0) - float(spec.cost) - follow_cost),
				identifier + " and its next action each commit their own payment exactly once")
			var ammo_before_duplicate: int = int(room.player.class_state_view().ammo)
			var enhanced_before_duplicate: int = int(room.player.class_state_view().enhanced_shots)
			room.player.role_kit.on_skill_finished(finished_cast)
			check(room.player.class_state_view().ammo == ammo_before_duplicate
				and room.player.class_state_view().enhanced_shots == enhanced_before_duplicate,
				identifier + " repeated completion callback cannot grant a second refill or enhancement")
			await wait_idle()
			await frames(30)
			check(room.player.class_state_view().ammo == expected_ammo
				and room.player.class_state_view().enhanced_shots == expected_enhanced,
				identifier + " passing its original end time cannot replay old completion rewards")
			check(target.health.current < 10000.0 and count_reason("accepted", next_slot) == 1
				and int(projectiles.get("primary", 0)) == (1 if next_slot == "attack" else 0),
				identifier + " combo retains real enemy contacts and exactly its requested basic creation")
			if slot == "q":
				check(loadout_event_count("gunner_q_completed") == 1,
					"Q recovery completion emits its actual equipment completion event only once")

func test_gunner_unfinished_cancellation() -> void:
	for entry: Dictionary in [{"slot":"q", "branch":""}, {"slot":"q", "branch":"B"}, {"slot":"ultimate", "branch":"B"}]:
		for mode: String in ["dash", "death"]:
			var slot: String = str(entry.slot)
			var identifier: String = "CH02_SK01" if slot == "q" else "CH02_SK04"
			await current_fixture("CH02", [], {identifier:str(entry.branch)})
			room.player.role_kit.ammo = 1
			var cost: float = float(room.player.skill_definition(slot).cost)
			await press(slot)
			check(await wait_skill_release(identifier), identifier + " cancellation case has one real shot in flight")
			check(not room.player.abilities.recovery_chain_ready(), identifier + " cancellation happens before future shots complete")
			var released_before: int = skill_releases(identifier)
			if mode == "dash":
				await press("dash")
			else:
				Game.run.hp = 0.0
			await frames(75)
			var state: Dictionary = room.player.class_state_view()
			check(int(state.ammo) == (3 if mode == "dash" else 1) and int(state.enhanced_shots) == 0,
				identifier + str(entry.branch) + " unfinished " + mode + " gives only its own valid dash refill, never skill completion refill")
			check(skill_releases(identifier) == released_before and int(projectiles.get(identifier, 0)) == released_before
				and int(room.player.export_role_state().finished_serial) == -1,
				identifier + " unfinished " + mode + " does not complete its serial or create future shots")
			check(room.player.abilities.cast_serial == 1 and is_equal_approx(Game.run.resource, units(100.0) - cost)
				and room.player.skill_cooldown(slot) > 0.0 and room.player.combo_queue.is_empty(),
				identifier + " cancelled commitment retains its one payment and identity cooldown")
			if slot == "q":
				check(loadout_event_count("gunner_q_completed") == 0,
					"unfinished Q emits no equipment movement-completion event")

func test_empty_reload_dash_gate() -> void:
	await current_fixture("CH02")
	room.player.role_kit.ammo = 0
	await frames(2)
	check(room.player.class_state_view().ammo == 0 and room.player.class_state_view().reloading,
		"an empty real gunner kit starts its automatic reload before the mapped dodge")
	await press("dash")
	check(room.player.dash_remaining > 0.0 and int(room.telemetry.dashes) == 1,
		"empty-magazine reload permits the actual gunner dodge")
	mapped("attack", true)
	await frames(30)
	check(count_reason("dashing", "attack") == 1 and count_reason("reloading", "attack") == 0
		and count_reason("ammo_empty", "attack") == 0,
		"a fresh press during empty-magazine dodge explicitly rejects dashing before reload availability")
	check(room.player.dash_remaining == 0.0 and room.player.class_state_view().ammo == 2
		and not room.player.class_state_view().reloading and int(room.telemetry.shots) == 0
		and int(projectiles.get("primary", 0)) == 0,
		"successful dodge really grants two rounds while a held rejected press creates no automatic shot")
	check(room.player.combo_queue.is_empty() and room.player.attack_buffer == 0.0,
		"rejected reload/dodge press leaves no queued action or held retry")
	mapped("attack", false)
	await frames(2)
	await press("attack")
	await frames(15)
	check(count_reason("accepted", "attack") == 1 and int(room.telemetry.shots) == 1
		and int(projectiles.get("primary", 0)) == 1 and room.player.class_state_view().ammo == 1,
		"real release and fresh press restore exactly one ordinary projectile and consume exactly one of the dodge rounds")
	check(target.health.current < 10000.0 and is_equal_approx(Game.run.resource, units(100.0)),
		"restored ordinary shot makes real enemy contact without spending skill energy")

func test_current_continuity() -> void:
	await test_long_skill_queue_continuity()
	await test_continuity_rejection_and_cancel()
	await test_gunner_completed_recovery()
	await test_gunner_unfinished_cancellation()
	await test_empty_reload_dash_gate()

func run_checks() -> void:
	if not Game.profile_path.contains("test_combat_combos"):
		get_tree().quit(2)
		return
	get_tree().create_timer(100.0).timeout.connect(func(): push_error("Combat combo fixture timeout"); get_tree().quit(1))
	AudioServer.set_bus_mute(0, true)
	var installer: Node = load(AssetCatalog.resolve("res://scripts/presentation/app/main.gd")).new()
	installer._install_inputs()
	installer.free()
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.handle_input_locally = true
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(stage)
	check(Game.new_profile() and Game.start_run(), "isolated combo profile starts real production run")
	var continuity_only: bool = Game.profile_path.contains("combat_combos_continuity")
	if not continuity_only:
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
	await test_current_continuity()
	var capture_requested: bool = OS.get_environment("CODEX_CAPTURE_COMBOS") == "1" or OS.get_cmdline_user_args().has("--capture-combos")
	if capture_requested and not continuity_only and DisplayServer.get_name() != "headless":
		await capture_live_combo()
	if is_instance_valid(hud_layer):
		hud_layer.free()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await frames(2)
	print("COMBAT COMBOS ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
