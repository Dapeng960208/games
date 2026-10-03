class_name B07Content
extends RefCounted
## B07 authored identities, mechanics and fixed geometry. Runtime chapter gates
## belong to NumericalRules; this reader cannot enable a chapter by loading it.
const DATA_PATH := "res://data/levels/b07/content.json"
const PROFILE_IDS := ["F", "R", "C", "S", "A", "T"]
const LEVELS := [31, 33, 35]
static var _data: Dictionary = {}
static var _errors: Array = []
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		_errors.append("Missing B07 authored catalog")
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(DATA_PATH)) != OK or not parser.data is Dictionary:
		_errors.append("Invalid B07 authored JSON")
		return
	_errors = validate_data(parser.data)
	if _errors.is_empty(): _data = parser.data.duplicate(true)

static func catalog() -> Dictionary:
	_ensure_loaded()
	return _data.duplicate(true)

static func enemy(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("enemies", {}).get(id, {}).duplicate(true)

static func room(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("rooms", {}).get(id, {}).duplicate(true)

static func geometry(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("room_geometry", {}).get(id, {}).duplicate(true)

static func boss() -> Dictionary:
	_ensure_loaded()
	return _data.get("boss", {}).duplicate(true)

static func enemy_ids() -> Array:
	_ensure_loaded()
	return _data.get("enemy_ids", []).duplicate(true)

static func room_ids() -> Array:
	_ensure_loaded()
	return _data.get("room_ids", []).duplicate(true)

static func skills_for_difficulty(id: String, difficulty: int) -> Array:
	if difficulty not in range(5): return []
	var definition := enemy(id)
	var result: Array = []
	for tier: int in [0, 2, 4]:
		if tier <= difficulty and definition.get("skills", {}).has(str(tier)):
			result.append(definition.skills[str(tier)].duplicate(true))
	return result

static func validate() -> Array:
	_ensure_loaded()
	return _errors.duplicate(true)

static func _number(value: Variant, minimum: float = 0.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum

static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and float(value[0]) <= 2800 and float(value[1]) <= 1800

static func _skill(value: Variant, tier: int) -> bool:
	return value is Dictionary and value.get("minimum_difficulty") == tier and value.get("parameters") is Dictionary and not str(value.get("source_text", "")).is_empty()

static func validate_data(value: Dictionary) -> Array:
	var errors: Array = []
	if value.get("biome_id") != "B07" or value.get("schema_version") != 1:
		errors.append("Invalid B07 catalog identity/schema")
	if value.get("status") != "runtime_candidate" or value.get("runtime_enabled") != false:
		errors.append("B07 catalog must leave release gating to NumericalRules")
	for key: String in ["profiles", "enemies", "rooms", "boss", "mechanics", "progression", "contracts", "blueprint", "room_geometry"]:
		if not value.get(key) is Dictionary: errors.append("Missing dictionary: " + key)
	for key: String in ["enemy_ids", "room_ids"]:
		if not value.get(key) is Array: errors.append("Missing array: " + key)
	if not errors.is_empty(): return errors
	if value.enemies.size() != 18 or value.enemy_ids.size() != 18: errors.append("Expected 18 B07 species")
	if value.rooms.size() != 7 or value.room_ids.size() != 7 or value.room_geometry.size() != 7: errors.append("Expected six B07 rooms and BO07")
	if value.profiles.size() != 6: errors.append("Expected six input profiles")
	# JSON arrays contain floats; compare each numeric value, not Array's
	# type-sensitive nested equality against an integer constant array.
	var zone_levels: Variant = value.progression.get("zone_levels")
	if not zone_levels is Array or zone_levels.size() != 3:
		errors.append("Invalid B07 progression levels")
	else:
		for index in range(3):
			if not _number(zone_levels[index]) or float(zone_levels[index]) != float(LEVELS[index]): errors.append("Invalid B07 progression level")
	if value.progression.get("previous_boss") != "BO06": errors.append("Invalid B07 progression prerequisite")
	var names: Array = []
	for index in range(1, 19):
		var id := "B07-M%02d" % index
		if not value.enemies.get(id) is Dictionary or value.enemy_ids.count(id) != 1:
			errors.append("Invalid enemy membership: " + id)
			continue
		var entry: Dictionary = value.enemies[id]
		if entry.get("enemy_id") != id or entry.get("biome_id") != "B07" or entry.get("implementation_status") != "runtime_candidate": errors.append(id + " invalid identity")
		for key: String in ["name", "name_en", "silhouette"]:
			if str(entry.get(key, "")).is_empty(): errors.append(id + " missing " + key)
		if names.has(entry.get("name")): errors.append(id + " duplicated name")
		names.append(entry.get("name"))
		var profile := str(entry.get("profile", ""))
		if profile not in PROFILE_IDS or not entry.get("raw_stats") is Dictionary or entry.get("raw_stats") != value.profiles.get(profile):
			errors.append(id + " invalid raw profile")
		else:
			for key: String in ["max_hp", "damage", "move_speed", "armor", "magic_resist", "attack_range", "recovery_seconds"]:
				if not _number(entry.raw_stats.get(key), 0.01): errors.append(id + " invalid stat " + key)
		if entry.get("introduced_level") != (31 if index <= 6 else 33 if index <= 12 else 35): errors.append(id + " invalid first level")
		if not entry.get("skills") is Dictionary or not entry.get("unresolved_parameters") is Array:
			errors.append(id + " missing skill contract")
			continue
		for tier: int in [0, 2, 4]:
			if not _skill(entry.skills.get(str(tier)), tier): errors.append(id + " invalid D%d skill" % tier)
	var introduced: Array = []
	for index in range(7):
		var id := "L%02d" % (37 + index) if index < 6 else "BO07"
		if not value.rooms.get(id) is Dictionary or value.room_ids.count(id) != 1:
			errors.append("Invalid room membership: " + id)
			continue
		var entry: Dictionary = value.rooms[id]
		if entry.get("room_id") != id or entry.get("biome_id") != "B07" or entry.get("enemy_level") != [31, 31, 33, 33, 35, 35, 35][index]: errors.append(id + " invalid room identity/level")
		if not entry.get("introduced_enemy_ids") is Array:
			errors.append(id + " missing introductions")
			continue
		for enemy_id: Variant in entry.introduced_enemy_ids:
			if not value.enemies.has(enemy_id) or introduced.has(enemy_id): errors.append(id + " repeated/unknown introduction")
			introduced.append(enemy_id)
		_validate_geometry(value.room_geometry.get(id), id, errors)
	if introduced.size() != 18: errors.append("D0 introductions must cover every species")
	var king: Dictionary = value.boss
	if king.get("boss_id") != "BO07" or king.get("biome_id") != "B07" or king.get("level") != 35: errors.append("Invalid BO07 identity")
	if not king.get("skills") is Array or not king.get("phases") is Array:
		errors.append("Missing BO07 skills/phases")
		return errors
	if king.skills.size() != 6 or king.phases.size() != 3: errors.append("Invalid BO07 skills/phases count")
	else:
		for index in range(6):
			if not _skill(king.skills[index], [0, 0, 1, 2, 3, 4][index]): errors.append("Invalid BO07 difficulty gate")
	return errors

static func _validate_geometry(value: Variant, id: String, errors: Array) -> void:
	if not value is Dictionary or value.get("room_id") != id or value.get("biome_id") != "B07":
		errors.append(id + " missing fixed geometry")
		return
	for key: String in ["entry", "exit"]:
		if not _point(value.get(key)): errors.append(id + " invalid " + key)
	for key: String in ["walkable_polygon", "main_route", "encounter_anchors", "mirrors", "manual_gates", "stone_covers", "safe_routes"]:
		if not value.get(key) is Array: errors.append(id + " missing geometry " + key)
	if not value.get("mirrors") is Array: return
	var ids: Array = []
	for mirror: Variant in value.mirrors:
		if not mirror is Dictionary or not _point(mirror.get("position")) or not mirror.get("states") is Array:
			errors.append(id + " invalid mirror")
			continue
		if ids.has(mirror.get("id")) or str(mirror.get("id", "")).is_empty(): errors.append(id + " duplicate mirror")
		ids.append(mirror.get("id"))
		if mirror.states.size() != 3 or mirror.get("initial_state") != 0: errors.append(id + " mirror must have three states")
		for state: Variant in mirror.states:
			if not state is Dictionary or not state.get("path") is Array or not state.get("targets") is Array:
				errors.append(id + " missing fixed ray")
				continue
			if state.path.size() < 2 or state.path[0] != mirror.position: errors.append(id + " invalid ray origin")
			for point: Variant in state.path:
				if not _point(point): errors.append(id + " invalid ray coordinate")
