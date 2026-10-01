#!/usr/bin/env python3
"""Render/check the documentation-only Godot enemy and boss export."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "docs/balance/CURRENT_ENEMY_BOSS_CATALOG.md"
DIFFICULTIES = ("普通 D0", "进阶 D1", "困难 D2", "险境 D3", "极限 D4")
RANKS = {"normal": "普通", "elite": "精英"}
ROLES = {"melee": "近战", "charger": "冲锋", "ranged": "远程", "artillery": "炮击", "support": "辅助", "summoner": "召唤", "healer": "治疗", "assassin": "刺客", "swarm": "群袭", "cover_support": "掩体辅助", "displacement": "位移干扰", "defender": "防守", "flanker": "侧击", "ambusher": "伏击", "interference": "干扰", "terrain": "地形交互", "controller": "控制", "duelist": "决斗", "counter": "反击"}
ARCHETYPES = {"tank": "坦克", "caster": "施法", "assassin": "刺客", "skirmisher": "游击", "support": "辅助"}
TYPES = {"physical": "物理", "magic": "魔法"}
KINDS = {"melee": "近战", "charge": "位移攻击", "projectile": "弹体", "ground_area": "地面区", "pull": "牵引", "summon": "召唤", "haste": "加速", "guard": "防护", "heal": "治疗", "utility": "机关交互", "decoy": "诱饵", "counter": "反击"}


def n(value: float | int, precision: int = 2) -> str:
    return f"{float(value):.{precision}f}".rstrip("0").rstrip(".")


def cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def table(headers: list[str], rows: list[list[object]]) -> str:
    text = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    text.extend("| " + " | ".join(cell(v) for v in row) + " |" for row in rows)
    return "\n".join(text) + "\n"


def sample(enemy: dict, rank: str, level: int) -> dict:
    return next(x for x in enemy["samples"] if x["rank"] == rank and x["level"] == level)


def compact(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def params_text(params: dict) -> str:
    return "；".join(f"`{k}={compact(v)}`" for k, v in sorted(params.items())) or "无替换"


def validate(data: dict) -> None:
    assert data["schema"] == "EnemyBossDocumentation/v1"
    assert [x["enemy_id"] for x in data["ordinary"]] == [f"M{x:02}" for x in range(1, 37)]
    assert data["level_samples"] == [1, 5, 10, 15, 20]
    assert len(data["encounters"]) == 360
    progression = json.loads((ROOT / "data/enemy_progression.json").read_text(encoding="utf-8"))
    for path, digest in data["source_sha256"].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, f"stale export: {path}"
    for enemy in data["ordinary"]:
        assert len(enemy["samples"]) == 10
        authored = enemy["authored"]
        base = progression["profiles"][enemy["enemy_id"]]["base_stats"]
        assert enemy["base_stats"] == base
        role = data["archetype_stats"][authored.get("archetype", "skirmisher")]
        for entry in enemy["samples"]:
            level = entry["level"]
            elite = entry["rank"] == "elite"
            tier = 1 + sum(level >= threshold for threshold in (5, 10, 15))
            profile = entry["profile"]
            expected = {
                "max_hp": base["max_hp"] * role["hp"] * (1 + .055 * (level - 1)) * (1.2 if elite else 1),
                "damage": min(16.9, max(role["minimum_damage"], base["damage"] * role["damage"])) * (1 + .025 * (level - 1)) * (1.12 if elite else 1),
                "move_speed": min(132, base["move_speed"] * role["speed"] * (1 + .006 * (level - 1))),
                "armor": min(24, base["armor"] * role["armor"] + role["armor_bonus"] + (tier - 1) * role["armor_per_tier"]),
                "magic_resist": min(32, authored["magic_resist"] + (tier - 1) * role["resist_per_tier"] + (4 if elite else 0)),
            }
            for key, value in expected.items():
                assert math.isclose(profile[key], value, abs_tol=1e-7), (enemy["enemy_id"], level, entry["rank"], key, value, profile[key])
            assert profile["mechanic_tier"] == tier
            assert profile["difficulty"] == 0
            assert entry["sequence"], enemy["enemy_id"]
        assert enemy["enemy_id"] + ":normal:0" in data["appearances"]
    assert len(data["bosses"]) == 4
    assert sum(len(set(a["action_id"] for a in b["actions"])) for b in data["bosses"]) == 40
    for boss in data["bosses"]:
        assert len(boss["samples"]) == 5
        base = boss["samples"][0]
        for d, profile in enumerate(boss["samples"]):
            for key, expected in {
                "max_hp": base["max_hp"] * (1 + .16 * d),
                "damage": base["damage"] * (1 + .08 * d),
                "move_speed": base["move_speed"] * (1 + .045 * d),
                "armor": base["armor"] + 3 * d,
                "magic_resist": base["magic_resist"] + 3 * d,
            }.items():
                assert math.isclose(profile[key], expected, abs_tol=1e-7), (boss["boss_id"], d, key)
            assert profile["enemy_level"] == min(20, boss["base_level"] + 2 * d)
        assert all(a["command"] for a in boss["actions"])


def sequence_text(stages: list[dict]) -> str:
    results = []
    for i, stage in enumerate(stages, 1):
        parts = [f"{i}.{KINDS.get(stage['kind'], stage['kind'])}/{stage.get('shape', '')}", f"×{n(stage.get('damage_multiplier', 1))}", f"预警{n(stage['base_telegraph_seconds'])}s", f"锁定{n(stage['locked_seconds'])}s"]
        if stage.get("count", 1) != 1:
            parts.append(f"数量{stage['count']}")
        if stage.get("duration", 0) > 0:
            parts.append(f"持续{n(stage['duration'])}s")
        if "tick_interval" in stage:
            parts.append(f"间隔{n(stage['tick_interval'])}s")
        if stage.get("status"):
            parts.append("状态" + compact(stage["status"]))
        results.append("／".join(parts))
    return "；".join(results)


def appearance_text(data: dict, enemy_id: str, rank: str, difficulty: int) -> str:
    item = data["appearances"].get(f"{enemy_id}:{rank}:{difficulty}")
    if item is None:
        return "未自然编入"
    return f"{item['room_id']} / 区{item['zone_index'] + 1} / 批{item['wave_index'] + 1} / Lv.{item['level']}"


def boss_geometry(command: dict) -> str:
    fields = ("range", "travel_distance", "radius", "inner_radius", "width", "angle", "ring_gap_degrees", "count", "speed", "projectile_radius", "duration", "tick_interval", "max_active_hazards", "hatch_delay", "pod_health", "pod_break_armor_loss", "max_alive", "summon_enemy_id", "max_targets", "multiplier", "pull_distance", "landing_only", "damage_along_path", "weakpoint_duration", "weakpoint_delay")
    parts = [f"`{k}={compact(command[k])}`" for k in fields if k in command]
    if "paths" in command:
        parts.append(f"路径{len(command['paths'])}条")
    if "targets" in command:
        parts.append(f"落点{len(command['targets'])}个")
    if command.get("status"):
        parts.append("状态`" + compact(command["status"]) + "`")
    return "；".join(parts) or "—"


def render(data: dict) -> str:
    out = ["# 野怪与首领现状数值附录（重构确认稿）\n",
           "记录日期：2026-10-01。**本册记录当前运行解析值，尚未重构游戏数值。** 新装备、成长和掉落规则由重构设计主文档另行定义；不能把本册的现状表当作新目标配置。\n",
           f"源快照：`{data['source_snapshot']}`；导出引擎：Godot `{data['engine_version']}`。36 普通原型、36 可解析精英变体、4 首领；Lv.1/5/10/15/20 共 **360** 份普通/精英档案，五难度共 **20** 份首领档案，24 房 × 3 区 × 5 难度共 **360** 份实际有限遭遇计划，**40** 个不同首领招式。\n",
           "`data/enemies.json` 的 `gameplay_implemented:false` 是保留的目录状态，不能据此否认 `EnemyProfiles.resolve → EnemyBrain → EnemySkillRuntime` 已接入的运行路径，也不能把已解析档案等同完整美术与自然平衡验收。本次只调用解析器、纯招式构造与未入树的占位节点；没有启动主场景、推进战斗、调用 Game 或修改玩家档。\n",
           "表中生命/攻击基值允许小数，显示最多两位小数；计算保留浮点精度，不先四舍五入。速度、距离、宽度与体型半径单位为世界像素；前摇、锁定、收势单位为秒。`damage` 是释放命令的伤害输入，**不是每招最终扣血**；数量、持续伤害、护甲、魔抗、护盾、免疫和闪避共同决定实际结果。\n",
           "## 1. 普通怪计算顺序与边界\n",
           "令章节编号 `B∈{1,2,3,4}`、区序号 `Z∈{0,1,2}`、难度 `D=clamp(输入,0,4)`、等级 `L=clamp(输入,1,20)`。机械阶 `T` 为 Lv.1–4→1、Lv.5–9→2、Lv.10–14→3、Lv.15–20→4。同一阶参数按 tier 顺序覆盖，机制 ID 去重累积；20 级没有额外第 5 阶。\n",
           "| 层次 | 当前公式与边界 |\n| --- | --- |",
           "| 实际遭遇等级 | `L=clamp(1+(B−1)×4+Z×2+D×2,1,20)`；不读取玩家等级或装备。 |",
           "| 生命 | `HP=base_hp×角色原型生命系数×[1+0.055×(L−1)]×精英系数×[1+0.12D]`；普通系数1，精英1.20。 |",
           "| 伤害输入 | `A=min(16.9,max(原型最低伤害,base_damage×原型伤害系数))×[1+0.025×(L−1)]×精英系数×[1+0.10D]`；普通系数1，精英1.12。16.9限基础段，不限最终A。 |",
           "| 移速 | `V=min(132,base_speed×原型移速系数×[1+0.006×(L−1)])×[1+0.04D]`；精英不另乘移速。 |",
           "| 护甲 | `Armor=min(24,base_armor×原型护甲系数+原型护甲加值+(T−1)×阶护甲)+2D`；精英不另加护甲。 |",
           "| 魔抗 | `MR=min(32,catalog_magic_resist+(T−1)×阶魔抗+(精英?4:0))+2D`。 |",
           "| 收势 | 先做安全参数合并：`R0=max(base_recovery,安全修正后的tier_recovery)×max(1,原型收势系数−0.005×(L−1))`；再 `R=max(max(0.45,exposure),R0/[1+0.035D])`。 |",
           "| 单次命令原伤害 | `X=max(0,A或命令显式damage)×max(0,命令damage_multiplier)`；战寨半血狂怒释放时再×1.20，之后命中/区域跳伤不重乘。 |",
           "| 每次有效扣血 | 非真实伤害先按伤害类型取防御：`X×100/[100+max(0,防御−穿透)]×[1−clamp(减伤,0,0.65)]`；受击前既有腐蚀/感电修正另按第7.1节，再处理免疫、闪避/护盾/生命。 |",
           "| 威胁预算 | 精英先`ceil(base_threat×1.5)`，普通为base；再`ceil(结果×[1+0.25×(T−1)])`。召唤额外预留席位与威胁。 |",
           "\n**上限顺序：**132 速度、24 护甲、32 魔抗在难度层之前限制，因此 D4 最多可到速度153.12、护甲32、魔抗40；精英 Lv.20 攻击基础输入上限为 `16.9×1.475×1.12=27.92`，D4 可到39.09。现有旧注释的普通180生命/25伤害约束不能当成难度或精英最终上限。`EnemyDifficulty.apply` 保存难度前 `difficulty_base_stats`，重复应用按基值重算，不再次相乘。\n",
           "### 1.1 原型身份系数\n"]
    out.append(table(["原型", "HP系数", "伤害系数", "最低伤害", "移速系数", "护甲系数", "护甲加值", "每阶护甲", "每阶魔抗", "收势系数"], [[ARCHETYPES[k], n(v["hp"]), n(v["damage"]), n(v["minimum_damage"]), n(v["speed"]), n(v["armor"]), n(v["armor_bonus"]), n(v["armor_per_tier"]), n(v["resist_per_tier"]), n(v["recovery"])] for k, v in sorted(data["archetype_stats"].items())]))
    out.extend(["\n### 1.2 五难度额外倍率\n", table(["难度", "生命倍率", "伤害倍率", "移速倍率", "双抗各加", "收势除数"], [[DIFFICULTIES[d], n(1+.12*d), n(1+.10*d), n(1+.04*d), 2*d, n(1+.035*d,3)] for d in range(5)]),
                "\n### 1.3 预警与精英安全限制\n",
                "普通怪出生0.8秒不能造成伤害；前摇至少目录的minimum_tell且至少0.55秒，地面/圆环落点至少0.8秒；锁定至少0.4秒。`safe_disarm_ring` 前摇还不能低于fuse；后续段前摇不能低于hazard_stagger。扫描辅助可缩短远程瞄准，但不能突破0.55/0.8最低值。连招间隔至少0.55、暴露至少0.45；连招与弹体基础参数各≤3，单个施法者地面危险区≤2。完整反击窗口不按等级压缩。\n",
                "精英除M36外，在完整原型序列后追加固定方向线形余震：0.35倍伤害、参数宽20、持续0.35秒、tick间隔0.35秒；档案中的 `elite_aftershock_tell_seconds=0.8` 仅保存参数，真实序列前摇仍由 `EnemyBrain` 的地面段规则计算，必须查看下表而不能直接当成实发前摇。M36精英保留单次自爆，半径至少95、安全缺口至少50°、引信至少1.6秒，无死亡二次爆炸。\n",
                "## 2. 36 普通原型初始属性\n",
                "本节统一是 `resolve(ID,Lv.1,normal)` 后 `apply(D0)` 的对照底值。B02–B04怪物的Lv.1用于公式比较，实际章节起始等级见第4节；不能把Lv.1假装成其自然首次出现等级。\n"])
    for biome_id, biome in sorted(data["biomes"].items()):
        members = [e for e in data["ordinary"] if e["authored"]["biome_id"] == biome_id]
        out.append(f"### {biome_id} {biome['name']}\n")
        out.append(table(["ID", "名称", "原型/职责", "HP", "伤害基值", "护甲", "魔抗", "移速"], [[e["enemy_id"], e["authored"]["name"], ARCHETYPES[sample(e, "normal", 1)["profile"]["archetype"]]+" / "+ROLES.get(e["authored"]["role"], e["authored"]["role"]), *[n(sample(e, "normal", 1)["profile"][k]) for k in ("max_hp", "damage", "armor", "magic_resist", "move_speed")]] for e in members]))
        out.append("\n")
        out.append(table(["ID", "攻击射程", "最短实发前摇", "锁定", "收势", "体型半径", "伤害/表现类型", "行为ID / 种族"], [[e["enemy_id"], n(sample(e,"normal",1)["profile"]["attack_range"]), n(min(s["base_telegraph_seconds"] for s in sample(e,"normal",1)["sequence"])), n(sample(e,"normal",1)["sequence"][0]["locked_seconds"]), n(sample(e,"normal",1)["profile"]["recovery_seconds"]), n(e["authored"]["navigation_radius"]), TYPES[e["authored"]["damage_type"]]+" / "+e["authored"]["damage_kind"], "`"+e["authored"]["behavior_id"]+"` / "+sample(e,"normal",1)["profile"]["clan"]] for e in members]))
        out.append("\n")
    out.extend(["### 2.1 公式的原始输入（尚未乘身份系数）\n",
                "本表取enemy_progression.json的base_stats，加目录的magic_resist。`base_attack_range`只是作者基础参数，实际射程以第2节合并后的attack_parameters.range为准；同样不能把原始base_recovery直接当运行收势。\n",
                table(["ID","base_hp","base_damage","base_speed","base_armor","catalog_magic_resist","base_attack_range","base_recovery"],[[e["enemy_id"],*[n(e["base_stats"][k]) for k in ("max_hp","damage","move_speed","armor")],n(e["authored"]["magic_resist"]),n(e["base_stats"]["attack_range"]),n(e["base_stats"]["recovery_seconds"])] for e in data["ordinary"]]),
                "\n## 3. 36 精英变体初始属性\n",
                "统一为Lv.1、D0，可解析变体共36；**实际有限自然遭遇只编入18种精英**，名单和首次位置见第4节。射程、体型、基础伤害类型和行为身份沿用同ID普通原型；生命×1.20、伤害×1.12、魔抗+4，其余按各层公式，M36引信/圆环另按安全契约。下面前摇包含追加余震段的最小值，仅用于对照，分段时间见第6节。\n"])
    out.append(table(["ID", "名称", "HP", "伤害基值", "护甲", "魔抗", "移速", "攻击射程", "最短前摇", "收势"], [[e["enemy_id"], e["authored"]["name"], *[n(sample(e,"elite",1)["profile"][k]) for k in ("max_hp", "damage", "armor", "magic_resist", "move_speed", "attack_range")], n(min(s["base_telegraph_seconds"] for s in sample(e,"elite",1)["sequence"])), n(sample(e,"elite",1)["profile"]["recovery_seconds"])] for e in data["ordinary"]]))
    out.extend(["\n## 4. 所属章节、真实遭遇等级与首次出现\n",
                "区1/2/3是`zone_index=0/1/2`，批1是初始波。首次出现按房间ID升序、区序号、批序号检索真实 `encounter_plan`，表示该难度下最早模板位置，不表示玩家路线一定走到该房。\n"])
    encounter_rows = []
    for biome_id, biome in sorted(data["biomes"].items()):
        first_room = biome["room_ids"][0]
        for d in range(5):
            plans = sorted([p for p in data["encounters"] if p["room_id"] == first_room and p["difficulty"] == d], key=lambda p:p["zone_index"])
            encounter_rows.append([biome_id, DIFFICULTIES[d], " / ".join(str(p["enemy_level"]) for p in plans), " / ".join(str(p["total_count"]) for p in plans), sum(p["total_count"] for p in plans)])
    out.append(table(["章节", "难度", "三区等级", "三区累计自然怪数量", "每普通房总数"], encounter_rows))
    out.extend(["\n每区累计量 `ceil(([6,6,7][Z]+B−1+D)×1.4)`；有限后续波每批最多3、存活压力降低后至少间隔3秒；每区并发6、整房并发18，包括召唤席位，不是整房总击杀上限。精英仅允许困难及以上、带 `elite_objective` 的房间、区2/3后续批各至多1，且预算足够、ID不是M12或M36。\n",
                "### 4.1 普通原型五难度首次位置\n",
                table(["ID", "章节", *DIFFICULTIES], [[e["enemy_id"], e["authored"]["biome_id"], *[appearance_text(data,e["enemy_id"],"normal",d) for d in range(5)]] for e in data["ordinary"]]),
                "\n### 4.2 当前自然生成的精英首次位置\n"])
    elite_ids = sorted(set(k.split(":")[0] for k in data["appearances"] if ":elite:" in k))
    out.append(table(["ID", "困难 D2", "险境 D3", "极限 D4"], [[enemy_id, *[appearance_text(data,enemy_id,"elite",d) for d in (2,3,4)]] for enemy_id in elite_ids]))
    out.extend(["\n## 5. 全原型等级阶梯核心数值（D0）\n",
                "以下360行均来自真实解析器。每一组包含9个原型×5个等级，普通与精英各一组；难度倍率按第1节在这些值之后应用。射程与招式变化按第6节，体型和种族按第2节。\n"])
    for biome_id, biome in sorted(data["biomes"].items()):
        for rank, label in RANKS.items():
            out.append(f"### {biome_id} {biome['name']} · {label}\n")
            rows=[]
            for enemy in data["ordinary"]:
                if enemy["authored"]["biome_id"] != biome_id:
                    continue
                for level in data["level_samples"]:
                    p=sample(enemy,rank,level)["profile"]
                    rows.append([enemy["enemy_id"],level,p["mechanic_tier"],*[n(p[k]) for k in ("max_hp","damage","armor","magic_resist","move_speed","recovery_seconds")]])
            out.append(table(["ID","等级","机械阶","HP","伤害基值","护甲","魔抗","移速","收势"],rows))
            out.append("\n")
    out.extend(["## 6. 36 原型四阶参数与真实命令系数\n",
                "每个原型第1行列出完整Lv.1普通 `attack_parameters`，后续行只列相对上一行替换/新增的参数；未列出的字段沿用上一行，能重建各阶完整参数。序列来自真实 `EnemyBrain._build_sequence`，同一阶可能包含多个独立预警段；`×系数` 为该段单次命令，不把弹体数量、持续跳伤次数自动算成全部命中。调用构造时cycle=0、辅助次数未耗尽、未受扫描标记，奇偶轮换只改变几何/顺序时不改变这里的系数。\n",
                "辅助、诱饵、机关、护盾等命令虽保存默认伤害系数，最终是否造成伤害取决于 `EnemySkillRuntime` 的命令类型；不能据此给每个support命令算一段实伤。M17治疗预算耗尽后改0.6倍近战，M30有多连击时使用0.65倍近战；余震为0.35倍，M33减速线和M14黏液区为0倍。\n"])
    for enemy in data["ordinary"]:
        out.append(f"### {enemy['enemy_id']} {enemy['authored']['name']} · `{enemy['authored']['behavior_id']}`\n")
        previous={}
        rows=[]
        for level in (1,5,10,15):
            s=sample(enemy,"normal",level)
            p=s["profile"]
            delta={k:v for k,v in p["attack_parameters"].items() if k not in previous or previous[k]!=v}
            previous=p["attack_parameters"]
            rows.append([f"Lv.{level} / T{p['mechanic_tier']}", sequence_text(s["sequence"]), params_text(delta), p["tier_descriptions"][-1]])
        out.append(table(["阶起点","完整命令序列/系数/基础时序","完整初阶参数或相对前阶替换","设计阶说明"],rows))
        out.append("\n")
    out.extend(["### 6.1 精英追加段或自爆例外的实际前摇\n",
                "除M36外，原型序列沿用第6节，表中列精英末尾追加的余震段；M36列其唯一圆环。每格为四阶起点Lv.1/5/10/15的实发基础前摇；始终另有≥0.4秒锁定。\n",
                table(["ID","精英追加/替换段","Lv.1前摇","Lv.5前摇","Lv.10前摇","Lv.15前摇"],[[e["enemy_id"],"单次自爆，×1伤害，半径≥95，缺口≥50°" if e["enemy_id"]=="M36" else "线形余震，×0.35伤害，持续0.35s",*[n(sample(e,"elite",level)["sequence"][-1]["base_telegraph_seconds"]) for level in (1,5,10,15)]] for e in data["ordinary"]]),
                "\n## 7. 四族命中特性与首领例外\n",
                table(["种族","普通/精英特性","伤害或生命基准","边界"],[
                    ["B01 构装","蓄能护盾：有效伤害命中给自身1.5秒护盾","当前已解析最大HP×8%","冷却4秒；护盾使用当前难度最大HP；没命中/被拒绝/零伤害不触发"],
                    ["B02 虫族","毒蚀伤口：有效命中附1.8秒腐蚀","腐蚀power=该命令原伤害×55%","原招已带corrosion时不再追加；power不是1.8秒总伤害，周期结算按状态模块"],
                    ["B03 僵尸","墓火汲取：有效命中回复自身生命","min(当前HP上限×6%,该命令原伤害×25%)","冷却3秒；实际回血还受缺失HP/重伤影响；未回血不记成功触发"],
                    ["B04 兽人","半血狂怒：生命≤50%时伤害与移动提升","释放伤害×1.20，运行移动×1.18","释放时快照一次；不是每个tick重新相乘"],
                    ["四首领/机关端点","不套普通怪上述特性","首领走BossProfiles/BossBrain专属规则","首领可有独立护盾、战鼓、弱点等，见第8节"],
                ]),
                "\n普通召唤、虫卵幼虫、墓镇复苏和首领增援用普通档案并继承难度，但 `reward_enabled=false`，不生成金币/经验奖励或可获利尸体。普通召唤等级继承施法者；首领阶段增援等级为 `clamp(BossProfiles.LEVELS[id]+2D,1,20)`，出生时再安全应用难度，不把首领展示等级的+2D重复增加。\n",
                "### 7.1 敌人状态与持续伤害的精确结算\n",
                "同一状态只保留一份快照：较弱强度不覆盖也不延长，等强刷新不会缩短持续时间，更强替换；刷新保留原来的跳伤累计时钟。命令未显式power时，状态power使用该命令原伤害X；B02附带毒蚀使用0.55X。以下原伤害每包再走玩家受击与相应防御结算。\n",
                table(["状态/效果","原伤害或数值","时点/类型/边界"],[
                    ["灼烧 burn","每累计1秒：power×0.12","魔法包；总时长由该技能status.duration提供"],
                    ["腐蚀 corrosion","每累计1秒：power×0.08；B02附加毒蚀即0.55X×0.08=0.044X","物理包；存在时物理护甲先×0.85；后续直接伤害输入再×1.08，DoT不乘该1.08"],
                    ["流血 bleed","每累计1秒：power×0.10","物理包；不把持续时间直接乘成每次命中伤害"],
                    ["感电 shock","下一次直接受击追加独立magic包power×0.25","消费后移除状态，内部冷却1秒；致命首包后不再追加"],
                    ["减速 slow","移动倍率magnitude（例如0.70为原速70%）","独立于寒冷；选择最强减速、刷新较长剩余时间"],
                    ["寒冷 chill","移动倍率0.75，与slow取较低者m","最终减速倍率=1−(1−m)×[1−clamp(减速抗性,0,1)]；不追加跳伤"],
                    ["重伤 grievous","恢复量×0.60","强度固定1；不造成单独跳伤"],
                    ["持续地面区","每跳X，tick_interval限制0.35–2秒；持续时间限制0–8秒","普通持续区首跳在interval之后；lob落地先一次X再留区；duration=0即时一击"],
                ]),
                "\n不考虑被覆盖、离区和受击免疫时，持续区理论每目标触发数为`floor(duration/tick_interval)`，带lob时额外加落地一击；同施法者持久区最多2，创建新区域会撤掉最老区域，三落点不能都永久保留。DoT每秒的边界采用0.00001容差，未满1秒的剩余片段不自动结算一整跳。玩家一次直接受击后有0.65秒短无敌，直击短无敌和闪避保护不阻止既有DoT；正式状态invulnerable仍可阻止，两者不能混用。\n",
                "## 8. 四首领初始属性与五难度完整数值\n",
                "首领**不进入EnemyProfiles**：D0的STATS已经是章节首领基值，不能再乘Lv.5/10/15/20普通成长；等级只展示 `min(20,基础等级+2D)`。首领生命×(1+0.16D)、伤害×(1+0.08D)、速度×(1+0.045D)、双抗各+3D；难度不会缩短下节的完整预警/锁定。\n"])
    boss_rows=[]
    for boss in data["bosses"]:
        for d,p in enumerate(boss["samples"]):
            boss_rows.append([boss["boss_id"],p["name"],DIFFICULTIES[d],p["enemy_level"],*[n(p[k]) for k in ("max_hp","damage","armor","magic_resist","move_speed","attack_range","navigation_radius")],TYPES[p["damage_type"]],p["clan"]])
    out.append(table(["ID","名称","难度","展示等级","HP","伤害基值","护甲","魔抗","移速","档案射程","体型半径","默认伤害","种族"],boss_rows))
    out.extend(["\n### 8.1 专属防护、弱点、阶段与战术\n",
                "所有首领：出场0.8秒；HP≤70%进入阶段2，≤35%进入阶段3；每次转阶段停顿0.9秒。免强制位移，寒冷减速系数按目录，受击不能触发通用硬直；只有已获得弱点窗口可用显式interrupt打断。弱点窗口承受伤害×1.35；破机关窗口与招式暴露时长见下表。\n"])
    tactics=[]
    for boss in data["bosses"]:
        p=boss["samples"][0]; t=p["tactics"]
        tactics.append([boss["boss_id"],f"{n(t['min_range'])}–{n(t['max_range'])}",n(t["retreat_range"]),n(t["orbit_weight"]),n(t["chase_multiplier"]),p["chill_multiplier"],p["reinforcement_cap"],p["reinforcement_budget"],"；".join(f"阶段{w['phase']}："+"，".join(f"{m['enemy_id']}×{m['count']}" for m in w["members"]) for w in p["reinforcement_waves"])])
    out.append(table(["ID","偏好距离","后撤阈值","绕行权重","追击速度倍率","寒冷系数","阶段增援总上限","增援威胁预算","阶段增援组成"],tactics))
    out.append("\n")
    out.append(table(["ID","开局或专属收益","反制与窗口"],[
        ["BO01","开局护盾=最大HP×22%，持续3600秒；D0为319，D4为523.16","能源回路移除护盾；阀门禁用对应雷道2次，打开2.8秒核心窗口"],
        ["BO02","虫卵最多3次批次，每次2只、同时最多2；卵HP40、孵化2.2秒、破卵护甲−2","毁卵/断援，破本族节点开2.6秒；虫后开甲2.35秒；下节日蚀/震地等独立窗口按招式"],
        ["BO03","墓穴召回最多2次，用真实死亡收据，复苏子代不再登记","封墓关闭召回，打开2.5秒；扑击释放1.05秒后开2.2秒窗口（固定延迟）"],
        ["BO04","战鼓未破时狂怒5秒，首领原伤害×1.25；周围最多3个辅助目标加速×1.18","破鼓取消正在蓄力的狂怒并开2.5秒；冲锋撞墙开1.8秒；裂岩跃击落地1.45秒"],
    ]))
    out.extend(["\n## 9. 四首领全部40招：阶段、难度、伤害与时序\n",
                "阶段1/2/3招式池来自BossBrain.SEQUENCES；每位首领D1–D4分别额外累计1招，额外招在三个阶段均可用。表中伤害为**每弹/每次命中/每跳原输入**，按该招最低解锁难度和D4各计算一列；数量不会自动乘成对单目标的必然总伤害。未显式damage_type的招式使用首领默认类型。未指定cooldown使用5秒；冷却从释放时起记，不是完整动作时长。\n",
                "真实前摇 `max(0.55,tell或0.8)`，锁定 `max(0.24,lock或0.32)`；释放后收势至少 `max(0.45,recovery或1,weakpoint_delay+weakpoint_duration)`。表列命令原值，追踪/落点可随目标距离更新，锁定后冻结。未反制、目标在(400,0)、首领在(0,0)的几何采样用于展示路径数；酋长裂岩跃击落地延迟实际重算为 `max(0.1,travel_distance/speed)`，镇长扑击仍为命令固定1.05秒。不将采样距离视为固定战斗结果。\n"])
    for boss in data["bosses"]:
        out.append(f"### {boss['boss_id']} {boss['samples'][0]['name']}\n")
        grouped={}
        for action in boss["actions"]:
            grouped.setdefault(action["action_id"],[]).append(action)
        rows=[]
        for action_id, entries in grouped.items():
            entry=entries[0]; c=entry["command"]; d=entry["unlock_difficulty"]
            variants=[]
            seen=set()
            for e in entries:
                geometry=boss_geometry(e["command"])
                if geometry not in seen:
                    variants.append(f"P{e['phase']}：{geometry}")
                    seen.add(geometry)
            factor=c.get("damage_multiplier",1)
            raw_min=boss["samples"][d]["damage"]*factor
            raw_max=boss["samples"][4]["damage"]*factor
            rows.append([entry["name"]+f" / `{action_id}`","/".join(str(e["phase"]) for e in entries),DIFFICULTIES[d],KINDS.get(c["kind"],c["kind"])+"/"+c["shape"],TYPES.get(c.get("damage_type",boss["samples"][0]["damage_type"]),c.get("damage_type")),n(factor),f"{n(raw_min)} / {n(raw_max)}",f"{n(max(.55,c.get('tell',.8)))} / {n(max(.24,c.get('lock',.32)))} / {n(c.get('recovery',1))}",n(c.get("cooldown",5)),"；".join(variants),"`"+entry["source"]+"`"])
        out.append(table(["技能/稳定ID","阶段","最低难度","命令/形状","伤害类型","伤害系数","解锁档 / D4原伤害","前摇/锁定/命令收势","冷却","几何/状态/持续/弱点参数","来源"],rows))
        out.append("\n")
    out.extend(["BO04战鼓激活时，上表非零原伤害再×1.25；首领不再额外套B04普通怪半血×1.20。弱点×1.35影响玩家对首领的伤害，与首领出伤分开。范围/弹体/地面多段可能碰到多个目标或多次命中，实际总伤害必须从真实命中记录累加；短无敌、护盾和离开区域会减少结果。召唤/加速招的0伤害不生成伤害奖励。\n",
                "## 10. 来源与文档复现\n",
                "正式入库仅本Markdown及两份生成工具；JSON、引擎日志、隔离userdata位于忽略的artifacts目录，不入库。导出独立于主游戏存档，启动前仍隔离APPDATA/LOCALAPPDATA；不停止用户游戏，不导入资源，不扩大运行全套测试。\n",
                "```powershell\n$taskDir = Join-Path (Get-Location) 'artifacts/balance-enemy-catalog'\nNew-Item -ItemType Directory -Path $taskDir, \"$taskDir/userdata/Roaming\", \"$taskDir/userdata/Local\" -Force | Out-Null\n$oldAppData = $env:APPDATA\n$oldLocalAppData = $env:LOCALAPPDATA\ntry {\n    $env:APPDATA = \"$taskDir/userdata/Roaming\"\n    $env:LOCALAPPDATA = \"$taskDir/userdata/Local\"\n    & ./tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/balance/export_enemy_boss_catalog.gd -- \"--output=$taskDir/current.json\"\n    if ($LASTEXITCODE -ne 0) { throw 'Enemy/boss export failed' }\n} finally {\n    $env:APPDATA = $oldAppData\n    $env:LOCALAPPDATA = $oldLocalAppData\n}\npython ./tools/balance/render_enemy_boss_catalog.py --input \"$taskDir/current.json\"\npython ./tools/balance/render_enemy_boss_catalog.py --input \"$taskDir/current.json\" --check\n```\n",
                "`--check` 校验36×2×5完整性、360遭遇、20首领、40招、普通身份/等级/精英公式、首领五难度公式、17个源文件SHA-256及生成文档逐字一致性；源数值变化后需重新导出，旧JSON会被拒绝。当前Godot在受限环境可出现现有测试入口已明确允许的根证书库读取诊断，必须保留日志并排除其他ERROR/SCRIPT ERROR；本次证据不代表自然战斗平衡验收。\n",
                table(["实际来源","SHA-256（导出时）"],[[f"`{path}`",f"`{digest}`"] for path,digest in sorted(data["source_sha256"].items())]),
                "\n本册的命令原伤害与新成长/装备目标是两套状态；新参数获确认并实施后，再生成新运行快照并与本册逐表比较。\n"])
    return "\n".join(out)


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--output",type=Path,default=DEFAULT_OUTPUT)
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    data=json.loads(args.input.read_text(encoding="utf-8"))
    validate(data)
    result=render(data)
    if args.check:
        assert args.output.read_text(encoding="utf-8")==result,"generated document differs; run renderer without --check"
        print("PASS: 360 enemy/rank/level samples, 360 encounter zones, 20 boss samples, 40 skills; formulas and document match")
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(result,encoding="utf-8",newline="\n")
        print(f"Rendered {args.output.name}: {len(result.splitlines())} lines")


if __name__=="__main__":
    main()
