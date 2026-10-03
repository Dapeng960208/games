extends Node
## Actual isolated scene setup/lifecycle, not graphical or natural-play acceptance.
const Geometry=preload("res://scripts/levels/b08/geometry.gd")
const SharedHUD=preload("res://scripts/presentation/hud/hud.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 room painting: "+label)
func _ready() -> void: run.call_deferred()
func run() -> void:
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(1280,720)
	await get_tree().process_frame
	check(load("res://tests/levels/b08/test_room_painting_capture.gd").can_instantiate(),"bounded graphical proof parses")
	var path: String=Game.profile_path
	var existed:=FileAccess.file_exists(path)
	var digest:=FileAccess.get_sha256(path) if existed else ""
	var room=load("res://scenes/gameplay/world/b08_candidate.tscn").instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	check(room.painting_ready() and room.configuration_ready,"real scene accepts registered isolated L43 painting")
	if not room.painting_ready(): room.free(); get_tree().quit(1); return
	var mapping=room.painted_mapping
	var backdrop=room.get_node("MineBackdrop")
	check(backdrop.visible and backdrop.z_index==-20,"complete backdrop is behind floor signals")
	check(backdrop.blueprint_room_id=="L43" and backdrop.environment_world_rect==mapping.world_rect,"background shares same room identity and transform")
	check(backdrop.environment_chunks.chunks.size()==6,"six shared mother-image draw regions")
	check(backdrop.environment_chunks.native_detail==null,"unavailable native detail does not masquerade as loaded")
	check(room.sky_environment==null,"independent painting does not stack legacy floor assembly")
	check(room.camera.render_bounds==mapping.world_rect and room.camera.arena==mapping.floor.bounds,"camera uses full painting and physical outline")
	print("B08_PAINTING_CAMERA zoom=",room.camera.zoom," viewport=",get_viewport().get_visible_rect().size," painted=",room.camera.render_bounds)
	check(room.camera.zoom.is_equal_approx(Vector2(.85,.85)),"normal player camera scale retained")
	check(room.player.position==Geometry.point(Geometry.ENTRY.L43) and room.valid_ground(room.player.position,Balance.PLAYER_RADIUS),"same entry and full hero footprint")
	check(room.exit_position==Geometry.point(Geometry.EXIT.L43),"same exit anchor")
	check(room._flag.position==Vector2(340.4,481.8) and room.valid_ground(room._flag.position,20),"same real flag footprint")
	var identities: Array[String]=[]
	for actor: Node2D in room.enemies.get_children():
		if actor.static_actor: continue
		identities.append(actor.enemy_id)
		check(room.valid_ground(actor.position,actor.navigation_radius) and actor.navigation_radius==18,"unchanged enemy full-circle radius: "+actor.enemy_id)
		check(actor.native_art!=null and actor.native_art.convergence,"existing key-pose source active: "+actor.enemy_id)
	identities.sort()
	check(identities==["B08-M01","B08-M02","B08-M03"],"same finite first encounter")
	check(room.sky_interactions!=null and room.sky_projectile_art!=null,"existing runtime props and projectile presentation reused")
	var host=room.candidate_ui
	check(is_instance_valid(host) and host.hud.get_script().get_base_script()==SharedHUD,"existing combat HUD wired by thin local adapter")
	check(not room._hud.visible and host.hud.skill_slots.size()==5,"diagnostic label replaced by existing five-skill HUD")
	check(host.hud.quest_reward.text.contains("不保存") or host.hud.quest_reward.text.contains("no saves"),"no fictional candidate rewards")
	host.show_backpack()
	await get_tree().process_frame
	check(get_tree().paused and room.input_blocked,"existing backpack interrupts candidate input")
	room._open_room("L44")
	await get_tree().process_frame
	check(not get_tree().paused and room.candidate_ui==null and room._hud.visible,"room change tears down modal and candidate HUD")
	check(not room.painting_ready() and not backdrop.visible and room.sky_interactions==null,"L44 does not receive unreviewed first-room assets")
	check(Game.run.completed_reward_ids.is_empty() and Game.run.boss_defeats.is_empty(),"no progression or reward writes")
	check(await room.cleanup_for_exit(),"bounded real cleanup")
	room.free()
	Game.reload_profile()
	await get_tree().process_frame
	check(FileAccess.file_exists(path)==existed and (not existed or FileAccess.get_sha256(path)==digest),"isolated profile bytes unchanged")
	print("B08_ROOM_PAINTING checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
