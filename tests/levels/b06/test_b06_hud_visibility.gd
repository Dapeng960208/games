extends "res://tests/levels/b06/test_b06_environment_main.gd"
## Real Main route fixture; moves only the player/camera and advances real clocks.
## No actor/prop relocation, helper fixture, hidden danger or balance claims.
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
func _capture(name: String) -> void:
	if name.begins_with("hud-"): await super._capture(name)
func _capture_environment(room: Node2D) -> void:
	if room.layout_id not in captured_rooms: captured_rooms.append(room.layout_id)
	if room.layout_id not in ["L35","L36","BO06"]: return
	check(is_instance_valid(room.b06_environment),"real Main candidate environment")
	room.player.position=Geometry.world_point([1400,900])
	room.camera.follow_target(); room.camera.force_update_scroll()
	app.hud.refresh()
	check(app.hud._b06_tactical_layout,"candidate tactical HUD active")
	for cell: Control in app.hud.skill_slots:
		check(cell.visible and cell.get_global_rect().size.x>=44 and cell.get_global_rect().size.y>=44,"all five class skill targets remain usable")
	check(app.hud.health_label.visible and app.hud.resource_label.visible and app.hud.passive_panel.visible,"class health resource passive retained")
	if room.layout_id=="L35":
		await _capture("hud-"+selected_hero+"-l35-center.png")
		var bell:=Geometry.world_point(Geometry.room("L35").tide_bell)
		_assert_clear(room,Rect2(bell-Vector2(42,122),Vector2(84,122)),"north bell center")
		room.player.position=bell+Vector2(0,55)
		room.camera.follow_target(); room.camera.force_update_scroll()
		await _capture("hud-"+selected_hero+"-l35-bell-approach.png")
		check(not room.interaction_hint().is_empty(),"near bell interaction available")
	elif room.layout_id=="L36":
		for step in 100:
			if str(room.b06_mechanics.state.clock_state().phase)=="warning": break
			room.b06_mechanics.tick(.1,false)
		room.b06_environment.refresh_water();room.b06_mechanics.queue_redraw()
		await _capture("hud-"+selected_hero+"-l36-warning.png")
		for at:Array in [[1400,460],[1400,1400]]:
			_assert_clear(room,Rect2(Geometry.world_point(at)-Vector2(18,30),Vector2(36,60)),"central tide arrow "+str(at))
	else:
		room.player.position=Geometry.world_point([1400,720])+Vector2(0,55)
		room.camera.follow_target();room.camera.force_update_scroll()
		await _capture("hud-"+selected_hero+"-boss-near-idle.png")
		var boss:Node2D=room._boss_actor
		var body:Rect2=boss.body_bounds
		_assert_clear(room,Rect2(boss.position+Vector2(-115,body.position.y-62),Vector2(230,body.size.y+62)),"boss head body name and health")
		for step in 120:
			boss.boss_brain.tick(boss,.02,room.player)
			if not boss.boss_brain.current_telegraph().is_empty(): break
		check(not boss.boss_brain.current_telegraph().is_empty(),"real boss selected danger")
		room.enemy_telegraphs.refresh();boss.queue_redraw()
		await _capture("hud-"+selected_hero+"-boss-danger.png")
		check(app.hud.boss_cast_plate.visible and app.hud.boss_cast_plate.info.stage!="idle","live danger timing retained")
		var titles=preload("res://scripts/domain/combat/boss_ability_catalog.gd")
		for action:String in preload("res://scripts/levels/b06/combat/enemy_skills.gd").BOSS_ACTIONS:
			for english:bool in [false,true]: check(titles.title(action,english)!=action,"authored B06 boss title "+action)
		check(titles.title("unknown_test_action")=="unknown_test_action","unknown title fallback")
		check(app.hud.boss_cast_plate.info.title==titles.title(boss.boss_brain.current_action,Words.locale=="en"),"live HUD uses authored title")
		_assert_clear(room,Rect2(boss.position+Vector2(-115,body.position.y-62),Vector2(230,body.size.y+62)),"boss body during danger")
		# Same HUD instance can leave B06 without leaking its layout into old chapters.
		var original:Dictionary=room.layout
		room.layout=original.duplicate();room.layout["biome_id"]="B04";room.layout["b06_candidate"]=false
		app.hud._apply_layout()
		check(app.hud.skill_dock.scale==Vector2.ONE and app.hud.room_identity_plate.visible and app.hud.expedition_beads.visible,"legacy layout restores unchanged")
		room.layout=original;app.hud._apply_layout()
func _assert_clear(room: Node2D, world_rect: Rect2, label:String) -> void:
	var screen_rect:Rect2=app.hud.get_global_transform_with_canvas().affine_inverse()*room.get_global_transform_with_canvas()*world_rect
	for bounds:Rect2 in app.hud.coverage_rects():
		check(not screen_rect.intersects(bounds),label+" avoids HUD "+str(bounds))
	if app.hud.boss_cast_plate.visible: check(not screen_rect.intersects(app.hud.boss_cast_plate.get_global_rect()),label+" avoids boss cast plate")
