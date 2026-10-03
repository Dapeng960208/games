#!/usr/bin/env python3
"""Complete a fixed stage in small managed batches; retain every failure.
Do not put this orchestration process under test_workspace (its children own locks).
"""
import argparse,hashlib,json,os,pathlib,subprocess,sys
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
HEROES=['CH01','CH02','CH03'];MIXES=['class6','class4','shared6'];SAMPLES=['G2','P5','lowG2'];SEEDS=list(range(1001,1011))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def collect(candidate,mage,warrior=0):
 rows={};build=sha(ROOT/'docs/levels/b05/balance/evidence/b05_frozen_builds_v1.json');controller=sha(ROOT/'tests/support/b05_balance_controller.gd')
 for p in sorted((ROOT.parent/'_test_output/B05').glob('*/summary.json')):
  s=json.loads(p.read_text())
  if s.get('hero')=='CH01' and s.get('warrior_candidate',0)!=warrior:continue
  if s.get('calibration_candidate')!=candidate or not s.get('clean_harness') or s.get('invalidated_reason') or s.get('source_changes_during_run'):continue
  if s.get('room') or s.get('directed_results') is not None or s.get('difficulty')!=4:continue
  data=json.loads((p.parent/'observations.json').read_text());protocol=data.get('measurement_protocol',{})
  if protocol.get('frozen_manifest_sha256')!=build or protocol.get('source_sha256',{}).get('tests/support/b05_balance_controller.gd')!=controller:continue
  for r in data['cases']:
   c=r['configuration'];h=c['hero_id'];sample=c['sample'];mix=c['mix'];seed=c['seed']
   if h not in HEROES or sample not in SAMPLES or mix not in MIXES or seed not in SEEDS or c.get('experiment'):continue
   if h=='CH03' and int(r['fixture']['resolved_stats'].get('mage_balance_candidate',0))!=mage:continue
   if int(r['fixture']['boss_profile'].get('enemy_calibration_snapshot',{}).get('version',0))!=candidate or not r.get('actual_enemy_commands'):continue
   rows[(h,mix,sample,seed)]={'hero':h,'mix':mix,'sample':sample,'seed':seed,'active_seconds':r['simulation_seconds'],'outcome':r['outcome'],'hp_record_only':r['hp_fraction'],'resource_zero_seconds':r['resource_empty_seconds'],'casts':r['casts'],'run_id':p.parent.name,'report_sha256':sha(p.parent/'observations.json'),'g2_gate':sample=='G2' and r['outcome']=='boss_defeated' and r['hp_fraction']>0 and 60-1e-6<=r['simulation_seconds']<=90+1e-6}
 return rows
def main():
 p=argparse.ArgumentParser();p.add_argument('--warrior-candidate',type=int,choices=[0,1],default=0);p.add_argument('--candidate',type=int,required=True);p.add_argument('--mage-candidate',type=int,default=1);p.add_argument('--stage',choices=['class6','standard','comparisons'],default='class6');p.add_argument('--batch-size',type=int,default=2);a=p.parse_args()
 if os.environ.get('GAMES_TEST_RUN_ID'):raise SystemExit('Children own the managed locks; invoke orchestrator directly.')
 if not 1<=a.batch_size<=3:raise SystemExit('Bound batches to1–3seeds.')
 prefix=ROOT/f'docs/levels/b05/balance/evidence/b05_matrix_c{a.candidate}_m{a.mage_candidate}{"_w"+str(a.warrior_candidate) if a.warrior_candidate else ""}'
 plan={'schema':'b05-fixed-matrix-plan-v1','candidate':a.candidate,'mage_candidate':a.mage_candidate,'heroes':HEROES,'mixes':MIXES,'samples':SAMPLES,'seeds':SEEDS,'required_boss_cases':270,'g2_target':'every seed60–90active seconds and alive victory; HP record only','controller_sha256':sha(ROOT/'tests/support/b05_balance_controller.gd'),'frozen_build_sha256':sha(ROOT/'docs/levels/b05/balance/evidence/b05_frozen_builds_v1.json'),'no_gear_or_controller_changes':True}
 if a.warrior_candidate:plan['warrior_candidate']=a.warrior_candidate
 planpath=pathlib.Path(str(prefix)+'_plan.json')
 if planpath.exists() and json.loads(planpath.read_text())!=plan:raise SystemExit('Frozen plan changed; create a new plan version.')
 planpath.write_text(json.dumps(plan,indent=2)+'\n')
 resultpath=pathlib.Path(str(prefix)+f'_{a.stage}.json')
 selected=[(h,m,s,seed) for s in (['P5','lowG2'] if a.stage=='comparisons' else ['G2']) for m in (['class6'] if a.stage=='class6' else MIXES) for h in HEROES for seed in SEEDS]
 def save(rows,status):
  selectedrows=[rows[k] for k in selected if k in rows];missing=[k for k in selected if k not in rows];fail=[r for r in selectedrows if r['sample']=='G2' and not r['g2_gate']]
  result={'schema':'b05-fixed-matrix-stage-v1','candidate':a.candidate,'mage_candidate':a.mage_candidate,'stage':a.stage,'status':status,'required':len(selected),'recorded':len(selectedrows),'missing':missing,'g2_failed_rows':fail,'complete':not missing,'stage_g2_pass':not missing and not fail if a.stage!='comparisons' else None,'whole_chapter_accepted':False,'rows':selectedrows}
  resultpath.write_text(json.dumps(result,indent=2)+'\n');return result
 rows=collect(a.candidate,a.mage_candidate,a.warrior_candidate);save(rows,'running')
 for sample in (['P5','lowG2'] if a.stage=='comparisons' else ['G2']):
  for mix in (['class6'] if a.stage=='class6' else MIXES):
   for hero in HEROES:
    missing=[s for s in SEEDS if (hero,mix,sample,s) not in rows]
    for i in range(0,len(missing),a.batch_size):
     batch=missing[i:i+a.batch_size];print('MATRIX_BATCH',a.candidate,hero,mix,sample,batch,flush=True)
     cmd=[sys.executable,str(ROOT/'tools/balance/run_b05_acceptance.py'),'--candidate',str(a.candidate),'--hero',hero,'--mix',mix,'--sample',sample,'--seeds',','.join(map(str,batch)),'--max-seconds','240','--host-timeout','150']
     if hero=='CH01' and a.warrior_candidate:cmd+=['--warrior-candidate',str(a.warrior_candidate)]
     if hero=='CH03' and a.mage_candidate:cmd+=['--mage-candidate',str(a.mage_candidate)]
     status=subprocess.run(cmd,cwd=ROOT).returncode;rows=collect(a.candidate,a.mage_candidate,a.warrior_candidate);save(rows,'running')
     if status or any((hero,mix,sample,s) not in rows for s in batch):save(rows,'blocked_invalid_batch');raise SystemExit('Inspect incomplete/invalid batch; no silent retry.')
    summary=save(rows,'running');print('MATRIX_GROUP_COMPLETED',hero,mix,sample,'failed_g2_rows',len(summary['g2_failed_rows']),flush=True)
 result=save(rows,'completed');print('MATRIX_STAGE_RESULT',json.dumps({k:v for k,v in result.items() if k!='rows'}),flush=True)
if __name__=='__main__':main()
