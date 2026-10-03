extends SceneTree
## Region traits are exercised through the real skill runtime and health/status
## objects. This suite needs no player scene, live run, save or random selection.
## Run with tools/test.ps1 -Suite biome_enemy_skills -SkipImport.

const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Difficulty = preload("res://scripts/domain/combat/enemy_difficulty.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Brain = preload("res://scripts/gameplay/monsters/enemy_brain.gd")
const HealthScript = preload("res://scripts/domain/combat/health.gd")
const StatusScript = preload("res://scripts/domain/combat/combat_status.gd")
const SIGNATURE_IDS := {"B01":"capacitor_guard", "B02":"venom_wound", "B03":"grave_drain", "B04":"blood_rage"}
const REPRESENTATIVES := {"B01":"M01", "B02":"M10", "B03":"M19", "B04":"M28"}
const ATTACK_KINDS: Array[String] = ["melee", "projectile", "charge", "ground_area", "pull"]

class ActorFixture extends Node2D:
	var room: Node2D
	var profile: Dictionary = {}
	var health = HealthScript.new()
	var status = StatusScript.new()
	var state: StringName = &"chase"
	var actor_kind: String = "enemy"
	var rank: String = "normal"
	var contact_damage: float = 20.0
	var collision_radius: float = 12.0
	var navigation_radius: float = 12.0
	var knockback: Vector2 = Vector2.ZERO
	var accepts_damage: bool = true
	var hits: Array[Dictionary] = []
	var statuses: Array[Dictionary] = []
	var heals: Array[float] = []

	func _init() -> void:
		add_child(health)
		health.reset(100.0)

	func is_alive() -> bool:
		return not health.dead and not is_queued_for_deletion()

	func receive_damage(amount: float, origin: Vector2) -> bool:
		if not accepts_damage or not is_alive():
			return false
		hits.append({"amount":amount, "origin":origin})
		return health.damage(amount)

	func receive_enemy_status(command: Dictionary) -> bool:
		statuses.append(command.duplicate(true))
		status.apply(str(command.get("id", "")), float(command.get("power", 0.0)), float(command.get("duration", -1.0)))
		return true

	func heal(amount: float) -> float:
		if not is_alive():
			return 0.0
		var restored: float = minf(maxf(0.0, health.maximum - health.current), maxf(0.0, amount))
		health.current += restored
		heals.append(restored)
		return restored

class RoomFixture extends Node2D:
	var player: Node2D
	var enemy_props: Node2D
	var enemies: Node2D = Node2D.new()
	var recipients: Array[Node2D] = []

	func _init() -> void:
		add_child(enemies)
		process_mode = Node.PROCESS_MODE_DISABLED

	func enemy_skill_targets() -> Array:
		return recipients

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true

	func blocked_fraction(_from: Vector2, _to: Vector2, _radius: float = 0.0) -> float:
		return 1.0

	func move_actor(from: Vector2, displacement: Vector2, _radius: float) -> Vector2:
		return from + displacement

	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void:
		pass

var runtime_script: Script
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("BIOME ENEMY SKILL FAIL: " + description)

func _near(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) < 0.001, description + " (actual=" + str(actual) + ", expected=" + str(expected) + ")")

func _run() -> void:
	# Load the real runtime after the SceneTree and singleton startup complete.
	runtime_script = load(AssetCatalog.resolve("res://scripts/gameplay/monsters/enemy_skill_runtime.gd"))
	_check(runtime_script != null and runtime_script.can_instantiate(), "real skill runtime loads")
	if runtime_script == null or not runtime_script.can_instantiate():
		quit(1)
		return
	_profiles_and_commands()
	_capacitor_guard()
	_venom_wound()
	_grave_drain()
	_blood_rage()
	_only_accepted_damage_triggers()
	_damage_growth_reaches_every_attack()
	_difficulty_growth_reaches_real_skills()
	print("BIOME_ENEMY_SKILL_TESTS checks=" + str(checks) + " failures=" + str(failures))
	quit(0 if failures == 0 else 1)

func _profiles_and_commands() -> void:
	var counts: Dictionary = {"B01":0, "B02":0, "B03":0, "B04":0}
	var behaviors: Array[String] = []
	for enemy_id: String in Catalog.enemy_ids():
		var authored: Dictionary = Catalog.enemy(enemy_id)
		var biome_id: String = str(authored.get("biome_id", ""))
		_check(counts.has(biome_id), enemy_id + " has a playable region")
		if not counts.has(biome_id):
			continue
		counts[biome_id] += 1
		var behavior: String = str(authored.get("behavior_id", ""))
		_check(not behavior.is_empty() and not behaviors.has(behavior), enemy_id + " keeps a unique authored behavior")
		behaviors.append(behavior)
		for level: int in [1, 15]:
			var profile: Dictionary = Profiles.resolve(enemy_id, level)
			var signature: Dictionary = profile.get("biome_skill", {})
			var label: String = enemy_id + " L" + str(level)
			_check(str(signature.get("id", "")) == SIGNATURE_IDS[biome_id], label + " resolves its region mechanism")
			_check(not str(profile.get("biome_skill_name", "")).is_empty() and not str(profile.get("biome_skill_name_en", "")).is_empty(), label + " exposes translated skill names")
			_check(str(profile.get("behavior_id", "")) == behavior, label + " preserves its authored behavior")
			var brain := Brain.new()
			brain.configure(profile)
			var commands: Array[Dictionary] = brain._build_sequence()
			var original_profile: Dictionary = profile.duplicate(true)
			original_profile.erase("biome_skill")
			var original_brain := Brain.new()
			original_brain.configure(original_profile)
			_check(commands.size() == original_brain._build_sequence().size(), label + " region trait preserves the existing finite sequence")
			_check(not commands.is_empty(), label + " has executable commands")
			for command: Dictionary in commands:
				_check(command.get("biome_skill", {}) == signature, label + " " + str(command.kind) + " carries the region mechanism")
				_check(str(command.get("behavior_id", "")) == behavior, label + " command keeps its individual behavior")
	for biome_id: String in counts:
		_check(int(counts[biome_id]) == 9, biome_id + " owns nine distinct ordinary enemies")
	_check(behaviors.size() == 36, "all 36 distinct behaviors remain present")
	var detached: Dictionary = Profiles.resolve("M01")
	detached.biome_skill.guard_ratio = 99.0
	_near(float(Profiles.resolve("M01").biome_skill.guard_ratio), 0.08, "region signature copies cannot mutate future profiles")

func _fixture(biome_id: String, base_damage: float = 20.0) -> Dictionary:
	var room := RoomFixture.new()
	root.add_child(room)
	var caster := ActorFixture.new()
	caster.room = room
	caster.profile = Profiles.resolve(str(REPRESENTATIVES[biome_id]))
	caster.position = Vector2(100, 200)
	caster.contact_damage = base_damage
	room.enemies.add_child(caster)
	var victim := ActorFixture.new()
	victim.room = room
	victim.actor_kind = "player"
	victim.position = Vector2(170, 200)
	victim.health.reset(10000.0)
	room.add_child(victim)
	room.recipients.append(victim)
	room.player = victim
	var runtime: Node2D = runtime_script.new()
	room.add_child(runtime)
	runtime.configure(room)
	return {"room":room, "caster":caster, "victim":victim, "runtime":runtime}

func _command(fixture: Dictionary, kind: String = "melee", extra: Dictionary = {}) -> Dictionary:
	var caster: ActorFixture = fixture.caster
	var victim: ActorFixture = fixture.victim
	var command: Dictionary = {"kind":kind, "origin":caster.position, "target":victim.position, "direction":caster.position.direction_to(victim.position), "range":200.0, "radius":100.0, "angle":PI / 2.0, "damage_multiplier":1.0, "biome_skill":caster.profile.biome_skill.duplicate(true)}
	if kind == "projectile":
		command.merge({"radius":6.0, "speed":4000.0}, true)
	elif kind == "charge":
		command.merge({"radius":12.0, "path_mode":"line", "speed":4000.0, "duration":0.1, "travel_distance":120.0}, true)
	elif kind == "ground_area":
		command.merge({"shape":"circle", "duration":0.0}, true)
	elif kind == "pull":
		command.merge({"shape":"line", "radius":12.0, "pull_distance":0.0}, true)
	command.merge(extra, true)
	return command

func _emit(fixture: Dictionary, kind: String = "melee", extra: Dictionary = {}) -> void:
	fixture.runtime.emit_skill(fixture.caster, _command(fixture, kind, extra))
	if kind in ["projectile", "charge"]:
		fixture.runtime.advance(0.15)

func _capacitor_guard() -> void:
	var f: Dictionary = _fixture("B01")
	_emit(f)
	_near(f.caster.status.shield(), 8.0, "B01 accepted strike grants eight percent maximum HP shield")
	_near(float(f.caster.status.guards.get("biome:capacitor", {}).get("remaining", 0.0)), 1.5, "B01 ward lasts 1.5 seconds")
	f.caster.status.absorb(8.0)
	_emit(f)
	_near(f.caster.status.shield(), 0.0, "B01 cannot refill a spent shield during its owner cooldown")
	f.runtime.advance(3.99)
	_emit(f)
	_near(f.caster.status.shield(), 0.0, "B01 cooldown lasts the full four seconds")
	f.runtime.advance(0.02)
	_emit(f)
	_near(f.caster.status.shield(), 8.0, "B01 shield can trigger after its four second cooldown")
	f.caster.status.absorb(8.0)
	f.runtime.cancel_owner(f.caster)
	_emit(f)
	_near(f.caster.status.shield(), 8.0, "owner cancellation clears B01 cooldown")
	f.caster.status.absorb(8.0)
	f.runtime.reset_room()
	_emit(f)
	_near(f.caster.status.shield(), 8.0, "room reset clears B01 cooldown")
	f.caster.status.tick(1.5)
	_near(f.caster.status.shield(), 0.0, "real status timer expires the capacitor ward")
	f.room.free()

func _venom_wound() -> void:
	var f: Dictionary = _fixture("B02")
	_emit(f, "melee", {"damage_multiplier":1.5, "status":{"id":"burn", "duration":2.0}})
	_check(f.victim.statuses.size() == 2, "B02 preserves original burn and adds one venom packet")
	var venom: Dictionary = f.victim.statuses[1] if f.victim.statuses.size() > 1 else {}
	_check(venom.get("id", "") == "corrosion", "B02 added status is corrosion")
	_near(float(venom.get("duration", 0.0)), 1.8, "B02 venom lasts 1.8 seconds")
	_near(float(venom.get("power", 0.0)), 16.5, "B02 venom snapshots 55 percent of actual 30 damage strike")
	f.victim.statuses.clear()
	_emit(f, "melee", {"damage_multiplier":1.5, "status":{"id":"corrosion", "duration":2.0}})
	_check(f.victim.statuses.size() == 1, "B02 native acid skill gets no duplicate corrosion")
	_near(float(f.victim.statuses[0].get("power", 0.0)) if not f.victim.statuses.is_empty() else 0.0, 30.0, "native corrosion retains its original full damage snapshot")
	f.victim.statuses.clear()
	_emit(f, "melee", {"status":"corrosion"})
	_check(f.victim.statuses.size() == 1, "B02 string corrosion payload also avoids duplicate venom")
	f.room.free()

func _grave_drain() -> void:
	var f: Dictionary = _fixture("B03")
	f.caster.health.current = 40.0
	_emit(f)
	_near(f.caster.health.current, 45.0, "B03 accepted 20 damage strike restores one quarter as health")
	_emit(f)
	_near(f.caster.health.current, 45.0, "B03 consecutive hits respect the owner heal cooldown")
	f.runtime.advance(2.99)
	_emit(f)
	_near(f.caster.health.current, 45.0, "B03 heal cooldown lasts the full three seconds")
	f.runtime.advance(0.02)
	_emit(f, "melee", {"damage_multiplier":5.0})
	_near(f.caster.health.current, 51.0, "B03 large strike cannot heal above six percent maximum HP")
	f.runtime.cancel_owner(f.caster)
	_emit(f)
	_near(f.caster.health.current, 56.0, "owner cancellation clears B03 cooldown")
	f.runtime.reset_room()
	_emit(f)
	_near(f.caster.health.current, 61.0, "room reset clears B03 cooldown")
	f.runtime.cancel_owner(f.caster)
	f.caster.health.current = 99.0
	_emit(f)
	_near(f.caster.health.current, 100.0, "B03 real heal method never exceeds maximum HP")
	f.room.free()

func _blood_rage() -> void:
	var f: Dictionary = _fixture("B04")
	_emit(f, "melee", {"damage_multiplier":1.5})
	_near(float(f.victim.hits[0].amount), 30.0, "B04 full health uses original skill damage")
	_near(f.runtime.movement_multiplier(f.caster), 1.0, "B04 full health has no rage movement bonus")
	f.caster.health.current = 51.0
	_emit(f, "melee", {"damage_multiplier":1.5})
	_near(float(f.victim.hits[1].amount), 30.0, "B04 above half health retains original damage")
	f.caster.health.current = 50.0
	_emit(f, "melee", {"damage_multiplier":1.5})
	_near(float(f.victim.hits[2].amount), 36.0, "B04 half health increases actual skill damage by twenty percent")
	_check(f.runtime.movement_multiplier(f.caster) >= 1.18, "B04 half health increases actual movement multiplier")
	f.caster.health.current = 80.0
	_near(f.runtime.movement_multiplier(f.caster), 1.0, "B04 healing above half health removes movement bonus")
	# The rage bonus is frozen at emission with the original skill geometry.
	f.caster.health.current = 50.0
	f.runtime.emit_skill(f.caster, _command(f, "projectile", {"damage_multiplier":1.5}))
	f.caster.health.current = 80.0
	f.runtime.advance(0.15)
	_near(float(f.victim.hits[3].amount), 36.0, "B04 emitted projectile keeps its damage snapshot after healing")
	f.room.free()

func _only_accepted_damage_triggers() -> void:
	for biome_id: String in ["B01", "B02", "B03"]:
		for outcome: String in ["miss", "rejected", "zero_damage"]:
			var f: Dictionary = _fixture(biome_id)
			f.caster.health.current = 40.0
			if outcome == "miss":
				f.victim.position = Vector2(500, 200)
			elif outcome == "rejected":
				f.victim.accepts_damage = false
			_emit(f, "melee", {"damage_multiplier":0.0 if outcome == "zero_damage" else 1.0})
			var label: String = biome_id + " " + outcome
			_near(f.caster.status.shield(), 0.0, label + " grants no ward")
			_near(f.caster.health.current, 40.0, label + " restores no health")
			_check(f.victim.statuses.is_empty(), label + " applies no venom")
			_check(f.runtime.biome_skill_cooldowns.is_empty(), label + " consumes no region cooldown")
			f.room.free()

func _damage_growth_reaches_every_attack() -> void:
	for biome_id: String in SIGNATURE_IDS:
		for kind: String in ATTACK_KINDS:
			var observed: Array[Dictionary] = []
			for base_damage: float in [20.0, 40.0]:
				var f: Dictionary = _fixture(biome_id, base_damage)
				f.caster.health.current = 40.0
				_emit(f, kind, {"damage_multiplier":0.8})
				var label: String = biome_id + " " + kind + " base=" + str(base_damage)
				_check(f.victim.hits.size() == 1, label + " executes one accepted direct attack")
				var actual_damage: float = float(f.victim.hits[0].amount) if not f.victim.hits.is_empty() else 0.0
				_near(actual_damage, base_damage * 0.8 * (1.2 if biome_id == "B04" else 1.0), label + " uses actual scaled skill damage")
				var venom_power: float = 0.0
				var poison_damage: float = 0.0
				if biome_id == "B02":
					_check(f.victim.statuses.size() == 1, label + " applies one corrosion packet")
					venom_power = float(f.victim.statuses[0].power) if not f.victim.statuses.is_empty() else 0.0
					_near(venom_power, actual_damage * 0.55, label + " venom power follows actual command damage")
					for packet: Dictionary in f.victim.status.tick(1.0):
						if packet.kind == "corrosion":
							poison_damage += float(packet.damage)
					_near(poison_damage, venom_power * 0.08, label + " real status tick scales poison damage")
				var restored: float = f.caster.health.current - 40.0
				if biome_id == "B03":
					_near(restored, minf(actual_damage * 0.25, 6.0), label + " drain uses actual damage with maximum HP cap")
				observed.append({"damage":actual_damage, "venom":venom_power, "poison":poison_damage, "heal":restored})
				f.room.free()
			_check(float(observed[1].damage) > float(observed[0].damage), biome_id + " " + kind + " direct damage grows with stronger monster stats")
			if biome_id == "B02":
				_check(float(observed[1].venom) > float(observed[0].venom) and float(observed[1].poison) > float(observed[0].poison), kind + " both venom power and real poison damage grow")
			elif biome_id == "B03":
				_check(float(observed[1].heal) > float(observed[0].heal), kind + " stronger damage increases drain until the HP cap")

func _difficulty_growth_reaches_real_skills() -> void:
	# Resolve a real L20 prototype, pass through the production difficulty helper,
	# then execute its skill. Both actor damage and health use the returned stats.
	for biome_id: String in SIGNATURE_IDS:
		var observed: Array[Dictionary] = []
		for difficulty: int in [0, 4]:
			var f: Dictionary = _fixture(biome_id)
			var profile: Dictionary = Difficulty.apply(Profiles.resolve(str(REPRESENTATIVES[biome_id]), 20), difficulty)
			f.caster.profile = profile
			f.caster.contact_damage = float(profile.damage)
			f.caster.health.reset(float(profile.max_hp))
			f.caster.health.current = f.caster.health.maximum * 0.5
			var before_health: float = f.caster.health.current
			var label: String = biome_id + " L20 D" + str(difficulty)
			_emit(f)
			_check(f.victim.hits.size() == 1, label + " real difficulty profile executes an accepted melee hit")
			var actual_damage: float = float(f.victim.hits[0].amount) if not f.victim.hits.is_empty() else 0.0
			_near(actual_damage, float(profile.damage) * (1.2 if biome_id == "B04" else 1.0), label + " runtime uses difficulty damage and region bonus")
			var poison_damage: float = 0.0
			if biome_id == "B02":
				_check(f.victim.statuses.size() == 1 and f.victim.statuses[0].id == "corrosion", label + " real difficulty hit delivers venom")
				var power: float = float(f.victim.statuses[0].power) if not f.victim.statuses.is_empty() else 0.0
				_near(power, actual_damage * 0.55, label + " venom snapshots actual difficulty damage")
				for packet: Dictionary in f.victim.status.tick(1.0):
					if packet.kind == "corrosion":
						poison_damage += float(packet.damage)
				_near(poison_damage, actual_damage * 0.55 * 0.08, label + " real corrosion tick uses difficulty-scaled power")
			var restored: float = f.caster.health.current - before_health
			if biome_id == "B03":
				_near(restored, minf(actual_damage * 0.25, float(profile.max_hp) * 0.06), label + " drain combines real difficulty damage with its scaled HP cap")
				_check(restored > 0.0 and restored <= float(profile.max_hp) * 0.06 + 0.001, label + " drain remains bounded after difficulty growth")
			var shield: float = f.caster.status.shield()
			if biome_id == "B01":
				_near(shield, float(profile.max_hp) * 0.08, label + " capacitor ward follows the difficulty-scaled health pool")
			elif biome_id == "B04":
				_check(f.runtime.movement_multiplier(f.caster) >= 1.18, label + " difficulty actor still receives half-health rage movement")
			observed.append({"damage":actual_damage, "poison":poison_damage, "heal":restored, "shield":shield})
			f.room.free()
		_check(float(observed[1].damage) > float(observed[0].damage), biome_id + " L20 maximum difficulty increases actual skill hit damage")
		if biome_id == "B02":
			_check(float(observed[1].poison) > float(observed[0].poison), "real B02 maximum difficulty increases corrosion tick damage")
		elif biome_id == "B03":
			_check(float(observed[1].heal) >= float(observed[0].heal), "real B03 difficulty growth cannot reduce health drain")
		elif biome_id == "B01":
			_check(float(observed[1].shield) > float(observed[0].shield), "real B01 difficulty growth increases capacitor ward")
