extends RefCounted
## Native separate-texture B05 pose bank. Existing atlases and all 599 variant
## records are untouched. A fixed anatomy ratio is reused for every source pose.
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const ROOT := "asset://enemies/b05_poses_v1/"
const REGENERATED_ROOT := "asset://enemies/b05_regenerated_poses_v1/"
const FIRST_ROOM_ROOT := "asset://levels/b05/enemies/"
const FIRST_ROOM_IDS := ["B05-M01","B05-M02","B05-M04"]
const IDS := ["B05-M01","B05-M02","B05-M03","B05-M04","B05-M05","B05-M06","B05-M07","B05-M08","B05-M09","B05-M10","B05-M11","B05-M12","B05-M13","B05-M14","B05-M15","B05-M16","B05-M17","B05-M18"]
static var _banks: Dictionary={}
static var _loaded: Dictionary={}
static var _first_room_banks: Dictionary={}
static var _first_room_loaded: Dictionary={}

static func entry(identity: String) -> Dictionary:
	return _entry_from_bank(bank(identity))

## An explicitly selected room body variant; codex/default art remains unchanged.
static func first_room_entry(identity: String) -> Dictionary:
	var result := _entry_from_bank(first_room_bank(identity))
	if not result.is_empty(): result["first_room_race_variant"] = true
	return result

static func _entry_from_bank(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var frame: Dictionary=value.clips.idle[0]
	return {"texture":frame.texture,"texture_path":frame.texture_path,"region":frame.region,"foot":frame.foot,
		"source_height":value.body_height,"source_family":"storybook_2_5d_v1","biome_id":"B05","visual_clan":"plant",
		"individual_body":true,"b05_native_bank":true,"runtime_quality_gate_passed":bool(value.get("runtime_quality_gate_passed",false))}

static func bank(identity: String) -> Dictionary:
	if identity not in IDS: return {}
	_ensure_loaded(identity)
	return _banks.get(identity,{}).duplicate(true)

static func first_room_bank(identity: String) -> Dictionary:
	if identity not in FIRST_ROOM_IDS: return {}
	if not _first_room_loaded.has(identity):
		_first_room_loaded[identity] = true
		_load_manifest(FIRST_ROOM_ROOT,identity,true)
	return _first_room_banks.get(identity,{}).duplicate(true)

static func _ensure_loaded(identity: String) -> void:
	if _loaded.has(identity): return
	_loaded[identity]=true
	# Metadata is cheap; only the encountered species owns resident pose textures.
	# Keep manifest precedence and fallback unchanged without preloading all 54.
	_load_manifest(ROOT,identity)
	_load_manifest(REGENERATED_ROOT,identity)

static func _load_manifest(source_root: String, requested_identity: String, first_room_variant: bool = false) -> void:
	var manifest_name := "manifest_first_room_revision.json" if first_room_variant else "manifest.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(source_root+manifest_name)): return
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(source_root+manifest_name)))
	if not raw is Dictionary or raw.get("asset_family")!="storybook_2_5d_v1": return
	for identity: String in [requested_identity]:
		var source: Dictionary=raw.get("identities",{}).get(identity,{})
		if source.is_empty() or float(source.get("reference_body_height_px",0))<=0: continue
		var clips: Dictionary={}
		for pose: String in ["idle","telegraph","execute"]:
			var spec: Dictionary=source.get("frames",{}).get(pose,{})
			if spec.is_empty(): continue
			var path: String=source_root+str(spec.texture)
			if not FileAccess.file_exists(AssetCatalog.resolve(path)) and not ResourceLoader.exists(AssetCatalog.resolve(path)): continue
			var texture: Texture2D=Sampler.sampled(path)
			if texture==null: continue
			var region:=Rect2(float(spec.region[0]),float(spec.region[1]),float(spec.region[2]),float(spec.region[3]))
			var foot:=Vector2(float(spec.foot[0]),float(spec.foot[1]))
			var outlet:=Vector2(float(spec.visual_outlet[0]),float(spec.visual_outlet[1]))
			if not Rect2(Vector2.ZERO,texture.get_size()).encloses(region) or not region.has_point(foot) or not region.has_point(outlet): continue
			var outlets: Array[Vector2]=[]
			for point: Array in spec.get("outlets",[spec.visual_outlet]):
				var anchor:=Vector2(float(point[0]),float(point[1]))
				if region.has_point(anchor): outlets.append(anchor)
			clips[pose]=[{"name":pose,"texture":texture,"texture_path":path,"region":region,"foot":foot,"outlet":outlet,"outlets":outlets,"core":Vector2(float(spec.core_anchor[0]),float(spec.core_anchor[1]))}]
		if clips.size()!=3: continue
		clips["locked"]=clips.telegraph
		if identity=="B05-M04":
			clips["telegraph"]=[clips.telegraph[0],clips.execute[0]]
			clips["locked"]=clips.execute
		clips["walk"]=clips.idle
		clips["recovery"]=clips.idle
		var target: Dictionary = _first_room_banks if first_room_variant else _banks
		target[identity]={"clips":clips,"texture":clips.idle[0].texture,"body_height":float(source.reference_body_height_px),"source_family":"storybook_2_5d_v1","facing":"right","b05_native_bank":true,"runtime_quality_gate_passed":bool(source.get("runtime_quality_gate_passed",raw.get("runtime_quality_gate_passed",false)))}
