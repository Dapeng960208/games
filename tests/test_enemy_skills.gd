extends SceneTree
## Enemy commands run against real scene nodes and deterministic swept geometry.
## Only the isolated test profile may be used by the real-player checks.

const HealthScript = preload("res://scripts/combat/health.gd")

class ActorFixture extends Node2D:
	var room: Node2D
	var health = HealthScript.new()
	var state: StringName = &"chase"
	var enemy_id: String = "fixture_enemy"
	var actor_kind: String = "enemy"
	var zone_index: int = 0
	var protected_dash: bool = false
	var contact_damage: float = 20.0
	var armor: float = 15.0
	var knockback: Vector2 = Vector2.ZERO
	var collision_radius: float = 12.0
	var navigation_radius: float = 12.0
	var kind: String = "node"
	var hits: Array[Dictionary] = []
	var statuses: Array[Dictionary] = []
	var accepts_damage: bool = true

	func _init() -> void:
		add_child(health)
		health.reset(100.0)

	func is_alive() -> bool:
		return not health.dead and not is_queued_for_deletion()

	func dash_protected() -> bool:
		return protected_dash

	func receive_damage(amount: float, origin: Vector2) -> bool:
		if not accepts_damage or not is_alive():
			return false
		hits.append({"amount":amount,"origin":origin})
		return health.damage(amount)

	func receive_enemy_status(command: Dictionary) -> bool:
		statuses.append(command.duplicate(true))
		return true

	func take_damage(amount: float, _kind: StringName, _direction: Vector2 = Vector2.ZERO) -> bool:
		return health.damage(amount)

class RoomFixtureBase extends Node2D:
	const ARENA = Rect2(0, 0, 1000, 800)
	var player: Node2D
	var enemy_props: Node2D
	var enemies: Node2D = Node2D.new()
	var obstructions: Array[Rect2] = []
	var layout_id: String = "enemy_skill_fixture"
	var telemetry: Dictionary = {"player_hits":0,"dashes":0}
	var spawned: Array[Node2D] = []
	var anchors: Array[Node2D] = []
	var summon_budget: int = 20
	var move_calls: int = 0

	func _init() -> void:
		add_child(enemies)
		process_mode = Node.PROCESS_MODE_DISABLED

	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void:
		pass

	func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
		return blocked_fraction(from, to) >= 1.0

	func valid_ground(at: Vector2, radius: float = 0.0) -> bool:
		if not ARENA.grow(-radius).has_point(at):
			return false
		for wall: Rect2 in obstructions:
			if wall.grow(radius).has_point(at):
				return false
		return true

	func blocked_fraction(from: Vector2, to: Vector2, radius: float = 0.0) -> float:
		var fraction: float = 1.0
		var segment: Vector2 = to - from
		if segment.is_zero_approx():
			return 1.0 if valid_ground(from, radius) else 0.0
		var allowed: Rect2 = ARENA.grow(-radius)
		for axis: int in range(2):
			if segment[axis] > 0.0:
				fraction = minf(fraction, (allowed.end[axis] - from[axis]) / segment[axis])
			elif segment[axis] < 0.0:
				fraction = minf(fraction, (allowed.position[axis] - from[axis]) / segment[axis])
		for wall: Rect2 in obstructions:
			var box: Rect2 = wall.grow(radius)
			if box.has_point(from):
				return 0.0
			var corners: Array[Vector2] = [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]
			for edge: int in range(4):
				var crossing: Variant = Geometry2D.segment_intersects_segment(from,to,corners[edge],corners[(edge + 1) % 4])
				if crossing != null:
					fraction = minf(fraction, maxf(0.0, from.distance_to(crossing) / segment.length() - 0.00001))
		return clampf(fraction,0.0,1.0)

	func move_actor(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
		move_calls += 1
		return from + displacement * blocked_fraction(from,from + displacement,radius)

	func spawn_enemy_summon(caster: Node2D, prototype_id: String, at: Vector2) -> Node2D:
		var living: int = 0
		for enemy: Node2D in enemies.get_children():
			if enemy.is_alive():
				living += 1
		if living >= 18 or summon_budget <= 0 or not valid_ground(at,12.0):
			return null
		var summoned: ActorFixture = ActorFixture.new()
		summoned.room = self
		summoned.enemy_id = prototype_id
		summoned.position = at
		summoned.set_meta("summon_owner",caster.get_instance_id())
		enemies.add_child(summoned)
		spawned.append(summoned)
		summon_budget -= 1
		return summoned

	func spawn_enemy_skill_anchor(caster: Node2D, at: Vector2, hit_points: float, _anchor_kind: String = "") -> Node2D:
		var anchor: Node2D = spawn_enemy_summon(caster,"fixture_anchor",at)
		if anchor != null:
			anchor.health.reset(hit_points)
			anchor.set_meta("enemy_skill_anchor",true)
			anchors.append(anchor)
		return anchor

class RoomFixture extends RoomFixtureBase:
	var recipients: Array[Node2D] = []

	func enemy_skill_targets() -> Array:
		return recipients

var runtime_script: Script
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ENEMY SKILL FAIL: " + description)

func _near(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) < 0.001,description + " (actual=" + str(actual) + ", expected=" + str(expected) + ")")

func _room() -> RoomFixture:
	var room := RoomFixture.new()
	root.add_child(room)
	return room

func _actor(room: Node2D, at: Vector2, friendly: bool = false) -> ActorFixture:
	var actor := ActorFixture.new()
	actor.room = room
	actor.position = at
	if friendly:
		room.enemies.add_child(actor)
	else:
		room.add_child(actor)
		if room is RoomFixture:
			room.recipients.append(actor)
	return actor

func _runtime(room: Node2D) -> Node2D:
	var runtime: Node2D = runtime_script.new()
	room.add_child(runtime)
	runtime.configure(room)
	return runtime

func _command(kind: String, caster: Node2D, target: Vector2, extra: Dictionary = {}) -> Dictionary:
	var command: Dictionary = {"kind":kind,"origin":caster.position,"target":target,"direction":caster.position.direction_to(target),"range":500.0,"radius":6.0,"angle":PI / 2.0,"damage_multiplier":1.0}
	command.merge(extra,true)
	return command

func _run() -> void:
	runtime_script = load("res://scripts/combat/enemy_skill_runtime.gd")
	_check(runtime_script != null and runtime_script.can_instantiate(),"enemy runtime loads and can instantiate")
	if runtime_script == null or not runtime_script.can_instantiate():
		quit(1)
		return
	_projectile_sweeps()
	_fallback_targets()
	_melee_geometry()
	_ring_geometry()
	_delayed_time_budget()
	_lifecycle()
	_motion_walls()
	_support_limits()
	_counter_limits()
	_screen_guards()
	_refraction_walls()
	_breakable_lines()
	_weld_cover()
	_anchor_capacity()
	_charge_timing_and_landing()
	_wall_cancelled_landings()
	_interrupted_motion()
	_real_pull_cooldowns()
	_scan_marks()
	_refraction_spread()
	_hatching_pods()
	_failed_hatch_exposure()
	_pod_disarm_debuff()
	_lob_impacts()
	_summon_limits()
	_real_player_damage()
	print("ENEMY_SKILL_TESTS checks=" + str(checks) + " failures=" + str(failures))
	quit(0 if failures == 0 else 1)

func _projectile_sweeps() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,200),true)
	var player := _actor(room,Vector2(250,200))
	room.player = player
	var deployment := _actor(room,Vector2(250,400))
	deployment.add_to_group("hero_deployments")
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":4000.0,"damage_multiplier":1.5,"status":"chill"}))
	runtime.emit_skill(caster,_command("projectile",caster,deployment.position,{"speed":4000.0}))
	_check(player.hits.is_empty() and deployment.hits.is_empty(),"projectile creation never applies synchronous damage")
	_check(runtime.active_effect_count() >= 2,"projectiles remain scheduled until advanced")
	runtime.advance(0.12)
	_near(player.health.current,70.0,"high-speed swept projectile hits player between frame endpoints")
	_check(player.statuses.size() == 1 and player.statuses[0].id == "chill","string status command becomes accepted-hit status payload")
	_near(deployment.health.current,80.0,"high-speed swept projectile hits deployment between frame endpoints")
	runtime.advance(0.3)
	_check(player.hits.size() == 1 and deployment.hits.size() == 1,"one projectile cannot hit the same recipient again")
	room.free()

	room = _room()
	caster = _actor(room,Vector2(100,200),true)
	player = _actor(room,Vector2(350,200))
	room.player = player
	room.obstructions = [Rect2(220,100,20,200)]
	runtime = _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":8000.0}))
	runtime.advance(0.1)
	_check(player.hits.is_empty(),"high-speed projectile stops at wall before target")
	_check(runtime.active_effect_count() == 0,"wall collision retires projectile")
	room.free()

func _fallback_targets() -> void:
	var room := RoomFixtureBase.new()
	root.add_child(room)
	var caster := _actor(room,Vector2(100,200),true)
	var player := _actor(room,Vector2(200,200))
	room.player = player
	var deployment := _actor(room,Vector2(200,400))
	deployment.add_to_group("hero_deployments")
	var other_room := _room()
	var unrelated := _actor(other_room,Vector2(150,200))
	unrelated.add_to_group("hero_deployments")
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":4000.0}))
	runtime.emit_skill(caster,_command("projectile",caster,deployment.position,{"speed":4000.0}))
	runtime.advance(0.15)
	_check(player.hits.size() == 1 and deployment.hits.size() == 1,"fallback targets include room player and live deployment")
	_check(unrelated.hits.is_empty(),"deployment from another room is never a hostile target")
	room.free()
	other_room.free()

func _melee_geometry() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(300,300),true)
	var front := _actor(room,Vector2(365,300))
	var behind := _actor(room,Vector2(245,300))
	var flank := _actor(room,Vector2(315,380))
	var far := _actor(room,Vector2(450,300))
	room.player = front
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("melee",caster,Vector2(400,300),{"range":100.0,"angle":PI / 2.0}))
	_check(front.hits.size() == 1,"melee cone hits a recipient in front")
	_check(behind.hits.is_empty() and flank.hits.is_empty(),"melee cone excludes rear and flank recipients")
	_check(far.hits.is_empty(),"melee cone respects its range")
	front.hits.clear()
	room.obstructions = [Rect2(330,200,10,200)]
	runtime.emit_skill(caster,_command("melee",caster,Vector2(400,300),{"range":100.0,"angle":PI / 2.0}))
	_check(front.hits.is_empty(),"melee cannot damage through wall")
	room.free()

func _lifecycle() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,200),true)
	var player := _actor(room,Vector2(170,200))
	room.player = player
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":100.0,"delay":0.5}))
	_check(player.hits.is_empty(),"explicit delayed melee does not resolve during emission")
	runtime.advance(0.2)
	_check(player.hits.is_empty(),"delayed melee does not resolve before due time")
	caster.health.damage(100.0)
	runtime.advance(1.0)
	_check(player.hits.is_empty() and runtime.active_effect_count() == 0,"caster death cancels outstanding delayed damage")
	caster.health.reset(100.0)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":100.0}))
	paused = true
	runtime.advance(5.0)
	_check(player.hits.is_empty() and runtime.active_effect_count() > 0,"explicit advance honors scene pause")
	paused = false
	runtime.advance(1.0)
	_check(player.hits.size() == 1,"paused projectile resumes from remaining travel")
	player.hits.clear()
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":100.0,"delay":0.5}))
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":100.0}))
	runtime.cancel_owner(caster)
	_check(runtime.active_effect_count() == 0,"cancel_owner removes delayed and traveling effects")
	runtime.advance(2.0)
	_check(player.hits.is_empty(),"cancelled skills cannot damage later")
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":100.0,"delay":0.5}))
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":100.0}))
	runtime.emit_skill(caster,_command("ground_area",caster,player.position,{"radius":100.0,"duration":3.0}))
	runtime.emit_skill(caster,_command("charge",caster,Vector2(400,200),{"range":300.0,"duration":1.0}))
	_check(runtime.has_motion(caster),"charge owns caster motion while scheduled")
	runtime.reset_room()
	_check(runtime.active_effect_count() == 0 and not runtime.has_motion(caster),"room reset clears effects and caster motion ownership")
	runtime.advance(2.0)
	_check(player.hits.is_empty(),"room reset prevents late damage from old room")
	_near(caster.position.x,100.0,"room reset prevents old charge from moving caster")
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":100.0,"delay":0.5}))
	caster.free()
	runtime.advance(1.0)
	_check(player.hits.is_empty() and runtime.active_effect_count() == 0,"freed caster cannot leave stale-reference delayed damage")
	room.free()

func _delayed_time_budget() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,200),true)
	var player := _actor(room,Vector2(150,200))
	room.player = player
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":100.0,"delay":0.9}))
	runtime.advance(1.0)
	_check(player.hits.is_empty(),"delayed projectile only travels leftover frame time after becoming due")
	runtime.advance(0.5)
	_check(player.hits.size() == 1,"delayed projectile completes its remaining travel on later advance")
	room.free()

func _ring_geometry() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,100),true)
	var center := _actor(room,Vector2(400,400))
	var annulus := _actor(room,Vector2(470,400))
	var outside := _actor(room,Vector2(540,400))
	var rejecting := _actor(room,Vector2(400,470))
	rejecting.accepts_damage = false
	room.player = annulus
	var runtime := _runtime(room)
	var command: Dictionary = _command("ground_area",caster,Vector2(400,400),{"shape":"ring","inner_radius":45.0,"radius":100.0,"duration":0.5,"tick_interval":0.35,"delay":0.2,"status":{"id":"slow","magnitude":0.25,"duration":0.6}})
	runtime.emit_skill(caster,command)
	command.target = Vector2(700,700)
	command.status.id = "changed_after_emission"
	caster.position = Vector2(200,100)
	runtime.advance(0.19)
	_check(annulus.hits.is_empty(),"delayed ground ring does not hit during its warning")
	runtime.advance(0.2)
	_check(annulus.hits.is_empty(),"lasting ground ring waits for first periodic tick")
	runtime.advance(0.17)
	_check(annulus.hits.size() == 1,"ring strikes annulus at frozen target after first tick")
	_check(center.hits.is_empty(),"ring preserves its safe center")
	_check(outside.hits.is_empty(),"ring excludes recipients beyond outer edge")
	_check(annulus.statuses.size() == 1 and annulus.statuses[0].id == "slow","accepted damage receives frozen status payload")
	_check(rejecting.statuses.is_empty(),"rejected damage does not bypass immunity with status")
	runtime.advance(1.0)
	_check(annulus.hits.size() == 1,"short-lived ring has no extra tick after expiry")
	_check(runtime.active_effect_count() == 0,"ground ring lifetime ends without lingering effects")
	room.free()

func _motion_walls() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,200),true)
	var player := _actor(room,Vector2(350,200))
	room.player = player
	room.obstructions = [Rect2(220,100,20,200)]
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("charge",caster,Vector2(500,200),{"range":400.0,"radius":16.0,"speed":2000.0,"duration":0.4}))
	runtime.advance(0.4)
	_check(caster.position.x > 100.0 and caster.position.x <= 208.01,"charge moves forward but stops its body at wall")
	_check(room.move_calls > 0,"charge uses room actor collision movement")
	_check(bool(caster.get_meta("enemy_charge_wall_stop",false)),"charge collision records a real wall-stop outcome")
	_check(player.hits.is_empty(),"charge cannot damage a recipient behind wall")
	room.free()

	room = _room()
	caster = _actor(room,Vector2(100,200),true)
	player = _actor(room,Vector2(350,200))
	room.player = player
	runtime = _runtime(room)
	# The line of sight clears this wall, while the physical recipient's radius
	# meets its corner. A center-only pull would incorrectly pass through it.
	room.obstructions = [Rect2(260,207,15,50)]
	runtime.emit_skill(caster,_command("pull",caster,player.position,{"shape":"circle","range":400.0,"radius":400.0,"pull_distance":100.0,"damage_multiplier":0.0}))
	_check(player.position.x < 350.0 and player.position.x >= 286.99,"pull respects recipient body radius beside a wall")
	_check(room.move_calls > 0,"pull uses room actor collision movement")
	room.free()

func _support_limits() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(200,300),true)
	var allies: Array[ActorFixture] = []
	for index: int in range(4):
		var ally := _actor(room,Vector2(240 + 20 * index,300),true)
		ally.enemy_id = "fixture_ally_" + str(index)
		ally.health.current = 25.0
		allies.append(ally)
	var far := _actor(room,Vector2(800,300),true)
	far.health.current = 25.0
	var runtime := _runtime(room)
	var heal: Dictionary = _command("heal",caster,caster.position,{"amount":20.0,"radius":160.0,"max_targets":2,"max_receives":2})
	runtime.emit_skill(caster,heal)
	var changed: int = 0
	for ally: ActorFixture in allies:
		if ally.health.current > 25.0:
			changed += 1
	_check(changed == 2,"healing honors per-cast recipient limit")
	for index: int in range(8):
		runtime.emit_skill(caster,heal)
	for ally: ActorFixture in allies:
		_check(ally.health.current <= 55.001,"healing respects two-receive and fifteen-percent caps")
		_check(ally.health.current <= ally.health.maximum,"healing cannot exceed maximum health")
	_near(far.health.current,25.0,"healing does not affect allies outside support radius")
	var guard: Dictionary = _command("guard",caster,caster.position,{"amount":30.0,"radius":160.0,"duration":0.5})
	runtime.emit_skill(caster,guard)
	var guarded: float = runtime.filter_incoming_damage(allies[0],100.0,&"primary",Vector2.LEFT)
	_check(guarded >= 0.0 and guarded < 100.0,"guard reduces incoming damage for nearby ally")
	runtime.emit_skill(caster,guard)
	var refreshed: float = runtime.filter_incoming_damage(allies[0],100.0,&"primary",Vector2.LEFT)
	_check(refreshed >= guarded - 0.001,"repeated guard refresh cannot compound damage reduction")
	var haste: Dictionary = _command("haste",caster,caster.position,{"multiplier":1.3,"radius":160.0,"duration":0.5})
	for index: int in range(6):
		runtime.emit_skill(caster,haste)
	var multiplier: float = runtime.movement_multiplier(allies[0])
	_check(multiplier > 1.0 and multiplier <= 1.35,"repeated haste stays inside bounded movement bonus")
	_near(runtime.movement_multiplier(far),1.0,"haste respects support radius")
	runtime.advance(0.6)
	_near(runtime.filter_incoming_damage(allies[0],100.0,&"primary",Vector2.LEFT),100.0,"guard expires on runtime time")
	_near(runtime.movement_multiplier(allies[0]),1.0,"haste expires on runtime time")
	runtime.emit_skill(caster,guard)
	runtime.emit_skill(caster,haste)
	runtime.reset_room()
	_near(runtime.filter_incoming_damage(allies[0],100.0,&"primary",Vector2.LEFT),100.0,"room reset clears guard modifier")
	_near(runtime.movement_multiplier(allies[0]),1.0,"room reset clears haste modifier")
	room.free()

func _summon_limits() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(200,200),true)
	var player := _actor(room,Vector2(260,200))
	room.player = player
	var runtime := _runtime(room)
	var summon: Dictionary = _command("summon",caster,Vector2(250,250),{"enemy_id":"fixture_summon","count":4,"max_alive":2,"radius":40.0})
	for index: int in range(5):
		runtime.emit_skill(caster,summon)
	_check(player.hits.is_empty(),"summoning never applies synchronous spawn damage")
	runtime.advance(1.0)
	_check(room.spawned.size() > 0 and room.spawned.size() <= 2,"summon spam respects per-owner living summon cap")
	_check(room.summon_budget == 20 - room.spawned.size(),"summons consume the room helper budget once per successful spawn")
	_check(player.hits.is_empty(),"summons have no hidden direct hit during runtime advance")
	room.free()

	room = _room()
	caster = _actor(room,Vector2(200,200),true)
	for index: int in range(16):
		_actor(room,Vector2(100 + index * 20,500),true)
	runtime = _runtime(room)
	summon = _command("summon",caster,Vector2(250,250),{"enemy_id":"fixture_summon","count":5,"max_alive":5,"radius":40.0})
	runtime.emit_skill(caster,summon)
	runtime.advance(1.0)
	_check(room.enemies.get_child_count() == 18 and room.spawned.size() == 1,"summon request respects shared 18-enemy room cap")
	room.free()

func _counter_limits() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(200,300),true)
	var player := _actor(room,Vector2(270,300))
	room.player = player
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("counter",caster,player.position,{"duration":3.0,"range":120.0,"hit_cap":3}))
	_near(runtime.filter_incoming_damage(caster,0.0,&"primary",Vector2.LEFT),0.0,"zero incoming damage remains zero during counter")
	for index: int in range(2):
		_near(runtime.filter_incoming_damage(caster,10.0,&"primary",Vector2.LEFT),10.0,"counter counting does not secretly absorb incoming damage")
	runtime.advance(0.4)
	_check(player.hits.is_empty(),"zero-damage input never consumes one of the three counter hits")
	runtime.filter_incoming_damage(caster,10.0,&"primary",Vector2.LEFT)
	_check(player.hits.is_empty(),"reaching counter cap schedules retaliation without synchronous damage")
	runtime.advance(0.94)
	_check(player.hits.is_empty(),"counter retaliation preserves its reaction delay")
	runtime.advance(0.02)
	_check(player.hits.size() == 1,"third positive hit releases one delayed counterattack")
	for index: int in range(8):
		runtime.filter_incoming_damage(caster,10.0,&"primary",Vector2.LEFT)
	runtime.advance(1.0)
	_check(player.hits.size() == 1,"spent counter cannot release extra retaliations from later incoming hits")
	runtime.emit_skill(caster,_command("counter",caster,player.position,{"duration":3.0,"range":120.0,"hit_cap":1}))
	runtime.filter_incoming_damage(caster,10.0,&"primary",Vector2.LEFT)
	caster.health.damage(100.0)
	runtime.advance(1.0)
	_check(player.hits.size() == 1,"caster death cancels counter retaliation waiting to resolve")
	room.free()

func _screen_guards() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(200,300),true)
	var ally := _actor(room,Vector2(230,300),true)
	ally.enemy_id = "fixture_ally"
	var runtime := _runtime(room)
	var screen: Dictionary = _command("guard",caster,Vector2(400,300),{"mode":"screen","duration":0.5,"radius":200.0,"charges":2})
	runtime.emit_skill(caster,screen)
	_near(runtime.filter_incoming_damage(caster,20.0,&"q",Vector2.LEFT),20.0,"screen lets direct skill damage pass")
	_near(runtime.filter_incoming_damage(caster,20.0,&"primary",Vector2.RIGHT),20.0,"screen lets rear incoming projectile pass")
	_near(runtime.filter_incoming_damage(caster,20.0,&"primary",Vector2.ZERO),20.0,"screen cannot invent front direction for an undirected hit")
	_near(runtime.filter_incoming_damage(ally,20.0,&"primary",Vector2.LEFT),20.0,"personal screen does not grant a neighboring ally free charges")
	_near(runtime.filter_incoming_damage(caster,0.0,&"primary",Vector2.LEFT),0.0,"zero damage does not spend a screen charge")
	_near(runtime.filter_incoming_damage(caster,20.0,&"primary",Vector2.LEFT),0.0,"screen blocks first front primary projectile")
	_near(runtime.filter_incoming_damage(caster,20.0,&"child",Vector2.LEFT),0.0,"screen blocks second front child projectile")
	_near(runtime.filter_incoming_damage(caster,20.0,&"primary",Vector2.LEFT),20.0,"screen has finite charges after two blocked projectiles")
	runtime.emit_skill(caster,screen)
	runtime.advance(0.6)
	_near(runtime.filter_incoming_damage(caster,20.0,&"primary",Vector2.LEFT),20.0,"unspent screen charges expire with the effect")
	room.free()

func _refraction_walls() -> void:
	var walls: Array = [[Rect2(235,240,30,100)],[Rect2(165,190,20,20)],[Rect2(315,190,20,20)]]
	var descriptions: Array[String] = ["one-refraction projectile reaches target around a wall on the direct chord","first refraction leg cannot cross wall","second refraction leg cannot cross wall"]
	for index: int in range(walls.size()):
		var room := _room()
		var caster := _actor(room,Vector2(100,300),true)
		var player := _actor(room,Vector2(400,300))
		room.player = player
		room.obstructions.assign(walls[index])
		var runtime := _runtime(room)
		runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":1000.0,"range":500.0,"lifetime":2.0,"refraction_points":[Vector2(250,100)]}))
		_check(player.hits.is_empty(),"refraction projectile never resolves damage during creation")
		runtime.advance(0.5)
		_check(player.hits.size() == (1 if index == 0 else 0),descriptions[index])
		_check(runtime.active_effect_count() == 0,"refraction projectile ends after hit or wall contact")
		room.free()
	var room := _room()
	var caster := _actor(room,Vector2(100,300),true)
	var player := _actor(room,Vector2(400,300))
	var extra_bend := _actor(room,Vector2(250,600))
	room.player = player
	room.obstructions = [Rect2(235,240,30,100)]
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":1000.0,"range":500.0,"lifetime":2.0,"refraction_points":[Vector2(250,100),extra_bend.position,Vector2(800,600)]}))
	runtime.advance(0.25)
	_check(player.hits.is_empty(),"reaching the one bend alone does not instantly damage the final target")
	runtime.advance(0.25)
	_check(player.hits.size() == 1 and extra_bend.hits.is_empty(),"extra authored bend points cannot extend a one-refraction skill into an unbounded path")
	room.free()

	room = _room()
	caster = _actor(room,Vector2(100,200),true)
	player = _actor(room,Vector2(125,200))
	room.player = player
	runtime = _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,player.position,{"speed":100.0,"range":100.0,"lifetime":0.2}))
	runtime.advance(1.0)
	_check(player.hits.size() == 1,"projectile sweeps the live portion of a frame before lifetime expires")
	room.free()

func _breakable_lines() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,300),true)
	caster.enemy_id = "M33"
	var player := _actor(room,Vector2(200,300))
	room.player = player
	var runtime := _runtime(room)
	var line: Dictionary = _command("ground_area",caster,Vector2(300,300),{"shape":"line","breakable":true,"range":200.0,"width":16.0,"radius":16.0,"duration":2.0,"tick_interval":0.35,"anchor_health":24.0,"damage_multiplier":0.0,"status":{"id":"slow","magnitude":0.25,"duration":0.6}})
	runtime.emit_skill(caster,line)
	_check(room.anchors.size() == 1,"M33 line creates a real damageable endpoint node")
	if room.anchors.size() != 1:
		room.free()
		return
	var endpoint: Node2D = room.anchors[0]
	_check(endpoint.get_meta("enemy_skill_anchor_kind","") == "hazard_endpoint","M33 endpoint is identified as a hazard anchor")
	_near(endpoint.health.current,24.0,"M33 endpoint has finite authored health")
	_check(endpoint.position.distance_to(Vector2(300,300)) < 0.01,"M33 endpoint sits at the real line end")
	_check(player.statuses.is_empty(),"creating endpoint never synchronously applies line status")
	runtime.advance(0.36)
	_check(player.statuses.size() == 1 and player.statuses[0].id == "slow","live M33 line applies slow through the recipient status API")
	endpoint.take_damage(24.0,&"primary",Vector2.LEFT)
	_check(not endpoint.is_alive(),"ordinary direct damage can destroy M33 endpoint")
	runtime.advance(0.36)
	_check(player.statuses.size() == 1,"destroyed endpoint removes line before its next status tick")
	_check(runtime.active_effect_count() == 0,"destroyed endpoint leaves no active M33 hazard")
	for index: int in range(3):
		runtime.emit_skill(caster,line)
	var living_endpoints: int = 0
	for anchor: Node2D in room.anchors:
		if is_instance_valid(anchor) and anchor.is_alive():
			living_endpoints += 1
	_check(living_endpoints == 2,"M33 replacement preserves at most two live breakable lines")
	runtime.cancel_owner(caster)
	living_endpoints = 0
	for anchor: Node2D in room.anchors:
		if is_instance_valid(anchor) and anchor.is_alive():
			living_endpoints += 1
	_check(living_endpoints == 0 and runtime.active_effect_count() == 0,"cancelling M33 owner removes both hazard lines and their endpoints")
	room.free()

func _weld_cover() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(200,300),true)
	caster.enemy_id = "M06"
	var first := _actor(room,Vector2(180,300),true)
	first.enemy_id = "first_covered_ally"
	var second := _actor(room,Vector2(180,330),true)
	second.enemy_id = "second_covered_ally"
	var forward := _actor(room,Vector2(300,300),true)
	forward.enemy_id = "forward_ally"
	var flank := _actor(room,Vector2(180,420),true)
	flank.enemy_id = "flank_ally"
	var runtime := _runtime(room)
	var cover: Dictionary = _command("guard",caster,Vector2(400,300),{"mode":"cover","amount":30.0,"radius":200.0,"duration":3.0,"max_targets":3})
	runtime.emit_skill(caster,cover)
	_check(room.anchors.size() == 1,"M06 guard creates a real front plate node")
	if room.anchors.size() != 1:
		room.free()
		return
	var plate: Node2D = room.anchors[0]
	_check(plate.get_meta("enemy_skill_anchor_kind","") == "weld_cover" and plate.actor_kind == "cover","M06 plate exposes physical cover identity")
	_check(plate.position.distance_to(Vector2(242,300)) < 0.01,"M06 plate stands in front of its caster")
	_near(plate.health.current,30.0,"M06 allies share one finite plate health pool")
	_near(runtime.filter_incoming_damage(forward,20.0,&"primary",Vector2.LEFT),20.0,"front ally does not receive protection from plate behind it")
	_near(runtime.filter_incoming_damage(flank,20.0,&"primary",Vector2.LEFT),20.0,"ally outside plate width receives no guard network")
	_near(runtime.filter_incoming_damage(first,20.0,&"q",Vector2.LEFT),20.0,"M06 physical plate does not block direct skill damage")
	_near(runtime.filter_incoming_damage(first,20.0,&"primary",Vector2.RIGHT),20.0,"M06 physical plate does not block rear incoming damage")
	_near(plate.health.current,30.0,"unsupported attack types and directions never consume plate health")
	_near(runtime.filter_incoming_damage(first,20.0,&"primary",Vector2.LEFT),0.0,"M06 plate absorbs front projectile for ally behind it")
	_near(plate.health.current,10.0,"blocked projectile consumes actual shared plate health")
	_near(runtime.filter_incoming_damage(second,20.0,&"child",Vector2.LEFT),10.0,"second ally only receives remaining shared plate absorption")
	_check(not plate.is_alive(),"shared plate is destroyed when its health is exhausted")
	_check(bool(caster.get_meta("enemy_cover_broken",false)),"destroying M06 plate records a real break for its repair counterplay window")
	_near(runtime.filter_incoming_damage(first,20.0,&"primary",Vector2.LEFT),20.0,"destroying plate immediately removes first ally guard")
	_near(runtime.filter_incoming_damage(second,20.0,&"primary",Vector2.LEFT),20.0,"destroying plate immediately removes second ally guard")
	runtime.advance(0.01)
	runtime.emit_skill(caster,cover)
	plate = room.anchors[-1]
	plate.take_damage(30.0,&"primary",Vector2.LEFT)
	_near(runtime.filter_incoming_damage(first,20.0,&"primary",Vector2.LEFT),20.0,"directly shooting plate removes its guard network")
	runtime.advance(0.3)
	_check(runtime.active_effect_count() == 0,"broken M06 plate leaves no active support or visual after cleanup")
	caster.remove_meta("enemy_cover_broken")
	cover.duration = 0.2
	runtime.emit_skill(caster,cover)
	plate = room.anchors[-1]
	runtime.advance(0.3)
	_check(not plate.is_alive() and not bool(caster.get_meta("enemy_cover_broken",false)),"M06 plate natural expiry does not pretend the player broke it")
	cover.duration = 3.0
	runtime.emit_skill(caster,cover)
	plate = room.anchors[-1]
	runtime.cancel_owner(caster)
	_check(not plate.is_alive() and not bool(caster.get_meta("enemy_cover_broken",false)),"cancelling M06 plate does not start a false repair counterplay window")
	room.free()

func _anchor_capacity() -> void:
	for full_room: bool in [false,true]:
		var room := _room()
		var caster := _actor(room,Vector2(100,300),true)
		var player := _actor(room,Vector2(200,300))
		room.player = player
		if full_room:
			for index: int in range(17):
				_actor(room,Vector2(100 + index * 20,500),true)
		else:
			room.summon_budget = 0
		var runtime := _runtime(room)
		var reason: String = "18-enemy cap" if full_room else "spawn budget"
		runtime.emit_skill(caster,_command("ground_area",caster,Vector2(300,300),{"shape":"line","breakable":true,"range":200.0,"width":16.0,"duration":2.0,"tick_interval":0.35,"status":"slow"}))
		_check(room.anchors.is_empty() and runtime.active_effect_count() == 0,"M33 refuses unsupported line when " + reason + " prevents its endpoint")
		runtime.advance(1.0)
		_check(player.hits.is_empty() and player.statuses.is_empty(),"failed M33 endpoint cannot leave damaging or slowing line")
		runtime.emit_skill(caster,_command("guard",caster,Vector2(400,300),{"mode":"cover","amount":30.0,"radius":200.0,"duration":3.0}))
		_check(room.anchors.is_empty(),"M06 refuses plate when " + reason + " prevents its physical anchor")
		_near(runtime.filter_incoming_damage(caster,20.0,&"primary",Vector2.LEFT),20.0,"failed M06 plate cannot grant invisible guard network")
		room.free()

func _real_player_damage() -> void:
	var game: Node = root.get_node("Game")
	_check(str(game.profile_path).contains("test_enemy_skills"),"real-player check uses isolated enemy-skills profile")
	if not str(game.profile_path).contains("test_enemy_skills"):
		return
	game.run = load("res://scripts/core/run_state.gd").new()
	game.run.hero_id = "CH01"
	game.run.level = 1
	game.run.max_hp = 100.0
	game.run.hp = 100.0
	game.run.shield = 0.0
	game.run.stats = {"armor":25.0,"equipment_damage_reduction":0.20,"attack":27.0,"resource_type":"rage","resource_max":100.0,"loadout":{}}
	var room := _room()
	var caster := _actor(room,Vector2(200,300),true)
	var player: Node2D = load("res://scripts/combat/player.gd").new()
	player.room = room
	player.position = Vector2(270,300)
	player.visible = false
	room.player = player
	room.recipients.append(player)
	room.add_child(player)
	var runtime := _runtime(room)
	player.grant_guard(10.0,5.0,"test_guard")
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":150.0,"damage_multiplier":2.5}))
	_near(game.run.hp,78.0,"enemy skill uses real armor and equipment reduction before shield absorption")
	_near(game.run.shield,0.0,"real-player guard absorbs mitigated enemy damage")
	_near(player.status.shield(),0.0,"real-player shield status remains synchronized")
	_check(room.telemetry.player_hits == 1,"real receive_damage path updates hit telemetry")
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":150.0,"damage_multiplier":2.5}))
	_near(game.run.hp,78.0,"hurt invulnerability rejects duplicate enemy skill damage")
	_check(room.telemetry.player_hits == 1,"rejected duplicate never increments hit telemetry")
	_near(float(game.run.stats.equipment_damage_reduction),0.20,"damage path preserves permanent equipment modifier")
	player.invulnerable = 0.0
	game.run.hp = 100.0
	_check(player.start_dash(Vector2.RIGHT),"real player starts an unobstructed dash")
	_check(player.dash_protected(),"CH01 dash begins inside actual protection window")
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":250.0,"damage_multiplier":2.5}))
	_near(game.run.hp,100.0,"enemy skill cannot damage inside dash protection window")
	_check(room.telemetry.player_hits == 1,"dash-rejected skill never increments hit telemetry")
	player._tick_dash(0.10)
	_check(player.dash_remaining > 0.0 and not player.dash_protected(),"protection expires before real dash movement completes")
	runtime.emit_skill(caster,_command("melee",caster,player.position,{"range":250.0,"damage_multiplier":2.5}))
	_near(game.run.hp,68.0,"enemy skill damages after exact dash protection boundary")
	room.free()
	game.run = null

func _charge_timing_and_landing() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,200),true)
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("charge",caster,Vector2(200,200),{"range":400.0,"speed":100.0,"duration":0.0,"radius":20.0}))
	runtime.advance(0.25)
	_near(caster.position.x,125.0,"zero-duration charge derives travel time from authored speed")
	_check(runtime.has_motion(caster),"zero-duration command does not collapse a long charge into one frame")
	runtime.advance(0.75)
	_near(caster.position.x,200.0,"charge stops at locked target distance instead of full nominal range")
	_check(not runtime.has_motion(caster),"speed-derived charge releases motion when locked target is reached")
	_check(not bool(caster.get_meta("enemy_charge_wall_stop",false)),"normal charge completion does not invent a wall-stop outcome")
	room.free()

	room = _room()
	caster = _actor(room,Vector2(100,400),true)
	var midflight := _actor(room,Vector2(250,400) + Vector2.RIGHT.orthogonal() * 80.0)
	var landing := _actor(room,Vector2(400,400))
	room.player = landing
	runtime = _runtime(room)
	runtime.emit_skill(caster,_command("charge",caster,landing.position,{"range":300.0,"duration":1.0,"path_mode":"arc","arc_height":80.0,"landing_only":true,"radius":20.0}))
	runtime.advance(0.5)
	_check(caster.position.distance_to(midflight.position) < 0.01,"landing-only arc actually passes through the midflight recipient")
	_check(midflight.hits.is_empty() and landing.hits.is_empty(),"landing-only arc applies no damage while traveling")
	runtime.advance(0.5)
	_check(landing.hits.size() == 1 and midflight.hits.is_empty(),"landing-only arc hits its final landing area once")
	room.free()

func _wall_cancelled_landings() -> void:
	for mode: String in ["leap","burrow","arc"]:
		var room := _room()
		var caster := _actor(room,Vector2(100,400),true)
		var beside_wall := _actor(room,Vector2(190,350))
		var locked_landing := _actor(room,Vector2(400,400))
		room.player = beside_wall
		room.obstructions = [Rect2(220,250,20,300)]
		var runtime := _runtime(room)
		runtime.emit_skill(caster,_command("charge",caster,locked_landing.position,{"path_mode":mode,"landing_only":true,"range":300.0,"duration":1.0,"arc_height":60.0,"radius":30.0}))
		runtime.advance(1.0)
		_check(not runtime.has_motion(caster) and bool(caster.get_meta("enemy_charge_wall_stop",false)),mode + " wall contact stops and releases landing-only motion")
		_check(caster.position.distance_to(beside_wall.position) < 42.0 and caster.position.distance_to(locked_landing.position) > 42.0,mode + " fixture catches an untelegraphed impact at the wall instead of locked landing")
		_check(beside_wall.hits.is_empty() and locked_landing.hits.is_empty(),mode + " wall stop cancels landing damage instead of moving its AoE to contact point")
		runtime.advance(1.0)
		_check(beside_wall.hits.is_empty() and locked_landing.hits.is_empty(),mode + " cancelled landing cannot damage later")
		room.free()

func _attach_real_room_props(room: Node2D) -> Node2D:
	var props: Node2D = load("res://scripts/world/room_props.gd").new()
	props.visible = false
	room.add_child(props)
	props.configure(room,{})
	room.enemy_props = props
	return props

func _real_pull_cooldowns() -> void:
	for cooldown: float in [2.5,3.0]:
		var room := _room()
		var caster := _actor(room,Vector2(100,300),true)
		caster.enemy_id = "M23"
		var player := _actor(room,Vector2(350,300))
		room.player = player
		var props: Node2D = _attach_real_room_props(room)
		var runtime := _runtime(room)
		var pull: Dictionary = _command("pull",caster,player.position,{"shape":"circle","radius":400.0,"pull_distance":50.0,"damage_multiplier":0.0,"displacement_cooldown":cooldown})
		runtime.emit_skill(caster,pull)
		_near(player.position.x,300.0,"M23 first eligible pull moves its recipient")
		_check(not props.displacement_ready(player),"M23 actual displacement is recorded by real RoomProps cooldown")
		props.update(2.15)
		runtime.emit_skill(caster,pull)
		_near(player.position.x,300.0,"M23 cannot move same recipient again after only 2.15 seconds")
		props.update(cooldown - 2.15 + 0.01)
		_check(props.displacement_ready(player),"real RoomProps clock releases M23 displacement after authored cooldown")
		runtime.emit_skill(caster,pull)
		_near(player.position.x,250.0,"M23 may move recipient again after full displacement cooldown")
		_check(not props.displacement_ready(player),"successful second M23 pull starts a fresh cooldown")
		room.free()
	var room := _room()
	var caster := _actor(room,Vector2(100,300),true)
	var player := _actor(room,Vector2(350,300))
	room.player = player
	var props: Node2D = _attach_real_room_props(room)
	var runtime := _runtime(room)
	var pull: Dictionary = _command("pull",caster,player.position,{"shape":"circle","radius":400.0,"pull_distance":50.0,"damage_multiplier":0.0,"displacement_cooldown":2.5})
	player.protected_dash = true
	runtime.emit_skill(caster,pull)
	_check(player.position == Vector2(350,300) and props.displacement_ready(player),"dash-rejected M23 pull neither moves nor records displacement cooldown")
	player.protected_dash = false
	# Centerline sight is clear, but the recipient starts tangent to an inflated
	# wall corner. The swept body cannot move left at all, so no cooldown is due.
	room.obstructions = [Rect2(318,307,20,50)]
	runtime.emit_skill(caster,pull)
	_check(player.position == Vector2(350,300) and props.displacement_ready(player),"fully wall-blocked M23 pull does not consume displacement cooldown")
	room.obstructions.clear()
	pull.erase("displacement_cooldown")
	caster.enemy_id = "M07"
	runtime.emit_skill(caster,pull)
	runtime.emit_skill(caster,pull)
	_near(player.position.x,250.0,"ordinary M07 pull without cooldown field remains independently usable")
	_check(props.displacement_ready(player),"M07 pull without cooldown field never registers an M23 displacement lock")
	room.free()

func _scan_marks() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,200),true)
	caster.enemy_id = "M19"
	caster.zone_index = 2
	var shooter := _actor(room,Vector2(150,300),true)
	shooter.zone_index = 2
	var remote_shooter := _actor(room,Vector2(150,350),true)
	remote_shooter.zone_index = 3
	var player := _actor(room,Vector2(250,200))
	room.player = player
	var runtime := _runtime(room)
	var scan: Dictionary = _command("utility",caster,player.position,{"action":"scan_mark","shape":"cone","range":300.0,"angle":PI / 3.0,"duration":2.0})
	runtime.emit_skill(caster,scan)
	_check(player.hits.is_empty(),"M19 scan only marks and never deals direct damage")
	_near(runtime.consume_scan_mark(remote_shooter),1.0,"shooter in another encounter zone cannot consume M19 mark")
	_near(runtime.consume_scan_mark(shooter),0.85,"same-zone shooter consumes one fifteen-percent timing benefit")
	_near(runtime.consume_scan_mark(shooter),1.0,"M19 mark benefits exactly one shot")
	for index: int in range(4):
		runtime.emit_skill(caster,scan)
	_near(runtime.consume_scan_mark(shooter),0.85,"refreshing M19 scan preserves one mark benefit")
	_near(runtime.consume_scan_mark(shooter),1.0,"repeated M19 scans never stack extra consumable marks")
	player.protected_dash = true
	runtime.emit_skill(caster,scan)
	_near(runtime.consume_scan_mark(shooter),1.0,"dash-protected target rejects scan mark")
	player.protected_dash = false
	player.position = Vector2(100,400)
	runtime.emit_skill(caster,scan)
	_near(runtime.consume_scan_mark(shooter),1.0,"scan cone excludes off-axis target")
	player.position = Vector2(250,200)
	room.obstructions = [Rect2(175,100,20,200)]
	runtime.emit_skill(caster,scan)
	_near(runtime.consume_scan_mark(shooter),1.0,"scan cannot mark player through wall")
	room.obstructions.clear()
	runtime.emit_skill(caster,scan)
	caster.health.damage(100.0)
	_near(runtime.consume_scan_mark(shooter),1.0,"scanner death invalidates its unconsumed mark")
	_check(runtime.marks.is_empty(),"dead scanner mark is removed when considered for consumption")
	caster.health.reset(100.0)
	scan.duration = 0.5
	runtime.emit_skill(caster,scan)
	runtime.advance(0.6)
	_near(runtime.consume_scan_mark(shooter),1.0,"scan mark expires without consumption")
	runtime.emit_skill(caster,scan)
	runtime.cancel_owner(caster)
	_near(runtime.consume_scan_mark(shooter),1.0,"owner cancellation removes pending scan mark")
	runtime.emit_skill(caster,scan)
	runtime.reset_room()
	_near(runtime.consume_scan_mark(shooter),1.0,"room reset removes pending scan mark")
	room.free()

func _refraction_spread() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(200,400),true)
	caster.enemy_id = "M31"
	# These fixed endpoints are separated by at least 108 px from every other
	# authored path, so each hit proves a separate angled refraction trajectory.
	var left := _actor(room,Vector2(573.429131,127.410293))
	var middle := _actor(room,Vector2(634.099026,240.900974))
	var right := _actor(room,Vector2(661.136400,366.718108))
	room.player = middle
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("projectile",caster,middle.position,{"count":3,"projectile_angles":[-16.0,0.0,16.0],"refraction_points":[Vector2(475,400)],"speed":1000.0,"range":500.0,"projectile_radius":6.0,"lifetime":2.0,"pierce":true}))
	runtime.advance(0.275)
	_check(left.hits.is_empty() and middle.hits.is_empty() and right.hits.is_empty(),"M31 angled projectiles reach separate bends before any final hit")
	runtime.advance(0.225)
	_check(left.hits.size() == 1,"M31 left projectile follows its own rotated refraction path")
	_check(middle.hits.size() == 1,"M31 center projectile hits once rather than receiving collapsed spread hits")
	_check(right.hits.size() == 1,"M31 right projectile follows its own rotated refraction path")
	_check(runtime.projectiles.is_empty(),"M31 refracted spread retires after finite travel")
	room.free()

func _living_spawn_count(room: Node2D, prototype_id: String) -> int:
	var count: int = 0
	for candidate: Node2D in room.spawned:
		if is_instance_valid(candidate) and candidate.is_alive() and candidate.enemy_id == prototype_id:
			count += 1
	return count

func _living_pod_count(room: Node2D) -> int:
	var count: int = 0
	for anchor: Node2D in room.anchors:
		if is_instance_valid(anchor) and anchor.is_alive() and anchor.get_meta("enemy_skill_anchor_kind","") == "summon_pod":
			count += 1
	return count

func _hatching_pods() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,300),true)
	caster.enemy_id = "M12"
	var player := _actor(room,Vector2(250,300))
	room.player = player
	var runtime := _runtime(room)
	var pod_skill: Dictionary = _command("summon",caster,Vector2(250,300),{"count":1,"max_alive":2,"hatch_delay":1.2,"breakable":true,"pod_health":22.0,"exposure_after_hatch":1.6})
	runtime.emit_skill(caster,pod_skill)
	_check(_living_pod_count(room) == 1 and _living_spawn_count(room,"M14") == 0,"M12 first creates a physical pod instead of an immediate M14")
	if room.anchors.is_empty():
		room.free()
		return
	var pod: Node2D = room.anchors[0]
	var pod_position: Vector2 = pod.position
	_near(pod.health.current,22.0,"M12 pod exposes finite twenty-two health")
	runtime.advance(1.19)
	_check(_living_spawn_count(room,"M14") == 0,"M12 pod cannot hatch before its full visible delay")
	_check(not caster.has_meta("enemy_pod_hatched"),"M12 exposure window does not begin while pod is still waiting to hatch")
	_check(pod.position == pod_position,"M12 pod remains stationary while awaiting hatch")
	_check(player.hits.is_empty(),"pending M12 pod has no synchronous or hidden contact damage")
	runtime.advance(0.02)
	_check(_living_spawn_count(room,"M14") == 1 and _living_pod_count(room) == 0,"intact M12 pod is replaced by exactly one M14 after delay")
	_near(float(caster.get_meta("enemy_pod_hatched",0.0)),1.6,"successful M12 hatch signals its authored exposure window")
	_check(player.hits.is_empty(),"M14 hatching does not apply free spawn damage")
	room.free()

	room = _room()
	caster = _actor(room,Vector2(100,300),true)
	caster.enemy_id = "M12"
	runtime = _runtime(room)
	pod_skill = _command("summon",caster,Vector2(250,300),{"count":2,"max_alive":2,"hatch_delay":1.2,"breakable":true,"pod_health":22.0})
	for index: int in range(4):
		runtime.emit_skill(caster,pod_skill)
	_check(_living_pod_count(room) == 2,"pending M12 pods already count toward the two-summon owner cap")
	if room.anchors.is_empty():
		room.free()
		return
	pod = room.anchors[0]
	pod.take_damage(22.0,&"primary",Vector2.LEFT)
	runtime.advance(1.21)
	_check(_living_spawn_count(room,"M14") == 1,"destroyed M12 pod never hatches while surviving sibling still does")
	_check(_living_pod_count(room) == 0,"hatched or destroyed M12 pods leave no live anchor")
	runtime.emit_skill(caster,pod_skill)
	_check(_living_spawn_count(room,"M14") == 1 and _living_pod_count(room) == 1,"live M14 and pending M12 pods share one two-unit owner cap")
	runtime.cancel_owner(caster)
	_check(_living_spawn_count(room,"M14") == 0 and _living_pod_count(room) == 0,"cancelling M12 owner releases both child and pending pod")
	runtime.advance(2.0)
	_check(_living_spawn_count(room,"M14") == 0 and runtime.active_effect_count() == 0,"cancelled M12 pod cannot hatch later")
	room.summon_budget = 0
	runtime.emit_skill(caster,pod_skill)
	_check(_living_pod_count(room) == 0 and runtime.jobs.is_empty(),"no-budget M12 request cannot leave an invisible pending hatch")
	room.free()

func _lob_impacts() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,100),true)
	caster.enemy_id = "M11"
	var first := _actor(room,Vector2(250,250))
	var second := _actor(room,Vector2(500,250))
	var third := _actor(room,Vector2(750,250))
	room.player = first
	var runtime := _runtime(room)
	runtime.emit_skill(caster,_command("ground_area",caster,first.position,{"lob":true,"targets":[first.position,second.position,third.position],"shape":"circle","radius":30.0,"duration":1.0,"tick_interval":0.35,"max_active_hazards":2}))
	_check(first.hits.size() == 1 and second.hits.size() == 1 and third.hits.size() == 1,"M11 resolved volley delivers all three landing splashes after its tell")
	runtime.advance(0.36)
	_check(first.hits.size() == 1,"oldest M11 landing keeps impact but leaves no third persistent pool")
	_check(second.hits.size() == 2 and third.hits.size() == 2,"two newest M11 pools keep their periodic damage")
	_check(runtime.hazards.size() == 2,"three M11 impact splashes preserve the two-pool persistent cap")
	runtime.advance(1.0)
	_check(first.hits.size() == 1 and second.hits.size() == 3 and third.hits.size() == 3,"M11 pools apply only ticks within their finite lifetime")
	_check(runtime.active_effect_count() == 0,"M11 impact visuals and persistent pools expire completely")
	room.free()

func _pod_disarm_debuff() -> void:
	var room := _room()
	var caster := _actor(room,Vector2(100,300),true)
	caster.enemy_id = "M12"
	var runtime := _runtime(room)
	var command: Dictionary = _command("summon",caster,Vector2(250,300),{"count":2,"max_alive":2,"hatch_delay":1.2,"breakable":true,"pod_health":22.0,"pod_break_armor_loss":10.0})
	runtime.emit_skill(caster,command)
	_check(room.anchors.size() == 2,"M12 armor-break fixture creates two damageable pods")
	if room.anchors.size() != 2:
		room.free()
		return
	room.anchors[0].take_damage(22.0,&"primary",Vector2.LEFT)
	_check(is_equal_approx(caster.armor,5.0) and bool(caster.get_meta("enemy_pod_broken",false)),"destroying M12 pod immediately removes ten caster armor and records disarm")
	runtime.advance(0.01)
	_near(caster.armor,5.0,"pod death signal and next runtime tick cannot apply armor loss twice")
	room.anchors[1].take_damage(22.0,&"primary",Vector2.LEFT)
	runtime.advance(0.01)
	_near(caster.armor,0.0,"second destroyed M12 pod clamps armor at zero rather than making it negative")
	caster.armor = 15.0
	command.count = 1
	runtime.emit_skill(caster,command)
	runtime.cancel_owner(caster)
	runtime.advance(0.01)
	_near(caster.armor,15.0,"cancelling an intact pod does not count as a player disarm or reduce caster armor")
	room.free()

func _interrupted_motion() -> void:
	for interruption: String in ["stale_origin","pending_knockback","external_move","active_knockback"]:
		var room := _room()
		var caster := _actor(room,Vector2(100,300),true)
		var nearby := _actor(room,Vector2(130,320))
		var endpoint := _actor(room,Vector2(400,300))
		room.player = endpoint
		var runtime := _runtime(room)
		var command: Dictionary = _command("charge",caster,endpoint.position,{"path_mode":"arc","arc_height":0.0,"landing_only":true,"range":300.0,"duration":1.0,"radius":40.0})
		if interruption == "stale_origin":
			caster.position += Vector2(0,20)
		elif interruption == "pending_knockback":
			caster.knockback = Vector2(1,0)
		runtime.emit_skill(caster,command)
		if interruption in ["external_move","active_knockback"]:
			runtime.advance(0.1)
			_check(runtime.has_motion(caster),interruption + " fixture begins with a valid controlled charge")
			if interruption == "external_move":
				caster.position += Vector2(0,20)
			else:
				caster.knockback = Vector2(15,0)
		else:
			_check(not runtime.has_motion(caster),interruption + " prevents a charge from starting from invalid frozen state")
		var interrupted_position: Vector2 = caster.position
		runtime.advance(1.0)
		_check(not runtime.has_motion(caster) and caster.position == interrupted_position,interruption + " cancels controlled motion without snapping actor back onto its old path")
		_check(nearby.hits.is_empty() and endpoint.hits.is_empty(),interruption + " cannot create an untelegraphed landing impact at either interruption or destination")
		room.free()

func _failed_hatch_exposure() -> void:
	for failure: String in ["broken","cancelled","budget"]:
		var room := _room()
		var caster := _actor(room,Vector2(100,300),true)
		caster.enemy_id = "M12"
		var runtime := _runtime(room)
		runtime.emit_skill(caster,_command("summon",caster,Vector2(250,300),{"count":1,"max_alive":2,"hatch_delay":1.2,"breakable":true,"pod_health":22.0,"exposure_after_hatch":1.6}))
		_check(room.anchors.size() == 1,"M12 " + failure + " fixture begins with an actual pending pod")
		if room.anchors.size() != 1:
			room.free()
			continue
		match failure:
			"broken":
				room.anchors[0].take_damage(22.0,&"primary",Vector2.LEFT)
			"cancelled":
				runtime.cancel_owner(caster)
			"budget":
				room.summon_budget = 0
		runtime.advance(1.3)
		_check(_living_spawn_count(room,"M14") == 0 and not caster.has_meta("enemy_pod_hatched"),"M12 " + failure + " hatch cannot signal exposure without a successfully created child")
		room.free()
