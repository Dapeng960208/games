extends SceneTree
## EnemyBrain acceptance; a stub actor integrates velocity and records commands.
## Frozen geometry is also checked against the real EnemySkillRuntime consumer.
## Run with tools/test.ps1 -Suite enemy_brain -SkipImport.
## No EnemyActor scene, navigation implementation, live Game run, or player save.

const Brain = preload("res://scripts/gameplay/monsters/enemy_brain.gd")
const SkillRuntime = preload("res://scripts/gameplay/monsters/enemy_skill_runtime.gd")
const STEP: float = 0.01
const EPSILON: float = STEP + 0.00001
const LEVELS: Array[int] = [1, 5, 10, 15]
const ACTIVE_TELL: Array[String] = ["telegraph", "locked"]
const ACTIONABLE_KINDS: Array[String] = ["melee", "projectile", "charge", "ground_area", "pull", "guard", "haste", "heal", "counter", "summon", "decoy", "utility"]
# These are commands/geometry consumed by the actor or skill layer. Deliberately
# exclude behavior_id, enemy_id, name, tier, mechanics, raw parameters, damage,
# health and path_mode: changing an identity label is not a new behavior.
const COMMAND_KEYS: Array[String] = [
	"kind", "shape", "origin", "direction", "target", "targets", "points",
	"range", "radius", "inner_radius", "angle", "width", "count",
	"spread_degrees", "speed", "projectile_angles", "projectile_radius",
	"pierce", "refraction_points", "duration", "lifetime", "tick_interval",
	"max_active_hazards", "max_count", "max_alive", "max_targets",
	"target_count", "max_receives", "charges", "hit_cap", "multiplier",
	"mode", "pull_distance", "distance", "repel", "require_corpse", "slow",
	"travel_distance", "arc_height", "arc_angle", "damage_along_path",
	"landing_shape", "action", "ring_gap_degrees", "safe_gap_degrees",
	"paths", "ring_start", "ring_end"
]

class ActorStub:
	extends Node2D
	var state: StringName = &"emerging"
	var state_time: float = 0.8
	var velocity: Vector2 = Vector2.ZERO
	var knockback: Vector2 = Vector2.ZERO
	var aim_direction: Vector2 = Vector2.RIGHT
	var alive: bool = true
	var room: Node2D
	var status: RefCounted
	var clock_seconds: float = 0.0
	var casts: Array[Dictionary] = []

	func is_alive() -> bool:
		return alive

	func cast_enemy_skill(skill: Dictionary) -> void:
		casts.append({"time": clock_seconds, "skill": skill.duplicate(true)})

class StatusStub:
	extends RefCounted
	var shield_value: float = 0.0

	func shield() -> float:
		return shield_value

class PropsStub:
	extends RefCounted
	var targets: Dictionary = {}
	var carrying: bool = false
	var in_shallow_pool: bool = false
	var returns: int = 0
	var requested_actions: Array[String] = []
	var requested_tags: Array[String] = []

	func target_for(_actor: Node2D, action: String) -> Dictionary:
		requested_actions.append(action)
		return targets.get(action, {"valid": false}).duplicate(true)

	func carried_by(_actor: Node2D) -> bool:
		return carrying

	func return_stolen(_actor: Node2D) -> void:
		if carrying:
			returns += 1
			carrying = false

	func is_in_tag(_point: Vector2, tag: String) -> bool:
		requested_tags.append(tag)
		return tag == "shallow_pool" and in_shallow_pool

class RoomStub:
	extends Node2D
	var enemy_props: RefCounted
	var last_sound_position: Vector2 = Vector2.ZERO
	var utility_requests: Array[String] = []

	# Matches the real room convenience wrapper, which deliberately exposes only
	# a point. Object-targeting brains must query enemy_props to preserve the ID.
	func enemy_utility_target(caster: Node2D, action: String) -> Vector2:
		utility_requests.append(action)
		if action == "last_player_sound":
			return last_sound_position
		var target: Dictionary = enemy_props.target_for(caster, action)
		return target.get("position", caster.position)

	func navigation_direction(origin: Vector2, target: Vector2, _radius: float) -> Vector2:
		return origin.direction_to(target)

	func has_line_of_sight(_origin: Vector2, _target: Vector2) -> bool:
		return true

	func blocked_fraction(_origin: Vector2, _target: Vector2, _radius: float) -> float:
		return 1.0

var checks: int = 0
var failures: int = 0
var profiles: Script
var catalog: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENEMY BRAIN FAIL: " + label)

func _run() -> void:
	for path: String in ["res://scripts/domain/combat/enemy_profiles.gd", "res://scripts/data/enemy_profiles.gd"]:
		if FileAccess.file_exists(AssetCatalog.resolve(path)):
			profiles = load(AssetCatalog.resolve(path)) as Script
			break
	_check(profiles != null, "EnemyProfiles resolver is available")
	if profiles == null:
		quit(1)
		return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://data/monsters/enemies.json")))
	_check(document is Dictionary, "ordinary enemy catalog parses")
	if not document is Dictionary:
		quit(1)
		return
	catalog = document.get("enemies", {})
	_check(catalog.size() == 54, "all 54 ordinary prototypes are represented")
	_all_prototypes_and_tiers()
	_lock_is_a_snapshot()
	_spawn_and_invalid_targets()
	_damage_during_spawn_is_safe()
	_single_use_bomber()
	_scene_object_targets()
	_socket_recharge_requires_empty_shield()
	_lifetime_heal_budget()
	_charge_wall_stops_combo()
	_shadow_stealth_requires_terrain_and_movement()
	_stolen_objects_return_after_damage()
	_last_sound_is_a_snapshot()
	_broken_pod_opens_recovery()
	_hatched_pod_restarts_exposure()
	_normalized_line_geometry()
	_normalized_projectile_paths()
	_normalized_ring_arcs()
	_produced_mechanic_parameters()
	_cover_rebuild_cooldown()
	_displaced_locked_charge_is_cancelled()
	print("ENEMY BRAIN TESTS: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func _profile(id: String, level: int) -> Dictionary:
	return profiles.call("resolve", id, level, "normal").duplicate(true)

func _simulation(profile: Dictionary, target_position: Vector2 = Vector2(130.0, 0.0)) -> Dictionary:
	var actor := ActorStub.new()
	var victim := ActorStub.new()
	root.add_child(actor)
	root.add_child(victim)
	victim.position = target_position
	var brain: RefCounted = Brain.new()
	brain.configure(profile)
	return {
		"brain": brain, "actor": actor, "victim": victim, "profile": profile,
		"time": 0.0, "seen_casts": 0, "casts": [], "warning": {},
		"phases": [], "motion": [], "recovery_seconds": 0.0, "recovery_windows": [],
		"saw_recovery": false, "brain_moved_actor": false, "lock_moved": false
	}

func _dispose(sim: Dictionary) -> void:
	(sim.actor as Node).free()
	if is_instance_valid(sim.victim):
		(sim.victim as Node).free()
	if sim.has("room") and is_instance_valid(sim.room):
		(sim.room as Node).free()

func _scene_simulation(profile: Dictionary, target_position: Vector2 = Vector2(130.0, 0.0)) -> Dictionary:
	var sim: Dictionary = _simulation(profile, target_position)
	var room := RoomStub.new()
	var props := PropsStub.new()
	room.enemy_props = props
	root.add_child(room)
	sim.actor.room = room
	sim.room = room
	sim.props = props
	return sim

func _until_cycle(sim: Dictionary, cycle_count: int, max_frames: int = 8000) -> void:
	for _frame: int in range(max_frames):
		_advance(sim)
		if int(sim.brain.cycle) >= cycle_count:
			return

func _commands(sim: Dictionary, kind: String, action: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cast: Dictionary in sim.casts:
		var skill: Dictionary = cast.skill
		if str(skill.get("kind", "")) == kind and (action.is_empty() or str(skill.get("action", "")) == action):
			result.append(skill)
	return result

func _runtime(sim: Dictionary) -> Node2D:
	var runtime: Node2D = SkillRuntime.new()
	sim.room.add_child(runtime)
	runtime.configure(sim.room)
	runtime.set_physics_process(false)
	return runtime

func _wait_for_lock(sim: Dictionary, kind: String, shape: String = "") -> Dictionary:
	for _frame: int in range(5000):
		_advance(sim)
		var tell: Dictionary = sim.brain.current_telegraph()
		if bool(tell.get("locked", false)) and str(tell.get("kind", "")) == kind and (shape.is_empty() or str(tell.get("shape", "")) == shape):
			return tell.duplicate(true)
	_check(false, str(sim.profile.enemy_id) + " reaches the requested locked geometry")
	return {}

func _next_cast(sim: Dictionary) -> Dictionary:
	var previous_count: int = (sim.casts as Array).size()
	for _frame: int in range(5000):
		_advance(sim)
		if (sim.casts as Array).size() > previous_count:
			return sim.casts[previous_count].skill
	_check(false, str(sim.profile.enemy_id) + " emits its locked command")
	return {}

func _advance(sim: Dictionary, delta: float = STEP) -> void:
	var actor: ActorStub = sim.actor
	var before: Vector2 = actor.position
	sim.time = float(sim.time) + delta
	actor.clock_seconds = float(sim.time)
	sim.brain.tick(actor, delta, sim.victim)
	if not actor.position.is_equal_approx(before):
		sim.brain_moved_actor = true
	# Attach the warning observed *before* this tick to each actual command. The
	# warning must exist over real ticks, not merely be advertised in a payload.
	while int(sim.seen_casts) < actor.casts.size():
		var cast: Dictionary = actor.casts[int(sim.seen_casts)].duplicate(true)
		cast.warning = (sim.warning as Dictionary).duplicate(true)
		(sim.casts as Array).append(cast)
		sim.seen_casts = int(sim.seen_casts) + 1
	if not actor.casts.is_empty() and is_equal_approx(float(actor.casts.back().time), float(sim.time)):
		sim.warning = {}
	var phase: String = str(actor.state)
	var telegraph: Dictionary = sim.brain.current_telegraph()
	if phase in ACTIVE_TELL and not telegraph.is_empty():
		if (sim.warning as Dictionary).is_empty() or int(sim.warning.get("stage", -1)) != int(telegraph.get("stage", -1)):
			sim.warning = {"started": float(sim.time), "locked_at": -1.0,
				"stage": int(telegraph.get("stage", -1)), "tell": telegraph.duplicate(true)}
		if bool(telegraph.get("locked", false)):
			if float(sim.warning.locked_at) < 0.0:
				sim.warning.locked_at = float(sim.time)
				sim.warning.locked_target = telegraph.get("target", Vector2.ZERO)
				sim.warning.locked_direction = telegraph.get("direction", Vector2.ZERO)
			elif telegraph.get("target", Vector2.ZERO) != sim.warning.locked_target or telegraph.get("direction", Vector2.ZERO) != sim.warning.locked_direction:
				sim.lock_moved = true
		elif float(sim.warning.locked_at) >= 0.0:
			# A briefly acquired lock cannot be credited as a continuous lock.
			sim.lock_moved = true
			sim.warning.locked_at = -1.0
	else:
		# A removed warning cannot be reused to satisfy a later attack's timing.
		sim.warning = {}
	var phase_changed: bool = (sim.phases as Array).is_empty() or str(sim.phases.back()) != phase
	if phase_changed:
		(sim.phases as Array).append(phase)
	if phase == "recovery":
		sim.saw_recovery = true
		sim.recovery_seconds = float(sim.recovery_seconds) + delta
		if phase_changed:
			(sim.recovery_windows as Array).append(0.0)
		var last_window: int = (sim.recovery_windows as Array).size() - 1
		sim.recovery_windows[last_window] = float(sim.recovery_windows[last_window]) + delta
	if phase in ["execute", "reposition"] and actor.velocity.length() > 0.01:
		var velocity := [phase, snappedf(actor.velocity.x, 0.1), snappedf(actor.velocity.y, 0.1)]
		var motion: Array = sim.motion
		if not motion.is_empty() and motion.back().slice(0, 3) == velocity:
			motion.back()[3] = snappedf(float(motion.back()[3]) + delta, STEP)
		else:
			velocity.append(snappedf(delta, STEP))
			motion.append(velocity)
	# Navigation/physics belongs to EnemyActor; the test supplies a collision-free
	# integration so approaches and authored sidesteps can finish naturally.
	actor.position += actor.velocity * delta

func _first_cycle(profile: Dictionary, cycle_count: int = 1) -> Dictionary:
	var sim: Dictionary = _simulation(profile)
	for _frame: int in range(2200):
		_advance(sim)
		if int(sim.brain.cycle) >= 1 and not sim.has("first_cycle_signature"):
			sim.first_cycle_signature = _fingerprint(sim)
		if int(sim.brain.cycle) >= cycle_count or str(sim.actor.state) == "spent":
			break
	return sim

func _neutralize_stat_growth(profile: Dictionary, baseline: Dictionary) -> void:
	# Keep each resolved tier's mechanics while eliminating ordinary level growth
	# as a possible reason that two traces differ.
	for key: String in ["max_hp", "hp", "damage", "move_speed", "speed", "armor", "attack_range"]:
		if baseline.has(key):
			profile[key] = baseline[key]
	for container: String in ["stats", "base_stats"]:
		if profile.get(container) is Dictionary and baseline.get(container) is Dictionary:
			for key: String in ["max_hp", "hp", "damage", "move_speed", "speed", "armor", "attack_range"]:
				if baseline[container].has(key):
					profile[container][key] = baseline[container][key]

func _canonical(value: Variant) -> Variant:
	if value is Node2D:
		return _canonical(value.position)
	if value is Object:
		# Resource/instance IDs never establish mechanical differences.
		return null
	if value is Vector2:
		return [snappedf(value.x, 0.01), snappedf(value.y, 0.01)]
	if value is float:
		return snappedf(value, 0.01)
	if value is Array or value is PackedVector2Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_canonical(item))
		return items
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			if str(key) in COMMAND_KEYS:
				result[str(key)] = _canonical(value[key])
		return result
	return value

func _fingerprint(sim: Dictionary) -> String:
	var commands: Array = []
	for cast: Dictionary in sim.casts:
		commands.append(_canonical(cast.skill))
	return JSON.stringify({"commands": commands, "motion": sim.motion,
		"phases": sim.phases, "recovery_seconds": snappedf(float(sim.recovery_seconds), 0.02)})

func _all_prototypes_and_tiers() -> void:
	var distinct: Dictionary = {}
	var multi_stage_count: int = 0
	for number: int in range(1, 37):
		var id: String = "M%02d" % number
		_check(catalog.has(id), id + " exists in the catalog")
		var baseline: Dictionary = _profile(id, 1)
		var preceding: String = ""
		for level: int in LEVELS:
			var profile: Dictionary = _profile(id, level)
			_neutralize_stat_growth(profile, baseline)
			# M03's authored movement trigger is after every second attack at tier 1;
			# observing three cycles distinguishes tier 3's after-every-attack route.
			var cycle_count: int = 3 if id == "M03" else 1
			var sim: Dictionary = _first_cycle(profile, cycle_count)
			var label: String = id + " level " + str(level)
			_check(not (sim.casts as Array).is_empty(), label + " executes a real skill command")
			_check(int(sim.brain.cycle) >= cycle_count or str(sim.actor.state) == "spent", label + " finishes every observed attack cycle")
			_check(not bool(sim.brain_moved_actor), label + " leaves position integration to the actor")
			_check(bool(sim.saw_recovery), label + " opens a visible recovery window")
			for window: float in sim.recovery_windows:
				_check(window + EPSILON >= 0.45, label + " each executed segment opens >= 0.45 seconds of recovery")
			_check(not bool(sim.lock_moved), label + " preserves its locked geometry")
			var stages: Dictionary = {}
			var previous_stage_cast: float = -100.0
			for cast: Dictionary in sim.casts:
				var command: Dictionary = cast.skill
				_check(str(command.get("kind", "")) in ACTIONABLE_KINDS, label + " emits a kind implemented by the skill runtime")
				_check(float(command.get("delay", 0.0)) == 0.0, label + " emits only the currently warned segment")
				var warning: Dictionary = cast.warning
				_check(not warning.is_empty(), label + " command is preceded by an observed warning")
				if warning.is_empty():
					continue
				var stage_key: String = str(warning.get("stage", -1)) + ":" + str(warning.started)
				if stages.has(stage_key):
					continue
				stages[stage_key] = true
				var minimum: float = maxf(0.55, float(catalog[id].get("minimum_tell_seconds", 0.55)))
				var shape: String = str(warning.tell.get("shape", ""))
				var kind: String = str(command.get("kind", ""))
				if kind == "ground_area" or (shape in ["circle", "ring", "area", "circles", "landing", "pool"] and kind not in ["guard", "haste", "heal", "counter", "summon", "decoy", "utility"]):
					minimum = maxf(minimum, 0.8)
				_check(float(cast.time) - float(warning.started) + EPSILON >= minimum,
					label + " stage " + str(warning.stage) + " has its full tell >= " + str(minimum))
				_check(float(warning.locked_at) >= 0.0 and float(cast.time) - float(warning.locked_at) + EPSILON >= 0.4,
					label + " stage " + str(warning.stage) + " waits >= 0.4 seconds after lock")
				_check(float(warning.started) + EPSILON >= previous_stage_cast,
					label + " each combo segment starts a new warning after the preceding cast")
				_check(float(cast.time) + EPSILON >= 0.8, label + " cannot damage during birth grace")
				previous_stage_cast = float(cast.time)
			if stages.size() > 1:
				multi_stage_count += 1
			var combo_count: int = int(profile.get("attack_parameters", {}).get("combo_count", 1))
			_check(stages.size() >= combo_count, label + " executes every authored combo segment with its own warning")
			var signature: String = _fingerprint(sim)
			if level == 1:
				var base_signature: String = str(sim.get("first_cycle_signature", signature))
				_check(not distinct.has(base_signature), id + " differs in execution from " + str(distinct.get(base_signature, "none")) + " without identity fields")
				distinct[base_signature] = id
			else:
				_check(signature != preceding, label + " consumes the new tier in commands, geometry, motion, sequence or recovery")
			preceding = signature
			_dispose(sim)
	_check(distinct.size() == 36, "all 36 base execution patterns are mechanically distinct")
	_check(multi_stage_count > 36, "combo timing coverage includes base combos and higher tiers")

func _lock_is_a_snapshot() -> void:
	var sim: Dictionary = _simulation(_profile("M03", 1), Vector2(280.0, 0.0))
	for _frame: int in range(1000):
		_advance(sim)
		var tell: Dictionary = sim.brain.current_telegraph()
		if bool(tell.get("locked", false)):
			break
	var locked: Dictionary = sim.brain.current_telegraph().duplicate(true)
	_check(bool(locked.get("locked", false)), "M03 reaches an observable locked aim")
	if bool(locked.get("locked", false)):
		var locked_direction: Vector2 = locked.get("direction", Vector2.ZERO)
		var locked_target: Vector2 = locked.get("target", Vector2.ZERO)
		(sim.victim as Node2D).position = Vector2(0.0, 280.0)
		for _frame: int in range(200):
			_advance(sim)
			var current: Dictionary = sim.brain.current_telegraph()
			if bool(current.get("locked", false)):
				_check((current.get("direction", Vector2.ZERO) as Vector2).is_equal_approx(locked_direction), "M03 locked aim does not turn toward moved victim")
				_check((current.get("target", Vector2.ZERO) as Vector2).is_equal_approx(locked_target), "M03 locked point does not follow moved victim")
			if not (sim.casts as Array).is_empty():
				break
		_check(not (sim.casts as Array).is_empty(), "M03 fires after its lock delay")
		if not (sim.casts as Array).is_empty():
			var fired: Dictionary = sim.casts[0].skill
			_check((fired.get("direction", Vector2.ZERO) as Vector2).is_equal_approx(locked_direction), "M03 emitted shot uses the locked direction")
			_check(not bool(sim.lock_moved), "M03 retains the complete snapshot until execution")
	_dispose(sim)

func _spawn_and_invalid_targets() -> void:
	for id: String in ["M01", "M03", "M11", "M36"]:
		var sim: Dictionary = _simulation(_profile(id, 15), Vector2(1.0, 0.0))
		for _frame: int in range(79):
			_advance(sim)
		_check((sim.casts as Array).is_empty(), id + " birth grace remains harmless for 0.79 seconds at point blank")
		_check((sim.actor as Node2D).position.is_equal_approx(Vector2.ZERO), id + " birth grace does not drive approach movement")
		_dispose(sim)
	var sim: Dictionary = _simulation(_profile("M01", 1))
	var victim: ActorStub = sim.victim
	sim.victim = null
	for _frame: int in range(300):
		_advance(sim)
	_check((sim.casts as Array).is_empty(), "null victim produces no cast")
	_check((sim.actor.velocity as Vector2).is_zero_approx(), "null victim leaves zero velocity")
	sim.victim = victim
	victim.alive = false
	for _frame: int in range(300):
		_advance(sim)
	_check((sim.casts as Array).is_empty(), "dead victim produces no cast")
	victim.free()
	# The public signature accepts Node2D or null. Godot rejects a freed Object
	# before entering a typed method, so the caller must clear that reference.
	sim.victim = null
	_dispose(sim)
	var dead: Dictionary = _simulation(_profile("M36", 15), Vector2(1.0, 0.0))
	dead.actor.alive = false
	for _frame: int in range(300):
		_advance(dead)
	_check((dead.casts as Array).is_empty(), "dead actor cannot execute or explode")
	_check((dead.actor.velocity as Vector2).is_zero_approx(), "dead actor receives no movement")
	dead.brain.tick(null, STEP, dead.victim)
	dead.brain.on_damaged(null, {})
	_check(true, "null actor is accepted safely by tick and on_damaged")
	_dispose(dead)

func _damage_during_spawn_is_safe() -> void:
	for id: String in ["M08", "M25", "M26", "M34", "M36"]:
		var sim: Dictionary = _simulation(_profile(id, 15), Vector2(1.0, 0.0))
		for _frame: int in range(79):
			sim.brain.on_damaged(sim.actor, {"damage": 1.0, "source_position": Vector2.RIGHT * 20.0})
			_advance(sim)
		_check((sim.casts as Array).is_empty(), id + " taking damage cannot bypass birth grace")
		_dispose(sim)

func _single_use_bomber() -> void:
	for level: int in LEVELS:
		var sim: Dictionary = _first_cycle(_profile("M36", level))
		var detonations: int = 0
		for cast: Dictionary in sim.casts:
			if str(cast.skill.get("kind", "")) == "ground_area":
				detonations += 1
		_check(detonations == 1, "M36 level " + str(level) + " detonates exactly once across its full sequence")
		var casts_before: int = (sim.casts as Array).size()
		for _frame: int in range(600):
			_advance(sim)
		_check((sim.casts as Array).size() == casts_before and str(sim.actor.state) == "spent", "M36 level " + str(level) + " remains spent after detonation")
		_dispose(sim)
	var countdown: Dictionary = _simulation(_profile("M36", 15), Vector2(40.0, 0.0))
	for _frame: int in range(500):
		_advance(countdown)
		if str(countdown.actor.state) == "locked":
			break
	_check(str(countdown.actor.state) == "locked" and (countdown.casts as Array).is_empty(), "M36 reaches a harmless locked countdown")
	countdown.actor.alive = false
	for _frame: int in range(400):
		_advance(countdown)
	_check((countdown.casts as Array).is_empty(), "destroying M36 during its countdown cancels all detonation commands")
	_dispose(countdown)

func _scene_object_targets() -> void:
	var sim: Dictionary = _scene_simulation(_profile("M16", 1), Vector2(110.0, 0.0))
	var loot_point := Vector2(0.0, 70.0)
	var nest_point := Vector2(-260.0, -40.0)
	sim.props.targets = {
		"steal_quest_object": {"valid": true, "id": "loot_a", "position": loot_point},
		"return_to_nest": {"valid": true, "id": "nest_a", "position": nest_point}
	}
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) == "telegraph":
			break
	var tell: Dictionary = sim.brain.current_telegraph()
	_check(str(tell.get("action", "")) == "steal_quest_object", "M16 begins a room-object interaction")
	_check(str(tell.get("target_id", "")) == "loot_a", "M16 resolves the prop's actual identity")
	_check((tell.get("target", Vector2.ZERO) as Vector2).is_equal_approx(loot_point), "M16 utility points at loot instead of the victim")
	# The prop index can change while a tell is displayed. The committed object
	# and point stay fixed; ordinary attacks still use the separate victim aim.
	sim.props.targets["steal_quest_object"] = {"valid": true, "id": "loot_b", "position": Vector2(0.0, -75.0)}
	for _frame: int in range(600):
		_advance(sim)
		if not _commands(sim, "utility", "steal_quest_object").is_empty():
			break
	var utilities: Array[Dictionary] = _commands(sim, "utility", "steal_quest_object")
	_check(utilities.size() == 1, "M16 emits one locked pickup command")
	if not utilities.is_empty():
		_check(str(utilities[0].get("target_id", "")) == "loot_a", "M16 pickup retains its warned prop identity")
		_check((utilities[0].get("target", Vector2.ZERO) as Vector2).is_equal_approx(loot_point), "M16 pickup retains its warned prop point")
	sim.props.carrying = true
	_until_cycle(sim, 1)
	var melee: Array[Dictionary] = _commands(sim, "melee")
	_check(not melee.is_empty(), "M16 completes the ordinary attack in its sequence")
	if not melee.is_empty():
		_check((melee[0].get("direction", Vector2.ZERO) as Vector2).is_equal_approx(Vector2.RIGHT), "M16 ordinary attack aims at the victim, independently from loot")
	var before: Vector2 = sim.actor.position
	_advance(sim)
	var return_velocity: Vector2 = sim.actor.velocity
	_check(return_velocity.length() > 0.0 and return_velocity.normalized().is_equal_approx(before.direction_to(nest_point)), "M16 carrying an object moves toward its nest after the current cycle")
	_check("return_to_nest" in sim.props.requested_actions, "M16 asks scene props for its authored nest")
	_dispose(sim)

func _socket_recharge_requires_empty_shield() -> void:
	for shield_amount: float in [25.0, 0.0]:
		var sim: Dictionary = _scene_simulation(_profile("M25", 1), Vector2(60.0, 0.0))
		var status := StatusStub.new()
		status.shield_value = shield_amount
		sim.actor.status = status
		var socket_point := Vector2(0.0, 50.0)
		sim.props.targets = {"socket_recharge": {"valid": true, "id": "socket_a", "position": socket_point}}
		for _frame: int in range(600):
			_advance(sim)
			if str(sim.actor.state) == "locked":
				break
		if is_zero_approx(shield_amount):
			var tell: Dictionary = sim.brain.current_telegraph()
			_check(str(tell.get("target_id", "")) == "socket_a", "M25 empty shield locks the actual socket identity")
			_check((tell.get("target", Vector2.ZERO) as Vector2).is_equal_approx(socket_point), "M25 empty shield locks the actual socket point")
			sim.props.targets["socket_recharge"] = {"valid": true, "id": "socket_b", "position": Vector2(0.0, -50.0)}
		_until_cycle(sim, 1)
		var recharges: Array[Dictionary] = _commands(sim, "utility", "socket_recharge")
		if shield_amount > 0.0:
			_check(recharges.is_empty(), "M25 with remaining shield never emits socket_recharge")
		else:
			_check(recharges.size() == 1, "M25 with no shield emits its warned recharge")
			if not recharges.is_empty():
				_check(str(recharges[0].get("target_id", "")) == "socket_a" and (recharges[0].get("target", Vector2.ZERO) as Vector2).is_equal_approx(socket_point), "M25 recharge preserves the locked socket after scene props change")
		_dispose(sim)
	var depleted_mid_tell: Dictionary = _scene_simulation(_profile("M25", 1), Vector2(60.0, 0.0))
	var changing_status := StatusStub.new()
	changing_status.shield_value = 25.0
	depleted_mid_tell.actor.status = changing_status
	var actual_socket := Vector2(0.0, 50.0)
	depleted_mid_tell.props.targets = {"socket_recharge": {"valid": true, "id": "socket_live", "position": actual_socket}}
	for _frame: int in range(600):
		_advance(depleted_mid_tell)
		if str(depleted_mid_tell.actor.state) == "telegraph":
			break
	changing_status.shield_value = 0.0
	_until_cycle(depleted_mid_tell, 2)
	var recharge_count: int = 0
	for cast: Dictionary in depleted_mid_tell.casts:
		if str(cast.skill.get("action", "")) != "socket_recharge":
			continue
		recharge_count += 1
		_check(str(cast.skill.get("target_id", "")) == "socket_live" and (cast.skill.get("target", Vector2.ZERO) as Vector2).is_equal_approx(actual_socket), "M25 shield depleted mid-tell never recharges at a victim fallback point")
		var warning: Dictionary = cast.get("warning", {}).get("tell", {})
		_check(str(warning.get("target_id", "")) == "socket_live" and (warning.get("target", Vector2.ZERO) as Vector2).is_equal_approx(actual_socket), "M25 shield depleted mid-tell warns the actual socket before recharge")
	_check(recharge_count > 0, "M25 eventually recharges from a valid socket after mid-tell shield depletion")
	_dispose(depleted_mid_tell)

func _lifetime_heal_budget() -> void:
	for level: int in LEVELS:
		var sim: Dictionary = _simulation(_profile("M17", level))
		_until_cycle(sim, 6)
		_check(int(sim.brain.cycle) >= 6, "M17 level " + str(level) + " completes more than five cycles")
		var heals: Array[Dictionary] = _commands(sim, "heal")
		_check(heals.size() == 2, "M17 level " + str(level) + " consumes at most its two lifetime healing charges")
		_check(not _commands(sim, "melee").is_empty(), "M17 level " + str(level) + " keeps acting after exhausting healing")
		_dispose(sim)

func _charge_wall_stops_combo() -> void:
	var profile: Dictionary = _profile("M02", 15)
	# Raise the floor above normal recovery so this tests consumption of the wall
	# stun parameter, rather than accidentally passing on ordinary recovery alone.
	profile.attack_parameters.wall_stun_seconds = 2.35
	var sim: Dictionary = _simulation(profile, Vector2(190.0, 0.0))
	for _frame: int in range(600):
		_advance(sim)
		if not _commands(sim, "charge").is_empty():
			break
	_check(str(sim.actor.state) == "execute", "M02 reaches its first charge execution")
	sim.actor.set_meta("enemy_charge_wall_stop", true)
	_until_cycle(sim, 1)
	_check(int(sim.brain.cycle) == 1, "M02 wall collision finishes the interrupted cycle")
	_check(_commands(sim, "charge").size() == 1, "M02 wall collision cancels every remaining combo charge")
	_check((sim.recovery_windows as Array).size() == 1, "M02 interrupted combo has one recovery window")
	if not (sim.recovery_windows as Array).is_empty():
		_check(float(sim.recovery_windows[0]) + EPSILON >= 2.35, "M02 wall collision recovery consumes wall_stun_seconds")
	_check(not sim.actor.has_meta("enemy_charge_wall_stop"), "M02 consumes the collision signal exactly once")
	_dispose(sim)

func _shadow_stealth_requires_terrain_and_movement() -> void:
	var chase: Dictionary = _scene_simulation(_profile("M32", 1), Vector2(1000.0, 0.0))
	for _frame: int in range(85):
		_advance(chase)
	_check(str(chase.actor.state) == "chase", "M32 terrain test reaches approach movement")
	_check(not bool(chase.actor.get_meta("enemy_shadow_stealth", false)), "M32 outside marked terrain cannot enter stealth")
	chase.props.in_shallow_pool = true
	_advance(chase)
	_check(bool(chase.actor.get_meta("enemy_shadow_stealth", false)), "M32 inside shallow pool is visibly shadowed while chasing")
	chase.props.in_shallow_pool = false
	_advance(chase)
	_check(not bool(chase.actor.get_meta("enemy_shadow_stealth", false)), "M32 loses stealth immediately after leaving marked terrain")
	chase.props.in_shallow_pool = true
	_advance(chase)
	chase.actor.alive = false
	_advance(chase)
	_check(not bool(chase.actor.get_meta("enemy_shadow_stealth", false)), "M32 cannot retain movement stealth after death")
	_dispose(chase)
	var idle: Dictionary = _scene_simulation(_profile("M32", 1), Vector2(1000.0, 0.0))
	idle.props.in_shallow_pool = true
	for _frame: int in range(85):
		_advance(idle)
	idle.victim.alive = false
	_advance(idle)
	_check(str(idle.actor.state) == "idle" and not bool(idle.actor.get_meta("enemy_shadow_stealth", false)), "M32 clears movement stealth when its victim becomes invalid")
	_dispose(idle)
	var profile: Dictionary = _profile("M32", 10)
	profile.attack_parameters.sidestep_distance = 48.0
	var sim: Dictionary = _scene_simulation(profile, Vector2(170.0, 0.0))
	sim.props.in_shallow_pool = true
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) == "reposition":
			_advance(sim)
			break
	_check(str(sim.actor.state) == "reposition" and bool(sim.actor.get_meta("enemy_shadow_stealth", false)), "M32 marked-terrain reposition keeps its visible stealth state")
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) == "telegraph":
			break
	_check(str(sim.actor.state) == "telegraph", "M32 exposes its leap telegraph after reposition")
	_check(not bool(sim.actor.get_meta("enemy_shadow_stealth", false)), "M32 telegraph ends stealth immediately, even within marked terrain")
	var tell: Dictionary = sim.brain.current_telegraph()
	_check(bool(tell.get("terrain_stealth", false)), "M32 leap records that its departure terrain allows a shadow path")
	_check(not (sim.props.requested_tags as Array).is_empty() and "shallow_pool" in sim.props.requested_tags, "M32 queries the actual scene terrain tag")
	_dispose(sim)

func _stolen_objects_return_after_damage() -> void:
	for id: String in ["M16", "M35"]:
		for level: int in [1, 15]:
			var profile: Dictionary = _profile(id, level)
			var sim: Dictionary = _scene_simulation(profile, Vector2(60.0, 0.0))
			var action: String = "steal_quest_object" if id == "M16" else "steal_scene_lamp"
			sim.props.targets = {
				action: {"valid": true, "id": "recoverable_prop", "position": Vector2(0.0, 45.0)},
				"return_to_nest": {"valid": true, "id": "nest", "position": Vector2.ZERO}
			}
			sim.props.carrying = true
			for _frame: int in range(85):
				_advance(sim)
			var threshold: float = float(profile.max_hp) * (0.12 if level == 15 else 0.25)
			var label: String = id + " level " + str(level)
			sim.brain.on_damaged(sim.actor, {"damage": threshold * 0.49, "kind": "primary"})
			sim.brain.on_damaged(sim.actor, {"damage": threshold * 0.50, "kind": "primary"})
			_check(bool(sim.props.carrying) and int(sim.props.returns) == 0, label + " keeps its object below the accumulated release threshold")
			sim.brain.on_damaged(sim.actor, {"damage": threshold * 0.02, "kind": "primary"})
			var released_at: float = float(sim.time)
			_check(not bool(sim.props.carrying) and int(sim.props.returns) == 1, label + " returns the carried object exactly once when cumulative damage reaches its threshold")
			_check(str(sim.actor.state) == "recovery" and float(sim.actor.state_time) >= 1.0, label + " returning an object opens a recovery window")
			_check((sim.brain.current_telegraph() as Dictionary).is_empty(), label + " returning an object cancels its pending warning")
			var steals_before: int = _commands(sim, "utility", action).size()
			for _frame: int in range(299):
				_advance(sim)
			_check(_commands(sim, "utility", action).size() == steals_before, label + " cannot steal again during the first 2.99 seconds after release")
			for _frame: int in range(2000):
				_advance(sim)
				if _commands(sim, "utility", action).size() > steals_before:
					break
			var subsequent_casts: Array[Dictionary] = []
			for cast: Dictionary in sim.casts:
				if str(cast.skill.get("action", "")) == action and float(cast.time) > released_at:
					subsequent_casts.append(cast)
			_check(not subsequent_casts.is_empty(), label + " can begin another warned theft after the finite cooldown")
			if not subsequent_casts.is_empty():
				_check(float(subsequent_casts[0].time) - released_at + EPSILON >= 3.0, label + " does not emit a theft before the full three-second cooldown")
			_check(int(sim.props.returns) == 1, label + " does not repeatedly return an already released object")
			_dispose(sim)

func _last_sound_is_a_snapshot() -> void:
	var sim: Dictionary = _scene_simulation(_profile("M28", 1), Vector2(120.0, 0.0))
	var old_sound := Vector2(0.0, 100.0)
	sim.room.last_sound_position = old_sound
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) == "telegraph":
			break
	var initial: Dictionary = sim.brain.current_telegraph()
	_check(str(initial.get("kind", "")) == "charge", "M28 displays a charge toward its last heard sound")
	_check((initial.get("target", Vector2.ZERO) as Vector2).is_equal_approx(old_sound), "M28 uses the room's old sound point rather than the current victim")
	_check("last_player_sound" in sim.room.utility_requests, "M28 obtains sound history through the room hook even when props exist")
	_check("last_player_sound" not in sim.props.requested_actions, "M28 does not substitute a props lookup for sound history")
	sim.victim.position = Vector2(-120.0, 0.0)
	sim.room.last_sound_position = Vector2(80.0, -100.0)
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) == "locked":
			break
	var locked: Dictionary = sim.brain.current_telegraph()
	_check(bool(locked.get("locked", false)), "M28 visibly locks its sound-based charge")
	_check((locked.get("target", Vector2.ZERO) as Vector2).is_equal_approx(old_sound), "M28 retains the old sound point when newer sound and victim positions change")
	sim.victim.position = Vector2(180.0, 160.0)
	for _frame: int in range(600):
		_advance(sim)
		if not _commands(sim, "charge").is_empty():
			break
	var charges: Array[Dictionary] = _commands(sim, "charge")
	_check(charges.size() == 1, "M28 emits the one warned charge")
	if not charges.is_empty():
		_check((charges[0].get("direction", Vector2.ZERO) as Vector2).is_equal_approx(Vector2.DOWN), "M28 executes along the locked sound direction instead of tracking the victim")
		_check((charges[0].get("target", Vector2.ZERO) as Vector2).is_equal_approx(old_sound), "M28 emitted charge ends at the original sound point")
	_dispose(sim)

func _broken_pod_opens_recovery() -> void:
	var sim: Dictionary = _simulation(_profile("M12", 1))
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) == "locked":
			break
	_check(str(sim.actor.state) == "locked" and (sim.casts as Array).is_empty(), "M12 broken-pod fixture reaches a harmless locked summon")
	sim.actor.set_meta("enemy_pod_broken", true)
	_advance(sim)
	_check(not sim.actor.has_meta("enemy_pod_broken"), "M12 consumes a broken-pod notification once")
	_check(str(sim.actor.state) == "recovery" and float(sim.actor.state_time) + EPSILON >= 1.6, "M12 broken pod immediately opens a >= 1.6-second recovery")
	_check((sim.brain.current_telegraph() as Dictionary).is_empty(), "M12 broken pod cancels its pending summon warning")
	_until_cycle(sim, 1)
	_check((sim.casts as Array).is_empty(), "M12 cannot hatch or attack while recovering from pod destruction")
	_check((sim.recovery_windows as Array).size() == 1 and float(sim.recovery_windows[0]) + EPSILON >= 1.6, "M12 pod-break recovery lasts the complete observed 1.6 seconds")
	_dispose(sim)

func _hatched_pod_restarts_exposure() -> void:
	var sim: Dictionary = _simulation(_profile("M12", 15))
	var locked: Dictionary = _wait_for_lock(sim, "summon")
	if locked.is_empty():
		_dispose(sim)
		return
	var command: Dictionary = _next_cast(sim)
	var exposure: float = float(command.get("exposure_after_hatch", 0.0))
	_check(is_equal_approx(exposure, 1.6), "M12 tier four produces an explicit 1.6-second post-hatch exposure")
	for _frame: int in range(int(round(float(command.get("hatch_delay", 1.6)) / STEP))):
		_advance(sim)
	_check(str(sim.actor.state) == "recovery" and float(sim.actor.state_time) < 0.3, "M12 hatch fixture reaches the end of its original pre-hatch recovery")
	var prior_cast_count: int = (sim.casts as Array).size()
	sim.actor.set_meta("enemy_pod_hatched", exposure)
	_advance(sim)
	var exposure_started: float = float(sim.time)
	_check(not sim.actor.has_meta("enemy_pod_hatched"), "M12 consumes a successful hatch exposure signal once")
	_check(str(sim.actor.state) == "recovery" and float(sim.actor.state_time) + EPSILON >= exposure, "M12 successful hatch starts a fresh full exposure instead of reusing elapsed recovery")
	_check((sim.brain.current_telegraph() as Dictionary).is_empty(), "M12 hatch exposure clears any queued attack geometry")
	for _frame: int in range(600):
		_advance(sim)
		if str(sim.actor.state) != "recovery":
			break
	_check(float(sim.time) - exposure_started + EPSILON >= exposure, "M12 stays exposed for the complete duration after the hatch signal")
	_check((sim.casts as Array).size() == prior_cast_count, "M12 cannot cast during its new post-hatch exposure")
	_dispose(sim)

func _normalized_line_geometry() -> void:
	for id: String in ["M22", "M33"]:
		for level: int in [5, 15]:
			var sim: Dictionary = _scene_simulation(_profile(id, level), Vector2(69.0, -11.0))
			sim.actor.position = Vector2(37.0, -29.0)
			var locked: Dictionary = _wait_for_lock(sim, "ground_area", "line")
			if locked.is_empty():
				_dispose(sim)
				continue
			var label: String = id + " level " + str(level)
			var origin: Vector2 = locked.get("origin", Vector2.ZERO)
			var direction: Vector2 = locked.get("direction", Vector2.RIGHT)
			var endpoint: Vector2 = origin + direction.normalized() * float(locked.get("range", 0.0))
			var points: Array = locked.get("points", [])
			_check(points.size() == 2, label + " line warning produces exactly two final points")
			if points.size() == 2:
				_check((points[0] as Vector2).is_equal_approx(origin) and (points[1] as Vector2).is_equal_approx(endpoint), label + " line warning spans the full range from its final offset origin")
			_check((locked.get("target", Vector2.ZERO) as Vector2).is_equal_approx(endpoint) and (locked.get("target_position", Vector2.ZERO) as Vector2).is_equal_approx(endpoint), label + " all line endpoints agree after normalization")
			var offset: Array = locked.get("origin_offset", [])
			_check(offset.size() == 2 and Vector2(float(offset[0]), float(offset[1])).length() > 0.0, label + " fixture exercises a real authored origin offset")
			if offset.size() == 2:
				var offset_origin: Vector2 = sim.actor.position + Vector2(float(offset[0]), float(offset[1])).rotated(direction.angle())
				_check(origin.is_equal_approx(offset_origin), label + " applies the origin offset before building its line")
			var tail: Vector2 = origin.lerp(endpoint, 0.90)
			_check(tail.distance_to(origin) > (sim.victim.position as Vector2).distance_to(origin), label + " tail probe lies beyond the player's old near target")
			sim.victim.position = tail
			var command: Dictionary = _next_cast(sim)
			_check(command.get("points", []) == points, label + " actor cast preserves the exact locked line points")
			var runtime: Node2D = _runtime(sim)
			_check(runtime.shape_contains(command, tail, 0.0), label + " runtime hits the already-drawn tail after the player moves there")
			var mismatch: Dictionary = command.duplicate(true)
			mismatch["range"] = 1.0
			mismatch["target"] = origin + direction
			_check(runtime.shape_contains(mismatch, tail, 0.0), label + " frozen line points override stale scalar range and target")
			_check(not runtime.shape_contains(mismatch, tail + direction.orthogonal() * 100.0, 0.0), label + " runtime does not hit outside the drawn line width")
			_dispose(sim)

func _normalized_projectile_paths() -> void:
	for level: int in [5, 15]:
		var sim: Dictionary = _scene_simulation(_profile("M31", level), Vector2(280.0, 95.0))
		var locked: Dictionary = _wait_for_lock(sim, "projectile")
		if locked.is_empty():
			_dispose(sim)
			continue
		var expected_count: int = 2 if level == 5 else 3
		var paths: Array = locked.get("paths", [])
		var base_points: Array = locked.get("points", [])
		var angles: Array = sim.profile.attack_parameters.projectile_angles
		var origin: Vector2 = locked.origin
		var label: String = "M31 level " + str(level)
		_check(paths.size() == expected_count and base_points.size() == 3, label + " warns every complete one-refraction path")
		for index: int in range(paths.size()):
			var path: Array = paths[index]
			_check(path.size() == 3, label + " projectile " + str(index) + " has origin, bend and endpoint")
			if path.size() != 3 or base_points.size() != 3:
				continue
			for point_index: int in range(3):
				var expected: Vector2 = origin + ((base_points[point_index] as Vector2) - origin).rotated(deg_to_rad(float(angles[index])))
				_check((path[point_index] as Vector2).is_equal_approx(expected), label + " rotates the complete path for projectile " + str(index))
			_check(absf((path[0] as Vector2).distance_to(path[1]) - float(locked.range) * 0.55) < 0.01 and absf((path[1] as Vector2).distance_to(path[2]) - float(locked.range) * 0.45) < 0.01, label + " full path retains both authored leg lengths")
		sim.victim.position = Vector2(-150.0, 210.0)
		var command: Dictionary = _next_cast(sim)
		_check(command.get("paths", []) == paths, label + " actor cast preserves every locked projectile path")
		var mismatch: Dictionary = command.duplicate(true)
		mismatch["range"] = 7.0
		mismatch["projectile_angles"] = [90.0, -90.0, 180.0]
		mismatch["spread_degrees"] = 180.0
		var runtime: Node2D = _runtime(sim)
		runtime.emit_skill(sim.actor, mismatch)
		_check(runtime.projectiles.size() == expected_count, label + " runtime emits the warned number of complete paths")
		for index: int in range(mini(paths.size(), runtime.projectiles.size())):
			var path: Array = paths[index]
			var shot: Dictionary = runtime.projectiles[index]
			_check((shot.position as Vector2).is_equal_approx(path[0]) and shot.waypoints == path.slice(1), label + " runtime projectile origin and waypoints equal its frozen path")
			_check((shot.direction as Vector2).is_equal_approx((path[0] as Vector2).direction_to(path[1])), label + " runtime direction follows its first path segment despite stale angles")
			var length: float = (path[0] as Vector2).distance_to(path[1]) + (path[1] as Vector2).distance_to(path[2])
			_check(absf(float(shot.distance_left) - length) < 0.01, label + " runtime travel budget follows the full path despite stale range")
		_dispose(sim)

func _normalized_ring_arcs() -> void:
	for level: int in LEVELS:
		var sim: Dictionary = _scene_simulation(_profile("M36", level), Vector2(70.0, 35.0))
		var locked: Dictionary = _wait_for_lock(sim, "ground_area", "ring")
		if locked.is_empty():
			_dispose(sim)
			continue
		var gap: float = deg_to_rad(float(sim.profile.attack_parameters.get("ring_gap_degrees", 0.0)))
		var start: float = float(locked.get("ring_start", 0.0))
		var end: float = float(locked.get("ring_end", 0.0))
		var label: String = "M36 level " + str(level)
		_check(absf(end - start - (TAU - gap)) < 0.00001, label + " normalized ring arc exactly subtracts its authored safe gap")
		var origin: Vector2 = locked.origin
		var radius: float = float(locked.radius) * 0.65
		var gap_midpoint: Vector2 = origin + Vector2.from_angle((locked.direction as Vector2).angle()) * radius
		var arc_midpoint: Vector2 = origin + Vector2.from_angle((start + end) * 0.5) * radius
		sim.victim.position = Vector2(-190.0, -160.0)
		var command: Dictionary = _next_cast(sim)
		_check(float(command.get("ring_start", -100.0)) == start and float(command.get("ring_end", -100.0)) == end, label + " actor cast keeps the locked absolute arc angles")
		var runtime: Node2D = _runtime(sim)
		_check(runtime.shape_contains(command, arc_midpoint, 0.0), label + " runtime hits the midpoint of the drawn damage arc")
		_check(runtime.shape_contains(command, gap_midpoint, 0.0) == is_zero_approx(gap), label + " runtime respects a safe gap only in the tiers that author one")
		var mismatch: Dictionary = command.duplicate(true)
		mismatch["ring_gap_degrees"] = 180.0 if is_zero_approx(gap) else 0.0
		mismatch["direction"] = -(command.direction as Vector2)
		_check(runtime.shape_contains(mismatch, arc_midpoint, 0.0), label + " absolute ring arc overrides changed direction and gap metadata")
		_check(runtime.shape_contains(mismatch, gap_midpoint, 0.0) == is_zero_approx(gap), label + " stale gap metadata cannot alter the frozen safe region")
		_dispose(sim)

func _produced_mechanic_parameters() -> void:
	for id: String in ["M08", "M25", "M18", "M23", "M11"]:
		for level: int in LEVELS:
			var profile: Dictionary = _profile(id, level)
			var sim: Dictionary = _first_cycle(profile)
			var label: String = id + " level " + str(level)
			match id:
				"M08":
					var guards: Array[Dictionary] = _commands(sim, "guard")
					_check(not guards.is_empty(), label + " emits its directional guard")
					for command: Dictionary in guards:
						_check(absf(float(command.get("shield_ratio", -1.0)) - minf(0.35, float(profile.attack_parameters.guard_ratio))) < 0.00001, label + " sends the capped authored guard ratio to runtime")
				"M25":
					var sockets: Array[Dictionary] = _commands(sim, "utility", "socket_recharge")
					_check(not sockets.is_empty(), label + " produces a recharge command")
					for command: Dictionary in sockets:
						_check(is_equal_approx(float(command.get("guard_ratio", -1.0)), 0.3), label + " produces its authored 0.3 socket guard ratio")
				"M18":
					var bites: Array[Dictionary] = _commands(sim, "utility", "bite_breakable_wall")
					_check(not bites.is_empty(), label + " produces a breakable wall bite")
					for command: Dictionary in bites:
						_check(int(command.get("breakable_wall_cap", -1)) == 1, label + " limits wall destruction to one authored wall")
				"M23":
					var utilities: Array[Dictionary] = _commands(sim, "utility", "polarity_displacement")
					var pulls: Array[Dictionary] = _commands(sim, "pull", "polarity_displacement")
					_check(not utilities.is_empty() and pulls.size() == utilities.size(), label + " emits a derived pull for every polarity action")
					for command: Dictionary in utilities + pulls:
						_check(is_equal_approx(float(command.get("displacement_cooldown", -1.0)), float(profile.attack_parameters.displacement_cooldown)), label + " carries displacement cooldown into utility and derived pull")
				"M11":
					var lobs: Array[Dictionary] = _commands(sim, "ground_area")
					var expected_lobs: int = 1 if level < 5 else (2 if level < 10 else 3)
					_check(lobs.size() == expected_lobs, label + " emits the learned single, paired or triple individually warned landings")
					for command: Dictionary in lobs:
						_check(bool(command.get("lob", false)), label + " marks every landing as a lob")
			_dispose(sim)

func _cover_casts(sim: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cast: Dictionary in sim.casts:
		if str(cast.skill.get("kind", "")) == "guard" and str(cast.skill.get("mode", "")) == "cover":
			result.append(cast)
	return result

func _cover_rebuild_cooldown() -> void:
	for level: int in [1, 15]:
		var profile: Dictionary = _profile("M06", level)
		var cooldown: float = float(profile.attack_parameters.cover_rebuild_seconds)
		var label: String = "M06 level " + str(level)
		_check(is_equal_approx(cooldown, 8.0 if level == 1 else 10.0), label + " fixture retains its authored rebuild interval")
		var baseline: Dictionary = _simulation(profile)
		for _frame: int in range(12000):
			_advance(baseline)
			if _cover_casts(baseline).size() >= 3:
				break
		var deployments: Array[Dictionary] = _cover_casts(baseline)
		_check(deployments.size() >= 3, label + " repeatedly deploys finite cover rather than permanently stopping")
		for index: int in range(1, deployments.size()):
			_check(float(deployments[index].time) - float(deployments[index - 1].time) + EPSILON >= cooldown, label + " actual cover commands respect the full rebuild interval")
		_dispose(baseline)
		var broken: Dictionary = _simulation(profile)
		var queued_rebuild: bool = false
		for _frame: int in range(12000):
			_advance(broken)
			var tell: Dictionary = broken.brain.current_telegraph()
			if _cover_casts(broken).size() == 1 and bool(tell.get("locked", false)) and str(tell.get("kind", "")) == "guard" and str(tell.get("mode", "")) == "cover":
				queued_rebuild = true
				break
		_check(queued_rebuild, label + " reaches a pending rebuild for the break-signal regression")
		# Inject the room's one-shot break event while a rebuild is already queued;
		# ignoring the event would emit that cover within the next lock interval.
		broken.actor.set_meta("enemy_cover_broken", true)
		_advance(broken)
		var consumed_at: float = float(broken.time)
		_check(not broken.actor.has_meta("enemy_cover_broken"), label + " consumes the cover break event once")
		for _frame: int in range(int(round(cooldown / STEP)) - 1):
			_advance(broken)
		_check(_cover_casts(broken).size() == 1, label + " breaking cover restarts the whole cooldown and invalidates an already queued rebuild")
		for _frame: int in range(12000):
			_advance(broken)
			if _cover_casts(broken).size() > 1:
				break
		var after_break: Array[Dictionary] = _cover_casts(broken)
		_check(after_break.size() >= 2, label + " eventually rebuilds after a cover break")
		if after_break.size() >= 2:
			_check(float(after_break[1].time) - consumed_at + EPSILON >= cooldown, label + " actual rebuilt cover waits a full interval from break consumption")
		_dispose(broken)

func _displaced_locked_charge_is_cancelled() -> void:
	for id: String in ["M02", "M04", "M05", "M14", "M15", "M21", "M28", "M32"]:
		var sim: Dictionary = _simulation(_profile(id, 15), Vector2(120.0, 0.0))
		var locked: Dictionary = _wait_for_lock(sim, "charge")
		if locked.is_empty():
			_dispose(sim)
			continue
		var casts_before: int = (sim.casts as Array).size()
		var cycle_before: int = int(sim.brain.cycle)
		sim.actor.position += Vector2(30.0, 0.0)
		_advance(sim)
		_check((sim.casts as Array).size() == casts_before, id + " displacement after lock cannot emit a shifted charge")
		_check((sim.brain.current_telegraph() as Dictionary).is_empty(), id + " displacement removes the stale locked path")
		_check(str(sim.actor.state) == "recovery" and float(sim.actor.state_time) + EPSILON >= 0.45, id + " displacement opens a safe recovery window")
		_until_cycle(sim, cycle_before + 1)
		_check(int(sim.brain.cycle) == cycle_before + 1 and (sim.casts as Array).size() == casts_before, id + " displacement cancels the remainder of the old charge combo")
		_dispose(sim)
	var pending: Dictionary = _simulation(_profile("M02", 15), Vector2(120.0, 0.0))
	var locked: Dictionary = _wait_for_lock(pending, "charge")
	if locked.is_empty():
		_dispose(pending)
		return
	var origin: Vector2 = pending.actor.position
	var prior_casts: int = (pending.casts as Array).size()
	pending.actor.knockback = Vector2(12.0, 0.0)
	_advance(pending)
	_check((pending.actor.position as Vector2).is_equal_approx(origin), "M02 pending-knockback fixture has not yet moved the actor")
	_check((pending.casts as Array).size() == prior_casts and (pending.brain.current_telegraph() as Dictionary).is_empty(), "M02 pending knockback cancels locked charge before position integration")
	_check(str(pending.actor.state) == "recovery" and float(pending.actor.state_time) + EPSILON >= 0.45, "M02 pending knockback creates a safe recovery window")
	pending.actor.knockback = Vector2.ZERO
	_until_cycle(pending, 1)
	_check((pending.casts as Array).size() == prior_casts, "M02 clearing pending knockback does not revive the old combo")
	_dispose(pending)
