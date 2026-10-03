extends Node2D
## Native candidate void painting bound to the authored collision rectangle.
const Geometry=preload("res://scripts/levels/b05/world/room_geometry.gd")
const TextureSource=preload("res://scripts/presentation/world/environment_detail.gd")
var texture: Texture2D
var world_rect:=Rect2()
func configure(layout: Dictionary,allow_candidate: bool=false) -> bool:
	if preload("res://scripts/infrastructure/assets/world_art.gd").environment_room_id(layout)!="L27": return false
	var path:="asset://world/rooms_2k/L27/void_v2.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(path)): return false
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	if not value is Dictionary or (not allow_candidate and not bool(value.get("approved",false))): return false
	var definition:=Geometry.room("L27")
	var index:=int(value.get("void_index",-1))
	if index<0 or index>=definition.get("voids",[]).size(): return false
	var rectangle: Array=definition.voids[index]
	world_rect=Rect2(Geometry.world_point([rectangle[0],rectangle[1]]),Geometry.world_point([rectangle[2],rectangle[3]]))
	texture=TextureSource.load_mip_texture(str(value.texture))
	if texture==null: return false
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw();return true
func _draw() -> void:
	if texture!=null: draw_texture_rect(texture,world_rect,false)
