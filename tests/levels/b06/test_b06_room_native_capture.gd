extends Node
## Actual RoomController/BO06/prop render over a candidate floor. Not floor acceptance
## or natural combat balance evidence. Saves only to the managed output folder.
const Art = preload("res://scripts/levels/b06/art/native_art.gd")
var output := ""
func _ready() -> void: _capture.call_deferred()
func _capture() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b06_room_native_capture") or DisplayServer.get_name()=="headless": get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(2560,1440)
	get_window().size=Vector2i(2560,1440)
	Game.run=null
	if not Game.new_profile() or not Game.start_run({"expedition":true,"biome_id":"B01","seed":26012}): get_tree().quit(2); return
	var room=load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.process_mode=Node.PROCESS_MODE_DISABLED
	room.spawn_enabled=false
	add_child(room)
	await get_tree().process_frame
	var prepared:Dictionary=room.prepare_expedition_node({"room_id":"BO06","biome_id":"B06","role":"boss","difficulty":2,"seed":26012,"node_index":6,"b06_candidate":true})
	if not prepared.get("valid",false): get_tree().quit(1); return
	room.apply_prepared_expedition_node(prepared)
	for child in room.get_children():
		if child is CanvasItem and child not in [room.enemies,room.player,room.b06_mechanics,room.enemy_telegraphs,room.enemy_skills,room.interaction_overlay]: child.hide()
	room.camera.enabled=false
	var camera:=Camera2D.new()
	camera.position=Vector2(812,522)
	camera.zoom=Vector2(1.2,1.2)
	add_child(camera)
	camera.make_current()
	var floor:=Sprite2D.new()
	floor.texture=preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(Art.ROOT+str(Art.manifest().rooms.BO06.texture))
	floor.centered=false
	floor.position=Vector2(-1624*.11/.78,-1044*.13/.74)
	floor.scale=Vector2(1624/.78,1044/.74)/Vector2(floor.texture.get_size())
	floor.z_index=-30
	room.add_child(floor)
	var layer:=CanvasLayer.new()
	add_child(layer)
	var label:=Label.new()
	label.position=Vector2(40,30)
	label.add_theme_font_size_override("font_size",30)
	label.add_theme_color_override("font_color",Color("193548"))
	label.text="B06 candidate: actual room / boss / tide props. Floor alignment under review."
	layer.add_child(label)
	room.player.position=Vector2(840,680)
	room._boss_actor.aim_direction=Vector2.RIGHT
	room._boss_actor.body_visual.advance(.016)
	await _save("bo06-native-room-idle.png")
	room._boss_actor.health.current=floorf(float(room._boss_actor.health.maximum)*.65)
	room._boss_actor.boss_brain.tick(room._boss_actor,.016,room.player)
	room.b06_mechanics.tick(10)
	room._boss_actor.boss_brain._begin_action(room._boss_actor,room.player,"dual_cannon")
	room._boss_actor.body_visual.advance(.016)
	await _save("bo06-native-room-high-warning.png")
	var report:=FileAccess.open(AssetCatalog.resolve(output.path_join("room-native-capture.json")),FileAccess.WRITE)
	report.store_string(JSON.stringify({"dimensions":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"candidate_only":true,"floor_alignment_verified":false,"boss_height_world":207,"collision_radius":room._boss_actor.navigation_radius,"tide_phase":room.b06_mechanics.state.clock_state().phase},"\t"))
	await room.combat_audio.wait_for_cleanup()
	room.free();Game.run=null
	print("B06_ROOM_NATIVE_CAPTURE ",output)
	get_tree().quit(0)
func _save(name: String) -> void:
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	if image.get_size()!=Vector2i(2560,1440) or image.save_png(output.path_join(name))!=OK: get_tree().quit(1)
