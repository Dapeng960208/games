extends SceneTree
## Focused market/recycle acceptance, isolated saves and real workshop controls.
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Art = preload("res://scripts/infrastructure/assets/equipment_art.gd")
const Rules = preload("res://scripts/domain/combat/equipment_effects.gd")
var game: Node
var app: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")
	create_timer(120).timeout.connect(func(): push_error("Market acceptance timeout"); quit(1))

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+description)

func frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func panel() -> Control:
	return app.screen.find_child("Workshop",true,false)

func _transactions() -> void:
	check(game.new_profile(),"fresh isolated profile")
	check(not game.buy_equipment_set("S09","no-money"),"unaffordable set rejected")
	check(game.start_run() and game.add_gold(50000),"earn market fixture gold through real run")
	game.finish_run("extracted")
	var before: Dictionary = game.profile.duplicate(true)
	check(game.equipment_set_quote("S09").price == 810 and game.profile == before,"six-piece quote is pure and costs 810")
	check(not game.buy_equipment_set("missing") and not game.buy_equipment_set("S02"),"unknown and boss-locked sets rejected")
	check(game.buy_equipment("EQ61","one-piece") and game.upgrade_equipment("EQ61","one-refine"),"buy and refine one set piece")
	check(game.equipment_set_quote("S09").price == 648,"partial set only charges discounted missing pieces")
	var wallet: int = game.profile.permanent_gold
	check(game.buy_equipment_set("S09","set-1"),"complete set in one real save")
	check(game.profile.permanent_gold == wallet-648 and game.equipment_level("EQ61") == 1,"one set debit preserves existing refinement")
	check(game.buy_equipment_set("S09","set-1") and game.profile.permanent_gold == wallet-648,"repeated set transaction cannot debit twice")
	check(not game.buy_equipment_set("S10","set-1"),"set transaction collision rejected")
	game.reload_profile()
	check(game.profile.equipment.has("EQ66") and game.buy_equipment_set("S09","set-1"),"set receipt and items survive restart")
	check(game.equip_equipment_set("S09") and game.selected_stats().sets.S09 == 6,"equip all six slots in one save")
	check(game.start_run(),"start actual new equipment snapshot")
	check(game.run.stats.sets.S09 == 6 and game.run.equipment_snapshot.has("EQ61"),"new equipment reaches production run stats")
	check(not game.buy_equipment_set("S10") and not game.equip_equipment_set("S09") and not game.sell_equipment_items(["EQ01"]),"camp mutations rejected during run")
	game.finish_run("extracted")
	check(game.buy_equipment_set("S10","set-2") and game.upgrade_equipment("EQ67","refine-sale"),"prepare spare set with refinement")
	check(game.equipment_sell_value("EQ67") == 57,"refined recycle value uses base 25 percent plus paid step 20 percent")
	before = game.profile.duplicate(true)
	check(not game.sell_equipment_items([]) and not game.sell_equipment_items(["EQ67","EQ67"]) and not game.sell_equipment_items(["EQ67","missing"]),"empty, duplicate and unknown selections reject atomically")
	check(not game.sell_equipment_items(["EQ67","EQ61"]) and game.profile == before,"an equipped piece rejects the whole batch")
	var blocker: String = game.profile_path+"_blocker"
	var file := FileAccess.open(AssetCatalog.resolve(blocker),FileAccess.WRITE)
	file.store_string("not a directory")
	file.close()
	game._store.path = blocker+"/profile.json"
	check(not game.sell_equipment_items(["EQ67","EQ68"],"sale-failed") and game.profile == before,"failed sale preserves inventory, wallet and receipts")
	check(not game.buy_equipment_set("S11","set-failed") and game.profile == before,"failed bundle purchase preserves all fields")
	game._store.path = game.profile_path
	check(game.buy_equipment_set("S11","set-failed"),"failed bundle can retry after storage repair")
	wallet = game.profile.permanent_gold
	check(game.sell_equipment_items(["EQ68","EQ67"],"sale-failed"),"batch sells two spare items")
	check(game.profile.permanent_gold == wallet+92 and not game.profile.equipment.has("EQ67") and not game.profile.equipment.has("EQ68"),"exact batch proceeds and exact inventory removals")
	check(game.sell_equipment_items(["EQ67","EQ68"],"sale-failed") and game.profile.permanent_gold == wallet+92,"reordered same sale receipt credits once")
	check(not game.sell_equipment_items(["EQ69"],"sale-failed"),"sale transaction collision rejected")
	game.reload_profile()
	check(game.profile.permanent_gold == wallet+92 and not game.profile.equipment.has("EQ67"),"sale survives reload despite old purchase and upgrade history")
	check(game.sell_equipment_items(["EQ68","EQ67"],"sale-failed") and game.profile.permanent_gold == wallet+92,"sale retry after reload never credits again")
	check(game.buy_equipment("EQ67") and game.equipment_level("EQ67") == 0,"sold refined equipment can be bought again unrefined")
	check(game.buy_equipment_set("S10") and game.profile.equipment.has("EQ68"),"a previously bought set can fill recycled gaps")
	check(game.start_run(),"start boss milestone fixture")
	for boss: String in ["BO01","BO02","BO03","BO04"]: check(game.record_boss_defeat(boss),"unlock existing set "+boss)
	game.finish_run("extracted")
	for id: String in Registry.equipment_ids():
		if not game.profile.equipment.has(id): check(game.buy_equipment(id),"own catalog item "+id)
	game.reload_profile()
	check(game.profile.equipment.size() == 96,"expanded full inventory survives profile validation")
	check(game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":4242}),"all 96 owned items fit a real expedition checkpoint")
	game.reload_profile()
	check(game.run != null and game.run.equipment_snapshot.size() == 96,"real expedition recovery retains all 96 equipment records")
	check(not game.finish_run("abandoned").is_empty(),"recovered expanded inventory can settle safely")

func _art_and_rules() -> void:
	for number in range(9,15):
		var id := "S%02d" % number
		var ids := Registry.set_item_ids(id)
		var loadout := {}
		var owned := {}
		for eq: String in ids:
			loadout[Registry.equipment(eq).slot] = eq
			owned[eq] = {"level":0}
			check(Art.texture(eq) != null,"real generated texture for "+eq)
		check(ids.size() == 6 and Rules.implemented_set_ids().has(id),"six real pieces and implemented rules for "+id)
		var effects: RefCounted = Rules.new()
		var stats: Dictionary = StatResolver.resolve("CH01",1,loadout,owned)
		effects.configure(loadout,stats,"rage")
		var ctx: Dictionary = {"event_id":"fixture", "hp":stats.max_hp*.4,"max_hp":stats.max_hp,"resource":80.0,"resource_max":100.0,"shield":20.0,"moving":true,"enemy_damage":true,"hp_damage":1.0,"shield_absorbed":0.0,"original_basic":true,"equipment_eligible":true,"damage_source":"primary","proc_depth":0,"valid_target":true,"target_id":"target","target_alive":true,"critical":true,"X":100.0,"H":stats.attack,"target_states":[],"remaining_cooldowns":{"Q":4.0},"resource_type":"rage","base_cost":10.0,"cast_success":true}
		if id == "S12": ctx.hp = stats.max_hp
		var passive: Dictionary = Registry.sets()[id].shop_passive
		check(float(effects.passive_modifiers(ctx)[passive.stat]) >= float(passive.amount),id+" two-piece passive activates under its condition")
		match id:
			"S09":
				var result: Dictionary = effects.handle("damaged",ctx)
				check(result.shield_ratio == .05 and result.damage_bonus >= .08,"Dawn 4-piece shield and 6-piece damage")
				ctx.event_id = "damage-2"
				check(effects.handle("damaged",ctx).shield_ratio == 0.0,"Dawn shield obeys cooldown")
			"S10":
				var result: Dictionary = effects.handle("dash",ctx)
				check(result.shield_ratio == .04 and result.move_speed_bonus >= .15,"Mossleaf movement and dash shield")
			"S11":
				check(effects.handle("skill_cast",ctx).damage_bonus >= .13,"Starbell paid skill damage buff")
				var refund := 0.0
				for index in range(4):
					ctx.event_id = "basic-"+str(index)
					for record: Dictionary in effects.handle("after_hit",ctx).cooldown_refunds: refund += float(record.seconds)
				check(is_equal_approx(refund,.35),"Starbell fourth basic hit refunds an actual cooldown")
			"S12":
				var result: Dictionary = effects.handle("after_hit",ctx)
				check(result.attack_speed_bonus >= .08 and result.bonus_hits.size() == 1 and result.bonus_hits[0].damage == 30.0,"Honeywing critical combo and precise bonus")
			"S13":
				var result: Dictionary = effects.handle("kill",ctx)
				check(result.heal_ratio == .02 and result.shield_ratio == .05,"Pumpkin kill recovery and shield")
				ctx.event_id = "duplicate-kill"
				check(effects.handle("kill",ctx).heal_ratio == 0.0,"same enemy cannot heal twice")
			"S14":
				check(effects.handle("damaged",ctx).attack_speed_bonus >= .10,"Terracotta low-health speed")
				ctx.event_id = "low-hit"
				var result: Dictionary = effects.handle("after_hit",ctx)
				check(result.bonus_hits.size() == 1 and result.bonus_hits[0].damage == 25.0,"Terracotta low-health bonus damage")
		# Derived packets never retrigger the new attack effects.
		ctx.event_id = "derived"
		ctx.proc_depth = 1
		check(effects.handle("after_hit",ctx).bonus_hits.is_empty(),id+" derived damage cannot recurse")
		var next := loadout.duplicate()
		for slot: String in Registry.SLOTS.slice(2): next.erase(slot)
		effects.rebind(next,stats,"rage")
		check(not Rules.source_active(id+"_4",Rules.loadout_binding(next)),id+" four-piece effects retire when broken")

func click(name: String) -> void:
	var button := panel().find_child(name,true,false) as Button
	check(button != null and not button.disabled,"usable real control "+name)
	if button != null and not button.disabled: button.pressed.emit()
	await frames()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png("res://artifacts/"+name+".png")

func _ui() -> void:
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	root.add_child(app)
	await frames()
	app.show_camp()
	await frames()
	app.screen.find_child("Open_shop",true,false).pressed.emit()
	await frames()
	check(panel().shop_sets and panel().find_children("Set_*","Button",true,false).size() == 14,"camp shop opens all fourteen bundles without another toggle")
	for id: String in ["S09","S10","S11","S12","S13","S14"]:
		check(panel().item_list.get_global_rect().encloses(panel().find_child("Set_"+id,true,false).get_global_rect()),"new set immediately visible: "+id)
	await click("ToggleSetShop")
	check(not panel().shop_sets and panel().find_child("Item_EQ01",true,false) != null,"single-item shop remains accessible")
	await click("ToggleSetShop")
	await click("Set_S09")
	check(panel().action_button.disabled,"already fitted set cannot re-equip")
	await click("Set_S10")
	await click("PrimaryAction")
	await create_timer(.35).timeout
	check(game.selected_stats().sets.get("S10") == 6,"real set shop equips all six slots")
	app.show_workshop("inventory")
	await frames()
	await click("Tab_shop")
	check(panel().shop_sets and panel().find_child("Set_S09",true,false) != null,"inventory shop tab exposes the new bundles immediately")
	await click("Tab_inventory")
	panel().slot_filter = "weapon"
	panel().set_filter = "S09"
	panel()._render()
	await frames()
	check(panel().find_children("Item_*","Button",true,false).size() == 1,"owned weapon and set filters reproduce the one-row inventory")
	await click("ViewAllEquipment")
	check(panel().find_children("Item_*","Button",true,false).size() == game.profile.equipment.size(),"view all owned clears filters and shows exactly the permanent inventory")
	await click("ToggleRecycle")
	check(panel().find_child("SellItem_EQ67",true,false).disabled,"currently fitted gear protected in recycle UI")
	await click("SellItem_EQ61")
	await click("SellItem_EQ62")
	check(panel().sale_selection.size() == 2,"two real row clicks select two items")
	await click("PrimaryAction")
	check(app.modals.size() == 1,"batch sale presents its confirmation")
	app._pop_modal()
	await frames()
	check(not panel().busy and panel().sale_selection.size() == 2 and not panel().action_button.disabled,"Esc dismissal retains selections and unlocks retry")
	await click("PrimaryAction")
	app.modals[-1].node.find_child("CancelEquipmentSale",true,false).pressed.emit()
	await frames()
	check(game.profile.equipment.has("EQ61") and panel().sale_selection.size() == 2,"cancel preserves inventory and selection")
	await click("PrimaryAction")
	var wallet: int = game.profile.permanent_gold
	app.modals[-1].node.find_child("ConfirmEquipmentSale",true,false).pressed.emit()
	await frames()
	check(not game.profile.equipment.has("EQ61") and not game.profile.equipment.has("EQ62") and game.profile.permanent_gold == wallet+92,"confirmed real UI batch credits exactly once")
	check(panel().sale_selection.is_empty(),"completed sale clears only finished selection")
	await click("SelectAllForSale")
	check(panel().sale_selection.size() == game.profile.equipment.size()-6,"select all excludes every equipped item")
	await click("ClearSaleSelection")
	check(panel().sale_selection.is_empty() and panel().action_button.disabled,"clear selection disables empty sale")
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1280,900)]:
			if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(extent)
			await frames()
			app.show_workshop("shop")
			await frames()
			check(panel().shop_sets,"shop defaults to bundles "+locale+str(extent))
			check(panel().action_button.get_global_rect().end.x <= root.get_visible_rect().end.x+1,"set action fits "+locale+str(extent))
			await capture("equipment_sets_"+locale+"_%dx%d" % [extent.x,extent.y])
			app.show_workshop("inventory")
			await frames()
			panel().inventory_recycle = true
			panel().sale_selection = {"EQ63":true,"EQ64":true,"EQ65":true}
			panel()._render()
			await frames()
			check(not panel().action_button.disabled,"recycle action usable "+locale+str(extent))
			await capture("equipment_recycle_"+locale+"_%dx%d" % [extent.x,extent.y])
	if app.music != null: await app.music.wait_for_cleanup()
	app.free()
	app = null
	await frames()

func _run() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_equipment_market"):
		push_error("Refusing player profile")
		quit(2)
		return
	_transactions()
	_art_and_rules()
	await _ui()
	print("EQUIPMENT MARKET: %d checks, %d failures; bundles/refinement/recycle/restart/rollback/real UI; renderer=%s" % [checks,failures,DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
