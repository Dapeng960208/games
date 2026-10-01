extends Control
## A parchment combat journal: live stats, equipped items and explanations.

const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const INK := MineStyle.INK
const MUTED := MineStyle.MUTED
const GOLD := MineStyle.AMBER
const CYAN := MineStyle.CYAN
const SLOTS := ["weapon","head","chest","hands","feet","charm"]
var room: Node
var detail_title: Label
var detail_body: Label
var mineral: Texture2D
var base_stats: Dictionary = {}

class StatGlyph extends Control:
	var symbol := "attack"
	var tint := MineStyle.AMBER
	func _draw() -> void:
		var c := Vector2(15,15)
		if symbol in ["armor","magic_resist","equipment_damage_reduction"]:
			draw_polyline(PackedVector2Array([Vector2(5,5),Vector2(25,5),Vector2(23,19),Vector2(15,27),Vector2(7,19),Vector2(5,5)]),tint,1.8,true)
			if symbol == "magic_resist":
				draw_polyline(PackedVector2Array([Vector2(15,9),Vector2(20,15),Vector2(15,21),Vector2(10,15),Vector2(15,9)]),tint,1.5,true)
			else: draw_line(Vector2(15,8),Vector2(15,23),tint,1.7,true)
		elif symbol in ["ability_power","resource_max"]:
			draw_polyline(PackedVector2Array([Vector2(15,2),Vector2(23,15),Vector2(15,28),Vector2(7,15),Vector2(15,2)]),tint,1.8,true)
			draw_line(Vector2(15,4),Vector2(15,25),Color(tint,.6),1,true)
		elif symbol in ["crit_chance","crit_multiplier"]:
			draw_arc(c,8,0,TAU,24,tint,1.7,true)
			for axis in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]: draw_line(c+axis*10,c+axis*14,tint,1.7,true)
			if symbol == "crit_multiplier": draw_circle(c,3,tint)
		elif symbol == "max_hp":
			draw_polyline(PackedVector2Array([Vector2(7,7),Vector2(13,7),Vector2(13,3),Vector2(19,3),Vector2(19,7),Vector2(25,7),Vector2(25,13),Vector2(19,13),Vector2(19,24),Vector2(13,24),Vector2(13,13),Vector2(7,13),Vector2(7,7)]),tint,1.6,true)
		else:
			draw_polyline(PackedVector2Array([Vector2(7,25),Vector2(23,5),Vector2(24,12)]),tint,2.4,true)
			draw_line(Vector2(16,7),Vector2(23,5),tint,2.0,true)
			draw_line(Vector2(6,18),Vector2(14,25),tint,2.0,true)
			if symbol in ["armor_penetration","magic_penetration"]: draw_line(Vector2(4,12),Vector2(27,17),Color(tint,.7),1.5,true)

func configure(source_room: Node, close: Callable) -> void:
	room = source_room
	name = "CharacterDossier"
	size = Vector2(1020,620)
	mineral = Sampler.sampled("res://assets/generated/ui/storybook_parchment_v1.png")
	base_stats = StatResolver.resolve(Game.run.hero_id,Game.run.level,{}, {})
	_build(close)
	queue_redraw()

func _draw() -> void:
	for index in range(54):
		var tone := MineStyle.PAPER_LIGHT.lerp(MineStyle.PANEL,float(index)/53.0)
		draw_rect(Rect2(28,65+index*9,964,10),tone)
	if mineral != null: draw_texture_rect(mineral,Rect2(28,65,964,487),false,Color(1,1,1,0.12))
	draw_circle(Vector2(191,270),128,Color(CYAN,.045))
	draw_arc(Vector2(191,270),130,-2.85,0.05,64,Color(CYAN,.22),2,true)
	draw_arc(Vector2(191,270),142,0.25,2.9,64,Color(GOLD,.22),1,true)
	draw_line(Vector2(359,112),Vector2(359,550),Color(GOLD,.4),1,true)
	for y in [135,253,371]:
		draw_line(Vector2(386,y),Vector2(958,y),Color(CYAN,.22),1,true)
	for y in [183,224,301,342,419,460]:
		draw_line(Vector2(390,y),Vector2(956,y),Color(CYAN,.09),1,true)
	draw_line(Vector2(386,465),Vector2(958,465),Color(GOLD,.48),1,true)

func _text(value: String, at: Vector2, extent: Vector2, font_size: int, color: Color = INK) -> Label:
	return MineStyle.literal(self,value,at,extent,font_size,color)

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _build(close: Callable) -> void:
	var hero: Dictionary = ContentRegistry.hero(Game.run.hero_id)
	var stats: Dictionary = Game.run.stats
	var frame := MineStyle.panel(self,Vector2(28,28),Vector2(964,532))
	frame.name = "ParchmentCharacterFrame"
	frame.add_theme_stylebox_override("panel",MineStyle.box(Color(0,0,0,0),MineStyle.COPPER,1))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 10
	var heading := _text(_t("拾荒者 · 战斗档案","SALVAGER · COMBAT DOSSIER"),Vector2(330,41),Vector2(360,35),22,GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.z_index = 11
	_text(MineStyle.content_text(hero,"name")+"  /  Lv."+str(Game.run.level),Vector2(70,103),Vector2(248,34),24,GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MineStyle.hero_portrait(self,Game.run.hero_id,Vector2(99,145),Vector2(186,211))
	for index in SLOTS.size():
		var slot: String = SLOTS[index]
		var id: String = str(Game.run.loadout_snapshot.get(slot,""))
		var item: Dictionary = ContentRegistry.equipment(id)
		var at := Vector2(46 if index < 3 else 286,152+(index%3)*70)
		var cell := _hitbox("Equipment_"+slot,at,Vector2(52,52))
		MineStyle.button_skin(cell,"socket")
		MineStyle.equipment_icon(cell,item if not item.is_empty() else {"slot":slot},Vector2(4,4),Vector2(44,44))
		var item_name := MineStyle.content_text(item,"name",Words.text("EMPTY_SLOT"))
		var summary := _equipment_summary(item)
		cell.mouse_entered.connect(func(): _explain(item_name,summary))
		cell.focus_entered.connect(func(): _explain(item_name,summary))
		cell.pressed.connect(func(): _explain(item_name,summary))
	var identity: String = MineStyle.content_text(hero,"class_name")
	_text(identity,Vector2(70,361),Vector2(248,28),18,CYAN).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actor_meter(_t("生命","HEALTH"),Game.run.hp,Game.run.max_hp,Vector2(58,397),MineStyle.RED)
	_actor_meter(MineStyle.content_text(hero,"resource_name"),Game.run.resource,float(stats.get("resource_max",100)),Vector2(58,439),MineStyle.resource_color(str(hero.get("resource_type","rage"))))
	for index in range(4):
		var slot: String = ["q","secondary","f","ultimate"][index]
		var skill: Dictionary = hero.get("skills",{}).get(slot,{})
		var cell := _hitbox("DossierSkill_"+slot,Vector2(70+index*58,478),Vector2(48,36))
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = Sampler.sampled("res://assets/generated/skills/"+Game.run.hero_id+"_"+slot+"_v1.png")
		icon.size = Vector2(40,32)
		icon.position = Vector2(4,0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var title := MineStyle.content_text(skill,"name")
		var description := MineStyle.content_text(skill,"description")
		cell.mouse_entered.connect(func(): _explain(title,description))
		cell.focus_entered.connect(func(): _explain(title,description))
		var action: String = ["skill_q","skill_secondary","skill_f","skill_ultimate"][index]
		var key: String = ControlBindings.label_for(action,Game.profile.get("settings",{}).get("controls",{}),Words.locale)
		_text(key,Vector2(66+index*58,514),Vector2(57,21),11,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(_t("攻击","OFFENSE"),Vector2(387,109),Vector2(570,27),18,GOLD)
	_text(_t("生存","DEFENSE"),Vector2(387,227),Vector2(570,27),18,GOLD)
	_text(_t("精通 / 资源","MASTERY / RESOURCE"),Vector2(387,345),Vector2(570,27),18,GOLD)
	var definitions: Array = [
		["attack","攻击力","Attack",false,GOLD,"原始物理攻击的基础数值。"],
		["ability_power","法术强度","Ability power",false,Color("8860b7"),"术士法术与法术遗物的基础数值。"],
		["crit_chance","暴击率","Critical chance",true,GOLD,"原始直接攻击触发暴击的几率。"],
		["crit_multiplier","暴击伤害","Critical damage",true,GOLD,"暴击伤害相对普通命中的总倍率。"],
		["armor","护甲","Armor",false,Color("6d805b"),"降低受到的物理伤害。"],
		["magic_resist","魔法抗性","Magic resistance",false,Color("526aa1"),"降低受到的魔法伤害。"],
		["max_hp","最大生命","Max health",false,MineStyle.RED,"角色可拥有的生命上限。"],
		["equipment_damage_reduction","伤害减免","Reduction",true,CYAN,"装备提供的额外减伤，不包含护甲与魔抗。"],
		["armor_penetration","物理穿透","Armor pierce",false,GOLD,"物理攻击忽略的护甲点数。"],
		["magic_penetration","法术穿透","Magic pierce",false,Color("8860b7"),"魔法攻击忽略的魔抗点数。"],
		["true_damage_bonus","真伤附加","True damage",false,Color("a47d32"),"每次原始直接命中附加固定真实伤害。"],
		["resource_max",MineStyle.content_text(hero,"resource_name")+"上限","Max resource",false,CYAN,"当前职业资源上限；只有法力职业受最大法力装备加成。"]]
	for index in definitions.size():
		var group_index: int = index/4
		var row_index: int = (index%4)/2
		_stat_row(definitions[index],Vector2(386+(index%2)*292,143+group_index*118+row_index*41))
	detail_title = _text(_t("装备与属性","EQUIPMENT & ATTRIBUTES"),Vector2(386,469),Vector2(570,25),18,CYAN)
	detail_body = _text(_t("悬停或聚焦属性、装备与技能，查看来源和实战效果。","Hover or focus a stat, item or skill to inspect its source and effect."),Vector2(386,496),Vector2(570,40),14,MUTED)
	detail_body.max_lines_visible = 2
	detail_body.clip_text = true
	var back := _hitbox("CloseCharacterDossier",Vector2(923,88),Vector2(42,35))
	back.text = "×"
	MineStyle.button_skin(back,"socket")
	back.add_theme_font_size_override("font_size",28)
	back.add_theme_color_override("font_color",GOLD)
	back.pressed.connect(close)
	back.grab_focus()

func _hitbox(id: String, at: Vector2, extent: Vector2) -> Button:
	var button := Button.new()
	button.name = id
	button.position = at
	button.size = extent
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover",MineStyle.box(Color(CYAN,.10),Color.TRANSPARENT,0))
	button.add_theme_stylebox_override("focus",MineStyle.box(Color(CYAN,.06),CYAN,1))
	add_child(button)
	return button

func _actor_meter(title: String, value: float, maximum: float, at: Vector2, tint: Color) -> void:
	_text(title+"  "+str(ceili(value))+" / "+str(ceili(maximum)),at,Vector2(272,25),15,INK)
	var bar := MineStyle.meter(self,at+Vector2(0,28),Vector2(272,6),tint)
	bar.max_value = maximum
	bar.value = value

func _stat_row(definition: Array, at: Vector2) -> void:
	var key: String = definition[0]
	var title := _t(str(definition[1]),str(definition[2]))
	var value := float(Game.run.stats.get(key,0.0))
	var percent: bool = definition[3]
	var row := _hitbox("AttributeRow_"+key,at,Vector2(280,36))
	var glyph := StatGlyph.new()
	glyph.position = Vector2(1,2)
	glyph.size = Vector2(30,30)
	glyph.symbol = key
	glyph.tint = definition[4]
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)
	MineStyle.literal(row,title,Vector2(41,4),Vector2(150,28),16,MUTED)
	var number := MineStyle.literal(row,_value(value,percent),Vector2(182,2),Vector2(88,30),23,INK)
	number.name = "Attribute_"+key
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var basis := float(base_stats.get(key,0.0))
	var explanation := _t("基础（含等级） ","Base (with level) ")+_value(basis,percent)+_t("  +  装备/常驻 ","  +  Equipment ")+_value(value-basis,percent)+"\n"+str(definition[5])
	row.mouse_entered.connect(func(): _explain(title+"  "+_value(value,percent),explanation))
	row.focus_entered.connect(func(): _explain(title+"  "+_value(value,percent),explanation))
	row.pressed.connect(func(): _explain(title+"  "+_value(value,percent),explanation))

func _value(number: float, percent: bool) -> String:
	return "%.1f%%" % (number*100.0) if percent else "%.1f" % number

func _equipment_summary(item: Dictionary) -> String:
	var contributions: Array[String] = []
	for key: String in item.get("base_stats",{}):
		var value: float = item.base_stats[key]
		contributions.append(Words.text("STAT_"+key.to_upper())+" +"+_value(value,key in ["crit_chance","crit_multiplier","attack_speed","damage_reduction","cooldown_reduction"]))
	return " · ".join(contributions)+"\n"+MineStyle.content_text(item,"affix_text")

func _explain(title: String, description: String) -> void:
	if detail_title == null: return
	detail_title.text = title
	detail_body.text = description
