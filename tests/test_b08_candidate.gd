extends Node
const Gate = preload("res://scripts/world/b08_candidate_gate.gd")
const Wind = preload("res://scripts/world/b08_wind_state.gd")
const Geometry = preload("res://scripts/world/b08_geometry.gd")
const Content = preload("res://scripts/world/b08_content.gd")
const Numbers = preload("res://scripts/combat/b08_numbers.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B08: "+label)
func _ready() -> void: run.call_deferred()
func run() -> void:
	if not Gate.enabled() or not Game.profile_path.begins_with("user://test_b08_candidate/"): get_tree().quit(2); return
	check(not Gate.valid_arguments(["--candidate-b08"]),"profile required")
	check(not Gate.valid_arguments(["--candidate-b08","--test-profile=user://profile.json"]),"production rejected")
	check(not Gate.valid_arguments(["--candidate-b08","--candidate-b06","--test-profile=user://test_b08_candidate/a.json"]),"mixed chapter rejected")
	check(not Gate.valid_arguments(["--candidate-b08","--test-profile=user://test_b08_candidate/../profile.json"]),"traversal rejected")
	check(Content.catalog().enemies.size()==18 and Content.room_ids().size()==7,"authored identities")
	check(not preload("res://config/numerical_rules.gd").b05_candidate_enabled(),"production chapter gate unchanged")
	var wind := Wind.new()
	check(wind.configure(["north","south"]),"wind configure")
	check(wind.movement("north",Vector2.RIGHT,Vector2.RIGHT)==1.2,"tailwind +20")
	check(wind.movement("north",Vector2.RIGHT,Vector2.LEFT)==.9,"headwind -10")
	check(wind.movement("",Vector2.RIGHT,Vector2.RIGHT)==1,"normal safe route")
	check(wind.begin_turn("north","player"),"begin channel")
	check(not wind.begin_turn("south","player"),"one switch at a time")
	wind.advance(.59)
	check(wind.pending.is_empty() and wind.lanes.north==0,"cannot skip channel")
	wind.advance(.01)
	check(not wind.pending.is_empty() and wind.lanes.north==0,"warning after .6s")
	wind.advance(.99)
	check(wind.lanes.north==0,"no early rotation")
	wind.advance(.01)
	check(wind.lanes.north==1,"rotation after full warning")
	wind.begin_turn("north","player")
	wind.advance(1.6)
	check(wind.lanes.north==2 and wind.consume_boss_counter(),"sidewind counter opens")
	check(not wind.consume_boss_counter(),"counter once")
	check(wind.grant_tailwind("wing","north",true,120),"warned real move grants boon")
	check(wind.consume_tailwind("wing",false,true)==1,"basic cannot consume")
	check(wind.consume_tailwind("wing",true,false)==1,"support cannot consume")
	check(wind.consume_tailwind("wing",true,true)==1.12,"next active +12")
	check(wind.consume_tailwind("wing",true,true)==1,"single consumption")
	check(not wind.grant_tailwind("wing","north",true,120),"ICD prevents restack")
	check(wind.admit_displacement("player") and not wind.admit_displacement("player"),"2s repeated push protection")
	wind.advance(10)
	check(wind.grant_tailwind("wing","north",true,120),"ICD expires")
	wind.advance(4)
	check(wind.consume_tailwind("wing",true,true)==1,"4s window expires")
	wind.break_flag()
	check(not wind.grant_tailwind("other","north",true,120),"broken flag suppresses")
	var old_clock: float = wind.now
	wind.advance(20,true)
	check(wind.now==old_clock,"pause freezes")
	wind.advance(8)
	check(wind.grant_tailwind("other","north",true,120),"suppression ends after 8s")
	check(wind.admit_dive("first") and not wind.admit_dive("second"),"one dive only")
	wind.release_dive("first")
	check(wind.admit_dive("second"),"dive lease releases")
	for id: String in Content.room_ids():
		check(Geometry.contains(id,Geometry.point(Geometry.ENTRY[id]),20),id+" entry on floor")
		check(Geometry.contains(id,Geometry.point(Geometry.EXIT[id]),20),id+" exit on floor")
		for lane: Dictionary in Geometry.lanes(id): check(Geometry.contains(id,lane.vane,20),id+" vane reachable floor")
		var start := Geometry.point(Geometry.ENTRY[id])
		check(Geometry.contains(id,Geometry.move(id,start,Vector2(-2000,0),20),20),id+" forced move clips")
	for id: String in Content.catalog().enemies:
		for d in 5:
			var p := Numbers.profile(id,d)
			check(p.max_hp>0 and p.damage>0 and p.crit_chance==.25 and p.crit_multiplier==2,id+" numbers D"+str(d))
	check(Numbers.profile("BO08").max_hp==32292 and Numbers.profile("BO08").damage==632,"authored Boss D0 only")
	var room = load("res://scenes/b08_candidate.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	check(room.configuration_ready and room.player!=null,"production player candidate scene")
	check(Game.run.demo and Game.run.level==20,"disposable explicit Lv20 diagnostic fixture")
	check(room.enemies.get_child_count()==4,"three real winged actors and flag")
	var live_lane: Dictionary = Geometry.lanes("L43")[0]
	room.player.position = live_lane.vane
	room.release_gate = false
	room.interact()
	check(not room.wind.channel.is_empty(),"actual F interaction starts channel")
	room._physics_process(.6)
	check(not room.wind.pending.is_empty(),"actual channel starts visible warning")
	room._physics_process(1.0)
	check(room.wind.lanes[live_lane.id]==1,"actual room applies wind rotation")
	room._flag.take_damage(999999,&"test",Vector2.ZERO,{"damage_type":"true"})
	check(room.wind.suppressed_until==room.wind.now+8,"actual destructible flag suppresses support")
	await get_tree().process_frame
	for id: String in Content.room_ids():
		room._open_room(id)
		check(room.layout_id==id and room.valid_ground(room.player.position,20),"live room "+id)
		# Fixed entry→exit path must remain connected without any wind requirement.
		var start := Vector2i((room.player.position-Vector2(20,20))/40)
		var finish := Vector2i((room.exit_position-Vector2(20,20))/40)
		check(room._grid.get_point_path(start,finish).size()>1,id+" permanent route")
	room._open_room("L43")
	var diver: MineEnemy
	for actor: MineEnemy in room.enemies.get_children():
		if actor.enemy_id=="B08-M02": diver=actor
	check(diver!=null and diver.brain!=null,"real diver brain")
	room.player.position = Vector2(880,550)
	diver.position = Vector2(800,550)
	diver.brain.phase = "chase"
	diver.brain._begin(diver,room.player)
	var locked: Vector2 = diver.brain.action.target
	room.player.position += Vector2(60,0)
	diver.brain.tick(diver,.2,room.player)
	check(diver.brain.action.target==locked,"dive never tracks after warning lock")
	diver.brain.tick(diver,1,room.player)
	check(diver.brain.phase=="transit","dive physical travel")
	var hp: float = diver.health.current
	check(diver.take_damage(10,&"test",Vector2.ZERO,{"damage_type":"true"}) and diver.health.current<hp,"flight remains targetable")
	for frame in 100:
		diver.brain.tick(diver,1.0/60,room.player)
		diver._finish_motion(1.0/60)
		if diver.brain.phase=="recovery": break
	check(diver.brain.phase=="recovery" and diver.brain.remaining>=1.1,"landing real recovery >=1.1s")
	check(room.valid_ground(diver.position,diver.navigation_radius),"landing footpoint clipped")
	room.player.invulnerable = 0
	var before: float = Game.run.hp
	room.hit_circle(diver,{"kind":"test","target":room.player.position},1,75)
	check(Game.run.hp<before,"actual player damage path")
	room._open_room("BO08")
	var boss: MineEnemy
	for actor: MineEnemy in room.enemies.get_children():
		if actor.enemy_id=="BO08": boss=actor
	check(boss!=null and boss.brain!=null,"distinct commander actor")
	room.wind.counter_ready=true
	room.wind.counter_until=room.wind.now+10
	boss.brain.action={"kind":"dive","origin":boss.position,"target":boss.position,"radius":95.0,"coefficient":1.2}
	boss.brain._release(boss)
	boss.brain._land(boss)
	check(boss.brain.remaining==3.0 and boss.brain.weak_until>boss.brain.clock,"sidewind extends landing and vulnerability")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"candidate grants no progression")
	room.free()
	print("B08_CANDIDATE checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
