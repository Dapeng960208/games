extends SceneTree
## Current roster documentation from production resolvers, no combat/save writes.
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Numbers = preload("res://scripts/combat/enemy_numerical_v2.gd")
const Abilities = preload("res://scripts/combat/enemy_ability_catalog.gd")

func _initialize() -> void:
	var destination := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): destination = argument.trim_prefix("--output=")
	if destination.is_empty():
		push_error("Pass -- --output=<temporary json path>")
		quit(2)
		return
	var document := {"schema":"ProgressiveMonsterCatalog/v1", "ordinary":[], "rooms":[], "sources":{}}
	for path: String in ["data/enemies.json","data/enemy_progression.json","data/rooms.json","data/numerical_v2.json","scripts/combat/enemy_profiles.gd","scripts/combat/enemy_numerical_v2.gd","scripts/combat/enemy_difficulty.gd","scripts/combat/enemy_ability_catalog.gd","scripts/combat/enemy_brain.gd","scripts/combat/enemy_skill_runtime.gd","scripts/combat/enemy_warning_timing.gd","scripts/combat/boss_brain.gd","scripts/combat/enemy_art.gd","scripts/combat/enemy_visual.gd","scripts/combat/enemy_skill_presentation.gd","scripts/combat/enemy_telegraphs.gd","scripts/world/world_catalog.gd"]:
		document.sources[path] = FileAccess.get_sha256("res://" + path)
	for id: String in Catalog.enemy_ids():
		var definition: Dictionary = Catalog.enemy(id)
		var chapter := Numbers.chapter_for_id(id)
		var values: Array = []
		var skill_samples: Array = []
		for d: int in 5:
			var profile := Profiles.resolve(id,chapter*5,"normal",2,d)
			var sample := {"difficulty":d,"level":profile.enemy_level,"mechanic_tier":profile.mechanic_tier}
			for key: String in ["max_hp","damage","armor","magic_resist","move_speed","recovery_seconds"]: sample[key] = profile[key]
			sample["skill_factor"] = Numbers.skill_factor(profile)
			values.append(sample)
			skill_samples.append(Abilities.all_skills(id,d,profile))
		var skills: Array = skill_samples[4]
		for skill: Dictionary in skills:
			var command: Dictionary = skill.command
			skill["damage_by_difficulty"] = []
			skill["runtime_values_by_difficulty"] = []
			skill["timing_by_difficulty"] = []
			for d: int in 5:
				var profile := Profiles.resolve(id,chapter*5,"normal",2,d)
				var packet := Numbers.command(command,profile)
				var active_at_d: bool = int(skill.min_difficulty) <= d and not (id == "M36" and int(skill.min_difficulty) > 0 and int(skill.min_difficulty) != d)
				skill.damage_by_difficulty.append(packet.get("damage",0) if active_at_d else null)
				var values_at_d := {}
				for key: String in ["damage","anchor_health","cover_hp","pod_health","pod_break_armor_loss","amount","status"]:
					if packet.has(key): values_at_d[key] = packet[key]
				skill.runtime_values_by_difficulty.append(values_at_d if active_at_d else null)
				var actual_timing := {}
				for candidate: Dictionary in skill_samples[d]:
					if candidate.ability_id == skill.ability_id: actual_timing = candidate.warning_timing.duplicate(true); break
				skill.timing_by_difficulty.append(actual_timing if active_at_d else null)
		document.ordinary.append({"id":id,"definition":definition,"samples":values,"skills":skills})
	for room_id: String in Catalog.room_ids():
		var room := {"id":room_id,"biome_id":Catalog.room(room_id).biome_id,"difficulties":[]}
		for d: int in 5:
			var composition := {}
			var total := 0
			for zone: int in 3:
				var plan := Profiles.encounter_plan(room_id,zone,d,2)
				total += int(plan.total_count)
				for id: String in plan.composition: composition[id] = int(composition.get(id,0)) + int(plan.composition[id])
			room.difficulties.append({"difficulty":d,"total":total,"composition":composition})
		document.rooms.append(room)
	var file := FileAccess.open(destination,FileAccess.WRITE)
	if file == null:
		push_error("Cannot open export destination")
		quit(2)
		return
	file.store_string(JSON.stringify(document,"\t")+"\n")
	file.close()
	print("Exported54 ordinary profiles,270 numeric samples and120 room compositions")
	quit()
