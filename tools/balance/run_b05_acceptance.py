#!/usr/bin/env python3
"""One bounded, serialized actual-scene batch. Zero exit means clean harness, not balance pass."""
import argparse, hashlib, json, os, pathlib, re, statistics, subprocess, sys, time, resource
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
sys.path.insert(0,str(ROOT/'tools/testing'))
from test_workspace import ensure_managed
from b05_source_dependencies import fingerprint

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--boss-test-candidate',choices=['','A','B'],default='');p.add_argument('--hero-level',type=int,choices=[21,25],default=21);p.add_argument('--mage-affix-profile',choices=['frozen','resource_cooldown'],default='frozen');p.add_argument('--manifest-reference',default='docs/levels/b05/balance/evidence/b05_frozen_builds_v1.json');p.add_argument('--warrior-candidate',type=int,choices=[0,1],default=0);p.add_argument('--screenshots',action='store_true');p.add_argument('--counter-policy',choices=['frozen','all_skills','q_approach'],default='frozen');p.add_argument('--mage-candidate',type=int,choices=[0,1],default=0);p.add_argument('--single-enemy',default='');p.add_argument('--hit-pressure',action='store_true');p.add_argument('--max-seconds',type=int,default=180);p.add_argument('--candidate',type=int,choices=[0,2,3,4,5,6,7,8,9,10,11,12,15],default=0);p.add_argument('--p3',action='store_true');p.add_argument('--hero',default='CH01');p.add_argument('--mix',default='class6',choices=['class6','class4','shared6']);p.add_argument('--sample',default='G2',choices=['G2','P5','lowG2','naked']);p.add_argument('--seeds',default=','.join(map(str,range(1001,1011))));p.add_argument('--room',default='');p.add_argument('--difficulty',type=int,default=4);p.add_argument('--real-time',action='store_true');p.add_argument('--rendered',action='store_true');p.add_argument('--host-timeout',type=int,default=240);a=p.parse_args()
 ensure_managed('B05');out=pathlib.Path(os.environ['GAMES_TEST_OUTPUT_DIR'])
 entry='tests/levels/b05/test_b05_p3_tolerance.tscn' if a.p3 else 'tests/levels/b05/test_b05_counter_skill_sensitivity.tscn' if a.counter_policy!='frozen' else 'tests/levels/b05/test_b05_balance_matrix.tscn'
 sources=fingerprint(entry)
 exclusions={'scripts/levels/b05/world/floor_repair.gd':'Read-only geometry-to-shader Sprite2D overlay; only instantiated by native MineBackdrop, replaced by the headless test backdrop. No collider/actor/AI/state writes.'} if not a.rendered else {}
 combat_sources={f:v for f,v in sources.items() if f not in exclusions}
 protocol={'target_revision':'user-2026-10-02T16:31:36-G2-BossTTK-60-to90-HP-record-only','schema':'s11-controlled-matrix-v2','counter_policy':a.counter_policy,'boss_test_candidate':a.boss_test_candidate,'mage_candidate':a.mage_candidate,'mage_affix_profile':a.mage_affix_profile,'warrior_candidate':a.warrior_candidate,'protocol_pinned':True,'seeds':list(map(int,a.seeds.split(','))),'max_seconds':a.max_seconds,'timing_mode':'real_time' if a.real_time else 'fixed_fps','display_mode':'gpu' if a.rendered else 'headless','probe':False,'capture_policy':'gpu_start_end_outside_combat' if a.screenshots else 'none','controller_version':'b05-zero-basic-controller-v1','requested_audio_driver':'Dummy','calibration':json.loads((ROOT/'data/rules/numerical.json').read_text())['enemy_calibration'],'source_sha256':sources,'combat_source_sha256':combat_sources,'noncombat_source_exclusions':exclusions,'frozen_manifest_sha256':sha(ROOT/a.manifest_reference)}
 if a.candidate:
  protocol['calibration']['version']=a.candidate
  if a.candidate!=15:protocol['calibration']['chapters']['B05']={r:{'hp':{2:4.4,3:9.,4:9.,5:8.5,6:8.3,7:8.7,8:8.9,9:8.2,10:1.0,11:1.0,12:1.0}[a.candidate] if r=='boss' else 1.,'attack':{10:1.35,11:2.5,12:3.5}[a.candidate] if a.candidate in [10,11,12] and r in ['normal','elite'] else .35 if a.candidate==3 and r=='boss' else 1.,'skill':1.} for r in ['normal','elite','boss']}
 (out/'protocol.json').write_text(json.dumps(protocol,indent=2))
 cmd=['godot',* ([] if a.rendered else ['--headless']),'--path',str(ROOT),'--audio-driver','Dummy',*(['--max-fps','60'] if a.real_time else ['--fixed-fps','60']),('res://tests/levels/b05/test_b05_p3_tolerance.tscn' if a.p3 else 'res://tests/levels/b05/test_b05_counter_skill_sensitivity.tscn' if a.counter_policy!='frozen' else 'res://tests/levels/b05/test_b05_balance_matrix.tscn'),'--','--candidate-b05','--test-profile=user://test_b05_candidate/balance/acceptance.json',f'--max-seconds={a.max_seconds}',f'--heroes={a.hero}',f'--mix={a.mix}',f'--samples={a.sample}',f'--seeds={a.seeds}',f'--difficulties={a.difficulty}',f'--output={out}/observations.json',f'--manifest-output={out}/manifest.json',f'--protocol-file={out}/protocol.json','--timing-mode='+protocol['timing_mode']]
 cmd.append('--mage-affix-profile='+a.mage_affix_profile)
 cmd.append('--hero-level='+str(a.hero_level))
 if a.boss_test_candidate:cmd.append('--boss-test-candidate='+a.boss_test_candidate)
 if a.screenshots:cmd.append("--capture-directory="+str(out/"screenshots"))
 if a.counter_policy!="frozen":cmd.append("--counter-policy="+a.counter_policy)
 if a.warrior_candidate:cmd.append("--warrior-balance-candidate="+str(a.warrior_candidate))
 if a.mage_candidate:cmd.append("--mage-balance-candidate="+str(a.mage_candidate))
 if a.candidate:cmd.append('--b05-balance-candidate='+str(a.candidate))
 if a.single_enemy:cmd.append("--single-enemy="+a.single_enemy)
 if a.hit_pressure:cmd.append("--hit-pressure=true")
 if a.room:cmd.append('--room-id='+a.room)
 memory_before=pathlib.Path("/proc/meminfo").read_text() if pathlib.Path("/proc/meminfo").exists() else "unavailable"
 start=time.monotonic()
 try:r=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=a.host_timeout)
 except subprocess.TimeoutExpired as e:
  (out/'engine.log').write_text(str(e.stdout));print('HOST WATCHDOG: incomplete batch; no acceptance');return 2
 (out/'engine.log').write_text(r.stdout);print(r.stdout)
 clean=r.returncode==0 and not re.search(r'SCRIPT ERROR|^ERROR:',r.stdout,re.M)
 report=json.loads((out/'observations.json').read_text()) if (out/'observations.json').exists() else {}
 cases=report.get('cases',[]);clean=clean and not report.get('failures') and len(cases)==len(protocol['seeds'])
 if (out/'manifest.json').exists():clean=clean and sha(out/'manifest.json')==protocol['frozen_manifest_sha256']
 for row in cases:
  if row['configuration']['hero_id']=='CH03':clean=clean and row['casts'].get('attack',0)==0 and row['input_diagnostics']['actual_shots']==0
 after_sources=fingerprint(entry)
 source_changes=[f for f in sorted(set(combat_sources)|set(after_sources)) if f not in exclusions and combat_sources.get(f)!=after_sources.get(f)]
 clean=clean and not source_changes
 summary={'schema':'b05-strength-batch-v1','clean_harness':clean,'engine_returncode':r.returncode,'engine_signal':-r.returncode if r.returncode<0 else None,'children_max_rss_kib':resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,'counter_policy':a.counter_policy,'boss_test_candidate':a.boss_test_candidate,'mage_candidate':a.mage_candidate,'mage_affix_profile':a.mage_affix_profile,'warrior_candidate':a.warrior_candidate,'calibration_candidate':a.candidate,'hero':a.hero,'hero_level':a.hero_level,'mix':a.mix,'sample':a.sample,'room':a.room,'difficulty':a.difficulty,'seeds':protocol['seeds'],'wins':sum(x['outcome'] in ['boss_defeated','room_cleared'] for x in cases),'single_actor_defeats':sum(x['outcome']=='single_actor_defeated' for x in cases),'count':len(cases),'minimum_active_seconds':min((x['simulation_seconds'] for x in cases),default=None),'maximum_active_seconds':max((x['simulation_seconds'] for x in cases),default=None),'median_active_seconds':statistics.median(x['simulation_seconds'] for x in cases) if cases else None,'median_end_hp':statistics.median(x['hp_fraction'] for x in cases) if cases else None,'host_seconds':time.monotonic()-start,'measurement':'Active native60Hz simulation includes approach, mechanics, immunity, recovery and healing. Host seconds separate. Automated input, not human play.','source_changes_during_run':source_changes,'noncombat_source_changes':[f for f,v in sources.items() if f in exclusions and sha(ROOT/f)!=v]}
 if a.p3: summary['directed_results']=[r.get('directed_result',{}) for r in cases]
 if cases and not a.p3 and a.counter_policy=='frozen' and not a.room and a.difficulty==4:
  if a.sample=='G2':summary['absolute_gate']=clean and summary['wins']==10 and summary['minimum_active_seconds']+1e-6>=60 and summary['maximum_active_seconds']-1e-6<=90
  elif a.sample=='lowG2':summary['absolute_gate']=clean and summary['wins']==10 and True
  elif a.sample=='P5':summary['paired_gate']='Requires corresponding G2 group: at least9 wins AND (inherited TTK>=1.15G2 comparator; HP now record-only).'
 (out/'resource_diagnostics.json').write_text(json.dumps({'memory_before':memory_before,'memory_after':pathlib.Path('/proc/meminfo').read_text() if pathlib.Path('/proc/meminfo').exists() else 'unavailable','children_max_rss_kib':resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,'engine_returncode':r.returncode},indent=2))
 (out/'summary.json').write_text(json.dumps(summary,indent=2));print('B05_BATCH_SUMMARY',json.dumps(summary));return 0 if clean else 1
if __name__=='__main__':raise SystemExit(main())
