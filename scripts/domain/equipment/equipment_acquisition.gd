class_name EquipmentAcquisition
extends RefCounted
## Pure, versioned generation. Callers persist each returned receipt atomically
## with its acquisition, and pass it on retry. No profile, IO or global RNG.
## Natural kill room caps and successful-extraction pity counters belong to the
## reward owner. This module only generates the frozen event's value records.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const V3 = preload("res://scripts/domain/equipment/equipment_acquisition_v3.gd")
const V4 = preload("res://scripts/domain/equipment/equipment_acquisition_v4.gd")
const GENERATOR_VERSION := 4
# Immutable v2 eligibility overlay. All numerical/roll definitions remain v1.
const V2_SET_HEROES := {"S01":["CH03"],"S02":["CH01","CH02","CH03"],"S03":["CH01","CH02","CH03"],"S04":["CH02"],"S05":["CH01"],"S06":["CH01","CH02","CH03"],"S07":["CH02"],"S08":["CH01","CH02","CH03"],"S09":["CH01"],"S10":["CH01","CH02","CH03"],"S11":["CH03"],"S12":["CH02"],"S13":["CH01","CH02","CH03"],"S14":["CH01"]}
const V2_TEMPLATE_SETS := {"EQ01":"","EQ02":"","EQ03":"S01","EQ04":"S02","EQ05":"S03","EQ06":"S04","EQ07":"S05","EQ08":"S06","EQ09":"S07","EQ10":"S08","EQ11":"","EQ12":"","EQ13":"S01","EQ14":"S02","EQ15":"S03","EQ16":"S04","EQ17":"S05","EQ18":"S06","EQ19":"S07","EQ20":"S08","EQ21":"","EQ22":"","EQ23":"S01","EQ24":"S02","EQ25":"S03","EQ26":"S04","EQ27":"S05","EQ28":"S06","EQ29":"S07","EQ30":"S08","EQ31":"","EQ32":"","EQ33":"S01","EQ34":"S02","EQ35":"S03","EQ36":"S04","EQ37":"S05","EQ38":"S06","EQ39":"S07","EQ40":"S08","EQ41":"","EQ42":"","EQ43":"S01","EQ44":"S02","EQ45":"S03","EQ46":"S04","EQ47":"S05","EQ48":"S06","EQ49":"S07","EQ50":"S08","EQ51":"","EQ52":"","EQ53":"S01","EQ54":"S02","EQ55":"S03","EQ56":"S04","EQ57":"S05","EQ58":"S06","EQ59":"S07","EQ60":"S08","EQ61":"S09","EQ62":"S09","EQ63":"S09","EQ64":"S09","EQ65":"S09","EQ66":"S09","EQ67":"S10","EQ68":"S10","EQ69":"S10","EQ70":"S10","EQ71":"S10","EQ72":"S10","EQ73":"S11","EQ74":"S11","EQ75":"S11","EQ76":"S11","EQ77":"S11","EQ78":"S11","EQ79":"S12","EQ80":"S12","EQ81":"S12","EQ82":"S12","EQ83":"S12","EQ84":"S12","EQ85":"S13","EQ86":"S13","EQ87":"S13","EQ88":"S13","EQ89":"S13","EQ90":"S13","EQ91":"S14","EQ92":"S14","EQ93":"S14","EQ94":"S14","EQ95":"S14","EQ96":"S14","EQ97":"S01","EQ98":"S01","EQ99":"S02","EQ100":"S02","EQ101":"S03","EQ102":"S03","EQ103":"S04","EQ104":"S04","EQ105":"S05","EQ106":"S05","EQ107":"S06","EQ108":"S06","EQ109":"S07","EQ110":"S07","EQ111":"S08","EQ112":"S08","EQ113":"S09","EQ114":"S09","EQ115":"S10","EQ116":"S10","EQ117":"S11","EQ118":"S11","EQ119":"S12","EQ120":"S12","EQ121":"S13","EQ122":"S13","EQ123":"S14","EQ124":"S14"}
const VALIDATION_CACHE_LIMIT := 2048
static var _validated_fingerprints: Dictionary = {}
static var _v1_contract_hash := ""
## Immutable generator-v1 contract, captured from numerical_v2.json and the
## approved V2 registry overlay. Future balance changes must add a new generator
## version/snapshot; never rewrite this archive or validate history from live
## tables. Receipts carry only the version, not a caller-editable rules snapshot.
const V1_PARAMETERS := {
	"source_commit":"8daa519f2ea1a7dcc3f422b4df96ac81d65986b9",
	"versions":{"ruleset":2.0,"equipment_instance":1.0,"reward_policy":2.0,"optional_chest_receipt":2.0,"scale":10.0},
	"roll_order":["pool","rarity","slot","template","item_level","enhancement_rank","enhancement_gains","main_rolls","affixes"],
	"main_roll":{"min":0.85,"max":1.15,"steps":100.0},
	"rarities":{"white":{"name":"白","main_multiplier":1.0,"affix_count":0.0,"percentage_multiplier":1.0},"green":{"name":"绿","main_multiplier":1.2,"affix_count":2.0,"percentage_multiplier":1.1},"purple":{"name":"紫","main_multiplier":1.5,"affix_count":3.0,"percentage_multiplier":1.25},"gold":{"name":"金","main_multiplier":1.875,"affix_count":4.0,"percentage_multiplier":1.4}},
	"slots":{"weapon":{"name":"武器","physical":{"attack":90.0},"magic":{"ability_power":140.0}},"head":{"name":"头部","shared":{"max_hp":160.0,"armor":40.0,"magic_resist":40.0}},"chest":{"name":"胸部","shared":{"max_hp":320.0,"armor":80.0,"magic_resist":80.0}},"hands":{"name":"手部","physical":{"attack":30.0},"magic":{"ability_power":40.0}},"legs":{"name":"裤子","shared":{"max_hp":240.0,"armor":60.0,"magic_resist":60.0}},"feet":{"name":"鞋子","shared":{"max_hp":120.0,"move_speed":0.03}},"ring":{"name":"戒指","physical":{"attack":30.0},"magic":{"ability_power":40.0}},"charm":{"name":"饰品","physical":{"attack":40.0},"magic":{"ability_power":60.0}}},
	"affixes":{"attack":{"name":"攻击","min":20.0,"max":40.0,"scaling":"flat","slots":["weapon","hands","ring","charm"],"power_type":"physical"},"ability_power":{"name":"法强","min":30.0,"max":60.0,"scaling":"flat","slots":["weapon","hands","ring","charm"],"power_type":"magic"},"max_hp":{"name":"生命","min":100.0,"max":200.0,"scaling":"flat","slots":["head","chest","hands","legs","feet","ring","charm"]},"hp_ratio":{"name":"生命加成","min":0.02,"max":0.05,"scaling":"percent","slots":["head","chest","legs","ring","charm"]},"armor":{"name":"护甲","min":20.0,"max":60.0,"scaling":"flat","slots":["head","chest","hands","legs","feet","ring","charm"]},"magic_resist":{"name":"魔抗","min":20.0,"max":60.0,"scaling":"flat","slots":["head","chest","hands","legs","feet","ring","charm"]},"max_mana":{"name":"法力容量","min":80.0,"max":160.0,"scaling":"flat","slots":["head","ring","charm"],"power_type":"magic"},"armor_penetration":{"name":"物穿","min":20.0,"max":50.0,"scaling":"flat","slots":["weapon","hands","ring","charm"],"power_type":"physical"},"magic_penetration":{"name":"法穿","min":20.0,"max":50.0,"scaling":"flat","slots":["weapon","hands","ring","charm"],"power_type":"magic"},"crit_chance":{"name":"暴击率","min":0.01,"max":0.03,"scaling":"percent","slots":["weapon","head","hands","ring","charm"]},"crit_multiplier":{"name":"暴击伤害增量","min":0.05,"max":0.15,"scaling":"percent","slots":["weapon","hands","ring","charm"]},"attack_speed":{"name":"攻速","min":0.02,"max":0.05,"scaling":"percent","slots":["weapon","hands","feet","ring","charm"]},"cooldown_reduction":{"name":"冷却缩减","min":0.01,"max":0.03,"scaling":"percent","slots":["head","hands","ring","charm"]},"move_speed":{"name":"移速","min":0.02,"max":0.04,"scaling":"percent","slots":["legs","feet","ring","charm"]},"damage_bonus":{"name":"直接增伤","min":0.03,"max":0.06,"scaling":"percent","slots":["weapon","hands","ring","charm"]},"damage_reduction":{"name":"装备减伤","min":0.01,"max":0.025,"scaling":"percent","slots":["head","chest","legs","feet","ring","charm"]},"resource_gain_bonus":{"name":"职业资源回复加成","min":0.05,"max":0.12,"scaling":"percent","slots":["head","hands","ring","charm"]},"status_duration":{"name":"状态持续时间","min":0.03,"max":0.08,"scaling":"percent","slots":["weapon","hands","ring","charm"]},"burn_damage":{"name":"灼烧伤害加成","min":0.04,"max":0.1,"scaling":"percent","slots":["weapon","hands","ring","charm"]},"corrosion_damage_bonus":{"name":"腐蚀增伤","min":0.04,"max":0.1,"scaling":"percent","slots":["weapon","hands","ring","charm"]},"true_damage_bonus":{"name":"原始命中真实附伤","min":10.0,"max":20.0,"scaling":"flat","slots":["weapon","ring","charm"]}},
	"affix_tendency_weight":2.0,
	"affix_default_weight":1.0,
	"normal_quality_weights":[[60.0,35.0,5.0,0.0],[20.0,60.0,20.0,0.0],[5.0,35.0,55.0,5.0],[0.0,15.0,70.0,15.0],[0.0,5.0,70.0,25.0]],
	"elite_quality_weights":[[0.0,80.0,20.0,0.0],[0.0,50.0,48.0,2.0],[0.0,20.0,70.0,10.0],[0.0,5.0,65.0,30.0],[0.0,0.0,60.0,40.0]],
	"boss_quality_weights":[[0.0,80.0,20.0,0.0],[0.0,40.0,55.0,5.0],[0.0,10.0,75.0,15.0],[0.0,0.0,60.0,40.0],[0.0,0.0,40.0,60.0]],
	"drop_enhancement":{"non_gold":{"0":60.0,"1":20.0,"2":10.0,"3":5.0,"4":3.0,"5":2.0},"gold":{"0":70.0,"1":30.0},"max_by_rarity":{"white":5.0,"green":5.0,"purple":5.0,"gold":1.0}},
	"kill_drop_chance":{"normal":0.01,"elite":0.15,"summon":0.0},
	"boss_drop_counts":[2.0,2.0,3.0,3.0,4.0],
	"guaranteed_room_drop_count":1.0,
	"wish_slot_chance":0.5,
	"item_level_offsets":{"-1":20.0,"0":60.0,"1":20.0},
	"enhancement_random":{"rank_success_rate":1.0,"gain_percent_weights":{"8":10.0,"9":20.0,"10":40.0,"11":20.0,"12":10.0},"gain_scope":"all_flat_main_attributes_of_this_item","gain_formula":"1 + sum(step_gain_percent)/100","reroll_unlock_hero_level":10.0,"reroll_keep_rule":"max(old_gain_percent, new_gain_percent)","reroll_no_improvement_pity":4.0,"pity_gain_percent_increment":1.0,"gain_percent_max":12.0,"reroll_gold_fraction":0.5,"reroll_material_fraction":0.5,"reroll_core":0.0,"reroll_refundable":false,"inherit_overlap_rule":"max_per_step; ties_keep_target_counter","inherit_require":"source_rank >= target_rank and merged_total_gain > target_total_gain","legacy_gain_percent_per_step":10.0,"low_level_reroll_makeup":"per operation ceil(base_rank_gold*0.5*S(target_ilvl)) minus ceil(base_rank_gold*0.5*S(settled_price_ilvl_peak)), positive only; includes no-improvement operations; update each peak by max"},
	"enhancement_gold":[40.0,60.0,90.0,130.0,180.0,240.0,310.0,390.0,480.0,580.0],
	"cost_item_level_per_level":0.03,
	"shop_price_multiplier":{"white":0.8,"green":1.2},
	"shop_rarities":["white","green"],
	"forge_costs":{"green":{"gold":200.0,"common":12.0,"race":6.0,"core":0.0},"purple":{"gold":400.0,"common":24.0,"race":12.0,"core":2.0},"gold":{"gold":800.0,"common":48.0,"race":24.0,"core":6.0}}
}
const V1_TEMPLATES := {
	"EQ01":{"slot":"weapon","drop_origin":"B01","race_id":"B01","affix_tendencies":["attack","armor_penetration"],"price":60.0},
	"EQ02":{"slot":"weapon","drop_origin":"B02","race_id":"B02","affix_tendencies":["attack_speed","crit_chance"],"price":100.0},
	"EQ03":{"slot":"weapon","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","magic_penetration"],"price":180.0},
	"EQ04":{"slot":"weapon","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","max_mana"],"price":180.0},
	"EQ05":{"slot":"weapon","drop_origin":"B02","race_id":"B02","affix_tendencies":["crit_chance","crit_multiplier"],"price":180.0},
	"EQ06":{"slot":"weapon","drop_origin":"B02","race_id":"B02","affix_tendencies":["attack","armor_penetration"],"price":180.0},
	"EQ07":{"slot":"weapon","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp","armor"],"price":180.0},
	"EQ08":{"slot":"weapon","drop_origin":"B03","race_id":"B03","affix_tendencies":["attack","true_damage_bonus"],"price":180.0},
	"EQ09":{"slot":"weapon","drop_origin":"B04","race_id":"B04","affix_tendencies":["attack","crit_multiplier"],"price":180.0},
	"EQ10":{"slot":"weapon","drop_origin":"B04","race_id":"B04","affix_tendencies":["ability_power","magic_penetration"],"price":180.0},
	"EQ100":{"slot":"ring","drop_origin":"B01","race_id":"B01","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ101":{"slot":"legs","drop_origin":"B02","race_id":"B02","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ102":{"slot":"ring","drop_origin":"B02","race_id":"B02","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ103":{"slot":"legs","drop_origin":"B02","race_id":"B02","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ104":{"slot":"ring","drop_origin":"B02","race_id":"B02","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ105":{"slot":"legs","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ106":{"slot":"ring","drop_origin":"B03","race_id":"B03","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ107":{"slot":"legs","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ108":{"slot":"ring","drop_origin":"B03","race_id":"B03","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ109":{"slot":"legs","drop_origin":"B04","race_id":"B04","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ11":{"slot":"head","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp"],"price":60.0},
	"EQ110":{"slot":"ring","drop_origin":"B04","race_id":"B04","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ111":{"slot":"legs","drop_origin":"B04","race_id":"B04","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ112":{"slot":"ring","drop_origin":"B04","race_id":"B04","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ113":{"slot":"legs","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ114":{"slot":"ring","shop_only":true,"race_id":"B01","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ115":{"slot":"legs","shop_only":true,"race_id":"B02","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ116":{"slot":"ring","shop_only":true,"race_id":"B02","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ117":{"slot":"legs","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ118":{"slot":"ring","shop_only":true,"race_id":"B01","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ119":{"slot":"legs","shop_only":true,"race_id":"B02","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ12":{"slot":"head","drop_origin":"B04","race_id":"B04","affix_tendencies":["ability_power","max_mana"],"price":100.0},
	"EQ120":{"slot":"ring","shop_only":true,"race_id":"B02","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ121":{"slot":"legs","shop_only":true,"race_id":"B03","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ122":{"slot":"ring","shop_only":true,"race_id":"B03","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ123":{"slot":"legs","shop_only":true,"race_id":"B04","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ124":{"slot":"ring","shop_only":true,"race_id":"B04","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ13":{"slot":"head","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","magic_resist"],"price":140.0},
	"EQ14":{"slot":"head","drop_origin":"B01","race_id":"B01","affix_tendencies":["magic_resist","max_mana"],"price":140.0},
	"EQ15":{"slot":"head","drop_origin":"B02","race_id":"B02","affix_tendencies":["crit_chance","armor_penetration"],"price":140.0},
	"EQ16":{"slot":"head","drop_origin":"B02","race_id":"B02","affix_tendencies":["armor_penetration","attack"],"price":140.0},
	"EQ17":{"slot":"head","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp"],"price":140.0},
	"EQ18":{"slot":"head","drop_origin":"B03","race_id":"B03","affix_tendencies":["cooldown_reduction"],"price":140.0},
	"EQ19":{"slot":"head","drop_origin":"B04","race_id":"B04","affix_tendencies":["crit_chance"],"price":140.0},
	"EQ20":{"slot":"head","drop_origin":"B04","race_id":"B04","affix_tendencies":["magic_resist","cooldown_reduction"],"price":140.0},
	"EQ21":{"slot":"chest","drop_origin":"B01","race_id":"B01","affix_tendencies":["max_hp","armor"],"price":60.0},
	"EQ22":{"slot":"chest","drop_origin":"B02","race_id":"B02","affix_tendencies":["damage_reduction","magic_resist"],"price":100.0},
	"EQ23":{"slot":"chest","drop_origin":"B01","race_id":"B01","affix_tendencies":["max_hp","magic_resist"],"price":180.0},
	"EQ24":{"slot":"chest","drop_origin":"B01","race_id":"B01","affix_tendencies":["max_hp","max_mana"],"price":180.0},
	"EQ25":{"slot":"chest","drop_origin":"B02","race_id":"B02","affix_tendencies":["max_hp","armor"],"price":180.0},
	"EQ26":{"slot":"chest","drop_origin":"B02","race_id":"B02","affix_tendencies":["max_hp","magic_resist"],"price":180.0},
	"EQ27":{"slot":"chest","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp"],"price":180.0},
	"EQ28":{"slot":"chest","drop_origin":"B03","race_id":"B03","affix_tendencies":["damage_reduction"],"price":180.0},
	"EQ29":{"slot":"chest","drop_origin":"B04","race_id":"B04","affix_tendencies":["max_hp"],"price":180.0},
	"EQ30":{"slot":"chest","drop_origin":"B04","race_id":"B04","affix_tendencies":["move_speed"],"price":180.0},
	"EQ31":{"slot":"hands","drop_origin":"B03","race_id":"B03","affix_tendencies":["attack"],"price":60.0},
	"EQ32":{"slot":"hands","drop_origin":"B04","race_id":"B04","affix_tendencies":["ability_power","max_mana"],"price":100.0},
	"EQ33":{"slot":"hands","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","magic_penetration"],"price":120.0},
	"EQ34":{"slot":"hands","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","attack_speed"],"price":120.0},
	"EQ35":{"slot":"hands","drop_origin":"B02","race_id":"B02","affix_tendencies":["crit_chance"],"price":120.0},
	"EQ36":{"slot":"hands","drop_origin":"B02","race_id":"B02","affix_tendencies":["attack","armor_penetration"],"price":120.0},
	"EQ37":{"slot":"hands","drop_origin":"B03","race_id":"B03","affix_tendencies":["attack"],"price":120.0},
	"EQ38":{"slot":"hands","drop_origin":"B03","race_id":"B03","affix_tendencies":["attack"],"price":120.0},
	"EQ39":{"slot":"hands","drop_origin":"B04","race_id":"B04","affix_tendencies":["crit_chance","crit_multiplier"],"price":120.0},
	"EQ40":{"slot":"hands","drop_origin":"B04","race_id":"B04","affix_tendencies":["attack_speed"],"price":120.0},
	"EQ41":{"slot":"feet","drop_origin":"B01","race_id":"B01","affix_tendencies":["move_speed"],"price":60.0},
	"EQ42":{"slot":"feet","drop_origin":"B02","race_id":"B02","affix_tendencies":["cooldown_reduction"],"price":100.0},
	"EQ43":{"slot":"feet","drop_origin":"B01","race_id":"B01","affix_tendencies":["magic_penetration","move_speed"],"price":120.0},
	"EQ44":{"slot":"feet","drop_origin":"B01","race_id":"B01","affix_tendencies":["max_mana","move_speed"],"price":120.0},
	"EQ45":{"slot":"feet","drop_origin":"B02","race_id":"B02","affix_tendencies":["damage_reduction"],"price":120.0},
	"EQ46":{"slot":"feet","drop_origin":"B02","race_id":"B02","affix_tendencies":["armor_penetration","move_speed"],"price":120.0},
	"EQ47":{"slot":"feet","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp"],"price":120.0},
	"EQ48":{"slot":"feet","drop_origin":"B03","race_id":"B03","affix_tendencies":["damage_reduction"],"price":120.0},
	"EQ49":{"slot":"feet","drop_origin":"B04","race_id":"B04","affix_tendencies":["crit_chance","crit_multiplier"],"price":120.0},
	"EQ50":{"slot":"feet","drop_origin":"B04","race_id":"B04","affix_tendencies":["move_speed"],"price":120.0},
	"EQ51":{"slot":"charm","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp","armor"],"price":60.0},
	"EQ52":{"slot":"charm","drop_origin":"B04","race_id":"B04","affix_tendencies":["magic_resist","max_hp"],"price":100.0},
	"EQ53":{"slot":"charm","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","magic_penetration"],"price":160.0},
	"EQ54":{"slot":"charm","drop_origin":"B01","race_id":"B01","affix_tendencies":["ability_power","max_mana"],"price":160.0},
	"EQ55":{"slot":"charm","drop_origin":"B02","race_id":"B02","affix_tendencies":["crit_chance","crit_multiplier"],"price":160.0},
	"EQ56":{"slot":"charm","drop_origin":"B02","race_id":"B02","affix_tendencies":["ability_power","cooldown_reduction"],"price":160.0},
	"EQ57":{"slot":"charm","drop_origin":"B03","race_id":"B03","affix_tendencies":["max_hp","damage_reduction"],"price":160.0},
	"EQ58":{"slot":"charm","drop_origin":"B03","race_id":"B03","affix_tendencies":["attack","true_damage_bonus"],"price":160.0},
	"EQ59":{"slot":"charm","drop_origin":"B04","race_id":"B04","affix_tendencies":["armor_penetration","crit_multiplier"],"price":160.0},
	"EQ60":{"slot":"charm","drop_origin":"B04","race_id":"B04","affix_tendencies":["magic_resist","ability_power"],"price":160.0},
	"EQ61":{"slot":"weapon","shop_only":true,"race_id":"B01","affix_tendencies":["attack","armor"],"price":180.0},
	"EQ62":{"slot":"head","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","magic_resist"],"price":140.0},
	"EQ63":{"slot":"chest","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","armor"],"price":180.0},
	"EQ64":{"slot":"hands","shop_only":true,"race_id":"B01","affix_tendencies":["attack","armor"],"price":120.0},
	"EQ65":{"slot":"feet","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","move_speed"],"price":120.0},
	"EQ66":{"slot":"charm","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","cooldown_reduction"],"price":160.0},
	"EQ67":{"slot":"weapon","shop_only":true,"race_id":"B02","affix_tendencies":["attack","attack_speed"],"price":180.0},
	"EQ68":{"slot":"head","shop_only":true,"race_id":"B02","affix_tendencies":["max_hp","crit_chance"],"price":140.0},
	"EQ69":{"slot":"chest","shop_only":true,"race_id":"B02","affix_tendencies":["max_hp","magic_resist"],"price":180.0},
	"EQ70":{"slot":"hands","shop_only":true,"race_id":"B02","affix_tendencies":["attack_speed","attack"],"price":120.0},
	"EQ71":{"slot":"feet","shop_only":true,"race_id":"B02","affix_tendencies":["move_speed","armor"],"price":120.0},
	"EQ72":{"slot":"charm","shop_only":true,"race_id":"B02","affix_tendencies":["cooldown_reduction","max_hp"],"price":160.0},
	"EQ73":{"slot":"weapon","shop_only":true,"race_id":"B01","affix_tendencies":["ability_power","magic_penetration"],"price":180.0},
	"EQ74":{"slot":"head","shop_only":true,"race_id":"B01","affix_tendencies":["max_mana","cooldown_reduction"],"price":140.0},
	"EQ75":{"slot":"chest","shop_only":true,"race_id":"B01","affix_tendencies":["max_hp","magic_resist"],"price":180.0},
	"EQ76":{"slot":"hands","shop_only":true,"race_id":"B01","affix_tendencies":["ability_power","cooldown_reduction"],"price":120.0},
	"EQ77":{"slot":"feet","shop_only":true,"race_id":"B01","affix_tendencies":["move_speed","magic_resist"],"price":120.0},
	"EQ78":{"slot":"charm","shop_only":true,"race_id":"B01","affix_tendencies":["ability_power","max_mana"],"price":160.0},
	"EQ79":{"slot":"weapon","shop_only":true,"race_id":"B02","affix_tendencies":["attack","crit_chance"],"price":180.0},
	"EQ80":{"slot":"head","shop_only":true,"race_id":"B02","affix_tendencies":["crit_chance","armor"],"price":140.0},
	"EQ81":{"slot":"chest","shop_only":true,"race_id":"B02","affix_tendencies":["max_hp","armor"],"price":180.0},
	"EQ82":{"slot":"hands","shop_only":true,"race_id":"B02","affix_tendencies":["attack_speed","crit_multiplier"],"price":120.0},
	"EQ83":{"slot":"feet","shop_only":true,"race_id":"B02","affix_tendencies":["move_speed","max_hp"],"price":120.0},
	"EQ84":{"slot":"charm","shop_only":true,"race_id":"B02","affix_tendencies":["crit_chance","armor_penetration"],"price":160.0},
	"EQ85":{"slot":"weapon","shop_only":true,"race_id":"B03","affix_tendencies":["attack","max_hp"],"price":180.0},
	"EQ86":{"slot":"head","shop_only":true,"race_id":"B03","affix_tendencies":["max_hp","magic_resist"],"price":140.0},
	"EQ87":{"slot":"chest","shop_only":true,"race_id":"B03","affix_tendencies":["max_hp","armor"],"price":180.0},
	"EQ88":{"slot":"hands","shop_only":true,"race_id":"B03","affix_tendencies":["attack","attack_speed"],"price":120.0},
	"EQ89":{"slot":"feet","shop_only":true,"race_id":"B03","affix_tendencies":["move_speed","max_hp"],"price":120.0},
	"EQ90":{"slot":"charm","shop_only":true,"race_id":"B03","affix_tendencies":["max_hp","magic_resist"],"price":160.0},
	"EQ91":{"slot":"weapon","shop_only":true,"race_id":"B04","affix_tendencies":["attack","armor_penetration"],"price":180.0},
	"EQ92":{"slot":"head","shop_only":true,"race_id":"B04","affix_tendencies":["max_hp","armor"],"price":140.0},
	"EQ93":{"slot":"chest","shop_only":true,"race_id":"B04","affix_tendencies":["max_hp","armor"],"price":180.0},
	"EQ94":{"slot":"hands","shop_only":true,"race_id":"B04","affix_tendencies":["attack","attack_speed"],"price":120.0},
	"EQ95":{"slot":"feet","shop_only":true,"race_id":"B04","affix_tendencies":["move_speed","armor"],"price":120.0},
	"EQ96":{"slot":"charm","shop_only":true,"race_id":"B04","affix_tendencies":["damage_bonus","max_hp"],"price":160.0},
	"EQ97":{"slot":"legs","drop_origin":"B01","race_id":"B01","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0},
	"EQ98":{"slot":"ring","drop_origin":"B01","race_id":"B01","affix_tendencies":["damage_bonus","crit_chance"],"price":160.0},
	"EQ99":{"slot":"legs","drop_origin":"B01","race_id":"B01","affix_tendencies":["max_hp","armor","magic_resist"],"price":180.0}
}
const V1_SLOT_ORDER: Array[String] = ["weapon","head","chest","hands","legs","feet","ring","charm"]
const V1_LEVEL_CAP := 20
const RARITIES: Array[String] = ["white", "green", "purple", "gold"]
const EVENT_SOURCES: Array[String] = ["normal", "elite", "room", "chest", "boss", "summon"]
const EVENT_KEYS: Array[String] = ["event_id", "seed", "source", "race_id", "difficulty", "challenge_level", "power_type", "wish_slot", "force_gold"]
const ITEM_KEYS: Array[String] = ["instance_id", "source_event_id", "template_id", "rarity", "power_type", "item_level", "source", "location"]

## context requires event_id, seed, source, race_id, difficulty,
## challenge_level, power_type and hero_id (v2). wish_slot defaults to none. force_gold is
## allowed only for a D4 boss; if no generated item is gold, replace item zero
## with a freshly generated gold item (same count, new N/g and k/u).
## The frozen_result overload rejects changed requests and invalid receipts.
static func roll_event(context: Dictionary, frozen_result: Dictionary = {}) -> Dictionary:
	var version := int(frozen_result.get("generator_version", 4 if context.get("race_id") == "B06" else 3))
	var error := _event_error(context, version)
	if not error.is_empty(): return _failure(error)
	var request: Dictionary = _canonical(context)
	if not request.has("wish_slot"): request.wish_slot = ""
	if not request.has("force_gold"): request.force_gold = false
	var fingerprint := _fingerprint(request)
	if not frozen_result.is_empty():
		if frozen_result.get("context_fingerprint") != fingerprint or not frozen_result.get("context") is Dictionary or _fingerprint(frozen_result.context) != fingerprint:
			return _failure("event_context_changed")
		if not event_result_valid(frozen_result): return _failure("invalid_frozen_result")
		return frozen_result.duplicate(true)
	if int(request.challenge_level) > Growth.level_cap() or (request.race_id == "B05" and Growth.level_cap() < V3.LEVEL_CAP): return _failure("unreleased_challenge_level")
	var version_error := _dispatch_version(version, true)
	if not version_error.is_empty(): return _failure(version_error)
	return _roll_event_version(request, version)

## Historical generation is entered only after dispatching its recorded version;
## it deliberately never checks the current live rules or the current catalog.
static func _roll_event_v1(context: Dictionary) -> Dictionary:
	return _roll_event_version(context, 1)

static func _roll_event_version(context: Dictionary, version: int) -> Dictionary:
	var error := _event_error(context, version)
	if not error.is_empty(): return _failure(error)
	var request: Dictionary = _canonical(context)
	if not request.has("wish_slot"): request.wish_slot = ""
	if not request.has("force_gold"): request.force_gold = false
	var fingerprint := _fingerprint(request)
	var pool := natural_pool(str(request.race_id), str(request.get("hero_id", "")) if version >= 2 else "", version)
	if pool.is_empty() and request.source != "summon": return _failure("empty_race_pool")
	var result := {"ok":true, "error":"", "source_event_id":request.event_id,
		"context":request, "context_fingerprint":fingerprint, "versions":_versions(),
		"generator_version":version, "triggered":false, "forced_gold":false,
		"items":[], "warnings":[]}
	if request.source == "summon": return _seal(result)
	if request.wish_slot != "" and not pool.has(request.wish_slot):
		result.warnings.append("wish_slot_unavailable")
	# Trigger has a separate event stream. It never consumes an item roll.
	if request.source in ["normal", "elite"]:
		var chance := float(_value("kill_drop_chance")[request.source])
		var gate := _rng(int(request.seed), str(request.event_id), "trigger:" + str(request.source), version)
		if not _chance(gate, chance): return _seal(result)
	result.triggered = true
	var count := int(_value("boss_drop_counts")[int(request.difficulty)]) if request.source == "boss" else int(_value("guaranteed_room_drop_count"))
	for index in count:
		var item := _event_item(request, pool, index, false, version)
		if item.is_empty(): return _failure("item_generation_failed")
		result.items.append(item)
	if request.force_gold:
		var has_gold := false
		for item: Dictionary in result.items: has_gold = has_gold or item.rarity == "gold"
		if not has_gold:
			result.items[0] = _event_item(request, pool, 0, true, version)
			if result.items[0].is_empty(): return _failure("gold_replacement_failed")
			result.forced_gold = true
	return _seal(result)

## Explicit-template path for purchases/crafting and independent drop fixtures.
## Purchases/crafts are +0. Transactions own unlocks, affordability, capacity,
## context freezing and persistence; no caller-supplied random values/ledgers.
static func roll_item(spec: Dictionary, seed: int) -> Dictionary:
	var version := 4 if V4.TEMPLATES.has(spec.get("template_id")) else 3
	if not _dispatch_version(GENERATOR_VERSION, true).is_empty() or not _item_error(spec).is_empty(): return {}
	var request: Dictionary = _canonical(spec)
	if not request.has("location"): request.location = "pending" if request.source == "drop" else "inventory"
	var rng := _rng(seed, str(request.source_event_id), "item:" + str(request.instance_id) + ":" + str(request.source), version)
	return _finish_item(request, rng, seed, _fingerprint(request), version)

## Single version-dispatch gate. V3 appends B05/cap25; V4 appends B06/cap30.
## Pre-B06 new acquisitions keep their v3 RNG domain and item-level contract;
## numerical roll/quality/economy definitions retain the original V1 contract.
## V1/V2 receipts select their original archives, caps and RNG domains.
static func current_version_error() -> String:
	return _dispatch_version(GENERATOR_VERSION, true)

static func _dispatch_version(version: int, current_creation: bool) -> String:
	if version not in [1, 2, 3, 4]: return "unsupported_generator_version"
	if current_creation and (not _live_v1_matches() or not _live_v2_matches() or not _live_v3_matches() or not _live_v4_matches()): return "generation_version_mismatch"
	return ""

static func _allowed_heroes_v2(template_id: String) -> Array:
	if not V2_TEMPLATE_SETS.has(template_id): return []
	var set_id: String = V2_TEMPLATE_SETS[template_id]
	return ["CH01", "CH02", "CH03"] if set_id.is_empty() else V2_SET_HEROES.get(set_id, []).duplicate()

static func _level_cap(version: int) -> int:
	return V4.LEVEL_CAP if version >= 4 else (V3.LEVEL_CAP if version >= 3 else V1_LEVEL_CAP)

static func _allowed_heroes(template_id: String, version: int) -> Array:
	if version >= 4 and V4.TEMPLATES.has(template_id): return V4.TEMPLATES[template_id].allowed_heroes.duplicate()
	if version >= 3 and V3.TEMPLATES.has(template_id): return V3.TEMPLATES[template_id].allowed_heroes.duplicate()
	return _allowed_heroes_v2(template_id)

static func _live_v3_matches() -> bool:
	if Growth.level_cap() not in [20, V3.LEVEL_CAP, V4.LEVEL_CAP]: return false
	if Registry.equipment_ids(2).size() != V1_TEMPLATES.size() + (V3.TEMPLATES.size() if Growth.level_cap() >= V3.LEVEL_CAP else 0) + (V4.TEMPLATES.size() if Growth.level_cap() >= V4.LEVEL_CAP else 0): return false
	for id: String in V3.TEMPLATES:
		var live := Registry.equipment(id, 2)
		for key: String in V3.TEMPLATES[id]:
			if _canonical(live.get(key)) != _canonical(V3.TEMPLATES[id][key]): return false
	return true

static func _live_v4_matches() -> bool:
	if Growth.level_cap() < V4.LEVEL_CAP: return true
	for id: String in V4.TEMPLATES:
		var live := Registry.equipment(id, 2)
		for key: String in V4.TEMPLATES[id]:
			if _canonical(live.get(key)) != _canonical(V4.TEMPLATES[id][key]): return false
	return true

static func _live_v2_matches() -> bool:
	for id: String in V2_TEMPLATE_SETS:
		var template := Registry.equipment(id, 2)
		if template.get("allowed_heroes") != _allowed_heroes_v2(id) or template.get("class_policy_version") != 1: return false
	return true

static func _live_v1_matches() -> bool:
	var current_parameters := Rules.parameters()
	var parameters := {}
	for key: String in V1_PARAMETERS:
		if not current_parameters.has(key): return false
		parameters[key] = current_parameters[key]
	var templates := {}
	for id: String in V1_TEMPLATES:
		var source := Registry.equipment(id, 2)
		var template := {}
		for key in ["slot", "shop_only", "drop_origin", "race_id", "affix_tendencies", "price"]:
			if source.has(key): template[key] = source[key]
		templates[id] = template
	var current := {"parameters":parameters, "templates":templates, "slot_order":Registry.slots(2), "level_cap":V1_LEVEL_CAP}
	if _v1_contract_hash.is_empty():
		var archive := {"parameters":V1_PARAMETERS, "templates":V1_TEMPLATES, "slot_order":V1_SLOT_ORDER, "level_cap":V1_LEVEL_CAP}
		_v1_contract_hash = JSON.stringify(_canonical(archive), "", false, true).sha256_text()
	# Dictionary iteration order determines weighted intervals and k assignment,
	# so creation compatibility checks ordered values, not only sorted JSON.
	return JSON.stringify(_canonical(current), "", false, true).sha256_text() == _v1_contract_hash

## Keys are available slots in registry order; templates are stable-ID sorted.
## Never falls back to another race or includes a shop-exclusive template.
static func natural_pool(race_id: String, hero_id: String = "", version: int = 0) -> Dictionary:
	if version == 0: version = 4 if Growth.level_cap() >= V4.LEVEL_CAP else 3
	if version not in [1, 2, 3, 4] or (not hero_id.is_empty() and hero_id not in ["CH01", "CH02", "CH03"]): return {}
	# B05 is class-filtered from its first generation; never offer all 35 as a
	# natural pool when a caller omitted the hero context.
	if race_id == "B05" and (version < 3 or hero_id.is_empty()): return {}
	if race_id == "B06" and (version < 4 or hero_id.is_empty()): return {}
	var unordered := {}
	var ids := V1_TEMPLATES.keys()
	if version >= 3: ids.append_array(V3.TEMPLATES.keys())
	if version >= 4: ids.append_array(V4.TEMPLATES.keys())
	for id: String in ids:
		var template := _template(id, version)
		if not hero_id.is_empty() and hero_id not in _allowed_heroes(id, version): continue
		if not bool(template.get("shop_only", false)) and str(template.get("drop_origin", "")) == race_id and str(template.get("race_id", "")) == race_id:
			if not unordered.has(template.slot): unordered[template.slot] = []
			unordered[template.slot].append(id)
	var candidates := {}
	for slot: String in V1_SLOT_ORDER:
		if unordered.has(slot): candidates[slot] = unordered[slot]
	return candidates

static func quality_weights(source: String, difficulty: int) -> Dictionary:
	if source not in EVENT_SOURCES or difficulty < 0 or difficulty >= _value("normal_quality_weights").size() or source == "summon": return {}
	var key := "boss_quality_weights" if source == "boss" else ("elite_quality_weights" if source == "elite" else "normal_quality_weights")
	var row: Array = _value(key)[difficulty]
	var result := {}
	for index in RARITIES.size(): result[RARITIES[index]] = int(row[index])
	return result

static func enhancement_weights(rarity: String) -> Dictionary:
	if rarity not in RARITIES: return {}
	return _value("drop_enhancement")["gold" if rarity == "gold" else "non_gold"].duplicate(true)

## Integral weights express wish probability exactly, including fallback/single
## available-slot cases. Configured wish probability is a finite decimal.
static func slot_weights(pool: Dictionary, wish_slot: String = "") -> Dictionary:
	var result := {}
	for slot: String in pool:
		if pool[slot] is Array and not pool[slot].is_empty(): result[slot] = 1
	if result.size() <= 1 or wish_slot.is_empty() or not result.has(wish_slot): return result
	var probability := Instances._fraction(_value("wish_slot_chance"))
	for slot: String in result:
		result[slot] = probability[0] * (result.size() - 1) if slot == wish_slot else probability[1] - probability[0]
	return result

## Frozen B05 union weights. A wished-slot hit stays locked; on the non-wish
## branch these multiply the original per-template probability mass (slot mass
## divided by template count), not a new globally uniform template pool.
static func template_weights(candidates: Array, context: Dictionary, version: int = GENERATOR_VERSION) -> Dictionary:
	if not _event_error(context, version).is_empty(): return {}
	var result := {}
	for id: Variant in candidates:
		if not id is String or result.has(id): return {}
		var template := _template(id, version)
		if template.is_empty() or template.get("race_id") != context.race_id or bool(template.get("shop_only", false)): return {}
		if version >= 2 and context.hero_id not in _allowed_heroes(id, version): return {}
		var preferred := false
		if (version >= 3 and context.race_id == "B05") or (version >= 4 and context.race_id == "B06"):
			var preferences = V4 if context.race_id == "B06" else V3
			var room: String = str(context.get("room_id", ""))
			var monster: String = str(context.get("monster_id", ""))
			preferred = template.slot in preferences.ROOM_PREFERRED_SLOTS.get(room, []) or template.slot == preferences.MONSTER_PREFERRED_SLOT.get(monster, "")
			var unique: Array = preferences.UNIQUE_PREFERENCES.get(id, [])
			preferred = preferred or room in unique or monster in unique
		result[id] = (V4.PREFERENCE_WEIGHT if context.race_id == "B06" else V3.PREFERENCE_WEIGHT) if preferred else 1
	return result

## Integer common-denominator encoding of original_slot_weight / slot_count.
## Excluding the wished slot conditions only the non-wish branch. Its mass is
## never redistributed into that slot, so the original wish-hit chance survives.
static func preference_slot_weights(pool: Dictionary, context: Dictionary, excluded_slot: String = "", version: int = GENERATOR_VERSION) -> Dictionary:
	var template_maps := {}
	var denominator := 1
	for slot: String in pool:
		if slot == excluded_slot: continue
		var weights := template_weights(pool[slot], context, version)
		if weights.is_empty(): return {}
		template_maps[slot] = weights
		denominator = denominator * weights.size() / Instances._gcd(denominator, weights.size())
	var original := slot_weights(pool, str(context.get("wish_slot", "")))
	var result := {}
	for slot: String in template_maps:
		var weight_sum := 0
		for weight: Variant in template_maps[slot].values(): weight_sum += int(weight)
		result[slot] = int(original[slot]) * weight_sum * denominator / template_maps[slot].size()
	return result

static func _has_preference(pool: Dictionary, context: Dictionary, version: int = GENERATOR_VERSION) -> bool:
	for slot: String in pool:
		for weight: Variant in template_weights(pool[slot], context, version).values():
			if int(weight) != 1: return true
	return false

static func _uniform_weights(weights: Dictionary) -> bool:
	if weights.is_empty(): return false
	var first := int(weights.values()[0])
	for weight: Variant in weights.values():
		if int(weight) != first: return false
	return true

## Exact categorical selector. Tickets are integers in [0,total-1]; zero-weight
## entries cannot be selected, including the first and last boundary tickets.
static func weighted_ticket(weights: Dictionary, ticket: int) -> String:
	if ticket < 0: return ""
	for key: Variant in weights:
		if not _integer(weights[key], 0, 2147483647): return ""
		var weight := int(weights[key])
		if ticket < weight: return str(key)
		ticket -= weight
	return ""

static func _event_item(context: Dictionary, pool: Dictionary, index: int, forced_gold: bool, version: int = 1) -> Dictionary:
	var stream := "item:%d" % index + (":gold_replacement" if forced_gold else "")
	var rng := _rng(int(context.seed), str(context.event_id), stream, version)
	# Pool -> rarity -> wish/other slot -> template -> ilvl -> N -> g -> k ->
	# affix type/u. Explicit/fixed stages do not consume unnecessary random draws.
	var rarity := "gold" if forced_gold else _weighted(rng, quality_weights(str(context.source), int(context.difficulty)))
	var wish: String = str(context.wish_slot)
	var slot := _weighted(rng, slot_weights(pool, wish))
	if version >= 3 and _has_preference(pool, context, version):
		# Keep the original draw as the wish hit/miss decision. Missing/no
		# applicable provenance takes exactly the old seeded v3 draw sequence.
		var locked_wish := pool.has(wish) and slot == wish
		if not locked_wish:
			var mass := preference_slot_weights(pool, context, wish if pool.has(wish) else "", version)
			slot = _weighted(rng, mass)
	if slot.is_empty(): return {}
	var candidates: Array = pool[slot]
	var weights := template_weights(candidates, context, version) if version >= 3 else {}
	var template_id := str(candidates[rng.randi_range(0, candidates.size() - 1)]) if version < 3 or _uniform_weights(weights) else _weighted(rng, weights)
	if template_id.is_empty(): return {}
	var item_level := int(context.challenge_level)
	if context.source != "boss":
		item_level = clampi(item_level + int(_weighted(rng, _value("item_level_offsets"))), 1, V1_LEVEL_CAP if int(context.challenge_level) <= V1_LEVEL_CAP else _level_cap(version))
	var spec := {"instance_id":"v2:" + (str(context.event_id) + ":" + str(index)).sha256_text(),
		"source_event_id":context.event_id, "template_id":template_id, "rarity":rarity,
		"power_type":context.power_type, "item_level":item_level, "source":"drop", "location":"pending"}
	if version >= 2: spec["hero_id"] = context.hero_id
	var item := _finish_item(spec, rng, int(context.seed), _fingerprint(context), version)
	if item.is_empty(): return {}
	item.source_kind = context.source
	item.source_metadata["race_id"] = context.race_id
	item.source_metadata["difficulty"] = context.difficulty
	item.source_metadata["challenge_level"] = context.challenge_level
	item.source_metadata["item_index"] = index
	item.source_metadata["stream"] = stream
	item.source_metadata["forced_gold"] = forced_gold
	for field: String in ["room_id", "monster_id"]:
		if context.has(field): item.source_metadata[field] = context[field]
	return item

static func _finish_item(spec: Dictionary, rng: RandomNumberGenerator, seed: int, fingerprint: String, version: int = 1) -> Dictionary:
	var rank := int(_weighted(rng, enhancement_weights(str(spec.rarity)))) if spec.source == "drop" else 0
	var steps: Array = []
	for index in rank:
		steps.append({"g":int(_weighted(rng, _value("enhancement_random").gain_percent_weights)), "pity":0, "base_price_peak":_enhancement_price(index + 1, int(spec.item_level))})
	var quantile_max := int(_value("main_roll").steps)
	var main := {}
	for key: String in _main_keys(str(spec.template_id), str(spec.power_type), version):
		main[key] = rng.randi_range(0, quantile_max)
	var weights := _affix_weights(str(spec.template_id), str(spec.power_type), version)
	var affixes: Array = []
	for index in int(_value("rarities")[spec.rarity].affix_count):
		var key := _weighted(rng, weights)
		if key.is_empty(): return {}
		affixes.append({"type":key, "u":rng.randi_range(0, quantile_max)})
		weights.erase(key)
	var source := {"event_id":spec.source_event_id, "seed":seed, "context_fingerprint":fingerprint,
		"generator_version":version, "rules_source_commit":_value("source_commit"),
		"versions":_versions(), "roll_order":_value("roll_order")}
	var item := {"instance_id":spec.instance_id, "template_id":spec.template_id,
		"source_event_id":spec.source_event_id, "item_level":spec.item_level, "rarity":spec.rarity,
		"power_type":spec.power_type, "main_rolls":main, "affix_type_and_quantile":affixes,
		"enhancement_rank":rank, "enhancement_steps":steps, "enhancement_gold_ledger":[], "material_ledger":[],
		"purchase_baseline_gold":_purchase_baseline_price(str(spec.template_id), str(spec.rarity), int(spec.item_level), version),
		"source_kind":spec.source, "source_metadata":source, "location":spec.location,
		"equipment_instance_version":int(_value("versions").equipment_instance), "ruleset_version":int(_value("versions").ruleset),
		"scale_version":int(_value("versions").scale), "enhancement_reroll_history":[], "reforge_slot":-1, "lock_state":false}
	if version >= 2:
		item["class_policy_version"] = 3 if V4.TEMPLATES.has(spec.template_id) else (2 if V3.TEMPLATES.has(spec.template_id) else 1)
		item["allowed_heroes"] = _allowed_heroes(str(spec.template_id), version)
		item["acquired_for_hero"] = item.allowed_heroes[0] if item.allowed_heroes.size() == 1 else spec.hero_id
	return item

## These helpers use the archived contract exclusively. Integer-cost arithmetic
## still shares Economy's exact ceil primitive; no current price tables leak in.
static func _value(key: String) -> Variant:
	return V1_PARAMETERS[key]

static func _template(id: String, version: int = GENERATOR_VERSION) -> Dictionary:
	if version >= 4 and V4.TEMPLATES.has(id): return V4.TEMPLATES[id]
	if version >= 3 and V3.TEMPLATES.has(id): return V3.TEMPLATES[id]
	return V1_TEMPLATES.get(id, {})

static func _versions() -> Dictionary:
	var result: Dictionary = _canonical(_value("versions"))
	result["ruleset_version"] = int(result.ruleset)
	result["scale_version"] = int(result.scale)
	return result

static func _main_keys(template_id: String, power_type: String, version: int = GENERATOR_VERSION) -> Array:
	var definition: Dictionary = _value("slots")[_template(template_id, version).slot]
	return definition.get("shared", definition.get(power_type, {})).keys()

static func _affix_weights(template_id: String, power_type: String, version: int = GENERATOR_VERSION) -> Dictionary:
	var result := {}
	var template := _template(template_id, version)
	var tendencies: Array = template.get("affix_tendencies_by_power", {}).get(power_type, template.get("affix_tendencies", []))
	var definitions: Dictionary = _value("affixes")
	for key: String in definitions:
		var definition: Dictionary = definitions[key]
		if template.slot in definition.slots and str(definition.get("power_type", power_type)) == power_type:
			result[key] = int(_value("affix_tendency_weight")) if key in tendencies else int(_value("affix_default_weight"))
	return result

static func _scaled_gold(base: int, level: int, multiplier: Variant = 1) -> int:
	var increment := Instances._fraction(_value("cost_item_level_per_level"))
	var ratio := Instances._fraction(multiplier)
	return Economy.ceil_ratio(base * ratio[0] * (increment[1] + increment[0] * (level - 1)), ratio[1] * increment[1])

static func _enhancement_price(rank: int, level: int) -> int:
	return _scaled_gold(int(_value("enhancement_gold")[rank - 1]), level)

static func _purchase_baseline_price(template_id: String, rarity: String, level: int, version: int = GENERATOR_VERSION) -> int:
	return _scaled_gold(int(_template(template_id, version).price), level, _value("shop_price_multiplier")["white" if rarity == "white" else "green"])

static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for value: Variant in weights.values(): total += int(value)
	return weighted_ticket(weights, rng.randi_range(0, total - 1)) if total > 0 else ""

static func _chance(rng: RandomNumberGenerator, probability: float) -> bool:
	var fraction := Instances._fraction(probability)
	return rng.randi_range(0, fraction[1] - 1) < fraction[0]

static func _rng(seed: int, event_id: String, domain: String, version: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# SHA-256 avoids engine String.hash implementation changes. Length-delimited
	# serialization prevents ambiguous identity concatenation. 60 bits fit int64.
	var identity := JSON.stringify(["equipment_acquisition", version, seed, event_id, domain])
	rng.seed = identity.sha256_text().substr(0, 15).hex_to_int()
	return rng

static func _event_error(context: Dictionary, version: int = 1) -> String:
	for key: Variant in context:
		if key not in EVENT_KEYS and not (version >= 2 and key == "hero_id") and not (version >= 3 and key in ["room_id", "monster_id"]): return "unknown_event_field"
	if version >= 2 and (context.get("hero_id") not in ["CH01", "CH02", "CH03"] or context.get("power_type") != ("magic" if context.get("hero_id") == "CH03" else "physical")): return "invalid_hero_context"
	if not context.has_all(["event_id", "seed", "source", "race_id", "difficulty", "challenge_level", "power_type"]): return "missing_event_field"
	if not _text(context.event_id) or not _text(context.race_id): return "invalid_event_identity"
	var preferences = V4 if version >= 4 and context.race_id == "B06" else V3
	if context.race_id == "B06":
		if version < 4 or context.get("room_id") not in V4.ROOM_LEVELS: return "invalid_room_context"
		if context.challenge_level != V4.ROOM_LEVELS[context.room_id]: return "invalid_challenge_level"
		if context.source != "summon" and (context.source == "boss") != (context.room_id == "BO06"): return "invalid_boss_room"
	if context.has("room_id"):
		if context.race_id not in ["B05", "B06"] or not context.room_id is String or not preferences.ROOM_PREFERRED_SLOTS.has(context.room_id): return "invalid_room_context"
	if context.has("monster_id"):
		if context.race_id not in ["B05", "B06"] or context.source not in ["normal", "elite"] or not context.monster_id is String or not preferences.MONSTER_PREFERRED_SLOT.has(context.monster_id): return "invalid_monster_context"
	if not _integer(context.seed, -9007199254740991, 9007199254740991): return "invalid_seed"
	if not context.source is String or context.source not in EVENT_SOURCES: return "invalid_source"
	if not _integer(context.difficulty, 0, _value("normal_quality_weights").size() - 1): return "invalid_difficulty"
	if not _integer(context.challenge_level, 1, _level_cap(version)): return "invalid_challenge_level"
	if context.power_type not in ["physical", "magic"]: return "invalid_power_type"
	if not context.get("wish_slot", "") is String: return "invalid_wish_slot"
	if context.get("wish_slot", "") != "" and context.wish_slot not in V1_SLOT_ORDER: return "invalid_wish_slot"
	if not context.get("force_gold", false) is bool: return "invalid_force_gold"
	if context.get("force_gold", false) and (context.source != "boss" or int(context.difficulty) != _value("boss_drop_counts").size() - 1): return "invalid_force_gold_source"
	return ""

static func _item_error(spec: Dictionary) -> String:
	for key: Variant in spec:
		if key not in ITEM_KEYS and key != "hero_id": return "unknown_item_field"
	if spec.get("hero_id") not in ["CH01", "CH02", "CH03"]: return "invalid_hero_context"
	var allowed := _allowed_heroes(str(spec.get("template_id", "")), GENERATOR_VERSION)
	if allowed.size() == 1 and spec.get("power_type") != ("magic" if allowed[0] == "CH03" else "physical"): return "class_power_mismatch"
	if not spec.has_all(["instance_id", "source_event_id", "template_id", "rarity", "power_type", "item_level", "source"]): return "missing_item_field"
	for key in ["instance_id", "source_event_id", "template_id"]:
		if not _text(spec[key]): return "invalid_item_identity"
	if _template(str(spec.template_id)).is_empty(): return "invalid_template"
	if V3.TEMPLATES.has(spec.template_id) and Growth.level_cap() < V3.LEVEL_CAP: return "unreleased_template"
	if V4.TEMPLATES.has(spec.template_id) and Growth.level_cap() < V4.LEVEL_CAP: return "unreleased_template"
	if spec.rarity not in RARITIES or spec.power_type not in ["physical", "magic"]: return "invalid_item_type"
	if not _integer(spec.item_level, 25 if V4.TEMPLATES.has(spec.template_id) else 1, mini(_level_cap(4 if V4.TEMPLATES.has(spec.template_id) else 3), Growth.level_cap())): return "invalid_item_level"
	if spec.source not in ["purchase", "craft", "drop"]: return "invalid_item_source"
	if spec.source == "purchase" and spec.rarity not in _value("shop_rarities"): return "invalid_shop_rarity"
	if spec.source == "craft" and not _value("forge_costs").has(spec.rarity): return "invalid_craft_rarity"
	if spec.get("location", "inventory") not in ["inventory", "pending"]: return "invalid_item_location"
	return ""

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

## JSON reload represents integers as doubles. Canonicalize integral values so
## a saved receipt is identical to its in-memory counterpart after a reload.
static func _canonical(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991:
		return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_canonical(item))
		return result
	return value

static func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(_canonical(value), "", true, true).sha256_text()

static func _seal(result: Dictionary) -> Dictionary:
	result["result_fingerprint"] = _fingerprint(result)
	return result

## Persisted reward validation verifies the complete deterministic result, not
## merely legal individual instances. No ownership or cap state is consulted.
static func event_result_valid(result: Dictionary) -> bool:
	# Always check the complete current payload's hash first. An edited receipt
	# cannot borrow a cached result by retaining or recomputing its old seal.
	if not _valid_receipt(result): return false
	var fingerprint: String = result.result_fingerprint
	if _validated_fingerprints.has(fingerprint): return true
	if not _dispatch_version(int(result.generator_version), false).is_empty(): return false
	if _fingerprint(_roll_event_version(result.context, int(result.generator_version))) != _fingerprint(result): return false
	if _validated_fingerprints.size() >= VALIDATION_CACHE_LIMIT:
		_validated_fingerprints.erase(_validated_fingerprints.keys()[0])
	_validated_fingerprints[fingerprint] = true
	return true

static func _valid_receipt(result: Dictionary) -> bool:
	if not Instances._value_tree(result): return false
	if not result.has_all(["ok", "error", "source_event_id", "context", "context_fingerprint", "versions", "generator_version", "triggered", "forced_gold", "items", "warnings", "result_fingerprint"]): return false
	if result.ok != true or not _integer(result.generator_version, 1, GENERATOR_VERSION): return false
	if not result.context is Dictionary or not result.versions is Dictionary or _fingerprint(result.versions) != _fingerprint(_versions()): return false
	if not result.items is Array: return false
	for item: Variant in result.items:
		if not item is Dictionary: return false
	var unsigned := result.duplicate(true)
	unsigned.erase("result_fingerprint")
	return result.result_fingerprint == _fingerprint(unsigned)

static func _failure(error: String) -> Dictionary:
	return {"ok":false, "error":error, "items":[]}
