#!/usr/bin/env python3
"""Render current roster/skills/numeric documentation from the Godot export.

The export is a temporary file; source-derived docs are committed. --check compares
exact rendered output without rewriting it. This is not a balance simulation.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def cell(value):
    return str(value).replace('|', ' / ').replace('\n', ' ')


def table(headers, rows):
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '|' + '|'.join(['---'] * len(headers)) + '|'] +
                     ['| ' + ' | '.join(cell(v) for v in row) + ' |' for row in rows]) + '\n'


def warning_document(doc):
    source = (ROOT / 'scripts/combat/enemy_warning_timing.gd').read_text()
    constants = {key: json.loads(re.search(r'const ' + key + r'[^=]*= (\[[^\]]+\])', source).group(1))
                 for key in ['TELL_FACTORS','LOCK_FACTORS','ORDINARY_SHORT_FLOORS','ORDINARY_AREA_FLOORS','ORDINARY_BOMBER_FLOORS']}
    text = ['# 普通怪与首领预警缩短：实际时序表',
            '更新：2026-10-02。用户要求普通怪和首领预警更紧凑。本轮仅改V2的追踪前摇和固定锁定段；HP、伤害系数、恢复/反击窗口、招式冷却、场地几何与出生保护不因这项调整而变化。冻结的V1历史冒险保留原时序。',
            '## 计算规则',
            '前摇=max(家族最低值, 原始前摇×所选难度倍率)；锁定=max(锁定最低值, 原始锁定×所选难度倍率)。总预警=前摇+锁定。始终从原始值计算，重复读取不复乘。普通怪扫描标记再将追踪段乘0.85但不突破该档最低值，锁定段不被扫描缩短。',
            table(['D','追踪倍率','锁定倍率','野怪短招最低秒','野怪区域/冲锋最低秒','爆破兵最低秒'],
                  [[d]+[constants[k][d] for k in constants] for d in range(5)]),
            '普通怪锁定最低0.22秒，原0.40秒按D0–D4实际变为0.30/0.28/0.26/0.24/0.22秒。首领短招最低0.45秒，区域/冲锋最低0.60秒，外半径≥350的环形最低0.75秒，锁定最低0.24秒。几何上只有着地环形的冲锋同样归区域；普通怪既有区域行为分类保留。',
            '恢复是施放后的反击窗口，不从总预警里扣除。多段技能的每段都有自己的完整追踪+锁定，按段生效，不把几段共享一个倒计时。M36最新准备招和唯一爆破均保留其引信家族下限。',
            '## 全54种普通怪',
            '所属章末等级、普通品阶的每个真实基础/难度招式。单元格为“追踪 + 锁定 = 总秒”；—表示未解锁或M36该档已替换。旧值来自同一命令的原始时序快照，不是视觉估算。']
    rows=[]
    for enemy in doc['ordinary']:
        for skill in enemy['skills']:
            timings=skill['timing_by_difficulty']
            baseline=next((v for v in timings if v),{})
            old=f"{baseline.get('authored_tell_seconds',0):.3f}+{baseline.get('authored_lock_seconds',0):.3f}"
            row=[enemy['id']+' '+skill['name'],baseline.get('family',''),old]
            for t in timings:
                row.append('—' if not t else f"{t['tell_seconds']:.3f}+{t['lock_seconds']:.3f}={t['tell_seconds']+t['lock_seconds']:.3f}")
            rows.append(row)
    text.append(table(['怪物 / 技能','家族','旧追踪+锁定','D0','D1','D2','D3','D4'],rows))
    text += ['## 四首领40招与交替震环的内外变体',
             '同样显示追踪+锁定=总秒；未来难度技能在未解锁档位留空。基础招的三阶段和各合法难度都逐帧核查；恢复、冷却、弱点与伤害字段逐项对比保持。交替震环另列内外圈，较大外圈有更高的安全下限。']
    grouped={}
    for s in doc.get('boss_warning_samples',[]):
        if s['action']=='alternating_ring' and 'variant' not in s: continue
        key=(s['boss_id'],s['action'],s.get('variant',''),s['family'])
        grouped.setdefault(key,{})[s['difficulty']]=s
    rows=[]
    for key,samples in sorted(grouped.items()):
        first=next(iter(samples.values()))
        row=[key[0]+' '+first['name']+(' / '+key[2] if key[2] else ''),key[3],f"{first['before_tell']:.3f}+{first['before_lock']:.3f}"]
        for d in range(5):
            s=samples.get(d)
            row.append('—' if not s else f"{s['tell']:.3f}+{s['lock']:.3f}={s['tell']+s['lock']:.3f}")
        rows.append(row)
    text.append(table(['首领 / 技能','家族','旧追踪+锁定','D0','D1','D2','D3','D4'],rows))
    text += ['## 同步与证据边界',
             'EnemyBrain.timing_for_command与BossBrain._apply_warning_timing共同调用enemy_warning_timing；实际phase时钟、释放点、地面预警、施法条和图鉴读取最终时序。首领不再被旧0.55秒UI/运行下限悄悄拉长；旧V1输入仍保持原值。',
             '[验收记录](../audits/PROGRESSIVE_MONSTERS_2026-10-02.md)登记命令、真实tick→释放→伤害与画面验证边界。本轮没有恢复S11，也不将有界夹具视为完整自然难度调校。',
             '逐技能原始/缩放参数及全部采样见[机器可读快照](progressive_monster_commands.json)，源文件哈希见[技能册](../ORDINARY_MONSTER_EXPANSION.md#来源sha-256)。']
    return '\n\n'.join(text)+'\n'


def render(doc):
    roster = json.loads((ROOT / 'data/enemies.json').read_text())['enemies']
    progression = json.loads((ROOT / 'data/enemy_progression.json').read_text())['profiles']
    rules = json.loads((ROOT / 'data/numerical_v2.json').read_text())
    ordinary = doc['ordinary']
    main = [
        '# 前四关普通怪扩充与难度技能登记',
        '更新：2026-10-02。用户确认第一关保留9种，后续每关增加3种：B01/B02/B03/B04分别9/12/15/18种，共54种普通怪，另有4位首领。旧M01–M36身份保持；新增M37–M39属B02、M40–M45属B03、M46–M54属B04。',
        '本册由生产目录、属性解析器及 EnemyAbilityCatalog.all_skills 导出；图鉴与战斗共用同一技能来源。列出命令不等于自然战斗平衡验收，实效与画面证据另见末节。S11仍暂停。',
        '## 等级、难度和数量的边界',
        '- 新规则的区域等级仍为每章5级阶梯：三战区为5×(章−1)+1/3/5；难度不抬高等级\n- mechanic_tier仍由1/5/10/15级划分并用于既有技能伤害倍率；难度技能另用difficulty_mechanics，不能混算\n- D0只有本体技能；D1/D2/D3/D4依次累计解锁1/2/3/4个额外机制。每轮最多从已解锁池轮换1段，不同时追加4段；M36为单次爆破例外，各难度在唯一爆破前施放该档最新解锁的准备招，旧准备招被替换而非连放，爆破后停机\n- 物种数不等于同屏数量；仍每区6、整房18并发，有限增援、3秒间隔、低压力才补员，出生至少0.8秒保护\n- M42/M45/M51计入保护型配额，M43/M48计入功能支援配额；原配额保持每战区各至多1个，非无限支援叠加',
        '## 四关物种与难度解锁矩阵',
    ]
    for b in ['B01', 'B02', 'B03', 'B04']:
        items = [e for e in ordinary if e['definition']['biome_id'] == b]
        main += [f'### {b} · {len(items)}种', table(['ID / 名称', '基础机制', 'D1', 'D2', 'D3', 'D4'], [
            [e['id'] + ' ' + e['definition']['name'], e['definition']['behavior_id']] +
            [next((s['name'] for s in e['skills'] if s['min_difficulty'] == d), '缺失') for d in range(1, 5)] for e in items])]
    main += ['## 逐怪技能、实际命令与反制',
             '以下在所属章末等级、V2、普通品阶、D4动作恢复配置下导出；伤害列再逐档重新解析。伤害列依次为D0/D1/D2/D3/D4的未减伤单次命令伤害；未解锁或M36被新准备招替换时用“—”。持续区域通常每tick结算；多弹体/连段不能把单次值误当总伤害。状态、种族命中特性、护盾吸收和目标抗性另行结算。冷却列表示整轮结束后的恢复窗口，非每招独立计时。']
    for e in ordinary:
        d = e['definition']
        main += [f"### {e['id']} {d['name']}",
                 f"{d['biome_id']} · {d['behavior_id']} · {d['tell']}。反制：{d['counter']}。",
                 table(['技能 / 门槛', '效果 / 实际参数', '触发与反制', '前摇/锁定/恢复秒', 'D0→D4单次伤害'], [
                     [s['name'] + ' / D' + str(s['min_difficulty']), s['effect'], s['trigger'] + '；' + s['counter'],
                      '/'.join(f'{s[k]:.2f}' for k in ['tell_seconds', 'lock_seconds', 'cooldown']),
                      '/'.join('—' if n is None else str(n) for n in s['damage_by_difficulty'])] for s in e['skills']])]
    main += ['## 实际房间编成', '下表来自 encounter_plan，非仅reference_wave登记。列举D0和D4真实有限波次累计数；D1–D3同样由定向检查验证每种怪在本族至少一个房间自然出现。']
    main.append(table(['房间','D0累计 / 种类计数','D4累计 / 种类计数'], [
        [r['id']] + [str(r['difficulties'][d]['total']) + ' / ' + ', '.join(k+'×'+str(v) for k,v in sorted(r['difficulties'][d]['composition'].items())) for d in [0,4]] for r in doc['rooms']]))
    main += ['## 数值与美术入口',
             '- [实际数值册](balance/ORDINARY_MONSTER_NUMBERS.md)：基础值、公式、54种×五难度采样\n- [V2短预警完整时序](balance/ENEMY_WARNING_TIMING.md)：普通怪与首领的逐难度旧值/新值和家族下限\n- [外观与资源索引](ENEMY_VARIANTS.md)：身体、脚点、技能UI与高清图鉴素材映射\n- [开发进度](DEVELOPMENT_PROGRESS.md)与[四关路线图](LEVEL_ROADMAP.md)：已实现和待验证范围\n- [本轮验收记录](audits/PROGRESSIVE_MONSTERS_2026-10-02.md)：只登记实际执行的检查；完整S11自然平衡仍暂停',
             '## 再生成',
             '使用独立XDG目录与 --test-profile 隔离档运行 tools/godot/godot --headless --path . --script tools/balance/export_progressive_monsters.gd -- --output=/tmp/progressive-monsters.json；首领时序由 tests/test_boss_warning_timing.gd 用 --output=/tmp/boss-warning-timings.json 生成。随后 python tools/balance/render_progressive_monsters.py --input /tmp/progressive-monsters.json --boss-timing-input /tmp/boss-warning-timings.json。加 --check 只比较文本。导出只读解析器，不创建战斗、不写玩家档。',
             '完整原始命令与各档已缩放的伤害、端点HP和状态强度见[机器可读快照](balance/progressive_monster_commands.json)。command字段为缩放前招式输入，runtime_values_by_difficulty为所选难度缩放后值；null表示尚未解锁或M36该档不使用此准备招。',
             '### 来源SHA-256', table(['源文件','SHA-256'], sorted(doc['sources'].items()))]
    numbers = ['# 普通怪扩充：当前数值与难度采样',
               '更新：2026-10-02。本册是当前54普通怪V2解析值，与[技能/关卡册](../ORDINARY_MONSTER_EXPANSION.md)配套。旧CURRENT和TARGET数值册保留其冻结历史基线，不改写旧快照冒充当前结果。',
               '## 本轮数值边界',
               '原M01–M36的基础属性、等级参数、既有数值配置与校准快照未变；新增18种使用下列独立基础值。新增难度技能会改变实际战斗压力，因此不声称总体难度/TTK不变。没有恢复S11或宣称自然平衡完成。',
               '## 新增18种的原始基础值',
               table(['ID','HP','攻击','速度','护甲','魔抗','射程','基础恢复'], [
                   [e['id']] + [progression[e['id']]['base_stats'][k] for k in ['max_hp','damage','move_speed','armor']] +
                   [roster[e['id']]['magic_resist']] + [progression[e['id']]['base_stats'][k] for k in ['attack_range','recovery_seconds']]
                   for e in ordinary if int(e['id'][1:]) > 36]),
               '新种的等级5/10/15在基础1.0秒暴露窗口上依次延长到1.1/1.2/1.3秒；实际恢复还取职业类型恢复倍率和既有难度缩放，不得低于暴露窗口。额外动作按所选难度解锁，不由这些等级条目伪造。',
               '## 当前生产公式',
               '先由enemy_profiles解析职业类型、等级、品阶与有界速度/抗性；再由enemy_numerical_v2做一次整数化。HP/攻击最终将各因子作为有理数连乘后四舍五入一次，不能逐项舍入。',
               '- HP = round(等级解析HP × enemy_baseline_multiplier.max_hp × combat_scale × 章节HP系数 × D生命倍率 × 校准HP系数)\n- 攻击 = round(等级解析攻击 × enemy_baseline_multiplier.damage × combat_scale × 章节攻击系数 × D攻击倍率 × 校准攻击系数)\n- 章节HP系数 = 1 + 0.12×(章−1)；章节攻击系数 = 1 + 0.08×(章−1)\n- 护甲/魔抗 = round((等级解析值上限后 + 2×D) × combat_scale)\n- 速度 = min(132, 等级解析速度) × (1 + 0.04×D)\n- 恢复 = max(暴露窗口, 基础恢复/(1 + 0.035×D))\n- 技能包 = round(攻击 × 招式damage_multiplier × 等级技能倍率 × 难度技能倍率 × 校准技能系数 × 额外已授权倍率)；支援与无伤位移为0\n- 精英保留原HP×1.2、攻击×1.12、魔抗+4；普通种类数量不包含另一份精英物种',
               table(['配置键','当前值'], [[k,json.dumps(rules[k],ensure_ascii=False)] for k in ['combat_scale','enemy_baseline_multiplier','difficulty_hp_multipliers','difficulty_damage_multipliers','ordinary_skill_tier_multipliers','ordinary_skill_difficulty_multipliers']]),
               '## 54种普通怪 × 五档难度',
               '在各自章末等级5/10/15/20采样；实际房间前两战区等级分别低4/2级。攻击不是单技能最终伤害，技能见配套册。速度/恢复保留小数，HP/攻击/双抗是整数。',
               table(['ID','级别','D','HP','攻击','护甲','魔抗','速度','恢复秒','技能总倍率'], [
                   [e['id'],s['level'],s['difficulty'],s['max_hp'],s['damage'],s['armor'],s['magic_resist'],f"{s['move_speed']:.3f}",f"{s['recovery_seconds']:.3f}",f"{s['skill_factor']:.5f}"] for e in ordinary for s in e['samples']]),
               '## 实施与验证边界',
               '属性值来自生产解析，不代表实战击杀时长。技能状态持续伤害、回返弹体唯一命中、打断/取消、自然生成和技能UI实效须以[验收记录](../audits/PROGRESSIVE_MONSTERS_2026-10-02.md)为准；S11自然战斗、获取时长和完整群战平衡继续暂缓。']
    outputs = {'docs/ORDINARY_MONSTER_EXPANSION.md':'\n\n'.join(main)+'\n',
            'docs/balance/ORDINARY_MONSTER_NUMBERS.md':'\n\n'.join(numbers)+'\n',
            'docs/balance/progressive_monster_commands.json':json.dumps(doc,ensure_ascii=False,indent=2)+'\n'}
    if 'boss_warning_samples' in doc:
        outputs['docs/balance/ENEMY_WARNING_TIMING.md']=warning_document(doc)
    return outputs


def main():
    p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--boss-timing-input',type=Path);p.add_argument('--check',action='store_true');args=p.parse_args()
    doc=json.loads(args.input.read_text())
    for path, expected in doc['sources'].items():
        if hashlib.sha256((ROOT/path).read_bytes()).hexdigest()!=expected:
            raise SystemExit('Stale production export; regenerate after change: '+path)
    if args.boss_timing_input: doc['boss_warning_samples']=json.loads(args.boss_timing_input.read_text())
    outputs=render(doc)
    for path,text in outputs.items():
        target=ROOT/path
        if args.check:
            if not target.exists() or target.read_text()!=text: raise SystemExit('Out of date: '+path)
        else: target.write_text(text)
        print(('Checked ' if args.check else 'Wrote ')+path)


if __name__=='__main__': main()
