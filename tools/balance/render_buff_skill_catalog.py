#!/usr/bin/env python3
"""Render the current, source-grounded buff/skill appendix using standard Python.

The optional skill JSON comes from export_buff_skill_catalog.gd, run in an empty
Godot project with no autoloads. --check can recover those exact preview rows
from the checked-in appendix; every input source fingerprint is revalidated.
No profile, runtime content, or gameplay source is read through Game or changed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs/balance/CURRENT_BUFF_SKILL_CATALOG.md"
SNAPSHOT = "8daa519f2ea1a7dcc3f422b4df96ac81d65986b9"
INPUTS = [
    "data/heroes.json", "scripts/combat/hero_abilities.gd",
    "scripts/combat/hero_passives.gd", "scripts/combat/player.gd",
    "scripts/combat/class_relics.gd", "scripts/combat/race_relics.gd",
    "scripts/combat/combat_status.gd", "scripts/combat/hit_chain.gd",
    "scripts/combat/stat_resolver.gd", "scripts/combat/damage_resolver.gd",
    "scripts/combat/equipment_effects.gd", "scripts/combat/combat_loadout.gd",
    "scripts/combat/hero_deployment.gd", "scripts/combat/projectile.gd",
    "scripts/combat/room.gd", "scripts/combat/enemy.gd",
    "scripts/combat/enemy_biome_skills.gd", "scripts/combat/enemy_skill_runtime.gd",
    "scripts/combat/boss.gd", "scripts/combat/boss_brain.gd",
    "scripts/core/expedition_state.gd", "scripts/core/run_controller.gd",
    "scripts/world/room_props.gd", "scripts/combat/resonance_circuit.gd",
    "scripts/core/control_bindings.gd", "config/balance.gd",
]
SOURCES = {p: (ROOT / p).read_text(encoding="utf-8-sig") for p in INPUTS}
HEROES = json.loads(SOURCES["data/heroes.json"])
LEVELS = [1, 2, 3, 4, 10, 12, 14, 16, 18, 20]
KEY_NAMES = {
    "name":"名称", "cost":"资源消耗", "cooldown":"实际冷却(s)",
    "base_cooldown":"基础冷却(s)", "windup":"前摇(s)", "duration":"动作总时长(s)",
    "travel":"位移距离", "travel_time":"位移时长(s)", "coefficient":"每段伤害/H",
    "radius":"半径", "knockback":"击退", "movement":"施放时移动倍率",
    "arc":"扇形角度(度)", "guard":"护盾/最大生命", "guard_duration":"减伤时长(s)",
    "damage_reduction":"独立战吼减伤", "range":"射程/落点范围", "speed":"弹速",
    "pierce":"额外穿透敌人数", "pierce_multiplier":"后续目标伤害倍率",
    "fuse":"榴弹引信(s)", "shots":"发数", "health":"节点生命",
    "explosion_radius":"爆炸半径", "tick_coefficient":"每秒跳伤/H",
    "lifetime":"部署持续时间(s)", "waves":"波数", "echo_along_path":"沿途节点回声",
    "follow_player":"跟随角色", "unlock":"解锁等级", "damage_type":"伤害类型",
}

def cell(value):
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    elif isinstance(value, float):
        value = f"{value:.8g}"
    elif isinstance(value, bool):
        value = "true" if value else "false"
    return str(value).replace("|", "&#124;").replace("\r", "").replace("\n", "<br>")

def table(headers, rows):
    rows = list(rows)
    for index, row in enumerate(rows, 1):
        if len(row) != len(headers):
            raise ValueError(f"Table {headers!r}, row {index}: expected {len(headers)} cells, got {len(row)}")
    return "\n".join(["| " + " | ".join(map(cell, headers)) + " |",
                      "| " + " | ".join("---" for _ in headers) + " |"] +
                     ["| " + " | ".join(map(cell, row)) + " |" for row in rows]) + "\n"

def validate_table_layout(text):
    """Check every table row against its header, counting unescaped pipes."""
    expected = None
    count = 0
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.startswith("|"):
            expected = None
            continue
        separators = 0
        backslashes = 0
        for character in line:
            if character == "|" and backslashes % 2 == 0:
                separators += 1
            backslashes = backslashes + 1 if character == "\\" else 0
        columns = separators - 1
        if expected is None:
            expected = columns
            count += 1
        elif columns != expected:
            raise ValueError(f"Markdown table line {line_number}: expected {expected} columns, got {columns}")
    return count

def ref(path, needle):
    lines = SOURCES[path].splitlines()
    index = next((i for i, line in enumerate(lines, 1) if needle in line), None)
    if index is None:
        raise ValueError(f"Missing source anchor {path}: {needle}")
    return f"[{Path(path).name}:{index}](../../{path}#L{index})"

def block(title, headers, rows):
    return f"\n## {title}\n\n" + table(headers, rows)

def raw_rows_from_document(text):
    part = text.split("<!-- SKILL_PREVIEW_ROWS_START -->", 1)[1].split("<!-- SKILL_PREVIEW_ROWS_END -->", 1)[0]
    result = []
    for line in part.splitlines():
        if not line.startswith("| CH0"):
            continue
        cells = [x.strip() for x in line.strip("|").split("|")]
        hero, level, slot, branch, spec, timeline = cells
        result.append({"hero":hero, "level":int(level), "slot":slot,
                       "branch":"" if branch == "默认" else branch,
                       "spec":json.loads(spec), "timeline":json.loads(timeline)})
    return {"format":1, "rows":result}

def validate(rows):
    keys = [(r["hero"], r["level"], r["slot"], r["branch"]) for r in rows]
    expected = [(h,l,s,b) for h in ["CH01","CH02","CH03"] for l in range(1,21)
                for s in ["q","secondary","f","ultimate"]
                for b in (["","A","B"] if (s=="q" and l>=18) or (s=="ultimate" and l>=20) else [""])]
    if sorted(keys) != sorted(expected) or len(keys) != 264:
        raise ValueError("Skill preview must cover 264 unique runtime combinations")
    for row in rows:
        spec = row["spec"]
        if spec["unlock"] != HEROES[row["hero"]]["skills"][row["slot"]]["unlock"]:
            raise ValueError("Skill unlock differs from current registry")
        if spec["base_cooldown"] != spec["cooldown"]:
            raise ValueError("Unbuffed catalog contains CDR")
        if not all(0 <= event["time"] <= spec["duration"] + .00001 for event in row["timeline"]):
            raise ValueError("Timeline outside committed action")

def numerical_ledger():
    """All numeric/arithmetic behavior branches, excluding art and separate catalogs.

    This is intentionally a source appendix, not a guessed formula parser.
    Function and enclosing conditional context preserve the actual branch.
    """
    selects = {
        "scripts/combat/equipment_effects.gd": {"_empty","_eligible","_basic","_health_ratio","_shop_condition","_cap_modifiers","skill_cost","_root","reserve_native","root_usage","_ready","_activate","_buff","_window","_nth","_consecutive","_status","_extend","_shield","_heal","_restore_resource","_refund","_bonus","_prune_history","_history_total"},
        "scripts/combat/room.gd": {"fire_from_player","spawn_projectile","resolve_weapon_hit","strike_area","resolve_direct_hit","resolve_derived_hit","_prepare_relics","_relic_rank_multiplier","_emit_reserved_relics","spawn_ability_projectile","add_deployment","node_echo"},
        "scripts/core/run_controller.gd": {"damage_player","_damage_reduction","heal_player","_healing_gain","try_spend_resource","restore_resource","purchase_run_supply","prepare_safe_resources","advance_expedition_node","commit_expedition_completion","choose_run_relic"},
        "scripts/core/expedition_state.gd": {"add_supply_offers"},
        "scripts/world/room_props.gd": {"damage_bonus","move_multiplier","resource_regen_multiplier","grant_buff","utility","_polarity_displacement","displacement_ready","record_displacement","_update_beacon","_refresh_beacon","_roll_beacon_effect","update"},
        "scripts/combat/enemy.gd": {"take_damage","apply_biome_counter","biome_weakpoint_open","effective_armor","biome_counter_status","heal","apply_burn","apply_status","tick_statuses","apply_knockback"},
        "scripts/combat/boss.gd": {"configure_boss","configure","take_damage","apply_counter"},
        "scripts/combat/boss_brain.gd": {"incoming_damage_multiplier","outgoing_damage_multiplier","apply_arena_counter","_release","_phase_for_ratio","_update_weakpoint","_open_weakpoint","_counter_weakpoint","apply_biome_counter","_enter_phase","movement_speed"},
        "scripts/combat/enemy_skill_runtime.gd": {"emit_skill","advance","movement_multiplier","consume_scan_mark","filter_incoming_damage","_support","_release_counter","_blood_rage_active","_biome_signature","_apply_biome_hit","_execute","clear_target_guards","_deal","_scan_mark","_pod_disarmed","_pull"},
        "scripts/core/control_bindings.gd": {"install"},
    }
    rows = []
    for path in INPUTS:
        if not path.endswith(".gd") or path == "scripts/combat/stat_resolver.gd":
            continue
        function = "常量/默认值"
        conditions = []
        for number, line in enumerate(SOURCES[path].splitlines(), 1):
            match = re.match(r"(?:static )?func ([\w]+)\(", line)
            if match:
                function = match[1]
                conditions = []
            if line.lstrip().startswith("#") or "preload(" in line:
                continue
            if function.startswith(("_draw", "draw_", "_play_", "_emit_feedback", "_display_", "visual_", "_deployment_")):
                continue
            if path in selects and function not in selects[path] and function != "常量/默认值":
                continue
            indent = len(line) - len(line.lstrip("\t"))
            conditions = [(depth, text) for depth, text in conditions if depth < indent]
            stripped = line.strip()
            if stripped.startswith(("if ", "elif ", "else:", "match ", "for ")) and stripped.endswith(":"):
                conditions.append((indent, stripped))
            without_strings = re.sub(r'"(?:\\.|[^"\\])*"', '""', stripped)
            has_number = re.search(r"(?<![\w])(?:\d+(?:\.\d+)?|\.\d+)(?![\w])", without_strings)
            arithmetic = re.search(r"(?:\+=|\*=|\-=|/=|\s[+*/-]\s)", without_strings)
            if stripped and (has_number or arithmetic):
                rows.append([f"[{Path(path).name}:{number}](../../{path}#L{number})", function,
                             " → ".join(text for _,text in conditions) or "—", "`" + stripped.replace("`", "") + "`"])
    return rows

def render(preview):
    rows = preview["rows"]
    validate(rows)
    lookup = {(r["hero"],r["level"],r["slot"],r["branch"]):r for r in rows}
    out = ["# 当前技能、Buff与伤害结算数值总表（现状附录草稿）\n",
           f"基线源码快照：`{SNAPSHOT}`。整理日期：2026-10-01。\n",
           "本文记录当前运行代码的实际数值，不是重构后的批准设计。尚未改动运行数据、战斗脚本或玩家存档。[装备与角色现状附录](CURRENT_HERO_EQUIPMENT_CATALOG.md)维护96个固定装备模板、14套装和基础成长；[敌人/Boss现状附录](CURRENT_ENEMY_BOSS_CATALOG.md)维护基值和招式全表。本文完整登记它们共享的Buff、伤害结算、触发预算和技能联动。未来参数见[待确认方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)及[目标数值表](TARGET_NUMERICAL_TABLES.md)。\n",
           "技能表来自Godot 4.7.2在**无主场景、无autoload**隔离项目中编译原文 `spec/_branch/_apply_branch/_timeline` 后的264条实际预览；它不加载Game，不读取真实玩家档。其他表来自下列源码表达式的静态梳理。文末保留所有覆盖源的SHA-256和数值分支索引，不能把显示文案当作已实现逻辑。\n",
           "单位：世界距离沿当前战斗坐标；秒为游戏内未暂停时间；`0.08=8%`，暴击率`+0.03`指增加3个百分点。`AD`为当前攻击，`AP`为法强，`MHP`为最大生命，`X`为原始直接包金额，`H`按来源分开定义。\n"]
    out.append(block("1. H、X与属性口径", ["来源", "实际计算", "边界/来源"], [
        ["三职业普攻", "H=AD；X=AD；法师普攻为魔法类型但不加入AP", ref("scripts/combat/player.gd","func attack_power")+"；"+ref("scripts/combat/room.gd","func fire_from_player")],
        ["战士/枪手直接技能", "H=AD；X=技能系数×H", ref("scripts/combat/player.gd","func skill_power")],
        ["法师直接技能/节点/领域", "H=AD+0.7×max(0,AP)；X=各自技能系数×H", ref("scripts/combat/player.gd","func skill_power")],
        ["法师职业遗物RL01/RL02/RL03", "独立遗物威力=AP；不使用AD+0.7AP", ref("scripts/combat/class_relics.gd","static func _power")],
        ["装备状态/派生附伤", "状态power取原攻击上下文H；派生伤害取saved X×接受系数", ref("scripts/combat/equipment_effects.gd","func _bonus")],
        ["X的保存时机", "职业猎印/被动额外伤害、普通增伤、暴击、连击之前保存", ref("scripts/combat/room.gd",'"X":amount')],
        ["等级成长（现状）", "g=(clamp(L,1,20)-1)/19；攻击=AD₁(1+0.10g)，AP=AP₁(1+0.20g)，MHP=HP₁(1+0.20g)，护甲/魔抗=基础+6g；再加装备", ref("scripts/combat/stat_resolver.gd","var growth")],
        ["百分比池", "装备平坦值先相加；增伤/攻速等池内相加并封顶；最终独立倍率相乘", "完整封顶见第7节；未来方案需要另行批准"],
    ]))
    out.append("\n## 2. 十二技能基础收益、阶段升级与分支\n\n当前Q/W/E/R解锁等级为1/2/3/4；Q分支18级，R分支20级。当前不是8/16级永久分支。下表不包含装备、暴击、连击、敌人抗性和额外职业追加包。\n\n")
    summaries = {
        "CH01:q":"单次1.5H；命中获得1破势；位移160；10级消耗20→15。",
        "CH01:secondary":"单次(2.2+0.45×破势)H；3层3.55H且免30怒、半径140、击退90、扇形160°。",
        "CH01:f":"单次0.6H；无须命中也得1破势；护盾12%MHP/4s，14级18%；另25%减伤1.5s。",
        "CH01:ultimate":"(4.0+0.60×破势)H；16级基础4.6H；3层+半径30/击退25。",
        "CH02:q":"3发×0.35H=1.05H；退移150；10级消耗25→20；默认发射间隔0.06s。",
        "CH02:secondary":"主目标2H；额外穿透1敌×65%=1.3H；12级后次目标2H。",
        "CH02:f":"0.65s引信后1.1H；命中施加4s猎印；半径110，14级130。",
        "CH02:ultimate":"4发×1.2H=4.8H；16级移动45%→70%；各发间隔0.24s。",
        "CH03:q":"圆形爆炸1.25H+感电；90内节点回声0.35H，每敌每施放最多一次；10级弹速650→850。",
        "CH03:secondary":"节点0.15H/1.2s，14s最多11次=1.65H；0.35s展开，首发1.55s；35HP，12级50HP；最多2节点。",
        "CH03:f":"自身0.8H+寒冷；引爆260内节点，每节点(1+0.65×电荷)H；2个满能节点另5.9H，总6.7H；14级CD11→9。",
        "CH03:ultimate":"建场0.6H感电+5跳×0.8H=4.6H；每跳1s寒冷；16级半径180→210；建场充满场内展开节点。",
    }
    skill_rows=[]
    for hero in ["CH01","CH02","CH03"]:
        for slot in ["q","secondary","f","ultimate"]:
            spec=lookup[hero,1,slot,""]["spec"]
            skill_rows.append([hero+" "+HEROES[hero]["class_name"],spec["input"]+" "+spec["name"],spec["unlock"],spec["cost"],spec["cooldown"],summaries[hero+":"+slot]])
    out.append(table(["职业","技能","解锁级","基础资源","基础CD(s)","有效收益与限制"],skill_rows))
    out.append("\n### 2.1 所有等级关键参数（Godot实际预览）\n\n解锁前也列出定义值，但实际施放仍被unlock门槛阻止。`—`表示该技能没有这个参数。没有分支时列原始定义；A/B覆盖项见2.2。所有CD列使用0冷却缩减；实际CD=基础CD×[1−clamp(CDR,0,0.30)]。\n")
    for hero in ["CH01","CH02","CH03"]:
        for slot in ["q","secondary","f","ultimate"]:
            specs=[lookup[hero,level,slot,""]["spec"] for level in LEVELS]
            keys=sorted(set().union(*(s.keys() for s in specs)) - {"hero","slot","input","branch","name"})
            out.append(f"\n#### {hero} {specs[0]['input']} {specs[0]['name']}\n\n")
            out.append(table(["参数"]+["L"+str(l) for l in LEVELS], [[KEY_NAMES.get(key,key)]+[s.get(key,"—") for s in specs] for key in keys]))
            out.append("\n实际出手时间(s，自提交起)："+"；".join(f"L{level}={cell(lookup[hero,level,slot,'']['timeline'])}" for level in LEVELS)+"。\n")
    out.append("\n### 2.2 分支全部参数\n\n下表展示解锁等级的默认/A/B完整参数，不只展示改动字段。未列出的职业临时破势加成在正式施放提交后才加入。\n")
    for hero in ["CH01","CH02","CH03"]:
        for level,slot in [(18,"q"),(20,"ultimate")]:
            specs=[lookup[hero,level,slot,b]["spec"] for b in ["","A","B"]]
            keys=sorted(set().union(*(s.keys() for s in specs)) - {"hero","slot","input","branch","name"})
            definition=HEROES[hero]["branches"][str(level)]
            out.append(f"\n#### {hero} L{level} {specs[0]['input']}\n\n")
            out.append(table(["参数","默认","A "+definition["A"]["name"],"B "+definition["B"]["name"]],[[KEY_NAMES.get(k,k)]+[s.get(k,"—") for s in specs] for k in keys]))
            out.append(table(["分支","实际出手timeline","设计表原文说明"],[[b or "默认",lookup[hero,level,slot,b]["timeline"],definition[b]["description"] if b else "默认主技能"] for b in ["","A","B"]]))
    out.append("\n战士R分支B的破势增量加在**每一波**：3层时每波(1.9+3×0.6)H=3.7H，两波全中7.4H；A三层(5.4+1.8)H=7.2H。枪手Q的1.05/0.75/1.65H均是假设3发全中同敌；R A主目标6H、额外穿透目标最多4.2H。法师R A最大5.15H，B最大3.2H；领域0秒没有额外免费跳伤，最后整数秒先结算再到期。\n")
    out.append(block("3. 职业被动、资源与节点",["类别","触发/数值","时长/冷却/覆盖规则","来源"],[
        ["战士 三铆护甲","每3次有效原始普攻root得8%MHP护盾","3s护盾；6s ICD；冷却中不积攒；同挥击多敌只计一次",ref("scripts/combat/hero_passives.gd","if _hero == \"CH01\":")],
        ["战士 破势","有效普攻+1、Q命中+1、E出手+1、RL03每第三普攻+1；上限3","W/R提交即消费，取消后不返；W每层+0.45H，R+0.60H；满3层W资源消耗=0",ref("scripts/combat/player.gd","func gain_break_stacks")],
        ["战士 怒气","有效普攻+8；实际HP受伤+5","受伤回怒ICD1s；脱战5s后每秒−6；仅盾伤不回5怒",ref("scripts/combat/player.gd","Game.restore_resource(5.0)")],
        ["枪手 两发校准","同目标2次有效普攻，下一原始普攻或直接技能追加0.65H","焦点5s；消费后ICD2s；更换目标重新记1；消费需生命/护盾真实损失",ref("scripts/combat/hero_passives.gd","func before_hit")],
        ["枪手 猎印（独立于两发校准）","E真实命中、RL03第三普攻产生猎印；W/R命中消费另加1.25H","猎印4s；最多登记32目标；与两发校准可同次追加1.90H；源代码在伤害前消费猎印",ref("scripts/combat/player.gd","func class_modify_hit_amount")],
        ["法师 交响回路","有效原始普攻/成功技能交替加1，首行动1，最多3；满层后的下次成功技能回8法力，260内最近未满展开节点+1电荷","进度8s；触发ICD2s期间不积攒；空放合法技能可积攒，失败提交不计；多波不重复",ref("scripts/combat/hero_passives.gd","func skill_committed")],
        ["能量/法力恢复","能量18/s；法力5/s；可读装备后的resource_regen","成功技能之后枪手延迟0.5s，法师0.8s；实际与data中resource_regen_delay列对照",ref("scripts/combat/player.gd","var regen_step")],
        ["法晶电荷","0–3；Q经过90内每节点每施放+1；R建场范围内+3；交响回路最近节点+1；RL03范围300内+1/2","只有展开且视线可达节点；不存超量电荷",ref("scripts/combat/hero_deployment.gd","func charge_node")],
        ["法晶引爆","层0/1/2/3：伤害1/1.65/2.3/2.95H，半径100/120/140/160","E连接260；销毁先提交；两节点爆炸可叠加；派生无暴击/连击/感电消费/装备命中链",ref("scripts/combat/hero_deployment.gd","func detonate")],
        ["法晶回声","Q爆心/穿相路径90内节点发半径70、0.35H回声","同敌同次施放最多一次；无感电、不触发原始命中或递归",ref("scripts/combat/room.gd","func node_echo")],
        ["法晶维持","最多2；0.35s展开，14s寿命，第一次攻击t1.55，之后每1.2s","最多11射；每次稳定最近1个视线可达敌；换第三节点退休最早节点、不返费/不免费引爆",ref("scripts/combat/hero_deployment.gd","next_attack = 1.0")],
        ["施放事务","验证→支付资源→破势消费→设CD→记录被动→创建固定timeline","取消只丢未出手事件；已发射/部署/消耗/冷却不撤回；技能系数/威力/攻击属性在提交时快照",ref("scripts/combat/hero_abilities.gd","func try_cast")],
    ]))
    out.append(block("4. 连击与闪避/受击保护",["机制","数值","实际作用与来源"],[
        ["命中连击","最多100层；每层0.005；倍率1+层×0.005，上限1.5","原始普攻/直接技能，真实HP或盾损失后+1；当前包用接触前层数；同attack_id多敌共用倍率。"+ref("scripts/combat/hit_chain.gd","func multiplier")],
        ["断连","4s无有效命中归零","暂停不流逝；ID账本最多256条；旧穿透包不能在断连后再计一次。"+ref("scripts/combat/hit_chain.gd","func record_hit")],
        ["五档提示","10/25/50/75/100层=+5/+12.5/+25/+37.5/+50%","只是对应已有连续增伤，不额外提供一份里程碑Buff。"+ref("scripts/combat/hit_chain.gd","const MILESTONES")],
        ["战士闪避","110距离/0.18s；CD2.2s；保护[0,0.10)s","免费；不受装备主动CD缩减；装备退还dash秒数可影响。"+ref("scripts/combat/player.gd","func start_dash")],
        ["枪手闪避","160距离/0.22s；CD2.0s；保护[0.04,0.16)s","免费；普通移动与闪避分别检测。"+ref("scripts/combat/player.gd","func dash_protected")],
        ["法师闪避","第0.08s移130；动作0.18s；CD2.6s；保护[0.08,0.18)s","免费；按合法地面裁切。"+ref("scripts/combat/player.gd","func _tick_dash")],
        ["受击保护","普通直接受击设置0.65s无敌间隔","DOT绕过受击与闪避保护，显式invulnerable状态仍阻止DOT；击退120，衰减660/s。"+ref("config/balance.gd","const HURT_INVULNERABILITY")],
    ]))
    out.append(block("5. 三遗物×职业×等级及四族适配",["职业","遗物","I级","II级","范围/频率/规则"],[
        ["CH01","RL01裂地楔","额外最多3敌，每敌0.4AD物理","每敌0.6AD物理","主普攻命中后；以玩家为中心200内，前方半角55°；排除原目标"],
        ["CH01","RL02破甲齿","腐蚀power=AD；每秒0.08AD，4s","power=1.5AD；每秒0.12AD，5s","护甲×0.85；DOT基础合计0.32AD/0.60AD；有效普攻刷新快照"],
        ["CH01","RL03回震砧","12%MHP护盾4s、+1破势","18%MHP护盾4s、+1破势","每第三次普攻计数root；派生护盾不重新发装备shield_gain"],
        ["CH02","RL01分流弹匣","2扇弹每发0.4AD物理","每发0.6AD物理","与方向±1.05rad；射程420，寿命0.65s；不再次派生"],
        ["CH02","RL02倒钩弹芯","流血power=AD；每秒0.10AD/3s","power=1.5AD；每秒0.15AD/3s","基础DOT总0.30AD/0.45AD"],
        ["CH02","RL03追猎准星","第三普攻追加0.35AD并猎印4s","追加0.525AD并猎印4s","W/R消费猎印额外1.25H独立计算；显示文案仍写右键或R，实际是secondary/W和R"],
        ["CH03","RL01共鸣棱镜","额外最多2敌，每敌0.4AP魔法","每敌0.6AP魔法","主命中位置135内，排除原目标；不使用法师技能H"],
        ["CH03","RL02余烬晶核","灼烧power=AP；0.12AP/s、3s","power=1.5AP；0.18AP/s、3s","另乘(1+burn_damage)；基础DOT总0.36AP/0.54AP"],
        ["CH03","RL03归流线圈","第三普攻回3法力，300内节点+1，主目标追加0.35AP","回4.5法力，节点+2，追加0.525AP","节点需展开、可见；追加目标死亡则不再追加，资源/充能仍可执行"],
    ]))
    out.append("\n来源："+ref("scripts/combat/class_relics.gd","static func apply_reserved")+"、"+ref("scripts/combat/room.gd","func _prepare_relics")+"。RL01/02/03按I/II级（rank clamp1..2），II统一系数×1.5，RL04–RL12只有预留ID，当前未开放实际效果。第三普攻RL03使用现有shots%3判断（发射计数），不等同职业被动的三次有效命中；分流/感电/额外命中不会消费新的遗物根预算。\n\n")
    out.append(table(["副本","适配通道","真实增益","叠加边界"],[
        ["B01晴辉","RL03/arc，三职业","每第3次有效普攻root回复1职业资源；ICD3s","独立有效命中计数，不覆盖RL03原生第三发效果"],
        ["B02琥珀","RL02/ember，三职业","原生DOT持续时间×1.20","战士4→4.8、II5→6；枪手/法师3→3.6；完整秒跳数决定实际总伤害；明确duration时不再加装备通用时长"],
        ["B03墓灯","RL03/arc，仅战士","HP<35%时原回震护盾量×1.20","I14.4%MHP、II21.6%；不加时长、不叠加容量；其他职业无附加战斗数值"],
        ["B04战寨","RL01/split，三职业","触发位置距角色≤160，分流伤害×1.10","I每目标0.44主属性、II0.66；最大触发距离与受击目标范围不同"],
        ["其余配对","所有未匹配通道","无额外数值效果","材料主题/名称装饰不产生战斗加成"],
    ]))
    out.append("\n"+ref("scripts/combat/race_relics.gd","static func confirmed_original_hit")+"。全部遗物派生包强制proc_depth=1、equipment_eligible=false、original_basic=false、critical=false；同root同通道只执行一次，账本最多256root。RL02一律传入职业/种族计算后的显式正duration，因此当前这三种原生遗物DOT不再吃装备通用status_duration；普通技能未显式duration的状态才走该默认时长加成。\n")
    out.append(block("6. 状态、护盾与治疗完整规则",["状态/池","数值公式","持续/覆盖/免疫规则","来源"],[
        ["灼烧 burn","每完整秒0.12×snapshot power，魔法；玩家施加敌人时power*=1+burn_damage","默认3s；同族不相加；强度更弱连时长也拒绝；同强度时长取max；强度更高替换新时长；沿用tick余量",ref("scripts/combat/combat_status.gd","func apply")],
        ["腐蚀 corrosion","每完整秒0.08power，物理；目标有效护甲×0.85；直接原始命中额外增伤8%+corrosion_damage_bonus","默认4s；额外增伤占直接60%池；腐蚀不会降低魔抗；玩家被腐蚀受直接攻击incoming×1.08，DOT不加该8%",ref("scripts/combat/player.gd","incoming *= 1.08")],
        ["流血 bleed","每完整秒0.10power，物理","默认3s；tick按完整有效秒，不把3.6s补成4跳",ref("scripts/combat/combat_status.gd","var coefficient")],
        ["感电 shock","下一原始直接命中消费旧感电，另造成0.25power魔法包","默认3s；消费ICD1s；不暴击/不产生递归；此击新感电在消费后施加；派生节点/领域不消费",ref("scripts/combat/combat_status.gd","func consume_shock")],
        ["寒冷 chill","普通敌人移动×0.80；Boss×0.90；玩家×0.75","默认3s；与普通slow分开；状态时长增幅上限40%；S03另20%也共用40%池",ref("scripts/combat/enemy_skill_runtime.gd","func movement_multiplier")],
        ["普通 slow","玩家普通slow取最小multiplier，再与chill取更慢值","默认magnitude0.8；刷新remaining=max(原,新)；不触发chill专用装备；最终减速×(1−slow_resistance)",ref("scripts/combat/player.gd",'if identifier == "slow"')],
        ["重伤 grievous","治疗实际amount×0.60（降低40%）","默认3s；power强制1；作用于战斗治疗和敌人吸血；安全补给_healing_gain默认multiplier1",ref("scripts/combat/combat_status.gd","func healing_multiplier")],
        ["独立减伤","damage_reduction与brace_guard同源族各保时钟，生效取max；状态值clamp0..0.65","不把强效果持续期延长到弱长Buff；玩家装备减伤+动态装备减伤+状态减伤合计最终65%",ref("scripts/combat/combat_status.gd","func damage_modifiers")],
        ["显式无敌","invulnerable强制power1，最终damage=0","阻止物理/魔法/真实与DOT；与闪避时间窗分开",ref("scripts/combat/damage_resolver.gd","if immune:")],
        ["来源护盾","单源new amount=min(max(旧容量,新容量),MHP×cap)，cap装备35%，其他50%","同源刷新自己的duration；异源生效=max容量，不相加；每次吸收的消耗同时从所有来源扣一次；反馈只记一次",ref("scripts/combat/combat_status.gd","func grant_guard")],
        ["装备状态时长","腐蚀4，其余3；duration=base×[1+min(0.40,通用+S03寒冷0.20)]","派生寒冷不加S03原始专属20%；延长类每次+0.30s，上限base×1.40；不重新apply、不重置tick/H",ref("scripts/combat/equipment_effects.gd","func _status")],
        ["燃伤快照","power=原power×[1+当前burn_damage]；保存原H归因","装备burn_damage上限60%；现状敌人apply_status对CombatStatus.apply拒绝弱状态仍return true，确认归因存在差异，重构需修正",ref("scripts/combat/enemy.gd","func apply_status")],
        ["盾→血结算","防御算后的damage先吸收盾，余量扣HP；真实伤害也先扣盾","反馈显示实际消耗=min(amount,目标HP/盾)，不显示过量",ref("scripts/combat/enemy.gd","final_amount = status.absorb")],
        ["治疗","min(缺血,amount×治疗倍率)，死亡不复活，不能超MHP","不同一次性治疗可依事务顺序执行；装备另有1s总量3%MHP限流",ref("scripts/core/run_controller.gd","func _healing_gain")],
    ]))
    out.append(block("7. 装备与Buff共享上限、触发和限流",["项目","现状上限/公式","适用范围"],[
        ["装备平坦贡献","攻击45；AP90；MHP220；护甲/魔抗各70；法力150；物/法穿各40；真实附伤12","六槽基础值×(1+0.1强化0..5)后累计，容量HP/MP逐件round；无独立装备实例"],
        ["暴击","总crit_chance≤75%；总crit_multiplier1..2.5","只原始普攻当前实际抽暴击；技能当前不暴击；每root共享一次暴击结果"],
        ["直接伤害加成","60%，来源相加","静态装备+条件装备+补给8%+信标20%+腐蚀8%及专用增伤；职业追加先入amount；连击、弱点为独立倍率"],
        ["攻速/移速","总装备静态+动态攻速60%、移速45%","攻击间隔=基础interval/(1+AS)；移动=基础speed×(1+MS)×减速倍率；施放movement另乘；信标15%占MS池"],
        ["装备减伤","静态+动态装备桶35%；玩家再加状态减伤后总65%","护甲/魔抗的100/(100+抗性)独立乘；不与65%混用"],
        ["其他属性桶","CDR30%；burn_damage60%；corrosion_damage_bonus60%；status_duration40%","CDR仅主动技能定义；多系统读取上限由stat/effect/player统一截断（现状）"],
        ["状态/伤害包预算","同root最多4包","原生状态/3遗物预留在装备触发之前；原生遗物不计装备1.20X系数金额；packet=false的纯Buff事件不占包"],
        ["装备派生总额","同root全目标SUM(accepted_coefficient)≤1.20","每包最多3目标，240半径，生者且视线；接受系数=min(请求,剩余预算/本包目标数)；amount=保存X×接受系数"],
        ["装备护盾","最多35%MHP/单源；各来源max","默认4s，不能从多个2%来源相加成4%；命令一次性，不是永久属性"],
        ["装备回血","任意滑动1s窗口总≤3%MHP","接受=min(请求ratio,0.03−历史总ratio,缺血ratio−本事件已计划ratio)；再经重伤"],
        ["装备资源恢复","任意5s窗口总≤20%resource_max；单次怒1/能2/法3","EQ32每第5普攻且ICD3s；接受还须有缺资源、相同职业资源类型"],
        ["装备CD退还","任意1s窗口合计≤0.50s","接受=min(请求秒,0.5−历史退还,剩余CD)；主动选择Q/W/E/R当前最长CD，按固定顺序打平；dash独立"],
        ["消耗降低","EQ56下一有费成功技能8%，窗口3s；公式最低1资源，泛化最多20%","0资源满破势W仍为0；技能预览不消费，支付成功skill_cast后窗口删除"],
        ["词条条件字典","shielded>0盾；moving真实普通移动；resource_half≥50%；full_hp≥100%；injured0<HP<100%；low_hp0<HP≤50%","条件被动每次读取；低血50%与旧EQ11/21/51的30%门槛不同"],
        ["覆盖/换装/暂停","同effect ID buff覆盖自己的amount/until；不同ID对可加属性相加；击退scale相乘","换装只保留前后同时有效来源，不清ICD/消耗标记/限流历史；菜单暂停不推进时间；派生proc_depth≥1不再进入原始链"],
    ]))
    out.append("\n来源："+ref("scripts/combat/stat_resolver.gd","const EQUIPMENT_CAPS")+"、"+ref("scripts/combat/equipment_effects.gd","func _cap_modifiers")+"、"+ref("scripts/combat/equipment_effects.gd","func reserve_native")+"。96件装备和14套具体条件/ICD/效果另列装备附录；本节限流与第11节共享实现分支一起约束它们。\n")
    out.append(block("8. 补给、信标与设施增益",["类型","成本/获得","真实收益","时长/范围/限制"],[
        ["快速止血","20金币","15%MHP立即回血","小/大治疗购买互斥，满血不能买，成功事务一次；安全治疗未显式带重伤倍率"],
        ["修整服务","60金币","35%MHP立即回血","与小治疗互斥；不超过缺血"],
        ["应急护盾","40金币","15%MHP","下一战斗房；首个实际吸收时才开始4s计时；离房即移除，即使未用；跨安全存点保存"],
        ["便携增幅","60金币","直接增伤+8%","后续2个战斗房；每完成1房减1；占60%池；不能重复买同offer"],
        ["勘探扫描","20金币","揭示指定路线节点","无战斗属性；避免误写为damage/crit Buff"],
        ["跳过遗物选择","选择skip","6%MHP立即治疗","安全边界事务结算；不触发战斗治疗Buff，不改变永久属性"],
        ["法力/能量补剂（历史兼容）","40/20金币","法力最大资源30%/能量20%","当前reward_policy≥1不生成这两类付费offer；新规则补给整备免费恢复mana/energy至上限；怒气不适用"],
        ["复苏信标","接近固定72范围自动触发","25%MHP治疗","实际正恢复才消耗信标，满血保留；有重伤为15%MHP；45s原位刷新随机功能"],
        ["源能信标","接近72","30%resource_max恢复","有缺资源才消耗；资源容量不增加；不修改自动回复速率"],
        ["战意信标","接近72","直接增伤+20%","15s；同类设备刷新同源，不叠加；并入60%池"],
        ["守护信标","接近72","25%MHP护盾","15s；room_prop:guard；和其他护盾取max；切房清除"],
        ["迅行信标","接近72","移动加成+15%","12s；同类刷新；与装备共用45%池"],
        ["场景护盾插座","普通敌人utility socket_recharge","指定敌人获得MHP×guard_ratio；默认30%","ratio clamp0..50%；进入CombatStatus的enemy来源；默认duration5s；插座CD4s；可由招式参数覆盖，招式全表另列"],
        ["环境节点充能","charge_resonance调用","法师已展开节点+指定电荷（默认1）","传入范围、可见性；不产生原始攻击、装备事件和资源"],
    ]))
    out.append("\n补给来源："+ref("scripts/core/run_controller.gd","func purchase_run_supply")+"、"+ref("scripts/core/expedition_state.gd","const SUPPLIES")+"；信标："+ref("scripts/world/room_props.gd","const BUFFS")+"、"+ref("scripts/world/room_props.gd","func grant_buff")+"。设施只随机功能，不移动几何点。信标效果随房间configure/clear清除，暂停冻结时钟。\n")
    out.append("\n### 8.1 已移除输入的旧C/V回路（保留源码，不计当前角色可用收益）\n\n"+ref("scripts/core/control_bindings.gd",'for action: String in ["circuit_place", "circuit_release"]')+"删除两个InputMap动作。房间仍创建回路对象，但新房anchors为空且当前没有正式可触发的布桩/释放输入。为保证源码数值不遗漏，仅登记残留实现，不能把它算进当前DPS或玩法已完成度。\n\n")
    out.append(table(["残留机制","源码数值","可用性"],[
        ["布桩","最远460；两桩长100–680；0.4s展开、布桩CD.2；玩家距线<850；最多3电荷","旧API存在；当前输入不开放"],
        ["放电","消费1/2/3电荷：魔法伤害(0.8+.9×电荷)AD=1.7/2.6/3.5AD；半宽50/62/74；CD.7","调用resolve_direct_hit但标记proc_depth1和equipment_eligible=false；现状仍可消费旧感电和享有player.stat增伤，但不参与连击/装备原始链"],
        ["放电职业收益","战士击退120，其他25；存活命中目标施寒冷；枪手额外猎印4s；法师节点充电spent，其他职业有命中回spent×6=6/12/18资源","当前未开放；不是法师正式技能H；与新被动收益分开"],
        ["节点充能范围","回路线段中点；半径=线段长度/2+120","残留API，仅登记"],
    ]))
    out.append(block("9. 野怪/Boss增益与玩家Buff的分离",["系统","数值","覆盖/来源"],[
        ["B01普通敌 蓄能护盾","有效技能命中后8%自身MHP盾、1.5s，ICD4s","只普通enemy，非boss/静态机关；技能伤害真实损失才触发"],
        ["B02普通敌 毒蚀伤口","有效命中附corrosion1.8s；power=该技能damage×0.55","每完整1s .08power，即.044×该技能damage；已有原生corrosion的招式不再添加一次"],
        ["B03普通敌 墓火汲取","有效命中heal=min(command.damage×0.25,自身MHP×0.06)，ICD3s","按命令快照damage而非最终玩家HP损失；重伤再×0.6，缺血再截断"],
        ["B04普通敌 半血狂怒","自身HP≤50%且>0：出招damage×1.20、移动×1.18","伤害在提交时冻结，不能把已有command再重复乘；移速与haste取max而非相乘，上限1.35"],
        ["普通敌机制反制","solar_conduit/brood_egg/war_drum弱点最终受伤×1.35；默认6s","counter duration clamp.01..30s；战鼓反制有效护甲=0；日曜反制清除自身/支援盾；多反制只一次1.35"],
        ["Boss弱点","Boss当前weakpoint_open时受伤×1.35","boss.take_damage前乘；普通怪biome弱点资格排除boss，不重复1.35；具体招式窗口见敌人附录"],
        ["Boss阶段","HP≤70%进入2，≤35%进入3（定义可覆盖）","阶段切换负责清理老hazard/弱点与有限增援；阶段本身不自动提高damage_multiplier"],
        ["BO01初始盾","22%MHP、3600s","太阳回路反制移除；与Boss其他机制分开，不能把全部首领当晴辉普通怪8%盾"],
        ["BO04战鼓狂怒","5s；出招damage×1.25；附近最多3目标haste×1.18/5s","破鼓停止狂怒并禁用，与普通怪半血1.20分开；同一command只快照一次"],
        ["Boss反制窗口","BO01太阳核2.8s；BO02破卵2.6s；BO03脱线2.5s；BO04破鼓2.5s","还有落地/撞墙/招式弱点；来自作者参数，不能统一套成同一duration"],
        ["普通敌击退","精英实际distance×0.5，Boss免击退","正常敌位移被墙裁切；hit反应最多1s一次/0.12s；与伤害是否生效分开"],
    ]))
    out.append("\n来源："+ref("scripts/combat/enemy_biome_skills.gd","const SIGNATURES")+"、"+ref("scripts/combat/enemy.gd","func take_damage")+"、"+ref("scripts/combat/boss_brain.gd","func incoming_damage_multiplier")+"。普通敌辅助guard/heal/haste/counter/barrier/scan参数及所有招式的覆盖表达式保留在第11节；这类支援盾可与CombatStatus来源盾串行吸收，不能混记为玩家max共享护盾。\n")
    out.append("\n### 9.1 敌人辅助Buff执行器：默认、硬上限与覆盖\n\n具体敌人原型可覆盖这些默认；每个原型覆盖值见敌人附录。来源："+ref("scripts/combat/enemy_skill_runtime.gd","func _support")+"、"+ref("scripts/combat/enemy_skill_runtime.gd","func filter_incoming_damage")+"。\n\n")
    out.append(table(["项目","数值/公式","叠加/失败边界"],[
        ["支援范围/目标","默认radius200、max_targets3 clamp1..3，必须可见；directional/screen/socket/counter只自身","可exclude_self/exclude_support_recipients；同enemy_id支援怪不互相充能；不选skill anchor；近者优先"],
        ["heal支援","默认.10MHP；最终min(request,.15MHP)；同wave同target最多2次，参数可降1","只有真实回血才记receipts；重伤×.6；默认尸体haste需180半径同zone可见尸体，先消费才施加"],
        ["通用guard支援","默认.20MHP；容量clamp0..35%MHP；默认duration3s clamp.2..6s","独立supports池，在双抗/DR前依顺序吸收；同施法者+kind+目标替换旧来源；不同施法者可串行吸收；真伤跳过此池"],
        ["directional guard","angle默认1.9rad，半角clamp0..PI；只来自正面范围有效","from_direction近零的DOT不被定向阻挡"],
        ["cover guard","cover HP默认35 clamp1..80；前42放实体掩体；射线穿过掩体平面且距中心≤60","只primary/child；消耗真实掩体HP；初选受援者侧向90约束；掩体被破停止"],
        ["screen guard","默认3次clamp1..4；每次消耗1，完全抵挡一次有效普攻/child","须方向有效；不挡直接技能/DOT；耗尽移除"],
        ["haste支援","默认1.18 clamp1..1.35；持续3s clamp.2..6s","多来源取max，和blood_rage也max，寒冷独立乘.8/.9；require_corpse先消费尸体"],
        ["counter支援","默认3击clamp1..4；到hit_cap或到期反击；默认auto_release=true；延迟至少.95s；默认射程140、角1.3rad","非真实入伤才进入filter计hit；counter本身不抵伤；派生反击仍走命令伤害"],
        ["scan_mark","房间同时最多1个；默认3s clamp.5..4；同zone下一远程攻击消费使前摇×.85","原始最低预警时间仍保留；不可叠加多份.85"],
        ["decoy","1–2假身；默认2s clamp.3..4；offset±62","只有visuals；不增加伤害/减伤；潜行同理仅透明度视觉，不虚构camouflage Buff"],
        ["召唤囊破坏","armor=max(0,armor−pod_break_armor_loss)，默认0；BO02为每囊2","真实HP耗尽才生效，cancel/delete不削甲"],
        ["四族签名后备值","runtime缺cooldown_seconds时默认4s；当前B03 SIGNATURES明定3s","不是当前墓镇怪CD4s；有真正收益才开始CD，未命中/拒伤/满HP不计"],
    ]))
    out.append("\n## 10. 完整伤害流水线与跨系统算例\n\n")
    out.append(table(["步骤","当前真实执行","避免歧义"],[
        [1,"复制攻击上下文；保存X=原输入amount，H=已提交power或当前AD；记录pre-hit目标状态","法师技能H已包含0.7AP；保存X不含职业追加/暴击/连击"],
        [2,"预留原生状态；普攻已按ember→split→arc预留遗物；装备before_hit读接触前状态与条件","共用同root4包；同root/同packet预留幂等"],
        [3,"仅source=primary按min(.75,基础crit+装备crit_bonus)抽一次；消费目标旧感电","原始技能当前不暴击；感电另包后执行"],
        [4,"增伤B=player.static+补给+信标+装备before条件；腐蚀时另+0.08+腐蚀专用增伤","B最终min(.60,B)，这些来源在同一个加法桶"],
        [5,"amount加枪手猎印1.25H与被动0.65H；计算amount×(1+min(.60,B))×暴伤C×连击(1+.005×接触前层)","连击独立于60%；职业额外伤害也享受直接包倍率；破势已在提交时加入技能系数"],
        [6,"Boss弱点×1.35（若当前打开）；敌人支援过滤（counter/guard/barrier/stationary）","真实伤害跳过减伤支援，显式invulnerable仍阻止"],
        [7,"物理抗性=max(0,effective_armor×腐蚀0.85−物穿)；魔法抗性=max(0,MR−法穿)","战鼓反制先effective_armor=0；抗性最低0，不产生负护甲额外伤害"],
        [8,"非真实damage×100/(100+R)×[1−clamp(DR,0,.65)]；普通怪反制弱点再×1.35","玩家受伤DR=装备桶+max状态桶+动态装备桶合并一次；真实伤害跳过抗性与DR"],
        [9,"来源盾吸收→余量HP；确认实际HP/盾变化；原始包确认数值先保存","原始只打盾也计有效命中；无敌与零伤害不推进被动/连击"],
        [10,"原始确认后追加固定真实附伤（上限12，非暴击）；登记职业被动、连击、种族遗物有效普攻计数","追加真实包与原始包分开；不会把原始未破盾变成伪造原始破盾"],
        [11,"若目标存活，旧感电另魔法包0.25power；施加当前原生状态；成功状态通知装备","本击新状态不追溯增加同击before_hit；敌人apply_status现状接受结果差异见第6节"],
        [12,"真实原始命中且目标仍活才击退；装备after_hit按武器→头胸手脚→饰品/套装顺序续算，状态请求须先落地再继续","装备派生=max保存X×接受系数；不暴击、不加连击、不触发原始/装备递归；派生死亡仅S01灼烧kill例外"],
    ]))
    out.append("\n纯防御公式：`D_nontrue=D_raw×100/[100+max(0,R_effective−Pen)]×(1−clamp(DR,0,.65))`；`D_true=D_raw`。显式无敌把最终数值清零；两者最后都先扣盾。普通敌/Boss独立弱点倍率按其对应入口乘一次。\n\n")
    out.append(table(["例子","代入","结果/意义"],[
        ["战士当前L18三层W","当前裸AD=27×(1+.10×17/19)=29.415789；X=(2.2+3×.45)×AD","X=104.426053；资源0；只是示例，装备与新设计值不混入"],
        ["法师技能与遗物区别","假定AD30、AP80；skill H=86；Q1.25H=107.5；RL01I=.4AP","遗物每额外敌32，不能误用.4×86=34.4；法师普攻=30"],
        ["独立倍率与上限","假定原伤100；增伤装备35%+补给8%+信标20%+腐蚀8%=71%→60%；50连击1.25；暴伤1.5；Boss弱点1.35","防御前=100×1.6×1.25×1.5×1.35=405；技能当前不暴击则270"],
        ["护甲与减伤","承接405；目标armor40腐蚀×.85=34；物穿10→24；DR20%","405×100/124×.8=261.290323；若盾30，HP损失231.290323（还有足够生命）"],
        ["派生总预算","保存X100；已有root coefficient.8；请求.35×3敌","剩余.4，接受.4/3=.133333，每敌13.3333，总40；不按405暴击伤害再乘"],
        ["共存护盾","MHP200；战吼18%=36/4s，职业被动8%=16/3s，信标25%=50/15s","实际盾50；一次吸收20后各池16/0/30，生效30；不能把三池相加为102"],
        ["重伤与装备治疗限流","MHP200，1s内已装备治疗2%=4；新请求2%=4，尚缺血","剩余额度1%=2；重伤×.6，实际至多1.2HP；职业/信标治疗是否限流由各来源独立决定"],
    ]))
    out.append("\n### 10.1 已发现的现状接口偏差（重构时须明确修正）\n\n")
    out.append(table(["差异","当前事实","设计/验收影响"],[
        ["状态接受bool未完整透传","enemy.apply_status总return true，未返回CombatStatus.apply/grant_guard结果","弱状态被拒绝仍可能触发successful-status装备或设施CD；不能把意图注释当已实现确认门槛"],
        ["装备after链未全局受confirmed保护","room.resolve_direct_hit原生状态循环和loadout.after_hit在confirmed块之外；_eligible仅检查来源/深度/valid_target","被动、连击严格HP/盾实际损失；装备after链/原生状态当前存在被无敌或0伤拒绝后仍执行的路径。未来须统一确认门槛并覆盖测试"],
        ["猎印提前消费","class_modify_hit_amount在target.take_damage之前直接erase class_mark","与HeroPassives的预约→有效损失后消费规则不同；重构应明确命中被无敌拒绝是否返还猎印"],
        ["旧感电提前消费","room消费旧shock早于target.take_damage的免疫判断","显式无敌目标可在拒绝原始伤害时丢失shock；派生节点不走这一入口；未来需确认后再消费"],
        ["遗物第三发与职业有效三击不同","原生RL03用run.shots%3，职业与B01适配各有有效root计数","空发/没命中可能改变下一次遗物第三发时机，不能笼统写成全部每第三次有效命中"],
        ["辅助盾与来源盾不同","enemy_runtime.supports在双抗前串行，CombatStatus.guards在双抗后shared_max","当前两套实现均需各自记录；未来统一策略时必须给迁移与回归验收"],
        ["RRL03枪手文案键位旧","ClassRelics显示‘鼠标右键或R引爆’，实际消费source secondary/ultimate即W/R","当前键位以运行输入和source为准，不能从旧description推计算路径"],
    ]))
    ledger=numerical_ledger()
    out.append(f"\n## 11. 可追溯数值分支索引（{len(ledger)}行）\n\n这是源码表达式表，保留条件、默认值、快照、上限和算术分支，不是新方案参数。视觉绘制/声音采样参数不计为战斗Buff；装备逐件、敌人招式全表已由独立附录覆盖，因此这里只重复它们的共享结算分支。原始代码里的数字标识（技能槽/层数/预算/计数）有意保留，便于后续重构不漏条件。\n\n")
    out.append(table(["精确来源","函数/区域","生效分支","原文计算表达式"],ledger))
    out.append("\n## 12. 全等级原始运行预览表与来源指纹\n\n此表保留全部264条skill spec与实际timeline，供标准库Python检查重复、缺项、source对应和文档可重建。尚未解锁的定义可被预览，但不代表可施放。\n\n<!-- SKILL_PREVIEW_ROWS_START -->\n")
    out.append(table(["职业","等级","内部槽","分支","完整spec JSON","timeline JSON"],[[r["hero"],r["level"],r["slot"],r["branch"] or "默认",r["spec"],r["timeline"]] for r in rows]))
    out.append("<!-- SKILL_PREVIEW_ROWS_END -->\n\n")
    out.append(table(["源文件","SHA-256"],[[p,hashlib.sha256((ROOT/p).read_bytes()).hexdigest()] for p in INPUTS]))
    out.append("\n检查：`python tools/balance/render_buff_skill_catalog.py --check`。重建时先在空Godot项目运行 `tools/balance/export_buff_skill_catalog.gd -- <仓库绝对路径> <JSON绝对路径>`（须以该空项目为--path且无autoload），再运行 `python tools/balance/render_buff_skill_catalog.py --skills-json <JSON路径>`。生成文件UTF-8；缓存JSON/空项目/日志位于artifacts，不入Git。\n\n")
    out.append("已验证范围：264条实际技能预览与当前源码静态规则；本附录没有新增平衡模拟，也没有宣称自然战斗、锻造经济或未来随机实例已验收。无网络请求；本机Godot根证书库读取诊断不属于本导出器脚本错误。\n")
    return "\n".join(out)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--skills-json", type=Path)
    parser.add_argument("--check", action="store_true")
    args=parser.parse_args()
    if args.skills_json:
        preview=json.loads(args.skills_json.read_text(encoding="utf-8-sig"))
    elif DOC.exists():
        preview=raw_rows_from_document(DOC.read_text(encoding="utf-8"))
    else:
        parser.error("Initial generation requires --skills-json from the empty-project Godot exporter")
    result=render(preview)
    table_count = validate_table_layout(result)
    if args.check:
        current=DOC.read_text(encoding="utf-8")
        if current != result:
            raise SystemExit("CHECK FAILED: catalog differs from sources/preview; regenerate and review")
        print(f"CHECK OK: 264 runtime skill combinations; {len(numerical_ledger())} numerical source branches; {len(INPUTS)} fingerprints; {table_count} tables with consistent columns")
    else:
        DOC.parent.mkdir(parents=True,exist_ok=True)
        DOC.write_text(result,encoding="utf-8",newline="\n")
        print(f"WROTE {DOC}: 264 skill combinations, {len(numerical_ledger())} branches")

if __name__ == "__main__":
    main()
