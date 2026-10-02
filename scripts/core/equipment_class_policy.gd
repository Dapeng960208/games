class_name EquipmentClassPolicy
extends RefCounted
## Released qualification contract. Adding/changing a membership requires a new
## policy/generator version; historical generation keeps its archived contract.
const VERSION := 1
const HEROES := ["CH01", "CH02", "CH03"]
const SET_HEROES := {
	"S01":["CH03"], "S02":["CH01","CH02","CH03"], "S03":["CH01","CH02","CH03"],
	"S04":["CH02"], "S05":["CH01"], "S06":["CH01","CH02","CH03"],
	"S07":["CH02"], "S08":["CH01","CH02","CH03"], "S09":["CH01"],
	"S10":["CH01","CH02","CH03"], "S11":["CH03"], "S12":["CH02"],
	"S13":["CH01","CH02","CH03"], "S14":["CH01"]
}

static func allowed_heroes(set_id: String) -> Array:
	return HEROES.duplicate() if set_id.is_empty() else SET_HEROES.get(set_id, []).duplicate()

static func power_type(hero_id: String) -> String:
	return "magic" if hero_id == "CH03" else "physical"

## Stable template membership for validating archived acquisition metadata.
## Do not consult a mutable live catalog while verifying an existing receipt.
static func template_allowed_heroes(template_id: String) -> Array:
	if not template_id.begins_with("EQ") or not template_id.trim_prefix("EQ").is_valid_int(): return []
	var number := int(template_id.trim_prefix("EQ"))
	if template_id != "EQ%02d" % number or number < 1 or number > 124: return []
	var set_number := 0
	if number <= 60:
		var position := (number - 1) % 10
		if position >= 2: set_number = position - 1
	elif number <= 96:
		set_number = 9 + int((number - 61) / 6)
	else:
		set_number = 1 + int((number - 97) / 2)
	return allowed_heroes("" if set_number == 0 else "S%02d" % set_number)
