extends Node
const Layouts = preload("res://scripts/world/b05_room_layouts.gd")
const Geometry = preload("res://scripts/world/b05_room_geometry.gd")
const Host = preload("res://scripts/world/b05_room_mechanisms.gd")
const Schema = preload("res://scripts/world/b05_mechanism_snapshot.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B05 ROOT LIVE: "+label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b05_root_well_live"): get_tree().quit(2); return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":25002}),"isolated baseline")
	var room=load("res://scenes/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	for actor in room.enemies.get_children(): actor.free()
	room.layout=Layouts.build("L25",25002)
	room.layout_id="L25"
	room.expedition_context={"biome_id":"B05","room_id":"L25","role":"branch","difficulty":0}
	room._configure_ground_boundary()
	var host=Host.new();room.add_child(host);room.b05_mechanics=host
	check(host.configure_room(room,Geometry.room("L25"),0),"production host configured")
	var well=host.well_target("L25-root-01")
	check(well is MineEnemy and well.static_actor and not well.reward_enabled and well.actor_kind=="objective","ordinary attackable but no-reward objective")
	var initial: float=well.health.current
	check(not well.take_damage(10,&"primary",Vector2.RIGHT,{"invulnerable":true}),"rejected damage does not disconnect")
	check(float(host._network.snapshot().wells[well.well_id].hp)==initial,"network unchanged by immunity")
	check(well.take_damage(11,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"legal actual hit lands")
	check(float(host._network.snapshot().wells[well.well_id].hp)==float(well.health.current),"post-settlement HP receipt matches network")
	var plant: MineEnemy=load("res://scenes/enemy.tscn").instantiate()
	plant.room=room;plant.position=well.position+Vector2(40,0)
	plant.configure(Profiles.resolve("B05-M01",21,"normal",2,0),{"reward_enabled":false})
	room.enemies.add_child(plant)
	check(host.register_plant("test-plant",plant),"real enemy registers")
	host.tick(0.1)
	check(plant.status.guards.has("b05_root_network"),"real guard granted")
	check(float(plant.status.guards.b05_root_network.remaining)==12.0,"explicit twelve-second lifetime")
	var amount: float=plant.status.shield()
	plant.status.tick_guard(2.0);host.tick(2.0)
	check(float(plant.status.guards.b05_root_network.remaining)==10.0,"remaining time decreases without regrant")
	plant.position += Vector2(600,0);host.tick(0.1);plant.position -= Vector2(600,0);host.tick(0.1)
	check(plant.status.shield()==amount and float(plant.status.guards.b05_root_network.remaining)==10.0,"leave/reenter neither stacks nor resets shield")
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(host.checkpoint()))
	if not Schema.validate_checkpoint(snapshot): print("SNAPSHOT_DIAGNOSTIC ",JSON.stringify(snapshot))
	check(Schema.validate_checkpoint(snapshot),"full JSON mechanism snapshot valid")
	plant.status.tick_guard(3.0)
	check(host.restore_checkpoint(snapshot),"same room restores authored roots and residual pool")
	check(float(plant.status.guards.b05_root_network.remaining)==10.0,"restore preserves exact residual not fresh twelve")
	var before:=JSON.stringify(host.checkpoint())
	var broken:=snapshot.duplicate(true);broken.plant_guards["test-plant"].guard.remaining=999
	check(not host.restore_checkpoint(broken) and JSON.stringify(host.checkpoint())==before,"invalid restore atomic")
	check(host.set_well_mode(plant,"speed",6),"speed mode selected")
	check(host.movement_multiplier(plant)==1.08 and not host.well_can_refresh(well.well_id),"speed mode does not also grant shield")
	var killed_before: int=Game.run.kills
	check(well.take_damage(initial*2,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"confirmed destruction")
	host.tick(0.1)
	check(not well.is_alive() and not host.connected(plant) and Game.run.kills==killed_before,"destroyed well disconnects without kill rewards")
	check(not well.take_damage(100,&"primary",Vector2.RIGHT,{}),"repeat destruction rejected")
	plant.status.tick_guard(10.1);host.tick(10.1)
	check(not plant.status.guards.has("b05_root_network"),"old earned shield expires and cannot refresh after destruction")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_ROOT_WELL_LIVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
