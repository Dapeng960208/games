extends VBoxContainer
## Presentation of real equipment contributions and conditional affixes.
## Refinement uses StatResolver; triggered bonuses are never added to base stats.
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const RATIOS := ["attack_speed", "move_speed", "crit_chance", "crit_multiplier", "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration"]

static func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func contributions(item: Dictionary, level: int, hero_id: String) -> Dictionary:
	if item.is_empty(): return {}
	var id := str(item.id)
	return Resolver.resolve(hero_id, 1, {str(item.slot):id}, {id:{"level":level}}).get("uncapped_equipment_contribution", {})

static func stat_text(key: String, value: float) -> String:
	var caption := Words.text("STAT_"+key.to_upper())
	if key == "max_mana": caption = _t("最大法力（法力职业）", "Max mana (mana heroes)")
	var amount := "%+.1f%%" % (value*100.0) if key in RATIOS else "%+.1f" % value
	return caption+"  "+amount

static func affix_kind(item: Dictionary) -> String:
	var text := str(item.get("affix_text", ""))
	if "护盾" in text: return _t("护盾触发", "Shield trigger")
	if "回复" in text or "治疗" in text: return _t("恢复触发", "Recovery trigger")
	if "冲刺" in text or "移速" in text: return _t("机动触发", "Mobility trigger")
	for word: String in ["灼烧", "感电", "寒冷", "腐蚀", "流血", "重伤"]:
		if word in text: return _t("状态联动", "Status synergy")
	return _t("战斗触发", "Combat trigger")

func configure(item: Dictionary, level: int, width: float, hero_id: String, affix_first: bool = false) -> void:
	name = "EquipmentTraits"
	custom_minimum_size.x = width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	if affix_first: _affix(item,width)
	_heading(_t("基础加成", "BASE BONUSES"), width, MineStyle.CYAN)
	var stats := contributions(item, level, hero_id)
	for key: String in stats:
		_line(stat_text(key, float(stats[key])), width, MineStyle.INK)
	if not affix_first: _affix(item,width)

func _affix(item: Dictionary, width: float) -> void:
	_heading(affix_kind(item), width, MineStyle.AMBER)
	_line(MineStyle.content_text(item, "affix_text", _t("无专属词条", "No special affix")), width, MineStyle.INK)
	_line(_t("条件满足时触发，收益不计入固定属性。", "Triggered benefits are separate from base stats."), width, MineStyle.MUTED, 12)

func _heading(text: String, width: float, tint: Color) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MineStyle.box(MineStyle.PAPER_LIGHT.lerp(tint,.08), tint.lightened(.2), 1))
	add_child(panel)
	var label := _line("◆  "+text, width-12, tint, 14, panel)
	label.custom_minimum_size.y = 26

func _line(text: String, width: float, tint: Color, font_size: int = 14, parent: Node = self) -> Label:
	var label := MineStyle.literal(parent, text, Vector2.ZERO, Vector2(width,0), font_size, tint)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = text
	return label
