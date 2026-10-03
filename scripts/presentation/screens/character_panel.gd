extends Control
## Camp and combat share the same complete attribute and equipment inspectors.
const SkillInspect = preload("res://scripts/presentation/screens/skill_inspection.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Sheet = preload("res://scripts/presentation/screens/stat_sheet.gd")
const Details = preload("res://scripts/presentation/equipment/equipment_details.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
var room: Node
var detail_title: Label
var detail_body: Label
var detail_scroll: ScrollContainer

func configure(source_room: Node, close: Callable) -> void:
	room = source_room
	name = "CharacterDossier"
	size = Vector2(1020,620)
	var hero: Dictionary = ContentRegistry.hero(Game.run.hero_id)
	GameStyle.panel(self,Vector2(16,10),Vector2(988,55))
	GameStyle.literal(self,Inspect.t("冒险者档案","Adventurer dossier"),Vector2(35,18),Vector2(730,37),27)
	var back := GameStyle.button(self,"BACK",Vector2(833,18),Vector2(153,40),close)
	back.name = "CloseCharacterDossier"
	var left := GameStyle.panel(self,Vector2(16,80),Vector2(294,524))
	GameStyle.literal(left,GameStyle.content_text(hero,"name"),Vector2(18,14),Vector2(260,33),26)
	GameStyle.literal(left,GameStyle.content_text(hero,"class_name")+" · Lv."+str(Game.run.level),Vector2(18,54),Vector2(260,26),16,GameStyle.CYAN)
	GameStyle.hero_portrait(left,Game.run.hero_id,Vector2(58,93),Vector2(178,203))
	var slots: Array[String] = Game.equipment_slots(true)
	var per_side := 4 if slots.size() == 8 else 3
	for index: int in slots.size():
		var slot: String = slots[index]
		var id := str(Game.run.loadout_snapshot.get(slot,""))
		var item: Dictionary = Game.equipment_definition(id,true)
		var button := GameStyle.button(left,"",Vector2(12 if index < per_side else 236,95+(index%per_side)*51),Vector2(46,46),func(): _show_item(item))
		button.name = "Equipment_"+slot
		GameStyle.button_skin(button,"socket")
		GameStyle.equipment_icon(button,item if not item.is_empty() else {"slot":slot},Vector2(3,3),Vector2(40,40))
		button.tooltip_text = Inspect.tooltip(item,int(Game.run.equipment_snapshot.get(id,{}).get("enhancement_rank",Game.run.equipment_snapshot.get(id,{}).get("level",0))),Game.run.hero_id)
	var Dossier := preload("res://scripts/presentation/screens/hero_dossier.gd")
	Dossier.metric(left,Inspect.t("当前生命","Current HP"),"%d / %d" % [ceili(Game.run.hp),ceili(Game.run.max_hp)],Vector2(16,315),Vector2(262,64))
	Dossier.metric(left,GameStyle.content_text(hero,"resource_name"),"%d / %d" % [ceili(Game.run.resource),ceili(float(Game.run.stats.resource_max))],Vector2(16,389),Vector2(262,60))
	for index: int in 4:
		var key: String = ["q","secondary","f","ultimate"][index]
		var skill: Dictionary = hero.get("skills",{}).get(key,{})
		var action := GameStyle.button(left,"",Vector2(16+index*66,464),Vector2(62,44),func(): _show_skill(key,skill))
		action.name = "DossierSkill_"+key
		GameStyle.button_skin(action,"socket")
		Dossier.skill_icon(action,Game.run.hero_id,key,Vector2(8,4),Vector2(46,36))
		action.tooltip_text = GameStyle.content_text(skill,"name")
	var right := GameStyle.panel(self,Vector2(326,80),Vector2(678,524))
	detail_title = GameStyle.literal(right,Inspect.t("角色属性","Character attributes"),Vector2(20,17),Vector2(470,51),24)
	var restore := GameStyle.button(right,"",Vector2(513,20),Vector2(145,38),_show_sheet)
	restore.name = "DossierAllStats"
	restore.text = Inspect.t("完整属性","All attributes")
	restore.add_theme_font_size_override("font_size",14)
	detail_scroll = ScrollContainer.new()
	detail_scroll.name = "DossierDetailScroll"
	detail_scroll.position = Vector2(20,83)
	detail_scroll.size = Vector2(638,423)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(detail_scroll)
	_show_sheet()
	back.grab_focus()

func _clear_detail() -> void:
	for child: Node in detail_scroll.get_children(): detail_scroll.remove_child(child); child.queue_free()
	detail_scroll.scroll_vertical = 0

func _show_sheet() -> void:
	_clear_detail()
	detail_title.text = Inspect.t("角色属性 · 当前配装","Attributes · current loadout")
	var actor: Variant = room.get("player") if is_instance_valid(room) else null
	var sheet := Sheet.new()
	detail_scroll.add_child(sheet)
	sheet.configure(Inspect.breakdown(Game.run.hero_id,Game.run.level,Game.run.loadout_snapshot,Game.run.equipment_snapshot,actor,Game.run.ruleset_version(),Game.hero_talents(Game.run.hero_id)),620,"Attribute_")

func _show_item(item: Dictionary) -> void:
	_clear_detail()
	detail_title.text = GameStyle.content_text(item,"name",Words.text("EMPTY_SLOT"))
	var content := Details.new()
	detail_scroll.add_child(content)
	content.configure(item,int(Game.run.equipment_snapshot.get(str(item.get("instance_id",item.get("id",""))),{}).get("enhancement_rank",Game.run.equipment_snapshot.get(str(item.get("id","")),{}).get("level",0))),620,Game.run.hero_id,Game.run.stats,Game.run.stats)
	Details.set_changes(content,Game.run.stats,Game.run.stats,620,str(item.get("set_id","")))

func _explain(title: String, explanation: String) -> void:
	_clear_detail()
	detail_title.text = title
	detail_body = GameStyle.literal(detail_scroll,explanation,Vector2.ZERO,Vector2(620,0),17)
	detail_body.custom_minimum_size.x = 620

func _show_skill(slot: String, skill: Dictionary) -> void:
	var actor: Variant = room.get("player") if is_instance_valid(room) else null
	var spec: Dictionary = actor.skill_definition(slot) if is_instance_valid(actor) else HeroAbilities.preview_spec(Game.run.hero_id,Game.run.level,Game.run.stats,slot)
	var summary := Words.text("HUD_FINAL_COST",{"cost":spec.get("cost",0),"resource":GameStyle.content_text(ContentRegistry.hero(Game.run.hero_id),"resource_name"),"cooldown":snappedf(float(spec.get("cooldown",0)),0.1)})
	_explain(GameStyle.content_text(skill,"name"),summary+"\n\n"+SkillInspect.describe(Game.run.hero_id,Game.run.level,Game.run.stats,slot,spec,actor))
