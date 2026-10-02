extends SceneTree
const Atlas = preload("res://scripts/combat/hero_directional_atlas.gd")
const Visual = preload("res://scripts/combat/hero_visual.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func _initialize() -> void:
	var heroes: Array[String] = ["CH01","CH02","CH03"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--directional-heroes="): heroes.assign(argument.trim_prefix("--directional-heroes=").split(",",false))
	for hero: String in heroes:
		var family: Dictionary=Atlas.load_family(hero)
		check(family.size()==8,hero+" complete approved eight-direction family")
		if family.is_empty(): continue
		var identities := {}
		for index: int in 8:
			var direction:=Vector2.from_angle(index*PI/4)
			var key: String=Atlas.DIRECTIONS[index]
			check(Atlas.direction_key(direction)==key,hero+key+" quantization")
			for phase: String in Atlas.PHASES:
				var frame: Dictionary=Atlas.frame_info(hero,direction,phase,.5)
				check(not frame.is_empty() and str(frame.direction_key)==key,hero+key+phase+" actual source direction")
				if frame.is_empty(): continue
				var signature: String=str(frame.path)+str(frame.region)
				check(not identities.has(signature),hero+key+phase+" independent authored pixels")
				identities[signature]=true
				check(frame.source_body_height>=320,hero+key+phase+" measured native density")
				check(Visual.source_horizontal_flip(direction,frame)==1.0,hero+key+phase+" no fake directional mirroring")
				var pose: Dictionary={"direction":direction,"slot":"basic","phase":phase,"progress":.5}
				var sampled: Dictionary=Visual.presentation_frame_info(hero,"back" if direction.y<-.2 else "front",pose,0,false)
				check(sampled.path==frame.path and sampled.region==frame.region,hero+key+phase+" production sampler selects same pixels")
				var transform:=Visual.body_transform(frame,hero,direction,Vector2.ZERO,pose)
				check((transform*Vector2(0,8)).distance_to(Vector2(0,8))<.01,hero+key+phase+" stable ground foot")
				if phase=="release":
					var muzzle:=Visual.release_muzzle_local(hero,"basic",direction)
					check(muzzle.distance_to(transform*Vector2(frame.anchors.muzzle))<.01,hero+key+" body and frozen launch use one anchor")
					if hero!="CH01": check(Vector2(frame.weapon_axis).normalized().dot(direction)>=.95,hero+key+" observed weapon axis agrees")
		check(identities.size()==24,hero+"24distinctdirectionalposes")
	print("HERO DIRECTIONAL ATLAS: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
