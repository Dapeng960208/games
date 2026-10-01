extends SceneTree
## Real proximity beacons drive the HUD. No fabricated UI buff dictionaries are used.
## Run through tools/test.ps1 -Suite hud_buffs with an isolated test_ profile.

const EFFECTS := ["damage", "guard", "haste"]
const DURATIONS := {"damage":15.0, "guard":15.0, "haste":12.0}
const PERCENTAGES := {"damage":"20%", "guard":"25%", "haste":"15%"}
const CLEAR_POINTER := Vector2(640, 360)
const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")

var checks := 0
var failures := 0
var app: Node
var game: Node
var room: Node2D
var hud: Control
var props: Node2D
var base_damage_bonus := 0.0
var base_move_speed := 0.0
var expected_haste_speed := 0.0
var graphical := false
var captures: Array[String] = []
var coverage: Dictionary = {}
var movement_measurements: Dictionary = {}

func _initialize() -> void:
	call_deferred("run_checks")
	create_timer(60.0).timeout.connect(func(): push_error("HUD buff suite timed out"); quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func frames(count: int = 3) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func mouse_move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func mouse_button(at: Vector2, index: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = at
	event.global_position = at
	event.pressed = down
	root.push_input(event, true)

func clear_hud_focus() -> void:
	var focus := root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	mouse_move(CLEAR_POINTER)
	hud.hovered_control = null
	hud.focused_control = null
	hud.last_hover_control = null
	hud.hover_grace = 0.0
	hud._update_tooltip()

func set_combat_running(enabled: bool) -> void:
	room.set_physics_process(enabled)
	room.player.set_physics_process(enabled)
	for enemy in room.enemies.get_children():
		enemy.set_physics_process(false)
		enemy.set_process(false)

func real_buff(effect: String) -> Dictionary:
	for state: Dictionary in props.active_buffs():
		if str(state.effect) == effect:
			return state
	return {}

func visible_chips() -> Array[Button]:
	var result: Array[Button] = []
	for child in hud.buff_row.get_children():
		if child is Button and child.is_visible_in_tree() and not child.is_queued_for_deletion():
			result.append(child)
	return result

func assert_chips(expected_effects: Array, context: String) -> void:
	hud.refresh()
	var actual := visible_chips()
	check(hud.buff_row.visible == not expected_effects.is_empty(), context + ": row visibility matches real active buffs")
	check(actual.size() == expected_effects.size(), context + ": exactly one visible chip per active kind")
	var seen: Dictionary = {}
	for chip in actual:
		var state: Dictionary = chip.state
		var effect: String = str(state.get("effect", ""))
		check(effect in expected_effects and not seen.has(effect), context + ": unique actual buff " + effect)
		seen[effect] = true
		var real_state := real_buff(effect)
		check(not real_state.is_empty(), context + ": chip is backed by RoomProps.active_buffs " + effect)
		if real_state.is_empty():
			continue
		check(is_equal_approx(float(state.remaining), float(real_state.remaining)), context + ": chip carries current remaining seconds " + effect)
		check(chip.remaining_seconds() == ceili(float(real_state.remaining)), context + ": countdown uses ceiling of real remaining " + effect)
		check(hud.buff_chips.get(effect) == chip, context + ": keyed chip identifies visible control " + effect)
		check(chip.size.x >= 44 and chip.size.y >= 44, context + ": buff interaction target is at least 44 px " + effect)
	var painted: Array[Rect2] = hud.active_buff_coverage_rects()
	check(painted.size() == expected_effects.size(), context + ": coverage includes only active buff backplates")
	for bounds in painted:
		check(bounds.size.is_equal_approx(Vector2(40, 40)), context + ": painted backplate stays 40 px")

func pickup_all() -> void:
	var count := 0
	for item: Dictionary in props.props:
		if str(item.kind) != "beacon":
			continue
		# Keep the three HUD effects deterministic while entering real seeded
		# beacons through the production automatic activation path.
		var effect: String = EFFECTS[count]
		item.merge(RoomProps.BUFFS[effect].duplicate(true),true)
		item.effect = effect
		room.player.position = item.position
		props.update(0.01)
		check(not real_buff(effect).is_empty(), "real automatic beacon approach grants " + effect)
		check(bool(item.used) and not bool(item.available), "real prop is consumed once " + str(item.effect))
		count += 1
	check(count == 3, "authored room exposes three real automatic buff beacons")

func tick_buffs(delta: float) -> void:
	# Both owning physics loops are stopped before deterministic advancement.
	# This is the same production countdown and CombatStatus expiry, once each.
	props.update(delta)
	room.player.status.tick(delta)
	hud.refresh()

func run_checks() -> void:
	# Pointer acceptance exercises real weapon/cast paths without speaker output.
	AudioServer.set_bus_mute(0, true)
	game = root.get_node("Game")
	graphical = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	if not game.profile_path.contains("test_"):
		push_error("Refusing HUD buff tests without isolated --test-profile=test_...")
		quit(2)
		return
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(), "create isolated HUD buff profile")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	check(game.select_hero("CH02"), "select real ranged hero for input acceptance")
	# Isolate room-owned buff behavior from the expedition's required entry choice.
	check(game.start_run(), "start legacy room for real buff pickups")
	await frames(4)
	room = app.room
	hud = app.hud
	check(is_instance_valid(room) and is_instance_valid(hud), "real app creates room and HUD")
	if not is_instance_valid(room) or not is_instance_valid(hud):
		quit(1)
		return
	props = room.enemy_props
	check(is_instance_valid(props), "real room owns production RoomProps")
	if not is_instance_valid(props):
		quit(1)
		return
	room.spawn_enabled = false
	set_combat_running(false)
	Words.set_locale("zh_CN")
	base_damage_bonus = room.player.stat("damage_bonus", 0.0)
	base_move_speed = room.player.stat("move_speed", 220.0)
	# The starter profile already equips movement bonuses. Room haste adds
	# 15 percentage points of the hero's base speed, within the shared 45% cap.
	var hero_base_speed: float = ContentRegistry.hero(game.run.hero_id).move_speed
	expected_haste_speed = minf(base_move_speed + hero_base_speed * 0.15, hero_base_speed * 1.45)
	assert_chips([], "before pickup")
	record_coverage("no_buffs")
	var status_bounds: Rect2 = hud.status_panel.get_global_rect()
	var buff_bounds: Rect2 = hud.buff_row.get_global_rect()
	check(is_equal_approx(buff_bounds.position.x, status_bounds.position.x) and buff_bounds.position.y >= status_bounds.end.y and not buff_bounds.intersects(status_bounds), "buff row aligns below the status panel without overlap")
	var lane := find_movement_lane(expected_haste_speed * 0.5 + Balance.PLAYER_RADIUS * 2.0)
	check(not lane.is_empty(), "authored geometry provides a swept clear movement lane")
	if not lane.is_empty():
		movement_measurements["baseline"] = await measure_keyboard_movement(lane, "before haste")
	pickup_all()
	if not lane.is_empty():
		movement_measurements["haste"] = await measure_keyboard_movement(lane, "after haste")
		var baseline: Dictionary = movement_measurements.baseline
		var accelerated: Dictionary = movement_measurements.haste
		check(is_equal_approx(float(baseline.duration), 0.5) and baseline.ticks == accelerated.ticks, "both real movement samples run for the same 0.5 seconds")
		check(absf(float(accelerated.distance) - float(baseline.distance) - (expected_haste_speed - base_move_speed) * 0.5) < 0.1, "actual haste travel gains the expected 15 percent base-speed contribution within cap")
		for effect: String in EFFECTS:
			check(props.grant_buff(effect, room.player), "refresh real buff after live movement measurement " + effect)
	assert_chips(EFFECTS, "all pickups active")
	check_buff_artwork()
	record_coverage("three_buffs")
	check(is_equal_approx(room.player.stat("damage_bonus", 0.0), base_damage_bonus + 0.20), "damage pickup adds real 20 percent attack bonus")
	check(is_equal_approx(room.player.status.shield(), float(game.run.max_hp) * 0.25), "guard pickup grants real 25 percent max-HP CombatStatus shield")
	check(is_equal_approx(props.move_multiplier(), 1.15) and is_equal_approx(room.player.stat("move_speed", 220.0), expected_haste_speed), "haste pickup adds real 15 percent base movement speed within the shared cap")
	await check_tooltips()
	check_countdown_and_refresh()
	await check_pause()
	check_expiry_and_room_reset()
	await check_live_input()
	clear_hud_focus()
	Input.action_release("attack")
	Input.action_release("skill_secondary")
	set_combat_running(false)
	check(await room.combat_audio.wait_for_cleanup(), "combat audio releases playback before fixture teardown")
	game.finish_run("extracted")
	await frames()
	write_coverage_report()
	app.set_process(false)
	check(await app.music.wait_for_cleanup(), "music releases playback before fixture teardown")
	app.free()
	await frames(8)
	print("HUD_BUFFS_TEST_RESULT checks=", checks, " failures=", failures, " captures=", captures.size(), " graphics=", graphical)
	quit(1 if failures else 0)

func find_movement_lane(distance: float) -> Dictionary:
	# Ask the actual room collision geometry; no authored room coordinate is
	# assumed to remain open. Both experiments reuse the exact returned lane.
	var anchors: Array = [room.layout.entry]
	anchors.append_array(room.layout.get("topology_probes", []))
	anchors.append_array(room.layout.get("objective_points", []))
	anchors.append_array(room.layout.get("spawn_points", []))
	var directions := {"move_right":Vector2.RIGHT, "move_down":Vector2.DOWN, "move_left":Vector2.LEFT, "move_up":Vector2.UP}
	for at: Vector2 in anchors:
		if not room.valid_ground(at, Balance.PLAYER_RADIUS):
			continue
		for action: String in directions:
			var direction: Vector2 = directions[action]
			var target := at + direction * distance
			if room.blocked_fraction(at, target, Balance.PLAYER_RADIUS) < 1.0:
				continue
			if not room.move_actor(at, direction * distance, Balance.PLAYER_RADIUS).is_equal_approx(target):
				continue
			var crosses_beacon := false
			for item: Dictionary in props.props:
				var closest := Geometry2D.get_closest_point_to_segment(item.position,at,target)
				crosses_beacon = crosses_beacon or closest.distance_to(item.position) <= RoomProps.BEACON_RADIUS
			if crosses_beacon: continue
			return {"position":at, "direction":direction, "action":action, "clear_distance":distance}
	return {}

func measure_keyboard_movement(lane: Dictionary, context: String) -> Dictionary:
	clear_hud_focus()
	var released := true
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "skill_secondary", "dash"]:
		released = released and not Input.is_action_pressed(action)
	check(released and room.controls_enabled(), context + ": movement starts with released inputs and active combat controls")
	check(room.player.knockback.is_zero_approx() and room.player.dash_remaining <= 0.0 and not room.player.abilities.busy(), context + ": movement has no knockback, dash or skill displacement")
	room.player.position = lane.position
	var speed: float = room.player.stat("move_speed", 220.0)
	var predicted_speed := base_move_speed if context == "before haste" else expected_haste_speed
	check(is_equal_approx(speed, predicted_speed), context + ": production movement stat matches the expected equipment and prop bonuses")
	var steps: int = roundi(Engine.physics_ticks_per_second * 0.5)
	# SceneTree emits physics_frame before node physics. Begin and release on
	# that same boundary, giving the real Player exactly `steps` input polls.
	await physics_frame
	set_combat_running(true)
	var first_frame: int = Engine.get_physics_frames()
	Input.action_press(str(lane.action))
	for _index in range(steps):
		await physics_frame
	Input.action_release(str(lane.action))
	set_combat_running(false)
	var ticks: int = Engine.get_physics_frames() - first_frame
	var duration := float(ticks) / Engine.physics_ticks_per_second
	var displacement: Vector2 = room.player.position - Vector2(lane.position)
	var distance := displacement.length()
	check(ticks == steps and absf(distance - speed * duration) < 0.1, context + ": real keyboard movement distance matches speed over 30 physics ticks")
	check(displacement.normalized().is_equal_approx(Vector2(lane.direction)) and room.player.knockback.is_zero_approx(), context + ": actual movement remains straight and free of knockback")
	return {"ticks":ticks, "duration":duration, "speed":speed, "distance":distance, "start":[lane.position.x, lane.position.y], "direction":[lane.direction.x, lane.direction.y], "clear_distance":lane.clear_distance}

func check_buff_artwork() -> void:
	# Read back each texture only once; normal per-frame HUD checks need no image
	# copies. This covers the actual textures drawn by the three active controls.
	for effect: String in EFFECTS:
		var chip: Button = hud.buff_chips[effect]
		var texture: Texture2D = chip.generated_texture
		var artwork: Image = texture.get_image() if texture != null else null
		check(texture != null and artwork != null and not artwork.is_empty(), "active buff uses generated artwork " + effect)
		check(artwork != null and artwork.has_mipmaps() and chip.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "active buff artwork uses mipmapped linear sampling " + effect)
		check(chip.get_theme_font_size("font_size") >= 16, "buff countdown font stays at least 16 px " + effect)
		var suffix := "pressure" if effect == "damage" else effect
		check(texture == TextureSampler.sampled("res://assets/generated/props/buff_" + suffix + "_v1.png"), "buff artwork shares the production sampled texture cache " + effect)

func check_tooltips() -> void:
	for locale: String in ["zh_CN", "en"]:
		Words.set_locale(locale)
		clear_hud_focus()
		hud.refresh()
		await capture("hud_buffs_" + locale + "_1280")
		for effect: String in EFFECTS:
			clear_hud_focus()
			var chip: Button = hud.buff_chips[effect]
			var info: Dictionary = hud.buff_info(effect)
			check(not str(info.name).is_empty() and str(info.description).contains(PERCENTAGES[effect]), locale + ": tooltip names the real effect and percentage " + effect)
			check(is_equal_approx(float(info.duration), float(DURATIONS[effect])) and is_equal_approx(float(info.remaining), float(real_buff(effect).remaining)), locale + ": tooltip duration and remaining match real buff " + effect)
			check(info.state is Dictionary and info.state == real_buff(effect), locale + ": tooltip state comes directly from RoomProps " + effect)
			check(str(info.summary).contains(str(int(DURATIONS[effect]))), locale + ": tooltip summary includes full duration " + effect)
			var note := str(info.note).to_lower()
			check((note.contains("刷新") and note.contains("不叠加")) if locale == "zh_CN" else (note.contains("refresh") and note.contains("stack")), locale + ": tooltip explains refresh without stacking " + effect)
			chip.grab_focus()
			hud._update_tooltip()
			check(hud.tooltip_panel.visible and hud.active_detail_slot == "buff:" + effect and hud.tooltip_title.text == str(info.name), locale + ": keyboard focus exposes correct buff tooltip " + effect)
			for field: String in ["description", "summary", "note"]:
				check(not str(info[field]).is_empty() and hud.tooltip_body.text.contains(str(info[field])), locale + ": keyboard tooltip includes " + field + " for " + effect)
			if effect == "damage":
				await capture("hud_buffs_tooltip_" + locale + "_1280")
			chip.release_focus()
			mouse_move(chip.get_global_rect().get_center())
			await frames(2)
			hud._update_tooltip()
			check(not chip.has_focus() and hud.tooltip_panel.visible and hud.tooltip_title.text == str(info.name), locale + ": actual pointer hover exposes buff tooltip " + effect)
	clear_hud_focus()
	Words.set_locale("zh_CN")
	hud.refresh()

func check_countdown_and_refresh() -> void:
	tick_buffs(1.25)
	assert_chips(EFFECTS, "fractional countdown")
	for effect: String in EFFECTS:
		check(is_equal_approx(float(real_buff(effect).remaining), float(DURATIONS[effect]) - 1.25), "timer advances once for " + effect)
		check(props.grant_buff(effect, room.player), "production grant_buff refresh succeeds for " + effect)
		check(is_equal_approx(float(real_buff(effect).remaining), float(DURATIONS[effect])), "refresh resets real duration for " + effect)
	assert_chips(EFFECTS, "same-kind refresh")
	check(props.active_buffs().size() == 3 and is_equal_approx(room.player.stat("damage_bonus", 0.0), base_damage_bonus + 0.20), "refresh creates no extra damage stack")
	check(room.player.status.guards.size() == 1 and is_equal_approx(room.player.status.shield(), float(game.run.max_hp) * 0.25), "refresh creates no extra guard source or shield amount")
	check(is_equal_approx(room.player.stat("move_speed", 220.0), expected_haste_speed), "refresh creates no extra haste stack")

func check_pause() -> void:
	# Restore production loops before pausing: unchanged timers must be caused by
	# the actual pause modal, not by the deterministic fixture's disabled physics.
	set_combat_running(true)
	app.show_pause()
	check(paused and not app.modals.is_empty(), "real pause modal pauses the scene tree")
	var before: Dictionary = {}
	for effect: String in EFFECTS:
		before[effect] = float(real_buff(effect).remaining)
	var guard_remaining: float = room.player.status.guards[RoomProps.GUARD_SOURCE].remaining
	props.update(2.0)
	await frames(6)
	for effect: String in EFFECTS:
		check(is_equal_approx(float(real_buff(effect).remaining), float(before[effect])), "pause freezes production buff timer " + effect)
	check(is_equal_approx(float(room.player.status.guards[RoomProps.GUARD_SOURCE].remaining), guard_remaining), "pause freezes real CombatStatus guard timer")
	assert_chips(EFFECTS, "paused countdown")
	set_combat_running(false)
	app._pop_modal()
	check(not paused, "closing pause modal restores tree")
	clear_hud_focus()

func check_expiry_and_room_reset() -> void:
	tick_buffs(11.75)
	assert_chips(EFFECTS, "last fractional haste second")
	check(hud.buff_chips.haste.remaining_seconds() == 1, "positive fractional duration displays one second")
	tick_buffs(0.25)
	assert_chips(["damage", "guard"], "haste expires independently")
	check(is_equal_approx(room.player.stat("move_speed", 220.0), base_move_speed), "haste expiry restores real movement speed")
	tick_buffs(3.0)
	assert_chips([], "all durations expired")
	check(is_equal_approx(room.player.stat("damage_bonus", 0.0), base_damage_bonus) and is_zero_approx(room.player.status.shield()), "expiry removes real damage and guard effects")
	for effect: String in EFFECTS:
		check(props.grant_buff(effect, room.player), "restore real buff before clear " + effect)
	hud.refresh()
	hud.buff_chips.damage.grab_focus()
	hud._update_tooltip()
	check(hud.tooltip_panel.visible, "active buff tooltip exists before room clear")
	props.clear()
	assert_chips([], "room props clear")
	hud._update_tooltip()
	check(not hud.tooltip_panel.visible and not room.player.status.guards.has(RoomProps.GUARD_SOURCE), "clear removes own guard and stale tooltip")
	props.configure(room, room.layout)
	pickup_all()
	assert_chips(EFFECTS, "reconfigured room pickups")
	props.configure(room, room.layout)
	assert_chips([], "room props configure resets active buffs")
	check(props.active_buffs().is_empty() and not room.player.status.guards.has(RoomProps.GUARD_SOURCE), "configure clears room-owned states and guard source")
	check(props.grant_buff("guard", room.player), "grant real guard before shield depletion check")
	check(props.grant_buff("damage", room.player) and props.grant_buff("haste", room.player), "grant real companion buffs before zero-time depletion cleanup")
	assert_chips(EFFECTS, "shield before depletion")
	var guard_remaining: float = real_buff("guard").remaining
	var damage_remaining: float = real_buff("damage").remaining
	var haste_remaining: float = real_buff("haste").remaining
	room.player.status.absorb(room.player.status.shield())
	# CombatStatus removes depleted sources on its production tick, without
	# advancing any duration here. Depletion should not await the 15s expiry.
	var status_clock: float = room.player.status.clock
	var shock_cooldown: float = room.player.status.shock_cooldown
	check(room.player.status.tick(-1.0).is_empty() and room.player.status.tick(NAN).is_empty() and room.player.status.tick(INF).is_empty(), "invalid time emits no status damage")
	check(room.player.status.guards.has(RoomProps.GUARD_SOURCE) and is_equal_approx(room.player.status.clock, status_clock), "invalid time cannot mutate a depleted guard or status clock")
	check(room.player.status.tick(0.0).is_empty(), "zero time cleans guard without emitting status damage")
	check(is_equal_approx(room.player.status.clock, status_clock) and is_equal_approx(room.player.status.shock_cooldown, shock_cooldown), "zero time preserves clock and shock cooldown")
	assert_chips(["damage", "haste"], "absorbed guard hides before duration expiry")
	check(guard_remaining > 0.0 and real_buff("guard").is_empty(), "depleted CombatStatus shield disappears from real active_buffs immediately")
	check(is_equal_approx(float(real_buff("damage").remaining), damage_remaining) and is_equal_approx(float(real_buff("haste").remaining), haste_remaining), "zero-time guard cleanup does not advance other buff durations")
	props.configure(room, room.layout)
	hud.set_interaction_enabled(false)
	check(props.grant_buff("damage", room.player), "grant real buff while modal interaction is disabled")
	hud.refresh()
	check(hud.buff_chips.damage.focus_mode == Control.FOCUS_NONE, "new buff chips stay outside modal keyboard focus order")
	hud.set_interaction_enabled(true)
	check(hud.buff_chips.damage.focus_mode == Control.FOCUS_ALL, "reenabling HUD restores buff chip keyboard access")
	props.configure(room, room.layout)
	assert_chips([], "final reset before live input")

func check_live_input() -> void:
	pickup_all()
	hud.refresh()
	check(game.grant_hero_xp(3600, "hud_buff_input_unlocks"), "unlock secondary through real XP API")
	game.restore_resource(1000)
	room.player.position = room.layout.entry
	clear_hud_focus()
	set_combat_running(true)
	await frames(4)
	check(room.controls_enabled() and room.player.is_physics_processing(), "live combat controls run for pointer acceptance")
	for surface: String in ["chip", "tooltip"]:
		for button: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			await check_pointer_surface(surface, button)
	clear_hud_focus()
	await frames(3)
	var shots_before: int = game.run.shots
	Input.action_press("attack")
	await frames(ceili(float(game.run.stats.attack_interval) * Engine.physics_ticks_per_second) + 8)
	Input.action_release("attack")
	check(game.run.shots > shots_before, "released pointer gate permits a fresh real weapon attack")
	await frames(3)
	var secondary_before: float = room.player.cooldowns.secondary
	Input.action_press("skill_secondary")
	await frames(2)
	Input.action_release("skill_secondary")
	check(secondary_before <= 0.0 and room.player.cooldowns.secondary > 0.0, "released pointer gate permits a fresh real secondary cast")

func check_pointer_surface(surface: String, button: MouseButton) -> void:
	clear_hud_focus()
	await frames(2)
	var chip: Button = hud.buff_chips.damage
	mouse_move(chip.get_global_rect().get_center())
	await frames(2)
	hud._update_tooltip()
	var at: Vector2 = chip.get_global_rect().get_center()
	if surface == "tooltip":
		check(hud.tooltip_panel.visible, "buff tooltip is visible before pointer blocking test")
		at = hud.tooltip_panel.get_global_rect().get_center()
		mouse_move(at)
		await frames(2)
	var action := "attack" if button == MOUSE_BUTTON_LEFT else "skill_secondary"
	var context := surface + " " + ("LMB" if button == MOUSE_BUTTON_LEFT else "RMB")
	var shots_before: int = game.run.shots
	var secondary_before: float = room.player.cooldowns.secondary
	mouse_button(at, button, true)
	var guarded_on_press: bool = room.pointer_input_blocked
	Input.action_press(action)
	await frames(3)
	check(guarded_on_press and not room.pointer_controls_enabled(), context + ": surface blocks pointer combat immediately")
	check(game.run.shots == shots_before and is_equal_approx(float(room.player.cooldowns.secondary), secondary_before), context + ": click leaks neither attack nor secondary")
	check(app.modals.is_empty() and not paused, context + ": buff interaction keeps combat running without a skill modal")
	for _index in range(app.modals.size()):
		var modal_count: int = app.modals.size()
		app._pop_modal()
		if app.modals.size() >= modal_count:
			check(false, context + ": unexpected modal could not be dismissed")
			break
	mouse_move(CLEAR_POINTER)
	await frames(8)
	check(not paused and not room.pointer_controls_enabled(), context + ": dragging held button outside preserves release gate")
	check(game.run.shots == shots_before and is_equal_approx(float(room.player.cooldowns.secondary), secondary_before), context + ": held input remains blocked outside HUD")
	mouse_button(CLEAR_POINTER, button, false)
	Input.action_release(action)
	clear_hud_focus()
	await frames(3)
	check(room.pointer_controls_enabled(), context + ": releasing clears pointer gate")

func capture(filename: String) -> void:
	if not graphical:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(not frame.is_empty() and frame.get_size() == Vector2i(1280, 720), "actual buff screenshot resolution " + filename)
	var saved: bool = frame.save_png("res://artifacts/" + filename + ".png") == OK
	check(saved, "save actual engine buff screenshot " + filename)
	if saved:
		captures.append(filename + ".png")

func rect_data(bounds: Rect2) -> Dictionary:
	return {"x":bounds.position.x, "y":bounds.position.y, "width":bounds.size.x, "height":bounds.size.y}

func union_area(rectangles: Array[Rect2]) -> float:
	var edges: Array[float] = []
	for bounds in rectangles:
		if not edges.has(bounds.position.x): edges.append(bounds.position.x)
		if not edges.has(bounds.end.x): edges.append(bounds.end.x)
	edges.sort()
	var result := 0.0
	for index in range(edges.size() - 1):
		var left := edges[index]
		var right := edges[index + 1]
		var intervals: Array[Vector2] = []
		for bounds in rectangles:
			if bounds.position.x < right and bounds.end.x > left:
				intervals.append(Vector2(bounds.position.y, bounds.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		var height := 0.0
		var end := -INF
		for interval in intervals:
			if interval.x > end:
				height += interval.y - interval.x
			elif interval.y > end:
				height += interval.y - end
			end = maxf(end, interval.y)
		result += (right - left) * height
	return result

func record_coverage(key: String) -> void:
	var standing: Array[Rect2] = hud.coverage_rects()
	var painted: Array[Rect2] = hud.active_buff_coverage_rects()
	var combined: Array[Rect2] = standing.duplicate()
	combined.append_array(painted)
	var standing_data: Array[Dictionary] = []
	var buff_data: Array[Dictionary] = []
	for bounds in standing: standing_data.append(rect_data(bounds))
	for bounds in painted: buff_data.append(rect_data(bounds))
	var buff_area := union_area(painted)
	coverage[key] = {
		"standing_rects":standing_data,
		"standing_union_px":union_area(standing),
		"standing_coverage":union_area(standing) / (1280.0 * 720.0),
		"active_buff_painted_rects":buff_data,
		"active_buff_painted_union_px":buff_area,
		"active_buff_painted_coverage":buff_area / (1280.0 * 720.0),
		"combined_union_px":union_area(combined),
		"combined_coverage":union_area(combined) / (1280.0 * 720.0),
		"row_bounds":rect_data(hud.buff_row.get_global_rect()),
		"row_visible":hud.buff_row.visible
	}
	if key == "three_buffs":
		check(is_equal_approx(buff_area, 4800.0), "three 40px buff backplates add exactly 4800 painted pixels")
		check(hud.buff_row.size.is_equal_approx(Vector2(140, 44)), "three active buff targets occupy a 140 by 44 row")
		check(coverage.no_buffs.standing_rects == standing_data, "active buffs preserve the original standing HUD coverage rectangles")

func write_coverage_report() -> void:
	var report := {
		"logical_viewport":[1280, 720],
		"graphics":graphical,
		"captures":captures,
		"fixture":"Real CH02 app room. Three seeded automatic RoomProps beacons have their real effect definitions fixed to damage/guard/haste and activate through player approach plus production update, without E. Movement lanes avoid beacon activation rings. Room/player physics are stopped only for deterministic status ticks and rendered screenshots; input checks restore both production physics loops.",
		"movement_measurements":movement_measurements,
		"measurements":coverage
	}
	var file := FileAccess.open("res://artifacts/hud_buffs_coverage.json", FileAccess.WRITE)
	check(file != null, "independent buff coverage report can be written")
	report["checks"] = checks
	report["failures"] = failures
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
