extends Node
## One real-actor swap through combat, clear checkpoint and reload. No balance
## simulation; the regression protects owned-only inventory and survival values.
const Gear = preload("res://scripts/core/backpack_equipment.gd")
const Backpack = preload("res://scripts/ui/backpack_panel.gd")
const Dossier = preload("res://scripts/ui/character_panel.gd")
const ExpeditionController = preload("res://scripts/world/expedition_controller.gd")
var checks := 0
var failures := 0
var room: Node2D

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(40.0).timeout.connect(func(): push_error("Backpack fixture timed out"); get_tree().quit(1))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("BACKPACK: "+label)

func _run() -> void:
	if not Game.profile_path.contains("test_backpack"): get_tree().quit(2); return
	check(Game.new_profile(), "isolated starter collection")
	check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":960109}), "real expedition")
	if Game.run == null: get_tree().quit(1); return
	var expedition: RefCounted = ExpeditionController.new(Game)
	room = load("res://scenes/room.tscn").instantiate()
	var prepared: Dictionary = room.prepare_expedition_node(expedition.current_context())
	check(bool(prepared.get("valid",false)), "entrance ready")
	if not bool(prepared.get("valid",false)): get_tree().quit(1); return
	room.apply_prepared_expedition_node(prepared)
	add_child(room)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.set_input_blocked(true)
	var runtime: Dictionary = room.expedition_runtime_snapshot()
	for offer: Dictionary in Game.expedition_snapshot().relic_offers:
		check(Game.choose_run_relic(offer.offer_id,"skip","",runtime), "skip initial relic offer")
	var state: Dictionary = Game.expedition_snapshot()
	check(Game.choose_expedition_node(int(state.next_node.node_index),str(state.next_node.room_id)), "select combat node")
	check(Game.advance_expedition_node(runtime,str(state.checkpoint_id)), "enter combat checkpoint")
	prepared = room.prepare_expedition_node(expedition.current_context())
	check(bool(prepared.get("valid",false)), "combat room ready")
	if not bool(prepared.get("valid",false)): get_tree().quit(1); return
	room.apply_prepared_expedition_node(prepared)
	room.set_input_blocked(true)
	Game.run.hp = 65.0
	Game.run.resource = 9.0
	room.player.position = room.layout.entry+Vector2(160,0)
	room.player.aim_direction = Vector2(0,1)
	room.player.cooldowns.q = 2.7
	room.player.status.guards["room_prop:backpack"] = {"amount":25.0,"remaining":7.0}
	Game.run.shield = 10.0 # Fifteen points were already consumed by live damage.
	var before_position: Vector2 = room.player.position
	var before_aim: Vector2 = room.player.aim_direction
	var original: Dictionary = Game.run.receipt().duplicate(true)
	var enemy: Node2D = room.spawn_enemy(room.layout.entry+Vector2(500,0),"M01")
	var enemy_count: int = room.enemies.get_child_count()
	var enemy_health: float = enemy.health.current
	for index: int in 2:
		room.player.passives.record_hit(enemy,&"primary",{"root_event_id":"backpack:passive:"+str(index),"original_basic":true,"equipment_eligible":true,"proc_depth":0,"hp_damage":1.0})
	check(int(room.player.passives.snapshot().current) == 2,"actual hero passive has two confirmed basic-hit stacks before swap")
	var loot := Game.run.id+":backpack:EQ08"
	check(Game.collect_expedition_equipment(loot,"EQ08",2), "collect actual unextracted refined weapon")
	var available: Array[Dictionary] = Gear.available(Game)
	check(available.size() == 7 and Gear.preview(Game,"EQ60","charm").is_empty(), "bag includes starter gear and loot, never unowned catalog")
	var attack_before: float = Game.run.stats.attack
	var changed: Dictionary = Gear.apply(room,"EQ08","weapon",str(Game.run.expedition.checkpoint_id))
	check(bool(changed.get("success",false)) and not bool(changed.get("persisted",true)), "combat swap applies immediately without writing partial room")
	check(Game.run.loadout_snapshot.weapon == "EQ08" and int(Game.run.equipment_snapshot.EQ08.level) == 2 and not is_equal_approx(Game.run.stats.attack,attack_before), "gear and refinement affect actual resolved stats")
	check(is_equal_approx(Game.run.hp,65.0) and is_equal_approx(Game.run.resource,9.0) and is_equal_approx(room.player.cooldowns.q,2.7), "absolute health, resources and cooldown preserved")
	check(is_equal_approx(Game.run.shield,10.0), "partly spent beacon shield cannot refill on equipment change")
	check(bool(changed.get("passive_restored",false)) and int(room.player.passives.snapshot().current) == 2 and room.player.passives._seen.has("backpack:passive:0"),"same-room swap retains actual passive stacks and consumed hit identities")
	check(room.player.position == before_position and room.player.aim_direction == before_aim and enemy.health.current == enemy_health and room.enemies.get_child_count() == enemy_count, "actor stays in place and live enemies stay unchanged")
	check(Game.run.receipt() == original, "incidental saves retain authoritative entry receipt")
	var completion := Game.run.id+":backpack:complete"
	check(Game.commit_expedition_completion(completion,room.expedition_runtime_snapshot(),{"gold":0,"xp":0,"mastery":0,"equipment":[]}), "normal clear persists live equipment")
	Game.reload_profile()
	check(Game.run != null and Game.run.loadout_snapshot.weapon == "EQ08" and int(Game.run.equipment_snapshot.EQ08.level) == 2 and not Game.profile.equipment.has("EQ08"), "reload retains temporary gear while loot remains unsecured")
	if Game.run == null: room.free(); get_tree().quit(1); return
	room.restore_expedition_runtime(Game.run.expedition.runtime)
	var removed: Dictionary = Gear.apply(room,"","weapon",str(Game.run.expedition.checkpoint_id))
	check(bool(removed.get("success",false)) and bool(removed.get("persisted",false)), "safe-room unequip persists")
	check(str(Game.run.loadout_snapshot.weapon).is_empty() and is_equal_approx(Game.run.hp,65.0), "unequip contributes no item and cannot create health")
	Game.reload_profile()
	check(Game.run != null and str(Game.run.loadout_snapshot.weapon).is_empty(), "empty slot survives validated receipt reload")
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel: Control = Backpack.new()
	panel.theme = MineStyle.make_theme()
	panel.position = Vector2(110,50)
	ui.add_child(panel)
	panel.configure(room,func(): pass)
	panel.selected_id = "EQ08"; panel.selected_slot = "weapon"; panel._render()
	check(panel.find_children("BackpackSlot_*","Button",true,false).size() == 8 and panel.find_child("BackpackItem_EQ60",true,false) == null, "eight displayed slots and owned-only clickable list")
	await _capture("inventory_1280",Vector2i(1280,720),panel)
	await _capture("inventory_1920",Vector2i(1920,1080),panel)
	panel.find_child("BackpackDetailTab_compare",true,false).pressed.emit()
	check(panel.find_child("CompareStat_attack",true,false) != null,"field backpack exposes full replacement number comparison")
	panel.find_child("BackpackSearch",true,false).text = "no matching equipment"
	panel.find_child("BackpackSearch",true,false).text_changed.emit("no matching equipment")
	check(panel.find_children("BackpackItem_*","Button",true,false).is_empty(),"field search never invents unowned catalog entries")
	panel.find_child("BackpackAllItems",true,false).pressed.emit()
	check(panel.find_children("BackpackItem_*","Button",true,false).size() == 7,"clear field search restores the six starter items and real run loot")
	panel.tab = "stats"; panel._render()
	check(panel.find_children("BackpackAttribute_*","Label",true,false).size() == Backpack.ATTRIBUTES.size(), "complete scrollable attribute sheet")
	await _capture("attributes_1280",Vector2i(1280,720),panel)
	panel.hide()
	var dossier: Control = Dossier.new()
	dossier.theme = MineStyle.make_theme()
	dossier.position = Vector2(130,50)
	ui.add_child(dossier)
	dossier.configure(room,func(): pass)
	check(dossier.find_children("Attribute_*","Label",true,false).size() == 25,"combat dossier shares every resolved attribute")
	dossier.find_child("Equipment_chest",true,false).pressed.emit()
	check(dossier.find_child("ItemStat_max_hp",true,false) != null,"combat dossier equipment shows complete actual numbers instead of a clipped summary")
	await _capture("dossier_item_1280",Vector2i(1280,720),dossier)
	dossier.find_child("DossierAllStats",true,false).pressed.emit()
	check(dossier.find_children("Attribute_*","Label",true,false).size() == 25,"combat dossier can return from item detail to all attributes")
	ui.free(); room.free()
	print("BACKPACK: %d checks / %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func _capture(label: String, window_size: Vector2i, panel: Control) -> void:
	get_window().size = window_size
	for _index in 3: await get_tree().process_frame
	check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "panel fits "+label)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	check(frame.save_png("res://artifacts/backpack_"+label+".png") == OK,"capture "+label)
