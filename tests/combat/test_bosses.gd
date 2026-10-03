extends SceneTree
## Four-boss acceptance. Run only with:
## tools/test.ps1 -Suite bosses -SkipImport

const Profiles = preload("res://scripts/domain/combat/boss_profiles.gd")
const Brain = preload("res://scripts/gameplay/bosses/boss_brain.gd")
const Layouts = preload("res://scripts/domain/world/boss_layouts.gd")
const Props = preload("res://scripts/presentation/world/room_props.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const FixedLayouts = preload("res://scripts/domain/world/fixed_room_layouts.gd")
const IDS: Array[String] = ["BO01","BO02","BO03","BO04"]
const ACTIONABLE := ["melee","projectile","charge","ground_area","pull","guard","haste","heal","counter","summon","decoy","utility"]

class HealthStub:
	extends RefCounted
	var maximum: float = 1000.0
	var current: float = 1000.0
	var dead: bool = false

class ActorStub:
	extends Node2D
	var health := HealthStub.new()
	var state: StringName = &"emerging"
	var state_time: float = 0.8
	var velocity := Vector2.ZERO
	var casts: Array[Dictionary] = []
	var phase_events: Array[int] = []
	var weakpoint_events: Array[Dictionary] = []

	func is_alive() -> bool:
		return not health.dead

	func cast_enemy_skill(skill: Dictionary) -> void:
		casts.append(skill.duplicate(true))

	func boss_phase_started(next_phase: int, _ratio: float) -> void:
		phase_events.append(next_phase)

	func boss_weakpoint_changed(open: bool, id: String, duration: float) -> void:
		weakpoint_events.append({"open":open,"id":id,"duration":duration})

class VictimStub:
	extends Node2D
	var alive: bool = true

	func is_alive() -> bool:
		return alive

class GameStub:
	extends Node
	var run: Variant = null
	var profile: Dictionary = {"settings":{}}

class RoomStub:
	extends Node2D
	var layout: Dictionary = {}
	var obstructions: Array[Rect2] = []
	var gold_drops: Array[Dictionary] = []
	var enemy_skills: Node2D
	var fx_font: Font = ThemeDB.fallback_font
	var deaths: int = 0
	var enemies: Node2D
	var player: Node2D

	func _init() -> void:
		enemies = Node2D.new()
		enemies.name = "Enemies"
		add_child(enemies)
		player = Node2D.new()
		player.name = "Player"
		add_child(player)

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true

	func enemy_died(_enemy: Node2D) -> void:
		deaths += 1

	func add_damage_text(_at: Vector2, _amount: float, _kind: StringName, _context: Dictionary = {}) -> void:
		pass

	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void:
		pass

	func move_actor(from: Vector2, displacement: Vector2, _radius: float) -> Vector2:
		return from + displacement

	func navigation_direction(from: Vector2, to: Vector2, _radius: float) -> Vector2:
		return from.direction_to(to)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS TEST FAIL: " + label)

func _run() -> void:
	_profiles_and_finite_reinforcements()
	_layout_contract()
	_brain_actions_and_locked_geometry()
	_phase_and_counterplay()
	await _boss_node_contract()
	print("BOSS TESTS: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func _profiles_and_finite_reinforcements() -> void:
	var behaviors: Dictionary = {}
	for id: String in IDS:
		var profile: Dictionary = Profiles.resolve(id, 2)
		_check(not profile.is_empty() and Profiles.validate(profile).is_empty(), id + " profile is complete and valid")
		_check(profile.phase_thresholds == [0.7,0.35] and profile.rank == "boss" and profile.immune_forced_movement, id + " has the shared boss phase/control contract")
		_check(float(profile.chill_multiplier) == 0.5 and float(profile.max_hp) > 1000.0 and float(profile.damage) > 0.0, id + " has real boss combat stats")
		_check(str(profile.visual_asset) == AssetCatalog.boss_body(id), id + " uses its original boss art path")
		behaviors[str(profile.behavior_id)] = true
		var count: int = 0
		var threat: int = 0
		var members: Dictionary = {}
		for wave: Dictionary in profile.reinforcement_waves:
			_check(int(wave.phase) in [2,3], id + " only reinforces at authored phase boundaries")
			count += int(wave.count)
			threat += int(wave.threat)
			for member: Dictionary in wave.members:
				members[str(member.enemy_id)] = int(members.get(str(member.enemy_id),0)) + int(member.count)
		var authored_count: int = 0
		for member: Dictionary in profile.arena.reinforcements:
			authored_count += int(member.count)
			_check(int(members.get(str(member.enemy_id),0)) == int(member.count), id + " preserves the authored finite count for " + str(member.enemy_id))
		_check(count == authored_count and count <= int(profile.reinforcement_cap), id + " reinforcement total respects the actor cap")
		_check(threat <= int(profile.reinforcement_budget), id + " reinforcement total respects the threat budget")
	_check(behaviors.size() == 4, "all four bosses have distinct behavior identities")
	_check(Catalog.validate().is_empty(), "boss implementation preserves the authored world catalog")

func _layout_contract() -> void:
	var geometry_signatures: Dictionary = {}
	for id: String in IDS:
		var layout: Dictionary = Layouts.build(id, 74191)
		var replay: Dictionary = Layouts.build(id, 74191)
		_check(not layout.is_empty() and Layouts.validate(layout).is_empty(), id + " independent arena validates")
		_check(var_to_str(layout) == var_to_str(replay), id + " arena is deterministic for a saved seed")
		_check(layout.arena == Rect2(Vector2.ZERO, FixedLayouts.ARENA.size * FixedLayouts.PLAYFIELD_SCALE) and layout.room_id == id+"_arena" and layout.boss_id == id, id + " follows the normal compact room identity/arena shape")
		_check(layout.has_all(["static_obstructions","static_obstruction_kinds","prop_instances","encounter_zones","hazard_zones","dynamic_reservations","buff_anchors"]), id + " exposes RoomProps/room layout keys")
		_check(_static_recipes_match(layout), id + " visible static recipes match physical terrain alongside room boundaries")
		_check(layout.interactables.size() >= 3 and layout.interactables.size() == layout.boss_counterplay.size(), id + " has physical arena counter descriptors")
		_check(layout.reinforcement_spawns.size() >= 4 and layout.reinforcement_plan == Catalog.bosses()[id].arena.reinforcements, id + " exposes finite add spawn/config data")
		geometry_signatures[var_to_str([layout.obstructions,layout.visual_markers,layout.interactables])] = true
		var host := RoomStub.new()
		host.layout = layout
		host.obstructions.assign(layout.obstructions)
		var props: RoomProps = Props.new()
		_check(props.configure(host, layout), id + " arena can be consumed by the real RoomProps")
		_check(props.configuration_errors.is_empty() and props.active_buffs().is_empty(), id + " RoomProps starts without stale state")
		props.free()
		host.free()
	_check(geometry_signatures.size() == 4, "the four boss arenas are not reskinned copies")

func _static_recipes_match(layout: Dictionary) -> bool:
	if layout.static_obstructions.size() != layout.static_obstruction_kinds.size(): return false
	for index: int in layout.static_obstructions.size():
		var collision_index: int = layout.obstructions.find(layout.static_obstructions[index])
		if collision_index < 0 or layout.obstruction_kinds[collision_index] != layout.static_obstruction_kinds[index]: return false
	return true

func _brain_actions_and_locked_geometry() -> void:
	var expected: Dictionary = {
		"BO01":["hammer_fan","ladle_drag"],
		"BO02":["root_fork","spore_pod"],
		"BO03":["glide","capacitor_burst"],
		"BO04":["resonance_ring","sound_blade"],
	}
	for id: String in IDS:
		var sim: Dictionary = _simulation(id)
		var locked: Dictionary = _advance_to_state(sim, &"locked")
		_check(not locked.is_empty() and bool(locked.locked), id + " first action reaches an explicit locked tell")
		var frozen: String = var_to_str([locked.get("origin"),locked.get("target"),locked.get("points",[]),locked.get("paths",[]),locked.get("direction")])
		sim.victim.position += Vector2(510,-370)
		sim.brain.tick(sim.actor,0.05,sim.victim)
		var after: Dictionary = sim.brain.current_telegraph()
		_check(frozen == var_to_str([after.get("origin"),after.get("target"),after.get("points",[]),after.get("paths",[]),after.get("direction")]), id + " locked target and geometry do not track")
		_advance_casts(sim, 2)
		_check(sim.actor.casts.size() >= 2, id + " executes two phase-one attacks")
		if sim.actor.casts.size() >= 2:
			_check(str(sim.actor.casts[0].action_id) == expected[id][0] and str(sim.actor.casts[1].action_id) == expected[id][1], id + " first encounter demonstrates one full attack before combining the second")
			_check(str(sim.actor.casts[0].kind) in ACTIONABLE and str(sim.actor.casts[1].kind) in ACTIONABLE, id + " emits commands consumed by EnemySkillRuntime")
			_check(_geometry_is_executable(sim.actor.casts[0]) and _geometry_is_executable(sim.actor.casts[1]), id + " warning geometry is also executable hit geometry")
		_dispose(sim)

func _phase_and_counterplay() -> void:
	for id: String in IDS:
		var sim: Dictionary = _simulation(id)
		sim.actor.health.current = 690.0
		sim.brain.tick(sim.actor,0.01,sim.victim)
		_check(sim.brain.phase_index() == 2 and sim.actor.phase_events == [2] and sim.brain.current_telegraph().is_empty(), id + " 70% transition clears the old warning")
		sim.actor.health.current = 340.0
		sim.brain.tick(sim.actor,0.01,sim.victim)
		_check(sim.brain.phase_index() == 3 and sim.actor.phase_events == [2,3] and sim.brain.current_telegraph().is_empty(), id + " 35% transition is one-shot and clears the old warning")
		_dispose(sim)

	var forge: Dictionary = _simulation("BO01")
	forge.actor.health.current = 690.0
	forge.brain.tick(forge.actor,0.01,forge.victim)
	var slag: Dictionary = _advance_to_action(forge,"slag_lane")
	var slag_lane: int = int(slag.get("lane_index",-1))
	_check(slag_lane >= 0 and forge.brain.apply_arena_counter("BO01:cooling_valve:"+str(slag_lane)) and forge.brain.current_telegraph().is_empty(), "BO01 cooling valve extinguishes the currently warned slag direction")
	_dispose(forge)

	var brood: Dictionary = _simulation("BO02")
	var roots: Dictionary = _advance_to_action(brood,"root_fork")
	_check(roots.get("paths",[]).size() == 3 and brood.brain.apply_arena_counter("BO02:root_knot:0") and brood.brain.current_telegraph().get("paths",[]).size() == 2 and not brood.brain.apply_arena_counter("BO02:root_knot:0"), "BO02 broken root removes one current warned/executable fork and cannot be reused")
	_dispose(brood)

	var hangar: Dictionary = _simulation("BO03")
	hangar.actor.health.current = 690.0
	hangar.brain.tick(hangar.actor,0.01,hangar.victim)
	var runways: Dictionary = _advance_to_action(hangar,"runway_pair")
	var live_lane: int = int(runways.get("lane_indices",[-1])[0])
	_check(runways.get("paths",[]).size() == 2 and hangar.brain.apply_arena_counter("BO03:fuse_box:"+str(live_lane)) and hangar.brain.current_telegraph().get("paths",[]).size() == 1 and live_lane not in hangar.brain.current_telegraph().get("lane_indices",[]) and not hangar.brain.apply_arena_counter("BO03:fuse_box:"+str(live_lane)), "BO03 fuse removes the matching current warning/projectile path and is one-use")
	_dispose(hangar)

	var bell: Dictionary = _simulation("BO04")
	bell.actor.health.current = 690.0
	bell.brain.tick(bell.actor,0.01,bell.victim)
	var replay: Dictionary = _advance_to_action(bell,"replay_path")
	_check(replay.get("paths",[]).size() == 2 and bell.brain.apply_arena_counter("BO04:edge_bell:0") and bell.brain.current_telegraph().get("paths",[]).size() == 1, "BO04 broken bell clears one trail from the current warning and executable replay")
	_dispose(bell)

func _boss_node_contract() -> void:
	var registered_stub: bool = false
	var game_stub: Node
	var game_host: Node = root.get_node_or_null("Game")
	var started_run: bool = false
	if game_host != null:
		if game_host.run == null:
			if not bool(game_host.has_profile):
				game_host.new_profile()
			started_run = bool(game_host.start_run())
	else:
		game_stub = GameStub.new()
		game_stub.run = RefCounted.new()
		Engine.register_singleton("Game",game_stub)
		registered_stub = true
	var boss_script: Script = load(AssetCatalog.resolve("res://scripts/gameplay/bosses/boss_actor.gd"))
	if boss_script != null:
		_boss_arena_counter_contract(boss_script)
	var scene: PackedScene = load(AssetCatalog.resolve("res://scenes/gameplay/bosses/boss.tscn"))
	var scene_instance: Node = scene.instantiate() if scene != null else null
	_check(boss_script != null and scene_instance != null and scene_instance.get_script() == boss_script, "boss scene instantiates the dedicated EnemyActor subclass")
	if scene_instance != null:
		scene_instance.free()
	var host := RoomStub.new()
	host.layout = Layouts.build("BO01",9182)
	root.add_child(host)
	var boss = boss_script.new() if boss_script != null else null
	if boss == null:
		_check(false,"boss script constructs through the room's new() API")
		if registered_stub:
			Engine.unregister_singleton("Game")
			game_stub.free()
		host.queue_free()
		return
	boss.room = host
	boss.position = host.layout.boss_spawn
	_check(boss.configure_boss("BO01",1,9182), "room new/configure_boss integration API succeeds")
	host.enemies.add_child(boss)
	_check(boss.actor_kind == "boss" and boss.rank == "boss" and not boss.reward_enabled and boss.brain.get_script() == Brain, "boss node cannot enter ordinary reward or ordinary brain paths")
	boss.boss_phase_started(2,0.69)
	boss.boss_phase_started(2,0.68)
	boss.boss_phase_started(3,0.34)
	var requests: Array[Dictionary] = boss.take_reinforcement_requests()
	var status: Dictionary = boss.reinforcement_status()
	_check(requests.size() == 2 and status.requested_phases == [2,3], "each finite reinforcement wave can be drained exactly once")
	_check(int(status.count) <= int(status.cap) and int(status.threat) <= int(status.budget) and boss.take_reinforcement_requests().is_empty(), "reinforcement queue respects both limits and cannot double tick")
	var options: Dictionary = boss.reinforcement_spawn_options()
	_check(options.owner == boss and not options.reward_enabled, "reinforcements are owner-bound and award no gold/XP")
	var completions: Array[Dictionary] = []
	boss.completed.connect(func(_id: String, payload: Dictionary) -> void: completions.append(payload))
	boss.health.damage(boss.health.maximum)
	_check(completions.size() == 1 and bool(completions[0].get("complete",false)) and completions[0].get("boss_id","") == "BO01" and host.deaths == 1, "boss death emits completion and enters room cleanup exactly once")
	await process_frame
	host.queue_free()
	if registered_stub:
		Engine.unregister_singleton("Game")
		game_stub.free()
	elif started_run and is_instance_valid(game_host):
		game_host.finish_run("abandoned")

func _boss_arena_counter_contract(boss_script: Script) -> void:
	var arena_script: Script = load(AssetCatalog.resolve("res://scripts/gameplay/world/boss_arena.gd"))
	_check(arena_script != null, "real BossArena counter host loads")
	if arena_script == null:
		return
	for id: String in IDS:
		var host := RoomStub.new()
		host.layout = Layouts.build(id,3107)
		host.obstructions.assign(host.layout.obstructions)
		root.add_child(host)
		var boss = boss_script.new()
		boss.room = host
		boss.position = host.layout.boss_spawn
		boss.configure_boss(id,0,3107)
		host.enemies.add_child(boss)
		var arena: Node2D = arena_script.new()
		host.add_child(arena)
		arena.configure_boss_arena(host,host.layout,boss)
		var counter_id: String = str(host.layout.boss_counterplay[0].id)
		var accepted: bool = false
		if id in ["BO01", "BO03"]:
			host.player.position = host.layout.boss_counterplay[0].position
			accepted = bool(arena.interact(counter_id,host.player))
		else:
			var target: Node2D = arena.targets.get(counter_id)
			if is_instance_valid(target):
				target.take_damage(1000.0,&"primary",Vector2.RIGHT,{"original_basic":true,"equipment_eligible":true})
				accepted = not arena.targets.has(counter_id)
		var counters: Dictionary = boss.boss_brain.counter_snapshot()
		var consumed: bool = int(counters.disabled_lane) == 0 if id in ["BO01","BO03"] else (0 in counters.broken_roots if id == "BO02" else 0 in counters.broken_bells)
		_check(accepted and consumed, id + " real arena counter is consumed by its interact/attack action and reaches BossBrain")
		host.free()

func _simulation(id: String) -> Dictionary:
	var actor := ActorStub.new()
	actor.position = Vector2(1400,900)
	var victim := VictimStub.new()
	victim.position = Vector2(1820,930)
	var brain: RefCounted = Brain.new()
	brain.configure(Profiles.resolve(id,0),71237)
	return {"actor":actor,"victim":victim,"brain":brain}

func _dispose(sim: Dictionary) -> void:
	(sim.actor as Node).free()
	(sim.victim as Node).free()

func _advance_to_state(sim: Dictionary, wanted: StringName) -> Dictionary:
	for _step: int in 400:
		sim.brain.tick(sim.actor,0.02,sim.victim)
		if sim.brain.state_name() == wanted:
			return sim.brain.current_telegraph()
	return {}

func _advance_casts(sim: Dictionary, wanted: int) -> void:
	for _step: int in 1600:
		if sim.actor.casts.size() >= wanted:
			return
		sim.brain.tick(sim.actor,0.02,sim.victim)

func _advance_to_action(sim: Dictionary, wanted: String) -> Dictionary:
	for _step: int in 1800:
		sim.brain.tick(sim.actor,0.02,sim.victim)
		var telegraph: Dictionary = sim.brain.current_telegraph()
		if str(telegraph.get("action_id","")) == wanted:
			return telegraph
	return {}

func _geometry_is_executable(command: Dictionary) -> bool:
	var shape: String = str(command.get("shape",""))
	if shape == "line":
		return command.get("paths",[]).size() > 0 or (command.get("points",[]).size() >= 2 and float(command.get("width",0.0)) > 0.0)
	if shape == "ring":
		return command.has("ring_start") and command.has("ring_end") and float(command.ring_end) > float(command.ring_start)
	if shape in ["circle","cone"]:
		return float(command.get("radius",command.get("range",0.0))) > 0.0
	return false
