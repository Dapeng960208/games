extends Node
const Layouts=preload("res://scripts/world/b05_room_layouts.gd")
const Geometry=preload("res://scripts/world/b05_room_geometry.gd")
const Host=preload("res://scripts/world/b05_room_mechanisms.gd")
const Skills=preload("res://scripts/combat/b05_enemy_skills.gd")
const Schema=preload("res://scripts/world/b05_mechanism_snapshot.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("B05 SUNLEAF: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b05_sunleaf"): get_tree().quit(2);return
	Game.run=null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":29002}),"isolated baseline")
	var room=load("res://scenes/room.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED;room.spawn_enabled=false
	add_child(room);await get_tree().process_frame
	for actor in room.enemies.get_children(): actor.free()
	room.layout=Layouts.build("L29",29002);room.layout_id="L29"
	room.expedition_context={"biome_id":"B05","room_id":"L29","role":"branch","difficulty":4}
	room._configure_ground_boundary()
	var host=Host.new();room.add_child(host);room.b05_mechanics=host
	check(host.configure_room(room,Geometry.room("L29"),4),"L29 production host")
	var west:=Geometry.world_point([980,720]);var east:=Geometry.world_point([1820,720])
	var caster=load("res://scenes/enemy.tscn").instantiate()
	caster.room=room;caster.position=west+Vector2(100,0)
	caster.configure(Skills.profile("B05-M14",25,4),{"reward_enabled":false})
	room.enemies.add_child(caster)
	room.player.position=west;room.release_gate=false
	check(room.nearby_interaction().get("kind","")=="b05_sunleaf","F discovers fixed leaf")
	check(room.interaction_hint().contains("遮光"),"hint states shade action")
	check(host.can_enemy_cast(caster,{"requires_sunlight":true}),"open west allows beam")
	caster.brain.tick(caster,0.81,room.player)
	check(bool(caster.brain.current_skill().get("requires_sunlight",false)),"real M14 starts solar telegraph")
	room.interact()
	check(not host.can_enemy_cast(caster,{"requires_sunlight":true}),"production F closes western source")
	check(caster.brain.current_skill().is_empty() and caster.brain.cooldown>=5.5,"closing interrupts cast with half cooldown")
	check(host.can_enemy_cast(caster,Skills.basic(caster.profile,caster.position,west)),"shade does not disable basic attacks")
	caster.position=east+Vector2(100,0)
	check(host.can_enemy_cast(caster,{"requires_sunlight":true}),"east stays independently lit")
	caster.position=west+Vector2(100,0)
	var closed: Dictionary=JSON.parse_string(JSON.stringify(host.checkpoint()))
	if not Schema.validate_checkpoint(closed): print("SUNLEAF_SNAPSHOT ",JSON.stringify(closed))
	check(Schema.validate_checkpoint(closed) and closed.production_version==2,"v2 snapshot stores leaves")
	room.interact()
	check(host.can_enemy_cast(caster,{"requires_sunlight":true}),"F reopens source")
	caster.state=&"idle"
	var command:=Skills.active(caster.profile,caster.position,caster.position+Vector2(200,0),true)
	room.enemy_skills.emit_skill(caster,command)
	check(room.enemy_skills.jobs.size()>=2,"D4 released command schedules endpoint and second beam")
	room.interact()
	check(room.enemy_skills.jobs.is_empty(),"shade removes unresolved solar followups")
	room.interact()
	room.enemy_skills.advance(2.0)
	check(room.enemy_skills.jobs.is_empty(),"reopening cannot resurrect cancelled beam")
	check(host.restore_checkpoint(closed) and not host.can_enemy_cast(caster,{"requires_sunlight":true}),"JSON restore keeps closed state")
	var invalid:=closed.duplicate(true);invalid.sunleaf_closed["invented-leaf"]=true
	var before:=JSON.stringify(host.checkpoint())
	check(not host.restore_checkpoint(invalid) and JSON.stringify(host.checkpoint())==before,"foreign leaf rejected atomically")
	var legacy:=closed.duplicate(true);legacy.erase("sunleaf_closed");legacy.production_version=1
	check(host.restore_checkpoint(legacy) and host.can_enemy_cast(caster,{"requires_sunlight":true}),"v1 migration defaults authored leaves open")
	room.set_input_blocked(true);room.interact()
	check(host.can_enemy_cast(caster,{"requires_sunlight":true}),"UI-blocked F cannot toggle")
	room.set_input_blocked(false);room.release_gate=false
	room.player.position=west+Vector2(200,0)
	check(not host.toggle_sunleaf("L29-sunleaf-west",room.player),"out-of-range toggle rejected")
	room.player.position=west
	var old_obstructions: Array[Rect2]=room.obstructions.duplicate()
	room.obstructions.append(Rect2(west-Vector2(1,20),Vector2(2,40)))
	room.player.position=west-Vector2(40,0)
	check(not host.toggle_sunleaf("L29-sunleaf-west",room.player),"occluded interaction rejected")
	room.obstructions=old_obstructions
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free();Game.run=null
	print("B05_SUNLEAF checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
