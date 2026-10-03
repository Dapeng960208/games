extends Node
const Resolver=preload("res://scripts/combat/stat_resolver.gd")
const Powers=preload("res://scripts/combat/hero_abilities.gd")
const Rules=preload("res://config/numerical_rules.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
func _ready()->void:
	var enabled:= "--warrior-balance-candidate=1" in OS.get_cmdline_user_args()
	var rows:Array=[]
	for level in [5,10,15,20,25]:
		var stats:=Resolver.resolve("CH01",level,{}, {},2,{})
		check(int(stats.get("warrior_balance_candidate",0))==(1 if enabled else 0),"explicit isolated marker")
		var powers:=Powers.preview_powers("CH01",stats)
		check(powers.skill_H==Rules.integer(float(stats.attack)*(1.20 if enabled else 1.0)),"all-level skill H only")
		check(powers.basic_H==stats.attack and powers.relic_H==stats.attack,"basic and relic unchanged")
		var authored:=stats.duplicate(true)
		authored.erase("warrior_balance_candidate");authored.erase("warrior_skill_power_multiplier")
		for slot:String in ["q","secondary","f","ultimate"]:
			check(Powers.preview_spec("CH01",level,stats,slot)==Powers.preview_spec("CH01",level,authored,slot),"skill cost/cooldown/coefficients unchanged")
		check(preload("res://scripts/combat/hit_chain.gd").WINDOW==4.0,"combo window unchanged")
		rows.append({"level":level,"stats_without_candidate_tags":authored,"powers":powers})
	for hero:String in ["CH02","CH03"]:
		check(not Resolver.resolve(hero,25,{}, {},2,{}).has("warrior_balance_candidate"),"other class unaffected")
	print("WARRIOR_CANDIDATE_CONTRACT ",JSON.stringify({"enabled":enabled,"failures":failures,"rows":rows}))
	get_tree().quit(0 if failures==0 else 1)
