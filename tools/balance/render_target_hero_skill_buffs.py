#!/usr/bin/env python3
"""Render the integer hero/skill/buff proposal; never write runtime or profiles."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
from decimal import Decimal, ROUND_HALF_UP, ROUND_FLOOR
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/balance/TARGET_HERO_SKILL_BUFF_TABLES.md"
PARAMS = ROOT / "docs/balance/numerical_v2_parameters.json"
CURRENT = ROOT / "docs/balance/CURRENT_BUFF_SKILL_CATALOG.md"
HERO_PATH = ROOT / "data/heroes.json"
KEY_LEVELS = (1, 2, 3, 4, 10, 12, 14, 16, 18, 20)
SLOTS = ("q", "secondary", "f", "ultimate")
INPUTS = [PARAMS, CURRENT, HERO_PATH] + [ROOT / p for p in (
    "scripts/combat/hero_abilities.gd", "scripts/combat/hero_deployment.gd",
    "scripts/combat/hero_passives.gd", "scripts/combat/player.gd",
    "scripts/combat/class_relics.gd", "scripts/combat/race_relics.gd",
    "scripts/combat/combat_status.gd", "scripts/combat/equipment_effects.gd",
    "scripts/core/run_controller.gd", "scripts/world/room_props.gd")]

# The actual 264 current preview rows contain precisely these dimensions.
# Unknown fields fail generation rather than silently inheriting a scale.
FIELD_RULES = {
    "cost": "资源平值：R(旧值×10)，再按条件减耗/免耗规则结算",
    "health": "法晶生命平值：R(旧值×10)，35/50变350/500",
    "coefficient": "伤害/H比例：不放大；每段X=R(该比例×新H)",
    "tick_coefficient": "领域伤害/H比例：不放大；每跳X=R(该比例×新H)",
    "guard": "护盾/MHP比例：不放大；容量R(比例×新整数MHP)",
    "damage_reduction": "减伤比例：不放大；不把25%误写成250%",
    "movement": "施放移动比例：不放大",
    "pierce_multiplier": "后续目标伤害比例：不放大；新后续包R(新X×比例)",
    **{k: "时间/秒：原值保留，不取整数、不放大" for k in (
        "base_cooldown", "cooldown", "duration", "fuse", "guard_duration",
        "lifetime", "travel_time", "windup")},
    **{k: "世界距离/速度/角度：原值保留，不放大" for k in (
        "arc", "explosion_radius", "knockback", "radius", "range", "speed", "travel")},
    **{k: "次数/解锁等级：原值保留，不放大" for k in ("pierce", "shots", "unlock", "waves")},
    **{k: "标识/布尔/文案：原值保留" for k in (
        "branch", "damage_type", "echo_along_path", "follow_player", "hero", "input", "name", "slot")},
}


def d(value):
    return Decimal(str(value))


def R(value):
    """Nonnegative half-up, independent of Python's ties-to-even round."""
    value = d(value)
    if value < 0:
        raise ValueError("Integer combat magnitudes must be nonnegative")
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def floor(value):
    return int(d(value).to_integral_value(rounding=ROUND_FLOOR))


def cell(value):
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return str(value).replace("|", "&#124;").replace("\r", "").replace("\n", "<br>")


def table(headers, rows):
    rows = list(rows)
    for index, row in enumerate(rows, 1):
        if len(row) != len(headers):
            raise ValueError(f"Table {headers!r} row {index}: incorrect column count")
    return "\n".join(["| " + " | ".join(map(cell, headers)) + " |",
                      "| " + " | ".join("---" for _ in headers) + " |"] +
                     ["| " + " | ".join(map(cell, row)) + " |" for row in rows]) + "\n\n"


def ref(path, needle):
    index = next(i for i, line in enumerate((ROOT / path).read_text(encoding="utf-8-sig").splitlines(), 1) if needle in line)
    return f"[{Path(path).name}:{index}](../../{path}#L{index})"


def read_preview():
    text = CURRENT.read_text(encoding="utf-8")
    part = text.split("<!-- SKILL_PREVIEW_ROWS_START -->", 1)[1].split("<!-- SKILL_PREVIEW_ROWS_END -->", 1)[0]
    rows = []
    for line in part.splitlines():
        if not line.startswith("| CH0"):
            continue
        hero, level, slot, branch, spec, timeline = [html.unescape(c.strip()) for c in line.strip("|").split("|")]
        rows.append({"hero": hero, "level": int(level), "slot": slot,
                     "branch": "" if branch == "默认" else branch,
                     "spec": json.loads(spec), "timeline": json.loads(timeline)})
    expected = {(h, l, s, b) for h in ("CH01", "CH02", "CH03") for l in range(1, 21)
                for s in SLOTS for b in (("", "A", "B") if (s == "q" and l >= 18) or (s == "ultimate" and l >= 20) else ("",))}
    keys = [(r["hero"], r["level"], r["slot"], r["branch"]) for r in rows]
    if len(rows) != 264 or len(set(keys)) != 264 or set(keys) != expected:
        raise ValueError("Current appendix must supply all 264 unique actual previews")
    present = set().union(*(r["spec"] for r in rows))
    if present != set(FIELD_RULES):
        raise ValueError(f"Unclassified or missing skill fields: {present ^ set(FIELD_RULES)}")
    return rows


def hero_stats(c, hero, level):
    scale = d(c.get("combat_scale", 10))
    result = {}
    for key in ("attack", "ability_power", "max_hp", "armor", "magic_resist"):
        base = d(hero.get(key, 12 if key == "magic_resist" else 0)) * scale
        growth = d(c["growth"][key])
        raw = base * (1 + growth * (level - 1)) if key in ("attack", "ability_power", "max_hp") else base + growth * (level - 1)
        result[key] = R(raw)
    result["basic_H"] = R(d(result["attack"]) + d(".35") * result["ability_power"]) if hero["id"] == "CH03" else result["attack"]
    result["skill_H"] = R(d(result["attack"]) + d(".7") * result["ability_power"]) if hero["id"] == "CH03" else result["attack"]
    result["relic_H"] = result["ability_power"] if hero["id"] == "CH03" else result["attack"]
    result["resource_max"] = R(d(hero["resource_max"]) * scale)
    result["starting_resource"] = R(d(hero["starting_resource"]) * scale)
    result["resource_regen"] = R(d(hero["resource_regen"]) * scale)
    return result


def convert(row, stats, scale):
    old = row["spec"]
    spec = dict(old)
    for key in ("cost", "health"):
        if key in spec:
            spec[key] = R(d(spec[key]) * scale)
    h = stats["skill_H"]
    x = R(d(old["coefficient"]) * h)
    packets = len(row["timeline"])
    out = {"basic_H": stats["basic_H"], "skill_H": h, "relic_H": stats["relic_H"],
           "maximum_hp": stats["max_hp"], "cost": spec["cost"], "damage_each": x,
           "release_event_count": packets, "damage_total_base": x * packets,
           "original_damage_each": x, "original_damage_total_base": x * packets,
           "shield_amount": R(d(old.get("guard", 0)) * stats["max_hp"]),
           "heal_amount": 0, "resource_refund": 0, "state_power": h,
           "node_health": spec.get("health", 0)}
    hero, slot = row["hero"], row["slot"]
    if hero == "CH01" and slot in ("secondary", "ultimate"):
        momentum = d(".45") if slot == "secondary" else d(".6")
        amounts = [R((d(old["coefficient"]) + momentum * n) * h) for n in range(4)]
        out["momentum_damage_each_0_1_2_3"] = amounts
        out["momentum_damage_total_0_1_2_3"] = [v * packets for v in amounts]
        out["momentum_cost_0_1_2_3"] = [spec["cost"]] * 3 + [0 if slot == "secondary" else spec["cost"]]
    if "pierce_multiplier" in old:
        out["pierced_damage_each"] = R(d(x) * d(old["pierce_multiplier"]))
    if hero == "CH03" and slot == "q":
        out["node_echo_damage"] = R(d(".35") * h)
        out["shock_followup_base"] = R(d(".25") * h)
    if hero == "CH03" and slot == "secondary":
        out["original_damage_each"] = 0
        out["original_damage_total_base"] = 0
        out["damage_total_base"] = 0
        out["automatic_max_shots"] = 11
        out["automatic_max_damage"] = x * 11
        out["node_detonation_0_1_2_3"] = [R((1 + d(".65") * n) * h) for n in range(4)]
    if hero == "CH03" and slot == "f":
        out["same_snapshot_node_detonation_0_1_2_3"] = [R((1 + d(".65") * n) * h) for n in range(4)]
        out["two_full_nodes_plus_direct"] = x + 2 * out["same_snapshot_node_detonation_0_1_2_3"][3]
    if "tick_coefficient" in old:
        out["field_tick_damage"] = R(d(old["tick_coefficient"]) * h)
        out["field_tick_count"] = floor(old["lifetime"])
        out["field_max_damage"] = x + out["field_tick_damage"] * out["field_tick_count"]
        out["shock_followup_base"] = R(d(".25") * h)
    return {**row, "spec": spec, "target": out}


def summary(row):
    p, s = row["target"], row["spec"]
    parts = [f"每段{p['damage_each']}×{p['release_event_count']}；基础合计{p['damage_total_base']}"]
    if "momentum_damage_each_0_1_2_3" in p:
        parts.append("破势0/1/2/3每段=" + "/".join(map(str, p["momentum_damage_each_0_1_2_3"])))
        parts.append("对应总量=" + "/".join(map(str, p["momentum_damage_total_0_1_2_3"])))
    if "pierced_damage_each" in p:
        parts.append(f"每个穿透次目标{p['pierced_damage_each']}")
    if "node_echo_damage" in p:
        parts.append(f"节点回声{p['node_echo_damage']}；旧感电追加基值{p['shock_followup_base']}")
    if "automatic_max_damage" in p:
        parts = [f"节点每射{p['damage_each']}；最多11射合计{p['automatic_max_damage']}"]
        parts.append("节点0/1/2/3电荷引爆=" + "/".join(map(str, p["node_detonation_0_1_2_3"])))
    if "two_full_nodes_plus_direct" in p:
        parts.append("同快照节点0/1/2/3电荷引爆=" + "/".join(map(str, p["same_snapshot_node_detonation_0_1_2_3"])))
        parts.append(f"直接+2满节点={p['two_full_nodes_plus_direct']}")
    if "field_tick_damage" in p:
        parts.append(f"领域每跳{p['field_tick_damage']}×{p['field_tick_count']}；建场+全跳{p['field_max_damage']}")
    return "；".join(parts)


def benefit(row):
    p, s = row["target"], row["spec"]
    parts = [f"成本{p['cost']}；主动治疗0、直接退款0"]
    if "momentum_cost_0_1_2_3" in p:
        parts.append("0/1/2/3破势成本=" + "/".join(map(str, p["momentum_cost_0_1_2_3"])))
    if p["shield_amount"]:
        parts.append(f"护盾{p['shield_amount']}（{d(s['guard']) * 100}%MHP，4秒）")
    if p["node_health"]:
        parts.append(f"法晶生命{p['node_health']}")
    parts.append(f"状态power={p['state_power']}仅在实际施加状态时使用")
    return "；".join(parts)


def render(c, heroes, rows):
    scale = d(c.get("combat_scale", 10))
    if scale != 10:
        raise ValueError("This confirmed integer proposal requires combat_scale=10")
    if c.get("runtime_enabled") is not False:
        raise ValueError("This tool produces documents for a runtime-disabled proposal")
    targets = [convert(row, hero_stats(c, heroes[row["hero"]], row["level"]), scale) for row in rows]
    lookup = {(r["hero"], r["level"], r["slot"], r["branch"]): r for r in targets}
    out = ["# 新版角色、技能与Buff整数目标全表\n",
           f"日期：{c['date']}；现状来源提交：`{c['source_commit']}`。**本册是已确认方向的重构实施目标，尚未接入游戏或玩家档。** [主方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)约束结算、装备与经济；[目标总表](TARGET_NUMERICAL_TABLES.md)记录装备与敌人；[当前Buff技能册](CURRENT_BUFF_SKILL_CATALOG.md)保留现状。\n",
           "本册由[标准库生成器](../../tools/balance/render_target_hero_skill_buffs.py)读取[参数文件](numerical_v2_parameters.json)、三角色定义与CURRENT册内嵌的264条实际技能预览生成。264预览是当前规则的输入；新整数金额是目标计算结果。当前册的1455条源码数值索引不是已实施重构的证明。\n",
           "## 1. 单位与取整边界\n",
           "`R(x)=floor(max(0,x)+0.5)`，仅对非负战斗金额使用，即round_half_up；`.5`向上，不使用Python/Godot的隐含银行家取整。`combat_scale=10`：旧攻击27变270、资源100变1000。比例、秒、坐标、移速、弹速、角度、次数、电荷、层数和经验/金币/材料不属于战斗金额，保持各自原单位。不是给当前每个数字无差别乘10。\n",
           table(["结算项", "新版公式/整数写入位置", "保留规则"], [
               ["聚合AD/AP/HP/双抗", "旧英雄初值×10；成长→天赋完整表达式R；实例各平值完整公式R后加入角色；生命比例/动态属性在各自合成边界R", "新参数的装备基值、每级双抗、天赋平值已是新单位，不再×10；实例保存k/u，不能用取整结果逐次强化"],
               ["H", "使用已聚合取整的AD/AP；basic/skill/relic按各自口径再R", "法师basic=R(AD+.35AP)、skill=R(AD+.7AP)、relic=AP"],
               ["原始每段X/职业P", "X=R(系数×H)；P按每个已登记职业追加比例×H取整；X在P/B/C/K前保存", "手动直接技能与普攻每root共享一次暴击；节点/领域/DOT/派生不重新暴击"],
               ["原始总包与防御", "D_input=R((X+P)×(1+min(1,B))×C×K)；弱点/双抗/减伤之后，入CombatStatus盾/HP前R", "相同root暴击结果共享，穿透比例对对应新金额施加，世界碰撞不改"],
               ["抗性", "1000/(1000+max(0,新防御−新穿透))；先应用腐蚀护甲×.85", "分母常数100→1000，保持同比缩放的抵抗率；真伤/无敌路径按主方案"],
               ["状态快照power", "R(已定义来源H/遗物主属性×自身倍率×适用状态专属倍率)后保存；每完整秒R(tick系数×已保存power)", "不是用暴击/扣血替代power；计数、tick时点、覆盖、时长不改"],
               ["护盾", "容量R(新整数MHP×比例)；再按该来源容量上限和多源盾规则写入", "比例不再×10；多源盾仍max并同步扣除"],
               ["普通治疗", "完整比例×MHP×治疗倍率之后R一次，再截整数缺血；安全治疗使用其现状安全倍率", "不能先R比例金额再乘重伤；法师Lv2 MHP1103重伤复苏=R(.25×1103×.6)=165"],
               ["装备限流治疗", "候选R(新MHP×ratio)，先裁剪滑动预算/缺口，再R(accepted×治疗倍率)并最终截缺口", "与普通治疗区分；总预算R(.03MHP)，不能多包取整后突破"],
               ["一次资源成本/回复", "固定资源值×10；成本减耗后R，正成本最低10；免费技能仍0；回复增益后R并执行容量/历史限流", "固定30%补给/信标不吃资源回复桶；CD退款单位仍秒"],
               ["持续资源流", "每秒有效rate先R；每源累计应结算量Q(t)，本次提交floor(Q(t))−floor(Q(t_previous))；不足1余数留在源累计器", "不能逐帧R(rate×dt)，否则50/s会随FPS变化；怒气衰减同法计算正扣除量"],
               ["装备派生预算", "金额预算floor(6X/5)，以整数(6×X)//5精确求值；依现状接受系数和稳定顺序处理，逐包R后再裁剪整数剩余预算", "4包仍含原生状态/遗物/装备packet=true；遗物不计1.2X金额，纯Buff不占包"],
           ]),
           "整数边界不额外强制最小伤害1。R后为0的原始/派生包按0处理；confirmed仍要求真实HP或合法护盾正损失。实例主属性/词条只在完整roll公式完成后R，不能对中间因子提前取整；多个已整数实例再合成角色属性。护盾容量/HP/资源账本写整数，持续计时与倍率仍允许小数。所有目标表的伤害是防御前、无暴击/连击/直接增伤的基值，不能当作实际DPS。\n",
           "### 1.1 所有35个skill spec字段的完整转换登记\n",
           table(["字段", "转换规则"], sorted(FIELD_RULES.items())),
           "`damage_type`是类型标识；`damage_reduction`是比例；`coefficient/tick_coefficient`是伤害比例，三者不能按字段包含damage就放大10倍。264个原spec里没有主动技能heal/resource_refund平值：其目标均为0；职业被动/遗物退款独立列第4–5节。`guard_duration`在战士E是减伤时长1.5秒，主动护盾时长另固定4秒。\n",
           "### 1.2 技能执行上下文与Buff金额字段\n",
           table(["执行字段/命令", "新版变换", "源H与非金额边界"], [
               ["damage / amount / X", "本技能coef×整数H后R；保存X，最终直接包B/C/K后再R", "伤害类型damage_type保持；W法晶部署时没有免费原始接触伤害"],
               ["power / H / state_power", "按本次basic/skill/relic口径R后快照；状态专属倍率适用时合成后R", "标志类无敌/重伤power=1和减伤比例保持；旧已部署节点不回溯换H"],
               ["echo_damage", "R(.35×Q的H_skill)", "回声距离90/半径70不变；不暴击/递归"],
               ["field damage / tick damage", "R(tick_coefficient×R建场保存H_skill)", "每秒时点、lifetime、tick计数不变；不抽新暴击"],
               ["node damage / detonation", "每射R(.15×节点H)；引爆R((1+.65charge)×节点H)", "电荷0–3、节点数2、频率1.2秒保持"],
               ["health / node_health", "R(旧35/50×10)=350/500", "节点生命而非世界大小；不再对新数值乘10"],
               ["guard / shield_ratio / heal_ratio", "比例不变，乘对应新MHP后按护盾/普通治疗/装备治疗边界取整", "各来源时长、同源覆盖、max共享盾不变"],
               ["cost / base_cost / resource_restore / refund", "旧固定资源金额×10；cost在减耗后R，正下限10；退款加有效回复后R并限流", "怒/能/法通道不互换；满势W免费0；退CD单位秒不放大"],
               ["resource_max / starting_resource / resource_regen", "初始容量1000、怒起始200；每秒能180/法50；额外法力容量平值使用新参数", "resource_regen_delay .5/.8秒保持；持续流累计不足1余数"],
               ["damage_reduction / burn_damage / corrosion_damage_bonus", "保留原比例，进入主方案相应桶与上限", "不能因名称含damage或power而×10"],
           ]),
           "## 2. 三角色初始属性、成长与H\n"]
    initial = []
    for hero in heroes.values():
        s = hero_stats(c, hero, 1)
        initial.append([hero["id"] + " " + hero["name"], s["max_hp"], s["attack"], s["ability_power"], s["armor"], s["magic_resist"], s["basic_H"], s["skill_H"], s["relic_H"], f"{s['starting_resource']}/{s['resource_max']}", s["resource_regen"], hero["attack_interval"], hero["move_speed"]])
    out.append(table(["角色", "HP", "AD", "AP", "护甲", "魔抗", "H_basic", "H_skill", "H_relic", "初始/容量", "回复/秒", "普攻间隔/秒", "世界移速"], initial))
    out.append("裸装成长：AD/AP/HP分别为`R(10×旧初值×[1+成长比例×(L−1)])`，比例AD4%、AP5%、HP5%每级；双抗为`R(10×旧初值+新每级平值×(L−1))`，参数文件护甲每级+10、魔抗每级+8已经是新单位，不能再乘10。天赋的双抗平值每阶20，主力攻击/法强、体魄生命等百分比天赋不放大。本册裸装示例无装备、无天赋、无临时状态。当前技能等级覆盖1–20；未来25–60仅给H接口，不能声称已开放技能强化/分支。\n")
    for hero in heroes.values():
        out.append(f"### {hero['id']} {hero['name']}：Lv.1–20及未来接口校验点\n")
        out.append(table(["等级", "HP", "AD", "AP", "护甲", "魔抗", "H_basic", "H_skill", "H_relic", "天赋点"], [[level] + [hero_stats(c, hero, level)[key] for key in ("max_hp", "attack", "ability_power", "armor", "magic_resist", "basic_H", "skill_H", "relic_H")] + [level - 1] for level in list(range(1, 21)) + [25, 30, 40, 50, 60]]))
    out.append("## 3. 十二主动技能的全部关键等级整数收益\n\n下表逐项列出Lv1/2/3/4/10/12/14/16/18/20；解锁前为定义预览，无法施放。数字合计是每个包各自R后求和，不能把合计系数一次R替代逐包取整。法晶W每射与领域跳伤为自动包；枪手E延迟爆炸仍属于手动施放的原始直接root。\n")
    for hero in heroes.values():
        for slot in SLOTS:
            base = lookup[hero["id"], 1, slot, ""]
            out.append(f"### {hero['id']} {base['spec']['input']} {base['spec']['name']}\n")
            out.append(table(["等级/可施放", "H_skill", "每段/完整伤害", "护盾/生命/治疗/资源", "冷却/秒", "提交后出手timeline/秒"], [[f"{level}/{'是' if level >= row['spec']['unlock'] else '未解锁'}", row["target"]["skill_H"], summary(row), benefit(row), row["spec"]["cooldown"], row["timeline"]] for level in KEY_LEVELS for row in [lookup[hero["id"], level, slot, ""]]]))
    out.append("### 3.1 十二个Q/R分支：解锁级完整整数参数\n\n共有12个A/B选择，当前全等级展开是24条分支预览（Q18/19/20共18条，R20共6条）；完整264组合见第9节。此表列Q18与R20的每个A/B，世界范围、时序、系数与计数都保留，只有cost/法晶health字段换整数单位。\n")
    for hero in heroes.values():
        for level, slot in ((18, "q"), (20, "ultimate")):
            out.append(f"#### {hero['id']} L{level} {lookup[hero['id'], level, slot, '']['spec']['input']}\n")
            out.append(table(["分支", "H_skill", "伤害完整表", "盾/治疗/资源", "完整目标spec", "timeline"], [[branch + " " + hero["branches"][str(level)][branch]["name"], row["target"]["skill_H"], summary(row), benefit(row), row["spec"], row["timeline"]] for branch in ("A", "B") for row in [lookup[hero["id"], level, slot, branch]]]))
    out.append("节点引爆使用节点自身提交时保存的H；E表中的“同快照”是假设节点与E都用该等级裸装H，不表示升级/换装会回溯改变旧节点快照。最多两节点与0–3电荷不变；E的直接包可按root暴击，节点引爆包不暴击、不乘连击、不消费旧感电、不触发装备原始命中。法师R仅建场原始包可暴击，其自动跳伤不暴击。法师W的timeline事件是部署，并不造成该射击金额的免费接触伤害：target的original_damage为0，damage_each用于之后自动射。release_event_count是出手事件数，不是共享4触发包的预算计数。每个伤害包的后续防御、合法目标、取消与预算门槛仍按主方案。\n")
    out.append("## 4. 三职业被动、资源和节点的新版全量公式\n")
    out.append(table(["规则", "新版整数公式与Lv1示例", "保留条件/时间/计数"], [
        ["CH01三铆支护", "R(.08×MHP)：Lv1=120盾", "每3次有效原始普攻root；盾3秒、ICD6秒；冷却中不积攒；同源刷新/异源max"],
        ["CH01破势W", "每段R((2.2+.45n)×H)；Lv1n0/1/2/3=594/716/837/959；n3成本0，n0–2成本300", "n≤3；满层半径140/扇形160°/击退90均不放大；提交消费/取消不退"],
        ["CH01破势R", "每波R((当前branch coefficient+.60n)×H)，波数保持；Lv1默认n0/1/2/3=1080/1242/1404/1566", "R16强化、R20A/B沿现状；B破势追加在每一波，不只第一波"],
        ["CH01怒气", "有效普攻80；真实HP受伤50；脱战每秒扣60；先按30%回复桶放大正收益再限流/容量", "受伤回怒ICD1秒；只有盾损失不回50；脱战延迟5秒；衰减不享回复正增益"],
        ["CH02两发校准", "P_calibration=R(.65H)；Lv1=156；与猎印同击可追加156+300=456", "同目标2有效普攻，下一原始普攻/直接技能消费；焦点5秒、ICD2秒；未确认不消费"],
        ["CH02猎印", "P_mark=R(1.25H)；Lv1=300；W/R原始直接包享同包B/C/K", "E真实命中/RL03第三发产生，4秒，最多32目标；与校准独立；按主方案改成confirmed消费"],
        ["CH03交响回路", "触发时回R(80×[1+min(.30,资源回复)])，无增益=80；最近未满节点+1电荷", "普攻/成功技能交替，层≤3；进度8秒、ICD2秒；范围260/视线，电荷不变成10"],
        ["CH02自然能量", "180/s×(1+有效资源回复)，用累计整数差分；Lv1无增益=180/s", "成功技能后延迟.5秒；资源容量1000；不能逐帧四舍五入"],
        ["CH03自然法力", "50/s×(1+有效资源回复)，用累计整数差分；Lv1无增益=50/s", "成功技能后延迟.8秒；法力装备平值容量×10，怒/能不套法力词条"],
        ["法晶自动射", "每射R(.15×节点快照H)，Lv1=56；最多11射合计616", "展开.35秒、首射1.55秒、每1.2秒、寿命14秒、最多2节点；自动包不独立暴击"],
        ["法晶引爆", "R((1+.65电荷)×节点快照H)，Lv1电荷0/1/2/3=376/620/865/1109", "连接260、爆半径100/120/140/160；2节点各自算；电荷仍0–3"],
        ["法晶回声", "R(.35×该Q提交H)，Lv1=132；最多同敌同root一次", "半径70/路径或爆点90内；无感电、无暴击/连击/装备递归"],
        ["法晶生命", "W1–11级350；W12–20级500", "健康平值放大，展开/数量/射程/射频不放大；不是角色护盾"],
    ]))
    out.append("被动/节点来源：" + ref("scripts/combat/hero_passives.gd", "func record_hit") + "、" + ref("scripts/combat/player.gd", "func gain_break_stacks") + "、" + ref("scripts/combat/hero_deployment.gd", "func detonate") + "；这里只换目标金额与主方案列明的接受/暴击规则，未给自动节点新增原始攻击事件。\n")
    out.append("## 5. 九职业遗物I/II与四种族适配：新版整数目标\n\n以下Lv1裸装示例，H_relic分别270/240/280。遗物按登记通道只执行一次，派生不暴击、不乘连击、不重新触发装备；遗物资源回复有30%回复增益时先放大再资源容量限制。\n")
    out.append(table(["职业/遗物", "I新版公式/整数", "II新版公式/整数", "保持的时序/范围/计数"], [
        ["CH01 RL01裂地楔", "每敌R(.4AD)=108", "每敌R(.6AD)=162", "最多3敌，200范围、前55°半角，排原目标；物理"],
        ["CH01 RL02破甲齿", "power=R(AD)=270；每秒R(.08power)=22；4跳合计88", "power=R(1.5AD)=405；每秒R(.08power)=32；5跳合计160", "4/5秒；腐蚀护甲×.85；每跳取整后相加，非一次R(.32/.60AD)"],
        ["CH01 RL03回震砧", "盾R(.12MHP)=180；+1破势", "盾R(.18MHP)=270；+1破势", "原第三普攻发射计数；4秒；不新发装备shield_gain"],
        ["CH02 RL01分流弹匣", "2发各R(.4AD)=96；合计192", "2发各R(.6AD)=144；合计288", "±1.05rad、420射程/.65秒；2发不变20发"],
        ["CH02 RL02倒钩弹芯", "power=240；每秒R(.10power)=24；3跳72", "power=360；每秒36；3跳108", "流血3秒；独立快照，不复制原普攻暴击"],
        ["CH02 RL03追猎准星", "追加R(.35AD)=84；猎印P另300", "追加R(.525AD)=126；猎印P另300", "第三普攻；猎印4秒，W/R原始包消费；遗物附伤与猎印分开"],
        ["CH03 RL01共鸣棱镜", "每敌R(.4AP)=112", "每敌R(.6AP)=168", "135内最多2敌，排原目标；用AP280，不用skill376"],
        ["CH03 RL02余烬晶核", "无灼烧专属时power=280；每秒R(.12power)=34；3跳102", "power=420；每秒50；3跳150", "3秒；power另乘1+有效burn专属再R；直接B不复制"],
        ["CH03 RL03归流线圈", "回30法力，节点+1；主目标R(.35AP)=98", "回45法力，节点+2；主目标R(.525AP)=147", "原第三发；节点300内已展开/可见；目标死后回资源/充能仍可执行"],
    ]))
    out.append(table(["种族适配", "新版整数公式/示例", "不放大内容"], [
        ["B01晴辉→RL03", "每第3次有效普攻回10职业资源；有回复增益时R(10×[1+r])后容量截断", "有效root计数、ICD3秒；与RL03发射第三次分开"],
        ["B02琥珀→RL02", "DOT时长×1.20；CH01I/II=4.8/6秒，其余3.6秒；每跳整数金额按上表，完整跳数4/6/3", "时间小数不取整数；明确duration不再吃装备通用延时"],
        ["B03墓灯→战士RL03", "HP<35%时盾比例×1.20，Lv1I/II=R(.144/.216×1500)=216/324", "低血门槛35%，不是350%；其他职业无适配数字"],
        ["B04战寨→RL01", "触发距离≤160时系数×1.10；三职业I/II每敌分别119/178、106/158、123/185", "适配比例1.10、160距离与原目标上限不变"],
        ["未匹配配对", "额外战斗金额0", "材料/名称/主题不产生隐含Buff"],
    ]))
    out.append("来源：" + ref("scripts/combat/class_relics.gd", "static func _power") + "、" + ref("scripts/combat/class_relics.gd", "static func _emit_arc") + "、" + ref("scripts/combat/race_relics.gd", "static func confirmed_original_hit") + "。II级比例×1.5不再×10；示例是在最终比例与新主属性相乘后R。\n")
    out.append("## 6. 全部战斗状态、护盾与治疗的新版整数结算\n")
    out.append(table(["状态/池", "新版金额公式与示例", "接受/覆盖/计时规则保留"], [
        ["burn灼烧", "P=R(来源power×[1+min(1,burn专属)])，每完整秒R(.12P)魔法；法师Q的skill H376假设灼烧无专属时45/跳，+20%时P451→54/跳", "默认3秒；同族弱值拒绝，同强延时max，强值换新时长；不重置tick余量；Q原生是感电，不会自动附灼烧"],
        ["corrosion腐蚀", "P=R(来源power)，每秒R(.08P)物理；来源270时22/跳；防御护甲×.85", "默认4秒；原始直接增伤.08+corrosion专属进入总B100%加法桶，不另乘；不减魔抗"],
        ["bleed流血", "每秒R(.10P)物理；P240时24/跳", "默认3秒；完整秒计跳，3.6秒仍3跳；强值覆盖规则同状态族"],
        ["shock感电", "有效原始命中后消费旧快照，追加R(.25P)魔法；法师skill P376时94", "默认3秒、消费ICD1秒；新同击状态不追溯消费；不暴击/连击/递归；confirmed门槛按主方案"],
        ["chill寒冷", "没有伤害平值；普通敌移速×.8、Boss×.9、玩家×.75", "默认3秒；时长增幅池40%；倍率不×10；与slow独立"],
        ["slow减速", "最终移动保持原multiplier和slow_resistance公式", "默认.8；取最慢，持续时间max；不被当作chill触发专属装备"],
        ["grievous重伤", "战斗治疗R(accepted_heal×.6)；请求100且无限流/缺口时实得60", "40%减疗；默认3秒、状态power强制1仍不变10；安全补给按原安全规则"],
        ["brace_guard / damage_reduction", "独立状态族取强值，再与装备桶合成总≤65%", "状态power为比例0..65%，不×10；每来源独立时钟，不用弱长buff延长强减伤"],
        ["invulnerable显式无敌", "最终伤害0", "状态power标志1不变10；包括真伤与DOT；不等同闪避保护时间窗"],
        ["CombatStatus盾", "每源容量=min(max(旧整数容量,R(新MHP×ratio)),R(MHP×cap))；玩家cap.50/装备.35", "异源池max；扣盾同时扣各源，反馈仅一次；授予与刷新接受事件按主方案区分"],
        ["装备状态持续/延长", "原基础腐蚀4秒/其它3秒，×[1+min(.4,通用+适用专属)]；延长.30秒", "时间不放大，延长不重apply或重置H/tick；默认上限base×1.40"],
        ["战斗治疗", "R(请求金额×治疗倍率)，再截缺口；装备治疗另先受1秒R(.03MHP)预算", "死亡不复活；主方案accepted规则；同源ICD与事务顺序不改"],
        ["敌方来源/支持盾", "MHP比例容量基于新敌人整数生命；支持固定掩体HP35→350，clamp1..80变10..800", "支持盾双抗前串行、CombatStatus双抗后max；screen次数3仍3、上限4仍4；不能统乘所有支持参数"],
    ]))
    out.append("状态来源：" + ref("scripts/combat/combat_status.gd", "func apply") + "、" + ref("scripts/combat/combat_status.gd", "func grant_guard") + "；金额变换不移除敌人原型/Boss免疫、强值拒绝、计时余量和穿透/减伤顺序。盾/HP记录实际整数损失，不把过量/无敌包当成收益触发。\n")
    out.append("## 7. 补给、信标、装备共享限流与S06整数示例\n")
    out.append(table(["补给/设施", "新版整数公式", "Lv1 CH01 / CH02 / CH03示例", "保留价格/时间/限制"], [
        ["快速止血", "R(.15MHP)，截缺血", "225 / 165 / 158", "20金币；安全补给治疗规则，不与大治疗同买"],
        ["修整服务", "R(.35MHP)，截缺血", "525 / 385 / 368", "60金币；满血不能买；比例不另×10"],
        ["应急护盾", "R(.15MHP)", "225 / 165 / 158", "40金币；下一战斗房首个真实吸收后计4秒；离房清除"],
        ["便携增幅", "直接B+.08，不是平值攻击+80", "原始包额外×1.08，受B100%桶", "60金币，后续2战斗房，同offer不可重复"],
        ["勘探扫描", "战斗金额0", "0 / 0 / 0", "20金币，揭示路线，不虚构伤害收益"],
        ["跳过遗物", "R(.06MHP)安全治疗", "90 / 66 / 63", "安全事务，不触发战斗装备治疗；比例6%不变"],
        ["历史法力/能量补剂", "R(.30资源容量) / R(.20资源容量)", "法力300 / 能量200", "40/20金币历史；当前policy≥1不生成；整备免费满能/满法1000"],
        ["复苏信标", "R(.25MHP×有效治疗倍率)", "无重伤375/275/263；重伤225/165/158", "72接近范围、45秒刷新；真实正回血才消费"],
        ["源能信标", "R(.30资源容量)，无资源回复倍率", "默认每职业300", "有缺口才消费；不增加容量或回复率"],
        ["战意信标", "直接B+.20", "基础原始包×1.20，受B100%总桶", "15秒，同类刷新不叠加"],
        ["守护信标", "R(.25MHP)", "375 / 275 / 263", "15秒，room_prop:guard，多源max；切房清除"],
        ["迅行信标", "移速加法桶+.15，与装备/天赋/动态共cap.45", "裸装world220/255/230分别253/293.25/264.5", "12秒；世界移动允许小数，不为整数战斗金额"],
        ["敌方护盾插座", "R(新敌人MHP×guard_ratio)，默认.30，cap.50", "目标新MHP1000时默认300盾", "默认5秒、CD4秒；仅指定敌人，不是玩家补给"],
        ["节点充能设施", "新增电荷仍默认1", "不产生伤害/资源金额", "范围/视线/展开/3电荷上限保留"],
    ]))
    out.append(table(["共享规则", "新版整数/原单位公式", "Lv1示例/保持边界"], [
        ["装备回血预算", "滑动1秒总≤R(.03MHP)，候选治疗R(ratio×MHP)后裁剪剩余整数预算、缺口，再重伤", "CH01上限45；已治30，新请求30仅接受15，重伤后9；比例3%不变"],
        ["装备回资源EQ32", "desired=R((怒10/能20/法30)×[1+min(.30,资源回复)])；滑动5秒总≤R(.20容量)", "默认1000容量预算200；+30%回复时13/26/39；10/20/30为基础请求，不是放大后单次硬帽"],
        ["装备CD退款", "任意1秒合计≤.50秒；各请求.10/.15/.20/.25/.35等秒原值保留", "Q/W/E/R选择最长剩余冷却，dash独立；不能变5秒预算"],
        ["EQ56成本降低", "paid=0若免费；否则max(10,R(新base_cost×[1−min(.20,cost_reduction)]))", "8%窗口仍8%，战士W300→276；满3破势W保持0；窗口3秒支付成功才消费"],
        ["S06两件", "MHP比例+.10计60%桶；护盾下击退scale×1.20", "Lv1无其它生命比例CH01MHP1650；比例/世界击退不放大"],
        ["S06四件", "被动/E护盾accepted授予或刷新后B+.20", "4秒/ICD6秒；容量increased与accepted_refresh区分；不让装备派生盾递归触发"],
        ["S06六件", "护盾下满3破势W首次有效命中，每目标请求R(.6H_skill)物理", "Lv1H270请求162，最多3目标、ICD4秒、root一次；金额总≤floor(6X/5)，四包共享"],
        ["EQ38/EQ58替换条件", "EQ38有盾时请求R(.2X)；EQ58有盾时R(.02MHP)盾", "EQ58Lv1CH01=30盾/4秒、ICD6秒；不是治疗，不套回血预算"],
        ["其余固定装备/套装", "比例×新H/保存整数X/新整数MHP再R；真实附伤平值×10后最终聚合R", "其它固定机制、条件、ICD、目标上限不变；不乘品质/强化；全部96/42当前条目见装备册"],
        ["所有直接百分比桶", "暴率.75、暴伤2.50、攻速.80、移速.45、CDR.40、B1.00、装备DR.35/总DR.65、生命比例.60、状态延时.40、burn/corr1.00、资源回复.30", "这些上限沿主方案，完全不×10；旧CURRENT桶不是新目标桶"],
    ]))
    out.append("补给/信标来源：" + ref("scripts/core/run_controller.gd", "func purchase_run_supply") + "、" + ref("scripts/world/room_props.gd", "func move_multiplier") + "；装备限流来源：" + ref("scripts/combat/equipment_effects.gd", "func _restore_resource") + "、" + ref("scripts/combat/equipment_effects.gd", "func _refund") + "。金币与锻造材料仍由主方案经济公式计算，不能因为combat_scale把补给价格放大。\n")
    out.append("## 8. 实施与验收接口（本册责任范围）\n")
    out.append(table(["步骤", "需要落地的动作", "可复核结果"], [
        ["1", "集中定义combat_scale/R及整数金额类型，明确倍率/时间/坐标字段维度", "初始3角色表逐项匹配；35个spec字段分类齐全；R(.5)=1、R(1.5)=2"],
        ["2", "角色聚合完才取整，H分basic/skill/relic；敌人/装备按目标总表提供同单位属性", "Lv1法师AD180/AP280→basic278/skill376/relic280；抗性100→1000常数同步"],
        ["3", "技能cost/nodehealth平值转换；每段X/guard/DOTpower整数提交，保留264preview时序", "120关键等级行、12分支选择、264全组合与本册目标一致；解锁前仍不可施放"],
        ["4", "职业/遗物资源平值和正成本最低量转换，持续回复/衰减用累计整数差分", "180/50每秒跨30/60/144FPS一致；免费满势W=0；最低正成本10"],
        ["5", "固定Buff按新H/MHP计算、保留比例和计时；确认后消费/accepted status/accepted shield refresh落地", "无敌/零伤不消费标记或触发原始收益；EQ58仍护盾；节点/DOT不重新暴击"],
        ["6", "整数限流与派生预算最后裁剪，保持4触发包和不递归", "整数金额总≤floor(6X/5)，用整数(6×X)//5；装备回血/资源滑动窗口预算不被多包四舍五入突破"],
        ["7", "面板/日志显示最终整数、源H/X、已接受金额与被限流原因；存档迁移按主方案逐步清单", "当前数据/真实玩家档在本PR保持未改；实现PR以此表为接受目标，另做自然战斗/经济验收"],
    ]))
    out.append("上述是未来实现顺序及验收目标。当前生成器仅计算文档，不运行战斗、不读取玩家档、不修改data/scripts/config；不得将标准库检查成功表述为整套游戏重构已完成。\n")
    out.append("## 9. 264个全等级完整目标预览\n\n每条保留原完整spec及timeline结构，cost/health已换整数单位；target JSON明确各类H/每包damage/shield/heal/resource金额。state_power列是候选来源H，只有实际登记状态才施加，不表示所有技能新增DOT。\n\n<!-- TARGET_SKILL_ROWS_START -->\n")
    out.append(table(["角色", "等级", "槽", "分支", "新cost", "新H_skill", "完整新spec", "整数target金额", "原timeline"], [[r["hero"], r["level"], r["slot"], r["branch"] or "默认", r["spec"]["cost"], r["target"]["skill_H"], r["spec"], r["target"], r["timeline"]] for r in targets]))
    out.append("<!-- TARGET_SKILL_ROWS_END -->\n\n## 10. 生成与来源指纹\n\n命令：`python tools/balance/render_target_hero_skill_buffs.py`；一致性检查：`python tools/balance/render_target_hero_skill_buffs.py --check`。检查覆盖字段维度、264唯一组合、120关键等级、12分支选择、整数非负金额、初始属性、关键四舍五入例与全册表格列数；不宣称战斗/经济已验收。\n")
    out.append(table(["输入来源", "SHA-256"], [[str(p.relative_to(ROOT)).replace("\\", "/"), hashlib.sha256(p.read_bytes()).hexdigest()] for p in INPUTS]))
    result = "\n".join(out).rstrip() + "\n"
    validate(targets, result, c, heroes)
    return result


def validate(rows, text, c, heroes):
    if (R(".5"), R("1.5"), R("1057.5")) != (1, 2, 1058):
        raise ValueError("Half-up integer rule failed")
    expected_initial = {
        "CH01": (1500, 270, 0, 200, 120, 200, 1000, 0),
        "CH02": (1100, 240, 0, 80, 100, 1000, 1000, 180),
        "CH03": (1050, 180, 280, 60, 180, 1000, 1000, 50),
    }
    for hero, expected in expected_initial.items():
        stats = hero_stats(c, heroes[hero], 1)
        if tuple(stats[k] for k in ("max_hp", "attack", "ability_power", "armor", "magic_resist", "starting_resource", "resource_max", "resource_regen")) != expected:
            raise ValueError(f"Confirmed initial stats changed: {hero}")
    if hero_stats(c, heroes["CH01"], 20)["attack"] != 475 or hero_stats(c, heroes["CH01"], 20)["max_hp"] != 2925:
        raise ValueError("Confirmed level growth changed")
    if (c["growth"]["armor"], c["growth"]["magic_resist"]) != (10, 8):
        raise ValueError("Resistance growth must already use the new 10x units")
    if R(d(".25") * 1103 * d(".6")) != 165:
        raise ValueError("Ordinary healing must combine magnitude and healing multiplier before rounding")
    if sum(r["level"] in KEY_LEVELS and not r["branch"] for r in rows) != 120:
        raise ValueError("Missing one of the 120 default key-level summaries")
    if sum(r["branch"] in ("A", "B") and ((r["slot"] == "q" and r["level"] == 18) or (r["slot"] == "ultimate" and r["level"] == 20)) for r in rows) != 12:
        raise ValueError("Missing one of the 12 branch choices")
    money_keys = ("basic_H", "skill_H", "relic_H", "maximum_hp", "cost", "damage_each", "damage_total_base", "original_damage_each", "original_damage_total_base", "shield_amount", "heal_amount", "resource_refund", "state_power", "node_health")
    originals = {(r["hero"], r["level"], r["slot"], r["branch"]): r for r in read_preview()}
    for row in rows:
        for key in money_keys:
            if not isinstance(row["target"][key], int) or row["target"][key] < 0:
                raise ValueError(f"Noninteger/negative magnitude: {row['hero']} {key}")
        old = originals[row["hero"], row["level"], row["slot"], row["branch"]]
        for key, value in old["spec"].items():
            if key not in ("cost", "health") and row["spec"][key] != value:
                raise ValueError(f"Unscaled skill parameter changed: {key}")
        if row["timeline"] != old["timeline"]:
            raise ValueError("Current skill timing changed")
    expected_columns = None
    table_count = 0
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.startswith("|"):
            expected_columns = None
            continue
        columns = line.count("|") - 1
        if expected_columns is None:
            expected_columns = columns
            table_count += 1
        elif columns != expected_columns:
            raise ValueError(f"Bad Markdown table width at line {line_number}")
    return table_count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    c = json.loads(PARAMS.read_text(encoding="utf-8-sig"))
    heroes = json.loads(HERO_PATH.read_text(encoding="utf-8-sig"))
    result = render(c, heroes, read_preview())
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != result:
            raise SystemExit("CHECK FAILED: target skill/buff document differs from current inputs; regenerate")
        print("CHECK OK: 264 unique target previews; 120 key-level rows; 12 branch choices; 35 typed spec fields; integer magnitudes and Markdown tables")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(result, encoding="utf-8", newline="\n")
        print(f"WROTE {OUTPUT}: 264 target previews, 120 key-level rows, 12 branch choices")


if __name__ == "__main__":
    main()
