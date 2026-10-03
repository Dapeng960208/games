extends Node
const Layouts = preload("res://scripts/world/b06_room_layouts.gd")
const Geometry = preload("res://scripts/world/b06_room_geometry.gd")
const Runtime = preload("res://scripts/world/b06_tide_runtime.gd")
const Numbers = preload("res://scripts/combat/b06_enemy_numbers.gd")
const Candidate = preload("res://scripts/world/b06_candidate.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("B06 TIDE LIVE: "+label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not Game.profile_path.contains("test_b06_tide_live"): get_tree().quit(2); return
	Game.run = null
	check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":26002}),"isolated baseline")
	var room = load("res://scenes/room.tscn").instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	add_child(room)
	await get_tree().process_frame
	for actor in room.enemies.get_children(): actor.free()
	for context: Dictionary in Candidate.route():
		var prepared: Dictionary = room.prepare_expedition_node(context)
		check(bool(prepared.get("valid",false)),"candidate prepare "+str(context.room_id)+str(prepared.get("error","")))
		room.discard_prepared_expedition_node(prepared)
	room.layout = Layouts.build("L32",26002)
	room.layout_id = "L32"
	room.expedition_context = {"biome_id":"B06","room_id":"L32","role":"branch","difficulty":0,"b06_candidate":true}
	room._configure_ground_boundary()
	check(room.ground_polygon == Geometry.polygon("L32"),"actual MineRoom uses tide ground")
	var host := Runtime.new()
	room.add_child(host)
	room.b06_mechanics = host
	check(host.configure("L32"),"actual host configured")
	var profile: Dictionary = Numbers.ordinary("B06-M04",26,0)
	var enemy = room.spawn_enemy(Geometry.world_point([500,500]),"B06-M04",26,{"profile":profile,"reward_spawn_id":"b06-live-1","reward_enabled":false})
	check(is_instance_valid(enemy),"real MineEnemy instantiated")
	if is_instance_valid(enemy):
		host.tick(10)
		check(int(enemy.status.shield()) == int(round(enemy.health.maximum*.1)),"real CombatHealth shell")
		check(host.movement_multiplier(enemy,true) == 1.12,"actual actor wet speed")
		room.player.position = Geometry.world_point([500,500])
		var wet_speed: float = room.player.stat("move_speed",220)
		room.player.position = Geometry.world_point([840,990])
		check(is_equal_approx(wet_speed,room.player.stat("move_speed",220)*.85),"actual player stat tide slow")
		check(host.interact("drain_west",room.player,"player",func(): return Game.run.hp > 0,room.has_line_of_sight),"actual player gate channel")
		host.tick(.6)
		check(host.movement_multiplier(enemy,true) == 1.0,"actual gate drains actor patch")
	for context: Dictionary in Candidate.route():
		if context.role == "boss": continue
		context["node_index"] = -100
		var prepared: Dictionary = room.prepare_expedition_node(context)
		room.apply_prepared_expedition_node(prepared)
		check(is_instance_valid(room.b06_mechanics),"candidate actual host "+str(context.room_id))
		check(not room.objective_complete,"cannot clear before finite encounters")
		if context.room_id == "L35":
			room.player.position = Geometry.world_point([1400,396])
			check(room.objectives.interact("tide_bell",room.player),"actual objective F rings L35 bell")
			var saved_bell: Dictionary = JSON.parse_string(JSON.stringify(room.b06_mechanics.checkpoint()))
			check(room.b06_mechanics.next_tide_visible(),"actual bell shows direction early")
			room.b06_mechanics.tick(5,true)
			check(JSON.parse_string(JSON.stringify(room.b06_mechanics.checkpoint())) == saved_bell,"actual paused bell retains phase")
			room.b06_mechanics.tick(10)
			check(room.b06_mechanics.restore_checkpoint(saved_bell) and room.b06_mechanics.next_tide_visible(),"actual bell JSON resume")
		if context.room_id == "L33":
			room.player.position = Geometry.world_point([1000,500])
			room.b06_mechanics.tick(10)
			check(room.b06_mechanics.movement_multiplier(room.player) == .85,"actual L33 north floods first")
			var saved_market: Dictionary = JSON.parse_string(JSON.stringify(room.b06_mechanics.checkpoint()))
			room.b06_mechanics.tick(16)
			check(room.b06_mechanics.movement_multiplier(room.player) == 1,"actual L33 alternates north dry")
			check(room.b06_mechanics.restore_checkpoint(saved_market) and room.b06_mechanics.movement_multiplier(room.player) == .85,"actual L33 restores exact alternating phase")
		for zone_index in room.encounter_zones.size():
			room.player.position = room.encounter_zones[zone_index].center
			room._update_encounters(4.0)
			check(room._living_enemy_count() > 0,"actual finite wave "+str(context.room_id))
			for attempt in 4:
				for actor in room.enemies.get_children():
					check(not actor.reward_enabled,"candidate actor has no economic rewards")
					actor.free()
				room._update_encounters(4.0)
		check(room._encounters_exhausted(),"all candidate waves exhausted")
		room._tick_expedition(0)
		check(room.objective_complete and not room.objective_rewarded,"preview clear without permanent settlement")
	var seen := {}
	for context: Dictionary in Candidate.route():
		if context.role == "boss": continue
		for d in 5:
			for z in 2:
				var plan := Candidate.encounter_plan(context.room_id,z,d)
				check(not plan.is_empty(),"finite candidate plan")
				for wave: Array in plan.waves:
					check(wave.size() <= 6,"zone cap")
					for member: Dictionary in wave: seen[member.enemy_id] = true
	check(seen.size() == 18,"all eighteen candidate contacts")
	var last_context := {"room_id":"L32","biome_id":"B06","role":"branch","difficulty":0,"seed":26002,"node_index":1,"b06_candidate":true}
	var last_prepared: Dictionary = room.prepare_expedition_node(last_context)
	room.apply_prepared_expedition_node(last_prepared)
	room.player.loadout.event("room_enter",{"room_id":"L32","unvisited":true,"combat_room":true})
	room.b06_mechanics.tick(9.5)
	var safe: Dictionary = preload("res://scripts/combat/combat_snapshot.gd").capture(room)
	check(safe.get("mode") == "safe_boundary" and safe.get("runtime",{}).has("b06_mechanisms"),"existing safe snapshot admits versioned B06 payload")
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(safe))
	check(preload("res://scripts/core/expedition_state.gd").runtime_valid(reloaded,Game.run.hero_id,Game.run.stats),"production runtime validator accepts B06 safe payload JSON")
	room.b06_mechanics.tick(.5)
	check(preload("res://scripts/combat/combat_snapshot.gd").restore(room,reloaded),"production safe restore restores tide payload")
	check(room.b06_mechanics.state.clock_state().phase=="warning" and room.b06_mechanics.state.clock_state().remaining_seconds==.5,"safe restore cannot skip final half-second warning")
	var old: Dictionary = reloaded.duplicate(true)
	old.erase("runtime")
	check(preload("res://scripts/combat/combat_snapshot.gd").validate(old,Game.run.hero_id,Game.run.stats),"old payload-free save remains valid")
	if reloaded.is_empty():
		get_tree().quit(1)
		return
	var corrupt: Dictionary = reloaded.duplicate(true)
	corrupt.runtime.b06_mechanisms.difficulty=1
	check(not preload("res://scripts/combat/combat_snapshot.gd").restore(room,corrupt),"wrong difficulty does not mutate mechanism host")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup")
	room.free()
	Game.run = null
	print("B06_TIDE_LIVE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
