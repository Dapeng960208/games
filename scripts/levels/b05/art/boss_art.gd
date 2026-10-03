extends "res://scripts/presentation/monsters/enemy_visual.gd"
const TextureSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
## BO05-only native full-canvas pose renderer. No per-pose auto-fit or cropping.
## Anchors are source-pixel registrations, not collision or damage origins.
const ROOT := "asset://bosses/b05_poses_v1/"
const TextureSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const REFERENCE_HEIGHT := 1226.0
const WORLD_HEIGHT := 220.0
const WORLD_FOOT := Vector2(0,36)
const EXECUTE_SECONDS := 0.22
static var _frames: Dictionary = {}
var pose_name := "idle"
var _release_pose := "idle"
var _release_remaining := 0.0

static func family(action: String) -> String:
	if action == "crown_sweep": return "sweep"
	if action == "three_roots": return "root"
	return "cast"

static func frames() -> Dictionary:
	if not _frames.is_empty(): return _frames
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT+"runtime_manifest.json")))
	if not raw is Dictionary: return {}
	for spec: Dictionary in raw.get("poses",[]):
		var path: String=ROOT+str(spec.file)
		var texture: Texture2D=TextureSampler.sampled(path)
		if texture==null: continue
		var outlets: Array[Vector2]=[]
		if spec.absolute_outlets_px is Array:
			for point: Array in spec.absolute_outlets_px: outlets.append(Vector2(point[0],point[1]))
		_frames[str(spec.state)]={"texture":texture,"path":path,"foot":Vector2(spec.absolute_foot_px[0],spec.absolute_foot_px[1]),"core":Vector2(spec.absolute_core_px[0],spec.absolute_core_px[1]),"outlets":outlets,"head":Vector2(spec.absolute_head_px[0],spec.absolute_head_px[1]),"anatomy_height":float(spec.reference_anatomy_height_px),"solid_margin_passed":bool(spec.get("solid_margin_gate_passed",false))}
	return _frames

func configure(enemy: Node2D) -> void:
	pose_name="idle"
	_release_remaining=0
	frames()
	super.configure(enemy)
	_foot=WORLD_FOOT
	_bank={}
	_body_material.set_shader_parameter("preserve_source_color",true)
	for frame: Dictionary in _frames.values(): _prepare_contact_mask(frame.texture)
	apply_pose("idle")
	_update_pose(0)

func release(action: String) -> void:
	_release_pose=family(action)+"-execute"
	_release_remaining=EXECUTE_SECONDS
	apply_pose(_release_pose)

func advance(delta: float) -> void:
	if delta<=0 or (is_inside_tree() and get_tree().paused): return
	var brain_state: String=str(actor.boss_brain.state) if actor.boss_brain!=null else str(actor.state)
	if brain_state in ["emerging","phase_shift","dead"]:
		_release_remaining=0
	_release_remaining=maxf(0,_release_remaining-delta)
	var desired: String="idle"
	if _release_remaining>0: desired=_release_pose
	elif brain_state in ["windup","telegraph","locked"]:
		desired=family(str(actor.boss_brain.current_action))+"-windup"
	apply_pose(desired)
	super.advance(delta)

func apply_pose(value: String) -> void:
	if not _frames.has(value): value="idle"
	if not _frames.has(value): return
	pose_name=value
	var frame: Dictionary=body_frame()
	actor.body_texture=frame.texture
	actor.body_region=frame.region
	# A stable UI envelope stops the health/name bars jumping with pose changes.
	actor.body_bounds=Rect2(Vector2(-126,-178),Vector2(252,226))
	actor.set("_boss_art_path",_frames[value].path)
	queue_redraw()

func body_frame() -> Dictionary:
	if not _frames.has(pose_name): return super.body_frame()
	var frame: Dictionary=_frames[pose_name]
	var factor: float=WORLD_HEIGHT/float(frame.anatomy_height)
	var region:=Rect2(Vector2.ZERO,frame.texture.get_size())
	return {"texture":frame.texture,"region":region,"bounds":Rect2(-Vector2(frame.foot)*factor,region.size*factor),"name":pose_name,"source_family":"storybook_2_5d_v1","full_color":true}

func visual_landmarks() -> Dictionary:
	if not _frames.has(pose_name): return {}
	var frame: Dictionary=_frames[pose_name]
	var factor: float=WORLD_HEIGHT/float(frame.anatomy_height)
	var outlet_points: Array[Vector2]=[]
	for point: Vector2 in frame.outlets: outlet_points.append(to_global((point-Vector2(frame.foot))*factor))
	return {"pose":pose_name,"foot_global":to_global(Vector2.ZERO),"core_global":to_global((Vector2(frame.core)-Vector2(frame.foot))*factor),"outlets_global":outlet_points,"source_scale":factor,"head_global":to_global((Vector2(frame.head)-Vector2(frame.foot))*factor),"solid_margin_passed":frame.solid_margin_passed,"source_gate_passed":false}

func _draw() -> void:
	super._draw()
	if not is_instance_valid(actor) or actor.boss_brain==null or not actor.boss_brain.weakpoint_open() or not _frames.has(pose_name): return
	# Draw after the body, on the same canvas, so the actual flower remains
	# readable and the exposed-core ring follows mirror, sway and impact recoil.
	var frame: Dictionary=_frames[pose_name]
	var core: Vector2=(Vector2(frame.core)-Vector2(frame.foot))*WORLD_HEIGHT/float(frame.anatomy_height)
	draw_arc(core,11.0,-PI*.5,PI*1.5,32,Color("bfe8a7"),2.0,true)
