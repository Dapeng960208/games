class_name B10FinaleArtwork
extends Control
## Chapter illustration and read-only journal. Completion and rewards belong to
## committed profile/settlement records, never to the presentation layer.
const BLUE := Color("315a97")
const DEEP := Color("233c68")
const GOLD := Color("b99451")
const CLOUD := Color("f5f9ff")
const RING_ID := "B10-EASTER-RING"
var texture: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture = preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled("asset://level.b10.ui.chapter_banner")
	resized.connect(queue_redraw)

func _draw() -> void:
	if texture == null or size.x <= 0.0 or size.y <= 0.0: return
	var native := texture.get_size()
	var pixel_ratio := maxf(1.0,get_viewport().get_stretch_transform().get_scale().x)
	var factor := minf(1.0 / pixel_ratio,minf(size.x / native.x,size.y / native.y))
	var extent := native * factor
	draw_texture_rect(texture,Rect2((size-extent)*0.5,extent),false)

static func banner(parent: Node, at: Vector2, extent: Vector2) -> B10FinaleArtwork:
	var art := B10FinaleArtwork.new()
	art.name = "FinaleChapterIllustration"
	art.position = at
	art.size = extent
	parent.add_child(art)
	return art

static func completed() -> bool:
	return "BO10" in Game.profile.get("bosses",[])

static func ring_status() -> String:
	return _t("星冠万象戒 · 已领取","FINAL STAR RING · CLAIMED") if Game.finale_ring_claimed() else _t("星冠万象戒 · 尚未领取","FINAL STAR RING · UNCLAIMED")

static func ring_condition() -> String:
	return _t("每份存档仅一枚；领取记录永久保留。","One per save; the claim remains permanent.") if Game.finale_ring_claimed() else _t("最高难度 D4 击败星冠古龙并存活撤离。","Defeat the Starcrown Ancient Dragon on D4 and extract alive.")

static func panel_style(panel: Panel) -> void:
	panel.add_theme_stylebox_override("panel",GameStyle.box(CLOUD,GOLD,2))

static func show_preview(host: Node) -> void:
	var panel: Panel = host._push_modal("",Vector2(1096,654))
	panel.name = "FinaleChapterPreview"
	panel_style(panel)
	GameStyle.literal(panel,_t("10  星辉龙庭","10  STARLIT DRAGON COURT"),Vector2(28,16),Vector2(800,46),32,DEEP)
	var status := GameStyle.literal(panel,_t("终章已完成","CHAPTER COMPLETE") if completed() else _t("最终章节","FINAL CHAPTER"),Vector2(820,23),Vector2(248,29),16,BLUE)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	banner(panel,Vector2(28,72),Vector2(1040,304))
	GameStyle.literal(panel,_t("白金圣庭悬于云海，蓝星晶照亮归途。","A white-gold sanctuary above the clouds. Sapphire stars light the way home."),Vector2(28,386),Vector2(1040,32),21,DEEP)
	var facts := [[_t("六房 · 六位守关龙","SIX ROOMS · SIX DRAGONS"),_t("18 种龙裔 · 固定星门与步道","18 dragonkin species · fixed gates and paths")],[_t("星冠古龙 · Lv.50","ANCIENT DRAGON · Lv.50"),_t("三阶段星核 · 所有职业可击破","Three core phases · every hero can break them")],[_t("独一无二的纪念戒","A UNIQUE COMMEMORATIVE RING"),_t("全属性加成 · 每份存档一枚","All-stat bonuses · one ring per save")]]
	for index: int in facts.size():
		var card := GameStyle.panel(panel,Vector2(28+index*352,436),Vector2(336,76))
		panel_style(card)
		GameStyle.literal(card,facts[index][0],Vector2(14,9),Vector2(308,27),17,BLUE)
		GameStyle.literal(card,facts[index][1],Vector2(14,42),Vector2(308,26),12,DEEP)
	var available: bool = "B10" in host.ExpeditionScript.unlocked_biomes(Game.profile)
	var note := ring_status()+"  ·  "+ring_condition()
	if not available: note += "\n"+_t("击败第九章霜晶女王并撤离后，正式入口开放。","Defeat the Frostcrystal Queen in Chapter 9 and extract to unlock the entrance.")
	var requirement := GameStyle.literal(panel,note,Vector2(28,526),Vector2(1040,53),15,BLUE)
	requirement.name = "FinaleUnlockAndRewardStatus"
	requirement.mouse_filter = Control.MOUSE_FILTER_PASS
	requirement.tooltip_text = ring_status()+"\n"+ring_condition()
	GameStyle.button(panel,"BACK",Vector2(28,590),Vector2(242,44),host._pop_modal).grab_focus()
	var choose := GameStyle.button(panel,"",Vector2(740,590),Vector2(328,44),func():
		host.selected_biome = "B10"
		host.show_camp())
	choose.name = "ChooseFinaleChapter"
	choose.text = _t("选定第 10 章","SELECT CHAPTER 10") if available else _t("终章入口尚未解锁","FINAL ENTRANCE LOCKED")
	choose.disabled = not available
	GameStyle.primary(choose,BLUE)

static func completed_result(result: Dictionary) -> bool:
	return not bool(result.get("demo",false)) and str(result.get("outcome","")) == "extracted" and completed() and (bool(result.get("final_chapter_completed",false)) or "BO10" in result.get("boss_defeats",[]))

static func show_result(host: Node, result: Dictionary) -> void:
	var backdrop := GameStyle.panel(host.screen,Vector2(40,28),Vector2(1200,632))
	backdrop.name = "FinaleCompletionPanel"
	panel_style(backdrop)
	banner(backdrop,Vector2(20,12),Vector2(1160,284))
	GameStyle.literal(backdrop,_t("10 / 星辉龙庭 · 最终章","10 / STARLIT DRAGON COURT · FINAL CHAPTER"),Vector2(28,304),Vector2(816,27),16,BLUE)
	GameStyle.literal(backdrop,_t("终章完成 · 星冠归庭","JOURNEY COMPLETE"),Vector2(28,337),Vector2(816,62),38,DEEP).name = "FinaleCompletionHeading"
	GameStyle.literal(backdrop,_t("星冠古龙伏于圣庭，星门的光重新连起云海浮岛。\n你的冒险已写入龙庭星册。","The Starcrown Ancient Dragon rests in the sanctuary. Starlight reunites the floating courts.\nYour adventure is now written in the Dragon Court's star ledger."),Vector2(28,408),Vector2(800,66),18,DEEP)
	var receipt := GameStyle.literal(backdrop,_t("带回金币 %d · 战斗击杀 %d · 成长经验 +%d","GOLD KEPT %d · FOES DEFEATED %d · XP +%d") % [int(result.get("retained",0)),int(result.get("kills",0)),int(result.get("hero_xp_gained",0))],Vector2(28,498),Vector2(816,38),17,BLUE)
	receipt.name = "FinaleSettlementReceipt"
	var reward := GameStyle.panel(backdrop,Vector2(864,308),Vector2(308,228))
	panel_style(reward)
	GameStyle.equipment_icon(reward,{"id":RING_ID,"slot":"ring","rarity":"gold"},Vector2(102,12),Vector2(104,104))
	var newly_claimed := false
	var pending_ring := false
	for id: String in result.get("equipment_retained",[]):
		var item: Dictionary = Game.profile.get("equipment",{}).get(id,{})
		if item.get("template_id") == RING_ID and item.get("source_event_id") == str(result.get("run_id",""))+":finale_ring":
			newly_claimed = true
			pending_ring = item.get("location") == "pending"
	var reward_title := _t("首次领取 · 星冠万象戒","FIRST CLAIM · FINAL STAR RING") if newly_claimed else ring_status()
	GameStyle.literal(reward,reward_title,Vector2(16,126),Vector2(276,39),17,BLUE).name = "FinaleRingClaimStatus"
	var note := _t("全属性加成 · 已加入装备库存","All-stat bonuses · added to equipment") if newly_claimed else ring_condition()
	if newly_claimed and pending_ring: note = _t("库存已满 · 戒指已领取，等待入库","Inventory full · claimed ring awaits storage")
	GameStyle.literal(reward,note,Vector2(16,174),Vector2(276,42),13,DEEP)
	reward.mouse_filter = Control.MOUSE_FILTER_PASS
	var stat_lines: PackedStringArray = []
	var inspect: Script = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
	for key: String in preload("res://scripts/levels/b10/equipment/equipment_catalog.gd").FINALE_STATS:
		var amount: float = preload("res://scripts/levels/b10/equipment/equipment_catalog.gd").FINALE_STATS[key]
		stat_lines.append(inspect.caption(key)+"  "+inspect.value(key,amount,true,true,2))
	reward.tooltip_text = "\n".join(stat_lines)+"\n"+ring_condition()
	var return_button := GameStyle.button(backdrop,"RETURN_CAMP",Vector2(28,562),Vector2(336,48),host.show_camp)
	GameStyle.primary(return_button,BLUE)
	return_button.grab_focus()
	var inventory := GameStyle.button(backdrop,"",Vector2(382,562),Vector2(336,48),func(): host.show_workshop("inventory"))
	inventory.text = _t("查看带回装备","VIEW EXTRACTED EQUIPMENT")
	GameStyle.literal(host.screen,_t("冒险已经完成。你仍可重返已解锁地区，挑战不同难度。","Your adventure is complete. Return to unlocked regions for another challenge."),Vector2(68,676),Vector2(1144,28),15,DEEP)

static func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh
