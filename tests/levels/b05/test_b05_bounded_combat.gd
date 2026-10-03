extends "res://tests/levels/b05/test_b05_natural_encounters.gd"
## Three bounded D0 L25 samples. Legal owned B04 Lv20 green+3 fixtures,
## normal HP/damage/resources, real movement and QWER. Acquisition is assumed.
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Driver = preload("res://tests/support/b05_bounded_controller.gd")
func _run() -> void:
	if not Game.profile_path.begins_with("user://test_b05_candidate/natural"): get_tree().quit(2); return
	stage=SubViewport.new(); stage.size=Vector2i(1280,720); stage.handle_input_locally=true; add_child(stage)
	for hero: String in ["CH01","CH02","CH03"]:
		Game.run=null
		check(Game.new_profile() and Game.select_hero(hero),"bounded fresh profile "+hero)
		var fixture: Dictionary=b04_fixture(hero)
		check(not fixture.is_empty(),"legal B04 level20 green+3 fixture "+hero)
		if fixture.is_empty(): finish(); return
		var profile: Dictionary=Game.profile.duplicate(true)
		profile.hero_xp[hero]=Growth.thresholds()[19]
		profile.bosses=["BO01","BO02","BO03","BO04"]
		profile.equipment=fixture.owned.duplicate(true)
		profile.loadout=fixture.loadout.duplicate(true)
		profile.loadout_presets={hero:fixture.loadout.duplicate(true)}
		profile.talents={hero:fixture.talents.duplicate(true)}
		profile.branches[hero]=fixture.branches.duplicate(true)
		profile.equipment_discoveries=[]
		for item: Dictionary in fixture.owned.values(): profile.equipment_discoveries.append(item.template_id)
		profile.settings.auto_attack=false
		check(Game._commit_profile(profile) and Game.start_run({"expedition":true,"biome_id":"B05","seed":54873,"difficulty":0}),"bounded candidate departure "+hero+" "+Game.last_error)
		if Game.run==null: finish(); return
		var expedition=Controller.new(Game)
		if not await install(expedition.current_context()): finish(); return
		for offer: Dictionary in Game.expedition_snapshot().relic_offers:
			check(Game.choose_run_relic(offer.offer_id,"skip","",room.expedition_runtime_snapshot()),"resolve entry relic "+hero)
		var next: Dictionary=expedition.next_node()
		var prepared: Dictionary=room.prepare_expedition_node(expedition.candidate(next.room_id))
		var entered: bool=prepared.get("valid",false) and Game.choose_expedition_node(1,next.room_id) and Game.advance_expedition_node(room.expedition_runtime_snapshot())
		check(entered,"actual L25 entry "+hero+" "+Game.last_error)
		if not entered: finish(); return
		prepared.runtime=Game.expedition_snapshot().runtime.duplicate(true)
		room.apply_prepared_expedition_node(prepared)
		await get_tree().process_frame
		room.release_gate=false; room.pointer_release_gate=false
		var driver=Driver.new(); driver.configure(room)
		var elapsed:=0.0
		var minimum_hp: float=Game.run.hp
		var minimum_resource: float=Game.run.resource
		var resource_empty:=0.0
		var observed: Dictionary={}
		var first_kill:=-1.0
		var last_kills:=0
		var maximum_hp: float=Game.run.max_hp
		var initial_stats: Dictionary=Game.run.stats.duplicate(true)
		while elapsed<90 and Game.run!=null and Game.run.hp>0 and not room.objective_rewarded:
			room.release_gate=false; room.pointer_release_gate=false
			driver.step(elapsed)
			if actors().is_empty() and not room._encounters_exhausted():
				var zone: int=room.activated_encounters.size()
				room.player.request_move(room.encounter_zones[zone].center,false)
			for actor: EnemyActor in actors():
				var key:=str(actor.get_instance_id())
				if not observed.has(key): observed[key]={"enemy":actor.enemy_id,"signature":false,"basic":false,"releases":0}
				var command: Dictionary=actor.brain.current_skill()
				if not command.is_empty(): observed[key]["signature" if command.get("active",false) else "basic"]=true
				observed[key].releases=actor.brain.cycle
			step(.025)
			elapsed+=.025
			if Game.run==null: break
			minimum_hp=minf(minimum_hp,Game.run.hp)
			minimum_resource=minf(minimum_resource,Game.run.resource)
			if Game.run.resource<=0: resource_empty+=.025
			if int(room.telemetry.kills)>last_kills and first_kill<0: first_kill=elapsed
			last_kills=int(room.telemetry.kills)
			if int(round(elapsed*40))%20==0: await get_tree().process_frame
		var outcome:="cleared" if room.objective_rewarded else "died" if Game.run==null or Game.run.hp<=0 else "observation_limit"
		var row:={"hero":hero,"room":"L25","difficulty":0,"fixture":"B04 Lv20 green+3 eight slots;19 talents;owned gear assumed","outcome":outcome,"seconds":snappedf(elapsed,.025),"first_kill_seconds":first_kill,"kills":last_kills,"initial_max_hp":maximum_hp,"minimum_hp":minimum_hp,"remaining_hp":Game.run.hp if Game.run!=null else 0,"minimum_resource":minimum_resource,"resource_empty_seconds":resource_empty,"basic_shots":Game.run.shots if Game.run!=null else -1,"primary_hits":room.telemetry.primary_hits,"skill_casts":room.player.abilities.cast_serial,"resource_max":initial_stats.resource_max,"attack":initial_stats.attack,"spell_power":initial_stats.get("ability_power",0),"equipment_templates":fixture.owned.values().map(func(item): return item.template_id),"observed_enemies":observed.values(),"rejected":driver.rejected}
		if hero=="CH03": check(int(row.basic_shots)==0 and int(row.primary_hits)==0,"mage sample uses no basic attacks")
		check(int(row.skill_casts)>0,"actual class spell loop exercised "+hero)
		records.append(row)
		print("B05_BOUNDED_SAMPLE ",JSON.stringify(row))
		check(await room.combat_audio.wait_for_cleanup(),"bounded audio cleanup "+hero)
		room.free(); Game.run=null
	finish()

func b04_fixture(hero: String) -> Dictionary:
	var owned: Dictionary={}
	var loadout: Dictionary={}
	var pool: Dictionary=Acquisition.natural_pool("B04",hero)
	var power:="magic" if hero=="CH03" else "physical"
	for slot: String in ContentRegistry.slots(2):
		if not pool.has(slot) or pool[slot].is_empty(): return {}
		var candidates: Array=pool[slot].duplicate(); candidates.sort()
		var template: String=candidates[0]
		var rolls: Dictionary={}
		for key: String in Instances.main_keys(template,power): rolls[key]=50
		var legal: Array=Instances.legal_affixes(template,power)
		var preferred: Array=["ability_power" if power=="magic" else "attack","max_hp","armor","magic_resist","damage_bonus","resource_gain_bonus"]
		var affixes: Array=[]
		for key: String in preferred:
			if key in legal and affixes.size()<2: affixes.append({"type":key,"u":50})
		for key: String in legal:
			if affixes.size()>=2: break
			if not affixes.any(func(x): return x.type==key): affixes.append({"type":key,"u":50})
		var steps: Array=[]
		for rank in range(3): steps.append({"g":10,"pity":0,"base_price_peak":Economy.enhancement_price(rank+1,20)})
		var id:="b05-bounded:"+hero+":"+slot
		var item: Dictionary=Instances.create({"instance_id":id,"template_id":template,"source_event_id":"b05-bounded:owned-fixture","item_level":20,"rarity":"green","power_type":power,"main_rolls":rolls,"affix_type_and_quantile":affixes,"enhancement_steps":steps,"location":"equipped","purchase_baseline_gold":Economy.purchase_baseline_price(template,"green",20)})
		if item.is_empty() or not Instances.can_equip(item,hero,20): return {}
		owned[id]=item; loadout[slot]=id
	return {"owned":owned,"loadout":loadout,"talents":{"mastery":5,"precision":5,"agility":5,"dexterity":4},"branches":{"q":"B","ultimate":"A"}}
