class_name ExpeditionController
extends RefCounted
## UI-facing expedition coordinator. Game owns every persistent mutation; the
## room owns geometry and combat. Reopening this view never rolls a new route.

const Routes = preload("res://scripts/domain/world/route_generator.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Enemies = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Rewards = preload("res://scripts/domain/world/room_rewards.gd")
var game: Node
var last_error := ""

func _init(owner_game: Node = null) -> void:
	game = owner_game

func snapshot() -> Dictionary:
	if game == null or game.run == null or not game.has_method("expedition_snapshot"):
		return {}
	return game.expedition_snapshot()

func active() -> bool:
	return not snapshot().is_empty()

func current_index() -> int:
	return int(snapshot().get("node_index", 0))

func current_node() -> Dictionary:
	var state := snapshot()
	var nodes: Array = state.get("route", {}).get("nodes", [])
	var index := int(state.get("node_index", -1))
	return nodes[index].duplicate(true) if index >= 0 and index < nodes.size() else {}

func next_node() -> Dictionary:
	var state := snapshot()
	var nodes: Array = state.get("route", {}).get("nodes", [])
	var index := int(state.get("node_index", -1)) + 1
	return nodes[index].duplicate(true) if index >= 0 and index < nodes.size() else {}

func current_complete() -> bool:
	var state := snapshot()
	return not state.is_empty() and str(state.get("phase", "combat")) in ["safe", "cleared"]

func can_extract() -> bool:
	var node := current_node()
	return current_complete() and (bool(node.get("early_extraction", false)) or node.get("role", "") == "boss")

func next_options() -> Array:
	var node := next_node()
	if node.is_empty():
		return []
	var locked := str(snapshot().get("selected_next_room_id", ""))
	if not locked.is_empty():
		return [locked]
	var options: Array = node.get("options", []).duplicate()
	if options.is_empty():
		options.append(str(node.get("room_id", "")))
	return options

func candidate(room_id: String) -> Dictionary:
	var state := snapshot()
	var next := next_node()
	if not current_complete() or next.is_empty() or not next_options().has(room_id):
		return {}
	var next_route: Dictionary = state.get("route", {}).duplicate(true)
	var index := int(next.node_index)
	if Routes.is_template_node(next):
		next_route = Routes.choose(next_route, index, room_id)
		if not bool(next_route.get("valid", false)):
			return {}
	return context_for(next_route, index, int(state.get("difficulty", 0)))

func current_context() -> Dictionary:
	var state := snapshot()
	var context := context_for(state.get("route", {}), int(state.get("node_index", 0)), int(state.get("difficulty", 0)))
	context["runtime"] = state.get("runtime",{}).duplicate(true)
	context["phase"] = str(state.get("phase","combat"))
	return context

static func context_for(route_data: Dictionary, index: int, difficulty: int) -> Dictionary:
	var nodes: Array = route_data.get("nodes", [])
	if index < 0 or index >= nodes.size():
		return {}
	var result: Dictionary = nodes[index].duplicate(true)
	result["biome_id"] = str(result.get("biome_id", route_data.get("biome_id", "B01")))
	result["node_count"] = nodes.size()
	result["departure_level"] = int(route_data.get("departure_level", 0))
	result["difficulty"] = difficulty
	# Keep this deterministic integer within exact JSON and RNG seed ranges.
	result["seed"] = (int(route_data.get("seed", 0)) + index * 104729) & 0x7fffffff
	result["expedition"] = true
	if Catalog.b06_enabled() and result.biome_id=="B06":
		result["b06_candidate"] = true
		result["b06_progression"] = true
	return result

func preview(room_id: String) -> Dictionary:
	var definition := Catalog.room(room_id)
	var hero_id := str(game.run.hero_id) if game != null and game.run != null else "CH01"
	if not definition.is_empty():
		var result: Dictionary = definition.get("preview", {}).duplicate(true)
		# The same policy generates completion rewards and these branch conditions.
		# Authored catalog reward text may describe mechanics not yet implemented.
		result["reward"] = Rewards.preview(room_id, hero_id, Words.locale == "en",int(snapshot().get("difficulty",0)), int(snapshot().get("reward_policy_version",0)))
		result["name"] = str(definition.get("name", room_id))
		result["room_id"] = room_id
		var tags: Array[String] = []
		for entry: Dictionary in definition.get("reference_wave", []):
			var enemy := Catalog.enemy(str(entry.get("enemy_id", "")))
			var role := str(enemy.get("role", "melee"))
			if not tags.has(role):
				tags.append(role)
		result["enemy_tags"] = tags
		var next := next_node()
		if snapshot().get("scan_nodes",[]).has(int(next.get("node_index",-1))):
			var counts: Dictionary = {}
			for zone in Enemies.ZONE_COUNT:
				var plan: Dictionary = Enemies.encounter_plan(room_id,zone,int(snapshot().get("difficulty",0)),2 if Catalog.room(room_id).get("biome_id","") in ["B05","B06"] else 1)
				for wave: Array in plan.get("waves",[]):
					for member: Dictionary in wave:
						var id := str(member.get("enemy_id",""))
						counts[id] = int(counts.get(id,0))+1
			var roster: Array[String] = []
			for id: String in counts:
				roster.append(str(Catalog.enemy(id).get("name",id))+" ×"+str(counts[id]))
			result["scanned_roster"] = roster
		return result
	var node := next_node()
	return {"name":str(node.get("name", room_id)), "room_id":room_id, "objective":"", "risk":"", "reward":Rewards.preview(room_id, hero_id, Words.locale == "en",int(snapshot().get("difficulty",0)), int(snapshot().get("reward_policy_version",0))), "enemy_tags":[]}

static func unlocked_biomes(profile: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var bosses: Array = profile.get("bosses", [])
	var biome_ids: Array = Catalog.biomes().keys()
	biome_ids.sort()
	for biome_id: String in biome_ids:
		var requirement := str(Catalog.biomes().get(biome_id, {}).get("unlock_requires", ""))
		if requirement.is_empty() or bosses.has(requirement):
			result.append(biome_id)
	return result
