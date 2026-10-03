extends Node
## Real Main entry and progression render check; never instantiates environment helpers.
## Lethal fixture hits verify transactions; this is NOT strength acceptance.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Routes = preload("res://scripts/domain/world/route_generator.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
var checks := 0
var failures := 0
var app: Node
var seen := {}
var selected_hero := "CH01"
var output := ""
var captured_rooms := []
func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok: failures+=1; push_error("B06 MAIN: "+label)
	return ok
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	output=OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or DisplayServer.get_name()=="headless": get_tree().quit(2); return
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().size=Vector2i(2560,1440)
	check(int(Rules.parameters().implemented_chapters)==4,"shipped release gate unchanged")
	for args in [PackedStringArray(["--candidate-b06"]),PackedStringArray(["--candidate-b06","--test-profile=user://profile.json"]),PackedStringArray(["--candidate-b06","--test-profile=user://test_b06_candidate/../profile.json"]),PackedStringArray(["--candidate-b06","--candidate-b05","--test-profile=user://test_b06_candidate/a.json"])]:
		check(not Rules._candidate_arguments_valid(args,"b06"),"unsafe candidate process rejected")
	if not Rules.b06_candidate_enabled():
		check(not Catalog.biomes().has("B06") and Catalog.biomes().size()==4,"normal catalog remains closed")
		finish();return
	check(Catalog.validate().is_empty(),"registered candidate catalog "+str(Catalog.validate()))
	check(Catalog.biomes().size()==6 and Catalog.room_ids().size()==36 and Catalog.enemy_ids().size()==90,"six-chapter candidate only catalog")
	check(preload("res://scripts/infrastructure/content/content_registry.gd").equipment_ids(2).size()==194,"B06 real35template registration")
	for set_mode in [false,true]:
		check(preload("res://scripts/presentation/equipment/instance_acquisition_panel.gd").creation_ids(set_mode).all(func(id: String): return not id.begins_with("B06-")),"unversioned B06 shop/craft hidden")
	var legacy := Routes.generate("B04",26014,[],20)
	check(legacy.valid,"old route generator still valid")
	for node:Dictionary in legacy.nodes: check(node.biome_id not in ["B05","B06"],"legacy ring does not expand")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hero="): selected_hero=arg.trim_prefix("--hero=")
	if selected_hero not in ["CH01","CH02","CH03"]: get_tree().quit(2); return
	Game.run=null
	if not check(Game.new_profile() and Game.select_hero(selected_hero),"fresh isolated profile"): finish();return
	check(not Game.start_run({"expedition":true,"biome_id":"B06"}),"BO05 prerequisite is enforced")
	var fixture:Dictionary=Game.profile.duplicate(true)
	fixture.bosses=["BO01","BO02","BO03","BO04","BO05"]
	fixture.hero_xp[selected_hero]=Growth.thresholds()[24]
	if not check(Game._commit_profile(fixture),"prior-chapter-clear profile fixture "+Game.last_error): finish();return
	app=load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	app.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(app)
	await get_tree().process_frame
	app.selected_biome="B06"
	app.selected_difficulty=0
	app.show_camp()
	check(preload("res://scripts/app/expedition_controller.gd").unlocked_biomes(Game.profile).has("B06"),"actual camp selector admits B06")
	if "--mechanisms-only" not in OS.get_cmdline_user_args(): await _capture("main-camp-b06.png")
	app._start_run_with_wish()
	if not check(Game.run!=null and is_instance_valid(app.room) and not app.room_start_failed,"actual Main entry handler "+Game.last_error): finish();return
	app.room.process_mode=Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	var run_id:String=Game.run.id
	for index in range(1,Game.run.expedition.route.nodes.size()):
		app._clear_modals()
		for offer:Dictionary in Game.expedition_snapshot().relic_offers:
			app._choose_expedition_relic(offer.offer_id,"skip")
		var next:Dictionary=app.expedition.next_node()
		app._advance_expedition(next.room_id)
		if not check(int(Game.run.expedition.node_index)==index and app.room.layout_id==next.room_id,"Main preflight/transaction/room entry "+str(next.room_id)+" "+Game.last_error): finish();return
		app.room.process_mode=Node.PROCESS_MODE_DISABLED
		await get_tree().process_frame
		app._clear_modals()
		var room:Node2D=app.room
		if next.role=="supply": continue
		await _capture_environment(room)
		if next.role=="boss":
			if not check(is_instance_valid(room._boss_actor) and room._boss_actor.boss_id=="BO06","real BO06 factory"): finish();return
			room._boss_actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats})
			await get_tree().process_frame
			room._tick_expedition(.1)
		else:
			for zone in room.encounter_zones.size():
				room.player.position=room.encounter_zones[zone].center
				var planned:Dictionary=room._encounter_plan(zone)
				for wave_index in planned.waves.size():
					room._tick_expedition(4.0)
					var actors:Array=[]
					for actor in room.enemies.get_children():
						if actor.is_alive() and not actor.is_queued_for_deletion(): actors.append(actor)
					check(not actors.is_empty() and actors.size()<=6 and room._room_committed_slots()<=18,"actual finite wave cap")
					for actor in actors:
						seen[actor.enemy_id]=true
						check(actor.reward_enabled,"registered progression enemies use real reward path")
						actor.take_damage(100000000,&"primary",Vector2.RIGHT,{"damage_type":"true","attacker_stats":Game.run.stats})
					await get_tree().process_frame
					room._tick_expedition(.1)
			check(room._encounters_exhausted(),"all finite waves required before settlement")
			room._tick_expedition(.1)
		if not check(room.objective_complete and room.objective_rewarded,"actual clear receipt "+room.layout_id+" "+Game.last_error): finish();return
		var receipt:Dictionary=Game.run.receipt()
		room._tick_expedition(1.0)
		check(Game.run.receipt()==receipt,"duplicate completion tick is idempotent")
		for drop:Dictionary in Game.pending_field_equipment():
			app._choose_field_equipment(drop.drop_id,"keep",str(Game.expedition_snapshot().checkpoint_id))
		var saved_phase:Dictionary=room.b06_mechanics.state.clock_state()
		check(await room.combat_audio.wait_for_cleanup(),"room audio drained")
		Game.reload_profile()
		if not check(Game.run!=null and Game.run.id==run_id,"real disk checkpoint reload "+Game.last_error): finish();return
		var previous_environment: WeakRef = weakref(room.b06_environment)
		app._continue_game()
		app.room.process_mode=Node.PROCESS_MODE_DISABLED
		await get_tree().process_frame
		app._clear_modals()
		check(previous_environment.get_ref()==null,"Main reload releases prior environment")
		check(is_instance_valid(app.room.b06_environment),"Main resume restores candidate environment "+app.room.layout_id)
		if "--mechanisms-only" not in OS.get_cmdline_user_args(): await _capture(app.room.layout_id.to_lower()+"-main-resumed.png")
		check(app.room.objective_rewarded and app.room._living_enemy_count()==0,"cleared resume does not respawn/reward")
		check(app.room.b06_mechanics.state.clock_state()==saved_phase,"exact saved tide phase through Main resume")
	check(captured_rooms.size()==7,"all seven unique rooms captured through Main")
	check(seen.size()==18,"all18species passed through actual director")
	var pending:Array=Game.run.expedition.pending_equipment.keys()
	app._clear_modals()
	app.show_extraction()
	app._settle("extracted")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(app.room),"Main extraction releases room and environment")
	check(Game.run==null and "BO06" in Game.profile.bosses,"actual Main extraction banks BO06")
	for id:String in pending:
		check(Game.profile.equipment.has(id),"real B06 item banked")
		check(selected_hero in Game.profile.equipment[id].allowed_heroes,"banked item keeps class eligibility")
	var result:Dictionary=Game.last_result
	check(Game.finish_run("extracted")==result,"duplicate extraction frozen")
	Game.reload_profile()
	check(Game.run==null and Game.profile.total_runs==1 and "BO06" in Game.profile.bosses,"banked result survives disk reload")
	finish()
func finish() -> void:
	if is_instance_valid(app):
		app._shutdown_started=true
		app.set_process(false)
		app.set_process_input(false)
		app.set_process_unhandled_input(false)
		if is_instance_valid(app.room): await app.room.combat_audio.wait_for_cleanup()
		if is_instance_valid(app.music): check(await app.music.wait_for_cleanup(),"Main music cleanup")
		app.free()
	Game.run=null
	print("B06_ENVIRONMENT_MAIN checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func _capture_environment(room: Node2D) -> void:
	check(is_instance_valid(room.b06_environment),"Main installs native candidate helper "+room.layout_id)
	check(room.get_children().filter(func(child: Node): return child.name=="B06Environment").size()==1,"Main has exactly one environment layer")
	check(room.b06_mechanics.native_water_visual,"Main installs native water visuals")
	if room.layout_id not in captured_rooms: captured_rooms.append(room.layout_id)
	if room.layout_id=="BO06":
		if "--mechanisms-only" not in OS.get_cmdline_user_args(): await _capture("bo06-main-p1.png")
		room._boss_actor.health.current=floorf(room._boss_actor.health.maximum*.65)
		room._boss_actor.boss_brain.tick(room._boss_actor,.016,room.player)
	room.player.position=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point([1400,900])
	room.camera.follow_target(); room.camera.force_update_scroll()
	for phase: String in ["low","warning","high"]:
		if phase!="low":
			var guard:=0
			while str(room.b06_mechanics.state.clock_state().phase)!=phase and guard<160:
				room.b06_mechanics.tick(.1,false); guard+=1
		check(str(room.b06_mechanics.state.clock_state().phase)==phase,"Main same tide phase "+room.layout_id+" "+phase)
		room.b06_environment.refresh_water()
		for layer: Polygon2D in room.b06_environment.water_layers:
			var wet: bool=room.b06_mechanics.is_patch_wet(str(layer.get_meta("patch_id")))
			check(is_equal_approx(float(layer.material.get_shader_parameter("wet_opacity")),.48 if wet else .025),"Main water shares production state")
		room.b06_mechanics.queue_redraw()
		room.enemy_telegraphs.refresh()
		if "--mechanisms-only" not in OS.get_cmdline_user_args(): await _capture(room.layout_id.to_lower()+"-main-"+phase+".png")
	if "--mechanisms-only" in OS.get_cmdline_user_args():
		var geometry: Dictionary=preload("res://scripts/levels/b06/world/room_geometry.gd").room(room.layout_id)
		var mechanisms: Array=geometry.get("gates",[]).duplicate(true)
		if geometry.has("tide_bell"): mechanisms.append({"id":"tide_bell","position":geometry.tide_bell})
		if room.layout_id=="BO06": mechanisms.append({"id":"boss_near","position":[1400,720]})
		for mechanism: Dictionary in mechanisms:
			var point: Array=mechanism.get("position",[1400,900])
			room.player.position=preload("res://scripts/levels/b06/world/room_geometry.gd").world_point(point)+Vector2(0,55)
			room.camera.follow_target(); room.camera.force_update_scroll()
			await _capture(room.layout_id.to_lower()+"-main-approach-"+str(mechanism.id)+".png")
func _capture(name: String) -> void:
	if is_instance_valid(app.hud): app.hud.refresh()
	if is_instance_valid(app.room):
		app.room.queue_redraw()
		app.room.interaction_overlay.queue_redraw()
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440),"actual Main 2K framebuffer")
	check(image.save_png(output.path_join(name))==OK,"capture "+name)
