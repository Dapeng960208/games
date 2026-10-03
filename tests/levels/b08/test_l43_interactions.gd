extends Node
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
var checks:=0
var failures:=0
func check(value: bool, text: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 interactions: "+text)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	check(Game.profile_path.begins_with("user://test_b08_candidate/"),"isolated profile")
	var art=room.sky_interactions
	check(art!=null,"L43 gated interaction art loaded")
	if art==null: room.free(); get_tree().quit(1); return
	check(art.textures.size()==6 and art.errors.is_empty(),"six native sources include orthogonal pointer")
	for kind: String in art.frames:
		var frame: Dictionary=art.frames[kind]
		check(FileAccess.get_sha256(AssetCatalog.resolve(art.ROOT+frame.file))==frame.sha256,"original bytes "+kind)
		check((art.bounds(kind).position+Vector2(frame.anchor[0],frame.anchor[1])*float(frame.world_per_source_pixel)).is_zero_approx(),"registered source anchor maps to real point "+kind)
	var lane: Dictionary=Geometry.lanes("L43")[0]
	check(art.vane_body.position==lane.vane and art.flag_body.position==room._flag.position and room.exit_position==Geometry.point([2410,960]),"three original coordinates")
	check(room._flag.navigation_radius==18 and room.valid_ground(lane.vane,18),"no new prop collider or moved footprint")
	check(art.z_index==room.player.z_index and art.y_sort_enabled,"raised props share foot sort plane")
	room.player.position=art.flag_body.position+Vector2(0,-20)
	art.sync(1)
	check(is_equal_approx(art.flag_body.modulate.a,.46),"shared occlusion fades flag behind hero")
	room.player.position=art.flag_body.position+Vector2(0,20)
	art.sync(1)
	check(art.flag_body.modulate.a==1,"flag opacity restores in front")
	room.player.position=lane.vane+Vector2(0,-12)
	art.sync(1)
	check(is_equal_approx(art.vane_body.modulate.a,.46),"vane preserves hero readability")
	room.player.position=lane.vane
	room.input_blocked=false; room.release_gate=false
	room.interact()
	check(not room.wind.channel.is_empty() and room.wind.direction(lane.id,lane.direction)==Vector2.RIGHT,"real F interaction begins original .6 second channel")
	room.wind.advance(.6)
	check(not room.wind.pending.is_empty() and art.pointer_kind()=="vane_pointer" and room.wind.direction(lane.id,lane.direction)==Vector2.RIGHT,"warning does not change live pointer early")
	room.wind.advance(.999)
	check(room.wind.direction(lane.id,lane.direction)==Vector2.RIGHT,"full original warning time retained")
	room.wind.advance(.001)
	check(room.wind.direction(lane.id,lane.direction)==Vector2.LEFT and art.pointer_kind()=="vane_pointer","reverse selects mirrored native pointer")
	room.interact(); room.wind.advance(1.6)
	check(room.wind.direction(lane.id,lane.direction)==Vector2.UP and art.pointer_kind()=="vane_pointer_up","third actual wind state selects separately authored up pointer")
	Game.profile.settings["reduced_fx"]=true
	art.sync(1)
	check(art.pointer_kind()=="vane_pointer_up" and art.vane_body.visible,"reduced FX preserves third-state body")
	check(not room.exit_ready(),"real live encounters keep exit locked")
	room.player.position=room.exit_position
	room.interact()
	check(room.layout_id=="L43","locked exit cannot change rooms")
	for actor: Node2D in room.enemies.get_children():
		if not actor.static_actor: actor.health.current=0; actor._die()
	await get_tree().process_frame
	room._next_wave=maxi(0,room._authored_waves.size()-1) # Pending-wave fixture also covers D0's single wave.
	check(not room.exit_ready(),"remaining finite wave still blocks exit")
	room._next_wave=room._authored_waves.size() # Controlled cleared-state fixture.
	check(room.exit_ready() and room._flag.is_alive(),"static flag does not falsely lock cleared exit")
	var flag_at: Vector2=room._flag.position
	room._flag.health.current=0; room._flag._die()
	await get_tree().process_frame
	art.sync(1)
	check(art.flag_broken and art.flag_body.position==flag_at,"actual flag death selects debris at same registered foot")
	check(is_equal_approx(room.wind.suppressed_until-room.wind.now,8),"real flag break keeps original eight-second suppression")
	check(is_equal_approx(float(art.frames.flag_broken.world_per_source_pixel)*357,float(art.frames.flag_intact.world_per_source_pixel)*257),"broken base matches shared ground rim width")
	room.wind.advance(8); art.sync(1)
	check(art.flag_broken and room.wind.suppressed_until==room.wind.now,"broken flag remains broken after suppression ends")
	var weak_art: WeakRef=weakref(art)
	room.interact()
	check(room.layout_id=="L44" and room.sky_interactions==null and weak_art.get_ref()==null,"actual unlocked exit clears local skin without other-room activation")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no campaign rewards or completion writes")
	check(await room.cleanup_for_exit(),"bounded audio cleanup")
	room.free()
	await get_tree().process_frame
	print("B08_L43_INTERACTIONS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
