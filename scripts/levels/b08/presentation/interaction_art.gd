extends Node2D
## Read-only L43 skins. Wind, flag health and room availability stay in gameplay.
const ROOT := "asset://b08/rooms/l43/props/"
const Prop=preload("res://scripts/levels/b08/presentation/interaction_prop.gd")
var room: Node2D
var frames: Dictionary={}
var textures: Dictionary={}
var flag_owner: WeakRef
var flag_broken:=false
var flag_body: Node2D
var vane_body: Node2D
var lane: Dictionary={}
var errors: Array[String]=[]
func configure(owner_room: Node2D, flag: Node2D) -> bool:
	if owner_room.layout_id!="L43" or not OS.get_cmdline_user_args().has("--b08-art-convergence"): return false
	room=owner_room
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT+"manifest.json")))
	if not data is Dictionary: return false
	frames=data.frames
	for kind: String in frames:
		textures[kind]=preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(ROOT+str(frames[kind].file))
		if textures[kind]==null: errors.append("Missing interaction texture: "+kind)
	if not errors.is_empty(): return false
	y_sort_enabled=true
	z_index=2
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lane=preload("res://scripts/levels/b08/geometry.gd").lanes("L43")[0]
	flag_owner=weakref(flag)
	vane_body=_body("vane",lane.vane,bounds("vane_base").grow(18))
	flag_body=_body("flag",flag.position,bounds("flag_intact"))
	return true
func _body(kind: String, at: Vector2, visual: Rect2) -> Node2D:
	var body:=Prop.new()
	body.source=self; body.kind=kind
	add_child(body)
	body.configure(room,{"foot":at,"occludes":true,"visual_bounds":Rect2(at+visual.position,visual.size)})
	body.set_physics_process(false) # Parent supplies the same gameplay delta once.
	return body
func bounds(kind: String) -> Rect2:
	var frame: Dictionary=frames[kind]
	var scale_value:=float(frame.world_per_source_pixel)
	return Rect2(-Vector2(frame.anchor[0],frame.anchor[1])*scale_value,Vector2(frame.native_size[0],frame.native_size[1])*scale_value)
func sync(delta: float) -> void:
	var flag: Node2D=flag_owner.get_ref()
	flag_broken=not is_instance_valid(flag) or not flag.is_alive()
	flag_body.local_visual_bounds=bounds("flag_broken" if flag_broken else "flag_intact")
	flag_body.occludes=not flag_broken
	if flag_broken: flag_body.modulate.a=1
	else: flag_body._physics_process(delta)
	vane_body._physics_process(delta)
	flag_body.queue_redraw(); vane_body.queue_redraw()
func pointer_kind() -> String:
	return "vane_pointer_up" if absf(room.wind.direction(lane.id,lane.direction).y)>.5 else "vane_pointer"
func draw_body(canvas: CanvasItem, kind: String) -> void:
	if kind=="flag":
		_draw_native(canvas,"flag_broken" if flag_broken else "flag_intact")
		return
	_draw_native(canvas,"vane_base")
	var base: Dictionary=frames.vane_base
	var socket: Vector2=(Vector2(base.socket_pixel[0],base.socket_pixel[1])-Vector2(base.anchor[0],base.anchor[1]))*float(base.world_per_source_pixel)
	var direction: Vector2=room.wind.direction(lane.id,lane.direction)
	var pointer:=pointer_kind()
	if textures.has(pointer):
		canvas.draw_set_transform(socket,0,Vector2(-1,1) if direction.x<-.5 else Vector2.ONE)
		_draw_native(canvas,pointer)
		canvas.draw_set_transform(Vector2.ZERO)
func _draw_native(canvas: CanvasItem, kind: String, tint: Color=Color.WHITE) -> void:
	canvas.draw_texture_rect(textures[kind],bounds(kind),false,tint)
func draw_floor(canvas: CanvasItem) -> void:
	var ready: bool=room.exit_ready()
	canvas.draw_set_transform(room.exit_position)
	_draw_native(canvas,"exit_waymark",Color.WHITE if ready else Color(.65,.69,.73,.72))
	canvas.draw_arc(Vector2.ZERO,54,0,TAU,48,Color("43857c") if ready else Color("59677c"),2,true)
	canvas.draw_set_transform(Vector2.ZERO)
	_label(canvas,room.exit_position+Vector2(-47,46),"F 前往下一区域" if ready else "清剿后通行")
	var direction: Vector2=room.wind.direction(lane.id,lane.direction)
	# Small ground arrow makes all real directions readable, including reduced FX.
	var at: Vector2=lane.vane+Vector2(0,15)
	canvas.draw_line(at-direction*16,at+direction*16,Color("355b74"),2.5,true)
	canvas.draw_polyline(PackedVector2Array([at+direction*8+direction.orthogonal()*5,at+direction*16,at+direction*8-direction.orthogonal()*5]),Color("355b74"),2.5,true)
	var label:="F 调整风向"
	if room.wind.channel.get("lane","")==lane.id:
		label="调整中"
		canvas.draw_arc(lane.vane,26,-PI*.5,-PI*.5+TAU*(1-float(room.wind.channel.remaining)/room.wind.CHANNEL),32,Color("d5a245"),3,true)
	elif room.wind.pending.get("lane","")==lane.id:
		label="风向即将切换"
		canvas.draw_arc(lane.vane,26,0,TAU,40,Color("ed7d44"),3,true)
	_label(canvas,lane.vane+Vector2(-38,42),label)
	if flag_broken and room.wind.now<room.wind.suppressed_until:
		canvas.draw_arc(flag_body.position,25,0,TAU,32,Color("5893a3"),2,true)
		_label(canvas,flag_body.position+Vector2(-43,35),"顺风抑制 %.1f秒"%maxf(0,room.wind.suppressed_until-room.wind.now))
func _label(canvas: CanvasItem, at: Vector2, text: String) -> void:
	canvas.draw_string_outline(room.fx_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,3,Color("edf3f5"))
	canvas.draw_string(room.fx_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("273949"))
