extends RefCounted
## UI data uses the same settled H, packet and live cost providers as combat.
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Abilities = preload("res://scripts/gameplay/characters/hero_abilities.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
static var _authored_cache: Dictionary = {}

## New identity-based page entries contain settled specs from the service.
static func entry(view: Dictionary, skill_id: String) -> Dictionary:
	for value: Variant in view.get("skills",[]):
		if value is Dictionary and str(value.get("skill_id",value.get("id",""))) == skill_id:
			return value.duplicate(true)
	return {}

static func source_text(skill: Dictionary) -> String:
	var source: Variant = skill.get("source",{})
	if source is String: return source
	if not source is Dictionary: return ""
	if str(source.get("kind","")) == "starter":
		return Inspect.t("职业初始技能，开局永久拥有。","Starter skill, permanently learned from the beginning.")
	var room := str(source.get("room_id",source.get("room","")))
	var location := GameStyle.content_text(source,"name",GameStyle.content_text(source,"label",room))
	var kind := Inspect.t("支路探索","Side-route exploration") if str(source.get("kind","")) == "exploration" else Inspect.t("任务奖励","Quest reward")
	return room+" · "+location+"\n"+kind+Inspect.t("。获得后同时解锁三职业技能，死亡与撤离保留。",". Unlocks a skill for all three roles and persists through death and extraction.")

static func config_reason(reason: String) -> String:
	var messages: Dictionary = {
		"SKILL_CAMP_ONLY":["整次出征不能更换技能或分支，请返回营地。","Skills and branches stay fixed throughout an expedition. Return to camp to edit."],
		"SKILL_INVALID_LOADOUT":["请选择本职业四个互不重复、已学会的技能。","Choose four unique, learned skills from this role."],
		"SKILL_BRANCH_LOCKED":["技能熟练度尚未达到此分支的开放等级。","This skill has not reached the mastery required for that branch."],
		"SKILL_PROFILE_NOT_READY":["技能档案尚未准备好，请重新打开页面。","The skill profile is not ready. Reopen this page."],
		"SKILL_OPERATION_CONFLICT":["此前的保存仍需处理，请保持当前配置并重试。","A previous save still needs recovery. Keep this configuration and retry."],
		"SKILL_PENDING_CONFLICT":["存档已发生变化，请还原草稿并重新配置。","The save has changed. Revert this draft and configure again."],
		"SKILL_CONFIG_CAPACITY":["技能保存记录已达到上限，当前配置未应用。","Skill save records reached their limit. This configuration was not applied."],
	}
	if messages.has(reason): return str(messages[reason][1 if Words.locale == "en" else 0])
	return reason if not reason.is_empty() and not reason.begins_with("SKILL_") else Inspect.t("保存失败，当前草稿保留；请重试同一配置。","Save failed. Your draft is retained; retry the same configuration.")

static func spec_facts(spec: Dictionary) -> String:
	var lines := PackedStringArray()
	if spec.has("total_coefficient"):
		lines.append(Inspect.t("整次基础倍率 %.2fH","Total base coefficient %.2fH") % float(spec.total_coefficient))
	elif float(spec.get("coefficient",0.0)) > 0.0:
		lines.append(Inspect.t("单段基础倍率 %.2fH","Per-packet base coefficient %.2fH") % float(spec.coefficient))
	if spec.has("tick_coefficient"):
		lines.append(Inspect.t("持续效果每跳 %.2fH","Each sustained pulse %.2fH") % float(spec.tick_coefficient))
	if spec.has("windup") and spec.has("duration"):
		lines.append(Inspect.t("准备 %.2f 秒 · 总动作 %.2f 秒","Prepare %.2f s · Action %.2f s") % [float(spec.windup),float(spec.duration)])
	if spec.has("range"): lines.append(Inspect.t("距离 %.0f","Range %.0f") % float(spec.range))
	if spec.has("radius"): lines.append(Inspect.t("半径 %.0f","Radius %.0f") % float(spec.radius))
	if spec.has("shield_ratio"): lines.append(Inspect.t("护盾为最大生命 %.0f%%","Shield: %.0f%% of maximum HP") % (100.0 * float(spec.shield_ratio)))
	return "\n".join(lines)

## A read-only ledger entry: branch and upgrade prose comes from the hero catalog.
static func ledger_entry(hero_id: String, level: int, stats: Dictionary, slot: String, branches: Dictionary = {}) -> Dictionary:
	if int(Game.profile.get("role_combat_version",0)) >= 2 and Game.has_method("skill_page_view"):
		var identity := slot
		if slot in ["q","secondary","f","ultimate"]:
			var loadout: Array = Game.call("get_loadout",hero_id)
			if loadout.size() == 4: identity = str(loadout[["q","secondary","f","ultimate"].find(slot)])
		var page: Dictionary = Game.call("skill_page_view",hero_id,"run" if Game.run != null else "camp")
		var selected := entry(page,identity)
		return {"slot":slot,"skill_id":identity,"title":str(selected.get("name","")),"spec":selected.get("spec",{}),"unlock":1,"unlocked":selected.get("unlocked",false),"description":str(selected.get("description",""))}
	var hero := ContentRegistry.hero(hero_id)
	var skill: Dictionary = hero.get("skills",{}).get(slot,{}).duplicate(true)
	var spec := Abilities.preview_spec(hero_id,level,stats,slot)
	skill.merge(spec,true)
	var description := GameStyle.content_text(skill,"description")
	for upgrade: Dictionary in hero.get("upgrades",[]):
		if str(upgrade.get("skill","")) == slot and level >= int(upgrade.get("level",99)):
			description = Words.text("SKILL_UPGRADE_ACTIVE",{"level":upgrade.get("level",0)})+"\n"+GameStyle.content_text(upgrade,"description")+"\n\n"+Words.text("BASE_SKILL")+"\n"+description
	var choice := str(branches.get(slot,""))
	if not choice.is_empty():
		var branch: Dictionary = hero.get("branches",{}).get("18" if slot == "q" else "20",{}).get(choice,{})
		description = Words.text("BRANCH_ACTIVE",{"choice":choice})+" · "+GameStyle.content_text(branch,"name")+"\n"+GameStyle.content_text(branch,"description")+"\n\n"+Words.text("BASE_SKILL")+"\n"+description
	return {"slot":slot,"title":GameStyle.content_text(skill,"name"),"spec":skill,"unlock":int(skill.get("unlock",1)),"unlocked":level >= int(skill.get("unlock",1)),"description":describe(hero_id,level,stats,slot,skill,null,description)}

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
	if int(Game.profile.get("role_combat_version",0)) >= 2 or int(hero.get("role_combat_version",0)) >= 2:
		return authored_text(GameStyle.content_text(hero.get("passive",{}),"description"),int(stats.get("ruleset_version",1)))
	var version := int(stats.get("ruleset_version",1))
	var text := authored_text(GameStyle.content_text(hero.get("passive",{}),"description_v2" if version == 2 and hero.get("passive",{}).has("description_v2") else "description"),version)
	if version == 2 and str(hero.get("id","")) == "CH01":
		var passive: Dictionary = hero.get("passive",{})
		var maximum := _maximum_hp(stats,actor)
		var shield := Numbers.integer(maximum*float(passive.get("shield_hp_ratio",0)))
		text += "\n"+Inspect.t("当前触发护盾 %d，持续 %.1f 秒；内置冷却 %.1f 秒。多来源取最大容量，不叠加。","Current trigger grants %d shield for %.1f s; internal cooldown %.1f s. Overlapping sources use the largest capacity, without adding together.") % [shield,float(passive.get("duration",0)),float(passive.get("icd",0))]
	if version == 2 and str(hero.get("id","")) == "CH03":
		var gain := float(hero.get("passive",{}).get("resource_gain_v2",10))
		var multiplier: float = actor.resource_gain_multiplier() if is_instance_valid(actor) and actor.has_method("resource_gain_multiplier") else 1.0+float(stats.get("resource_gain_bonus",0))
		var amount := Numbers.integer(float(Numbers.scale(gain,version))*multiplier)
		text += "\n"+Inspect.t("当前触发回复 %d 法力（未满资源时；受剩余容量限制）。","Current trigger restores %d Mana before the remaining-capacity limit.") % amount
	return text

static func describe(hero: String, level: int, stats: Dictionary, slot: String, skill: Dictionary = {}, actor: Variant = null, authored: String = "") -> String:
	if int(Game.profile.get("role_combat_version",0)) >= 2 and slot in ["q","secondary","f","ultimate"] and Game.has_method("get_loadout"):
		var ids: Array = Game.call("get_loadout",hero)
		if ids.size() == 4: slot = str(ids[["q","secondary","f","ultimate"].find(slot)])
	if slot.begins_with("CH"):
		var view: Dictionary = Game.call("skill_page_view",hero,"run" if Game.run != null else "camp") if Game.has_method("skill_page_view") else {}
		var item := entry(view,slot)
		var spec: Dictionary = skill if not skill.is_empty() else item.get("spec",{})
		return str(item.get("description",authored))+"\n"+Inspect.t("消耗 %d · 冷却 %.2f 秒 · 准备 %.2f 秒 · 总动作 %.2f 秒","Cost %d · cooldown %.2f s · prepare %.2f s · action %.2f s") % [int(spec.get("cost",0)),float(spec.get("cooldown",0)),float(spec.get("windup",0)),float(spec.get("duration",0))]
	var version := int(stats.get("ruleset_version",1))
	if authored.is_empty():
		var definition: Dictionary = ContentRegistry.hero(hero).get("skills",{}).get(slot,{})
		authored = GameStyle.content_text(definition,"description")
	if version != 2 or slot == "dash": return authored
	var spec := skill if not skill.is_empty() else Abilities.preview_spec(hero,level,stats,slot)
	var powers := Abilities.preview_powers(hero,stats)
	if is_instance_valid(actor):
		powers = {"basic_H":actor.basic_power(),"skill_H":actor.skill_power(),"relic_H":actor.relic_power()}
	var power := int(powers.skill_H)
	var coefficient := float(spec.get("coefficient",0))
	var packet: Variant = Abilities.packet_amount(coefficient,power,stats)
	var lines: PackedStringArray = [Inspect.t("当前结算：普攻 H %d · 技能 H %d · 职业遗物 H %d","Current values: basic H %d · skill H %d · class relic H %d") % [int(powers.basic_H),power,int(powers.relic_H)],Inspect.t("本技能 %.2fH → 每包基础 %d；未计职业追加、增伤、暴击、连击或目标减免。","This skill %.2fH → base %d per packet, before class additions, bonuses, crit, combos or target mitigation.") % [coefficient,int(packet)]]
	var definition: Dictionary = ContentRegistry.hero(hero).get("skills",{}).get(slot,{})
	var summary: String = GameStyle.content_text(definition,"summary_v2", "")
	if not summary.is_empty(): lines.insert(0,summary)
	lines.insert(1,Inspect.t("消耗 %d · 冷却 %.2f 秒 · 准备 %.2f 秒 · 总动作 %.2f 秒","Cost %d · cooldown %.2f s · prepare %.2f s · action %.2f s") % [int(spec.cost),float(spec.cooldown),float(spec.windup),float(spec.duration)])
	if spec.has("range"): lines.append(Inspect.t("施放/弹体最大距离 %.0f","Cast/projectile maximum range %.0f") % float(spec.range))
	if spec.has("radius"): lines.append(Inspect.t("效果半径 %.0f","Effect radius %.0f") % float(spec.radius))
	if spec.has("movement"): lines.append(Inspect.t("施放时移动速度 %.0f%%","Movement speed while casting %.0f%%") % (100.0*float(spec.movement)))
	if not str(spec.get("branch","")).is_empty(): lines.append(Inspect.t("当前分支 %s；上方数字已包含其改变。","Current branch %s; the values above include its changes.") % str(spec.branch))
	if float(spec.get("burst_coefficient",0.0)) > 0.0:
		lines.append(Inspect.t("落点立即晶爆 %.2fH → %d，半径 %.0f；随后法晶自动攻击，最多2枚。","Immediate crystal blast %.2fH → %d, radius %.0f; then an automatic crystal remains, up to 2.") % [float(spec.burst_coefficient),int(Abilities.packet_amount(float(spec.burst_coefficient),power,stats)),float(spec.burst_radius)])
	if spec.has("tick_coefficient"):
		lines.append(Inspect.t("每跳 %.2fH → %d；持续 %.1f 秒。","Each tick %.2fH → %d; duration %.1f s.") % [float(spec.tick_coefficient),int(Abilities.packet_amount(float(spec.tick_coefficient),power,stats)),float(spec.lifetime)])
	if float(spec.get("guard",0)) > 0:
		var shield := Numbers.integer(_maximum_hp(stats,actor)*float(spec.guard))
		# HeroAbilities grants Q-B/E shields for 4 s. The spec's guard_duration
		# is E's separate damage-reduction timer, not the shield lifetime.
		lines.append(Inspect.t("本次释放授予护盾 %d，持续 4.0 秒；多来源取最大容量，不叠加。","This release grants %d shield for 4.0 s; overlapping sources use the largest capacity, without adding together.") % shield)
		if spec.has("damage_reduction"):
			lines.append(Inspect.t("另获 %.0f%% 减伤，持续 %.1f 秒（与护盾独立计时）。","Separately grants %.0f%% damage reduction for %.1f s, timed independently of the shield.") % [float(spec.damage_reduction)*100.0,float(spec.get("guard_duration",0))])
	if spec.has("health"): lines.append(Inspect.t("法晶生命 %d","Crystal health %d") % int(spec.health))
	if int(spec.get("shots",spec.get("waves",1))) > 1:
		lines.append(Inspect.t("共 %d 包；各包需实际命中，不视为必然总伤害。","%d packets; each must hit, so this is not guaranteed total damage.") % int(spec.get("shots",spec.get("waves",1))))
	if hero == "CH03":
		var multiplier: float = actor.resource_gain_multiplier() if is_instance_valid(actor) and actor.has_method("resource_gain_multiplier") else 1.0+float(stats.get("resource_gain_bonus",0))
		var refund := Numbers.integer(float(Numbers.scale(float(ContentRegistry.hero(hero).passive.get("resource_gain_v2",10)),version))*multiplier)
		var reduction: float = float(ContentRegistry.hero(hero).passive.get("q_cooldown_refund_v2",.6))
		lines.append(Inspect.t("可选连携：交替施法第3次回 %d 法力，Q剩余冷却减%.1f秒；Q→W→Q也有效。无需先普攻或先放法晶。","Optional weaving: the third alternating cast restores %d Mana and trims Q by %.1f s; Q→W→Q also works. No basic attack or crystal setup is required.") % [refund,reduction])
		lines.append(GameStyle.content_text(ContentRegistry.hero(hero),"quick_start_v2",""))
	# Old authored timings stay available to legacy adventures. V2 uses the live
	# spec above so an obsolete 5-second Q/48-second R cannot contradict the HUD.
	if not summary.is_empty():
		lines.append(Inspect.t("技能命中遵守地形与实际范围；闪避可中断，已提交成本不返还。","Terrain and actual range govern hits. Dodge can interrupt; committed costs are not refunded."))
		return "\n".join(lines)
	return "\n".join(lines)+"\n\n"+authored_text(authored,version)

static func _maximum_hp(stats: Dictionary, actor: Variant) -> float:
	return float(actor.stat("max_hp",float(stats.get("max_hp",0)))) if is_instance_valid(actor) and actor.has_method("stat") else float(stats.get("max_hp",0))
