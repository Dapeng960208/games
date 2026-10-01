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


def integer(value):
    return math.floor(max(0,value)+.5)


def table(headers, rows):
    esc = lambda x: str(x).replace('|', '\\|').replace('\n', '<br>')
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join(['---'] * len(headers)) + ' |'] + ['| ' + ' | '.join(esc(x) for x in row) + ' |' for row in rows]) + '\n\n'


def stat(value, key):
    return n(value * 100) + '%' if key == 'move_speed' else n(value)


def core(c, slot, power):
    return c['slots'][slot].get('shared', c['slots'][slot].get(power, {}))


def enhancement_multiplier(c, rank, mode='reference'):
    gains = [int(x) for x in c['enhancement_random']['gain_percent_weights']]
    per_rank = min(gains) if mode == 'min' else max(gains) if mode == 'max' else c['enhancement_reference_per_rank'] * 100
    return 1 + rank * per_rank / 100


def main_value(c, base, key, ilvl, quality, rank, roll, factor=1, enhancement_mode='reference'):
    percentage=key in c['percentage_main_keys']
    scale = 1 if percentage else (1 + c['main_item_level_per_level'] * (ilvl - 1)) * enhancement_multiplier(c, rank, enhancement_mode)
    value=base * factor * scale * c['rarities'][quality]['percentage_multiplier' if percentage else 'main_multiplier'] * roll
    return value if percentage else integer(value)


def main_range(c, slot, power, ilvl, quality, rank, factor=1):
    return '；'.join(f"{LABELS[k]} {stat(main_value(c,b,k,ilvl,quality,rank,c['main_roll']['min'],factor,'min'),k)}–{stat(main_value(c,b,k,ilvl,quality,rank,c['main_roll']['max'],factor,'max'),k)}" for k,b in core(c,slot,power).items())


def hero_stats(c, h, level):
    result = {}
    for key in ('attack', 'ability_power', 'max_hp', 'armor', 'magic_resist'):
        base = h.get(key, 0 if key == 'ability_power' else 12 if key == 'magic_resist' else 0)
        result[key] = integer(base*c['combat_scale']*(1+c['growth'][key]*(level-1)) if key in ('attack','ability_power','max_hp') else base*c['combat_scale']+c['growth'][key]*(level-1))
    return result


def enemy_chapter(enemy_id):
    return (int(enemy_id[1:]) - 1) // 9 + 1


def chapter_factor(c, chapter, key):
    return 1 + c['chapter_hp_per_step' if key == 'max_hp' else 'chapter_damage_per_step'] * (chapter - 1)


def render(c, heroes, items, sets, seeds):
    out = ['# 重构目标数值全表（待确认）\n', f"日期：{c['date']}。源提交：`{c['source_commit']}`。**以下全部为设计建议，尚未接入游戏。** 当前实现见四个 CURRENT 附录；解释与规则见 [主方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)。\n", '数值由 [参数文件](numerical_v2_parameters.json) 与 [生成器](../../tools/balance/render_target_numerical_tables.py) 生成。新版战斗属性/伤害以原基值×10，所有平值取非负四舍五入整数I(x)=floor(x+0.5)；百分比、时间、移动速度、距离、货币/材料、层数不乘10。单件主属性/词条在完整表达式后取整，角色聚合/技能H/每次伤害护盾治疗另在对应节点取整。主属性区间不包含普通词条、天赋、套装或临时Buff。\n', '## 1. 三角色初始属性与逐级成长\n']
    out += [table(['角色','生命','攻击','法强','护甲','魔抗','普攻间隔','射程','移速','初始资源 / 上限','资源基础回复'], [[h['id']+' '+h['name'],h['max_hp']*10,h['attack']*10,h.get('ability_power',0)*10,h['armor']*10,h.get('magic_resist',12)*10,h['attack_interval'],h['range'],h['move_speed'],f"{h['starting_resource']*10} / {h['resource_max']*10}",h['resource_regen']*10] for h in heroes.values()])]
    out += ['法师新普攻H=I(AD+0.35AP)，初始278；技能H=I(AD+0.7AP)，初始376；职业遗物仍AP，初始280。上表攻击180是AD。全部主动/分支/状态/资源新版详见 [技能Buff目标册](TARGET_HERO_SKILL_BUFF_TABLES.md)。\n']
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
        return {1:'Q',2:'W',3:'E',4:'R',5:'绿色定向锻造；+3；词条重铸',10:'紫色定向锻造；+5；Q强化；词条精炼/强化重锻',12:'W强化',14:'E强化',15:'金色定向锻造；+8',16:'R强化',18:'Q永久A/B分支',20:'R永久A/B分支；+10；研究经验'}.get(level,'每级基础成长、1天赋点' if level>1 else '')
    out += [table(['等级','累计经验','升到下一级','副本上限归属','额外解锁'], [[level,thresholds[level-1],thresholds[level]-thresholds[level-1] if level<60 else '最终上限',f"第{math.ceil(level/5)}副本",unlock(level)] for level in range(1,61)])]
    out += ['## 3. 八槽主属性基准与品质\n', table(['槽位','物理型Lv1白+0范围','法术型Lv1白+0范围'], [[v['name'],main_range(c,k,'physical',1,'white',0),main_range(c,k,'magic',1,'white',0)] for k,v in c['slots'].items()]), '上表展示85%–115%主roll范围，中点100%。金同等级/同强化增幅向量平值中点为白1.875倍，最差主roll对最高白roll仍高约38.6%；若+10强化增幅也分别极端，最低金仍高约13.4%（整数端点有微小偏移），另多4条词条。百分比不受强化影响、不乘10。\n', table(['品质','平值主属性/词条倍率','百分比主属性/词条倍率','普通词条数','掉落自带强化','购买 / 锻造初始强化'], [[r['name'],r['main_multiplier'],r['percentage_multiplier'],r['affix_count'],'0/1，权重70/30' if q=='gold' else '0/1/2/3/4/5，权重60/20/10/5/3/2','固定0'] for q,r in c['rarities'].items()])]
    comparisons=[]
    for q1,n1,q2,n2 in [('white',5,'green',3),('green',5,'purple',2),('purple',5,'gold',2)]:
        f1=c['rarities'][q1]['main_multiplier']*enhancement_multiplier(c,n1)
        f2=c['rarities'][q2]['main_multiplier']*enhancement_multiplier(c,n2)
        comparisons.append([c['rarities'][q1]['name']+f'+{n1}',n(f1),c['rarities'][q2]['name']+f'+{n2}',n(f2),n((f2/f1-1)*100)+'%',main_value(c,90,'attack',20,q1,n1,1),main_value(c,90,'attack',20,q2,n2,1)])
    out += [table(['左配装品质/N','参考Q×E','右配装品质/N','参考Q×E','右比左差','Lv20武器左攻击','Lv20武器右攻击'],comparisons),'品质强化等效比较固定i/T/R、每阶g=10%，只比平值主属性；普通词条和固定机制另计，随机极端不保证等值。金+2是玩家锻造结果，金掉落最高+1。\n']
    out += ['## 4. 124件装备模板逐件主属性目标区间\n', '原96件保留ID、名称、种族、价格基准和固定特性；原静态属性键只决定词条抽选倾向，不再叠加一次旧面板。新增28件裤子/戒指无额外固定触发特性，贡献主属性、随机词条及套装计数。固定特性与42个套装阈值的完整当前数值见 [装备附录](CURRENT_HERO_EQUIPMENT_CATALOG.md)；S06改动见主方案。\n']
    out += ['下表强化列为**主roll和每阶随机增幅同时取极端的完整范围**，不再假设每阶固定10%。参考算例若所有g=10%，必须单独标注；百分比主属性不乘强化向量。\n']
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
            for ilvl,q,rank in ((1,'white',0),(20,'purple',0),(20,'purple',5),(20,'gold',1),(20,'gold',10)):
                a=main_range(c,s,'physical',ilvl,q,rank,factor)
                b=main_range(c,s,'magic',ilvl,q,rank,factor)
                values.append(a if a==b else '物理：'+a+'<br>法术：'+b)
            rows.append([item_id,name,st or '通用0.75倍',tendency,effect]+values)
        out += [table(['ID','名称','套装','2倍权重倾向键','固定特性ID','Lv1白+0','Lv20紫+0','Lv20紫+5','Lv20金掉落+1','Lv20金锻造+10'],rows)]
    out += ['## 5. 全部21种普通词条范围\n', '独立选类型、再选101档分位k=0..100；同件装备类型不重复。品质倍率作用全部普通词条；装备等级仅作用固定数值词条；强化不作用普通词条。\n']
    rows=[]
    for key,a in c['affixes'].items():
        vals=[]
        for ilvl,q in ((1,'white'),(20,'green'),(20,'purple'),(20,'gold')):
            factor=c['rarities'][q]['main_multiplier' if a['scaling']=='flat' else 'percentage_multiplier']*(1+c['main_item_level_per_level']*(ilvl-1) if a['scaling']=='flat' else 1)
            def display(value): return n(value*100)+'个百分点' if a['scaling']=='percent' else str(integer(value))
            vals.append(display(a['min']*factor)+'–'+display(a['max']*factor))
        rows.append([key,a['name'],'、'.join(c['slots'][s]['name'] for s in a['slots']),a.get('power_type','两种类型'),a['scaling']]+vals)
    out += [table(['键','属性','允许槽位','适配类型','等级缩放','Lv1白基准（白装不实际抽词条）','Lv20绿','Lv20紫','Lv20金'],rows)]
    out += ['## 6. 强化、打造、重铸、精炼、继承成本\n', '装备等级金币系数S=1+0.03(i−1)；所有金币逐笔向上取整，所有材料不乘S。继承另补累计强化金币正差。\n']
    out += ['### 6.1 随机强化增幅与有界重锻\n', '每次支付必升一级，给该阶全部平值主属性共享一个随机g；E=1+Σg/100，主属性完整表达式后I。主roll k、普通词条u、品质/等级/固定特性不重抽。初次抽样独立，不加保底改变均值；单阶均值10个百分点，方差1.2平方百分点。所有预强化掉落也独立抽每阶g，支付记录为0。\n', table(['每阶g','概率','强化结果标识'], [[k+'个百分点',str(v)+'%',{'8':'基础','9':'良好','10':'标准','11':'卓越','12':'完美'}[k]] for k,v in c['enhancement_random']['gain_percent_weights'].items()]), table(['N','E最低','全10%参考E','E最高','最多重锻次数到全12%（最坏全8%）'], [[rank,n(enhancement_multiplier(c,rank,'min')),n(enhancement_multiplier(c,rank)),n(enhancement_multiplier(c,rank,'max')),rank*16] for rank in range(11)]), 'Lv10解锁强化重锻：选择已存在且g<12的一阶，用同样概率抽新g，只接受max(old,new)。连续3次未提高后，第4次直接升1个百分点；成功提高则计数归0。每阶独立计数，最多16次从8变12；不是16次保证完美主roll或词条。未解锁强化阶、g=12、无可改善平值主属性或事务未完成时拒绝扣费。\n']
    reroll_rows=[]
    for k in range(10):
        reroll_rows.append([f'重锻第{k+1}阶',math.ceil(c['enhancement_gold'][k]*.5),math.ceil(c['enhancement_gold'][k]*.5*1.57),math.ceil(c['enhancement_common'][k]*.5),math.ceil(c['enhancement_race'][k]*.5),0])
    out += [table(['操作','Lv1金币','Lv20金币','锻材','族材','核心'],reroll_rows), '重锻费用先完整乘0.5和S，再ceil；材料各ceil(单级材料×0.5)，核心0。重锻无提升也计一次已支付尝试和保底进度；费用不退款。每阶最多16次最坏成本见主稿；没有每日次数或真实时间等待。继承逐阶取max，sourceN≥targetN且总增幅严格改善才交易；同+10可改善，来源归0。重锻历史包括无提升记录，逐笔补到目标i的历史最高结算等级，不能低级廉价重锻再免费转高级。\n', '### 6.2 强化与其它操作成本\n']
    rows=[]
    for k in range(10):
        rows.append([f'+{k} → +{k+1}',c['enhancement_gold'][k],math.ceil(c['enhancement_gold'][k]*1.57),sum(c['enhancement_gold'][:k+1]),sum(math.ceil(x*1.57) for x in c['enhancement_gold'][:k+1]),c['enhancement_common'][k],c['enhancement_race'][k],c['enhancement_core'][k]])
    out += [table(['操作','Lv1金币','Lv20金币','Lv1累计金币','Lv20累计金币','锻材','种族材料','首领核心'],rows), table(['操作','Lv1金币','Lv20金币','锻材','种族材料','首领核心'], [[name,v['gold'],v['gold'] if name=='继承基础费' else math.ceil(v['gold']*1.57),v['common'],v['race'],v['core']] for name,v in [('造绿装',c['forge_costs']['green']),('造紫装',c['forge_costs']['purple']),('造金装',c['forge_costs']['gold']),('重铸',c['reroll_cost']),('精炼',c['refine_cost']),('继承基础费',c['inherit_cost'])]])]
    out += ['## 7. 全部难度掉落品质与自带强化概率\n', '表内品质概率为已触发掉装后的条件概率。最新边界：金最高+1，白绿紫可+5；购买/打造+0。N按品质条件抽，g再逐阶抽；免费掉落无强化支出。\n',table(['品质','+0','+1','+2','+3','+4','+5'],[[r['name']]+[str(c['drop_enhancement']['gold' if q=='gold' else 'non_gold'].get(str(rank),0))+'%' for rank in range(6)] for q,r in c['rarities'].items()])]
    rows=[]
    for group,key,chance in [('普通野怪','normal_quality_weights','每击杀1%，每房最多2件'),('自然精英','elite_quality_weights','每击杀15%，每房最多1件'),('首领','boss_quality_weights','结算保底2 / 2 / 3 / 3 / 4件')]:
        for difficulty,weights in enumerate(c[key]): rows.append([group,f'D{difficulty}',chance]+[f'{x}%' for x in weights]+[n(weights[0]*.02)+'%',n(weights[1]*.02)+'%',n(weights[2]*.02)+'%',n(weights[3]*.7)+'%',n(weights[3]*.3)+'%'])
    out += [table(['来源','难度','触发条件','白合计','绿合计','紫合计','金合计','白+5','绿+5','紫+5','金+0','金+1'],rows)]
    all_joint=[]
    for group,key in [('普通/清房/箱','normal_quality_weights'),('自然精英','elite_quality_weights'),('首领','boss_quality_weights')]:
        for d,quality_weights in enumerate(c[key]):
            for idx,(q,r) in enumerate(c['rarities'].items()):
                distribution=c['drop_enhancement']['gold' if q=='gold' else 'non_gold']
                all_joint.append([group,f'D{d}',r['name']]+[n(quality_weights[idx]*distribution.get(str(rank),0)/100)+'%' for rank in range(6)])
    out += [table(['来源','难度','品质','+0联合','+1联合','+2联合','+3联合','+4联合','+5联合'],all_joint),'联合概率=品质概率×该品质N概率；自然击杀还须乘1%/15%触发率并考虑房间上限。D4保底替换为金时重新生成金N0/1和g，不能保留原紫+5。\n']
    out += ['## 8. 敌人初始属性目标\n', '以当前真实Lv1/D0解析快照为基准：生命/原伤害×1.35×10×所属章节因子，双抗×10，完整计算后整数；时空不放大。精英已含旧倍率，不重乘。全部144阶/40Boss新包见 [敌人技能目标册](TARGET_ENEMY_SKILL_TABLES.md)。初值来自 [冻结输入](current_enemy_initial_values.json)。\n', '### 1–12章递增等级与归一化野怪标尺\n', '每章三个区5(B−1)+1/3/5、Boss5B，所有D均固定本章等级；D0–D4另乘难度倍率。章因子HP=1+.12(B−1)、原伤害=1+.08(B−1)，在演员完整表达式中各乘一次。下表标准原型固定M01旧Lv1 HP60/A14，只是归一化强度接口，不能冒充B05–B12新敌人；不同战斗职责的怪物不要求每只HP都大于前章。前三列为规划，只有B01–B04可进入。\n']
    chapter_rows=[]
    for b in range(1,13):
        levels=[5*(b-1)+j for j in (1,3,5)]
        hp=60*1.35*10*(1+.055*(levels[-1]-1))*chapter_factor(c,b,'max_hp')
        attack=14*1.35*10*(1+.025*(levels[-1]-1))*chapter_factor(c,b,'damage')
        chapter_rows.append([f'B{b:02}', '已发布4章内设计目标' if b<=4 else '未来接口，内容未制作', '/'.join(map(str,levels)),5*b,n(chapter_factor(c,b,'max_hp')),n(chapter_factor(c,b,'damage')),integer(hp),integer(attack),integer(hp*c['difficulty_hp_multipliers'][4]),integer(attack*c['difficulty_damage_multipliers'][4])])
    out += [table(['章','内容边界','三区固定等级','Boss等级','章HP因子','章A因子','标准原型末区D0 HP','D0 A','末区D4 HP','D4 A'],chapter_rows)]
    for rank in ('normal','elite'):
        out += ['### '+('36普通原型' if rank=='normal' else '36可解析精英原型（自然生成18种见现状附录）')+'：Lv1 / D0\n']
        out += [table(['ID','名称','章','生命','原伤害','护甲','魔抗','移速','攻击距离','收势'], [[e['id'],e['name'],enemy_chapter(e['id'])]+[str(integer(e['profiles'][rank][k]*c['enemy_baseline_multiplier'].get(k,1)*c['combat_scale']*(chapter_factor(c,enemy_chapter(e['id']),k) if k in ('max_hp','damage') else 1))) if k in ('max_hp','damage','armor','magic_resist') else n(e['profiles'][rank][k]) for k in ('max_hp','damage','armor','magic_resist','move_speed','attack_range','recovery_seconds')] for e in seeds['ordinary']])]
    out += ['### 四首领五难度完整属性（当前副本上限20）\n', '首领原STATS已含章节定位，不乘普通等级成长；再乘1.35、×10、章因子和D倍率。所有D固定5B，移除前稿D3/D4全20级及Δ追平。全金约+2标准配装的35–50秒/剩HP≥60%只是待验证平衡目标，见 [逐章Boss标尺](BOSS_DIFFICULTY_CALIBRATION.md)，当前倍率未证明达到。\n']
    rows=[]
    for b in seeds['bosses']:
        s=b['stats']
        for d in range(5):
            chapter=b['base_level']//5
            rows.append([b['id'],b['name'],b['base_level'],b['base_level'],f'D{d}',integer(s['max_hp']*1.35*10*chapter_factor(c,chapter,'max_hp')*c['difficulty_hp_multipliers'][d]),integer(s['damage']*1.35*10*chapter_factor(c,chapter,'damage')*c['difficulty_damage_multipliers'][d]),integer((s['armor']+3*d)*10),integer((s['magic_resist']+3*d)*10),n(s['move_speed']*(1+.045*d))])
    out += [table(['ID','名称','章节基准等级','挑战等级','难度','生命','原伤害','护甲','魔抗','移速'],rows),table(['难度','生命倍率','伤害倍率','普通怪移速','普通怪护甲/魔抗','首领移速','首领护甲/魔抗'], [[f'D{d}',c['difficulty_hp_multipliers'][d],c['difficulty_damage_multipliers'][d],n(1+.04*d),f'+{20*d}',n(1+.045*d),f'+{30*d}'] for d in range(5)])]
    out += ['## 9. 罗砧样例：升级、六件套、八件装备的静态攻击收益\n', '以下主roll取中点R=1、每阶g=10%的参考向量，**不是任意随机强化必得值**；不计普通词条、临时Buff、暴击、连击或条件套装增伤。18级样例六件均假设是Lv18紫装，N沿截图5/5/3/1/3/3，并非自动迁移认定。\n']
    h=heroes['CH01']
    rows=[]
    for level,quality,rank,slots,talent in [(18,'purple',None,['weapon','head','chest','hands','feet','charm'],0),(20,'purple',5,list(c['slots']),0),(20,'purple',5,list(c['slots']),.1),(20,'gold',10,list(c['slots']),.1)]:
        ranks={'weapon':5,'head':5,'chest':3,'hands':1,'feet':3,'charm':3}
        base=integer(h['attack']*c['combat_scale']*(1+c['growth']['attack']*(level-1))*(1+talent))
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
    assert c['drop_enhancement']['non_gold']=={'0':60,'1':20,'2':10,'3':5,'4':3,'5':2}
    assert c['drop_enhancement']['max_by_rarity']=={'white':5,'green':5,'purple':5,'gold':1}
    assert c['drop_enhancement']['gold']=={'0':70,'1':30}
    assert sum(c['drop_enhancement']['non_gold'].values())==100
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
    assert c['combat_scale']==10 and c['resistance_denominator']==1000
    random=c['enhancement_random']
    weights=random['gain_percent_weights']
    assert weights=={'8':10,'9':20,'10':40,'11':20,'12':10}
    assert sum(weights.values())==100 and sum(int(k)*v for k,v in weights.items())==1000
    assert random['rank_success_rate']==1 and random['reroll_no_improvement_pity']==4
    assert c['enhancement_reference_per_rank']==.1 and random['gain_percent_max']==12
    assert enhancement_multiplier(c,10,'min')==1.8 and enhancement_multiplier(c,10,'max')==2.2
    assert main_value(c,90,'attack',20,'gold',10,.85,enhancement_mode='min')>main_value(c,90,'attack',20,'white',10,1.15,enhancement_mode='max')
    assert sum(math.ceil(x*1.57) for x in c['enhancement_gold'])==3930
    assert c['chapter_hp_per_step']==.12 and c['chapter_damage_per_step']==.08
    chapter_hps=[60*(1+.055*(5*b-1))*chapter_factor(c,b,'max_hp') for b in range(1,13)]
    chapter_attacks=[14*(1+.025*(5*b-1))*chapter_factor(c,b,'damage') for b in range(1,13)]
    assert all(x<y for x,y in zip(chapter_hps,chapter_hps[1:]))
    assert all(x<y for x,y in zip(chapter_attacks,chapter_attacks[1:]))
    assert hero_stats(c,heroes['CH01'],18)['attack']==454
    assert main_value(c,90,'attack',20,'gold',10,1)==658
    assert main_value(c,90,'attack',20,'green',5,1)==main_value(c,90,'attack',20,'purple',2,1)
    assert main_value(c,90,'attack',20,'purple',5,1)==main_value(c,90,'attack',20,'gold',2,1)
    assert integer(1.5)==2 and integer(.49)==0
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
