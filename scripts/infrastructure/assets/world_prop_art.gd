class_name WorldPropArt
extends RefCounted
## Fresh painted map props and automatic beacons share raw atlases. Identity
## stays with the original gameplay asset key; regional UVs preserve all art.

const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const MANIFESTS := [
	"asset://props/storybook_props_b01_b02_v1.regions.json",
	"asset://props/storybook_props_b03_b04_v1.regions.json",
	"asset://props/storybook_props_factions_v2.regions.json",
	"asset://props/storybook_beacons_v1.regions.json",
	"asset://props/fixed_B01_props_v1.regions.json",
	"asset://props/fixed_B02_props_v1.regions.json",
	"asset://props/fixed_B03_props_v1.regions.json",
	"asset://props/fixed_B04_props_v1.regions.json",
	"asset://world/fixed_B01_edges_v1.regions.json",
	"asset://world/fixed_B02_edges_v1.regions.json",
	"asset://world/fixed_B03_edges_v1.regions.json",
	"asset://world/fixed_B04_edges_v1.regions.json"]
const ASSET_ALIASES := {
	"B01_winch":"B03_transformer", "B01_ore_cart":"B03_wrecked_drone", "B01_crate_stack":"B03_pipe_manifold",
	"B02_spore_nest":"B01_winch", "B02_root_barrier":"B01_crate_stack", "B02_fungal_rock":"B01_ore_cart",
	"B03_transformer":"T03_pumpkin_lantern", "B03_pipe_manifold":"T03_grave_barrier", "B03_wrecked_drone":"T03_funeral_cart",
	"B04_crystal_cluster":"T04_terracotta_cache", "B04_resonance_obelisk":"T04_war_totem", "B04_broken_receiver":"T04_signal_gong"}
static var _definitions: Dictionary = {}
static var _loaded: Dictionary = {}
static var _textures: Dictionary = {}
static var _fallback_assets: Dictionary = {}
static var _ground_inlays: Dictionary = {}
static var _compositions: Dictionary = {}

static func _load_manifests() -> void:
	for path: String in MANIFESTS:
		if _loaded.has(path) or not FileAccess.file_exists(AssetCatalog.resolve(path)): continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
		if not value is Dictionary or not value.get("regions") is Dictionary: continue
		var atlas_path: String = str(value.get("texture", ""))
		if atlas_path.is_empty(): continue
		for key: String in value.get("fallback_assets", {}):
			_fallback_assets[key] = str(value.fallback_assets[key])
		for key: String in value.get("fallback_aliases", {}):
			_fallback_assets[key] = str(value.fallback_aliases[key])
		for key: String in value.get("fallbacks", {}):
			_fallback_assets[key] = str(value.fallbacks[key])
		_ground_inlays.merge(value.get("ground_inlays",{}),true)
		_compositions.merge(value.get("landmark_compositions",{}),true)
		for key: String in value.regions:
			var pixels: Array = value.regions[key]
			if pixels.size()!=4: continue
			var source := Rect2(float(pixels[0]),float(pixels[1]),float(pixels[2]),float(pixels[3]))
			var anchor: Array = value.get("anchors", {}).get(key, [source.size.x*.5,source.size.y*.88])
			var footprint: Array = value.get("ground_footprints", {}).get(key, [])
			var ground := Rect2()
			if footprint.size()==4: ground = Rect2(float(footprint[0]),float(footprint[1]),float(footprint[2]),float(footprint[3]))
			_definitions[key] = {"path":atlas_path,"source":source,"foot":Vector2(float(anchor[0]),float(anchor[1])),"ground":ground}
		_loaded[path] = true

static func definition_for_asset(asset: String) -> Dictionary:
	_load_manifests()
	if _definitions.has(asset) and not ASSET_ALIASES.has(asset): return _definitions[asset]
	var key: String = str(_fallback_assets.get(asset,ASSET_ALIASES.get(asset,asset)))
	if not _definitions.has(key) and asset.contains("_prop_"):
		key = _same_faction_fallback(asset)
	return _definitions.get(key,{})

static func is_ground_inlay(asset: String) -> bool:
	_load_manifests()
	return _ground_inlays.has(asset)

static func composition_for_asset(asset: String) -> Array:
	_load_manifests()
	return _compositions.get(asset,[])

static func _same_faction_fallback(asset: String) -> String:
	# Missing minor drawings borrow a related object of their own civilization.
	# Completed manifests override these compatibility choices automatically.
	var structural: bool = "arch" in asset or "barrier" in asset or "column" in asset or "stela" in asset or "gate" in asset
	var utility: bool = "cart" in asset or "boat" in asset or "bench" in asset or "loom" in asset or "rack" in asset
	match asset.left(3):
		"B02": return "B01_crate_stack" if structural else ("B01_ore_cart" if utility else "B01_winch")
		"B03": return "T03_grave_barrier" if structural else ("T03_funeral_cart" if utility else "T03_pumpkin_lantern")
		"B04": return "T04_war_totem" if structural else ("T04_terracotta_cache" if utility else "T04_signal_gong")
	return "B03_pipe_manifold" if structural else ("B03_wrecked_drone" if utility else "B03_transformer")

static func has_authored_asset(asset: String) -> bool:
	return not definition_for_asset(asset).is_empty()

static func visual_identity(asset: String) -> String:
	# Aliases are compared by the effective image region, never by their label.
	if is_ground_inlay(asset): return "ground_inlay:"+asset
	var definition: Dictionary = definition_for_asset(asset)
	if definition.is_empty(): return ""
	var texture: Texture2D = texture_for_asset(asset)
	if texture==null: return ""
	var source: Rect2 = definition.source
	return str(definition.path)+"::%s,%s,%s,%s" % [source.position.x,source.position.y,source.size.x,source.size.y]

static func faction_assets(biome_id: String) -> Array[String]:
	_load_manifests()
	var keys: Array[String] = []
	for key: String in _definitions:
		if key.begins_with(biome_id+"_prop_") or key.begins_with(biome_id+"_edge_"):
			keys.append(key)
	keys.sort()
	return keys

static func texture_for_asset(asset: String) -> Texture2D:
	if _textures.has(asset): return _textures[asset]
	var definition: Dictionary = definition_for_asset(asset)
	if definition.is_empty():
		return Sampler.sampled(asset if (asset.begins_with("res://") or asset.begins_with("asset://")) else "asset://props/"+asset+"_v1.png")
	var parent: Texture2D = Sampler.sampled(str(definition.path))
	if parent==null or not Rect2(Vector2.ZERO,parent.get_size()).encloses(definition.source): return null
	var result := AtlasTexture.new()
	result.atlas = parent
	result.region = definition.source
	result.filter_clip = true
	_textures[asset] = result
	return result

static func local_region(asset: String) -> Rect2:
	var texture: Texture2D = texture_for_asset(asset)
	return Rect2(Vector2.ZERO,texture.get_size()) if texture!=null else Rect2()

static func fitted_scale(asset: String, target_size: Vector2) -> float:
	var texture: Texture2D = texture_for_asset(asset)
	if texture==null or texture.get_width()<=0 or texture.get_height()<=0: return 0.0
	return minf(target_size.x/texture.get_width(),target_size.y/texture.get_height())

static func bounds_at(asset: String, foot: Vector2, target_size: Vector2) -> Rect2:
	var texture: Texture2D = texture_for_asset(asset)
	if texture==null: return Rect2()
	var scale: float = fitted_scale(asset,target_size)
	var definition: Dictionary = definition_for_asset(asset)
	var native_foot: Vector2 = definition.get("foot",Vector2(texture.get_width()*.5,texture.get_height()))
	return Rect2(foot-native_foot*scale,texture.get_size()*scale)

static func sprite_quad(item: Dictionary) -> PackedVector2Array:
	var asset: String = str(item.get("asset",""))
	var texture: Texture2D = texture_for_asset(asset)
	if texture==null: return PackedVector2Array()
	var bounds: Vector2 = item.get("visual_size",Vector2.ZERO)
	var rotation: float = float(item.get("rotation",0.0))
	var rotated_size := Vector2(texture.get_width()*absf(cos(rotation))+texture.get_height()*absf(sin(rotation)),texture.get_width()*absf(sin(rotation))+texture.get_height()*absf(cos(rotation)))
	if bounds.x<=0 or bounds.y<=0: return PackedVector2Array()
	var scale: float = minf(bounds.x/rotated_size.x,bounds.y/rotated_size.y)
	var definition: Dictionary = definition_for_asset(asset)
	var anchor: Vector2 = definition.get("foot",Vector2(texture.get_width()*.5,texture.get_height()))
	var collision: Rect2 = item.get("collision_rect",Rect2())
	var foot: Vector2 = collision.get_center() if collision.has_area() else Vector2(item.get("position",Vector2.ZERO))
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2.ZERO,Vector2(texture.get_width(),0),texture.get_size(),Vector2(0,texture.get_height())]:
		points.append(foot+(corner-anchor).rotated(rotation)*scale)
	return points

static func authored_tint(tint: Color = Color.WHITE) -> Color:
	# A shared old-prop shader grades only pure-white commands. New painted
	# colors are already authored, and retain them with an imperceptible tint.
	return Color(tint.r*.994,tint.g*.994,tint.b*.994,tint.a)

static func draw_asset(canvas: CanvasItem, asset: String, foot: Vector2, target_size: Vector2, tint: Color = Color.WHITE) -> bool:
	var texture: Texture2D = texture_for_asset(asset)
	if texture==null: return false
	canvas.draw_texture_rect(texture,bounds_at(asset,foot,target_size),false,authored_tint(tint))
	return true
