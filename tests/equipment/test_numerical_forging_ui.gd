extends Node
const Fixtures = preload("res://tests/persistence/test_numerical_instance_storage.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Creation = preload("res://scripts/domain/equipment/instance_transactions.gd")
const ForgePanel = preload("res://scripts/presentation/equipment/instance_forging_panel.gd")
var checks := 0
var failures: Array[String] = []
var app: Node
var panel: Control

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAILED: ",label," Game=",Game.last_error," UI=",panel.forge_message if is_instance_valid(panel) else "", " Result=",panel.find_child("ForgeResult",true,false).text if is_instance_valid(panel) and panel.find_child("ForgeResult",true,false) != null else "")

func item(id: String,template: String = "EQ04",rarity: String = "green",level: int = 20,gains: Array = [],pity: int = 0) -> Dictionary:
	var rolls := {}
	for key: String in Instances.main_keys(template,"physical"): rolls[key] = 3 if id == "potential-only" else 50
	var affixes: Array = []
	var legal := Instances.legal_affixes(template,"physical")
	for index in ["white","green","purple","gold"].find(rarity)+ (0 if rarity == "white" else 1): affixes.append({"type":legal[index],"u":20})
	var steps: Array = []
	for index in gains.size(): steps.append({"g":gains[index],"pity":pity,"base_price_peak":Economy.enhancement_price(index+1,level)})
	return Instances.create({"instance_id":id,"template_id":template,"source_event_id":"fixture:"+id,"item_level":level,"rarity":rarity,"power_type":"physical","main_rolls":rolls,"affix_type_and_quantile":affixes,"enhancement_steps":steps,"purchase_baseline_gold":Economy.purchase_baseline_price(template,rarity,level)})

func same(a: Variant,b: Variant) -> bool:
	return JSON.stringify(Creation._canonical_values(a),"",true,true) == JSON.stringify(Creation._canonical_values(b),"",true,true)

func choose(id: String,kind: String) -> void:
	panel.mode = "inventory" if kind in ["sell","dismantle"] else "upgrade"
	panel.inventory_recycle = kind in ["sell","dismantle"]
	panel.selected_item = id
	panel.forge_kind = kind
	panel.forge_message = ""
	panel.forge_result_details = ""
	panel._render()

func press(name: String = "PrimaryAction") -> void:
	var button := panel.find_child(name,true,false) as Button
	check(button != null and not button.disabled,"usable real button "+name)
	if button != null and not button.disabled: button.pressed.emit()
	await get_tree().create_timer(0.32).timeout

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Game.profile_path.contains("test_numerical_forging_ui"):
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"isolated new profile")
	var profile: Dictionary = preload("res://scripts/domain/equipment/numerical_profile.gd").fresh(ProfileStore.fresh_profile())
	profile.hero_xp.CH01 = 3600
	profile.permanent_gold = 100000
	profile.bosses = ["BO01","BO02","BO03","BO04"]
	profile.materials = {"forge":1000,"race:B01":1000,"race:B02":1000,"race:B03":1000,"race:B04":1000,"core:B01":100,"core:B02":100,"core:B03":100,"core:B04":100}
	for record: Dictionary in [item("forge-target"),item("inherit-source","EQ04","white",1,[8,9]),item("inherit-target","EQ04","white",20),item("dismantle-target"),item("potential-only","EQ01","white",1,[8],3)]: profile.equipment[record.instance_id] = record
	check(Game._commit_profile(profile),"V2 forging fixture saved: "+Game.last_error)
	if not failures.is_empty():
		print(failures)
		get_tree().quit(1)
		return
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	await get_tree().process_frame
	for page: String in ["craft", "upgrade", "heroes"]:
		app.show_workshop(page)
		app.music_tick = 0.0
		app._process(0.31)
		check(app.music.desired_context == {"craft":"craft","upgrade":"forge","heroes":"camp"}[page], "actual workshop route selects music: "+page)
	app.show_workshop("upgrade")
	await get_tree().process_frame
	panel = app.screen.find_child("Workshop",true,false)
	check(panel != null and panel.find_child("ForgeInventory",true,false) != null,"actual V2 forge hub mounted")
	choose("forge-target","enhance")
	check(panel.find_child("ForgeIntegerPreview",true,false).text.contains("→"),"exact integer range preview")
	check(panel.find_child("ForgeAdvancedDetails",true,false).text.contains("10/20/40/20/10"),"enhancement probability disclosure")
	check(not panel.find_child("ForgeAdvancedDetails",true,false).visible,"calculation details start collapsed")
	check(panel.find_child("ForgeGoal_enhance",true,false) != null,"upgrade goal is visible")
	var gold: int = Game.profile.permanent_gold
	var action: Button = panel.action_button
	action.pressed.emit()
	action.pressed.emit()
	await get_tree().create_timer(0.32).timeout
	check(Game.profile.equipment["forge-target"].enhancement_rank == 1 and Game.profile.permanent_gold == gold-63,"rapid repeat adds one rank and one debit")
	await press("ForgeLock")
	choose("forge-target","sell")
	check(Game.profile.equipment["forge-target"].lock_state and panel.action_button.disabled,"lock blocks recycling")
	await press("ForgeLock")
	check(not Game.profile.equipment["forge-target"].lock_state and not panel.action_button.disabled,"unlock restores operation")
	choose("potential-only","enhancement_reroll")
	check(panel.find_child("ForgeRank",true,false) != null and panel.find_child("ForgeAdvancedDetails",true,false).text.contains("c=3"),"per-step pity displayed")
	await press()
	check(Game.profile.equipment["potential-only"].enhancement_steps[0].g == 9,"fourth reroll guaranteed improvement")
	check(panel.forge_result_details.contains("潜力提高") or panel.forge_result_details.contains("Potential improved"),"potential-only result never invents integer +1")
	choose("forge-target","refine")
	check(panel.find_child("ForgeIntegerPreview",true,false).text.contains("当前配装") or panel.find_child("ForgeIntegerPreview",true,false).text.contains("Current loadout"),"refine shows effective current loadout comparison")
	await press()
	check(Game.profile.equipment["forge-target"].affix_type_and_quantile[0].u == 30,"actual refine button increases u10")
	choose("forge-target","reforge")
	var old_affix: Dictionary = Game.profile.equipment["forge-target"].affix_type_and_quantile[0].duplicate(true)
	await press()
	var pending: Dictionary = Game.profile.equipment["forge-target"].get("pending_reforge",{}).duplicate(true)
	check(not pending.is_empty() and panel.find_child("PendingReforge",true,false) != null,"paid candidate has durable choice UI")
	if pending.is_empty():
		print("Numerical forging UI blocked: ",failures)
		get_tree().quit(1)
		return
	check(panel.find_child("PendingReforgeComparison",true,false).position.x == 20, "old and candidate affixes get dedicated side-by-side cards")
	check(panel.find_child("PendingReforgeDetails",true,false).position.x == 630, "paid decision details stay in the right action pane")
	var all_stats: Label = panel.find_child("PendingAllStats",true,false)
	check(not all_stats.visible, "unchanged stats are hidden by default")
	panel.find_child("PendingAllStatsToggle",true,false).button_pressed = true
	check(all_stats.visible, "full before/after stats remain available on demand")
	check(not panel.find_child("ForgeInstanceIdentity",true,false).text.contains("forge-target") and panel.find_child("ForgeInstanceIdentity",true,false).tooltip_text.contains("forge-target"), "instance identity is retained in secondary tooltip")
	gold = Game.profile.permanent_gold
	Game.reload_profile()
	app.show_camp()
	app.show_workshop("upgrade")
	await get_tree().process_frame
	panel = app.screen.find_child("Workshop",true,false)
	choose("forge-target","reforge")
	check(same(Game.profile.equipment["forge-target"].pending_reforge,pending) and panel.find_child("KeepReforge",true,false) != null,"reload/reopen preserves frozen candidate")
	await press("KeepReforge")
	check(not Game.profile.equipment["forge-target"].has("pending_reforge") and same(Game.profile.equipment["forge-target"].affix_type_and_quantile[0],old_affix) and Game.profile.permanent_gold == gold,"keep old resolves without second charge")
	choose("forge-target","reforge")
	check(panel.find_child("ForgeAffix",true,false).disabled,"reforge slot binding visible")
	await press()
	var replacement: Dictionary = Game.profile.equipment["forge-target"].pending_reforge.new_affix.duplicate(true)
	await press("ReplaceReforge")
	check(Game.profile.equipment["forge-target"].affix_type_and_quantile[0] == replacement,"replace commits frozen candidate")
	choose("forge-target","enhance")
	var before := Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	await press()
	var operation: String = panel.forge_transaction_id
	check(not operation.is_empty() and Game.profile == before,"failed write preserves assets and nonce")
	app.show_camp()
	app.show_workshop("upgrade")
	await get_tree().process_frame
	panel = app.screen.find_child("Workshop",true,false)
	check(panel.forge_transaction_id == operation and panel.selected_item == "forge-target","reopen resumes frozen failed-save request")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	await press()
	check(Game.profile.equipment["forge-target"].enhancement_rank == 2 and panel.forge_transaction_id.is_empty(),"retry commits once and clears cache")
	Game._store.max_document_bytes = 1
	await press()
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	await press("CancelForgeRetry")
	check(Game.pending_forging_v2().is_empty() and Game.profile.equipment["forge-target"].enhancement_rank == 2,"explicit cancel abandons unpaid failed attempt")
	choose("inherit-target","inherit")
	panel.forge_source_instance_id = "inherit-source"
	panel._render()
	var cost: String = panel.find_child("ForgeAdvancedDetails",true,false).text
	check(cost.contains("158") and (cost.contains("基础补差") or cost.contains("Base makeup")) and (cost.contains("重锻补差") or cost.contains("Reroll makeup")),"inherit full fee/base/reroll breakdown")
	await press()
	check(Game.profile.equipment["inherit-source"].enhancement_rank == 0 and Game.profile.equipment["inherit-target"].enhancement_rank == 2,"inherit source cleared target improved")
	choose("forge-target","sell")
	gold = Game.profile.permanent_gold
	await press()
	check(app.find_child("ForgeRecycleConfirmation",true,false) != null and Game.profile.equipment.has("forge-target"),"sell requires concrete confirmation")
	app.find_child("CancelForgeRecycle",true,false).pressed.emit()
	await get_tree().process_frame
	check(Game.profile.equipment.has("forge-target") and Game.profile.permanent_gold == gold,"cancel sale unchanged")
	await press()
	app.find_child("ConfirmForgeRecycle",true,false).pressed.emit()
	await get_tree().create_timer(0.32).timeout
	check(not Game.profile.equipment.has("forge-target") and Game.profile.permanent_gold > gold,"confirmed sale removes exactly selected instance")
	choose("dismantle-target","dismantle")
	var materials_before: int = Game.profile.materials.forge
	await press()
	app.find_child("ConfirmForgeRecycle",true,false).pressed.emit()
	await get_tree().create_timer(0.32).timeout
	check(not Game.profile.equipment.has("dismantle-target") and Game.profile.materials.forge == materials_before+4,"confirmed dismantle returns green base material")
	panel._switch_page("inventory")
	panel.inventory_recycle = true
	panel._render()
	check(panel.find_child("ForgeAction_sell",true,false) != null and panel.find_child("ForgeAction_dismantle",true,false) != null,"V2 recycle route usable for both actions")
	Game.reload_profile()
	check(not Game.profile.equipment.has("forge-target") and Game.profile.equipment["inherit-source"].enhancement_rank == 0,"forging and recycling survive reload")
	var capped := Game.profile.duplicate(true)
	for pair in [["head","EQ14"],["hands","EQ34"],["ring","EQ100"],["charm","EQ54"]]:
		var record := item("cap-"+pair[0],pair[1],"gold")
		var affixes: Array = [{"type":"resource_gain_bonus","u":0 if pair[0] == "head" else 100}]
		for key: String in Instances.legal_affixes(pair[1],"physical"):
			if key != "resource_gain_bonus" and affixes.size() < 4: affixes.append({"type":key,"u":100})
		record.affix_type_and_quantile = affixes
		capped.equipment[record.instance_id] = record
		capped.loadout[pair[0]] = record.instance_id
	check(Game._commit_profile(capped),"capped effective-loadout fixture saved")
	panel._switch_page("upgrade")
	choose("cap-head","refine")
	gold = Game.profile.permanent_gold
	check(panel.action_button.disabled and panel.find_child("ForgeIntegerPreview",true,false) != null,"capped equipped refine disabled with comparison retained")
	check(panel.find_child("ForgeResult",true,false).text.contains("不收取") or panel.find_child("ForgeResult",true,false).text.contains("no charge"),"cap rejection explains no fee")
	check(Game.profile.permanent_gold == gold,"capped quote never charges")
	check(panel.find_child("ForgeIntegerPreview",true,false).text.contains("30.0%"),"capped resource-gain percentage is not truncated to integer zero")
	var flat_profile: Dictionary = Game.profile.duplicate(true)
	var flat := item("flat-preview","EQ04","green",1)
	var other: String = Instances.legal_affixes("EQ04","physical").filter(func(key: String) -> bool: return key != "attack")[0]
	flat.affix_type_and_quantile = [{"type":"attack","u":100},{"type":other,"u":0}]
	flat_profile.equipment["flat-preview"] = flat
	check(Game._commit_profile(flat_profile),"flat affix preview fixture")
	choose("flat-preview","enhance")
	var flat_quote: Dictionary = Game.quote_forging_v2("enhance",{"instance_id":"flat-preview"})
	var expected_low := flat.duplicate(true)
	expected_low.enhancement_rank = 1
	expected_low.enhancement_steps = [{"g":8,"pity":0,"base_price_peak":40}]
	var expected_high := expected_low.duplicate(true)
	expected_high.enhancement_steps[0].g = 12
	check(flat_quote.before_stats.attack > flat_quote.before_main_stats.attack,"fixture contains extra flat attack affix")
	var range_text := str(int(Instances.main_stats(flat).attack))+" → "+str(int(Instances.main_stats(expected_low).attack))+"–"+str(int(Instances.main_stats(expected_high).attack))
	check(panel.find_child("ForgeIntegerPreview",true,false).text.contains(range_text),"actual main preview excludes flat affix before and after")
	for locale: String in ["zh_CN","en"]:
		Words.locale = locale
		panel._switch_page("upgrade")
		choose("inherit-target","enhance")
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			get_window().size = extent
			await get_tree().process_frame
			check(panel.action_button.position.y+panel.action_button.size.y <= 510 and panel.find_child("ForgeDetails",true,false).size.y > 200,"scroll layout bounded "+locale+str(extent))
	check(Game._commit_profile(ProfileStore.fresh_profile()),"isolated legacy fixture preserved")
	app.show_workshop("upgrade")
	await get_tree().process_frame
	panel = app.screen.find_child("Workshop",true,false)
	check(panel.find_child("ForgeInventory",true,false) == null and panel.find_child("EquipmentGrid",true,false) != null,"legacy upgrade continues through original catalog")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("Numerical forging UI: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
