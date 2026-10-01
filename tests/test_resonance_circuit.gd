extends Node
const RoomScene = preload("res://scenes/room.tscn")
var checks: int = 0
var failures: int = 0
var room: MineRoom

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + note)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Game.profile_path.contains("test_resonance_circuit"):
		get_tree().quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate","circuit_place","circuit_release"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.start_demo("CH01"), "standalone full-skill demo starts without profile")
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	for enemy in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(600,600)
	var circuit: Node2D = room.circuit
	check(not circuit.place(Vector2(1500,600)), "remote placement rejected")
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(480,540,40,120)])
	check(not circuit.place(Vector2(500,580)), "cannot place inside obstacle")
	room.geometry_enabled = false
	check(circuit.place(Vector2(600,440)), "first anchor")
	circuit.advance(0.21)
	check(not circuit.place(Vector2(600,480)), "anchors cannot stack")
	check(circuit.place(Vector2(600,760)), "second anchor")
	check(not circuit.intercept(Vector2(700,500),Vector2(500,500)), "arming period gives no instant shield")
	circuit.advance(0.5)
	check(not circuit.intercept(Vector2(700,500),Vector2(500,500),0.3), "a victim hit first cannot be retroactively saved")
	check(circuit.intercept(Vector2(700,500),Vector2(500,500)), "crossing hostile path stored")
	check(circuit.charge == 1, "one actual crossing one charge")
	room.set_pointer_input_blocked(true)
	check(circuit.intercept(Vector2(700,520),Vector2(500,520)), "hovering HUD cannot disable a deployed passive defense")
	room.set_pointer_input_blocked(false)
	check(not circuit.intercept(Vector2(700,800),Vector2(500,800)), "outside line segment not caught")
	circuit.intercept(Vector2(700,500),Vector2(500,500))
	check(circuit.charge == 3 and not circuit.intercept(Vector2(700,500),Vector2(500,500)), "full circuit cannot absorb more shots")
	var victim: MineEnemy = room.spawn_enemy(Vector2(615,520))
	victim.state = &"chase"
	victim.health.reset(10000)
	var health_before: float = victim.health.current
	check(circuit.discharge(), "manual release")
	check(victim.health.current < health_before and circuit.charge == 0, "real damage and finite charge spent")
	check(not bool(victim.last_damage_context.get("equipment_eligible",true)), "burst cannot start an equipment chain")
	check(not circuit.discharge(), "cannot repeat burst with empty charge")
	circuit.advance(0.8)
	victim.position = Vector2(700,540)
	circuit.advance(0.1)
	victim.position = Vector2(550,540)
	circuit.advance(0.1)
	check(circuit.charge == 1, "moving melee enemy charges line")
	victim.position = Vector2(700,540)
	circuit.advance(0.1)
	check(circuit.charge == 1, "one enemy cannot farm repeated crossing charges")
	room.input_blocked = true
	check(not circuit.discharge() and not circuit.intercept(Vector2(700,500),Vector2(500,500)), "modal blocks circuit action and interception")
	room.input_blocked = false
	get_tree().paused = true
	check(not circuit.discharge(), "pause blocks release")
	get_tree().paused = false
	check(circuit.place(Vector2(850,650)), "reposition anchor")
	check(circuit.charge == 0 and circuit.anchors.size() == 2, "reposition spends accumulated charge and keeps only two anchors")
	circuit.reset_room()
	check(circuit.anchors.is_empty() and circuit.charge == 0, "room reset retires every anchor")
	# Real EnemySkillRuntime swept projectile, not a direct circuit call.
	room.obstructions.clear()
	room.player.position = Vector2(500,600)
	circuit.place(Vector2(600,440))
	circuit.advance(0.21)
	circuit.place(Vector2(600,760))
	circuit.advance(0.5)
	victim.position = Vector2(820,600)
	var hp_before: float = Game.run.hp
	room.enemy_skills.emit_skill(victim,{"kind":"projectile","origin":victim.position,"direction":Vector2.LEFT,"target":room.player.position,"speed":800.0,"range":600.0,"damage":20.0})
	room.enemy_skills.advance(0.5)
	check(circuit.charge == 1 and Game.run.hp == hp_before, "actual hostile projectile caught before player collision")
	check(room.enemy_skills.projectiles.is_empty(), "caught projectile removed from runtime")
	var node: Node2D = room.add_deployment("node",Vector2(720,600),{"owner_player":room.player,"health":100.0})
	var node_hp: float = node.health
	circuit.charge = 0
	room.enemy_skills.emit_skill(victim,{"kind":"projectile","origin":victim.position,"direction":Vector2.LEFT,"target":room.player.position,"speed":800.0,"range":600.0,"damage":20.0,"pierce":2})
	room.enemy_skills.advance(0.5)
	check(node.health < node_hp,"piercing shot hits a node before the circuit")
	check(circuit.charge==1 and Game.run.hp==hp_before and room.enemy_skills.projectiles.is_empty(),"remaining piercing path is caught before reaching the player")
	await room.combat_audio.wait_for_cleanup()
	room.free()
	Game.finish_run("abandoned")
	print("Resonance circuit: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
