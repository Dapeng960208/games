extends Node2D
## Fixed full-canvas native states; no alpha-bounds fitting or collision edits.
const Source=preload("res://scripts/presentation/world/environment_detail.gd")
var host: Node2D
var leaf_id:=""
var states: Dictionary={}
var canvas_size:=Vector2(140,140)
func configure(owner_host: Node2D,id: String,point: Vector2) -> bool:
	var path:="asset://world/b05_sunleaf/manifest.json"
	if not FileAccess.file_exists(AssetCatalog.resolve(path)): return false
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	if not value is Dictionary: return false
	var size: Array=value.get("suggested_full_canvas_world_size",[140,140]);canvas_size=Vector2(size[0],size[1])
	for spec: Dictionary in value.get("states",[]):
		var native:=Source.load_mip_texture(str(spec.texture))
		if native==null: return false
		states[str(spec.id)]={"texture":native,"pivot":Vector2(spec.foot_uv[0],spec.foot_uv[1])}
	if not states.has("open") or not states.has("closed"): return false
	host=owner_host;leaf_id=id;position=point;z_index=2
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw();return true
func _draw() -> void:
	if not is_instance_valid(host) or states.is_empty(): return
	var key:="closed" if bool(host._sunleaf_closed.get(leaf_id,false)) else "open"
	var value: Dictionary=states[key]
	draw_texture_rect(value.texture,Rect2(-canvas_size*Vector2(value.pivot),canvas_size),false)
