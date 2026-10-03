extends Node
## Production UI/controller checks with isolated saves. AI is frozen; these are
## not natural-combat, subjective usability, or full keyboard-accessibility tests.
const Controls = preload("res://scripts/infrastructure/input/control_bindings.gd")
var checks := 0
var failures := 0
var app: Node
var viewport: SubViewport

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AUDIT UI FAIL: "+label)

func frames(count: int = 2) -> void:
	for index: int in count: await get_tree().process_frame

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func text_in(root: Node) -> String:
	var result := ""
	for child: Node in root.find_children("*","",true,false):
		if child is Label or child is Button or child is RichTextLabel: result += str(child.text)+"\n"
	return result

func modal(name: String) -> Control:
	return app.modals[-1].node.find_child(name,true,false)

func fit(panel: Control, label: String) -> void:
	check(panel != null and Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel.get_global_rect()),label+" panel fits viewport")
	if panel == null: return
	for item: Node in panel.find_children("*","BaseButton",true,false):
		if item is Control and item.is_visible_in_tree(): check(panel.get_global_rect().encloses(item.get_global_rect()),label+" "+str(item.name)+" stays inside panel")
		if str(panel.name) == "DemoBranchPreview":
			for child: Node in item.find_children("*","Label",true,false): check(item.get_global_rect().encloses(child.get_global_rect()),label+" branch explanation fits card")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/games-audit-ui-captures")
	viewport.get_texture().get_image().save_png("/tmp/games-audit-ui-captures/"+name+".png")

func run_checks() -> void:
	if not Game.profile_path.contains("test_audit_ui"):
		push_error("Audit UI requires an isolated --test-profile")
		get_tree().quit(2)
		return
	get_tree().create_timer(180.0,true).timeout.connect(func(): push_error("AUDIT UI timeout"); get_tree().quit(1))
	check(Game.new_profile(),"new isolated profile")
	Game.set_process(false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	viewport.add_child(app)
	await frames()
	app.show_camp()
	check(app.screen.find_child("StorageCapacityHint",true,false) != null,"camp shows bounded storage headroom")
	await _controls_and_tutorials()
	await _trial_and_relics()
	await _supplies()
	await _death_review()
	app._clear_modals()
	if Game.run != null: Game.finish_run("abandoned")
	await frames()
	app.set_process(false)
	if is_instance_valid(app.room) and is_instance_valid(app.room.combat_audio): await app.room.combat_audio.wait_for_cleanup()
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free()
	print("AUDIT UI: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _controls_and_tutorials() -> void:
	var actions := ["backpack","expedition_map","relic_details","pause"]
	var codes := [KEY_G,KEY_H,KEY_J,KEY_P]
	for index: int in actions.size():
		check(actions[index] in Controls.EDITABLE_ACTIONS,"menu action is editable: "+actions[index])
		check(Game.set_control_binding(actions[index],{"type":"key","code":codes[index]}),"menu binding persists: "+actions[index])
	check(not Game.set_control_binding("attack",{"type":"key","code":KEY_G}),"menu key conflict rejected")
	check(not Game.set_control_binding("attack",{"type":"key","code":KEY_ESCAPE}),"Escape reserved for safe cancel after pause moves")
	Game.reload_profile()
	var mouse_pause := InputEventMouseButton.new()
	mouse_pause.button_index = MOUSE_BUTTON_XBUTTON1
	mouse_pause.pressed = true
	check(Game.set_control_binding("pause",{"type":"mouse","code":MOUSE_BUTTON_XBUTTON1}),"pause can use a mouse button")
	app.show_settings()
	check(not app._is_menu_cancel(mouse_pause) and app._is_menu_cancel(key(KEY_ESCAPE)),"mouse pause preserves menu clicks and Escape exit")
	app._clear_modals()
	check(Game.set_control_binding("pause",{"type":"key","code":KEY_P}),"pause restores chosen keyboard binding")
	for index: int in actions.size(): check(InputMap.action_has_event(actions[index],key(codes[index])),"menu binding installed on reload: "+actions[index])
	app.show_settings()
	app._switch_settings_tab("controls")
	app._begin_control_binding("pause")
	app._capture_control_binding(key(KEY_ESCAPE))
	check(app.pending_binding_action.is_empty() and Game.profile.settings.controls.pause.code == KEY_P,"Esc cancels pause remapping")
	app._begin_control_binding("pause")
	app._capture_control_binding(key(KEY_G))
	check(app.pending_binding_action.is_empty() and app.binding_feedback.text.contains("背包"),"menu collision reports occupying action")
	app._clear_modals()
	# Old left-click movement must move the untouched attack default. Assign A
	# elsewhere so it must disappear from tutorial attack hints as well.
	var bindings: Dictionary = Game.profile.settings.controls.duplicate(true)
	bindings.merge({"click_move":{"type":"mouse","code":MOUSE_BUTTON_LEFT},"skill_q":{"type":"key","code":KEY_T},"move_up":{"type":"key","code":KEY_A}},true)
	Game.set_setting("controls",bindings)
	check(Controls.valid_overrides(Game.profile.settings.controls),"legacy movement plus remaps stay valid")
	check(not Controls.attack_backup_enabled(bindings),"occupied A isn't an attack alias")
	for language: String in ["zh_CN","en"]:
		Words.set_locale(language)
		for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			viewport.size = dimensions
			app.show_demo_select()
			await frames()
			var summary: String = app._current_control_summary()
			check(summary.contains(Controls.label_for("click_move",bindings,language)) and summary.contains("T / W / E / R"),"trial uses current movement and skills "+language)
			check(not summary.contains(" / A"),"trial hides occupied A alias "+language)
			check(summary.contains("G") and summary.contains("H") and summary.contains("J") and summary.contains("P"),"trial uses all current menu bindings")
			await capture("selection_"+language+"_"+str(dimensions.x)+"x"+str(dimensions.y))
			app._show_demo_branches("CH03")
			await frames()
			fit(modal("DemoBranchPreview"),"branch preview "+language)
			check(text_in(modal("DemoBranchPreview")).contains("18 / 20"),"trial explains unchanged permanent branch unlocks")
			await capture("branches_"+language+"_"+str(dimensions.x)+"x"+str(dimensions.y))
			app._clear_modals()
			app.show_settings()
			app._switch_settings_tab("controls")
			await frames()
			fit(modal("SettingsPanel"),"controls "+language)
			for action: String in actions: check(modal("SettingsPanel").find_child("Bind_"+action,true,false) != null,"settings exposes "+action)
			await capture("controls_"+language+"_"+str(dimensions.x)+"x"+str(dimensions.y))
			app._clear_modals()

func _trial_and_relics() -> void:
	viewport.size = Vector2i(1280,720)
	Words.set_locale("en")
	var original: Dictionary = Game.profile.duplicate(true)
	app._show_demo_branches("CH03")
	app._select_demo_branch("CH03","q","B")
	app._select_demo_branch("CH03","ultimate","A")
	app._start_demo("CH03",true)
	await frames(4)
	check(Game.run != null and Game.run.demo and Game.run.level == 20,"early branch trial launches real level20 sandbox")
	check(Game.run.branches_snapshot == {"q":"B","ultimate":"A"},"trial carries selected branches")
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	check(text_in(modal("TrialBrief")).contains("T / W / E / R") and not text_in(modal("TrialBrief")).contains("Right-click"),"real trial brief uses current keys")
	await capture("brief_en")
	app._clear_modals()
	app._show_pending_expedition_offer()
	await frames()
	var offer: Dictionary = Game.expedition_snapshot().relic_offers[0]
	check(viewport.gui_get_focus_owner().name.begins_with("RelicChoice_"),"initial relic focus is a choice rather than skip")
	check(modal("ExpeditionRelicModal").find_child("SkipExpeditionRelic",true,false).text.contains("no health"),"full health skip states zero benefit")
	app._request_relic_skip(str(offer.offer_id))
	await frames()
	check(modal("ConfirmRelicSkip") != null and viewport.gui_get_focus_owner().name != "ConfirmZeroBenefitSkip","zero-benefit skip requires confirmation with safe back focus")
	app._input(key(KEY_ESCAPE))
	check(Game.run.expedition.offers[offer.offer_id].decision == "","Escape cancels zero-benefit skip without consuming offer")
	app._request_relic_skip(str(offer.offer_id))
	await frames()
	modal("ConfirmRelicSkip").find_child("ConfirmZeroBenefitSkip",true,false).pressed.emit()
	await frames()
	check(Game.run.expedition.offers[offer.offer_id].decision == "skip","deliberate full-health skip remains available")
	app._clear_modals()
	for language: String in ["zh_CN","en"]:
		Words.set_locale(language)
		Game.run.hp = Game.run.max_hp-1.25
		app._show_expedition_relic({"offer_id":"fixture","candidates":["CR01","CR02","CR03"]})
		check(modal("ExpeditionRelicModal").find_child("SkipExpeditionRelic",true,false).text.contains("1.3"),"wounded skip previews bounded actual heal")
		app._clear_modals()
		Game.run.hp = Game.run.max_hp
		app._show_expedition_relic({"offer_id":"fixture","candidates":[]})
		check(viewport.gui_get_focus_owner().name == "ReviewEmptyRelicOffer","empty candidates have safe review focus")
		app._clear_modals()
	# Remapped menus execute against real running UI; Escape always closes them.
	app._input(key(KEY_G)); await frames()
	check(modal("CombatBackpackModal") != null and Game.run.backpack_opens == 1,"remapped backpack works and records a bounded session count")
	app._input(key(KEY_ESCAPE)); await frames()
	app._input(key(KEY_H)); await frames()
	check(not app.modals.is_empty(),"remapped route opens")
	app._input(key(KEY_ESCAPE)); await frames()
	app._input(key(KEY_J)); await frames()
	check(app.modals[-1].node.find_child("SkillDetailsBody",true,false).text.contains("护盾规则" if Words.locale == "zh_CN" else "Shield rule"),"details explains actual shared-max shield rule")
	app._input(key(KEY_ESCAPE)); await frames()
	app._input(key(KEY_P)); await frames()
	check(not app.modals.is_empty(),"remapped pause opens")
	app._input(key(KEY_ESCAPE)); await frames()
	check(app.modals.is_empty(),"immutable Esc exits remapped pause")
	Game.finish_run("abandoned")
	await frames()
	check(Game.profile == original,"branch trial restores exact original progression and settings")

func _boundary() -> Dictionary:
	var result: Dictionary = Game.run.expedition.runtime.duplicate(true)
	if str(result.get("mode","")) == "fresh_entry": result = app.room.expedition_runtime_snapshot()
	result.mode = "safe_boundary"
	result.hp = Game.run.hp
	result.resource = Game.run.resource
	return result

func _supplies() -> void:
	app._start_demo("CH03")
	await frames(4)
	app._clear_modals()
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	var guard := 0
	# Earlier combat objectives are synthetic safe boundaries; the actual supply
	# screen, actor snapshots and purchases below are production paths.
	while str(Game.expedition_snapshot().node.role) != "supply" and guard < 10:
		guard += 1
		for offer: Dictionary in Game.expedition_snapshot().relic_offers:
			if str(offer.decision).is_empty(): check(Game.choose_run_relic(offer.offer_id,"skip","",_boundary()),"resolve prior offer")
		var state: Dictionary = Game.expedition_snapshot()
		var next: Dictionary = state.next_node
		check(Game.choose_expedition_node(int(next.node_index),str(next.room_id)),"supply traversal choice")
		var entered: bool = Game.advance_expedition_node(_boundary(),str(state.checkpoint_id))
		check(entered,"supply traversal entry")
		if not entered: return
		if Game.run.expedition.phase == "combat": check(Game.commit_expedition_completion(Game.run.id+":audit:"+str(guard),_boundary(),{"gold":100,"xp":0,"mastery":0}),"synthetic earlier objective completion")
	app._on_run_started()
	await frames(4)
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	app._clear_modals()
	Game.run.hp = Game.run.max_hp-10.5
	Game.run.resource = 1.0
	for language: String in ["zh_CN","en"]:
		Words.set_locale(language)
		for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			viewport.size = dimensions
			app._show_expedition_supply()
			await frames()
			var panel := modal("ExpeditionSupplyModal")
			fit(panel,"supply "+language)
			check(panel.find_child("HealingChoiceRule",true,false).text.contains("10.5"),"heal grouping states actual deficit")
			check(panel.find_child("Supply_heal_small",true,false).text.contains("10.5") and panel.find_child("Supply_heal_large",true,false).text.contains("10.5"),"both heals preview actual capped gain")
			check(panel.find_child("Supply_mana",true,false) == null and panel.find_child("Supply_energy",true,false) == null,"safe UI removes paid auto-regenerating resources")
			check(not panel.find_child("PrepareSafeResources",true,false).disabled,"free refill available when resource missing")
			await capture("supply_"+language+"_"+str(dimensions.x)+"x"+str(dimensions.y))
			app._clear_modals()
	Words.set_locale("en")
	var gold: int = Game.run.gold
	app._show_expedition_supply()
	app._prepare_safe_resources()
	await frames()
	check(is_equal_approx(Game.run.resource,float(Game.run.stats.resource_max)) and Game.run.gold == gold,"free preparation fills resource without payment")
	check(is_equal_approx(Game.run.hp,Game.run.max_hp-10.5),"free preparation does not heal HP")
	check(modal("ExpeditionSupplyModal").find_child("PrepareSafeResources",true,false).disabled,"full refill reports disabled reason")
	var small: Dictionary = {}
	for offer: Dictionary in Game.expedition_snapshot().supply_offers:
		if offer.product_id == "heal_small": small = offer
	var before_purchase_gold: int = Game.run.gold
	Game.run.gold = 0
	check(app._supply_disabled_reason(small,false).contains("Not enough gold"),"unaffordable heal names its disabled reason")
	Game.run.gold = before_purchase_gold
	var before_purchase_hp: float = Game.run.hp
	Game.run.hp = Game.run.max_hp
	check(app._supply_disabled_reason(small,false).contains("Full health"),"full-health heal explains zero benefit")
	Game.run.hp = before_purchase_hp
	app._buy_expedition_supply(str(small.offer_id))
	await frames()
	check(is_equal_approx(Game.run.hp,Game.run.max_hp),"actual small heal equals preview")
	check(modal("ExpeditionSupplyModal").find_child("Supply_heal_large",true,false).text.contains("Other heal chosen"),"other heal gives mutual exclusion reason after purchase")
	var paid: int = Game.run.gold
	app._buy_expedition_supply(str(small.offer_id))
	await frames()
	check(Game.run.gold == paid,"repeat healing transaction doesn't pay twice")
	app._clear_modals()
	Game.finish_run("abandoned")
	await frames()

func _death_review() -> void:
	var event := {"elapsed":15.0,"kind":"dot","status":"burn","damage_type":"magic","source_name":"Ember caster","attack_id":"burn_test","hp_loss":8.0,"hp_before":8.0,"hp_after":0.0,"shield_absorbed":0.0,"key_states":["burn","grievous"],"lethal":true}
	var review := {"recent_events":[event],"lethal_event":event,"total_absorbed":12.0}
	for language: String in ["zh_CN","en"]:
		Words.set_locale(language)
		for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			viewport.size = dimensions
			app.show_result({"outcome":"death","death_review":review})
			check(app.screen.find_child("ReviewDeath",true,false) != null,"failure result links to bounded damage evidence")
			app._show_death_review(review)
			await frames()
			fit(modal("DeathReviewModal"),"death review "+language)
			check(modal("DeathReviewModal").find_child("DeathCause",true,false).text.contains("Ember caster"),"death review preserves recorded source")
			check(modal("DeathReviewModal").find_child("DeathMechanicNote",true,false).text.contains("燃烧" if language == "zh_CN" else "Burn"),"death review explains lethal recorded mechanism")
			await capture("death_"+language+"_"+str(dimensions.x)+"x"+str(dimensions.y))
			app._clear_modals()
	app._show_death_review({})
	check(modal("DeathReviewModal").find_child("DeathCause",true,false).text.contains("unknown"),"unknown death source is never invented")
