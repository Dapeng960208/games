extends SceneTree
## Production Main/Room/Game integration with frozen combat. The completion
## payload is an explicit deterministic reward fixture; actors, UI callbacks,
## saves, equipment decisions and successful restores use production code.
## Run with --script res://tests/equipment/test_field_equipment_ui.gd --
## --test-profile=user://test_field_equipment_ui.json
## Headless verifies controls/input/state, not rendered appearance.

const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const WordsScript = preload("res://scripts/infrastructure/localization/strings.gd")
const Schema = preload("res://scripts/domain/expedition/expedition_state.gd")
const EquipmentIcon = preload("res://scripts/presentation/components/equipment_icon.gd")
const EquipmentArt = preload("res://scripts/infrastructure/assets/equipment_art.gd")

class Fixture:
	extends Node
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

class RestoreProbe:
	extends Node2D
	var target: Node2D
	var failures_left := 1
	var restore_calls := 0
	var objective_complete: bool:
		get:
			return bool(target.objective_complete)
	var expedition_context: Dictionary:
		get:
			return target.expedition_context
	func expedition_runtime_snapshot() -> Dictionary:
		return target.expedition_runtime_snapshot()
	func restore_expedition_runtime(runtime: Dictionary) -> bool:
		restore_calls += 1
		if failures_left > 0:
			failures_left -= 1
			return false
		return target.restore_expedition_runtime(runtime)
	func set_input_blocked(value: bool) -> void:
		target.set_input_blocked(value)

var checks := 0
var failures := 0
var finished := false
var game: Node
var app: Node
var fixture: Node
var deadline: Timer
var real_room: Node2D
var restore_probe: RestoreProbe
var healthy_store_path := ""
var original_equipment: Dictionary = {}
var original_sets: Dictionary = {}
var permanent_loadout: Dictionary = {}
var permanent_equipment: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FIELD EQUIPMENT UI FAIL: " + description)

func frames(count: int = 3) -> void:
	for _index in count:
		await process_frame
		await physics_frame

func key(code: Key, shift: bool = false) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = code
	pressed.physical_keycode = code
	pressed.shift_pressed = shift
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await frames(1)

func _top(name: String) -> Control:
	if not is_instance_valid(app) or app.modals.is_empty(): return null
	return app.modals[-1].node.find_child(name, true, false) as Control

func _press(name: String) -> bool:
	var button := _top(name) as Button
	check(button != null and not button.disabled, "enabled production button exists: " + name)
	if button == null or button.disabled: return false
	button.pressed.emit()
	return true

func _retry_error() -> bool:
	if app.modals.is_empty():
		check(false, "failed transaction opens a retry modal")
		return false
	var focus := root.gui_get_focus_owner() as Button
	check(focus != null and app.modals[-1].node.is_ancestor_of(focus), "retry error owns keyboard focus")
	if focus == null: return false
	check(focus.text == WordsScript.text("RETRY"), "focused error action retries the same request")
	if focus.text != WordsScript.text("RETRY"): return false
	focus.pressed.emit()
	return true

func _pending(id: String) -> Dictionary:
	for offer: Dictionary in game.pending_field_equipment():
		if str(offer.equipment_id) == id: return offer
	return {}

func _decision(drop_id: String) -> String:
	return str(game.run.expedition.claimed_drop_ids.get(drop_id, {}).get("field_decision", ""))

func _icons(card: Control) -> Array[Control]:
	var result: Array[Control] = []
	for control: Control in card.find_children("*", "Control", true, false):
		if control.get_script() == EquipmentIcon: result.append(control)
	return result

func _fits(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)

func _native_icon_pixels(icon: Control, description: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# Observe a real CanvasItem redraw, then sample the native viewport. No image
	# fixture or replacement texture may stand in for the production miniature.
	var draw_count: Array[int] = [0]
	var observe: Callable = func(): draw_count[0] += 1
	icon.draw.connect(observe)
	icon.queue_redraw()
	await RenderingServer.frame_post_draw
	icon.draw.disconnect(observe)
	check(draw_count[0] > 0, description + ": original native miniature fallback draws")
	var pixels := root.get_texture().get_image()
	var scale_to_pixels := Vector2(pixels.get_size()) / root.get_visible_rect().size
	var bounds := icon.get_global_rect()
	var colors: Dictionary = {}
	# Sample the interior, excluding the card, tooltip and icon frame. The
	# authored shapes use several distinct metal/accent colors in this region.
	for y: int in range(18, 80, 4):
		for x: int in range(18, 80, 4):
			var at := (bounds.position + bounds.size * Vector2(x, y) / 96.0) * scale_to_pixels
			var pixel := pixels.get_pixel(clampi(int(at.x), 0, pixels.get_width() - 1), clampi(int(at.y), 0, pixels.get_height() - 1))
			colors[Vector3i(int(pixel.r * 15), int(pixel.g * 15), int(pixel.b * 15))] = true
	check(colors.size() >= 5, description + ": original native miniature fallback is visibly multicolored in the rendered viewport")

func _inspect_layout(locale: String, expected_current: String, expected_next: String, long_copy: bool) -> void:
	var panel := _top("FieldEquipmentModal")
	check(panel != null, locale + ": field comparison is the visible modal")
	if panel == null: return
	check(panel.size.is_equal_approx(Vector2(980, 620)), locale + ": expanded 980 by 620 trait comparison")
	check(_fits(Rect2(Vector2.ZERO, Vector2(1280, 720)), panel.get_global_rect()), locale + ": modal fits the game viewport")
	check(bool(app.modals[-1].get("required", false)) and paused, locale + ": pending decision pauses play and cannot be silently dismissed")
	var comparison := panel.find_child("FieldEquipmentComparison", true, false) as Control
	var equip := panel.find_child("FieldEquipNow", true, false) as Button
	var keep := panel.find_child("FieldKeepCurrent", true, false) as Button
	check(comparison != null and equip != null and keep != null, locale + ": comparison and both decisions are present")
	if comparison == null or equip == null or keep == null: return
	check(root.gui_get_focus_owner() == keep, locale + ": preserving current equipment has initial focus")
	check(_fits(panel.get_global_rect(), comparison.get_global_rect()), locale + ": comparison remains inside the panel")
	check(_fits(panel.get_global_rect(), equip.get_global_rect()) and _fits(panel.get_global_rect(), keep.get_global_rect()), locale + ": both decision buttons stay inside the panel")
	check(not equip.get_global_rect().intersects(keep.get_global_rect()), locale + ": decision buttons do not overlap")
	check(equip.size.y >= 44 and keep.size.y >= 44, locale + ": keyboard and pointer actions retain full target height")
	var displayed: Dictionary = comparison.get("preview")
	var expected: Dictionary = game.preview_field_equipment(str(displayed.drop_id))
	check(displayed == expected, locale + ": comparison uses the real current and candidate stats")
	for stat: String in ["attack", "ability_power", "max_hp", "armor", "magic_resist"]:
		check(comparison.find_child("FieldStat_" + stat, true, false) != null, locale + ": major base stat has a comparison row: " + stat)
	for pair: Array in [["FieldCurrentEquipment", expected_current], ["FieldNextEquipment", expected_next]]:
		var card := comparison.find_child(pair[0], true, false) as Control
		check(card != null, locale + ": named equipment card " + str(pair[0]))
		if card == null: continue
		check(_fits(comparison.get_global_rect(), card.get_global_rect()), locale + ": equipment card is contained")
		var icons := _icons(card)
		check(icons.size() == 1, locale + ": card renders one production equipment icon")
		if icons.size() == 1:
			var data: Dictionary = icons[0].get("equipment_data")
			check(str(data.get("id", "")) == str(pair[1]), locale + ": icon identifies actual equipment " + str(pair[1]))
			check(data == Registry.equipment(str(pair[1])) and str(data.get("slot", "")) == str(displayed.slot), locale + ": production icon receives the complete equipment definition and matching slot")
			var painted: Texture2D = EquipmentArt.texture(str(pair[1]))
			check(painted is AtlasTexture and icons[0].get("generated_texture") == painted, locale + ": comparison loads the exact regenerated 2.5D equipment illustration")
			check(_fits(card.get_global_rect(), icons[0].get_global_rect()), locale + ": equipment icon stays within its card")
		var title := card.find_child("FieldEquipmentName", true, false) as Label
		check(title != null and title.max_lines_visible == 2 and title.tooltip_text == title.text, locale + ": long equipment names have bounded lines and full text tooltips")
	for name: String in ["FieldStatChanges", "FieldSetChanges", "FieldCurrentAffix", "FieldNextAffix"]:
		var scroll := comparison.find_child(name, true, false) as ScrollContainer
		check(scroll != null, locale + ": independently scrollable content exists: " + name)
		if scroll == null: continue
		check(scroll.clip_contents and _fits(comparison.get_global_rect(), scroll.get_global_rect()), locale + ": " + name + " clips within comparison")
		check(scroll.get_global_rect().end.y <= minf(equip.get_global_rect().position.y, keep.get_global_rect().position.y) + 1.0, locale + ": " + name + " cannot cover the decisions")
		if long_copy and name in ["FieldCurrentAffix", "FieldNextAffix"]:
			var bar := scroll.get_v_scroll_bar()
			check(bar.max_value > bar.page, locale + ": long affix creates real vertical overflow in " + name)
			scroll.scroll_vertical = int(bar.max_value)
			await frames(2)
			check(scroll.scroll_vertical > 0 and absf(float(scroll.scroll_vertical) - (bar.max_value - bar.page)) <= 2.0, locale + ": long affix scrolls to its final lines")
			var end_offset := scroll.scroll_vertical
			scroll.grab_focus()
			await key(KEY_UP)
			check(scroll.scroll_vertical < end_offset, locale + ": focused long affix scrolls with the keyboard")
	var reached: Dictionary = {}
	for reverse in [false, true]:
		for _index in 8:
			await key(KEY_TAB, reverse)
			var focus := root.gui_get_focus_owner()
			check(focus != null and panel.is_ancestor_of(focus), locale + ": keyboard traversal remains inside field modal")
			if focus != null: reached[str(focus.name)] = true
	check(reached.has("FieldEquipNow") and reached.has("FieldKeepCurrent"), locale + ": keyboard reaches both choices")
	keep.grab_focus()
	await key(KEY_ESCAPE)
	check(_top("FieldEquipmentModal") == panel, locale + ": Escape keeps the unresolved required decision")

func _long_content(enabled: bool) -> void:
	if not enabled:
		Registry._equipment = original_equipment.duplicate(true)
		Registry._sets = original_sets.duplicate(true)
		return
	for id: String in ["EQ01", "EQ02", "EQ04"]:
		var data: Dictionary = Registry._equipment[id]
		data.name = "超长战地装备名称用于验证换行与裁剪边界".repeat(5)
		data.name_en = "Extremely long field equipment name for bounded comparison layout ".repeat(5)
		for field: String in ["affix_text", "description"]:
			data[field] = "长词缀：命中后保留剩余冷却、独立护盾和生命值，不重复触发入场奖励。".repeat(25)
			data[field + "_en"] = "Long affix: preserve remaining cooldowns, independent guards and current health without repeating room entry rewards. ".repeat(25)
	for threshold: Dictionary in Registry._sets.S02.thresholds.values():
		threshold.text = "套装门槛变化：持续效果、触发冷却以及战地装备的本局限制。".repeat(18)
		threshold.text_en = "Set threshold changes: persistent effects, internal cooldowns, and field equipment that lasts for this expedition. ".repeat(18)

func _show_locale(locale: String) -> void:
	WordsScript.set_locale(locale)
	app._clear_modals()
	app._show_pending_expedition_offer()
	await frames()

func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var path := "res://artifacts/field_equipment_ui_" + suffix + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "graphical evidence saved: " + suffix)

func _complete_fixture(drops: Array, mastery: int = 0) -> bool:
	var id: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	var completed: bool = game.commit_expedition_completion(id, real_room.expedition_runtime_snapshot(), {"gold":0, "xp":0, "mastery":mastery, "equipment":drops})
	check(completed, "real completion transaction accepts deterministic equipment reward fixture")
	if completed: app._show_pending_expedition_offer()
	await frames()
	return completed

func _save_failure_and_equip() -> void:
	var offer := _pending("EQ02")
	check(not offer.is_empty(), "first new weapon has an undecided field offer")
	if offer.is_empty(): return
	var before: Dictionary = game.run.live_receipt()
	var profile_before: Dictionary = game.profile.duplicate(true)
	var bytes_before := FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path))
	var actor_before: Dictionary = real_room.expedition_runtime_snapshot()
	var original_panel := _top("FieldEquipmentModal")
	var original_comparison := _top("FieldEquipmentComparison")
	game._store.path = game.profile_path + "/unwritable.json"
	_press("FieldEquipNow")
	await frames()
	check(game.last_error == "STORAGE_WRITE_FAILED", "equip fails at the real durable storage boundary")
	check(game.run.live_receipt() == before and game.profile == profile_before, "failed equip preserves receipt and permanent profile")
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path)) == bytes_before, "failed equip preserves on-disk profile bytes")
	check(real_room.expedition_runtime_snapshot() == actor_before and _decision(str(offer.drop_id)).is_empty(), "failed equip leaves actor state and pending decision untouched")
	check(not app.expedition_action_pending, "failed save releases the UI transaction guard for retry")
	var back: Button = null
	for button: Button in app.modals[-1].node.find_children("*", "Button", true, false):
		if button.text == WordsScript.text("BACK"): back = button
	check(back != null, "save failure offers Back to the displayed decision")
	if back != null: back.pressed.emit()
	await frames()
	check(_top("FieldEquipmentModal") == original_panel and _top("FieldEquipmentComparison") == original_comparison, "Back returns to the same comparison without rebuilding or losing its request")
	check(str(original_comparison.get("selected_decision")) == "equip" and root.gui_get_focus_owner() == _top("FieldEquipNow"), "Back preserves the attempted equip selection and keyboard focus")
	check(game.run.live_receipt() == before, "Back does not implicitly choose equip or keep")
	_press("FieldEquipNow")
	await frames()
	check(game.last_error == "STORAGE_WRITE_FAILED", "same visible equip action can fail again before recovery")
	game._store.path = healthy_store_path
	_retry_error()
	await frames()
	check(_decision(str(offer.drop_id)) == "equip" and game.run.loadout_snapshot.weapon == "EQ02", "the same production retry equips once after storage recovery")
	check(game.run.expedition.pending_equipment.has("EQ02") and not game.profile.equipment.has("EQ02"), "field equip remains unsecured expedition loot")
	var next := _pending("EQ04")
	check(not next.is_empty() and next.current_id == "EQ02", "the next same-slot offer compares against the item just equipped")
	check(_top("FieldEquipmentModal") != null, "successful equip advances directly to the next field decision")

func _restore_failure_and_retry() -> void:
	var offer := _pending("EQ04")
	if offer.is_empty():
		check(false, "second field offer exists for restore failure")
		return
	_long_content(true)
	await _show_locale("en")
	await _inspect_layout("en / set and long text", "EQ02", "EQ04", true)
	_long_content(false)
	await _show_locale("zh_CN")
	restore_probe = RestoreProbe.new()
	restore_probe.target = real_room
	fixture.add_child(restore_probe)
	app.room = restore_probe
	_press("FieldEquipNow")
	await frames()
	check(restore_probe.restore_calls == 1, "the committed equip reaches the injected restore failure exactly once")
	check(_decision(str(offer.drop_id)) == "equip" and game.run.loadout_snapshot.weapon == "EQ04", "restore failure retains the already committed decision")
	var committed: Dictionary = game.run.live_receipt()
	var saved := FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path))
	_retry_error()
	await frames()
	check(restore_probe.restore_calls == 2, "error retry reaches the real Room restore")
	check(game.run.live_receipt() == committed and FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path)) == saved, "restore retry is idempotent and cannot save or grant the item twice")
	check(real_room.player.loadout.effects.equipped.has("EQ04") and not real_room.player.loadout.effects.equipped.has("EQ02"), "real player effects now bind the committed field loadout")
	check(not app.expedition_action_pending and _top("FieldEquipmentModal") != null, "restored actor proceeds to the remaining field offer")
	app.room = real_room
	restore_probe.target = null
	restore_probe.free()
	restore_probe = null

func _stale_checkpoint_and_keep() -> void:
	var offer := _pending("EQ05")
	check(not offer.is_empty() and offer.current_id == "EQ04", "third offer sees the restored current weapon")
	if offer.is_empty(): return
	var keep := _top("FieldKeepCurrent") as Button
	if keep == null:
		check(false, "third offer provides a keep button")
		return
	var comparison := _top("FieldEquipmentComparison")
	var connections: Array = comparison.get_signal_connection_list("choice_requested")
	check(connections.size() == 1, "displayed comparison binds a single production decision callback")
	if connections.size() != 1: return
	# Retain the actual comparison-to-Main connection. The old panel itself is
	# freed on departure, while this closure still belongs to the surviving Main.
	var displayed_callback: Callable = connections[0].callable.bind("keep")
	var shown_checkpoint: String = game.run.expedition.checkpoint_id
	app._clear_modals()
	var next: Dictionary = game.expedition_snapshot().next_node
	app._advance_expedition(str(next.room_id))
	real_room = app.room
	real_room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	check(game.run.expedition.checkpoint_id != shown_checkpoint, "production room transition moves beyond the displayed checkpoint")
	if game.run.expedition.phase == "combat":
		if not await _complete_fixture([]): return
	else:
		check(false, "stale callback fixture reaches a second combat room")
		return
	var before: Dictionary = game.run.live_receipt()
	var saved := FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path))
	displayed_callback.call()
	displayed_callback = Callable()
	connections.clear()
	comparison = null
	keep = null
	await frames()
	check(game.run.live_receipt() == before and FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path)) == saved, "old visible-button callback cannot act against a newer cleared checkpoint")
	check(_decision(str(offer.drop_id)).is_empty(), "stale keep callback leaves the unresolved old drop available")
	check(not app.expedition_action_pending, "stale callback releases the UI guard")
	app._clear_modals()
	app._show_pending_expedition_offer()
	await frames()
	check(root.gui_get_focus_owner() == _top("FieldKeepCurrent"), "new checkpoint opens with the keep action focused")
	var loadout_before: Dictionary = game.run.loadout_snapshot.duplicate(true)
	await key(KEY_ENTER)
	check(_decision(str(offer.drop_id)) == "keep", "Enter activates the real default keep decision")
	check(game.run.loadout_snapshot == loadout_before and game.run.loadout_snapshot.weapon == "EQ04", "keep preserves the current field loadout")
	check(game.pending_field_equipment().is_empty() and app.modals.is_empty() and not paused, "all decisions resolved resumes the current room")
	check(game.run.expedition.pending_equipment.has("EQ05") and not game.profile.equipment.has("EQ05"), "keeping current gear still retains the drop only as pending loot")

func _destroy_app() -> void:
	if not is_instance_valid(app): return
	app._clear_modals()
	if is_instance_valid(real_room) and is_instance_valid(real_room.combat_audio):
		await real_room.combat_audio.wait_for_cleanup()
	app.free()
	app = null
	real_room = null
	await frames(1)

func _reload_check() -> void:
	var receipt: Dictionary = game.run.live_receipt()
	check(game.profile.loadout == permanent_loadout, "live field choices preserve every permanent camp loadout slot")
	check(game.profile.equipment == permanent_equipment, "live field choices preserve the complete permanent equipment inventory")
	await _destroy_app()
	game.reload_profile()
	check(game.run != null and game.run.loadout_snapshot.weapon == "EQ04", "disk reload restores the selected temporary weapon")
	check(game.pending_field_equipment().is_empty(), "resolved decisions are not offered again after reload")
	check(game.run.expedition.claimed_drop_ids == JSON.parse_string(JSON.stringify(receipt.expedition.claimed_drop_ids)), "disk reload preserves each immutable equip or keep decision")
	check(game.profile.loadout == permanent_loadout, "reloaded field choices preserve every permanent camp loadout slot")
	# JSON restores numeric levels as floats (0.0), whereas fresh_profile used
	# integers (0). Normalize the expected inventory through the same format,
	# retaining every nested key/value and the exact set of owned equipment.
	var stored_equipment: Dictionary = JSON.parse_string(JSON.stringify(permanent_equipment))
	check(game.profile.equipment == stored_equipment, "reloaded field choices preserve the complete permanent equipment inventory")
	check(Schema.valid(game.run.live_receipt(), game.profile), "complete field decision receipt passes production schema validation")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	fixture.add_child(app)
	app._continue_game()
	real_room = app.room
	if is_instance_valid(real_room): real_room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	check(is_instance_valid(real_room) and real_room.configuration_ready, "real Main resumes a valid room from the saved field equipment checkpoint")
	check(app.modals.is_empty(), "resume does not recreate resolved field decisions")

func _timed_out() -> void:
	if finished: return
	push_error("Field equipment UI acceptance timed out")
	quit(1)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).get_file().begins_with("test_field_equipment_ui"):
		push_error("Refusing field equipment UI tests without the isolated test_field_equipment_ui profile prefix")
		quit(2)
		return
	game.set_process(false)
	root.size = Vector2i(1280, 720)
	if game.run != null: game.finish_run("abandoned")
	check(game.new_profile(), "create isolated field equipment UI profile")
	healthy_store_path = game._store.path
	original_equipment = Registry._equipment.duplicate(true)
	original_sets = Registry._sets.duplicate(true)
	permanent_loadout = game.profile.loadout.duplicate(true)
	permanent_equipment = game.profile.equipment.duplicate(true)
	fixture = Fixture.new()
	root.add_child(fixture)
	# A fixture-owned Timer is freed explicitly with the test. A long-lived
	# SceneTreeTimer would otherwise retain its callback beyond test teardown.
	deadline = Timer.new()
	deadline.one_shot = true
	deadline.wait_time = 120.0
	deadline.process_mode = Node.PROCESS_MODE_ALWAYS
	deadline.timeout.connect(_timed_out)
	fixture.add_child(deadline)
	deadline.start()
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	fixture.add_child(app)
	check(game.start_run({"expedition":true, "biome_id":"B01", "seed":41827}), "start real expedition through Main's connected Game signal")
	real_room = app.room
	if not is_instance_valid(real_room):
		check(false, "main constructs the production expedition room")
		finished = true
		quit(1)
		return
	real_room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	_press("SkipExpeditionRelic")
	await frames()
	app._advance_expedition("L02")
	real_room = app.room
	real_room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	check(real_room.layout_id == "L02", "production route enters the requested objective room")
	var drops: Array = []
	for id: String in ["EQ02", "EQ04", "EQ05"]:
		drops.append({"drop_id":game.run.id + ":ui:" + id, "equipment_id":id})
	if not await _complete_fixture(drops, 180):
		finished = true
		quit(1)
		return
	check(_top("ExpeditionRelicModal") != null and _top("FieldEquipmentModal") == null, "required relic choice precedes every field equipment offer")
	_press("SkipExpeditionRelic")
	await frames()
	check(game.pending_field_equipment().size() == 3, "all three deterministic new drops have production field offers")
	_long_content(true)
	for locale: String in ["zh_CN", "en"]:
		await _show_locale(locale)
		await _inspect_layout(locale + " / long text", "EQ01", "EQ02", true)
		if locale == "zh_CN": await _capture("long_text_zh")
	_long_content(false)
	await _show_locale("en")
	await _capture("normal_en")
	await _show_locale("zh_CN")
	await _capture("normal_zh")
	await _save_failure_and_equip()
	await _restore_failure_and_retry()
	await _stale_checkpoint_and_keep()
	await _reload_check()
	await _destroy_app()
	game._store.path = healthy_store_path
	_long_content(false)
	WordsScript.set_locale("zh_CN")
	if game.run != null: game.finish_run("abandoned")
	deadline.stop()
	deadline.timeout.disconnect(_timed_out)
	fixture.free()
	fixture = null
	deadline = null
	finished = true
	print("FIELD EQUIPMENT UI: %d checks, %d failures; production callbacks/save/retry/restore/checkpoints/locales/layout" % [checks, failures])
	quit(1 if failures else 0)
