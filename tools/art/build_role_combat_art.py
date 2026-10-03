"""Register original hand-painted skill PNGs; build badges and the star companion.

Retired flat body fixtures remain only in ignored review output.
Portrait and hand-painted PNG provenance is maintained beside each source image.
"""
from pathlib import Path
import json
import math
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PALETTES = {'warrior':('CH01','#233b66','#e0e6ef','#d6554e','#ffbc62'),
            'gunner':('CH02','#329ca9','#f8f3e8','#e9846c','#78e5e5'),
            'mage':('CH03','#352c4d','#202330','#695184','#9edfea')}
INK='#514253'; GOLD='#d2ac64'

def n(v): return str(round(v,2))
def path(d,fill='none',width=3,stroke=INK):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>'
def oval(x,y,rx,ry,fill,stroke=INK,width=3):
    return f'<ellipse cx="{n(x)}" cy="{n(y)}" rx="{n(rx)}" ry="{n(ry)}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>'
def line(a,b,color,width=3):
    return path(f'M{n(a[0])} {n(a[1])} L{n(b[0])} {n(b[1])}','none',width,color)
def star(x,y,r,color):
    pts=[]
    for i in range(8):
        t=i*math.pi/4-math.pi/2; s=r if i%2==0 else r*.32
        pts.append(f'{n(x+math.cos(t)*s)} {n(y+math.sin(t)*s)}')
    return path('M'+' L'.join(pts)+' Z',color,2,GOLD)
def svg(body,w,h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'

def icon(role,i):
    _,main,light,accent,glow=PALETTES[role]
    if role=='mage':light='#e3e8f4'
    gold='#c3ccd9' if role=='mage' else '#d2ac64'
    # The silhouette carries the skill identity at 44 px; no text or random marks.
    badge=oval(64,64,59,59,main,gold,3)+oval(64,64,52,52,'none',light,1)
    def axe(x,y,s=1,angle=0):
        shape=line((0,-24),(0,33),gold,8)
        shape+=path('M-3 -23 Q24 -36 35 -15 Q34 8 12 14 L9 -4 L-3 0 Z',light,3,gold)
        shape+=path('M16 -23 Q26 -19 27 -12','none',4,glow)
        return f'<g transform="translate({x} {y}) rotate({angle}) scale({s})">{shape}</g>'
    def bullet(x,y,s=1,angle=0,color=None):
        shape=path('M-6 12 L-6 -5 Q-6 -12 0 -18 Q6 -12 6 -5 L6 12 Z',color or light,3,gold)
        shape+=line((-5,5),(5,5),accent,3)
        return f'<g transform="translate({x} {y}) rotate({angle}) scale({s})">{shape}</g>'
    def boot(x,y,s=1):
        shape=path('M-13 -27 L11 -27 L9 0 Q15 8 26 11 L27 24 L-17 24 L-20 17 L-15 -2 Z',light,4,gold)
        shape+=path('M-12 -14 L8 -14 M-14 13 L12 13','none',5,accent)
        return f'<g transform="translate({x} {y}) scale({s})">{shape}</g>'
    def burst(x,y,r,color):
        points=[]
        for j in range(16):
            angle=j*math.pi/8;length=r if j%2==0 else r*.48
            points.append(f'{n(x+math.cos(angle)*length)} {n(y+math.sin(angle)*length)}')
        return path('M'+' L'.join(points)+' Z',color,3,gold)
    if role=='warrior':
        shapes=[
            # Charge: a broad forward arrow and an advancing axe.
            path('M19 67 L46 67 L46 51 L73 73 L46 95 L46 79 L19 79 Z',accent,3,gold)+axe(77,50,.93,25),
            # Cleave: the cutting arc reaches a fractured ground wedge.
            path('M25 72 Q40 32 97 30 L90 45 Q57 49 44 83 Z',accent,3,gold)+axe(44,48,.8,-42)+path('M24 100 L49 89 L61 99 L68 84 L89 95 L103 89','none',6,glow),
            # Warcry: a helmet broadcasts three clear sound rays.
            path('M45 38 Q65 22 81 39 L81 65 L70 77 L46 72 L41 52 Z',light,4,gold)+path('M45 52 L70 52 L62 66 L46 63 Z',main,3,gold)+path('M87 38 L100 29 M91 55 L108 55 M87 72 L100 82','none',6,glow)+path('M33 46 Q20 63 34 80','none',6,accent),
            # Axe crash: a vertical weapon plunges into an impact crater.
            oval(64,95,38,13,'none',glow,5)+burst(64,88,25,accent)+axe(57,46,.98,0)+path('M28 29 L28 60 M98 32 L98 63','none',5,glow),
            # Double sweep: opposed axe heads with two counterposed crescents.
            path('M23 58 Q19 26 54 23 M105 72 Q107 102 74 105','none',7,glow)+path('M45 18 L57 23 L47 32 M83 96 L72 105 L84 108',accent,3,gold)+axe(45,60,.68,-10)+axe(83,70,.68,170),
            # Stone guard: a solid rock shield with a broad stone crest.
            path('M25 37 L38 22 L55 30 L72 20 L95 31 L104 45 L91 56 L34 57 Z',accent,4,gold)+path('M34 45 L64 32 L94 45 L88 83 L64 105 L40 83 Z',light,4,gold)+path('M64 42 L75 61 L63 70 L72 85 L55 94 L60 70 L49 59 Z',main,3,gold),
            # Fault line: an extended fissure, distinct from the short axe cut.
            path('M57 108 L68 82 L55 69 L70 51 L63 34 L83 18 L73 42 L83 54 L69 74 L78 88 L69 108 Z',accent,4,gold)+path('M28 89 L41 71 L47 90 Z M88 57 L101 40 L108 65 Z M27 51 L38 34 L46 56 Z',light,3,gold),
            # Rift pull: inward arrows collapse into the central fissure.
            path('M18 45 L35 45 L35 33 L55 61 L35 89 L35 77 L18 77 Z M110 45 L93 45 L93 33 L73 61 L93 89 L93 77 L110 77 Z',light,3,gold)+path('M65 22 L59 43 L68 55 L58 75 L66 102','none',7,accent),
            # Returning throw: a flying axe follows a large return arrow.
            path('M29 35 Q93 11 99 63 Q100 96 42 98','none',7,glow)+path('M44 84 L23 99 L45 108 Z',accent,3,gold)+axe(62,59,.8,52)+path('M21 54 L38 48 M18 69 L35 63','none',5,light),
            # Counter: the impact bounces away from the shield edge.
            path('M31 32 L64 24 L83 38 L79 76 Q61 94 39 101 L28 72 Z',light,4,gold)+path('M43 43 L65 40 L65 70 L44 81 Z',main,3,gold)+path('M108 80 L83 61 L102 36','none',8,accent)+path('M89 34 L107 26 L107 45 Z',glow,3,gold),
            # Whirlwind: broad spiral ribbons wrap a compact central axe.
            path('M29 34 Q91 17 100 42 Q107 59 32 63 Q11 72 86 77 Q109 86 49 100','none',8,glow)+path('M43 24 L87 18 L96 37 M31 86 L46 103 L75 100','none',5,accent)+axe(58,59,.66,28),
            # Stomp: a boot drives the radial ground fracture.
            oval(64,96,42,13,'none',glow,5)+path('M26 102 L39 95 L50 103 L62 96 L77 108 M88 96 L103 102','none',6,accent)+boot(59,56,1.1)
        ]
    elif role=='gunner':
        shapes=[
            # Retreat fire: a backward arrow underneath a forward barrel.
            path('M67 79 L41 79 L41 65 L17 87 L41 106 L41 93 L67 93 Z',accent,3,gold)+path('M46 41 L68 29 L85 34 L101 32 L108 45 L85 58 L62 53 L49 70 L37 61 Z',light,4,gold)+line((87,40),(107,32),glow,6)+path('M94 66 L108 56','none',5,glow),
            # Rail shot: a luminous lance cuts through two target plates.
            path('M32 35 L48 29 L55 89 L39 96 Z M74 24 L88 21 L98 79 L81 85 Z',accent,4,gold)+path('M21 100 L86 27 L103 23 L98 41 L32 109 Z',glow,4,gold)+line((31,99),(93,30),light,5),
            # Grenade: a broad casing, pull ring and outward shock strokes.
            oval(64,67,26,31,accent,gold,4)+path('M48 37 L67 32 L83 41 L78 49 L62 42 L47 45 Z',light,4,gold)+oval(81,26,12,9,'none',light,5)+path('M51 57 L76 57 M52 75 L76 75 M34 65 L19 65 M94 65 L110 65 M40 92 L31 104 M90 92 L98 104','none',5,glow),
            # Barrage: six descending rounds form one dense volley silhouette.
            ''.join(bullet(x,y,.75,32) for x,y in [(53,35),(75,35),(97,35),(34,64),(56,64),(78,64)])+burst(40,98,19,glow)+path('M87 74 L77 90 M106 66 L96 82','none',5,light),
            # Fan shot: three diverging barrels of light from one origin.
            path('M34 97 L37 53 M39 95 L66 43 M43 98 L88 75','none',5,glow)+bullet(36,34,.9,0)+bullet(72,31,.9,30)+bullet(100,65,.9,58)+oval(30,103,9,5,accent,gold,3),
            # Smoke step: the boot silhouette emerges from a pale smoke cloud.
            path('M23 92 Q10 83 22 70 Q11 55 28 48 Q33 27 52 39 Q67 30 76 47 Q95 44 101 62 Q117 72 106 87 Q108 102 87 101 Z',glow,4,gold)+boot(60,62,.94)+path('M25 75 Q40 65 42 79 M82 85 Q91 75 102 81','none',5,main),
            # Explosive round: a single heavy shell against a jagged explosion.
            burst(66,65,45,accent)+bullet(65,61,1.68,39)+path('M26 30 L40 43 M91 91 L104 104','none',5,glow),
            # Root mine: a low ground disc and three binding legs.
            oval(64,75,36,17,light,gold,4)+oval(64,67,26,18,accent,gold,4)+path('M48 67 L53 44 L75 44 L81 67 Z',light,4,gold)+oval(64,54,8,8,glow,gold,3)+path('M36 89 L29 98 L21 98 M64 91 L64 108 M92 89 L100 98 L107 98','none',6,glow),
            # Chain shot: three reticles are joined by the jumping round.
            path('M30 86 L63 34 L99 77','none',6,glow)+''.join(oval(x,y,14,14,'none',light,4)+line((x-20,y),(x+20,y),gold,3)+line((x,y-20),(x,y+20),gold,3) for x,y in [(30,86),(63,34),(99,77)])+oval(63,34,5,5,accent,'none',0),
            # Tactical reload: a magazine sits between two directional arrows.
            path('M44 34 L78 28 L88 43 L81 91 L48 97 L40 84 Z',light,4,gold)+''.join(bullet(x,61,.62,4,glow) for x in [52,64,76])+path('M25 84 Q8 42 41 23 M96 29 Q117 65 90 103','none',6,glow)+path('M28 22 L46 19 L41 37 Z M85 90 L87 107 L102 98 Z',accent,3,gold),
            # Suppressive sweep: one carbine paints a wide arc of fire.
            path('M26 44 Q65 7 105 45','none',6,glow)+bullet(33,36,.62,-28)+bullet(65,23,.62,0)+bullet(98,37,.62,28)+path('M20 72 L33 61 L75 61 L83 67 L102 67 L104 81 L72 85 L49 81 L42 102 L28 97 L30 80 L20 81 Z',light,4,gold)+line((79,72),(102,72),glow,5),
            # Sentry: a raised rail barrel above a three-legged emplacement.
            path('M48 65 L63 50 L79 65 L74 83 L51 83 Z',accent,4,gold)+path('M51 48 L70 39 L103 39 L108 51 L72 58 L54 58 Z',light,4,gold)+line((77,46),(105,46),glow,5)+path('M56 81 L30 104 M65 84 L65 109 M74 81 L101 103','none',9,light)+oval(63,67,8,8,glow,gold,3)
        ]
    else:
        shapes=[
            # Star-bell missile: a bell-shaped shell with a single bright core.
            path('M22 86 L47 73 M20 67 L40 60 M34 99 L51 85','none',6,gold)+path('M52 63 Q45 40 66 31 Q91 31 88 56 L103 75 L58 94 L55 74 Z',light,4,gold)+star(74,59,26,glow)+oval(82,85,9,9,accent,gold,3),
            # Leap strike: a star dives onto a small impact ring.
            oval(68,95,35,13,'none',glow,5)+path('M32 67 Q22 30 60 23 Q86 20 85 56','none',6,gold)+path('M74 56 L85 75 L98 53 Z',light,3,gold)+star(68,87,19,glow)+star(34,32,13,light),
            # Ring guard: an open tilted orbit with three stars, no shield.
            '<g transform="rotate(-22 64 64)">'+oval(64,64,40,26,'none',glow,7)+star(27,57,12,light)+star(86,42,13,light)+star(80,88,13,light)+'</g>',
            # Star garden: upright star beacons surround a ground field.
            oval(64,82,41,22,'none',glow,5)+oval(64,82,29,14,'none',gold,4)+path('M29 75 L29 45 M64 65 L64 31 M99 75 L99 45','none',4,gold)+star(29,40,13,light)+star(64,28,17,glow)+star(99,40,13,light)+star(64,82,11,light),
            # Star rain: three equal stars open in a fan.
            path('M62 100 L29 51 M64 97 L64 45 M67 100 L98 51','none',5,gold)+star(27,36,20,glow)+star(64,26,21,light)+star(101,36,20,glow)+oval(64,104,11,5,accent,gold,3),
            # Soft shield: an opaque star shield framed by large woolly lobes.
            path('M64 30 Q78 18 87 32 Q104 31 100 48 Q114 60 101 75 Q102 91 82 96 L64 108 L46 96 Q26 91 27 75 Q14 60 28 48 Q24 31 41 32 Q50 18 64 30 Z',light,4,gold)+path('M42 44 Q64 35 86 44 Q92 72 64 94 Q36 72 42 44 Z',accent,3,gold)+star(64,60,22,glow)+path('M32 57 Q28 63 34 69 M96 57 Q100 63 94 69','none',4,accent),
            # Comet: a heavy bright head with a long tapering diagonal tail.
            path('M24 102 L43 47 L55 59 L66 28 L89 50 L101 65 L71 68 L82 82 Z',light,3,gold)+path('M20 82 L44 56 M40 108 L63 85','none',5,gold)+oval(86,40,22,22,glow,gold,4)+star(86,40,13,light),
            # Vortex: a broad spiral pulls into a dark, empty core.
            path('M28 89 Q6 33 65 23 Q111 16 105 67 Q101 104 52 102 Q19 99 30 61 Q38 34 73 42 Q96 48 83 73 Q74 89 56 75 Q43 64 59 59','none',8,glow)+oval(64,65,10,10,main,gold,3)+path('M18 77 L24 96 L40 85 Z',light,3,gold),
            # Star chain: three large nodes joined by a zigzag arc.
            path('M29 87 L63 33 L98 79','none',7,gold)+star(29,87,21,light)+star(63,33,22,glow)+star(98,79,21,light),
            # Resonance: two equal stars share two vibrating wave bands.
            path('M24 38 Q65 19 104 38 M24 92 Q65 111 104 92','none',5,gold)+star(41,64,28,glow)+star(87,64,28,light)+path('M51 55 Q64 46 77 55 M51 74 Q64 82 77 74','none',4,accent),
            # Patrol: the single companion follows a tilted orbital path.
            oval(64,65,45,28,'none',gold,5)+path('M28 91 Q41 106 65 100','none',5,glow)+star(85,41,20,glow)+star(44,76,24,light)+oval(39,76,2.6,4,main,'none',0)+oval(49,76,2.6,4,main,'none',0)+path('M89 74 L103 81 L106 64 Z',glow,3,gold),
            # Blink: a departing star at the origin and a long forward arrow.
            oval(33,92,21,10,'none',glow,5)+star(33,81,22,light)+path('M44 63 L76 33 L67 28 L101 25 L99 58 L90 49 L56 82 Z',glow,4,gold)+path('M18 53 L30 47 M46 106 L55 100','none',5,gold)
        ]
    return badge+shapes[i-1]

def companion():
    parts=[];states={}
    for row,state in enumerate(['follow','basic','leap','guard','vortex','patrol','chorus']):
        frames=[]
        for f in range(4):
            y=[0,-3,0,3][f]
            shape=f'M64 {22+y} Q72 {47+y} 84 {51+y} Q95 {54+y} 106 {64+y} Q81 {72+y} 77 {85+y} Q73 {97+y} 64 {106+y} Q56 {80+y} 42 {77+y} Q28 {72+y} 22 {64+y} Q45 {57+y} 50 {42+y} Q56 {27+y} 64 {22+y} Z'
            b=path(shape,'#eaf3fe',2,'#9daac4')+oval(55,64+y,4,6,'#55516c','none',0)+oval(73,64+y,4,6,'#55516c','none',0)+path(f'M60 {77+y} Q64 {81+y} 68 {77+y}','none',2,'#9a7a98')
            if state!='follow':
                for j in range(3):b+=star(64+math.cos(j*math.tau/3+f*.35)*48,64+math.sin(j*math.tau/3+f*.35)*48,4+f%2,'#ffdb83')
            if state=='basic':b+=path(f'M16 87 Q27 78 37 {71-f*2}','none',3,'#e4bf6e')
            ox,oy=f*128,row*128;parts.append(f'<g transform="translate({ox} {oy})">{b}</g>');frames.append([ox,oy,128,128])
        states[state]={'regions':frames,'fps':8 if state=='follow' else 12,'loop':state in ['follow','guard','vortex','patrol']}
    folder=ROOT/'assets/characters/mage/companion';folder.mkdir(parents=True,exist_ok=True)
    (folder/'star_companion.svg').write_text(svg(''.join(parts),512,896),encoding='utf-8')
    (folder/'star_companion.json').write_text(json.dumps({'schema_version':1,'hero_id':'CH03','texture':'asset://heroes/ch03_star_companion.svg','states':states,'anchor':[64,64],'body_size':36,'original_art':True},indent=2)+'\n',encoding='utf-8')

def main():
    fragment = ROOT / "assets/characters/role_art_manifest_fragment.json"
    entries = json.loads(fragment.read_text(encoding="utf-8")).get("resources", {}) if fragment.exists() else {}
    for role,(hero,*_) in PALETTES.items():
        production=ROOT/f'assets/characters/{role}/animations/combat_clips.json'
        if not production.exists():
            production.write_text(json.dumps({'schema_version':2,'hero_id':hero,'enabled':False,'production_ready':False,'reason':'awaiting complete approved hand-painted PNG action family','clips':{}},indent=2)+'\n',encoding='utf-8')
        entries[f'heroes/{hero.lower()}_combat_clips.json']=f'res://assets/characters/{role}/animations/combat_clips.json'
        folder=ROOT/f'assets/characters/{role}/skills';folder.mkdir(parents=True,exist_ok=True)
        for i in range(1,13):
            filename=f'sk{i:02}_icon.png'
            if not (folder/filename).is_file():
                raise FileNotFoundError(folder/filename)
            entries[f'skill.{hero.lower()}_sk{i:02}']=f'res://assets/characters/{role}/skills/{filename}'
        (folder/'badge.svg').write_text(svg(icon(role,1),128,128),encoding='utf-8');entries[f'heroes/{hero.lower()}_badge.svg']=f'res://assets/characters/{role}/skills/badge.svg'
        entries[f'characters/{role}/portraits/full_illustration.png']=f'res://assets/characters/{role}/portraits/full_illustration.png'
        entries[f'heroes/{hero.lower()}_storybook_portrait_v1.png']=f'res://assets/characters/{role}/portraits/full_illustration.png'
    companion()
    entries['heroes/ch03_star_companion.svg']='res://assets/characters/mage/companion/star_companion.svg'
    entries['heroes/ch03_star_companion.json']='res://assets/characters/mage/companion/star_companion.json'
    entries['heroes/ch02_mine.svg']='res://assets/characters/gunner/skills/sk08_icon.svg'
    entries['heroes/ch02_sentry.svg']='res://assets/characters/gunner/skills/sk12_icon.svg'
    (ROOT/'assets/characters/role_art_manifest_fragment.json').write_text(json.dumps({'resources':entries},indent=2)+'\n',encoding='utf-8')
    sources={
        'created_date':'2026-10-03',
        'authors':'Project-original hand-painted skill PNGs generated individually with built-in ImageGen; SVG badges and small star companion; character PNGs have separate per-role provenance',
        'rights':'Project-authored original resources; no third-party character pack or traced image used',
        'tool':'tools/art/build_role_combat_art.py',
        'svg_resources':{'skill_icons':0,'role_badges':3,'star_companion_states':7,'body_animations':'none in production','legacy_skill_svg':'Unregistered skill sources; mine/sentry compatibility aliases retained'},
        'handpainted_skill_icons':{'count':36,'tool':'built-in image_gen.imagegen','generation_records':'assets/characters/<role>/skills/skNN_icon.generation.json','native_source_dimensions':[1254,1254],'upscaled':False,'display_pixels_2560x1440':{'pool':84,'equipped':96,'detail':132,'hud':112},'native_2048_source':False},
        'character_bitmaps':{
            'portraits':'assets/characters/<role>/portraits/*.provenance.json or *.generation.json',
            'action_sources':'Latest candidate assets/characters/<role>/animations/basic_southeast_a/b.png and corresponding generation.json',
            'processed_samples':'assets/characters/<role>/animations/basic_southeast_split_review.json; native atlas working copies in ignored tools/godot/art_preview/<role>/split_native',
            'retired_sources':'Old eight-frame and 64-frame candidates with provenance remain in ignored tools/godot/art_preview/<role>/retired_se'},
        'technical_motion':{'status':'retired flat SVG development fixture only','location':'tools/godot/art_preview/<role> (ignored)','registered_in_production_manifest':False},
        'handpainted_motion':{'status':'incomplete southeast review samples; production clips disabled','full_eight_direction_family_ready':False,'native_2k_requirement_met':False},
        'runtime_identity_review':{'CH01':'legacy male warrior bitmap family; redesigned continuous family pending','CH02':'legacy adult female gunner bitmap family; redesigned continuous family pending','CH03':'FAILED: legacy bitmap family is a male engineer, not female Lumi; female portrait and SE review samples do not complete the battle family'},
        'runtime_atlas_limit':2048,'palettes':PALETTES,'manifest_fragment':'role_art_manifest_fragment.json'}
    source_path = ROOT / 'assets/characters/role_art_sources.json'
    if source_path.exists():
        current = json.loads(source_path.read_text(encoding='utf-8'))
        for key in ('created_date', 'authors', 'rights', 'tool', 'svg_resources', 'handpainted_skill_icons', 'palettes', 'manifest_fragment'):
            current[key] = sources[key]
        sources = current
    source_path.write_text(json.dumps(sources,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for source in ROOT.glob('assets/characters/*/skills/*_icon.svg'):ET.parse(source)
    print(f'Generated {len(entries)} original role-art resource entries')

if __name__=='__main__':
    main()
