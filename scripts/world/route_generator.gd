class_name RouteGenerator
extends RefCounted
## Route API (zero-based node indices):
## generate("B01", seed) returns eight nodes and all legal template assignments.
## generate(..., [{"node_index":1,"room_id":"L02"}]) reproduces explicit choices.
## choose(route, node_index, room_id) accepts ONLY a currently visible option,
## locks preceding rooms, and replans the suffix with the original seed.
## Each node's options have at least one complete matching suffix, never a dead end.
## This solves template matching, not physical navigation or room gameplay.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const COMBAT_NODES := [1, 2, 3, 5, 6]
const ROLES := ["branch", "branch", "objective", "branch", "elite_objective"]
const NODE_ROLES := ["entrance", "branch", "branch", "objective", "supply", "branch", "elite_objective", "boss"]
const BUDGETS := [0, 12, 14, 16, 0, 20, 24, 0]
static var _path_cache: Dictionary = {}

static func _enumerate(ids: Array, tags: Dictionary, slot: int, path: Array, result: Array) -> void:
	if slot == ROLES.size():
		result.append(path.duplicate())
		return
	for id: String in ids:
		if path.has(id) or not tags[id].has(ROLES[slot]):
			continue
		path.append(id)
		_enumerate(ids, tags, slot + 1, path, result)
		path.pop_back()

static func _all_paths(biome_id: String) -> Array:
	if not _path_cache.has(biome_id):
		var ids: Array = Catalog.biomes()[biome_id]["room_ids"]
		var tags: Dictionary = {}
		for id: String in ids:
			tags[id] = Catalog.room(id)["role_tags"]
		var paths: Array = []
		_enumerate(ids, tags, 0, [], paths)
		_path_cache[biome_id] = paths
	return _path_cache[biome_id].duplicate(true)

static func _matches(path: Array, fixed: Dictionary) -> bool:
	for slot: int in fixed:
		if path[slot] != fixed[slot]:
			return false
	return true

static func _error(reason: String) -> Dictionary:
	return {"valid": false, "error": reason, "nodes": []}

static func generate(biome_id: String, seed_value: int, choices: Array = []) -> Dictionary:
	var biomes: Dictionary = Catalog.biomes()
	if not biomes.has(biome_id):
		return _error("Unknown biome: " + biome_id)
	var fixed: Dictionary = {}
	for choice: Variant in choices:
		if not choice is Dictionary:
			return _error("Choices must contain node_index and room_id dictionaries")
		var index: int = int(choice.get("node_index", -1))
		var slot: int = COMBAT_NODES.find(index)
		if slot < 0:
			return _error("Only combat nodes accept template choices")
		var id: String = str(choice.get("room_id", ""))
		if fixed.has(slot) and fixed[slot] != id:
			return _error("Conflicting choices for the same node")
		fixed[slot] = id
	var paths: Array = []
	for path: Array in _all_paths(biome_id):
		if _matches(path, fixed):
			paths.append(path)
	if paths.is_empty():
		return _error("Choices have no legal five-template completion")
	# Local route stream: does not advance global RNG, combat, events, or rewards.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ (biome_id.hash() << 1)
	for i: int in range(paths.size() - 1, 0, -1):
		var j: int = random.randi_range(0, i)
		var temporary: Array = paths[i]
		paths[i] = paths[j]
		paths[j] = temporary
	var selected: Array = paths[0]
	var nodes: Array = []
	var prefix: Dictionary = fixed.duplicate()
	for index: int in range(8):
		var role: String = NODE_ROLES[index]
		var node: Dictionary = {"node_index": index, "role": role, "threat_budget": BUDGETS[index], "room_id": "", "options": [], "early_extraction": index in [3, 6], "next_node": index + 1 if index < 7 else -1}
		var slot: int = COMBAT_NODES.find(index)
		if slot >= 0:
			var options: Array = []
			for path: Array in paths:
				if _matches(path, prefix) and not options.has(path[slot]):
					options.append(path[slot])
			node["room_id"] = selected[slot]
			node["options"] = options
			node["name"] = Catalog.room(selected[slot])["name"]
			node["previews"] = {}
			for option: String in options:
				var definition: Dictionary = Catalog.room(option)
				node["previews"][option] = {"name": definition["name"], "objective": definition["preview"]["objective"], "risk": definition["preview"]["risk"], "reward": definition["preview"]["reward"], "objective_id": definition["objective_id"]}
			prefix[slot] = selected[slot]
		elif role == "boss":
			node["room_id"] = biomes[biome_id]["boss_id"]
			node["name"] = Catalog.bosses()[node["room_id"]]["name"]
			node["arena_id"] = Catalog.bosses()[node["room_id"]]["arena"]["arena_id"]
		else:
			node["room_id"] = "service_" + role
			node["name"] = Catalog.services()[role]["name"]
			node["safe"] = true
		nodes.append(node)
	return {"valid": true, "seed": seed_value, "biome_id": biome_id, "content_version": Catalog.content_version(), "choices": choices.duplicate(true), "nodes": nodes, "template_ids": selected.duplicate(), "candidate_paths": paths, "navigation_validated": false}

static func choose(route: Dictionary, node_index: int, room_id: String) -> Dictionary:
	if not route.get("valid", false) or node_index not in COMBAT_NODES:
		return _error("Invalid route or non-combat node")
	var nodes: Array = route.get("nodes", [])
	if nodes.size() != 8 or not nodes[node_index].get("options", []).has(room_id):
		return _error("Template is not a visible option for this node")
	var choices: Array = []
	for index: int in COMBAT_NODES:
		if index > node_index:
			break
		choices.append({"node_index": index, "room_id": room_id if index == node_index else nodes[index]["room_id"]})
	# Retain explicit later constraints if a caller supplied them to generate().
	for previous: Dictionary in route.get("choices", []):
		if int(previous["node_index"]) > node_index:
			choices.append(previous.duplicate(true))
	return generate(str(route["biome_id"]), int(route["seed"]), choices)
