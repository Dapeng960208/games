extends SceneTree
const Admission=preload("res://scripts/world/b05_hazard_admission.gd")
const Geometry=preload("res://scripts/world/b05_room_geometry.gd")
const Skills=preload("res://scripts/combat/b05_enemy_skills.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error("B05 ADMISSION: "+label)
func _initialize() -> void: call_deferred("run")
func circle(at: Vector2,radius: float,persistent: bool=false) -> Dictionary:
	return {"kind":"ground_area","shape":"circle","origin":at,"target":at,"direction":Vector2.RIGHT,"radius":radius,"coefficient":100,"duration":2.0 if persistent else 0.0,"followups":[]}
func run() -> void:
	for id: String in ["L25","L26","L27","L28","L29","L30","BO05"]:
		var host=Admission.new();check(host.configure(id),id+" configured")
		var route:=Geometry.route(id,"main_route")
		var point: Vector2=route[1]
		var instant:=host.admit(circle(point,20),id+":instant",false)
		check(instant.b05_admitted,id+" instantaneous attack may cross main route")
		check(not host.admit(circle(point,20,true),id+":persistent",false).b05_admitted,id+" lingering hazard cannot cut main route")
		var controlled:=circle(point,20);controlled.coefficient=0;controlled["status"]={"id":"root","duration":.6}
		check(not host.admit(controlled,id+":control",false).b05_admitted,id+" zero-damage control also protects route")
		var whole:=circle(point+Vector2(180,0),10);whole.followups=[circle(point,20,true)]
		check(not host.admit(whole,id+":whole",false).b05_admitted,id+" delayed child admitted with whole command")
		var variant:=host.admit(circle(point,20,true),id+":reposition",true)
		check(not variant.b05_admitted or host._allowed(Admission.describe(variant),id+":reposition"),id+" repositioned whole geometry satisfies routes")
	var host=Admission.new();check(host.configure("L25"),"budget fixture")
	var center:=Geometry.world_point([1400,900])
	var radius:=sqrt(host.effective_area*.20/PI)
	check(host.admit(circle(center,radius),"a",false).b05_admitted,"twenty-percent original admitted")
	check(not host.admit(circle(center,radius),"b",false).b05_admitted,"overlapping second still conservatively exceeds30percent")
	check(host.admit(circle(center,radius),"a",false).b05_admitted,"retarget same cast does not double-reserve")
	host.cancel("a")
	check(host.admit(circle(center,radius),"b",false).b05_admitted,"explicit cancellation frees reservation")
	host.advance(100)
	check(not host.admitted("b"),"finite lease expires")
	var follow:=circle(center,10);follow.followups=[circle(center+Vector2(10,0),10)];follow.followups[0]["delay"]=3
	check(host.admit(follow,"delayed",false).b05_admitted,"delayed whole command admitted")
	host.advance(2)
	check(host.admitted("delayed"),"lease retains delayed geometry after initial release")
	var original:=circle(center,20);original.followups=[circle(center+Vector2(100,0),20)]
	var rotated:=Admission._transform(original,center,PI*.5,Vector2(60,0))
	check(Vector2(rotated.followups[0].target).is_equal_approx(Vector2(rotated.target)+Vector2(0,100)),"whole child rotation and translation coherent")
	check(original.followups[0].target==center+Vector2(100,0),"original command not mutated")
	var charge:=Skills.active(Skills.profile("B05-M03",25,4),Geometry.world_point([320,900]),Geometry.world_point([1000,900]),true)
	var footprints:=Admission.describe(charge)
	var persistent_count:=0
	for footprint: Dictionary in footprints:
		if footprint.persistent: persistent_count+=1
	check(persistent_count>0,"deterministic post-motion moss trail included")
	check(not host.admit(charge,"moss",false).b05_admitted,"future trail crossing frozen route rejected")
	var shell_command:=Skills.active(Skills.profile("B05-M16",25,4),center,center+Vector2(160,0),true)
	var shell_footprints:=Admission.describe(shell_command)
	var possible_shell_paths:=0
	for footprint: Dictionary in shell_footprints:
		if footprint.persistent: possible_shell_paths+=1
	check(possible_shell_paths==2,"both outer-shell landing corridors covered before release")
	var invalid:=circle(Vector2(INF,0),20)
	check(not host.admit(invalid,"invalid",false).b05_admitted,"nonfinite geometry rejected")
	for id in range(1,19):
		for difficulty in [0,2,4]:
			var command:=Skills.active(Skills.profile("B05-M%02d"%id,25,difficulty),center,center+Vector2(160,0),true)
			var shapes:=Admission.describe(command)
			check(not shapes.is_empty() or not Admission._harmful(command),"all current ordinary skill footprints modeled")
	for action: String in Skills.BOSS_ACTIONS:
		var command:=Skills.boss_action(Skills.boss_profile(4),action,center,center+Vector2(100,0),3,[center+Vector2(200,0)])
		check(not Admission.describe(command).is_empty() or not Admission._harmful(command),"boss footprint modeled")
	print("B05_HAZARD_ADMISSION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
