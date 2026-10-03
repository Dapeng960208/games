extends Node
const Crit=preload("res://scripts/domain/combat/crit_policy.gd")
const Power=preload("res://scripts/domain/combat/enemy_power_policy.gd")
const Damage=preload("res://scripts/domain/combat/damage_resolver.gd")
const Stats=preload("res://scripts/domain/combat/stat_resolver.gd")
const Profiles=preload("res://scripts/domain/combat/enemy_profiles.gd")
const Calibration=preload("res://scripts/domain/combat/enemy_calibration.gd")
const S05=preload("res://scripts/levels/b05/combat/enemy_skills.gd")
const S06=preload("res://scripts/levels/b06/combat/enemy_skills.gd")
const Codec=preload("res://scripts/levels/b06/combat/combat_state_codec.gd")
var checks:=0
var failures:=0
class Arena extends RoomController:
	func _ready()->void: pass
	func _draw()->void: pass
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures+=1; push_error("GLOBAL CRIT: "+label)
func _ready()->void: _run.call_deferred()
func _run()->void:
	if not Game.profile_path.contains("test_global_crit"): get_tree().quit(2); return
	var stats:={"ruleset_version":2,"crit_policy_version":1,"crit_chance":.25,"crit_multiplier":2.0}
	check(Crit.chance({})==.25 and Crit.multiplier({})==2.0,"global defaults")
	check(Crit.chance(stats,2)==1 and Crit.multiplier(stats,9)==3,"sum then caps 100/300")
	check(Crit.chance(stats,-2)==0 and Crit.multiplier(stats,-9)==1,"lower bounds")
	var observed:=0
	for i in 10000:
		check(not Crit.roll(313,str(i),0) and Crit.roll(313,str(i),1),"0/100 exact")
		var critical:=Crit.roll(313,str(i),.25)
		check(critical==Crit.roll(313,str(i),.25),"seed/event reproducible")
		if critical: observed+=1
	check(observed>2300 and observed<2700,"25 percent seeded frequency "+str(observed))
	for type:String in ["physical","magic"]:
		check(Damage.resolve(101,type,stats,{"ruleset_version":2},{"critical":true,"already_critical":false}).damage==202,"200 percent total "+type)
		var capped:=stats.duplicate(); capped.crit_multiplier=9
		check(Damage.resolve(101,type,capped,{"ruleset_version":2},{"critical":true,"already_critical":false}).damage==303,"300 percent cap "+type)
		check(Damage.resolve(202,type,stats,{"ruleset_version":2},{"critical":true,"already_critical":true}).damage==202,"pre-multiplied not doubled "+type)
	check(Damage.resolve(100,"true",stats,{"ruleset_version":2},{"critical":true,"already_critical":false}).damage==100,"derived true damage excluded")
	var frozen:=Crit.freeze({"damage":101},stats,313,"cast:4")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(frozen))
	check(Crit.freeze(saved,stats,999,"different").critical==frozen.critical,"JSON freeze does not reroll")
	for hero:String in ["CH01","CH02","CH03"]:
		var base:=Stats.resolve(hero,10,{}, {},2)
		var candidate:=Crit.apply_player(base,{"version":15})
		check(candidate.crit_chance==.25 and candidate.crit_multiplier==2,"all hero defaults "+hero)
		check(Crit.apply_player(base,{"version":14})==base,"archive14 untouched "+hero)
		base.uncapped_equipment_contribution={"crit_chance":.65,"crit_multiplier":.8}
		base.hero_base.talent_crit_chance=.20
		candidate=Crit.apply_player(base,{"version":15})
		check(candidate.crit_chance==1 and is_equal_approx(candidate.crit_multiplier,2.8),"raw equipment plus talent final clamp "+hero)
	var caster:={"crit_policy_version":1,"primary_role":"caster","damage":65,"ability_power":200,"skill_base_power":25}
	check(Power.amount({"ability_id":"mage:basic","damage_type":"magic"},caster,1)==65,"magic basic uses AD")
	check(Power.amount({"active":true,"damage_type":"physical"},caster,1.5)==325,"physical active caster uses AP plus base")
	check(Power.amount({"active":true,"count":5},caster,1)==205,"five shots divide base budget")
	check(Power.amount({"active":true,"derived":true},caster,1)==200,"followup cannot repeat base")
	var c05:=S05.profile("B05-M14",25,4,"normal",Calibration.archived(15),4)
	var c06:=S06.profile("B06-M07",30,4,"normal",Calibration.archived(15),4)
	check(not c05.is_empty() and not c06.is_empty(),"candidate production caster profiles")
	if not c05.is_empty():
		var basic:=S05.freeze_damage(S05.basic(c05,Vector2.ZERO,Vector2.RIGHT),c05)
		var active:=S05.freeze_damage(S05.active(c05,Vector2.ZERO,Vector2.RIGHT,true),c05)
		check(basic.power_source=="attack" and active.power_source=="ability_power","B05 frozen power split")
	if not c06.is_empty():
		var basic:=S06.freeze_damage(S06.basic(c06,Vector2.ZERO,Vector2.RIGHT),c06)
		var active:=S06.freeze_damage(S06.active(c06,Vector2.ZERO,Vector2.RIGHT,true,true),c06)
		check(basic.power_source=="attack" and active.power_source=="ability_power","B06 frozen power split")
	await _live()
	print("GLOBAL_CRIT_RESULT checks=",checks," failures=",failures," seeded_25_percent=",observed)
	get_tree().quit(0 if failures==0 else 1)
func _live()->void:
	Game.run=RunSession.new()
	Game.run.enemy_calibration_snapshot=Calibration.archived(15)
	Game.run.hero_id="CH03"
	Game.run.stats=Stats.resolve("CH03",10,{}, {},2)
	Game.run.max_hp=100000
	Game.run.hp=100000
	var room:=Arena.new()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.geometry_enabled=false
	room.spawn_enabled=false
	room.run_seed=313
	for name_value:String in ["Enemies","Projectiles"]:
		var container:=Node2D.new(); container.name=name_value; room.add_child(container)
	add_child(room)
	room.player=HeroActor.new(); room.player.room=room; room.add_child(room.player)
	room.enemy_skills=EnemySkillRuntime.new(); room.add_child(room.enemy_skills); room.enemy_skills.configure(room)
	var target:=EnemyActor.new(); target.room=room; target.training_ai_disabled=true
	target.configure(Profiles.resolve("M01",1,"normal",2,0),{"reward_enabled":false})
	room.enemies.add_child(target)
	target.armor=0; target.magic_resist=0; target.health.maximum=100000; target.health.current=100000
	for source:String in ["primary","q","secondary","f","ultimate"]:
		room.crit_rolls.clear(); Game.run.stats.uncapped_equipment_contribution={"crit_chance":.75,"crit_multiplier":0.0}; Game.run.stats=Game.run.stats
		var before:float=target.health.current
		var context:={"attack_id":source,"root_event_id":source,"attacker_stats":Game.run.stats.duplicate(true),"damage_type":"magic","power":100}
		room.resolve_direct_hit(target,100,StringName(source),"",0,Vector2.RIGHT,context)
		print("LIVE ",source," delta=",before-target.health.current," receipt=",target.last_damage_result," statscrit=",Game.run.stats.crit_chance)
		check(target.health.current<before and bool(room.crit_rolls.get(source,false)),"actual direct HP critical "+source)
	for source:String in ["node","field","node_detonation","node_echo"]:
		var before:float=target.health.current
		room.resolve_derived_hit(target,100,StringName(source),Vector2.RIGHT,{"root_event_id":"spell:"+source,"spell_critical_eligible":true,"attacker_stats":Game.run.stats.duplicate(true),"damage_type":"magic"})
		check(before-target.health.current==200,"actual spell HP doubles "+source)
	var before:float=target.health.current
	room.resolve_derived_hit(target,100,&"burn",Vector2.RIGHT,{"dot":true,"spell_critical_eligible":true,"attacker_stats":Game.run.stats.duplicate(true),"damage_type":"magic"})
	check(before-target.health.current==100,"derived DoT remains 100")
	# Identical direct packet, actual HP at zero/guaranteed critical and over-cap.
	for hero:String in ["CH01","CH02","CH03"]:
		Game.run.hero_id=hero
		Game.run.stats=Stats.resolve(hero,10,{}, {},2)
		for values:Array in [[0.0,2.0,100],[1.0,2.0,200],[1.0,9.0,300]]:
			room.player.hit_chain.reset()
			room.crit_rolls.clear()
			var attack_stats:Dictionary=Game.run.stats.duplicate(true)
			attack_stats.crit_chance=values[0]; attack_stats.crit_multiplier=values[1]
			var hp_before:float=target.health.current
			room.resolve_direct_hit(target,100,&"q","",0,Vector2.RIGHT,{"root_event_id":"edge:"+hero,"attack_id":"edge:"+hero,"attacker_stats":attack_stats,"damage_type":"magic","already_critical":false})
			check(hp_before-target.health.current==values[2],"live same skill packet "+hero+" expected "+str(values[2]))
			print("HP_ENDPOINT hero=",hero," chance=",values[0]," multiplier=",values[1]," loss=",hp_before-target.health.current)
	# Real spell casts create their own projectile/deployment payloads.
	Game.run.hero_id="CH03"; Game.run.level=20
	Game.run.stats=Stats.resolve("CH03",20,{}, {},2)
	Game.run.stats.uncapped_equipment_contribution={"crit_chance":.75,"crit_multiplier":0.0}; Game.run.stats=Game.run.stats
	room.player.position=Vector2(300,300); target.position=Vector2(330,300)
	for slot:String in ["q","secondary","f","ultimate"]:
		Game.run.resource=100000
		room.player.cooldowns={"q":0.0,"secondary":0.0,"f":0.0,"ultimate":0.0}; room.player.abilities.cancel(); room.player.hit_chain.reset(); target.status.states.clear()
		var hp_before:float=target.health.current
		var accepted:bool=room.player.abilities.try_cast(slot,target.position)
		check(accepted,"production mage cast accepted "+slot)
		if not accepted: continue
		room.player.abilities.tick(10)
		for projectile:Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion(): projectile.hit(target)
		check(target.health.current<hp_before,"production mage cast loses HP "+slot)
		for deployment:Node in get_tree().get_nodes_in_group("hero_deployments"):
			if deployment.room!=room or deployment.is_queued_for_deletion(): continue
			check(bool(deployment.options.get("spell_critical_eligible",false)) and not str(deployment.options.get("root_event_id","")).is_empty(),"cast carries frozen root to "+deployment.kind)
			if deployment.kind=="field":
				target.status.states.clear(); hp_before=target.health.current
				deployment.advance(1.0)
				check(hp_before-target.health.current==2*deployment.damage,"actual ground field tick doubles without extra proc")
			elif deployment.kind=="node":
				target.status.states.clear(); hp_before=target.health.current
				deployment.advance(1.6)
				for projectile:Node in room.projectiles.get_children():
					if not projectile.is_queued_for_deletion() and projectile.source==&"node": projectile.hit(target)
				check(hp_before-target.health.current==2*deployment.damage,"actual spawned node projectile doubles")
	for deployment:Node in get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.room==room: deployment.free()
	# Real enemy runtime -> real player -> Game.damage_player -> armor -> HP.
	var attacker:=EnemyActor.new(); attacker.room=room; attacker.training_ai_disabled=true
	var profile:=S06.profile("B06-M07",30,0,"normal",Calibration.archived(15),4)
	attacker.configure(profile,{"reward_enabled":false}); room.enemies.add_child(attacker)
	var c:=S06.basic(profile,Vector2.ZERO,Vector2.RIGHT)
	var packet:Dictionary=room.enemy_skills.b06.prepare(attacker,c)
	packet.damage=100; packet.critical=true
	Game.run.stats.armor=0; Game.run.stats.magic_resist=0; Game.run.stats.damage_reduction=0; Game.run.stats.equipment_damage_reduction=0
	room.player.invulnerable=0; Game.run.shield=0
	before=Game.run.hp
	room.enemy_skills._deal(room.player,packet,Vector2.ZERO)
	check(before-Game.run.hp==200,"enemy runtime critical lands exactly 200 HP")
	var encoded:=Codec.encode(packet,func(actor:Node2D)->String:return "caster" if actor==attacker else "player")
	check(encoded.ok,"crit command codec serializes")
	if encoded.ok:
		var json:Variant=JSON.parse_string(JSON.stringify(encoded.value))
		var decoded:=Codec.decode(json,func(id:String)->Node2D:return attacker if id=="caster" else room.player)
		check(decoded.ok and decoded.value.critical and decoded.value.damage==100,"crit command JSON retains roll and unmultiplied amount")
	# Authentic candidate15 packet survives the complete runtime JSON codec,
	# validation and restore, with the stored crit decision unchanged.
	var pending:Dictionary=room.enemy_skills.b06.prepare(attacker,c)
	pending["remaining"]=.5
	room.enemy_skills.jobs.append(pending)
	var encode_actor:=func(actor:Node2D)->String:return "caster" if actor==attacker else "player" if actor==room.player else "target"
	var decode_actor:=func(id:String)->Node2D:return attacker if id=="caster" else room.player if id=="player" else target
	var runtime_saved:Dictionary=room.enemy_skills.b06.capture_candidate(encode_actor)
	check(not runtime_saved.is_empty(),"candidate15 full runtime capture")
	if not runtime_saved.is_empty():
		var runtime_json:Dictionary=JSON.parse_string(JSON.stringify(runtime_saved))
		check(room.enemy_skills.b06.validate_candidate(runtime_json,decode_actor),"candidate15 JSON runtime validates")
		get_tree().paused=true
		room.enemy_skills.advance(2)
		check(room.enemy_skills.jobs.size()==1 and room.enemy_skills.jobs[0].remaining==.5,"paused candidate command does not age or roll")
		get_tree().paused=false
		check(room.enemy_skills.b06.restore_candidate(runtime_json,decode_actor),"candidate15 runtime restores")
		check(room.enemy_skills.jobs.size()==1 and room.enemy_skills.jobs[0].critical==pending.critical and room.enemy_skills.jobs[0].damage==pending.damage,"restored candidate retains exact critical and amount")
	room.enemy_skills.jobs.clear()
	# Main spell base is a per-cast budget, not a gift on every shot/tick.
	var budget_stats:={"crit_policy_version":1,"ruleset_version":2,"primary_role":"caster","damage":65,"ability_power":200,"skill_base_power":25,"crit_chance":0.0,"crit_multiplier":2.0}
	var volley:={"kind":"projectile","count":5,"origin":room.player.position,"direction":Vector2.RIGHT,"target":room.player.position,"damage_type":"magic","owner":weakref(attacker),"owner_id":attacker.get_instance_id(),"critical":false}
	Power.stamp(volley,budget_stats); volley.damage=Power.amount(volley,budget_stats,1.0)
	volley=Crit.freeze(volley,budget_stats,313,"budget-volley")
	var share_total:=0.0
	before=Game.run.hp
	for shot_index:int in 5:
		room.player.invulnerable=0
		room.enemy_skills._deal(room.player,volley,room.player.position)
		share_total+=float(volley.spell_base_share)
	check(is_equal_approx(share_total,1.0) and before-Game.run.hp==1025,"five real AP hits total 5*200+25, share sum1")
	var pool:={"kind":"ground_area","shape":"circle","radius":90.0,"duration":2.0,"tick_interval":.5,"origin":room.player.position,"target":room.player.position,"damage_type":"magic","owner":weakref(attacker),"owner_id":attacker.get_instance_id(),"critical":false}
	Power.stamp(pool,budget_stats); pool.damage=Power.amount(pool,budget_stats,1.0)
	pool=Crit.freeze(pool,budget_stats,313,"budget-pool")
	room.enemy_skills._spawn_hazards(pool)
	before=Game.run.hp
	for tick_index:int in 4:
		room.player.invulnerable=0
		room.enemy_skills.advance(.5)
	check(float(pool.spell_base_share)*4.0<=1.0 and before-Game.run.hp==820,"four real AP ticks total4*(200+5), base budget20<=25")
	print("AP_BUDGET_ENDPOINT volley_hp=1025 volley_share=",share_total," pool_hp=",before-Game.run.hp," pool_share=",float(pool.spell_base_share)*4.0)
	for number:int in range(1,7):
		var boss_profile:Dictionary
		if number==5: boss_profile=S05.boss_profile(0,Calibration.archived(15),4)
		elif number==6: boss_profile=S06.boss_profile(0,Calibration.archived(15),4)
		else: boss_profile=preload("res://scripts/domain/combat/boss_profiles.gd").resolve("BO%02d"%number,0,2,Calibration.archived(15))
		var boss:=BossActor.new(); boss.room=room; boss.training_ai_disabled=true; boss.configure(boss_profile); room.enemies.add_child(boss)
		check(Crit.enabled(boss.profile) and boss.profile.crit_chance==.25 and boss.profile.crit_multiplier==2,"boss production defaults "+str(number))
		for critical:bool in [false,true]:
			var command:Dictionary=Crit.freeze({"damage":100,"owner":weakref(boss),"owner_id":boss.get_instance_id(),"critical":critical,"damage_type":"physical"},boss.profile,313,"boss-test")
			Game.run.hp=100000; Game.run.shield=0; room.player.status.states.clear(); room.player.status.guards.clear(); room.player.invulnerable=0
			before=Game.run.hp
			room.enemy_skills._deal(room.player,command,Vector2.ZERO)
			check(before-Game.run.hp==(200 if critical else 100),"boss actual HP "+str(number)+" critical="+str(critical))
			print("HP_ENDPOINT boss=",number," critical=",critical," loss=",before-Game.run.hp)
		boss.free()
	room.free()
	await get_tree().process_frame
