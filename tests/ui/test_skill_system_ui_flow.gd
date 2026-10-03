extends Node
## Runs only after the root's integration gate. Setup unlocks and mastery are
## synthetic; subsequent configuration, save failure, departure and HUD controls
## use the real Main/Workshop/Game path. It does not claim natural balance.

const MainScene = preload("res://scenes/app/main.tscn")
const Catalog = preload("res://scripts/domain/combat/skill_catalog.gd")
const Workshop = preload("res://scripts/presentation/equipment/workshop_panel.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
var app: Node
var checks := 0
var failures: Array[String] = []

class PreviewApp extends Node:
	func show_camp() -> void:
		pass
	func show_codex() -> void:
		pass

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(180.0).timeout.connect(func(): push_error("Skill UI integration timeout"); get_tree().quit(1))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("SKILL UI: " + label)

func frames(count: int = 2) -> void:
	for index: int in count:
		await get_tree().process_frame

func panel() -> Control:
	return app.screen.find_child("Workshop", true, false) as Control

func button(name_value: String) -> Button:
	var node: Button = app.find_child(name_value, true, false) as Button
	check(node != null, "actual UI control exists: " + name_value)
	return node

func press(name_value: String) -> void:
	var node := button(name_value)
	if node != null:
		check(not node.disabled, "actual UI control enabled: " + name_value)
		if not node.disabled:
			node.pressed.emit()
	await frames()

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory: String = Game.profile_path.get_base_dir() + "/captures"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated screenshot directory")
	var pixels: Image = get_viewport().get_texture().get_image()
	print("UI CAPTURE %s: window=%s logical_rect=%s pixels=%s" % [name_value, DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, pixels.get_size()])
	if name_value.contains("-2k-"):
		check(pixels.get_size() == Vector2i(2560,1440), "actual captured pixels are 2560 by 1440: " + name_value)
	check(pixels.save_png(directory + "/" + name_value + ".png") == OK, "actual graphical capture " + name_value)

func _run() -> void:
	if Game.profile_path.contains("test_skill_icon_hud"):
		await _icon_hud_preview()
		return
	if Game.profile_path.contains("test_skill_system_ui_module"):
		await _fixture_preview()
		return
	if not Game.profile_path.contains("test_skill_system_ui_flow"):
		push_error("Use --test-profile containing test_skill_system_ui_flow")
		get_tree().quit(2)
		return
	check(Game.new_profile(), "isolated new profile")
	for group: String in ["SG01", "SG02", "SG03", "SG04", "SG05", "SG06", "SG07", "SG08"]:
		check(bool(Game.grant_skill_group(group, "fixture:ui-unlock:" + group).ok), "synthetic setup unlocks " + group)
	var setup: Dictionary = Game.profile.duplicate(true)
	for hero: String in Catalog.HEROES:
		setup.skill_state[hero].mastery[hero + "_SK01"] = 140
		setup.skill_state[hero].mastery[hero + "_SK04"] = 300
	check(Game._commit_profile(setup), "synthetic branch-ready setup commits through the valid store")
	app = MainScene.instantiate()
	get_tree().root.add_child(app)
	await frames()
	check(get_viewport().get_visible_rect().size == Vector2(1280,720), "real UI viewport is 1280 by 720")
	for hero: String in Catalog.HEROES:
		await _camp_configuration(hero)
	await _failed_save()
	for hero: String in Catalog.HEROES:
		await _departure_and_hud(hero)
	app.queue_free()
	await frames()
	print("SKILL SYSTEM UI FLOW: %d checks; failures=%s; renderer=%s; synthetic setup and real UI operations (not natural balance)" % [checks, failures, DisplayServer.get_name()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _fixture_preview() -> void:
	check(Game.new_profile(), "isolated UI module profile")
	var before: Dictionary = Game.profile.duplicate(true)
	var fixture := {"hero_view":{}, "skill_page_view":{}}
	for hero: String in Catalog.HEROES:
		fixture.hero_view[hero] = Game.hero_view(hero, "camp")
		var view: Dictionary = Game.skill_page_view(hero, "camp")
		view.editable = true
		for entry: Dictionary in view.skills:
			entry.unlocked = true
			entry.mastery_level = 5
			entry.mastery_xp = 300
		fixture.skill_page_view[hero] = view
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	app = PreviewApp.new()
	get_tree().root.add_child(app)
	var page: Control = Workshop.new()
	page.app = app
	page.theme = GameStyle.make_theme()
	page.set_meta("dossier_fixture", fixture)
	app.add_child(page)
	await frames()
	check(get_viewport().get_visible_rect().size == Vector2(1280,720), "fixture preview uses actual 1280 by 720 viewport")
	for hero: String in Catalog.HEROES:
		page.mode = "heroes"
		page.preview_hero = hero
		page._render()
		await frames()
		var select: Button = button("PrimaryAction")
		check(select != null and select.disabled, hero + " fixture cannot select or persist a character")
		check(page.find_child("HeroRoleSummary", true, false) != null, hero + " has a clear role profile")
		await capture(hero + "-fixture-character")
		page.mode = "skills"
		page._render()
		await frames()
		check(page.find_children("SkillPool_CH*", "Button", true, false).size() == 12, hero + " fixture contains twelve skills")
		for index: int in 12:
			var identity: String = hero + "_SK%02d" % (index+1)
			var item: Button = page.find_child("SkillPool_"+identity,true,false) as Button
			var icons: Array[Node] = item.find_children("*","TextureRect",true,false) if item != null else []
			var icon: TextureRect = icons[0] as TextureRect if icons.size() == 1 else null
			var logical: String = "asset://skill."+identity.to_lower()
			check(item != null and str(item.get_meta("entry",{}).get("icon_id","")) == logical.trim_prefix("asset://") and icon != null and icon.texture != null and icon.texture == Sampler.sampled(logical) and icon.texture.get_size() == Vector2(1254,1254) and AssetCatalog.resolve(logical).ends_with("_icon.png"), identity + " actual pool TextureRect binds its original native PNG by stable icon identity")
		check(page.find_children("SkillPool_CH*", "Button", true, false).filter(func(node: Node) -> bool: return node.visible).size() == 12, hero + " empty search displays all twelve pool entries")
		var search: LineEdit = page.find_child("SkillPoolSearch", true, false)
		search.text = "NO_MATCH_FIXTURE"
		search.text_changed.emit(search.text)
		check(page.find_children("SkillPool_CH*", "Button", true, false).filter(func(node: Node) -> bool: return node.visible).is_empty(), hero + " no-match search hides pool entries")
		search.text = ""
		search.text_changed.emit("")
		check(page.find_children("SkillPool_CH*", "Button", true, false).filter(func(node: Node) -> bool: return node.visible).size() == 12, hero + " clearing search restores the full pool")
		await press("SkillPool_" + hero + "_SK05")
		await press("ReplaceDraftSkill")
		await press("SwapSkill_q")
		var draft: Dictionary = page.get_meta("dossier_draft_" + hero, {})
		check(draft.get("loadout", []).size() == 4 and hero + "_SK05" in draft.loadout, hero + " fixture supports four-slot replacement and swapping")
		await press("SkillPool_" + hero + "_SK01")
		await press("SkillBranch_A")
		check(str(page.get_meta("dossier_draft_" + hero).branches.get(hero + "_SK01", "")) == "A", hero + " fixture selects a mastery-four branch")
		await press("SkillBranch_original")
		check(page.get_meta("dossier_draft_" + hero).branches.has(hero + "_SK01") and str(page.get_meta("dossier_draft_" + hero).branches[hero + "_SK01"]).is_empty(), hero + " reset branch explicitly retains its empty choice")
		await press("ApplySkillConfig")
		var message: Label = page.find_child("SkillConfigMessage", true, false)
		check(message != null and not message.text.is_empty() and Game.profile == before, hero + " fixture Apply explains preview mode and writes nothing")
		fixture.apply_failed = true
		fixture.apply_message = "保存失败：草稿保留（隔离预览）"
		page.set_meta("dossier_fixture", fixture)
		await press("ApplySkillConfig")
		check(bool(page.get_meta("dossier_message_error", false)) and Game.profile == before, hero + " fixture exposes retained save-error state without storage mutation")
		await press("SwapSkill_f")
		check(not bool(page.get_meta("dossier_message_error",false)) and (page.find_child("SkillConfigLockReason",true,false) as Label).text.contains("未应用") and Game.profile == before,hero+" editing a preview failure clears stale errors and retains the unsaved draft")
		await capture(hero + "-fixture-skills")
		fixture.skill_page_view[hero].editable = false
		fixture.skill_page_view[hero].lock_reason = "整次出征只读"
		page.set_meta("dossier_fixture", fixture)
		page._render()
		await frames()
		check(button("ApplySkillConfig").disabled and button("SwapSkill_q").disabled and button("DiscardSkillDraft").disabled, hero + " fixture read-only state disables edits and draft discard")
		check(page.find_child("SkillConfigLockReason", true, false) != null, hero + " fixture read-only reason is visible")
		await capture(hero + "-fixture-readonly")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(2560,1440))
		await frames(5)
		check(DisplayServer.window_get_size() == Vector2i(2560,1440), "actual graphical window reaches the user's target 2560 by 1440")
		for hero: String in Catalog.HEROES:
			page.preview_hero = hero
			page.mode = "heroes"
			page._render()
			await frames()
			await capture(hero + "-2k-fixture-character")
			page.mode = "skills"
			page._render()
			await frames()
			var text: Label = page.find_child("InspectedSkillDescription", true, false)
			check(text != null and text.get_theme_font_size("font_size") >= 18, hero + " 2K page retains at least eighteen logical-pixel detail text")
			await capture(hero + "-2k-fixture-skills")
	check(Game.profile == before and Game.run == null, "all UI fixtures leave storage and expedition untouched")
	app.queue_free()
	await frames()
	print("SKILL UI MODULE: %d checks; failures=%s; fixed-value preview only; renderer=%s" % [checks, failures, DisplayServer.get_name()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _icon_hud_preview() -> void:
	check(Game.new_profile(),"isolated icon HUD profile")
	check(bool(Game.grant_skill_group("SG01","fixture:icon-hud-unlock").ok),"synthetic collection setup unlocks each role's SK05")
	app = MainScene.instantiate()
	get_tree().root.add_child(app)
	await frames()
	for hero: String in Catalog.HEROES:
		check(Game.select_hero(hero),hero+" camp selects icon-check role")
		app.show_workshop("heroes")
		await frames()
		await capture(hero+"-native-icon-character")
		app.show_workshop("skills")
		await frames()
		await press("InspectSkill_q")
		await press("SkillPool_"+hero+"_SK05")
		await press("ReplaceDraftSkill")
		await press("SwapSkill_q")
		await press("ApplySkillConfig")
		check(Game.get_loadout(hero)[1] == hero+"_SK05",hero+" actual camp swap applies SK05 to W")
		await capture(hero+"-native-icon-skills")
		app.show_camp()
		app._start_run()
		await frames()
		if app.find_child("ConfirmWishDeparture",true,false) != null: await press("ConfirmWishDeparture")
		await frames(4)
		for offer_index: int in 8:
			if app.modals.is_empty():
				app._show_pending_expedition_offer()
				await frames()
			if app.find_child("ConfirmZeroBenefitSkip",true,false) != null:
				await press("ConfirmZeroBenefitSkip")
			elif app.find_child("SkipExpeditionRelic",true,false) != null:
				await press("SkipExpeditionRelic")
			elif app.find_child("FieldKeepCurrent",true,false) != null:
				await press("FieldKeepCurrent")
			else:
				break
		check(app.modals.is_empty(),hero+" actual relic decision leaves all four HUD slots unobstructed")
		check(Game.run != null and is_instance_valid(app.hud) and app.route == "run",hero+" actual entrance creates HUD")
		if Game.run == null or not is_instance_valid(app.hud): continue
		app.hud.refresh()
		var original: Array[Texture2D] = []
		for index: int in 4:
			var cell: Button = app.hud.skill_slots[index]
			var identity: String = Game.run.skill_loadout_snapshot[index]
			var logical: String = "asset://skill."+identity.to_lower()
			check(cell.skill_id == identity and cell.icon_id == logical and cell.generated_texture != null and cell.generated_texture == Sampler.sampled(logical) and cell.generated_texture.get_size() == Vector2(1254,1254),hero+" live HUD slot "+str(index)+" uses the frozen skill's original PNG")
			original.append(cell.generated_texture)
		for index: int in 5: app.hud.refresh(); await frames(1)
		check(range(4).all(func(index: int)->bool: return app.hud.skill_slots[index].generated_texture == original[index]),hero+" repeated HUD refresh reuses cached icon texture instances")
		await capture(hero+"-native-icon-hud")
		check(not Game.finish_run("abandoned").is_empty(),hero+" entrance-only icon fixture cleans up explicitly")
		await frames()
	app.queue_free()
	await frames()
	print("SKILL ICON HUD: %d checks; failures=%s; renderer=%s; entrance-only identity fixture" % [checks,failures,DisplayServer.get_name()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _camp_configuration(hero: String) -> void:
	app.show_workshop("heroes")
	await frames()
	await press("Preview_" + hero)
	if str(Game.profile.selected_hero) != hero:
		await press("PrimaryAction")
	check(str(Game.profile.selected_hero) == hero, hero + " selection uses redesigned character page")
	check(app.find_child("HeroConfigLockReason",true,false) != null, hero + " character page has explicit edit state")
	var saved: Array = Game.get_loadout(hero)
	var scroll: ScrollContainer = app.find_child("HeroStatScroll",true,false)
	for index: int in 4:
		var cell: Button = app.find_child("HeroEquipped_"+Catalog.INPUT_SLOTS[index],true,false)
		var icons: Array[Node] = cell.find_children("*","TextureRect",true,false) if cell != null else []
		var icon: TextureRect = icons[0] as TextureRect if icons.size() == 1 else null
		check(cell != null and str(cell.get_meta("skill_id","")) == saved[index] and str(cell.get_meta("input_slot","")) == Catalog.INPUT_SLOTS[index] and icon != null and icon.texture == Sampler.sampled("asset://skill."+str(saved[index]).to_lower()),hero+" character card exposes saved identity and native icon "+str(index))
		check(cell != null and scroll != null and scroll.get_global_rect().encloses(cell.get_global_rect()),hero+" saved skill card is entirely visible before scrolling "+str(index))
	await capture(hero + "-character")
	await press("HeroEquipped_ultimate")
	var page: Control = panel()
	check(page != null and str(page.mode) == "skills" and int(page.get_meta("dossier_slot",-1)) == 3 and str(page.get_meta("dossier_skill_id","")) == str(saved[3]),hero+" character R card opens the corresponding saved skill and slot")
	check((app.find_child("SkillPool_"+str(saved[3]),true,false) as Button).has_focus(),hero+" character-to-skill navigation focuses the matching pool entry")
	check(page != null and page.find_children("SkillPool_CH*", "Button", true, false).size() == 12, hero + " has twelve real pool buttons")
	for slot: String in Catalog.INPUT_SLOTS:
		check(page.find_child("InspectSkill_" + slot, true, false) != null, hero + " exposes configured " + slot)
	await press("InspectSkill_q")
	var before: Dictionary = Game.profile.duplicate(true)
	await press("SkillPool_" + hero + "_SK05")
	var description: Label = app.find_child("InspectedSkillDescription", true, false) as Label
	check(description != null and not description.text.is_empty() and description.get_theme_font_size("font_size") >= 18, hero + " detail is readable and source-backed")
	check(app.find_child("SkillDescriptionScroll", true, false) is ScrollContainer, hero + " long descriptions and branches scroll")
	await press("ReplaceDraftSkill")
	check(Game.profile == before, hero + " local replacement draft does not change saved slots")
	check((app.find_child("SkillLoadoutStatus",true,false) as Label).text.contains("草稿") and (app.find_child("SkillConfigLockReason",true,false) as Label).text.contains("未应用"),hero+" unapplied draft has persistent status beside its four slots")
	await capture(hero+"-skills-dirty")
	await press("DiscardSkillDraft")
	check(Game.profile == before and (app.find_child("SkillConfigLockReason",true,false) as Label).text.contains("已还原") and (app.find_child("InspectSkill_q",true,false) as Button).has_focus(),hero+" revert restores saved slots and focus without a save")
	await capture(hero+"-skills-reverted")
	await press("ReplaceDraftSkill")
	await press("SwapSkill_q")
	var draft: Dictionary = panel().get_meta("dossier_draft_" + hero, {})
	check(draft.get("loadout", []).size() == 4 and hero + "_SK05" in draft.loadout, hero + " replace and swap preserve exactly four unique identities")
	var expected: Array = draft.loadout.duplicate()
	await press("ApplySkillConfig")
	check(Game.get_loadout(hero) == expected, hero + " apply commits the complete four-slot draft")
	await press("SkillPool_" + hero + "_SK01")
	await press("SkillBranch_A")
	await press("ApplySkillConfig")
	check(str(Game.get_skill_progress(hero, hero + "_SK01").branch) == "A", hero + " first branch follows skill identity even when not equipped")
	await press("SkillBranch_original")
	await press("ApplySkillConfig")
	check(str(Game.get_skill_progress(hero, hero + "_SK01").branch).is_empty(), hero + " original branch resets the saved branch instead of retaining A")
	await press("SkillPool_" + hero + "_SK04")
	await press("SkillBranch_B")
	await press("ApplySkillConfig")
	check(str(Game.get_skill_progress(hero, hero + "_SK04").branch) == "B", hero + " terminal branch uses mastery five")
	var search: LineEdit = app.find_child("SkillPoolSearch", true, false) as LineEdit
	check(search != null, hero + " searchable pool")
	if search != null:
		search.text = "NO_MATCH_EXPECTED"
		search.text_changed.emit(search.text)
		check((app.find_child("SkillPoolEmpty",true,false) as Control).visible, hero + " empty search has a visible explanation")
		search.text = ""
		search.text_changed.emit(search.text)
		search.grab_focus()
		panel()._render()
		await frames()
		check((app.find_child("SkillPoolSearch",true,false) as LineEdit).has_focus(),hero+" rebuilding the same skill page preserves search keyboard focus")
	if hero == "CH02": await _role_context_roundtrip()
	await capture(hero + "-skills")
	var committed: Dictionary = Game.profile.skill_state[hero].duplicate(true)
	Game.reload_profile()
	check(JSON.parse_string(JSON.stringify(Game.profile.skill_state[hero])) == JSON.parse_string(JSON.stringify(committed)), hero + " configured slots and branches survive actual reload")

func _role_context_roundtrip() -> void:
	var before: Dictionary = Game.profile.duplicate(true)
	await press("InspectSkill_secondary")
	await press("SkillPool_CH02_SK05")
	await press("SwapSkill_f")
	var draft: Dictionary = panel().get_meta("dossier_draft_CH02",{}).duplicate(true)
	var search: LineEdit = app.find_child("SkillPoolSearch",true,false)
	search.text = "SK05"
	search.text_changed.emit(search.text)
	await press("SkillFilter_learned")
	await press("SkillHero_CH03")
	await press("SwapSkill_q")
	var other: Dictionary = panel().get_meta("dossier_draft_CH03",{}).duplicate(true)
	await press("SkillHero_CH02")
	check(int(panel().get_meta("dossier_slot",-1)) == 1 and str(panel().get_meta("dossier_skill_id","")) == "CH02_SK05" and str(panel().get_meta("dossier_search","")) == "SK05" and str(panel().get_meta("dossier_filter","")) == "learned","switching roles restores each inspected slot, skill, search and filter")
	check(panel().get_meta("dossier_draft_CH02",{}) == draft and panel().get_meta("dossier_draft_CH03",{}) == other and Game.profile == before,"role switches retain separate unapplied drafts and preserve saved configurations")
	await press("DiscardSkillDraft")
	await press("SkillHero_CH03")
	await press("DiscardSkillDraft")
	await press("SkillHero_CH02")
	search = app.find_child("SkillPoolSearch",true,false)
	search.text = ""
	search.text_changed.emit("")
	await press("SkillFilter_all")

func _failed_save() -> void:
	app.show_workshop("skills")
	await frames()
	var hero: String = str(Game.profile.selected_hero)
	var before: Dictionary = Game.profile.duplicate(true)
	await press("SwapSkill_q")
	var expected: Array = panel().get_meta("dossier_draft_" + hero).loadout.duplicate()
	var limit: int = Game._store.max_document_bytes
	Game._store.max_document_bytes = 1
	await press("ApplySkillConfig")
	check(Game.profile == before and bool(panel().get_meta("dossier_message_error",false)), "new UI exposes storage failure without applying partial slots")
	check(app.find_child("SkillConfigMessage",true,false) != null and not str(panel().get_meta("dossier_draft_"+hero).operation_id).is_empty(), "new UI retains the pending draft and operation id")
	check((app.find_child("SkillConfigLockReason",true,false) as Label).text.contains("保存失败"),"real failed apply remains visible beside the configuration controls")
	await capture(hero+"-skills-save-failed")
	Game._store.max_document_bytes = limit
	var apply := button("ApplySkillConfig")
	if apply != null:
		apply.grab_focus()
		check(apply.has_focus(), "apply button accepts keyboard focus")
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = true
		get_viewport().push_input(key)
		await frames()
		key.pressed = false
		get_viewport().push_input(key)
		await frames()
	check(Game.get_loadout(hero) == expected and not bool(panel().get_meta("dossier_message_error",true)), "keyboard activation retries and commits the same complete configuration")
	check((app.find_child("SkillConfigLockReason",true,false) as Label).text.contains("配置已保存"),"successful retry persistently replaces the save failure status")
	await capture(hero+"-skills-save-retried")

func _departure_and_hud(hero: String) -> void:
	check(Game.select_hero(hero), "fixture selects next departure role " + hero)
	app.show_camp()
	app._start_run()
	await frames()
	if app.find_child("ConfirmWishDeparture", true, false) != null:
		await press("ConfirmWishDeparture")
	await frames(4)
	check(Game.run != null and is_instance_valid(app.room) and app.route == "run", hero + " actual camp route creates a frozen expedition")
	if Game.run == null or not is_instance_valid(app.room) or not is_instance_valid(app.hud) or app.route != "run":
		return
	var frozen: Array = Game.run.skill_loadout_snapshot.duplicate()
	var view: Dictionary = app.room.player.combat_hud_view()
	app.hud.refresh()
	check(view.get("slots", []).size() == 4 and view.role_state == app.room.player.class_state_snapshot(), hero + " HUD data comes from actual actor/kit state")
	for entry: Dictionary in view.get("slots", []):
		var shown: Dictionary = app.hud.skill_info(str(entry.input_slot))
		check(str(shown.get("skill_id", "")) == str(entry.skill_id) and float(shown.get("cost", -1)) == float(entry.cost), hero + " HUD follows configured identity " + str(entry.skill_id))
	check(app.hud.status_panel.position == Vector2(12,22), hero + " original HUD status layout stays in place")
	await capture(hero + "-hud")
	app.show_workshop("skills")
	await frames()
	check((app.find_child("ApplySkillConfig",true,false) as Button).disabled and (app.find_child("SwapSkill_q",true,false) as Button).disabled and (app.find_child("DiscardSkillDraft",true,false) as Button).disabled, hero + " expedition skill page disables editing and draft discard")
	check(not str((app.find_child("SkillConfigLockReason",true,false) as Label).text).is_empty(), hero + " expedition skill page explains the lock")
	check(not bool(Game.apply_skill_config(hero, Catalog.starter_ids(hero), {}, "fixture:ui-run-lock:"+hero).ok), hero + " direct service also rejects expedition editing")
	check(Game.run.skill_loadout_snapshot == frozen, hero + " read-only inspection preserves departure slots")
	await capture(hero + "-skills-readonly")
	app.show_camp()
	# This UI-only fixture stops at the entrance; extraction is correctly locked
	# until real objectives are complete. Natural extraction has its own run.
	check(not Game.finish_run("abandoned").is_empty(), hero + " explicit entrance-fixture cleanup retains permanent skill collection")
	await frames()
	Game.reload_profile()
	check(Game.profile.skill_state[hero].learned.size() == 12, hero + " unlocks survive abandoned entrance-fixture/restart")
