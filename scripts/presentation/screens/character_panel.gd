extends Control
## Expedition dossier shares the complete new pages and is always read only.
const Dossier = preload("res://scripts/presentation/screens/hero_dossier.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Details = preload("res://scripts/presentation/equipment/equipment_details.gd")
const RoleSkin = preload("res://scripts/presentation/components/role_skin.gd")
var room: Node
var body: Control
var preview_hero := ""
var action_button: Button
var detail_body: Label
var _close: Callable

func configure(source_room: Node, close: Callable) -> void:
	room = source_room
	_close = close
	name = "CharacterDossier"
	size = Vector2(1248,640)
	preview_hero = str(Game.run.hero_id) if Game.run != null else str(Game.profile.get("selected_hero","CH01"))
	set_meta("dossier_page","heroes")
	_render()

func _render() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var colors := RoleSkin.palette(preview_hero)
	var header := RoleSkin.panel(self,preview_hero,Vector2.ZERO,Vector2(1248,104))
	GameStyle.literal(header,Inspect.t("冒险者档案","ADVENTURER DOSSIER"),Vector2(18,12),Vector2(740,37),27,colors.deep)
	var close := Dossier._button(header,"CloseCharacterDossier",Inspect.t("返回战斗","Back"),Vector2(1077,13),Vector2(152,43),_close,preview_hero)
	for index: int in 2:
		var value: String = ["heroes","skills"][index]
		Dossier._button(header,"DossierPage_"+value,[Inspect.t("角色","Character"),Inspect.t("技能","Skills")][index],Vector2(16+index*116,59),Vector2(108,40),func(): _switch_page(value),preview_hero,str(get_meta("dossier_page","heroes")) == value)
	if Game.run != null:
		var slots := Game.equipment_slots(true)
		for index: int in slots.size():
			var slot := str(slots[index])
			var item := Game.equipment_definition(str(Game.run.loadout_snapshot.get(slot,"")),true)
			var button := Dossier._button(header,"Equipment_"+slot,"",Vector2(280+index*53,59),Vector2(46,40),func(): _show_item(item),preview_hero)
			GameStyle.equipment_icon(button,item if not item.is_empty() else {"slot":slot},Vector2(4,1),Vector2(38,38))
			button.tooltip_text = Inspect.tooltip(item,int(Game.run.equipment_snapshot.get(str(item.get("instance_id",item.get("id",""))),{}).get("enhancement_rank",0)),Game.run.hero_id)
	Dossier._button(header,"DossierAllStats",Inspect.t("完整属性与来源","All attributes and sources"),Vector2(745,59),Vector2(304,40),_show_sheet,preview_hero)
	body = Control.new()
	body.name = "DossierBody"
	body.position = Vector2(16,110)
	body.size = Vector2(1216,510)
	add_child(body)
	if str(get_meta("dossier_page","heroes")) == "skills": Dossier.render_skills(self)
	else: Dossier.render(self)
	GameStyle.literal(self,Inspect.t("出征配置已锁定 · 技能与分支仅可在营地修改","Expedition configuration locked · Skills and branches can only be changed in camp"),Vector2(18,618),Vector2(1212,22),18,colors.muted).name = "ExpeditionDossierLock"
	close.grab_focus()

func _switch_page(value: String) -> void:
	set_meta("dossier_page",value)
	set_meta("dossier_focus","DossierPage_"+value)
	_render()

func _show_sheet() -> void:
	set_meta("dossier_page","heroes")
	set_meta("dossier_sources_open",true)
	set_meta("dossier_focus","HeroStatScroll")
	_render()
	var source: Control = find_child("CharacterStatSheet",true,false) as Control
	var scroll := find_child("HeroStatScroll",true,false) as ScrollContainer
	if source != null and scroll != null: scroll.ensure_control_visible.call_deferred(source)

func _select_hero() -> void:
	# The shared page keeps this button disabled during every expedition phase.
	pass

func _show_item(item: Dictionary) -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var colors := RoleSkin.palette(preview_hero)
	var page := RoleSkin.panel(body,preview_hero,Vector2.ZERO,body.size)
	GameStyle.literal(page,GameStyle.content_text(item,"name",Words.text("EMPTY_SLOT")),Vector2(20,15),Vector2(950,39),27,colors.deep)
	Dossier._button(page,"BackToDossier",Inspect.t("返回档案","Back to dossier"),Vector2(1020,15),Vector2(174,44),_render,preview_hero)
	var scroll := Dossier._scroll(page,"DossierEquipmentScroll",Vector2(20,73),Vector2(1176,417))
	var content := Details.new()
	scroll.add_child(content)
	var record: Dictionary = Game.run.equipment_snapshot.get(str(item.get("instance_id",item.get("id",""))),{})
	content.configure(item,int(record.get("enhancement_rank",record.get("level",0))),1150,Game.run.hero_id,Game.run.stats,Game.run.stats)
	Details.set_changes(content,Game.run.stats,Game.run.stats,1150,str(item.get("set_id","")))
