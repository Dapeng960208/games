#!/usr/bin/env python3
"""Staged small acceptance plan. Never runs before explicit frozen source review.
A plan is printed by default. A caller selects one stage, not an automatic matrix.
"""
import argparse,hashlib,json,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
RUNNER=ROOT/'tools/balance/run_b06_baseline.py'

from b06_source_dependencies import fingerprint

def plan():
 base=['--seeds','1001','--max-seconds','150']
 normal=['--room','L31','--difficulties','0','--samples','naked_entry']
 stages={
 'boss15_minimum_preflight':[['--archive','15','--player-level','26','--samples','G2','--mix','class6','--difficulties','4','--mage-affix-profile','resource_cooldown','--entry-preflight']],
 'boss15_minimum_g2':[['--archive','15','--player-level','26','--samples','G2','--mix','class6','--difficulties','4','--mage-affix-profile','resource_cooldown']],
 'boss15_minimum_A':[['--archive','15','--player-level','26','--samples','G2','--mix','class6','--difficulties','4','--mage-affix-profile','resource_cooldown','--boss-test-candidate','A']],
 'naked_room':[normal],
 # Native AI with a single real actor, explicitly not natural wave evidence.
 'naked_representatives':[[*normal,'--single-enemy',enemy,'--enemy-rank',rank] for enemy,rank in [('B06-M01','normal'),('B06-M03','elite')]],
 'boss_g2':[['--samples','G2','--mix','class6','--difficulties','4','--mage-affix-profile','resource_cooldown']],
 'boss_p5':[['--samples','P5','--mix','class6','--difficulties','4','--mage-affix-profile','resource_cooldown']],
 'ordinary_representatives':[['--room','L31','--samples','G2','--mix','class6','--difficulties','0,4','--single-enemy',enemy,'--enemy-rank',rank,'--mage-affix-profile','resource_cooldown'] for enemy,rank in [('B06-M01','normal'),('B06-M03','elite')]],
 'boss_mix_boundary':[['--samples','G2,P5','--mix',mix,'--difficulties','4','--mage-affix-profile','resource_cooldown'] for mix in ['class4','shared6']],
 'ordinary_gear_boundary':[['--room','L31','--samples','G2,P5','--mix','class6','--difficulties','0,4','--mage-affix-profile','resource_cooldown']],
 # Run only after endpoints are promising; do not expand a known failure.
 'ordinary_middle':[['--room','L31','--samples','G2','--mix','class6','--difficulties','1,2,3','--mage-affix-profile','resource_cooldown']],
 }
 return {k:[base+c for c in v] for k,v in stages.items()}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--stage',choices=list(plan()));p.add_argument('--frozen-source',type=pathlib.Path);p.add_argument('--write-frozen-source',type=pathlib.Path);a=p.parse_args()
 if a.write_frozen_source:
  a.write_frozen_source.write_text(json.dumps(fingerprint(),indent=2)+'\n');print('Frozen source written. This does not assert parse-ready or authorize execution.');return 0
 if not a.stage:
  print(json.dumps({'stages':plan(),'policy':'Wait for implementation parse-ready and explicit source freeze. All old evidence retained. Mixed-orientation SU6 excluded. G2 mage uses declared effective fourth affixes; P5 has only original 3 affixes. No automatic 10-seed expansion.'},ensure_ascii=False,indent=2));return 0
 if not a.frozen_source:p.error('--stage requires --frozen-source from reviewed parse-ready code')
 pinned=json.loads(a.frozen_source.read_text())
 for args in plan()[a.stage]:
  if pinned!=fingerprint():raise SystemExit('Source changed versus reviewed freeze; refusing to start or continue.')
  result=subprocess.run([sys.executable,str(RUNNER),*args],cwd=ROOT)
  if result.returncode:return result.returncode
  if pinned!=fingerprint():raise SystemExit('Source changed during run; preserve evidence but do not accept it.')
 return 0
if __name__=='__main__':raise SystemExit(main())
