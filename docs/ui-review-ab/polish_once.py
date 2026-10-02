"""One-time source correction for the static UI review; no runtime files changed."""
from pathlib import Path
import ast, json
root=Path(__file__).resolve().parents[2]
p=root/'docs/ui-review-ab/source/render.py'
s=p.read_text(encoding='utf-8')
s=s.replace("def font(size): return ImageFont.truetype(str(FONT), size)","""def font(size):
    f = ImageFont.truetype(str(FONT), size)
    try:
        axes = f.get_variation_axes()
        weights = [(600 if size >= 28 else 480) if b'Weight' in a['name'] else a['default'] for a in axes]
        f.set_variation_by_axes(weights)
    except (AttributeError, OSError):
        pass
    return f""")
insert="""
# Bind rendered labels to the actual cropped illustration and equipment slot.
GEAR_META = {}; SLOT_ART = {}
for filename in ['storybook_equipment_v2.manifest.json','storybook_shop_sets_v2.manifest.json']:
    mp = ROOT/'assets/generated/equipment'/filename
    if mp.exists():
        md = read(mp); GEAR_META.update(md.get('items',{})); SLOT_ART.update(md.get('slot_fallbacks',{}))
old_gear = list(EQUIPMENT); ordered = []; chosen = set()
for slot, fallback_name in [('weapon','武器'),('head','头部'),('chest','胸甲'),('hands','手套'),('legs','腿部'),('feet','鞋靴'),('ring','戒指'),('charm','饰品')]:
    matches = [(key,im) for key,im in old_gear if GEAR_META.get(key,{}).get('slot') == slot]
    matches.sort(key=lambda pair: (GEAR_META[pair[0]].get('race_id') != 'B01', pair[0]))
    if matches:
        ordered.append(matches[0]); chosen.add(matches[0][0])
    elif slot in SLOT_ART:
        key='slot:'+slot; ordered.append((key,crop_entry(SLOT_ART[slot]))); GEAR_META[key]={'name':fallback_name,'slot':slot}
    else:
        raise RuntimeError('No verified equipment-slot art: '+slot)
EQUIPMENT = ordered + [pair for pair in old_gear if pair[0] not in chosen]
GEAR_NAMES = [GEAR_META.get(key,{}).get('name',key) for key,im in EQUIPMENT]
PRIMARY_NAME = GEAR_NAMES[0]
weapon_options=[pair for pair in old_gear if GEAR_META.get(pair[0],{}).get('slot') == 'weapon']
COMPARE_GEAR = [weapon_options[0][1],weapon_options[1][1]]
COMPARE_NAMES = [GEAR_META[pair[0]].get('name',pair[0]) for pair in weapon_options[:2]]
"""
if '# Bind rendered labels' not in s: s=s.replace('HEROES = []',insert+'\nHEROES = []',1)
s=s.replace("ITEM_NAMES = ['守庭战斧','日曜头冠','巡庭胸甲','黄铜护手','巡卫长裤','遗庭战靴','日轮戒指','构装护符']","ITEM_NAMES = GEAR_NAMES[:8]")
s=s.replace('ITEM_NAMES[idx%8]','GEAR_NAMES[idx%len(GEAR_NAMES)]')
s=s.replace('else ITEM_NAMES[j%8]','else GEAR_NAMES[(j*8)%len(GEAR_NAMES)]')
s=s.replace("'守庭战斧 +3'", "PRIMARY_NAME+' +3'")
s=s.replace("['巡卫战斧 +2',PRIMARY_NAME+' +3'][j]", "COMPARE_NAMES[j]+(' +2' if j==0 else ' +3')")
s=s.replace("EQUIPMENT[j*2][1]", "COMPARE_GEAR[0] if reforge else COMPARE_GEAR[j]")
s=s.replace('守庭战斧','晴辉构装旅者核心')
s=s.replace('c.portrait(x,229,586,652,j)','c.portrait(x,229,586,620,j)')
s=s.replace('c.text(x+35,795,','c.text(x+35,858,')
body="""
# Use a complete approved gameplay body, never a portrait bust on the arena floor.
WORLD_HERO = None
family_path = ROOT/'assets/generated/heroes/CH01_storybook_family_v1.json'
if family_path.exists():
    family = read(family_path)
    if family.get('enabled'):
        action_path = family.get('assets',{}).get('actions',{}).get('front')
        if action_path:
            action = read(ROOT/action_path.replace('res://',''))
            frames = action.get('frames',[])
            frame = next((f for f in frames if f.get('name') == 'idle'),frames[0] if frames else {})
            if frame.get('region'): WORLD_HERO = crop_entry(frame,action.get('texture'))
if WORLD_HERO is None: WORLD_HERO = opened('assets/characters/salvager.png')
ENEMY_ART = {}
for mp in sorted((ROOT/'assets/generated').rglob('*.regions.json')):
    if 'storybook' not in mp.name or not ('bodies' in mp.name or 'boss' in mp.name): continue
    md=read(mp)
    for identity,entry in md.get('entries',md.get('regions',{})).items():
        if identity.startswith(('M','BO')):
            try: ENEMY_ART[identity]=crop_entry(entry,md.get('texture'))
            except (OSError,ValueError,TypeError): pass
"""
if '# Use a complete approved' not in s: s=s.replace('def world(i=0):',body+'\ndef world(i=0):',1)
s=s.replace("    opts = sorted((ROOT/'assets/generated').rglob(stem+'*storybook*.png'))", "    if stem in ENEMY_ART: return ENEMY_ART[stem]\n    opts = sorted((ROOT/'assets/generated').rglob(stem+'*storybook*.png'))")
s=s.replace('c.art(HEROES[0],789,429,156,244)','c.art(WORLD_HERO,789,429,156,244)')
s=s.replace('c.art(enemy(j),x+30,y+14,283,190)','c.art(enemy([0,1,9,10,18,19,27,28][j]),x+30,y+14,283,190)')
# The fixed source now directly reproduces the correction, without this script.
ast.parse(s)
p.write_text(s,encoding='utf-8')
sp=p.with_name('screens.json'); screens=json.loads(sp.read_text(encoding='utf-8'))
for row in screens:
    if row[3]=='skill':
        names=[['破阵冲锋','裂地重斩','铁壁战吼','天崩斧落'],['游击撤射','磁轨贯穿','震爆榴弹','火力倾泻'],['奥术晶爆','星界法晶','冰霜新星','星陨领域']]
        row[1]=names[row[5]//4][row[5]%4]; row[4]='QWER'[row[5]%4]+' · 技能详情'
sp.write_text(json.dumps(screens,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Source corrections applied and Python syntax checked.')
