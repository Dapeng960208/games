#!/usr/bin/env python3
"""Compact receipt-derived comparisons. Never substitutes inferred set bonus damage."""
import argparse,collections,hashlib,json,pathlib
p=argparse.ArgumentParser();p.add_argument('observations',nargs='+');p.add_argument('--output',required=True);a=p.parse_args()
rows=[];sources=[]
for name in a.observations:
 f=pathlib.Path(name);d=json.loads(f.read_text());sources.append({'batch':f.parent.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'failures':d.get('failures',[])})
 for c in d['cases']:
  damage=collections.Counter();sources_damage=collections.Counter();procs=collections.Counter();commands=collections.defaultdict(list)
  for x in c['outgoing_packets']:
   if x.get('boss') and x.get('feedback_kind')=='hp':
    damage[x['kind']]+=x['amount'];sources_damage[x.get('damage_source','unclassified')]+=x['amount']
    if x.get('proc_depth',0)>0:procs[x.get('damage_source',x['kind'])]+=x['amount']
  for x in c['actual_enemy_commands']:
   commands[x.get('action_id',x.get('ability_id','unknown'))].append({k:x.get(k) for k in ['b06_phase','stage','stage_count','damage','observed_room_time']})
  paid=[x for x in c['ability_timeline_audit'] if x['kind']=='paid_commit']
  metric=c.get('b06_metrics',{});hp=c['outgoing']['boss_hp'];t=c['simulation_seconds']
  rows.append({'batch':f.parent.name,'configuration':c['configuration'],'mage_affix_profile':c['fixture']['manifest'].get('mage_affix_profile','frozen'),'outcome':c['outcome'],'active_seconds':t,'effective_dps':hp/t,'admitted_time_dps':hp/metric['damage_admitted_seconds'] if metric.get('damage_admitted_seconds') else None,'actual_hp_damage':hp,'damage_by_kind':dict(damage),'damage_by_source':dict(sources_damage),'explicit_proc_packet_damage':dict(procs),'set_damage_note':'Multiplicative set effects are already folded into actual packets; no invented standalone attribution. Empty proc packets does not prove no set effects.','casts':c['casts'],'paid_cast_count':len(paid),'paid_resource_total':sum(x['paid_cost'] for x in paid),'class_refunds':sum(x['effective_class_refund'] for x in paid),'resource_rejections':{k:v for k,v in c['resource_rejections'].items() if k.startswith('resource:')},'resource_empty_seconds':c['resource_empty_seconds'],'b06_metrics':metric,'resource_metric_note':'Ready-resource-blocked seconds means at least one ready skill unaffordable while ability idle; not all offense stopped.','phases':c['phases'],'actual_commands':dict(commands),'hp_fraction':c['hp_fraction'],'hp_loss':c['hp_loss'],'shield_absorbed':c['shield_absorbed'],'kills':c['negative_control']['kills'],'enemy_roster':list(c['enemy_roster'].values()),'incoming_packets':c['incoming_packets'],'hits':c['negative_control']['effective_received_hits']})
out={'schema':'b06-combat-comparison-v1','sources':sources,'cases':rows,'scope':'Controlled B06 observations; exact scenarios and fixtures stated per case. Not human play acceptance.'}
pathlib.Path(a.output).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
for r in rows:print(r['configuration']['mix'],r['configuration']['hero_id'],round(r['active_seconds'],3),round(r['effective_dps'],1),r['b06_metrics'])
