extends Node
const Resolver=preload("res://scripts/domain/combat/stat_resolver.gd")
const Powers=preload("res://scripts/gameplay/characters/hero_abilities.gd")
const Rules=preload("res://scripts/infrastructure/content/runtime_rules.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
func _ready()->void:
	var enabled:= "--mage-balance-candidate=1" in OS.get_cmdline_user_args()
	for level in [5,10,15,20,25]:
		var stats:=Resolver.resolve("CH03",level,{}, {},2,{})
		check(int(stats.get("mage_balance_candidate",0))==(1 if enabled else 0),"explicit isolated marker Lv"+str(level))
		var base_skill:=Rules.integer(float(stats.attack)+.7*float(stats.ability_power))
		var powers:=Powers.preview_powers("CH03",stats)
		check(powers.skill_H==Rules.integer(base_skill*(2.5 if enabled else 1.0)),"all-level spell H only multiplier")
		check(powers.basic_H==Rules.integer(float(stats.attack)+.35*float(stats.ability_power)),"basic H unchanged")
		check(powers.relic_H==stats.ability_power,"AP/relic H unchanged")
		check(stats.resource_regen==(160 if enabled else 80) and stats.resource_max==1200 and stats.starting_resource==1200,"regen only; capacity/entry unchanged")
		check(stats.max_hp==stats.hero_base.max_hp and stats.armor==stats.hero_base.armor and stats.magic_resist==stats.hero_base.magic_resist,"naked defenses/HP unchanged")
		for slot:String in ["q","secondary","f","ultimate"]:
			var spec:=Powers.preview_spec("CH03",level,stats,slot)
			check(float(spec.cost)==(120.0 if slot=="q" else 500.0 if slot=="ultimate" else 200.0),"cost unchanged "+slot)
			check(Powers.packet_amount(1.0,float(powers.skill_H),stats)==powers.skill_H,"packet does not multiply H twice")
	for hero:String in ["CH01","CH02"]:
		var stats:=Resolver.resolve(hero,25,{}, {},2,{})
		check(not stats.has("mage_balance_candidate"),"physical class untouched")
	print("MAGE_CANDIDATE_CONTRACT failures=",failures);get_tree().quit(0 if failures==0 else 1)
