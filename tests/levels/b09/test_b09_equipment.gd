extends Node
const Catalog = preload("res://scripts/levels/b09/equipment/equipment_catalog.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Effects = preload("res://scripts/domain/combat/equipment_effects.gd")
const Forging = preload("res://scripts/domain/equipment/instance_forging.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
const Skills = preload("res://scripts/levels/b09/combat/skills.gd")
const Content = preload("res://scripts/levels/b09/world/content.gd")
var checks := 0
var failures := 0
var serial := 0
var items: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("B09 EQUIPMENT: "+label)

func near(value: float, expected: float, label: String) -> void:
	check(is_equal_approx(value,expected),label+" actual="+str(value))

func ctx(extra: Dictionary = {}) -> Dictionary:
	serial+=1
	var id := "gear:"+str(serial)
	var context := {"event_id":id,"attack_id":id,"root_event_id":id,"target_id":"one","target_alive":true,"hp":500,"max_hp":1000,"resource":100,"resource_max":1000,"resource_type":"mana","H":100,"X":300,"equipment_eligible":true,"original_basic":false,"damage_source":"skill","proc_depth":0,"confirmed":true,"paid_cost":100,"cast_success":true,"combat_active":true,"skill_slot":"secondary","slot":"secondary","target_states":[],"attacker_stats":{"attack":100,"ability_power":200}}
	context.merge(extra,true)
	return context

func fx(set_id: String = "", count: int = 6, unique: String = "") -> RefCounted:
	var effect := Effects.new()
	effect.stats={"ruleset_version":2,"attack":100,"ability_power":200,"max_hp":1000,"resource_max":1000}
	effect.resource_type="mana"
	if not set_id.is_empty(): effect.set_counts[set_id]=count
	if not unique.is_empty(): effect.equipped[unique]=true
	return effect

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if OS.get_cmdline_user_args().has("--b09-release-gate"):
		check(not Rules.b09_candidate_enabled(),"ordinary profile lacks B09 candidate")
		check(int(Rules.value("implemented_chapters"))==6,"six formal chapters remain released")
		check(preload("res://scripts/domain/progression/hero_progression.gd").level_cap()==30,"formal level cap30")
		check(ContentRegistry.equipment_ids(2).size()==194,"formal catalog retains194 released templates")
		check(ContentRegistry.equipment("B09-SW-weapon",2).is_empty(),"B09 definition inaccessible outside strict candidate")
		check(not ContentRegistry.sets(2).has("B09-SW"),"B09 sets inaccessible")
		var denied := Acquisition.roll_item({"instance_id":"unreleased","source_event_id":"unreleased","template_id":"B09-SW-weapon","rarity":"purple","power_type":"physical","item_level":45,"source":"drop","hero_id":"CH01"},1)
		check(denied.is_empty(),"new B09 instance creation refuses production")
		var event := Acquisition.roll_event({"event_id":"unreleased","seed":1,"source":"room","race_id":"B09","difficulty":0,"challenge_level":41,"hero_id":"CH01","power_type":"physical","room_id":"L49"})
		check(not bool(event.get("ok",false)),"new B09 drop refuses production")
		check(Acquisition.current_version_error().is_empty(),"existing acquisition remains valid")
		print("B09 EQUIPMENT RELEASE GATE: %d checks, %d failures" % [checks,failures])
		get_tree().quit(0 if failures==0 else 1)
		return
	if not Rules.b09_candidate_enabled(): push_error("B09 equipment requires isolated candidate flag/profile"); get_tree().quit(2); return
	_catalog()
	_warrior()
	_gunner()
	_mage()
	_shared()
	_uniques()
	_lifecycle()
	await _live()
	print("B09 EQUIPMENT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func _catalog() -> void:
	check(Catalog.validate().is_empty(),"authored 35 templates/four sets")
	check(ContentRegistry.validate(2).is_empty(),"shared registry validates candidate")
	check(Acquisition.current_version_error().is_empty(),"generation preserves v1-v4 archive")
	check(int(Rules.value("implemented_chapters"))==6,"candidate preserves six formal chapters")
	for hero: String in ["CH01","CH02","CH03"]:
		var pool := Acquisition.natural_pool("B09",hero,5)
		var count := 0
		check(pool.size()==8,hero+" eight slots")
		for ids: Array in pool.values(): count+=ids.size()
		check(count==19,hero+" 8 profession + 8 shared + 3 unique")
	for id: String in Catalog.equipment_ids():
		var definition := ContentRegistry.equipment(id,2)
		var hero: String=definition.allowed_heroes[0]
		var item := Acquisition.roll_item({"instance_id":"actual:"+id,"source_event_id":"fixture:"+id,"template_id":id,"rarity":"purple","power_type":"magic" if hero=="CH03" else "physical","item_level":45,"source":"drop","location":"inventory","hero_id":hero},731)
		check(not item.is_empty(),id+" real randomized instance")
		if item.is_empty(): continue
		items[item.instance_id]=item
		check(Instances.validate(item).is_empty(),id+" instance provenance/stat bounds")
		check(Forging._item_error(item).is_empty(),id+" enhancement canonical price at45")
		check(not Instances.stats(item).is_empty(),id+" actual main and random stats")
		for character: String in ["CH01","CH02","CH03"]:
			check(Instances.can_equip(item,character,45)==(character in definition.allowed_heroes),id+" full-slot class "+character)
		check(not Instances.can_equip(item,hero,20),id+" item-level qualification")
		var loadout := {definition.slot:item.instance_id}
		var stats := Resolver.resolve(hero,45,loadout,{item.instance_id:item},2)
		check(not stats.is_empty() and stats.equipment_templates.get(definition.slot)==id,id+" real resolver/traits binding")
		var instance := Effects.new()
		instance.configure(loadout,stats,str(stats.get("resource_type","")))
		check(instance.equipped.has(id),id+" fixed trait from validated instance")
		var restored: Dictionary=JSON.parse_string(JSON.stringify(item))
		check(Instances.validate(restored).is_empty(),id+" JSON reload validation")
	for d in 5:
		var event := {"event_id":"bossgear:"+str(d),"seed":37,"source":"boss","race_id":"B09","difficulty":d,"challenge_level":45,"hero_id":"CH03","power_type":"magic","room_id":"BO09","force_gold":d==4}
		var receipt := Acquisition.roll_event(event)
		check(bool(receipt.get("ok",false)),"D"+str(d)+" actual queen drop receipt")
		if not bool(receipt.get("ok",false)): continue
		check(receipt.items.size()==int(Rules.value("boss_drop_counts")[d]),"boss keeps authored count D"+str(d))
		check(Acquisition.event_result_valid(receipt),"full receipt frozen replay D"+str(d))
		check(Acquisition.roll_event(event,receipt)==receipt,"no reroll on retry D"+str(d))
		if d==4: check(receipt.items.any(func(value: Dictionary) -> bool: return value.rarity=="gold"),"D4 force-gold replaces instead of adds")
	check(Acquisition.natural_pool("B09","",5).is_empty(),"no classless pool")
	var invalid := Acquisition.roll_item({"instance_id":"bad","source_event_id":"bad","template_id":"B09-SW-weapon","rarity":"green","power_type":"magic","item_level":45,"source":"drop","hero_id":"CH03"},1)
	check(invalid.is_empty(),"wrong exclusive power rejects")

func _warrior() -> void:
	var e := fx("B09-SW")
	near(e.handle("before_hit",ctx()).get("b09_shield_damage_bonus",0),0.12,"SW2 W shield-only bonus")
	near(e.handle("before_hit",ctx({"skill_slot":"q"})).get("b09_shield_damage_bonus",0),0,"SW2 no Q bonus")
	var cast := ctx({"b09_layers_before":2})
	check(e.handle("after_hit",cast).has("b09_break_layer"),"SW4 confirmed W extra layer")
	cast.attack_id="second_tick"; cast.target_id="two"
	check(not e.handle("after_hit",cast).has("b09_break_layer"),"SW4 one extra layer per W")
	e=fx("B09-SW")
	var hit := ctx({"b09_layers_before":0})
	var out: Dictionary=e.handle("after_hit",hit)
	check(out.bonus_hits.size()==1 and out.bonus_hits[0].damage==20,"SW4 no crystal adds0.20AD")
	check(e.handle("after_hit",ctx()).bonus_hits.is_empty(),"SW4 ICD7")
	e.advance(7.0,ctx())
	check(e.handle("after_hit",ctx()).bonus_hits.size()==1,"SW4 exact ICD release")
	e=fx("B09-SW")
	e.handle("b09_barrier_broken",ctx())
	var miss := ctx({"confirmed":false})
	e.handle("after_hit",miss)
	check(e._window("B09-SW_6:next_w"),"SW6 miss preserves 6s window")
	hit=ctx()
	near(e.handle("before_hit",hit).damage_bonus,0.12,"SW6 next W +12% preview")
	check(e._window("B09-SW_6:next_w"),"before-hit preview never spends token")
	out=e.handle("after_hit",hit)
	near(out.get("heal_amount",0),30,"SW6 confirmed W heals3%")
	check(not e._window("B09-SW_6:next_w"),"SW6 window consumed by hit")
	e.handle("b09_barrier_broken",ctx())
	check(not e._window("B09-SW_6:next_w"),"SW6 ICD10 blocks rearm")
	e=fx("B09-SW")
	e.handle("b09_barrier_broken",ctx({"damage_source":"equipment","proc_depth":1}))
	check(not e._window("B09-SW_6:next_w"),"derived break cannot arm")
	e=fx("B09-SW")
	hit=ctx()
	near(e.handle("before_hit",hit).damage_bonus,0,"breaking W starts without future bonus")
	e.handle("b09_barrier_broken",hit)
	near(e.handle("after_hit",hit).get("heal_amount",0),0,"breaking W does not consume newly armed heal")
	check(e._window("B09-SW_6:next_w"),"breaking W keeps future window")
	hit.attack_id="same_cast_other_target"; hit.target_id="two"
	near(e.handle("before_hit",hit).damage_bonus,0,"remaining targets in breaking W lack future bonus")
	near(e.handle("after_hit",hit).get("heal_amount",0),0,"remaining breaking W targets cannot heal")
	check(e._window("B09-SW_6:next_w"),"remaining targets preserve next W token")
	near(e.handle("before_hit",ctx()).damage_bonus,0.12,"later cast uses newly armed token")

func _gunner() -> void:
	var e := fx("B09-SG")
	near(e.handle("before_hit",ctx({"skill_slot":"f"})).damage_bonus,0.08,"SG2 E directly +8%")
	var hit := ctx({"skill_slot":"f"})
	var out: Dictionary=e.handle("after_hit",hit)
	check(e._window("B09-SG_4:mark:one"),"SG4 own E creates frostline mark")
	near(out.b09_slow.multiplier,0.90,"SG4 normal10% ordinary slow")
	out=e.handle("after_hit",ctx())
	check(out.bonus_hits.size()==1 and out.bonus_hits[0].damage==40,"SG6 W adds0.40AD")
	check(not e._window("B09-SG_4:mark:one"),"SG6 consumes mark")
	near(e.passive_modifiers(ctx()).move_speed_bonus,0.08,"SG6 speed8%")
	e.advance(3.0,ctx())
	near(e.passive_modifiers(ctx()).move_speed_bonus,0,"SG6 speed expires3s")
	e=fx("B09-SG")
	out=e.handle("after_hit",ctx({"skill_slot":"f","b09_target_boss":true}))
	near(out.b09_slow.multiplier,0.95,"SG4 Boss5% slow")
	e.advance(4.0,ctx())
	check(e.handle("after_hit",ctx()).bonus_hits.is_empty(),"SG6 mark expires4s")
	e=fx("B09-SG")
	check(e.handle("after_hit",ctx()).bonus_hits.is_empty(),"no mark means ordinary W unaffected")

func _mage() -> void:
	var e := fx("B09-SM")
	near(e.handle("before_hit",ctx({"skill_slot":"f"})).damage_bonus,0.08,"SM2 E +8%")
	var cast := ctx({"skill_slot":"f"})
	near(e.handle("after_hit",cast).resource_restore,0,"SM4 one normal enemy no refund")
	cast.target_id="two"
	near(e.handle("after_hit",cast).resource_restore,60,"SM4 same E two distinct targets restores60")
	cast.target_id="three"
	near(e.handle("after_hit",cast).resource_restore,0,"SM4 cast only once")
	e=fx("B09-SM")
	near(e.handle("after_hit",ctx({"skill_slot":"f","b09_single_boss":true})).resource_restore,30,"SM4 single Boss restores30")
	e=fx("B09-SM")
	near(e.handle("after_hit",ctx({"skill_slot":"f","b09_single_boss":true,"paid_cost":0})).resource_restore,0,"SM4 must actually pay")
	for slot: String in ["secondary","ultimate"]:
		e=fx("B09-SM")
		cast=ctx({"slot":slot,"skill_slot":slot})
		e.handle("skill_cast",cast)
		for i in 4:
			cast.target_id="target"+str(i)
			e.handle("after_hit",cast)
			check(e._window("B09-SM_6:mark:"+str(cast.target_id))==(i<3),"SM6 "+slot+" first segment max3 target "+str(i))
		for i in 3:
			var out: Dictionary=e.handle("after_hit",ctx({"skill_slot":"q","target_id":"target"+str(i)}))
			check(out.bonus_hits.size()==1 and out.bonus_hits[0].damage==50,"SM6 Q0.25AP consumes individual mark")
			check(not e._window("B09-SM_6:mark:target"+str(i)),"SM6 each mark once")
		e.handle("skill_cast",ctx({"skill_slot":slot}))
		check(not e.roots.values().back().get("b09_condense_armed",false),"SM6 ICD10 blocks next paid round")

func _shared() -> void:
	var e := fx("B09-SU")
	near(e.b09_slow_duration(5.0),4.0,"SU2 normal slow duration-20%")
	near(e.b05_control_duration(5.0),5.0,"SU2 does not cancel root/bridge")
	near(e.passive_modifiers(ctx({"hp":499})).b09_direct_reduction,0.08,"SU4 below50%")
	near(e.passive_modifiers(ctx({"hp":500})).b09_direct_reduction,0,"SU4 threshold strict")
	var out: Dictionary=e.handle("damaged",ctx({"enemy_damage":true,"hp_damage":99}))
	check(out.shields.is_empty(),"SU6 real damage below10%")
	out=e.handle("damaged",ctx({"enemy_damage":true,"hp_damage":1}))
	check(bool(out.get("b09_cleanse",false)) and out.shields.size()==1,"SU6 threshold cleanses and shields")
	near(out.shields[0].ratio,0.03,"SU6 shield3% maxHP")
	near(out.shields[0].duration,4.0,"SU6 shield4s")
	check(e.handle("damaged",ctx({"enemy_damage":true,"hp_damage":100})).shields.is_empty(),"SU6 ICD15")
	e=fx("B09-SU")
	check(e.handle("damaged",ctx({"enemy_damage":false,"hp_damage":999})).shields.is_empty(),"SU6 self damage rejected")
	check(e.handle("damaged",ctx({"enemy_damage":true,"hp_damage":0,"shield_absorbed":999})).shields.is_empty(),"SU6 only HP loss counts")

func _uniques() -> void:
	var e := fx("",0,"B09-U01")
	near(e.passive_modifiers(ctx()).b09_glide_distance_scale,0.75,"U01 original ice glide25% shorter")
	e=fx("",0,"B09-U02")
	near(e.handle("ordinary_negative_cleared",ctx({"actually_cleared":false})).get("heal_amount",0),0,"U02 failed cleanse heals0")
	near(e.handle("ordinary_negative_cleared",ctx({"actually_cleared":true})).get("heal_amount",0),20,"U02 actual cleanse heals2%")
	near(e.handle("ordinary_negative_cleared",ctx({"actually_cleared":true})).get("heal_amount",0),0,"U02 ICD15")
	e=fx("",0,"B09-U03")
	e.handle("b09_barrier_broken",ctx())
	near(e.passive_modifiers(ctx()).damage_reduction_bonus,0.06,"U03 break grants6%4s")
	e.advance(4.0,ctx())
	near(e.passive_modifiers(ctx()).damage_reduction_bonus,0,"U03 expires")
	e.handle("b09_barrier_broken",ctx())
	near(e.passive_modifiers(ctx()).damage_reduction_bonus,0,"U03 ICD12 prevents refresh")

func _lifecycle() -> void:
	for id: String in ["B09-SW","B09-SG","B09-SM","B09-SU"]:
		var e := fx(id,1)
		near(e.handle("before_hit",ctx({"skill_slot":"f"})).damage_bonus,0,id+" one piece no2 bonus")
		e=fx(id)
		e.windows[id+"_6:temporary"]=e.clock+4
		e.cooldowns[id+"_6"]=e.clock+10
		e.handle("room_enter",ctx({"room_id":"next"}))
		check(not e.windows.has(id+"_6:temporary") and e.cooldowns.has(id+"_6"),id+" room clears temporary, retains ICD")
	var e := fx("B09-SW")
	check(e.handle("after_hit",ctx({"proc_depth":1})).bonus_hits.is_empty(),"derived hits cannot recursively trigger")
	var hit := ctx()
	hit.root_packets_used=4
	check(e.handle("after_hit",hit).bonus_hits.is_empty(),"four native packets prevent fifth equipment packet")

func _live() -> void:
	Game.run=null
	check(Game.new_profile() and Game.start_run(),"real isolated game session")
	var room = load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	for actor in room.enemies.get_children(): actor.free()
	var route := Traversal.new()
	check(route.configure(room,0,271) and route.start(),"real B09 room")
	var loadout := {}
	for item: Dictionary in items.values():
		if str(item.template_id).begins_with("B09-SW-"): loadout[ContentRegistry.equipment(item.template_id,2).slot]=item.instance_id
	var stats := Resolver.resolve("CH01",45,loadout,items,2)
	Game.run.hero_id="CH01"; Game.run.level=45; Game.run.stats=stats; Game.run.loadout_snapshot=loadout; Game.run.equipment_snapshot=items
	Game.run.max_hp=stats.max_hp; Game.run.hp=stats.max_hp*0.5
	room.player.loadout.configure(room.player)
	var enemy: Node2D=room.spawn_enemy(Vector2(500,500),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,0)})
	check(room.resolve_direct_hit(enemy,20,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:W","attack_id":"live:W","attacker_stats":stats}),"real W contact")
	check(int(enemy.get_meta("b09_layers"))==0,"real SW4 W removes both layers")
	check(room.player.loadout.effects._window("B09-SW_6:next_w"),"real last-layer break arms next W")
	room.player.status.apply("burn",10,2)
	room.player.status.apply("bleed",10,5)
	room.player._enemy_slow_remaining=3
	check(room.player.clear_ordinary_negative() and not room.player.status.has("bleed") and room.player.status.has("burn"),"real cleanse longest DOT first")
	check(room.player.clear_ordinary_negative() and not room.player.status.has("burn"),"real cleanse remaining DOT")
	check(room.player.clear_ordinary_negative() and room.player._enemy_slow_remaining==0,"real cleanse normal slow after DOT")
	check(not room.player.clear_ordinary_negative(),"real empty cleanse no event")
	var snapshot := Snapshot.capture(room)
	check(not snapshot.is_empty() and Snapshot.validate(snapshot,"CH01",stats),"real snapshot accepts B09 modifier/state")
	var unequipped := Resolver.resolve("CH01",45,{},items,2)
	var replacement := Snapshot.for_loadout(snapshot,loadout,{},unequipped,"CH01",stats)
	check(not replacement.is_empty(),"snapshot can unequip B09 source")
	if not replacement.is_empty():
		check(replacement.equipment.cooldowns==snapshot.equipment.cooldowns,"unequip cannot refresh ICDs")
		check(not replacement.equipment.windows.has("B09-SW_6:next_w"),"unequip removes unconsumed source window")
	enemy.set_meta("b09_layers",0)
	enemy.status.grant_guard(500,4,"fixture_shield",enemy.health.maximum)
	var before_shield: float=enemy.status.shield()
	var before_hp: float=enemy.health.current
	enemy.take_damage(100,&"secondary",Vector2.RIGHT,{"damage_type":"true","root_event_id":"shieldbonus","equipment_eligible":true,"proc_depth":0,"b09_shield_damage_bonus":0.12})
	near(before_shield-enemy.status.shield(),112,"live SW2 shield receives12% bonus")
	near(before_hp-enemy.health.current,0,"SW2 shield bonus never spills into HP")
	for actor in room.enemies.get_children(): actor.free()
	_bind(room,"CH02","B09-SG")
	enemy=room.spawn_enemy(Vector2(550,500),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,0)})
	enemy.health.maximum=1000000; enemy.health.current=1000000
	check(room.resolve_direct_hit(enemy,20,&"f","",0,Vector2.RIGHT,{"root_event_id":"live:SG:E","attack_id":"live:SG:E"}),"live gunner E")
	near(enemy._ordinary_slow_multiplier,0.9,"live frostline slow10%")
	check(room.player.loadout.effects._window("B09-SG_4:mark:"+str(enemy.get_instance_id())),"live E owns its mark")
	check(room.resolve_direct_hit(enemy,20,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:SG:W","attack_id":"live:SG:W"}),"live gunner W")
	check(not room.player.loadout.effects._window("B09-SG_4:mark:"+str(enemy.get_instance_id())),"live W consumes own frostline")
	near(room.player.loadout.modifiers().move_speed_bonus,0.08,"live SG6 speed modifier applied")
	for actor in room.enemies.get_children(): actor.free()
	_bind(room,"CH03","B09-SM")
	room.player.position=Vector2(500,500)
	var group: Array[Node2D]=[]
	for i in 4:
		var actor: Node2D=room.spawn_enemy(Vector2(540+i*5,500),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,0)})
		actor.health.maximum=1000000; actor.health.current=1000000
		group.append(actor)
	var mana_before: float=Game.run.resource
	check(room.player.cast_skill("f",Vector2(540,500)),"real paid mage E submits")
	var paid: float=float(room.player.abilities.active.paid_cost)
	check(paid>0,"real mage E paid mana")
	room.player.abilities.tick(2.0)
	near(Game.run.resource,mana_before-paid+60,"live SM4 actual E two+ hits restores60")
	check(room.player.cast_skill("secondary",Vector2(540,500)),"real paid mage W submits")
	room.player.abilities.tick(2.0)
	var marked := 0
	for actor: Node2D in group:
		if room.player.loadout.effects._window("B09-SM_6:mark:"+str(actor.get_instance_id())): marked+=1
	check(marked==3,"live W first burst marks maximum three")
	var q: Dictionary={"root_event_id":"live:SM:Q","attack_id":"live:SM:Q","paid_cost":50}
	for actor: Node2D in group:
		room.resolve_direct_hit(actor,20,&"q","",0,Vector2.RIGHT,q)
	check(room.player.loadout.effects.windows.keys().all(func(key: String) -> bool: return not key.begins_with("B09-SM_6:mark:") or not room.player.loadout.effects._window(key)),"live Q consumes each marked target")
	for actor in room.enemies.get_children(): actor.free()
	_bind(room,"CH03","B09-SM")
	var queen = load("res://scenes/gameplay/bosses/boss.tscn").instantiate()
	queen.room=room
	queen.position=Vector2(550,500)
	queen.configure(Skills.boss_profile(0))
	room.enemies.add_child(queen)
	room.b09_mechanics.register_actor(queen)
	mana_before=Game.run.resource
	check(room.player.cast_skill("f",queen.position),"actual paid E versus real Queen")
	paid=float(room.player.abilities.active.paid_cost)
	room.player.abilities.tick(2.0)
	near(Game.run.resource,mana_before-paid+30,"live single-Queen E refund30")
	_bind(room,"CH02","B09-SG")
	room.resolve_direct_hit(queen,20,&"f","",0,Vector2.RIGHT,{"root_event_id":"live:SG:BossE","attack_id":"live:SG:BossE"})
	near(queen._ordinary_slow_multiplier,0.95,"real Queen ordinary slow5%")
	_bind(room,"CH01","B09-SU")
	Game.run.hp=Game.run.max_hp*0.49
	room.player.status.apply("burn",10,2)
	room.player.status.apply("bleed",10,5)
	room.player.loadout.effects.counts["B09-SU_6:damage"]=int(Game.run.max_hp*0.1)-1
	room.player.invulnerable=0
	check(room.player.receive_damage(100,room.player.position+Vector2(30,0),{"damage_type":"true"}),"live SU actual enemy damage")
	check(not room.player.status.has("bleed") and room.player.status.has("burn"),"live SU6 commands cleanse longest DOT")
	check(room.player.status.guards.has("equipment:B09-SU_6"),"live SU6 commands actual3% shield")
	_bind(room,"CH01","B09-SU")
	Game.run.hp=Game.run.max_hp*0.49
	room.player.invulnerable=0
	room.player.receive_damage(100,room.player.position,{"damage_type":"true","self_damage":true})
	check(not room.player.loadout.effects.counts.has("B09-SU_6:damage"),"live self damage cannot contribute to SU6")
	_bind(room,"CH01","B09-SW")
	var warm_loadout: Dictionary=Game.run.loadout_snapshot.duplicate(true)
	warm_loadout["charm"]="actual:B09-U03"
	Game.run.stats=Resolver.resolve("CH01",45,warm_loadout,items,2)
	Game.run.loadout_snapshot=warm_loadout
	room.player.loadout.configure(room.player)
	var lamp: String=room.b09_mechanics.lamps.keys()[0]
	room.player.position=room.b09_mechanics.lamps[lamp].at
	queen.position=room.player.position+Vector2(20,0)
	queen.set_meta("b09_layers",1)
	room.b09_mechanics.lamps[lamp].ready=0.0
	check(room.b09_mechanics.activate_lamp(lamp),"actual warm lamp completes")
	check(room.player.loadout.effects._window("B09-SW_6:next_w"),"warm lamp final Queen layer arms SW6")
	near(room.player.loadout.modifiers().damage_reduction_bonus,0.06,"warm lamp final layer triggers U03 guard")
	var ice_loadout: Dictionary={"feet":"actual:B09-U01"}
	Game.run.stats=Resolver.resolve("CH01",45,ice_loadout,items,2)
	Game.run.loadout_snapshot=ice_loadout
	room.player.loadout.configure(room.player)
	room.b09_mechanics.lamps[lamp].warm_until=0.0
	room.player.position=Content.rect(Content.room("L49").ice_rects[0]).get_center()
	room.b09_mechanics.cancel_glide(room.player)
	room.b09_mechanics.movement_velocity(room.player,Vector2.RIGHT,Vector2(220,0),0.1)
	var distance := Vector2.ZERO
	for i in 5: distance+=room.b09_mechanics.movement_velocity(room.player,Vector2.ZERO,Vector2.ZERO,0.05)*0.05
	near(distance.length(),30.0,"real U01 ice glide30 pixels instead of40")
	for actor in room.enemies.get_children(): actor.free()
	_bind(room,"CH01","B09-SW")
	warm_loadout=Game.run.loadout_snapshot.duplicate(true)
	warm_loadout["charm"]="actual:B09-U03"
	Game.run.stats=Resolver.resolve("CH01",45,warm_loadout,items,2)
	Game.run.loadout_snapshot=warm_loadout
	room.player.loadout.configure(room.player)
	room.player.position=Vector2(1100,650)
	var bearer: Node2D=room.spawn_enemy(Vector2(900,500),"B09-M05",41,{"profile":Skills.profile("B09-M05",41,0)})
	bearer.state=&"execute"
	room.enemy_skills.emit_skill(bearer,Skills.active(bearer.profile,bearer.position,Vector2(900,650)))
	check(not room.b09_mechanics.walls.is_empty(),"actual M05 releases destructible ice shield")
	if not room.b09_mechanics.walls.is_empty():
		var shield: Node2D=room.b09_mechanics.walls.back().actor.get_ref()
		check(bool(shield.get_meta("b09_enemy_shield",false)),"M05 shield receives exact shield-body identity")
		var bearer_hp: float=bearer.health.current
		before_hp=shield.health.current
		shield.take_damage(100,&"secondary",Vector2.RIGHT,{"damage_type":"true","damage_source":"skill","root_event_id":"live:M05:shieldtap","equipment_eligible":true,"proc_depth":0,"b09_shield_damage_bonus":0.12})
		near(before_hp-shield.health.current,112,"real M05 shield body W112%")
		near(bearer.health.current,bearer_hp,"shield body bonus cannot spill into M05")
		var breaking_hp: float=Game.run.hp
		check(room.resolve_direct_hit(shield,1000000,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:M05:shieldbreak","attack_id":"live:M05:shieldbreak","damage_type":"true"}),"real W destroys M05 ice shield")
		check(room.player.loadout.effects._window("B09-SW_6:next_w"),"real M05 shield break arms SW6")
		near(Game.run.hp,breaking_hp,"real shield-breaking W does not heal early")
		near(room.player.loadout.modifiers().damage_reduction_bonus,0.06,"real M05 shield break grants U03")
		bearer.set_meta("b09_layers",0)
		check(room.resolve_direct_hit(bearer,20,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:M05:nextW","attack_id":"live:M05:nextW","damage_type":"true"}),"next real W confirms against shield owner")
		near(Game.run.hp-breaking_hp,Rules.integer(Game.run.max_hp*0.03),"real next W consumes3% heal")
		check(not room.player.loadout.effects._window("B09-SW_6:next_w"),"real next W consumes shield-break token")
	_bind(room,"CH01","B09-SW")
	var layer_target: Node2D=room.spawn_enemy(Vector2(1000,500),"B09-M01",41,{"profile":Skills.profile("B09-M01",41,0)})
	layer_target.set_meta("b09_layers",1)
	var layer_hp: float=Game.run.hp
	check(room.resolve_direct_hit(layer_target,20,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:lastlayer:W","attack_id":"live:lastlayer:W","damage_type":"true"}),"real W hits final crystal layer")
	check(int(layer_target.get_meta("b09_layers"))==0 and room.player.loadout.effects._window("B09-SW_6:next_w"),"same W final-layer event preserves next W window")
	near(Game.run.hp,layer_hp,"final-layer-breaking W does not heal early")
	check(room.resolve_direct_hit(layer_target,20,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:lastlayer:nextW","attack_id":"live:lastlayer:nextW","damage_type":"true"}),"real next W after crystal break")
	near(Game.run.hp-layer_hp,Rules.integer(Game.run.max_hp*0.03),"next W after final layer heals3%")
	check(not room.player.loadout.effects._window("B09-SW_6:next_w"),"next W consumes final-layer token")
	_bind(room,"CH01","B09-SW")
	warm_loadout=Game.run.loadout_snapshot.duplicate(true)
	warm_loadout["charm"]="actual:B09-U03"
	Game.run.stats=Resolver.resolve("CH01",45,warm_loadout,items,2)
	Game.run.loadout_snapshot=warm_loadout
	room.player.loadout.configure(room.player)
	var mason: Node2D=room.spawn_enemy(Vector2(900,500),"B09-M12",41,{"profile":Skills.profile("B09-M12",41,0)})
	mason.state=&"execute"
	room.enemy_skills.emit_skill(mason,Skills.active(mason.profile,mason.position,Vector2(900,650)))
	check(not room.b09_mechanics.walls.is_empty(),"actual M12 releases ordinary crystal wall")
	if not room.b09_mechanics.walls.is_empty():
		var wall: Node2D=room.b09_mechanics.walls.back().actor.get_ref()
		check(is_instance_valid(wall) and not bool(wall.get_meta("b09_enemy_shield",false)),"ordinary M12 wall is not an enemy shield")
		if is_instance_valid(wall):
			before_hp=wall.health.current
			wall.take_damage(100,&"secondary",Vector2.RIGHT,{"damage_type":"true","damage_source":"skill","root_event_id":"live:M12:walltap","equipment_eligible":true,"proc_depth":0,"b09_shield_damage_bonus":0.12})
			near(before_hp-wall.health.current,100,"ordinary crystal wall receives no shield multiplier")
			check(room.resolve_direct_hit(wall,1000000,&"secondary","",0,Vector2.RIGHT,{"root_event_id":"live:M12:wallbreak","attack_id":"live:M12:wallbreak","damage_type":"true"}),"real W destroys ordinary crystal wall")
			check(not room.player.loadout.effects._window("B09-SW_6:next_w"),"ordinary wall death cannot arm SW6")
			near(room.player.loadout.modifiers().damage_reduction_bonus,0,"ordinary wall death cannot grant U03")
	room.free()
	await get_tree().process_frame

func _bind(room: Node2D, hero: String, set_id: String) -> void:
	for node: Node2D in room.player.resonance_nodes(): node.free()
	room.player.passives.reset()
	var loadout := {}
	for item: Dictionary in items.values():
		if str(item.template_id).begins_with(set_id+"-"): loadout[ContentRegistry.equipment(item.template_id,2).slot]=item.instance_id
	var stats := Resolver.resolve(hero,45,loadout,items,2)
	Game.run.hero_id=hero; Game.run.level=45; Game.run.stats=stats
	Game.run.loadout_snapshot=loadout; Game.run.equipment_snapshot=items
	Game.run.max_hp=stats.max_hp; Game.run.hp=stats.max_hp*0.5
	Game.run.resource=stats.resource_max*0.5; Game.run.shield=0
	room.player.status.states.clear(); room.player.status.guards.clear()
	room.player._enemy_slow_remaining=0; room.player._enemy_root_remaining=0
	room.player.cooldowns={"q":0.0,"secondary":0.0,"f":0.0,"ultimate":0.0}
	room.player.attack_remaining=0; room.player.dash_remaining=0
	room.player.abilities.configure(room.player)
	room.player.loadout.configure(room.player)
	room.input_blocked=false; room.release_gate=false
