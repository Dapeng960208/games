#!/usr/bin/env python3
"""One natural first-four route attempt per managed engine lock, no injected damage."""
import argparse,json,os,pathlib,re,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from test_workspace import ensure_managed
from first_four_source_dependencies import fingerprint

def main():
 p=argparse.ArgumentParser();p.add_argument('--chapter',type=int,choices=range(1,5),required=True);p.add_argument('--difficulty',type=int,choices=range(5),required=True);p.add_argument('--equipment',choices=['naked','green0','G2','P5'],default='naked');p.add_argument('--hero',choices=['CH01','CH02','CH03'],required=True);p.add_argument('--seed',type=int,default=1001);p.add_argument('--max-seconds',type=int,default=3600);p.add_argument('--parse-only',action='store_true');a=p.parse_args()
 ensure_managed('B05');out=pathlib.Path(os.environ['GAMES_TEST_OUTPUT_DIR']);before=fingerprint()
 cmd=['godot','--headless','--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--fixed-fps','60']
 if a.parse_only:cmd+=['res://tests/test_first_four_natural_chapter.tscn','--','--enemy-species-candidate=15','--test-profile=user://test_first_four_natural_chapter/parse.json','--parse-only=true']
 else:cmd+=['res://tests/test_first_four_natural_chapter.tscn','--','--enemy-species-candidate=15','--test-profile=user://test_first_four_natural_chapter/route.json',f'--hero={a.hero}',f'--chapter={a.chapter}',f'--difficulty={a.difficulty}',f'--equipment={a.equipment}',f'--seed={a.seed}','--mode=chapter',f'--max-seconds={a.max_seconds}',f'--output={out}/observations.json']
 (out/'protocol.json').write_text(json.dumps({'schema':'first-four-natural-route-v1','source_sha256':before,'command':cmd,'no_universal_seed_claim':True},indent=2))
 r=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=7200)
 (out/'engine.log').write_text(r.stdout);print(r.stdout)
 after=fingerprint();changed=[f for f in sorted(set(before)|set(after)) if before.get(f)!=after.get(f)]
 report=json.loads((out/'observations.json').read_text()) if (out/'observations.json').exists() else {}
 clean=r.returncode==0 and not re.search(r'SCRIPT ERROR|^ERROR:',r.stdout,re.M) and not report.get('failures') and not changed and (a.parse_only or bool(report))
 summary={'clean_harness':clean,'source_changes':changed,'chapter':a.chapter,'entry_level':(a.chapter-1)*5+1,'difficulty':a.difficulty,'equipment':a.equipment,'hero':a.hero,'seed':a.seed,'outcome':report.get('outcome'),'active_seconds':report.get('active_seconds'),'kills':report.get('kills'),'hits':report.get('effective_received_hits'),'hp_loss':report.get('hp_loss'),'shield_absorbed':report.get('shield_absorbed'),'final_hp':report.get('final_hp'),'basic_shots':report.get('basic_shots_total'),'empty_equipment_verified':report.get('empty_equipment_verified'),'rooms':[{k:v for k,v in x.items() if k in ['room_id','outcome','active_seconds','kills','hp_loss','shield_absorbed','effective_received_hits','end_hp','native_net_healing_inferred']} for x in report.get('rooms',[])]}
 (out/'summary.json').write_text(json.dumps(summary,indent=2));print('FIRST_FOUR_NATURAL_ROUTE_SUMMARY',json.dumps(summary));return 0 if clean else 1
if __name__=='__main__':raise SystemExit(main())
