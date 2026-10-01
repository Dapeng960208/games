#!/usr/bin/env python3
"""Render current runtime enemy calibration without changing frozen target books.

Uses only the standard library. Default writes RUNTIME_CALIBRATION_TABLES.md;
--check detects parameter/archive/source drift, and --self-test checks arithmetic
and rejects an unarchived calibration. No Godot, player saves, or simulations.
"""
from __future__ import annotations

import argparse
from decimal import Decimal, ROUND_HALF_UP, getcontext
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
getcontext().prec = 80
OUTPUT = "docs/balance/RUNTIME_CALIBRATION_TABLES.md"
SNAPSHOT = "8daa519f2ea1a7dcc3f422b4df96ac81d65986b9"
FROZEN = {
    "docs/balance/current_enemy_initial_values.json": "513e43fc73767a8c2d0ce8e97f5f6c046d275864023eb5e21f229500d06a7895",
    "docs/balance/current_enemy_skill_inputs.json": "54bc69502d2fd31738b4b08cbcbb36135b9ce48afb23563c49b1cc3822c61611",
}
CURRENT = (
    "data/numerical_v2.json", "data/enemy_progression.json",
    "scripts/combat/enemy_calibration.gd", "scripts/combat/enemy_numerical_v2.gd",
    "scripts/combat/enemy_profiles.gd", "scripts/combat/boss_profiles.gd",
)
RANKS = ("normal", "elite", "boss")
FACTORS = ("hp", "attack", "skill")
CHAPTERS = tuple(f"B{i:02}" for i in range(1, 5))
TIERS = (1, 5, 10, 15)
DAMAGE_KINDS = {"melee", "charge", "projectile", "ground_area", "pull", "counter"}
STAT_KEYS = ("max_hp", "damage", "armor", "magic_resist")
STATUS_RATIOS = {"burn": Decimal(".12"), "corrosion": Decimal(".08"),
                 "bleed": Decimal(".10"), "shock": Decimal(".25")}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decimal(value):
    require(not isinstance(value, bool) and isinstance(value, (int, Decimal)),
            f"Expected a JSON number, got {value!r}")
    result = Decimal(value)
    require(result.is_finite(), f"Non-finite number: {value}")
    return result


def integer(value):
    value = decimal(value)
    require(value >= 0, "Cannot round a negative combat value")
    return int(value.quantize(Decimal(1), rounding=ROUND_HALF_UP))


def number(value):
    return format(decimal(value).normalize(), "f")


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"), parse_float=Decimal,
                      parse_constant=lambda token: (_ for _ in ()).throw(ValueError(token)))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table(headers, rows):
    def cell(value):
        return str(value).replace("|", "\\|").replace("\n", "<br>")
    return "\n".join(["| " + " | ".join(headers) + " |",
                       "| " + " | ".join("---" for _ in headers) + " |"] +
                      ["| " + " | ".join(cell(v) for v in row) + " |" for row in rows]) + "\n\n"


def archive_entries(path):
    """Read the archive's data literal; never execute or rewrite GDScript."""
    text = path.read_text(encoding="utf-8")
    start = re.search(r"(?m)^const ARCHIVES\s*:=\s*\{", text)
    require(start is not None, "Unsupported enemy calibration archive declaration")
    begin = start.end() - 1
    depth = 0
    quoted = escaped = comment = False
    chars = []
    for char in text[begin:]:
        if comment:
            if char == "\n":
                comment = False
                chars.append(char)
            continue
        if not quoted and char == "#":
            comment = True
            continue
        chars.append(char)
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
    require(depth == 0 and not quoted, "Unterminated calibration archive")
    literal = "".join(chars)
    literal = re.sub(r'([,{]\s*)(\d+)\s*:', r'\1"\2":', literal)
    literal = re.sub(r",\s*([}\]])", r"\1", literal)
    return json.loads(literal, parse_float=Decimal)


def validate_calibration(snapshot, archives):
    require(isinstance(snapshot, dict) and set(snapshot) == {"version", "chapters"},
            "Current calibration requires exactly version/chapters")
    version = decimal(snapshot["version"])
    require(version == int(version) and 1 <= version <= 1000, "Invalid calibration version")
    archive = archives.get(str(int(version)))
    require(isinstance(archive, dict), f"Calibration version {version} has no immutable archive")
    require(set(snapshot["chapters"]) == set(CHAPTERS) and set(archive) == set(CHAPTERS),
            "Exactly four implemented calibration chapters are required")
    for chapter in CHAPTERS:
        ranks = snapshot["chapters"][chapter]
        require(isinstance(ranks, dict) and set(ranks) == set(RANKS), f"Bad ranks: {chapter}")
        for rank in RANKS:
            factors = ranks[rank]
            require(isinstance(factors, dict) and set(factors) == set(FACTORS), f"Bad factors: {chapter}/{rank}")
            for key in FACTORS:
                actual = decimal(factors[key])
                archived = decimal(archive[chapter].get(rank, {}).get(key, 1))
                require(Decimal(".05") <= actual <= 10 and actual == archived,
                        f"Unarchived or out-of-range factor: {chapter}/{rank}/{key}")


def tier_index(level):
    return max(index for index, threshold in enumerate(TIERS) if level >= threshold)


def chapter_for(identifier):
    return int(identifier[2:]) if identifier.startswith("BO") else (int(identifier[1:]) - 1) // 9 + 1


def factor(config, chapter, rank, key):
    return decimal(config["enemy_calibration"]["chapters"][f"B{chapter:02}"][rank][key])


def chapter_factor(config, chapter, key):
    return 1 + decimal(config["chapter_hp_per_step" if key == "max_hp" else "chapter_damage_per_step"]) * (chapter - 1)


def resolved_stats(config, source, chapter, rank, difficulty):
    """Actor boundary: every factor, including calibration, precedes one I()."""
    output = {}
    for key, d_key, tune_key in (("max_hp", "difficulty_hp_multipliers", "hp"),
                                 ("damage", "difficulty_damage_multipliers", "attack")):
        product = (decimal(source[key]) * decimal(config["enemy_baseline_multiplier"][key]) *
                   decimal(config["combat_scale"]) * chapter_factor(config, chapter, key) *
                   decimal(config[d_key][difficulty]) * factor(config, chapter, rank, tune_key))
        output[key] = integer(product)
    for key, cap in (("armor", 24), ("magic_resist", 32)):
        defense = decimal(source[key])
        if rank != "boss":
            defense = min(Decimal(cap), defense)
        output[key] = integer((defense + (3 if rank == "boss" else 2) * difficulty) * decimal(config["combat_scale"]))
    return output


def ordinary_source(enemy, level, rank, growth):
    """Lv1 seeds already include identity/elite factors; never apply them twice.

    HP/A are linear within 1..20; defenses are authored per mechanic tier.
    Derive from unrounded seeds, never from a rounded V2 D0 actor.
    """
    start = enemy["tiers"][0]["profiles"][rank]
    tier = enemy["tiers"][tier_index(level)]
    source = dict(tier["profiles"][rank])
    source["max_hp"] = decimal(start["max_hp"]) * (1 + decimal(growth["hp_per_level"]) * (level - 1))
    source["damage"] = decimal(start["damage"]) * (1 + decimal(growth["damage_per_level"]) * (level - 1))
    return source, tier


def skill_factor(config, chapter, rank, difficulty, level=None, phase=1):
    if rank == "boss":
        base = decimal(config["boss_skill_difficulty_multipliers"][difficulty]) * decimal(config["boss_skill_phase_multipliers"][phase - 1])
    else:
        base = decimal(config["ordinary_skill_tier_multipliers"][tier_index(level)]) * decimal(config["ordinary_skill_difficulty_multipliers"][difficulty])
    return base * factor(config, chapter, rank, "skill")


def commands(tier, rank):
    if rank == "normal":
        return tier["commands"]
    change = tier["elite_delta"]
    return change["replace"] if "replace" in change else tier["commands"] + change["append"]


def packet(command, attack, strength):
    if command["kind"] not in DAMAGE_KINDS or (command["kind"] == "counter" and not command.get("auto_release", True)):
        return 0
    return integer(decimal(attack) * decimal(command.get("damage_multiplier", 1)) * strength)


def extras(command, damage, strength, scale):
    output = []
    for key in ("anchor_health", "cover_hp", "pod_health", "pod_break_armor_loss"):
        if key not in command or (key == "cover_hp" and "anchor_health" in command):
            continue
        value = integer(decimal(command[key]) * scale * (1 if key == "pod_break_armor_loss" else strength))
        if key in ("anchor_health", "cover_hp"):
            value = min(800, max(10, value))
        output.append(f"{key}={value}")
    state = command.get("status", {})
    if state.get("id") in STATUS_RATIOS:
        power = integer(decimal(state["power"]) * scale * strength) if "power" in state else damage
        output.append(f"{state['id']}: power={power}, tick={integer(power * STATUS_RATIOS[state['id']])}")
    return "; ".join(output) or "—"


def context(root):
    hashes = {}
    for path, expected in FROZEN.items():
        actual = digest(root / path)
        require(actual == expected, f"Immutable input changed: {path}; review lineage before regenerating")
        hashes[path] = actual
    for path in CURRENT:
        hashes[path] = digest(root / path)
    initial = load(root / "docs/balance/current_enemy_initial_values.json")
    frozen = load(root / "docs/balance/current_enemy_skill_inputs.json")
    require(initial["source_snapshot"] == frozen["source_snapshot"] == SNAPSHOT, "Wrong frozen source commit")
    require(initial["source_sha256"] == frozen["source_sha256"], "Frozen source manifests disagree")
    progression = load(root / "data/enemy_progression.json")
    require(digest(root / "data/enemy_progression.json") == frozen["source_sha256"]["data/enemy_progression.json"],
            "Authored progression changed from frozen source; a new reviewed baseline is required")
    config = load(root / "data/numerical_v2.json")
    require(config["schema"] == "NumericalRuntime/v2" and config["implemented_chapters"] == 4 and config["chapter_level_step"] == 5,
            "Unsupported runtime chapter/schema contract")
    require(config["combat_scale"] == 10, "Unsupported combat scale")
    for key, size in (("difficulty_hp_multipliers", 5), ("difficulty_damage_multipliers", 5),
                      ("ordinary_skill_difficulty_multipliers", 5), ("ordinary_skill_tier_multipliers", 4),
                      ("boss_skill_difficulty_multipliers", 5), ("boss_skill_phase_multipliers", 3)):
        require(len(config[key]) == size and all(decimal(x) > 0 for x in config[key]), f"Invalid factors: {key}")
    validate_calibration(config["enemy_calibration"], archive_entries(root / "scripts/combat/enemy_calibration.gd"))
    return {"config": config, "frozen": frozen, "initial": initial,
            "growth": progression["level_rules"], "hashes": hashes}


def validate(data):
    frozen, growth = data["frozen"], data["growth"]
    require([e["id"] for e in frozen["ordinary"]] == [f"M{i:02}" for i in range(1, 37)], "Ordinary input coverage")
    require([b["id"] for b in frozen["bosses"]] == [f"BO{i:02}" for i in range(1, 5)], "Boss input coverage")
    initial = {entry["id"]: entry for entry in data["initial"]["ordinary"]}
    count = 0
    for enemy in frozen["ordinary"]:
        require([t["reference_level"] for t in enemy["tiers"]] == list(TIERS), "Frozen mechanic tiers changed")
        for rank in ("normal", "elite"):
            for key in STAT_KEYS:
                require(initial[enemy["id"]]["profiles"][rank][key] == enemy["tiers"][0]["profiles"][rank][key], "Independent frozen seed mismatch")
            for index, level in enumerate(TIERS):
                generated, _ = ordinary_source(enemy, level, rank, growth)
                for key in STAT_KEYS:
                    count += 1
                    require(abs(decimal(generated[key]) - decimal(enemy["tiers"][index]["profiles"][rank][key])) < Decimal(".000000001"),
                            f"Unrounded baseline reconstruction mismatch: {enemy['id']}/{rank}/Lv{level}/{key}")
    require(sum(len(b["actions"]) for b in frozen["bosses"]) == 40, "Boss action coverage")
    require(sum(len(a["variants"]) for b in frozen["bosses"] for a in b["actions"]) == 103, "Boss phase coverage")
    require(sum(len(a["variants"]) * (5 - a["unlock_difficulty"]) for b in frozen["bosses"] for a in b["actions"]) == 395, "Boss difficulty/phase coverage")
    require(integer(Decimal(".5")) == 1 and integer(Decimal("2.5")) == 3, "Half-up boundary")
    # Calibration belongs before actor rounding; this fixture fails if a rounded
    # baseline is multiplied, and is independent of today's all-one archive.
    require(integer(Decimal("10.49") * Decimal("1.1")) == 12 and integer(integer(Decimal("10.49")) * Decimal("1.1")) == 11,
            "Full-expression calibration boundary")
    require(packet({"kind": "counter", "auto_release": False}, 999, Decimal("2")) == 0,
            "Counter stance must remain zero")
    require(packet({"kind": "summon", "damage_multiplier": 1}, 999, Decimal("2")) == 0,
            "Support must remain zero")
    return count


def render(data):
    config, frozen, growth = (data[k] for k in ("config", "frozen", "growth"))
    snapshot = config["enemy_calibration"]
    out = ["# 当前运行敌人校准数值表\n",
           "**状态：参数推演已生成，战斗平衡验收待完成。本文不是胜率、TTK、容错或自然经济时长的实测证据。**\n",
           f"当前运行校准版本：**{snapshot['version']}**；生产数值开关：**{str(config['runtime_enabled']).lower()}**；配置状态：`{config['status']}`。仅展示文件中当前、且与不可变归档一致的校准；未写入配置的候选版本不在本表中。\n",
           "新出发冻结此校准；已开始的冒险按保存的校准快照继续，缺校准字段的旧V2局永久使用原系数1。因此本表不是所有历史存档的实时演员表。\n",
           "生成：`python tools/balance/render_runtime_calibration.py`。检查：`python tools/balance/render_runtime_calibration.py --check`。参数、归档或相关源码变化后重新生成；检查模式会拒绝过时文件，不会自动接受一个尚未归档的系数。原TARGET册及其源指纹保持不变。\n",
           "## 1. 来源、范围与舍入\n",
           f"旧演员与命令基线固定在提交 `{SNAPSHOT}`。Lv1输入已包含原型职责与精英1.2HP/1.12攻击/+4魔抗，不能再次叠加。Lv1完整未取整HP/A按冻结旧成长重建固定章节等级，双抗取对应冻结机制阶的值；全部288组四阶/身份基线逐字段交叉检查。\n",
           f"旧HP成长每级 `{number(growth['hp_per_level'])}`，旧攻击成长每级 `{number(growth['damage_per_level'])}`。当前只覆盖已发布B01–B04，普通/精英每章三区为 `5(B−1)+1/3/5`，Boss为 `5B`；不读玩家等级、职业或装备。36个可解析精英不等于36个自然精英，本表不改变遇敌登记。\n",
           "设 `I(x)=floor(x+0.5)`，Python使用Decimal/ROUND_HALF_UP，所有因子先相乘再取整：\n",
           "- `HP=I(旧同级未取整HP × baselineHP × 10 × F_HP(B) × HP_D × chapter/rank.hp)`\n",
           "- `A=I(旧同级未取整A × baselineA × 10 × F_A(B) × Damage_D × chapter/rank.attack)`\n",
           "- 普通/精英 `S=tierSkill × skill_D × chapter/rank.skill`；Boss `S=bossSkill_D × phaseSkill × chapter/boss.skill`\n",
           "- 每次命中/每弹/每跳 `Q=I(整数A × 原命令系数c × S)`；纯支援、召唤、诱饵和不自动释放的counter架势为0。已取整Q不能再乘技能校准；表中不含按战况触发的兽人狂怒1.2或战鼓1.25，它们在真实发包前进入完整乘积一次\n",
           "- 普通/精英双抗 `I((min(旧护甲,24)+2D)×10)` / `I((min(旧魔抗,32)+2D)×10)`；Boss为 `I((旧双抗+3D)×10)`。校准不影响双抗，Boss不套普通帽\n",
           "- 防御减伤仍是 `E/(1000+E)`，不另封顶65%；独立通用减伤DR才封顶65%。表中Q均为减伤前值，不是保证总伤害\n",
           "- 端点/掩体/虫卵 `I(旧耐久×10×S)`，端点/掩体夹10–800、虫卵不夹800；破卵削甲固定×10。比例盾/治疗按实际受益者整数HP重算，不叠S；35%支援盾、15%治疗与原次数限制保持\n",
           "\n不压缩预警/锁定/暴露窗口、不增发弹体/危险区/召唤数量。本次生成只验证数据与公式；实测过程、控制器和失败样本另见 [S11受控矩阵](S11_CONTROLLED_MATRIX.md)。\n",
           "### 输入与实现指纹\n",
           table(["文件", "SHA256", "角色"], [[path, value, "冻结旧输入" if path in FROZEN else "当前运行/一致性来源"] for path, value in data["hashes"].items()]),
           "冻结JSON内保留原17项源码指纹；当前运行源码已实施重构，不能拿当前源码冒充旧提交重算该指纹。旧成长JSON另外按冻结指纹验证，本文从不改写这些文件。上表实现指纹支持追踪，不能替代真实Godot输出校验。\n",
           "## 2. 当前校准与基础因子\n",
           f"baselineHP=`{number(config['enemy_baseline_multiplier']['max_hp'])}`，baselineA=`{number(config['enemy_baseline_multiplier']['damage'])}`，战斗scale=`{number(config['combat_scale'])}`。以下系数全部读取当前运行JSON，未复制候选配置。\n",
           table(["章", "身份", "HP校准", "A校准", "技能校准"],
                 [[chapter, rank] + [number(snapshot["chapters"][chapter][rank][key]) for key in FACTORS] for chapter in CHAPTERS for rank in RANKS]),
           table(["D", "演员HP", "演员A", "普通技能D", "Boss技能D"],
                 [[d] + [number(config[key][d]) for key in ("difficulty_hp_multipliers", "difficulty_damage_multipliers", "ordinary_skill_difficulty_multipliers", "boss_skill_difficulty_multipliers")] for d in range(5)]),
           table(["章", "三区等级", "Boss等级", "F_HP", "F_A"],
                 [[f"B{b:02}", "/".join(str(5*(b-1)+x) for x in (1,3,5)), 5*b, number(chapter_factor(config,b,"max_hp")), number(chapter_factor(config,b,"damage"))] for b in range(1,5)]),
           "普通T1–T4技能因子：" + "/".join(number(x) for x in config["ordinary_skill_tier_multipliers"]) + "；Boss阶段P1–P3因子：" + "/".join(number(x) for x in config["boss_skill_phase_multipliers"]) + "。\n",
           "## 3. 普通/精英：实际固定章节等级 × D0–D4\n",
           "共36原型×3区域等级×2身份×5难度=**1080行**。逐包Q按冻结序列顺序以 `/` 分隔，不把多个弹体/多跳加成一包；精英附加余震或M36替换序列保留。S列包含本章本身份技能校准，A列已包含本章本身份攻击校准。\n"]
    for enemy in frozen["ordinary"]:
        chapter = chapter_for(enemy["id"])
        out.append(f"### {enemy['id']} {enemy['name']} / B{chapter:02}\n")
        rows = []
        for zone in range(1,4):
            level = 5 * (chapter - 1) + (1,3,5)[zone-1]
            for rank in ("normal", "elite"):
                source, tier = ordinary_source(enemy, level, rank, growth)
                for d in range(5):
                    actor = resolved_stats(config, source, chapter, rank, d)
                    strength = skill_factor(config, chapter, rank, d, level=level)
                    sequence = "/".join(str(packet(command, actor["damage"], strength)) for command in commands(tier, rank))
                    rows.append([f"Z{zone}/L{level}/T{tier_index(level)+1}", rank, d] + [actor[key] for key in STAT_KEYS] + [number(strength), sequence])
        out.append(table(["区/级/阶", "身份", "D", "HP", "A", "护甲", "魔抗", "S", "逐包Q"], rows))
    out += ["## 4. Boss演员：固定章级 × D0–D4\n", "20行演员值；进入阶段只影响发包S，不再修改演员A。\n"]
    rows = []
    for boss in frozen["bosses"]:
        chapter = chapter_for(boss["id"])
        for d in range(5):
            actor = resolved_stats(config, boss["stats"], chapter, "boss", d)
            rows.append([boss["id"], boss["base_level"], d] + [actor[key] for key in STAT_KEYS] +
                        ["/".join(number(skill_factor(config, chapter, "boss", d, phase=p)) for p in (1,2,3))])
    out.append(table(["Boss", "等级", "D", "HP", "A", "护甲", "魔抗", "S(P1/P2/P3)"], rows))
    out += ["## 5. Boss技能：全部有效难度/阶段组合\n", "40技能ID、103阶段变体、**395个有效难度/阶段组合**。解锁D不足或未编写阶段的组合不生成。status的tick表示各自每跳输入（shock为下次直伤追加）；预警、间隔、数量仍见冻结技能册。\n"]
    for boss in frozen["bosses"]:
        chapter = chapter_for(boss["id"])
        out.append(f"### {boss['id']} {boss['name']}\n")
        rows = []
        for action in boss["actions"]:
            for variant in action["variants"]:
                command = variant["command"]
                for d in range(int(action["unlock_difficulty"]), 5):
                    actor = resolved_stats(config, boss["stats"], chapter, "boss", d)
                    strength = skill_factor(config, chapter, "boss", d, phase=variant["phase"])
                    q = packet(command, actor["damage"], strength)
                    rows.append([action["id"], variant["phase"], d, command["kind"], number(command.get("damage_multiplier",1)), number(strength), q,
                                 extras(command,q,strength,decimal(config["combat_scale"]))])
        out.append(table(["技能", "阶段", "D", "命令", "c", "S", "Q", "状态/耐久输入"], rows))
    out += ["## 6. 验证边界\n",
            "生成器检查冻结文件完整性、17项源清单一致、旧成长指纹、当前校准与归档一致、288组四阶/身份基线（1152个属性对照）、1080普通/精英边界行、20Boss演员及395技能组合；同时检查半点取整、禁止先取整基线再乘校准和零伤命令。\n",
            "**未在本次Python生成中运行Godot或开展战斗实测。平衡仍待验收；参数表生成成功不会把候选方案、控制脚本、自然路线或6–10小时目标标记为通过。**\n"]
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Read a specific checkout/snapshot")
    parser.add_argument("--output", type=Path, help="Default: ROOT/" + OUTPUT)
    parser.add_argument("--check", action="store_true", help="Fail if the generated document is stale")
    parser.add_argument("--self-test", action="store_true", help="Validate inputs/arithmetic without writing a document")
    args = parser.parse_args()
    require(not (args.check and args.self_test), "Choose --check or --self-test")
    root = args.root.resolve()
    data = context(root)
    checks = validate(data)
    expected = render(data)
    # Configuration must be one snapshot, not a mixture of concurrent edits.
    for path, original in data["hashes"].items():
        require(digest(root/path) == original, f"Source changed while rendering: {path}; rerun")
    destination = args.output if args.output is not None else root / OUTPUT
    if args.check:
        require(destination.is_file() and destination.read_text(encoding="utf-8") == expected,
                f"Stale runtime calibration table: {destination}; regenerate")
    elif not args.self_test:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(expected, encoding="utf-8")
    print(f"PASS: calibration v{data['config']['enemy_calibration']['version']}; {checks} frozen stat checks; "
          "1080 ordinary/elite rows, 20 Boss rows, 395 skill combinations; balance PENDING")


if __name__ == "__main__":
    main()
