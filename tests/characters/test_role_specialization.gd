extends Node
## Targeted V2 role behavior, using production actors, casts, collisions and
## resource clocks. The spell-only segment never calls fire or grants resources.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Growth = preload("res://scripts/domain/progression/skill_progression.gd")
var room: RoomController
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run_checks")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fixture(hero: String) -> void:
	if is_instance_valid(room): room.free()
	Game.run.hero_id = hero
	Game.run.level = 8
	Game.run.frozen_versions = Numbers.frozen_versions(Numbers.V2)
	Game.run.stats = StatResolver.resolve(hero,8,{},{},Numbers.V2)
	Game.run.stats.crit_chance = 0.0
	Game.profile.skill_state[hero] = Growth.fresh_state(hero)
	Game.run.skill_loadout_snapshot = Growth.starter_ids(hero)
	Game.run.skill_branches_snapshot = {hero + "_SK01":"", hero + "_SK04":""}
	Game.run.loadout_snapshot.clear()
	Game.run.equipment_snapshot.clear()
	Game.run.relics.clear()
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	Game.run.resource = Game.run.stats.resource_max
	Game.run.resource_regen_remainder = 0.0
	Game.run.resource_decay_remainder = 0.0
	Game.run.shield = 0
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = false
	room.release_gate = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(600,450)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false

func target(offset := Vector2(100,0)) -> EnemyActor:
	var enemy: EnemyActor = room.spawn_enemy(room.player.position+offset,"M01")
	enemy.health.reset(1000000,Numbers.V2)
	enemy.armor = 0
	enemy.magic_resist = 0
	enemy.reward_enabled = false
	enemy.training_ai_disabled = true
	enemy.rank = "boss" # Stable hit target, no AI, ordinary production damage path.
	return enemy

func step(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var dt := minf(1.0/60.0,remaining)
		for slot: String in room.player.cooldowns:
			room.player.cooldowns[slot] = maxf(0,float(room.player.cooldowns[slot])-dt)
		room.player._tick_class_state(dt)
		room.player._tick_resources(dt)
		room.player.abilities.tick(dt)
		for projectile: Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion(): projectile._physics_process(dt)
		for child: Node in room.get_children():
			if child.is_in_group("hero_deployments") and child.has_method("advance") and not child.is_queued_for_deletion(): child.advance(dt)
		room.player._consume_buffered_skill()
		room.player._tick_skill_buffer(dt)
		remaining -= dt

func run_checks() -> void:
	if not Game.profile_path.contains("test_role_specialization"):
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(),"isolated run")
	for hero: String in ["CH01","CH02","CH03"]:
		fixture(hero)
		for slot: String in ["q","secondary","f","ultimate"]:
			var spec: Dictionary = room.player.abilities.spec(slot)
			check(float(spec.duration)>float(spec.windup),hero+slot+" finite preparation/recovery")
			check(float(spec.cost)>0 and float(spec.cooldown)>0,hero+slot+" positive cost/cooldown")
		var old: Dictionary = HeroAbilities.preview_spec(hero,8,{"ruleset_version":1},"q")
		check(is_equal_approx(float(old.cooldown),2.4 if hero=="CH03" else 6.0),hero+" legacy numeric units use the current skill identity and timing")
		check(float(old.cost)==(12.0 if hero=="CH03" else 25.0 if hero=="CH02" else 20.0),hero+" legacy preview keeps authored resource units")
	_test_mage_independent()
	_test_spell_only()
	_test_buffer()
	if is_instance_valid(room): room.free()
	print("ROLE SPECIALIZATION: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_mage_independent() -> void:
	for slot: String in ["q","secondary","f","ultimate"]:
		fixture("CH03")
		var enemy := target()
		var before := float(enemy.health.current)
		check(room.player.cast_skill(slot,enemy.position),"standalone mage "+slot+" commits without basics/nodes")
		step(0.60)
		check(float(enemy.health.current)<before,"standalone mage "+slot+" causes direct useful damage")
	fixture("CH03")
	var enemy := target()
	var beginning: float = Game.run.resource
	check(room.player.cast_skill("secondary",enemy.position),"weave W")
	room.player.abilities.tick(.4)
	check(room.player.class_status().current==1 and Game.run.resource==beginning-200,"first actual spell release earns one star without refund")
	check(room.player.cast_skill("q",enemy.position),"weave Q")
	room.player.abilities.tick(.4)
	check(room.player.class_status().current==2 and Game.run.resource==beginning-200-120,"second actual spell release earns a second star")
	check(room.player.cast_skill("f",enemy.position),"weave E")
	check(Game.run.resource==beginning-200-120-200 and room.player.class_status().current==2,"third spell payment cannot award stars or an early refund")
	room.player.abilities.tick(.139)
	check(room.player.class_status().current==2,"third windup keeps the existing stars")
	room.player.abilities.tick(.001)
	check(room.player.class_status().current==3 and bool(room.player.class_state_view().ready),"third actual release primes the next spell's chorus")
	check(Game.run.resource==beginning-200-120-200 and is_equal_approx(room.player.skill_cooldown("q"),2.4),"priming chorus neither refunds mana nor trims identity cooldowns")
	var retained: float = Game.run.resource
	room.player.passives.skill_committed("f",room.player.abilities.cast_serial)
	check(Game.run.resource==retained and room.player.class_status().current==3,"retired commit callback cannot consume primed stars or refund")
	room.player.abilities.cancel()
	check(Game.run.resource==retained and room.player.class_status().current==3,"cancelling released recovery preserves primed chorus")
	check(room.player.cast_skill("ultimate",enemy.position),"fourth spell commits with primed chorus")
	var unboosted_power: float = room.player.abilities.active.power
	room.player.abilities.tick(.299)
	check(Game.run.resource==retained-500 and room.player.class_status().current==3,"fourth windup pays once and cannot consume or refund before release")
	room.player.abilities.tick(.001)
	check(Game.run.resource==retained-500+100 and room.player.class_status().current==0,"fourth actual release consumes three stars and refunds ten mana")
	check(room.player.abilities.active.power==Numbers.amount(unboosted_power*1.25,Numbers.V2) and is_equal_approx(float(room.player.abilities.active.guard_multiplier),1.25),"chorus freezes the 25-percent damage and shield boost on that cast")
	retained=Game.run.resource
	room.player.notify_skill_release(room.player.abilities.active.duplicate(true))
	room.player.passives.skill_committed("ultimate",room.player.abilities.cast_serial)
	check(Game.run.resource==retained and room.player.class_status().current==0,"duplicate release and retired commit callbacks cannot refund or stack again")
	room.player.abilities.cancel()
	check(Game.run.resource==retained,"cancelling released chorus recovery cannot refund again")
	step(2.4)
	Game.run.resource=0
	check(not room.player.cast_skill("q",enemy.position) and room.player.abilities.last_failure=="resource","insufficient resource rejects a ready skill")
	check(room.player.passives.snapshot().current==0,"failed cast cannot stack")
	fixture("CH03")
	room.player.aim_direction=Vector2.LEFT
	var landing:=room.player.position+Vector2.DOWN*120
	check(room.player.cast_skill("secondary",landing),"downward ground spell commits")
	room.player.aim_direction=Vector2.UP
	room.player.abilities.tick(.07)
	check(Vector2(room.player.abilities.active.direction).dot(Vector2.DOWN)>.99,"ground spell pose holds actual committed landing despite pointer turn")
	fixture("CH03")
	enemy=target()
	Game.run.resource=600
	check(room.player.cast_skill("q",enemy.position),"Q-W-Q first Q commits")
	step(.30)
	check(room.player.cast_skill("secondary",enemy.position),"Q-W-Q W commits")
	step(2.15)
	var before_repeat: float=Game.run.resource
	check(room.player.cast_skill("q",enemy.position),"Q-W-Q third alternating cast commits")
	check(Game.run.resource==before_repeat-120 and room.player.class_status().current==2,"repeated skill payment does not award the third star early")
	room.player.abilities.tick(.28)
	check(Game.run.resource==before_repeat-120 and room.player.class_status().current==3,"Q-W-Q releases prime chorus; three distinct skill identities are not required")
	check(room.player.cast_skill("f",enemy.position),"primed chorus cancellation fixture commits")
	retained=Game.run.resource
	room.player.abilities.tick(.139)
	room.player.abilities.cancel()
	room.player.abilities.tick(1.0)
	check(Game.run.resource==retained and room.player.class_status().current==3 and room.player.skill_cooldown("f")==7.0,"cancelling before first release spends the committed cost and cooldown but preserves primed stars")
	room.player._tick_class_state(8.0)
	check(room.player.class_status().current==0 and room.player.resonance_nodes().is_empty(),"eight seconds without a release clears stars and leaves retired crystal nodes absent")

func _test_spell_only() -> void:
	fixture("CH03")
	var enemy := target()
	var casts:=0
	var time:=0.0
	var next_cast:=0.0
	var minimum: float = Game.run.resource
	while time<60.0:
		if time+0.0001>=next_cast:
			check(room.player.cast_skill("q",enemy.position),"60s no-basic Q cast %d"%casts)
			casts+=1
			next_cast+=2.45
		step(.05)
		minimum=minf(minimum,float(Game.run.resource))
		time+=.05
	check(casts>=24 and room.player.get_node("HeroFeedback").basic_events==0,"60 seconds spell-only with at least24 casts and zero basics")
	check(minimum>=1080 and Game.run.resource>1000,"Q-only mana sustains through real regeneration and chorus without injected refills")
	check(float(enemy.health.current)<1000000,"spell-only projectiles actually hit")

func _test_buffer() -> void:
	fixture("CH03")
	var enemy := target()
	room.player.cooldowns[room.player.skill_id_for_slot("q")]=.15
	var resource: float = Game.run.resource
	check(room.player.request_skill("q",enemy.position),"final150ms cooldown accepts pre-input")
	check(room.player.combo_queue.size()==1 and Game.run.resource==resource,"pre-input does not spend early")
	check(not room.player.request_skill("q",enemy.position),"repeat input cannot duplicate queue")
	step(.16)
	check(room.player.abilities.cast_serial==1 and room.player.combo_queue.is_empty(),"pre-input commits once at readiness")
	room.player.abilities.cancel()
	room.player.cooldowns[room.player.skill_id_for_slot("q")]=.15
	check(room.player.request_skill("q",enemy.position),"second pending input")
	room.player.clear_buffered_skill()
	step(.2)
	check(room.player.abilities.cast_serial==1,"clearing queue prevents delayed cast")
	room.player.cooldowns[room.player.skill_id_for_slot("q")]=.17
	check(not room.player.request_skill("q",enemy.position),"beyond160ms retains cooldown failure")
