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
	return {"q":"Q", "secondary":"Right click" if Words.locale == "en" else "鼠标右键", "f":"F", "ultimate":"R"}.get(slot,slot)

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
		"CH01:secondary":["积攒破势，再用鼠标右键消耗重击。","Build Momentum, then spend it with right click."],
		"CH01:f":["F 获得护盾、击退敌人并补一层破势。","F grants a shield, pushes enemies and adds Momentum."],
		"CH01:ultimate":["积满破势后，R 发动重锤落井。","Build full Momentum before dropping the hammer with R."],
		"CH02:secondary":["游走标记目标，再用鼠标右键消耗猎印。","Mark a target while moving; right click consumes the mark."],
		"CH02:f":["F 放下伏板，诱敌触发猎印。","Place a trap with F and lure enemies into its mark."],
		"CH02:ultimate":["标记关键目标后，R 连续贯穿。","Mark a priority target, then fire the R barrage."],
		"CH03:secondary":["鼠标右键布置节点，Q 穿过节点蓄能。","Place a node with right click; fire Q through it to charge."],
		"CH03:f":["先布节点、用 Q 充能，再按 F 引爆。","Place nodes, charge with Q, then detonate with F."],
		"CH03:ultimate":["R 给范围内节点充满，接 F 引爆。","R fully charges nearby nodes; follow with F to detonate."]}
	var pair: Array = hints.get(hero_id+":"+slot,["",""])
	return str(pair[1 if Words.locale == "en" else 0])
