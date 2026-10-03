extends Node
const Layouts = preload("res://scripts/levels/b05/world/room_layouts.gd")
const Geometry = preload("res://scripts/levels/b05/world/room_geometry.gd")
const Host = preload("res://scripts/levels/b05/world/room_mechanisms.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B05 TRANSITIONS: "+label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b05_room_transitions"): get_tree().quit(2); return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":26002}),"isolated baseline")
	var room=load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	for actor in room.enemies.get_children(): actor.free()
	room.layout=Layouts.build("L26",26002)
	room.layout_id="L26"
	room.expedition_context={"biome_id":"B05","room_id":"L26","role":"branch","difficulty":0}
	room._configure_ground_boundary()
	var host=Host.new();room.add_child(host);room.b05_mechanics=host
	check(host.configure_room(room,Geometry.room("L26"),0),"production host configured")
	var well=host.well_target("L26-root-01")
	check(not room.valid_ground(well.position,0),"well centre blocks walking")
	check(room.valid_ground(well.position+Vector2(43,0),14),"beyond foot radius is clear")
	check(not room.valid_ground(well.position+Vector2(41,0),14),"actor radius respected")
	check(not host.blocks_ground(well.position+Vector2(25,25),0),"round footprint not sprite rectangle")
	var stopped: Vector2=room.move_actor(well.position-Vector2(80,0),Vector2(160,0),14)
	check(stopped.x <= well.position.x-41.99,"ordinary movement cannot pass through well")
	var bounds: Array=host.navigation_bounds();bounds.clear()
	check(host.navigation_bounds().size()==1,"navigation bounds returned by value")
	var bridge:=Geometry.world_point([1400,540])
	check(not room.valid_ground(bridge,0),"initial vine gate blocks")
	var closed: Dictionary=JSON.parse_string(JSON.stringify(host.checkpoint()))
	var initial_obstructions: int=room.obstructions.size()
	room.player.position=Geometry.world_point([784,990])
	room.release_gate=false
	check(room.nearby_interaction().get("kind","")=="b05_gate","production F route finds watergate")
	check(room.interaction_hint().contains("0.6"),"production hint displays channel time")
	room.interact()
	check(not host.checkpoint().network.channel.is_empty(),"production F starts watergate channel")
	host.tick(0.3)
	check(host.notify_actor_hit("player",1),"actual consumed damage interrupts")
	host.tick(0.4)
	check(not host.bridge_is_open("L26-vine-door") and not room.valid_ground(bridge,0),"interrupted gate remains closed")
	room.interact()
	check(not host.checkpoint().network.channel.is_empty(),"production F restarts channel")
	room.set_input_blocked(true)
	check(host.checkpoint().network.channel.is_empty(),"UI blocks cancel channel immediately")
	room.set_input_blocked(false);room.release_gate=false
	room.interact()
	host.tick(0.61)
	check(host.bridge_is_open("L26-vine-door") and room.valid_ground(bridge,0),"completed channel opens actual collision")
	check(room.obstructions.size()==initial_obstructions-1,"only matching gate removed")
	check(room.layout.static_obstructions.size()==initial_obstructions,"immutable source preserved")
	check(not host.interact("L26-watergate",room.player,"player",func(): return true,func(_a,_b): return true),"completed gate cannot reward/retrigger")
	check(room.nearby_interaction().get("kind","")!="b05_gate","completed gate removed from interaction list")
	var opened: Dictionary=JSON.parse_string(JSON.stringify(host.checkpoint()))
	check(host.restore_checkpoint(closed) and not room.valid_ground(bridge,0),"closed save restores collision after open")
	check(host.restore_checkpoint(opened) and room.valid_ground(bridge,0),"open save removes restored collision")
	check(host.restore_checkpoint(opened) and room.obstructions.size()==initial_obstructions-1,"repeat restore idempotent")
	var before:=JSON.stringify(host.checkpoint())
	check(not host.configure_room(room,Geometry.room("L25"),0) and JSON.stringify(host.checkpoint())==before,"reconfiguration rejected atomically")
	# The permanent western route remains walkable before and after opening.
	for saved: Dictionary in [closed,opened]:
		check(host.restore_checkpoint(saved),"route state restored")
		var route: Array=Geometry.room("L26").main_route
		for index in range(route.size()-1):
			var a:=Geometry.world_point(route[index]);var b:=Geometry.world_point(route[index+1])
			for step in range(21):
				check(room.valid_ground(a.lerp(b,float(step)/20.0),14),"permanent western bypass remains usable")
	check(host.restore_checkpoint(closed),"restore living well")
	check(well.take_damage(well.health.maximum*2,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats}),"destroy actual well")
	host.tick(0.1)
	check(not room.valid_ground(well.position,0),"destroyed remnant retains footprint")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_ROOM_TRANSITIONS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
