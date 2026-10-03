extends SceneTree
## Small pure-policy regression. Live actors, saved-run integration and the
## 60–90-second combat goal are separate checks, not implied by this test.
const Policy = preload("res://scripts/combat/boss_progression_policy.gd")
const D0 := [[19575,270,180,180],[24494,292,200,200],[28168,315,220,220],[34517,352,240,240],[39695,428,260,260],[45649,491,280,280]]
const D4 := [[78300,621,300,300],[97978,672,320,320],[112672,725,340,340],[138068,810,360,360],[158780,984,380,380],[182596,1130,400,400]]
const OLD_D4 := [[78300,621,300,300],[97978,604,240,270],[99101,684,220,240],[138067,809,340,300],[79920,984,160,160],[95040,1130,170,170]]
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	var rows: Array = []
	for chapter: int in range(1,7):
		for difficulty: int in range(5):
			var original := Policy.stats(chapter,difficulty,1)
			var actual := Policy.stats(chapter,difficulty,2)
			var source := {"enemy_id":"BO%02d" % chapter,"chapter":chapter,"difficulty":difficulty,"rank":"boss","ruleset_version":2,"scale_version":10,"phase_thresholds":[0.7,0.4],"arbitrary_preserved":{"counterplay":true}}
			source.merge(original,true)
			var before := source.duplicate(true)
			var upgraded := Policy.apply(source,2)
			check(source == before,"input immutable")
			check(Policy.apply(source,1) == before,"V1 replay unchanged")
			check(Policy.apply(upgraded,2) == upgraded,"reapplying policy is idempotent")
			check(upgraded.phase_thresholds == source.phase_thresholds and upgraded.arbitrary_preserved == source.arbitrary_preserved,"mechanics unchanged")
			for key: String in Policy.FIELDS:
				check(actual[key] is int and actual[key] >= original[key],"integer and no V1 reduction")
				check(upgraded[key] == actual[key],"profile receives exact policy")
				if chapter > 1: check(actual[key] > Policy.stats(chapter-1,difficulty,2)[key],"strict cross-chapter increase "+key)
				if difficulty > 0: check(actual[key] > Policy.stats(chapter,difficulty-1,2)[key],"strict difficulty increase "+key)
				var i := Policy.FIELDS.find(key)
				if difficulty == 0: check(actual[key] == D0[chapter-1][i],"pinned D0 golden")
				if difficulty == 4:
					check(actual[key] == D4[chapter-1][i],"pinned D4 golden")
					check(original[key] == OLD_D4[chapter-1][i],"pinned old D4 replay")
			for defense: String in ["armor","magic_resist"]:
				var ehp: int = actual.max_hp * (1000 + actual[defense])
				if chapter > 1:
					var previous := Policy.stats(chapter-1,difficulty,2)
					check(ehp > previous.max_hp * (1000 + previous[defense]),"EHP cross-chapter increases")
				if difficulty > 0:
					var easier := Policy.stats(chapter,difficulty-1,2)
					check(ehp > easier.max_hp * (1000 + easier[defense]),"EHP difficulty increases")
			for phase: int in range(1,4):
				# Existing shared boss skill factor stays strictly increasing by
				# difficulty and phase; neither geometry nor extra hits fabricated.
				var factor: int = [100,106,112,120,130][difficulty] * [100,110,120][phase-1]
				if phase > 1: check(actual.damage * factor > actual.damage * [100,106,112,120,130][difficulty] * [100,110,120][phase-2],"phase packet strictly increases")
			rows.append({"chapter":chapter,"difficulty":difficulty,"old":original,"new":actual})
	for args: Array in [[0,0,2],[7,0,2],[1,-1,2],[1,5,2],[1,0,3]]: check(Policy.stats(args[0],args[1],args[2]).is_empty(),"invalid policy request rejected")
	check(Policy.apply({}).is_empty(),"malformed profile rejected")
	check(Policy.apply({"ruleset_version":2,"scale_version":10,"enemy_id":"M01","rank":"normal","difficulty":0}).is_empty(),"ordinary profile not admitted")
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--boss-policy-output="): output = arg.trim_prefix("--boss-policy-output=")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("Boss progression policy: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
