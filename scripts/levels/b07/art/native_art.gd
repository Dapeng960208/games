extends RefCounted
## First identity-reviewed M01 idle pilot. No other species/poses are implied.
## Native anchors affect presentation only, never strike origins or collision.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const MANIFEST := "asset://levels/b07/registration/native_art.json"
static var _manifest: Dictionary={}
static func enabled() -> bool:
	return Rules.b07_candidate_enabled() and "--b07-art-trial" in OS.get_cmdline_user_args()
static func manifest() -> Dictionary:
	if not enabled(): return {}
	if _manifest.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(MANIFEST)))
		if raw is Dictionary and raw.get("version")==1 and raw.get("asset_family")=="storybook_2_5d_v1": _manifest=raw
	return _manifest
static func frame(identity: String, pose: String = "idle") -> Dictionary:
	if identity!="B07-M01": return {}
	var record: Dictionary=manifest().get("identities",{}).get(identity,{})
	if not bool(record.get("source_identity_review_passed",false)): return {}
	var source: Dictionary=record.get("frames",{}).get(pose,{})
	if not source.has_all(["texture","region","foot","core_anchor","visual_outlet"]): return {}
	var filename:=str(source.texture)
	if not filename.begins_with("asset://levels/b07/enemies/m01/") or not filename.ends_with(".png"): return {}
	var texture:=Sampler.sampled(filename)
	if texture==null or float(record.get("reference_body_height_px",0))<=0: return {}
	var region:=Rect2(float(source.region[0]),float(source.region[1]),float(source.region[2]),float(source.region[3]))
	var foot:=Vector2(source.foot[0],source.foot[1])
	if not Rect2(Vector2.ZERO,texture.get_size()).encloses(region) or not region.has_point(foot): return {}
	return {"name":pose,"texture":texture,"texture_path":filename,"region":region,"foot":foot,
		"core":Vector2(source.core_anchor[0],source.core_anchor[1]),"outlet":Vector2(source.visual_outlet[0],source.visual_outlet[1]),
		"reference_height":float(record.reference_body_height_px),"runtime_quality_gate_passed":false}
static func entry(identity: String) -> Dictionary:
	var idle:=frame(identity)
	if idle.is_empty(): return {}
	return {"texture":idle.texture,"texture_path":idle.texture_path,"region":idle.region,"foot":idle.foot,
		"source_height":idle.reference_height,"source_family":"storybook_2_5d_v1","biome_id":"B07","visual_clan":"lizard",
		"individual_body":true,"b07_native_bank":true,"runtime_quality_gate_passed":false}
static func bank(identity: String) -> Dictionary:
	var clips: Dictionary={}
	for pose: String in ["idle","telegraph","execute"]:
		var value:=frame(identity,pose)
		if value.is_empty(): return {} # An idle pilot is not a complete motion bank.
		clips[pose]=[value]
	clips["locked"]=clips.telegraph
	clips["walk"]=clips.idle
	clips["recovery"]=clips.idle
	return {"clips":clips,"texture":clips.idle[0].texture,"body_height":clips.idle[0].reference_height,
		"source_family":"storybook_2_5d_v1","facing":"right","b07_native_bank":true,"runtime_quality_gate_passed":false}
