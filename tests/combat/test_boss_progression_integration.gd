extends SceneTree
## Actual profile/packet seam for the isolated six-chapter candidate. Does not
## spawn a scene, read a player save, or run the frozen natural-play matrix.
const Policy = preload("res://scripts/domain/combat/boss_progression_policy.gd")
const Profiles = preload("res://scripts/domain/combat/boss_profiles.gd")
const Calibration = preload("res://scripts/domain/combat/enemy_calibration.gd")
const Numbers = preload("res://scripts/domain/combat/enemy_numbers.gd")
const B05 = preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
const B06 = preload("res://scripts/levels/b06/combat/enemy_numbers.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func packet(profile: Dictionary, chapter: int, phase: int) -> int:
	if chapter == 5: return B05.skill_damage(profile,100,phase)
	if chapter == 6: return B06.skill_damage(profile,100,phase)
	return int(Numbers.command({"kind":"melee","damage_multiplier":1.0},profile,phase).get("damage",-1))
func _initialize() -> void:
	if not preload("res://scripts/infrastructure/content/runtime_rules.gd").b06_candidate_enabled():
		push_error("Requires isolated --candidate-b06 --test-profile=user://test_b06_candidate/...json")
		quit(2)
		return
	var snapshot := Calibration.archived(13)
	check(Calibration.valid(snapshot) and Calibration.numerical_version(snapshot)==2,"archive13 selects v2")
	var outputs: Array = []
	for chapter: int in range(1,7):
		for difficulty: int in range(5):
			var id := "BO%02d" % chapter
			var current := Profiles.resolve(id,difficulty,2,snapshot)
			var old := Profiles.resolve(id,difficulty,2,{})
			var old_archive := Profiles.resolve(id,difficulty,2,Calibration.archived(1))
			check(not current.is_empty() and not old.is_empty(),"live profile exists "+id)
			if current.is_empty() or old.is_empty(): continue
			var golden := Policy.stats(chapter,difficulty,2)
			var old_golden := Policy.stats(chapter,difficulty,1)
			for key: String in Policy.FIELDS:
				check(current[key] == golden[key],"production v2 exact "+id+":"+str(difficulty)+":"+key)
				check(old[key] == old_golden[key] and old_archive[key] == old_golden[key],"old snapshots replay "+id+":"+key)
			check(int(current.get("boss_progression_version",0))==2,"policy version marked")
			check(int(old.get("boss_progression_version",1))==1,"old replay not upgraded")
			for key: String in ["phase_thresholds","reinforcement_waves","reinforcement_cap","reinforcement_budget","reserved_summon_count","navigation_radius","move_speed","recovery_seconds","behavior_id","damage_type"]:
				check(current.get(key)==old.get(key),"mechanical field preserved "+key)
			var packets: Array = []
			for phase: int in range(1,4):
				var amount := packet(current,chapter,phase)
				packets.append(amount)
				check(amount>0,"current profile admitted to actual skill damage")
				check(packet(old,chapter,phase)>0,"old profile admitted to actual skill damage")
				if phase>1: check(amount>int(packets[phase-2]),"actual phase packet increases")
				if difficulty>0: check(amount>packet(Profiles.resolve(id,difficulty-1,2,snapshot),chapter,phase),"actual difficulty packet increases")
				if chapter>1: check(amount>packet(Profiles.resolve("BO%02d"%(chapter-1),difficulty,2,snapshot),chapter-1,phase),"actual chapter packet increases")
			outputs.append({"id":id,"difficulty":difficulty,"stats":golden,"phase_packets":packets})
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--boss-integration-output="): output=arg.trim_prefix("--boss-integration-output=")
	if not output.is_empty():
		var f := FileAccess.open(AssetCatalog.resolve(output),FileAccess.WRITE)
		f.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":outputs},"\t"))
	print("Boss progression integration: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
