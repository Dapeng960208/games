class_name RouteGenerator
extends RefCounted
## Route API (zero-based node indices):
## generate("B01", seed) returns eight nodes and all legal template assignments.
## generate("B01", seed, [], level) returns a level-scaled 6/8/10/12-node
## version-one expedition, preserving its regional descent schedule.
## generate_single_biome("B01", seed, [], level) creates a version-two
## expedition within one clan, with balanced scaffold reuse at longer tiers.
## generate(..., [{"node_index":1,"room_id":"L02"}]) reproduces explicit choices.
## choose(route, node_index, room_id) accepts ONLY a currently visible option,
## locks preceding rooms, and replans the suffix with the original seed.
## Each node's options have at least one complete matching suffix, never a dead end.
## This solves template matching, not physical navigation or room gameplay.

const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
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

static func _departure_cap() -> int:
	return int(preload("res://scripts/infrastructure/content/runtime_rules.gd").value("level_cap", 20))

static func _legacy_departure_cap() -> int:
	return 30 if Catalog.b06_enabled() else 25 if Catalog.b05_enabled() else 20

static func generate(biome_id: String, seed_value: int, choices: Array = [], departure_level: int = 0) -> Dictionary:
	if departure_level < 0 or departure_level > _legacy_departure_cap():
		return _error("Departure level must be 0 (legacy) or 1 through %d" % _legacy_departure_cap())
	if biome_id in ["B05","B06","B10"]: return _error("This chapter requires generate_single_biome")
	if departure_level > 0:
		return _generate_dynamic(biome_id, seed_value, choices, departure_level)
	return _generate_legacy(biome_id, seed_value, choices)

## New expeditions stay within the selected clan. Version one retains its
## original descent-ring schedule for already saved routes and existing APIs.
static func generate_single_biome(biome_id: String, seed_value: int, choices: Array = [], departure_level: int = 1) -> Dictionary:
	if departure_level < 1 or departure_level > _departure_cap():
		return _error("Departure level must be 1 through %d for a single-biome expedition" % _departure_cap())
	return _generate_dynamic(biome_id,seed_value,choices,departure_level,2)

static func _generate_legacy(biome_id: String, seed_value: int, choices: Array) -> Dictionary:
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
	if not _is_integer(route.get("departure_level", 0)):
		return _error("Invalid departure level")
	if int(route.get("departure_level", 0)) < 0 or int(route.get("departure_level", 0)) > _departure_cap():
		return _error("Invalid departure level")
	if int(route.get("departure_level", 0)) > 0:
		return _choose_dynamic(route, node_index, room_id)
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

## New expeditions retain their departure level even after the hero levels up.
## Level zero deliberately keeps the original eight-node save/replay format.
static func node_count_for_level(level: int) -> int:
	if level <= 0: return 8
	if level <= 4: return 6
	if level <= 9: return 8
	if level <= 14: return 10
	return 12

## All six final-court guardians precede the hydra, at every departure level.
static func node_count_for_biome(biome_id: String, level: int) -> int:
	return 9 if biome_id == "B10" else node_count_for_level(level)

static func length_for_level(level: int) -> int:
	return node_count_for_level(level)

static func roles_for_length(count: int) -> Array:
	match count:
		6: return ["entrance", "branch", "objective", "supply", "elite_objective", "boss"]
		8: return NODE_ROLES.duplicate()
		9: return ["entrance", "branch", "objective", "branch", "supply", "objective", "branch", "elite_objective", "boss"]
		10: return ["entrance", "branch", "branch", "objective", "supply", "branch", "objective", "branch", "elite_objective", "boss"]
		12: return ["entrance", "branch", "branch", "objective", "branch", "supply", "objective", "branch", "branch", "objective", "elite_objective", "boss"]
	return []

static func is_template_node(node: Dictionary) -> bool:
	return str(node.get("role", "")) in ["branch", "objective", "elite_objective"]

static func supply_index(route: Dictionary) -> int:
	var nodes: Array = route.get("nodes", [])
	for index: int in range(nodes.size()):
		if str(nodes[index].get("role", "")) == "supply": return index
	return -1

static func scan_indices(route: Dictionary) -> Array:
	var result: Array = []
	var nodes: Array = route.get("nodes", [])
	var supply: int = supply_index(route)
	if supply < 0: return result
	for index: int in range(supply + 1, nodes.size()):
		if is_template_node(nodes[index]): result.append(index)
	return result

## Authored regions form the descent ring B01 -> B02 -> B03 -> B04 -> B01.
## Three consecutive combat templates share a region; services and the boss
## inherit the latest combat region. This schedule cannot be altered by a save.
static func biome_for_index(start_biome: String, index: int, count: int, dynamic_version: int = 1) -> String:
	var biomes: Array = Catalog.biomes().keys()
	# Version-one saves keep their original four-region descent ring.
	if dynamic_version == 1:
		biomes = ["B01", "B02", "B03", "B04"]
	biomes.sort()
	var roles: Array = roles_for_length(count)
	if not biomes.has(start_biome) or index < 0 or index >= roles.size(): return ""
	if dynamic_version == 2: return start_biome
	var combat_count: int = 0
	for current: int in range(index + 1):
		if is_template_node({"role":roles[current]}): combat_count += 1
	var offset: int = maxi(0, combat_count - 1) / 3
	return str(biomes[(biomes.find(start_biome) + offset) % biomes.size()])

static func budget_for_index(index: int, count: int) -> int:
	var budgets: Array = []
	match count:
		6: budgets = [0, 12, 16, 0, 24, 0]
		8: budgets = BUDGETS
		9: budgets = [0, 12, 16, 20, 0, 22, 26, 30, 0]
		10: budgets = [0, 12, 14, 16, 0, 20, 22, 24, 28, 0]
		12: budgets = [0, 12, 14, 16, 18, 0, 22, 24, 26, 28, 32, 0]
	return int(budgets[index]) if index >= 0 and index < budgets.size() else -1

static func _template_indices(roles: Array) -> Array:
	var result: Array = []
	for index: int in range(roles.size()):
		if is_template_node({"role":roles[index]}): result.append(index)
	return result

static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floor(value) == value and absf(value) <= 9007199254740991.0)

static func _valid_choice_fields(choice: Variant) -> bool:
	return choice is Dictionary and _is_integer(choice.get("node_index")) and choice.get("room_id") is String

## A bounded bipartite matching replaces factorial full-path enumeration.
## At most nine slots / twenty-four templates exist in a dynamic expedition.
## Fixed rooms are locked; flexible slots can move along augmenting paths.
static func _augment(slot: int, candidates: Array, owners: Dictionary, locked: Dictionary, visited: Dictionary) -> bool:
	for room_id: String in candidates[slot]:
		if visited.has(room_id) or locked.has(room_id): continue
		visited[room_id] = true
		if not owners.has(room_id) or _augment(int(owners[room_id]), candidates, owners, locked, visited):
			owners[room_id] = slot
			return true
	return false

static func _completion(candidates: Array, fixed: Dictionary, allow_repetition: bool = false) -> Array:
	if allow_repetition: return _single_biome_completion(candidates,fixed)
	var owners: Dictionary = {}
	var locked: Dictionary = {}
	for slot: int in fixed:
		var room_id: String = str(fixed[slot])
		if slot < 0 or slot >= candidates.size() or not candidates[slot].has(room_id) or locked.has(room_id): return []
		owners[room_id] = slot
		locked[room_id] = true
	for slot: int in range(candidates.size()):
		if not fixed.has(slot) and not _augment(slot, candidates, owners, locked, {}): return []
	var selected: Array = []
	selected.resize(candidates.size())
	for room_id: String in owners:
		selected[int(owners[room_id])] = room_id
	return selected

## One clan owns six authored scaffolds, while the longest expedition has nine
## combat slots. Reuse stays deterministic and balanced, with generated adjacent
## repeats avoided when an alternative exists. Explicit choices keep their ID.
static func _single_biome_completion(candidates: Array, fixed: Dictionary) -> Array:
	for slot: int in fixed:
		if slot < 0 or slot >= candidates.size() or not candidates[slot].has(str(fixed[slot])): return []
	var selected: Array = []
	var usage: Dictionary = {}
	for slot: int in range(candidates.size()):
		var pool: Array = candidates[slot]
		if pool.is_empty(): return []
		var chosen := str(fixed.get(slot,""))
		if chosen.is_empty():
			var previous := str(selected[-1]) if not selected.is_empty() else ""
			var best_score := 2147483647
			for room_id: String in pool:
				var score := int(usage.get(room_id,0))*2+(100 if pool.size()>1 and room_id==previous else 0)
				if score < best_score:
					chosen = room_id
					best_score = score
		selected.append(chosen)
		usage[chosen] = int(usage.get(chosen,0))+1
	return selected

static func _generate_dynamic(biome_id: String, seed_value: int, choices: Array, departure_level: int, dynamic_version: int = 1) -> Dictionary:
	var biomes: Dictionary = Catalog.biomes()
	if not biomes.has(biome_id): return _error("Unknown biome: " + biome_id)
	if biome_id in ["B05","B06","B10"] and dynamic_version != 2: return _error("This chapter requires a single-biome route")
	var count: int = node_count_for_biome(biome_id, departure_level)
	var roles: Array = roles_for_length(count)
	var indices: Array = _template_indices(roles)
	var fixed: Dictionary = {}
	for choice: Variant in choices:
		if not _valid_choice_fields(choice): return _error("Choices require an integer node_index and a string room_id")
		var slot: int = indices.find(int(choice.get("node_index", -1)))
		if slot < 0: return _error("Only combat nodes accept template choices")
		var id: String = str(choice.get("room_id", ""))
		if fixed.has(slot) and fixed[slot] != id: return _error("Conflicting choices for the same node")
		fixed[slot] = id
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ (biome_id.hash() << 1) ^ (count << 24)
	var candidates: Array = []
	for index: int in indices:
		var pool: Array = []
		var region: String = biome_for_index(biome_id, index, count,dynamic_version)
		for room_id: String in biomes[region]["room_ids"]:
			if Catalog.room(room_id)["role_tags"].has(roles[index]): pool.append(room_id)
		if biome_id in ["B05","B06"]:
			# Preserve twelve stations, but teach the six authored rooms in order.
			# Lv20 B04 graduates must begin in Lv21, never a random Lv25 room.
			var slot := indices.find(index)
			var first := 31 if biome_id=="B06" else 25
			pool = ["L%02d" % (first+slot)] if slot < 6 else ["L%02d"%(first+4),"L%02d"%(first+5)]
		elif biome_id == "B10":
			pool = ["L%02d" % (55 + indices.find(index))]
		for i: int in range(pool.size() - 1, 0, -1):
			var j: int = random.randi_range(0, i)
			var temporary: String = str(pool[i])
			pool[i] = pool[j]
			pool[j] = temporary
		candidates.append(pool)
	var selected: Array = _completion(candidates, fixed,dynamic_version==2)
	if selected.is_empty(): return _error("Choices have no legal non-repeating completion")
	var nodes: Array = []
	var prefix: Dictionary = fixed.duplicate()
	var bosses: Dictionary = Catalog.bosses()
	var services: Dictionary = Catalog.services()
	for index: int in range(count):
		var role: String = str(roles[index])
		var region: String = biome_for_index(biome_id, index, count,dynamic_version)
		var node: Dictionary = {"node_index":index,"role":role,"biome_id":region,"threat_budget":budget_for_index(index,count),"room_id":"","options":[],"early_extraction":role in ["objective","elite_objective"],"next_node":index+1 if index < count-1 else -1}
		var slot: int = indices.find(index)
		if slot >= 0:
			var options: Array = []
			for option: String in candidates[slot]:
				if prefix.has(slot) and prefix[slot] != option: continue
				var trial: Dictionary = prefix.duplicate()
				trial[slot] = option
				if not _completion(candidates, trial,dynamic_version==2).is_empty(): options.append(option)
			node["room_id"] = selected[slot]
			node["options"] = options
			node["name"] = Catalog.room(str(selected[slot]))["name"]
			node["previews"] = {}
			for option: String in options:
				var definition: Dictionary = Catalog.room(option)
				node["previews"][option] = {"name":definition["name"],"biome_id":region,"objective":definition["preview"]["objective"],"risk":definition["preview"]["risk"],"reward":definition["preview"]["reward"],"objective_id":definition["objective_id"]}
			prefix[slot] = selected[slot]
		elif role == "boss":
			node["room_id"] = biomes[region]["boss_id"]
			node["name"] = bosses[node["room_id"]]["name"]
			node["arena_id"] = bosses[node["room_id"]]["arena"]["arena_id"]
		else:
			node["room_id"] = "service_" + role
			node["name"] = services[role]["name"]
			node["safe"] = true
		nodes.append(node)
	return {"valid":true,"seed":seed_value,"biome_id":biome_id,"content_version":Catalog.content_version(),"choices":choices.duplicate(true),"nodes":nodes,"template_ids":selected,"navigation_validated":false,"departure_level":departure_level,"node_count":count,"dynamic_version":dynamic_version}

static func _choose_dynamic(route: Dictionary, node_index: int, room_id: String) -> Dictionary:
	if not _is_integer(route.get("departure_level")) or not _is_integer(route.get("dynamic_version")) or not _is_integer(route.get("node_count")) or not _is_integer(route.get("seed")):
		return _error("Invalid dynamic route metadata")
	if not route.get("biome_id") is String or not route.get("nodes") is Array or not route.get("choices", []) is Array:
		return _error("Invalid dynamic route structure")
	var level: int = int(route.get("departure_level", 0))
	var count: int = node_count_for_biome(str(route.get("biome_id", "")), level)
	var nodes: Array = route.get("nodes", [])
	var version := int(route.get("dynamic_version",0))
	if not route.get("valid", false) or level < 1 or level > _departure_cap() or version not in [1,2] or nodes.size() != count or int(route.get("node_count", -1)) != count:
		return _error("Invalid dynamic route")
	if version == 1 and level > _legacy_departure_cap(): return _error("Invalid historical departure level")
	for node: Variant in nodes:
		if not node is Dictionary or not node.get("room_id") is String or not node.get("options") is Array:
			return _error("Invalid dynamic node structure")
	for previous: Variant in route.get("choices", []):
		if not _valid_choice_fields(previous): return _error("Invalid dynamic route choice")
	var indices: Array = _template_indices(roles_for_length(count))
	if not indices.has(node_index) or not nodes[node_index].get("options", []).has(room_id): return _error("Template is not a visible option for this node")
	var choices: Array = []
	for index: int in indices:
		if index > node_index: break
		choices.append({"node_index":index,"room_id":room_id if index == node_index else nodes[index]["room_id"]})
	for previous: Dictionary in route.get("choices", []):
		if int(previous["node_index"]) > node_index: choices.append(previous.duplicate(true))
	return generate_single_biome(str(route["biome_id"]),int(route["seed"]),choices,level) if version==2 else generate(str(route["biome_id"]), int(route["seed"]), choices, level)
