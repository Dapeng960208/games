#!/usr/bin/env python3
"""Import actual archive15 resolver rows into existing chapter documentation.
A profile verification/export, not a claim of full damage or combat acceptance.
"""
import argparse, csv, hashlib, io, json, subprocess
from collections import defaultdict
from pathlib import Path
from sync_level_numerical_docs import ROOT, OUT, DOCS, info, constant, frozen_text, I, replace_block
FIELDS=['id','chapter','level','rank','difficulty','primary_role','max_hp','damage','ability_power','skill_base_power','armor','magic_resist','crit_chance','crit_multiplier']
TEXT={'id','rank','primary_role'};FLOAT={'crit_chance','crit_multiplier'}
SOURCES=['data/enemy_species_policy_v4.json','scripts/combat/enemy_species_policy.gd','scripts/combat/shared_enemy_growth.gd','scripts/combat/crit_policy.gd','scripts/combat/enemy_calibration.gd','scripts/combat/enemy_profiles.gd','scripts/combat/enemy_numerical_v2.gd','scripts/combat/b05_enemy_numbers.gd','scripts/combat/b06_enemy_numbers.gd','scripts/combat/boss_profiles.gd']
PROPOSAL='docs/balance/proposals/ENEMY_SPECIES_V4_CANDIDATE.json'
def verify(rows,defs,meta):
    g=frozen_text('scripts/combat/shared_enemy_growth.gd');roles=constant(g,'ROLES');hd=constant(g,'HP_D');ad=constant(g,'ATTACK_D')
    crit=(ROOT/'scripts/combat/crit_policy.gd').read_text()
    defaultc=constant(crit,'DEFAULT_CHANCE');defaultm=constant(crit,'DEFAULT_MULTIPLIER');capc=constant(crit,'MAX_CHANCE');capm=constant(crit,'MAX_MULTIPLIER')
    with (OUT/'ARCHIVE14_B01_B06.csv').open() as f: old=list(csv.DictReader(f))
    keys=lambda r:(r['id'],int(r['level']),r['rank'],int(r['difficulty']))
    old={keys(r):r for r in old};assert len(rows)==len(old)==2730 and {keys(r) for r in rows}==set(old)
    assert set(defs)==set(meta) and len(defs)==90
    for r in rows:
        L,B,D=r['level'],r['chapter'],r['difficulty'];assert 1<=B<=6
        if r['rank']=='boss':
            expected={k:int(old[keys(r)][k]) for k in ['max_hp','damage','armor','magic_resist']}
            expected.update(ability_power=0,skill_base_power=0,primary_role='boss',crit_chance=defaultc,crit_multiplier=defaultm)
        else:
            name,ch,raw,archetype,authored=meta[r['id']];assert ch==B
            d=defs[r['id']];a=roles[archetype];p=d['specialization_percent'];elite=r['rank']=='elite';t=4 if L>=15 else 3 if L>=10 else 2 if L>=5 else 1
            growth=.5*(L-1)+(B-1)+2*D
            hp=raw['max_hp']*a[0]*(1+.055*(L-1))*(1.2 if elite else 1)*1.35*10*(1+.12*(B-1))*hd[D]
            attack=min(16.9,max(a[2],raw['damage']*a[1]))*(1+.025*(L-1))*(1.12 if elite else 1)*1.35*10*(1+.08*(B-1))*ad[D]
            armor=(min(24,raw['armor']*a[3]+a[4]+(t-1)*a[5])+growth)*10
            mr=(min(32,raw['magic_resist']+(t-1)*a[6]+(4 if elite else 0))+growth)*10
            expected={k:I(v*p[k]/100) for k,v in [('max_hp',hp),('damage',attack),('armor',armor),('magic_resist',mr)]}
            expected.update(ability_power=I(attack*d['ability_power_percent_of_base_attack']/100),skill_base_power=I(attack*d['skill_base_attack_budget_ratio']),primary_role=d['primary_role'],crit_chance=min(capc,defaultc+d['crit_chance_bonus']),crit_multiplier=min(capm,defaultm+d['crit_multiplier_bonus']))
            if d['primary_role']=='tank':assert p=={'max_hp':200,'damage':100,'armor':130,'magic_resist':130}
        for k,v in expected.items():assert r[k]==v,(r['id'],L,D,r['rank'],k,r[k],v)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--input',type=Path);ap.add_argument('--check',action='store_true');args=ap.parse_args()
    path=OUT/'ARCHIVE15_B01_B06.csv'
    if args.input:rows=json.loads(args.input.read_text())
    else:
        with path.open() as f:rows=[{k:v if k in TEXT else float(v) if k in FLOAT else int(v) for k,v in r.items()} for r in csv.DictReader(f)]
    rows=sorted(rows,key=lambda r:(r['chapter'],r['id'],r['level'],r['rank'],r['difficulty']))
    config=json.loads((ROOT/SOURCES[0]).read_text());assert config['base_multiplier']==1 and not config['default_enabled']
    defs=config['enemies'];meta=info();verify(rows,defs,meta)
    proposal=json.loads((ROOT/PROPOSAL).read_text());evidence=proposal['level_evidence'];ep=ROOT/evidence['path']
    assert hashlib.sha256(ep.read_bytes()).hexdigest()==evidence['sha256']
    spawned=json.loads(ep.read_text())['actual_spawn_rows'];details=proposal['enemies'];assert set(details)==set(defs)
    for id,e in details.items():
        observed={(r['room'],r['enemy_level'],r['difficulty'],r['rank']) for r in spawned if r['enemy_id']==id}
        claimed={(r['room'],r['level'],r['difficulty'],r['rank']) for r in e['spawn_evidence']};assert claimed==observed,id
        for key in ['primary_role','secondary_role','specialization_percent','ability_power_percent_of_base_attack','crit_chance_bonus','crit_multiplier_bonus','skill_base_attack_budget_ratio']:assert e[key]==defs[id][key],(id,key)
    buf=io.StringIO();w=csv.DictWriter(buf,fieldnames=FIELDS,lineterminator='\n');w.writeheader();w.writerows([{k:r[k] for k in FIELDS} for r in rows]);data=buf.getvalue()
    manifest={'profile_source_commit':'591a0ab','damage_source_commit':'b222dcbf885ce57b996ad0ba72f43399471f28ac','archive':15,'enemy_species_version':4,'default_enabled':False,'profile_export_checks':42847,'profile_export_failures':0,'row_count':2730,'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES},'spawn_evidence':evidence,'csv_sha256':hashlib.sha256(data.encode()).hexdigest(),'boundary':'Profile resolver verification only. Damage packets, RNG, movement and full combat require separate evidence.'}
    generated={path:data,OUT/'ARCHIVE15_MANIFEST.json':json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'}
    lookup={(r['id'],r['level'],r['rank'],r['difficulty']):r for r in rows}
    def v(id,L,rank,d):return ' / '.join(str(lookup[id,L,rank,d][k]) for k in ['max_hp','damage','ability_power','armor','magic_resist'])
    for ch,filename in enumerate(DOCS,1):
        lines=['## archive15逐种定位、等级与属性（隔离候选）','', '统一基础1.0；普通/精英v4替代archive14的1.5与旧定位专项，不在旧整数面板上除乘。坦克HP×2、甲/MR×1.30为用户精确要求；其余定位量值为待验实现选项。默认新出发仍archive14，15仅显式隔离候选。Boss四属性沿独立v2，新增全局暴击不等于Boss实战已验收。','', '下表逐ID列出主副定位、实际出场计划D0/D4样本的房间:等级配对、专项和源基础。房间分布不是解析器全网格，D1–D3与召唤出场另验。B01–B04同房不同战区可变级；B05/B06按房固定级。英雄最低入场等级/装备基准不改怪物等级，不随玩家追平。','', '| ID / 名称 | 主定位；副职责 | 已采样房间:等级 | HP / AD / 甲 / MR专项% | AP预算% | 最终暴击率 / 暴伤 |','|---|---|---|---|---:|---|']
        ids=sorted(id for id,e in details.items() if e['chapter']==ch)
        for id in ids:
            e=details[id];d=defs[id];rooms=defaultdict(set)
            for r in e['spawn_evidence']:rooms[r['room']].add(r['level'])
            groups=defaultdict(list)
            for room,levels in sorted(rooms.items()):groups[tuple(sorted(levels))].append(room)
            spawn='；'.join(','.join(rr)+':'+ '/'.join(map(str,ll)) for ll,rr in groups.items())
            p=' / '.join(str(d['specialization_percent'][k]) for k in ['max_hp','damage','armor','magic_resist'])
            sample=lookup[id,min(e['actual_spawn_levels']),'normal',0]
            lines.append(f"| {id} {e['name']} | {e['primary_role_zh']}；{e['secondary_role']} | {spawn} | {p} | {d['ability_power_percent_of_base_attack']} | {sample['crit_chance']*100:g}% / ×{sample['crit_multiplier']:g} |")
        lines+=['', '### 真实resolver属性表','', '每种取实际已采样最低出场等级，列内顺序 **HP / AD / AP / 护甲 / 魔抗**。精英与D4列是相同ID/等级的可解析合同，不宣称该ID在此房自然生成精英。法系另有 `skill_base_power=I(A0×0.25)`，A0为专精前未取整基础攻击；AP与技能基础不从已降低的AD倒算。全部2730行含技能基础、最终暴击和中间难度见[archive15完整CSV](../balance/resolver_tables/ARCHIVE15_B01_B06.csv)。','', '| ID | 展示Lv | 普通D0 | 精英D0 | 普通D4 | 精英D4 |','|---|---:|---|---|---|---|']
        for id in ids:
            L=min(details[id]['actual_spawn_levels']);lines.append(f'| {id} | {L} | '+' | '.join(v(id,L,rank,d) for rank,d in [('normal',0),('elite',0),('normal',4),('elite',4)])+' |')
        hero_level=5*(ch-1)+1
        naked='B01 D0–D2允许裸装连续整章通关；D3/D4不应裸通。' if ch==1 else f'B{ch:02d}全部D0–D4不应裸装连续整章通关。'
        lines+=['','### 本章当前验收协议','',f'角色固定Lv{hero_level}；装备iLv≤{hero_level}，天赋/技能必须是该级实际合法范围。这是测试协议，不新增准入门槛，也不改怪物房间等级。'+naked+'所有样本采用正常连续整章；不要求秒死或首房死亡，不以逐房满血重置/旧章末级样本代替。旧Lv25/Lv30或archive14结果仍只代表其原冻结条件，不能标作新协议通过。']
        lines+=['', '来源：`data/enemy_species_policy_v4.json`、真实profile导出42847项0失败（含archive14黄金回放）。[来源指纹](../balance/resolver_tables/ARCHIVE15_MANIFEST.json)与 `python tools/balance/sync_species_numerical_docs.py --check` 校验2730行及实际出场样本配对。这里只证明属性解析和旧版回放；AP实际技能、暴击seed/多段、行为节奏和三职业整关须看独立检查，不能据本表宣称通过。']
        doc=ROOT/'docs/levels'/filename;generated[doc]=replace_block(doc,'ARCHIVE15_PROFILE','\n'.join(lines))
    for p,body in generated.items():
        if args.check:assert p.exists() and p.read_text()==body,f'Stale archive15 document: {p.relative_to(ROOT)}'
        else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(body)
    print('Verified 2730 archive15 profile rows and 90 species in original chapter documents.' if args.check else 'Synchronized archive15 profile candidate into six original chapter documents.')
if __name__=='__main__':main()
