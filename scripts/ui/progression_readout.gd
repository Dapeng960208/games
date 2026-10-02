extends RefCounted
## Read-only presentation of committed growth. Pending room rewards never unlock skills.

const SKILLS := ["q", "secondary", "f", "ultimate"]

static func describe(hero_id: String, total_xp: int) -> Dictionary:
	var xp := clampi(total_xp, 0, ContentRegistry.XP_THRESHOLDS[-1])
	var level := ContentRegistry.level_for_xp(xp)
	var cap := level == ContentRegistry.XP_THRESHOLDS.size()
	var start: int = ContentRegistry.XP_THRESHOLDS[level-1]
	var target := ContentRegistry.next_level_xp(level)
	var next_skill: Dictionary = {}
	var hero: Dictionary = ContentRegistry.hero(hero_id)
	for slot: String in SKILLS:
		var skill: Dictionary = hero.get("skills",{}).get(slot,{})
		if int(skill.get("unlock",1)) > level:
			next_skill = skill.duplicate(true)
			next_skill["slot"] = slot
			break
	return {"hero_id":hero_id,"level":level,"xp":xp,"progress":xp-start,"span":maxi(1,target-start),
		"remaining":maxi(0,target-xp),"capped":cap,"next_skill":next_skill}

static func key_for(slot: String) -> String:
	var action: String = {"q":"skill_q","secondary":"skill_secondary","f":"skill_f","ultimate":"skill_ultimate"}.get(slot,"")
	return ControlBindings.label_for(action,Game.profile.get("settings",{}).get("controls",{}),Words.locale) if not action.is_empty() else slot

static func next_goal(hero_id: String, xp: int) -> String:
	var info := describe(hero_id,xp)
	var english := Words.locale == "en"
	if info.capped:
		return "Max level · refine equipment and skill branches" if english else "等级已满 · 调整装备搭配与技能分支"
	var skill: Dictionary = info.next_skill
	if not skill.is_empty():
		var name := MineStyle.content_text(skill,"name")
		var unlock: int = skill.unlock
		var remaining: int = ContentRegistry.XP_THRESHOLDS[unlock-1]-int(info.xp)
		return ("Lv.%d · %s %s · %d XP to unlock" if english else "Lv.%d · %s %s · 还需 %d 经验") % [unlock,key_for(skill.slot),name,remaining]
	return ("Lv.%d · %d XP to next level · refine your build" if english else "下一级 Lv.%d · 还需 %d 经验 · 完善装备搭配") % [int(info.level)+1,int(info.remaining)]

static func unlock_hint(hero_id: String, slot: String) -> String:
	var hints := {
		"CH01:secondary":["积攒破势，再用 {secondary} 裂地重斩消耗爆发。","Build Momentum, then spend it with the {secondary} cleave."],
		"CH01:f":["{f} 战吼获得护盾、短时减伤，推开敌人并补破势。","{f} grants a shield, brief damage reduction, space and Momentum."],
		"CH01:ultimate":["积满破势后，{ultimate} 天崩斧落完成爆发。","Build full Momentum for the {ultimate} Skyfall Axe finisher."],
		"CH02:secondary":["先用 {f} 榴弹标记，再用 {secondary} 贯穿消费猎印。","Mark with the {f} grenade, then consume marks with the {secondary} piercer."],
		"CH02:f":["{f} 投掷榴弹，出手0.65秒后爆炸并施加猎印。","{f} throws a grenade that explodes and marks after a 0.65 s fuse."],
		"CH02:ultimate":["标记关键目标后，{ultimate} 连射倾泻火力。","Mark a priority target, then fire the {ultimate} barrage."],
		"CH03:secondary":["{secondary} 布置法晶，{q} 穿过法晶为节点蓄能。","Place crystals with {secondary}; pass {q} through them to charge."],
		"CH03:f":["先布晶、用 {q} 充能，再按 {f} 新星引爆。","Place crystals, charge with {q}, then detonate with the {f} nova."],
		"CH03:ultimate":["{ultimate} 领域持续寒冷控制并充满法晶，接 {f} 引爆。","{ultimate} chills through field ticks and fills crystals; follow with {f}."]}
	var pair: Array = hints.get(hero_id+":"+slot,["",""])
	var v2: bool = Game.run.ruleset_version() == 2 if Game.run != null else int(Game.profile.get("ruleset_version",1)) == 2
	if v2:
		if hero_id == "CH02" and slot == "f": pair = ["{f} 投向怪群，0.5秒后爆炸并标记。","Throw {f} into a pack; it explodes and marks after 0.5 s."]
		elif hero_id == "CH03":
			pair = {"secondary":["{secondary} 落点立即晶爆，留下的法晶自动攻击。","{secondary} blasts immediately and leaves an auto-attacking crystal."],"f":["被近身按 {f}：立即伤害并减速，不需要先放法晶。","Press {f} when surrounded: damage and slow, with no crystal setup."],"ultimate":["把 {ultimate} 放进怪群：持续伤害与减速，无需前置。","Place {ultimate} on a pack: repeated damage and slows, no setup."]}.get(slot,pair)
	var hint: String = str(pair[1 if Words.locale == "en" else 0])
	for key: String in SKILLS: hint = hint.replace("{"+key+"}",key_for(key))
	return hint
