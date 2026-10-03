#!/usr/bin/env python3
"""Retain versioned numeric QA evidence, excluding images, saves and disposable logs."""
import hashlib,json,pathlib,re,collections
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
DEST=ROOT/'artifacts/balance/b05/runs'
KEEP=['configuration','outcome','probe','rendering','display_server','pause_seconds','process_frames','simulation_seconds','host_wall_seconds','timing_mode','physics_steps','physics_delta_min','physics_delta_max','hp_fraction','hp_loss','shield_absorbed','effective_player_healing','effective_boss_healing','boss_initial_shield','outgoing','weakpoint_seconds','attackable_seconds','resource_empty_seconds','resource_rejections','casts','cast_failures','phases','phase_skip_details','input_diagnostics','incoming_packets','outgoing_packets','ability_timeline_audit','directed_result','negative_control']
def main():
 DEST.mkdir(exist_ok=True);index=[]
 for folder in sorted((ROOT.parent/'_test_output/B05').iterdir()):
  paths=[folder/'observations.json',folder/'pilot.json']
  for source in paths:
   if not source.exists():continue
   data=json.loads(source.read_text())
   if data.get('controller')!='b05-zero-basic-controller-v1':continue
   summary=json.loads((folder/'summary.json').read_text()) if (folder/'summary.json').exists() else {}
   log=next((p.read_text() for p in [folder/'engine.log',folder/'console.log'] if p.exists()),'')
   errors=bool(re.search(r'SCRIPT ERROR|(?:^|\\n)ERROR:',log,re.M))
   result={'schema':'b05-durable-numeric-evidence-v1','run_id':folder.name,'run_complete':(folder/'.complete').exists(),'raw_report_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_report':str(source.relative_to(ROOT.parent)),'controller':data['controller'],'measurement_protocol':data.get('measurement_protocol',{}),'engine':data.get('engine'),'physics_hz':data.get('physics_hz'),'time_scale':data.get('time_scale'),'checks':data.get('checks'),'failures':data.get('failures',[]),'script_errors_observed':errors,'summary_at_preservation':summary,'invalidated_reason':summary.get('invalidated_reason'),'cases':[]}
   for r in data.get('cases',[]):
    row={k:r[k] for k in KEEP if k in r};fixture=r.get('fixture',{})
    row['fixture_identity']={'case_id':fixture.get('case_id'),'manifest_sha256':data.get('measurement_protocol',{}).get('frozen_manifest_sha256'),'manifest_file':'tests/fixtures/balance/b05_reference_builds.json','controller_policy':fixture.get('controller_policy'),'resolved_stats':fixture.get('resolved_stats'),'skills':fixture.get('skills'),'boss_profile':fixture.get('boss_profile'),'directed_initial_conditions':fixture.get('directed_initial_conditions'),'negative_control_scope':fixture.get('negative_control_scope'),'naked_manifest':fixture.get('manifest') if r.get('configuration',{}).get('sample')=='naked' else None}
    row['enemy_roster']={k:{f:v.get(f) for f in ['template','rank','actor_kind','level','spawn_t','initial_hp','max_hp','actor_damage','armor','magic_resist','initial_shield','last_hp','last_shield','exit_t']} for k,v in r.get('enemy_roster',{}).items()}
    row['samples']=[{k:s.get(k) for k in ['t','hp','shield','resource','boss_hp','boss_shield','phase','player_position','cooldowns','hit_chain','break_stacks','live_enemies']} for s in r.get('samples',[])]
    row['controller_decisions']=r.get('decisions',[])
    row['phase_and_input_events']=[e for e in r.get('events',[]) if e.get('kind') in ['phase_entered','weakpoint_changed','arena_counter','player_request','boss_release']]
    row['actual_enemy_commands']=[{k:c.get(k) for k in ['observed_room_time','action_id','boss_id','caster_enemy_id','damage','damage_type','coefficient','b05_phase','enemy_skill_phase','tell','lock','ruleset_version','enemy_command_version']} for c in r.get('actual_enemy_commands',[])]
    row['direct_arithmetic_audit']=[{k:v for k,v in a.items() if k not in ['attacker_stats','target_states_before','class_passive_before','class_passive_after']}|{'passive_ready_before':a.get('class_passive_before',{}).get('ready')} for a in r.get('direct_audit',[])]
    mana=r.get('mana_ledger',[]);ticks=[m for m in mana if m['kind']=='native_frame_regen'];row['paid_resource_events']=[m for m in mana if m['kind']=='paid_cast_resource']
    buckets=collections.defaultdict(lambda:{'intended':0.,'actual':0.,'overcap':0.,'frames':0})
    for m in ticks:
     b=buckets[int(m['t'])]
     for k in ['intended','actual','overcap']:b[k]+=m[k]
     b['frames']+=1
    row['native_regen_second_buckets']=[{'second':t,**b} for t,b in sorted(buckets.items())]
    row['native_regen_totals']={k:sum(m[k] for m in ticks) for k in ['intended','actual','overcap']}
    result['cases'].append(row)
   target=DEST/(folder.name+'.json');target.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
   index.append({'run_id':folder.name,'path':target.name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'case_count':len(result['cases']),'run_complete':result['run_complete'],'invalidated_reason':result['invalidated_reason'],'script_errors_observed':errors,'clean_harness':summary.get('clean_harness'),'candidate':summary.get('calibration_candidate',data.get('measurement_protocol',{}).get('calibration',{}).get('version'))})
 (DEST/'index.json').write_text(json.dumps({'schema':'b05-evidence-index-v1','runs':index},indent=2)+'\n');print('Preserved',len(index),'numeric reports;',sum(p.stat().st_size for p in DEST.glob('*.json')),'bytes')
if __name__=='__main__':main()
