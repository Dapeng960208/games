#!/usr/bin/env python3
"""Verify archive14 resolver rows and synchronize the original chapter documents.

Import actual Godot output with --input; --check verifies the committed CSV,
source fingerprints, complete roster grid, formula parity and generated blocks.
This is a documentation check, not a combat acceptance runner.
"""
import argparse, ast, csv, hashlib, io, json, math, re, subprocess
from functools import lru_cache
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/balance/resolver_tables'
SOURCES = ['scripts/combat/shared_enemy_growth.gd','scripts/combat/monster_role_policy.gd','scripts/combat/boss_progression_policy.gd','scripts/combat/enemy_profiles.gd','scripts/combat/enemy_numerical_v2.gd','scripts/combat/b05_enemy_numbers.gd','scripts/combat/b06_enemy_numbers.gd','scripts/combat/enemy_calibration.gd','data/enemy_progression.json','data/enemies.json','data/b05_content.json','data/b06_content.json','data/numerical_v2.json']
DOCS = ['01_SUNLIT_RUINS.md','02_AMBER_HIVE.md','03_PUMPKIN_TOWN.md','04_REDROCK_FORT.md','05_BLOOMING_TREE_COURT.md','06_TIDAL_CORAL_CITY.md']
FIELDS = ['id','chapter','level','rank','difficulty','max_hp','damage','armor','magic_resist']
FREEZE = 'aca0c65e05481015029a17789905b1d66efbdd86'
@lru_cache(maxsize=None)
def frozen_text(path):
    return subprocess.check_output(["git", "show", f"{FREEZE}:{path}"], cwd=ROOT, text=True)
def sha(p): return hashlib.sha256(frozen_text(str(p.relative_to(ROOT))).encode()).hexdigest()
def read(p): return json.loads(frozen_text(p))
def constant(text,name):
    m=re.search(r'const '+name+r'\s*:?=\s*(\{.*?\}|\[.*?\]|[0-9.]+)',text,re.S)
    assert m,name
    return ast.literal_eval(m[1])
def I(x): return math.floor(x + .5)
def role(archetype,authored):
    if archetype in ('tank','support'): return archetype
    if archetype in ('caster','assassin'): return 'output'
    assert archetype=='skirmisher'
    return 'output' if authored in ('R','ranged','artillery') else 'skirmisher'
def info():
    entries=read('data/enemies.json')['enemies']; profiles=read('data/enemy_progression.json')['profiles']; result={}
    for id,e in entries.items():
        raw=dict(profiles[id]['base_stats']);raw['magic_resist']=e.get('magic_resist',0)
        result[id]=(e['name'],int(e['biome_id'][1:]),raw,e['archetype'],e['role'])
    for b in (5,6):
        for id,e in read(f'data/b{b:02d}_content.json')['enemies'].items():
            result[id]=(e['name'],b,e['raw_stats'],{'F':'skirmisher','R':'skirmisher','C':'caster','S':'support','A':'assassin','T':'tank'}[e['profile']],e['profile'])
    return result

def verify(rows,meta):
    g=frozen_text(SOURCES[0]);p=frozen_text(SOURCES[1]);b=frozen_text(SOURCES[2])
    roles=constant(g,'ROLES');spec=constant(p,'SPECIALIZATION');hd=constant(g,'HP_D');ad=constant(g,'ATTACK_D')
    c={key:constant(g,key) for key in ['HP_PER_LEVEL','ATTACK_PER_LEVEL','HP_PER_CHAPTER','ATTACK_PER_CHAPTER','DEFENSE_PER_LEVEL','DEFENSE_PER_CHAPTER','DEFENSE_PER_DIFFICULTY']}
    def boss(ch,d):
        vals=[constant(b,k) for k in ['V1_HP','V1_ATTACK','V1_ARMOR','V1_MR']]
        def v1(n,t):
            j=n-1
            return [I(vals[0][j]*1.35*10*(1+.12*j)*hd[t]),I(vals[1][j]*1.35*10*(1+.08*j)*ad[t]),(vals[2][j]+(3 if n<=4 else 2)*t)*10,(vals[3][j]+(3 if n<=4 else 2)*t)*10]
        baseline=v1(1,0)
        for n in range(2,ch+1):
            old=v1(n,0);baseline=[max(old[0],I(baseline[0]*1.15)),max(old[1],I(baseline[1]*1.08)),max(old[2],baseline[2]+20),max(old[3],baseline[3]+20)]
        old=v1(ch,d)
        return [max(old[0],I(baseline[0]*hd[d])),max(old[1],I(baseline[1]*ad[d])),max(old[2],baseline[2]+30*d),max(old[3],baseline[3]+30*d)]
    expected={(id,5*(e[1]-1)+z,rank,d) for id,e in meta.items() for z in (1,3,5) for rank in ('normal','elite') for d in range(5)}
    expected|={(f'BO{ch:02d}',5*ch,'boss',d) for ch in range(1,7) for d in range(5)}
    keys=[(r['id'],r['level'],r['rank'],r['difficulty']) for r in rows]
    assert len(keys)==len(set(keys))==2730 and set(keys)==expected,'Incomplete or duplicated resolver grid'
    for r in rows:
        L,B,D=r['level'],r['chapter'],r['difficulty']
        if r['rank']=='boss': values=boss(B,D)
        else:
            name,ch,raw,archetype,authored=meta[r['id']];assert ch==B
            a=roles[archetype];s=spec[role(archetype,authored)];elite=r['rank']=='elite';t=4 if L>=15 else 3 if L>=10 else 2 if L>=5 else 1
            growth=c['DEFENSE_PER_LEVEL']*(L-1)+c['DEFENSE_PER_CHAPTER']*(B-1)+c['DEFENSE_PER_DIFFICULTY']*D
            values=[raw['max_hp']*a[0]*(1+c['HP_PER_LEVEL']*(L-1))*(1.2 if elite else 1)*1.35*10*(1+c['HP_PER_CHAPTER']*(B-1))*hd[D],min(16.9,max(a[2],raw['damage']*a[1]))*(1+c['ATTACK_PER_LEVEL']*(L-1))*(1.12 if elite else 1)*1.35*10*(1+c['ATTACK_PER_CHAPTER']*(B-1))*ad[D],(min(24,raw['armor']*a[3]+a[4]+(t-1)*a[5])+growth)*10,(min(32,raw['magic_resist']+(t-1)*a[6]+(4 if elite else 0))+growth)*10]
            values=[I(v*1.5*s[i]/100) for i,v in enumerate(values)]
        actual=[r[k] for k in FIELDS[5:]]
        assert values==actual,(r,values)

def replace_block(path,tag,body,before=None):
    start=f'<!-- {tag}_START -->';end=f'<!-- {tag}_END -->';s=path.read_text();block=start+'\n'+body.rstrip()+'\n'+end
    if start in s:
        a=s.index(start);b=s.index(end,a)+len(end);new=s[:a]+block+s[b:]
    else:
        a=s.index(before) if before else s.index('\n')+1;new=s[:a]+'\n'+block+'\n\n'+s[a:]
    return new

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--input',type=Path);ap.add_argument('--check',action='store_true');args=ap.parse_args()
    csvpath=OUT/'ARCHIVE14_B01_B06.csv';manifestpath=OUT/'ARCHIVE14_MANIFEST.json'
    if args.input: rows=json.loads(args.input.read_text())
    else:
        with csvpath.open() as f: rows=[{k:int(v) if k not in ('id','rank') else v for k,v in r.items()} for r in csv.DictReader(f)]
    rows=sorted(rows,key=lambda r:(r['chapter'],r['id'],r['level'],r['rank'],r['difficulty']))
    meta=info();verify(rows,meta)
    buf=io.StringIO();w=csv.DictWriter(buf,fieldnames=FIELDS,lineterminator='\n');w.writeheader();w.writerows([{k:r[k] for k in FIELDS} for r in rows]);data=buf.getvalue()
    manifest={'archive':14,'enemy_growth_version':3,'boss_progression_version':2,'source_commit':FREEZE,'row_count':2730,'ordinary_elite_rows':2700,'boss_rows':30,'source_sha256':{p:sha(ROOT/p) for p in SOURCES},'csv_sha256':hashlib.sha256(data.encode()).hexdigest(),'verification':'29316 checks, 0 failures: resolver, ordinary/elite live actor fields, JSON reconstruction, monotonicity and unchanged independent Boss v2. Not a natural combat acceptance.'}
    generated={csvpath:data,manifestpath:json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',OUT/'.gdignore':''}
    lookup={(r['id'],r['level'],r['rank'],r['difficulty']):r for r in rows}
    def values(id,L,rank,d): return ' / '.join(str(lookup[id,L,rank,d][k]) for k in FIELDS[5:])
    for ch,filename in enumerate(DOCS,1):
        L=ch*5;ids=sorted(id for id,e in meta.items() if e[1]==ch);path=ROOT/'docs/levels'/filename
        title='## archive14候选基线与完整roster' if ch<5 else '### 3.2 archive14候选基线与完整roster'
        lines=[title,'','最新用户目标已改为base1.0与按定位增强；下表保留已核验archive14历史候选，archive15隔离候选的逐种值及AP/暴击见本文新版段，不相互叠乘。','',f'archive14 / 普通精英v3；B{ch:02d}固定前/中/后区Lv{L-4}/{L-2}/{L}，不随玩家追平。'+('默认已发布章节。' if ch<5 else '同树隔离候选，默认未发布。'),'',f'本章{len(ids)}种普通怪，精英是同ID的rank而非新增物种；下表统一取章末Lv{L}，数值顺序均为 **HP / 攻击A / 护甲 / 魔抗**。D0与D4只是展示端点，全部三区、普通/精英与D0–D4实际resolver结果见[完整CSV](../balance/resolver_tables/ARCHIVE14_B01_B06.csv)。解析可用不代表全部rank在每个自然房间同时生成。','', '计算与取整唯一口径见[数值总案第9节](../balance/LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md#9-野怪首领与难度标尺)：HP/攻击每级5.5%/2.5%、每章12%/8%；双防额外0.5(L−1)+(B−1)+2D在基础帽后，×10×1.5×单一专项后最终取整。基础1.5、专项与双防增量是实现选项，并非用户指定比例。原始技能表继续有效；A不是最终技能扣血。','', '| ID / 当前名称 | 原型→专项 | 普通D0 | 精英D0 | 普通D4 | 精英D4 |','|---|---|---|---|---|---|']
        for id in ids:
            name,_,raw,a,authored=meta[id]
            lines.append(f'| {id} {name} | {authored} / {a}→{role(a,authored)} | '+ ' | '.join(values(id,L,rank,d) for rank,d in [('normal',0),('elite',0),('normal',4),('elite',4)])+' |')
        lines+=['','本轮有真实resolver与普通/精英演员属性接线检查；没有据此宣称三职业自然战斗、装备或连续整关已验收。裸装目标是正常连续整关不能通，不要求秒死或首房必死。旧archive0–13快照继续原规则，不按此表重算。']
        before='## 4. Boss' if ch>=5 else None
        new=replace_block(path,'ARCHIVE14_ROSTER','\n'.join(lines),before)
        # Render the Boss block using the intermediate text without filesystem side effects.
        start='<!-- ARCHIVE14_BOSS_START -->';end='<!-- ARCHIVE14_BOSS_END -->'
        bosslines=['### 当前Boss独立v2数值','',f'BO{ch:02d} 固定Lv{L}；不套普通/精英1.5、定位专项或等级成长。每行仍为HP/攻击/护甲/魔抗；递推及D0取整边界见总案第9.2节。','', '| 难度 | HP / A / 护甲 / 魔抗 |','|---|---|']+[f'| D{d} | {values(f"BO{ch:02d}",L,"boss",d)} |' for d in range(5)]+['','Boss三职业60–90秒目标仍未验收；此表仅核对共享resolver，旧预合并诊断不算本轮通过。']
        block=start+'\n'+'\n'.join(bosslines)+'\n'+end
        if start in new:
            a=new.index(start);b=new.index(end,a)+len(end);new=new[:a]+block+new[b:]
        else:
            headings=list(re.finditer(r'^## .*?(?:Boss|首领|虫后|BO03).*$',new,re.M));assert headings,filename
            a=new.index('\n',headings[0].start())+1;new=new[:a]+'\n'+block+'\n\n'+new[a:]
        generated[path]=new
    path=ROOT/'docs/balance/LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md'
    evidence=f'''冻结源码提交 `{FREEZE}`；共享成长源码SHA-256 `{manifest['source_sha256'][SOURCES[0]]}`。完整源指纹与CSV指纹见[机器校验清单](resolver_tables/ARCHIVE14_MANIFEST.json)。

真实Godot resolver导出共2730行（90个普通怪身份×三区×两rank×五D=2700，六Boss×五D=30）；每章对应原正文同步展示全roster的D0/D4与Boss五D，[完整CSV](resolver_tables/ARCHIVE14_B01_B06.csv)保留全部中间等级/难度。定向29316项0失败含普通/精英真实演员四属性接线、JSON重建与单调性，Boss独立v2保持；不含完整三职业自然战斗验收。

复核：`python tools/balance/sync_level_numerical_docs.py --check`。此归档校验从上述冻结Git提交读取源码，后续新版代码不改写archive14；不是当前新版运行状态检查。从 `tests/test_shared_enemy_growth.gd` 的受控输出重新导入用 `--input <受控输出JSON>`；脚本逐字段复算2730行、检查完整roster笛卡尔积和来源哈希，更新原正文。不能用手工改表替代resolver导出。'''
    generated[path]=replace_block(path,'SHARED_MODEL_EVIDENCE',evidence)
    for path,body in generated.items():
        if args.check: assert path.exists() and path.read_text()==body,f'Stale document/data: {path.relative_to(ROOT)}'
        else: path.parent.mkdir(parents=True,exist_ok=True);path.write_text(body)
    print('Verified 2730 resolver rows, source hashes, and six original chapter documents.' if args.check else 'Synchronized 2730 verified resolver rows into six original chapter documents.')
if __name__=='__main__': main()
