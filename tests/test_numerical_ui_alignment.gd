extends Node
## Real scene/controls in isolated V2 profiles. Presentation checks, not balance.
const Fixtures = preload("res://tests/test_numerical_instance_storage.gd")
const Economy = preload("res://scripts/core/instance_economy.gd")
const Migration = preload("res://scripts/core/numerical_migration.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Skills = preload("res://scripts/ui/skill_inspection.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Sheet = preload("res://scripts/ui/stat_sheet.gd")
var checks := 0
var failures: Array[String] = []
var app: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAILED: ",label)

func frames() -> void:
	for index in 3: await get_tree().process_frame

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(100).timeout.connect(func(): print("UI alignment timed out"); get_tree().quit(1))

func all_text(node: Node) -> String:
	var result := str(node.text)+"\n" if node is Label or node is Button or node is RichTextLabel else ""
	for child: Node in node.get_children(): result += all_text(child)
	return result

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(Game.profile_path).get_base_dir().path_join("s10-ui-captures")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): folder = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder+"/"+label+".png") == OK,"capture "+label)

func _run() -> void:
	if not Game.profile_path.contains("test_numerical_ui_alignment"):
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"isolated profile")
	var profile := Fixtures.fixture_profile()
	profile.hero_xp.CH01 = 3600
	profile.hero_xp.CH03 = 3600
	profile.talents = {"CH01":{"mastery":5,"precision":5,"vitality":5,"dexterity":4}}
	var duplicate := Fixtures.fixture_instance("ui-roll-copy","EQ03",50,"physical",20)
	duplicate.rarity = "gold"
	for key: String in Instances.legal_affixes("EQ03","physical").slice(0,4): duplicate.affix_type_and_quantile.append({"type":key,"u":20})
	duplicate.enhancement_steps = [{"g":8,"pity":0,"base_price_peak":Economy.enhancement_price(1,20)},{"g":10,"pity":0,"base_price_peak":Economy.enhancement_price(2,20)}]
	duplicate.enhancement_rank = 2
	profile.equipment[duplicate.instance_id] = duplicate
	check(Game._commit_profile(profile),"eight-slot/talent/duplicate fixture: "+Game.last_error)
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await frames()
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		app.show_camp()
		await frames()
		var camp_stats: Label = app.screen.find_child("CampCombatStats",true,false)
		check(camp_stats != null and not camp_stats.text.contains(".0") and camp_stats.text.contains(str(int(Game.selected_stats().attack))),"camp hero card uses same integer attack "+locale)
		check(app._amount(2.5) == "2.5" and app._amount(486.0) == "486","times/legacy fractions retained without fake decimal "+locale)
		check(Words.text("SLOT_LEGS") != "SLOT_LEGS" and Words.text("SLOT_RING") != "SLOT_RING","translated new slots "+locale)
		check(Inspect.value("attack",463,false,false,2) == "463" and Inspect.value("attack",0,true,true,2) == "+0","settled flat integers "+locale)
		check(Inspect.value("attack",0.4,true) == "+0.4" and Inspect.value("attack_interval",0.125) == "0.125 s","legacy fractions/time retained "+locale)
		check(Inspect.value("hp_ratio",0.126,false,true,2) == "12.6%","ratio remains percent "+locale)
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1920,1080)]:
			get_window().size = extent
			app.show_workshop("inventory")
			await frames()
			var panel: Control = app.screen.find_child("Workshop",true,false)
			var capacity: Control = app.screen.find_child("StorageCapacityHint",true,false)
			var header: Control = panel.find_child("WorkshopHeader",true,false)
			check(capacity != null and header.get_global_rect().encloses(capacity.get_global_rect()),"capacity hint stays inside header "+locale+str(extent))
			var navigation: Control = panel.find_child("OpenCharacterStats",true,false)
			check(capacity != null and capacity.get_global_rect().end.y <= navigation.get_global_rect().position.y,"capacity hint avoids the navigation row "+locale+str(extent))
			panel.selected_item = duplicate.instance_id
			panel._render()
			await frames()
			for slot: String in ContentRegistry.slots(2): check(panel.find_child("Slot_"+slot,true,false) != null,"slot "+slot+locale+str(extent))
			check(panel.find_child("EquipmentGrid",true,false).get_child_count() == 9,"duplicates remain separate "+locale+str(extent))
			var detail: Control = panel.find_child("EquipmentDetailContent",true,false)
			check(detail.find_child("InstanceId",true,false).text.contains(duplicate.instance_id),"instance identity visible "+locale+str(extent))
			var actual := Instances.stats(duplicate)
			check(detail.find_child("ItemStat_attack",true,false).get_child(3).text == str(int(actual.attack)),"actual settled integer displayed "+locale+str(extent))
			check(detail.find_child("MainRoll_attack",true,false).text.contains("k 50/100") and detail.find_child("AffixRoll_"+str(duplicate.affix_type_and_quantile[0].type),true,false).text.contains("u 20/100"),"main and affix ranges visible "+locale+str(extent))
			check(not all_text(panel).contains("SLOT_") and not all_text(panel).contains("hp_ratio"),"no raw schema keys "+locale+str(extent))
			check(not panel.find_child("LoadoutStatSummary",true,false).text.contains(".0"),"loadout integer summary "+locale+str(extent))
			check(panel.action_button.position.y+panel.action_button.size.y <= 510 and detail.custom_minimum_size.x <= 448,"detail bounded and scrollable "+locale+str(extent))
			await capture("inventory-"+locale+"-"+str(extent.x)+"x"+str(extent.y))
			panel.detail_tab = "compare"
			panel._render()
			await frames()
			check(panel.find_child("CombatCompare_q_packet",true,false) != null,"Q packet comparison visible "+locale+str(extent))
			panel.detail_tab = "stats"
			if extent.x == 1440:
				panel._show_character_stats()
				await frames()
				await capture("attributes-"+locale)
				app._pop_modal()
				await frames()
			var sheet := Sheet.new()
			add_child(sheet)
			var report := Inspect.breakdown("CH01",20,profile.loadout,profile.equipment,null,2,profile.talents.CH01)
			sheet.configure(report,620)
			await frames()
			var row: Node = sheet.find_child("StatSource_attack",true,false)
			var sources: Dictionary = row.get_meta("sources")
			check(row.get_child_count() == 7 and sources.talents > 0 and sources.gear == report.total.attack-report.talented.attack,"talents distinct from gear "+locale+str(extent))
			check(row.get_child(6).text == str(int(report.total.attack)),"source total equals resolver "+locale+str(extent))
			sheet.queue_free()
			await frames()
	var legacy := ProfileStore.fresh_profile()
	legacy.hero_xp.CH03 = 3600
	var migrated := Migration.migrate_profile(legacy,"migration:s10-ui")
	check(not migrated.is_empty(),"real migration fixture")
	var record: Dictionary = migrated.equipment[migrated.loadout.weapon]
	var definition := ContentRegistry.equipment(str(record.template_id),2).duplicate(true)
	definition.instance_record = record
	definition.instance_id = record.instance_id
	var view: Control = load("res://scripts/ui/equipment_details.gd").new()
	add_child(view)
	view.configure(definition,int(record.enhancement_rank),426,"CH01",{}, {})
	check(view.find_child("LegacyEquipWaiver",true,false) != null and view.find_child("LegacyEquipWaiver",true,false).text.contains("Lv.20"),"current hero migration waiver visible")
	check(Inspect.waiver_note(record,"CH02").is_empty(),"unreferenced hero receives no waiver claim")
	view.queue_free()
	await frames()
	await _live_ui()
	await _shield_amounts()
	app.queue_free()
	Game.run = null
	await frames()
	await get_tree().create_timer(0.3).timeout
	print("Numerical UI alignment: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _live_ui() -> void:
	var owned := {}
	var fitted := {}
	for template: String in ContentRegistry.set_item_ids("S06",2):
		var item := Fixtures.fixture_instance("live-"+template,template,50,"magic",1)
		owned[item.instance_id] = item
		fitted[ContentRegistry.equipment(template,2).slot] = item.instance_id
	var mage := Resolver.resolve("CH03",20,fitted,owned,2,{})
	mage.resource_gain_bonus = 0.30
	Game.run = RunState.new()
	Game.run.hero_id = "CH03"
	Game.run.level = 20
	Game.run.stats = mage
	Game.run.loadout_snapshot = fitted
	Game.run.equipment_snapshot = owned
	Game.run.max_hp = mage.max_hp
	Game.run.hp = mage.max_hp-17
	Game.run.resource = 800
	var room: Node2D = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	add_child(room)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var hud: Control = load("res://scripts/ui/hud.gd").new()
	hud.room = room
	add_child(hud)
	await frames()
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		var prior_hero: String = Game.run.hero_id
		var prior_resource: Variant = Game.run.resource
		for resource_hero: String in ["CH01","CH02","CH03"]:
			Game.run.hero_id = resource_hero
			Game.run.resource = 1000
			hud.refresh()
			var font: Font = hud.resource_label.get_theme_font("font")
			var text_width: float = font.get_string_size(hud.resource_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,hud.resource_label.get_theme_font_size("font_size")).x
			check(text_width <= hud.resource_label.size.x and hud.resource_label.text.contains("1000 / "),"full four-digit resource fits without ellipsis "+resource_hero+locale)
		Game.run.hero_id = prior_hero
		Game.run.resource = prior_resource
		hud.refresh()
		var info: Dictionary = hud.skill_info("q")
		var powers := HeroAbilities.preview_powers("CH03",mage)
		check(info.summary.contains("180") and info.description.contains("skill H %d" % int(powers.skill_H) if locale == "en" else "技能 H %d" % int(powers.skill_H)),"HUD shared H/cost "+locale)
		check(info.description.contains("104") and Skills.passive_text(ContentRegistry.hero("CH03"),mage,room.player).contains("104"),"passive refund uses shared gain multiplier "+locale)
		check(Skills.authored_text("20怒气 35 health 0.10 s 160 units",2) == "200怒气 350 health 0.10 s 160 units" and Skills.authored_text("节点生命 35 → 50 / node health increases from 35 to 50",2).contains("350 → 500 / node health increases from 350 to 500"),"authored conversion includes upgrade health, excludes time/range "+locale)
		var backpack: Control = load("res://scripts/ui/backpack_panel.gd").new()
		add_child(backpack)
		backpack.configure(room,func(): pass)
		backpack.tab = "stats"
		backpack._render()
		await frames()
		check(backpack.find_child("BackpackAttribute_attack",true,false).text == str(int(mage.attack)),"backpack uses V2 resolver "+locale)
		check(backpack.find_child("BackpackAttribute_resource_regen",true,false).text == "65","integer effective regeneration "+locale)
		backpack.queue_free()
		await frames()
	room.player.grant_guard(100,4,"hero_f")
	var report := Inspect.breakdown("CH03",20,fitted,owned,room.player,2,{})
	var live_sheet := Sheet.new()
	add_child(live_sheet)
	live_sheet.configure(report,620)
	check(live_sheet.find_child("SetTrigger_S06_4",true,false).text.contains("6.0") and live_sheet.find_child("SetTrigger_S06_4",true,false).text.contains("4.0"),"real accepted guard shows set cooldown and duration")
	check(live_sheet.find_child("StatSource_damage_bonus",true,false).get_meta("sources").buff == 0.20,"real set buff is separate current source")
	live_sheet.queue_free()
	check(int(report.live.resource_regen) == 65,"live effective rate rounded once")
	var capped := mage.duplicate(true)
	capped.uncapped_equipment_contribution = {"hp_ratio":0.72,"resource_gain_bonus":0.44,"cooldown_reduction":0.37}
	capped.equipment_contribution = {"hp_ratio":0.60,"resource_gain_bonus":0.30,"cooldown_reduction":0.30}
	capped.cooldown_reduction = 0.30
	var notes := "\n".join(Inspect.cap_notes(capped))
	check(notes.contains("12.0%") and notes.contains("14.0%") and notes.contains("7.0%") and not notes.contains("hp_ratio"),"raw effective and cap losses shown")
	hud.queue_free()
	room.queue_free()
	await frames()

func _shield_amounts() -> void:
	Game.run = RunState.new()
	Game.run.hero_id = "CH01"
	Game.run.stats = Resolver.resolve("CH01",20,{}, {},2,{})
	Game.run.level = 20
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 1000
	var room: Node2D = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	add_child(room)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var hud: Control = load("res://scripts/ui/hud.gd").new()
	hud.room = room
	add_child(hud)
	await frames()
	for sample: Array in [[13,"f",""],[14,"f",""],[20,"f",""],[18,"q","B"],[20,"q","B"]]:
		var level: int = sample[0]
		var slot: String = sample[1]
		Game.run.level = level
		Game.run.stats = Resolver.resolve("CH01",level,{}, {},2,{})
		Game.run.stats.branches = {"q":sample[2]}
		Game.run.max_hp = Game.run.stats.max_hp
		Game.run.hp = Game.run.max_hp-17
		Game.run.shield = 0
		Game.run.resource = 1000
		room.player.status.states.clear()
		room.player.status.guards.clear()
		room.player.cooldowns.clear()
		room.player.abilities.cancel()
		room.player.passives.reset()
		var spec: Dictionary = room.player.skill_definition(slot)
		check(room.player.abilities.try_cast(slot,room.player.position+Vector2.RIGHT*20),"actual shield skill commits "+str(sample))
		room.player.abilities.tick(float(spec.duration)+0.01)
		var guard: Dictionary = room.player.status.guards.get("hero_"+slot,{})
		check(not guard.is_empty() and typeof(guard.amount) == TYPE_INT and guard.remaining == 4.0,"actual integer shield with four-second duration "+str(sample))
		if guard.is_empty(): continue
		for locale: String in ["zh_CN","en"]:
			Words.set_locale(locale)
			var live: Dictionary = hud.skill_info(slot)
			var camp := Skills.describe("CH01",level,Game.run.stats,slot,spec)
			var phrase := ("grants %d shield for 4.0 s" if locale == "en" else "授予护盾 %d，持续 4.0 秒") % int(guard.amount)
			check(live.description.contains(phrase) and camp.contains(phrase),"live/camp shield integer equals actual grant "+str(sample)+locale)
			if slot == "f":
				var reduction: Dictionary = room.player.status.states.get("brace_guard",{})
				var reduction_phrase := "25% damage reduction for 1.5 s" if locale == "en" else "25% 减伤，持续 1.5 秒"
				check(not reduction.is_empty() and reduction.power == 0.25 and reduction.remaining == 1.5 and live.description.contains(reduction_phrase),"E shield and damage-reduction clocks distinct "+str(sample)+locale)
	Game.run.shield = 0
	room.player.status.guards.clear()
	room.player.passives.reset()
	var target := Node2D.new()
	room.add_child(target)
	for index in 3:
		room.player.passives.record_hit(target,&"primary",{"original_basic":true,"equipment_eligible":true,"root_event_id":"ui-passive:"+str(index),"hp_damage":1,"proc_depth":0})
	var passive_guard: Dictionary = room.player.status.guards.get("hero_passive:three_rivets",{})
	check(not passive_guard.is_empty() and typeof(passive_guard.amount) == TYPE_INT and passive_guard.remaining == 3.0,"three actual confirmed-hit records grant passive integer shield")
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		var description := Skills.passive_text(ContentRegistry.hero("CH01"),Game.run.stats,room.player)
		var phrase := ("grants %d shield for 3.0 s" if locale == "en" else "护盾 %d，持续 3.0 秒") % int(passive_guard.get("amount",0))
		check(description.contains(phrase) and description.contains("6.0"),"passive UI integer and lifetime equal actual grant "+locale)
	hud.queue_free()
	room.queue_free()
	await frames()
