#!/usr/bin/env python3
"""Freeze real enemy commands and render the documentation-only combat proposal.

The normal render/check path uses the checked-in input, not artifacts or user saves.
--freeze-export is an explicit maintenance step for a pure Godot export.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/balance/current_enemy_skill_inputs.json"
OUTPUT = ROOT / "docs/balance/TARGET_ENEMY_SKILL_TABLES.md"
PARAMS = ROOT / "docs/balance/numerical_v2_parameters.json"
TIERS = (1, 5, 10, 15)
SCALE = Decimal(10)
CALIBRATION = Decimal("1.35")
CHAPTER_HP_STEP = Decimal(".12")
CHAPTER_DAMAGE_STEP = Decimal(".08")
HP_D = tuple(map(Decimal, ("1", "1.4", "2", "2.8", "4")))
DAMAGE_D = tuple(map(Decimal, ("1", "1.2", "1.5", "1.85", "2.3")))
TIER_SKILL = tuple(map(Decimal, ("1", "1.08", "1.16", "1.25")))
ENEMY_SKILL_D = tuple(map(Decimal, ("1", "1.05", "1.10", "1.15", "1.20")))
BOSS_SKILL_D = tuple(map(Decimal, ("1", "1.06", "1.12", "1.20", "1.30")))
BOSS_PHASE = tuple(map(Decimal, ("1", "1.10", "1.20")))
KINDS = {"melee":"近战", "charge":"位移攻击", "projectile":"弹体", "ground_area":"地面区", "pull":"牵引攻击", "summon":"召唤", "haste":"加速", "guard":"防护", "heal":"治疗", "utility":"机关交互", "decoy":"诱饵", "counter":"受击反击"}
DAMAGE_KINDS = {"melee", "charge", "projectile", "ground_area", "pull", "counter"}
TYPES = {"physical":"物理", "magic":"魔法"}
STAT_KEYS = ("max_hp", "damage", "armor", "magic_resist", "move_speed", "attack_range", "recovery_seconds", "damage_type", "mechanic_tier", "enemy_level")
COMMAND_REMOVE = {"enemy_id", "boss_id", "behavior_id", "biome_skill", "origin", "direction", "fx_color"}
FLAT_KEYS = ("cover_hp", "anchor_health", "pod_health", "pod_break_armor_loss")


def dec(value):
    return Decimal(str(value))


def rounded(value):
    value = dec(value)
    assert value >= 0, value
    return int(value.quantize(Decimal(1), rounding=ROUND_HALF_UP))


def n(value):
    return format(dec(value).normalize(), "f")


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def table(headers, rows):
    esc = lambda value: str(value).replace("|", "\\|").replace("\n", "<br>")
    return "\n".join(["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"] + ["| " + " | ".join(esc(v) for v in row) + " |" for row in rows]) + "\n\n"


def clean_command(command):
    result = {key: value for key, value in command.items() if key not in COMMAND_REMOVE}
    # Spatial coordinates depend on the export fixture. Preserve topology/counts;
    # the runtime source remains the authority for the complete path geometry.
    for key in ("target", "targets", "paths"):
        if key in result:
            result[key + "_count"] = len(result[key]) if key != "target" else 1
            del result[key]
    return result


def freeze(export):
    assert export["schema"] == "EnemyBossDocumentation/v1"
    result = {"schema":"EnemySkillInputs/v1-documentation-only", "runtime_enabled":False,
              "source_snapshot":export["source_snapshot"], "engine_version":export["engine_version"],
              "source_sha256":export["source_sha256"], "reference_levels":list(TIERS),
              "ordinary":[], "bosses":[]}
    for enemy in export["ordinary"]:
        first = next(s["profile"] for s in enemy["samples"] if s["rank"] == "normal" and s["level"] == 1)
        entry = {"id":enemy["enemy_id"], "name":first["name"], "biome_id":first["biome_id"],
                 "biome_skill":first["biome_skill"], "tiers":[]}
        for level in TIERS:
            normal = next(s for s in enemy["samples"] if s["rank"] == "normal" and s["level"] == level)
            elite = next(s for s in enemy["samples"] if s["rank"] == "elite" and s["level"] == level)
            commands = [clean_command(c) for c in normal["sequence"]]
            elite_commands = [clean_command(c) for c in elite["sequence"]]
            # Most elites append aftershock; M36 replaces its explosion geometry.
            elite_delta = {"append":elite_commands[len(commands):]} if elite_commands[:len(commands)] == commands else {"replace":elite_commands}
            entry["tiers"].append({"tier":normal["profile"]["mechanic_tier"], "reference_level":level,
                                   "profiles":{rank:{k:s["profile"][k] for k in STAT_KEYS} for rank,s in (("normal",normal),("elite",elite))},
                                   "commands":commands, "elite_delta":elite_delta})
        result["ordinary"].append(entry)
    for boss in export["bosses"]:
        profile = boss["samples"][0]
        entry = {"id":boss["boss_id"], "name":profile["name"], "base_level":boss["base_level"],
                 "stats":{k:profile[k] for k in STAT_KEYS if k in profile}, "actions":[]}
        by_id = {}
        for action in boss["actions"]:
            action_id = action["action_id"]
            if action_id not in by_id:
                item = {"id":action_id, "name":action["name"], "unlock_difficulty":action["unlock_difficulty"],
                        "source":action["source"], "variants":[]}
                entry["actions"].append(item)
                by_id[action_id] = item
            by_id[action_id]["variants"].append({"phase":action["phase"], "command":clean_command(action["command"])})
        result["bosses"].append(entry)
    return result


def frozen_json(data):
    """Compact commands with one readable tier/action record per line."""
    compact = lambda value: json.dumps(value,ensure_ascii=False,separators=(",",":"))
    meta={k:v for k,v in data.items() if k not in ("ordinary","bosses")}
    lines=[json.dumps(meta,ensure_ascii=False,indent=2)[:-2]+",", '  "ordinary": [']
    for i,enemy in enumerate(data["ordinary"]):
        header=compact({k:v for k,v in enemy.items() if k!="tiers"})[:-1]
        lines.append("    "+header+',"tiers": [')
        lines.extend("      "+compact(t)+( "," if j<len(enemy["tiers"])-1 else "") for j,t in enumerate(enemy["tiers"]))
        lines.append("    ]}"+( "," if i<len(data["ordinary"])-1 else ""))
    lines += ['  ],', '  "bosses": [']
    for i,boss in enumerate(data["bosses"]):
        header=compact({k:v for k,v in boss.items() if k!="actions"})[:-1]
        lines.append("    "+header+',"actions": [')
        lines.extend("      "+compact(a)+( "," if j<len(boss["actions"])-1 else "") for j,a in enumerate(boss["actions"]))
        lines.append("    ]}"+( "," if i<len(data["bosses"])-1 else ""))
    lines += ['  ]', '}']
    text="\n".join(lines)+"\n"
    assert json.loads(text)==data
    return text


def validate(data):
    assert data["schema"] == "EnemySkillInputs/v1-documentation-only" and data["runtime_enabled"] is False
    assert [e["id"] for e in data["ordinary"]] == [f"M{x:02}" for x in range(1,37)]
    assert len(data["bosses"]) == 4
    assert sum(len(b["actions"]) for b in data["bosses"]) == 40
    assert sum(len(a["variants"]) for b in data["bosses"] for a in b["actions"]) == 103
    assert len(data["source_sha256"]) == 17
    for source, digest in data["source_sha256"].items():
        assert hashlib.sha256((ROOT/source).read_bytes()).hexdigest() == digest, f"source changed: {source}"
    for enemy in data["ordinary"]:
        assert int(enemy["biome_id"][1:]) == ordinary_chapter(enemy)
        assert [t["reference_level"] for t in enemy["tiers"]] == list(TIERS)
        assert [t["tier"] for t in enemy["tiers"]] == [1,2,3,4]
        for tier in enemy["tiers"]:
            assert tier["commands"]
            assert set(tier["elite_delta"]) in ({"append"},{"replace"})
            for rank in ("normal","elite"):
                assert tier["profiles"][rank]["damage"] > 0
            for command in all_commands(tier,"normal") + all_commands(tier,"elite"):
                assert command["kind"] in KINDS
                assert dec(command.get("damage_multiplier",1)) >= 0
    # Cross-check shared proposal values after the main design updates them.
    params = load(PARAMS)
    assert params["runtime_enabled"] is False
    assert params["enemy_baseline_multiplier"] == {"max_hp":1.35,"damage":1.35}
    assert dec(params["combat_scale"]) == SCALE and params["resistance_denominator"] == 1000
    assert dec(params["chapter_hp_per_step"]) == CHAPTER_HP_STEP
    assert dec(params["chapter_damage_per_step"]) == CHAPTER_DAMAGE_STEP
    assert tuple(map(dec,params["difficulty_hp_multipliers"])) == HP_D
    assert tuple(map(dec,params["difficulty_damage_multipliers"])) == DAMAGE_D
    for key,expected in (("ordinary_skill_tier_multipliers",TIER_SKILL), ("ordinary_skill_difficulty_multipliers",ENEMY_SKILL_D), ("boss_skill_difficulty_multipliers",BOSS_SKILL_D), ("boss_skill_phase_multipliers",BOSS_PHASE)):
        assert tuple(map(dec,params[key])) == expected, f"proposal mismatch: {key}"
    assert rounded("2.5") == 3 and rounded("0.5") == 1 and rounded("0.49") == 0
    assert ordinary_stats(data["ordinary"][0]["tiers"][0],"normal",0,1)["damage"] == 189
    assert packet(data["ordinary"][0]["tiers"][0]["commands"][0],435,ENEMY_SKILL_D[4]) == 522
    assert packet(data["ordinary"][33]["tiers"][0]["commands"][0],158) == 0
    assert boss_stats(data["bosses"][0],4)["damage"] == 621
    assert packet(data["bosses"][0]["actions"][0]["variants"][2]["command"],621,BOSS_SKILL_D[4]*BOSS_PHASE[2]) == 1114


def all_commands(tier, rank):
    if rank == "normal":
        return tier["commands"]
    delta = tier["elite_delta"]
    return delta["replace"] if "replace" in delta else tier["commands"] + delta["append"]


def ordinary_chapter(enemy):
    return (int(enemy["id"][1:])-1)//9+1


def boss_chapter(boss):
    return int(boss["id"][2:])


def chapter_factor(chapter, key):
    assert 1 <= chapter <= 12
    return 1+(CHAPTER_HP_STEP if key=="max_hp" else CHAPTER_DAMAGE_STEP)*(chapter-1)


def ordinary_stats(tier, rank, difficulty, chapter):
    p = tier["profiles"][rank]
    return {"max_hp":rounded(dec(p["max_hp"])*CALIBRATION*SCALE*chapter_factor(chapter,"max_hp")*HP_D[difficulty]),
            "damage":rounded(dec(p["damage"])*CALIBRATION*SCALE*chapter_factor(chapter,"damage")*DAMAGE_D[difficulty]),
            "armor":rounded((dec(p["armor"])+2*difficulty)*SCALE),
            "magic_resist":rounded((dec(p["magic_resist"])+2*difficulty)*SCALE)}


def boss_stats(boss, difficulty):
    p = boss["stats"]
    chapter=boss_chapter(boss)
    assert boss["base_level"]==5*chapter
    return {"max_hp":rounded(dec(p["max_hp"])*CALIBRATION*SCALE*chapter_factor(chapter,"max_hp")*HP_D[difficulty]),
            "damage":rounded(dec(p["damage"])*CALIBRATION*SCALE*chapter_factor(chapter,"damage")*DAMAGE_D[difficulty]),
            "armor":rounded((dec(p["armor"])+3*difficulty)*SCALE),
            "magic_resist":rounded((dec(p["magic_resist"])+3*difficulty)*SCALE)}


def packet(command, base_damage, skill_factor=1):
    if command["kind"] not in DAMAGE_KINDS or (command["kind"] == "counter" and not command.get("auto_release",True)):
        return 0
    return rounded(dec(base_damage)*dec(command.get("damage_multiplier",1))*dec(skill_factor))


def status_text(command, q, factor=1):
    status = command.get("status",{})
    if not status:
        return "无"
    result = status["id"] + f" {n(status.get('duration',0))}s"
    if "magnitude" in status:
        result += f"；系数{n(status['magnitude'])}"
    sid = status["id"]
    if sid in ("burn","corrosion","bleed","shock"):
        power = rounded(dec(status["power"])*SCALE*dec(factor)) if "power" in status else q
        coefficient = {"burn":".12", "corrosion":".08", "bleed":".10", "shock":".25"}[sid]
        unit = "下次直伤追加" if sid == "shock" else "每1s原伤害"
        result += f"；power={power}；{unit}{rounded(dec(power)*dec(coefficient))}"
    return result


def timing(command, ordinary=False):
    tell = command["base_telegraph_seconds"] if ordinary else max(.55,command.get("tell",.8))
    lock = command["locked_seconds"] if ordinary else max(.24,command.get("lock",.32))
    return f"预警{n(tell)}s；锁定{n(lock)}s"


def damage_unit(command):
    if command["kind"] not in DAMAGE_KINDS:
        return "无直接伤害"
    if command["kind"] == "counter":
        if not command.get("auto_release",True):
            return "反击架势0伤害；随后独立近战命令计伤"
        return "格挡反击命中一次"
    if command["kind"] == "ground_area" and dec(command.get("duration",0)) > 0:
        interval = min(dec(2),max(dec(".35"),dec(command.get("tick_interval",.65))))
        duration = min(dec(8),max(dec(0),dec(command.get("duration",0))))
        hops = int(duration // interval)
        if command.get("lob"):
            return f"落点一次+每{n(interval)}s/跳；持续{n(duration)}s（最多{hops+1}次/区）"
        return f"每{n(interval)}s/跳；持续{n(duration)}s（最多{hops}跳/区）"
    if command["kind"] == "ground_area":
        return "一次区域命中"
    if command["kind"] == "projectile":
        return "每枚弹体命中一次"
    if command["kind"] == "charge":
        landing = command.get("landing_only",False) or command.get("path_mode","line") in ("leap","burrow")
        along = not command.get("landing_only",False) and (command.get("path_mode","line") not in ("leap","burrow") or command.get("damage_along_path",False))
        if landing and along:
            return "沿途一次+完成落地一次；每包均为Q，实收受无敌限制"
        return "仅完成落地命中一次" if landing else "沿途每目标最多一次"
    return "每次命中一次"


def mechanics(command):
    separate = {"kind","action_id","damage_multiplier","damage_type","status","base_telegraph_seconds","locked_seconds","tell","lock"}
    return "；".join(f"`{k}={json.dumps(command[k],ensure_ascii=False,separators=(',',':'))}`" for k in sorted(command) if k not in separate) or "沿用现状命令"


def support_values(command, hp, factor):
    result = []
    for key in FLAT_KEYS:
        if key in command:
            extra = 1 if key == "pod_break_armor_loss" else factor
            amount=rounded(dec(command[key])*SCALE*dec(extra))
            if key in ("cover_hp","anchor_health"):
                amount=min(800,max(10,amount))
            result.append(f"{key}={amount}"+("（同一掩体输入别名，不叠加）" if key=="cover_hp" and "anchor_health" in command else ""))
    for key in ("guard_ratio","shield_ratio","heal_ratio"):
        if key in command:
            if command.get("action")=="socket_recharge" and key=="shield_ratio" and "guard_ratio" in command:
                result.append("shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加")
                continue
            prefix = "受益目标生命"
            ratio=dec(command[key])
            if key=="heal_ratio": ratio=min(dec(".15"),ratio)
            elif key=="shield_ratio" and command["kind"]=="guard": ratio=min(dec(".35"),ratio)
            elif key=="guard_ratio" and command.get("action")=="socket_recharge": ratio=min(dec(".50"),ratio)
            amount = rounded(dec(hp)*ratio)
            result.append(f"{key}={n(command[key])}；按本体生命样例{amount}（{prefix}×原比例）")
    return "；".join(result) or "—"


def render(data):
    ordinary_count = sum(len(t["commands"]) for e in data["ordinary"] for t in e["tiers"])
    valid_boss_count = sum((5-a["unlock_difficulty"])*len(a["variants"]) for b in data["bosses"] for a in b["actions"])
    out = ["# 野怪与首领技能目标全表（重构确认稿）\n",
           "**以下全部是待确认的设计数值，尚未接入游戏。** 当前真实值仍由 [现状怪物与首领附录](CURRENT_ENEMY_BOSS_CATALOG.md) 记录。本册配合 [主方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md) 与 [目标属性总表](TARGET_NUMERICAL_TABLES.md)，明确基础值扩大10倍之后每个技能的整数输入。\n",
           f"冻结输入来自 Godot `{data['engine_version']}` 对提交 `{data['source_snapshot']}` 的纯 Profile/Brain 导出：[current_enemy_skill_inputs.json](current_enemy_skill_inputs.json)。36原型×4阶=144组普通命令序列，共{ordinary_count}个普通命令位置；40个首领技能ID、103个阶段变体、{valid_boss_count}个有效难度/阶段组合。精英附加命令另计。该文件与 [生成器](../../tools/balance/render_target_enemy_skills.py) 入库后，不依赖忽略的 artifacts 缓存。新倍率同时核对 [主方案参数](numerical_v2_parameters.json)，禁止两份表口径漂移。\n",
           "## 1. 整数化顺序与适用范围\n",
           "定义 `R(x)=floor(x+0.5)`，仅接受非负输入；生成器用 Decimal/ROUND_HALF_UP 实现。每个完整属性先计算所有属性层倍率，再 R 一次；技能拿已整数化的演员伤害，乘招式与技能倍率后 R 一次。运行实装须在减伤、追加伤害、每跳状态伤害与治疗/盾实际入账时各 R 一次，不能使用截断或 Python 默认银行家舍入。\n",
           "章节B按1–12递增：`F_HP(B)=1+0.12×(B−1)`，`F_A(B)=1+0.08×(B−1)`。当前原型M01–M09属于B1、M10–M18属于B2、M19–M27属于B3、M28–M36属于B4；BO01–BO04一一对应B1–B4。章节系数作用演员生命与基础伤害，不二次修改技能damage_multiplier。\n",
           "本次校准标尺是对应章等级与装备等级的全金装、约+2强化能显著压制本章D4首领；英雄配装输出/生命与实战击杀时间的验证见主方案。敌人只按章/区域与D固定计算，玩家获得更好装备时不会随玩家属性追平。B5–B12目前仅记录公式与标准样例，不能据这些样例宣称关卡已发布。\n",
           "普通/精英：`HP=R(旧同等级D0生命×1.35×10×F_HP(B)×HP_D)`，`A=R(旧同等级D0伤害×1.35×10×F_A(B)×Damage_D)`。旧 Profile 已包括原型、等级与精英身份，禁止重复叠精英生命1.2/伤害1.12。护甲/魔抗=`R((旧同等级D0双抗+2D)×10)`；既有旧等级防御上限24/32按单位换成240/320，难度加值仍在旧上限之后。所有D难度的本章三区等级固定为`5(B−1)+1 / +3 / +5`，首领固定Lv`5B`；同章提高D只改变难度倍率，不额外抬等级，也不读取玩家等级。\n",
           "首领：`HP=R(旧章节D0生命×1.35×10×F_HP(B)×HP_D)`，`A=R(旧章节D0伤害×1.35×10×F_A(B)×Damage_D)`；演员始终使用本章Lv5B基准。双抗=`R((旧章节双抗+3D)×10)`。旧首领的`1+0.16D / 1+0.08D`不再叠加；已取消旧方案D3/D4统一Lv20与章节等级差额补正。\n",
           "普通/精英技能原伤害 `Q=R(A×原招式系数×TierSkill[t]×EnemySkillD[D])`；首领 `Q=R(A×原招式系数×BossSkillD[D]×Phase[P])`。新增技能倍率作用每次命中与持续区域的每一跳，不再乘一次整段总伤害。加速、召唤、治疗、护盾、诱饵、机关交互的命令即使缓存有damage_multiplier=1，也没有直接伤害。M34反击架势auto_release=false，本命令0伤害，随后独立melee命令照表计伤；不能重复算一次counter。\n",
           table(["难度","HP_D","Damage_D","普通技能D倍率","首领技能D倍率"],[[f"D{d}",n(HP_D[d]),n(DAMAGE_D[d]),n(ENEMY_SKILL_D[d]),n(BOSS_SKILL_D[d])] for d in range(5)]),
           table(["阶级","参考等级","普通额外技能倍率","首领阶段","首领阶段倍率"],[[f"T{t}",TIERS[t-1],n(TIER_SKILL[t-1]),f"P{t}" if t<=3 else "—",n(BOSS_PHASE[t-1]) if t<=3 else "—"] for t in range(1,5)]),
           "### 1.1 十二章系数、区域等级与未来接口\n",
           table(["章节","状态","三区固定等级（所有D相同）","首领固定等级","F_HP","F_A","现有怪物/首领"],[[f"B{b}","已发布章，数值重构待接入" if b<=4 else "未来公式接口，未制作本章原型",f"{5*(b-1)+1} / {5*(b-1)+3} / {5*b}",5*b,n(chapter_factor(b,"max_hp")),n(chapter_factor(b,"damage")),f"M{9*(b-1)+1:02}–M{9*b:02} / BO{b:02}" if b<=4 else "—"] for b in range(1,13)]),
           "未来B5–B12仅保留同一公式接口，不声称已有新野怪或Boss。下列与主目标总表使用相同的**M01标准原型归一化样例**：旧Lv1/D0生命60、伤害14，无精英/原型额外倍率；在本章第三区等级L=5B先用目标普通等级成长`HP_old=60×[1+0.055×(L−1)]`、`A_old=14×[1+0.025×(L−1)]`，再校准×1.35×10、章节系数与D倍率后R。D4从完整未舍入属性乘D倍率后R，不能将D0整数再乘D倍率。该样例不是未来真实怪物定稿；当前运行等级仍上限20，扩展章的L21–60仅为目标接口演算。\n",
           table(["章/标准参考级","标准HP D0","标准HP D4","标准A D0","标准A D4"],[[f"B{b}/Lv{5*b}",rounded(dec(60)*(1+dec('.055')*(5*b-1))*CALIBRATION*SCALE*chapter_factor(b,'max_hp')),rounded(dec(60)*(1+dec('.055')*(5*b-1))*CALIBRATION*SCALE*chapter_factor(b,'max_hp')*HP_D[4]),rounded(dec(14)*(1+dec('.025')*(5*b-1))*CALIBRATION*SCALE*chapter_factor(b,'damage')),rounded(dec(14)*(1+dec('.025')*(5*b-1))*CALIBRATION*SCALE*chapter_factor(b,'damage')*DAMAGE_D[4])] for b in range(1,13)]),
           "生命、攻击/法强、护甲/魔抗/穿透、真伤、护盾、治疗、DoT power、可击破端点生命与固定护甲削减属于扩大10倍的战斗数值；百分比/系数、暴击率、概率、移速、射程、距离、角度、数量、时间、金币/经验/材料不做该单位扩大。角色资源上限与回复固定量按主方案×10，但支持次数、受益次数、召唤预算等计数不×10。新增技能倍率不缩短预警/锁定，不增发弹体、召唤或区域。普通已存在的四阶命令数量差异照旧保留。\n",
           "敌技能命中玩家的减伤输入：`E=max(0,相应防御×状态防御系数−穿透)`，`r=E/(1000+E)`，`Hurt=R(Q×其它合法百分比修正×(1−r)×(1−DR))`；双抗不另设65%上限，独立的通用减伤DR（装备与有效技能/状态）统一封顶65%；真伤绕过双抗。玩家减伤后的护盾扣减与生命扣减均使用整数且总计不得超过 Hurt。例：Q=1000、有效护甲1000得到实伤500；扩大前Q=100、护甲100同样实伤50，单位扩大本身不会改变克制比例。腐蚀已有物理护甲系数0.85、直接受伤1.08；不重复作用到腐蚀自身每跳。敌人承受玩家攻击的独立支援盾仍先于防御吸收，CombatStatus盾仍在减伤后吸收，分别按原顺序结算整数；本册不改变既有盾时序。\n",
           "状态百分比系数本身保持：burn每1s为`R(power×0.12)`魔法；corrosion每1s为`R(power×0.08)`物理；bleed每1s为`R(power×0.10)`物理；shock下次直伤追加`R(power×0.25)`魔法。默认power=本招整数Q；若原命令显式power为旧绝对值，先×10并乘本招技能倍率再R。减速magnitude与时长保持。状态每跳仍进入1000分母防御公式，表中是减伤前输入。\n",
           "旧绝对掩体/虫卵生命：`R(旧绝对量×10×该技能倍率)`；掩体/可拆线端点旧1–80生命限制随单位变成10–800，再应用限制，虫卵不套该80旧上限。M06的cover_hp与anchor_health是同一掩体输入的别名，优先anchor_health，只生成一个耐久值。M25充盾同样优先guard_ratio，shield_ratio仅为回退别名，只充一个盾。比例盾/治疗保留原比例字段，实际量=`R(受益者新整数生命×原比例)`；不叠技能阶级/难度/阶段倍率，避免生命与技能倍数复合。旧绝对型护盾/治疗仅×10，不加技能强度；当前命令没有这类绝对输入。破卵扣甲为`R(旧固定扣甲×10)`，不乘技能倍率。支援盾保持35%受益者HP上限、治疗保持15%上限，治疗还受实际缺失生命限制。盾/治疗列以受益者生命等于施法者为演算样例，真实受益者不同则重算。CombatStatus单源盾的50%上限与多来源取最大池仍按其现有实现，不把该规则套到独立支援盾。\n",
           "## 2. 全部36野怪、四阶命令与普通/精英D0/D4\n",
           "四阶参考等级依次Lv1/Lv5/Lv10/Lv15，T4在Lv20仍用同一命令序列但基础伤害更高。所有表行叠本原型所属章的F_HP/F_A；D0与D4在**同一参考等级**下比较，是分离阶/章/难度的公式对照样例，不是实际每章都会生成全部四阶。真实本章三区按固定章级1/3/5偏移重新解析Profile并选择对应tier，再套公式；首领为5B，各D不再额外抬L。不能把本表Lv1/5/10/15直接当所有实际房间等级。所有伤害列都是单次/单枚/每跳原伤害，不是整招保证总实伤。冻结序列是初始循环/可用支援次数状态；M17治疗次数耗尽的伤害分支另列，M06掩体冷却期间省略掩体命令，M05奇偶循环只翻转弧线方向、M11奇偶循环只镜像落点、M23奇偶循环切拉/推，伤害公式相同。\n"]
    for enemy in data["ordinary"]:
        chapter=ordinary_chapter(enemy)
        out.append(f"### {enemy['id']} {enemy['name']}（B{chapter}，F_HP={n(chapter_factor(chapter,'max_hp'))} / F_A={n(chapter_factor(chapter,'damage'))}）\n")
        rows = []
        for tier in enemy["tiers"]:
            t = tier["tier"]
            for rank in ("normal","elite"):
                s0,s4 = ordinary_stats(tier,rank,0,chapter),ordinary_stats(tier,rank,4,chapter)
                k0,k4 = TIER_SKILL[t-1]*ENEMY_SKILL_D[0],TIER_SKILL[t-1]*ENEMY_SKILL_D[4]
                commands = all_commands(tier,rank)
                old = tier["profiles"][rank]["damage"]
                labels = []
                old_values = []
                new0,new4 = [],[]
                supports=[]
                for i,command in enumerate(commands,1):
                    label = f"{i}.{KINDS[command['kind']]}×{n(command.get('damage_multiplier',1))}"
                    labels.append(label)
                    raw = dec(old)*dec(command.get("damage_multiplier",1)) if command["kind"] in DAMAGE_KINDS and not (command["kind"]=="counter" and not command.get("auto_release",True)) else dec(0)
                    old_values.append(f"{i}:{n(raw)}")
                    q0,q4 = packet(command,s0["damage"],k0),packet(command,s4["damage"],k4)
                    new0.append(f"{i}:{q0}")
                    new4.append(f"{i}:{q4}")
                    v0,v4 = support_values(command,s0["max_hp"],k0),support_values(command,s4["max_hp"],k4)
                    if v0 != "—": supports.append(f"{i}.D0 {v0}<br>D4 {v4}")
                rows.append([f"T{t}/Lv{tier['reference_level']}","普通" if rank=="normal" else "精英",f"{s0['max_hp']}/{s4['max_hp']}",f"{s0['damage']}/{s4['damage']}","<br>".join(labels),"；".join(old_values),"；".join(new0),"；".join(new4),"<br>".join(supports) or "—"])
        out.append(table(["阶/参考级","身份","目标生命D0/D4","目标A D0/D4","完整命令序列与原系数","当前D0原伤害（浮点）","目标D0整数Q","目标D4整数Q","盾/治疗/端点目标量"],rows))
        detail_rows=[]
        for tier in enemy["tiers"]:
            for i,command in enumerate(tier["commands"],1):
                q0 = packet(command,ordinary_stats(tier,"normal",0,chapter)["damage"],TIER_SKILL[tier["tier"]-1])
                q4 = packet(command,ordinary_stats(tier,"normal",4,chapter)["damage"],TIER_SKILL[tier["tier"]-1]*ENEMY_SKILL_D[4])
                detail_rows.append([f"T{tier['tier']}-{i}",TYPES.get(command.get("damage_type",tier["profiles"]["normal"]["damage_type"]),command.get("damage_type","")),damage_unit(command),timing(command,True),status_text(command,q0,TIER_SKILL[tier['tier']-1])+"<br>D4："+status_text(command,q4,TIER_SKILL[tier['tier']-1]*ENEMY_SKILL_D[4]),mechanics(command)])
        out.append(table(["命令位置","类型","计伤单位/持续区域每跳","保留时序","普通目标状态输入D0/D4","原机制参数（百分比/时空/数量保持）"],detail_rows))
        if enemy["id"] == "M36":
            out.append("精英以单次爆炸序列替换：半径至少95、缺口至少50°、预警至少1.6s；没有追加余震。\n")
        else:
            out.append("精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。\n")
        if enemy["id"]=="M17":
            out.append("治疗已实际释放次数达到min(2,support_charges)后，序列第1项改为近战×0.6（角160°、距离58，无附加状态）；其后原近战与精英余震保持。下列来自带哈希的 [Brain条件分支](../../scripts/combat/enemy_brain.gd)，不冒充Godot初始状态导出的治疗命令。\n")
            out.append(table(["阶/参考级","身份","耗尽后第1项D0 Q","耗尽后第1项D4 Q"],[[f"T{t['tier']}/Lv{t['reference_level']}",rank,rounded(dec(ordinary_stats(t,rank,0,chapter)["damage"])*dec(".6")*TIER_SKILL[t["tier"]-1]),rounded(dec(ordinary_stats(t,rank,4,chapter)["damage"])*dec(".6")*TIER_SKILL[t["tier"]-1]*ENEMY_SKILL_D[4])] for t in enemy["tiers"] for rank in ("normal","elite")]))
    out += ["## 3. 种族技能、比例效果与条件增伤\n",
            "种族技能沿用现状触发边界，盾/治疗依据最终整数HP或power自然扩大；不让首领继承普通怪的半血狂怒。此处不把百分比字段乘10，也不对比例盾/治疗额外叠技能倍率。\n",
            table(["种族","目标计算方式","触发/时间保持","禁止重复倍率"],[
                ["B01 构装护盾","R(本体新HP×0.08)","有效攻击命中触发；1.5s盾，4s冷却","HP已×10；不叠技能倍率"],
                ["B02 寄生腐蚀","额外腐蚀power=R(本招Q×0.55)，每跳R(power×0.08)","1.8s；本招已是corrosion则不另叠种族腐蚀","Q已含技能倍率，power不能再次乘技能倍率"],
                ["B03 缝合回复","R(min(本体HP×0.06,本招整数Q×0.25))","有效命中触发，3s冷却；受重伤再×0.6并R","Q已含技能增幅；回复不再乘技能倍率"],
                ["B04 巨人半血狂怒","Q=R(A×本招系数×TierSkill×EnemySkillD×1.2)","生命≤50%，移动倍率1.18保持","仅乘一次1.2；表中默认未狂怒"],
                ["BO01 首领开场盾","R(首领新HP×0.22)","开场护盾，原长时限3600s保持","首领HP已包括难度/挑战等级；不叠技能倍率"],
                ["BO04 未打断战鼓狂怒","Q=R(A×本招系数×BossSkillD×Phase×1.25)","5s；打断成功则不获得该增伤","不叠普通B04半血倍率；表中默认未狂怒"],
            ]),
            "## 4. 四首领五难度的整型技能基础输入\n"]
    out.append(table(["首领/所属章","本章固定级","难度/实际级","新生命","新A","新护甲","新魔抗","开场盾（仅BO01）"],[[f"{b['id']}/B{boss_chapter(b)}",b["base_level"],f"D{d}/Lv{b['base_level']}",s["max_hp"],s["damage"],s["armor"],s["magic_resist"],rounded(dec(s["max_hp"])*dec(".22")) if b["id"]=="BO01" else "—"] for b in data["bosses"] for d in range(5) for s in [boss_stats(b,d)]]))
    out += ["## 5. 40个首领技能的全部有效难度/阶段整数伤害\n",
            "阶段沿用生命≤70%进入P2、≤35%进入P3；切阶段预警0.9s、出生0.8s。每项仅在原序列存在的阶段与解锁难度出现：表中`—`表示该阶段/难度没有该技能。P1/P2/P3数字是单次/单枚/每跳Q，不能相加当作一轮总伤害。额外难度技能原已在三个阶段都可出现；其原预警、释放数量与路径保持。\n"]
    for boss in data["bosses"]:
        out.append(f"### {boss['id']} {boss['name']}\n")
        rows=[]
        detail_rows=[]
        for action in boss["actions"]:
            values=[]
            for d in range(5):
                parts=[]
                for phase in range(1,4):
                    variant = next((v for v in action["variants"] if v["phase"]==phase),None)
                    q = packet(variant["command"],boss_stats(boss,d)["damage"],BOSS_SKILL_D[d]*BOSS_PHASE[phase-1]) if variant and d>=action["unlock_difficulty"] else None
                    parts.append(f"P{phase}:{q}" if q is not None else f"P{phase}:—")
                values.append("；".join(parts))
            first=action["variants"][0]["command"]
            rows.append([action["id"],action["name"],KINDS[first["kind"]],n(first.get("damage_multiplier",1)),f"D{action['unlock_difficulty']}+"]+values)
            for variant in action["variants"]:
                phase=variant["phase"]
                command=variant["command"]
                d=action["unlock_difficulty"]
                qmin=packet(command,boss_stats(boss,d)["damage"],BOSS_SKILL_D[d]*BOSS_PHASE[phase-1])
                qmax=packet(command,boss_stats(boss,4)["damage"],BOSS_SKILL_D[4]*BOSS_PHASE[phase-1])
                support= support_values(command,boss_stats(boss,4)["max_hp"],BOSS_SKILL_D[4]*BOSS_PHASE[phase-1])
                detail_rows.append([f"{action['id']}/P{phase}",TYPES.get(command.get("damage_type",boss["stats"]["damage_type"]),command.get("damage_type","")),damage_unit(command),timing(command),f"D{d}：{status_text(command,qmin,BOSS_SKILL_D[d]*BOSS_PHASE[phase-1])}<br>D4：{status_text(command,qmax,BOSS_SKILL_D[4]*BOSS_PHASE[phase-1])}",mechanics(command),support])
        out.append(table(["技能ID","名称","命令","原系数","解锁","D0整数Q","D1整数Q","D2整数Q","D3整数Q","D4整数Q"],rows))
        out.append(table(["技能/阶段","伤害类型","单次/持续区域每跳","保留预警/锁定","有效最低D与D4状态输入","原机制与时空参数","D4绝对端点/盾/治疗"],detail_rows))
    out += ["## 6. 持续伤害、可反制窗口与奖励边界\n",
            "持续区域：duration夹0–8s、tick_interval夹0.35–2s；非投掷区域从第一个间隔开始跳，投掷区域落点立即一次再按间隔跳。表列理论次数以目标始终在区内计算；玩家已有受击无敌、离开区域与区域清理会减少实际命中。既有同施法者持久区域最多2个，三落点都落地命中但只保留最新两个持久区；不要把伤害增加解释为扩张区域数量。现状边界见 [运行实现](../../scripts/combat/enemy_skill_runtime.gd)。\n",
            "Boss弱点窗口仍使**玩家对Boss伤害**×1.35，不属于Boss对玩家增伤；窗口延迟/持续见技能表。BO03 sweep_land保留固定弱点延迟1.05s；BO04 crag_leap释放时按实际位移路程/速度更新弱点延迟。强制位移免疫保持，首领chill幅度系数0.5保持。\n",
            "召唤类Q=0表示召唤动作自身无直接伤害，召出的怪物仍按其原型独立产生攻击；召唤怪、复生怪、机关端点零金币、零经验、零历练、零装备，不计自然击杀奖励或可奖励尸体。强化后的虫卵/掩体只能提高战斗耐久，不能生成额外掉落。自然怪、房间与首领奖励另见 [奖励现状](CURRENT_REWARD_CATALOG.md) 与主方案目标表。\n",
            "## 7. 冻结来源与复现\n",
            "运行 `python tools/balance/render_target_enemy_skills.py --check`，校验36×4阶、完整命令顺序、36种精英差异、40技能/103阶段变体/有效组合、17份运行源SHA256、非负整数四舍五入和文档逐字一致。普通生成命令不读存档、不启Godot、不依赖artifacts，也不写运行数据。首次冻结/刷新须先按现状生成器隔离APPDATA与LOCALAPPDATA导出纯解析JSON，再运行 `python tools/balance/render_target_enemy_skills.py --freeze-export artifacts/balance-enemy-catalog/current.json`；这是显式维护操作。\n",
            "空间fixture坐标已从小型冻结输入移除，保留targets_count/paths_count与所有伤害、状态、时间、半径、系数及原机制标量；完整几何由带源哈希的Brain实现负责，不据此改变真实移动轨迹。\n",
            table(["来源","SHA256"],[[f"[{p}](../../{p})",h] for p,h in sorted(data["source_sha256"].items())]),
            "文档校验只证明公式与表格一致。新倍率、盾治疗叠加、整数舍入与高难度战斗体验仍需获得方案确认后实现，并以普通/精英、各Boss阶段的实际对战样本校准；当前游戏仍执行CURRENT册中的旧值。\n"]
    return "\n".join(out).rstrip()+"\n"


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,default=INPUT)
    parser.add_argument("--output",type=Path,default=OUTPUT)
    parser.add_argument("--freeze-export",type=Path)
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    if args.freeze_export:
        assert not args.check, "freeze and check are separate maintenance operations"
        data=freeze(load(args.freeze_export))
        validate(data)
        args.input.write_text(frozen_json(data),encoding="utf-8")
    else:
        data=load(args.input)
        validate(data)
    expected=render(data)
    if args.check:
        assert args.output.read_text(encoding="utf-8")==expected, f"stale document: {args.output}"
        print("PASS: 144 ordinary tiers, 40 boss actions / 103 phase variants, source hashes, integer formulas and document")
    else:
        args.output.write_text(expected,encoding="utf-8")
        print("Rendered documentation-only target enemy skill tables")


if __name__ == "__main__":
    main()
