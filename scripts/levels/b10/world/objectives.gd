extends RefCounted
## Fixed paired stargates. Travel is displacement only: never healing or a reset.
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
const CHANNEL_SECONDS := 0.6
const TRANSIT_SECONDS := 0.4
var host: Node2D
var gates: Dictionary = {}
var channel: Dictionary = {}
var gate_cooldown := 0.0

func configure(value: Node2D) -> void:
	host = value
	host.required_count = 0
	host.completed_count = 0
	host.finished = true
	gates.clear()
	channel.clear()
	var definition: Dictionary = host.layout.get("b10_geometry", {})
	for gate: Dictionary in definition.get("gates", []):
		var id := str(gate.id)
		var from := Geometry.world_point(gate.position)
		var destination := Geometry.world_point(gate.destination)
		gates[id] = {"position": from, "destination": destination, "pair_id": str(gate.pair_id)}
		host.add_element(id, from, "星门 · 目的地已标记", "utility", "", {
			"required": false, "repeatable": true, "interactive": true,
			"description": "引导0.6秒后传送；受击或离开取消。生命与技能冷却保持。",
			"destination": destination, "interaction_priority": 2})

func tick(delta: float) -> void:
	gate_cooldown = maxf(0.0, gate_cooldown - delta)
	if channel.is_empty(): return
	var actor: Node2D = channel.actor.get_ref()
	if not is_instance_valid(actor) or not is_instance_valid(host.room) or Game.run == null:
		cancel_interaction()
		return
	if bool(host.room.get("input_blocked")) or Game.run.hp <= 0.0 or actor.position.distance_to(channel.origin) > 100.0 or Game.run.hp < float(channel.hp) or Game.run.shield < float(channel.shield):
		cancel_interaction()
		return
	channel.remaining = maxf(0.0, float(channel.remaining) - delta)
	var element: Dictionary = host.element(str(channel.id))
	element["progress"] = clampf(1.0 - float(channel.remaining) / (CHANNEL_SECONDS + TRANSIT_SECONDS), 0.0, 1.0)
	if not bool(channel.transit) and float(channel.remaining) <= TRANSIT_SECONDS:
		channel.transit = true
		_clear_queued_input(actor)
	if float(channel.remaining) > 0.0: return
	var destination: Vector2 = channel.destination
	if host.room.has_method("valid_ground") and not host.room.valid_ground(destination, 24.0):
		cancel_interaction()
		return
	var gate_id := str(channel.id)
	var origin: Vector2 = actor.position
	_clear_queued_input(actor)
	actor.position = destination
	# Movement-triggered equipment reads this sampling origin. Teleportation is
	# not real walking, and therefore never completes a movement requirement.
	var loadout: Variant = actor.get("loadout")
	if loadout != null: loadout.set("_last_position", destination)
	host.room.set("_previous_player_position", destination)
	actor.set_meta("b10_portal_landing_until", host.room.get("elapsed"))
	actor.set_meta("b10_portal_destination", destination)
	gate_cooldown = 0.6
	channel.clear()
	element["progress"] = 0.0
	host.event("star_gate_traversed", {"id": gate_id, "from": origin, "position": destination,
		"source_zone": Geometry.zone_at(str(host.layout.blueprint_room_id), origin),
		"destination_zone": Geometry.zone_at(str(host.layout.blueprint_room_id), destination),
		"movement_distance": 0.0})
	if host.room.has_method("add_ring"):
		host.room.add_ring(destination, Color("dfbd6f"), 45.0, 0.4)

func _clear_queued_input(actor: Node2D) -> void:
	if actor.has_method("clear_buffered_skill"): actor.clear_buffered_skill()
	if actor.has_method("clear_movement_target"): actor.clear_movement_target()
	actor.set("attack_buffer", 0.0)

func interact(id: String, actor: Node2D) -> bool:
	if not gates.has(id) or not channel.is_empty() or gate_cooldown > 0.0 or Game.run == null or Game.run.hp <= 0.0:
		return false
	var gate: Dictionary = gates[id]
	if actor.position.distance_to(gate.position) > 100.0: return false
	if host.room.has_method("valid_ground") and not host.room.valid_ground(gate.destination, 24.0): return false
	channel = {"id": id, "actor": weakref(actor), "origin": gate.position,
		"destination": gate.destination, "remaining": CHANNEL_SECONDS + TRANSIT_SECONDS,
		"transit": false, "hp": Game.run.hp, "shield": Game.run.shield}
	_clear_queued_input(actor)
	# New enemy targeting can reject this fixed landing during channel/transit;
	# existing, already warned attacks retain their original target positions.
	actor.set_meta("b10_portal_landing_until", float(host.room.get("elapsed")) + CHANNEL_SECONDS + TRANSIT_SECONDS)
	actor.set_meta("b10_portal_destination", gate.destination)
	host.event("star_gate_channel", {"id": id, "position": gate.position,
		"destination": gate.destination, "seconds": CHANNEL_SECONDS})
	return true

func cancel_interaction() -> void:
	if channel.is_empty(): return
	var element: Dictionary = host.element(str(channel.id))
	if not element.is_empty(): element["progress"] = 0.0
	var actor: Node2D = channel.actor.get_ref()
	if is_instance_valid(actor): actor.set_meta("b10_portal_landing_until", -1.0)
	channel.clear()

func blocks_dash() -> bool:
	return not channel.is_empty()

func encounter_directive(_index: int) -> Dictionary:
	return {}

func status_text() -> String:
	return "击败龙卫和本房巨龙。星门引导0.6秒；星核可攻击，宽步路始终可达。" if str(host.layout.get("blueprint_room_id", "")) != "BO10" else "击败九头龙。三处星核可击破减轻龙盾，双门与环路连接全部核台。"

func status_text_en() -> String:
	return "Defeat the guards and this room's dragon. Stargates channel for 0.6s; walkways and breakable cores remain reachable." if str(host.layout.get("blueprint_room_id", "")) != "BO10" else "Defeat the nine-headed dragon. Break three star cores to weaken its shield; paired gates and walkways reach every core."

func draw_world(canvas: Node2D) -> void:
	for gate: Dictionary in gates.values():
		var at: Vector2 = gate.position
		canvas.draw_circle(at, 38.0, Color("b696d4", 0.17))
		canvas.draw_arc(at, 38.0, 0, TAU, 48, Color("dfbd6f"), 3.0, true)
		canvas.draw_arc(at, 28.0, 0, TAU, 48, Color("a584ce"), 2.0, true)
		for index: int in range(4):
			var ray := Vector2.RIGHT.rotated(PI * 0.5 * index)
			canvas.draw_line(at + ray * 31.0, at + ray * 45.0, Color("dfbd6f"), 3.0, true)
	if not channel.is_empty():
		var destination: Vector2 = channel.destination
		canvas.draw_arc(destination, 100.0, 0, TAU, 64, Color("c09fe3", 0.7), 2.0, true)
		canvas.draw_line(channel.origin, destination, Color("c09fe3", 0.22), 2.0, true)
