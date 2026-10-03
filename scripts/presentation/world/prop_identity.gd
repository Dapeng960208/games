class_name PropIdentity
extends RefCounted
## Functional objects own their painted silhouettes. Fixed scenery keeps its
## authored feet/collisions and borrows an unused image of the same civilization.

const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
const OBJECTIVES := {
	"B01":["B01_prop_crystal_valve","B01_prop_orrery","B01_prop_runic_disk"],
	"B02":["B02_prop_chrysalis_rack","B02_prop_molting_pavilion","B02_prop_resin_vein"],
	"B03":["B03_prop_hat_headstone","B03_edge_east","B03_prop_coffin_postbox"],
	"B04":["B04_edge_north","B04_edge_south","B04_edge_east"]}
const EDGE_NAMES := {"north":"外围短墙","east":"侧岸边景","south":"低矮边栏","west":"侧庭棚亭","corner":"转角花岩","foreground":"近景花草","gateway":"开放拱门","backdrop":"远景建筑"}
static var _names: Dictionary = {}
static var _pools: Dictionary = {}

static func objective_keys(biome_id: String) -> Array[String]:
	var result: Array[String] = []
	for key: String in OBJECTIVES.get(biome_id,[]): result.append(key)
	return result

static func reserved_identities(layout: Dictionary, biome_id: String) -> Dictionary:
	var reserved: Dictionary = {}
	for asset: String in objective_keys(biome_id): _reserve(reserved,asset)
	for field: String in ["fixed_optional_rewards","fixed_world_entities","interactables","boss_counterplay"]:
		for item: Dictionary in layout.get(field,[]): _reserve(reserved,str(item.get("asset","")))
	return reserved

static func _reserve(reserved: Dictionary, asset: String) -> void:
	var identity: String = PropArt.visual_identity(asset)
	if not identity.is_empty(): reserved[identity]=true

static func used_identities(items: Array) -> Dictionary:
	var used: Dictionary = {}
	for item: Dictionary in items: _reserve(used,str(item.get("asset","")))
	return used

static func _pool(biome_id: String) -> Array[String]:
	if not _pools.has(biome_id):
		var assets: Array[String] = []
		for asset: String in PropArt.faction_assets(biome_id):
			if not PropArt.visual_identity(asset).is_empty(): assets.append(asset)
		_pools[biome_id]=assets
	return _pools[biome_id]

static func choose_asset(original: String, biome_id: String, used: Dictionary, reserved: Dictionary, solid: bool = false, landmark: bool = false) -> String:
	var original_identity: String = PropArt.visual_identity(original)
	if not original_identity.is_empty() and not used.has(original_identity) and not reserved.has(original_identity):
		used[original_identity]=true
		return original
	var original_definition: Dictionary = PropArt.definition_for_asset(original)
	var original_source: Rect2 = original_definition.get("source",Rect2(0,0,100,100))
	var ratio: float = original_source.size.x/maxf(1.0,original_source.size.y)
	var best: String = ""
	var best_score: float = INF
	# Lexically sorted assets make equal scores stable across rooms and run seeds.
	for candidate: String in _pool(biome_id):
		var identity: String = PropArt.visual_identity(candidate)
		if used.has(identity) or reserved.has(identity): continue
		var source: Rect2 = PropArt.definition_for_asset(candidate).get("source",Rect2())
		var candidate_ratio: float = source.size.x/maxf(1.0,source.size.y)
		var score: float = absf(log(maxf(.05,candidate_ratio)/maxf(.05,ratio)))
		if "_edge_" in candidate: score+=1.0
		if "foreground" in candidate: score+=1.0 if solid or landmark else .15
		if "backdrop" in candidate: score+=.8 if landmark else 2.5
		if solid and not _structural(candidate): score+=3.0
		if score<best_score:
			best=candidate
			best_score=score
	if not best.is_empty(): used[PropArt.visual_identity(best)]=true
	return best

static func _structural(asset: String) -> bool:
	for kind: String in ["column","bench","gate","arch","furnace","greenhouse","sculpture","anvil","rack","urn","loom","headstone","crate","pavilion","well","calyx","cottage","warehouse","postoffice","shop","north","east","south"]:
		if kind in asset: return true
	return false

static func unique_scenery(items: Array, layout: Dictionary, biome_id: String) -> Array:
	if not bool(layout.get("fixed_layout",false)): return items
	var reserved: Dictionary = reserved_identities(layout,biome_id)
	var used: Dictionary = {}
	var protected: Dictionary = {}
	# A reward's scenery is its only body; preserve that exact instance and keep
	# every other decoration away from the reward's effective texture region.
	for reward: Dictionary in layout.get("fixed_optional_rewards",[]):
		var identity: String = PropArt.visual_identity(str(reward.get("asset","")))
		var at: Vector2 = reward.get("position",Vector2.ZERO)
		for index: int in items.size():
			var item: Dictionary = items[index]
			if PropArt.visual_identity(str(item.get("asset","")))==identity and Vector2(item.get("position",Vector2.INF)).distance_to(at)<.5:
				protected[index]=true
				used[identity]=true
				break
	var order: Array[int] = []
	for index: int in items.size(): order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var priority_a: int = _priority(items[a],protected.has(a))
		var priority_b: int = _priority(items[b],protected.has(b))
		return a<b if priority_a==priority_b else priority_a<priority_b)
	for index: int in order:
		var item: Dictionary = items[index]
		if bool(item.get("static",false)) or protected.has(index): continue
		var original: String = str(item.get("asset",""))
		if original.is_empty(): continue
		var selected: String = choose_asset(original,biome_id,used,reserved,"solid" in item.get("tags",[]),"fixed_landmark" in item.get("tags",[]))
		if selected.is_empty():
			push_warning("No distinct scenery region remains for "+str(item.get("id","")))
			continue
		if selected!=original:
			item["visual_replaces_asset"]=original
			item["asset"]=selected
			item["name"]=display_name(selected)
		item["visual_identity"]=PropArt.visual_identity(selected)
	return items

static func _priority(item: Dictionary, protected: bool) -> int:
	if protected: return 0
	if "fixed_landmark" in item.get("tags",[]): return 1
	return 2 if "solid" in item.get("tags",[]) else 3

static func display_name(asset: String) -> String:
	if _names.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://data/world/fixed_rooms.json")))
		if value is Dictionary:
			for biome: String in value.get("regions",{}):
				for family: Dictionary in value.regions[biome].get("asset_families",[]):
					_names[biome+"_prop_"+str(family.key)]=str(family.get("name",family.key))
	if _names.has(asset): return str(_names[asset])
	if "_edge_" in asset: return str(EDGE_NAMES.get(asset.get_slice("_edge_",1),"外围景物"))
	return "主题陈设"
