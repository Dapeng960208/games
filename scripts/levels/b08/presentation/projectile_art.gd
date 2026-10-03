extends RefCounted
## Frozen bow cue only. The feather and ground marker retain the real hit position.
const LAUNCH_DISTANCE:=320.0*.14
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
func attach_launch(actor: Node2D, shot: Dictionary) -> void:
	if texture==null or actor.enemy_id!="B08-M01" or actor.native_art==null or not actor.native_art.convergence: return
	var origin: Vector2=shot.position
	var outlet: Vector2=origin+actor.native_art.release_outlet(actor.aim_direction.x<-.1)
	# The close-range threat must never be displaced toward the drawn bow. Only
	# a brief source cue connects the frozen outlet to the unchanged projectile.
	if actor.room.blocked_fraction(origin,outlet,3)<.999: return
	shot["visual_launch"]={"outlet":outlet,"remaining":float(shot.remaining)}
func launch_strength(shot: Dictionary) -> float:
	var launch: Dictionary=shot.get("visual_launch",{})
	if launch.is_empty(): return 0.0
	return clampf(1.0-(float(launch.remaining)-float(shot.remaining))/LAUNCH_DISTANCE,0.0,1.0)
func draw(canvas: CanvasItem, shot: Dictionary) -> bool:
	if texture==null or shot.packet.get("enemy_id","")!="B08-M01": return false
	var strength:=launch_strength(shot)
	if strength>0:
		var outlet: Vector2=shot.visual_launch.outlet
		if canvas.blocked_fraction(outlet,shot.position,3)>=.999:
			canvas.draw_line(outlet,shot.position,Color("527f9d",strength*.55),1.25,true)
			canvas.draw_circle(outlet,3.0,Color("fff2c2",strength*.9))
	# Keep this ground marker in reduced FX as well. It is a contact cue, not an
	# expanded collision radius; the native feather stays at the same position.
	var direction: Vector2=shot.direction
	canvas.draw_line(shot.position-direction*8,shot.position+direction*4,Color("29485a"),4,true)
	canvas.draw_line(shot.position-direction*7,shot.position+direction*3,Color("fff2c2"),1.5,true)
	canvas.draw_set_transform(shot.position,direction.angle())
	canvas.draw_texture_rect_region(texture,bounds(),region)
	canvas.draw_set_transform(Vector2.ZERO)
	return true
