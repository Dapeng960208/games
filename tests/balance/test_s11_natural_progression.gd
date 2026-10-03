extends Node
## Automated natural-route sampling: only production input/transactions, no
## injected progress. Simulation time is distinct from wall and human play.
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Controller = preload("res://tests/support/s11_battle_controller.gd")
const Expedition = preload("res://scripts/app/expedition_controller.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Backpack = preload("res://scripts/gameplay/equipment/backpack_equipment.gd")
const Abilities = preload("res://scripts/gameplay/characters/hero_abilities.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Forging = preload("res://scripts/domain/equipment/instance_forging.gd")
const Fixtures = preload("res://tests/support/s11_battle_fixtures.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const ObservedRoom = preload("res://tests/support/s11_observed_room.gd")
const DamageTrail = preload("res://tests/support/s11_damage_trail.gd")
const POLICY := "natural-route-v2"
var trail
var room_initial_hp := 0.0
var room_initial_stats := {}
var room_resource_empty := 0.0
var room_recorded := false
var excluded_actor_ids := {}
var stage: SubViewport
var room: RoomController
var controller
var expedition
var hero := "CH01"
var limit := 1800.0
var elapsed := 0.0
var room_started := 0.0
var next_decision := 0.0
var next_observation := 30.0
var run_count := 0
var transitioning := false
var finished := false
var output := "/tmp/s11-natural.jsonl"
var started_wall := 0
var last_level := 1
var clears := 0
var wins := 0
var deaths := 0
var maximum_difficulty := 0
var next_departure := 0.0
func _ready() -> void: call_deferred("begin")
func record(kind: String, extra: Dictionary = {}) -> void:
	var value := {"kind":kind,"hero":hero,"simulation_seconds":elapsed,"wall_seconds":float(Time.get_ticks_msec()-started_wall)/1000.0,"runs":run_count,"clears":clears,"wins":wins,"deaths":deaths,"level":Game.hero_level(hero),"gold":Game.profile.permanent_gold,"materials":Game.profile.get("materials",{}).duplicate(true)}
	value.merge(extra,true)
	var file := FileAccess.open(AssetCatalog.resolve(output),FileAccess.READ_WRITE if FileAccess.file_exists(AssetCatalog.resolve(output)) else FileAccess.WRITE)
	file.seek_end(); file.store_line(JSON.stringify(value)); file.close()
	print("NATURAL ",kind," t=",snappedf(elapsed,.1)," level=",Game.hero_level(hero)," room=",room.layout_id if is_instance_valid(room) else "camp")
func begin() -> void:
	if not Game.profile_path.contains("test_s11_natural_progression"): get_tree().quit(2); return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hero="): hero = arg.get_slice("=",1)
		if arg.begins_with("--sim-seconds="): limit = float(arg.get_slice("=",1))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if hero not in ProfileStore.HERO_IDS: get_tree().quit(2); return
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.handle_input_locally = true
	add_child(stage)
	process_physics_priority = 100
	started_wall = Time.get_ticks_msec()
	Numbers.parameters(); Numbers._parameters.runtime_enabled = true
	Game._test_ruleset_override = 0
	if not Game.new_profile() or not Game.select_hero(hero): get_tree().quit(2); return
	trail = DamageTrail.new(); Game.damage_trail = trail
	record("start",{"controller":Controller.VERSION,"policy":POLICY,"sample":"automated natural route, not human play","seed_rule":"20001+run ordinal, no loot inspection","time_scale":Engine.time_scale})
	depart()
func depart() -> void:
	run_count += 1
	var biomes := Expedition.unlocked_biomes(Game.profile)
	var biome := "B01"
	for id: String in biomes:
		if Game.hero_level(hero) >= (int(id.trim_prefix("B"))-1)*5+1: biome = id
	if Game.hero_level(hero) == Growth.level_cap():
		var missing := {}
		for template: String in preferred_templates():
			var found := false
			for item: Dictionary in Game.profile.equipment.values():
				if item.template_id == template and item.rarity == "gold" and int(item.item_level) >= Game.hero_level(hero) and Instances.can_equip(item,hero,Game.hero_level(hero)): found = true; break
			if not found:
				var race: String = Economy._historical_race(template)
				missing[race] = int(missing.get(race,0))+1
		var needed := 0
		for race: String in missing:
			if race in biomes and int(missing[race]) > needed: biome = race; needed = missing[race]
	# Difficulty is a global progression tier carried into newly unlocked
	# chapters; raise it after Boss extraction and lower it after defeat.
	if not Game.start_run({"expedition":true,"seed":20000+run_count,"biome_id":biome,"difficulty":maximum_difficulty,"wish_slot":wish_slot()}): stop("departure_rejected"); return
	expedition = Expedition.new(Game)
	room = RoomScene.instantiate()
	room.set_script(ObservedRoom)
	if DisplayServer.get_name() == "headless": room.get_node("MineBackdrop").set_script(load(AssetCatalog.resolve("res://tests/support/s11_headless_backdrop.gd")))
	var prepared: Dictionary = room.prepare_expedition_node(expedition.current_context())
	if not prepared.get("valid",false): stop("layout_rejected"); return
	room.apply_prepared_expedition_node(prepared)
	room.interaction_requested.connect(interaction)
	room.room_completed.connect(completed_room)
	stage.add_child(room)
	controller = Controller.new(); controller.configure(room)
	arm_room_observation()
	room_started = elapsed
	transitioning = false
	record("departure",{"biome":biome,"difficulty":maximum_difficulty,"seed":20000+run_count,"run_id":Game.run.id,"loot_seed":Game.run.expedition.get("loot_seed",0),"stats":Game.run.stats})
func _physics_process(delta: float) -> void:
	if finished or started_wall == 0: return
	elapsed += delta
	if elapsed >= next_observation:
		next_observation += 30.0
		record("observation",{"position":room.player.position if is_instance_valid(room) else Vector2.ZERO,"input":room.controls_enabled() if is_instance_valid(room) else false,"transitioning":transitioning,"nav":room.navigation_target() if is_instance_valid(room) else {},"phase":Game.run.expedition.phase if Game.run != null else "camp","hp":Game.run.hp if Game.run != null else 0,"actors":room._living_enemy_count() if is_instance_valid(room) else 0,"last_decision":controller.decisions.back() if controller != null and not controller.decisions.is_empty() else {},"rejected":controller.rejected if controller != null else {}})
	if elapsed >= limit: stop("observation_limit"); return
	if not is_instance_valid(room):
		if elapsed >= next_departure and not transitioning: depart()
		return
	if transitioning: return
	if Game.run == null:
		finish_adventure(str(Game.last_result.get("outcome","death"))); return
	if Game.run.hp <= 0:
		finish_adventure("death"); return
	if transitioning or not room.controls_enabled(): return
	if Game.run.resource <= 0: room_resource_empty += delta
	if elapsed-room_started > 600:
		record("stalled",{"position":room.player.position,"navigation":room.navigation_target(),"actors":room._living_enemy_count(),"objective":room.objectives.status() if is_instance_valid(room.objectives) else {}})
		stop("controller_stalled"); return
	controller.step(elapsed-room_started)
	if elapsed < next_decision: return
	next_decision = elapsed+.1
	var danger: bool = controller.danger_at(room.player.position,controller.visible_threats()) > 0
	if danger: return
	if is_instance_valid(room._boss_actor) and room._boss_actor.is_alive(): return
	if room._living_enemy_count() > 0: return
	# Authored objective navigation is visible to the player. Required targets
	# receive real attacks; charging/sealing requires actual movement/interaction.
	var objective: Dictionary = room.objectives.navigation_target() if is_instance_valid(room.objectives) and not room.objectives.is_complete() else {}
	var id := str(objective.get("id",""))
	if not id.is_empty():
		var actor: Node2D = room.objectives.targets.get(id)
		if is_instance_valid(actor) and actor.is_alive(): controller.attack_target(elapsed-room_started,actor,controller.visible_threats(),true); return
		var at: Vector2 = objective.position
		if room.player.position.distance_to(at) > 65: room.player.request_move(at,false)
		else:
			room.player.clear_movement_target()
			room.interact()
		return
	if room._living_enemy_count() > 0: return
	var destination: Dictionary = room.navigation_target()
	if not destination.has("position"): return
	var at: Vector2 = destination.position
	if room.player.position.distance_to(at) > 65: room.player.request_move(at,false)
	else: room.interact()
func completed_room() -> void:
	flush_room_observation("cleared")
	clears += 1
	record("room_cleared",{"room":room.layout_id,"room_seconds":elapsed-room_started,"hp":Game.run.hp,"hp_max":Game.run.max_hp,"resource":Game.run.resource,"pending_materials":Game.run.expedition.pending_materials,"pending_count":Game.run.expedition.pending_equipment.size()})
	if Game.hero_level(hero) > last_level:
		last_level = Game.hero_level(hero)
		record("level",{"new_level":last_level})
	call_deferred("field_progress")
func field_progress() -> void:
	if not is_instance_valid(room) or Game.run == null or Game.run.expedition.phase != "cleared": return
	for drop: Dictionary in Game.pending_field_equipment():
		var preview: Dictionary = Game.preview_field_equipment(drop.drop_id)
		var gain := not preview.is_empty() and score(preview.next_stats) > score(Game.run.stats)+.001
		if gain:
			var prior_score := score(Game.run.stats)
			var result: Dictionary = Backpack.apply(room,drop.equipment_id,drop.slot,Game.run.expedition.checkpoint_id)
			if result.get("success",false): record("field_equip",{"slot":drop.slot,"instance":drop.equipment_id,"score_before":prior_score,"score_after":score(Game.run.stats),"hp_after":Game.run.hp,"resource_after":Game.run.resource})
		else:
			Game.choose_field_equipment(drop.drop_id,"keep",room.expedition_runtime_snapshot(),Game.run.expedition.checkpoint_id)

func interaction(kind: String,_context: Dictionary) -> void:
	if transitioning: return
	transitioning = true
	call_deferred("handle_interaction",kind)
func handle_interaction(kind: String) -> void:
	if kind == "extract": finish_adventure("extracted"); return
	if kind == "early_extract" and float(Game.run.hp)/float(Game.run.max_hp) < .4: finish_adventure("extracted"); return
	for offer: Dictionary in Game.expedition_snapshot().relic_offers:
		var choice := "skip"
		if float(Game.run.hp)/Game.run.max_hp >= .4:
			for candidate: String in offer.candidates:
				if int(Game.run.expedition.relic_levels.get(candidate,0)) < 2 and (Game.run.expedition.relic_levels.has(candidate) or Game.run.expedition.relic_levels.size() < 4): choice = candidate; break
		if not Game.choose_run_relic(offer.offer_id,choice,"",room.expedition_runtime_snapshot()): stop("relic_decision_rejected"); return
		record("relic_choice",{"choice":choice,"offer":offer.offer_id})
	if Game.run.expedition.phase == "safe":
		Game.prepare_safe_resources(room.expedition_runtime_snapshot(),Game.run.expedition.checkpoint_id)
		for offer: Dictionary in Game.expedition_snapshot().supply_offers:
			if offer.product_id == "heal_large" and float(Game.run.hp)/Game.run.max_hp < .65 and Game.run.gold >= offer.price:
				Game.purchase_run_supply(offer.offer_id,room.expedition_runtime_snapshot())
	var options: Array = expedition.next_options()
	if options.is_empty():
		if expedition.can_extract(): finish_adventure("extracted")
		else: stop("no_route_option")
		return
	var choice := str(options[0])
	var context: Dictionary = expedition.candidate(choice)
	var prepared: Dictionary = room.prepare_expedition_node(context)
	if not prepared.get("valid",false): stop("next_layout_rejected"); return
	if not Game.choose_expedition_node(context.node_index,choice) or not Game.advance_expedition_node(room.expedition_runtime_snapshot(),Game.run.expedition.checkpoint_id):
		room.discard_prepared_expedition_node(prepared); stop("advance_rejected"); return
	prepared.runtime = Game.expedition_snapshot().runtime.duplicate(true)
	flush_room_observation("transition")
	room.apply_prepared_expedition_node(prepared)
	controller.configure(room)
	arm_room_observation()
	room_started = elapsed
	transitioning = false
func finish_adventure(outcome: String) -> void:
	flush_room_observation(outcome)
	transitioning = true
	var result: Dictionary = Game.finish_run(outcome)
	if result.is_empty(): stop("settlement_rejected"); return
	if outcome == "death": deaths += 1; maximum_difficulty = maxi(0,maximum_difficulty-1)
	else:
		wins += 1
		if Game.hero_level(hero) >= 5 and str(room.expedition_context.get("role","")) == "boss": maximum_difficulty = mini(4,maximum_difficulty+1)
	record("settlement",{"result":result,"equipment":Game.profile.equipment.size()})
	await room.combat_audio.wait_for_cleanup()
	room.queue_free(); room = null
	camp_progress()
	next_departure = elapsed+8.0 # fixed player-facing camp decision allowance
	transitioning = false
func camp_progress() -> void:
	# Frozen legal camp policy: spend only earned assets, preserve starters,
	# choose visible permanent stats and pursue the published chapter build.
	var points: int = Growth.available_points(Game.hero_talents(hero),Game.hero_level(hero))
	for index in points:
		for node: String in ["mastery","precision","agility","dexterity","vitality","resistance"]:
			if Game.allocate_hero_talent(node): break
	if Game.hero_level(hero) >= 18: Game.set_hero_branch("q","B")
	if Game.hero_level(hero) >= 20: Game.set_hero_branch("ultimate","A")
	equip_best()
	var ids: Array = Game.profile.equipment.keys()
	ids.sort()
	for id: String in ids:
		var item: Dictionary = Game.profile.equipment[id]
		if id in Game.profile.loadout.values() or str(item.source_event_id).begins_with("starter:"): continue
		if item.rarity not in ["white","green"] or int(item.item_level) >= Game.hero_level(hero)-3: continue
		var result: Dictionary = Game.forge_equipment_v2("dismantle",{"instance_id":id},"natural:dismantle:"+str(run_count)+":"+str(ids.find(id)))
		if result.ok: record("dismantle",{"instance":id})
		else: record("camp_transaction_rejected",{"action":"dismantle","instance":id,"result":result})
	var desired := preferred_templates()
	for template: String in desired:
		var slot: String = ContentRegistry.equipment(template,2).slot
		var equipped: String = Game.profile.loadout.get(slot,"")
		var existing: Dictionary = Game.profile.equipment.get(equipped,{})
		var power := "magic" if hero == "CH03" else "physical"
		if Game.hero_level(hero) == Growth.level_cap() and (existing.get("rarity","") != "gold" or existing.get("template_id","") != template or int(existing.get("item_level",0)) < Game.hero_level(hero)):
			var request := {"template_id":template,"rarity":"gold","power_type":power,"item_level":Game.hero_level(hero)}
			var quote: Dictionary = Game.quote_craft_equipment_v2(request)
			if affordable(quote):
				var result: Dictionary = Game.craft_equipment_v2(request,"natural:craft:"+str(run_count)+":"+template)
				if result.ok: record("craft",{"template":template,"cost":quote})
				else: record("camp_transaction_rejected",{"action":"craft","template":template,"result":result})
			else: record("camp_quote_unavailable",{"action":"craft","template":template,"quote":quote})
		elif equipped.is_empty():
			var request := {"template_id":template,"rarity":"green","power_type":power,"item_level":Game.hero_level(hero)}
			var quote: Dictionary = Game.quote_equipment_v2(request)
			if affordable(quote):
				var result: Dictionary = Game.purchase_equipment_v2(request,"natural:purchase:"+str(run_count)+":"+template)
				if result.ok: record("purchase",{"template":template,"cost":quote})
				else: record("camp_transaction_rejected",{"action":"purchase","template":template,"result":result})
			else: record("camp_quote_unavailable",{"action":"purchase","template":template,"quote":quote})
	equip_best()
	for slot: String in ["weapon","hands","chest","head","legs","feet","ring","charm"]:
		var id: String = Game.profile.loadout.get(slot,"")
		if id.is_empty(): continue
		var item: Dictionary = Game.profile.equipment[id]
		var target: int = mini(Forging.manual_cap(Game.hero_level(hero)),2 if item.rarity == "gold" else 5 if item.rarity == "purple" else 3)
		while int(Game.profile.equipment[id].enhancement_rank) < target:
			var quote: Dictionary = Game.quote_forging_v2("enhance",{"instance_id":id})
			if not affordable(quote):
				record("camp_quote_unavailable",{"action":"enhance","instance":id,"quote":quote})
				break
			var rank: int = int(Game.profile.equipment[id].enhancement_rank)+1
			if not Game.upgrade_equipment(id,"natural:enhance:"+str(run_count)+":"+slot+":"+str(rank)):
				record("camp_transaction_rejected",{"action":"enhance","instance":id,"error":Game.last_error})
				break
			record("enhance",{"slot":slot,"rank":rank,"cost":quote.gold})
	var gear: Array = []
	var high_set := true
	for template: String in desired:
		var slot: String = ContentRegistry.equipment(template,2).slot
		var item: Dictionary = Game.profile.equipment.get(Game.profile.loadout.get(slot,""),{})
		gear.append({"slot":slot,"template":item.get("template_id",""),"rarity":item.get("rarity",""),"ilvl":item.get("item_level",0),"rank":item.get("enhancement_rank",0)})
		if item.get("template_id","") != template or item.get("rarity","") != "gold" or int(item.get("enhancement_rank",0)) < 2 or int(item.get("item_level",0)) < Game.hero_level(hero): high_set = false
	var current_stats := Game.selected_stats()
	var core_count := 0
	for count in current_stats.get("sets",{}).values(): core_count = maxi(core_count,int(count))
	var purple_count := 0
	var gold_count := 0
	var weapon_rank := 0
	for item: Dictionary in gear:
		if item.rarity == "purple": purple_count += 1
		if item.rarity == "gold": gold_count += 1
		if item.slot == "weapon": weapon_rank = int(item.rank)
	var milestones := {"level20":Game.hero_level(hero)==20,"spent_talents":19-Growth.available_points(Game.hero_talents(hero),20),"core_pieces":core_count,"purple_pieces":purple_count,"gold_pieces":gold_count,"main_weapon_rank":weapon_rank,"all_slots_filled":Game.profile.loadout.size()==8 and Game.profile.loadout.values().all(func(id): return not str(id).is_empty())}
	record("camp_build",{"equipment":gear,"chapter_gold_plus2_complete":high_set,"high_difficulty_milestones":milestones,"stats":current_stats})

func wish_slot() -> String:
	var weapon: Dictionary = Game.profile.equipment.get(Game.profile.loadout.get("weapon",""),{})
	if str(weapon.get("source_event_id","")).begins_with("starter:"): return "weapon"
	var lowest := INF
	var chosen := "weapon"
	var desired := preferred_templates()
	for slot: String in ["weapon","hands","chest","head","legs","feet","ring","charm"]:
		var item: Dictionary = Game.profile.equipment.get(Game.profile.loadout.get(slot,""),{})
		if item.is_empty(): return slot
		var quality: float = float({"white":0,"green":1,"purple":2,"gold":3}.get(item.rarity,0))+float(item.enhancement_rank)/20.0+float(item.item_level)/100.0
		if Game.hero_level(hero) == Growth.level_cap() and item.template_id not in desired: quality -= 1.0
		if quality < lowest: lowest = quality; chosen = slot
	return chosen

func preferred_templates() -> Array:
	var chapter := clampi(ceili(float(Game.hero_level(hero))/5.0),1,4)
	var result: Array = Fixtures.SET_TEMPLATES[Fixtures.SETS_BY_CHAPTER[chapter][hero]].duplicate()
	if chapter == 4 and hero != "CH01": result[0] = "EQ05"; result[6] = "EQ102"
	return result

func affordable(quote: Dictionary) -> bool:
	if not quote.get("ok",false) or int(quote.gold) > int(Game.profile.permanent_gold): return false
	for key: String in quote.get("materials",{}):
		if int(quote.materials[key]) > int(Game.profile.materials.get(key,0)): return false
	return true

func score(stats: Dictionary) -> float:
	if stats.is_empty(): return -INF
	var power: Dictionary = Abilities.preview_powers(hero,stats)
	var offense := (.65*float(power.basic_H)/maxf(.1,float(stats.attack_interval))+.35*float(power.skill_H))*(1.0+float(stats.damage_bonus))*(1.0+float(stats.crit_chance)*(float(stats.crit_multiplier)-1.0))
	return offense+float(stats.max_hp)*.045+float(stats.armor+stats.magic_resist)*.1+float(stats.get("armor_penetration",0)+stats.get("magic_penetration",0))*.2

func equip_best() -> void:
	var ids: Array = Game.profile.equipment.keys()
	ids.sort()
	for slot: String in Game.equipment_slots():
		var best: String = Game.profile.loadout.get(slot,"")
		var best_score := score(Game.selected_stats())
		for id: String in ids:
			var item: Dictionary = Game.profile.equipment[id]
			if ContentRegistry.equipment(item.template_id,2).slot != slot or not Instances.can_equip(item,hero,Game.hero_level(hero)): continue
			var value := score(Game.preview_stats(id))
			var desired: Array = preferred_templates()
			var preferred: bool = item.rarity == "gold" and item.template_id in desired and int(item.item_level) >= Game.hero_level(hero)
			var best_item: Dictionary = Game.profile.equipment.get(best,{})
			var best_preferred: bool = best_item.get("rarity","") == "gold" and best_item.get("template_id","") in desired and int(best_item.get("item_level",0)) >= Game.hero_level(hero)
			if (preferred and not best_preferred) or (preferred == best_preferred and value > best_score+.001): best = id; best_score = value
		if not best.is_empty() and best != Game.profile.loadout.get(slot,""):
			var old: String = Game.profile.loadout.get(slot,"")
			var source := ""
			var highest := int(Game.profile.equipment[best].enhancement_rank)
			for candidate: String in ids:
				var item: Dictionary = Game.profile.equipment[candidate]
				if candidate == best or item.power_type != Game.profile.equipment[best].power_type or ContentRegistry.equipment(item.template_id,2).slot != slot: continue
				if int(item.enhancement_rank) > highest and int(item.enhancement_rank) <= Forging.manual_cap(Game.hero_level(hero)):
					source = candidate; highest = int(item.enhancement_rank)
			if not source.is_empty():
				var request := {"source_instance_id":source,"target_instance_id":best}
				var quote: Dictionary = Game.quote_forging_v2("inherit",request)
				if affordable(quote):
					var operation := "natural:inherit:"+str(run_count)+":"+source.sha256_text().left(24)+":"+best.sha256_text().left(24)
					var moved: Dictionary = Game.forge_equipment_v2("inherit",request,operation)
					if moved.ok: record("inherit",{"source":source,"target":best,"gold":quote.gold,"rank":Game.profile.equipment[best].enhancement_rank})
					else: record("camp_transaction_rejected",{"action":"inherit","source":source,"target":best,"result":moved})
				else: record("camp_quote_unavailable",{"action":"inherit","source":source,"target":best,"quote":quote})
			if Game.equip_item(best): record("equip",{"slot":slot,"old":old,"new":best,"score":score(Game.selected_stats())})
			else: record("camp_transaction_rejected",{"action":"equip","instance":best,"error":Game.last_error})
func stop(reason: String) -> void:
	if finished: return
	finished = true
	flush_room_observation(reason)
	record("stop",{"reason":reason,"last_error":Game.last_error,"unfinished_run":Game.run != null})
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(.2).timeout
	get_tree().quit(0 if reason == "observation_limit" else 1)

func arm_room_observation() -> void:
	room_recorded = false
	room_resource_empty = 0.0
	room_initial_hp = Game.run.hp
	room_initial_stats = Game.run.stats.duplicate(true)
	trail.all_events.clear()
	room.get("packets").clear()
	room.get("releases").clear()
	excluded_actor_ids = room.get("actor_roster").duplicate()
	for actor: Node in room.enemies.get_children():
		if not actor.is_queued_for_deletion(): excluded_actor_ids.erase(str(actor.get_instance_id()))
	room.call("scan_actors")
	room.set("recording",true)

func flush_room_observation(reason: String) -> void:
	if room_recorded or not is_instance_valid(room) or trail == null: return
	room_recorded = true
	room.call("scan_actors")
	room.set("recording",false)
	var hp_loss := 0.0
	var shield_loss := 0.0
	for packet: Dictionary in trail.all_events:
		hp_loss += float(packet.hp_loss)
		shield_loss += float(packet.shield_absorbed)
	var roster: Dictionary = room.get("actor_roster").duplicate(true)
	for id in excluded_actor_ids: roster.erase(id)
	var end_hp: float = Game.run.hp if Game.run != null else 0.0
	record("room_metrics",{"reason":reason,"room":room.layout_id,"room_seconds":elapsed-room_started,"initial_stats":room_initial_stats,"hp_start":room_initial_hp,"hp_end":end_hp,"hp_loss":hp_loss,"shield_absorbed":shield_loss,"effective_healing":maxf(0.0,end_hp-room_initial_hp+hp_loss),"resource_empty_seconds":room_resource_empty,"incoming_packets":trail.all_events.duplicate(true),"outgoing_packets":room.get("packets").duplicate(true),"actor_roster":roster})
