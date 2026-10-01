extends Node
## A17/A30: real current-objective reachability and versioned reward contracts.
const Rewards = preload("res://scripts/world/room_rewards.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const FirstFour = preload("res://scripts/world/first_four_objectives.gd")
const RoomScene = preload("res://scenes/room.tscn")
const Routes = preload("res://scripts/world/route_generator.gd")
const Coordinator = preload("res://scripts/world/expedition_controller.gd")
const Chart = preload("res://scripts/ui/expedition_panel.gd")

class PreviewGame extends Node:
	var run := RunState.new()
	var state: Dictionary = {}
	func expedition_snapshot() -> Dictionary:
		return state.duplicate(true)

var checks := 0
var failures := 0
var room: MineRoom

func _ready() -> void:
	call_deferred("run_checks")
	get_tree().create_timer(60.0).timeout.connect(func(): push_error("Audit rewards timed out"); get_tree().quit(1))

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AUDIT REWARDS: " + description)

func run_checks() -> void:
	if not Game.profile_path.contains("test_audit_rewards"):
		push_error("Audit rewards requires isolated profile")
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	check(Game.new_profile() and Game.start_run(), "isolated real player starts")
	_legacy_contract()
	_current_policy()
	_historical_discoveries()
	_reachable_objectives()
	await _preview_layout()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "room audio drains")
		room.free()
	Game.finish_run("abandoned")
	await get_tree().process_frame
	print("AUDIT REWARDS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _legacy_contract() -> void:
	for hero: String in Registry.heroes():
		for row: Array in [["L02","full",18,1], ["L02","reduced",34,0], ["L03","full",30,0], ["L03","mobile",12,1], ["L06","full",24,2], ["L06","reduced",8,0]]:
			var historical := Rewards.build(row[0], row[1], hero, 17, "legacy")
			check(historical.gold == row[2] and historical.equipment.size() == row[3], "legacy authored gold/theme/count bargain preserved " + str(row))
			for difficulty in range(-1, 5):
				check(Rewards.build(row[0], row[1], hero, 17, "legacy", [], [], [], difficulty) == Rewards.build(row[0], row[1], hero, 17, "legacy", [], [], [], difficulty, 0), "missing policy keeps historical exact draw")
		# Already-saved race policies keep both their published reward and RNG.
		var race := Rewards.build("L02", "reduced", hero, 17, "legacy", [], [], [], 0, 0)
		check(race.gold == 34 and race.equipment.size() == 1, "historical faction policy is not silently migrated")
	check(Rewards.build("L02", "full", "CH01", 17, "test", [], [], [], 0, 0).equipment[0].equipment_id == "EQ41", "historical race draw matches pre-fix real-engine snapshot")
	check(Rewards.qualities("L02") == ["full","reduced"] and Rewards.qualities("L03") == ["full","mobile"], "old objective interface still exposes its actual legacy branches")

func _current_policy() -> void:
	var conditions := {"B01":"Charge all conduits", "B02":"Destroy all brood nests", "B03":"Seal all graves", "B04":"Break all barricades"}
	for id: String in Catalog.room_ids() + Catalog.bosses().keys():
		var boss := Catalog.bosses().has(id)
		check(Rewards.qualities(id, 1) == ["full"], id + " current policy has only a reachable full outcome")
		for hero: String in Registry.heroes():
			for difficulty in range(5):
				var reward := Rewards.build(id, "full", hero, 960208, "current", [], [], [], difficulty, 1)
				var old := Rewards.build(id, "full", hero, 960208, "current", [], [], [], difficulty, 0)
				check(reward == old, id + " full rewards retain amount, progression, level and deterministic roll")
				var count := 2 + int(difficulty / 2) if boss else (2 if difficulty >= 2 else 1)
				check(reward.equipment.size() == count, id + " number of drops preserves difficulty scaling")
				var pool := Rewards.race_equipment_pool(Rewards.biome_for_reward(id), hero)
				var seen: Array = []
				for drop: Dictionary in reward.equipment:
					check(pool.has(drop.equipment_id) and not seen.has(drop.equipment_id), id + " distinct suitable same-faction drops")
					seen.append(drop.equipment_id)
				for english: bool in [false, true]:
					var preview := Rewards.preview(id, hero, english, difficulty, 1)
					check(preview.contains(str(reward.gold) + (" gold" if english else "金币")) and preview.contains(str(count) + (" faction gear" if english else "件本族装备")), id + " preview exactly matches paid gold and count")
					check(preview.contains("clear enemies" if english else "清场") and preview.contains("Extract" if english else "撤离"), id + " preview states encounter and extraction gates")
					if english and not boss: check(preview.contains(conditions[Rewards.biome_for_reward(id)]), id + " preview names the actual FirstFour task")
					for drop: Dictionary in reward.equipment:
						var lower := mini(3, maxi(0, difficulty - 1) + (1 if boss and difficulty >= 1 else 0))
						var upper := mini(3, lower + (1 if difficulty == 1 else 0))
						check(drop.drop_level >= lower and drop.drop_level <= upper and preview.contains("+%d%s%d" % [lower, "–" if english else "～", upper]), id + " enhancement preview and actual bounds agree")
		for unreachable: String in ["reduced","mobile","repaired"]:
			check(Rewards.build(id, unreachable, "CH01", 17, "current", [], [], [], 0, 1).is_empty(), id + " cannot mint a retired objective reward")
	for id: String in ["L01", "L11"]:
		for difficulty in range(5):
			var optional_id := "side_crate" if id == "L01" else "research_2"
			var reward := Rewards.optional(id, optional_id, "CH01", 17, "optional", [], [], [], difficulty, 1)
			check(reward == Rewards.optional(id, optional_id, "CH01", 17, "optional", [], [], [], difficulty, 0), "optional version-2 receipts retain exact values")
			var preview := Rewards.preview(id, "CH01", true, difficulty, 1)
			check(preview.contains(str(reward.gold) + " gold") and preview.contains("After clear:") and reward.xp == 0 and reward.mastery == 0, "optional cache preview discloses actual additional reward")
	check(not Rewards.preview("L02", "CH01", true, 0, 1).contains("cargo") and not Rewards.preview("L11", "CH01", true, 0, 1).contains("third package"), "retired objective text removed from new previews")
	check(Rewards.build("L01", "full", "CH01", 1, "event", [], [], [], -1, 1).is_empty(), "current policy needs real expedition difficulty")
	check(Rewards.build("L01", "full", "CH01", 1, "event", [], [], [], 0, 2).is_empty() and Rewards.preview("L01", "CH01", true, 0, 2).is_empty() and Rewards.qualities("L01", 2).is_empty(), "unknown future policy fails closed")

func _historical_discoveries() -> void:
	var pool := Rewards.race_equipment_pool("B01", "CH01")
	var sold: String = str(pool[-1])
	var owned_after_sale: Array = pool.slice(0, pool.size() - 1)
	var historical: Array = pool.duplicate()
	var repeats: Dictionary = {}
	var sold_draws := 0
	for seed_value in range(64):
		var old := Rewards.build("L01", "full", "CH01", seed_value, "sale", owned_after_sale, [], [], 0, 0)
		check(old.equipment[0].equipment_id == sold, "historical ownership-only policy reproducibly refreshed sale guarantee")
		var reward := Rewards.build("L01", "full", "CH01", seed_value, "sale", historical, [], [], 0, 1)
		var id: String = reward.equipment[0].equipment_id
		repeats[id] = true
		if id == sold: sold_draws += 1
		check(reward == Rewards.build("L01", "full", "CH01", seed_value, "sale", historical, [], [], 0, 1), "history policy retries freeze the same draw")
		var unseen := Rewards.build("L01", "full", "CH01", seed_value, "discovery", owned_after_sale, [], [], 0, 1)
		check(unseen.equipment[0].equipment_id == sold, "truly undiscovered gear keeps first-discovery protection")
	check(repeats.size() > 1 and sold_draws < 64, "sold but historically discovered gear has no forced reacquisition guarantee")
	check(historical == pool and owned_after_sale == pool.slice(0, pool.size() - 1), "policy never modifies discovery or ownership inputs")
	var pending: Array = [sold]
	var reward := Rewards.build("L01", "full", "CH01", 17, "pending", pool.slice(0, pool.size() - 2), pending, [], 0, 1)
	check(reward.equipment[0].equipment_id == pool[-2] and pending == [sold], "pending discovery excludes a duplicate without mutating the receipt")

func _reachable_objectives() -> void:
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	for id: String in Catalog.room_ids():
		var biome: String = Catalog.room(id).biome_id
		var prepared := room.prepare_expedition_node({"room_id":id,"role":"branch","biome_id":biome,"node_index":1,"node_count":6,"difficulty":0,"seed":146556,"phase":"combat","expedition":true})
		check(bool(prepared.get("valid", false)), id + " real expedition layout prepares")
		if not bool(prepared.get("valid", false)): continue
		room.apply_prepared_expedition_node(prepared)
		room.spawn_enabled = false
		room.set_input_blocked(false)
		room.release_gate = false
		for actor: Node in room.enemies.get_children():
			if str(actor.get("actor_kind")) != "objective": actor.free()
		var host: Node2D = room.objectives
		check(host.module.get_script() == FirstFour and host.status().rules == "first_four_combat_v1", id + " production dispatcher chooses current mechanics")
		for item: Dictionary in host.elements.values():
			if not bool(item.get("required", true)): continue
			room.player.position = item.position
			if biome in ["B01", "B03"]:
				check(host.interact(str(item.id), room.player), id + " actual objective interaction starts")
				host.tick(1.61)
			else:
				room.player.original_hit(item.target_actor, 1000000.0, &"primary")
		host.tick(0.01)
		check(host.finished and host.completed_count == host.required_count and host.quality == "full", id + " actual reachable completed quality is full")
		check(not Rewards.build(id, str(host.quality), "CH01", 146556, "actual", [], [], [], 0, 1).is_empty(), id + " reachable quality has a current reward")
		for item: Dictionary in host.elements.values():
			check(not str(item.id) in ["cargo_cart","gear_stop","furnace_cut"], id + " retired alternate-quality controls are absent")

func _preview_layout() -> void:
	var original_locale := Words.locale
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var host := Control.new()
	host.size = Vector2(1280, 720)
	host.theme = MineStyle.make_theme()
	viewport.add_child(host)
	var game := PreviewGame.new()
	game.run.hero_id = "CH03"
	add_child(game)
	var controller := Coordinator.new(game)
	for locale: String in ["zh_CN", "en"]:
		Words.locale = locale
		for biome: String in Catalog.biomes():
			var route := Routes.generate_single_biome(biome, 41827, [], 1)
			for current: int in [0, 1, 3, 4]:
				game.state = {"route":route,"node_index":current,"phase":"cleared","completed_nodes":range(current + 1),"difficulty":4,"reward_policy_version":1}
				var chart := Chart.new()
				chart.position = Vector2(132, 148)
				chart.size = Vector2(1016, 480)
				host.add_child(chart)
				chart.configure(controller, true)
				await get_tree().process_frame
				await get_tree().process_frame
				var cards := chart.find_children("Choose_*", "Button", true, false)
				check(cards.size() == controller.next_options().size(), "route keeps each actual choice with expanded rewards")
				for card: Button in cards:
					var reward: Label = card.find_child("RouteReward", true, false)
					var room_id := String(card.name).trim_prefix("Choose_")
					check(reward.text == Rewards.preview(room_id, "CH03", locale == "en", 4, 1), room_id + " coordinator and visible route use the saved current policy")
					var previous_bottom := 0.0
					for label: Label in card.get_children():
						var height := label.get_line_count() * label.get_line_height() + maxi(0, label.get_line_count() - 1) * label.get_theme_constant("line_spacing")
						check(label.size.y + 1.0 >= height and not label.clip_text and label.max_lines_visible == -1, room_id + " shaped label fits without cropping")
						check(label.position.y >= previous_bottom and Rect2(Vector2.ZERO, card.size).encloses(label.get_rect()), room_id + " labels stay ordered inside actual card")
						previous_bottom = label.get_rect().end.y
				var scroll: ScrollContainer = chart.find_child("RouteOptions", true, false)
				if not cards.is_empty():
					var last_reward: Label = cards[-1].find_child("RouteReward", true, false)
					scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
					await get_tree().process_frame
					check(scroll.get_global_rect().encloses(last_reward.get_global_rect()), "full last reward block remains reachable by scrolling")
				chart.free()
	game.free()
	viewport.free()
	Words.locale = original_locale
