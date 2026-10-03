extends Node
const Numbers = preload("res://scripts/levels/b08/numbers.gd")
const Encounters = preload("res://scripts/levels/b08/encounters.gd")
const Gate = preload("res://scripts/levels/b08/candidate_gate.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures+=1; push_error("B08 L44: "+label)
func _ready() -> void: run.call_deferred()
func actor(room: Node, id: String) -> EnemyActor:
	for candidate: EnemyActor in room.enemies.get_children():
		if candidate.enemy_id==id and candidate.is_alive() and not candidate.is_queued_for_deletion(): return candidate
	return null
func run() -> void:
	if not Gate.enabled(): get_tree().quit(2); return
	for d in 5:
		var waves := Encounters.waves("L44",d)
		check(waves.size()==(2 if d>=3 else 1),"finite wave count D"+str(d))
		check(waves[0].size()==3 and waves[0][1].rank==("elite" if d>=3 else "normal"),"front replacement D"+str(d))
	var room = load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	room.difficulty=4
	room._open_room("L44")
	check(room._living_combatants()==3 and room._next_wave==1,"authored first three actors")
	var priest := actor(room,"B08-M04")
	var guard := actor(room,"B08-M05")
	var thrower := actor(room,"B08-M06")
	check(priest!=null and guard!=null and thrower!=null,"three independent identities")
	priest.position=Vector2(720,560)
	guard.position=Vector2(760,600)
	thrower.position=Vector2(980,440)
	room.player.position=Vector2(780,760)
	priest.brain._begin(priest,room.player)
	check(priest.brain.action.kind=="support" and priest.brain.action.recipient.get_ref()==guard,"priest freezes one eligible ally")
	check(priest.brain.remaining==1.1,"priest full warning")
	priest.brain._release(priest)
	check(room.harbor.support.has(guard.get_instance_id()) and priest.brain.remaining==1.5,"D4 support completes with exposed recovery")
	check(not room.harbor.grant_support(priest,guard),"support cannot stack")
	var boss: EnemyActor = room.spawn_enemy(Vector2(900,650),"BO08",40)
	check(not room.harbor.grant_support(priest,boss),"priest excludes Boss")
	boss.free()
	check(room.harbor.reposition_multiplier(guard)==1.0,"support does not accelerate walking")
	room.harbor.begin_reposition(guard)
	check(room.harbor.reposition_multiplier(guard)==1.15,"next warned reposition +15")
	room.harbor.end_reposition(guard,100,true)
	check(int(guard.status.shield())==roundi(guard.health.maximum*.04),"D2 real post-move guard")
	var shield: float = guard.status.shield()
	room.harbor.end_reposition(guard,100,true)
	check(guard.status.shield()==shield,"post-move shield is one-shot")
	check(room.harbor.grant_support(priest,guard),"new successful aid")
	room.harbor.advance(5)
	check(not room.harbor.support.has(guard.get_instance_id()),"aid expires at 5s")
	priest.brain.cooldown=0
	priest.brain._begin(priest,room.player)
	priest.take_damage(1,&"test",Vector2.ZERO,{"damage_type":"true"})
	check(priest.brain.phase=="recovery" and priest.brain.cooldown>=5.5,"real direct damage interrupts support")
	check(not room.harbor.support.has(guard.get_instance_id()),"interrupted cast grants nothing")
	room.warnings.clear()
	guard.position=Vector2(460,330) # Authored north-going L44 lane.
	room.player.position=Vector2(460,530)
	guard.brain._begin(guard,room.player)
	check(guard.brain.action.kind=="shield" and is_equal_approx(guard.position.distance_to(guard.brain.action.target),100),"shield advances frozen 100 units")
	check(guard.brain.remaining==1.0,"shield full warning")
	guard.brain._release(guard)
	var origin: Vector2 = guard.position
	for frame in 100:
		guard.brain.tick(guard,1.0/60,room.player)
		guard._finish_motion(1.0/60)
		if guard.brain.phase=="recovery": break
	check(guard.brain.phase=="recovery" and guard.position.distance_to(origin)>=88,"actual shield physical advance")
	check(room.valid_ground(guard.position,guard.navigation_radius),"shield clips to safe ground")
	check(room.wind.boons.get(str(guard.get_instance_id()),{}).get("available",true)==false,"shield consumes earned tailwind once")
	room._flag.take_damage(999999,&"test",Vector2.ZERO,{"damage_type":"true"})
	check(not room.wind.grant_tailwind("another","lane_0",true,100),"broken flag suppresses racial wind advantage")
	await get_tree().process_frame
	# The bell is attackable before its first release, and destruction cancels it.
	room.warnings.clear()
	thrower.position=Vector2(960,480)
	room.player.position=Vector2(960,700)
	thrower.brain._begin(thrower,room.player)
	var bell: EnemyActor = thrower.brain.action.bell.get_ref()
	check(bell!=null and bell.static_actor and bell.reward_enabled==false,"real destructible skill bell")
	var hp: float = Game.run.hp
	bell.take_damage(999999,&"test",Vector2.ZERO,{"damage_type":"true"})
	thrower.brain.tick(thrower,1.1,room.player)
	check(thrower.brain.phase=="recovery" and room.harbor.chimes.is_empty() and Game.run.hp==hp,"breaking warning bell prevents damage")
	await get_tree().process_frame
	# Miss the first ring, enter the smaller D4 echo, and observe real damage.
	thrower.brain.cooldown=0
	room.warnings.clear()
	room.player.position=Vector2(960,700)
	thrower.brain._begin(thrower,room.player)
	var center: Vector2 = thrower.brain.action.target
	room.player.position=center+Vector2(150,0)
	thrower.brain._release(thrower)
	var job: Dictionary = room.harbor.chimes[thrower.get_instance_id()]
	check(job.phase=="echo_warning" and job.echo_radius==55.0 and job.remaining==.8,"D4 exact delayed smaller echo")
	room.player.position=center
	room.player.invulnerable=0
	hp=Game.run.hp
	room.harbor.advance(.79)
	check(Game.run.hp==hp,"echo cannot hit early")
	room.harbor.advance(.01)
	check(Game.run.hp<hp and room.harbor.chimes.is_empty(),"actual echo damage once after .8s")
	check(not room.warnings.has(str(thrower.get_instance_id())),"chime releases warning budget")
	# Movement interruption cannot leave an armed bell that blocks future casts.
	thrower.brain.cooldown=0
	room.warnings.clear()
	room.player.position=Vector2(960,700)
	thrower.brain._begin(thrower,room.player)
	thrower.position+=Vector2(40,0)
	thrower.brain.tick(thrower,.1,room.player)
	check(thrower.brain.phase=="recovery" and room.harbor.chimes.is_empty(),"interrupted throw releases armed bell ownership")
	await get_tree().process_frame
	thrower.brain.cooldown=0
	thrower.brain._begin(thrower,room.player)
	check(thrower.brain.action.kind=="chime" and not room.harbor.chimes.is_empty(),"new throw admitted after cancellation")
	thrower.take_damage(999999,&"test",Vector2.ZERO,{"damage_type":"true"})
	check(room.harbor.chimes.is_empty(),"owner death cancels all pending chime damage")
	await get_tree().process_frame
	# D0 has no second ring; room replacement removes delayed jobs and buffs.
	room.difficulty=0
	room._open_room("L44")
	thrower=actor(room,"B08-M06")
	room.player.position=Vector2(960,700)
	thrower.position=Vector2(960,480)
	thrower.brain._begin(thrower,room.player)
	room.player.position+=Vector2(150,0)
	thrower.brain._release(thrower)
	check(room.harbor.chimes.is_empty(),"D0 no echo")
	room.difficulty=3
	room._open_room("L44")
	for enemy: EnemyActor in room.enemies.get_children():
		if not enemy.static_actor: enemy.free()
	room._tick_authored_waves(2.99)
	check(room._living_combatants()==0,"reinforcements wait full 3s")
	room._tick_authored_waves(.01)
	check(room._living_combatants()==2 and room._next_wave==2,"one finite D3 later wave")
	for enemy: EnemyActor in room.enemies.get_children():
		if not enemy.static_actor: enemy.free()
	room._tick_authored_waves(20)
	check(room._living_combatants()==0 and room._next_wave==2,"no infinite waves")
	room._open_room("L45")
	check(room.harbor.support.is_empty() and room.harbor.chimes.is_empty(),"transition clears L44 ownership")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no progression reward writes")
	check(await room.cleanup_for_exit(),"drain real audio on test exit")
	room.free()
	await get_tree().process_frame
	print("B08_L44 checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
