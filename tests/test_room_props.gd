extends SceneTree
## Real state and geometry assertions; image appearance needs graphical review.
const Props = preload("res://scripts/world/room_props.gd")
const Layouts = preload("res://scripts/world/room_layouts.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Status = preload("res://scripts/combat/combat_status.gd")
const Generator = preload("res://scripts/world/room_generator.gd")
var checks: int = 0
var failures: int = 0

class TestRoom extends Node2D:
	var player: Node2D
	var obstructions: Array[Rect2] = []
	var gold_drops: Array[Dictionary] = []
	var layout: Dictionary = {}
	func move_actor(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
		var at: Vector2 = from
		var steps: int = maxi(1,ceili(displacement.length()/2.0))
		for index: int in steps:
			var next: Vector2 = at + displacement / float(steps)
			if not Layouts.clear_for_actor(layout,next,radius):
				break
			at = next
		return at

class TestActor extends Node2D:
	var status: RefCounted = Status.new()
	var alive: bool = true
	var health: RefCounted
	var rank: String = "normal"
	var navigation_radius: float = 18.0
	func stat(_key: String, _fallback: float) -> float:
		return 200.0
	func grant_guard(amount: float, duration: float, source: String) -> void:
		status.grant_guard(amount, duration, source, 200.0)
	func apply_status(kind: String, power: float, duration: float) -> bool:
		return status.grant_guard(power, duration, kind, 200.0)
	func is_alive() -> bool:
		return alive

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _load(test_room: TestRoom, props: Node2D, id: String, seed_value: int = 8441) -> void:
	test_room.layout = Generator.generate(id,seed_value)
	test_room.obstructions.assign(test_room.layout.obstructions)
	props.configure(test_room, test_room.layout)

func _effect(props: Node2D, index: int, effect: String) -> Dictionary:
	var item: Dictionary = props.props[index]
	item.merge(Props.BUFFS[effect].duplicate(true), true)
	item.effect = effect
	return item

func _run() -> void:
	var test_room := TestRoom.new()
	root.add_child(test_room)
	var props := Props.new()
	test_room.add_child(props)
	var actor := TestActor.new()
	test_room.add_child(actor)
	test_room.player = actor
	var signatures: Array = []
	var themes: Dictionary = {}
	for id: String in Catalog.room_ids():
		_load(test_room, props, id)
		check(props.props.size() == 3, id + " offers three seeded exploration supplies")
		check(props.obstacle_recipes.size() == test_room.obstructions.size() + test_room.layout.decoration_instances.size(), id + " every collision and harmless decoration has a visual recipe")
		var signature: String = props.biome_id
		for recipe: Dictionary in props.obstacle_recipes:
			if "non_solid" in recipe.get("tags", []):
				check(not recipe.collision_rect.has_area() and not test_room.obstructions.has(recipe.rect), id + " decorative art creates no collision")
			else:
				check(recipe.rect == test_room.obstructions[int(recipe.index)], id + " recipe preserves actual collision footprint")
			signature += str(recipe.kind) + str(recipe.rect)
		check(signature not in signatures, id + " independent layout recipe")
		signatures.append(signature)
		themes[props.biome_id] = true
		var positions: Array = []
		for item: Dictionary in props.props:
			check(Layouts.clear_for_actor(test_room.layout, item.position, 35.0), id + " device clearance")
			check(props._line_clear(item.anchor, item.position, 25.0), id + " device swept connection to authored reachable anchor")
			check(item.position.distance_to(test_room.layout.entry) >= 300.0 and item.position.distance_to(test_room.layout.exit) >= 160.0, id + " supplies stay away from entrance and exit")
			for previous: Vector2 in positions:
				check(previous.distance_to(item.position)>=600.0,id+" supplies distributed at least 600 units apart")
			for objective: Vector2 in test_room.layout.objective_points:
				check(item.position.distance_to(objective) >= 125.0, id + " separate relic interaction radius")
			positions.append(item.position)
		props.configure(test_room, test_room.layout)
		for index: int in props.props.size():
			check(props.props[index].position == positions[index], id + " placement reproducible")
	check(themes.size() == 4 and signatures.size() == 24, "four biomes and all 24 templates configured")
	for seed_value: int in [42,2026,9923]:
		for id: String in Catalog.room_ids():
			_load(test_room,props,id,seed_value)
			check(props.props.size()==3 and props.configuration_errors.is_empty(),id+" seed "+str(seed_value)+" never silently loses a supply")
			for item: Dictionary in props.props:
				var sprite_bounds := Rect2(item.position+Vector2(-39,-49),Vector2(78,76))
				for instance: Dictionary in test_room.layout.prop_instances:
					check(not sprite_bounds.intersects(instance.visual_rect.grow(8)),id+" supply sprite does not overlap generated prop art")
	_load(test_room, props, "L01")
	var first_positions: Array = []
	for item: Dictionary in props.props:
		first_positions.append(item.position)
	_load(test_room,props,"L01",9923)
	check(props.props[0].position!=first_positions[0] and props.props[1].position!=first_positions[1],"new room seed changes distributed supply locations")
	_load(test_room,props,"L01")
	var damage_device: Dictionary = _effect(props,0,"damage")
	actor.position = damage_device.position + Vector2(73,0)
	props.update(.01)
	check(not damage_device.used, "73 units cannot activate a 72-unit beacon")
	actor.position = damage_device.position
	check(props.nearest_interaction(actor.position).is_empty(), "beacon never competes for E interaction")
	props.update(.01)
	check(damage_device.used, "proximity beacon grants real damage modifier")
	check(is_equal_approx(props.damage_bonus(), .20), "damage device adds exactly 20 percent attack category A")
	check(not props.interact(damage_device.id, actor).success, "manual E cannot activate a proximity beacon")
	check(damage_device.used and not damage_device.available and damage_device.activations==1, "consumed beacon exposes dormant state")
	props.update(7.0)
	check(is_equal_approx(props.buffs.damage.remaining, 8.0), "buff timer decrements once")
	check(props.grant_buff("damage", actor), "same-kind buff can refresh from distinct source")
	check(is_equal_approx(props.damage_bonus(), .20) and is_equal_approx(props.buffs.damage.remaining,15.0), "refresh does not multiply attack stacks")
	paused = true
	props.update(20.0)
	check(is_equal_approx(props.buffs.damage.remaining,15.0), "pause freezes timers even if update is called")
	var guard_device: Dictionary = _effect(props,1,"guard")
	actor.position = guard_device.position
	props.update(.01)
	check(not guard_device.used, "pause cannot consume beacon")
	paused = false
	props.update(.01)
	check(guard_device.used, "shield beacon activates automatically")
	check(is_equal_approx(actor.status.shield(),50.0), "shield is real CombatStatus at 25 percent max HP")
	check(is_equal_approx(actor.status.absorb(30.0),0.0) and is_equal_approx(actor.status.shield(),20.0), "device shield absorbs actual damage")
	var haste_device: Dictionary = _effect(props,2,"haste")
	actor.position = haste_device.position
	props.update(.01)
	check(haste_device.used and is_equal_approx(props.move_multiplier(),1.15), "haste grants 15 percent for 12 seconds")
	props.update(12.0)
	actor.status.tick(12.0)
	check(is_equal_approx(props.move_multiplier(),1.0) and is_equal_approx(props.damage_bonus(),.20), "independent buff durations")
	props.update(3.0)
	actor.status.tick(3.0)
	check(props.active_buffs().is_empty() and is_equal_approx(actor.status.shield(),0.0), "all buffs and CombatStatus shield expire")
	props.grant_buff("guard",actor)
	actor.status.grant_guard(20,40,"unrelated",200)
	props.grant_buff("damage",actor)
	_load(test_room,props,"L07")
	check(props.active_buffs().is_empty() and props.damage_bonus()==0.0, "room change clears buffs")
	check(not actor.status.guards.has(Props.GUARD_SOURCE) and actor.status.guards.has("unrelated"), "room change removes only own shield source")
	# A thin test wall is deliberately inserted between two close positions.
	var blocked_device: Dictionary = props.props[0]
	_effect(props,0,"damage")
	actor.position = blocked_device.position-Vector2(60,0)
	var blocking_wall := Rect2(blocked_device.position-Vector2(35,15),Vector2(10,30))
	props.layout.obstructions.append(blocking_wall)
	check(props.nearest_interaction(actor.position).is_empty(), "near interaction cannot pass through wall")
	props.update(.01)
	check(not blocked_device.used, "blocked proximity does not consume")
	_load(test_room,props,"L07")
	actor.position = Vector2(250,900)
	test_room.gold_drops = [{"at":actor.position,"amount":7,"age":4.0},{"at":actor.position+Vector2(4,0),"amount":11,"age":1.0}]
	var locked_loot: Dictionary = props.target_for(actor,"steal_quest_object")
	check(props.utility(actor,"steal_quest_object",{"target":locked_loot.position,"target_id":locked_loot.id,"carry_limit":2}).success, "M16 removes actual recoverable ground loot")
	check(test_room.gold_drops.size()==1, "stolen loot unavailable for simultaneous pickup")
	check(props.carried_by(actor), "brain can query actual carried loot before returning to nest")
	check(not props.utility(actor,"steal_quest_object",{"target":locked_loot.position,"target_id":locked_loot.id}).success and test_room.gold_drops.size()==1, "frozen utility target never swaps to another drop after pickup")
	check(not props.utility(actor,"steal_quest_object",{"carry_limit":1}).success, "M16 enforces authored carry limit")
	check(props.utility(actor,"steal_quest_object",{"carry_limit":2}).success, "M16 returns every payload even when an explicit larger carry limit is configured")
	actor.alive = false
	props.update(.01)
	var returned: int = 0
	for drop: Dictionary in test_room.gold_drops:
		returned += int(drop.amount)
	check(returned==18 and test_room.gold_drops.size()==2 and props.stolen.is_empty(), "M16 death returns entire exact loot payload")
	check(not props.carried_by(actor), "return clears carried query")
	actor.alive = true
	check(not props.utility(actor,"bite_breakable_wall").success, "ordinary walls cannot be destroyed")
	_load(test_room,props,"L11")
	var thin: Dictionary = props.target_for(actor,"bite_breakable_wall")
	check(bool(thin.valid), "L11 exposes explicit thin-wall target")
	check(Layouts.clear_for_actor(test_room.layout,thin.position,24.0), "thin-wall approach target is clear ground rather than wall center")
	actor.position = thin.position
	var before: int = test_room.obstructions.size()
	var thin_count: int = props.query_tag("thin_wall").size()
	check(props.utility(actor,"bite_breakable_wall",{"range":200.0}).success, "M18 breaks explicit thin wall")
	check(test_room.obstructions.size()==before-1 and props.query_tag("thin_wall").size()==thin_count-1, "thin wall removal changes movement collision and tags")
	check(not props.target_for(actor,"bite_breakable_wall").valid and props.utility(actor,"bite_breakable_wall",{"range":5000,"breakable_wall_cap":1}).reason=="wall_break_cap", "M18 success consumes per-caster authored wall cap")
	var damaged_layout: Dictionary = props.effective_layout()
	check(damaged_layout.obstructions.size()==damaged_layout.obstruction_kinds.size(),"destroyed wall keeps obstruction kind indices aligned")
	check(props.configure(test_room,damaged_layout),"destroyed room state can be configured again")
	check(props.query_tag("thin_wall").size()==thin_count-1,"reconfiguring effective layout never resurrects a destroyed thin-wall target")
	_load(test_room,props,"L13")
	var movable: Dictionary = props.query_tag("movable")[0]
	# Isolate one actual generated, collidable small prop for the magnetic
	# geometry checks; random neighbors are covered in the generator suite.
	test_room.layout.obstructions.assign([movable.rect])
	test_room.obstructions.assign([movable.rect])
	props.layout.obstructions.assign([movable.rect])
	# The player is now registered with the room for proximity beacons, so
	# approach from outside the prop footprint rather than standing inside it.
	actor.position = movable.position - Vector2(float(movable.get("radius",20.0)) + 15.0,0)
	check(props.utility(actor,"polarity_displacement",{"direction":Vector2.RIGHT,"travel_distance":20.0}).success, "M23 moves marked small prop")
	check(props._entity(movable.id).position==movable.position+Vector2(20,0), "movable has actual changed world position")
	props.update(3.0)
	check(not test_room.obstructions.has(movable.rect) and test_room.obstructions.has(props._entity(movable.id).rect),"magnetic move updates physical collision footprint")
	props._move_prop_entity(props._entity(movable.id),movable.position)
	actor.position = movable.position - Vector2(150,0)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	test_room.add_child(enemies)
	var ordinary := TestActor.new()
	ordinary.position = actor.position + Vector2(70,10)
	enemies.add_child(ordinary)
	var elite := TestActor.new()
	elite.rank = "elite"
	elite.position = actor.position + Vector2(90,-60)
	enemies.add_child(elite)
	var outside := TestActor.new()
	outside.position = actor.position + Vector2(20,90)
	enemies.add_child(outside)
	var ordinary_start: Vector2 = ordinary.position
	var elite_start: Vector2 = elite.position
	var outside_start: Vector2 = outside.position
	var pull_result: Dictionary = props.utility(actor,"polarity_displacement",{"target":movable.position,"target_id":movable.id,"polarity":"pull","direction":Vector2.RIGHT,"range":180.0,"angle":deg_to_rad(80.0),"travel_distance":35.0})
	check(pull_result.success and int(pull_result.moved_props)==1 and int(pull_result.moved_enemies)==1, "magnet moves real prop and ordinary enemy in warned cone")
	check(props._entity(movable.id).position.x < movable.position.x and ordinary.position.distance_to(actor.position)<ordinary_start.distance_to(actor.position), "pull moves props and ordinary enemies toward caster")
	check(ordinary.position.distance_to(ordinary_start)<=35.01 and elite.position==elite_start and outside.position==outside_start, "magnet limits displacement and excludes elite/outside cone")
	var held_prop: Vector2 = props._entity(movable.id).position
	var held_actor: Vector2 = ordinary.position
	var blocked_pulse: Dictionary = props.utility(actor,"polarity_displacement",{"target_id":movable.id,"target":held_prop,"polarity":"push","direction":Vector2.RIGHT,"range":180.0,"angle":deg_to_rad(80.0),"travel_distance":35.0})
	check(not blocked_pulse.success and props._entity(movable.id).position==held_prop and ordinary.position==held_actor, "magnetic shared target cooldown blocks repeated props and ordinary actor displacement")
	paused = true
	props.update(5.0)
	check(not props.displacement_ready(ordinary), "pause freezes displacement cooldown")
	paused = false
	props.update(3.0)
	var pushed: Dictionary = props.utility(actor,"polarity_displacement",{"target_id":movable.id,"target":held_prop,"polarity":"push","direction":Vector2.RIGHT,"range":180.0,"angle":deg_to_rad(80.0),"travel_distance":35.0})
	check(pushed.success and props._entity(movable.id).position.x>held_prop.x, "push uses opposite polarity from pull")
	props.update(3.0)
	ordinary.position = actor.position + Vector2(40,0)
	var magnet_wall := Rect2(actor.position+Vector2(68,-45),Vector2(12,90))
	test_room.layout.obstructions.append(magnet_wall)
	props.layout.obstructions.append(magnet_wall)
	props.utility(actor,"polarity_displacement",{"polarity":"push","direction":Vector2.RIGHT,"range":180.0,"angle":deg_to_rad(80.0),"travel_distance":35.0})
	check(ordinary.position.x <= magnet_wall.position.x-ordinary.navigation_radius and Layouts.clear_for_actor(test_room.layout,ordinary.position,ordinary.navigation_radius), "magnetic actor displacement obeys swept room collision")
	test_room.layout.obstructions.erase(magnet_wall)
	props.layout.obstructions.erase(magnet_wall)
	enemies.free()
	var socket: Dictionary = props.query_tag("shield_socket")[0]
	actor.position = socket.position
	actor.status.guards.clear()
	check(props.utility(actor,"socket_recharge",{"guard_ratio":.30}).success and is_equal_approx(actor.status.shield(),30.0), "M25 gains configured 30 percent real guard only at visible socket")
	check(not props.utility(actor,"socket_recharge").success, "socket cooldown blocks repeated zero-cost recharge")
	_load(test_room,props,"L21")
	var pool: Dictionary = props.query_tag("shallow_pool")[0]
	actor.position = pool.position
	check(props.is_in_tag(actor.position,"shallow_pool") and props.utility(actor,"visible_burrow_path").success, "M32 burrow terrain limited to explicit traversable shallow pool")
	actor.position += Vector2(150,0)
	check(not props.is_in_tag(actor.position,"shallow_pool") and not props.utility(actor,"visible_burrow_path",{"range":300}).success, "M32 cannot burrow on unmarked ground")
	var lamp: Dictionary = props.query_tag("scene_lamp")[0]
	actor.position = lamp.position
	check(props.utility(actor,"steal_scene_lamp",{"radius":110.0}).success, "M35 turns off an actual scene lamp")
	check(float(props._entity(lamp.id).dark_remaining)>0 and props.z_index==1, "lamp darkness stays below actors and warnings")
	check(props.query_tag("dark_field")[0].radius==110.0 and props.is_in_tag(lamp.position+Vector2(109,0),"dark_field") and not props.is_in_tag(lamp.position+Vector2(111,0),"dark_field"), "M35 actual field draw/query share authored 110 radius")
	props.return_stolen(actor)
	check(float(props._entity(lamp.id).dark_remaining)==0, "lamp restored when carrier dies")
	check(not props.utility(actor,"made_up_action").success, "unimplemented utilities never report success")
	props.clear()
	test_room.free()
	print("Room props checks: %d; failures: %d" % [checks,failures])
	quit(1 if failures else 0)
