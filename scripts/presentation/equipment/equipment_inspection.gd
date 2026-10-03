extends RefCounted
## Read-only view data. Every permanent value comes from the production resolver.
const Eligibility = preload("res://scripts/presentation/equipment/equipment_eligibility.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const FLAT_KEYS := Resolver.FLAT_KEYS
const NAMES := {
	"hp_ratio":["生命加成","Health bonus"], "resource_gain_bonus":["资源获取加成","Resource gain bonus"],
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
	"damage_bonus":["伤害加成","Damage bonus"], "damage_reduction":["通用装备减伤","Equipment reduction"],
	"equipment_damage_reduction":["通用减伤","General reduction"],
	"armor_damage_reduction":["护甲物理减伤","Physical armor reduction"], "magic_damage_reduction":["魔抗魔法减伤","Magic resist reduction"],
	"burn_damage":["燃烧伤害加成","Burn damage bonus"], "corrosion_damage_bonus":["腐蚀伤害加成","Corrosion damage bonus"],
	"status_duration":["状态持续加成","Status duration bonus"]}
const GROUPS := [
	["进攻","OFFENSE",["attack","ability_power","crit_chance","crit_multiplier","attack_interval","attack_speed_bonus","range","armor_penetration","magic_penetration","true_damage_bonus","damage_bonus"]],
	["生存","DEFENSE",["max_hp","armor","magic_resist","armor_damage_reduction","magic_damage_reduction","equipment_damage_reduction"]],
	["机动与资源","UTILITY & RESOURCE",["move_speed","move_speed_bonus","resource_max","resource_regen","cooldown_reduction","burn_damage","corrosion_damage_bonus","status_duration","hp_ratio","resource_gain_bonus"]]]
const RATIOS := ["hp_ratio","resource_gain_bonus","crit_chance","crit_multiplier","attack_speed","attack_speed_bonus","move_speed_bonus","cooldown_reduction","damage_bonus","damage_reduction","equipment_damage_reduction","armor_damage_reduction","magic_damage_reduction","burn_damage","corrosion_damage_bonus","status_duration"]

static func t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func caption(key: String) -> String:
	var names: Array = NAMES.get(key,[key,key])
	return str(names[1] if Words.locale == "en" else names[0])

static func value(key: String, amount: float, signed: bool = false, item_value: bool = false, version: int = 1) -> String:
	if key in RATIOS or (item_value and key == "move_speed"):
		return ("%+.1f" if signed else "%.1f") % (amount*100.0) + (t("百分点"," pp") if signed else "%")
	if version == 2 and key in FLAT_KEYS: return ("%+d" if signed else "%d") % int(amount)
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
	var talented := Resolver.resolve(hero_id,level,{}, {},version,talents)
	var total := Resolver.resolve(hero_id,level,loadout,owned,version,talents)
	var live := total.duplicate(true)
	var triggers := {}
	if is_instance_valid(actor) and actor.has_method("stat"):
		for group: Array in GROUPS:
			for key: String in group[2]: live[key] = float(actor.call("stat",key,float(total.get(key,0))))
		if version == 2:
			if actor.get("loadout") != null and actor.loadout.effects != null:
				var effects: Variant = actor.loadout.effects
				triggers = {"clock":effects.clock,"cooldowns":effects.cooldowns.duplicate(true),"buffs":effects.buffs.duplicate(true)}
			var modifiers: Dictionary = actor.loadout.modifiers() if actor.get("loadout") != null else {}
			var caps: Dictionary = Numbers.value("caps")
			for pair: Array in [["damage_bonus","damage_bonus","damage_bonus"],["crit_chance","crit_bonus","crit_chance"],["attack_speed_bonus","attack_speed_bonus","attack_speed"],["move_speed_bonus","move_speed_bonus","move_speed"],["resource_gain_bonus","resource_gain_bonus","resource_gain_bonus"]]:
				live[pair[0]] = minf(float(caps[pair[2]]),float(live.get(pair[0],0))+float(modifiers.get(pair[1],0)))
			if actor.has_method("resource_gain_multiplier"):
				live.resource_regen = Numbers.integer(float(live.resource_regen)*float(actor.resource_gain_multiplier()))
			if actor.get("status") != null:
				var status_values: Dictionary = actor.status.damage_modifiers()
				live.equipment_damage_reduction = minf(0.65,float(total.get("equipment_damage_reduction",0))+float(status_values.get("damage_reduction",0))+float(modifiers.get("damage_reduction_bonus",0)))
	return {"triggers":triggers,"talented":talented,"hero_id":hero_id,"level":level,"intrinsic":intrinsic,"leveled":leveled,"total":total,"live":live,"loadout":loadout.duplicate(true),"owned":owned.duplicate(true)}

static func set_preview(set_id: String, hero_id: String, level: int, loadout: Dictionary, owned: Dictionary) -> Dictionary:
	var fitted := loadout.duplicate(true)
	var records := owned.duplicate(true)
	for id: String in Registry.set_item_ids(set_id):
		fitted[Registry.equipment(id).slot] = id
		if not records.has(id): records[id] = {"level":0}
	return Resolver.resolve(hero_id,level,fitted,records)

static func tooltip(item: Dictionary, level: int, hero_id: String) -> String:
	var lines: PackedStringArray = [GameStyle.content_text(item,"name")+" +"+str(level)]
	if item.get("instance_record") is Dictionary:
		var record: Dictionary = item.instance_record
		lines.append(Eligibility.label(item))
		lines.append(Eligibility.affinity(record, hero_id))
		var error := Eligibility.reason(record, hero_id, Game.run.level if Game.run != null else Game.hero_level(hero_id))
		if not error.is_empty(): lines.append(error)
		lines.append("iLv %d · %s · %s" % [int(record.item_level),rarity_name(str(record.rarity)),str(record.instance_id)])
	var stats := item_values(item,level,hero_id)
	for key: String in stats:
		if item.get("instance_record") is Dictionary and is_zero_approx(float(stats[key])): continue
		lines.append(caption(key)+"  "+value(key,float(stats[key]),true,true,2 if item.get("instance_record") is Dictionary else 1))
	lines.append(GameStyle.content_text(item,"affix_text"))
	return "\n".join(lines)

static func rarity_name(rarity: String) -> String:
	var names := {"white":["白色","White"],"green":["绿色","Green"],"purple":["紫色","Purple"],"gold":["金色","Gold"]}
	var pair: Array = names.get(rarity,[rarity,rarity])
	return t(pair[0],pair[1])

static func rarity(item: Dictionary) -> String:
	return str(item.get("instance_record",{}).get("rarity",""))

static func rarity_color(item: Dictionary) -> Color:
	# White gear needs a slate outline against parchment. Text labels accompany
	# the four colors so quality remains readable without relying on hue alone.
	return {"white":Color("626977"),"green":Color("24704b"),"purple":Color("78399b"),"gold":Color("99600b")}.get(rarity(item),GameStyle.INK)

static func rarity_label(item: Dictionary) -> String:
	var quality := rarity(item)
	return rarity_name(quality) if not quality.is_empty() else ""

static func type_name(power_type: String) -> String:
	return t("法术型","Magic") if power_type == "magic" else t("物理型","Physical")

static func waiver_note(record: Dictionary, hero_id: String) -> String:
	var waiver: Dictionary = record.get("legacy_equip_waiver",{})
	if hero_id not in waiver.get("hero_ids",[]): return ""
	var notes: PackedStringArray = []
	if bool(waiver.get("type",false)): notes.append(t("保留旧属性类型兼容，仍遵守专属套职业限制","Original stat-type compatibility retained; class set restrictions still apply"))
	if bool(waiver.get("level",false)) and hero_id in waiver.get("level_hero_ids",waiver.get("hero_ids",[])):
		notes.append(t("原配装等级豁免：达到 Lv.%d 后到期","Original loadout level waiver: expires at Lv.%d") % int(record.item_level))
	return t("旧装备兼容 · ","Legacy compatibility · ")+"; ".join(notes) if not notes.is_empty() else ""

static func cap_notes(stats: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var raw: Dictionary = stats.get("uncapped_equipment_contribution",{}).duplicate(true)
	var applied: Dictionary = stats.get("equipment_contribution",{}).duplicate(true)
	var version := int(stats.get("ruleset_version",1))
	if version == 2:
		# Gear and talents share these final caps; report the loss after both.
		var base: Dictionary = stats.get("hero_base",{})
		var hero: Dictionary = Registry.hero(str(stats.get("hero_id","")))
		raw["crit_chance"] = float(raw.get("crit_chance",0))+(preload("res://scripts/domain/combat/crit_policy.gd").DEFAULT_CHANCE if preload("res://scripts/domain/combat/crit_policy.gd").enabled(stats) else float(hero.get("crit_chance",0.05)))+float(base.get("talent_crit_chance",0))
		applied["crit_chance"] = float(stats.get("crit_chance",0))
		raw["crit_multiplier"] = float(raw.get("crit_multiplier",0))+(preload("res://scripts/domain/combat/crit_policy.gd").DEFAULT_MULTIPLIER if preload("res://scripts/domain/combat/crit_policy.gd").enabled(stats) else float(hero.get("crit_multiplier",1.5)))
		applied["crit_multiplier"] = float(stats.get("crit_multiplier",0))
		raw["attack_speed"] = float(raw.get("attack_speed",0))+float(base.get("talent_attack_speed",0))
		applied["attack_speed"] = float(stats.get("attack_speed_bonus",0))
		raw["cooldown_reduction"] = float(raw.get("cooldown_reduction",0))+float(base.get("talent_cooldown_reduction",0))
		applied["cooldown_reduction"] = float(stats.get("cooldown_reduction",0))
	for key: String in raw:
		var loss := float(raw[key])-float(applied.get(key,0))
		if loss > 0.00001:
			notes.append(caption(key)+t("：原总额 ",": raw total ")+value(key,float(raw[key]),false,true,version)+t("，有效 ","; effective ")+value(key,float(applied.get(key,0)),false,true,version)+t("，封顶损失 ","; cap loss ")+value(key,loss,false,true,version))
	return notes
