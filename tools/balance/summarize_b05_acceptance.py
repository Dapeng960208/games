#!/usr/bin/env python3
"""Aggregate clean, exact-seed Boss batches; never turn partial coverage into a pass."""
import argparse, collections, json, pathlib, statistics
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'project.godot').is_file())
def main():
 p=argparse.ArgumentParser();p.add_argument('--mage-candidate',type=int,default=0);p.add_argument('--candidate',type=int,required=True);p.add_argument('--output',type=pathlib.Path);a=p.parse_args()
 found={};sources={};excluded=[]
 for path in sorted((ROOT.parent/'_test_output/B05').glob('*/summary.json')):
  s=json.loads(path.read_text())
  if s.get('calibration_candidate',0)!=a.candidate or s.get('room') or s.get('difficulty')!=4 or s.get('directed_results') is not None:continue
  if s.get('warrior_candidate',0):continue
  if s.get('hero')=='CH03' and s.get('mage_candidate',0)!=a.mage_candidate:continue
  if not s.get('clean_harness') or s.get('source_changes_during_run'):excluded.append(str(path));continue
  data=json.loads((path.parent/'observations.json').read_text());protocol=data['measurement_protocol']
  for row in data['cases']:
   c=row['configuration'];key=(c['hero_id'],c['mix'],c['sample'],c['seed'])
   found[key]=row;sources[key]=str(path.parent)
 groups=[]
 for hero in ['CH01','CH02','CH03']:
  for mix in ['class6','class4','shared6']:
   baseline=[found[(hero,mix,'G2',s)] for s in range(1001,1011) if (hero,mix,'G2',s) in found]
   for sample in ['G2','P5','lowG2']:
    rows=[found[(hero,mix,sample,s)] for s in range(1001,1011) if (hero,mix,sample,s) in found]
    missing=[s for s in range(1001,1011) if (hero,mix,sample,s) not in found]
    times=[r['simulation_seconds'] for r in rows];hp=[r['hp_fraction'] for r in rows]
    wins=sum(r['outcome']=='boss_defeated' and r['hp_fraction']>0 for r in rows)
    g={'hero':hero,'mix':mix,'sample':sample,'missing_seeds':missing,'count':len(rows),'wins':wins,'minimum_active_seconds':min(times,default=None),'maximum_active_seconds':max(times,default=None),'median_active_seconds':statistics.median(times) if times else None,'median_hp':statistics.median(hp) if hp else None,'passed':False}
    if not missing:
     if sample=='G2':g['passed']=wins==10 and min(times)+1e-6>=60 and max(times)-1e-6<=90
     elif sample=='lowG2':g['passed']=wins==10;g['scope']='Inherited survival stress comparison; HP and duration observations only'
     elif len(baseline)==10:
      g['ttk_ratio_to_g2']=statistics.median(times)/statistics.median(r['simulation_seconds'] for r in baseline)
      g['hp_percentage_points_below_g2']=100*(statistics.median(r['hp_fraction'] for r in baseline)-statistics.median(hp))
      g['passed']=wins>=9 and g['ttk_ratio_to_g2']>=1.15
    g['evidence']=sorted({sources[(hero,mix,sample,r['configuration']['seed'])] for r in rows});groups.append(g)
 result={'mage_candidate':a.mage_candidate,'calibration_candidate':a.candidate,'target':'G2 every seed60–90 active seconds; remainingHP recorded only; other qualities explicitly comparative','recorded_unique_boss_cases':len(found),'required_boss_cases':270,'boss_matrix_passed':all(g['passed'] for g in groups),'whole_chapter_accepted':False,'other_requirements':'Ordinary/elite D0–D4, priorgear entry, P3 and real-time rendering need separate verified evidence. This tool never infers them.','excluded_batches':excluded,'groups':groups}
 text=json.dumps(result,indent=2)
 if a.output:a.output.write_text(text)
 else:print(text)
if __name__=='__main__':main()
