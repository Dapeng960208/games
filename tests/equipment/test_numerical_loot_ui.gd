extends Node
## Real Main pickup callbacks with canonical V2 reward instances and isolated saves.
const Fixtures = preload("res://tests/persistence/test_numerical_instance_storage.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Loot = preload("res://scripts/domain/expedition/expedition_rewards.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
var checks := 0
var failures: Array[String] = []
var app: Node
var room: RoomController

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAILED: ",label)

func frames() -> void:
	for index in 3: await get_tree().process_frame

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(90).timeout.connect(func(): print("Numerical loot UI timed out"); get_tree().quit(1))

func press(button: Button) -> void:
	check(button != null and not button.disabled,"enabled actual pickup action")
	if button != null and not button.disabled: button.pressed.emit()
	await frames()

func skip_relics() -> void:
	while not app.modals.is_empty():
		var button: Button = app.modals[-1].node.find_child("ConfirmZeroBenefitSkip",true,false)
		if button == null: button = app.modals[-1].node.find_child("SkipExpeditionRelic",true,false)
		if button == null: break
		await press(button)

func action(prefix: String, drop_id: String) -> Button:
	if app.modals.is_empty(): return null
	for button: Button in app.modals[-1].node.find_children(prefix+"*","Button",true,false):
		if str(button.get_meta("drop_id","")) == drop_id: return button
	return null

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(Game.profile_path).get_base_dir().path_join("loot-ui-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png")) == OK,"capture "+label)

func _run() -> void:
	if not Game.profile_path.contains("test_numerical_loot_ui"): get_tree().quit(2); return
	Game.run = null
	check(Game.new_profile(),"isolated new profile")
	var profile := Fixtures.fixture_profile()
	profile.hero_xp.CH01 = 3600
	check(Game._commit_profile(profile),"V2 permanent inventory fixture")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	await frames()
	check(Game.start_run({"expedition":true,"biome_id":"B01","seed":1735}),"actual V2 expedition")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	await skip_relics()
	app._advance_expedition(str(app.expedition.next_options()[0]))
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	await skip_relics()
	check(Game.run.expedition.phase == "combat","entered real combat room")
	if Game.run.expedition.phase != "combat": await finish(); return
	var revision: int = Game._store._current.revision
	var expected: Dictionary = Game.run.expedition.duplicate(true)
	var started := Time.get_ticks_usec()
	for index in 12:
		var spawn := "burst:"+str(index)
		var event := Game.run.id+":node:"+str(Game.run.expedition.node_index)+":kill:"+spawn
		check(Loot.add(expected,Game.run.id,Game.run.hero_id,event,"normal",0,"M01"),"reference seeded burst reward")
		check(Game.queue_expedition_kill_reward(spawn,"M01"),"queue real same-frame kill")
	check(Game._store._current.revision == revision and Game.run.staged_loot_requests.size() == 12,"burst performs no save inside damage callbacks")
	await frames()
	check(Game._store._current.revision == revision+1 and Game.run.staged_loot_requests.is_empty(),"12 kills commit together in exactly one atomic save")
	check(Game.run.expedition.loot_events == expected.loot_events and Game.run.expedition.pending_equipment == expected.pending_equipment and Game.run.expedition.pity_snapshot == expected.pity_snapshot,"batch preserves serial seeded rewards, instances and pity order")
	print("KILL_BATCH 12 deaths / 1 save; fixture elapsed usec=",Time.get_ticks_usec()-started)
	Game._store.max_document_bytes = 1
	check(Game.queue_expedition_kill_reward("retry-burst","M01"),"failed-save burst queues once")
	await frames()
	check(Game.run.staged_loot_requests.size() == 1 and Game._store._current.revision == revision+1,"storage failure retains uncommitted event without granting it")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.flush_expedition_kill_rewards() and Game.run.staged_loot_requests.is_empty(),"retry commits frozen staged event")
	# Deterministically find a real normal-kill stream yielding an extra item.
	var spawned := ""
	for serial in 10000:
		var id := "pickup-actor:"+str(serial)
		var event := Game.run.id+":node:"+str(Game.run.expedition.node_index)+":kill:"+id
		if Acquisition.roll_event(Loot.context(Game.run.expedition,Game.run.id,Game.run.hero_id,event,"normal",0)).get("triggered",false):
			spawned = id
			break
	check(not spawned.is_empty() and Game.record_expedition_kill_reward(spawned,"M01"),"canonical kill receipt grants a real instance")
	Game.run.hp = maxi(1,int(Game.run.max_hp)-100)
	room.player.cooldowns.q = 3.25
	var completion := Game.run.id+":node:"+str(Game.run.expedition.node_index)+":complete"
	check(Game.commit_expedition_completion(completion,room.expedition_runtime_snapshot()),"canonical room receipt commits")
	room.objective_complete = true
	room.objective_rewarded = true
	var offers := Game.pending_field_equipment()
	check(offers.size() >= 2,"real journal contains at least two selectable drops")
	if offers.size() < 2: await finish(); return
	var pending: Dictionary = Game.run.expedition.pending_equipment.duplicate(true)
	var owned: Dictionary = Game.profile.equipment.duplicate(true)
	app._on_expedition_room_completed()
	await frames()
	check(app.modals.is_empty() and not get_tree().paused,"clearing a room never forces a loot popup or pause")
	app._show_loot_pickup()
	await frames()
	await skip_relics()
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
			get_window().size = extent
			app._clear_modals()
			app._show_loot_pickup()
			await frames()
			check(not app.modals.is_empty() and app.modals[-1].node.find_child("LootPickupModal",true,false) != null and get_tree().paused,"discovery modal pauses combat")
			var cards: Array[Node] = app.modals[-1].node.find_children("LootCard_*","Panel",true,false)
			check(cards.size() == offers.size(),"one complete card per committed instance")
			for card: Panel in cards:
				var identifier := str(card.get_meta("equipment_id"))
				var record: Dictionary = pending[identifier]
				var definition := Game.equipment_definition(identifier,true)
				check(card.find_child("LootItemName",true,false).text == GameStyle.content_text(definition,"name"),"real template name for instance")
				var art: Control = card.find_child("LootItemArt",true,false)
				check(not art.is_empty and art.generated_texture != null and art.equipment_data.id == record.template_id,"real template artwork for pending instance")
				var stats: Dictionary = Instances.stats(record)
				var key: String = Instances.main_keys(str(record.template_id),str(record.power_type))[0]
				check(card.find_child("LootItemStats",true,false).tooltip_text.contains(Inspect.value(key,float(stats[key]),true,true,2)),"summary contains the actual rolled stat")
				check(action("LootInspect_",identifier) != null and not action("LootInspect_",identifier).disabled and action("LootPack_",identifier) != null,"both instance actions rendered")
			await capture("discovery-"+locale+"-"+str(extent.x))
	await press(app.modals[-1].node.find_child("LootPickupLater",true,false))
	check(app.modals.is_empty() and not get_tree().paused and Game.run.expedition.pending_equipment == pending,"later returns to field without losing or rerolling loot")
	room.release_gate = false
	room.player.position = room.loot_position()
	check(room.nearby_interaction().get("kind") == "loot","actual loot marker remains interactable")
	room.interact()
	await frames()
	check(not app.modals.is_empty(),"Interact reopens the real pickup modal")
	var pack_id := str(offers[0].drop_id)
	await press(action("LootPack_",pack_id))
	check(Game.run.expedition.claimed_drop_ids[pack_id].field_decision == "keep" and Game.pending_field_equipment().size() == offers.size()-1,"Pack records this unique drop decision exactly once")
	var equip_id := str(offers[1].drop_id)
	await press(action("LootInspect_",equip_id))
	check(not app.modals.is_empty() and app.modals[-1].node.find_child("FieldEquipmentModal",true,false) != null,"Compare opens the real fitting modal")
	var comparison: Control = app.modals[-1].node.find_child("FieldEquipmentComparison",true,false)
	var candidate: Control = comparison.find_child("FieldNextEquipment",true,false)
	var record: Dictionary = pending[equip_id]
	check(candidate.find_child("InstanceId",true,false).text.contains(equip_id),"comparison preserves the drop identity")
	var key: String = Instances.main_keys(str(record.template_id),str(record.power_type))[0]
	check(candidate.find_child("ItemStat_"+key,true,false).get_child(3).text == Inspect.value(key,float(Instances.stats(record)[key]),false,true,2),"comparison shows actual integer instance attributes")
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		comparison.get_parent().remove_child(comparison)
		comparison.queue_free()
		app._clear_modals()
		app._show_field_equipment({"drop_id":equip_id})
		comparison = app.modals[-1].node.find_child("FieldEquipmentComparison",true,false)
		await frames()
		await capture("comparison-"+locale)
	var health: float = Game.run.hp
	var resource: float = Game.run.resource
	await press(comparison.find_child("FieldEquipNow",true,false))
	var slot: String = ContentRegistry.equipment(str(record.template_id),2).slot
	check(Game.run.loadout_snapshot[slot] == equip_id and Game.run.equipment_snapshot[equip_id].main_rolls == record.main_rolls,"Collect & equip applies the exact dropped instance")
	check(Game.run.hp <= health and Game.run.resource <= resource and room.player.cooldowns.q == 3.25,"fitting does not heal or reset resource/cooldown")
	check(Game.profile.equipment == owned,"packing and fitting do not bank unsecured loot")
	var unresolved := Game.pending_field_equipment()
	for offer: Dictionary in unresolved: await press(action("LootPack_",str(offer.drop_id)))
	check(Game.pending_field_equipment().is_empty() and app.modals.is_empty(),"all resolved drops close pickup flow")
	Game.reload_profile()
	check(Game.run != null and Game.run.loadout_snapshot[slot] == equip_id and Game.run.expedition.claimed_drop_ids[pack_id].field_decision == "keep" and Game.run.expedition.claimed_drop_ids[equip_id].field_decision == "equip","checkpoint reload preserves both choices")
	await legacy_ui()
	await finish()

func legacy_ui() -> void:
	check(not Game.finish_run("abandoned").is_empty(),"V2 isolated run settles")
	await frames()
	app.show_camp()
	Game._test_ruleset_override = 1
	check(Game.new_profile() and Game.profile.get("ruleset_version",1) == 1,"explicit frozen legacy fixture")
	check(Game.start_run({"expedition":true,"biome_id":"B01","seed":41827}),"legacy expedition starts")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	await skip_relics()
	app._advance_expedition("L02")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	await skip_relics()
	var event := Game.run.id+":node:1:complete"
	check(Game.commit_expedition_completion(event,room.expedition_runtime_snapshot(),{"gold":15,"equipment":[{"drop_id":event+":gear:0","equipment_id":"EQ04","drop_level":3}]}),"historical template reward fixture")
	room.objective_complete = true
	room.objective_rewarded = true
	app._show_loot_pickup()
	await frames()
	await skip_relics()
	var card: Control = app.modals[-1].node.find_child("LootCard_EQ04",true,false)
	check(card != null and not card.find_child("LootItemName",true,false).text.is_empty(),"legacy template still builds a full card")
	await press(app.modals[-1].node.find_child("LootInspect_EQ04",true,false))
	check(app.modals[-1].node.find_child("EquipmentTraits",true,false) != null,"legacy comparison keeps frozen traits")
	await press(app.modals[-1].node.find_child("FieldEquipNow",true,false))
	check(Game.run.loadout_snapshot.weapon == "EQ04" and Game.run.equipment_snapshot.EQ04.level == 3,"legacy fitting still commits template and refinement")
	Game._test_ruleset_override = 0

func finish() -> void:
	app.queue_free()
	get_tree().paused = false
	await frames()
	if Game.run != null: Game.finish_run("abandoned")
	await get_tree().create_timer(0.3).timeout
	print("Numerical loot UI: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
