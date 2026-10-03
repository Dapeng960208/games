extends RefCounted
## Each body uses native pixels with a single uniform reduction. No stretch or
## pixel enlargement: the ground foot and contact mask share this exact bounds.
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
static var _frames: Dictionary = {}

static func frame(id: String) -> Dictionary:
	if _frames.has(id): return _frames[id]
	var path := Skills.art_id(id)
	if not FileAccess.file_exists(AssetCatalog.resolve(path)) and not ResourceLoader.exists(AssetCatalog.resolve(path)): return {}
	var texture: Texture2D = Sampler.sampled(path)
	if texture==null: return {}
	var size := texture.get_size()
	var height := 300.0 if id=="BO10" else 218.0 if Skills.is_boss(id) else 112.0
	var factor := minf(1.0,height/size.y)
	var foot := size*Vector2(.5,.84)
	var value := {"texture":texture,"region":Rect2(Vector2.ZERO,size),"bounds":Rect2(-foot*factor,size*factor),"name":"idle","texture_path":path,"full_color":true,"source_family":"b10_bright_handpainted_2_5d","scale":factor,"foot":Vector2.ZERO}
	_frames[id]=value
	return value
