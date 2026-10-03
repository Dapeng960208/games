extends SceneTree
## Source metadata and real EnemyVisual transform checks; no screenshot or GPU
## acceptance claim. Run in the same isolated no-autoload B06 test project.
const Art=preload("res://scripts/combat/b06_native_art.gd")
const Visual=preload("res://scripts/combat/enemy_visual.gd")
const Skills=preload("res://scripts/combat/b06_enemy_skills.gd")
class Body extends Node2D:
	var enemy_id:="B06-M01"
	var static_actor:=false
	var profile: Dictionary={}
	var body_texture: Texture2D
	var empty_body_texture: Texture2D
	var body_bounds:=Rect2(-43,-48,86,86)
	var body_region:=Rect2()
	var room: Node2D
	var state: StringName=&"chase"
	var state_time:=1.0
	var aim_direction:=Vector2.RIGHT
	var knockback:=Vector2.ZERO
	var move_speed:=70.0
	var navigation_radius:=18.0
	var reaction_remaining:=0.0
	var brain: RefCounted
	func is_alive() -> bool: return true
class Room extends Node2D:
	var player: Node2D
	var enemies=Node2D.new()
	func _init() -> void: add_child(enemies)
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B06 POSE: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var textures: Array=[]
	var ordinary: Array = Art.identities().filter(func(id: String) -> bool: return id.begins_with("B06-M"))
	for id: String in ordinary:
		var bank:=Art.bank(id)
		check(not bank.is_empty() and bank.b06_native_bank,"separate native bank "+id)
		check(bank.runtime_quality_gate_passed==bool(JSON.parse_string(FileAccess.get_file_as_string(Art.ROOT+"manifest.json")).get("runtime_quality_gate_passed",false)),"metadata test only forwards visual gate")
		var room=Room.new(); root.add_child(room); room.process_mode=Node.PROCESS_MODE_DISABLED
		var actor=Body.new(); actor.enemy_id=id; actor.profile=Skills.profile(id,21,4); actor.room=room; room.enemies.add_child(actor)
		var body=Visual.new(); actor.add_child(body); body.configure(actor)
		var reference_factor:=float(body._bank.world_reference_height)/float(bank.body_height)
		check(is_equal_approx(float(body._bank.world_reference_height),18*3.8*1.2),"one anatomy scale not doubled")
		check(body._foot==Vector2(0,18),"registered foot remains18")
		for pose: String in ["idle","telegraph","execute"]:
			var source: Dictionary=bank.clips[pose][0] 
			var pose_factor: float = reference_factor * float(source.get("source_pose_scale",1.0))
			body.selected_frame=source
			var frame: Dictionary=body.body_frame()
			check(frame.texture.get_size()==Vector2(1254,1254),"native1254 unchanged")
			check(frame.texture==source.texture,"per-frame texture source")
			textures.append(frame.texture.get_instance_id())
			check(is_equal_approx(float(frame.bounds.size.y)/1254,pose_factor),"fixed world identity with declared anatomy correction")
			check((Vector2(frame.bounds.position)+Vector2(source.foot)*pose_factor).is_zero_approx(),"each absolute foot maps to localzero")
			for facing: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
				actor.aim_direction=facing; body._update_pose(0)
				var actual: Dictionary=body.b06_visual_outlet()
				var expected: Vector2=room.to_local(body.to_global((Vector2(source.outlet)-Vector2(source.foot))*pose_factor))
				check(Vector2(actual.position).is_equal_approx(expected),"sameframe mirrored outlet "+id+pose)
				check(actual.texture_path==source.texture_path,"outlet texture evidence")
		actor.state=&"locked"; body._read_phase(0); body._select_frame()
		check(body.selected_frame.name=="telegraph","lock keeps actual tell/channel pose")
		actor.state=&"execute"; body._read_phase(0); body._select_frame()
		check(body.selected_frame.name=="execute","release pose")
		actor.state=&"recovery"; body._read_phase(0); body._select_frame()
		check(body.selected_frame.name=="idle","declared idle recovery fallback")
		var frozen_frame: String = str(body.selected_frame.texture_path)
		var frozen_transform: Transform2D = body.transform
		paused = true
		body.advance(0.1)
		check(str(body.selected_frame.texture_path)==frozen_frame and body.transform==frozen_transform,"pause preserves pose and transform")
		paused = false
		var portrait: Dictionary = Art.entry(id)
		check(Rect2(Vector2.ZERO,Vector2(1254,1254)).encloses(portrait.region),"codex region stays inside native source")
		check(portrait.region.size.x < 1254 and portrait.region.size.y < 1254,"codex bounds exclude blank canvas")
		room.free()
	var unique: Dictionary={}
	for id in textures: unique[id]=true
	check(textures.size()==ordinary.size()*3 and unique.size()==ordinary.size()*3,"independent native texture for each identity pose")
	check(Art.bank("M01").is_empty() and Art.bank("B05-M01").is_empty(),"chapter identity isolation")
	for action: String in ["siege_claw","return_pincer","dual_cannon","shell_bombard","tidal_wall","coral_escort"]:
		for stage: String in ["telegraph","locked","release","recovery"]:
			var value: Dictionary = Art.boss_frame(action,stage)
			var expected: String = "idle" if stage=="recovery" or action=="coral_escort" else ("melee" if action in ["siege_claw","return_pincer"] else "cannon")+("-execute" if stage=="release" else "-telegraph")
			check(value.name==expected,"exact Boss dispatch "+action+stage)
			for mirror: bool in [false,true]:
				var mapped: Dictionary = Art.placement(value,Vector2(200,300),220,mirror)
				check(is_equal_approx(mapped.scale,220.0/900.0),"fixed Boss anatomy scale")
				check(mapped.ground==Vector2(200,300),"stable support pivot")
	check(Art.boss_frame("dual_cannon","release",true).name=="exposed","exposure override")
	check(Art.boss_frame("siege_claw","release",true,true).name=="defeated","defeat priority")
	for id: String in ["drain_gate","reef_pillar","tide_clock"]:
		check(not Art.prop_frame(id).is_empty(),"separate prop "+id)
	for spec: Dictionary in Art.manifest().rooms.values():
		check(not spec.geometry_alignment_verified and not spec.runtime_ready,"floor remains source candidate")
	print("B06 pose bank: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
