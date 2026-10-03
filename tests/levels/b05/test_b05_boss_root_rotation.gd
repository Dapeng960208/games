extends Node
const Layouts = preload("res://scripts/levels/b05/world/room_layouts.gd")
const Geometry = preload("res://scripts/levels/b05/world/room_geometry.gd")
const Host = preload("res://scripts/levels/b05/world/room_mechanisms.gd")
const Schema = preload("res://scripts/levels/b05/world/mechanism_snapshot.gd")
var checks := 0
var failures := 0
class CounterProbe extends Node2D:
	var counters: Array = []
	func apply_arena_counter(_kind: String, payload: Dictionary) -> bool:
		counters.append(payload)
		return true
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B05 ROOT ROTATION: "+label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b05_boss_root_rotation"): get_tree().quit(2); return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":35002}),"isolated baseline")
	var room=load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED;room.spawn_enabled=false
	add_child(room);await get_tree().process_frame
	for actor in room.enemies.get_children(): actor.free()
	room.layout=Layouts.build("BO05",35002);room.layout_id="BO05"
	room.expedition_context={"biome_id":"B05","room_id":"BO05","role":"boss","difficulty":0}
	room._configure_ground_boundary()
	var host=Host.new();room.add_child(host);room.b05_mechanics=host
	check(host.configure_room(room,Geometry.room("BO05"),0),"boss room configured")
	check(host.boss_root_state().active_count==1,"opening phase starts one well")
	var ids: Array=host._targets.keys();ids.sort()
	check(host.well_is_active(ids[0]) and not host.well_is_active(ids[1]),"P1 authored ordered first well")
	host.boss_phase_changed(2)
	check(host.boss_root_state().active_count==2,"P2 two wells")
	host.tick(19.0)
	check(host.well_is_active(ids[0]) and host.well_is_active(ids[1]),"P2 does not rotate")
	host.boss_phase_changed(3)
	host.tick(5.5)
	var checkpoint: Dictionary=JSON.parse_string(JSON.stringify(host.checkpoint()))
	check(Schema.validate_checkpoint(checkpoint),"rotation timer JSON valid")
	host.tick(100.0,true)
	check(host._boss_cycle==5.5 and host.well_is_active(ids[0]),"explicit pause freezes phase timer")
	host.tick(0.6)
	check(not host.well_is_active(ids[0]) and host.well_is_active(ids[1]) and host.well_is_active(ids[2]),"P3 rotates to second pair at six seconds")
	check(is_equal_approx(host._boss_cycle,0.1),"timer remainder retained")
	check(host.restore_checkpoint(checkpoint),"restore precise rotation state")
	host.tick(0.6)
	check(not host.well_is_active(ids[0]) and host.well_is_active(ids[2]),"restore resumes same next rotation")
	host.tick(6.0)
	check(host.well_is_active(ids[0]) and not host.well_is_active(ids[1]) and host.well_is_active(ids[2]),"third pair follows")
	host.tick(6.0)
	check(host.well_is_active(ids[0]) and host.well_is_active(ids[1]) and not host.well_is_active(ids[2]),"rotation wraps")
	var invalid:=host.checkpoint();invalid.well_activation[ids[2]]=true
	var before:=JSON.stringify(host.checkpoint())
	check(not host.restore_checkpoint(invalid) and before==JSON.stringify(host.checkpoint()),"three simultaneous wells rejected atomically")
	var probe:=CounterProbe.new();room.add_child(probe);room._boss_actor=probe
	var inactive=host.well_target(ids[2])
	check(inactive.take_damage(inactive.health.maximum*2,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"inactive well can be destroyed")
	check(probe.counters.is_empty(),"inactive well gives no active-root exposure")
	var active=host.well_target(ids[0])
	check(active.take_damage(active.health.maximum*2,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"active well can be destroyed")
	check(probe.counters.size()==1,"active well emits exactly one exposure counter")
	for step in 7:
		host.tick(6.0)
		check(host.boss_root_state().active_count<=1 and not host.well_is_active(ids[0]) and not host.well_is_active(ids[2]),"rotation never resurrects destroyed wells")
	var remaining=host.well_target(ids[1])
	check(remaining.take_damage(remaining.health.maximum*2,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"destroy last well")
	host.tick(6.0)
	check(host.all_wells_closed() and host.boss_root_state().active_count==0,"all destroyed stays unpowered")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_BOSS_ROOT_ROTATION checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
