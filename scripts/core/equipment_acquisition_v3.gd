extends RefCounted
## Immutable generator-v3 additions, frozen from the B05 authored catalog.
## Do not read live JSON here: historical receipts must survive future balancing.
## V1/V2 retain their own 124-template archive and level-20 cap.
const LEVEL_CAP := 25
const TEMPLATES := {
	"B05-SG-accessory":{"slot":"charm","race_id":"B05","affix_tendencies_by_power":{"physical":["damage_bonus","max_hp"]},"price":160,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-chest":{"slot":"chest","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","armor"]},"price":180,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-feet":{"slot":"feet","race_id":"B05","affix_tendencies_by_power":{"physical":["move_speed"]},"price":120,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-hands":{"slot":"hands","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","crit_chance"]},"price":120,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-head":{"slot":"head","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","crit_chance"]},"price":140,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-legs":{"slot":"legs","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","armor","magic_resist"]},"price":180,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-ring":{"slot":"ring","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","crit_chance"]},"price":160,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SG-weapon":{"slot":"weapon","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","damage_bonus"]},"price":180,"allowed_heroes":["CH02"],"power_types":["physical"],"set_id":"B05-SG","drop_origin":"B05","class_policy_version":2},
	"B05-SM-accessory":{"slot":"charm","race_id":"B05","affix_tendencies_by_power":{"magic":["max_mana","max_hp"]},"price":160,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-chest":{"slot":"chest","race_id":"B05","affix_tendencies_by_power":{"magic":["max_hp","magic_resist"]},"price":180,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-feet":{"slot":"feet","race_id":"B05","affix_tendencies_by_power":{"magic":["move_speed"]},"price":120,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-hands":{"slot":"hands","race_id":"B05","affix_tendencies_by_power":{"magic":["ability_power","cooldown_reduction"]},"price":120,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-head":{"slot":"head","race_id":"B05","affix_tendencies_by_power":{"magic":["max_mana","magic_resist"]},"price":140,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-legs":{"slot":"legs","race_id":"B05","affix_tendencies_by_power":{"magic":["max_hp","armor","magic_resist"]},"price":180,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-ring":{"slot":"ring","race_id":"B05","affix_tendencies_by_power":{"magic":["ability_power","resource_gain_bonus"]},"price":160,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SM-weapon":{"slot":"weapon","race_id":"B05","affix_tendencies_by_power":{"magic":["ability_power","damage_bonus"]},"price":180,"allowed_heroes":["CH03"],"power_types":["magic"],"set_id":"B05-SM","drop_origin":"B05","class_policy_version":2},
	"B05-SU-accessory":{"slot":"charm","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","damage_reduction","cooldown_reduction"],"magic":["max_hp","damage_reduction","cooldown_reduction"]},"price":160,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-chest":{"slot":"chest","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","damage_reduction"],"magic":["max_hp","damage_reduction"]},"price":180,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-feet":{"slot":"feet","race_id":"B05","affix_tendencies_by_power":{"physical":["move_speed","damage_reduction"],"magic":["move_speed","damage_reduction"]},"price":120,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-hands":{"slot":"hands","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","cooldown_reduction"],"magic":["ability_power","cooldown_reduction"]},"price":120,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-head":{"slot":"head","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","magic_resist"],"magic":["max_hp","magic_resist"]},"price":140,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-legs":{"slot":"legs","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","armor","magic_resist"],"magic":["max_hp","armor","magic_resist"]},"price":180,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-ring":{"slot":"ring","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","max_hp"],"magic":["ability_power","max_hp"]},"price":160,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SU-weapon":{"slot":"weapon","race_id":"B05","affix_tendencies_by_power":{"physical":["attack"],"magic":["ability_power"]},"price":180,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"B05-SU","drop_origin":"B05","class_policy_version":2},
	"B05-SW-accessory":{"slot":"charm","race_id":"B05","affix_tendencies_by_power":{"physical":["resource_gain_bonus","max_hp"]},"price":160,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-chest":{"slot":"chest","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","armor"]},"price":180,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-feet":{"slot":"feet","race_id":"B05","affix_tendencies_by_power":{"physical":["move_speed","damage_reduction"]},"price":120,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-hands":{"slot":"hands","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","crit_chance"]},"price":120,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-head":{"slot":"head","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","armor"]},"price":140,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-legs":{"slot":"legs","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","armor","magic_resist"]},"price":180,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-ring":{"slot":"ring","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","resource_gain_bonus"]},"price":160,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-SW-weapon":{"slot":"weapon","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","damage_bonus"]},"price":180,"allowed_heroes":["CH01"],"power_types":["physical"],"set_id":"B05-SW","drop_origin":"B05","class_policy_version":2},
	"B05-U01":{"slot":"feet","race_id":"B05","affix_tendencies_by_power":{"physical":["move_speed","damage_reduction"],"magic":["move_speed","damage_reduction"]},"price":120,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"","drop_origin":"B05","class_policy_version":2},
	"B05-U02":{"slot":"ring","race_id":"B05","affix_tendencies_by_power":{"physical":["attack","max_hp"],"magic":["ability_power","max_hp"]},"price":160,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"","drop_origin":"B05","class_policy_version":2},
	"B05-U03":{"slot":"charm","race_id":"B05","affix_tendencies_by_power":{"physical":["max_hp","damage_reduction","cooldown_reduction"],"magic":["max_hp","damage_reduction","cooldown_reduction"]},"price":160,"allowed_heroes":["CH01","CH02","CH03"],"power_types":["physical","magic"],"set_id":"","drop_origin":"B05","class_policy_version":2}
}

## Approved B05 acquisition supplement: relative template weight, never a fixed
## drop probability. Wish hits stay locked; non-wish uses original slot/template
## mass times the preference union. Overlaps never stack.
const PREFERENCE_WEIGHT := 2
const ROOM_PREFERRED_SLOTS := {
	"L25":["head", "chest"], "L26":["legs", "feet"],
	"L27":["hands", "ring"], "L28":["hands", "ring"],
	"L29":["weapon", "charm"], "L30":["weapon", "charm"],
	"BO05":["weapon", "charm"]
}
const MONSTER_PREFERRED_SLOT := {
	"B05-M01":"chest", "B05-M02":"head", "B05-M03":"feet",
	"B05-M04":"ring", "B05-M05":"chest", "B05-M06":"legs",
	"B05-M07":"hands", "B05-M08":"charm", "B05-M09":"feet",
	"B05-M10":"head", "B05-M11":"chest", "B05-M12":"hands",
	"B05-M13":"weapon", "B05-M14":"charm", "B05-M15":"legs",
	"B05-M16":"ring", "B05-M17":"weapon", "B05-M18":"charm"
}
const UNIQUE_PREFERENCES := {
	"B05-U01":["L26", "B05-M03", "B05-M06"],
	"B05-U02":["L28", "B05-M04", "B05-M10"],
	"B05-U03":["L30", "B05-M13", "B05-M18"]
}
