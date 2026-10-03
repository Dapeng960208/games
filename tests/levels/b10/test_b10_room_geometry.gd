extends Node
const Content = preload("res://scripts/levels/b10/world/content.gd")
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
const Layouts = preload("res://scripts/levels/b10/world/room_layouts.gd")
const Generator = preload("res://scripts/gameplay/world/room_generator.gd")
const Portals = preload("res://scripts/levels/b10/world/objectives.gd")
var checks := 0
var failures: Array[String] = []

class PortalRoom extends Node2D:
	var elapsed := 10.0
	var input_blocked := false
	var _previous_player_position := Vector2.ZERO
	var floor_polygon := PackedVector2Array()
	func valid_ground(at: Vector2, _radius: float) -> bool:
		return Geometry2D.is_point_in_polygon(at, floor_polygon)

class MovementSampler extends RefCounted:
	var _last_position := Vector2.ZERO

class PortalActor extends Node2D:
	var attack_buffer := 1.0
	var loadout := MovementSampler.new()
	var cooldowns := {"Q": 4.0, "W": 6.0, "E": 9.0, "R": 18.0}
	var dash_cooldown := 2.0
	var queued := true
	func clear_buffered_skill() -> void: queued = false
	func clear_movement_target() -> void: pass

class PortalHost extends Node2D:
	var room: Node2D
	var layout: Dictionary = {}
	var required_count := 0
	var completed_count := 0
	var finished := false
	var elements: Dictionary = {}
	var events: Array = []
	func add_element(id: String, at: Vector2, label: String, kind: String, asset: String, extra: Dictionary) -> Dictionary:
		var value := {"id": id, "position": at, "label": label, "kind": kind, "asset": asset}
		value.merge(extra, true)
		elements[id] = value
		return value
	func element(id: String) -> Dictionary: return elements.get(id, {})
	func event(id: String, data: Dictionary) -> void: events.append({"name": id, "data": data})

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not Game.profile_path.contains("test_b10_room_geometry"):
		printerr("B10 world test requires its isolated profile")
		get_tree().quit(2)
		return
	check(Content.validate().is_empty(), "final chapter content identities")
	var paintings: Array[String] = []
	for id: String in Content.room_ids():
		var source := Geometry.room(id)
		check(Geometry.validate(id).is_empty(), id + " connected wide floor: " + str(Geometry.validate(id)))
		var layout := Layouts.build(id, 901)
		var again := Layouts.build(id, 902)
		check(layout.ground_polygon == again.ground_polygon, id + " geometry stays fixed across seed")
		check(layout.ground_polygon == Geometry.polygon(id), id + " runtime uses authored floor edge")
		check(layout.entry == Geometry.world_point(source.entry), id + " entry shares blueprint transform")
		check(layout.dragon_spawn == Geometry.world_point(source.dragon_spawn), id + " dragon footpoint shares mapping")
		check(layout.get("b10_final", false) and not layout.get("b06_candidate", false), id + " production layout")
		if id != "BO10":
			check(Generator.generate(id, 901).ground_polygon == layout.ground_polygon, id + " standard generator selects final chapter")
		var painting := str(Content.room(id).background)
		check(not paintings.has(painting), id + " owns independent background")
		paintings.append(painting)
		var placement: Array = source.placement_normalized_rect
		for index: int in source.walkable_polygon.size():
			var pixel: Array = source.walkable_polygon[index]
			var normalized: Array = source.walkable_normalized_polygon[index]
			var from_painting := Vector2((float(normalized[0]) - float(placement[0])) / float(placement[2]) * 2800,
				(float(normalized[1]) - float(placement[1])) / float(placement[3]) * 1800) * 0.58
			check(from_painting.distance_to(Geometry.world_point(pixel)) < 0.002, id + " floor/painting vertex " + str(index))
	_test_portals()
	Game.run = null
	for failure: String in failures: printerr(failure)
	print("B10 room geometry and star gates: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_portals() -> void:
	Game.run = RunSession.new()
	Game.run.hp = 1234
	Game.run.shield = 90
	Game.run.resource = 567
	var room := PortalRoom.new()
	room.floor_polygon = Geometry.polygon("L55")
	var host := PortalHost.new()
	host.layout = Layouts.build("L55", 901)
	host.room = room
	var actor := PortalActor.new()
	var portals := Portals.new()
	portals.configure(host)
	var gates: Array = Geometry.room("L55").gates
	actor.position = Geometry.world_point(gates[0].position)
	var start := actor.position
	var destination := Geometry.world_point(gates[0].destination)
	check(portals.interact(str(gates[0].id), actor), "fixed gate accepts nearby actor")
	check(not actor.queued and actor.attack_buffer == 0.0, "gate clears only uncommitted inputs")
	portals.tick(0.59)
	check(actor.position == start, "full 0.6s channel before travel")
	portals.tick(0.4)
	check(actor.position == start, "0.4s transit before arrival")
	portals.tick(0.02)
	check(actor.position == destination, "gate arrives at paired fixed endpoint")
	check(Game.run.hp == 1234 and Game.run.shield == 90 and Game.run.resource == 567, "teleport preserves hp, shield and resource")
	check(actor.cooldowns == {"Q": 4.0, "W": 6.0, "E": 9.0, "R": 18.0} and actor.dash_cooldown == 2.0, "teleport never resets any cooldown")
	check(actor.loadout._last_position == destination and room._previous_player_position == destination, "teleport excluded from movement samples")
	check(not portals.interact(str(gates[1].id), actor), "bounded immediate reentry")
	portals.tick(0.7)
	check(portals.interact(str(gates[1].id), actor), "reverse gate returns along the same pair")
	Game.run.hp -= 1
	portals.tick(0.1)
	check(portals.channel.is_empty() and actor.position == destination, "hit cancels channel without teleport")
	check(portals.interact(str(gates[1].id), actor), "cancel allows new deliberate interaction")
	actor.position += Vector2(120, 0)
	portals.tick(0.1)
	check(portals.channel.is_empty(), "leaving landing pad cancels channel")
	actor.position = destination
	check(portals.interact(str(gates[1].id), actor), "gate can channel after return")
	room.input_blocked = true
	portals.tick(0.1)
	check(portals.channel.is_empty(), "modal input block cancels channel")
	actor.free()
	host.free()
	room.free()
