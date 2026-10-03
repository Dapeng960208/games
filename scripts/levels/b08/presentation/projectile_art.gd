extends RefCounted
## Native feather arrow follows the unchanged frozen projectile position/direction.
var texture: Texture2D
var region:=Rect2()
var world_length:=36.0
var source: Dictionary={}
func configure(room_id: String) -> bool:
	if room_id!="L43" or not OS.get_cmdline_user_args().has("--b08-art-l43") or not OS.get_cmdline_user_args().has("--b08-art-convergence"): return false
	var root:="asset://b08/enemies/m01/"
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(root+"projectile.json")))
	if not parsed is Dictionary: return false
	source=parsed
	texture=preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(root+str(source.file))
	var values: Array=source.region
	region=Rect2(values[0],values[1],values[2],values[3])
	world_length=float(source.world_length)
	return texture!=null and region.size.x>0 and Rect2(Vector2.ZERO,texture.get_size()).encloses(region)
func bounds() -> Rect2:
	var height:=world_length*region.size.y/region.size.x
	return Rect2(-world_length+6,-height*.5,world_length,height)
func draw(canvas: CanvasItem, shot: Dictionary) -> bool:
	if texture==null or shot.packet.get("enemy_id","")!="B08-M01": return false
	canvas.draw_set_transform(shot.position,Vector2(shot.direction).angle())
	canvas.draw_texture_rect_region(texture,bounds(),region)
	canvas.draw_set_transform(Vector2.ZERO)
	return true
