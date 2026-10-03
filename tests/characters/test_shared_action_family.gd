extends SceneTree
## Isolated metadata/texture fixtures exercise identity admission and production
## sampling. They are not game artwork, screenshots or natural-play evidence.
const Shared = preload("res://scripts/presentation/characters/hero_shared_action_family.gd")
const Visual = preload("res://scripts/presentation/characters/hero_visual.gd")

class TailAbilities extends RefCounted:
	var active: Dictionary = {}
	func busy() -> bool: return not active.is_empty()

class TailGunner extends Node2D:
	var abilities := TailAbilities.new()
	var aim_direction := Vector2.LEFT
	var visual_hitstop := 0.0
	var shot_cooldown := .1
	func hero_id() -> String: return "CH02"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(hero: String) -> Dictionary:
	var image := Image.create(1024,1024,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(image)
	var textures: Dictionary = {}
	var directions: Dictionary = {}
	for key: String in Shared.DIRECTIONS:
		var frames: Array = []
		for index: int in Shared.POSES.size():
			var x: int = (index%2)*512
			var y: int = 0 if index%4 < 2 else 512
			var path: String = "asset://heroes/"+hero.to_lower()+"_poses_"+key.to_lower()+"_"+("a" if index < 4 else "b")+".png"
			textures[path] = texture
			frames.append({"name":Shared.POSES[index],"texture":path,"region":[x,y,512,512],"foot":[x+256,y+490],"head":[x+256,y+90],"grip":[x+310,y+250],"muzzle":[x+350+index*8,y+200+index*3],"body_height":200 if index == 6 else 400})
		directions[key] = {"reference_body_height":400,"frames":frames}
	return {"data":{"schema_version":3,"hero_id":hero,"enabled":true,"production_ready":true,"directions":directions},"textures":textures}

func check_admission() -> void:
	var source: Dictionary = fixture("CH03")
	check(not Shared.validate_family(source.data,"CH03",source.textures).is_empty(),"all eight measured views admitted together")
	for error: String in ["disabled","not_ready","wrong_hero","wrong_schema","missing_view","old_twelve_view","wrong_view_key","missing_pose","wrong_pose","mixed_hero","mixed_view","outside","overlap","foot","height","reference","boolean","optional_anchor"]:
		var data: Dictionary = source.data.duplicate(true)
		match error:
			"disabled": data.enabled = false
			"not_ready": data.production_ready = false
			"wrong_hero": data.hero_id = "CH02"
			"wrong_schema": data.schema_version = 2
			"missing_view": data.directions.erase("NW")
			"old_twelve_view": data.directions.ESE = data.directions.SE.duplicate(true)
			"wrong_view_key":
				data.directions.ESE = data.directions.SE.duplicate(true)
				data.directions.erase("SE")
			"missing_pose": data.directions.E.frames.pop_back()
			"wrong_pose": data.directions.E.frames[0].name = "basic_release"
			"mixed_hero": data.directions.E.frames[0].texture = "asset://heroes/ch02_poses_e_a.png"
			"mixed_view": data.directions.E.frames[0].texture = "asset://heroes/ch03_poses_w_a.png"
			"outside": data.directions.E.frames[0].region[2] = 4096
			"overlap": data.directions.E.frames[1].region = data.directions.E.frames[0].region.duplicate()
			"foot": data.directions.E.frames[0].foot = [1024,1024]
			"height": data.directions.E.frames[0].body_height = NAN
			"reference": data.directions.E.reference_body_height = 128
			"boolean": data.enabled = 1
			"optional_anchor": data.directions.E.frames[0].pet = [INF,0]
		check(Shared.validate_family(data,"CH03",source.textures).is_empty(),error+" refuses whole family")

func check_sampling() -> void:
	var previous: Dictionary = Shared._families.duplicate()
	for hero: String in ["CH01","CH02","CH03"]:
		var source: Dictionary = fixture(hero)
		var family: Dictionary = Shared.validate_family(source.data,hero,source.textures)
		Shared._families[hero] = family
		var identities: Dictionary = {}
		for direction_index: int in Shared.DIRECTIONS.size():
			var direction := Vector2.from_angle(direction_index*PI/4.0)
			var key: String = Shared.DIRECTIONS[direction_index]
			for pose_name: String in Shared.POSES:
				var recorded: Dictionary = family.directions[key][pose_name]
				var signature: String = str(recorded.path)+str(recorded.region)
				check(not identities.has(signature),hero+key+pose_name+" independent source region")
				identities[signature] = true
			var idle: Dictionary = Visual.presentation_frame_info(hero,"front",{"phase":"idle","direction":direction},0.0,false)
			check(str(idle.art_family) == "shared_action" and str(idle.direction_key) == key,hero+key+" production idle uses eight-way identity")
			for offset: float in [-PI/8.0+.0001,PI/8.0-.0001]:
				check(Shared.sample_family(family,direction.rotated(offset),"idle",0.0,"idle").direction_key == key,hero+key+" continuous aim quantizes inside actual 45-degree view")
			var left: Dictionary = Visual.presentation_frame_info(hero,"front",{"phase":"idle","direction":direction},3.0,true)
			var right: Dictionary = Visual.presentation_frame_info(hero,"front",{"phase":"idle","direction":direction},12.0,true)
			check(left.frame_name == "walk_left" and right.frame_name == "walk_right",hero+key+" distance drives two genuine walk poses")
			var dash_pose: Dictionary = {"phase":"idle","direction":direction,"dash_progress":.5}
			var dash: Dictionary = Visual.presentation_frame_info(hero,"front",dash_pose,0.0,false,true)
			check(dash.frame_name == "dash" and dash.direction_key == key,hero+key+" dash stays new identity")
			check(is_equal_approx(float(dash.bounds.size.y)/float(dash.region.size.y),112.0/400.0),hero+key+" crouched native height does not enlarge body scale")
			var transform: Transform2D = Visual.body_transform(dash,hero,direction,Vector2.ZERO,dash_pose)
			check(Visual.source_horizontal_flip(direction,dash) == 1.0 and transform.x.is_equal_approx(Vector2.RIGHT) and transform.y.is_equal_approx(Vector2.DOWN) and (transform*Vector2(0,8)).is_equal_approx(Vector2(0,8)),hero+key+" true authored direction has no mirror, rotation or sole drift")
			if hero == "CH02":
				var reload: Dictionary = Visual.presentation_frame_info(hero,"front",{"phase":"idle","direction":direction,"reload_progress":.5},0.0,false)
				check(reload.frame_name == "guard_cast" and reload.direction_key == key,hero+key+" reload uses same new actor")
			for phase: String in ["windup","release","recovery"]:
				var basic: Dictionary = Visual.presentation_frame_info(hero,"front",{"phase":phase,"slot":"basic","direction":direction,"progress":.5},0.0,false)
				check(basic.frame_name == "basic_"+phase and basic.direction_key == key,hero+key+phase+" production basic selects contact phase")
				for skill_index: int in 12:
					var skill_id: String = "%s_SK%02d" % [hero,skill_index+1]
					var pose: Dictionary = {"phase":phase,"skill_id":skill_id,"slot":"skill","direction":direction,"authored_phase_progress":.5}
					var frame: Dictionary = Visual.presentation_frame_info(hero,"front",pose,0.0,false)
					var category: String = str(Shared.SKILL_ACTIONS[hero][skill_index])
					var expected: String = "guard_cast" if category == "guard_cast" and phase == "release" else "dash" if category == "dash" and phase == "release" else "basic_"+phase
					check(frame.frame_name == expected and frame.direction_key == key and frame.art_family == "shared_action",skill_id+key+phase+" category and stable skill identity")
					if phase == "release":
						var expected_muzzle: Vector2 = Visual.body_transform(frame,hero,direction,Vector2.ZERO,pose)*Vector2(frame.anchors.muzzle)
						check(Visual.release_muzzle_local(hero,"skill",direction,skill_id).is_equal_approx(expected_muzzle),skill_id+key+" frozen release anchor follows skill identity")
			var tail: Dictionary = Visual.presentation_frame_info(hero,"front",{"phase":"unknown_tail","skill_id":hero+"_SK99","direction":direction},0.0,false)
			check(tail.frame_name == "idle" and tail.art_family == "shared_action",hero+key+" unknown presentation tail keeps new idle identity")
		check(identities.size() == 64,hero+" complete sixty-four source poses")
		check(Shared.sample_family(family,Vector2.RIGHT,"release",NAN,"basic").is_empty(),hero+" invalid phase time does not sample")
		check(Shared.sample_family(family,Vector2.RIGHT,"release",.5,"CH04_SK01").is_empty(),hero+" cross-class action rejected")
	Shared._families = previous

func check_real_feedback_tail() -> void:
	var previous: Dictionary = Shared._families.duplicate()
	var source: Dictionary = fixture("CH02")
	Shared._families["CH02"] = Shared.validate_family(source.data,"CH02",source.textures)
	var actor := TailGunner.new()
	var feedback: Node2D = load("res://scripts/presentation/characters/hero_feedback.gd").new()
	feedback.name = "HeroFeedback"
	feedback.actor = actor
	actor.add_child(feedback)
	var data: Dictionary = {"hero":"CH02","slot":"skill","skill_id":"CH02_SK03","input_slot":"e","windup":.06,"duration":.42,"effect_kind":"grenade"}
	feedback.cast_started(data,Vector2.LEFT,Vector2.ZERO,41)
	feedback._cast_age = .5
	feedback._shot_age = .4
	var direction := Vector2.DOWN
	feedback.observe_basic("attack_strike",.29,direction)
	var tail: Dictionary = feedback.pose_state()
	check(tail.skill_id == "CH02_SK03" and tail.phase == "recovery","real finished grenade feedback retains skill identity before basic presentation")
	var basic: Dictionary = Visual.gunner_presentation_pose(actor,tail)
	var release: Dictionary = Visual.presentation_frame_info("CH02","front",basic,0.0,false)
	check(basic.skill_id == "" and basic.input_slot == "" and basic.direction == direction and basic.phase == "release","real new basic contact clears finished skill identity and keeps committed aim")
	check(release.frame_name == "basic_release" and release.action == "basic" and release.body_action == "basic","finished guard-category skill cannot select guard body for real basic contact")
	var muzzle: Vector2 = Visual.body_transform(release,"CH02",direction,Vector2.ZERO,basic)*Vector2(release.anchors.muzzle)
	check(muzzle.is_equal_approx(Visual.release_muzzle_local("CH02","basic",direction)),"tail-to-basic body contact matches frozen actual basic muzzle")
	feedback._cast.clear()
	feedback._basic_age = .31
	var held: Dictionary = Visual.gunner_presentation_pose(actor,feedback.pose_state())
	check(held.skill_id == "" and held.input_slot == "" and held.slot == "basic" and held.phase == "recovery" and held.direction == direction,"real basic cooldown hold keeps clean basic identity and aim")
	actor.abilities.active = {"elapsed":.02,"direction":Vector2.LEFT,"next_event":0,"events":[{"time":.06}]}
	feedback.cast_started(data,Vector2.LEFT,Vector2.ZERO,42)
	feedback.observe_basic("attack_strike",.29,direction)
	var busy_pose: Dictionary = feedback.pose_state()
	var unclaimed: Dictionary = Visual.gunner_presentation_pose(actor,busy_pose)
	check(unclaimed == busy_pose and unclaimed.skill_id == "CH02_SK03","a busy committed skill keeps its own pose despite a basic feedback event")
	actor.free()
	Shared._families = previous
func _initialize() -> void:
	# SceneTree -s compiles before autoload identifiers are registered.
	call_deferred("_run")

func _run() -> void:
	check_admission()
	check_sampling()
	check_real_feedback_tail()
	print("SHARED ACTION FAMILY: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
