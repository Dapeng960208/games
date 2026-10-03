class_name WorldCatalog
extends RefCounted
## Authored world definitions only. Catalog membership does not imply a playable scene.
## Returned dictionaries are deep copies so a run cannot mutate shared content.

const ORDINARY_ROSTER_COUNTS := {"B01": 9, "B02": 12, "B03": 15, "B04": 18, "B05": 18, "B06": 18, "B10": 18}
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const B05 = preload("res://scripts/levels/b05/world/runtime_catalog.gd")
const B06 = preload("res://scripts/levels/b06/world/runtime_catalog.gd")
const B10 = preload("res://scripts/levels/b10/world/runtime_catalog.gd")
const B10Combat = preload("res://scripts/levels/b10/combat/enemy_skills.gd")

static func b10_enabled() -> bool:
	return Rules.chapter_enabled("B10")

static func b06_enabled() -> bool:
	return Rules.b06_candidate_enabled()

static func b05_enabled() -> bool:
	return Rules.b05_candidate_enabled()

const ROOM_PATH := "res://data/world/rooms.json"
const ENEMY_PATH := "res://data/monsters/enemies.json"
const DAMAGE_KINDS := ["kinetic", "fire", "electric", "cold", "corrosion"]
const STATUS_KINDS := ["burn", "shock", "chill", "corrosion", "guard"]
static var _rooms: Dictionary = {}
static var _enemies: Dictionary = {}
static var _load_errors: Array = []
static var _loaded: bool = false

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(AssetCatalog.resolve(path)):
		_load_errors.append("Missing world catalog: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	if not parsed is Dictionary:
		_load_errors.append("Invalid world catalog JSON: " + path)
		return {}
	return parsed

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_rooms = _read_json(ROOM_PATH)
	_enemies = _read_json(ENEMY_PATH)

static func room(id: String) -> Dictionary:
	_ensure_loaded()
	if b10_enabled() and id in B10.biome().room_ids: return B10.room(id)
	if b06_enabled() and id in B06.biome().room_ids: return B06.room(id)
	return B05.room(id) if b05_enabled() and id in B05.biome().room_ids else _rooms.get("rooms", {}).get(id, {}).duplicate(true)

static func enemy(id: String) -> Dictionary:
	_ensure_loaded()
	if b10_enabled() and id.begins_with("B10-M"): return _b10_enemy(id)
	if b06_enabled() and id.begins_with("B06-M"): return B06.enemy(id)
	return B05.enemy(id) if b05_enabled() and id.begins_with("B05-M") else _enemies.get("enemies", {}).get(id, {}).duplicate(true)

static func room_ids() -> Array:
	_ensure_loaded()
	var ids: Array = _rooms.get("rooms", {}).keys()
	if b05_enabled(): ids.append_array(B05.biome().room_ids)
	if b06_enabled(): ids.append_array(B06.biome().room_ids)
	if b10_enabled(): ids.append_array(B10.biome().room_ids)
	ids.sort()
	return ids

static func enemy_ids() -> Array:
	_ensure_loaded()
	var ids: Array = _enemies.get("enemies", {}).keys()
	if b05_enabled(): ids.append_array(B05.biome().enemy_ids)
	if b06_enabled(): ids.append_array(B06.biome().enemy_ids)
	if b10_enabled(): ids.append_array(B10.biome().enemy_ids)
	ids.sort()
	return ids

static func biomes() -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = _rooms.get("biomes", {}).duplicate(true)
	if b05_enabled(): result["B05"] = B05.biome()
	if b06_enabled(): result["B06"] = B06.biome()
	if b10_enabled(): result["B10"] = B10.biome()
	return result

## The ten-region roadmap is display-only. Unimplemented plans never enter
## biomes(), whose membership drives runtime route generation and validation.
static func region_plan() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	var playable: Dictionary = biomes()
	var planned: Dictionary = _rooms.get("planned_regions", {})
	for index in range(int(Rules.value("planned_chapters", 10))):
		var biome_id := "B%02d" % (index+1)
		var entry: Dictionary = playable.get(biome_id,planned.get(biome_id,{})).duplicate(true)
		entry["biome_id"] = biome_id
		entry["implemented"] = playable.has(biome_id)
		entry["status"] = "implemented" if entry.implemented else "todo"
		if not entry.implemented:
			entry["name"] = entry.get("name","第 %d 关" % (index+1))
			entry["name_en"] = entry.get("name_en","Region %d" % (index+1))
		result.append(entry)
	return result

static func bosses() -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = _enemies.get("bosses", {}).duplicate(true)
	if b05_enabled(): result["BO05"] = B05.boss()
	if b06_enabled(): result["BO06"] = B06.boss()
	if b10_enabled():
		for id: String in B10Combat.catalog().get("bosses", {}):
			result[id] = _b10_boss(id)
	return result

static func _b10_enemy(id: String) -> Dictionary:
	var result := B10Combat.enemy_definition(id)
	if result.is_empty(): return {}
	result.merge({"behavior_id":"b10_" + id.to_lower(), "behavior_graph":"b10_species_skills",
		"visual_descriptor":str(result.name), "counter":str(result.counter_and_drop_text),
		"silhouette_id":id, "telegraph_id":id + "_tell", "drop_group":"B10",
		"summon_ownership":"room_shared_capacity_no_rewards", "damage_kind":"kinetic",
		"status_applications":[]}, true)
	return result

static func _b10_boss(id: String) -> Dictionary:
	var result := B10Combat.boss_definition(id)
	if result.is_empty(): return {}
	var arena_id := "BO10_arena" if id == "BO10" else "L%02d_arena" % (54 + int(id.trim_prefix("B10-D")))
	result.merge({"biome_id":"B10", "phase_thresholds":[0.7, 0.35], "reinforcement_cap":4 if id == "BO10" else 0,
		"reinforcement_budget":4 if id == "BO10" else 0,
		"arena":{"arena_id":arena_id, "reinforcements":[]}, "room_guardian":id != "BO10"}, true)
	return result

static func services() -> Dictionary:
	_ensure_loaded()
	return _rooms.get("services", {}).duplicate(true)

static func director() -> Dictionary:
	_ensure_loaded()
	return _enemies.get("director", {}).duplicate(true)

static func content_version() -> int:
	_ensure_loaded()
	return int(_rooms.get("content_version", 0))

static func validate() -> Array:
	_ensure_loaded()
	var errors: Array = _load_errors.duplicate()
	var candidate_count := int(b05_enabled()) + int(b06_enabled())
	var final_count := int(b10_enabled())
	var expected_rooms := 24 + candidate_count * 6 + final_count * 6
	var expected_enemies := 54 + candidate_count * 18 + final_count * 18
	var expected_biomes := 4 + candidate_count + final_count
	var expected_bosses := 4 + candidate_count + final_count * 7
	if room_ids().size() != expected_rooms:
		errors.append("Expected %d combat templates" % expected_rooms)
	if enemy_ids().size() != expected_enemies:
		errors.append("Expected %d normal enemy prototypes" % expected_enemies)
	if biomes().size() != expected_biomes or bosses().size() != expected_bosses:
		errors.append("Expected %d biomes and %d independent bosses" % [expected_biomes, expected_bosses])
	if content_version() != int(_enemies.get("content_version", -1)):
		errors.append("World catalog versions differ")
	var behavior_ids: Array = []
	var objective_ids: Array = []
	for room_id: String in room_ids():
		var value: Dictionary = room(room_id)
		for field: String in ["room_id", "name", "biome_id", "role_tags", "objective_id", "objective_count", "topology_id", "mechanic", "reference_wave", "preview"]:
			if not value.has(field) or str(value[field]).is_empty():
				errors.append(room_id + " missing " + field)
		if value.get("room_id") != room_id or not biomes().has(value.get("biome_id", "")):
			errors.append(room_id + " has invalid identity or biome")
		if objective_ids.has(value.get("objective_id", "")):
			errors.append(room_id + " reuses another template objective")
		objective_ids.append(value.get("objective_id", ""))
		for tag: String in value.get("role_tags", []):
			if tag not in ["branch", "objective", "elite_objective"]:
				errors.append(room_id + " has unknown route role " + tag)
		for member: Dictionary in value.get("reference_wave", []):
			var enemy_definition: Dictionary = enemy(str(member.get("enemy_id", "")))
			if enemy_definition.is_empty() or int(member.get("count", 0)) < 1:
				errors.append(room_id + " has invalid enemy reference")
			elif enemy_definition.get("biome_id", "") != value.get("biome_id", ""):
				errors.append(room_id + " references another biome's enemy")
	for enemy_id: String in enemy_ids():
		var value: Dictionary = enemy(enemy_id)
		for field: String in ["enemy_id", "name", "biome_id", "behavior_id", "behavior_graph", "role", "visual_descriptor", "tell", "counter", "silhouette_id", "telegraph_id", "drop_group", "summon_ownership"]:
			if not value.has(field) or str(value[field]).is_empty():
				errors.append(enemy_id + " missing " + field)
		if value.get("enemy_id") != enemy_id or not biomes().has(value.get("biome_id", "")):
			errors.append(enemy_id + " has invalid identity or biome")
		if value.get("damage_kind", "") not in DAMAGE_KINDS:
			errors.append(enemy_id + " has invalid damage kind")
		if int(value.get("threat_cost", 0)) not in [1, 2, 3, 4]:
			errors.append(enemy_id + " has invalid threat cost")
		for status: String in value.get("status_applications", []):
			if status not in STATUS_KINDS:
				errors.append(enemy_id + " has invalid status " + status)
		if behavior_ids.has(value.get("behavior_id", "")):
			errors.append(enemy_id + " reuses another prototype behavior")
		behavior_ids.append(value.get("behavior_id", ""))
	for biome_id: String in biomes():
		var biome: Dictionary = biomes()[biome_id]
		if biome.get("room_ids", []).size() != 6 or biome.get("enemy_ids", []).size() != int(ORDINARY_ROSTER_COUNTS.get(biome_id, 0)):
			errors.append(biome_id + " must own six rooms and %d enemies" % int(ORDINARY_ROSTER_COUNTS.get(biome_id, 0)))
		for room_id: String in biome.get("room_ids", []):
			if room(room_id).get("biome_id", "") != biome_id:
				errors.append(biome_id + " has invalid room membership")
		for enemy_id: String in biome.get("enemy_ids", []):
			if enemy(enemy_id).get("biome_id", "") != biome_id:
				errors.append(biome_id + " has invalid enemy membership")
		if not bosses().has(biome.get("boss_id", "")) or bosses().get(biome.get("boss_id",""),{}).get("biome_id","") != biome_id:
			errors.append(biome_id + " has invalid boss")
	for boss_id: String in bosses():
		var boss: Dictionary = bosses()[boss_id]
		if boss.get("boss_id", "") != boss_id or boss.get("arena", {}).get("arena_id", "").is_empty():
			errors.append(boss_id + " missing identity or independent arena")
		if boss.get("phase_thresholds", []) != ([0.7,0.4] if boss_id=="BO06" else [0.7, 0.35]):
			errors.append(boss_id + " has invalid phase thresholds")
		var reinforcement_threat: int = 0
		var reinforcement_count: int = 0
		for member: Dictionary in boss.get("arena", {}).get("reinforcements", []):
			var definition: Dictionary = enemy(str(member.get("enemy_id", "")))
			var amount: int = int(member.get("count", 0))
			if definition.is_empty() or definition.get("biome_id", "") != boss.get("biome_id", "") or amount < 1:
				errors.append(boss_id + " has invalid arena reinforcement")
			reinforcement_threat += int(definition.get("threat_cost", 0)) * amount
			reinforcement_count += amount
		if reinforcement_threat > int(boss.get("reinforcement_budget", 0)) or reinforcement_count > int(boss.get("reinforcement_cap", 0)):
			errors.append(boss_id + " arena reinforcement exceeds its budget")
	return errors
