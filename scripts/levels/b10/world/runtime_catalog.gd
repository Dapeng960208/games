extends RefCounted
## Runtime entry, independent of B05/B06 debug candidate switches.
const Content = preload("res://scripts/levels/b10/world/content.gd")
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")

static func biome() -> Dictionary:
	return {"biome_id": "B10", "name": "星辉龙庭", "name_en": "Starlit Dragon Court",
		"race": "星辉龙族", "race_en": "Starlit Dragonkin",
		"room_ids": ["L55", "L56", "L57", "L58", "L59", "L60"],
		"enemy_ids": Content.enemy_ids(), "boss_id": "BO10", "unlock_requires": "BO09",
		"accent": "b595e7", "visual": "日光珍珠白龙庭、淡紫鳞楼与金色星环", "final_chapter": true}

static func room(id: String) -> Dictionary:
	if id not in biome().room_ids: return {}
	var result := Content.room(id)
	var definition := Geometry.room(id)
	var zones: Array = []
	for index: int in definition.encounter_anchors.size():
		zones.append({"id": id + "_encounter_" + str(index + 1),
			"center": definition.encounter_anchors[index], "concurrent_cap": 3,
			"activation_distance": 800, "minimum_player_spawn_distance": 430})
	var wave: Array = []
	for enemy_id: String in result.introduced_enemy_ids:
		wave.append({"enemy_id": enemy_id, "count": 1})
	result.merge({"role_tags": ["branch", "objective", "elite_objective"],
		"objective_id": "b10_dragon_" + id.to_lower(), "objective_count": 0,
		"expedition_objective_count": 0, "topology_id": "b10_fixed_" + id.to_lower(),
		"mechanic": result.encounter_text, "reference_wave": wave,
		"preview": {"objective": result.encounter_text,
			"risk": "有限波次后出现独立巨龙；星门和步行环路始终可达", "reward": result.reward_bias_text},
		"geometry": {"encounter_zones": zones, "room_concurrent_cap": 6}}, true)
	return result

static func enemy(id: String) -> Dictionary:
	return preload("res://scripts/levels/b10/combat/enemy_skills.gd").enemy_definition(id)

static func boss() -> Dictionary:
	return preload("res://scripts/levels/b10/combat/enemy_skills.gd").boss_definition("BO10")
