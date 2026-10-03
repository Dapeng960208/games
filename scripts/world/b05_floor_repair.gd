extends Node2D
## Candidate-only native material overlay. Frozen collision/portals are unchanged.
const Geometry=preload("res://scripts/world/b05_room_geometry.gd")
const WorldArt=preload("res://scripts/world/world_art.gd")
const Sampler=preload("res://scripts/world/environment_detail.gd")
const ShaderSource=preload("res://shaders/b05_floor_repair.gdshader")
var world_rect:=Rect2()
var source_polygon:=PackedVector2Array()
var portal:=Rect2()
var layers: Array[Sprite2D]=[]
func configure(layout: Dictionary,allow_candidate: bool=false) -> bool:
	var id:=WorldArt.environment_room_id(layout)
	if not layers.is_empty() or id not in ["L26","L27","L29","L30","BO05"]: return false
	var folder:="res://assets/generated/world/rooms_2k/"+id+"/"
	var definitions: Array[Dictionary]=[]
	for name: String in ["floor_repair_v1","root_fascia_v1"]:
		var path:=folder+name+".json"
		if not FileAccess.file_exists(path): return false
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or (not allow_candidate and not bool(value.get("approved",false))): return false
		definitions.append(value)
	var patch_path:=folder+"native_floor_patches_v1.json"
	if FileAccess.file_exists(patch_path):
		var patches: Variant=JSON.parse_string(FileAccess.get_file_as_string(patch_path))
		if patches is Dictionary and (allow_candidate or bool(patches.get("approved",false))):
			var fascia_definition: Dictionary=definitions[1]
			fascia_definition["recommended_repair_source_rect"]=definitions[0].get("recommended_repair_source_rect",[205,680,1130,175])
			definitions.clear()
			for patch: Dictionary in patches.get("patches",[]): definitions.append(patch)
			definitions.append(fascia_definition)
	var definition:=Geometry.room(id)
	for point: Array in definition.art.walkable_normalized_polygon: source_polygon.append(Vector2(point[0],point[1])*Vector2(1536,1024))
	if source_polygon.size()<3 or source_polygon.size()>16: return false
	world_rect=WorldArt.environment_world_rect(layout.arena,"B05",id)
	if not world_rect.has_area(): return false
	# Portals follow the room's fixed authored entry/exit and200-world-pixel width.
	portal=_portal_rect(definition.entry)
	var second_portal:=_portal_rect(definition.exit)
	var polygon_uniform:=source_polygon.duplicate();polygon_uniform.resize(16)
	for index in definitions.size():
		var texture:=Sampler.load_mip_texture(str(definitions[index].texture))
		if texture==null: return false
		var sprite:=Sprite2D.new();sprite.texture=texture;sprite.centered=false
		sprite.visible=bool(definitions[index].get("visible",true))
		sprite.position=world_rect.position;sprite.scale=world_rect.size/texture.get_size()
		sprite.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var mat:=ShaderMaterial.new();mat.shader=ShaderSource
		mat.set_shader_parameter("ground",polygon_uniform);mat.set_shader_parameter("ground_count",source_polygon.size())
		mat.set_shader_parameter("south_portal",Vector4(portal.position.x,portal.position.y,portal.size.x,portal.size.y))
		var repair_rect: Array=definitions[index].get("recommended_repair_source_rect",[205,680,1130,175])
		mat.set_shader_parameter("repair_rect",Vector4(repair_rect[0],repair_rect[1],repair_rect[2],repair_rect[3]))
		var clip_rect: Array=definitions[index].get("paint_clip_source_rect",repair_rect)
		mat.set_shader_parameter("paint_clip_rect",Vector4(clip_rect[0],clip_rect[1],clip_rect[2],clip_rect[3]))
		var entrance_join: Array=definitions[index].get("entrance_join_source_rect",[0,0,0,0])
		mat.set_shader_parameter("entrance_join_rect",Vector4(entrance_join[0],entrance_join[1],entrance_join[2],entrance_join[3]))
		mat.set_shader_parameter("secondary_portal",Vector4(second_portal.position.x,second_portal.position.y,second_portal.size.x,second_portal.size.y))
		var feathers: Array=definitions[index].get("repair_feather_source_pixels",[0,32,0,0])
		mat.set_shader_parameter("repair_feather",Vector4(feathers[0],feathers[1],feathers[2],feathers[3]))
		mat.set_shader_parameter("fascia_all_edges",bool(definitions[-1].get("fascia_all_edges",false)))
		mat.set_shader_parameter("fascia_in_repair_region",bool(definitions[-1].get("fascia_in_repair_region",false)))
		mat.set_shader_parameter("reference_painting",WorldArt.environment_texture_for("B05",id))
		mat.set_shader_parameter("match_reference_shading",bool(definitions[index].get("match_reference_shading",false)))
		var reference: Array=definitions[index].get("reference_offset_source_pixels",[0,-96])
		mat.set_shader_parameter("reference_offset",Vector2(reference[0],reference[1]))
		var average: Array=definitions[index].get("material_average_rgb",[.85,.70,.45])
		mat.set_shader_parameter("material_average",Vector3(average[0],average[1],average[2]))
		mat.set_shader_parameter("unique_patch",bool(definitions[index].get("unique_patch",false)))
		mat.set_shader_parameter("fascia",index==definitions.size()-1)
		sprite.material=mat;add_child(sprite);layers.append(sprite)
	z_index=-7
	return true

func _portal_rect(blueprint: Array) -> Rect2:
	var at:=Geometry.image_point(blueprint,Vector2i(1536,1024))
	var half:=Vector2(100,100)/world_rect.size*Vector2(1536,1024)
	var distances: Array[float]=[at.x-220,1316-at.x,at.y-217,832-at.y]
	var side:=distances.find(distances.min())
	match side:
		0: return Rect2(0,at.y-half.y,at.x+40,half.y*2)
		1: return Rect2(at.x-40,at.y-half.y,1536-at.x+40,half.y*2)
		2: return Rect2(at.x-half.x,0,half.x*2,at.y+40)
		_: return Rect2(at.x-half.x,at.y-40,half.x*2,1024-at.y+40)
