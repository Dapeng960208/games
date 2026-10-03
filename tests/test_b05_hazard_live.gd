extends Node
const Layouts=preload("res://scripts/world/b05_room_layouts.gd")
const Geometry=preload("res://scripts/world/b05_room_geometry.gd")
const Host=preload("res://scripts/world/b05_room_mechanisms.gd")
const Skills=preload("res://scripts/combat/b05_enemy_skills.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("B05 HAZARD LIVE: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b05_hazard_live"): get_tree().quit(2);return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":35007}),"isolated baseline")
	var room=load("res://scenes/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED;room.spawn_enabled=false
	add_child(room);await get_tree().process_frame
	for actor in room.enemies.get_children(): actor.free()
	room.layout=Layouts.build("BO05",35007);room.layout_id="BO05"
	room.expedition_context={"biome_id":"B05","room_id":"BO05","role":"boss","difficulty":4}
	room._configure_ground_boundary()
	var host=Host.new();room.add_child(host);room.b05_mechanics=host
	check(host.configure_room(room,Geometry.room("BO05"),4),"production arena configured")
	var caster=load("res://scenes/enemy.tscn").instantiate()
	caster.room=room;caster.position=Vector2(800,600)
	caster.configure(Skills.profile("B05-M01",25,4),{"reward_enabled":false});room.enemies.add_child(caster)
	room.player.position=caster.position+Vector2(100,0)
	host._hazard_admission.maximum_ratio=0
	caster.brain.tick(caster,.81,room.player)
	check(caster.brain.phase==&"recovery" and caster.brain.current_skill().is_empty(),"denied ordinary command never enters invisible telegraph")
	check(caster.brain.cooldown>=3.0 and caster.brain._remaining>=1.0,"denial consumes half active cooldown and at least one second")
	check(room.enemy_skills.jobs.is_empty() and room.enemy_skills.hazards.is_empty(),"denial releases no hidden runtime damage")
	host._hazard_admission.maximum_ratio=.3
	caster.brain.tick(caster,1.3,room.player)
	check(caster.brain.phase==&"telegraph","ordinary actor resumes chase/basic instead of remaining stuck")
	caster.brain.tick(caster,1.0,room.player)
	check(caster.brain.phase==&"locked","accepted command reaches lock")
	var locked: Dictionary=caster.brain.current_skill().duplicate(true)
	var expected: Vector2=locked.target
	room.player.position+=Vector2(120,100)
	caster.brain.tick(caster,.1,room.player)
	check(caster.brain.current_skill().get("target")==expected,"locked geometry does not retarget")
	var boss=load("res://scenes/combat/boss.tscn").instantiate()
	boss.room=room;boss.position=Vector2(600,600)
	check(boss.configure_boss("BO05",4,35007,2),"real BO05 configures")
	room.enemies.add_child(boss);room._boss_actor=boss
	room.player.position=boss.position+Vector2(100,0)
	host._hazard_admission.maximum_ratio=0
	boss.boss_brain.elapsed=7.0
	boss.boss_brain._begin_action(boss,room.player,"crown_sweep")
	check(boss.boss_brain.state==&"recovery" and boss.boss_brain.command.is_empty(),"boss rejected command clears warning/release state")
	check(boss.boss_brain.state_time>=1 and float(boss.boss_brain._action_ready_at.crown_sweep)>=10.5,"boss rejection spends half cooldown")
	host._hazard_admission.maximum_ratio=.3
	boss.boss_brain.elapsed=12.0
	boss.boss_brain._begin_action(boss,room.player,"crown_sweep")
	check(boss.boss_brain.state==&"telegraph" and bool(boss.boss_brain.command.get("b05_admitted",false)),"boss resumes admitted warned action")
	var reservation_id:=str(boss.boss_brain.command.b05_admission_id)
	var lease: float=host._hazard_admission.reservations[reservation_id].expires
	host.tick(50,true)
	check(host._hazard_admission.reservations[reservation_id].expires==lease and host._hazard_admission.clock==0,"pause does not advance reservations")
	room.enemy_skills.cancel_owner(boss)
	check(not host._hazard_admission.admitted(reservation_id),"owner cancellation frees admitted command lease")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_HAZARD_LIVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
