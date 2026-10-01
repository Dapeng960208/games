extends RefCounted
## UI data uses the same settled H, packet and live cost providers as combat.
const Numbers = preload("res://config/numerical_rules.gd")
const Abilities = preload("res://scripts/combat/hero_abilities.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
static var _authored_cache: Dictionary = {}

static func authored_text(text: String, version: int) -> String:
	if version != Numbers.V2: return text
	if _authored_cache.has(text): return str(_authored_cache[text])
	var original := text
	# Authored explanations retain time, range, stacks and coefficients. Only
	# explicit old-unit resource/health quantities are converted for V2 readers.
	var pattern := RegEx.new()
	pattern.compile("([0-9]+(?:\\.[0-9]+)?)(\\s*(?:怒气|能量|法力|生命|[Rr]age|[Ee]nergy|[Mm]ana|health))")
	var matches := pattern.search_all(text)
	matches.reverse()
	for found: RegExMatch in matches:
		text = text.substr(0,found.get_start())+str(Numbers.scale(float(found.get_string(1)),version))+found.get_string(2)+text.substr(found.get_end())
	text = text.replace("怒气消耗 20 → 15","怒气消耗 200 → 150").replace("能量消耗 25 → 20","能量消耗 250 → 200")
	text = text.replace("节点生命 35 → 50","节点生命 350 → 500").replace("node health increases from 35 to 50","node health increases from 350 to 500")
	text = text.replace("Rage cost decreases from 20 to 15","Rage cost decreases from 200 to 150").replace("Energy cost decreases from 25 to 20","Energy cost decreases from 250 to 200")
	if _authored_cache.size() >= 128: _authored_cache.clear()
	_authored_cache[original] = text
	return text

static func passive_text(hero: Dictionary, stats: Dictionary, actor: Variant = null) -> String:
	var version := int(stats.get("ruleset_version",1))
	var text := authored_text(MineStyle.content_text(hero.get("passive",{}),"description"),version)
	if version == 2 and str(hero.get("id","")) == "CH03":
		var gain := float(hero.get("passive",{}).get("resource_gain",8))
		var multiplier: float = actor.resource_gain_multiplier() if is_instance_valid(actor) and actor.has_method("resource_gain_multiplier") else 1.0+float(stats.get("resource_gain_bonus",0))
		var amount := Numbers.integer(float(Numbers.scale(gain,version))*multiplier)
		text += "\n"+Inspect.t("当前触发回复 %d 法力（未满资源时；受剩余容量限制）。","Current trigger restores %d Mana before the remaining-capacity limit.") % amount
	return text

static func describe(hero: String, level: int, stats: Dictionary, slot: String, skill: Dictionary = {}, actor: Variant = null, authored: String = "") -> String:
	var version := int(stats.get("ruleset_version",1))
	if authored.is_empty():
		var definition: Dictionary = ContentRegistry.hero(hero).get("skills",{}).get(slot,{})
		authored = MineStyle.content_text(definition,"description")
	if version != 2 or slot == "dash": return authored
	var spec := skill if not skill.is_empty() else Abilities.preview_spec(hero,level,stats,slot)
	var powers := Abilities.preview_powers(hero,stats)
	if is_instance_valid(actor):
		powers = {"basic_H":actor.basic_power(),"skill_H":actor.skill_power(),"relic_H":actor.relic_power()}
	var power := int(powers.skill_H)
	var coefficient := float(spec.get("coefficient",0))
	var packet: Variant = Abilities.packet_amount(coefficient,power,stats)
	var lines: PackedStringArray = [Inspect.t("当前结算：普攻 H %d · 技能 H %d · 职业遗物 H %d","Current values: basic H %d · skill H %d · class relic H %d") % [int(powers.basic_H),power,int(powers.relic_H)],Inspect.t("本技能 %.2fH → 每包基础 %d；未计职业追加、增伤、暴击、连击或目标减免。","This skill %.2fH → base %d per packet, before class additions, bonuses, crit, combos or target mitigation.") % [coefficient,int(packet)]]
	if spec.has("tick_coefficient"):
		lines.append(Inspect.t("每跳 %.2fH → %d；持续 %.1f 秒。","Each tick %.2fH → %d; duration %.1f s.") % [float(spec.tick_coefficient),int(Abilities.packet_amount(float(spec.tick_coefficient),power,stats)),float(spec.lifetime)])
	if spec.has("health"): lines.append(Inspect.t("法晶生命 %d","Crystal health %d") % int(spec.health))
	if int(spec.get("shots",spec.get("waves",1))) > 1:
		lines.append(Inspect.t("共 %d 包；各包需实际命中，不视为必然总伤害。","%d packets; each must hit, so this is not guaranteed total damage.") % int(spec.get("shots",spec.get("waves",1))))
	if hero == "CH03":
		var multiplier: float = actor.resource_gain_multiplier() if is_instance_valid(actor) and actor.has_method("resource_gain_multiplier") else 1.0+float(stats.get("resource_gain_bonus",0))
		var refund := Numbers.integer(float(Numbers.scale(float(ContentRegistry.hero(hero).passive.resource_gain),version))*multiplier)
		lines.append(Inspect.t("满共鸣被动触发时回复 %d 法力，受剩余容量限制；不是每次施放返还。","Full-Resonance passive trigger restores %d Mana, limited by remaining capacity; this is conditional, not every cast.") % refund)
	return "\n".join(lines)+"\n\n"+Inspect.t("基础动作说明（当前强化与分支以实时值为准）","Base action reference (current upgrades/branches use the values above)")+"\n"+authored_text(authored,version)
