extends RefCounted
const Registry = preload("res://scripts/data/content_registry.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Text = preload("res://scripts/ui/strings.gd")

static func _t(zh: String, en: String) -> String:
	return en if Text.locale == "en" else zh

static func label(item_or_record: Dictionary) -> String:
	var item := item_or_record
	if item.has("template_id"): item = Registry.equipment(str(item.template_id), 2)
	var allowed: Array = item.get("allowed_heroes", [])
	if allowed.size() == 3: return _t("适用：所有职业", "For: all classes")
	var names := {"CH01":_t("战士", "Warrior"), "CH02":_t("枪手", "Gunner"), "CH03":_t("法师", "Mage")}
	var labels: PackedStringArray = []
	for hero: String in allowed: labels.append(str(names.get(hero, hero)))
	return _t("仅限：", "Only: ") + " / ".join(labels)

static func reason(record: Dictionary, hero_id: String, level: int) -> String:
	match Instances.equip_error(record, hero_id, level):
		"CLASS_LOCKED": return _t("职业不符 · ", "Wrong class · ") + label(record)
		"POWER_TYPE_LOCKED": return _t("该专属装备属性类型与职业不符", "This exclusive item's stat type does not match the class")
		"ITEM_LEVEL_LOCKED": return _t("等级不足 · 需要 Lv.%d", "Level locked · requires Lv.%d") % int(record.get("item_level", 1))
		"INVALID_INSTANCE": return _t("装备记录无效", "Invalid equipment record")
	return ""

static func affinity(record: Dictionary, hero_id: String) -> String:
	var power := str(record.get("power_type", ""))
	if power.is_empty(): return ""
	var title := _t("法术属性", "Magic stats") if power == "magic" else _t("物理属性", "Physical stats")
	if power != Registry.ClassPolicy.power_type(hero_id):
		title += _t(" · 属性取向不同，请比较实际收益", " · different stat focus; compare actual gains")
	return title
