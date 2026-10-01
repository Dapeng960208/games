extends Control
## Camp and combat share the same complete attribute and equipment inspectors.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Sheet = preload("res://scripts/ui/stat_sheet.gd")
const Details = preload("res://scripts/ui/equipment_details.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
var room: Node
var detail_title: Label
var detail_body: Label
var detail_scroll: ScrollContainer

func configure(source_room: Node, close: Callable) -> void:
	room = source_room
	name = "CharacterDossier"
	size = Vector2(1020,620)
	var hero: Dictionary = ContentRegistry.hero(Game.run.hero_id)
	MineStyle.panel(self,Vector2(20,9),Vector2(980,53))
	var left := MineStyle.panel(self,Vector2(20,69),Vector2(286,531))
	MineStyle.literal(left,MineStyle.content_text(hero,"name")+" · Lv."+str(Game.run.level),Vector2(16,13),Vector2(254,37),24,MineStyle.AMBER)
	MineStyle.hero_portrait(left,Game.run.hero_id,Vector2(64,66),Vector2(158,187))
	for index: int in Game.equipment_slots(true).size():
		var slot: String = Game.equipment_slots(true)[index]
		var id := str(Game.run.loadout_snapshot.get(slot,""))
		var item: Dictionary = Game.equipment_definition(id,true)
		var button := MineStyle.button(left,"",Vector2(12 if index < (4 if Game.equipment_slots(true).size() == 8 else 3) else 222,81+(index%(4 if Game.equipment_slots(true).size() == 8 else 3))*(46 if Game.equipment_slots(true).size() == 8 else 63)),Vector2(46,44) if Game.equipment_slots(true).size() == 8 else Vector2(52,52),func(): _show_item(item))
		button.name = "Equipment_"+slot
		MineStyle.button_skin(button,"socket")
		MineStyle.equipment_icon(button,item if not item.is_empty() else {"slot":slot},Vector2(3,3),Vector2(40,38) if Game.equipment_slots(true).size() == 8 else Vector2(46,46))
		button.tooltip_text = Inspect.tooltip(item,int(Game.run.equipment_snapshot.get(id,{}).get("enhancement_rank",Game.run.equipment_snapshot.get(id,{}).get("level",0))),Game.run.hero_id)
	MineStyle.literal(left,MineStyle.content_text(hero,"class_name"),Vector2(16,274),Vector2(254,30),18,MineStyle.CYAN)
	MineStyle.literal(left,Inspect.t("生命 %d / %d\n资源 %d / %d","HP %d / %d\nResource %d / %d") % [ceili(Game.run.hp),ceili(Game.run.max_hp),ceili(Game.run.resource),ceili(float(Game.run.stats.resource_max))],Vector2(16,313),Vector2(254,70),17)
	MineStyle.literal(left,Inspect.t("点装备查看强化值与完整词条；条件效果在属性表下方。","Select gear for refined stats and full affixes. Conditional effects follow the attribute table."),Vector2(16,384),Vector2(254,59),14,MineStyle.MUTED)
	for index: int in 4:
		var key: String = ["q","secondary","f","ultimate"][index]
		var skill: Dictionary = hero.get("skills",{}).get(key,{})
		var action := MineStyle.button(left,"",Vector2(17+index*64,461),Vector2(58,48),func(): _explain(MineStyle.content_text(skill,"name"),MineStyle.content_text(skill,"description")))
		action.name = "DossierSkill_"+key
		MineStyle.button_skin(action,"socket")
		var icon := TextureRect.new()
		icon.texture = Sampler.sampled("res://assets/generated/skills/"+Game.run.hero_id+"_"+key+"_v1.png")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(7,5)
		icon.size = Vector2(44,36)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action.add_child(icon)
		action.tooltip_text = MineStyle.content_text(skill,"name")
	var right := MineStyle.panel(self,Vector2(322,69),Vector2(678,531))
	detail_title = MineStyle.literal(right,Inspect.t("角色属性 · 当前配装","CHARACTER STATS · CURRENT LOADOUT"),Vector2(18,12),Vector2(490,60),22,MineStyle.AMBER)
	var restore := MineStyle.button(right,"",Vector2(508,14),Vector2(150,39),_show_sheet)
	restore.name = "DossierAllStats"
	restore.text = Inspect.t("完整属性","All attributes")
	restore.add_theme_font_size_override("font_size",14)
	detail_scroll = ScrollContainer.new()
	detail_scroll.name = "DossierDetailScroll"
	detail_scroll.position = Vector2(18,78)
	detail_scroll.size = Vector2(642,436)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(detail_scroll)
	MineStyle.literal(self,Inspect.t("拾荒者 · 战斗档案","SALVAGER · COMBAT DOSSIER"),Vector2(24,17),Vector2(720,41),27,MineStyle.AMBER)
	var back := MineStyle.button(self,"BACK",Vector2(814,17),Vector2(184,40),close)
	back.name = "CloseCharacterDossier"
	_show_sheet()
	back.grab_focus()

func _clear_detail() -> void:
	for child: Node in detail_scroll.get_children(): detail_scroll.remove_child(child); child.queue_free()
	detail_scroll.scroll_vertical = 0

func _show_sheet() -> void:
	_clear_detail()
	detail_title.text = Inspect.t("角色属性 · 当前配装","CHARACTER STATS · CURRENT LOADOUT")
	var actor: Variant = room.get("player") if is_instance_valid(room) else null
	var sheet := Sheet.new()
	detail_scroll.add_child(sheet)
	sheet.configure(Inspect.breakdown(Game.run.hero_id,Game.run.level,Game.run.loadout_snapshot,Game.run.equipment_snapshot,actor,Game.run.ruleset_version(),Game.hero_talents(Game.run.hero_id)),620,"Attribute_")

func _show_item(item: Dictionary) -> void:
	_clear_detail()
	detail_title.text = MineStyle.content_text(item,"name",Words.text("EMPTY_SLOT"))
	var content := Details.new()
	detail_scroll.add_child(content)
	content.configure(item,int(Game.run.equipment_snapshot.get(str(item.get("instance_id",item.get("id",""))),{}).get("enhancement_rank",Game.run.equipment_snapshot.get(str(item.get("id","")),{}).get("level",0))),620,Game.run.hero_id,Game.run.stats,Game.run.stats)
	Details.set_changes(content,Game.run.stats,Game.run.stats,620,str(item.get("set_id","")))

func _explain(title: String, explanation: String) -> void:
	_clear_detail()
	detail_title.text = title
	detail_body = MineStyle.literal(detail_scroll,explanation,Vector2.ZERO,Vector2(620,0),17)
	detail_body.custom_minimum_size.x = 620
