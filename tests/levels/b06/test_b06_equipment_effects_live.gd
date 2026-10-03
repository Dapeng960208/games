extends Node
## Targeted real-actor B06 gear slice, isolated save path required.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
var room: RoomController
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
		var record:=Acquisition.roll_item({"instance_id":"b06live:"+slot,"source_event_id":"b06live:fixture","template_id":id,"rarity":"white","power_type":"magic" if hero=="CH03" else "physical","hero_id":hero,"item_level":30,"source":"drop","location":"inventory"},100)
		check(not record.is_empty(),"fixture legal "+id)
		owned[record.instance_id]=record
		loadout[slot]=record.instance_id
	Game.run.hero_id=hero
	Game.run.level=30
	Game.run.frozen_versions=Numbers.frozen_versions(2)
	Game.run.stats=StatResolver.resolve(hero,30,loadout,owned,2)
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
func target(offset:=Vector2(80,0))->EnemyActor:
	var enemy:EnemyActor=room.spawn_enemy(room.player.position+offset,"M01")
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
		var guards: Dictionary = room.player.status.guards.duplicate(true)
		room.player.status.tick(dt)
		room.player._b06_guard_ends(guards,"expired")
		Game.run.shield=room.player.status.shield()
		room.player._tick_b05_control(dt)
		room.player.passives.tick(dt)
		room.player.abilities.tick(dt)
		room.player.loadout.tick(dt)
		for projectile:Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():projectile._physics_process(dt)
		remaining-=dt
func run_checks()->void:
	if not Game.profile_path.contains("test_b06_equipment_effects_live"):
		get_tree().quit(2);return
	check(Game.new_profile() and Game.start_run(),"isolated real run")
	_warrior()
	_gunner()
	_mage()
	_shared()
	_tide_uniques()
	_cleanup_and_immune()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
		room.free()
	Game.run=null
	print("B06 EQUIPMENT LIVE: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
func _warrior()->void:
	fixture("CH01","B06-SW")
	var enemy:=target()
	check(room.player.cast_skill("f",enemy.position),"SW actual E")
	step(.7)
	room.player.loadout.refresh_modifiers()
	near(room.player.loadout.modifiers().received_displacement_reduction,.25,"SW2 live E source")
	check(room.player.receive_damage(100,enemy.position,{"damage_type":"true","attacker_stats":{},"bypass_invulnerability":true}),"SW shield absorption")
	var resource:float=Game.run.resource
	check(room.player.cast_skill("secondary",enemy.position),"SW actual W")
	var paid:float=room.player.abilities.active.paid_cost
	step(.7)
	check(room.player.loadout.effects.cooldowns.has("B06-SW_4"),"SW4 real W refund")
	check(Game.run.resource>=resource-paid+Numbers.integer(paid*.15),"SW4 actual paid refund")
	check(room.player.loadout.effects.cooldowns.has("B06-SW_6"),"SW6 actual derived forward wave")
	var state:=Snapshot.capture(room)
	check(not state.is_empty(),"B06 snapshot captures")
	check(Snapshot.restore(room,JSON.parse_string(JSON.stringify(state))),"B06 snapshot restores")
func _gunner()->void:
	fixture("CH02","B06-SG")
	var first:=target(Vector2(80,0));var second:=target(Vector2(170,0))
	room.player.class_mark_target(first)
	check(room.player.cast_skill("q",first.position),"SG Q real move")
	step(.8)
	room.player.cooldowns.f=5
	check(room.player.cast_skill("secondary",first.position),"SG actual W")
	step(.8)
	check(room.player.loadout.effects.cooldowns.has("B06-SG_4"),"SG4 Q to marked W receipt")
	check(not room.player.loadout._b06_tide_mark.is_empty(),"SG6 two distinct actual pierced targets")
	check(second.health.current<second.health.maximum,"actual second penetration damage")
	Game.run.resource=Game.run.stats.resource_max
	check(room.player.cast_skill("ultimate",first.position),"SG real R "+room.player.last_cast_error)
	step(.25)
	room.player.abilities.cancel()
	var fired:=0
	for root:Dictionary in room.player.loadout.effects.roots.values():
		if root.has("b06_r_ordinals"):fired+=root.b06_r_ordinals.size()
	check(room.player.loadout.effects.cooldowns.has("B06-SG_6"),"SG6 actual fired shot activates")
	check(fired==1,"cancel after first emitted R preserves only one bonus round")
	var expiry:float=room.player.loadout.effects.cooldowns.get("B06-SG_6",0)
	step(1)
	near(room.player.loadout.effects.cooldowns.get("B06-SG_6",0),expiry,"cancel future R cannot restart ICD")
func _mage()->void:
	fixture("CH03","B06-SM")
	var enemy:=target(Vector2(80,0))
	var ring_targets:Array=[enemy,target(Vector2(100,20)),target(Vector2(100,-20)),target(Vector2(120,0)),target(Vector2(130,0))]
	check(room.player.cast_skill("f",enemy.position),"SM E actual hit")
	step(.6)
	for index in 3:
		room.player.cooldowns.q=0
		Game.run.resource=Game.run.stats.resource_max
		check(room.player.cast_skill("q",enemy.position),"SM actual paid Q "+str(index))
		step(.5)
	Game.run.resource=Game.run.stats.resource_max
	check(room.player.cast_skill("secondary",enemy.position),"SM real W")
	var radius:float=room.player.abilities.active.spec.burst_radius
	near(radius,float(room.player.abilities.spec("secondary").burst_radius)*1.1,"SM2 immediate-only radius")
	step(.3)
	check(room.player.loadout.effects.cooldowns.has("B06-SM_4"),"SM4 actual E then immediate W")
	check(room.player.loadout._b06_pending_rings.size()==1,"SM6 paid Q triple queues delayed ring")
	var ring:Dictionary=room.player.loadout._b06_pending_rings[0].duplicate(true) if not room.player.loadout._b06_pending_rings.is_empty() else {}
	var before_ring:Array=[]
	for actor:Node2D in ring_targets: before_ring.append(actor.health.current)
	get_tree().paused=true
	room.player.loadout.tick(1)
	check(room.player.loadout._b06_pending_rings.size()==1,"pause freezes pending ring")
	get_tree().paused=false
	room.player.position+=Vector2(200,0)
	Game.run.stats.ability_power*=2
	if not ring.is_empty():check(room.player.loadout._b06_pending_rings[0].damage==ring.damage and room.player.loadout._b06_pending_rings[0].burst_position==ring.burst_position,"ring frozen origin power")
	step(.85)
	check(room.player.loadout._b06_pending_rings.is_empty(),"ring releases once after .8s")
	var ring_hits:=0
	for i:int in ring_targets.size():
		if ring_targets[i].health.current<before_ring[i]:ring_hits+=1
	check(ring_hits<=4 and ring_hits>0,"bounded real ring targets count="+str(ring_hits))
	check(room.player.loadout.effects.roots.values().any(func(root:Dictionary)->bool:return bool(root.get("b06_ring_released",false))),"real delayed derived ring")
func _shared()->void:
	for hero:String in ["CH01","CH02","CH03"]:
		fixture(hero,"B06-SU")
		var enemy:=target()
		near(room.player.loadout.modifiers().received_displacement_reduction,.2,"SU2 all classes")
		check(not room.player.status.guards.has("equipment:B06-SU_4"),"SU4 no free room shield")
		room.player.loadout.tick(11.5)
		check(not room.player.status.guards.has("equipment:B06-SU_4"),"SU4 waits full period")
		var state:=Snapshot.capture(room)
		check(not state.is_empty() and Snapshot.restore(room,JSON.parse_string(JSON.stringify(state))),"SU4 period JSON resume")
		room.player.loadout.tick(.51)
		check(room.player.status.guards.has("equipment:B06-SU_4"),"SU4 period survives resume")
		room.player.grant_guard(Game.run.max_hp*.3,10,"other")
		room.player.receive_damage(Game.run.max_hp*.07,enemy.position,{"damage_type":"true","attacker_stats":{},"bypass_invulnerability":true})
		check(Game.run.shield>0,"SU4 source broken beneath larger pool")
		var ctx:Dictionary={"root_event_id":"su:direct","attack_id":"su:direct","original_basic":true,"equipment_eligible":true,"attacker_stats":Game.run.stats}
		check(room.resolve_direct_hit(enemy,100,&"primary","",0,Vector2.RIGHT,ctx),"SU6 confirmed direct trigger")
		check(room.player.loadout.effects.cooldowns.has("B06-SU_6"),"SU6 shared source ending on "+hero)
		near(room.player.loadout.modifiers().move_speed_bonus,.08,"SU6 movement bonus")
		var expiry:float=room.player.loadout.effects.cooldowns.get("B06-SU_6",0)
		room.resolve_direct_hit(enemy,100,&"primary","",0,Vector2.RIGHT,ctx)
		near(room.player.loadout.effects.cooldowns.get("B06-SU_6",0),expiry,"repeat event no double proc")
func _tide_uniques()->void:
	fixture("CH01","B06-SU",["B06-U01","B06-U02","B06-U03"])
	var enemy:=target()
	room.player.grant_guard(200,4,"test")
	room.player.receive_damage(100,enemy.position,{"damage_type":"true","attacker_stats":{},"bypass_invulnerability":true})
	Game.run.hp=Game.run.max_hp-500
	near(room.player.heal(100,"external"),108,"U02 actual received heal")
	near(room.player.loadout.modifiers().terrain_slow_reduction,.2,"U01 terrain modifier")
	near(room.player.loadout.modifiers().received_displacement_reduction,.2,"U01 does not add push resistance")
	var host:=preload("res://scripts/levels/b06/world/tide_runtime.gd").new()
	room.add_child(host);room.b06_mechanics=host
	check(host.configure("L32"),"live mechanism fixture")
	host.tick(10)
	room.player.position=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point([500,500])
	var wet_speed:float=room.player.stat("move_speed",220)
	var pushed:Vector2=host.push_actor(room.player,Vector2(40,0))
	near(pushed.length(),32,"actual tide displacement SU2 only")
	room.player.position=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point([840,990])
	near(wet_speed,room.player.stat("move_speed",220)*.88,"U01 real tide slow .85 to .88")
	room.player.position=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point([840,990])
	check(host.interact("drain_west",room.player,"player",func():return Game.run.hp>0,room.has_line_of_sight),"U03 channel starts")
	host.tick(.3);host.cancel_interaction();host.tick(.4)
	check(not room.player.status.guards.has("equipment:B06-U03"),"interrupted channel no shield")
	check(host.interact("drain_west",room.player,"player",func():return Game.run.hp>0,room.has_line_of_sight),"U03 range channel")
	room.player.position+=Vector2(500,0);host.tick(.6)
	check(not room.player.status.guards.has("equipment:B06-U03"),"out-of-range channel no shield")
	room.player.position=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point([840,990])
	check(host.interact("drain_west",room.player,"player",func():return Game.run.hp>0,room.has_line_of_sight),"U03 alive channel")
	Game.run.hp=0;host.tick(.6)
	check(not room.player.status.guards.has("equipment:B06-U03"),"dead channel no shield")
	Game.run.hp=Game.run.max_hp
	check(host.interact("drain_west",room.player,"player",func():return Game.run.hp>0,room.has_line_of_sight),"U03 second channel")
	host.tick(.6)
	check(room.player.status.guards.has("equipment:B06-U03"),"U03 actual completed drain shield")

func _cleanup_and_immune()->void:
	fixture("CH03","B06-SM")
	var enemy:=target()
	enemy.status.apply("invulnerable",1,5)
	check(room.player.cast_skill("f",enemy.position),"immune E cast succeeds")
	step(.6)
	check(not room.player.loadout.effects.windows.has("B06-SM_4:burst"),"immune E cannot arm SM4")
	enemy.status.states.clear()
	enemy.status.grant_guard_result(100,4,"test",enemy.health.maximum,false)
	var hp:float=enemy.health.current
	var ctx:Dictionary={"root_event_id":"shield_only","attack_id":"shield_only","original_basic":false,"equipment_eligible":true,"attacker_stats":Game.run.stats}
	check(room.resolve_direct_hit(enemy,20,&"f","",0,Vector2.RIGHT,ctx),"actual shield-only E confirmed")
	near(enemy.health.current,hp,"shield-only preserves HP")
	check(room.player.loadout.effects.windows.has("B06-SM_4:burst"),"shield-only E arms SM4")
	room.player.loadout.effects.counts["B06-SM_6:q"]=3
	Game.run.resource=Game.run.stats.resource_max
	check(room.player.cast_skill("secondary",enemy.position),"cleanup W commits")
	step(.3)
	check(room.player.loadout._b06_pending_rings.size()==1,"cleanup has real queued ring")
	room.player.loadout.event("room_enter",{"room_id":"different","unvisited":true})
	check(room.player.loadout._b06_pending_rings.is_empty() and not room.player.loadout.effects.counts.has("B06-SM_6:q"),"room departure clears ring and stacks")
	fixture("CH01","B06-SU")
	enemy=target()
	room.player.loadout.tick(3)
	var period:float=room.player.loadout.effects.cooldowns["B06-SU_4:period"]
	var old_stats:Dictionary=Game.run.stats.duplicate(true)
	var old_loadout:Dictionary=Game.run.stats.loadout.duplicate(true)
	var state:=Snapshot.capture(room)
	var empty_stats:Dictionary=StatResolver.resolve("CH01",30,{},Game.run.equipment_snapshot,2)
	var migrated:=Snapshot.for_loadout(state,old_loadout,{},empty_stats,"CH01",old_stats)
	check(not migrated.is_empty(),"unequip migration valid")
	if not migrated.is_empty():near(migrated.equipment.cooldowns["B06-SU_4:period"],period,"unequip preserves period")
	room.player.grant_guard(Game.run.max_hp*.06,1,"equipment:B06-SU_4")
	step(1.01)
	check(room.player.loadout.effects.windows.has("B06-SU_6:ended"),"natural shield expiry arms SU6")
	room.player.loadout.effects.windows.erase("B06-SU_6:ended")
	room.player.loadout.event("shield_source_ended",{"source":"B06-SU_4","cause":"unequipped"})
	check(not room.player.loadout.effects.windows.has("B06-SU_6:ended"),"unequip ending never arms")
