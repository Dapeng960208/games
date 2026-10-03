class_name WorldArt
extends RefCounted
## Shared sunlit ruin palette. Textured machinery keeps its silhouette, alpha
## and texture detail; its shadows no longer inherit the old black mine grade.

const PROP_SHADER = preload("res://shaders/world/sunlit_props.gdshader")
const FLOOR_PATH := "asset://world/storybook_floor_v1.png"
const EDGE_PATH := "asset://world/storybook_edge_v1.png"
const FACTION_FLOOR_PATH := "asset://world/storybook_floor_factions_v2.png"
const PUMPKIN_FLOOR_PATH := "asset://world/fixed_B03_floor_v1.png"
const FACTION_FLOOR_REGIONS := {"B02":Rect2(0,0,724,724),"B03":Rect2(724,0,724,724),"B04":Rect2(1448,0,724,724)}
const ARCHITECTURE_PATH := "asset://world/storybook_architecture_v2.png"
const ARCHITECTURE_MANIFEST := "asset://world/storybook_architecture_v2.regions.json"
static var _materials: Dictionary = {}
static var _architecture: Dictionary = {}
static var _floors: Dictionary = {}
static var _environments: Dictionary = {}
static var _environment_recency: Array[String] = []
const ENVIRONMENT_CACHE_LIMIT := 2
const EnvironmentTexture = preload("res://scripts/presentation/world/environment_detail.gd")

static func environment_room_id(layout: Dictionary) -> String:
	# Boss encounters may override room_id for the expedition node. The fixed
	# blueprint remains the authority for the painting and its dry-ground edge.
	return str(layout.get("blueprint_room_id",layout.get("room_id","")))

static func environment_definition(biome_id: String, room_id: String = "") -> Dictionary:
	var key: String = biome_id+":"+room_id
	if _environments.has(key):
		_environment_recency.erase(key)
		_environment_recency.append(key)
		return _environments[key]
	var candidates: Array[String] = []
	if not room_id.is_empty():
		candidates.append("asset://world/rooms/"+room_id+"_environment_v1.json")
	# Older rooms and service layouts still have their approved faction art.
	# An absent or incomplete room resource can use that compatibility fallback.
	candidates.append("asset://world/fixed_"+biome_id+"_environment_v3.json")
	candidates.append("asset://world/fixed_"+biome_id+"_environment_v2.json")
	for manifest_path: String in candidates:
		if not FileAccess.file_exists(AssetCatalog.resolve(manifest_path)): continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(manifest_path)))
		if not value is Dictionary: continue
		var path: String = str(value.get("texture",""))
		var values: Array = value.get("walkable_normalized_rect",[])
		if values.size()!=4 or not FileAccess.file_exists(AssetCatalog.resolve(path)): continue
		var central := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
		if not central.has_area() or not Rect2(Vector2.ZERO,Vector2.ONE).encloses(central): continue
		var placement: Rect2 = central
		var placement_values: Array = value.get("placement_normalized_rect",[])
		if placement_values.size()==4:
			var proposed := Rect2(float(placement_values[0]),float(placement_values[1]),float(placement_values[2]),float(placement_values[3]))
			if proposed.has_area() and Rect2(Vector2.ZERO,Vector2.ONE).encloses(proposed): placement=proposed
		# Environment textures have their own bounded residency. The global UI
		# sampler retains every path, which would accumulate all visited rooms.
		var texture: Texture2D = EnvironmentTexture.load_mip_texture(path)
		if texture==null: continue
		var result := {"path":path,"texture":texture,"source":Rect2(Vector2.ZERO,texture.get_size()),"walkable_normalized_rect":central,"placement_normalized_rect":placement,"metadata":value,"manifest_path":manifest_path,"room_id":room_id,"room_specific":manifest_path==candidates[0] and not room_id.is_empty()}
		_environments[key] = result
		_environment_recency.erase(key)
		_environment_recency.append(key)
		while _environment_recency.size()>ENVIRONMENT_CACHE_LIMIT:
			_environments.erase(_environment_recency.pop_front())
		return result
	return {}

static func environment_texture_for(biome_id: String, room_id: String = "") -> Texture2D:
	return environment_definition(biome_id,room_id).get("texture",null)

static func environment_world_rect(arena: Rect2, biome_id: String, room_id: String = "") -> Rect2:
	var definition: Dictionary = environment_definition(biome_id,room_id)
	if definition.is_empty(): return Rect2()
	var central: Rect2 = definition.placement_normalized_rect
	var size: Vector2 = arena.size/central.size
	return Rect2(arena.position-central.position*size,size)

static func environment_point(arena: Rect2, biome_id: String, normalized: Vector2, room_id: String = "") -> Vector2:
	var bounds: Rect2 = environment_world_rect(arena,biome_id,room_id)
	return bounds.position+normalized*bounds.size

static func environment_ground_polygon(arena: Rect2, biome_id: String, room_id: String = "") -> PackedVector2Array:
	var definition: Dictionary = environment_definition(biome_id,room_id)
	var result := PackedVector2Array()
	for point: Array in definition.get("metadata",{}).get("walkable_normalized_polygon",[]):
		if point.size()==2: result.append(environment_point(arena,biome_id,Vector2(float(point[0]),float(point[1])),room_id))
	return result

static func floor_definition(biome_id: String) -> Dictionary:
	if biome_id=="B03" and FileAccess.file_exists(AssetCatalog.resolve(PUMPKIN_FLOOR_PATH)):
		var painted: Texture2D = preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(PUMPKIN_FLOOR_PATH)
		if painted!=null: return {"path":PUMPKIN_FLOOR_PATH,"source":Rect2(Vector2.ZERO,painted.get_size())}
	if FACTION_FLOOR_REGIONS.has(biome_id) and FileAccess.file_exists(AssetCatalog.resolve(FACTION_FLOOR_PATH)):
		return {"path":FACTION_FLOOR_PATH,"source":FACTION_FLOOR_REGIONS[biome_id]}
	var texture: Texture2D = preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(FLOOR_PATH)
	return {"path":FLOOR_PATH,"source":Rect2(Vector2.ZERO,texture.get_size()) if texture!=null else Rect2()}

static func floor_texture_for(biome_id: String) -> Texture2D:
	if _floors.has(biome_id): return _floors[biome_id]
	var definition: Dictionary = floor_definition(biome_id)
	var texture: Texture2D = preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(str(definition.path))
	if texture==null: return null
	if str(definition.path)==FLOOR_PATH: return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = definition.source
	atlas.filter_clip = true
	_floors[biome_id] = atlas
	return atlas

static func architecture_region(key: String) -> Dictionary:
	if _architecture.is_empty() and FileAccess.file_exists(AssetCatalog.resolve(ARCHITECTURE_MANIFEST)):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ARCHITECTURE_MANIFEST)))
		if parsed is Dictionary: _architecture = parsed
	var values: Array = _architecture.get("regions", {}).get(key, [])
	if values.size() != 4: return {}
	var area := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
	var point: Array = _architecture.get("anchors", {}).get(key, [area.size.x*0.5,area.size.y*0.88])
	var footprint: Array = _architecture.get("ground_footprints", {}).get(key, [])
	var ground := Rect2()
	if footprint.size()==4: ground = Rect2(float(footprint[0]),float(footprint[1]),float(footprint[2]),float(footprint[3]))
	return {"source":area,"foot":Vector2(float(point[0]),float(point[1])),"ground":ground}

static func architecture_tint(biome_id: String) -> Color:
	match biome_id:
		"B02": return Color(1.0,0.91,0.73)
		"B03": return Color(0.92,1.0,0.94)
		"B04": return Color(1.0,0.79,0.65)
		_: return Color.WHITE

static func palette(biome_id: String) -> Dictionary:
	match biome_id:
		"B02":
			return {"ground":Color("f4d68f"),"stone":Color("ffe3a7"),"stone_side":Color("cea15f"),"seam":Color("bf985d"),"foliage":Color("60834c"),"leaf":Color("a9c372"),"water":Color("6fb6a1"),"accent":Color("e5a548"),"gold":Color("e7b559"),"shadow":Color("8b7858")}
		"B03":
			return {"ground":Color("dce6d7"),"stone":Color("e8efd9"),"stone_side":Color("b6a6c2"),"seam":Color("aa94b8"),"foliage":Color("698c75"),"leaf":Color("a3bf94"),"water":Color("929ac2"),"accent":Color("df9663"),"gold":Color("dfa65b"),"shadow":Color("7d748c")}
		"B04":
			return {"ground":Color("e6a079"),"stone":Color("efc18f"),"stone_side":Color("bd7a5c"),"seam":Color("a6734e"),"foliage":Color("6e854f"),"leaf":Color("b5bf79"),"water":Color("72a89b"),"accent":Color("df774b"),"gold":Color("e4b565"),"shadow":Color("86664f")}
		_:
			return {"ground":Color("f3e2c5"),"stone":Color("f8e9cd"),"stone_side":Color("d0b69a"),"seam":Color("c6b18d"),"foliage":Color("3d8b78"),"leaf":Color("86c491"),"water":Color("379c9b"),"accent":Color("63bdba"),"gold":Color("dca957"),"shadow":Color("6a706b")}

static func material_for(biome_id: String) -> ShaderMaterial:
	if not _materials.has(biome_id):
		var colors: Dictionary = palette(biome_id)
		var result := ShaderMaterial.new()
		result.shader = PROP_SHADER
		result.set_shader_parameter("cream", colors.stone)
		result.set_shader_parameter("shadow", colors.shadow)
		result.set_shader_parameter("brass", colors.gold)
		result.set_shader_parameter("accent", colors.accent)
		_materials[biome_id] = result
	return _materials[biome_id]
