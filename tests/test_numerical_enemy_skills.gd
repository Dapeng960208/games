extends Node
## S09: frozen independent Decimal goldens are checked after real actor emission
## through EnemySkillRuntime. Scene entry loads the real Game autoload first.
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Bosses = preload("res://scripts/combat/boss_profiles.gd")
const Target = preload("res://scripts/combat/enemy_numerical_v2.gd")
const Golden = preload("res://tests/test_numerical_enemy_targets.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Numbers = preload("res://config/numerical_rules.gd")
var checks := 0
var failures: Array[String] = []
var failure_count := 0
var packets := 0
var room: TestRoom
var runtime: RecordingRuntime
var player: RecordingPlayer

class TestRoom extends MineRoom:
	func _ready() -> void: pass
	func _draw() -> void: pass
	func add_damage_text(_at: Vector2, _value: float, _kind: StringName = &"primary", _context: Dictionary = {}) -> void: pass

class RecordingRuntime extends EnemySkillRuntime:
	var recorded: Array[Dictionary] = []
	var capture_only := true
	func _execute(command: Dictionary) -> void:
		recorded.append(command.duplicate(true))
		if not capture_only: super._execute(command)

class RecordingPlayer extends SalvagerPlayer:
	var received: Array[Dictionary] = []
	var received_states: Array[Dictionary] = []
	func receive_damage(amount: float, origin: Vector2, context: Dictionary = {}) -> bool:
		received.append({"amount":amount,"context":context.duplicate(true)})
		return super.receive_damage(amount,origin,context)
	func receive_enemy_status(command: Dictionary) -> bool:
		received_states.append(command.duplicate(true))
		return super.receive_enemy_status(command)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failure_count += 1
		if failures.size() < 40 and not failures.has(label): failures.append(label)

func _ready() -> void: call_deferred("_run")

func _run() -> void:
	if not Game.profile_path.contains("test_numerical_enemy_skills"):
		get_tree().quit(2)
		return
	Game.run = RunState.new()
	Game.run.hero_id = "CH01"
	Game.run.level = 1
	Game.run.stats = Resolver.resolve("CH01",1,{}, {},2)
	Game.run.max_hp = 1000000
	Game.run.hp = 1000000
	room = TestRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.visible = false
	room.fx_font = ThemeDB.fallback_font
	room.geometry_enabled = false
	room.spawn_enabled = false
	for node_name: String in ["Enemies","Projectiles"]:
		var container := Node2D.new()
		container.name = node_name
		room.add_child(container)
	add_child(room)
	player = RecordingPlayer.new()
	player.room = room
	room.player = player
	room.add_child(player)
	player.position = Vector2(400,0)
	runtime = RecordingRuntime.new()
	room.enemy_skills = runtime
	room.add_child(runtime)
	runtime.configure(room)
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/balance/current_enemy_skill_inputs.json"))
	if not "--runtime-only" in OS.get_cmdline_user_args():
		_all_ordinary(frozen)
		_all_bosses(frozen)
	_actual_packets_and_support()
	_actual_facilities()
	room.queue_free()
	Game.run = null
	await get_tree().process_frame
	await get_tree().process_frame
	print("Numerical real enemy skills: ",checks," checks; packets=",packets," failure_count=",failure_count," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _actor(id: String, level: int = 15, difficulty: int = 4, rank: String = "normal") -> MineEnemy:
	var actor := MineEnemy.new()
	actor.room = room
	actor.training_ai_disabled = true
	actor.configure(Profiles.resolve(id,level,rank,2,difficulty),{"reward_enabled":false})
	room.enemies.add_child(actor)
	actor.state = &"chase"
	return actor

func _tokens(actual: Dictionary, source: Dictionary) -> Array[String]:
	packets += 1
	check(actual.damage is int,"runtime integer packet")
	check(actual.enemy_command_version == 2 and actual.scale_version == 10,"runtime command has one-time scale marker")
	var result: Array[String] = [str(actual.damage)]
	for key: String in ["anchor_health","cover_hp","pod_health","pod_break_armor_loss"]:
		if source.has(key):
			check(actual[key] is int,"runtime integer endpoint "+key)
			result.append(key+"="+str(actual[key]))
	var state: Dictionary = source.get("status",{})
	if Target.STATUS_RATIOS.has(str(state.get("id",""))):
		result.append("power="+str(actual.status.power))
		result.append("tick="+str(Target.status_tick(actual.status)))
	for key: String in ["count","duration","tick_interval","range","width","radius","angle","speed","tell","lock","recovery","max_alive","max_targets","charges","hit_cap","auto_release","hatch_delay","weakpoint_duration","weakpoint_delay"]:
		if source.has(key): check(is_equal_approx(float(actual.get(key,0)),float(source[key])) if source[key] is float else actual.get(key) == source[key],"authored timing/geometry/count retained: "+key)
	return result

func _all_ordinary(frozen: Dictionary) -> void:
	var tiers := 0
	var positions := 0
	for enemy: Dictionary in frozen.ordinary:
		for tier: Dictionary in enemy.tiers:
			tiers += 1
			positions += tier.commands.size()
			for rank: String in ["normal","elite"]:
				var originals: Array = tier.commands.duplicate(true)
				if rank == "elite":
					if tier.elite_delta.has("replace"): originals = tier.elite_delta.replace.duplicate(true)
					else: originals.append_array(tier.elite_delta.append)
				var tokens: Array[String] = []
				for d in 5:
					var actor := _actor(enemy.id,int(tier.reference_level),d,rank)
					for key: String in Target.PROFILE_FLATS: tokens.append(str(actor.profile[key]))
					var sequence: Array = actor.brain._build_sequence()
					check(sequence.size() == originals.size(),"real Brain frozen sequence "+enemy.id)
					for index in sequence.size():
						runtime.recorded.clear()
						actor.cast_enemy_skill(sequence[index])
						check(runtime.recorded.size() == 1,"real ordinary actor emits once")
						if runtime.recorded.is_empty(): continue
						var command: Dictionary = runtime.recorded[0]
						tokens.append_array(_tokens(command,originals[index]))
						var before := command.duplicate(true)
						actor.cast_enemy_skill(command)
						check(runtime.recorded[-1].damage == before.damage and runtime.recorded[-1].get("status",{}) == before.get("status",{}),"runtime retry never reapplies coefficient/rage/scale")
					actor.free()
				var key := "%s:T%d:%s" % [enemy.id,tier.tier,rank]
				check("|".join(tokens).sha256_text() == Golden.ORDINARY_HASHES[key],"live Decimal targets "+key)
	check(tiers == 144 and positions == 311,"all144 ordinary tiers/311 command positions")

func _all_bosses(frozen: Dictionary) -> void:
	var actions := 0
	var variants := 0
	var combinations := 0
	for boss_data: Dictionary in frozen.bosses:
		for action: Dictionary in boss_data.actions:
			actions += 1
			var tokens: Array[String] = []
			for variant: Dictionary in action.variants:
				variants += 1
				for d in range(int(action.unlock_difficulty),5):
					combinations += 1
					var boss := MineBoss.new()
					boss.room = room
					boss.training_ai_disabled = true
					boss.configure(Bosses.resolve(boss_data.id,d,2))
					room.enemies.add_child(boss)
					boss.state = &"chase"
					var brain: BossBrain = boss.boss_brain
					brain.phase = int(variant.phase)
					brain.current_action = action.id
					brain.command = brain._build_action(boss,player,action.id)
					var before := boss.profile.duplicate(true)
					runtime.recorded.clear()
					if action.id != "grave_recall": brain._execute(boss)
					if action.id == "grave_recall":
						check(brain.command.is_empty(),"real Brain rejects grave recall without a corpse")
						boss.cast_enemy_skill(variant.command)
						check(runtime.recorded.is_empty(),"no corpse: real grave recall emits no damaging packet")
						var recall: Dictionary = variant.command.duplicate(true)
						recall.enemy_skill_phase = int(variant.phase)
						runtime.emit_skill(boss,recall)
					check(not runtime.recorded.is_empty(),"real Boss release "+action.id)
					if not runtime.recorded.is_empty():
						tokens.append_array(_tokens(runtime.recorded[0],variant.command))
						for stroke: Dictionary in runtime.recorded:
							check(stroke.damage == runtime.recorded[0].damage and stroke.enemy_skill_phase == variant.phase,"split strokes share frozen integer/phase")
					check(boss.profile == before,"phase never mutates actorA")
					boss.free()
			check("|".join(tokens).sha256_text() == Golden.BOSS_HASHES[boss_data.id+":"+action.id],"live Boss Decimal targets "+boss_data.id+":"+action.id)
	check(actions == 40 and variants == 103 and combinations == 395,"all40 Boss skills/103 variants/395 valid D-phase combinations")

func _reset_packets() -> void:
	runtime.reset_room()
	runtime.recorded.clear()
	player.received.clear()
	player.received_states.clear()
	player.status.states.clear()
	player.status.guards.clear()
	player.invulnerable = 0
	Game.run.hp = Game.run.max_hp
	Game.run.shield = 0

func _actual_packets_and_support() -> void:
	runtime.capture_only = false
	player.position = Vector2(550,400)
	var actor := _actor("M10",10,4)
	actor.position = Vector2(400,400)
	var shot := {"kind":"melee","origin":actor.position,"target":player.position,"direction":Vector2.RIGHT,"range":220.0,"angle":1.8,"damage_multiplier":.62,"status":{"id":"corrosion","duration":3.0}}
	_reset_packets()
	actor.cast_enemy_skill(shot)
	var amount: int = Target.command(shot,actor.profile).damage
	check(player.received.size()==1 and player.received[0].amount==amount,"real player receives one scaled integer packet")
	check(player.received_states.size()==1 and player.received_states[0].power==amount and player.received_states[0].power is int,"authored corrosion applies once with integerQ")
	var ticks: Array = player.status.tick(1.0)
	check(ticks.size()==1 and ticks[0].damage==Target.status_tick({"id":"corrosion","power":amount}),"real status tick uses integer power once")
	var raw_tick: int = int(ticks[0].damage)
	var before: int = int(Game.run.hp)
	player.receive_damage(raw_tick,actor.position,{"dot":true,"damage_type":"physical"})
	var expected: Dictionary = Damage.resolve(raw_tick,"physical",{},Game.run.stats,{"armor_multiplier":.85})
	check(before-Game.run.hp == expected.damage,"actual corrosion tick defense without direct1.08 duplicate")
	_reset_packets()
	shot.erase("status")
	actor.cast_enemy_skill(shot)
	check(player.received_states.size()==1 and player.received_states[0].power==Target._round_product([amount,.55]),"racial venom snapshots integer55% once")
	_reset_packets()
	player.invulnerable = 1
	actor.cast_enemy_skill(shot)
	check(player.received_states.is_empty(),"rejected direct packet cannot grant racial status")
	_reset_packets()
	var harmless: Dictionary = shot.duplicate(true)
	harmless.damage = 0
	actor.cast_enemy_skill(harmless)
	check(player.received.is_empty() and runtime.recorded[0].damage==0,"explicit practice zero stays zero")
	_reset_packets()
	var multi := {"kind":"projectile","origin":actor.position,"target":player.position,"direction":Vector2.RIGHT,"range":400.0,"speed":400.0,"count":3,"projectile_angles":[0.0,0.0,0.0],"damage_multiplier":.42}
	actor.cast_enemy_skill(multi)
	check(runtime.projectiles.size()==3,"three authored projectiles preserved")
	for projectile: Dictionary in runtime.projectiles: check(projectile.damage==Target.command(multi,actor.profile).damage and projectile.damage is int,"each projectile owns same integerQ")
	runtime.advance(.5)
	check(player.received.size()==3,"all three projectiles independently collide")
	_reset_packets()
	var area := {"kind":"ground_area","shape":"circle","origin":actor.position,"target":player.position,"direction":Vector2.RIGHT,"radius":70.0,"duration":2.1,"tick_interval":1.0,"damage_multiplier":.42}
	actor.cast_enemy_skill(area)
	runtime.advance(1.01)
	player.invulnerable=0
	runtime.advance(1.01)
	check(player.received.size()==2,"area preserves two interval-based ticks")
	for hit: Dictionary in player.received: check(hit.amount==Target.command(area,actor.profile).damage,"each area tick reusesQ without rescaling")
	actor.free()
	_test_rage_and_drum()
	_test_support_and_pods()
	_test_capacitor_and_drain()

func _test_rage_and_drum() -> void:
	_reset_packets()
	var actor := _actor("M28",20,4)
	actor.position=Vector2(400,400)
	actor.health.current = int(actor.health.maximum)/2
	var command := {"kind":"melee","origin":actor.position,"target":player.position,"direction":Vector2.RIGHT,"range":220.0,"angle":1.8,"damage_multiplier":.65,"delay":1.0}
	actor.cast_enemy_skill(command)
	var expected: int = Target.command(command,actor.profile,1,1.2).damage
	check(runtime.jobs[0].damage==expected,"racial rage included before single packet rounding")
	actor.health.current=actor.health.maximum
	runtime.advance(1.01)
	check(player.received[0].amount==expected,"delayed rage remains frozen after healing")
	actor.free()
	_reset_packets()
	var boss := MineBoss.new()
	boss.room=room
	boss.training_ai_disabled=true
	boss.configure(Bosses.resolve("BO04",4,2))
	room.enemies.add_child(boss)
	boss.state=&"chase"
	boss.position=Vector2(400,400)
	boss.boss_brain.phase=3
	boss.boss_brain.rage_time=5
	boss.boss_brain.current_action="axe_fan"
	boss.boss_brain.command=boss.boss_brain._build_action(boss,player,"axe_fan")
	boss.boss_brain.command.delay=1.0
	boss.boss_brain._execute(boss)
	expected=Target._round_product([boss.profile.damage,1.15,1.25,1.3,1.2])
	check(runtime.jobs[0].damage==expected,"Boss phase and war-drum1.25 applied once")
	boss.boss_brain.phase=1
	boss.boss_brain.rage_time=0
	runtime.advance(1.01)
	check(player.received[0].amount==expected,"delayed Boss phase and drum remain frozen")
	boss.free()

func _test_support_and_pods() -> void:
	_reset_packets()
	var actor := _actor("M17",10,4)
	actor.position=Vector2(400,400)
	var recipient := _actor("M10",10,4)
	recipient.position=Vector2(430,400)
	recipient.health.reset(103,2)
	recipient.health.current=1
	var heal := {"kind":"heal","origin":actor.position,"target":actor.position,"direction":Vector2.RIGHT,"radius":100.0,"heal_ratio":.8,"max_targets":1,"exclude_self":true,"max_receives":2}
	actor.cast_enemy_skill(heal)
	check(recipient.health.current==16,"support heal rounded15% uses recipientHP without skill strength")
	actor.cast_enemy_skill(heal)
	actor.cast_enemy_skill(heal)
	check(recipient.health.current==31,"support target two-receipt limit retained")
	var guard := {"kind":"guard","mode":"network","origin":actor.position,"target":actor.position,"direction":Vector2.RIGHT,"radius":100.0,"shield_ratio":.8,"max_targets":1,"exclude_self":true,"charges":2}
	actor.cast_enemy_skill(guard)
	check(runtime.supports[-1].amount==36 and runtime.supports[-1].amount is int,"support35% cap rounds once rather than floors")
	check(runtime.supports[-1].charges==2,"shield charge count unscaled")
	check(is_equal_approx(runtime.filter_incoming_damage(recipient,5.4,&"skill",Vector2.RIGHT),.4),"support absorbs integer5 without rounding leftover early")
	check(runtime.supports[-1].amount==31 and runtime.supports[-1].amount is int,"spent support pool remains integer")
	runtime.supports.clear()
	var cover := {"kind":"guard","mode":"cover","origin":actor.position,"target":actor.position,"direction":Vector2.RIGHT,"radius":100.0,"anchor_health":70.0,"cover_hp":2.0,"duration":3.0}
	actor.cast_enemy_skill(cover)
	var plate: Node2D = runtime._anchor(runtime.supports[-1])
	check(plate.health.maximum==800,"real cover clamps scaled durable endpoint800 once")
	_reset_packets()
	await_free_anchors()
	var pod := {"kind":"summon","origin":actor.position,"target":Vector2(650,450),"direction":Vector2.RIGHT,"count":1,"max_alive":2,"hatch_delay":2.0,"pod_health":100.0,"pod_break_armor_loss":2.0}
	actor.cast_enemy_skill(pod)
	check(runtime.jobs.size()==1,"one authored pod reservation")
	var anchor: Node2D = runtime._anchor(runtime.jobs[0])
	check(anchor.health.maximum==1392,"real pod above800 remains uncapped")
	var before := actor.armor
	anchor.health.damage(anchor.health.maximum)
	check(actor.armor==maxf(0,before-20),"actual pod break reduces armor20 exactly once")
	runtime._pod_disarmed(runtime.jobs[0])
	check(actor.armor==maxf(0,before-20),"pod repeated callback does not repeat armor loss")
	actor.free()
	recipient.free()
	_reset_packets()

func await_free_anchors() -> void:
	# Queued anchors must not occupy a slot in the next isolated subcase.
	for actor: Node in room.enemies.get_children():
		if actor.is_queued_for_deletion(): actor.free()

func _actual_facilities() -> void:
	_reset_packets()
	var host := preload("res://scripts/world/room_objectives.gd").new()
	host.room=room
	host.layout={"arena":room.ARENA,"obstructions":[]}
	room.add_child(host)
	for raw: float in [80.0,130.0,120.0,195.0]:
		var id := "durability_"+str(raw)
		var item: Dictionary = host.add_target(id,Vector2(800,500),raw,"","Fixture")
		var target: MineEnemy = item.target_actor
		check(target.health.maximum==Numbers.integer(raw*10) and target.health.maximum is int and target.status.ruleset_version==2,"real facility target inherits scale10 and ruleset2")
		target.take_damage(101.4,&"skill",Vector2.ZERO,{"damage_type":"true","equipment_eligible":false})
		check(target.health.current==Numbers.integer(raw*10)-101,"real facility target integer receiver")
		target.free()
	var scaled: Dictionary = host.add_target("native",Vector2(800,500),1300,"","Native",{"scale_version":10})
	check(scaled.target_actor.health.maximum==1300,"native facility durability marker prevents second10x")
	scaled.target_actor.free()
	var before: int = int(Game.run.hp)
	var hazard: Dictionary = host.add_hazard(player.position,30,7.25,1.1,.25)
	check(hazard.damage==73 and hazard.damage is int and hazard.delay==1.1 and hazard.radius==30,"facility hazard complete scale rounds once and keeps warning geometry")
	host._tick_hazards(1.1)
	host._tick_hazards(.1)
	check(player.received[-1].amount==73 and Game.run.hp<before,"actual facility hazard hits player at new scale")
	check(host.add_hazard(player.position,30,0).damage==0,"facility zero damage remainszero")
	check(host.add_hazard(player.position,30,73,1,.25,{"scale_version":10}).damage==73,"native facility hazard never double scales")
	Game.run.stats.ruleset_version=1
	var legacy: Dictionary = host.add_target("legacy",Vector2(800,500),80.5,"","Legacy")
	check(legacy.target_actor.health.maximum==80.5 and legacy.target_actor.status.ruleset_version==1,"legacy facility target stays unchanged")
	legacy.target_actor.free()
	check(host.add_hazard(player.position,30,7.25).damage==7.25,"legacy facility hazard stays fractional")
	Game.run.stats.ruleset_version=2
	host.targets.clear()
	host.free()
	var props := preload("res://scripts/world/room_props.gd").new()
	props.room=room
	props.entities=[{"id":"test_socket","kind":"shield_socket","tags":["shield_socket"],"position":Vector2(400,400),"radius":20.0,"enabled":true,"cooldown":0.0}]
	room.add_child(props)
	room.enemy_props=props
	var caster := _actor("M25",15,4)
	caster.position=Vector2(400,400)
	caster.health.reset(103,2)
	caster.cast_enemy_skill({"kind":"utility","action":"socket_recharge","target":caster.position,"range":100.0,"guard_ratio":.3,"shield_ratio":.9,"duration":1.6})
	check(caster.status.shield()==31 and caster.status.shield() is int,"real socket utility uses one guard ratio and integer recipientHP")
	check(props.entities[0].cooldown==4.0,"socket cooldown remains4seconds")
	caster.free()
	props.free()
	room.enemy_props=null

func _test_capacitor_and_drain() -> void:
	for id: String in ["M01","M19"]:
		_reset_packets()
		var caster := _actor(id,15,4)
		caster.position=Vector2(400,400)
		caster.health.reset(103,2)
		caster.health.current=52
		var command := {"kind":"melee","origin":caster.position,"target":player.position,"direction":Vector2.RIGHT,"range":220.0,"angle":1.8,"damage_multiplier":1.0}
		caster.cast_enemy_skill(command)
		if id=="M01": check(caster.status.shield()==8 and caster.status.shield() is int,"actual capacitor integer8% maxHP shield")
		else: check(caster.health.current==58,"actual grave drain respects integer6% maxHP cap")
		player.invulnerable=0
		caster.cast_enemy_skill(command)
		if id=="M01": check(caster.status.shield()==8,"capacitor repeat cannot stack within cooldown")
		else: check(caster.health.current==58,"grave drain cannot repeat before3seconds")
		caster.free()
