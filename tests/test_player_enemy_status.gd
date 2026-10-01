extends Node
## Real player-node negative statuses through the production damage/gear pipeline.

const RoomScene = preload("res://scenes/room.tscn")
const Registry = preload("res://scripts/data/content_registry.gd")
const PropsScript = preload("res://scripts/world/room_props.gd")

class RegenPropsStub extends Node2D:
	func damage_bonus() -> float:
		return 0.0
	func move_multiplier() -> float:
		return 1.0
	func resource_regen_multiplier() -> float:
		return 1.5

var room: MineRoom
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fixture(hero: String = "CH01", equipment: Array[String] = []) -> void:
	if is_instance_valid(room):
		room.free()
	var loadout: Dictionary = {}
	var owned: Dictionary = {}
	for id: String in equipment:
		loadout[str(Registry.equipment(id).slot)] = id
		owned[id] = {"level":0}
	Game.run.hero_id = hero
	Game.run.level = 1
	Game.run.stats = StatResolver.resolve(hero,1,loadout,owned)
	Game.run.stats["crit_chance"] = 0.0
	Game.run.loadout_snapshot = loadout.duplicate(true)
	Game.run.equipment_snapshot = owned.duplicate(true)
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.shield = 0.0
	Game.run.resource = 100.0
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(600,600)
	room.player.aim_direction = Vector2.RIGHT

func run_checks() -> void:
	if not Game.profile_path.contains("test_player_enemy_status"):
		push_error("Refusing non-test profile; use test_player_enemy_status in profile path")
		get_tree().quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(),"isolated incoming-status run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_application_contract()
	_test_dot_cadence_and_contact_protection()
	_test_shield_armor_and_equipment()
	_test_chill_movement_and_expiry()
	_test_ordinary_slow()
	_test_room_prop_modifiers()
	_test_shock_corrosion_directness()
	_test_pause_and_death()
	if is_instance_valid(room):
		room.free()
	print("PLAYER ENEMY STATUS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_application_contract() -> void:
	fixture()
	room.player.grant_guard(20.0,4.0,"own_guard")
	check(not room.player.receive_enemy_status({"id":"guard","power":999.0}),"enemy status API cannot overwrite the player's guard pool")
	check(Game.run.shield == 20.0,"rejected guard status preserves existing protection")
	check(not room.player.receive_enemy_status({"id":"burn","power":-1.0}),"negative status snapshot is rejected")
	check(not room.player.receive_enemy_status({"id":"burn","power":INF}),"infinite status snapshot is rejected")
	check(not room.player.receive_enemy_status({"id":"chill","duration":0.0}),"nonpositive explicit duration is rejected")
	check(not room.player.receive_enemy_status({"id":"unknown"}),"unknown negative status is rejected")
	check(room.player.receive_enemy_status({"status":"burn","power":100.0,"origin":Vector2(40,50)}),"status alias accepts a real source snapshot")
	check(room.player.status.has("burn") and float(room.player.status.states.burn.remaining) == 3.0,"incoming burn uses shared three-second duration")
	check(Game.run.shield == 20.0,"negative status application does not alter a player's guard")
	check(not room.player.receive_damage(0.0,Vector2.ZERO) and room.player.invulnerable == 0.0,"zero damage cannot create contact protection")

func _test_dot_cadence_and_contact_protection() -> void:
	fixture()
	var before: float = Game.run.hp
	room.player.invulnerable = 9.0
	room.player.receive_enemy_status({"id":"burn","power":100.0,"origin":Vector2(40,50)})
	room.player._physics_process(0.999)
	check(Game.run.hp == before,"player burn has no early fractional tick")
	room.player._physics_process(0.001)
	check(is_equal_approx(before-Game.run.hp,75.0/7.0),"12 raw burn uses twelve magic resistance, despite active contact protection")
	check(is_equal_approx(room.player.invulnerable,8.0) and room.player.knockback == Vector2.ZERO,"DOT neither renews hurt protection nor creates knockback")
	room.player._physics_process(2.0)
	check(is_equal_approx(before-Game.run.hp,225.0/7.0) and not room.player.status.has("burn"),"three magic burn ticks apply including exact expiry")
	before = Game.run.hp
	room.player._physics_process(1.0)
	check(Game.run.hp == before,"expired burn cannot deal residual damage")
	fixture()
	room.player.receive_enemy_status({"id":"burn","power":100.0})
	room.player._physics_process(0.75)
	room.player.receive_enemy_status({"id":"burn","power":50.0})
	before = Game.run.hp
	room.player._physics_process(0.25)
	check(is_equal_approx(before-Game.run.hp,37.5/7.0),"player burn refresh preserves tick cadence and replaces source power before magic resistance")
	fixture()
	check(room.player.start_dash(Vector2.RIGHT) and room.player.dash_protected(),"steel-step fixture enters its actual protected window")
	before = Game.run.hp
	check(not room.player.receive_damage(12.0,Vector2.ZERO),"normal enemy hit respects dodge protection")
	check(room.player.receive_damage(12.0,Vector2.ZERO,{"dot":true}),"existing enemy DOT bypasses dodge protection")
	check(is_equal_approx(before-Game.run.hp,10.0) and room.player.invulnerable == 0.0,"protected-window DOT still uses armor and creates no new iframe")
	fixture()
	Game.run.stats.armor = 1000.0
	room.player.receive_enemy_status({"id":"burn","power":100.0})
	before = Game.run.hp
	room.player._physics_process(1.0)
	check(is_equal_approx(before-Game.run.hp,75.0/7.0),"raising armor to one thousand does not change magic burn damage")
	fixture()
	Game.run.stats.magic_resist = 100.0
	room.player.receive_enemy_status({"id":"burn","power":100.0})
	before = Game.run.hp
	room.player._physics_process(1.0)
	check(is_equal_approx(before-Game.run.hp,6.0),"one hundred magic resistance halves twelve raw burn damage")

func _test_shield_armor_and_equipment() -> void:
	fixture("CH01",["EQ07","EQ17","EQ27","EQ37"])
	room.player.status = CombatStatus.new()
	Game.run.shield = 0.0
	room.player.grant_guard(20.0,5.0,"test_guard")
	var prior_hp: float = Game.run.hp
	var prior_interval: float = room.player.stat("attack_interval",0.5)
	room.player.receive_enemy_status({"id":"burn","power":100.0})
	room.player._physics_process(1.0)
	check(is_equal_approx(Game.run.shield,65.0/7.0) and Game.run.hp == prior_hp,"burn applies magic resistance before consuming guard")
	check(room.player.stat("attack_interval",0.5)<prior_interval,"DOT absorption reaches real equipment damaged event and S05 attack-speed buff")
	room.player._physics_process(1.0)
	check(Game.run.shield == 0.0 and is_equal_approx(prior_hp-Game.run.hp,10.0/7.0),"second magic DOT tick exhausts shield and sends exact overflow to health")
	room.player._physics_process(1.0)
	check(is_equal_approx(prior_hp-Game.run.hp,85.0/7.0) and room.player.status.shield() == 0.0,"later magic DOT reaches health after shield exhaustion")

func walk_sample() -> float:
	var before: Vector2 = room.player.position
	room.input_blocked = false
	room.release_gate = false
	Input.action_press("move_right")
	room.player._physics_process(0.2)
	Input.action_release("move_right")
	room.input_blocked = true
	return room.player.position.distance_to(before)

func _test_chill_movement_and_expiry() -> void:
	fixture("CH02")
	var normal: float = walk_sample()
	check(room.player.receive_enemy_status({"id":"chill","duration":2.0}),"incoming chill can have an explicit enemy duration")
	check(is_equal_approx(walk_sample(),normal * 0.75),"enemy chill reduces actual walking speed by twenty-five percent")
	room.player.receive_enemy_status({"id":"chill","duration":2.0})
	check(is_equal_approx(walk_sample(),normal * 0.75),"repeated chill refreshes without stacking its slow")
	room.player._physics_process(2.0)
	check(not room.player.status.has("chill") and is_equal_approx(walk_sample(),normal),"movement recovers immediately after chill expires")
	fixture("CH02",["EQ45"])
	room.player.receive_enemy_status({"id":"chill"})
	check(is_equal_approx(room.player.stat("move_speed",255.0),204.0),"EQ45 immediately reduces chill's slow magnitude by twenty percent")
	check(is_equal_approx(walk_sample(),40.8),"equipment slow resistance affects real displacement")
	fixture("CH02",["EQ47"])
	room.player.grant_guard(10.0,4.0,"test_guard")
	room.player.receive_enemy_status({"id":"chill"})
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0*0.7875),"shield-conditional slow resistance combines without creating acceleration")

func _test_shock_corrosion_directness() -> void:
	fixture()
	room.player.receive_enemy_status({"id":"shock","power":100.0})
	room.player.receive_enemy_status({"id":"corrosion","power":0.0})
	var before: float = Game.run.hp
	room.player.receive_damage(10.0,Vector2.ZERO,{"dot":true})
	check(is_equal_approx(before-Game.run.hp,1000.0/117.0) and room.player.status.has("shock"),"DOT uses corrosion-reduced seventeen armor without consuming shock or gaining direct-hit amplification")
	before = Game.run.hp
	var prior_event_serial: int = room.player.loadout._event_serial
	room.player.receive_damage(10.0,Vector2.ZERO)
	check(is_equal_approx(before-Game.run.hp,120.0/13.0+625.0/28.0),"corroded physical body uses seventeen armor while stored shock separately uses unchanged magic resistance")
	check(room.player.loadout._event_serial == prior_event_serial + 1,"physical body and magic shock dispatch only one equipment damaged event")
	check(not room.player.status.has("shock") and room.player.status.has("corrosion"),"direct enemy hit consumes shock while corrosion remains")
	room.player.receive_enemy_status({"id":"shock","power":200.0})
	check(not room.player.receive_damage(10.0,Vector2.ZERO) and room.player.status.has("shock"),"iframe-rejected hit cannot consume a reapplied shock")
	room.player.invulnerable = 0.0
	before = Game.run.hp
	room.player.receive_damage(10.0,Vector2.ZERO)
	check(is_equal_approx(before-Game.run.hp,120.0/13.0) and room.player.status.has("shock"),"shock cooldown preserves its state while the body still uses corrosion-reduced armor")
	room.player._physics_process(1.0)
	before = Game.run.hp
	room.player.receive_damage(10.0,Vector2.ZERO)
	check(is_equal_approx(before-Game.run.hp,120.0/13.0+625.0/14.0) and not room.player.status.has("shock"),"magic shock becomes eligible after one second without inheriting corrosion's armor reduction")
	fixture()
	before = Game.run.hp
	room.player.receive_damage(12.0,Vector2.ZERO)
	room.player.receive_enemy_status({"id":"shock","power":100.0})
	check(is_equal_approx(before-Game.run.hp,10.0) and room.player.status.has("shock"),"runtime hit-then-apply order cannot consume shock from its own hit")

func _test_ordinary_slow() -> void:
	fixture("CH02")
	check(not room.player.receive_enemy_status({"id":"slow","magnitude":-0.1}),"ordinary slow rejects negative movement multipliers")
	check(not room.player.receive_enemy_status({"id":"slow","magnitude":1.1}),"ordinary slow cannot become an acceleration buff")
	check(not room.player.receive_enemy_status({"id":"slow","magnitude":INF}),"ordinary slow rejects nonfinite movement multipliers")
	check(not room.player.receive_enemy_status({"id":"slow","duration":0.0}),"ordinary slow rejects nonpositive duration")
	check(room.player.receive_enemy_status({"id":"slow","duration":1.4,"magnitude":0.8}),"ordinary slow accepts its separate duration and multiplier contract")
	check(not room.player.status.has("chill") and not room.player.status.has("slow"),"ordinary slow never writes a chill or offensive status state")
	check(is_equal_approx(walk_sample(),40.8),"ordinary twenty-percent slow changes actual movement")
	room.player.receive_enemy_status({"id":"slow","duration":0.3,"magnitude":0.9})
	check(is_equal_approx(room.player.stat("move_speed",255.0),204.0) and room.player._enemy_slow_remaining >= 1.19,"weaker shorter slow does not erase existing strength or duration")
	room.player._physics_process(0.6)
	room.player.receive_enemy_status({"id":"slow","duration":2.0,"magnitude":0.6})
	check(is_equal_approx(room.player.stat("move_speed",255.0),153.0),"stronger slow replaces the multiplier and refreshes duration")
	room.player._physics_process(1.9)
	room.player.receive_enemy_status({"id":"slow","duration":0.5,"magnitude":0.9})
	room.player._physics_process(0.49)
	check(is_equal_approx(room.player.stat("move_speed",255.0),153.0),"later weak application refreshes the strongest ordinary slow without multiplying it")
	room.player._physics_process(0.011)
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0),"ordinary slow expiry restores normal movement")
	room.player.receive_enemy_status({"status":"slow","duration":1.0})
	get_tree().paused = true
	room.player._physics_process(1.0)
	get_tree().paused = false
	check(is_equal_approx(room.player._enemy_slow_remaining,1.0) and is_equal_approx(room.player.stat("move_speed",255.0),204.0),"pause freezes ordinary slow and alias uses the default multiplier")
	fixture("CH02",["EQ45"])
	room.player.receive_enemy_status({"id":"slow","duration":3.0,"magnitude":0.6})
	check(is_equal_approx(room.player.stat("move_speed",255.0),153.0) and float(room.player.loadout.modifiers().slow_resistance) == 0.0,"ordinary slow cannot activate chill-only EQ45 resistance")
	room.player.receive_enemy_status({"id":"chill","duration":0.2})
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0*0.68),"chill and ordinary slow share the strongest magnitude before resistance")
	room.player._physics_process(0.2)
	check(not room.player.status.has("chill") and is_equal_approx(room.player.stat("move_speed",255.0),153.0),"chill expiry immediately removes its conditional resistance while independent slow remains")
	fixture("CH02",["EQ47"])
	room.player.grant_guard(10.0,4.0,"test_guard")
	room.player.receive_enemy_status({"id":"slow","duration":2.0,"magnitude":0.8})
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0*0.83),"shield-conditional resistance reduces ordinary slow magnitude")
	room.player.receive_enemy_status({"id":"chill","duration":2.0})
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0*0.7875),"weaker ordinary slow cannot compound the stronger chill penalty")

func _props_fixture() -> Node2D:
	var props: Node2D = room.get("enemy_props")
	if not is_instance_valid(props):
		props = PropsScript.new()
		room.add_child(props)
		room.set("enemy_props",props)
	props.clear()
	return props

func _prop_hit() -> float:
	var target: MineEnemy = room.spawn_enemy(room.player.position+Vector2(80,0))
	target.armor = 0.0
	target.health.reset(1000.0)
	room.player.original_hit(target,20.0,&"q")
	return 1000.0-target.health.current

func _test_room_prop_modifiers() -> void:
	fixture("CH02")
	var has_props_api: bool = false
	for property: Dictionary in room.get_property_list():
		if str(property.name) == "enemy_props":
			has_props_api = true
			break
	check(has_props_api,"production room exposes the player-facing enemy_props getter contract")
	if not has_props_api:
		return
	var props: Node2D = _props_fixture()
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),0.0) and is_equal_approx(room.player.stat("move_speed",255.0),255.0),"room props with no active buff preserve original player stats")
	check(props.grant_buff("damage",room.player) and props.grant_buff("haste",room.player),"real RoomProps grants damage and haste sources")
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),0.2) and is_equal_approx(_prop_hit(),24.0),"room damage buff reaches the actual original-hit damage bucket")
	check(is_equal_approx(walk_sample(),255.0*1.15*0.2),"room haste reaches actual movement as a fifteen-percent bonus")
	props.grant_buff("damage",room.player)
	props.grant_buff("haste",room.player)
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),0.2) and is_equal_approx(room.player.stat("move_speed",255.0),293.25),"refreshing real prop sources does not double their bonuses")
	props.update(12.0)
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0) and is_equal_approx(room.player.stat("damage_bonus",0.0),0.2),"haste expires independently while the longer damage source remains")
	props.update(3.0)
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),0.0) and is_equal_approx(_prop_hit(),20.0),"damage expiry immediately restores actual hit damage")
	fixture("CH02",["EQ11","EQ31"])
	props = _props_fixture()
	Game.run.stats.damage_bonus = 0.55
	props.grant_buff("damage",room.player)
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),0.6) and is_equal_approx(_prop_hit(),32.0),"permanent gear, prop and conditional gear damage share the sixty-percent A cap")
	Game.run.stats.move_speed_bonus = 0.3
	Game.run.stats.move_speed = 255.0*1.3
	Game.run.hp = Game.run.max_hp*0.2
	room.player.loadout.event("state_changed")
	props.grant_buff("haste",room.player)
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0*1.45),"permanent move gear, conditional gear and prop haste share the forty-five-percent cap")
	room.player.receive_enemy_status({"id":"slow","duration":2.0,"magnitude":0.8})
	check(is_equal_approx(walk_sample(),255.0*1.45*0.8*0.2),"ordinary slow applies after the capped positive movement bucket")
	props.clear()
	check(is_equal_approx(room.player.stat("damage_bonus",0.0),0.55) and is_equal_approx(room.player.stat("move_speed",255.0),255.0*1.35*0.8),"clearing room props removes only their contributions")
	fixture("CH02")
	props = _props_fixture()
	Game.run.resource = 0.0
	room.player._physics_process(1.0)
	check(is_equal_approx(Game.run.resource,18.0),"real props keep existing resource regeneration at their neutral multiplier")
	var regen_props := RegenPropsStub.new()
	room.add_child(regen_props)
	room.set("enemy_props",regen_props)
	Game.run.resource = 0.0
	room.player._physics_process(1.0)
	check(is_equal_approx(Game.run.resource,27.0),"resource regeneration consumes the props getter through actual player physics")
	regen_props.free()
	check(is_equal_approx(room.player.stat("resource_regen",18.0),18.0),"freed props are safely ignored without stale temporary bonuses")
	room.set("enemy_props",null)
	check(is_equal_approx(room.player.stat("move_speed",255.0),255.0) and is_equal_approx(room.player.stat("damage_bonus",0.0),0.0),"missing props retain the original player stat behavior")

func _test_pause_and_death() -> void:
	fixture()
	room.player.receive_enemy_status({"id":"burn","power":100.0})
	var before: float = Game.run.hp
	get_tree().paused = true
	room.player._physics_process(2.0)
	check(Game.run.hp == before and float(room.player.status.states.burn.remaining) == 3.0,"pause freezes player status duration and DOT damage")
	get_tree().paused = false
	room.player._physics_process(1.0)
	check(is_equal_approx(before-Game.run.hp,75.0/7.0),"magic burn cadence resumes without catching up paused time")
	fixture()
	Game.run.hp = 1.0
	room.player.receive_enemy_status({"id":"burn","power":100.0})
	room.player.receive_enemy_status({"id":"corrosion","power":100.0})
	room.player._physics_process(4.0)
	check(Game.run == null and Game.last_result.get("outcome","") == "death","lethal first DOT tick settles death and stops remaining same-frame ticks safely")
	check(not room.player.receive_enemy_status({"id":"chill"}),"dead player cannot accept a late negative-status callback")
