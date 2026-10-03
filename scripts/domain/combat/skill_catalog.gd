class_name SkillCatalog
extends RefCounted
## Stable identities are separate from the four input actions.

const HEROES := ["CH01", "CH02", "CH03"]
const INPUT_SLOTS := ["q", "secondary", "f", "ultimate"]
const KIT_PATHS := {
	"CH01":"res://scripts/gameplay/characters/kits/warrior_kit.gd",
	"CH02":"res://scripts/gameplay/characters/kits/gunner_kit.gd",
	"CH03":"res://scripts/gameplay/characters/kits/mage_kit.gd",
}
const GROUP_ROOMS := ["L02", "L05", "L08", "L11", "L14", "L17", "L20", "L23"]
const GROUP_NAMES := ["浮晶桥支路档案", "升降回路任务", "蜂台支路档案", "研究匣任务", "糖仓支路档案", "墓灯任务", "岩街支路档案", "提灯任务"]

static func skills(hero_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not KIT_PATHS.has(hero_id):
		return result
	var kit: Script = load(KIT_PATHS[hero_id])
	if kit == null or not kit.has_method("skill_specs"):
		return result
	var entries: Array = kit.call("skill_specs")
	for index: int in entries.size():
		var entry: Dictionary = entries[index].duplicate(true)
		entry["skill_id"] = "%s_SK%02d" % [hero_id, index + 1]
		entry["hero_id"] = hero_id
		entry["hero"] = hero_id
		entry["icon_id"] = "skill.%s" % str(entry.skill_id).to_lower()
		entry["base_cooldown"] = float(entry.get("base_cooldown", entry.get("cooldown", 0.0)))
		entry["source"] = source_for(index + 1)
		entry["acquisition_group"] = "" if index < 4 else "SG%02d" % (index - 3)
		result.append(entry)
	return result

static func skill(skill_id: String) -> Dictionary:
	var hero_id: String = skill_id.get_slice("_", 0)
	for entry: Dictionary in skills(hero_id):
		if str(entry.skill_id) == skill_id:
			return entry
	return {}

static func starter_ids(hero_id: String) -> Array[String]:
	var result: Array[String] = []
	if hero_id in HEROES:
		for index: int in 4:
			result.append("%s_SK%02d" % [hero_id, index + 1])
	return result

static func source_for(skill_number: int) -> Dictionary:
	if skill_number <= 4:
		return {"kind":"starter", "name":"职业初始技能", "room_id":"", "group_id":""}
	var group_index: int = skill_number - 5
	if group_index < 0 or group_index >= GROUP_ROOMS.size():
		return {}
	return {"kind":"exploration" if group_index % 2 == 0 else "quest", "name":GROUP_NAMES[group_index], "room_id":GROUP_ROOMS[group_index], "group_id":"SG%02d" % (group_index + 1)}

static func group_skills(group_id: String) -> Array[String]:
	var result: Array[String] = []
	if group_id.length() != 4 or not group_id.begins_with("SG"):
		return result
	var index: int = int(group_id.substr(2))
	if index < 1 or index > 8 or group_id != "SG%02d" % index:
		return result
	for hero_id: String in HEROES:
		result.append("%s_SK%02d" % [hero_id, index + 4])
	return result
