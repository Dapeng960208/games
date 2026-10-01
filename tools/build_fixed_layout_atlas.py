"""Render the proposed authored room layouts; never touches runtime game data."""
from pathlib import Path
import json
import math
import html
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/levels/fixed_layouts'
INK = '#392444'
MUTED = '#776b7a'
PAPER = '#fcf4e4'
GOLD = '#ad8040'
ROUTE = '#258b86'
RED = '#cb6c5c'
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
fonts = {}


def font(size=22, bold=False):
    key = (size, bold)
    if key not in fonts:
        fonts[key] = ImageFont.truetype(BOLD if bold else FONT, size)
    return fonts[key]


def project(p):
    x, y = p
    return (100 + x * .32 + y * .19, 450 - x * .10 + y * .31)


def wrapped(draw, text, xy, width, size=22, fill=INK, bold=False, line_height=None):
    f = font(size, bold)
    lines, line = [], ''
    for char in str(text):
        if char == '\n' or (line and draw.textlength(line + char, font=f) > width):
            lines.append(line)
            line = '' if char == '\n' else char
        else:
            line += char
    if line:
        lines.append(line)
    y = xy[1]
    for line in lines:
        draw.text((xy[0], y), line, font=f, fill=fill)
        y += line_height or size * 1.55
    return y


def poly_rect(rect):
    x, y, w, h = rect
    return [project((x, y)), project((x + w, y)), project((x + w, y + h)), project((x, y + h))]


def translucent(image, polygon, fill, outline=None, width=1):
    layer = Image.new('RGBA', image.size)
    d = ImageDraw.Draw(layer)
    d.polygon(polygon, fill=fill)
    if outline:
        d.line(polygon + [polygon[0]], fill=outline, width=width)
    image.alpha_composite(layer)


def badge(draw, p, text, color, radius=19):
    x, y = p
    draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=color, outline=PAPER, width=3)
    f = font(17, True)
    box = draw.textbbox((0,0), text, font=f)
    draw.text((x-(box[2]-box[0])/2, y-13), text, font=f, fill=PAPER)


def icon(draw, position, key, name, color, landmark=False):
    """Schematic 2.5D silhouettes, not production sprites or final art."""
    x, y = position
    s = 1.6 if landmark else 1
    edge = INK
    def pts(values): return [(x+a*s, y+b*s) for a,b in values]
    def box(values): return (x+values[0]*s,y+values[1]*s,x+values[2]*s,y+values[3]*s)
    draw.ellipse(box((-32,-9,35,12)), fill='#cbbda1')
    meaning = (key + name).lower()
    if landmark and any(k in meaning for k in ['clock','dial','ring','日轮','日曜','圆纹','练武','擂台']):
        draw.ellipse(box((-47,-28,47,13)),fill='#e8cc8e',outline=GOLD,width=3)
        draw.ellipse(box((-34,-23,34,7)),fill=color,outline=edge,width=2)
        for t in range(8):
            a=t*math.tau/8
            draw.line(pts([(math.cos(a)*21,math.sin(a)*10-8),(math.cos(a)*40,math.sin(a)*19-8)]),fill=PAPER,width=3)
        draw.ellipse(box((-9,-15,9,-1)),fill='#f4dfa4',outline=edge)
    elif any(k in meaning for k in ['柱','column','pillar']):
        draw.polygon(pts([(-18,0),(11,7),(23,-2),(23,-59),(-7,-65),(-18,-57)]),fill='#e6d9b8',outline=edge)
        draw.polygon(pts([(-18,-57),(-7,-65),(23,-59),(10,-51)]),fill=PAPER,outline=GOLD)
        draw.line(pts([(10,-51),(10,6)]),fill=GOLD,width=2)
        draw.line(pts([(-7,-57),(5,-34),(-2,-8)]),fill=color,width=5)
    elif any(k in meaning for k in ['屋','店','棚','房','邮','亭','铺','屋','house','market','stall','tent','workshop']):
        draw.polygon(pts([(-29,-5),(0,6),(28,-9),(28,-40),(0,-31),(-29,-43)]), fill='#efd9b3', outline=edge)
        draw.polygon(pts([(-34,-40),(0,-67),(34,-47),(0,-29)]), fill=color, outline=edge)
        draw.line(pts([(0,-29),(0,6)]), fill=GOLD, width=2)
        draw.rounded_rectangle(box((-12,-20,-1,2)), radius=3, fill=INK)
    elif any(k in meaning for k in ['旗','帆','banner','flag','wind','风铃']):
        draw.line(pts([(0,2),(0,-64)]), fill=GOLD, width=5)
        draw.polygon(pts([(1,-62),(34,-52),(25,-28),(1,-37)]), fill=color, outline=edge)
        draw.ellipse(box((-6,-72,6,-60)), fill='#e4b864', outline=edge)
    elif any(k in meaning for k in ['树','叶','花','vine','tree','plant','garden','草','花圃']):
        draw.polygon(pts([(-7,3),(6,5),(9,-47),(-6,-50)]), fill='#ac8b5d', outline=edge)
        for a,b in [(-20,-45),(18,-47),(0,-66)]:
            draw.ellipse(box((a-21,b-18,a+21,b+18)), fill=color, outline=edge, width=2)
        draw.ellipse(box((-3,-52,10,-40)), fill='#f2d476')
    elif any(k in meaning for k in ['巢','蜂','hive','egg','茧','cocoon','wax']):
        draw.ellipse(box((-28,-51,28,3)), fill='#e2b758', outline=edge, width=2)
        for yy in [-39,-24,-10]:
            draw.arc(box((-24,yy-6,25,yy+10)), 0, 180, fill=GOLD, width=3)
        draw.ellipse(box((-11,-26,10,-6)), fill=color, outline=edge)
        draw.line(pts([(0,-51),(10,-66)]), fill='#96ad65', width=4)
    elif any(k in meaning for k in ['墓','棺','grave','coffin','memorial','雕','statue','totem','图腾']):
        draw.polygon(pts([(-18,3),(18,-5),(18,-59),(0,-70),(-18,-61)]), fill='#e0d6ce', outline=edge)
        draw.polygon(pts([(18,-5),(28,-11),(28,-63),(18,-59)]), fill='#b7a9ba', outline=edge)
        draw.line(pts([(-8,-42),(9,-47)]), fill=color, width=5)
        draw.line(pts([(0,-52),(0,-23)]), fill=color, width=4)
    elif any(k in meaning for k in ['鼓','drum','barrel','桶','炉','furnace','kiln']):
        draw.rectangle(box((-27,-43,27,-6)), fill=color, outline=edge, width=2)
        draw.ellipse(box((-27,-51,27,-35)), fill='#f6dfab', outline=edge, width=2)
        draw.arc(box((-27,-15,27,5)), 0, 180, fill=edge, width=3)
        for xx in [-18,0,18]: draw.line(pts([(xx,-40),(xx,-7)]), fill=GOLD, width=3)
    elif any(k in meaning for k in ['晶','crystal','棱','prism','日','sun','镜','mirror','仪','dial']):
        draw.ellipse(box((-29,-10,29,8)), fill='#e8c274', outline=edge, width=2)
        draw.polygon(pts([(0,-72),(23,-44),(13,-10),(-13,-4),(-22,-43)]), fill=color, outline=edge)
        draw.line(pts([(0,-72),(2,-28),(13,-10)]), fill=PAPER, width=3)
    elif any(k in meaning for k in ['瓜','pumpkin','灯','lantern']):
        draw.ellipse(box((-28,-44,28,4)), fill='#e7a45f', outline=edge, width=2)
        draw.arc(box((-16,-44,16,4)), 85, 275, fill='#bb6e3d', width=3)
        draw.line(pts([(0,-44),(5,-58)]), fill='#749665', width=6)
        draw.polygon(pts([(-12,-28),(-4,-32),(-4,-18)]), fill=color)
        draw.polygon(pts([(12,-28),(4,-32),(4,-18)]), fill=color)
    elif any(k in meaning for k in ['武','weapon','rack','牙','骨','bone','训练','dummy','靶']):
        draw.line(pts([(-22,2),(-14,-55),(20,-2)]), fill='#a27745', width=5)
        draw.line(pts([(-20,-30),(22,-42)]), fill=GOLD, width=5)
        for xx in [-8,9]: draw.line(pts([(xx,-44),(xx+8,-7)]), fill='#eee1c8', width=6)
        draw.ellipse(box((-12,-66,11,-42)), fill=color, outline=edge)
    elif any(k in meaning for k in ['船','boat','dock','cart','车','运输']):
        draw.polygon(pts([(-36,-14),(-15,3),(29,-6),(40,-26),(5,-18)]), fill='#c9a263', outline=edge)
        draw.polygon(pts([(-29,-18),(4,-35),(31,-26),(1,-11)]), fill=color, outline=edge)
        for xx in [-16,20]: draw.ellipse(box((xx-8,-1,xx+8,13)), fill=GOLD, outline=edge)
    elif any(k in meaning for k in ['泉','池','well','fountain','渠']):
        draw.ellipse(box((-37,-18,36,6)), fill='#d2c09a', outline=edge)
        draw.ellipse(box((-30,-16,29,-1)), fill=color, outline=GOLD)
        draw.line(pts([(0,-8),(0,-43)]), fill=GOLD, width=7)
        draw.ellipse(box((-17,-46,17,-34)), fill=color, outline=edge)
    else:
        draw.polygon(pts([(-25,-4),(0,7),(27,-7),(27,-36),(0,-24),(-25,-36)]), fill='#e7cca0', outline=edge)
        draw.polygon(pts([(-25,-36),(0,-49),(27,-36),(0,-24)]), fill=color, outline=edge)
        draw.line(pts([(0,-24),(0,7)]), fill=GOLD, width=3)


def draw_dashed(draw, points, color, width=5, dash=14, gap=10):
    for a,b in zip(points,points[1:]):
        length=math.dist(a,b)
        if not length: continue
        for start in range(0,int(length),dash+gap):
            t1,t2=start/length,min(1,(start+dash)/length)
            p1=(a[0]+(b[0]-a[0])*t1,a[1]+(b[1]-a[1])*t1)
            p2=(a[0]+(b[0]-a[0])*t2,a[1]+(b[1]-a[1])*t2)
            draw.line((p1,p2),fill=color,width=width)


def render_room(region, room):
    image=Image.new('RGBA',(1920,1640),PAPER)
    draw=ImageDraw.Draw(image)
    accent=region['palette']['accent']
    draw.rounded_rectangle((24,24,1895,1615),radius=26,outline=GOLD,width=3)
    draw.text((65,55),f"{region['biome_id']}  {region['name']}  /  固定布局设计",font=font(22),fill=MUTED)
    draw.text((65,95),f"{room['id']}  {room['name']}",font=font(42,True),fill=INK)
    draw.text((1440,70),'设计草案 · 等待确认',font=font(22,True),fill=GOLD)
    draw.text((1440,108),'2800 × 1800 / 坐标固定',font=font(21),fill=MUTED)
    arena=poly_rect([0,0,2800,1800])
    outer=poly_rect([-60,-60,2920,1920])
    draw.polygon(outer,fill=region['palette']['foliage'],outline=GOLD,width=2)
    shifted=[(x+7,y+20) for x,y in arena]
    draw.polygon(shifted,fill='#bfa882')
    draw.polygon(arena,fill=region['palette']['ground'],outline=GOLD,width=3)
    edge_symbols={
        'B01':[('greenhouse','外围小温室'),('tree','藤蔓树冠'),('fountain','画外水渠'),('flower','低花栏')],
        'B02':[('hive','蜂蜡巢壁'),('tree','巨叶树冠'),('house','蜜晶巢屋'),('flower','叶片矮栏')],
        'B03':[('house','紫瓦小屋'),('pumpkin','南瓜花圃'),('grave','低墓栏'),('tree','街口枯树')],
        'B04':[('tent','赤岩寨棚'),('banner','靛蓝战旗'),('totem','兽牙围栏'),('drum','外围鼓台')],
    }
    for (key,name),position in zip(edge_symbols[region['biome_id']],[(1150,-45),(-45,700),(2845,1050),(1350,1845)]):
        icon(draw,project(position),key,name,region['palette']['foliage'])
    for x in range(0,2801,350):
        draw.line([project((x,0)),project((x,1800))],fill='#d8cbb6',width=1)
    for y in range(0,1801,300):
        draw.line([project((0,y)),project((2800,y))],fill='#d8cbb6',width=1)
    translucent(image,poly_rect(room['open_zone']),(95,167,141,22),(95,167,141,100),2)
    draw=ImageDraw.Draw(image)
    route=[project(p) for p in room['route']]
    draw.line(route,fill='#eff7e9',width=24,joint='curve')
    draw_dashed(draw,route,ROUTE,5)
    side=[project(p) for p in room.get('side_route',[])]
    draw_dashed(draw,side,GOLD,4,10,9)
    for i,zone in enumerate(room['encounters'],1):
        cx,cy=zone['center']; r=zone['radius']
        points=[project((cx+math.cos(t)*r,cy+math.sin(t)*r)) for t in [k*math.tau/40 for k in range(40)]]
        translucent(image,points,(203,108,92,27),(203,108,92,125),2)
    draw=ImageDraw.Draw(image)
    subjects=[]
    for i,prop in enumerate(room['props'],1): subjects.append((prop['position'][1],i,prop))
    subjects.sort()
    landmark=room['landmark']
    icon(draw,project(landmark['position']),landmark['key'],landmark['name'],accent,True)
    p=project(landmark['position'])
    draw.text((p[0]-26,p[1]+18),'地标',font=font(17,True),fill=GOLD)
    for _,i,prop in subjects:
        p=project(prop['position'])
        if prop['solid']:
            w,h=prop['size']; x,y=prop['position']
            draw.line(poly_rect([x-w/2,y-h/2,w,h])+[project((x-w/2,y-h/2))],fill=RED,width=3)
        icon(draw,p,prop['key'],prop['name'],region['palette']['secondary'])
        badge(draw,(p[0]+24,p[1]-2),str(i),GOLD,14)
    for i,obj in enumerate(room['objectives'],1):
        p=project(obj['position']); icon(draw,p,'crystal',obj['name'],accent)
        badge(draw,(p[0],p[1]-75),f'O{i}',ROUTE,20)
    for i,beacon in enumerate(room['beacons'],1):
        p=project(beacon)
        draw.ellipse((p[0]-24,p[1]-10,p[0]+24,p[1]+10),outline=ROUTE,width=2)
        draw.line((p[0],p[1]-5,p[0],p[1]-33),fill=GOLD,width=5)
        draw.ellipse((p[0]-12,p[1]-49,p[0]+12,p[1]-26),fill=accent,outline=INK,width=2)
        badge(draw,(p[0],p[1]+22),f'B{i}',ROUTE,19)
    for i,zone in enumerate(room['encounters'],1):
        badge(draw,project(zone['center']),f'G{i}',RED,22)
    for key,label in [('entry','入口'),('exit','出口')]:
        p=project(room[key]); badge(draw,p,label,INK,28)
    if room.get('boss'):
        p=project(room['boss']['position'])
        badge(draw,p,'首领',RED,34)
        draw.text((p[0]-48,p[1]-70),room['boss']['name'],font=font(20,True),fill=INK)
    # The panel is a precise object schedule for later authored placement.
    draw.line((1420,176,1420,1580),fill='#dcc9a9',width=2)
    draw.text((1460,185),'固定物件清单',font=font(26,True),fill=INK)
    draw.text((1460,225),'编号 / 物件名称 / 世界坐标',font=font(18),fill=MUTED)
    y=263
    for i,prop in enumerate(room['props'],1):
        badge(draw,(1476,y+10),str(i),GOLD,14)
        label=prop['name']+('  ●' if prop['solid'] else '')
        draw.text((1501,y-5),label,font=font(20),fill=INK)
        x,z=prop['position']
        draw.text((1501,y+23),f'({x}, {z})',font=font(16),fill=MUTED)
        y+=57
    draw.text((1460,y+10),'● 小脚点碰撞；其余为无碰撞装饰',font=font(17),fill=RED)
    y+=55
    draw.text((1460,y),'敌群分区',font=font(23,True),fill=INK);y+=40
    for i,zone in enumerate(room['encounters'],1):
        y=wrapped(draw,f"G{i}  {zone['name']}：{'、'.join(zone['enemies'])}",(1460,y),385,17,line_height=26)+7
    draw.line((65,1080,1370,1080),fill='#dcc9a9',width=2)
    legends=[('主路线',ROUTE),('可选支路',GOLD),('O 任务目标',ROUTE),('B 固定信标',ROUTE),('G 敌群区域',RED),('绿框 开阔战斗区','#70a088')]
    x=70
    for label,color in legends:
        draw.ellipse((x,1105,x+13,1118),fill=color)
        draw.text((x+21,1097),label,font=font(19),fill=INK)
        x+=draw.textlength(label,font=font(19))+56
    y=1145
    y=wrapped(draw,'场景：'+room['motif'],(70,y),1270,24,bold=True)
    y=wrapped(draw,'目标：'+room['objective'],(70,y+8),1270,21)
    y=wrapped(draw,'故事：'+room['story'],(70,y+6),1270,20,fill=MUTED)
    loot='、'.join(room['loot'])
    y=wrapped(draw,'种族掉落：'+loot+'   /   遗物：'+room['relic'],(70,y+8),1270,19)
    if room.get('boss'):
        y=wrapped(draw,'首领技能：'+' → '.join(room['boss']['skills']),(70,y+10),1270,19,fill=RED)
    else:
        y=wrapped(draw,'设计约束：开阔中场；固定场景；信标靠近自动触发，功能随机。',(70,y+10),1270,18,fill=ROUTE)
    wrapped(draw,'边缘：'+room.get('edge_variant','外围文明景物与低边界自然过渡。'),(70,y+12),1270,18,fill=MUTED)
    draw.text((70,1570),'图中物件造型为位置示意；最终外观请对照本房美术参考。',font=font(17),fill=MUTED)
    path=OUT/'rooms'/f"{room['id']}.png"
    path.parent.mkdir(parents=True,exist_ok=True)
    image.convert('RGB').save(path,optimize=True)
    return path


def board(region):
    image=Image.new('RGB',(2560,1850),PAPER)
    draw=ImageDraw.Draw(image)
    draw.text((50,35),region['name']+' · 七个固定房间布局',font=font(40,True),fill=INK)
    draw.text((50,101),'六个战斗房间 + 一个首领场地  /  几何位置以逐房大图为准',font=font(23),fill=MUTED)
    for i,room in enumerate(region['rooms']):
        x=40+(i%4)*635;y=170+(i//4)*815
        src=Image.open(OUT/'rooms'/f"{room['id']}.png")
        src.thumbnail((608,685),Image.Resampling.LANCZOS)
        image.paste(src,(x,y))
        draw.text((x+10,y+700),f"{room['id']}  {room['name']}",font=font(26,True),fill=INK)
        wrapped(draw,room['motif'],(x+10,y+745),592,20,fill=MUTED,line_height=30)
    x,y=40+3*635,170+815
    draw.rounded_rectangle((x,y,x+607,y+685),radius=20,outline=GOLD,width=2)
    draw.text((x+28,y+36),'这一族的场景语言',font=font(28,True),fill=INK)
    yy=y+100
    for family in region['asset_families'][:8]:
        yy=wrapped(draw,'• '+family['name'],(x+30,yy),547,23,line_height=35)+15
    draw.text((x+30,y+610),'摆放固定 · 敌群按难度变化',font=font(24,True),fill=ROUTE)
    image.save(OUT/f"{region['biome_id']}_layout_board.png",optimize=True)


CSS = '''
:root{--paper:#fbf3e4;--ink:#392444;--muted:#786777;--gold:#ac8045;--line:#dec7a2;--green:#247f79}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:"Microsoft YaHei",sans-serif}button{font:inherit;color:inherit;cursor:pointer}header{padding:36px 5vw 24px;border-bottom:1px solid var(--line);background:#fffaf0}h1{font-size:32px;margin:0 0 12px}p{line-height:1.8;margin:8px 0}header p{color:var(--muted);max-width:1100px}.tabs{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}.tabs button{background:transparent;border:1px solid var(--gold);padding:11px 22px;border-radius:24px}.tabs button[aria-selected="true"]{background:var(--ink);color:var(--paper)}main{max-width:1560px;margin:auto;padding:28px 4vw 70px}.region{display:none}.region.active{display:block}.region-head{display:flex;justify-content:space-between;align-items:center;gap:24px}h2{margin:0;font-size:26px}.region-head p{color:var(--muted)}.art{width:100%;display:block;max-height:780px;object-fit:contain;border:1px solid var(--line);border-radius:14px;background:#eee5d2;margin:18px 0 8px}.caption{color:var(--muted);font-size:14px;margin:8px 0 28px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}.room{border:1px solid var(--line);border-radius:14px;overflow:hidden;background:#fffaf1}.room button{display:block;padding:0;border:0;width:100%;background:transparent}.room img{width:100%;display:block}.room-copy{padding:16px 20px 20px}.room h3{margin:0 0 8px}.room-copy p{font-size:14px;color:var(--muted)}.tag{font-size:13px;color:var(--green);margin-left:12px}.index{margin:22px 0;display:flex;gap:8px;flex-wrap:wrap}.index a{color:var(--ink);border-bottom:1px solid var(--gold);text-decoration:none;padding:7px}.rules{border-top:1px solid var(--line);margin-top:40px;padding-top:24px}.rules ul{line-height:1.9}.modal{position:fixed;inset:0;background:rgba(33,21,40,.93);display:none;z-index:10;padding:60px 2vw 20px;overflow:auto}.modal.open{display:block}.modal img{display:block;margin:0 auto;width:min(1920px,100%);background:var(--paper)}.close{position:fixed;right:25px;top:14px;padding:8px 18px;background:var(--paper);border:1px solid var(--gold);border-radius:20px}.modal-title{position:fixed;left:25px;top:18px;color:var(--paper)}.actions{display:flex;gap:12px;justify-content:center;margin:16px}.actions button,.actions a{background:var(--paper);border:1px solid var(--gold);padding:8px 18px;border-radius:20px;color:var(--ink);text-decoration:none}@media(max-width:800px){h1{font-size:25px}.grid{grid-template-columns:1fr}.region-head{display:block}header{padding:25px 6vw}.tabs button{padding:8px 13px}.modal{padding-top:65px}}@media print{header,.tabs,.art,.caption,.rules,.index{display:none}.region{display:block}.grid{display:block}.room{break-after:page;border:0}.room-copy{display:none}main{padding:0}.region-head{display:none}}
'''


def render_html(regions):
    e=lambda value:html.escape(str(value))
    tabs=''.join(f'<button role="tab" aria-selected="{str(i==0).lower()}" data-region="{r["biome_id"]}">{r["name"]}</button>' for i,r in enumerate(regions))
    sections=[]
    global CSS
    CSS += '.artpanel{aspect-ratio:1/1.1;background-size:400% 200%;background-repeat:no-repeat;background-color:#e9dcc7;border-top:1px solid var(--line);border-bottom:1px solid var(--line)}.gameplay{width:100%;display:block;border:1px solid var(--line);border-radius:12px;margin:20px 0}.edge-copy{display:grid;grid-template-columns:1fr 1fr;gap:24px}.edge-copy h3{margin-bottom:8px}@media(max-width:800px){.edge-copy{grid-template-columns:1fr}}@media print{.artpanel,.gameplay{display:none}}'
    tabs += '<button role="tab" aria-selected="false" data-region="perimeter">地图边缘</button>'
    for i,r in enumerate(regions):
        cards=[]
        for room in r['rooms']:
            room_id=room['id']; path=f'rooms/{room_id}.png'
            n=r['rooms'].index(room)
            position=f'{(n%4)*100/3:.4f}% {(n//4)*100}%'
            art=f"background-image:url('art/{r['biome_id']}_concepts.png');background-position:{position}"
            cards.append(f'''<article class="room" id="{room_id}"><div class="room-copy"><h3>{room_id} · {e(room['name'])}<span class="tag">{'首领' if room['kind']=='boss' else '战斗房间'}</span></h3><p>{e(room['motif'])}</p></div><div class="artpanel" style="{art}" role="img" aria-label="{e(room['name'])} 独立美术参考"></div><button data-room="{room_id}" aria-label="放大 {e(room['name'])} 固定布局"><img src="{path}" loading="lazy" alt="{e(room['name'])} 固定布局、目标、信标及物件坐标"></button><div class="room-copy"><p>{e(room['objective'])}</p><p>本房边缘：{e(room.get('edge_variant','外围文明景物自然过渡'))}</p><p>点击布局图，查看固定位置和物件编号。</p></div></article>''')
        links=''.join(f'<a href="#{room["id"]}">{room["id"]} {e(room["name"])}</a>' for room in r['rooms'])
        sections.append(f'''<section class="region {'active' if i==0 else ''}" id="{r['biome_id']}"><div class="region-head"><h2>{e(r['name'])} · {e(r['race'])}</h2><p>7 张房间设计图 / 点击逐房图片放大</p></div><p>{e(r['story'])}</p><h3>基于当前游戏元素的效果预览</h3><img class="gameplay" src="art/{r['biome_id']}_gameplay_preview.png" alt="{e(r['name'])} 保留现有角色怪物和HUD的设计效果图" onerror="this.hidden=true"><p class="caption">保留当前角色、怪物与HUD，展示固定摆放及完整边缘的预期效果。新增地标、边缘、图标需后续输出新素材；此图不是已上线截图。</p><h3>七房间美术总览</h3><img class="art" src="art/{r['biome_id']}_concepts.png" alt="{e(r['name'])} 七房间手绘奇幻美术参考" onerror="this.hidden=true"><p class="caption">美术板表达外形与材质，逐房布局图确定路线、物件和目标的固定位置。新道具与独立机关均为待确认设计。</p><nav class="index" aria-label="房间索引">{links}</nav><div class="grid">{''.join(cards)}</div></section>''')
    edges=[]
    for region in regions:
        labels={'north':'远侧 / 北','east':'东侧','south':'近侧 / 南','west':'西侧','transition':'地面过渡','foreground':'前景遮挡'}
        desc=region.get('edge_design',{})
        rows=''.join(f'<p><strong>{label}：</strong>{e(desc.get(key,"按该房外围景物过渡"))}</p>' for key,label in labels.items())
        edges.append(f'<article><h3>{region["name"]}</h3>{rows}</article>')
    sections.append(f'<section class="region" id="perimeter"><h2>四地图边缘设计</h2><img class="art" src="art/perimeter_concepts.png" alt="四种文明的边界、地面过渡、侧面和外围背景设计"><p class="caption">可走地面 → 低边界与植被 → 独立短侧面 → 外围文明背景 → 外角少量前景。禁止灰色空圈和地板贴图拉伸高墙。</p><div class="edge-copy">{"".join(edges)}</div></section>')
    data={room['id']:{'name':room['name'],'biome_id':r['biome_id']} for r in regions for room in r['rooms']}
    script='''const DATA=__DATA__;const modal=document.querySelector('.modal');const large=modal.querySelector('img');const title=modal.querySelector('.modal-title');let selected='',lastFocus=null;function show(id){selected=id;large.src='rooms/'+id+'.png';large.alt=DATA[id].name+'固定布局设计';title.textContent=id+' · '+DATA[id].name;document.querySelector('#download').href=large.src;modal.classList.add('open');document.body.style.overflow='hidden';document.querySelector('.close').focus()}function close(){modal.classList.remove('open');document.body.style.overflow='';if(lastFocus)lastFocus.focus()}document.querySelectorAll('[data-region]').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('[data-region]').forEach(t=>t.setAttribute('aria-selected',String(t===b)));document.querySelectorAll('.region').forEach(s=>s.classList.toggle('active',s.id===b.dataset.region))}));document.querySelectorAll('[data-room]').forEach(b=>b.addEventListener('click',()=>{lastFocus=b;show(b.dataset.room)}));document.querySelector('.close').addEventListener('click',close);document.addEventListener('keydown',e=>{if(e.key==='Escape')close();if(modal.classList.contains('open')&&['ArrowLeft','ArrowRight'].includes(e.key))move(e.key==='ArrowRight'?1:-1);if(e.key==='Tab'&&modal.classList.contains('open')){const focusable=[...modal.querySelectorAll('button,a')];let n=focusable.indexOf(document.activeElement)+(e.shiftKey?-1:1);e.preventDefault();focusable[(n+focusable.length)%focusable.length].focus()}});function move(step){let ids=Object.keys(DATA).filter(id=>DATA[id].biome_id===DATA[selected].biome_id);show(ids[(ids.indexOf(selected)+step+ids.length)%ids.length])}document.querySelector('#prev').addEventListener('click',()=>move(-1));document.querySelector('#next').addEventListener('click',()=>move(1));'''.replace('__DATA__',json.dumps(data,ensure_ascii=False))
    document=f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>四地图 · 28 房间固定布局设计册</title><style>{CSS}</style></head><body><header><h1>四地图 · 28 房间固定布局设计册</h1><p>明亮手绘卡通奇幻 · 古典遗迹与魔法文明 · 高机位三分之四斜俯视 · 2.5D。每房都有自己的地标、生态和生活物件；地形、道具、目标与信标位置固定。</p><p>此册用于确认设计，尚未替换游戏中的随机道具摆放。高难度可以增加怪群数量、属性及掉落品质，不移动场景元素。</p><nav class="tabs" role="tablist" aria-label="主题地图">{tabs}</nav></header><main>{''.join(sections)}<section class="rules"><h2>共同设计约束</h2><ul><li>每房独立人工布局，重复进入保持物件、路线、地标、目标和信标位置。</li><li>中心及主路宽阔；外围无碰撞装饰丰富画面，内场只放少量小脚点掩体。</li><li>无大矩形水池、坑洞或贴图拉伸高墙；各物件保持比例，建筑按独立2.5D素材制作。</li><li>信标位置固定，靠近自动获得状态；功能可随机，位置与视线保持可达。</li><li>房间名称沿用现有ID；新增种族地标、道具、独立机关和掉落名称属于设计草案。</li></ul></section></main><div class="modal" role="dialog" aria-modal="true" aria-label="房间设计大图"><span class="modal-title"></span><button class="close">关闭 ×</button><img alt=""><div class="actions"><button id="prev">← 上一房</button><a id="download" download>保存本房设计图</a><button id="next">下一房 →</button></div></div><script>{script}</script></body></html>'''
    (OUT/'index.html').write_text(document,encoding='utf-8')


def main():
    regions=[json.loads((OUT/f'B{i:02}.json').read_text(encoding='utf-8-sig')) for i in range(1,5)]
    total=0
    for region in regions:
        for room in region['rooms']:
            render_room(region,room);total+=1
        board(region)
    render_html(regions)
    print(f'Rendered {total} room diagrams, 4 layout boards and the local design atlas.')


if __name__=='__main__':
    main()
