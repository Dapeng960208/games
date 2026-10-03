extends RefCounted
## Original identity and selected keyposes. No claim of continuous animation.
const ROOT := "asset://b08/enemies/m01/"
const Sampler=preload("res://scripts/infrastructure/assets/texture_sampler.gd")
var texture: Texture2D
var region := Rect2()
var foot := Vector2.ZERO
var body_height := 0.0
var world_height := 100.0
var metadata: Dictionary = {}
var frames: Dictionary = {}
var textures: Dictionary = {}
var identity := ""
var active_pose := "idle"
var phase_age := 0.0
var last_phase := ""
var convergence := false
var source_scale := 0.0
var errors: Array[String] = []
func configure(actor_id: String, room_id: String) -> bool:
	if room_id!="L43" or not OS.get_cmdline_user_args().has("--b08-art-l43"): return false
	identity=actor_id
	if OS.get_cmdline_user_args().has("--b08-art-convergence") and actor_id in ["B08-M01","B08-M02","B08-M03"]:
		return _configure_poses("asset://b08/enemies/"+actor_id.trim_prefix("B08-").to_lower()+"/")
	if actor_id!="B08-M01": return false
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT+"manifest.json")))
	if not parsed is Dictionary: return false
	metadata=parsed
	texture=Sampler.sampled(ROOT+str(metadata.file))
	if texture==null: return false
	var frame: Dictionary=metadata.frame
	region=Rect2(frame.region[0],frame.region[1],frame.region[2],frame.region[3])
	foot=Vector2(frame.foot[0],frame.foot[1])
	body_height=float(metadata.body_height)
	world_height=float(metadata.world_body_height)
	source_scale=world_height/body_height if body_height>0 else 0.0
	return body_height>0 and Rect2(Vector2.ZERO,texture.get_size()).encloses(region)
func _configure_poses(root: String) -> bool:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(root+"poses.json")))
	if not parsed is Dictionary or parsed.get("actor_id","")!=identity: return false
	metadata=parsed
	world_height=float(metadata.world_body_height)
	frames=metadata.frames
	for name: String in frames:
		var frame: Dictionary=frames[name]
		var file: String=frame.file
		if not textures.has(file): textures[file]=Sampler.sampled(root+file)
		var candidate: Texture2D=textures[file]
		var values: Array=frame.region
		var rect:=Rect2(values[0],values[1],values[2],values[3])
		if candidate==null or not Rect2(Vector2.ZERO,candidate.get_size()).encloses(rect) or float(frame.world_per_source_pixel)<=0:
			errors.append("Invalid native frame: "+identity+"/"+name)
	if not errors.is_empty(): return false
	convergence=true
	set_pose("idle")
	return texture!=null
func set_pose(name: String) -> void:
	if not convergence or not frames.has(name): return
	active_pose=name
	var frame: Dictionary=frames[name]
	texture=textures[frame.file]
	var values: Array=frame.region
	region=Rect2(values[0],values[1],values[2],values[3])
	foot=Vector2(frame.foot[0],frame.foot[1])
	source_scale=float(frame.world_per_source_pixel)
	body_height=world_height/source_scale
func advance(delta: float, phase: String, action: Dictionary) -> void:
	if not convergence: return
	phase_age=phase_age+maxf(delta,0) if phase==last_phase else 0.0
	last_phase=phase
	set_pose(pose_for(phase,action,phase_age))
func pose_for(phase: String, action: Dictionary, age: float) -> String:
	if action.is_empty(): return "idle"
	if phase=="warning": return "warning"
	if phase=="transit": return "release" if identity=="B08-M02" else "idle"
	if phase=="recovery":
		if identity in ["B08-M01","B08-M03"] and age<.16: return "release"
		return "recovery"
	return "idle"
func bounds(mirrored: bool = false) -> Rect2:
	var factor:=source_scale
	var offset: Vector2=(region.position-foot)*factor
	var size: Vector2=region.size*factor
	if mirrored: offset.x=-offset.x-size.x
	return Rect2(offset,size)
func draw(canvas: CanvasItem, mirrored: bool = false, flash: float = 0.0) -> void:
	if texture==null: return
	canvas.draw_set_transform(Vector2.ZERO,0,Vector2(-1,1) if mirrored else Vector2.ONE)
	canvas.draw_texture_rect_region(texture,bounds(),region,Color.WHITE.lerp(Color(1.15,1.15,1.15),clampf(flash,0,1)))
	canvas.draw_set_transform(Vector2.ZERO)
