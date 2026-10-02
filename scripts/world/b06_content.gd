class_name B06Content
extends RefCounted
## Authored specification only: does not register actors, enable routes, resolve
## combat stats or implement skills. Unknown parameters stay explicit in JSON.
const DATA_PATH := "res://data/b06_content.json"
const PROFILE_IDS := ["F", "R", "C", "S", "A", "T"]
static var _data: Dictionary = {}
static var _errors: Array = []
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		_errors.append("Missing B06 authored catalog")
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(DATA_PATH)) != OK or not parser.data is Dictionary:
		_errors.append("Invalid B06 authored JSON")
		return
	var candidate: Dictionary = parser.data
	_errors = validate_data(candidate)
	if _errors.is_empty():
		_data = candidate.duplicate(true)

static func catalog() -> Dictionary:
	_ensure_loaded()
	return _data.duplicate(true)

static func enemy(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("enemies", {}).get(id, {}).duplicate(true)

static func room(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("rooms", {}).get(id, {}).duplicate(true)

static func boss() -> Dictionary:
	_ensure_loaded()
	return _data.get("boss", {}).duplicate(true)

static func enemy_ids() -> Array:
	_ensure_loaded()
	return _data.get("enemy_ids", []).duplicate(true)

static func room_ids() -> Array:
	_ensure_loaded()
	return _data.get("room_ids", []).duplicate(true)

## Returns authored cumulative additions, not executable combat commands.
static func skills_for_difficulty(id: String, difficulty: int) -> Array:
	if difficulty < 0 or difficulty > 4:
		return []
	var definition := enemy(id)
	var result: Array = []
	for tier: int in [0, 2, 4]:
		if tier <= difficulty and definition.get("skills", {}).has(str(tier)):
			result.append(definition.skills[str(tier)].duplicate(true))
	return result

static func validate() -> Array:
	_ensure_loaded()
	return _errors.duplicate(true)

static func _positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0

static func validate_data(value: Dictionary) -> Array:
	var errors: Array = []
	if value.get("biome_id") != "B06" or value.get("status") != "authored_only" or value.get("runtime_enabled") != false:
		errors.append("B06 catalog must be authored-only and disabled")
	if value.get("schema_version") != 1:
		errors.append("Unsupported B06 schema")
	for key: String in ["profiles", "enemies", "rooms", "boss", "mechanics", "progression", "contracts", "blueprint"]:
		if not value.get(key) is Dictionary:
			errors.append("Missing dictionary: " + key)
	for key: String in ["enemy_ids", "room_ids"]:
		if not value.get(key) is Array:
			errors.append("Missing array: " + key)
	if not errors.is_empty():
		return errors
	var enemies: Dictionary = value.enemies
	var rooms: Dictionary = value.rooms
	if enemies.size() != 18 or value.enemy_ids.size() != 18:
		errors.append("Expected exactly 18 B06 enemies")
	if rooms.size() != 7 or value.room_ids.size() != 7:
		errors.append("Expected six ordinary B06 rooms and BO06")
	if value.profiles.size() != 6:
		errors.append("Expected six raw input profiles")
	var seen_names: Array = []
	for index in range(1, 19):
		var id := "B06-M%02d" % index
		if not enemies.get(id) is Dictionary or value.enemy_ids.count(id) != 1:
			errors.append("Invalid enemy membership: " + id)
			continue
		var entry: Dictionary = enemies[id]
		if entry.get("enemy_id") != id or entry.get("biome_id") != "B06" or entry.get("implementation_status") != "authored_only":
			errors.append(id + " invalid identity/status")
		for key: String in ["name", "name_en", "silhouette"]:
			if str(entry.get(key, "")).is_empty():
				errors.append(id + " missing " + key)
		if seen_names.has(entry.get("name")):
			errors.append(id + " duplicated identity")
		seen_names.append(entry.get("name"))
		var profile := str(entry.get("profile", ""))
		if profile not in PROFILE_IDS or not value.profiles.get(profile) is Dictionary or not entry.get("raw_stats") is Dictionary:
			errors.append(id + " invalid raw profile")
			continue
		var raw: Dictionary = entry.raw_stats
		if raw != value.profiles[profile]:
			errors.append(id + " raw stats differ from authored profile")
		for key: String in ["max_hp", "damage", "move_speed", "armor", "magic_resist", "attack_range", "recovery_seconds"]:
			if not _positive_number(raw.get(key)):
				errors.append(id + " invalid raw stat: " + key)
		var expected_level := 26 if index <= 6 else 28 if index <= 12 else 30
		if entry.get("introduced_level") != expected_level:
			errors.append(id + " invalid first level")
		if not entry.get("unresolved_parameters") is Array or not entry.get("skills") is Dictionary:
			errors.append(id + " missing skill/unresolved contract")
			continue
		for tier: int in [0, 2, 4]:
			var skill: Variant = entry.skills.get(str(tier))
			if not skill is Dictionary:
				errors.append(id + " missing D%d skill" % tier)
			elif skill.get("minimum_difficulty") != tier or not skill.get("parameters") is Dictionary or str(skill.get("source_text", "")).is_empty():
				errors.append(id + " invalid D%d skill" % tier)
	var introductions: Array = []
	for index in range(7):
		var id := "L%02d" % (31 + index) if index < 6 else "BO06"
		if not rooms.get(id) is Dictionary or value.room_ids.count(id) != 1:
			errors.append("Invalid room membership: " + id)
			continue
		var entry: Dictionary = rooms[id]
		if entry.get("room_id") != id or entry.get("biome_id") != "B06":
			errors.append(id + " invalid identity")
		var level: int = [26, 26, 28, 28, 30, 30, 30][index]
		if entry.get("enemy_level") != level or entry.get("navigation_polygon") != null or entry.get("wave_members") != null:
			errors.append(id + " invalid level or fabricated geometry/waves")
		if not entry.get("introduced_enemy_ids") is Array or not entry.get("blueprint_percent_anchors") is Dictionary:
			errors.append(id + " missing introduction/anchor contract")
			continue
		for enemy_id: String in entry.introduced_enemy_ids:
			if not enemies.has(enemy_id) or introductions.has(enemy_id):
				errors.append(id + " invalid/repeated introduction")
			introductions.append(enemy_id)
		for anchor: Variant in entry.blueprint_percent_anchors.values():
			if not anchor is Array or anchor.is_empty():
				errors.append(id + " invalid anchor")
				continue
			var points: Array = anchor if anchor[0] is Array else [anchor]
			for point: Variant in points:
				if not point is Array or point.size() != 2:
					errors.append(id + " invalid percent point")
					continue
				for coordinate: Variant in point:
					if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate) < 0 or float(coordinate) > 100:
						errors.append(id + " percent coordinate outside blueprint")
	if introductions.size() != 18:
		errors.append("D0 room introductions must cover all 18 identities")
	var king: Dictionary = value.boss
	if king.get("boss_id") != "BO06" or king.get("biome_id") != "B06" or king.get("level") != 30:
		errors.append("Invalid B06 boss identity")
	if not king.get("skills") is Array or not king.get("phases") is Array:
		errors.append("Missing B06 boss skill/phase contracts")
		return errors
	var gates: Array = []
	for skill: Variant in king.skills:
		if not skill is Dictionary or not skill.get("parameters") is Dictionary:
			errors.append("Invalid B06 boss skill")
			continue
		var gate: Variant = skill.get("minimum_difficulty")
		if not (gate is int or gate is float) or not is_finite(float(gate)) or gate != int(gate):
			errors.append("Invalid B06 boss difficulty value")
			continue
		gates.append(int(gate))
	if gates != [0, 0, 1, 2, 3, 4] or king.phases.size() != 3:
		errors.append("Invalid B06 boss difficulty/phase coverage")
	return errors
