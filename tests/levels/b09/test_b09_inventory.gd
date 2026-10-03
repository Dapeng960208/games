extends Node
const Inventory = preload("res://scripts/levels/b09/equipment/candidate_inventory.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
var checks := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(detail)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(preload("res://scripts/infrastructure/content/runtime_rules.gd").b09_candidate_enabled(),"strict B09 candidate required")
	if failures: get_tree().quit(1); return
	Game.run=null
	check(Game.new_profile(),"isolated new profile")
	Game.profile.selected_hero="CH01"
	check(Game.start_run(),"candidate run")
	var inventory := Inventory.new()
	check(inventory.configure(),"Lv45 inventory configuration")
	var room: Node2D=load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	var route := Traversal.new()
	check(route.configure(room,4,309) and route.start(),"actual B09 room route")
	inventory.attach_room(room)
	room.set_process(false)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var wallet: int=Game.profile.permanent_gold
	var xp: Dictionary=Game.profile.hero_xp.duplicate(true)
	var unlocks: Array=Game.profile.bosses.duplicate()
	check(inventory.grant_catalog(),"19 real generated test instances: "+inventory.last_error)
	var count := 0
	for item: Dictionary in Game.profile.equipment.values():
		if not str(item.template_id).begins_with("B09-"): continue
		count+=1
		check(Instances.validate(item).is_empty(),"validated B09 instance "+item.template_id)
		check(Instances.can_equip(item,"CH01",45),"actual hero equip qualification "+item.template_id)
		check(not Instances.can_equip(item,"CH01",40),"item level lock "+item.template_id)
	check(count==19,"full 8+8+3 playable catalog")
	var before := JSON.stringify(Game.profile.equipment)
	check(inventory.grant_catalog() and JSON.stringify(Game.profile.equipment)==before,"catalog grant idempotence")
	Game.run.hp=floorf(Game.run.max_hp*0.4)
	Game.run.resource=10
	room.player.cooldowns.secondary=5.0
	room.player.dash_cooldown=2.0
	var hp: float=Game.run.hp
	for slot: String in ["weapon","head","chest","hands","legs","charm"]:
		check(inventory.equip("b09_catalog:CH01:B09-SW-"+("accessory" if slot=="charm" else slot)),"equip real instance "+slot+": "+inventory.last_error)
	check(int(Game.run.stats.sets.get("B09-SW",0))==6,"resolved six-piece actual set")
	check(Game.run.hp<=hp and Game.run.resource<=10,"equip cannot heal or refill resource")
	check(room.player.cooldowns.secondary==5.0 and room.player.dash_cooldown==2.0,"equip keeps spent cooldowns")
	var clock: float=room.player.loadout.effects.clock
	room.player.loadout.effects.cooldowns["B09-SW_6"]=clock+10
	check(inventory.equip("","charm") and inventory.equip("b09_catalog:CH01:B09-SW-accessory"),"remove and re-equip threshold")
	check(room.player.loadout.effects.cooldowns.get("B09-SW_6",0)==clock+10,"re-equip does not reset ICD")
	check(not inventory.equip("unknown_instance"),"reject unowned instance")
	# Choose a deterministic seed that passes the unchanged 1% normal gate;
	# then use real actor death callbacks to check admission, cap and dedupe.
	var kill_before: int=Game.profile.equipment.size()
	for index in 3:
		var spawn := "inventory_kill_"+str(index)
		var kill_event: String="b09_kill:"+Game.run.id+":L49:"+spawn
		var selected_seed := -1
		for candidate_seed in 10000:
			if preload("res://scripts/domain/equipment/equipment_acquisition.gd")._chance(preload("res://scripts/domain/equipment/equipment_acquisition.gd")._rng(candidate_seed,kill_event,"trigger:normal",5),0.01): selected_seed=candidate_seed; break
		check(selected_seed>=0,"find reproducible natural chance fixture")
		room.layout_seed=selected_seed
		var actor: Node2D=room.spawn_enemy(Vector2(600,500),"B09-M01",41,{"profile":preload("res://scripts/levels/b09/combat/skills.gd").profile("B09-M01",41,4),"reward_spawn_id":spawn})
		check(actor!=null,"real rewarded actor fixture")
		if actor==null: continue
		actor.set_physics_process(false)
		actor.take_damage(10000000,&"primary",Vector2.RIGHT,{"damage_type":"true"})
		check(inventory.receipts.has(kill_event) and inventory.receipts[kill_event].triggered,"actual kill callback uses natural gate")
		check(Game.profile.equipment.size()==kill_before+mini(2,index+1),"normal room cap two items")
		check(inventory.kill_reward(actor) and Game.profile.equipment.size()==kill_before+mini(2,index+1),"repeated kill does not duplicate")
		await get_tree().process_frame
	check(inventory.clear_reward("L49",4,309),"natural clear reward "+inventory.last_error)
	var event: String="b09_clear:"+Game.run.id+":L49"
	check(inventory.receipts[event].generator_version==5 and inventory.receipts[event].items.size()==1,"natural generator v5 room count")
	var receipt: Dictionary=inventory.receipts[event].duplicate(true)
	var saved := JSON.stringify(Game.profile.equipment)
	check(inventory.clear_reward("L49",4,309) and JSON.stringify(Game.profile.equipment)==saved,"repeated room clear grants once")
	check(not inventory.clear_reward("L49",3,309) and JSON.stringify(Game.profile.equipment)==saved,"changed clear request refuses frozen event")
	inventory.last_error=""
	check(inventory.receipts[event]==receipt,"frozen receipt unchanged on retry")
	check(Game.profile.permanent_gold==wallet and Game.profile.hero_xp==xp and Game.profile.bosses==unlocks,"gear awards preserve chapter unlocks XP wallet")
	var storage := Store.new(Game.profile_path)
	var stored := storage.load_document()
	check(not stored.is_empty() and preload("res://scripts/domain/expedition/expedition_rewards.gd").same(stored.profile.equipment,Game.profile.equipment),"existing atomic store reloads same instances: "+storage.last_error)
	for difficulty in 5:
		# Independent runs provide independent room events, while the source count
		# remains the established D0..D4 boss policy rather than a fixture grant.
		Game.run.id="b09_boss_policy_"+str(difficulty)
		check(inventory.clear_reward("BO09",difficulty,315),"actual boss gear policy D"+str(difficulty)+": "+inventory.last_error)
		var boss: Dictionary=inventory.receipts["b09_clear:"+Game.run.id+":BO09"]
		check(boss.items.size()==[2,2,3,3,4][difficulty],"boss count D"+str(difficulty))
		for item: Dictionary in boss.items: check(int(item.item_level)<=45 and int(item.item_level)>=44,"boss item level upper edge")
	Game.profile.gold_pity["B09"]=3
	Game.run.id="b09_forced_gold"
	check(inventory.clear_reward("BO09",4,915),"D4 persistent pity receipt")
	var gold := false
	for item: Dictionary in inventory.receipts["b09_clear:b09_forced_gold:BO09"].items: gold=gold or item.rarity=="gold"
	check(gold and Game.profile.gold_pity.B09==0,"fourth non-gold boss guarantee and reset")
	check(inventory.clear_reward("BO09",4,915) and Game.profile.gold_pity.B09==0,"pity retry retains original forced decision")
	check(await room.combat_audio.wait_for_cleanup(),"cleanup live audio")
	room.free()
	Game.run=null
	print("B09_INVENTORY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
