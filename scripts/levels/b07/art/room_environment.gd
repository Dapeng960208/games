extends Node2D
## Explicit opt-in canyon-gate trial. Original artwork is registered to fixed
## blueprint space; scenery never becomes navigation, damage or puzzle state.
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Sampler = preload("res://scripts/presentation/world/environment_detail.gd")
const Clip = preload("res://shaders/levels/b07/ground_clip.gdshader")
const ROOT := "asset://levels/b07/rooms/l37/"
const BLUEPRINT_BOUNDS := Rect2(-900,-800,4600,3000)
const BOUNDS := Rect2(-522,-464,2668,1740)
var layers: Array[Sprite2D]=[]
var source_polygon := PackedVector2Array()
var foundation: Node2D
var guardian_plinth: Node2D
func configure(layout: Dictionary) -> bool:
	if not Rules.b07_candidate_enabled() or "--b07-art-trial" not in OS.get_cmdline_user_args(): return false
	if not bool(layout.get("b07_candidate",false)) or str(layout.get("blueprint_room_id",""))!="L37" or not layers.is_empty(): return false
	for p: Array in Geometry.room("L37").walkable_polygon: source_polygon.append(Vector2(p[0],p[1]))
	if source_polygon.size()<3 or source_polygon.size()>16: return false
	if not _masked_layer("canyon_backdrop.png",BLUEPRINT_BOUNDS,true,"CanyonCityBackdrop",0): return false
	var rock:=Sampler.load_mip_texture(ROOT+"cliff_foundation.png")
	foundation=preload("res://scripts/levels/b07/art/terrace_foundation.gd").new()
	add_child(foundation)
	foundation.z_index=1
	if not foundation.configure(rock,source_polygon,0): return false
	if not _masked_layer("sandstone_floor.png",Rect2(0,0,2800,1800),false,"WalkableTerrace",2): return false
	guardian_plinth=preload("res://scripts/levels/b07/art/guardian_plinth.gd").new()
	add_child(guardian_plinth)
	guardian_plinth.z_index=3
	if not guardian_plinth.configure(layers[1].texture,rock): return false
	var guardian_texture:=Sampler.load_mip_texture(ROOT+"west_guardian.png")
	if guardian_texture==null: return false
	var guardian:=Sprite2D.new()
	guardian.name="WesternLizardGuardian"
	guardian.texture=guardian_texture
	guardian.centered=false
	guardian.region_enabled=true
	guardian.region_rect=Rect2(68,88,913,1378)
	var factor:=650.0/913.0
	guardian.position=Vector2(-700,1380-1378*factor)*Geometry.SCALE
	guardian.scale=Vector2.ONE*factor*Geometry.SCALE
	guardian.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	guardian.z_index=4
	add_child(guardian)
	layers.append(guardian)
	return true
func _masked_layer(filename: String, bounds: Rect2, exterior: bool, title: String, depth: int) -> bool:
	var texture:=Sampler.load_mip_texture(ROOT+filename)
	if texture==null: return false
	var size:=texture.get_size()
	var scale_to_blueprint:=maxf(bounds.size.x/size.x,bounds.size.y/size.y)
	var scaled_size:=size*scale_to_blueprint
	var crop:=(scaled_size-bounds.size)*.5
	var sprite:=Sprite2D.new()
	sprite.name=title
	sprite.texture=texture
	sprite.centered=false
	sprite.position=(bounds.position-crop)*Geometry.SCALE
	sprite.scale=Vector2.ONE*scale_to_blueprint*Geometry.SCALE
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.z_index=depth
	var polygon_uniform:=source_polygon.duplicate()
	polygon_uniform.resize(16)
	var mask:=ShaderMaterial.new()
	mask.shader=Clip
	mask.set_shader_parameter("ground",polygon_uniform)
	mask.set_shader_parameter("ground_count",source_polygon.size())
	mask.set_shader_parameter("scaled_blueprint_size",scaled_size)
	mask.set_shader_parameter("blueprint_crop",crop)
	mask.set_shader_parameter("blueprint_origin",bounds.position)
	mask.set_shader_parameter("draw_area_size",bounds.size)
	mask.set_shader_parameter("exterior",exterior)
	sprite.material=mask
	add_child(sprite)
	layers.append(sprite)
	return true
