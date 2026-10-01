extends SceneTree
## Production reward ledger, Main callbacks and actor-owned status data.
var checks := 0
var failures := 0
var app: Node
var room: Node2D
var deadline: Timer

func _initialize() -> void:
	call_deferred("run_checks")

func start_deadline() -> void:
	deadline = Timer.new()
	deadline.one_shot = true
	deadline.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(deadline)
	deadline.timeout.connect(func(): push_error("Loot UI fixture timed out"); quit(1))
	deadline.start(40)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("LOOT STATUS UI: "+label)

func frames() -> void:
	for index: int in 3: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	check(root.get_texture().get_image().save_png("res://artifacts/loot_status_"+label+".png") == OK, "capture "+label)

func press(name: String) -> void:
	var button: Button = app.modals[-1].node.find_child(name,true,false)
	check(button != null and not button.disabled, "real enabled action "+name)
	if button != null: button.pressed.emit()
	await frames()

func run_checks() -> void:
	start_deadline()
	var game: Node = root.get_node("Game")
	if not game.profile_path.contains("test_loot_status_ui"): quit(2); return
	AudioServer.set_bus_mute(0,true)
	check(game.new_profile(), "isolated profile")
	root.size = Vector2i(1280,720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	check(game.start_run({"expedition":true,"biome_id":"B01","seed":41827}), "real expedition")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	await press("SkipExpeditionRelic")
	app._advance_expedition("L02")
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	while not app.modals.is_empty() and app.modals[-1].node.find_child("SkipExpeditionRelic",true,false) != null:
		await press("SkipExpeditionRelic")
	var event: String = game.run.id+":node:1:complete"
	var drops := [{"drop_id":event+":gear:0","equipment_id":"EQ02","drop_level":2},{"drop_id":event+":gear:1","equipment_id":"EQ04","drop_level":3}]
	check(game.commit_expedition_completion(event,room.expedition_runtime_snapshot(),{"gold":15,"equipment":drops}), "actual reward transaction")
	room.objective_complete = true
	room.objective_rewarded = true
	app._show_loot_pickup()
	await frames()
	while not app.modals.is_empty() and app.modals[-1].node.find_child("SkipExpeditionRelic",true,false) != null:
		await press("SkipExpeditionRelic")
	check(app.modals[-1].node.find_child("LootPickupModal",true,false) != null and paused,"reward discovery pauses combat")
	check(app.modals[-1].node.find_children("LootCard_*","Panel",true,false).size() == 2,"one card per actual drop")
	var before: Dictionary = game.run.live_receipt().duplicate(true)
	await capture("discovery")
	await press("LootPickupLater")
	check(app.modals.is_empty() and not paused and game.run.gold == before.gold and game.run.expedition.claimed_drop_ids == before.expedition.claimed_drop_ids,"later preserves rewards and resumes")
	# Frozen physics cannot consume the normal release gate; all inputs are up.
	room.release_gate = false
	room.player.position = room.loot_position()
	check(room.nearby_interaction().get("kind") == "loot","real world loot marker is interactable")
	check(room.interaction_hint().contains("F"),"actual control binding in pickup hint")
	room.interact()
	await frames()
	check(not app.modals.is_empty(),"world Interact reopens pickup UI")
	await press("LootPack_EQ02")
	check(game.run.expedition.claimed_drop_ids[drops[0].drop_id].field_decision == "keep","pack commits existing ledger decision")
	check(game.pending_field_equipment().size() == 1 and not game.profile.equipment.has("EQ02"),"one unresolved drop remains and extraction ownership unchanged")
	await press("LootInspect_EQ04")
	check(app.modals[-1].node.find_child("EquipmentTraits",true,false) != null,"comparison exposes grouped actual traits")
	await capture("comparison")
	root.size = Vector2i(960,540)
	await frames()
	await capture("comparison_compact")
	root.size = Vector2i(1280,720)
	await frames()
	await press("FieldEquipNow")
	check(game.run.loadout_snapshot.weapon == "EQ04" and int(game.run.equipment_snapshot.EQ04.level) == 3,"pickup equips real refined gear")
	check(app.modals.is_empty() and game.pending_field_equipment().is_empty(),"resolved pickups close the drawer")
	check(game.run.gold == before.gold,"no repeated reward grant")
	room.player.grant_guard(20,3,"hero_q")
	room.player.grant_guard(45,1,"equipment:EQ04")
	room.player.status.apply("damage_reduction",.35,2)
	room.player.status.apply("burn",20,3)
	room.player.loadout.effects._buff("EQ04","attack_speed_bonus",.1,3)
	app.hud._update_buffs()
	check(app.hud.active_buffs.has("combat_guard") and app.hud.active_buffs.has("gear:EQ04"),"real guard and timed equipment modifiers have chips")
	check(app.hud.buff_info("damage_reduction").description.contains("35%"),"reduction displays real magnitude")
	check(app.hud.buff_info("burn").description.contains("2.4"),"damage over time displays real coefficient")
	check(game.run.shield == 45,"shield is maximum rather than sum")
	app.hud.hovered_control = app.hud.status_panel.find_child("ShieldDetails",true,false)
	app.hud._update_tooltip()
	check(app.hud.tooltip_body.text.contains("45") and app.hud.tooltip_body.text.contains("20"),"shield detail contains independent actual pools")
	await frames()
	await capture("shield_sources")
	room.player.status.tick(1.1)
	game.run.shield = room.player.status.shield()
	app.hud._update_buffs()
	check(game.run.shield == 20 and not app.hud.buff_info("combat_guard").description.contains("45"),"expired strongest shield reveals remaining pool")
	room.player.status.tick(3)
	room.player.loadout.effects.advance(4,{})
	game.run.shield = room.player.status.shield()
	app.hud._update_buffs()
	check(not app.hud.active_buffs.has("combat_guard") and not app.hud.active_buffs.has("gear:EQ04"),"expired real states remove their chips")
	app.free()
	await frames()
	game.finish_run("abandoned")
	deadline.free()
	print("LOOT STATUS UI: ",checks," checks / ",failures," failures")
	quit(1 if failures else 0)
