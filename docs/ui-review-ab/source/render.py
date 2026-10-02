#!/usr/bin/env python3
"""Deterministic review compositions, NOT runtime screenshots or balance data.
Uses the repository's existing illustrated assets without modifying them.
Run from any working directory: python docs/ui-review-ab/source/render.py
"""
from __future__ import annotations
import functools, hashlib, json, math, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/ui-review-ab'
W, H = 1920, 1080
INK = '#392843'; MUTED = '#817263'; PAPER = '#fff5de'; GOLD = '#b39059'
TEAL = '#297f80'; RED = '#b76c59'; GREEN = '#648361'; PURPLE = '#8975a5'
USED = set(); WARNINGS = []
FONT = ROOT / 'assets/fonts/NotoSansSC.ttf'
if not FONT.exists():
    FONT = Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
@functools.lru_cache(maxsize=64)
def font(size):
    f = ImageFont.truetype(str(FONT), size)
    try:
        axes = f.get_variation_axes()
        weights = [(600 if size >= 28 else 480) if b'Weight' in a['name'] else a['default'] for a in axes]
        f.set_variation_by_axes(weights)
    except (AttributeError, OSError):
        pass
    return f
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def rgb(s): return tuple(int(s[i:i+2], 16) for i in (1,3,5))
@functools.lru_cache(maxsize=128)
def opened(path):
    p = ROOT / str(path).replace('res://','')
    USED.add(str(p.relative_to(ROOT)))
    return Image.open(p).convert('RGBA')
def crop_entry(entry, texture=None):
    if isinstance(entry, list): rect = entry; path = texture
    else: rect = entry.get('region'); path = entry.get('texture', texture)
    if not path: return None
    image = opened(path)
    if rect and len(rect) == 4:
        x,y,w,h = [int(v) for v in rect]
        image = image.crop((x,y,x+w,y+h))
    return image
ICONS = {}; EQUIPMENT = []
for p in sorted((ROOT/'assets/generated/ui').glob('storybook_*v2.regions.json')):
    data = read(p)
    for key, entry in data.get('regions',{}).items():
        try: ICONS[key] = crop_entry(entry,data.get('texture'))
        except (OSError, ValueError, TypeError) as exc: WARNINGS.append(f'{p.name}:{key}: {exc}')
for name in ['storybook_equipment_v2.manifest.json','storybook_shop_sets_v2.manifest.json']:
    p = ROOT/'assets/generated/equipment'/name
    if p.exists():
        for key, entry in sorted(read(p).get('items',{}).items()):
            try:
                image = crop_entry(entry)
                if image: EQUIPMENT.append((key,image))
            except (OSError,ValueError,TypeError) as exc: WARNINGS.append(f'{key}: {exc}')

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

HEROES = []
for i in range(1,4):
    options = [f'assets/generated/heroes/CH0{i}_storybook_portrait_v1.png',f'assets/generated/heroes/CH0{i}_portrait_v1.png']
    found = next((p for p in options if (ROOT/p).exists()),None)
    if not found: raise RuntimeError(f'Missing approved portrait CH0{i}')
    HEROES.append(opened(found))
WORLD_PATHS = sorted((ROOT/'assets/generated/world/rooms').rglob('*.png'))
if not WORLD_PATHS: WORLD_PATHS = sorted((ROOT/'assets/generated/world').glob('*.png'))
if not EQUIPMENT: raise RuntimeError('No illustrated equipment assets found')
NAMES = ['罗砧','岑线','谷频']; ROLES = ['战士','枪手','法师']; ACCENTS = [RED,TEAL,PURPLE]
SKILLS = [['破阵冲锋','裂地重斩','铁壁战吼','天崩斧落'],['游击撤射','磁轨贯穿','震爆榴弹','火力倾泻'],['奥术晶爆','星界法晶','冰霜新星','星陨领域']]
SKILL_COPY = [
'向目标方向突进，命中后击退小型敌人并积累破势。',
'挥出正面扇形重斩，消耗破势获得更强的范围与冲击。',
'战吼震退近敌，获得短时护盾和减伤；不会恢复生命。',
'跃向合法落点，以重斧砸出大范围地裂，消耗破势强化爆发。',
'转移位置后连续射击。已发出的子弹不因动作取消而消失。',
'短暂稳枪后发射贯穿弹，可穿透第一名敌人。',
'向合法落点投掷定时榴弹，爆炸命中后建立猎印。',
'连续倾泻火力，攻击期间可缓慢移动并调整朝向。',
'发射奥术晶体，在碰撞或终点爆炸；经过法晶时为其充能。',
'部署星界法晶，自动攻击附近敌人；晶格显示当前充能。',
'释放近身寒冷新星，并引爆视线内已展开的法晶。',
'在目标区域展开持续领域，脉冲施加寒冷并为范围内法晶充能。']
SLOT_NAMES = ['武器','头部','胸甲','手套','腿部','鞋靴','戒指','饰品']
ITEM_NAMES = GEAR_NAMES[:8]
RARITIES = [('白色','#b7afa0'),('绿色',GREEN),('紫色',PURPLE),('金色',GOLD)]


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

def world(i=0):
    # Pick actual chapter entry rooms, not arbitrary alphabetical atlas offsets.
    room = {0:'L01',7:'L07',14:'L13',21:'L19',100:'BO01'}.get(i,'L01')
    exact = ROOT / ('assets/generated/world/rooms/'+room+'_environment_v1.png')
    if exact.exists(): return opened(str(exact.relative_to(ROOT)))
    if not WORLD_PATHS: return Image.new('RGBA',(W,H),'#d9d6b3')
    return opened(str(WORLD_PATHS[i % len(WORLD_PATHS)].relative_to(ROOT)))
def enemy(i=0,boss=False):
    stem = f'BO{i+1:02d}' if boss else f'M{i+1:02d}'
    if stem in ENEMY_ART: return ENEMY_ART[stem]
    opts = sorted((ROOT/'assets/generated').rglob(stem+'*storybook*.png'))
    opts += sorted((ROOT/'assets/generated').rglob(stem+'_v1.png'))
    if boss and (ROOT/f'assets/bosses/{stem}.png').exists(): opts += [ROOT/f'assets/bosses/{stem}.png']
    return opened(str(opts[0].relative_to(ROOT))) if opts else ICONS.get('crystal',HEROES[0])

class Canvas:
    def __init__(self, screen, scenic=False):
        self.screen = screen; self.image = Image.new('RGBA',(W,H),'#e7dcc0')
        bg = ImageOps.fit(world(0).convert('RGB'),(W,H),method=Image.Resampling.LANCZOS).convert('RGBA')
        if not scenic: bg = bg.filter(ImageFilter.GaussianBlur(7))
        self.image.alpha_composite(bg)
        self.image.alpha_composite(Image.new('RGBA',(W,H),(247,236,208,222 if not scenic else 65)))
        self.d = ImageDraw.Draw(self.image)
    def text(self,x,y,s,size=24,color=INK,width=None,lines=6,align='left'):
        s = str(s); f=font(size); result=[]
        for para in s.split('\n'):
            if not width: result.append(para); continue
            buf=''
            for ch in para:
                if self.d.textlength(buf+ch,font=f)>width and buf: result.append(buf); buf=ch
                else: buf+=ch
            result.append(buf)
        if len(result)>lines:
            result=result[:lines]; result[-1]=result[-1][:-1]+'…'
        for j,line in enumerate(result):
            xx=x if align=='left' else x-(self.d.textlength(line,font=f)/2 if align=='center' else self.d.textlength(line,font=f))
            self.d.text((round(xx),round(y+j*size*1.55)),line,font=f,fill=color,stroke_width=0)
        return y+len(result)*size*1.55
    def line(self,xy,fill=GOLD,width=2): self.d.line(xy,fill=fill,width=width)
    def panel(self,x,y,w,h,fill=PAPER,edge=GOLD,r=18,shadow=True):
        if shadow:
            layer=Image.new('RGBA',(W,H)); dr=ImageDraw.Draw(layer)
            dr.rounded_rectangle((x,y+6,x+w,y+h+8),r,fill=(68,46,35,38))
            self.image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(8)))
            self.d=ImageDraw.Draw(self.image)
        self.d.rounded_rectangle((x,y,x+w,y+h),r,fill=fill,outline=edge,width=2)
        self.d.rounded_rectangle((x+6,y+6,x+w-6,y+h-6),max(4,r-4),outline='#e3d2af',width=1)
        for xx,yy in [(x+15,y+15),(x+w-15,y+15),(x+15,y+h-15),(x+w-15,y+h-15)]:
            self.d.ellipse((xx-2,yy-2,xx+2,yy+2),fill=edge)
    def art(self,img,x,y,w,h,trim=True):
        if img is None: return
        if trim:
            b=img.getchannel('A').getbbox()
            if b: img=img.crop(b)
        img=ImageOps.contain(img,(max(1,int(w)),max(1,int(h))),Image.Resampling.LANCZOS)
        self.image.alpha_composite(img,(int(x+(w-img.width)/2),int(y+(h-img.height)/2)))
        self.d=ImageDraw.Draw(self.image)
    def scene(self,img,x,y,w,h):
        im=ImageOps.fit(img,(int(w),int(h)),method=Image.Resampling.LANCZOS)
        mask=Image.new('L',(int(w),int(h)),0); ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1),16,fill=255)
        self.image.paste(im,(int(x),int(y)),mask); self.d=ImageDraw.Draw(self.image)
    def icon(self,key,x,y,size=60): self.art(ICONS.get(key,ICONS.get('compass')),x,y,size,size)
    def button(self,x,y,w,label,primary=False,danger=False,disabled=False,h=58):
        col = '#ddd5c2' if disabled else (RED if danger else (TEAL if primary else '#f5e7c9'))
        self.panel(x,y,w,h,fill=col,edge='#b5a98a' if disabled else (col if primary or danger else GOLD),r=12,shadow=False)
        self.text(x+w/2,y+12,label,23,'#fff9e8' if primary or danger else (MUTED if disabled else INK),width=w-32,lines=1,align='center')
    def chip(self,x,y,label,color=TEAL,w=126):
        self.d.rounded_rectangle((x,y,x+w,y+34),9,fill=color)
        self.text(x+w/2,y+3,label,17,'#fff9e8',align='center')
    def bar(self,x,y,w,p,color=TEAL,h=13):
        self.d.rounded_rectangle((x,y,x+w,y+h),h//2,fill='#d8cdb6')
        self.d.rounded_rectangle((x,y,x+max(h,w*p),y+h),h//2,fill=color)
    def heading(self,x,y,title,caption=''):
        self.text(x,y,title,30); self.line((x,y+53,x+440,y+53),'#d8c7a2',1)
        if caption: self.text(x,y+65,caption,20,MUTED,width=500,lines=2)
    def rows(self,x,y,w,rows,gap=61):
        for k,(label,value) in enumerate(rows):
            yy=y+k*gap; self.text(x,yy,label,22,MUTED,width=w*.56,lines=1)
            self.text(x+w,yy,value,25,INK,align='right'); self.line((x,yy+44,x+w,yy+44),'#e0d2b7',1)
    def shell(self,active=None):
        _,title,group,_,state,_=self.screen
        self.panel(30,24,1860,89,fill='#fff6df',r=16)
        self.icon('compass',52,37,58); self.text(125,29,'深渊拾荒者',31); self.text(128,74,'ABYSS SALVAGER  /  ADVENTURE LEDGER',12,MUTED)
        self.text(677,42,title,36); self.icon('coin',1470,39,47); self.text(1530,44,'12,680',30)
        self.button(1702,40,157,'返回营地',h=54)
        nav=['英雄','技能','背包','商城','锻造','图鉴','档案']
        keys=['hero','skills','equipment','shop','axe_slash','crystal','compass']
        for j,name in enumerate(nav):
            x=30+j*232; selected=name==(active or group)
            self.panel(x,131,218,69,fill=TEAL if selected else '#f6ebd2',edge=TEAL if selected else '#c7b38c',r=12,shadow=False)
            self.icon(keys[j],x+13,141,44); self.text(x+73,147,name,26,'#fff9e8' if selected else INK)
        self.button(1668,135,222,'设置与操作',h=61)
        self.text(42,1028,'Esc  返回    ·    鼠标选择    ·    Enter  确认',18,MUTED)
        self.text(1878,1031,self.screen[0]+'  /  UI概念稿 · 示意数据',14,MUTED,align='right')
    def footer(self):
        self.text(1876,1044,self.screen[0]+'  /  UI概念稿 · 示意数据',14,'#554b46',align='right')
    def item(self,x,y,idx=0,selected=False,w=139,h=149,label=True):
        rarity,color=RARITIES[2 if idx==0 else (idx+1)%4]
        self.panel(x,y,w,h,fill='#fcf2dc',edge=TEAL if selected else '#c7b690',r=10,shadow=False)
        if selected: self.d.rounded_rectangle((x+3,y+3,x+w-3,y+h-3),8,outline=TEAL,width=3)
        self.art(EQUIPMENT[idx%len(EQUIPMENT)][1],x+11,y+9,w-22,h-43)
        self.d.rectangle((x+9,y+h-31,x+13,y+h-13),fill=color)
        if label: self.text(x+20,y+h-33,GEAR_NAMES[idx%len(GEAR_NAMES)],17,INK,width=w-25,lines=1)
        self.text(x+w-13,y+8,'+'+str(3 if idx==0 else idx%5),16,INK,align='right')
    def portrait(self,x,y,w,h,who=0):
        self.panel(x,y,w,h,fill='#f7ebd0')
        cx=x+w/2; cy=y+h*.46
        self.d.ellipse((cx-w*.36,cy-w*.36,cx+w*.36,cy+w*.36),fill='#e6ddbf',outline='#c5b080',width=2)
        self.d.ellipse((cx-w*.31,cy-w*.31,cx+w*.31,cy+w*.31),outline='#fdf8e9',width=3)
        self.art(HEROES[who%3],x+25,y+38,w-50,h-130)
        self.text(cx,y+h-89,NAMES[who%3]+' · '+ROLES[who%3],30,align='center')
        self.text(cx,y+h-43,'Lv.12  /  永久英雄',18,MUTED,align='center')

def roster(c,trial=False):
    c.shell('英雄')
    for j in range(3):
        x=40+j*626; c.portrait(x,229,586,620,j)
        c.chip(x+22,247,'0'+str(j+1)+' / '+ROLES[j],ACCENTS[j],155)
        c.text(x+35,858,['承伤蓄势，近战破阵','标记弱点，游击收割','布置法晶，共鸣引爆'][j],22,MUTED,width=510)
        c.button(x+26,906,535,'进入独立试玩' if trial else ('当前出战' if j==0 else '查看英雄'),primary=j==0)

def hero(c,who=0):
    c.shell('英雄'); c.panel(36,225,266,763)
    for j in range(3):
        c.panel(55,254+j*209,228,186,fill='#e6eee0' if j==who else '#f8edd6',edge=TEAL if j==who else GOLD,shadow=False)
        c.art(HEROES[j],67,265+j*209,89,133); c.text(174,279+j*209,NAMES[j],26); c.text(174,322+j*209,ROLES[j],20,MUTED)
        c.text(75,404+j*209,'已解锁  /  Lv.12',17,TEAL)
    c.portrait(323,225,659,763,who)
    c.panel(1005,225,878,763); c.heading(1038,255,'战斗档案','熟悉你的英雄，找到自己的战斗节奏。')
    c.chip(1666,257,ROLES[who],ACCENTS[who],168)
    c.text(1040,379,['前排破阵者','机动神射手','星界布阵者'][who],36)
    c.text(1040,443,['三次有效普攻积累护盾。以冲锋接敌，重斩消耗破势。','连续命中同一目标揭示弱点。用转位拉开距离并消耗猎印。','普攻与技能交替积累共鸣。布点、充能、引爆构成完整循环。'][who],24,MUTED,width=783,lines=3)
    c.rows(1040,581,787,[('生命上限','2,480'),('攻击 / 法术强度','326 / 148'),('防御 / 魔抗','182 / 126')])
    for j,key in enumerate(['axe_slash','rifle','crystal','dodge']): c.icon(key,1060+j*175,789,75)
    c.button(1040,906,380,'查看技能'); c.button(1450,906,390,'设为出战英雄',True)

def stats(c):
    c.shell('英雄'); c.portrait(37,224,480,766)
    c.panel(541,224,1345,766); c.heading(575,254,'属性来源明细','最终属性由基础成长、装备与效果共同构成。')
    c.text(1143,272,'基础',21,MUTED); c.text(1390,272,'装备',21,MUTED); c.text(1668,272,'最终',21,TEAL)
    rows=[('生命上限','1,800','+680','2,480'),('物理攻击','216','+110','326'),('法术强度','84','+64','148'),('物理防御','120','+62','182'),('魔法抗性','90','+36','126'),('暴击率','5%','+13%','18%'),('暴击伤害','150%','+28%','178%'),('移动速度','100%','+8%','108%')]
    for j,row in enumerate(rows):
        y=388+j*63
        for x,val,col in zip([578,1170,1418,1720],row,[INK,MUTED,MUTED,TEAL]): c.text(x,y,val,24,col)
        c.line((578,y+46,1828,y+46),'#e3d4b7',1)
    c.button(1540,913,288,'返回装备背包',True)

def skills(c,who=0):
    c.shell('技能'); c.portrait(37,223,408,766,who%3)
    for j in range(4):
        x=471+(j%2)*714; y=224+(j//2)*388
        c.panel(x,y,694,370); c.icon(['axe_slash','skills','crystal','dodge'][j],x+29,y+28,103)
        label=SKILLS[who%3][j] if who<3 else ['普通攻击','职业被动','闪避','交互'][j]
        c.text(x+153,y+34,label,32); c.chip(x+547,y+31,'QWER'[j],ACCENTS[who%3],106)
        c.text(x+154,y+89,'已解锁  /  成长节点 Lv.'+str(10+j*2),19,TEAL)
        desc=SKILL_COPY[(who%3)*4+j] if who<3 else ['鼠标左键 / A。仅有效命中产生连击。','根据职业条件自动触发，无需额外按键。','空格。按移动方向进行短距离闪避。','F。与出口、战利品和场景目标交互。'][j]
        c.text(x+30,y+163,desc,24,MUTED,width=627,lines=3)
        c.button(x+31,y+291,627,'查看详情',primary=j==0)

def skill(c,num):
    who=num//4; slot=num%4; c.screen[1]=SKILLS[who][slot]; c.shell('技能')
    c.panel(37,224,579,765); c.chip(68,254,'QWER'[slot]+' / '+ROLES[who],ACCENTS[who],168)
    c.d.ellipse((121,381,535,795),fill='#e6dec6',outline=GOLD,width=3)
    c.icon(['axe_slash','rifle','crystal'][who],178,425,300)
    c.text(324,833,SKILLS[who][slot],39,align='center'); c.text(324,900,'技能效果示意',19,MUTED,align='center')
    c.panel(639,224,1248,765); c.heading(675,254,'技能说明','技能表现与交互信息统一在一个详情面板中。')
    c.text(675,390,SKILL_COPY[num],28,width=1120,lines=3)
    cooldown=[6,4,11,42,7,3.5,12,40,5,3.5,11,48][num]
    c.rows(677,540,1118,[('默认快捷键','QWER'[slot]),('基础冷却',str(cooldown)+' 秒'),('解锁等级','Lv.'+str(slot+1)),('成长节点','Lv.'+str(10+slot*2))],gap=61)
    c.text(679,815,'具体消耗与伤害显示角色当前规则下的实际数值。',20,MUTED,width=1120)
    c.button(680,905,525,'返回技能'); c.button(1245,905,552,'前往独立试玩',True)

def branches(c,trial=False):
    c.shell('技能'); c.panel(38,225,1848,764)
    c.heading(78,254,'选择你的战斗方式','试玩选择不会解锁或修改正式档案。' if trial else '分支在对应等级开放；确认前可查看技能差异。')
    for row in range(2):
        y=395+row*268; c.chip(79,y-10,'Q · Lv.18' if row==0 else 'R · Lv.20',TEAL,170)
        for col in range(2):
            x=279+col*776; c.panel(x,y-19,731,214,fill='#eaf0e1' if col==0 else '#f7ecd5',edge=TEAL if col==0 else GOLD,shadow=False)
            c.icon('axe_slash' if row==0 else 'crystal',x+22,y+9,105)
            c.text(x+148,y+6,('A · ' if col==0 else 'B · ')+(['突进强化','守点冲击'][col] if row==0 else ['集中爆发','广域控制'][col]),30)
            c.text(x+149,y+73,['扩大位移与覆盖，单次伤害降低。','牺牲机动能力，强化特定战斗收益。'][col],23,MUTED,width=526,lines=2)
            c.text(x+150,y+153,'已选择' if col==0 else '点击选择',18,TEAL)
    c.button(1240,906,604,'开始 Lv.20 独立试玩' if trial else '确认分支',True)

def inventory(c,state=0):
    c.shell('背包'); c.panel(36,225,502,765)
    c.text(65,254,'本局配装' if state>=2 else '当前配装',28); c.text(494,263,'8 / 8',21,TEAL,align='right')
    c.art(HEROES[0],141,345,300,462)
    for k in range(8):
        x=60 if k<4 else 411; y=325+(k%4)*141
        c.item(x,y,k,w=103,h=116,label=False); c.text(x+50,y+116,SLOT_NAMES[k],16,MUTED,align='center')
    c.text(76,895,'罗砧 · 战士  Lv.12',26); c.text(77,938,'生命 2,480     攻击 326',20,MUTED)
    c.panel(559,225,806,765); c.text(588,253,'待拾取战利品' if state==3 else ('本局背包' if state==2 else '装备仓库'),29)
    c.text(1326,259,'24 / 80',21,TEAL,align='right')
    for j,l in enumerate(['全部','武器','防具','饰品']): c.button(584+j*186,308,172,l,primary=j==0,h=49)
    c.panel(585,372,751,49,fill='#f2e8d2',shadow=False,r=8); c.text(606,382,'搜索装备名称…',20,MUTED); c.text(1311,382,'按获得时间 ↓',18,MUTED,align='right')
    for j in range(20):
        x=585+(j%5)*153; y=443+(j//5)*122
        c.item(x,y,j,selected=j==0,w=138,h=110)
        if state==1 and j in [1,3,4,7]: c.chip(x+90,y+5,'✓',TEAL,37)
    c.button(588,925,353,'全部拾取' if state==3 else ('已选 4 件' if state==1 else '多选回收'),primary=state in [1,3])
    c.button(962,925,363,'整理背包')
    c.panel(1387,225,498,765); c.heading(1418,253,PRIMARY_NAME+' +3')
    c.chip(1419,331,'紫色 · 武器',PURPLE,176); c.art(EQUIPMENT[0][1],1505,379,255,238)
    c.rows(1418,637,429,[('物理攻击','+110'),('暴击率','+8%'),('装备等级','iLv.12')],gap=55)
    c.text(1419,817,'日曜巡卫  3 / 8',21,TEAL)
    c.text(1419,862,'撤离后永久入库' if state>=2 else '永久装备 · 已锁定保护',19,MUTED)
    c.button(1418,923,428,'装备到当前槽位',True)

def equipment(c,mode=0):
    c.shell('商城' if mode else '背包'); c.panel(37,225,820,766)
    c.text(77,260,'日曜巡卫套装' if mode else PRIMARY_NAME+' +3',39); c.chip(78,330,'金色 · 套装' if mode else '紫色 · 武器',GOLD if mode else PURPLE,190)
    if mode:
        for j in range(8): c.item(82+(j%4)*183,408+(j//4)*199,j,w=160,h=176)
        c.text(92,841,'拥有进度  3 / 8',25,TEAL); c.bar(93,894,686,.375)
    else:
        c.art(EQUIPMENT[0][1],176,401,533,416); c.text(99,860,'独立实例 · iLv.12 · 物理型',23,MUTED)
        c.text(99,912,'来源：晴辉遗庭 / 首领与清房奖励',21,MUTED,width=690)
    c.panel(880,225,1005,766); c.heading(919,259,'套装效果' if mode else '属性与词条')
    c.rows(921,377,916,[('物理攻击','+110'),('生命上限','+260'),('暴击率','+8%'),('强化阶','+3')])
    c.text(921,648,'日曜巡卫',29,TEAL); c.text(921,704,'以黄铜护甲与日轮刻纹组成的构装主题套装。\n套装激活条件与效果在配装时清晰展示。',24,MUTED,width=888,lines=3)
    c.button(918,907,436,'返回商城' if mode else '装备比较'); c.button(1380,907,457,'补齐套装' if mode else '穿戴装备',True)

def compare(c,reforge=False):
    c.shell('锻造' if reforge else '背包')
    for j in range(2):
        x=39+j*934; c.panel(x,225,909,765,edge=TEAL if j else GOLD)
        c.chip(x+34,255,['原词条','新词条'][j] if reforge else ['当前穿戴','选中装备'][j],TEAL if j else MUTED,190)
        c.art(COMPARE_GEAR[0] if reforge else COMPARE_GEAR[j],x+321,314,264,231)
        c.text(x+455,568,COMPARE_NAMES[j]+(' +2' if j==0 else ' +3'),34,align='center')
        c.rows(x+42,649,823,[('物理攻击',['296','326  ↑ 30'][j]),('暴击率',['13%','18%  ↑ 5%'][j]),('生命上限',['2,520','2,480  ↓ 40'][j])],gap=68)
        c.button(x+43,905,821,(['保留原词条','采用新词条'][j] if reforge else ['保留当前装备','穿戴选中装备'][j]),primary=bool(j))

def shop(c,sets=False):
    c.shell('商城'); c.panel(37,225,291,765)
    c.text(67,259,'商品分类',29)
    for j,name in enumerate(['全部装备','武器','防具','戒指与饰品','套装目录','仅看可购买']): c.button(60,326+j*91,245,name,primary=j==(4 if sets else 0),h=64)
    c.panel(350,225,1535,765); c.text(385,254,'装备套装' if sets else '单件装备',31); c.text(1848,263,'14 套 / 124 模板',20,MUTED,align='right')
    c.text(387,315,'所有购买使用营地金币，不含付费货币。',20,MUTED)
    for j in range(6):
        x=380+(j%3)*498; y=379+(j//3)*270
        c.panel(x,y,471,244,fill='#f9efd9',shadow=False)
        c.art(EQUIPMENT[(j*8)%len(EQUIPMENT)][1],x+12,y+16,179,169)
        c.text(x+205,y+29,(['日曜巡卫','琥珀守卫','缝线旅者','赤岩斗士','铜羽猎手','星纹贤者'][j] if sets else GEAR_NAMES[(j*8)%len(GEAR_NAMES)]),26,width=243,lines=1)
        c.chip(x+207,y+87,'套装' if sets else RARITIES[j%4][0],RARITIES[j%4][1],120)
        c.text(x+208,y+148,('3 / 8 已拥有' if j==0 else '点击查看详情') if sets else 'iLv.12  /  物理型',18,MUTED)
        c.button(x+19,y+187,432,('补齐套装  2,160' if sets else '购买  480'),primary=j==0,h=46)

def forge(c,mode=0):
    c.shell('锻造'); c.panel(37,225,361,765); c.text(65,252,'选择装备实例',28)
    for j in range(5):
        y=318+j*119; c.panel(58,y,319,105,fill='#e8eedc' if j==0 else '#f8edd4',edge=TEAL if j==0 else GOLD,shadow=False)
        c.art(EQUIPMENT[j][1],69,y+8,85,83); c.text(169,y+19,ITEM_NAMES[j]+' +3',22,width=192,lines=1); c.text(170,y+63,'iLv.12 · 紫色',17,MUTED)
    c.panel(422,225,1465,765)
    titles=['定向打造','装备强化','阶重锻','词条重铸','词条精炼','强化继承']
    for j,t in enumerate(titles): c.button(447+j*234,250,220,t,primary=j==mode,h=53)
    c.text(461,344,PRIMARY_NAME+' +3',35); c.chip(1630,348,'已锁定',MUTED,194)
    c.panel(457,423,570,411,fill='#f7ead0',shadow=False)
    c.art(EQUIPMENT[0][1],575,454,331,289); c.text(740,776,'当前 +3  →  目标 +4' if mode==1 else ['武器 · 紫色 · iLv.12','强化阶','选择第 2 阶','第 1 条：暴击率','暴击率 +8%','来源 +3 → 目标 +0'][mode],25,align='center')
    c.heading(1061,421,['打造条件','强化预览','重锻预览','重铸预览','精炼预览','继承预览'][mode])
    c.rows(1061,520,743,[('当前数值','326'),('预计变化','以实际结算为准'),('需要金币','480'),('所需材料','构装残片  12 / 8')],gap=61)
    c.text(1060,792,['选择槽位与品质后预览费用。','随机阶收益与品质分别展示。','保底进度  1 / 3','付款后展示候选，不重复抽取。','精炼上限与费用在确认前展示。','来源与目标不可相同；明示损耗。'][mode],21,MUTED,width=744,lines=2)
    c.text(461,859,'一次操作，一次扣款。保存失败时保留当前交易。',21,MUTED)
    c.button(460,918,598,'取消'); c.button(1088,918,738,titles[mode]+'并保存',True)

def codex(c):
    c.shell('图鉴'); c.panel(37,225,292,765); c.text(66,255,'发现记录',29)
    for j,name in enumerate(['全部怪物','晴辉遗庭','琥珀虫巢','南瓜墓镇','赤岩战寨','首领']): c.button(61,326+j*88,244,name,primary=j==0,h=62)
    c.panel(351,225,1536,765); c.text(387,255,'怪物图鉴',32); c.text(1848,267,'已发现  18 / 40',21,TEAL,align='right')
    for j in range(8):
        x=383+(j%4)*371; y=345+(j//4)*309; c.panel(x,y,343,287,fill='#f8ecd3',shadow=False)
        c.art(enemy([0,1,9,10,18,19,27,28][j]),x+30,y+14,283,190)
        c.text(x+170,y+219,['巡庭构装体','晶核守卫','琥珀猎虫','巨叶伏虫','缝线居民','墓镇守卫','赤岩斥候','战寨重装'][j],25,align='center')
        c.text(x+170,y+257,'已发现 · 查看资料',17,TEAL,align='center')

def monster(c,mode=0):
    c.shell('图鉴'); c.panel(37,225,807,765)
    if mode==2:
        c.text(440,421,'?',206,MUTED,align='center'); c.text(440,773,'尚未发现',39,align='center')
    else:
        c.art(enemy(0,mode==1),85,303,715,516); c.text(440,855,'日曜机关巨像' if mode else '巡庭构装体',40,align='center')
    c.chip(75,255,'未知' if mode==2 else ('首领' if mode else '普通怪'),GOLD if mode==1 else TEAL,147)
    c.panel(869,225,1018,765); c.heading(907,255,'发现条件' if mode==2 else '战斗资料')
    if mode==2:
        c.text(908,400,'探索对应地区并首次遭遇后，\n逐步解锁招式、弱点与掉落资料。',29,MUTED,width=891)
        c.text(908,568,'未知条目保留轮廓，不提前泄露全部情报。',23,MUTED,width=891)
    else:
        for j,(title,body) in enumerate([('所属地区','晴辉遗庭 · 构装文明'),('战斗特性','有效命中蓄能护盾。优先观察能源回路。'),('攻击预警','预备 → 锁定 → 释放 → 收势。锁定后及时侧移。'),('反制时机','利用收势窗口输出，避免在预警区持续站立。'),('可能掉落','本族装备、金币与构装材料。')]):
            yy=383+j*106; c.text(909,yy,title,22,TEAL); c.text(1083,yy,body,23,MUTED,width=720,lines=2)
    c.button(1321,917,520,'返回怪物图鉴',True)

def settings(c,tab):
    c.shell(); c.panel(37,225,356,765)
    for j,t in enumerate(['常规与辅助','画面设置','声音设置','操作绑定']): c.button(63,273+j*117,303,t,primary=j==tab,h=76)
    c.panel(418,225,1469,765); c.heading(457,258,['常规与辅助','画面设置','声音设置','操作绑定'][tab])
    options=[['语言|简体中文','自动普攻|开启','镜头震动|关闭','降低特效|关闭','敌人路径展示|关闭','文字缩放|100%'],['显示模式|无边框窗口','分辨率|1920 × 1080','界面缩放|100%','垂直同步|开启','降低特效|关闭','危险预警|始终保留'],['总音量|80%','音乐|60%','音效|85%','界面提示音|70%','音乐开关|开启','音效开关|开启'],['移动 / 跟随|鼠标右键','普通攻击|鼠标左键 / A','职业技能|Q / W / E / R','闪避 / 交互|空格 / F','背包 / 路线|B / M','技能 / 暂停|Tab / Esc']][tab]
    for j,s in enumerate(options):
        a,b=s.split('|'); y=381+j*78; c.text(462,y,a,26)
        if tab==2 and j<4:
            c.bar(1057,y+12,594,[.8,.6,.85,.7][j]); c.text(1816,y,b,24,TEAL,align='right')
        else: c.button(1182,y-5,632,b,primary=b=='开启',h=55)
    c.button(459,915,390,'恢复默认'); c.button(1172,915,642,'应用设置',True)

def archive(c,detail=False):
    c.shell('档案'); c.portrait(37,225,468,765)
    c.panel(530,225,1357,765); c.heading(566,256,'远征回顾' if detail else '永久冒险档案','每次远征都留下一页新的故事。')
    for j,(label,value) in enumerate([('已完成远征','24'),('最远地区','赤岩战寨'),('怪物发现','18 / 40')]):
        x=566+j*426; c.panel(x,382,400,146,fill='#f5e8cc',shadow=False); c.text(x+25,401,label,22,MUTED); c.text(x+25,446,value,35,TEAL)
    c.text(565,568,'本次远征' if detail else '最近远征',29)
    for j,(place,result) in enumerate([('晴辉遗庭','成功撤离'),('琥珀虫巢','成功撤离'),('南瓜墓镇','远征结束')]):
        y=638+j*82; c.icon('compass',567,y-7,56); c.text(641,y,place,26); c.text(1090,y,'08:42 · 困难',22,MUTED); c.text(1510,y,result,24,TEAL if j<2 else RED); c.text(1812,y,'详情  →',22,MUTED,align='right'); c.line((569,y+58,1824,y+58),'#ddcfb2',1)
    c.button(1417,917,407,'返回营地',True)

def expedition(c,mode=0):
    c.shell(); c.panel(37,225,1265,765); c.panel(1326,225,559,765)
    if mode==2:
        c.text(77,256,'远征路线 · 晴辉遗庭',34)
        points=[(169,460),(427,389),(686,480),(937,392),(1131,582),(866,757),(567,730),(279,801)]
        for a,b in zip(points,points[1:]): c.line((*a,*b),GOLD,6)
        for j,(x,y) in enumerate(points):
            c.d.ellipse((x-48,y-48,x+48,y+48),fill=TEAL if j<3 else '#e1d4b6',outline='#fff7df',width=5)
            c.text(x,y-23,'✓' if j<2 else str(j+1),32,'#fff9e8' if j<3 else INK,align='center'); c.text(x,y+61,['入口','战斗','当前位置','遗物','补给','战斗','首领','撤离'][j],20,INK,align='center')
    else:
        for j,place in enumerate(['晴辉遗庭','琥珀虫巢','南瓜墓镇','赤岩战寨']):
            x=67+(j%2)*612; y=255+(j//2)*292
            c.scene(world(j*7),x,y,584,256); c.panel(x+12,y+174,559,67,fill='#fff5de',edge=TEAL if j==0 else GOLD,shadow=False)
            c.text(x+37,y+184,place,29); c.text(x+535,y+195,'已解锁' if j<2 else '未解锁',18,TEAL if j<2 else MUTED,align='right')
        c.text(77,878,'后续八个地区：开发规划中，尚不能进入。',22,MUTED,width=1160)
    c.heading(1358,258,'当前远征计划'); c.text(1359,381,'晴辉遗庭',36)
    c.text(1359,446,'构装文明 / 日曜机关巨像',21,MUTED)
    c.text(1359,524,'选择难度',23)
    for j,name in enumerate(['普通','进阶','困难','严酷','极限']): c.button(1360+j*94,577,86,name,primary=j==2,h=50)
    c.rows(1359,675,486,[('推荐准备','检查八槽配装'),('规则','撤离后装备入库'),('解锁条件','击败前区首领并撤离')],gap=61)
    c.button(1359,916,486,'返回当前房间' if mode==2 else '开始远征',True)

def battle(c,mode=0):
    c.image=ImageOps.fit(world(100 if mode==2 else 0).convert('RGBA'),(W,H),method=Image.Resampling.LANCZOS); c.d=ImageDraw.Draw(c.image)
    c.panel(29,28,442,128); c.art(HEROES[0],41,41,95,99); c.text(151,43,'罗砧 · Lv.12',23); c.bar(151,85,286,.82,RED,17); c.bar(151,116,286,.64,GOLD,12)
    c.text(161,80,'2,034 / 2,480',13,'#fff9e8')
    c.panel(1446,28,442,224); c.text(1471,45,'晴辉遗庭  /  第 3 站',24); c.text(1473,100,'当前目标',19,TEAL); c.text(1473,139,'清理守卫并前往出口',23,width=383); c.text(1473,194,'剩余敌人  4',20,MUTED)
    c.art(WORLD_HERO,789,429,156,244)
    for j in range(3): c.art(enemy(j),1030+j*174,395+(j%2)*128,139,177)
    c.d.arc((898,469,1368,699),180,355,fill='#da9c42',width=8)
    c.d.arc((907,478,1359,690),180,355,fill='#fff1bd',width=3)
    c.text(1111,416,'326',41,'#ffe7a0'); c.chip(987,707,'破势 × 3',RED,174)
    c.panel(1472,288,410,116); c.text(1496,307,'连击 ×25',31); c.text(1496,356,'伤害 +12.5%   ·   3.2s',21,TEAL)
    if mode==2:
        c.panel(514,27,875,115); c.text(951,37,'日曜机关巨像  ·  第二阶段',29,align='center'); c.bar(548,90,807,.62,RED,22)
        c.panel(634,159,636,79); c.text(952,172,'交叉雷网  ·  锁定预警',29,RED,align='center'); c.bar(664,218,576,.72,GOLD,8)
        c.art(enemy(0,True),1030,260,387,423)
    if mode==0:
        c.panel(519,27,877,93); c.text(958,37,'独立试玩  /  不影响正式档案',29,align='center'); c.text(958,81,'练习移动、闪避与职业连招',19,MUTED,align='center')
    c.panel(503,898,916,143)
    for j in range(4):
        x=528+j*160; c.icon(['axe_slash','skills','crystal','dodge'][j],x,915,99); c.chip(x+32,992,'QWER'[j],TEAL,49)
    c.panel(1181,919,207,91,fill='#f4e6c8',shadow=False); c.text(1284,925,'空格',22,align='center'); c.text(1284,967,'闪避',23,align='center')
    c.panel(27,938,434,101); c.text(52,954,'右键移动   左键 / A 普攻',21); c.text(52,993,'F 交互   B 背包   M 路线',18,MUTED)
    c.panel(1470,919,417,119); c.text(1495,935,'金币  1,280',26); c.text(1495,983,'Esc 暂停   Tab 技能详情',19,MUTED)
    c.footer()

def reward(c,supply=False):
    c.shell(); c.panel(38,225,1847,765); c.text(961,252,'安全补给' if supply else '选择一件远征遗物',39,align='center')
    c.text(961,319,'本次整备完成后继续旅程。' if supply else '临时构筑仅作用于本次远征。确认前可查看完整说明。',22,MUTED,align='center')
    for j in range(3):
        x=78+j*593; c.panel(x,390,554,484,fill='#eaf0df' if j==0 else '#f8edd5',edge=TEAL if j==0 else GOLD)
        c.icon(['crystal','lantern','compass'][j],x+172,433,205)
        c.text(x+277,664,(['生命整备','职业资源','继续前进'][j] if supply else ['构装护盾','日轮余辉','先驱罗盘'][j]),32,align='center')
        c.text(x+36,736,(['生命恢复至安全阶段上限。','补充当前职业战斗资源。','状态已满，无需重复整备。'][j] if supply else ['加强护盾与前排持续作战。','围绕有效命中形成职业联动。','增强探索和节奏控制。'][j]),23,MUTED,width=480,lines=3)
    c.button(1123,916,680,'确认整备' if supply else '选择此遗物',True)

def modal(c,state=0):
    if state in [8,9,11,12]: battle(c,1)
    else: c.shell()
    layer=Image.new('RGBA',(W,H),(50,37,45,116)); c.image.alpha_composite(layer); c.d=ImageDraw.Draw(c.image)
    c.panel(440,229,1040,643,fill='#fff5df',edge=GOLD,r=22)
    positive=state in [2,4,9]; c.icon('coin' if state in [1,2,3] else ('compass' if positive else 'lantern'),898,265,125)
    c.text(960,410,c.screen[1],44,TEAL if positive else INK,align='center')
    messages=[
'将回收已选中的 4 件装备。穿戴中与锁定装备不会被选入。\n预计获得 720 金币。回收后无法恢复。',
'购买晴辉构装旅者核心 ×1，花费 480 金币。\n当前 12,680 → 购买后 12,200。',
'晴辉构装旅者核心已加入永久背包。\n现在可以前往背包查看或继续选购。',
'需要 480 金币，当前可用 320。\n本次购买没有发生扣款，原选择已保留。',
'晴辉构装旅者核心  +3 → +4\n本次结果已保存，具体属性变化在装备详情中查看。',
'拆解后装备将被永久移除。\n预计返还构装残片 ×8，请核对目标装备。',
'Q 已绑定「破阵冲锋」。\n请选择其他按键，或明确确认替换原绑定。',
'开始新档案将覆盖当前永久进度。\n本操作不可撤销，取消可保留现有档案。',
'战斗与计时已暂停。\n继续远征，或进入设置调整操作。',
'本次获得的装备将在撤离成功后永久入库。\n金币 1,280 · 新装备 3 件。',
'当前操作尚未完成保存。\n重试同一交易，不重复扣款、不重新抽取结果。',
'当前房间未能完整载入。\n保留已提交进度，可以重试或返回安全界面。',
'安全阶段保存当前状态；战斗中退出将回到本房入口检查点。\n请确认后退出，或继续本次远征。'][state]
    c.text(518,513,messages,26,MUTED,width=884,lines=4)
    left=['取消','取消购买','继续选购','返回商城','返回锻造','取消拆解','重新选择','保留档案','设置与操作','继续探索','取消未付款操作','返回营地','继续游戏'][state]
    right=['确认回收','确认购买','查看装备','查看获取途径','查看属性','确认拆解','替换绑定','确认新建','继续远征','确认撤离','重试并保存','重试载入','保存并退出'][state]
    c.button(487,758,451,left); c.button(982,758,451,right,primary=state not in [0,5,7],danger=state in [0,5,7],h=58)

def result(c,loss=False):
    c.shell(); c.panel(137,228,1646,763); c.icon('compass',879,247,161)
    c.text(960,410,'远征结束' if loss else '成功撤离',57,RED if loss else TEAL,align='center')
    c.text(960,494,'每次冒险，都会让你更了解这片世界。' if loss else '战利品已安全带回，新的旅程正在等待。',24,MUTED,align='center')
    for j in range(2):
        x=189+j*796; c.panel(x,576,748,267,fill='#f6e8cd',shadow=False)
        c.text(x+30,602,(['已保留','本局损失'][j] if loss else ['远征收获','新装备入库'][j]),30,TEAL if j==0 else (RED if loss else INK))
        if j==1 and not loss:
            for k in range(3): c.item(x+29+k*232,660,k,w=212,h=150)
        else:
            vals=([('英雄等级','Lv.12'),('永久装备','全部保留')] if j==0 else [('本局金币','扣除 50%'),('未结算经验 / 临时装备','未带回')]) if loss else [('金币收益','+1,280'),('远征时间','08:42')]
            c.rows(x+32,679,682,vals,gap=67)
    c.button(191,900,742,'查看远征记录'); c.button(985,900,746,'返回营地',True)

def title(c,loading=False):
    c.scene(world(0),0,0,W,H)
    veil=Image.new('RGBA',(W,H),(250,239,212,0)); vd=ImageDraw.Draw(veil)
    for x in range(W): vd.line((x,0,x,H),fill=(253,242,215,max(0,int(246*(1-x/W)))))
    c.image.alpha_composite(veil); c.d=ImageDraw.Draw(c.image)
    c.icon('compass',105,95,91); c.text(219,118,'ABYSS SALVAGER',27,TEAL)
    c.text(102,228,'深渊拾荒者',83); c.text(110,350,'向着阳光中的遗迹，出发。',32,MUTED)
    c.art(HEROES[0],1053,162,674,724)
    if loading:
        c.panel(110,752,1697,190); c.text(153,775,'正在前往晴辉遗庭',32); c.bar(154,850,1610,.68,TEAL,17); c.text(154,895,'提示：首领锁定预警后，及时侧移离开危险区域。',22,MUTED)
    else:
        for j,lab in enumerate(['继续旅程','完整技能试玩','开始新档案','设置与操作']): c.button(111,470+j*100,568,lab,primary=j==0,h=73)
        c.text(114,917,'三个职业 · 四族远征 · 独立冒险',23,TEAL)
    c.footer()

def camp(c):
    c.shell(); c.portrait(38,225,553,765)
    c.panel(615,225,1270,329); c.scene(world(0),635,244,1229,289)
    c.panel(650,373,699,143,shadow=False); c.text(678,390,'下一站，晴辉遗庭',37); c.text(680,455,'检查配装，选择难度，开启远征。',23,MUTED)
    for j,(t,k) in enumerate([('英雄档案','hero'),('技能成长','skills'),('装备背包','equipment'),('装备商城','shop')]):
        x=615+(j%2)*646; y=577+(j//2)*145; c.panel(x,y,624,123); c.icon(k,x+17,y+17,84); c.text(x+122,y+23,t,31); c.text(x+123,y+77,['选择伙伴与职业','查看连招与技能分支','八槽配装与多选回收','选购单件或补齐套装'][j],20,MUTED)
    c.button(619,906,546,'游戏试玩'); c.button(1197,906,653,'开始远征',True)

def components(c):
    c.shell(); c.panel(37,225,1848,765); c.heading(78,254,'组件与视觉状态','米白纸面 / 黄铜细边 / 深紫文字 / 手绘圆形徽章')
    for j,(lab,col) in enumerate([('纸面',PAPER),('文字',INK),('黄铜',GOLD),('主操作',TEAL),('危险',RED),('品质',PURPLE)]):
        x=79+j*294; c.panel(x,382,263,132,fill=col,edge=col,shadow=False); c.text(x+131,421,lab,27,INK if j==0 else '#fff7e5',align='center')
    c.button(80,568,398,'开始远征',True); c.button(509,568,398,'返回背包'); c.button(938,568,398,'确认拆解',danger=True); c.button(1367,568,398,'材料不足',disabled=True)
    for j in range(8): c.item(80+j*215,679,j,w=188,h=190)
    c.text(82,919,'稀有度同时使用颜色与文字；危险操作采用等宽双按钮确认。',25,MUTED,width=1640)

def progress(c):
    c.shell('技能'); c.portrait(37,225,430,765)
    c.panel(491,225,1395,765); c.heading(531,258,'天赋与成长','查看已获得能力及下一成长节点。')
    for j,lv in enumerate([1,2,3,4,10,12,14,16,18,20]):
        x=560+(j%5)*251; y=419+(j//5)*226
        c.d.ellipse((x,y,x+127,y+127),fill=TEAL if lv<=12 else '#ded3b8',outline=GOLD,width=3)
        c.text(x+64,y+31,str(lv),40,'#fff9e8' if lv<=12 else MUTED,align='center'); c.text(x+64,y+146,'已获得' if lv<=12 else '未解锁',21,TEAL if lv<=12 else MUTED,align='center')
    c.button(1193,916,650,'查看下一成长节点',True)

screens=read(Path(__file__).with_name('screens.json'))
# Match reviewed current skill names, not provisional labels in the initial inventory.
for row in screens:
    if row[3]=='skill': row[1]=SKILLS[row[5]//4][row[5]%4]; row[4]='QWER'[row[5]%4]+' · 技能详情'
(OUT/'png').mkdir(parents=True,exist_ok=True)
records=[]
for screen in screens:
    c=Canvas(screen,screen[3] in ['title','loading','battle']); kind=screen[3]; mode=screen[5]
    if kind=='title': title(c)
    elif kind=='camp': camp(c)
    elif kind=='roster': roster(c,bool(mode))
    elif kind=='hero': hero(c,mode)
    elif kind=='stats': stats(c)
    elif kind=='skills': skills(c,mode)
    elif kind=='skill': skill(c,mode)
    elif kind=='branches': branches(c,bool(mode))
    elif kind=='progress': progress(c)
    elif kind=='inventory': inventory(c,mode)
    elif kind=='equipment': equipment(c,mode)
    elif kind=='compare': compare(c,bool(mode))
    elif kind=='shop': shop(c,bool(mode))
    elif kind=='forge': forge(c,mode)
    elif kind=='codex': codex(c)
    elif kind=='monster': monster(c,mode)
    elif kind=='settings': settings(c,mode)
    elif kind=='archive': archive(c,bool(mode))
    elif kind=='expedition': expedition(c,mode)
    elif kind=='battle': battle(c,mode)
    elif kind=='reward': reward(c,bool(mode))
    elif kind=='modal': modal(c,mode)
    elif kind=='result': result(c,bool(mode))
    elif kind=='loading': title(c,True)
    elif kind=='components': components(c)
    else: raise ValueError(kind)
    path=OUT/'png'/(screen[0]+'.png'); c.image.convert('RGB').save(path,optimize=True)
    with Image.open(path) as verify: verify.verify()
    records.append({'id':screen[0],'title':screen[1],'group':screen[2],'state':screen[4],'file':'png/'+path.name,'width':W,'height':H,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    print(screen[0],path.stat().st_size,flush=True)

# Three readable contact sheets instead of one unusably tall image.
for start in range(0,len(records),26):
    chunk=records[start:start+26]; rows=math.ceil(len(chunk)/4)
    sheet=Image.new('RGB',(1920,80+rows*312),'#eee3ca'); d=ImageDraw.Draw(sheet)
    d.text((26,14),f'深渊拾荒者 / UI设计评审 {start+1:02d}–{start+len(chunk):02d}',font=font(30),fill=INK)
    for j,rec in enumerate(chunk):
        x=20+(j%4)*477; y=76+(j//4)*312
        thumb=Image.open(OUT/rec['file']).resize((457,257),Image.Resampling.LANCZOS); sheet.paste(thumb,(x,y)); d.text((x+4,y+266),rec['id'].split('-')[0]+' '+rec['title'],font=font(18),fill=INK)
    sheet.save(OUT/f'overview-{start//26+1:02d}.jpg',quality=90)
manifest={'version':'review-v1','status':'illustrated-design-proposal-not-runtime','reference_a':'https://www.canva.com/M/MAHW0OEk3j8','reference_b':'https://www.canva.com/M/MAHW0NM3jwk','reference_fidelity':'A/B assets were supplied to a separate Canva generation job. These deterministic compositions use repository art and documented visual conventions; exact pixel matching to A/B remains unverified.','example_data':True,'screens':records,'art_sources':sorted(USED),'warnings':WARNINGS}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
md=['# 深渊拾荒者 · 全界面视觉评审稿','',f'本目录包含 **{len(records)} 张 1920×1080 PNG**。这是静态界面设计提案，不是游戏实机截图，也没有改动运行 UI、存档或数值。','',
'## 参考与完成口径','',
'用户指定图1 / A负责风格，图2 / B负责布局。本批采用仓库原有手绘插画与米白羊皮纸、黄铜、深紫文字规范重新排版；A/B 原图在当前工具链未完成像素级读取和对照，因此**不能把本批称为已验收的 A/B 精确复刻**。Canva 主界面生成任务未提供可取得的成图，不计入本目录。','',
'本目录覆盖一级页面、英雄与12技能详情、装备/套装详情、装备比较、锻造子流程、怪物详情模板及关键状态。怪物资料是布局样例，不逐一生成40只怪物的内容变体。数值、库存、词条、样例物品/怪物名与部分新增页面为评审示意，不作为实现承诺或平衡真值。','',
'## 浏览','',
'打开下方图片可查看原图。`index.html` 是离线图片索引，不是可试玩游戏。','',
'![总览 01](overview-01.jpg)','![总览 02](overview-02.jpg)','![总览 03](overview-03.jpg)','',
'## 逐页原图','']
current=None
for rec in records:
    if current!=rec['group']: current=rec['group']; md += ['','### '+current,'']
    md += [f"#### {rec['id']} · {rec['title']}",rec['state'],'',f"![{rec['title']}]({rec['file']})",'']
md += ['## 可复现与来源','',
'运行 `python docs/ui-review-ab/source/render.py`，需要 Pillow 11.3.0 和仓库现有素材。源图只读取不修改；未复制或分发字体文件。素材来源逐项记录于 `manifest.json/art_sources`；相关授权记录参见 `../ASSET_LICENSES.md`。','',
'内容核对入口：`scripts/ui/main.gd`、`workshop_panel.gd`、`instance_forging_panel.gd`、`backpack_panel.gd`、`hud.gd`；规范依据 `docs/DEVELOPMENT_PROGRESS.md`、`docs/LEVEL_ROADMAP.md`、`docs/DEVELOPMENT_STANDARDS.md`、`docs/ROLE_SKILL_REDESIGN.md`。','',
'## 验收边界','',
'自动检查每张PNG可解码、画布尺寸、文件摘要与数量。自动检查不代表逐页视觉人工验收，不代表交互可用性或实机改造完成。']
(OUT/'README.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
html=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>深渊拾荒者 UI 评审</title><style>body{margin:0;padding:32px;background:#eee3ca;color:#392843;font:18px system-ui}header{max-width:1500px;margin:auto}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:24px}article{background:#fff5de;padding:18px;border:1px solid #b39059;border-radius:14px}img{width:100%;display:block}a{color:inherit}h2{font-size:23px}small{color:#817263}</style><header><h1>深渊拾荒者 · UI视觉评审</h1><p>78张 Full HD 静态设计提案。点击图片打开原图；示意数据，非实机截图。A/B精确匹配尚未验收。</p></header><main>']
for rec in records: html.append(f'<article><h2>{rec["id"]} · {rec["title"]}</h2><p>{rec["state"]}</p><a href="{rec["file"]}" target="_blank"><img loading="lazy" src="{rec["file"]}" alt="{rec["title"]}"></a></article>')
html.append('</main></html>'); (OUT/'index.html').write_text('\n'.join(html),encoding='utf-8')
(OUT/'render-report.json').write_text(json.dumps({'png_count':len(records),'expected_count':len(screens),'all_decode':True,'size':[W,H],'art_source_count':len(USED),'warnings':WARNINGS},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'png_count':len(records),'warnings':WARNINGS},ensure_ascii=False),flush=True)
