extends SceneTree
## Focused B05 gear contracts. No production profile access or broad balance matrix.
const Effects = preload("res://scripts/combat/equipment_effects.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
var Loadout: Script
var checks := 0
var failures := 0
var serial := 0

func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("B05 GEAR: " + label)
func near(value: float, expected: float, label: String) -> void:
	check(is_equal_approx(value, expected), label + " actual=" + str(value))
func ctx(extra: Dictionary = {}) -> Dictionary:
	serial += 1
	var value := {"event_id":"event:" + str(serial), "attack_id":"event:" + str(serial), "root_event_id":"event:" + str(serial), "target_id":"one", "target_alive":true,
		"ruleset_version":2, "hero_id":"CH01", "hp":500, "max_hp":1000, "resource":100, "resource_max":1000, "resource_type":"mana",
		"H":100, "X":300, "equipment_eligible":true, "original_basic":false, "damage_source":"skill", "proc_depth":0, "confirmed":true,
		"paid_cost":100, "cast_success":true, "combat_active":true, "skill_slot":"secondary", "slot":"secondary", "target_states":[], "remaining_cooldowns":{"F":4.0, "R":8.0},
		"b05_arc_targets":["one", "two", "three", "four"], "b05_pierce_targets":["two", "three"]}
	value.merge(extra, true)
	return value
func fx(set_id: String, pieces: int = 6, unique: String = "") -> RefCounted:
	var value := Effects.new()
	value.stats = {"ruleset_version":2, "attack":100, "ability_power":200, "max_hp":1000, "resource_max":1000}
	value.resource_type = "mana"
	if not set_id.is_empty(): value.set_counts[set_id] = pieces
	if not unique.is_empty(): value.equipped[unique] = true
	return value
func hit(value: RefCounted, extra: Dictionary = {}) -> Dictionary:
	return value.handle("after_hit", ctx(extra))
func _run() -> void:
	Loadout = load("res://scripts/combat/combat_loadout.gd")
	check(Effects.implemented_ids().size() == 96 and Effects.implemented_set_ids().size() == 14, "legacy manifest unchanged")
	check(Effects.implemented_ids(2).size() == 99 and Effects.implemented_set_ids(2).size() == 18, "V2 B05 manifest")
	for sid: String in ["B05-SW", "B05-SG", "B05-SM", "B05-SU"]:
		var loadout := {}
		var templates := {}
		for slot: String in Registry.V2_SLOTS:
			var id := sid + "-" + ("accessory" if slot == "charm" else slot)
			loadout[slot] = "instance:" + slot
			templates[slot] = id
		var binding: Dictionary = Effects.loadout_binding(loadout, {"ruleset_version":2, "loadout":loadout,"equipment_templates":templates})
		check(binding.set_counts.get(sid) == 8, sid + " full8 binds once")
		check(Effects.source_active(sid + "_6", binding) and not Effects.source_active(sid + "_8", binding), sid + " only2/4/6")
	_warrior()
	_gunner()
	_mage()
	_shared()
	_lifecycle()
	_geometry()
	print("B05 EQUIPMENT RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _warrior() -> void:
	var value := fx("B05-SW")
	near(value.b05_e_shield(100), 112, "SW2 E generated shield")
	check(hit(value).bonus_hits.is_empty(), "SW4 needs actual E absorption")
	value.handle("damaged", ctx({"enemy_damage":true,"e_shield_absorbed":10,"shield_absorbed":10}))
	var proc: Dictionary = hit(value)
	check(proc.bonus_hits.size() == 1 and proc.bonus_hits[0].target_ids.size() == 3, "SW4 short arc capped3")
	near(proc.bonus_hits[0].damage, 30, "SW4 fixed AD P")
	check(hit(value).bonus_hits.is_empty(), "SW4 consumes next W and ICD")
	value = fx("B05-SW")
	var same := ctx()
	value.handle("after_hit", same)
	same.target_id = "two"
	value.handle("after_hit", same)
	hit(value)
	proc = hit(value)
	check(proc.cooldown_refunds.size() == 1 and proc.cooldown_refunds[0].slot == "F", "SW6 three casts only refund E")
	near(proc.cooldown_refunds[0].seconds, 1.5, "SW6 refund exactly1.5")
	var q := ctx({"skill_slot":"q"})
	near(value.handle("before_hit", q).damage_bonus, 0.10, "SW6 next Q preview")
	near(value.handle("before_hit", ctx({"skill_slot":"q"})).damage_bonus, 0.10, "SW6 rejected preview does not consume")
	value.handle("after_hit", q)
	near(value.handle("before_hit", ctx({"skill_slot":"q"})).damage_bonus, 0.0, "SW6 consumes successful Q")
	value = fx("B05-SW")
	hit(value); value.advance(7.0, ctx()); hit(value); value.advance(3.0, ctx()); hit(value); value.advance(1.0, ctx())
	check(hit(value).cooldown_refunds.size() == 1, "SW6 truly rolling8s")

func _gunner() -> void:
	var value := fx("B05-SG")
	near(value.handle("before_hit", ctx({"hunter_marked":true})).damage_bonus, 0.08, "SG2 marked direct damage")
	near(value.handle("before_hit", ctx({"hunter_marked":true,"proc_depth":1})).damage_bonus, 0.0, "SG2 excludes derived damage")
	var shot := ctx({"hunter_marked":true})
	var proc: Dictionary = value.handle("after_hit", shot)
	check(proc.bonus_hits.size() == 1 and proc.bonus_hits[0].target_ids == ["two"], "SG4 exactlyone extra target")
	near(proc.bonus_hits[0].damage, 35, "SG4 fixed AD P")
	shot.target_id = "third"
	check(value.handle("after_hit", shot).bonus_hits.is_empty(), "SG4 once per W")
	value.handle("gunner_q_completed", ctx({"actual_distance":99.0}))
	near(value.handle("before_hit", ctx()).damage_bonus, 0.0, "SG6 rejects99 movement")
	value.handle("gunner_q_completed", ctx({"actual_distance":100.0}))
	shot = ctx()
	near(value.handle("before_hit", shot).damage_bonus, 0.12, "SG6 actual100 arms nextW")
	value.handle("after_hit", shot)
	shot.target_id = "two"
	near(value.handle("before_hit", shot).damage_bonus, 0.0, "SG6 main target only")
	near(value.handle("before_hit", ctx()).damage_bonus, 0.0, "SG6 consumed")

func _mage() -> void:
	var value := fx("B05-SM")
	near(value.handle("before_hit", ctx({"skill_slot":"q"})).damage_bonus, 0.08, "SM2 Q direct")
	for slot: String in ["q", "secondary"]:
		check(value.handle("skill_cast",ctx({"slot":slot,"skill_slot":slot,"paid_cost":20})).resource_restore == 0, "SM4 first2 no refund")
	var proc: Dictionary = value.handle("skill_cast",ctx({"slot":"f","skill_slot":"f","paid_cost":20}))
	near(proc.resource_restore, 60, "SM4 three alternating paid casts refund60")
	check(value.handle("skill_cast",ctx({"slot":"q","skill_slot":"q"})).resource_restore == 0, "SM4 ICD")
	value = fx("B05-SM")
	value.handle("skill_cast",ctx({"slot":"q","skill_slot":"q"}))
	value.handle("skill_cast",ctx({"slot":"q","skill_slot":"q"}))
	near(value.handle("skill_cast",ctx({"slot":"f","skill_slot":"f"})).resource_restore, 0, "SM4 adjacent same resets")
	near(value.handle("skill_cast",ctx({"slot":"q","skill_slot":"q"})).resource_restore, 60, "SM4 can restart alternating chain")
	value = fx("B05-SM")
	for slot: String in ["q","secondary","f"]: value.handle("skill_cast",ctx({"slot":slot,"skill_slot":slot,"paid_cost":0}))
	check(value.counts.is_empty(), "SM4 zero cost and failed payment excluded")
	proc = value.handle("mage_w_node_placed",ctx({"node_placed":false}))
	check(not proc.has("b05_bloom"), "SM6 no ring for failed placement")
	var node_context := ctx({"node_placed":true, "X":100})
	proc = value.handle("mage_w_node_placed",node_context)
	check(proc.has("b05_bloom") and proc.b05_bloom.delay == 1.0 and proc.b05_bloom.radius == 110.0, "SM6 exact delayed ring contract")
	proc = value.handle("b05_bloom_due",ctx({"root_event_id":node_context.root_event_id,"b05_bloom_targets":["one","two","three","four"],"bloom_damage":80}))
	check(proc.bonus_hits.size() == 1 and proc.bonus_hits[0].target_ids.size() == 3, "SM6 ring capped3")
	near(proc.bonus_hits[0].damage, 80, "SM6 uses fixed AP only")
	check(proc.bonus_hits[0].damage_by_target == {"one":80,"two":80,"three":80}, "SM6 AP above H retains full third0.40P packet")
	check(value.handle("b05_bloom_due",ctx({"root_event_id":node_context.root_event_id,"b05_bloom_targets":["four"],"bloom_damage":80})).bonus_hits.is_empty(), "same-root repeated derived releases share spent1.2P cap")
	check(value.handle("b05_bloom_due",ctx({"b05_bloom_targets":["one"],"bloom_damage":80})).bonus_hits.is_empty(), "derived event cannot manufacture new budget")
	var mixed := fx("B05-SM")
	var root:Dictionary = mixed._root("budget")
	root["raw_packet"]=100; root["damage_spent"]=100
	var mixed_context := ctx({"X":100})
	mixed._prime_b05_budget(mixed_context,root,200)
	var commands:Dictionary=mixed._empty()
	mixed._b05_packet(mixed_context,root,commands,"B05-SM_6:ring",0.0,0.4,["one","two","three"],3,"magic",80,false)
	check(commands.bonus_hits[0].damage_by_target=={"one":80,"two":60}, "same-frame prior derived100 clips later ring to shared240 budget")

func _shared() -> void:
	var value := fx("B05-SU")
	near(value.b05_control_duration(1), 0.8, "SU2 duration20%")
	near(value.b05_control_duration(1,0.8), 0.5, "SU2 total cap50%")
	value.handle("hostile_hazard",ctx({"hazard_id":"zone","inside":false}))
	check(value.advance(1,ctx()).shields.is_empty(), "SU4 no fabricated exit")
	value.handle("hostile_hazard",ctx({"hazard_id":"zone","inside":true}))
	value.handle("hostile_hazard",ctx({"hazard_id":"zone","inside":false}))
	check(value.advance(0.9,ctx()).shields.is_empty(), "SU4 wait1s")
	value.handle("hostile_hazard",ctx({"hazard_id":"zone","inside":false,"zone_damaged":true}))
	check(value.advance(0.2,ctx()).shields.is_empty(), "SU4 damage resets clean interval")
	var proc: Dictionary = value.advance(0.8,ctx())
	check(proc.shields.size() == 1 and proc.shields[0].duration == 4, "SU4 shield4s")
	near(proc.shield_ratio, 0.06, "SU4 HP6%")
	var root_hit := ctx({"original_basic":true,"damage_source":"primary"})
	value.handle("after_hit",root_hit); root_hit.target_id = "second"; value.handle("after_hit",root_hit)
	hit(value)
	proc = hit(value)
	near(proc.get("heal_amount",0), 30, "SU6 3 distinct casts heal3%")
	near(proc.move_speed_bonus, 0.08, "SU6 speed8%")
	check(hit(value).get("heal_amount",0) == 0, "SU6 ICD12")
	value = fx("",0,"B05-U01")
	near(value.handle("root_ended",ctx({"actually_rooted":false})).move_speed_bonus,0,"U01 cannot fabricate root")
	near(value.handle("root_ended",ctx({"actually_rooted":true})).move_speed_bonus,0.10,"U01 root end speed")
	value.advance(2,ctx()); near(value.passive_modifiers(ctx()).move_speed_bonus,0,"U01 expires2s")
	value = fx("",0,"B05-U02")
	check(value.handle("external_heal",ctx({"actual_healing":0})).shields.is_empty(),"U02 excludes overheal")
	proc=value.handle("external_heal",ctx({"actual_healing":1}))
	check(proc.shields.size()==1 and proc.shields[0].duration==3,"U02 external heal shield3s")
	near(proc.shield_ratio,0.02,"U02 HP2%")
	value = fx("",0,"B05-U03")
	near(value.handle("hostile_destructible_destroyed",ctx({"player_attributed":false})).damage_reduction_bonus,0,"U03 ownership required")
	near(value.handle("hostile_destructible_destroyed",ctx({"player_attributed":true})).damage_reduction_bonus,0.05,"U03 reduction5%")

func _lifecycle() -> void:
	var value := fx("B05-SW")
	hit(value); hit(value)
	value.advance(10.1,ctx({"combat_active":false}))
	check(value.counts.is_empty(),"out of combat10s clears partial counters")
	hit(value); value.cooldowns["B05-SW_6"]=20.0
	value.handle("room_enter",ctx({"room_id":"L26"}))
	check(value.counts.is_empty() and value.cooldowns["B05-SW_6"]==20.0,"room clears counters preservesICD")
	value.handle("room_enter",ctx({"room_id":"L27"}))
	value.handle("room_enter",ctx({"room_id":"L26"}))
	check(value.room_id=="L26", "reused fixed room keeps current snapshot identity without replaying entry")
	check(not Effects.source_active("B05-SW_6:q",{"set_counts":{"B05-SW":4}}),"swap removes absent tier")
	check(Effects.source_active("B05-U01",{"equipped":{"B05-U01":true}}),"unique source survives valid loadout")

class GeometryTarget extends Node2D:
	var navigation_radius := 10.0
	func is_alive() -> bool: return true
class GeometryRoom extends Node2D:
	var targets: Array[Node2D] = []
	func targets_in_radius(at: Vector2,radius:float)->Array:
		return targets.filter(func(t:Node2D)->bool:return t.position.distance_to(at)<=radius)
	func has_line_of_sight(_a:Vector2,_b:Vector2)->bool:return true
class GeometryPlayer extends Node2D:
	var room: Node2D
	var aim_direction := Vector2.RIGHT
func _geometry() -> void:
	var room := GeometryRoom.new()
	var player := GeometryPlayer.new(); player.room=room
	var loadout: RefCounted = Loadout.new(); loadout.owner_player=player
	for at: Vector2 in [Vector2(80,0),Vector2(150,0),Vector2(150,40),Vector2(50,0),Vector2(270,0)]:
		var target:=GeometryTarget.new();target.position=at;room.targets.append(target)
	var context := {"skill_slot":"secondary","b05_direction":Vector2.RIGHT,"target":room.targets[0]}
	var selected:Array=loadout._b05_pierce_targets(context)
	check(selected==[str(room.targets[1].get_instance_id())],"SG4 real ray selects behind, excludes lateral and180+")
	context.b05_direction=Vector2.LEFT
	check(loadout._b05_pierce_targets(context)==[str(room.targets[3].get_instance_id())],"SG4 follows committed ray direction")
	context.b05_direction=Vector2.RIGHT
	check(loadout._b05_arc_targets(context).size()==2,"SW4 short arc geometry")
	for target: Node2D in room.targets: target.free()
	player.free();room.free()
