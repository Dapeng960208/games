#!/usr/bin/env python3
"""Render proposal tables. Documentation only: no game writes or profile access."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs/balance/TARGET_NUMERICAL_TABLES.md'
PARAMS = ROOT / 'docs/balance/numerical_v2_parameters.json'
SEEDS = ROOT / 'docs/balance/current_enemy_initial_values.json'
LABELS = {'attack':'攻击', 'ability_power':'法强', 'max_hp':'生命', 'armor':'护甲', 'magic_resist':'魔抗', 'move_speed':'移速加成'}


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def n(value):
    return f'{value:.4f}'.rstrip('0').rstrip('.')


def table(headers, rows):
    esc = lambda x: str(x).replace('|', '\\|').replace('\n', '<br>')
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join(['---'] * len(headers)) + ' |'] + ['| ' + ' | '.join(esc(x) for x in row) + ' |' for row in rows]) + '\n\n'


def stat(value, key):
    return n(value * 100) + '%' if key == 'move_speed' else n(value)


def core(c, slot, power):
    return c['slots'][slot].get('shared', c['slots'][slot].get(power, {}))


def main_value(c, base, key, ilvl, quality, rank, roll, factor=1):
    scale = 1 if key in c['percentage_main_keys'] else (1 + c['main_item_level_per_level'] * (ilvl - 1)) * (1 + c['enhancement_per_rank'] * rank)
    return base * factor * scale * c['rarities'][quality]['main_multiplier'] * roll


def main_range(c, slot, power, ilvl, quality, rank, factor=1):
    return '；'.join(f"{LABELS[k]} {stat(main_value(c,b,k,ilvl,quality,rank,c['main_roll']['min'],factor),k)}–{stat(main_value(c,b,k,ilvl,quality,rank,c['main_roll']['max'],factor),k)}" for k,b in core(c,slot,power).items())


def hero_stats(c, h, level):
    result = {}
    for key in ('attack', 'ability_power', 'max_hp', 'armor', 'magic_resist'):
        base = h.get(key, 0 if key == 'ability_power' else 12 if key == 'magic_resist' else 0)
        result[key] = base * (1 + c['growth'][key] * (level - 1)) if key in ('attack','ability_power','max_hp') else base + c['growth'][key] * (level - 1)
    return result


def render(c, heroes, items, sets, seeds):
    out = ['# 重构目标数值全表（待确认）\n', f"日期：{c['date']}。源提交：`{c['source_commit']}`。**以下全部为设计建议，尚未接入游戏。** 当前实现见四个 CURRENT 附录；解释与规则见 [主方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)。\n", '数值由 [参数文件](numerical_v2_parameters.json) 与 [生成器](../../tools/balance/render_target_numerical_tables.py) 生成；四位小数只用于表格展示，运行方案保存浮点原值，不逐件整数舍入。主属性区间包含品质、装备等级与强化；不包含普通随机词条、天赋、套装或战斗 Buff。\n', '## 1. 三角色初始属性与逐级成长\n']
    out += [table(['角色','生命','攻击','法强','护甲','魔抗','普攻间隔','射程','移速','初始资源 / 上限','资源基础回复'], [[h['id']+' '+h['name'],h['max_hp'],h['attack'],h.get('ability_power',0),h['armor'],h.get('magic_resist',12),h['attack_interval'],h['range'],h['move_speed'],f"{h['starting_resource']} / {h['resource_max']}",h['resource_regen']] for h in heroes.values()])]
    out += ['法师的新普攻基值明确提议为AD+0.35AP，初始27.8；技能仍AD+0.7AP，初始37.6；职业遗物仍AP，初始28。上表的攻击18是AD，不是法师新普攻金额。现状仅AD的普攻口径仍单独保存在CURRENT册。\n']
    for h in heroes.values():
        out += [f"### {h['id']} {h['name']}：Lv.1–20 裸装、未分配天赋\n"]
        rows = []
        for level in range(1,21):
            s = hero_stats(c,h,level)
            rows.append([level] + [n(s[k]) for k in ('max_hp','attack','ability_power','armor','magic_resist')] + [level-1])
        out += [table(['等级','生命','攻击','法强','护甲','魔抗','累计天赋点'], rows)]
    out += ['### 当前20级到未来60级的公式校验点\n', table(['角色','等级','生命','攻击','法强','护甲','魔抗','天赋点'], [[h['id'],level] + [n(hero_stats(c,h,level)[k]) for k in ('max_hp','attack','ability_power','armor','magic_resist')] + [level-1] for h in heroes.values() for level in (20,25,30,40,50,60)])]
    thresholds = list(c['xp_thresholds_1_20'])
    for level in range(21,61):
        thresholds.append(thresholds[-1] + c['xp_after_20']['first_step'] + c['xp_after_20']['step_increment']*(level-21))
    out += ['## 2. 完整1–60级经验与解锁表\n', '21级以后为扩展公式预留；目前4副本仍以20级为上限，不能把预留等级记作已开放。\n']
    def unlock(level):
        return {1:'Q',2:'W',3:'E',4:'R',5:'绿色定向锻造；+3；重铸',10:'紫色定向锻造；+5；Q强化；精炼',12:'W强化',14:'E强化',15:'金色定向锻造；+8',16:'R强化',18:'Q永久A/B分支',20:'R永久A/B分支；+10；研究经验'}.get(level,'每级基础成长、1天赋点' if level>1 else '')
    out += [table(['等级','累计经验','升到下一级','副本上限归属','额外解锁'], [[level,thresholds[level-1],thresholds[level]-thresholds[level-1] if level<60 else '最终上限',f"第{math.ceil(level/5)}副本",unlock(level)] for level in range(1,61)])]
    out += ['## 3. 八槽主属性基准与品质\n', table(['槽位','物理型Lv1白+0范围','法术型Lv1白+0范围'], [[v['name'],main_range(c,k,'physical',1,'white',0),main_range(c,k,'magic',1,'white',0)] for k,v in c['slots'].items()]), '上表展示85%–115%范围，区间中点为100%。护甲类槽位两种类型使用相同主属性。\n', table(['品质','主属性倍率','普通词条数','掉落自带强化','购买 / 锻造初始强化'], [[r['name'],r['main_multiplier'],r['affix_count'],'0 / 1 / 2，权重60 / 30 / 10' if q=='gold' else '固定0','固定0'] for q,r in c['rarities'].items()])]
    out += ['## 4. 124件装备模板逐件主属性目标区间\n', '原96件保留ID、名称、种族、价格基准和固定特性；原静态属性键只决定词条抽选倾向，不再叠加一次旧面板。新增28件裤子/戒指无额外固定触发特性，贡献主属性、随机词条及套装计数。固定特性与42个套装阈值的完整当前数值见 [装备附录](CURRENT_HERO_EQUIPMENT_CATALOG.md)；S06改动见主方案。\n']
    templates = []
    for item in items.values():
        templates.append((item['id'],item['name'],item['slot'],item.get('set_id',''),c['starter_template_multiplier'] if not item.get('set_id') else 1, '、'.join(LABELS.get(k,c['affixes'].get(k,{}).get('name',k)) for k in item['base_stats']) or '无',item.get('affix_id','无')))
    for idx,(set_id,s) in enumerate(sorted(sets.items())):
        for delta,slot in enumerate(('legs','ring')):
            templates.append((f'EQ{97+idx*2+delta:02}',s['name']+('护腿' if slot=='legs' else '指环'),slot,set_id,1,'生命、护甲、魔抗' if slot=='legs' else '直接增伤、暴击率','无固定触发效果'))
    for slot,definition in c['slots'].items():
        out += [f"### {definition['name']}\n"]
        rows=[]
        for item_id,name,s,st,factor,tendency,effect in templates:
            if s!=slot: continue
            values=[]
            for ilvl,q,rank in ((1,'white',0),(20,'purple',0),(20,'purple',5),(20,'gold',2),(20,'gold',10)):
                a=main_range(c,s,'physical',ilvl,q,rank,factor)
                b=main_range(c,s,'magic',ilvl,q,rank,factor)
                values.append(a if a==b else '物理：'+a+'<br>法术：'+b)
            rows.append([item_id,name,st or '通用0.75倍',tendency,effect]+values)
        out += [table(['ID','名称','套装','2倍权重倾向键','固定特性ID','Lv1白+0','Lv20紫+0','Lv20紫+5','Lv20金掉落+2','Lv20金锻造+10'],rows)]
    out += ['## 5. 全部21种普通词条范围\n', '独立选类型、再选101档分位k=0..100；同件装备类型不重复。品质倍率作用全部普通词条；装备等级仅作用固定数值词条；强化不作用普通词条。\n']
    rows=[]
    for key,a in c['affixes'].items():
        vals=[]
        for ilvl,q in ((1,'white'),(20,'green'),(20,'purple'),(20,'gold')):
            factor=c['rarities'][q]['main_multiplier']*(1+c['main_item_level_per_level']*(ilvl-1) if a['scaling']=='flat' else 1)
            def display(value): return n(value*100)+'个百分点' if a['scaling']=='percent' else n(value)
            vals.append(display(a['min']*factor)+'–'+display(a['max']*factor))
        rows.append([key,a['name'],'、'.join(c['slots'][s]['name'] for s in a['slots']),a.get('power_type','两种类型'),a['scaling']]+vals)
    out += [table(['键','属性','允许槽位','适配类型','等级缩放','Lv1白基准（白装不实际抽词条）','Lv20绿','Lv20紫','Lv20金'],rows)]
    out += ['## 6. 强化、打造、重铸、精炼、继承成本\n', '装备等级金币系数S=1+0.03(i−1)；所有金币逐笔向上取整，所有材料不乘S。继承另补累计强化金币正差。\n']
    rows=[]
    for k in range(10):
        rows.append([f'+{k} → +{k+1}',c['enhancement_gold'][k],math.ceil(c['enhancement_gold'][k]*1.57),sum(c['enhancement_gold'][:k+1]),sum(math.ceil(x*1.57) for x in c['enhancement_gold'][:k+1]),c['enhancement_common'][k],c['enhancement_race'][k],c['enhancement_core'][k]])
    out += [table(['操作','Lv1金币','Lv20金币','Lv1累计金币','Lv20累计金币','锻材','种族材料','首领核心'],rows), table(['操作','Lv1金币','Lv20金币','锻材','种族材料','首领核心'], [[name,v['gold'],v['gold'] if name=='继承基础费' else math.ceil(v['gold']*1.57),v['common'],v['race'],v['core']] for name,v in [('造绿装',c['forge_costs']['green']),('造紫装',c['forge_costs']['purple']),('造金装',c['forge_costs']['gold']),('重铸',c['reroll_cost']),('精炼',c['refine_cost']),('继承基础费',c['inherit_cost'])]])]
    out += ['## 7. 全部难度掉落品质与自带强化概率\n', '表内品质概率为“已经触发一件装备掉落”之后的条件概率，不是每次击杀必掉。白/绿/紫均为+0；任何来源的金装掉落均最高+2。购买与打造均+0。\n']
    rows=[]
    for group,key,chance in [('普通野怪','normal_quality_weights','每击杀1%，每房最多2件'),('自然精英','elite_quality_weights','每击杀15%，每房最多1件'),('首领','boss_quality_weights','结算保底2 / 2 / 3 / 3 / 4件')]:
        for difficulty,weights in enumerate(c[key]): rows.append([group,f'D{difficulty}',chance]+[f'{x}%' for x in weights]+[n(weights[3]*0.6)+'%',n(weights[3]*0.3)+'%',n(weights[3]*0.1)+'%'])
    out += [table(['来源','难度','触发条件','白+0','绿+0','紫+0','金合计','金+0','金+1','金+2'],rows)]
    out += ['## 8. 敌人初始属性目标\n', '以下以当前真实Lv1/D0解析快照为基准：只将生命与原伤害乘1.35。普通怪之后按旧等级公式、再按新难度倍率计算；表列的精英已经包含旧精英倍率，不能再乘一次。初始快照来自 [冻结输入](current_enemy_initial_values.json)，源哈希与当前怪物附录一致。\n']
    for rank in ('normal','elite'):
        out += ['### '+('36普通原型' if rank=='normal' else '36可解析精英原型（自然生成18种见现状附录）')+'：Lv1 / D0\n']
        out += [table(['ID','名称','生命','原伤害','护甲','魔抗','移速','攻击距离','收势'], [[e['id'],e['name']]+[n(e['profiles'][rank][k]*c['enemy_baseline_multiplier'].get(k,1)) for k in ('max_hp','damage','armor','magic_resist','move_speed','attack_range','recovery_seconds')] for e in seeds['ordinary']])]
    out += ['### 四首领五难度完整属性（当前副本上限20）\n', '首领基值已含章节定位，不再乘普通怪的等级成长。D0–D2使用章节基值；D3/D4固定挑战20级，旧章首领额外生命×[1+0.055×(20−章节基准级)]、伤害×[1+0.025×(20−章节基准级)]。不读取玩家等级。\n']
    rows=[]
    for b in seeds['bosses']:
        s=b['stats']
        for d in range(5):
            gap=20-b['base_level'] if d>=3 else 0
            rows.append([b['id'],b['name'],b['base_level'],20 if d>=3 else b['base_level'],f'D{d}',n(s['max_hp']*1.35*(1+.055*gap)*c['difficulty_hp_multipliers'][d]),n(s['damage']*1.35*(1+.025*gap)*c['difficulty_damage_multipliers'][d]),n(s['armor']+3*d),n(s['magic_resist']+3*d),n(s['move_speed']*(1+.045*d))])
    out += [table(['ID','名称','章节基准等级','挑战等级','难度','生命','原伤害','护甲','魔抗','移速'],rows),table(['难度','生命倍率','伤害倍率','普通怪移速','普通怪护甲/魔抗','首领移速','首领护甲/魔抗'], [[f'D{d}',c['difficulty_hp_multipliers'][d],c['difficulty_damage_multipliers'][d],n(1+.04*d),f'+{2*d}',n(1+.045*d),f'+{3*d}'] for d in range(5)])]
    out += ['## 9. 罗砧样例：升级、六件套、八件装备的静态攻击收益\n', '以下随机主属性取中点R=1，**不计普通词条、临时Buff、暴击、连击或条件套装增伤**。18级样例六件均假设是Lv18紫装，强化沿用截图5/5/3/1/3/3；并非将现有玩家装备默认为紫装自动迁移。\n']
    h=heroes['CH01']
    rows=[]
    for level,quality,rank,slots,talent in [(18,'purple',None,['weapon','head','chest','hands','feet','charm'],0),(20,'purple',5,list(c['slots']),0),(20,'purple',5,list(c['slots']),.1),(20,'gold',10,list(c['slots']),.1)]:
        ranks={'weapon':5,'head':5,'chest':3,'hands':1,'feet':3,'charm':3}
        base=hero_stats(c,h,level)['attack']*(1+talent)
        equip=sum(main_value(c,core(c,s,'physical').get('attack',0),'attack',level,quality,rank if rank is not None else ranks[s],1) for s in slots)
        rows.append([level,'紫' if quality=='purple' else '金','截图强化' if rank is None else f'全+{rank}',len(slots),n(talent*100)+'%',n(base),n(equip),n(base+equip)])
    out += [table(['等级','品质','强化','槽数','攻击天赋加成','角色攻击','装备攻击','合计攻击'],rows),'此表只能验证静态计算；技能循环DPS、有效护盾、实际击杀时长仍需实现后做战斗样本验证。\n', '## 10. 全部房间、首领、可选箱的新奖励\n', '金币从现状policy1基础G0计算ceil(G0×2×[1+0.25D])，不对现有已放大的金币再相乘；自然击杀金币另计。以下每行是一个事件的收益，不是每次远征固定经过全部24房。\n']
    reward_names={}
    for line in (ROOT/'docs/balance/CURRENT_REWARD_CATALOG.md').read_text(encoding='utf-8').splitlines():
        if line.startswith('| L'):
            cells=[x.strip() for x in line.split('|')[1:-1]]
            if len(cells)==13:
                assert c['reward_base_gold'][cells[0]]==int(cells[3])
                reward_names[cells[0]]=cells[1]
    rows=[]
    for room_id,base in c['reward_base_gold'].items():
        rows.append([room_id,reward_names[room_id],base]+[math.ceil(base*c['reward_gold_base_multiplier']*(1+c['reward_difficulty_increment']*d)) for d in range(5)]+['30/38/45/53/60','180','1/1/1/1/1'])
    for boss in seeds['bosses']:
        rows.append([boss['id'],boss['name'],80]+[math.ceil(80*c['reward_gold_base_multiplier']*(1+c['reward_difficulty_increment']*d)) for d in range(5)]+['80/100/120/140/160','0','2/2/3/3/4'])
    for room_id,name,base in [('L01:side_crate','晴辉侧箱',18),('L11:research_2','虫窟研究箱',22)]:
        rows.append([room_id,name,base]+[math.ceil(base*c['reward_gold_base_multiplier']*(1+c['reward_difficulty_increment']*d)) for d in range(5)]+['0','0','1/1/1/1/1'])
    out += [table(['事件','名称','旧基础G0','D0金币','D1金币','D2金币','D3金币','D4金币','经验D0→D4','历练','装备数D0→D4'],rows)]
    rows=[]
    for d,mult in enumerate(c['material_difficulty_multipliers']):
        rows.append([f'D{d}',f"{math.ceil(3*mult)}/{math.ceil(mult)}/0",f"{math.ceil(2*mult)}/{math.ceil(mult)}/0",f"{math.ceil(8*mult)}/{math.ceil(4*mult)}/{c['material_boss_cores'][d]}"])
    out += [table(['难度','每房锻材/族材/核心','每自然精英额外锻材/族材/核心','每首领锻材/族材/核心'],rows),'材料按每个事件向上取整，核心不乘材料倍率；成功带回后永久结算。满级研究经验每360额外给4锻材/1族材，与上述收益分别记账。\n', '## 11. 复现与一致性边界\n', '`python tools/balance/render_target_numerical_tables.py --check` 检查参数范围、掉落概率、金装强化边界、全部模板数、词条可选数量、冻结来源哈希和文档逐字一致；不会读取玩家存档或启动游戏。\n']
    return '\n'.join(out).rstrip()+'\n'


def validate(c, heroes, items, sets, seeds):
    assert c['runtime_enabled'] is False
    assert len(heroes)==3 and len(items)==96 and len(sets)==14
    assert len(items)+2*len(sets)==124 and len(c['slots'])==8
    assert len(c['affixes'])==21 and c['main_roll']=={'min':.85,'max':1.15,'steps':100}
    assert len(seeds['ordinary'])==36 and len(seeds['bosses'])==4
    assert len(c['reward_base_gold'])==24
    assert hashlib.sha256((ROOT/'scripts/world/room_rewards.gd').read_bytes()).hexdigest()==c['reward_source_sha256']
    assert c['drop_enhancement']['non_gold']=={'0':100}
    assert c['drop_enhancement']['max']==2 and set(c['drop_enhancement']['gold'])=={'0','1','2'}
    assert sum(c['drop_enhancement']['gold'].values())==100
    for key in ('normal_quality_weights','elite_quality_weights','boss_quality_weights'):
        assert len(c[key])==5 and all(len(row)==4 and sum(row)==100 and min(row)>=0 for row in c[key])
    assert sum(c['item_level_offsets'].values())==100
    for slot in c['slots']:
        for power in ('physical','magic'):
            available=[key for key,a in c['affixes'].items() if slot in a['slots'] and a.get('power_type',power)==power]
            assert len(available)>=4,(slot,power,available)
    for key,digest in seeds['source_sha256'].items():
        assert hashlib.sha256((ROOT/key).read_bytes()).hexdigest()==digest, key
    assert abs(hero_stats(c,heroes['CH01'],18)['attack']-45.36)<1e-8
    assert abs(main_value(c,9,'attack',20,'gold',10,1)-49.14)<1e-8
    assert all(c['xp_thresholds_1_20'][i]<c['xp_thresholds_1_20'][i+1] for i in range(19))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    c=load(PARAMS)
    heroes=load(ROOT/'data/heroes.json')
    items=load(ROOT/'data/equipment.json')
    sets=load(ROOT/'data/sets.json')
    seeds=load(SEEDS)
    validate(c,heroes,items,sets,seeds)
    result=render(c,heroes,items,sets,seeds)
    if args.check:
        assert OUTPUT.read_text(encoding='utf-8')==result,'Target document differs; regenerate it'
        print('PASS: 3 heroes / 60 growth rows / 60 XP levels / 124 templates / 21 affixes / 72 enemy initials / 20 boss values / 30 reward events; proposal formulas and source hashes verified')
    else:
        OUTPUT.write_text(result,encoding='utf-8')
        print('Rendered',OUTPUT)


if __name__=='__main__':
    main()
