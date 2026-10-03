#!/usr/bin/env python3
"""B06 lawful real-scene observations; clean harness is never balance acceptance."""
import argparse, hashlib, json, os, pathlib, re, subprocess, sys
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
sys.path.insert(0,str(ROOT/'tools/testing'))
from test_workspace import ensure_managed
from b06_source_dependencies import fingerprint

def main():
 p=argparse.ArgumentParser();p.add_argument('--boss-test-candidate',choices=['none','A','B'],default='none');p.add_argument('--player-level',type=int,choices=[26,30],default=26);p.add_argument('--archive',type=int,choices=[14,15],default=14);p.add_argument('--entry-preflight',action='store_true');p.add_argument('--single-enemy',default='');p.add_argument('--enemy-rank',choices=['normal','elite'],default='normal');p.add_argument('--mage-affix-profile',choices=['frozen','resource_cooldown'],default='frozen');p.add_argument('--counter-policy',choices=['none','drain_pillar'],default='none');p.add_argument('--rendered',action='store_true');p.add_argument('--real-time',action='store_true');p.add_argument('--screenshots',action='store_true');p.add_argument('--heroes',default='CH01,CH02,CH03');p.add_argument('--mix',choices=['class6','class4','shared6'],default='class6');p.add_argument('--samples',default='G2,P5');p.add_argument('--seeds',default='1001');p.add_argument('--difficulties',default='4');p.add_argument('--room',default='');p.add_argument('--max-seconds',type=int,default=180);a=p.parse_args()
 ensure_managed('B06');out=pathlib.Path(os.environ['GAMES_TEST_OUTPUT_DIR'])
 sources=fingerprint()
 protocol={'schema':'s11-controlled-matrix-v2','protocol_pinned':True,'target':'G2 Boss60–90sec; HP recorded only; naked ordinary danger separate','controller_version':'b06-zero-basic-controller-v1','counter_policy':'visible hazard avoidance; no optional drain/pillar optimization in pilot','seeds':list(map(int,a.seeds.split(','))),'max_seconds':a.max_seconds,'timing_mode':'real_time' if a.real_time else 'fixed_fps','display_mode':'gpu' if a.rendered else 'headless','probe':False,'capture_policy':'gpu_start_end_outside_combat' if a.screenshots else 'none','requested_audio_driver':'Dummy','calibration':json.loads((ROOT/'data/rules/numerical.json').read_text())['enemy_calibration'],'source_sha256':sources,'dependency_scope':'Transitive res:// and production global-class closure from test scene and autoloads, including JSON paths supplied to production data registries and runner sources. Excludes documents, unrelated tests and asset pixel contents.','mixed_power_SU6':'undefined; not tested or passed','production_gate':'unchanged; debug candidate only'}
 protocol['calibration']['version']=a.archive
 protocol['player_level']=a.player_level
 protocol['entry_preflight']=a.entry_preflight
 protocol['boss_test_candidate']=a.boss_test_candidate
 (out/'protocol.json').write_text(json.dumps(protocol,indent=2))
 cmd=['godot',* ([] if a.rendered else ['--headless']),'--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility',* (['--max-fps','60'] if a.real_time else ['--fixed-fps','60']),'res://tests/levels/b06/test_b06_balance_matrix.tscn','--','--candidate-b06','--test-profile=user://test_b06_candidate/balance/baseline.json',f'--max-seconds={a.max_seconds}',f'--heroes={a.heroes}',f'--mix={a.mix}',f'--samples={a.samples}',f'--seeds={a.seeds}',f'--difficulties={a.difficulties}',f'--output={out}/observations.json',f'--manifest-output={out}/manifest.json',f'--protocol-file={out}/protocol.json']
 cmd.append('--boss-test-candidate='+a.boss_test_candidate)
 cmd.append('--player-level='+str(a.player_level))
 if a.archive==15:cmd.append('--enemy-species-candidate=15')
 if a.entry_preflight:cmd.append('--entry-preflight=true')
 cmd.append('--timing-mode='+protocol['timing_mode'])
 cmd.append('--counter-policy='+a.counter_policy)
 cmd.append('--mage-affix-profile='+a.mage_affix_profile)
 protocol['mage_affix_profile']=a.mage_affix_profile
 protocol['counter_policy']=a.counter_policy
 (out/'protocol.json').write_text(json.dumps(protocol,indent=2))
 if a.screenshots:cmd.append('--capture-directory='+str(out/'screenshots'))
 if a.room:cmd.append('--room-id='+a.room)
 if a.single_enemy:cmd.extend(['--single-enemy='+a.single_enemy,'--enemy-rank='+a.enemy_rank])
 r=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=3600)
 (out/'engine.log').write_text(r.stdout);print(r.stdout)
 (out/'engine_exit.json').write_text(json.dumps({'returncode':r.returncode,'signal':-r.returncode if r.returncode<0 else None},indent=2))
 report=json.loads((out/'observations.json').read_text()) if (out/'observations.json').exists() else {};cases=report.get('cases',[])
 after=fingerprint()
 changed=[f for f in sorted(set(sources)|set(after)) if sources.get(f)!=after.get(f)]
 clean=r.returncode==0 and not re.search(r'SCRIPT ERROR|^ERROR:',r.stdout,re.M) and not report.get('failures') and len(cases)==len(a.heroes.split(','))*len(a.samples.split(','))*len(a.seeds.split(','))*len(a.difficulties.split(','))
 if a.entry_preflight:
  clean=clean and not changed and all(c.get('preflight_only') and c.get('crit_policy_version')==1 and c.get('critical_hp_loss',0)>c.get('normal_hp_loss',0)>0 for c in cases)
  (out/'summary.json').write_text(json.dumps({'engine_returncode':r.returncode,'clean_harness':clean,'source_changes':changed,'preflight_only':True,'checks':report.get('checks'),'cases':[{k:c.get(k) for k in ['configuration','normal_hp_loss','critical_hp_loss','crit_chance','crit_multiplier','crit_policy_version']} for c in cases]},indent=2));return 0 if clean else 1
 clean=clean and not changed and all(c['configuration']['hero_id']!='CH03' or (c['input_diagnostics']['actual_shots']==0 and not c['casts'].get('attack',0)) for c in cases)
 summary={'engine_returncode':r.returncode,'clean_harness':clean,'source_changes':changed,'no_balance_acceptance_claim':True,'cases':[{'config':c['configuration'],'outcome':c['outcome'],'active_seconds':c['simulation_seconds'],'hp_fraction':c['hp_fraction'],'hits':c['negative_control']['effective_received_hits'],'shield_absorbed':c['shield_absorbed'],'hp_loss':c['hp_loss'],'kills':c['negative_control']['kills']} for c in cases]}
 (out/'summary.json').write_text(json.dumps(summary,indent=2));print('B06_BASELINE_SUMMARY',json.dumps(summary));return 0 if clean else 1
if __name__=='__main__':raise SystemExit(main())
