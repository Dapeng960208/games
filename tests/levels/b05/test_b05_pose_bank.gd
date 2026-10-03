extends SceneTree
## Source metadata and real EnemyVisual transform checks; no screenshot or GPU
## acceptance claim. Run in the same isolated no-autoload B05 test project.
const Art=preload("res://scripts/levels/b05/art/enemy_art.gd")
const Visual=preload("res://scripts/presentation/monsters/enemy_visual.gd")
const Skills=preload("res://scripts/levels/b05/combat/enemy_skills.gd")
class Body extends Node2D:
	var enemy_id:="B05-M01"
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
	if not value: failures+=1; push_error("B05 POSE: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var textures: Array=[]
	for id: String in Art.IDS:
		var bank:=Art.bank(id)
		check(not bank.is_empty() and bank.b05_native_bank,"separate native bank "+id)
		var manifest_path: String=str(bank.clips.idle[0].texture_path).get_base_dir()+"/manifest.json"
		var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(manifest_path)))
		check(bank.runtime_quality_gate_passed==bool(manifest.identities[id].get("runtime_quality_gate_passed",manifest.get("runtime_quality_gate_passed",false))),"metadata test forwards only independently granted visual gate")
		var room=Room.new(); root.add_child(room); room.process_mode=Node.PROCESS_MODE_DISABLED
		var actor=Body.new(); actor.enemy_id=id; actor.profile=Skills.profile(id,21,4); actor.navigation_radius=float(actor.profile.navigation_radius); actor.room=room; room.enemies.add_child(actor)
		var body=Visual.new(); actor.add_child(body); body.configure(actor)
		var reference_factor:=float(body._bank.world_reference_height)/float(bank.body_height)
		check(is_equal_approx(float(body._bank.world_reference_height),clampf(actor.navigation_radius*3.8,66.0,88.0)*1.2),"one anatomy scale not doubled")
		check(body._foot==Vector2(0,18),"registered foot remains18")
		for pose: String in ["idle","telegraph","execute"]:
			var source: Dictionary=bank.clips[pose][0] if pose!="telegraph" or id!="B05-M04" else bank.clips.telegraph[0]
			body.selected_frame=source
			var frame: Dictionary=body.body_frame()
			check(frame.texture.get_size()==Vector2(1254,1254),"native1254 unchanged")
			check(frame.texture==source.texture,"per-frame texture source")
			textures.append(frame.texture.get_instance_id())
			check(is_equal_approx(float(frame.bounds.size.y)/1254,reference_factor),"same fixed pixels/world all poses")
			check((Vector2(frame.bounds.position)+Vector2(source.foot)*reference_factor).is_zero_approx(),"each absolute foot maps to localzero")
			for facing: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
				actor.aim_direction=facing; body._update_pose(0)
				var actor_bounds: Rect2=body.transform*Rect2(frame.bounds)
				var card: Rect2=Rect2(body.skill_badge.position+body.skill_badge.detail_origin(),Vector2(254,61))
				check(card.end.y<=actor_bounds.position.y,"native body/organ canvas stays below optional detail card")
				var actual: Dictionary=body.b05_visual_outlet()
				var expected: Vector2=room.to_local(body.to_global((Vector2(source.outlet)-Vector2(source.foot))*reference_factor))
				check(Vector2(actual.position).is_equal_approx(expected),"sameframe mirrored outlet "+id+pose)
				check(actual.texture_path==source.texture_path,"outlet texture evidence")
				var all_outlets: Array[Dictionary]=body.b05_visual_outlets()
				check(all_outlets.size()==source.outlets.size(),"every authored organ has a room-space endpoint")
				for index: int in all_outlets.size():
					var point: Vector2=room.to_local(body.to_global((Vector2(source.outlets[index])-Vector2(source.foot))*reference_factor))
					check(Vector2(all_outlets[index].position).is_equal_approx(point),"multi-organ source and mirror correspondence")
		actor.state=&"locked"; body._read_phase(0); body._select_frame()
		check(body.selected_frame.name==("execute" if id=="B05-M04" else "telegraph"),"lock keeps actual tell/channel pose")
		actor.state=&"execute"; body._read_phase(0); body._select_frame()
		check(body.selected_frame.name=="execute","release pose")
		actor.state=&"recovery"; body._read_phase(0); body._select_frame()
		check(body.selected_frame.name=="idle","declared idle recovery fallback")
		for cycle: int in range(3):
			for state: StringName in [&"chase",&"telegraph",&"locked",&"execute",&"recovery"]:
				actor.state=state; body._read_phase(0); body._select_frame()
				var expected_pose: String="execute" if state==&"execute" or (id=="B05-M04" and state==&"locked") else "telegraph" if state in [&"telegraph",&"locked"] else "idle"
				check(body.selected_frame.name==expected_pose,"repeated state selects same native pose")
			var snapshot: Dictionary=body.selected_frame.duplicate()
			var clock_before: float=body._clock
			paused=true; body.advance(.1)
			check(body.selected_frame==snapshot and is_equal_approx(body._clock,clock_before),"pause freezes pose and render clock")
			paused=false
		room.free()
	var unique: Dictionary={}
	for id in textures: unique[id]=true
	check(textures.size()==Art.IDS.size()*3 and unique.size()==Art.IDS.size()*3,"three independent textures per registered identity")
	check(Art.bank("M01").is_empty() and Art.bank("B05-M99").is_empty(),"unregistered IDs cannot borrow an identity")
	print("B05 pose bank: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
