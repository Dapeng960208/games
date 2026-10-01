extends Node
const Enemy = preload("res://scripts/combat/enemy.gd")
const Boss = preload("res://scripts/combat/boss.gd")
const Profiles = preload("res://scripts/combat/boss_profiles.gd")
const Health = preload("res://scripts/combat/health.gd")
const Skills = preload("res://scripts/combat/enemy_skill_runtime.gd")
const Fx = preload("res://scripts/combat/equipment_effects.gd")
var checks := 0
var failures: Array[String] = []

class RoomFixture extends MineRoom:
	func add_damage_text(_at: Vector2, _value: float, _kind: StringName = &"primary", _context: Dictionary = {}) -> void:
		pass

class CapturingTarget extends MineEnemy:
	var packet: Dictionary = {}
	var input_amount := 0.0
	func take_damage(amount: float, _kind: StringName, _direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
		input_amount = amount
		packet = context.duplicate()
		return false

class LoadoutFixture extends CombatLoadout:
	var after: Dictionary = {}
	func event(name: String, extra: Dictionary = {}) -> Dictionary:
		if name == "after_hit": after = extra.duplicate()
		return {"damage_bonus":0.2}

class PlayerFixture extends SalvagerPlayer:
	func class_modify_hit_amount(_target: Node2D, amount: float, _source: StringName, _context: Dictionary) -> float:
		return amount * 1.1

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = get_tree().root.get_node("Game")
	if not str(game.profile_path).contains("test_numerical_receive_paths"):
		get_tree().quit(2)
		return
	game.run = RunState.new()
	game.run.stats = {"ruleset_version":2,"attack":100,"damage_bonus":0.2,"crit_multiplier":2.0,"loadout":{}}
	game.run.max_hp = 1000
	game.run.hp = 1000
	var room := RoomFixture.new()
	var player := PlayerFixture.new()
	room.player = player
	player.room = room
	player.loadout = LoadoutFixture.new()
	player.loadout.effects = Fx.new()
	player.hit_chain.configure(player)
	player.hit_chain.count = 100
	var target := CapturingTarget.new()
	target.health = Health.new()
	target.add_child(target.health)
	target.health.reset(1000,2)
	room.crit_rolls["raw"] = true
	room.resolve_direct_hit(target,10.5,&"primary","",0,Vector2.RIGHT,{"attack_id":"raw","root_event_id":"raw"})
	check(target.packet.X == 11, "real direct path saves rounded coefficient-H before class/buff/crit/chain")
	check(player.loadout.after.X == 11, "equipment after-hit receives unchanged raw X")
	check(target.input_amount == 51, "final direct damage independently includes class/buff/crit/chain")
	var skills := Skills.new()
	room.enemy_skills = skills
	var boss := Boss.new()
	boss.room = room
	boss.health = Health.new()
	boss.add_child(boss.health)
	var profile := Profiles.resolve("BO01",0)
	profile.ruleset_version = 2
	profile.max_hp = 101
	profile.armor = 1000
	boss.configure(profile)
	boss._initialize_boss_runtime()
	check(boss.status.ruleset_version == 2 and boss.status.shield() is int and boss.status.shield() == 22, "real boss initialization grants integer shield before first contact")
	boss.status.guards.clear()
	boss.boss_brain.weakpoint = "test"
	boss.boss_brain.weakpoint_time = 1
	check(skills.filter_incoming_damage(boss,6.75,&"skill",Vector2.RIGHT) == 6.75, "empty support filter preserves fractional intermediate")
	boss.take_damage(5,&"skill",Vector2.RIGHT)
	check(boss.health.current == 98, "real boss weakpoint-support-defense chain rounds once: I(5*1.35/2)=3")
	boss.free()
	target.free()
	player.free()
	skills.free()
	room.free()
	game.run = null
	print("Numerical receive paths: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
