extends "res://tests/equipment/test_numerical_acquisition_lifecycle.gd"
## Test the actual authoritative completion/save/reload boundary at every D,
## both below the cap and with every earned XP entering research carry-out.
const ROOM_XP := [30,38,45,53,60]
const BOSS_XP := [80,100,120,140,160]

func _ready() -> void:
	if not Game.profile_path.contains("test_numerical_reward_scaling_lifecycle"):
		get_tree().quit(2)
		return
	for difficulty in 5:
		for research: bool in [false, true]:
			var value := fixture()
			value.hero_xp.CH01 = 3600 if research else 0
			if research: value.research_xp = {"CH01":359}
			check(begin(value, difficulty), "start real D%d research=%s" % [difficulty,research])
			var total := 0
			var ended := false
			while Game.run != null and not ended:
				if not advance(): check(false, "route transition D" + str(difficulty)); break
				if Game.run.expedition.phase == "safe": continue
				var node: Dictionary = Game.run.expedition.route.nodes[int(Game.run.expedition.node_index)]
				var boss: bool = node.role == "boss"
				var expected: int = BOSS_XP[difficulty] if boss else ROOM_XP[difficulty]
				var event: String = Game.run.id + ":node:" + str(int(node.node_index)) + ":complete"
				var xp_before: int = int(Game.profile.hero_xp.CH01)
				var research_before: int = int(Game.profile.get("research_xp", {}).get("CH01", 0))
				var wallet_before: Dictionary = Game.profile.materials.duplicate(true)
				var gold_before: int = Game.run.gold
				check(clear_room(), "D%d %s completion atomically saves" % [difficulty,"Boss" if boss else "room"])
				total += expected
				check(Game.profile.progression_receipts[event].amount == expected, "canonical XP receipt D%d source=%s" % [difficulty,"Boss" if boss else "room"])
				var base_gold := 80 if boss else int(Rewards.v2_completion(str(node.room_id), 0).gold) / 2
				check(Game.run.gold - gold_before == ceili(base_gold * 2.0 * (1.0 + .25 * difficulty)), "gold uses source G0×2×D exactly once")
				if research:
					var rewards_count := int((research_before + expected) / 360)
					var materials := {} if rewards_count == 0 else {"forge":4 * rewards_count,"race:B01":rewards_count}
					check(Game.profile.hero_xp.CH01 == 3600 and int(Game.profile.research_xp.CH01) == (research_before + expected) % 360, "scaledXP advances research remainder at D" + str(difficulty))
					check(Loot.same(Game.run.expedition.loot_events[event].research_materials, materials) and Game.profile.materials == wallet_before, "scaledXP research materials remain pending at D" + str(difficulty))
				else:
					check(int(Game.profile.hero_xp.CH01) - xp_before == expected and int(Game.profile.hero_xp.CH01) == total, "scaledXP advances actual heroXP at D" + str(difficulty))
				var saved: Dictionary = Game.run.receipt()
				var profile_before: Dictionary = Game.profile.duplicate(true)
				check(Game.commit_expedition_completion(event, boundary()) and Game.profile == profile_before and Game.run.receipt() == saved, "completion retry neither addsXP nor research")
				Game.reload_profile()
				check(Game.run != null and Game.run.expedition.phase == "cleared" and Game.profile.progression_receipts[event].amount == expected, "D%d source XP receipt survives actual disk reload" % difficulty)
				if research:
					check(int(Game.profile.research_xp.CH01) == (359 + total) % 360 and Loot.same(Game.profile.materials, wallet_before), "research progress and pending ownership survive reload")
				else:
					check(int(Game.profile.hero_xp.CH01) == total, "actual scaled heroXP survives reload")
				if boss:
					var invalid: Dictionary = Game.profile.duplicate(true)
					invalid.progression_receipts[event].amount += 1
					check(not ExpeditionState.valid(Game.run.receipt(), invalid), "reject mismatched canonical XP receipt")
				ended = boss
			check(ended, "D%d %s exercised Boss checkpoint" % [difficulty,"research" if research else "heroXP"])
			check(not Game.finish_run("death").is_empty(), "finish isolated test journey")
	_tutorial_xp()
	print("Numerical reward scaling lifecycle: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _tutorial_xp() -> void:
	var value := fixture()
	value.hero_xp.CH01 = 0
	check(begin(value, 1) and advance(), "tutorial D1 fixture enters actual combat")
	Game.run.staged_tutorial = true
	check(clear_room(), "tutorial and scaled roomXP commit together")
	var event: String = Game.run.id + ":node:1:complete"
	check(Game.profile.hero_xp.CH01 == 68 and Game.profile.progression_receipts[event].amount == 68 and Game.run.expedition.loot_events[event].tutorial_xp == 30, "one-time tutorial30 adds to scaled D1 room38")
	Game.reload_profile()
	check(Game.run != null and Game.profile.hero_xp.CH01 == 68 and Game.profile.tutorial_completed.has("CH01"), "scaledXP plus explicit tutorial provenance survives reload")
	check(clear_room() and Game.profile.hero_xp.CH01 == 68, "tutorial retry cannot add a second reward")
