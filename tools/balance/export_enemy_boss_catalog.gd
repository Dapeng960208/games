extends SceneTree
## Documentation-only export. Pure resolvers and unparented brain fixtures;
## no Game calls, real actors, rooms, combat ticks or profile writes.

const EnemyProfilesScript = preload("res://scripts/combat/enemy_profiles.gd")
const EnemyDifficultyScript = preload("res://scripts/combat/enemy_difficulty.gd")
const EnemyBrainScript = preload("res://scripts/combat/enemy_brain.gd")
const BossProfilesScript = preload("res://scripts/combat/boss_profiles.gd")
const BossBrainScript = preload("res://scripts/combat/boss_brain.gd")
const Abilities = preload("res://scripts/combat/boss_ability_catalog.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const LEVEL_SAMPLES := [1, 5, 10, 15, 20]
const SOURCE_FILES := [
	"data/enemies.json", "data/enemy_progression.json", "data/rooms.json",
	"scripts/combat/enemy_profiles.gd", "scripts/combat/enemy_difficulty.gd",
	"scripts/combat/enemy_brain.gd", "scripts/combat/enemy_biome_skills.gd",
	"scripts/combat/enemy_skill_runtime.gd", "scripts/combat/boss_profiles.gd",
	"scripts/combat/boss_brain.gd", "scripts/combat/boss_ability_catalog.gd",
	"scripts/combat/boss.gd", "scripts/combat/room.gd",
	"scripts/combat/combat_status.gd", "scripts/combat/player.gd",
	"scripts/combat/damage_resolver.gd",
	"config/balance.gd",
]

func _initialize() -> void:
	var output := ""
	var snapshot := "8daa519f2ea1a7dcc3f422b4df96ac81d65986b9"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-snapshot="):
			snapshot = argument.trim_prefix("--source-snapshot=")
	if output.is_empty():
		push_error("Pass -- --output=<temporary JSON path>; no default file is written")
		quit(2)
		return
	var errors := Catalog.validate()
	if not errors.is_empty():
		push_error(str(errors))
		quit(2)
		return
	var hashes := {}
	for path: String in SOURCE_FILES:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var progression: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_progression.json"))
	var ordinary: Array = []
	for enemy_id: String in Catalog.enemy_ids():
		var authored: Dictionary = Catalog.enemy(enemy_id)
		var samples: Array = []
		for rank: String in ["normal", "elite"]:
			for level: int in LEVEL_SAMPLES:
				var profile: Dictionary = EnemyDifficultyScript.apply(EnemyProfilesScript.resolve(enemy_id, level, rank), 0)
				var brain = EnemyBrainScript.new()
				brain.configure(profile)
				var sequence: Array = brain._build_sequence()
				var stages: Array = []
				for index: int in sequence.size():
					var stage: Dictionary = sequence[index].duplicate(true)
					var area: bool = brain.AREA_BEHAVIORS.has(brain.behavior_id) or str(stage.get("kind", "")) == "ground_area" or str(stage.get("landing_shape", "")) in ["circle", "ring"]
					var tell: float = maxf(brain.MIN_AREA_TELL if area else brain.MIN_TELL, float(brain.parameters.get("tell_seconds", authored.get("minimum_tell_seconds", brain.MIN_TELL))))
					if brain.behavior_id == "safe_disarm_ring":
						tell = maxf(tell, float(brain.parameters.get("fuse_seconds", 1.3)))
					if index > 0:
						tell = maxf(tell, float(brain.parameters.get("hazard_stagger_seconds", 0.0)))
					stage["base_telegraph_seconds"] = tell
					stage["locked_seconds"] = brain._lock_seconds()
					stages.append(stage)
				samples.append({"level": level, "rank": rank, "profile": profile, "sequence": stages})
		ordinary.append({"enemy_id": enemy_id, "authored": authored, "base_stats":progression.profiles[enemy_id].base_stats, "samples": samples})
	var appearances := {}
	var encounters: Array = []
	for room_id: String in Catalog.room_ids():
		for difficulty: int in range(5):
			for zone: int in range(3):
				var plan: Dictionary = EnemyProfilesScript.encounter_plan(room_id, zone, difficulty)
				if plan.is_empty():
					push_error("Missing encounter: %s D%d Z%d" % [room_id, difficulty, zone])
					quit(2)
					return
				encounters.append({"room_id":room_id, "biome_id":plan.biome_id, "difficulty":difficulty, "zone_index":zone, "enemy_level":plan.enemy_level, "total_count":plan.total_count, "wave_count":plan.wave_count, "composition":plan.composition})
				for wave: Array in plan.waves:
					for member: Dictionary in wave:
						var key: String = "%s:%s:%d" % [member.enemy_id, member.rank, difficulty]
						if not appearances.has(key):
							appearances[key] = {"room_id":room_id, "zone_index":zone, "wave_index":int(member.wave_index), "level":int(member.enemy_level)}
	var bosses: Array = []
	for boss_id: String in BossProfilesScript.ids():
		var difficulty_samples: Array = []
		for difficulty: int in range(5):
			var profile: Dictionary = BossProfilesScript.resolve(boss_id, difficulty)
			var validation := BossProfilesScript.validate(profile)
			if not validation.is_empty():
				push_error(str(validation))
				quit(2)
				return
			difficulty_samples.append(profile)
		var actions: Array = []
		for phase: int in range(1, 4):
			var phase_actions: Array = BossBrainScript.SEQUENCES[boss_id][phase].duplicate()
			phase_actions.append_array(Abilities.UNLOCKS[boss_id])
			for action: String in phase_actions:
				var brain = BossBrainScript.new()
				brain.configure(BossProfilesScript.resolve(boss_id, 4), 1)
				brain.phase = phase
				var actor := Node2D.new()
				var victim := Node2D.new()
				victim.position = Vector2(400.0, 0.0)
				var command: Dictionary = brain._build_action(actor, victim, action)
				actor.free()
				victim.free()
				actions.append({"action_id":action, "name":Abilities.title(action), "phase":phase, "unlock_difficulty":maxi(0, Abilities.tier(boss_id, action)), "source":"boss_ability_catalog.gd" if Abilities.tier(boss_id, action) > 0 else "boss_brain.gd", "command":command})
		bosses.append({"boss_id":boss_id, "base_level":int(BossProfilesScript.LEVELS[boss_id]), "samples":difficulty_samples, "actions":actions})
	var payload := {
		"schema":"EnemyBossDocumentation/v1", "source_snapshot":snapshot,
		"engine_version":Engine.get_version_info().string, "source_sha256":hashes,
		"level_samples":LEVEL_SAMPLES, "archetype_stats":EnemyProfilesScript.ARCHETYPE_STATS,
		"biomes":Catalog.biomes(), "ordinary":ordinary, "appearances":appearances,
		"encounters":encounters, "bosses":bosses,
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open export path: " + output)
		quit(2)
		return
	file.store_string(JSON.stringify(_plain(payload), "\t") + "\n")
	file.close()
	print("Enemy/boss documentation exported: 36 prototypes, 360 level/rank samples, 360 encounter zones, 20 boss difficulty samples")
	quit(0)

func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[str(key)] = _plain(value[key])
		return result
	if value is Array:
		var result: Array = []
		for member: Variant in value:
			result.append(_plain(member))
		return result
	if value is Vector2:
		return [value.x, value.y]
	if value is Color:
		return value.to_html()
	return value
