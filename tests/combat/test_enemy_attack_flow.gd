extends "res://tests/combat/test_enemy_integration.gd"
## Real room, actor, navigation and recipient paths. Keep the player still so
## repeated misses reveal a decision/reach mismatch rather than successful dodges.

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_attack_flow"):
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated production run starts")
	fixture("L15")
	room.player.position = room.encounter_zones[1].center
	var native_actors: Array[EnemyActor] = []
	for index: int in 5:
		native_actors.append(room.spawn_enemy(room.player.position+Vector2.RIGHT.rotated(index*TAU/5)*60.0,["M27","M27","M21","M19","M23"][index],17,{"zone_index":1}))
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	var native_hp: float = Game.run.hp
	await get_tree().create_timer(6.0).timeout
	for actor: EnemyActor in native_actors:
		check(actor.brain.age > 5.0 and actor.is_physics_processing(), actor.enemy_id+" L15 crowd receives native physics ticks")
	check(Game.run.hp < native_hp,"standing among L15 level-17 enemies receives real damage")
	room.process_mode = Node.PROCESS_MODE_DISABLED
	_test_aggro()
	# Confirmed broken short attacks, ranged-to-melee followups, and one-shot
	# self blast. An empty field and motionless player must be punishable.
	for index: int in [6,9,10,13,16,17,18,21,25,29,30,35,36]:
		fixture()
		var id := "M%02d" % index
		var actor := room.spawn_enemy(room.player.position-Vector2(400,0), id, 15, {"zone_index":0})
		var hp: float = Game.run.hp
		until(func(): return Game.run.hp < hp and actor.brain.cycle > 0,32.0)
		check(Game.run.hp < hp,id+" approaches its actual attack reach and hurts a stationary player")
		check(actor.brain.cycle > 0,id+" completes a finite warned attack cycle")
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("ENEMY ATTACK FLOW: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_aggro() -> void:
	fixture()
	var actor := room.spawn_enemy(room.player.position-Vector2(120,0),"M01",1)
	actor.state = &"chase"
	check(actor._select_aggro_target() == room.player,"player is the default living aggro target")
	var node := HeroDeployment.new()
	room.add_child(node)
	node.configure(room,"node",{"health":1000.0,"damage":0.0,"lifetime":100.0})
	node.position = actor.position+Vector2(50,0)
	check(actor._select_aggro_target() == node,"closer visible node can draw ordinary enemy aggro")
	room.player.position = actor.position+Vector2(48,0)
	check(actor._select_aggro_target() == node,"nearly equal distances do not oscillate targets")
	actor.state = &"locked"
	room.player.position = actor.position+Vector2(5,0)
	check(actor._select_aggro_target() == node,"committed swing keeps its living target")
	actor.take_damage(1.0,&"primary",Vector2.ZERO,{"damage_type":"true"})
	check(actor._select_aggro_target() == room.player and actor.aggro_hold == 2.0,"direct hero hit draws bounded retaliation")
	actor.state = &"chase"
	actor.aggro_hold = 0.0
	actor.aggro_target = weakref(node)
	node.alive = false
	check(actor._select_aggro_target() == room.player,"dead deployment immediately returns aggro to the player")
	node.free()
	check(actor._select_aggro_target() == room.player,"freed target reference remains safe")
	var age: float = actor.brain.age
	get_tree().paused = true
	actor._physics_process(.5)
	check(actor.brain.age == age,"pause cannot advance enemy attack clocks")
	get_tree().paused = false
	actor._physics_process(.5)
	check(actor.brain.age > age,"unpause resumes the same enemy")
