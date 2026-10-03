extends RefCounted
## One original native idle pose only; no claim of a directional/action bank.
const ROOT := "asset://b08/enemies/m01/"
var texture: Texture2D
var region := Rect2()
var foot := Vector2.ZERO
var body_height := 0.0
var world_height := 100.0
var metadata: Dictionary = {}
func configure(identity: String, room_id: String) -> bool:
	if identity!="B08-M01" or room_id!="L43" or not OS.get_cmdline_user_args().has("--b08-art-l43"): return false
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT+"manifest.json")))
	if not parsed is Dictionary: return false
	metadata=parsed
	texture=preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(ROOT+str(metadata.file))
	if texture==null: return false
	var frame: Dictionary=metadata.frame
	region=Rect2(frame.region[0],frame.region[1],frame.region[2],frame.region[3])
	foot=Vector2(frame.foot[0],frame.foot[1])
	body_height=float(metadata.body_height)
	world_height=float(metadata.world_body_height)
	return body_height>0 and Rect2(Vector2.ZERO,texture.get_size()).encloses(region)
func bounds(mirrored: bool = false) -> Rect2:
	var factor:=world_height/body_height
	var offset: Vector2=(region.position-foot)*factor
	var size: Vector2=region.size*factor
	if mirrored: offset.x=-offset.x-size.x
	return Rect2(offset,size)
func draw(canvas: CanvasItem, mirrored: bool = false, flash: float = 0.0) -> void:
	if texture==null: return
	canvas.draw_set_transform(Vector2.ZERO,0,Vector2(-1,1) if mirrored else Vector2.ONE)
	canvas.draw_texture_rect_region(texture,bounds(),region,Color.WHITE.lerp(Color(1.15,1.15,1.15),clampf(flash,0,1)))
	canvas.draw_set_transform(Vector2.ZERO)
