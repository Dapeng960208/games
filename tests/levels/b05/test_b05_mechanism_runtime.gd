extends SceneTree
## Isolated no-autoload test. Copy runtime/root, this test, combat_status.gd,
## scripts/infrastructure/content/runtime_rules.gd and data/rules/numerical.json at matching res:// paths.
## No production targeting, art, gameplay or bridge collision claim is made.
const Runtime = preload("res://scripts/levels/b05/world/mechanism_runtime.gd")
const Status = preload("res://scripts/domain/combat/combat_status.gd")
class HealthFixture extends RefCounted:
	var maximum := 1000.0
class Plant extends Node2D:
	var enemy_id := "B05-M01"
	var actor_kind := "enemy"
	var health := HealthFixture.new()
	var status = Status.new(2)
	var alive := true
	func is_alive() -> bool: return alive
var checks := 0
var failures := 0
var hero_alive := true
var sight_clear := true
var bridge_events: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	host.position = Vector2(700, 500)
	var runtime = _new_runtime(host)
	runtime.bridge_changed.connect(func(id: String, opened: bool) -> void: bridge_events.append([id, opened]))
	var plant := Plant.new()
	host.add_child(plant)
	_check(runtime.register_plant("spawn1", plant), "legal plant registration")
	_check(not runtime.register_plant("duplicate", plant), "same actor cannot evade CD with second ID")
	var outsider := Plant.new()
	host.add_child(outsider)
	outsider.enemy_id = "B04-M01"
	_check(not runtime.register_plant("outsider", outsider), "other biome rejected")
	plant.status.grant_guard_result(200, 3, "other", 1000)
	_check(runtime.tick(0), "tick accepts zero delta")
	_check(plant.status.shield() == 200, "shared max shield retained")
	_check(plant.status.guards.b05_root_network.amount == 120, "root does not copy stronger external shield")
	plant.status.absorb(100)
	runtime.tick(1)
	_check(plant.status.guards.b05_root_network.amount == 20, "root cannot refresh before CD")
	runtime.unregister_plant("spawn1")
	_check(not runtime.register_plant("changed_id", plant), "unregister cannot switch stable identity to bypass CD")
	_check(runtime.register_plant("spawn1", plant), "stable spawn registration can resume")
	runtime.tick(0)
	_check(plant.status.guards.b05_root_network.amount == 20, "registration retains actor CD")
	# Invalid registrations are removed, but their root cooldown is retained.
	plant.alive = false
	runtime.tick(0)
	_check(not runtime._plants.has("spawn1"), "dead actor removed from active cache")
	plant.alive = true
	_check(runtime.register_plant("spawn1", plant), "same identity can bind after alive state restored")
	runtime.tick(0)
	_check(plant.status.guards.b05_root_network.amount == 20, "cleanup cannot reset root CD")
	plant.actor_kind = "objective"
	runtime.tick(0)
	_check(not runtime._plants.has("spawn1"), "changed identity removed")
	plant.actor_kind = "enemy"
	_check(runtime.register_plant("spawn1", plant), "legal identity rebind")
	var old_status = plant.status
	plant.status = Status.new(2)
	runtime.tick(0)
	_check(not runtime._plants.has("spawn1"), "replaced status invalidates cached binding")
	plant.status = old_status
	_check(runtime.register_plant("spawn1", plant), "components can rebind explicitly")
	var ephemeral := Plant.new()
	host.add_child(ephemeral)
	_check(runtime.register_plant("ephemeral", ephemeral), "temporary actor registered")
	ephemeral.free()
	runtime.tick(0)
	_check(not runtime._plants.has("ephemeral"), "freed actor removed from active cache")
	var before: Dictionary = runtime.checkpoint()
	_check(not runtime.tick(NAN), "invalid delta")
	_check(runtime.checkpoint() == before, "invalid delta unchanged")
	var target = runtime.well_target("well")
	_check(target != null and target.position == Vector2.ZERO, "fixed invisible well target")
	_check(not target.reward_enabled, "no rewards")
	_check(not target.take_damage(20, &"primary"), "unvalidated hit rejected")
	_check(not target.take_damage(INF, &"primary", Vector2.ZERO, {"legal_hit":true}), "nonfinite damage rejected")
	_check(target.take_damage(10, &"primary", Vector2.ZERO, {"legal_hit":true}), "fixture damage path")
	_check(target.last_damage_result.hp_damage == 10, "actual capped damage receipt")
	_check(not runtime.apply_confirmed_well_damage("missing", {"confirmed":true,"hp_damage":10}).confirmed, "unknown well rejected")
	_check(not runtime.apply_confirmed_well_damage("well", {"confirmed":false,"hp_damage":10}).confirmed, "unconfirmed receipt rejected")
	var hero := Node2D.new()
	host.add_child(hero)
	hero.position = Vector2(69, 0)
	_check(not _interact(runtime, hero), "outside production 68 range")
	hero.position = Vector2(68, 0)
	sight_clear = false
	_check(not _interact(runtime, hero), "blocked sight")
	sight_clear = true
	_check(_interact(runtime, hero), "F at inclusive range")
	runtime.tick(0.3)
	_check(not runtime.notify_actor_hit("hero", 0), "zero damage does not cancel")
	_check(runtime.notify_actor_hit("hero", 1), "real hit cancels")
	runtime.tick(1)
	_check(not runtime.bridge_is_open("bridge"), "cancelled channel cannot finish")
	_check(_interact(runtime, hero), "retry after hit")
	runtime.tick(0.2)
	var remaining_cd: float = runtime.checkpoint().network.cooldowns.spawn1
	runtime.tick(10, true)
	_check(runtime.checkpoint().network.channel.is_empty(), "pause cancels")
	_check(runtime.checkpoint().network.cooldowns.spawn1 == remaining_cd, "pause freezes CD")
	_check(_interact(runtime, hero), "retry after pause")
	hero_alive = false
	runtime.tick(0.6)
	_check(not runtime.bridge_is_open("bridge"), "death cancels before completion")
	hero_alive = true
	_check(_interact(runtime, hero), "retry after death")
	hero.position.x = 69
	runtime.tick(0.6)
	_check(not runtime.bridge_is_open("bridge"), "leaving range cancels")
	hero.position.x = 0
	_check(_interact(runtime, hero), "retry after range")
	runtime.tick(0.2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(runtime.checkpoint()))
	_check(runtime.restore_checkpoint(saved), "JSON checkpoint restore")
	_check(runtime.checkpoint().network.channel.is_empty(), "restore cancels stale F")
	_check(runtime.checkpoint().network.cooldowns == saved.network.cooldowns, "restore retains CD")
	_check(_interact(runtime, hero), "fresh F required after restore")
	runtime.tick(0.59)
	_check(not runtime.bridge_is_open("bridge"), "not complete at 0.59")
	runtime.tick(0.02)
	_check(runtime.bridge_is_open("bridge"), "complete at 0.6")
	_check(bridge_events == [["bridge", true]], "one geometry notification")
	_check(not target.is_alive(), "gate disables well target")
	_check(not _interact(runtime, hero), "completed gate cannot repeat")
	before = runtime.checkpoint()
	var bad: Dictionary = before.duplicate(true)
	bad.network.wells.well.hp = -1
	_check(not runtime.restore_checkpoint(bad), "bad checkpoint rejected")
	_check(runtime.checkpoint() == before, "bad checkpoint leaves state unchanged")
	bad = before.duplicate(true)
	bad.gate_positions.gate.x = 900
	_check(not runtime.restore_checkpoint(bad), "fixed geometry cannot change")
	var fresh = _new_runtime(host)
	_check(fresh.restore_checkpoint(JSON.parse_string(JSON.stringify(before))), "completed bridge roundtrip")
	_check(fresh.bridge_is_open("bridge") and not fresh.well_target("well").is_alive(), "bridge and well preserved")
	var damage_runtime = _new_runtime(host)
	var lethal: Dictionary = damage_runtime.apply_confirmed_well_damage("well", {"confirmed":true,"hp_damage":9999})
	_check(lethal.confirmed and lethal.hp_damage == 600 and lethal.destroyed, "production receipt caps well damage")
	_check(damage_runtime.checkpoint().network.locks.roots == 12, "destroying well starts lock")
	_check(_interact(damage_runtime, hero), "channel before leaving room")
	host.remove_child(damage_runtime)
	_check(damage_runtime.checkpoint().network.channel.is_empty(), "leaving tree cancels")
	damage_runtime.free()
	host.free()
	print("B05 mechanism runtime: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _new_runtime(parent: Node2D):
	var runtime = Runtime.new()
	parent.add_child(runtime)
	_check(runtime.configure("L25", {"well":{"x":0,"y":0,"frontline_hp":1000,"network_id":"roots"}}, {"gate":{"x":0,"y":0,"well_ids":["well"],"bridge_id":"bridge"}}, 12.0, 68.0), "explicit experimental timing and production radius")
	return runtime

func _interact(runtime, hero: Node2D) -> bool:
	return runtime.interact("gate", hero, "hero", func() -> bool: return hero_alive, func(_from: Vector2, _to: Vector2) -> bool: return sight_clear)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
