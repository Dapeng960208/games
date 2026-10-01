#!/usr/bin/env python3
"""Export the current hero/equipment numerical appendix (standard library only).

This is documentation tooling, not game data migration. It never opens player saves.
Run without arguments to regenerate the UTF-8 document, or --check to verify it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/balance/CURRENT_HERO_EQUIPMENT_CATALOG.md"
SNAPSHOT = "8daa519f2ea1a7dcc3f422b4df96ac81d65986b9"
DATE = "2026-10-01"
INPUTS = (
    "data/heroes.json", "data/equipment.json", "data/sets.json",
    "scripts/data/content_registry.gd", "scripts/combat/stat_resolver.gd",
    "scripts/core/economy_history.gd", "scripts/core/profile_store.gd",
    "scripts/core/run_controller.gd", "scripts/combat/hero_abilities.gd",
    "scripts/combat/equipment_effects.gd", "scripts/combat/player.gd",
    "scripts/combat/room.gd", "scripts/combat/damage_resolver.gd",
    "scripts/combat/combat_status.gd", "scripts/combat/hit_chain.gd",
)
STAT_LABELS = {
    "attack": "攻击", "ability_power": "法强", "max_hp": "生命",
    "max_mana": "法力上限", "armor": "护甲", "magic_resist": "魔抗",
    "armor_penetration": "物穿", "magic_penetration": "法穿",
    "crit_multiplier": "暴伤", "true_damage_bonus": "真实附伤",
    "attack_speed": "攻速", "move_speed": "移速", "crit_chance": "暴率",
    "cooldown_reduction": "减冷却", "damage_bonus": "增伤",
    "damage_reduction": "减伤", "burn_damage": "灼烧增伤",
    "corrosion_damage_bonus": "腐蚀增伤", "status_duration": "状态延时",
}
RATIO_STATS = {
    "crit_multiplier", "attack_speed", "move_speed", "crit_chance",
    "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage",
    "corrosion_damage_bonus", "status_duration",
}
SLOT_LABELS = {
    "weapon": "武器", "head": "头部", "chest": "胸部",
    "hands": "手部", "feet": "脚部", "charm": "饰品",
}
SAMPLE = {"EQ08": 5, "EQ18": 5, "EQ28": 3, "EQ38": 1, "EQ48": 3, "EQ58": 3}


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")


def number(value: float, digits: int = 4) -> str:
    return f"{value:.{digits}f}".rstrip("0").rstrip(".") or "0"


def roundf(value: float) -> float:
    """Godot rounds half away from zero; Python's round uses ties to even."""
    return float(math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5))


def cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\r", "").replace("\n", "<br>")


def table(headers: list[str], rows: list[list[object]]) -> list[str]:
    return ["| " + " | ".join(headers) + " |",
            "| " + " | ".join("---" for _ in headers) + " |"] + [
        "| " + " | ".join(cell(v) for v in row) + " |" for row in rows
    ] + [""]


def source(path: str, fragment: str = "", start: int = 1) -> str:
    lines = read(path).splitlines()
    found = next((i for i, line in enumerate(lines, 1)
                  if i >= start and fragment in line), None)
    if found is None:
        raise ValueError(f"Missing source anchor {path}: {fragment!r}")
    return f"[{path}:{found}](../../{path}#L{found})"


def array_constant(text: str, name: str) -> list:
    match = re.search(rf"const {name}(?:\s*:[^=\n]+)?\s*:?=\s*(\[[^\n]+\])", text)
    if not match:
        raise ValueError(f"Cannot parse {name}")
    return json.loads(match.group(1))


def load() -> tuple[dict, dict, dict, dict, list[int], list[int], list[str]]:
    heroes, items, sets = [json.loads(read(path)) for path in INPUTS[:3]]
    registry = read("scripts/data/content_registry.gd")
    slots = array_constant(registry, "SLOTS")
    xp = array_constant(registry, "XP_THRESHOLDS")
    costs = array_constant(registry, "UPGRADE_COSTS")
    caps_match = re.search(r"const EQUIPMENT_CAPS: Dictionary = (\{[^\n]+\})", read("scripts/combat/stat_resolver.gd"))
    if not caps_match:
        raise ValueError("Cannot parse equipment caps")
    caps = json.loads(caps_match.group(1))
    expected = ({f"CH{i:02}" for i in range(1, 4)},
                {f"EQ{i:02}" for i in range(1, 97)},
                {f"S{i:02}" for i in range(1, 15)})
    for title, actual, required in zip(("heroes", "items", "sets"), (heroes, items, sets), expected):
        if set(actual) != required:
            raise ValueError(f"Incomplete {title}: missing {required - set(actual)}, extra {set(actual) - required}")
        if any(v["id"] != k for k, v in actual.items()):
            raise ValueError(f"Mismatched IDs in {title}")
    if slots != list(SLOT_LABELS) or len(xp) != 20 or len(costs) != 5:
        raise ValueError("Registry slot / level / enhancement structure changed")
    for sid, definition in sets.items():
        members = [item for item in items.values() if item.get("set_id") == sid]
        if len(members) != 6 or {v["slot"] for v in members} != set(slots):
            raise ValueError(f"Invalid six-slot coverage in {sid}")
        if set(definition["thresholds"]) != {"2", "4", "6"}:
            raise ValueError(f"Missing threshold in {sid}")
    for item in items.values():
        if set(item["base_stats"]) - set(STAT_LABELS):
            raise ValueError(f"Unknown stat: {item['id']}")
        if item["slot"] not in slots or not item.get("affix_text"):
            raise ValueError(f"Missing slot or fixed trait: {item['id']}")
        for value in item["base_stats"].values():
            if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise ValueError(f"Invalid base attribute: {item['id']}")
    if any(sum(item["slot"] == slot for item in items.values()) != 16 for slot in slots):
        raise ValueError("Expected sixteen templates in every current slot")
    # Fail instead of silently regenerating a table with obsolete arithmetic.
    required = {
        "scripts/combat/stat_resolver.gd": [
            "float(clampi(level, 1, 20) - 1) / 19.0", "1.0 + 0.1 * upgrade",
            'clampi(int(record.get("level", record.get("upgrade_level", 0))), 0, 5)',
            'if key in ["max_hp", "max_mana"]:', "amount = roundf(amount)",
            "float(definition.max_hp) * (1.0 + 0.20 * growth)",
            "float(definition.attack) * (1.0 + 0.10 * growth)",
            '28.0 if hero_id == "CH03" else 0.0)) * (1.0 + 0.20 * growth)',
            "float(definition.armor) + 6.0 * growth", "else 12.0)) + 6.0 * growth",
        ],
        "scripts/core/run_controller.gd": ["price += int(item.price) * 9 / 10"],
        "scripts/core/profile_store.gd": ["var worth := int(item.price) / 4", "worth += ContentRegistry.UPGRADE_COSTS[index] / 5"],
        "scripts/combat/player.gd": ['maxf(0.0, stat("ability_power", 0.0)) * 0.7 if hero_id() == "CH03"'],
    }
    for path, fragments in required.items():
        text = read(path)
        for fragment in fragments:
            if fragment not in text:
                raise ValueError(f"Formula changed: {path}: {fragment}")
    history = read("scripts/core/economy_history.gd")
    if array_constant(history, "V1_UPGRADE_COSTS") != costs:
        raise ValueError("Live and v1 upgrade costs differ; document the new economic version first")
    for name, expected_value in [
        ("V1_PRICES", {eid: item["price"] for eid, item in items.items()}),
        ("V1_SETS", {sid: sorted(eid for eid, item in items.items() if item.get("set_id") == sid) for sid in sets}),
    ]:
        match = re.search(rf"const {name} := (\{{.*?\n\}})", history, re.DOTALL)
        if not match:
            raise ValueError(f"Cannot parse historical {name}")
        actual_value = json.loads(re.sub(r",\s*([}}\]])", r"\1", match.group(1)))
        if actual_value != expected_value:
            raise ValueError(f"Live and historical {name} differ; document the economic version first")
    if roundf(6.5) != 7 or round(6.5) != 6:
        raise ValueError("roundf semantics check failed")
    return heroes, items, sets, caps, xp, costs, slots


def item_stats(item: dict, upgrade: int) -> dict[str, float]:
    result = {}
    for key, value in item["base_stats"].items():
        amount = float(value) * (1.0 + 0.1 * upgrade)
        result[key] = roundf(amount) if key in {"max_hp", "max_mana"} else amount
    return result


def format_stats(stats: dict[str, float]) -> str:
    return "；".join(f"{STAT_LABELS[key]}+{number(value * 100 if key in RATIO_STATS else value)}"
                     f"{'百分点' if key in RATIO_STATS else ''}" for key, value in stats.items()) or "—"


def runtime_skills(level: int) -> dict[str, list[dict]]:
    """Read the twelve authored base-spec dictionaries; reject unknown syntax."""
    specs = re.findall(r'data = (\{[^\n]+\})', read("scripts/combat/hero_abilities.gd"))
    if len(specs) != 12:
        raise ValueError("Runtime skill spec structure changed")
    values = []
    for spec in specs:
        result = {}
        for key, expression in re.findall(r'"([^\"]+)":("[^\"]*"|[^,}]+)', spec):
            expression = expression.strip()
            condition = re.fullmatch(r"([0-9.]+) if level >= ([0-9]+) else ([0-9.]+)", expression)
            if condition:
                result[key] = float(condition[1] if level >= int(condition[2]) else condition[3])
            elif re.fullmatch(r"[0-9.]+", expression):
                result[key] = float(expression)
            elif expression.startswith('"') and expression.endswith('"'):
                result[key] = json.loads(expression)
            else:
                raise ValueError(f"Unknown runtime skill expression: {expression}")
        values.append(result)
    return {f"CH{i + 1:02}": values[i * 4:(i + 1) * 4] for i in range(3)}


def naked(hero: dict, level: int) -> dict[str, float]:
    g = (level - 1) / 19.0
    return {"max_hp": hero["max_hp"] * (1 + 0.2 * g),
            "attack": hero["attack"] * (1 + 0.1 * g),
            "ability_power": hero.get("ability_power", 28 if hero["id"] == "CH03" else 0) * (1 + 0.2 * g),
            "armor": hero["armor"] + 6 * g,
            "magic_resist": hero.get("magic_resist", 18 if hero["id"] == "CH03" else 12) + 6 * g}


def equipment_contribution(items: dict, caps: dict, selection: dict) -> tuple[dict, dict]:
    raw: dict[str, float] = {}
    for eid, level in selection.items():
        for key, value in item_stats(items[eid], level).items():
            raw[key] = raw.get(key, 0) + value
    effective = {key: min(value, caps.get(key, 0.75 if key == "crit_chance" else value))
                 for key, value in raw.items()}
    return raw, effective


def generate() -> str:
    heroes, items, sets, caps, xp, costs, slots = load()
    digest = hashlib.sha256()
    for path in INPUTS:
        digest.update(path.encode("utf-8") + b"\0" + read(path).replace("\r\n", "\n").encode("utf-8") + b"\0")
    lines = ["# 现状数值附录（重构确认稿）：角色、等级与完整装备目录", "",
             f"记录日期：{DATE}。源快照提交：`{SNAPSHOT}`。本附录只记录该提交的实际实现，作为数值重构的对照基线；未来等级、品质、随机属性与锻造方案另见设计主册。本文件不代表新方案已经进入游戏。", "",
             "覆盖：3名角色、三职业1–20级共60行成长值、12个基础主动技能、12个永久分支选项、96件装备模板、14套套装的42个阈值。当前只有六个生效装备槽，裤子与戒指属于待开发内容。当前没有白／绿／紫／金品质、装备等级、随机主属性或随机多词条；强化等级与品质不可混记。", "",
             "由 `python tools/balance/export_hero_equipment_catalog.py` 生成；`--check` 只读校验全量覆盖、来源常量、取整规则与文档一致性，不读取玩家存档。表内显示保留至4位小数，计算不按显示值提前取整。", "",
             f"来源文件规范化内容 SHA-256：`{digest.hexdigest()}`。", "",
             "## 1. 三职业初始属性与资源", "",
             "初始值读取 " + source("data/heroes.json") + "；实际属性解析读取 " + source("scripts/combat/stat_resolver.gd", "static func resolve") + "。初始属性表为Lv.1，无装备、遗物、连击、房间道具和临时效果。", ""]
    initial = [
        ("最大生命", "max_hp", "点"), ("攻击力", "attack", "点"),
        ("法术强度", "ability_power", "点"), ("护甲", "armor", "点"),
        ("魔抗", "magic_resist", "点"), ("普攻间隔", "attack_interval", "秒"),
        ("普攻距离", "range", "世界单位"), ("移动速度", "move_speed", "世界单位/秒"),
        ("暴击率", "crit_chance", "百分比"), ("暴击伤害倍率", "crit_multiplier", "倍"),
        ("普攻弹速", "projectile_speed", "世界单位/秒"),
        ("普攻扇形角", "attack_arc_degrees", "度"),
        ("资源上限", "resource_max", "点"), ("初始资源", "starting_resource", "点"),
        ("资源自然恢复", "resource_regen", "点/秒"),
        ("资源恢复延迟", "resource_regen_delay", "秒"), ("等级上限", "level_cap", "级"),
    ]
    rows = [["ID／姓名／职业", *[f"{h['id']} {h['name']}／{h['class_name']}" for h in heroes.values()], "—"],
            ["资源种类", *[f"{h['resource_name']}（{h['resource_type']}）" for h in heroes.values()], "—"],
            ["攻击类型", *[h["attack_type"] for h in heroes.values()], "—"]]
    for label, key, unit in initial:
        values = [number(h.get(key, 0) * (100 if key == "crit_chance" else 1)) for h in heroes.values()]
        rows.append([label, *values, unit])
    rows += [["最大法力（解析后）", 0, 0, 100, "点"],
             ["护甲减伤（裸装）", *[number(h["armor"] / (100 + h["armor"]) * 100) for h in heroes.values()], "%"],
             ["魔抗减伤（裸装）", *[number(h["magic_resist"] / (100 + h["magic_resist"]) * 100) for h in heroes.values()], "%"]]
    lines += table(["属性", *[f"{h['id']} {h['name']}／{h['class_name']}" for h in heroes.values()], "单位"], rows)
    lines += ["`magic_resist` 数据现在明确为12／10／18。若缺失，运行解析回退为CH03=18、其他职业=12，因此CH02缺字段时会变成12，不能把fallback写成其当前初始10。`ability_power` 缺失时CH03回退28，其余为0。装备物穿、法穿、真实附伤、攻速／移速加成、减冷却、增伤、装备减伤、灼烧／腐蚀增伤、状态延时的初始贡献均为0；最大法力只对mana职业成立，其他两职业的`max_mana=0`。法师解析后的初始法力填满资源上限。", "",
             "**H与普攻必须区分：**技能H定义为战士／枪手攻击力，法师`攻击力+0.7×法强`，法师Lv.1技能H=18+0.7×28=37.6。三职业原始普攻都只使用攻击力（法师初始18）；法师普攻不会自动加0.7法强。装备事件的H来自本次`context.power`，原始普攻是攻击快照，技能命中则可为技能H。原始攻击X是当前击次暴击与增伤前的原始伤害快照，不能把X直接等同固定法强。见 " + source("scripts/combat/player.gd", "func skill_power") + "、" + source("scripts/combat/room.gd", "func fire_from_player") + "、" + source("scripts/combat/room.gd", "func resolve_direct_hit") + "。", "",
             "战士原始普攻前摇固定0.12秒，真实命中半径105、扇形100°、基础击退12；枪手／法师提交普攻时立即出弹，枪口显示0.07秒，不另增加攻击等待，真实弹速分别950／720。自动普攻筛选范围为战士100、枪手630、法师460，与最终普攻射程分开。来源：" + source("scripts/combat/player.gd", "func auto_attack_range") + "、" + source("scripts/combat/player.gd", "func fire(") + "。", "",
             "### 1.1 普攻动作、资源规则与职业被动", ""]
    for hid, hero in heroes.items():
        lines += [f"#### {hid} {hero['name']} · {hero['class_name']}", ""]
        if "attack_timing" in hero:
            lines += table(["普攻动作字段", "值（秒）"], [[k, number(v)] for k, v in hero["attack_timing"].items()])
        if "resource_rules" in hero:
            lines += table(["资源规则字段", "值"], [[k, number(v)] for k, v in hero["resource_rules"].items()])
        passive = hero["passive"]
        lines += [f"**{passive['name']}：**{passive['description']}", ""]
        lines += table(["被动数值字段", "值"], [[k, number(v)] for k, v in passive.items() if isinstance(v, (int, float))])
    lines += ["### 1.2 闪避初始参数", "",
              "数值来自`heroes.json`内各角色`dash`；距离与速度使用世界单位，所有时间单位为秒，无敌窗按闪避动作计时。", ""]
    lines += table(["字段", "战士·钢步", "枪手·滑索步", "法师·折光步"],
                   [[key, *[number(h["dash"][key]) for h in heroes.values()]]
                    for key in ["distance", "duration", "windup", "recovery", "invincible_start", "invincible_end", "cooldown", "cost"]])
    lines += ["## 2. 当前等级收益、经验与技能节点", "",
              "当前成长是硬编码的满级总增量，并非每级20%／10%。`g=(clamp(L,1,20)-1)/19`；下表全部按真实解析公式复算。来源：" + source("scripts/combat/stat_resolver.gd", "var growth :=") + "。", ""]
    lines += table(["属性", "运行公式（无装备）", "每升一级的确定增量", "数据growth声明"], [
        ["生命", "HP₀×(1+0.20g)", "HP₀×0.20/19", "max_hp_ratio_at_cap=0.2；运行没有读取该字段"],
        ["攻击", "AD₀×(1+0.10g)", "AD₀×0.10/19", "attack_ratio_at_cap=0.1；运行没有读取该字段"],
        ["法强", "AP₀×(1+0.20g)", "AP₀×0.20/19", "growth没有AP声明；运行硬编码20%"],
        ["护甲", "Armor₀+6g", "6/19≈0.3158", "armor_at_cap=6；运行没有读取该字段"],
        ["魔抗", "MR₀+6g", "6/19≈0.3158", "growth没有魔抗声明；运行硬编码+6"],
        ["暴击、间隔、射程、移动、资源", "保持初始定义，装备另行增加", "0", "没有等级自动成长"],
    ])
    for hid, hero in heroes.items():
        lines += [f"### 2.{list(heroes).index(hid) + 1} {hid} {hero['name']} 1–20级裸装表", ""]
        rows = []
        for level in range(1, 21):
            stats = naked(hero, level)
            h = stats["attack"] + (0.7 * stats["ability_power"] if hid == "CH03" else 0)
            rows.append([level, *[number(stats[k]) for k in ["max_hp", "attack", "ability_power", "armor", "magic_resist"]], number(h)])
        lines += table(["等级", "生命", "攻击／普攻基值", "法强", "护甲", "魔抗", "技能H"], rows)
    lines += ["### 2.4 经验累计阈值与每级需求", "",
              "阈值是累计经验；达到阈值即进入该级。最高3600经验对应20级。`next_level_xp(L)`返回下一等级累计目标，20级仍返回3600，不表示还能升级。来源：" + source("scripts/data/content_registry.gd", "const XP_THRESHOLDS") + "、" + source("scripts/data/content_registry.gd", "static func level_for_xp") + "。", ""]
    lines += table(["等级", "到达该级累计XP", "上一级→本级需求", "本级→下一级需求"],
                   [[i + 1, v, v - xp[i - 1] if i else "—", xp[i + 1] - v if i < 19 else "满级"] for i, v in enumerate(xp)])
    lines += ["8→9级需要270XP，7→8级只需70XP；当前曲线确有突增。新单种族远征死亡丢弃未结算经验，已结算等级与经验保留；本附录不读取玩家的等级、经验或库存。", "",
              "### 2.5 全部技能基础参数与等级节点", "",
              "下表技能成本／冷却是无减冷却的基础定义，H系数在上文定义；完整mechanics逐字段列出，距离为世界单位、角度为度、时间为秒。实际释放参数由 " + source("scripts/combat/hero_abilities.gd", "func spec") + " 构建；冷却再乘`1-clamp(CDR,0,0.30)`。战士满3层破势释放W的实时成本为0，目录预览仍显示通常成本。", ""]
    for hid, hero in heroes.items():
        lines += [f"#### {hid} {hero['class_name']} 技能", ""]
        lines += table(["按键／内部槽", "名称", "解锁等级", "通常成本", "基础冷却（秒）", "完整基础mechanics"],
                       [[f"{s['input']}／{slot}", s["name"], s["unlock"], s["cost"], number(s["cooldown"]),
                         "；".join(f"{k}={json.dumps(v, ensure_ascii=False, separators=(',', ':'))}" for k, v in s.get("mechanics", {}).items())]
                        for slot, s in hero["skills"].items()])
        live1, live20 = runtime_skills(1)[hid], runtime_skills(20)[hid]
        lines += ["运行基准规格（未选分支、未消费破势、未应用装备／临时效果；Lv.1行仅表示基础规格，仍遵守技能解锁门槛）：", ""]
        lines += table(["按键", "运行伤害系数Lv.1→20", "总动作秒Lv.1→20", "前摇秒", "施法移速比例Lv.1→20", "运行专属参数Lv.1→20"],
                       [[skill["input"], f"{number(a['coefficient'])}→{number(b['coefficient'])}H", f"{number(a['duration'])}→{number(b['duration'])}", number(a["windup"]),
                         f"{number(a['movement'] * 100)}%→{number(b['movement'] * 100)}%",
                         "；".join(f"{k}={number(a[k])}→{number(b[k])}" for k in a if k not in {"name", "cost", "cooldown", "coefficient", "duration", "windup", "movement"})]
                        for skill, a, b in zip(hero["skills"].values(), live1, live20)])
        lines += table(["按键", "完整技能机制与条件说明（含资源／命中／派生限制）"],
                       [[skill["input"], skill["description"]] for skill in hero["skills"].values()])
        lines += table(["等级", "技能", "参数变化与收益"], [[v["level"], hero["skills"][v["skill"]]["input"], v["description"]] for v in hero["upgrades"]])
        lines += table(["永久等级门槛", "技能／分支", "名称", "完整变化（含代价）"],
                       [[gate, f"{'Q' if gate == '18' else 'R'}／{bid}", branch["name"], branch["description"]]
                        for gate, options in hero["branches"].items() for bid, branch in options.items()])
    lines += ["技能目录文案与运行细节：CH01 E运行`guard_duration=1.5`指短时减伤，职业护盾仍持续4秒。CH01 R-B运行总动作`duration=1.02`，两波释放时刻相隔0.20秒；不能只将文案收势0.25秒误当总动作时长。CH02 Q的`mechanics`未声明弹速，运行明确使用950；CH02 R-B保留每发1.2H、改3发，共3.6H，R-A每发1.5H、4发，共6H并限制移动。CH03 R标准理论总量0.6+5×0.8=4.6H；R-A=0.6+7×0.65=5.15H；R-B=0.6+4×0.65=3.2H，需实际留场命中。", "",
              "正式Q分支仍在18级、R分支在20级开放，并且只有合法A／B选择才改变实际技能；见 " + source("scripts/combat/hero_abilities.gd", "func _branch") + "、" + source("scripts/combat/hero_abilities.gd", "func _apply_branch") + "。营地Lv.8完整技能试玩和独立Lv.20分支试玩使用一次性fresh_profile，结束恢复正式档；试玩奖励、装备与分支均不写入正式成长档，不能把试玩记作永久提前解锁。来源：" + source("scripts/core/run_controller.gd", "var trial :=") + "。", "",
              "## 3. 全部96件装备：属性、强化与固定特性", "",
              "**当前计算顺序：**对每件已拥有且槽位匹配的模板，强化级U钳制到0–5；主属性`a=base_stats×(1+0.1U)`。仅生命／法力容量对每件先调用`roundf(a)`，其他属性保留小数；然后跨装备求和，最后执行装备贡献上限。固定条件特性与套装触发效果不乘强化倍率，也不会自动加入静态面板。来源：" + source("scripts/combat/stat_resolver.gd", "var multiplier :=") + "。", "",
              "`roundf`采用0.5远离零的取整，6.5→7；Python默认`round(6.5)`→6不可用于复算。以下数值是单件贡献，未施加全套上限。百分比型属性使用**百分点**表示加法贡献，例如暴率4%在+5变成6个百分点，最终是在角色初始5%上增加6个百分点。攻速／移速的百分点是倍率桶贡献，不能把10个百分点理解为减少10%攻击间隔。", "",
              "EQ01–EQ60记录本族来源；EQ61–EQ96是商城限定套装，当前JSON未给race_id，不能凭美术推断掉落种族。所有模板允许在合法槽位装备，掉落适配另由职业属性筛选控制；购买首领门槛逐件记录，不等同本族掉落是否可选。基础值以`base_stats`为准，不能从中文描述倒推。", ""]
    for slot in slots:
        selected = [(eid, item) for eid, item in items.items() if item["slot"] == slot]
        lines += [f"### 3.{slots.index(slot) + 1} {SLOT_LABELS[slot]}（{len(selected)}件）", "", "目录与来源：", ""]
        lines += table(["ID", "名称", "种族／来源", "套装", "单价", "购买首领门槛"],
                       [[eid, item["name"], "商城限定／无种族字段" if item.get("shop_only") else f"{item.get('race_id', '未声明')} {item.get('race_name', '')}",
                         item.get("set_id") or "无套装", item["price"], item.get("unlock_boss") or "无"] for eid, item in selected])
        lines += ["全部静态基础属性与强化后单件贡献：", ""]
        lines += table(["ID", "+0 基础", "+1（×1.1）", "+3（×1.3）", "+5（×1.5）"],
                       [[eid, *[format_stats(item_stats(item, u)) for u in [0, 1, 3, 5]]] for eid, item in selected])
        lines += ["固定条件特性（原始完整文案，强化不增加触发系数）：", ""]
        rows = []
        for eid, item in selected:
            passive = item.get("combat_passive")
            runtime = source("scripts/combat/equipment_effects.gd", 'var passive: Dictionary = Registry.equipment') if passive else source("scripts/combat/equipment_effects.gd", f'"{eid}"', 190)
            extra = "；".join(f"{k}={v}" for k, v in passive.items()) if passive else "事件特性"
            rows.append([eid, item["affix_text"], extra, runtime])
        lines += table(["ID", "完整固定特性", "结构化条件／实现方式", "运行来源"], rows)
    lines += ["### 3.7 条件与触发收益的公共计算限制", "",
              "当前‘主攻击’由装备事件 eligibility、原始深度与来源校验，不意味着每个特性只接受普攻；需要原始普攻计数的特性另用`_basic`。派生装备／状态／遗物伤害不再递归触发原始命中链。来源：" + source("scripts/combat/equipment_effects.gd", "func _eligible") + "。", ""]
    lines += table(["机制", "当前真实规则", "来源"], [
        ["静态属性", "只读base_stats；固定特性、套装、临时状态分开结算", source("scripts/combat/stat_resolver.gd", "var base_stats:")],
        ["商城被动条件", "shielded：盾>0；moving：实际移动；resource_half：资源上限>0且当前≥50%；full_hp：满血；injured：0<HP<满；low_hp：0<HP≤50%", source("scripts/combat/equipment_effects.gd", "func _shop_condition")],
        ["条件桶上限", "增伤60%、总暴率75%、装备攻速60%、移速45%、装备减伤35%、状态时长40%；条件只占扣除已有静态贡献后的剩余额度", source("scripts/combat/equipment_effects.gd", "func _cap_modifiers")],
        ["附加伤害X", "使用本击原始伤害快照；不再暴击；每根原始事件共享最多4个触发包、所有目标装备附伤系数合计≤1.2X", source("scripts/combat/equipment_effects.gd", "func _bonus")],
        ["护盾", "各来源保持独立期限、有效量取较强来源，不直接相加；装备盾单次比例钳制≤35%生命、默认4秒", source("scripts/combat/equipment_effects.gd", "func _shield")],
        ["装备治疗", "最近1秒合计最多3%最大生命，不能超过缺失生命；重伤另乘0.6", source("scripts/combat/equipment_effects.gd", "func _heal")],
        ["装备资源恢复", "每次按职业怒气1／能量2／法力3，ICD3秒；最近5秒合计≤资源上限20%，且不超过缺失资源", source("scripts/combat/equipment_effects.gd", "func _restore_resource")],
        ["冷却返还", "主动技能只选择剩余冷却最长者；闪避返还仅作用闪避；最近1秒合计返还≤0.50秒，不超过实际剩余冷却", source("scripts/combat/equipment_effects.gd", "func _refund")],
        ["状态授予", "腐蚀基础4秒，其余基础3秒；持续时间=基础×(1+min(40%,静态时长+寒冷套装时长))", source("scripts/combat/equipment_effects.gd", "func _status")],
        ["直接伤害", "原始伤害×(1+min(60%,增伤桶))×暴击倍率×连击倍率；随后按实际伤害类型过抗性／穿透和减伤", source("scripts/combat/room.gd", "var final_amount:")],
        ["连击倍率", "合格原始直接攻击有效命中积层，同一攻击多敌只计一次；1+0.005×层数，最高100层／+50%，4秒断连；本击使用命中前层数", source("scripts/combat/hit_chain.gd", "func multiplier")],
        ["抗性与穿透", "有效抗性=max(0,抗性−对应平坦穿透)；伤害×100/(100+有效抗性)×(1−通用减伤)，通用减伤≤65%；真实伤害跳过双抗与减伤", source("scripts/combat/damage_resolver.gd", "static func resolve")],
        ["真实附伤", "原始合格命中确认且目标仍存活后追加；不暴击，不参与装备递归链；不是攻击力或H加值", source("scripts/combat/room.gd", "var true_bonus:")],
    ])
    lines += ["## 4. 全部14套套装与2／4／6件效果", "",
              "阈值同时累计成立：六件满足2、4和6件，但仍受条件、目标存活、预算与ICD限制。下表完整保留`sets.json`文本；附带的`shop_passive`是新商城套装2件效果的结构化实现，不应再重复加一次2件文本收益。来源：" + source("data/sets.json") + "、" + source("scripts/combat/equipment_effects.gd", "func _has_set") + "。", ""]
    for sid, definition in sets.items():
        members = sorted(eid for eid, item in items.items() if item.get("set_id") == sid)
        lines += [f"### {sid} {definition['name']}", "",
                  f"成员：{'、'.join(members)}。种族：{definition.get('race_id', '未声明（商城限定）')}。目录套装解锁字段：{definition.get('unlock_boss') or '无'}。", ""]
        lines += table(["阈值", "完整效果"], [[f"{u}件", definition["thresholds"][u]["text"]] for u in ["2", "4", "6"]])
        if definition.get("shop_passive"):
            lines += ["2件结构化被动：`" + json.dumps(definition["shop_passive"], ensure_ascii=False, separators=(",", ":")) + "`。", ""]
    lines += ["## 5. 当前装备上限与购买／强化／回收经济", "",
              "### 5.1 装备贡献与角色总值上限", "",
              "贡献上限发生在单件强化和求和之后；它限制装备部分，角色基础与成长在之后相加。来源：" + source("scripts/combat/stat_resolver.gd", "const EQUIPMENT_CAPS") + "、" + source("scripts/combat/stat_resolver.gd", "static func clamp_equipment_contributions") + "。", ""]
    lines += table(["属性桶", "装备贡献上限", "补充"],
                   [[STAT_LABELS[key], number(value * 100) + "百分点" if key in RATIO_STATS else number(value),
                     "角色总暴伤最终钳制1–2.5倍" if key == "crit_multiplier" else "静态与条件共享上限" if key in {"attack_speed", "move_speed", "damage_bonus", "damage_reduction", "status_duration"} else "—"]
                    for key, value in caps.items()] + [["暴击率", "75个百分点", "角色基础+装备+条件总暴率最终≤75%"]])
    lines += ["生命容量不对总值取整；逐件生命装备贡献已经roundf，等级生命保留小数。实际普攻间隔=`初始间隔/(1+攻速桶)`，移动速度=`初始速度×(1+移速桶)`；减冷却乘技能基础冷却，减伤按防御公式作用。", "",
              "### 5.2 强化金币与取整示例", "",
              "当前只需金币，强化必成；最高+5，全部基础属性每级乘数增加0.1，固定特性不变。已全数触达对应贡献上限时阻止无收益支出；因HP／法力取整导致的一次平平台阶仍允许强化。来源：" + source("scripts/data/content_registry.gd", "const UPGRADE_COSTS") + "、" + source("scripts/core/run_controller.gd", "func upgrade_has_gain") + "。", ""]
    lines += table(["目标强化", "本次金币", "从+0累计金币", "基础属性倍率", "回收可返强化金币累计"],
                   [[f"+{u}", costs[u - 1], sum(costs[:u]), number(1 + 0.1 * u), sum(c // 5 for c in costs[:u])] for u in range(1, 6)])
    rounding_rows = []
    for eid, item in items.items():
        for key in ["max_hp", "max_mana"]:
            if key not in item["base_stats"]:
                continue
            for u in [1, 3, 5]:
                raw = item["base_stats"][key] * (1 + 0.1 * u)
                if roundf(raw) != round(raw):
                    rounding_rows.append([eid, STAT_LABELS[key], f"+{u}", number(raw), number(roundf(raw)), number(round(raw))])
    lines += [f"Godot与Python银行家舍入产生不同结果的目录组合（共{len(rounding_rows)}项，限本表展示的+1／+3／+5）：", ""]
    lines += table(["ID", "属性", "强化", "未取整", "真实roundf", "错误的Python round"], rounding_rows)
    lines += ["### 5.3 单件、整套补齐与出售", "",
              "整套报价只累计缺件，各缺件按`int(price)×9/10`整数运算折价；已拥有件不再收费，也不重置强化。出售=`单件基础购买价/4`整数运算+每个已完成强化步骤金币`cost/5`整数运算。当前模板所有价格与成本均可被对应分母整除。历史交易校验使用冻结经济版本v1，不能随新设计价格重算旧凭据。来源：" + source("scripts/core/run_controller.gd", "func equipment_set_quote") + "、" + source("scripts/core/profile_store.gd", "static func equipment_sell_price") + "、" + source("scripts/core/economy_history.gd", "const CURRENT_VERSION") + "。", ""]
    lines += table(["槽位／类型", "基础购买价", "整套缺件折价", "+0出售", "+1出售", "+3出售", "+5出售"],
                   [[label, price, price * 9 // 10, *[price // 4 + sum(c // 5 for c in costs[:u]) for u in [0, 1, 3, 5]]]
                    for label, price in [("六槽通用A", 60), ("六槽通用B", 100), ("套装武器／胸", 180), ("套装头", 140), ("套装手／脚", 120), ("套装饰", 160)]])
    lines += table(["套装", "六件基础总价", "全缺九折价", "全套+0出售", "全套+5强化成本", "全套+5出售"],
                   [[f"{sid} {definition['name']}", sum(i["price"] for i in items.values() if i.get("set_id") == sid),
                     sum(i["price"] * 9 // 10 for i in items.values() if i.get("set_id") == sid),
                     sum(i["price"] // 4 for i in items.values() if i.get("set_id") == sid),
                     6 * sum(costs), sum(i["price"] // 4 for i in items.values() if i.get("set_id") == sid) + 6 * sum(c // 5 for c in costs)] for sid, definition in sets.items()])
    lines += ["示例：已拥有S06武器EQ08和头EQ18，只买胸／手／脚／饰，缺件原价580、逐件九折为162+108+108+144=522；已拥有武器／头保持原强化。购买全套价810，强化每件+5共5400，全套+5出售为225+6×180=1305。买卖和重复撤离奖励按模板记录而非独立实例，这是现状，未来重构必须迁移。", "",
              "## 6. S06六件实际配装复算", "",
              "本例由用户截图讨论的模板与明确指定强化组合复算，**不读取玩家存档**：EQ08+5、EQ18+5、EQ28+3、EQ38+1、EQ48+3、EQ58+3；职业CH01。该组合攻击贡献17.5、真实附伤5.6、减冷却6个百分点、装备减伤11.7个百分点。这里不会把S06条件触发效果算进无条件攻击面板。", ""]
    lines += table(["部位", "ID", "强化", "单件静态贡献", "从+0强化支出"],
                   [[SLOT_LABELS[items[eid]["slot"]], eid, f"+{u}", format_stats(item_stats(items[eid], u)), sum(costs[:u])] for eid, u in SAMPLE.items()])
    raw, effective = equipment_contribution(items, caps, SAMPLE)
    lines += ["套装原始贡献：" + format_stats(raw) + "。各项均未碰到当前贡献上限；有效贡献与原始贡献相同。", ""]
    sample_rows = []
    for level in [13, 18, 20]:
        base = naked(heroes["CH01"], level)
        for key in ["attack", "max_hp", "armor", "magic_resist", "ability_power"]:
            added = effective.get(key, 0)
            sample_rows.append([level, STAT_LABELS[key], number(base[key]), number(added), number(base[key] + added)])
    lines += table(["等级", "属性", "裸装真实值", "装备静态增量", "配装后真实值"], sample_rows)
    lines += table(["等级", "物理综合减伤", "魔法综合减伤", "暴率／暴伤", "普攻间隔", "Q／W／E／R冷却（秒）"],
                   [[level, number((1 - 100 / (100 + naked(heroes["CH01"], level)["armor"]) * (1 - effective["damage_reduction"])) * 100) + "%",
                     number((1 - 100 / (100 + naked(heroes["CH01"], level)["magic_resist"]) * (1 - effective["damage_reduction"])) * 100) + "%",
                     "5%／1.5倍", "0.5秒", "／".join(number(c * (1 - effective["cooldown_reduction"])) for c in [6, 4, 11, 42])]
                    for level in [13, 18, 20]])
    lines += ["13→18级攻击只增加`27×0.10×5/19=0.7105`，配装攻击从46.2053变为46.9158；18→20级只增加0.2842。上述静态装备不提供生命、护甲、魔抗、法强、暴击或攻速。真实附伤5.6以独立真实伤害包进入合格原始命中，不应直接显示成攻击+5.6。", "",
              "### 6.1 条件收益与低可见度原因", ""]
    lines += table(["来源", "当前可得收益", "实际限制"], [
        ["EQ08+5", "冲刺后首个主攻击击退×1.25；ICD4秒", "运行冲刺窗3秒；强化不提升25%击退；首领免击退不会转成伤害"],
        ["EQ18+5", "敌人打破护盾后下一主攻击击退×1.30；ICD8秒", "运行破盾窗3秒；须实际盾吸收且敌人伤害破盾；无伤害收益"],
        ["EQ28+3", "当前移速低于基础时，受击退×0.75", "受减速时才有效；不额外提高伤害减免"],
        ["EQ38+1", "冲刺后首个主攻击命中寒冷目标，附加0.2X单体；ICD5秒", "运行冲刺窗3秒；战士自身普通技能不稳定提供寒冷；错过目标条件会消耗首击窗口"],
        ["EQ48+3", "冲刺结束获得2%最大生命护盾；ICD6秒", "4秒持续；来源护盾按较强值，不把多个2%相加；与S06冲刺前有盾条件不是同一时点"],
        ["EQ58+3", "命中寒冷目标获得2%最大生命护盾；ICD6秒", "需寒冷目标，4秒持续；不会因强化提升2%比例"],
        ["S06 2件", "有盾时主攻击击退×1.20", "首领免击退；不提高面板攻击；与EQ08/EQ18符合时乘算"],
        ["S06 4件", "有盾冲刺后2秒内首个主攻击直接增伤12%；ICD3秒", "冲刺发生时盾>0，命中时也要求盾>0；只限首个原始攻击窗口"],
        ["S06 6件", "敌人破盾后5秒内下一主攻击对最多3名目标各追加0.4X；ICD8秒", "敌人必须真正打破且吸收盾伤；派生不暴击、不递归，所有目标合计与其他装备共享1.2X预算"],
    ])
    lines += ["S06对应窗口/破盾行为来源：" + source("scripts/combat/equipment_effects.gd", "func _before") + "、" + source("scripts/combat/equipment_effects.gd", "func _dash") + "、" + source("scripts/combat/equipment_effects.gd", "func _damaged") + "。这个例子表明主要成长是基础静态数值、小幅减冷却与减伤；套装的大部分收益受击退、盾前置、破盾和寒冷条件限制。", "",
              "## 7. 复算与校验边界", "",
              "校验命令：`python tools/balance/export_hero_equipment_catalog.py --check`。生成器检查3／96／14完整ID、所有六槽覆盖、42套装阈值、20经验阈值、5强化费用、源公式关键常量及Godot roundf差异，再逐字对比整份生成结果。JSON、源码或任一表格变化时，应先核对运行规则，再更新本附录；不靠手工改一行表掩盖数据漂移。", "",
              "这是静态数值与事件规则附录，不代表自然战斗、装备构筑或长期留存已经验证。具体敌人／首领属性、当前与未来掉落随机比例、未来等级与锻造规则由独立附录和主设计册记录。当前源码只有固定模板预强化，没有已实现的随机属性比例可列为现状。", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate without writing files")
    args = parser.parse_args()
    try:
        result = generate()
        if args.check:
            if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != result:
                print("FAIL: catalog differs from source; regenerate after reviewing changes", file=sys.stderr)
                return 1
            print("PASS: 3 heroes / 60 level rows / 96 templates / 14 sets / 42 thresholds; formulas and roundf verified")
        else:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_text(result, encoding="utf-8", newline="\n")
            print(f"Generated {OUTPUT.relative_to(ROOT).as_posix()}")
        return 0
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
