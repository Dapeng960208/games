extends Node
## Targeted real-actor B05 gear slice, isolated save path required.
const RoomScene = preload("res://scenes/room.tscn")
const Numbers = preload("res://config/numerical_rules.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
var room: MineRoom
var checks := 0
var failures: Array[String] = []
func _ready() -> void: call_deferred("run_checks")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func near(value:float, expected:float,label:String)->void:
	check(is_equal_approx(value,expected),label+" actual="+str(value)+" expected="+str(expected))
func fixture(hero:String,set_id:String,unique_ids:Array=[])->void:
	if is_instance_valid(room): room.free()
	var owned:Dictionary={}
	var loadout:Dictionary={}
	for slot:String in ContentRegistry.V2_SLOTS:
		var id:String=set_id+"-"+("accessory" if slot=="charm" else slot)
		for unique_id:String in unique_ids:
			if ContentRegistry.equipment(unique_id,2).slot==slot:id=unique_id
		var record:=Acquisition.roll_item({"instance_id":"b05live:"+slot,"source_event_id":"b05live:fixture","template_id":id,"rarity":"white","power_type":"magic" if hero=="CH03" else "physical","hero_id":hero,"item_level":25,"source":"drop","location":"inventory"},100)
		check(not record.is_empty(),"fixture legal "+id)
		owned[record.instance_id]=record
		loadout[slot]=record.instance_id
	Game.run.hero_id=hero
	Game.run.level=25
	Game.run.frozen_versions=Numbers.frozen_versions(2)
	Game.run.stats=StatResolver.resolve(hero,25,loadout,owned,2)
	Game.run.stats.crit_chance=0.0
	Game.run.loadout_snapshot=loadout.duplicate()
	Game.run.equipment_snapshot=owned.duplicate(true)
	Game.run.relics.clear()
	Game.run.max_hp=Game.run.stats.max_hp
	Game.run.hp=Game.run.max_hp
	Game.run.resource=Game.run.stats.resource_max
	Game.run.shield=0
	room=RoomScene.instantiate()
	room.geometry_enabled=false
	room.process_mode=Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled=false
	room.input_blocked=false
	room.release_gate=false
	for enemy:Node in room.enemies.get_children():enemy.free()
	room.player.position=Vector2(600,450)
	room.player.aim_direction=Vector2.RIGHT
	room.combat_audio.audible=false
func target(offset:=Vector2(80,0))->MineEnemy:
	var enemy:MineEnemy=room.spawn_enemy(room.player.position+offset,"M01")
	enemy.health.reset(1000000)
	enemy.armor=0;enemy.magic_resist=0
	enemy.reward_enabled=false;enemy.training_ai_disabled=true;enemy.rank="boss"
	return enemy
func step(seconds:float)->void:
	var remaining:=seconds
	while remaining>0.000001:
		var dt:=minf(1.0/60,remaining)
		for slot:String in room.player.cooldowns:room.player.cooldowns[slot]=maxf(0,float(room.player.cooldowns[slot])-dt)
		room.player.invulnerable=maxf(0,room.player.invulnerable-dt)
		room.player._tick_b05_control(dt)
		room.player.passives.tick(dt)
		room.player.abilities.tick(dt)
		room.player.loadout.tick(dt)
		for projectile:Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():projectile._physics_process(dt)
		remaining-=dt
func run_checks()->void:
	if not Game.profile_path.contains("test_b05_equipment_live"):
		get_tree().quit(2);return
	Numbers.parameters()
	Numbers._parameters.implemented_chapters=5
	check(Game.new_profile() and Game.start_run(),"isolated real run")
	_warrior()
	_gunner()
	_mage()
	_shared_and_snapshot()
	if is_instance_valid(room):room.free()
	print("B05 EQUIPMENT LIVE: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func _warrior()->void:
	fixture("CH01","B05-SW")
	var enemy:=target()
	check(room.player.cast_skill("f",enemy.position),"SW E cast")
	step(.4)
	var spec:Dictionary=room.player.abilities.spec("f")
	near(room.player.status.guards.hero_f.amount,Numbers.integer(Game.run.max_hp*float(spec.guard)*1.12),"SW2 boosts generated E guard once")
	check(room.player.receive_damage(100,enemy.position,{"damage_type":"true","attacker_stats":{},"bypass_invulnerability":true}),"SW shield confirmed hostile hit")
	check(room.player.loadout.effects.windows.has("B05-SW_4:absorbed"),"SW4 actual E absorption arms")
	check(room.player.cast_skill("secondary",enemy.position),"SW W cast")
	step(.6)
	check(room.player.loadout.effects.cooldowns.has("B05-SW_4"),"SW4 real W releases derived arc")
	var original_cd:float=room.player.loadout.effects.cooldowns["B05-SW_4"]
	var state:Dictionary=Snapshot.capture(room)
	check(not state.is_empty(),"B05 real gear snapshot capture")
	check(Snapshot.restore(room,JSON.parse_string(JSON.stringify(state))),"B05 real gear JSON restore")
	near(room.player.loadout.effects.cooldowns["B05-SW_4"],original_cd,"snapshot preserves global proc ICD")
func _gunner()->void:
	fixture("CH02","B05-SG")
	var front:=target(Vector2(80,0));var behind:=target(Vector2(160,0));var lateral:=target(Vector2(160,70))
	room.player.class_mark_target(front)
	var behind_hp:float=behind.health.current
	var lateral_hp:float=lateral.health.current
	check(room.player.cast_skill("secondary",front.position),"SG actual W commits")
	step(.75)
	check(behind.health.current<behind_hp,"SG4 ray target hit")
	near(lateral.health.current,lateral_hp,"SG4 does not hit off-ray target")
	check(room.player.loadout.effects.cooldowns.has("B05-SG_4"),"SG4 marked original W emits extra segment")
	room.player.aim_direction=Vector2.RIGHT
	check(room.player.cast_skill("q",front.position),"SG Q movement")
	step(.6)
	check(room.player.loadout.effects.windows.has("B05-SG_6:w"),"SG6 actual Q displacement arms")
func _mage()->void:
	fixture("CH03","B05-SM")
	var enemy:=target(Vector2(100,0))
	var beginning:float=Game.run.resource
	var costs:=0.0
	for slot:String in ["secondary","q","f"]:
		costs+=float(room.player.abilities.spec(slot).cost)
		check(room.player.cast_skill(slot,enemy.position),"SM zero-basic cast "+slot)
		step(.45)
	check(room.player.loadout.effects.cooldowns.has("B05-SM_4"),"SM4 real paid alternating casts restore")
	# Existing three-cast class passive restores100, B05 adds its own60 exactly.
	near(Game.run.resource,beginning-costs+100+60,"SM4 additive actual60 mana, no double restore")
	check(room.player.loadout._b05_pending_blooms.is_empty(),"SM6 one-second delayed release completed")
	check(room.player.loadout.effects.cooldowns.has("B05-SM_6:ring"),"SM6 actual placement creates one live ring")
	check(room.player.get_node("HeroFeedback").basic_events==0,"SM runtime accepts zero basic attacks")
func _shared_and_snapshot()->void:
	fixture("CH03","B05-SU",["B05-U01","B05-U02","B05-U03"])
	var enemy:=target()
	check(room.player.receive_enemy_status({"id":"root","duration":.6}),"real root accepted")
	near(room.player._enemy_root_remaining,.48,"SU2 actual root duration reduction")
	check(not room.player.receive_enemy_status({"id":"root","duration":.6}),"active root cannot refresh chain")
	step(.5)
	near(room.player.loadout.modifiers().move_speed_bonus,.10,"U01 real root expiry grants speed")
	check(not room.player.receive_enemy_status({"id":"root","duration":.6}),"post-root protection blocks same control")
	step(2.0)
	check(room.player.receive_enemy_status({"id":"root","duration":.6}),"root protection expires")
	check(room.player.receive_enemy_status({"id":"slow","magnitude":.85,"duration":3}),"real slow accepted")
	near(room.player._enemy_slow_remaining,2.4,"SU2 actual slow duration reduction")
	Game.run.hp=Game.run.max_hp-100
	room.player.heal(50,"external")
	check(room.player.status.guards.has("equipment:B05-U02"),"U02 actual external healing grants guard")
	near(room.player.status.guards["equipment:B05-U02"].amount,Numbers.integer(Game.run.max_hp*.02),"U02 exact maxHP2% shield")
	room.player.notify_hostile_destructible_destroyed("test:enemy_anchor")
	near(room.player.loadout.modifiers().damage_reduction_bonus,.05,"U03 actual adapter destruction")
	room.player.notify_hostile_hazard("test:zone",true)
	room.player.notify_hostile_hazard("test:zone",false)
	step(1.01)
	check(room.player.status.guards.has("equipment:B05-SU_4"),"SU4 actual hazard-exit adapter")
	var state:=Snapshot.capture(room)
	check(not state.is_empty(),"root and unique gear snapshot")
	check(state.status.has("root_remaining") and state.status.has("root_protection_remaining"),"root state serialized")
	check(Snapshot.restore(room,JSON.parse_string(JSON.stringify(state))),"root state restores from JSON")
	var old:=state.duplicate(true);old.status.erase("root_remaining");old.status.erase("root_protection_remaining")
	check(Snapshot.validate(old,Game.run.hero_id,Game.run.stats),"old root-less saves remain valid")
	state.status.root_protection_remaining=3
	check(not Snapshot.validate(state,Game.run.hero_id,Game.run.stats),"root protection save bound validated")
