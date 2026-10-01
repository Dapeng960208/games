extends SceneTree
## Focused production UI acceptance for equipment guidance. All profile changes
## use Game's normal economy/equipment APIs and an isolated test profile.
## Run with --script res://tests/test_equipment_guidance_ui.gd --
## --test-profile=user://test_equipment_guidance_ui.json
## Headless checks controls and state only; graphical runs also save three views.

const Registry = preload("res://scripts/data/content_registry.gd")
const Text = preload("res://scripts/ui/strings.gd")
const BENEFIT_STATS := ["attack", "ability_power", "max_hp", "armor", "magic_resist", "armor_penetration", "magic_penetration", "true_damage_bonus", "crit_chance", "crit_multiplier", "cooldown_reduction", "move_speed", "damage_bonus", "damage_reduction", "resource_max"]

class Fixture:
	extends Node
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

var checks := 0
var failures := 0
var finished := false
var game: Node
var app: Node
var fixture: Node
var deadline: Timer

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EQUIPMENT GUIDANCE UI FAIL: " + description)

func frames(count: int = 3) -> void:
	for _index in count:
		await process_frame
		await physics_frame

func workshop() -> Control:
	return app.screen.find_child("Workshop", true, false) as Control

func _top(name_value: String) -> Control:
	if app.modals.is_empty(): return null
	return app.modals[-1].node.find_child(name_value, true, false) as Control

func _click(owner: Node, name_value: String) -> bool:
	if owner == null:
		check(false, "production control owner exists: " + name_value)
		return false
	var button := owner.find_child(name_value, true, false) as Button
	check(button != null and not button.disabled, "enabled production control: " + name_value)
	if button == null or button.disabled: return false
	var ancestor: Node = button.get_parent()
	while ancestor != null and ancestor != owner:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await frames(1)
		ancestor = ancestor.get_parent()
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.position = at
	press.global_position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	await frames()
	return true

func _labels(owner: Node) -> Array[Label]:
	var result: Array[Label] = []
	if owner == null: return result
	if owner is Label: result.append(owner)
	for label: Label in owner.find_children("*", "Label", true, false):
		result.append(label)
	return result

func _copy(owner: Node) -> String:
	var result: PackedStringArray = []
	if owner is Label: result.append(owner.text)
	for label: Label in _labels(owner): result.append(label.text)
	return "\n".join(result)

func _fits(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)

func _advice(owner: Control, name_value: String, action: Button, context: String) -> Control:
	var advice := owner.find_child(name_value, true, false) as Control
	check(advice != null, context + ": visible guidance exists")
	if advice == null: return null
	var labels := _labels(advice)
	var visible_lines := 0
	for label: Label in labels:
		var count := label.get_line_count()
		if label.max_lines_visible >= 0: count = mini(count, label.max_lines_visible)
		visible_lines += count
		check(not label.text.is_empty() and _fits(advice.get_global_rect(), label.get_global_rect()), context + ": guidance text fits its bounded container")
	check(visible_lines >= 1 and visible_lines <= 3, context + ": summary occupies at most three visible lines")
	check(advice.is_visible_in_tree() and _fits(owner.get_global_rect(), advice.get_global_rect()), context + ": guidance fits the existing UI")
	if action != null:
		check(not advice.get_global_rect().intersects(action.get_global_rect()), context + ": guidance cannot cover the action")
	return advice

func _keeps_tiers(before: Dictionary, after: Dictionary) -> bool:
	var prior: Dictionary = before.get("sets", {})
	var next: Dictionary = after.get("sets", {})
	for set_id: String in prior:
		for tier: int in [2, 4, 6]:
			if int(prior[set_id]) >= tier and int(next.get(set_id, 0)) < tier: return false
	return true

func _has_gain(before: Dictionary, after: Dictionary) -> bool:
	for stat: String in BENEFIT_STATS:
		if float(after.get(stat, 0)) > float(before.get(stat, 0)) + 0.00001: return true
	return float(after.get("attack_interval", 999)) < float(before.get("attack_interval", 999)) - 0.00001

func _unchanged(before: Dictionary, saved: PackedByteArray, context: String) -> void:
	check(game.profile == before, context + ": profile, currency, inventory and fitted loadout remain unchanged")
	check(FileAccess.get_file_as_bytes(game.profile_path) == saved, context + ": on-disk profile remains byte-identical")

func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	check(root.get_texture().get_image().save_png("res://artifacts/equipment_guidance_ui_" + suffix + ".png") == OK, "graphical evidence saved: " + suffix)

func _catalog_and_recommendation() -> void:
	app.show_workshop("shop")
	await frames()
	var panel := workshop()
	panel.shop_sets = false
	panel._render()
	await frames()
	check(panel.slot_filter == "weapon" and panel.available_only, "shop initially focuses on available weapons")
	var ids: Array = panel._filtered_equipment()
	check(ids.has("EQ01") and ids.has("EQ02") and ids.has("EQ08"), "default list retains owned and unaffordable class-appropriate weapons")
	check(not ids.has("EQ03") and not ids.has("EQ04"), "default list excludes pure other-role gear and boss-locked gear")
	for id: String in ids:
		var item: Dictionary = Registry.equipment(id)
		check(str(item.slot) == "weapon" and str(item.get("unlock_boss", "")).is_empty(), "default candidate is an unlocked weapon: " + id)
		check(not _copy(panel.find_child("ItemPurpose_" + id, true, false)).is_empty(), "list explains item purpose: " + id)
	var fitted_copy := _copy(panel.find_child("ItemState_EQ01", true, false))
	check(fitted_copy.contains("挂载") or fitted_copy.contains("Equipped"), "owned fitted item is distinguished directly in its row")
	var price_copy := _copy(panel.find_child("ItemState_EQ02", true, false))
	check(price_copy.contains("100") and (price_copy.contains("不足") or price_copy.to_lower().contains("short") or price_copy.to_lower().contains("need")), "unaffordable row retains its price and explains the balance shortfall")
	var before: Dictionary = game.profile.duplicate(true)
	var saved := FileAccess.get_file_as_bytes(game.profile_path)
	await _click(panel, "ViewAllEquipment")
	panel = workshop()
	check(not panel.available_only and panel.slot_filter == "all" and panel.set_filter == "all", "view-all click clears slot and set narrowing")
	check(panel._filtered_equipment().size() == Registry.equipment_ids().size(), "full catalog exposes every equipment definition")
	await _click(panel, "Item_EQ04")
	panel = workshop()
	check(panel.selected_item == "EQ04" and panel.action_button.disabled, "locked catalog item can be inspected but cannot be bought")
	var locked_copy := _copy(panel.find_child("ItemState_EQ04", true, false))
	check(locked_copy.contains("BO01") or locked_copy.contains("首领") or locked_copy.to_lower().contains("boss"), "locked row explains the boss requirement")
	await _click(panel, "ViewAllEquipment")
	panel = workshop()
	check(panel.available_only and not panel._filtered_equipment().has("EQ04"), "second toggle returns to the available list")
	await _click(panel, "Slot_weapon")
	_unchanged(before, saved, "catalog filtering and inspection")
	var empty_suggestion := workshop().find_child("RecommendEquipment", true, false) as Button
	check(empty_suggestion != null and empty_suggestion.disabled, "fresh zero-balance profile cannot be recommended an unpurchasable candidate")
	# Earn the recommendation fixture's spendable balance through settlement.
	app.show_camp()
	check(game.start_run() and game.add_gold(2000), "seed earned balance through the real run economy")
	if is_instance_valid(app.room):
		app.room.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(app.room.combat_audio): await app.room.combat_audio.wait_for_cleanup()
	game.finish_run("extracted")
	await frames()
	app.show_workshop("shop")
	await frames()
	workshop().shop_sets = false
	workshop()._render()
	await frames()
	before = game.profile.duplicate(true)
	saved = FileAccess.get_file_as_bytes(game.profile_path)
	await _click(workshop(), "RecommendEquipment")
	panel = workshop()
	var recommended: String = panel.selected_item
	check(recommended != str(game.profile.loadout.weapon) and panel._filtered_equipment().has(recommended), "recommendation selects a visible same-slot candidate")
	var current: Dictionary = game.selected_stats()
	var proposed: Dictionary = game.preview_stats(recommended)
	check(str(Registry.equipment(recommended).get("slot", "")) == "weapon" and _has_gain(current, proposed), "recommended candidate has an actual resolved base-stat gain")
	check(_keeps_tiers(current, proposed), "recommendation preserves every currently active set tier")
	_unchanged(before, saved, "recommendation")

func _context_upgrade_and_locales() -> void:
	# Purchase an unequipped weapon with earned money. Its
	# +1 attack differs from the +3 result of equipping AND refining from EQ01.
	app.show_camp()
	check(game.buy_equipment("EQ08"), "buy an unequipped candidate through the production transaction")
	app.show_workshop("inventory")
	await frames()
	await _click(workshop(), "Item_EQ08")
	var before: Dictionary = game.profile.duplicate(true)
	var saved := FileAccess.get_file_as_bytes(game.profile_path)
	for page: String in ["shop", "upgrade", "inventory"]:
		await _click(workshop(), "Tab_" + page)
		if page == "shop" and workshop().shop_sets: await _click(workshop(), "ToggleSetShop")
		check(workshop().mode == page and workshop().selected_item == "EQ08", "tab click preserves the valid selected equipment: " + page)
	Text.set_locale("en")
	await _click(workshop(), "Tab_upgrade")
	var panel := workshop()
	var advice := _advice(panel, "EquipmentAdvice", panel.action_button, "English upgrade")
	var fitted: Dictionary = game.preview_stats("EQ08")
	var refined: Dictionary = game.preview_upgrade_stats("EQ08")
	check(advice != null and advice.get_meta("before", {}) == fitted and advice.get_meta("after", {}) == refined, "upgrade summary receives the exact pure refinement preview pair")
	var upgrade_delta := float(refined.attack) - float(fitted.attack)
	var combined_delta := float(refined.attack) - float(game.selected_stats().attack)
	check(not is_equal_approx(upgrade_delta, combined_delta), "unequipped fixture distinguishes refinement from replacement")
	check(_copy(advice).contains("Attack %+.1f" % upgrade_delta) and not _copy(advice).contains("Attack %+.1f" % combined_delta), "upgrade guidance reports only candidate-to-next-level attack gain")
	check(panel.action_button.text.contains(str(game.upgrade_cost("EQ08"))), "upgrade action presents the real next-level price")
	_unchanged(before, saved, "cross-page selection and refinement preview")
	# A legitimate two-piece set makes losing a tier visible above ordinary gains.
	check(game.buy_equipment("EQ03") and game.buy_equipment("EQ13"), "buy the unlocked set fixture through normal transactions")
	check(game.equip_item("EQ03") and game.equip_item("EQ13"), "equip a real two-piece set through the normal API")
	for locale: String in ["zh_CN", "en"]:
		Text.set_locale(locale)
		app.show_workshop("shop")
		await frames()
		workshop().shop_sets = false
		workshop()._render()
		await frames()
		await _click(workshop(), "Item_EQ08")
		panel = workshop()
		advice = _advice(panel, "EquipmentAdvice", panel.action_button, locale + " camp")
		var labels := _labels(advice)
		check(not labels.is_empty() and (labels[0].text.contains("失去") if locale == "zh_CN" else labels[0].text.contains("Lose")) and labels[0].text.contains("2"), locale + ": lost two-piece tier is the first summary line")
		var protected_suggestion := panel.find_child("RecommendEquipment", true, false) as Button
		check(protected_suggestion != null and protected_suggestion.disabled, locale + ": suggestion refuses replacements that would break the active two-piece set")
		check(panel.body.size.is_equal_approx(Vector2(1216, 510)), locale + ": workshop retains its original compact body")
		check(_fits(Rect2(Vector2.ZERO, Vector2(1280, 720)), panel.action_button.get_global_rect()), locale + ": primary action remains in the viewport")
		check(root.gui_get_focus_owner() != null, locale + ": workshop retains keyboard focus")
		if locale == "en": await _capture("camp_en")

func _demo_field() -> void:
	Text.set_locale("zh_CN")
	app.show_camp()
	var permanent: Dictionary = game.profile.duplicate(true)
	var saved := FileAccess.get_file_as_bytes(game.profile_path)
	check(game.start_demo("CH02"), "start a production disposable hero trial")
	if game.run == null or not is_instance_valid(app.room): return
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	check(bool(game.run.demo), "field fixture is explicitly a demo run")
	var brief := _top("TrialBrief")
	var begin := root.gui_get_focus_owner() as Button
	if brief != null and begin != null and brief.is_ancestor_of(begin):
		await _click(brief,str(begin.name))
	await _click(app.modals[-1].node, "SkipExpeditionRelic")
	var options: Array = app.expedition.next_options()
	if options.is_empty(): return
	app._advance_expedition(str(options[0]))
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	var drop_id: String = game.run.id + ":guidance:EQ02"
	var completed: bool = game.commit_expedition_completion(game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete", app.room.expedition_runtime_snapshot(), {"gold":0, "xp":0, "mastery":0, "equipment":[{"drop_id":drop_id, "equipment_id":"EQ02"}]})
	check(completed, "real cleared-room transaction creates the deterministic trial drop")
	if not completed: return
	for locale: String in ["zh_CN", "en"]:
		Text.set_locale(locale)
		app._clear_modals()
		app._show_pending_expedition_offer()
		await frames()
		var modal := _top("FieldEquipmentModal")
		check(modal != null, locale + ": trial reward opens the actual field modal")
		if modal == null: continue
		var comparison := _top("FieldEquipmentComparison")
		var keep := _top("FieldKeepCurrent") as Button
		_advice(comparison, "FieldEquipmentAdvice", keep, locale + " field")
		check(modal.size.is_equal_approx(Vector2(980, 550)), locale + ": guidance preserves fixed field modal size")
		check(comparison.get("preview") == game.preview_field_equipment(drop_id), locale + ": guidance receives real current-run stats")
		check(root.gui_get_focus_owner() == keep, locale + ": keep remains the default field decision")
		var copy := _copy(comparison.find_child("FieldEquipmentScope", true, false)).to_lower()
		check((copy.contains("试玩") and copy.contains("正式") and (copy.contains("不") or copy.contains("仅"))) if locale == "zh_CN" else (copy.contains("trial") or copy.contains("demo")) and (copy.contains("not") or copy.contains("never")) and (copy.contains("collection") or copy.contains("inventory")), locale + ": demo notice explicitly excludes permanent inventory")
		await _capture("field_demo_" + locale)
	var loadout: Dictionary = game.run.loadout_snapshot.duplicate(true)
	await _click(app.modals[-1].node, "FieldKeepCurrent")
	check(game.pending_field_equipment().is_empty() and game.run.loadout_snapshot == loadout, "actual keep click resolves the offer without replacing current equipment")
	app._clear_modals()
	if is_instance_valid(app.room) and is_instance_valid(app.room.combat_audio):
		await app.room.combat_audio.wait_for_cleanup()
	game.finish_run("abandoned")
	await frames()
	_unchanged(permanent, saved, "completed disposable trial")

func _timed_out() -> void:
	if finished: return
	push_error("Equipment guidance UI acceptance timed out")
	quit(1)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).get_file().begins_with("test_equipment_guidance_ui"):
		push_error("Refusing equipment guidance UI without its isolated test_equipment_guidance_ui profile prefix")
		quit(2)
		return
	game.set_process(false)
	root.size = Vector2i(1280, 720)
	if game.run != null: game.finish_run("abandoned")
	check(game.new_profile(), "create isolated equipment guidance profile")
	Text.set_locale("zh_CN")
	fixture = Fixture.new()
	root.add_child(fixture)
	deadline = Timer.new()
	deadline.one_shot = true
	deadline.wait_time = 120.0
	deadline.process_mode = Node.PROCESS_MODE_ALWAYS
	deadline.timeout.connect(_timed_out)
	fixture.add_child(deadline)
	deadline.start()
	app = load("res://scenes/main.tscn").instantiate()
	fixture.add_child(app)
	await frames()
	await _catalog_and_recommendation()
	await _context_upgrade_and_locales()
	await _demo_field()
	app._clear_modals()
	if is_instance_valid(app.room) and is_instance_valid(app.room.combat_audio):
		await app.room.combat_audio.wait_for_cleanup()
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(), "equipment guidance music releases playback resources before exit")
	app.free()
	app = null
	await frames(1)
	if game.run != null: game.finish_run("abandoned")
	Text.set_locale("zh_CN")
	deadline.stop()
	deadline.timeout.disconnect(_timed_out)
	fixture.free()
	fixture = null
	deadline = null
	finished = true
	print("EQUIPMENT GUIDANCE UI: %d checks, %d failures; production clicks/recommendation/selection/upgrade/locales/demo" % [checks, failures])
	quit(1 if failures else 0)
