extends RefCounted
## Read-only view data. Every permanent value comes from the production resolver.
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const NAMES := {
	"attack":["攻击力","Attack"], "ability_power":["法术强度","Ability power"],
	"max_hp":["生命上限","Max health"], "armor":["护甲","Armor"], "magic_resist":["魔法抗性","Magic resistance"],
	"crit_chance":["暴击率","Critical chance"], "crit_multiplier":["暴击伤害","Critical damage"],
	"attack_interval":["普攻间隔","Attack interval"], "attack_speed":["攻击速度加成","Attack speed bonus"],
	"attack_speed_bonus":["攻速加成","Attack speed bonus"], "move_speed":["移动速度","Movement speed"],
	"move_speed_bonus":["移速加成","Movement speed bonus"], "range":["普攻距离","Attack range"],
	"resource_max":["职业资源上限","Max resource"], "resource_regen":["资源回复 / 秒","Resource regen / sec"],
	"max_mana":["法力上限（法力职业）","Max mana (mana heroes)"],
	"armor_penetration":["物理穿透","Armor penetration"], "magic_penetration":["法术穿透","Magic penetration"],
	"true_damage_bonus":["附加真实伤害","Flat true damage"], "cooldown_reduction":["冷却缩减","Cooldown reduction"],
	"damage_bonus":["常驻伤害加成","Permanent damage bonus"], "damage_reduction":["通用装备减伤","Equipment reduction"],
	"equipment_damage_reduction":["通用装备减伤","Equipment reduction"],
	"armor_damage_reduction":["护甲物理减伤","Physical armor reduction"], "magic_damage_reduction":["魔抗魔法减伤","Magic resist reduction"],
	"burn_damage":["燃烧伤害加成","Burn damage bonus"], "corrosion_damage_bonus":["腐蚀伤害加成","Corrosion damage bonus"],
	"status_duration":["状态持续加成","Status duration bonus"]}
const GROUPS := [
	["进攻","OFFENSE",["attack","ability_power","crit_chance","crit_multiplier","attack_interval","attack_speed_bonus","range","armor_penetration","magic_penetration","true_damage_bonus","damage_bonus"]],
	["生存","DEFENSE",["max_hp","armor","magic_resist","armor_damage_reduction","magic_damage_reduction","equipment_damage_reduction"]],
	["机动与资源","UTILITY & RESOURCE",["move_speed","move_speed_bonus","resource_max","resource_regen","cooldown_reduction","burn_damage","corrosion_damage_bonus","status_duration"]]]
const RATIOS := ["crit_chance","crit_multiplier","attack_speed","attack_speed_bonus","move_speed_bonus","cooldown_reduction","damage_bonus","damage_reduction","equipment_damage_reduction","armor_damage_reduction","magic_damage_reduction","burn_damage","corrosion_damage_bonus","status_duration"]

static func t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func caption(key: String) -> String:
	var names: Array = NAMES.get(key,[key,key])
	return str(names[1] if Words.locale == "en" else names[0])

static func value(key: String, amount: float, signed: bool = false, item_value: bool = false) -> String:
	if key in RATIOS or (item_value and key == "move_speed"):
		return ("%+.1f" if signed else "%.1f") % (amount*100.0) + (t("百分点"," pp") if signed else "%")
	if key == "attack_interval": return ("%+.3f s" if signed else "%.3f s") % amount
	return ("%+.1f" if signed else "%.1f") % amount

static func item_values(item: Dictionary, level: int, hero_id: String) -> Dictionary:
	if item.is_empty(): return {}
	if item.get("instance_record") is Dictionary:
		var record: Dictionary = item.instance_record.duplicate(true)
		if level != int(record.enhancement_rank):
			record.enhancement_steps = record.enhancement_steps.slice(0,clampi(level,0,record.enhancement_steps.size()))
			record.enhancement_rank = record.enhancement_steps.size()
			record.enhancement_reroll_history = []
			record.enhancement_gold_ledger = []
			record.material_ledger = []
		return Instances.stats(record)
	var id := str(item.id)
	return Resolver.resolve(hero_id,1,{str(item.slot):id},{id:{"level":clampi(level,0,5)}}).get("uncapped_equipment_contribution",{}).duplicate(true)

static func breakdown(hero_id: String, level: int, loadout: Dictionary, owned: Dictionary, actor: Variant = null, version: int = 1, talents: Dictionary = {}) -> Dictionary:
	var intrinsic := Resolver.resolve(hero_id,1,{}, {},version)
	var leveled := Resolver.resolve(hero_id,level,{}, {},version)
	var total := Resolver.resolve(hero_id,level,loadout,owned,version,talents)
	var live := total.duplicate(true)
	if is_instance_valid(actor) and actor.has_method("stat"):
		for group: Array in GROUPS:
			for key: String in group[2]: live[key] = float(actor.call("stat",key,float(total.get(key,0))))
	return {"hero_id":hero_id,"level":level,"intrinsic":intrinsic,"leveled":leveled,"total":total,"live":live,"loadout":loadout.duplicate(true),"owned":owned.duplicate(true)}

static func set_preview(set_id: String, hero_id: String, level: int, loadout: Dictionary, owned: Dictionary) -> Dictionary:
	var fitted := loadout.duplicate(true)
	var records := owned.duplicate(true)
	for id: String in Registry.set_item_ids(set_id):
		fitted[Registry.equipment(id).slot] = id
		if not records.has(id): records[id] = {"level":0}
	return Resolver.resolve(hero_id,level,fitted,records)

static func tooltip(item: Dictionary, level: int, hero_id: String) -> String:
	var lines: PackedStringArray = [MineStyle.content_text(item,"name")+" +"+str(level)]
	if item.get("instance_record") is Dictionary:
		var record: Dictionary = item.instance_record
		lines.append("iLv %d · %s · %s" % [int(record.item_level),str(record.rarity),str(record.instance_id)])
	var stats := item_values(item,level,hero_id)
	for key: String in stats: lines.append(caption(key)+"  "+value(key,float(stats[key]),true,true))
	lines.append(MineStyle.content_text(item,"affix_text"))
	return "\n".join(lines)

static func cap_notes(stats: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var raw: Dictionary = stats.get("uncapped_equipment_contribution",{})
	var applied: Dictionary = stats.get("equipment_contribution",{})
	for key: String in raw:
		if float(raw[key]) > float(applied.get(key,0))+0.00001:
			notes.append(caption(key)+t("：装备合计 ",": raw gear ")+value(key,float(raw[key]),false,true)+t("，上限后采用 ","; capped to ")+value(key,float(applied.get(key,0)),false,true))
	return notes
