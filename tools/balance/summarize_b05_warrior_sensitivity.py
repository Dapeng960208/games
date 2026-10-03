#!/usr/bin/env python3
"""Transparent fixed-versus-legal-counter diagnostics; never accepts a candidate."""
import collections,hashlib,json,pathlib
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def compact(c):
 packets=c['outgoing_packets'];roots=collections.defaultdict(list)
 for p in packets:
  if p.get('target_template')=='B05-ROOT':roots[str(p['target_id'])].append(p)
 times=sorted(set(p['t'] for p in packets if p['amount']>0));samples=c['samples']
 return {'seed':c['configuration']['seed'],'experiment':c['configuration'].get('experiment','frozen'),'outcome':c['outcome'],'active_seconds':c['simulation_seconds'],'hp_record_only':c['hp_fraction'],'phases':c['phases'],'outgoing':c['outgoing'],'casts':c['casts'],'resource_rejections':c['resource_rejections'],'timeline_event_counts':dict(collections.Counter(e['kind'] for e in c['ability_timeline_audit'])),'root_packets':[{'first_hit':min(p['t'] for p in ps),'last_hit':max(p['t'] for p in ps),'packets':len(ps),'skills':dict(collections.Counter(p['skill_slot'] for p in ps))} for ps in roots.values()],'largest_confirmed_damage_gaps':[{'seconds':b-a,'from':a,'to':b} for a,b in sorted(zip(times,times[1:]),key=lambda t:t[1]-t[0],reverse=True)[:5]],'sampled_chain_resets':[{'before':a['t'],'chain_before':a['hit_chain'],'after':b['t'],'chain_after':b['hit_chain']} for a,b in zip(samples,samples[1:]) if a['hit_chain']>=40 and b['hit_chain']<10]}
rows=[];manifests={}
for p in sorted((ROOT.parent/'_test_output/B05').glob('*/observations.json')):
 s=p.parent/'summary.json'
 if not s.exists():continue
 summary=json.loads(s.read_text())
 if summary.get('warrior_candidate',0):continue
 if not summary.get('clean_harness') or summary.get('calibration_candidate')!=7 or summary.get('hero')!='CH01':continue
 d=json.loads(p.read_text());protocol=d['measurement_protocol'];manifests[p.parent.name]=protocol.get('combat_source_sha256',{})
 for c in d['cases']:
  if c['configuration']['seed'] not in [1001,1007,1009] or c['configuration']['sample']!='G2':continue
  rows.append({'run_id':p.parent.name,'raw_sha256':digest(p),**compact(c)})
out={'schema':'b05-warrior-counter-sensitivity-v1','accepted':False,'fixed_build_sha256':digest(ROOT/'docs/levels/b05/balance/evidence/b05_frozen_builds_v1.json'),'policies_predeclared':['frozen','all_skills','q_approach'],'seed_selection':'1001 reference,1007 frozen slowest,1009 frozen fastest; selected before new policy results','rows':rows,'combat_hash_manifests':manifests}
(ROOT/'docs/levels/b05/balance/evidence/b05_warrior_counter_sensitivity_v1.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps([{k:r[k] for k in ['run_id','seed','experiment','active_seconds','outcome']} for r in rows],indent=2))
