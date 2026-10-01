extends SceneTree
## godot --headless --path . --script res://tests/test_routes.gd
## Verifies catalog and route matching only; physical navigation needs scene tests.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const Routes = preload("res://scripts/world/route_generator.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _valid_path(path: Array, biome_id: String) -> bool:
	if path.size() != 5:
		return false
	var visited: Array = []
	for slot: int in range(5):
		var definition: Dictionary = Catalog.room(str(path[slot]))
		if visited.has(path[slot]) or definition.get("biome_id", "") != biome_id:
			return false
		if not definition.get("role_tags", []).has(Routes.ROLES[slot]):
			return false
		visited.append(path[slot])
	return true

func _run() -> void:
	var errors: Array = Catalog.validate()
	_check(errors.is_empty(), "Catalog validates: " + str(errors))
	_check(Catalog.room_ids().size() == 24, "24 authored templates")
	_check(Catalog.enemy_ids().size() == 36, "36 authored normal enemies")
	_check(Catalog.bosses().size() == 4, "4 independent boss definitions")
	_check(Catalog.services().size() == 3, "3 service modules excluded from room count")
	var roadmap: Array[Dictionary] = Catalog.region_plan()
	_check(roadmap.size() == 12 and Catalog.biomes().size() == 4,"twelve-region roadmap preserves exactly four runtime biomes")
	for plan_index in range(4,12):
		var plan: Dictionary = roadmap[plan_index]
		var planned_id: String = str(plan.get("biome_id",""))
		_check(not plan.get("implemented",true) and plan.get("status","") == "todo" and not Catalog.biomes().has(planned_id),planned_id+" stays a display-only TODO")
		_check(not Routes.generate(planned_id,87).get("valid",true) and not Routes.generate(planned_id,87,[],15).get("valid",true),planned_id+" cannot enter legacy or dynamic routes")
	roadmap[4]["implemented"] = true
	_check(not Catalog.region_plan()[4].get("implemented",true),"roadmap copies cannot enable an unimplemented region")
	var detached: Dictionary = Catalog.room("L01")
	var original_name: String = str(detached["name"])
	detached["name"] = "mutated"
	detached["role_tags"].clear()
	_check(Catalog.room("L01")["name"] == original_name, "Catalog protects names from mutation")
	_check(Catalog.room("L01")["role_tags"].size() == 2, "Catalog protects nested data from mutation")
	_check(Catalog.room("unknown").is_empty() and Catalog.enemy("unknown").is_empty(), "Unknown content lookup is empty")
	_check(not Routes.generate("unknown", 0).get("valid", true), "Unknown biome rejected")
	_check(not Routes.generate("B01", 0, [{"node_index": 0, "room_id": "L01"}]).get("valid", true), "Service node cannot receive a template")
	_check(not Routes.generate("B01", 0, [{"node_index": 1, "room_id": "L01"}]).get("valid", true), "Mismatched role rejected")
	_check(not Routes.generate("B01", 0, [{"node_index": 1, "room_id": "L02"}, {"node_index": 2, "room_id": "L02"}]).get("valid", true), "Repeated template rejected")
	_check(not Routes.generate("B01", 0, [{"node_index": 1, "room_id": "L02"}, {"node_index": 1, "room_id": "L03"}]).get("valid", true), "Conflicting prior choices rejected")
	_check(not Routes.generate("B01", 0, ["L02"]).get("valid", true), "Malformed choice rejected")
	var constrained: Dictionary = Routes.generate("B01", 87, [{"node_index": 6, "room_id": "L06"}])
	_check(constrained.get("valid", false), "A future explicit elite choice is legal")
	for option: String in constrained["nodes"][1]["options"]:
		var revised: Dictionary = Routes.choose(constrained, 1, option)
		_check(revised.get("valid", false) and revised["nodes"][6]["room_id"] == "L06", "Earlier choice preserves future explicit constraint")
	seed(472)
	var expected_random: int = randi()
	seed(472)
	Routes.generate("B01", 98)
	_check(randi() == expected_random, "Route generation does not consume the global reward or encounter RNG")
	for biome_id: String in Catalog.biomes():
		var seen: Dictionary = {}
		for seed_value: int in range(1000):
			var route: Dictionary = Routes.generate(biome_id, seed_value)
			var identity: String = biome_id + "/" + str(seed_value)
			_check(route.get("valid", false), identity + " generates a complete route")
			if not route.get("valid", false):
				continue
			_check(route == Routes.generate(biome_id, seed_value), identity + " deterministic all nodes, choices and previews")
			_check(route["seed"] == seed_value and route["content_version"] == Catalog.content_version(), identity + " replay metadata")
			_check(route["nodes"].size() == 8, identity + " exactly eight nodes")
			_check(_valid_path(route["template_ids"], biome_id), identity + " five distinct matching templates")
			_check(not route["navigation_validated"], identity + " does not claim physical reachability")
			for template_id: String in route["template_ids"]:
				seen[template_id] = true
			var decision_count: int = 0
			for node: Dictionary in route["nodes"]:
				var index: int = int(node["node_index"])
				_check(node["role"] == Routes.NODE_ROLES[index], identity + " node role " + str(index))
				_check(node["threat_budget"] == Routes.BUDGETS[index], identity + " node budget " + str(index))
				if node["role"] == "branch" and node["options"].size() >= 2:
					decision_count += 1
				if index not in Routes.COMBAT_NODES:
					_check(node["options"].is_empty(), identity + " service and boss excluded from choices")
					continue
				_check(node["options"].has(node["room_id"]), identity + " selected room remains visible")
				for option: String in node["options"]:
					var chosen: Dictionary = Routes.choose(route, index, option)
					_check(chosen.get("valid", false), identity + " every visible option has a legal completion")
					if not chosen.get("valid", false):
						continue
					_check(_valid_path(chosen["template_ids"], biome_id), identity + " chosen suffix matches roles without repeats")
					_check(chosen["seed"] == seed_value and chosen["nodes"][index]["room_id"] == option, identity + " choice preserves seed and request")
					for previous: int in Routes.COMBAT_NODES:
						if previous >= index:
							break
						_check(chosen["nodes"][previous]["room_id"] == route["nodes"][previous]["room_id"], identity + " earlier rooms never change")
			_check(decision_count >= 2, identity + " at least two real branch decisions")
			_check(not Routes.choose(route, 1, "not_an_option").get("valid", true), identity + " cannot choose unoffered content")
			_check(not Routes.choose(route, 4, route["nodes"][1]["room_id"]).get("valid", true), identity + " cannot replace shop")
			if seed_value == 0:
				for candidate: Array in route["candidate_paths"]:
					_check(_valid_path(candidate, biome_id), identity + " retained candidate tree contains only valid complete paths")
				var sequential: Dictionary = route
				for index: int in Routes.COMBAT_NODES:
					var options: Array = sequential["nodes"][index]["options"]
					sequential = Routes.choose(sequential, index, str(options.back()))
					_check(sequential.get("valid", false), identity + " non-default choices remain completable at every step")
				_check(sequential == Routes.generate(biome_id, seed_value, sequential["choices"]), identity + " stored decisions reproduce full route")
		_check(seen.size() == 6, biome_id + " every one of six templates selected across 1000 seeds")
		print("ROUTE_SEEDS " + biome_id + " 1000 verified; all six templates covered")
	for special_seed: int in [-1, -9223372036854775807, 9223372036854775807]:
		var special: Dictionary = Routes.generate("B01", special_seed)
		_check(special.get("valid", false) and special == Routes.generate("B01", special_seed), "Full signed integer seed is deterministic")
	print("ROUTE_TESTS checks=" + str(checks) + " failures=" + str(failures))
	quit(0 if failures == 0 else 1)
