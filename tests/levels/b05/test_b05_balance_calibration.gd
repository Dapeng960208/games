extends SceneTree
const Calibration=preload("res://scripts/domain/combat/enemy_calibration.gd")
const Numbers=preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok: failures+=1;push_error(label)
func _initialize()->void:
	var old:=Calibration.archived(1)
	var candidate:=Calibration.archived(2)
	check(old.chapters.size()==4 and not old.chapters.has("B05"),"baseline archive unchanged")
	check(Calibration.valid(old) and Calibration.valid(candidate),"both exact archives valid")
	for d in 5:
		var baseline:=Numbers.boss(d,old)
		var changed:=Numbers.boss(d,candidate)
		check(changed.max_hp==int(round(float(baseline.max_hp)*4.4)),"shared durability multiplier applied once")
		for key:String in ["damage","armor","magic_resist","move_speed","enemy_level"]:check(baseline[key]==changed[key],"only HP changes: "+key)
		for phase in range(1,4):check(Numbers.skill_damage(baseline,110,phase)==Numbers.skill_damage(changed,110,phase),"same warning packet damage")
	for chapter in range(1,5):check(Calibration.factor(old,chapter,"boss","hp")==Calibration.factor(candidate,chapter,"boss","hp"),"old chapters unchanged")
	check(Numbers.boss(4,old).max_hp==79920,"authored explicit1000 baseline")
	check(Numbers.boss(4,candidate).max_hp==351648,"candidate2 explicit4.4 shared coefficient")
	var third:=Calibration.archived(3)
	check(Calibration.valid(third) and Numbers.boss(4,third).max_hp==719280,"candidate3 shared durability")
	check(Numbers.boss(4,third).damage==int(round(float(Numbers.boss(4,old).damage)*.35)),"candidate3 shared attack rounded once")
	var profile:=preload("res://scripts/levels/b05/combat/enemy_skills.gd").boss_profile(4,third)
	var cmd:=preload("res://scripts/levels/b05/combat/enemy_skills.gd").boss_action(profile,"crown_sweep",Vector2.ZERO,Vector2(100,0),3)
	var frozen:=preload("res://scripts/levels/b05/combat/enemy_skills.gd").freeze_damage(cmd,profile)
	check(not frozen.is_empty() and frozen.damage==Numbers.skill_damage(Numbers.boss(4,third),110,3) and frozen.damage>0,"candidate3 actual command freeze retains positive damage")
	check(JSON.parse_string(JSON.stringify(Calibration.current()))==JSON.parse_string(JSON.stringify(old)),"normal candidate launch remains baseline without balance opt-in")
	var forged:=candidate.duplicate(true);forged.chapters.B05.boss.hp=4.5
	check(not Calibration.valid(forged) and Numbers.boss(4,forged).is_empty(),"unknown unarchived tuning rejected")
	for version in [10,11,12]:
		var pressure:=Calibration.archived(version)
		var skills=preload("res://scripts/levels/b05/combat/enemy_skills.gd")
		check(Calibration.valid(pressure),"ordinary pressure archive exact")
		for d in 5:
			var baseline_boss:=Numbers.boss(d,old)
			var pressure_boss:=Numbers.boss(d,pressure)
			for key:String in baseline_boss:
				if key!="enemy_calibration_snapshot":check(baseline_boss[key]==pressure_boss[key],"pressure candidate leaves Boss unchanged")
			for level:int in [21,23,25]:
				for rank:String in ["normal","elite"]:
					for id in range(1,19):
						var a:Dictionary=skills.profile("B05-M%02d"%id,level,d,rank,old)
						var b:Dictionary=skills.profile("B05-M%02d"%id,level,d,rank,pressure)
						var authored:Dictionary=preload("res://scripts/levels/b05/world/content.gd").enemy("B05-M%02d"%id)
						var role:Array=Numbers.ROLES[authored.profile]
						var unrounded:float=minf(1690.0,maxf(float(role[2])*100.0,float(authored.raw_stats.damage)*float(role[1])))/100.0*(1.0+.025*(level-1))*1.35*10.0*1.32*float(Numbers.ATTACK_D[d])/100.0*(1.12 if rank=="elite" else 1.0)*float({10:1.35,11:2.5,12:3.5}[version])
						check(b.damage>a.damage and b.damage==int(floor(unrounded+.5)),"ordinary attack independently rounds full authored product once")
						for key:String in a:
							if key not in ["damage","attack_calibration","enemy_calibration_snapshot"]:check(a[key]==b[key],"ordinary non-attack fields unchanged "+key)
						var restored:Dictionary=JSON.parse_string(JSON.stringify(b))
						var packet:Dictionary=skills.freeze_damage(skills.basic(restored,Vector2.ZERO,Vector2(100,0)),restored)
						check(not packet.is_empty() and packet.damage>0,"ordinary archived attack survives serialization and command freeze")
		for chapter in range(1,5):
			for rank:String in ["normal","elite","boss"]:check(Calibration.factor(pressure,chapter,rank,"attack")==1.0,"earlier chapter pressure unchanged")
	print("B05_CALIBRATION failures=",failures);quit(0 if failures==0 else 1)
