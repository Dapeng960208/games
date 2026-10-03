extends SceneTree
## Real main/room/controller integration. Test movement positions enemies and
## objective interactions directly; this verifies flow, not human combat balance.
const Controller = preload("res://scripts/app/expedition_controller.gd")
var checks := 0
var failures := 0
var app: Node
var game: Node
var finished := false
var visited: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")

func _finalize() -> void:
	if not finished:
		printerr("EXPEDITION_FLOW did not reach its final marker")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + description)
	else:
		print("PASS ",description)

func frames(count: int) -> void:
	for _index in count:
		await physics_frame
		await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name+".png")

func resolve_offers() -> void:
	for _attempt in range(8):
		var unresolved: Array = []
		for offer: Dictionary in game.expedition_snapshot().get("relic_offers",[]):
			if str(offer.get("decision","")).is_empty():
				unresolved.append(offer)
		if unresolved.is_empty():
			break
		var offer: Dictionary = unresolved[0]
		# Exercise a real relic effect initially; subsequent skips are legal,
		# idempotent health recovery, not direct completion or rank mutation.
		var choice := str(offer.candidates[0]) if game.run.relics.is_empty() else "skip"
		app._choose_expedition_relic(str(offer.offer_id),choice)
		await frames(1)
	# Drops now present a real equipment decision after relics. Resolve it via
	# the production Keep control before testing ordinary map input.
	for _drop in range(8):
		if game.pending_field_equipment().is_empty(): break
		app._show_pending_expedition_offer()
		await frames(1)
		var keep: Button = app.find_child("FieldKeepCurrent",true,false) as Button
		check(keep != null and not keep.disabled,"field drop offers a live Keep decision")
		if keep == null or keep.disabled: break
		keep.pressed.emit()
		await frames(2)
	check(app.modals.is_empty(),"required relic and equipment decisions return control")

func interact_objective(host: Node, id: String) -> void:
	var element: Dictionary = host.element(id)
	check(not element.is_empty(),"authored objective exists: "+id)
	if element.is_empty():
		return
	app.room.player.position = element.position
	check(host.interact(id,app.room.player),"actual objective interaction: "+id)

func finish_objective() -> void:
	var host: Node = app.room.get("objectives")
	if host == null:
		host = app.room.get("room_objectives")
	check(host != null,"room owns an authored objective host")
	if host == null:
		return
	match str(app.room.layout_id):
		"L01":
			for index in 3:
				interact_objective(host,"brake_"+str(index))
		"L02":
			interact_objective(host,"cargo_cart")
			for _step in 1600:
				if host.is_complete():
					break
				app.room.player.position = host.element("cargo_cart").position
				host.tick(.1)
		"L03":
			interact_objective(host,"gear_stop")
			for index in 2:
				interact_objective(host,"key_"+str(index))
		"L04":
			for index in 3:
				interact_objective(host,"crate_"+str(index))
				interact_objective(host,"scale_"+str(index))
		"L05":
			for index in 2:
				app.room.player.position = host.element("beacon_"+str(index)).position
				for _tick in 82:
					host.tick(.1)
		"L06":
			interact_objective(host,"furnace_cut")
	check(host.is_complete(),"authored objective completes without setting its flag")

func finish_combat_node() -> void:
	app._clear_modals()
	# The final L02 wave is gated by real cart progress. This flow fixture
	# advances authored objectives directly, rather than simulating combat.
	if str(app.room.layout_id) == "L02":
		finish_objective()
	for _cycle in range(20):
		for zone: Dictionary in app.room.encounter_zones:
			app.room.player.position = zone.get("center",zone.get("position",app.room.player.position))
			app.room._update_encounters(2.0)
		for enemy in app.room.enemies.get_children():
			if enemy.is_alive():
				enemy.take_damage(100000.0,&"test")
		for drop: Dictionary in app.room.gold_drops.duplicate(true):
			app.room.player.position = drop.at
			app.room._update_gold(.01)
		await frames(2)
		if app.room._encounters_exhausted() and app.room._living_enemy_count() == 0:
			break
	check(app.room._encounters_exhausted(),"all finite encounter waves exhausted")
	if str(app.room.layout_id) != "L02":
		finish_objective()
	app.room.player.position = app.room.layout.entry
	for _retry in range(90):
		if app.room.objective_rewarded:
			break
		await frames(1)
	if not app.room.objective_rewarded:
		print("FLOW_GATE_DEBUG ",JSON.stringify({"room":app.room.layout_id,"complete":app.room.objective_complete,"phase":game.expedition_snapshot().phase,"error":game.last_error,"retry":app.room.progress_retry_timer,"snapshot":app.room.expedition_runtime_snapshot()}))
	check(app.room.objective_complete and app.room.objective_rewarded,"clear gate requires actual objective and committed reward")
	check(app.expedition.current_complete(),"Game receipt agrees room is cleared")
	await resolve_offers()

func run_checks() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_"):
		quit(2)
		return
	create_timer(180).timeout.connect(func(): push_error("Expedition flow timed out"); quit(1))
	if game.run != null:
		game.finish_run("abandoned")
	check(game.new_profile(),"fresh isolated profile")
	check(Controller.unlocked_biomes(game.profile) == ["B01"],"new profile only opens first biome")
	check(Controller.unlocked_biomes({"bosses":["BO02"]}) == ["B01"],"biome progression cannot skip missing prior boss")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	root.add_child(app)
	await frames(2)
	app.show_camp()
	app._start_run()
	await frames(3)
	check(app.route == "run" and app.expedition.active(),"real camp starts expedition instead of legacy single map")
	if not is_instance_valid(app.room):
		finish_suite()
		return
	check(app.expedition.current_index() == 0 and app.room.enemies.get_child_count() == 0,"safe entry is node one without enemies")
	check(not app.modals.is_empty() and app.modals[-1].get("required",false),"entry presents a required relic decision")
	await capture("expedition_entry_relic")
	await resolve_offers()
	var original_player: Node = app.room.player
	var route_before: Dictionary = game.expedition_snapshot().route.duplicate(true)
	var node_count: int = route_before.nodes.size()
	var expected_boss: String = str(route_before.nodes[-1].room_id)
	var template_count := 0
	for node: Dictionary in route_before.nodes:
		if str(node.role) in ["branch", "objective", "elite_objective"]: template_count += 1
	check(node_count == 6 and int(game.expedition_snapshot().departure_level) == 1,"normal level-one departure fixes a six-node expedition")
	var map_key := InputEventAction.new()
	map_key.action = "expedition_map"
	map_key.pressed = true
	app._input(map_key)
	check(paused and not app.modals.is_empty(),"M input opens the real paused route chart")
	var entry_cards: Array[Node] = app.find_children("Choose_*","Button",true,false)
	check(not entry_cards.is_empty() and not entry_cards[0].disabled,"M route at safe entry offers clickable departure without walking to exit")
	await capture("expedition_route_entry")
	app._pop_modal()
	app.show_expedition(false)
	check(game.expedition_snapshot().route == route_before,"reopening M map never rerolls candidate routes")
	app._pop_modal()
	var initial_options: Array = app.expedition.next_options()
	var branches := 1 if initial_options.size()>1 else 0
	var first_room := str(initial_options[0])
	check(game.choose_expedition_node(1,first_room),"route choice commits once before a simulated write failure")
	var old_layout := str(app.room.layout_id)
	var healthy_path: String = game._store.path
	game._store.path = healthy_path+"/blocked.json"
	app.show_expedition(true)
	app._advance_expedition(first_room)
	check(app.expedition.current_index()==0 and str(app.room.layout_id)==old_layout,"next-entry write failure leaves the previous room and node intact")
	check(app.room.player==original_player,"failed transition retains player instance")
	check(str(game.expedition_snapshot().selected_next_room_id)==first_room,"failed transition preserves the locked route choice")
	game._store.path = healthy_path
	app._clear_modals()
	for next_index in range(1,node_count):
		var options: Array = app.expedition.next_options()
		if options.size()>1:
			branches += 1
		check(not options.is_empty(),"next node has a legal route")
		var selected := str(options[0])
		app.show_expedition(false)
		var hp_before: float = game.run.hp
		var resource_before: float = game.run.resource
		var route_choice: Button = app.find_child("Choose_"+selected,true,false) as Button
		check(route_choice != null and not route_choice.disabled,"completed-room M route offers enabled next-room control")
		if route_choice == null or route_choice.disabled: break
		route_choice.pressed.emit()
		check(app.expedition.current_index() == next_index,"actual main advances to node "+str(next_index+1))
		if app.expedition.current_index() != next_index:
			break
		check(app.room.player == original_player,"room transition preserves the actual player instance")
		check(is_equal_approx(game.run.hp,hp_before) and is_equal_approx(game.run.resource,resource_before),"node transition does not refill health or resource")
		await frames(2)
		var current: Dictionary = app.expedition.current_node()
		if str(current.role) in ["branch", "objective", "elite_objective"]:
			check(not visited.has(app.room.layout_id),"combat template is not repeated")
			visited.append(str(app.room.layout_id))
			check(not app.expedition.can_extract(),"incomplete combat room cannot extract")
			app.show_expedition(false)
			var preview_cards: Array[Node] = app.find_children("Choose_*","Button",true,false)
			check(not preview_cards.is_empty() and preview_cards[0].disabled,"M remains preview-only while the room objective is incomplete")
			app._pop_modal()
			await finish_combat_node()
			check(app.expedition.can_extract() == bool(current.early_extraction),"early extraction follows the completed node marker")
		elif current.role == "supply":
			check(app.room.enemies.get_child_count() == 0,"supply stop stays free of enemies")
			app.show_expedition_service()
			var before_gold: int = game.run.gold
			for offer: Dictionary in game.expedition_snapshot().supply_offers:
				if str(offer.product_id)=="amplify" and before_gold>=int(offer.price):
					app._buy_expedition_supply(str(offer.offer_id))
					check(game.run.gold==before_gold-int(offer.price),"real supply UI spends carried gold exactly once")
					check(game.expedition_snapshot().temporary_buffs.has("amplify"),"supply purchase grants an actual next-room modifier")
			await capture("expedition_supply")
			app._clear_modals()
			var checkpoint: Dictionary = app.room.expedition_runtime_snapshot()
			check(game.save_expedition_checkpoint(checkpoint),"safe supply checkpoint commits current runtime")
			var receipt_before: Dictionary = game.run.receipt()
			if is_instance_valid(app.room.combat_audio):
				await app.room.combat_audio.wait_for_cleanup()
			app.set_process(false)
			if is_instance_valid(app.music):
				await app.music.wait_for_cleanup()
			app.free()
			await frames(2)
			game.reload_profile()
			check(game.run != null and game.run.id == str(receipt_before.id),"reload retains the active expedition instead of abandoning it")
			app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
			root.add_child(app)
			await frames(1)
			app._continue_game()
			await frames(2)
			check(app.route=="run" and app.expedition.current_index()==next_index and app.expedition.current_node().role=="supply","real Continue recreates the saved supply station")
			check(game.run.gold==int(receipt_before.gold) and game.expedition_snapshot().temporary_buffs.has("amplify"),"resume preserves the purchased modifier and net carried gold")
			check(is_equal_approx(game.run.hp,float(checkpoint.hp)),"resume restores absolute health")
			check(app.room.enemies.get_child_count()==0,"resumed safe checkpoint does not create a paid encounter")
			original_player = app.room.player
		elif current.role == "boss":
			check(str(current.room_id) == expected_boss and next_index == node_count - 1,"route ends in its actual region boss arena")
			check(app.room.enemies.get_child_count()>0 and app.room._living_enemy_count()>0,"a real living boss is present in the final arena")
			await capture("expedition_boss_entry")
	check(branches>=2,"one expedition offers at least two genuine branch decisions")
	check(visited.size()==template_count,"every selected authored combat map is visited exactly once")
	check(not app.expedition.can_extract(),"living final boss cannot be bypassed through extraction")
	if app.expedition.current_index()==node_count - 1 and app.room._living_enemy_count()>0:
		for enemy in app.room.enemies.get_children():
			if enemy.is_alive():
				enemy.take_damage(100000.0,&"test")
		for _retry in range(90):
			if app.room.objective_rewarded:
				break
			await frames(1)
		check(app.expedition.can_extract(),"actual boss death and committed reward open final extraction")
		if is_instance_valid(app.room.combat_audio):
			await app.room.combat_audio.wait_for_cleanup()
		app.show_extraction()
		var confirmed := false
		if not app.modals.is_empty():
			for button in app.modals[-1].node.find_children("*","BaseButton",true,false):
				if button.text==Words.text("CONFIRM_EXTRACT"):
					button.pressed.emit()
					confirmed = true
					break
		check(confirmed,"final extraction is confirmed through the real UI button")
		await frames(2)
		check(game.run==null and str(game.last_result.get("outcome",""))=="extracted","level-sized victory reaches actual result settlement")
		check(game.profile.bosses.has(expected_boss) and Controller.unlocked_biomes(game.profile).has("B02"),"successful first boss extraction unlocks the next biome")
		print("EXPEDITION_VISITED nodes=",node_count," templates=",JSON.stringify(visited)," boss=",expected_boss," outcome=",game.last_result.get("outcome",""))
		await capture("expedition_result")
	if game.run != null:
		if is_instance_valid(app.room.combat_audio):
			await app.room.combat_audio.wait_for_cleanup()
		game.finish_run("abandoned")
	await frames(2)
	finish_suite()

func finish_suite() -> void:
	if is_instance_valid(app):
		app._clear_modals()
		if is_instance_valid(app.room) and is_instance_valid(app.room.combat_audio):
			await app.room.combat_audio.wait_for_cleanup()
		app.set_process(false)
		if is_instance_valid(app.music):
			await app.music.wait_for_cleanup()
		app.free()
	finished = true
	print("EXPEDITION_FLOW_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
