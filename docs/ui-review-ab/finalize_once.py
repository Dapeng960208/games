from pathlib import Path
import ast
p=Path(__file__).resolve().parent/'source/render.py'
s=p.read_text(encoding='utf-8')
s=s.replace("rarity,color=RARITIES[(idx+1)%4]", "rarity,color=RARITIES[2 if idx==0 else (idx+1)%4]")
s=s.replace("str(idx%5),16,INK,align='right')", "str(3 if idx==0 else idx%5),16,INK,align='right')")
a="""def world(i=0):
    if not WORLD_PATHS: return Image.new('RGBA',(W,H),'#d9d6b3')
    return opened(str(WORLD_PATHS[i % len(WORLD_PATHS)].relative_to(ROOT)))"""
b="""def world(i=0):
    # Pick actual chapter entry rooms, not arbitrary alphabetical atlas offsets.
    room = {0:'L01',7:'L07',14:'L13',21:'L19',100:'BO01'}.get(i,'L01')
    exact = ROOT / ('assets/generated/world/rooms/'+room+'_environment_v1.png')
    if exact.exists(): return opened(str(exact.relative_to(ROOT)))
    if not WORLD_PATHS: return Image.new('RGBA',(W,H),'#d9d6b3')
    return opened(str(WORLD_PATHS[i % len(WORLD_PATHS)].relative_to(ROOT)))"""
if a in s: s=s.replace(a,b,1)
s=s.replace("c.image=ImageOps.fit(world(0).convert('RGBA'),(W,H),method=Image.Resampling.LANCZOS)","c.image=ImageOps.fit(world(100 if mode==2 else 0).convert('RGBA'),(W,H),method=Image.Resampling.LANCZOS)")
ast.parse(s); p.write_text(s,encoding='utf-8')
print('Selected item rarity/rank and chapter scenery synchronized.')
