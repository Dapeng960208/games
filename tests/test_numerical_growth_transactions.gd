extends Node
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	if not Game.profile_path.contains("test_numerical_growth_transactions"):
		get_tree().quit(2)
		return
	# A generated test-only profile, never a copy of player data.
	Game.run = null
	check(Game.new_profile(), "fresh synthetic profile")
	var profile := Game.profile.duplicate(true)
	profile.ruleset_version = 2
	profile.hero_xp.CH01 = 3600
	check(Game._commit_profile(profile), "save V2 synthetic growth state")
	check(Game.set_hero_talents({"mastery":5,"precision":5,"agility":5,"dexterity":4}), "save nineteen talents")
	check(not Game.set_hero_talents({"mastery":6}), "reject excessive rank")
	Game.reload_profile()
	check(Game.hero_talents().mastery == 5 and Game.hero_level() == 20, "allocation persists")
	check(Game.set_hero_talents({}), "free camp respec")
	check(Game.start_run(), "start targeted V2 test run")
	Game.run.hp = 777
	Game.run.resource = 123
	var wallet := int(Game.profile.permanent_gold)
	get_tree().paused = true
	check(Game.allocate_hero_talent("vitality"), "safe-pause allocates one point")
	check(Game.run.hp == 777 and Game.run.resource == 123 and int(Game.profile.permanent_gold) == wallet, "allocation does not heal/restore/spend")
	check(not Game.set_hero_talents({}), "respec is camp-only")
	get_tree().paused = false
	check(not Game.allocate_hero_talent("mastery"), "combat allocation rejected")
	check(Game.grant_hero_xp(360,"research-test:1"), "actual XP event commits research")
	check(Game.profile.materials.forge == 4 and Game.profile.materials["race:B01"] == 1, "actual research materials")
	check(Game.run.hp == 777 and Game.run.resource == 123, "XP refresh does not restore state")
	check(Game.grant_hero_xp(360,"research-test:1") and Game.profile.materials.forge == 4, "duplicate XP request cannot refund materials twice")
	var saved := ProfileStore.new(Game.profile_path).load_document()
	check(saved.profile.materials.forge == 4 and saved.profile.talents.CH01.vitality == 1, "atomic growth/material persistence")
	print("Numerical growth transactions: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
