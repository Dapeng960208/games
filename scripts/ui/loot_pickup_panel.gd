extends Control
## A view of committed rewards. Decisions use the existing idempotent ledger.
signal inspect_requested(drop_id: String)
signal pack_requested(drop_id: String)
signal close_requested()
const Traits = preload("res://scripts/ui/equipment_traits.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
var offers: Array = []

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func configure(items: Array) -> void:
	offers = items.duplicate(true)
	MineStyle.literal(self, _t("发现战利品", "LOOT DISCOVERED"), Vector2(28,18), Vector2(700,42), 29, MineStyle.AMBER)
	MineStyle.literal(self, _t("%d 件装备 · 选择一件查看词条，或收进行囊", "%d items · inspect traits or pack your loot") % offers.size(), Vector2(28,67), Vector2(780,30), 17, MineStyle.INK)
	var scroll := ScrollContainer.new()
	scroll.name = "LootPickupScroll"
	scroll.position = Vector2(28,108)
	scroll.size = Vector2(784,334)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for offer: Dictionary in offers: _card(list, offer)
	MineStyle.literal(self, _t("撤离后永久入库 · 途中可以试装 · 拾取不会恢复生命或重置技能", "Extract to secure · fit gear during the run · pickups preserve HP and cooldowns"), Vector2(28,454), Vector2(784,45), 14, MineStyle.MUTED)
	var close := MineStyle.button(self, "", Vector2(540,510), Vector2(272,44), func(): close_requested.emit())
	close.name = "LootPickupLater"
	close.text = _t("稍后整理 · 返回战场", "Later · return to the field")
	close.grab_focus()
	MineStyle.literal(self, _t("战利品标记处按交互键，可再次打开。", "Use Interact at the loot marker to reopen."), Vector2(28,515), Vector2(500,32), 14, MineStyle.CYAN)

func _card(list: VBoxContainer, offer: Dictionary) -> void:
	var item: Dictionary = Game.equipment_definition(str(offer.equipment_id),true)
	if item.is_empty(): return
	var record: Dictionary = item.get("instance_record",{})
	var suffix := str(offer.equipment_id).replace(":","_")
	var card := Panel.new()
	card.name = "LootCard_"+suffix
	card.set_meta("equipment_id",str(offer.equipment_id))
	card.custom_minimum_size = Vector2(760,152)
	card.add_theme_stylebox_override("panel", MineStyle.box(MineStyle.PAPER_LIGHT, Inspect.rarity_color(item) if not record.is_empty() else MineStyle.AMBER.lightened(.28), 2 if not record.is_empty() else 1))
	list.add_child(card)
	MineStyle.equipment_icon(card, item, Vector2(12,21), Vector2(104,104)).name = "LootItemArt"
	var level := int(offer.get("level",0))
	var title := MineStyle.literal(card, MineStyle.content_text(item,"name"), Vector2(128,10), Vector2(398,29), 20, Inspect.rarity_color(item))
	title.name = "LootItemName"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title.text
	var metadata := Words.text("SLOT_"+str(item.slot).to_upper())+" · "+MineStyle.content_text(item,"race_name")+" · "+_t("强化 +", "Refined +")+str(level)
	if not record.is_empty(): metadata = Words.text("SLOT_"+str(item.slot).to_upper())+" · iLv %d · %s · %s · +%d" % [int(record.item_level),Inspect.rarity_name(str(record.rarity)),Inspect.type_name(str(record.power_type)),level]
	MineStyle.literal(card, metadata, Vector2(128,42), Vector2(398,24), 14, MineStyle.AMBER).name = "LootItemMetadata"
	var stats := Inspect.item_values(item, level, Game.run.hero_id)
	var values: Array[String] = []
	for key: String in stats:
		if not record.is_empty() and is_zero_approx(float(stats[key])): continue
		values.append(Inspect.caption(key)+" "+Inspect.value(key,float(stats[key]),true,true,2) if not record.is_empty() else Traits.stat_text(key,float(stats[key])))
	var bonuses := MineStyle.literal(card, " · ".join(values), Vector2(128,71), Vector2(398,35), 14, MineStyle.CYAN)
	bonuses.name = "LootItemStats"
	bonuses.max_lines_visible = 2
	bonuses.tooltip_text = "\n".join(values)
	var affix_text := Traits.affix_kind(item)+" · "+MineStyle.content_text(item,"affix_text")
	if not record.is_empty():
		var affixes: PackedStringArray = []
		for entry: Dictionary in record.affix_type_and_quantile: affixes.append(Inspect.caption(str(entry.type)))
		affix_text = (_t("普通词条：","Random affixes: ")+" / ".join(affixes) if not affixes.is_empty() else _t("无普通随机词条","No random affixes"))+" · "+MineStyle.content_text(item,"affix_text")
	var affix := MineStyle.literal(card, affix_text, Vector2(128,108), Vector2(398,33), 13, MineStyle.MUTED)
	affix.max_lines_visible = 2
	affix.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	affix.tooltip_text = affix_text
	affix.mouse_filter = Control.MOUSE_FILTER_PASS
	var inspect := MineStyle.button(card, "", Vector2(546,28), Vector2(198,44), func(): inspect_requested.emit(str(offer.drop_id)))
	inspect.name = "LootInspect_"+suffix
	inspect.set_meta("drop_id",str(offer.drop_id))
	inspect.text = _t("对比并拾取", "Compare & collect")
	inspect.add_theme_font_size_override("font_size",16)
	MineStyle.primary(inspect)
	if not record.is_empty() and not Instances.can_equip(record,Game.run.hero_id,Game.run.level):
		inspect.disabled = true
		inspect.tooltip_text = _t("当前职业或等级不符合；仍可收进行囊，撤离后入库。","Hero type or level does not fit; you can still pack and extract this item.")
	var pack := MineStyle.button(card, "", Vector2(546,87), Vector2(198,44), func(): pack_requested.emit(str(offer.drop_id)))
	pack.name = "LootPack_"+suffix
	pack.set_meta("drop_id",str(offer.drop_id))
	pack.text = _t("收进行囊", "Pack loot")
	pack.add_theme_font_size_override("font_size",16)
