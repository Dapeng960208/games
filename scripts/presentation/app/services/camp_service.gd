extends RefCounted
## Camp behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func show_camp() -> void:
	if host.room_start_failed and Game.run != null: return
	preload("res://scripts/infrastructure/assets/equipment_art.gd").prefetch_owned(Game.profile.get("equipment",{}))
	host._new_screen("camp")
	host._screen_shade(0.07)
	var hero_id: String = Game.profile.get("selected_hero","CH01")
	var hero: Dictionary = ContentRegistry.hero(hero_id)
	var stats: Dictionary = Game.selected_stats()
	var level: int = Game.hero_level(hero_id)
	var identity: Array = host.HERO_LOOPS.get(hero_id,host.HERO_LOOPS.CH01)
	var accent = GameStyle.resource_color(str(hero.get("resource_type","rage")))
	var brand = GameStyle.panel(host.screen,Vector2.ZERO,Vector2(1280,64))
	brand.name = "CampBrand"
	host._camp_ui_icon(brand,"workshop",Vector2(26,7),Vector2(50,50))
	var brand_title = GameStyle.label(brand,"CAMP",Vector2(88,14),Vector2(320,40),24,GameStyle.INK)
	brand_title.name = "CampHeading"
	brand_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var codex_link = GameStyle.button(brand,"",Vector2(626,11),Vector2(140,44),host.show_codex)
	codex_link.text = host._ex_text("怪物图鉴","BESTIARY")
	codex_link.name = "OpenMonsterCodex"
	GameStyle.tab(codex_link)
	var profile_link = GameStyle.button(brand,"",Vector2(776,11),Vector2(140,44),host.show_profile)
	profile_link.text = host._ex_text("存档档案","PROFILE")
	GameStyle.tab(profile_link)
	var bank = Control.new()
	bank.position = Vector2(992,8)
	bank.size = Vector2(238,48)
	bank.name = "CampBank"
	brand.add_child(bank)
	host._camp_ui_icon(bank,"gold",Vector2(10,4),Vector2(36,36))
	GameStyle.literal(bank,str(int(Game.profile.get("permanent_gold",0))),Vector2(62,7),Vector2(162,34),23,GameStyle.INK)
	var portrait = GameStyle.hero_portrait(host.screen,hero_id,Vector2(28,116),Vector2(380,428))
	portrait.name = "CampHeroIllustration"
	var identity_plate = GameStyle.panel(host.screen,Vector2(42,505),Vector2(344,128))
	identity_plate.name = "CampHeroIdentity"
	GameStyle.literal(identity_plate,GameStyle.content_text(hero,"name"),Vector2(20,7),Vector2(210,40),30,GameStyle.INK)
	GameStyle.literal(identity_plate,"Lv."+str(level),Vector2(246,11),Vector2(78,35),22,accent).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	GameStyle.literal(identity_plate,host._ex_text(str(identity[0]),str(identity[3])),Vector2(21,48),Vector2(300,26),17,accent)
	GameStyle.literal(identity_plate,host._ex_text("生命 %d   攻击 %s   护甲 %d","HP %d   ATK %s   ARM %d") % [int(stats.get("max_hp",100)),host._amount(float(stats.get("attack",20))),int(stats.get("armor",0))],Vector2(21,78),Vector2(302,24),14,GameStyle.MUTED).name = "CampCombatStats"
	GameStyle.literal(identity_plate,host._ex_text(str(identity[2]),str(identity[4])),Vector2(21,105),Vector2(302,20),12,GameStyle.MUTED)
	var departure = GameStyle.panel(host.screen,Vector2(430,112),Vector2(806,196))
	departure.name = "CampDeparturePlan"
	host._camp_ui_icon(departure,"route",Vector2(17,10),Vector2(48,48))
	GameStyle.literal(departure,host._ex_text("下一站，向着阳光出发。","YOUR NEXT EXPEDITION."),Vector2(76,14),Vector2(706,39),27,GameStyle.INK)
	GameStyle.literal(departure,"",Vector2(24,63),Vector2(758,28),15,GameStyle.MUTED).name = "DepartureRouteHint"
	host._build_biome_selector()
	var difficulty_hint = GameStyle.literal(host.screen,"",Vector2(454,264),Vector2(758,22),12,GameStyle.INK)
	difficulty_hint.name = "DepartureDifficultyHint"
	var difficulty_choice = OptionButton.new()
	difficulty_choice.name = "DepartureDifficulty"
	difficulty_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	difficulty_choice.position = Vector2(967,214)
	difficulty_choice.size = Vector2(245,44)
	difficulty_choice.add_theme_font_size_override("font_size",17)
	for index in host.DIFFICULTY_KEYS.size(): difficulty_choice.add_item(Words.text(host.DIFFICULTY_KEYS[index]),index)
	host.selected_difficulty = clampi(host.selected_difficulty,0,host.DifficultyProfiles.MAX_DIFFICULTY)
	difficulty_choice.select(host.selected_difficulty)
	host.screen.add_child(difficulty_choice)
	difficulty_choice.item_selected.connect(func(index: int):
		host.selected_difficulty = clampi(index,0,host.DifficultyProfiles.MAX_DIFFICULTY)
		host._update_departure_difficulty_hint())
	host._update_departure_difficulty_hint()
	var choices = [
		["heroes",host._ex_text("英雄档案","HERO DOSSIERS"),host._ex_text("选择伙伴 · 找到你的战斗风格","Choose a hero and a fighting style"),0,GameStyle.CYAN],
		["skills",host._ex_text("技能修习","SKILL LEDGER"),host._ex_text("查看连招 · 解锁新的能力","Learn combos and unlock abilities"),1,Color("9b574c")],
		["inventory",host._ex_text("装备工坊","EQUIPMENT"),host._ex_text("仓库配装 · 多选回收换金币","Loadout · Sell spare gear for gold"),2,Color("997244")],
		["shop",host._ex_text("装备商城","EQUIPMENT SHOP"),(host._ex_text("八槽独立装备 · 选购或补齐","Eight-slot instances · Buy or complete") if int(Game.profile.get("ruleset_version",1)) == 2 else host._ex_text("六套新装备 · 整套购买或补齐","6 new sets · Buy or complete a set")),3,Color("657e4c")]
	]
	for index in choices.size():
		var entry: Array = choices[index]
		var mode: String = entry[0]
		var button = host._camp_navigation(host.screen,Vector2(430+(index%2)*414,326+(index/2)*116),Vector2(392,100),entry[1],entry[2],entry[3],entry[4],func(): host.show_workshop(mode))
		button.name = "Open_"+mode
	var circuit = GameStyle.panel(host.screen,Vector2(430,574),Vector2(444,67))
	circuit.name = "CampCircuitHint"
	host._camp_ui_icon(circuit,"state_shock",Vector2(10,6),Vector2(52,52))
	GameStyle.literal(circuit,host._ex_text("职业被动 · 自动生效","HERO PASSIVE · AUTOMATIC"),Vector2(74,9),Vector2(348,24),17,GameStyle.CYAN)
	GameStyle.literal(circuit,host._ex_text("四项技能搭配普攻   ·   在设置中开启自动普攻","Chain four skills with attacks · Auto attack in settings"),Vector2(74,37),Vector2(348,21),12,GameStyle.MUTED)
	circuit.tooltip_text = host._ex_text("每位英雄拥有符合职业定位的独特被动；战斗中自动触发，无需额外操作。","Each hero has a unique role-based passive that triggers automatically in combat.")
	circuit.mouse_filter = Control.MOUSE_FILTER_PASS
	var depart = host._camp_navigation(host.screen,Vector2(900,571),Vector2(336,82),host._ex_text("开始远征","BEGIN EXPEDITION"),host._ex_text("登上升降台 · 探索新的区域","Board the lift and explore"),4,GameStyle.CYAN,host._start_run,true)
	depart.name = "Depart"
	var demo = host._camp_navigation(host.screen,Vector2(430,658),Vector2(302,44),host._ex_text("完整技能试玩","FULL-SKILL TRIAL"),"",5,Color("826647"),host.show_demo_select)
	demo.name = "FullSkillDemo"
	GameStyle.button(host.screen,"MAIN_MENU",Vector2(42,650),Vector2(164,44),host.show_menu)
	var camp_settings = GameStyle.button(host.screen,"SETTINGS",Vector2(218,650),Vector2(168,44),host.show_settings)
	camp_settings.name = "CampSettings"
	camp_settings.text = host._ex_text("设置与操作","SETTINGS")
	camp_settings.size = Vector2(168,44)
	host._show_warning(host.screen,Vector2(752,671),Vector2(478,25))
	depart.grab_focus()

func _camp_navigation(parent: Node, at: Vector2, extent: Vector2, title: String, subtitle: String, icon_index: int, accent: Color, action: Callable, prominent: bool = false) -> Button:
	var tile = host.CampNavTile.new()
	tile.position = at
	tile.size = extent
	tile.custom_minimum_size = Vector2(44,44)
	parent.add_child(tile)
	tile.configure(title,subtitle,icon_index,accent,prominent)
	tile.pressed.connect(action)
	return tile

func _camp_ui_icon(parent: Node, key: String, at: Vector2, extent: Vector2) -> Control:
	var art_id: String = {"workshop":"lantern","gold":"coin","route":"compass","state_shock":"circuit_orb"}.get(key,key)
	var painted: Texture2D = host.CampArtwork.texture(art_id)
	if key in ["workshop","route"] and ResourceLoader.exists(AssetCatalog.resolve("asset://ui/refactor_v1/decor/compass_emblem.png")):
		painted = load(AssetCatalog.resolve("asset://ui/refactor_v1/decor/compass_emblem.png"))
	if painted != null:
		var illustration = TextureRect.new()
		illustration.texture = painted
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.position = at
		illustration.size = extent
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(illustration)
		return illustration
	var icon = Control.new()
	icon.set_script(load(AssetCatalog.resolve("res://scripts/presentation/components/generated_ui_icon.gd")))
	icon.position = at
	icon.size = extent
	parent.add_child(icon)
	icon.configure(key)
	return icon
func _departure_enemy_count(difficulty: int) -> int:
	var total = 0
	var definition: Dictionary = WorldCatalog.biomes().get(host.selected_biome,{})
	var rooms: Array = definition.get("room_ids",[])
	var sample_room = str(rooms[0]) if not rooms.is_empty() else "L01"
	for zone in host.DifficultyProfiles.ZONE_COUNT:
		total += int(host.DifficultyProfiles.encounter_plan(sample_room,zone,difficulty,2 if host.selected_biome in ["B05","B06","B10"] else 1).get("total_count",0))
	return total

func _update_departure_difficulty_hint() -> void:
	var route_hint: Label = host.screen.find_child("DepartureRouteHint", true, false)
	if route_hint != null:
		var hero_level: int = Game.hero_level(str(Game.profile.get("selected_hero", "CH01")))
		route_hint.text = host._ex_text("出发 Lv.%d · 预计 %d 站 / 目标、遗物、补给与首领", "DEPARTURE LV.%d · %d STOPS / OBJECTIVES, RELICS & A BOSS") % [hero_level, host.RoutePlanner.node_count_for_biome(host.selected_biome, hero_level)]
	var hint: Label = host.screen.find_child("DepartureDifficultyHint",true,false)
	if hint == null: return
	var difficulty = clampi(host.selected_difficulty,0,host.DifficultyProfiles.MAX_DIFFICULTY)
	var definition: Dictionary = WorldCatalog.biomes().get(host.selected_biome,{})
	var rooms: Array = definition.get("room_ids",[])
	var sample_room = str(rooms[0]) if not rooms.is_empty() else "L01"
	var level = host.DifficultyProfiles.encounter_level(sample_room,0,difficulty)
	var enhancement: String = ["+0","+0–1","+1","+2","+3"][difficulty]
	if int(Game.profile.get("ruleset_version",1)) == 2:
		var chapter = int(host.selected_biome.trim_prefix("B"))
		var first = (chapter-1)*5+1
		var counts: Array = preload("res://scripts/infrastructure/content/runtime_rules.gd").value("boss_drop_counts")
		hint.text = host._ex_text("固定挑战Lv.%d/%d/%d · 首领Lv.%d · 清房1件 / 首领%d件 · 金≤+1，其余≤+5","Fixed challenge Lv.%d/%d/%d · Boss Lv.%d · Room1 / Boss%d items · Gold≤+1, others≤+5") % [first,first+2,first+4,chapter*5,int(counts[difficulty])]
		if host.selected_biome == "B10":
			hint.text = host._ex_text("终章Lv.46/48/50 · 六房六龙 / 九首古龙Lv.50 · 清房1件 / 终首领%d件", "FINAL Lv.46/48/50 · SIX DRAGON ROOMS / NINE-HEAD HYDRA Lv.50 · Room1 / Final boss%d items") % int(counts[difficulty])
		return
	var normal_drops = 2 if difficulty >= 2 else 1
	var boss_drops = 2+int(difficulty/2)
	var boss_boost = host._ex_text("强化+1，上限+3","+1 boost, cap +3") if difficulty > 0 else host._ex_text("强化+0","+0")
	hint.text = host._ex_text("基础敌群 %d · 敌人Lv.%d · 本族掉落%d件 %s · 首领%d件 %s","BASE: %d foes · Enemy Lv.%d · Faction gear %d / %s · Boss %d / %s") % [host._departure_enemy_count(difficulty),level,normal_drops,enhancement,boss_drops,boss_boost]
	hint.tooltip_text = host._ex_text("基础敌数不含任务限量增援。敌人属性随等级成长。强化档次为现有掉落等级；重复装备按规则折算金币。","Base enemy count excludes limited objective reinforcements. Enemy stats grow with level. Enhancement is the current drop level; duplicate gear converts to gold.")
	hint.mouse_filter = Control.MOUSE_FILTER_PASS

func _build_biome_selector() -> void:
	var available: Array = host.ExpeditionScript.unlocked_biomes(Game.profile)
	if not available.has(host.selected_biome):
		host.selected_biome = "B01"
	var picker = OptionButton.new()
	picker.name = "DepartureBiome"
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.position = Vector2(454,214)
	picker.size = Vector2(495,44)
	picker.add_theme_font_size_override("font_size",17)
	var plans: Array[Dictionary] = WorldCatalog.region_plan()
	for index in plans.size():
		var definition: Dictionary = plans[index]
		var biome_id: String = definition.biome_id
		var implemented: bool = definition.implemented
		var locked = not available.has(biome_id)
		var status = host._ex_text(" · 待开发"," · TODO") if not implemented else (host._ex_text(" · 首领未解锁", " · Locked") if locked else "")
		if definition.get("candidate",false): status += host._ex_text(" · 候选试玩"," · Candidate")
		picker.add_item(GameStyle.content_text(definition,"name",biome_id)+status,index)
		picker.set_item_disabled(index,not implemented or locked)
		picker.set_item_metadata(index,biome_id if implemented else "")
		var race_name = GameStyle.content_text(definition,"race","")
		var availability = host._ex_text("已实现 · 可出发探索","Implemented · ready to explore")
		if not implemented:
			availability = host._ex_text("待开发 · 仅展示计划，尚不能进入","TODO · roadmap only; this region cannot be entered")
		elif locked:
			availability = host._ex_text("未解锁 · 击败前一区域首领并撤离后解锁","Locked · defeat the previous boss and extract to unlock")
			if biome_id == "B10": availability = host._ex_text("未解锁 · 击败第四关首领并撤离后开放终章", "Locked · defeat the fourth-region boss and extract to unlock the final chapter")
		picker.get_popup().set_item_tooltip(index,race_name+"\n"+availability)
	picker.select(int(host.selected_biome.trim_prefix("B"))-1)
	picker.item_selected.connect(func(index: int):
		if index < 0 or index >= picker.item_count or picker.is_item_disabled(index): return
		var biome_id: String = str(picker.get_item_metadata(index))
		if WorldCatalog.biomes().has(biome_id):
			host.selected_biome = biome_id
			host._update_departure_difficulty_hint())
	host.screen.add_child(picker)
	GameStyle.literal(host.screen,host._ex_text("击败首领并撤离后解锁 · 第四关后开放龙庭终章", "Defeat the boss and extract · Final court unlocks after Region 4"),Vector2(454,286),Vector2(490,18),10,GameStyle.MUTED)
	var roadmap = GameStyle.literal(host.screen,host._ex_text("10 个地区 · 前四关与龙庭已接入", "10 REGIONS · FIRST FOUR + FINAL COURT"),Vector2(953,286),Vector2(259,18),10,GameStyle.CYAN)
	if WorldCatalog.b06_enabled(): roadmap.text = host._ex_text("4 个已发布 · B05/B06 隔离候选", "4 RELEASED · B05/B06 ISOLATED CANDIDATES")
	elif WorldCatalog.b05_enabled(): roadmap.text = host._ex_text("4 个已发布 · B05 隔离候选", "4 RELEASED · B05 ISOLATED CANDIDATE")
	roadmap.name = "CampRegionPlanSummary"
	roadmap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	roadmap.tooltip_text = host._ex_text("前四关逐关解锁，通关第四关并撤离后开放第十关星辉龙庭。第五、六关保留隔离候选；第七至九关待开发。", "The first four regions unlock in order. Defeat Region 4 and extract to unlock Region 10, Starlit Dragon Court. Regions 5–6 remain isolated previews; Regions 7–9 are planned.")
