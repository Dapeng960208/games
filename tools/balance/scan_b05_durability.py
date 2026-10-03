#!/usr/bin/env python3
"""Frozen small sentinel grid. Each child batch obtains/releases the managed lock.
Do NOT wrap this orchestration script in test_workspace: children own the lease.
"""
import hashlib,json,os,pathlib,subprocess,sys
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
POINTS=[(9,8.2),(6,8.3),(5,8.5),(7,8.7),(8,8.9),(4,9.0)]
SENTINELS={'CH01':[1001,1004],'CH02':[1001,1008],'CH03':[1001]}
PLAN=ROOT/'docs/levels/b05/balance/evidence/b05_durability_scan_v1_plan.json'
RESULT=ROOT/'docs/levels/b05/balance/evidence/b05_durability_scan_v1_results.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def collect():
 rows={}
 for path in sorted((ROOT.parent/'_test_output/B05').glob('*/summary.json')):
  summary=json.loads(path.read_text())
  if summary.get('warrior_candidate',0):continue
  if not summary.get('clean_harness') or summary.get('source_changes_during_run') or summary.get('invalidated_reason'):continue
  if summary.get('room') or summary.get('sample')!='G2' or summary.get('mix')!='class6' or summary.get('difficulty')!=4:continue
  candidate=summary.get('calibration_candidate'); points=dict(POINTS)
  if candidate not in points:continue
  data=json.loads((path.parent/'observations.json').read_text());protocol=data.get('measurement_protocol',{})
  if protocol.get('frozen_manifest_sha256')!=sha(ROOT/'docs/levels/b05/balance/evidence/b05_frozen_builds_v1.json'):continue
  if protocol.get('source_sha256',{}).get('tests/support/b05_balance_controller.gd')!=sha(ROOT/'tests/support/b05_balance_controller.gd'):continue
  for r in data['cases']:
   c=r['configuration'];hero=c['hero_id'];seed=c['seed'];fixture=r['fixture'];stats=fixture['resolved_stats'];boss=fixture['boss_profile']
   if hero not in SENTINELS or seed not in SENTINELS[hero] or c.get('experiment'):continue
   if hero=='CH03' and int(stats.get('mage_balance_candidate',0))!=1:continue
   if abs(boss.get('hp_calibration',0)-points[candidate])>1e-9 or boss.get('attack_calibration')!=1:continue
   if not r.get('actual_enemy_commands'):continue
   rows[(candidate,hero,seed)]={'candidate':candidate,'hp_factor':points[candidate],'hero':hero,'seed':seed,'seconds':r['simulation_seconds'],'physics_steps':r['physics_steps'],'outcome':r['outcome'],'ending_hp_record_only':r['hp_fraction'],'passed_sentinel':r['outcome']=='boss_defeated' and r['hp_fraction']>0 and 60-1e-6<=r['simulation_seconds']<=90+1e-6,'run_id':path.parent.name,'raw_report_sha256':sha(path.parent/'observations.json'),'controller_sha256':protocol['source_sha256']['tests/support/b05_balance_controller.gd'],'build_manifest_sha256':protocol['frozen_manifest_sha256'],'reuse_note':'Exact archived actor factors, frozen build checksum and controller hash; full original per-run source manifests retained.'}
 return rows
def save(rows):
 result={'schema':'b05-durability-sentinel-scan-v1','scope':'Five fixed class6 G2 sentinels per shared coefficient; sampled points only, not a proven continuous interval or full matrix.','floating_representation_tolerance_seconds':1e-6,'rows':list(rows.values()),'points':[]}
 for candidate,hp in POINTS:
  values=[rows.get((candidate,h,s)) for h,seeds in SENTINELS.items() for s in seeds]
  complete=all(v is not None for v in values); result['points'].append({'candidate':candidate,'hp_factor':hp,'complete':complete,'all_five_sentinels_pass':complete and all(v['passed_sentinel'] for v in values),'minimum_seconds':min((v['seconds'] for v in values if v),default=None),'maximum_seconds':max((v['seconds'] for v in values if v),default=None)})
 RESULT.write_text(json.dumps(result,indent=2)+'\n');return result
def main():
 if os.environ.get('GAMES_TEST_RUN_ID'):raise SystemExit('Run scan orchestration outside managed wrapper; children acquire it.')
 plan={'schema':'b05-durability-sentinel-scan-plan-v1','frozen_before_new_grid_runs':True,'points':dict(POINTS),'sentinels':SENTINELS,'sample':'G2','mix':'class6','difficulty':4,'boss_attack_factor':1,'mage_candidate':1,'new_points_at_plan_freeze':[8.2,8.7,8.9],'previously_measured_points':[8.3,8.5,9.0],'no_gear_controller_warning_phase_or_combo_changes':True}
 if PLAN.exists() and json.loads(PLAN.read_text())!=json.loads(json.dumps(plan)):raise SystemExit('Existing frozen plan differs; create a new version instead.')
 PLAN.write_text(json.dumps(plan,indent=2)+'\n')
 rows=collect();save(rows)
 for candidate,hp in POINTS:
  for hero,seeds in SENTINELS.items():
   missing=[s for s in seeds if (candidate,hero,s) not in rows]
   if not missing:continue
   print('SCAN_BATCH',candidate,hp,hero,missing,flush=True)
   cmd=[sys.executable,str(ROOT/'tools/balance/run_b05_acceptance.py'),'--candidate',str(candidate),'--hero',hero,'--seeds',','.join(map(str,missing)),'--max-seconds','180','--host-timeout','120']
   if hero=='CH03':cmd+=['--mage-candidate','1']
   status=subprocess.run(cmd,cwd=ROOT).returncode
   rows=collect();save(rows)
   if status or any((candidate,hero,s) not in rows for s in missing):raise SystemExit('Batch incomplete or invalid; inspect rather than silently retry.')
 result=save(rows);print('SCAN_RESULT',json.dumps(result['points']),flush=True)
if __name__=='__main__':main()
