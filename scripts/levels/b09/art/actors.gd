extends RefCounted
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
static var _data: Dictionary = {}
static func manifest() -> Dictionary:
	if _data.is_empty(): _data=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("asset://b09/actors.json")))
	return _data
static func frame(identity: String, pose: String = "idle") -> Dictionary:
	var entry: Dictionary=manifest().identities.get(identity,{})
	if entry.is_empty(): return {}
	var value: Dictionary=entry.frames.get(pose,entry.frames.idle)
	var texture := Sampler.sampled(str(value.texture))
	if texture==null: return {}
	return {"texture":texture,"texture_path":value.texture,"region":Rect2(float(value.region[0]),float(value.region[1]),float(value.region[2]),float(value.region[3])),
		"foot":Vector2(float(value.foot[0]),float(value.foot[1])),"core":Vector2(float(value.core_anchor[0]),float(value.core_anchor[1])),
		"outlet":Vector2(float(value.visual_outlet[0]),float(value.visual_outlet[1])),"reference_height":float(entry.reference_body_height_px),"name":pose}
static func entry(identity: String) -> Dictionary:
	var value := frame(identity)
	if value.is_empty(): return {}
	return {"texture":value.texture,"texture_path":value.texture_path,"region":value.region,"foot":value.foot,"source_height":value.reference_height,
		"source_family":"storybook_2_5d_v1","biome_id":"B09","visual_clan":"crystal","individual_body":identity!="BO09","combat_body":identity=="BO09","b09_native_bank":true}
static func bank(identity: String) -> Dictionary:
	var clips := {}
	for pose: String in ["idle","telegraph","execute"]:
		var value := frame(identity,pose)
		if value.is_empty(): return {}
		clips[pose]=[value]
	clips["walk"]=clips.idle
	clips["locked"]=clips.telegraph
	clips["recovery"]=clips.idle
	return {"clips":clips,"texture":clips.idle[0].texture,"body_height":clips.idle[0].reference_height,"source_family":"storybook_2_5d_v1","facing":"right","b09_native_bank":true}
