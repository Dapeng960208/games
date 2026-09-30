extends RefCounted
## Expedition combat objectives for the construct court and amber hive.
## The host still owns the room gate: completing these never clears live enemies.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const CHARGE_SECONDS: float = 1.6
const CHARGE_RADIUS: float = 90.0
const COUNTER_RADIUS: float = 420.0
const COUNTER_SECONDS: float = 6.0
const PULSE_SECONDS: float = 5.0
const BROOD_INTERVAL: float = 8.0
const BROOD_RETRY: float = 1.0
const BROOD_TOTAL_PER_NEST: int = 2
const BROOD_ROOM_CAP: int = 4
const BROOD_META: StringName = &"first_four_brood_add"

var host
var biome_id: String = ""
var variant: int = 0
var objective_count: int = 2
var clock: float = 0.0
var ids: Array[String] = []
var brood_enemy_id: String = ""

func configure(next_host, next_biome_id: String, next_variant: int, count: int) -> void:
	host = next_host
	biome_id = next_biome_id
	variant = clampi(next_variant, 0, 5)
	objective_count = clampi(count, 2, 3)
	clock = 0.0
	ids.clear()
	brood_enemy_id = ""
	host.required_count = objective_count
	if biome_id == "B01":
		_configure_conduits()
	elif biome_id == "B02":
		_configure_nests()

func _configure_conduits() -> void:
	for index: int in objective_count:
		var id: String = "solar_conduit_%d" % index
		ids.append(id)
		host.add_element(id, host.combat_objective_point(index, objective_count), "古代能量回路 %d" % (index + 1), "circuit", "B01_winch", {
			"description": "按 E 启动；留在回路旁 1.6 秒充能，离开保留进度；充能后清除附近构装护盾并暴露弱点",
			"description_en": "Press E, then stay nearby for 1.6 s. Leaving keeps progress. Charged conduits break nearby construct shields and expose weakpoints.",
			"art_selector": "combat_objective", "charging": false, "charge_seconds": 0.0,
			"charge_radius": CHARGE_RADIUS, "next_pulse": 0.0, "pulse_remaining": 0.0, "phase": "待启动"
		})

func _configure_nests() -> void:
	var enemies: Array = Catalog.biomes().get("B02", {}).get("enemy_ids", [])
	if not enemies.is_empty():
		brood_enemy_id = str(enemies[0])
	for index: int in objective_count:
		var id: String = "brood_nest_%d" % index
		ids.append(id)
		host.add_target(id, host.combat_objective_point(index, objective_count), 80.0 + 10.0 * variant, "B02_spore_nest", "育虫巢 %d" % (index + 1), {
			"description": "攻击摧毁育虫巢，停止孵化并暴露附近虫群弱点；每巢最多孵化两只幼虫",
			"description_en": "Attack to destroy the nest, stop hatching, and expose nearby hive weakpoints. Each nest can hatch at most two small insects.",
			"art_selector": "combat_objective", "interactive": false,
			"spawned_total": 0, "next_spawn": BROOD_INTERVAL, "phase": "攻击摧毁"
		})

func tick(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta) or not _room_available() or _paused():
		return
	var step: float = minf(delta, 60.0)
	clock += step
	if biome_id == "B01":
		_tick_conduits(step)
	elif biome_id == "B02" and not bool(host.finished):
		_tick_nests()

func interact(id: String, actor: Node2D) -> bool:
	if biome_id != "B01" or not ids.has(id) or not _room_available() or _paused() or bool(host.finished):
		return false
	var item: Dictionary = host.element(id)
	if item.is_empty() or bool(item.get("done", false)) or not is_instance_valid(actor) or actor != host.player():
		return false
	if actor.position.distance_to(Vector2(item.position)) > CHARGE_RADIUS:
		return false
	if not bool(item.get("charging", false)):
		item["charging"] = true
		host.event("solar_conduit_started", {"id": id, "position": item.position})
	item["phase"] = "充能中"
	return true

func _tick_conduits(delta: float) -> void:
	for id: String in ids:
		var item: Dictionary = host.element(id)
		if item.is_empty():
			continue
		item["pulse_remaining"] = maxf(0.0, float(item.get("pulse_remaining", 0.0)) - delta)
		if bool(item.get("done", false)):
			# Charged machinery continues helping while the encounter gate is shut.
			if clock + 0.00001 >= float(item.get("next_pulse", clock + PULSE_SECONDS)):
				_pulse_conduit(id, item)
			continue
		if bool(host.finished) or not bool(item.get("charging", false)):
			continue
		if not host.near(item.position, CHARGE_RADIUS):
			item["phase"] = "已暂停 · 进度保留"
			continue
		item["phase"] = "充能中"
		item["charge_seconds"] = minf(CHARGE_SECONDS, float(item.get("charge_seconds", 0.0)) + delta)
		item["progress"] = float(item.charge_seconds) / CHARGE_SECONDS
		if float(item.charge_seconds) + 0.00001 >= CHARGE_SECONDS:
			host.set_done(id)
			item["charging"] = false
			item["phase"] = "已充能 · 弱点脉冲"
			host.event("solar_conduit_charged", {"id": id, "position": item.position})
			_pulse_conduit(id, item)
	if int(host.completed_count) >= objective_count and not bool(host.finished):
		host.finish()

func _pulse_conduit(id: String, item: Dictionary) -> void:
	item["next_pulse"] = clock + PULSE_SECONDS
	item["pulse_remaining"] = 0.65
	var affected: int = _counter_near(item.position, "solar_conduit")
	# This is visual/counter feedback only; no player-damaging hazard is created.
	host.event("solar_conduit_pulse", {"id": id, "position": item.position, "radius": COUNTER_RADIUS, "affected": affected})

func _tick_nests() -> void:
	for id: String in ids:
		if not _room_available() or bool(host.finished) or _paused():
			return
		var item: Dictionary = host.element(id)
		if item.is_empty() or bool(item.get("done", false)) or bool(item.get("destroyed", false)):
			continue
		if int(item.get("spawned_total", 0)) >= BROOD_TOTAL_PER_NEST or clock + 0.00001 < float(item.get("next_spawn", BROOD_INTERVAL)):
			continue
		# Retry pressure is bounded even when the actor budget or nearby ground is full.
		item["next_spawn"] = clock + BROOD_RETRY
		if brood_enemy_id.is_empty() or _live_brood_count() >= BROOD_ROOM_CAP:
			continue
		var spawn: Dictionary = _brood_spawn_point(item.position, int(item.get("spawned_total", 0)))
		if spawn.is_empty():
			continue
		var actor: Node2D = host.room.spawn_enemy(spawn.position, brood_enemy_id, 1, {"reward_enabled": false, "zone_index": -1})
		if not is_instance_valid(actor):
			continue
		actor.set_meta(BROOD_META, true)
		actor.set_meta(&"first_four_brood_nest_id", id)
		item["spawned_total"] = int(item.get("spawned_total", 0)) + 1
		item["next_spawn"] = clock + BROOD_INTERVAL
		host.event("brood_nest_hatched", {"id": id, "enemy_id": brood_enemy_id, "position": actor.position, "spawned_total": item.spawned_total})

func _brood_spawn_point(at: Vector2, spawned: int) -> Dictionary:
	var profile: Dictionary = Profiles.resolve(brood_enemy_id, 1)
	if profile.is_empty() or not host.room.has_method("spawn_enemy"):
		return {}
	var radius: float = float(profile.get("navigation_radius", 24.0))
	for index: int in 12:
		var angle: float = (index + spawned * 3 + variant) * TAU / 12.0
		var candidate: Vector2 = host.safe_point(at + Vector2.RIGHT.rotated(angle) * 96.0, radius)
		if candidate.distance_to(at) > 260.0 or not _spawn_ground_clear(candidate, radius):
			continue
		# Stay on the nest's reachable side of walls instead of placing an add on
		# an isolated patch of otherwise valid ground.
		if host.room.has_method("blocked_fraction") and float(host.room.blocked_fraction(at, candidate, radius)) < 1.0:
			continue
		return {"position": candidate}
	return {}

func _spawn_ground_clear(at: Vector2, radius: float) -> bool:
	if host.room.has_method("valid_ground") and not host.room.valid_ground(at, radius):
		return false
	var player: Node2D = host.player()
	if is_instance_valid(player) and player.position.distance_to(at) < radius + 52.0:
		return false
	# Include objective targets in the occupancy test, but never in brood counts.
	var actors: Node = host.room.get("enemies")
	if is_instance_valid(actors):
		for actor: Node2D in actors.get_children():
			if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.has_method("is_alive") or not actor.is_alive():
				continue
			var actor_radius: float = float(actor.get("navigation_radius") if actor.get("navigation_radius") != null else 24.0)
			if actor.position.distance_to(at) < radius + actor_radius + 8.0:
				return false
	return true

func _live_brood_count() -> int:
	var count: int = 0
	for actor: Node2D in host.combat_actors():
		if bool(actor.get_meta(BROOD_META, false)):
			count += 1
	return count

func _counter_near(at: Vector2, kind: String) -> int:
	var affected: int = 0
	var enemy_ids: Array = Catalog.biomes().get(biome_id, {}).get("enemy_ids", [])
	for actor: Node2D in host.combat_actors():
		if str(actor.get("actor_kind")) != "enemy" or not enemy_ids.has(str(actor.get("enemy_id"))) or actor.position.distance_to(at) > COUNTER_RADIUS:
			continue
		host.combat_counter_effect(actor, kind, COUNTER_SECONDS)
		affected += 1
	return affected

func on_target_hit(_id: String, _context: Dictionary) -> void:
	pass

func on_target_destroyed(id: String) -> void:
	if biome_id != "B02" or not ids.has(id) or not _room_available() or bool(host.finished):
		return
	var item: Dictionary = host.element(id)
	if item.is_empty() or bool(item.get("done", false)):
		return
	item["destroyed"] = true
	item["next_spawn"] = INF
	host.set_done(id)
	var affected: int = _counter_near(item.position, "brood_egg")
	host.event("brood_nest_destroyed", {"id": id, "position": item.position, "affected": affected})
	if int(host.completed_count) >= objective_count:
		host.finish()

func notify_enemy_death(_enemy) -> void:
	# Live add counts are derived from room actors, never retained references.
	pass

func notify_charge_impact(_caster, _from: Vector2, _to: Vector2) -> Dictionary:
	return {}

func status_text() -> String:
	if biome_id == "B01":
		return "能量回路 %d/%d · %s" % [host.completed_count, objective_count, "已充能，清理敌群后离开" if bool(host.finished) else "E 启动，近旁充能 1.6 秒；离开保留进度"]
	return "育虫巢 %d/%d · %s" % [host.completed_count, objective_count, "已摧毁，清理敌群后离开" if bool(host.finished) else "攻击摧毁；停止孵化并暴露虫群弱点"]

func status_text_en() -> String:
	if biome_id == "B01":
		return "Conduits %d/%d · %s" % [host.completed_count, objective_count, "Charged. Clear the remaining enemies to leave." if bool(host.finished) else "E to start; stay nearby for 1.6 s. Leaving keeps progress."]
	return "Brood nests %d/%d · %s" % [host.completed_count, objective_count, "Destroyed. Clear the remaining enemies to leave." if bool(host.finished) else "Attack nests to stop hatching and expose hive weakpoints."]

func navigation_target() -> Dictionary:
	var best: float = INF
	var destination: Dictionary = {}
	var player: Node2D = host.player()
	for id: String in ids:
		var item: Dictionary = host.element(id)
		if item.is_empty() or bool(item.get("done", false)) or bool(item.get("destroyed", false)):
			continue
		var distance: float = player.position.distance_squared_to(item.position) if is_instance_valid(player) else 0.0
		if distance < best:
			best = distance
			destination = {"id": id, "position": item.position, "title": str(item.label)}
	return destination

func blocks_dash() -> bool:
	return false

func encounter_directive(_index: int) -> Dictionary:
	return {}

func draw_world(canvas: Node2D) -> void:
	if biome_id != "B01":
		return
	for id: String in ids:
		var item: Dictionary = host.element(id)
		var remaining: float = float(item.get("pulse_remaining", 0.0))
		if remaining <= 0.0:
			continue
		var progress: float = 1.0 - remaining / 0.65
		canvas.draw_arc(item.position, lerpf(42.0, 142.0, progress), 0.0, TAU, 48, Color(0.56, 0.88, 0.79, (1.0 - progress) * 0.75), 3.0, true)

func _room_available() -> bool:
	return is_instance_valid(host) and is_instance_valid(host.room) and not host.room.is_queued_for_deletion()

func _paused() -> bool:
	return host.room.is_inside_tree() and host.room.get_tree().paused
