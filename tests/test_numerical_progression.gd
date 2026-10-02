extends SceneTree
const Growth = preload("res://scripts/core/hero_progression.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Stats = preload("res://scripts/combat/stat_resolver.gd")
const Store = preload("res://scripts/core/profile_store.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	check(Growth.level_cap() == 20 and Growth.rank_cap() == 5, "only released four chapters")
	check(Growth.rank_cap(60) == 15, "future talent rank interface")
	check(Growth.thresholds(60)[20] == 4040 and Growth.thresholds(60)[21] == 4520, "future linear XP increments")
	for index in Growth.thresholds().size():
		check(Growth.level_for_xp(Growth.thresholds()[index]) == index + 1, "each threshold grants exact level")
		if index > 0: check(Growth.level_for_xp(int(Growth.thresholds()[index])-1) == index, "before threshold remains old level")
	check(Registry.level_for_xp(170) == 5 and Registry.level_for_xp(170,2) == 4, "legacy XP unchanged")
	for hero in Registry.heroes():
		var definition: Dictionary = Registry.hero(hero)
		var curves: Dictionary = {"CH01":[.042,.065,12,8],"CH02":[.052,.045,7,7],"CH03":[.02,.04,5,12]}
		var curve: Array = curves[hero]
		for level in [1,20,60]:
			var base := Growth.hero_base(definition,level,{},60)
			for key in ["attack","ability_power","max_hp","armor","magic_resist","resource_max","resource_regen","starting_resource"]:
				check(base[key] is int,"integer base %s/%s/%s" % [hero,level,key])
			check(base.attack == int(floor(float(definition.attack)*10*(1+curve[0]*(level-1))+.5)),"class linear AD")
			check(base.max_hp == int(floor(float(definition.max_hp)*10*(1+curve[1]*(level-1))+.5)),"class linear HP")
			check(base.armor == int(definition.armor)*10+curve[2]*(level-1),"class armor growth")
			check(base.magic_resist == int(definition.magic_resist)*10+curve[3]*(level-1),"class MR growth")
			check(base.talent_points_available == level-1,"one point each level2+")
		var allocation := {"mastery":5,"precision":5,"agility":5,"dexterity":4}
		var resolved := Stats.resolve(hero,20,{}, {},2,allocation)
		check(resolved.talent_points_available == 0,"nineteen allocated")
		check(is_equal_approx(resolved.crit_chance,.1),"precision adds five points")
		check(is_equal_approx(resolved.attack_speed_bonus,.1),"agility adds ten points")
		check(is_equal_approx(resolved.cooldown_reduction,.04),"dexterity four points")
	check(Stats.resolve("CH01",20,{},{},2).attack == 485,"Lv20 warrior AD target")
	check(Stats.resolve("CH01",20,{},{},2).max_hp == 3353,"Lv20 warrior HP target")
	check(Stats.resolve("CH02",20,{},{},2).attack == 477 and Stats.resolve("CH02",20,{},{},2).max_hp == 2041,"Lv20 gunner growth targets")
	var mage := Stats.resolve("CH03",20,{},{},2)
	check(mage.attack == 248 and mage.ability_power == 626 and mage.max_hp == 1848 and mage.armor == 155 and mage.magic_resist == 408,"Lv20 mage growth targets")
	check(mage.resource_max == 1200 and mage.resource_regen == 80 and is_equal_approx(mage.resource_regen_delay,.25),"mage spell resource budget")
	check(is_equal_approx(float(Stats.resolve("CH03",20,{},{}).resource_regen),5.0),"legacy resource budget unchanged")
	check(not Growth.valid_talents({"mastery":6},20),"per-node cap enforced")
	check(not Growth.valid_talents({"mastery":5,"precision":5,"agility":5,"dexterity":5},20),"cannot spend twentieth point")
	check(not Growth.valid_talents({"fake":1},20),"unknown talent rejected")
	var p := Store.fresh_profile()
	p.ruleset_version = 2
	p.hero_xp.CH01 = 3590
	var award := Growth.award(p,"CH01",370,"fixture:1","B02")
	check(award.added == 10 and award.profile.hero_xp.CH01 == 3600,"cap reached without banked future XP")
	check(award.profile.materials.forge == 4 and award.profile.materials["race:B02"] == 1,"360 research grants four common and one current-race")
	check(award.profile.research_xp.CH01 == 0,"research remainder")
	var replay := Growth.award(award.profile,"CH01",370,"fixture:1","B02")
	check(replay.replayed and replay.profile == award.profile,"same event idempotent")
	check(Growth.award(award.profile,"CH01",371,"fixture:1","B02").is_empty(),"conflicting replay rejected")
	var remainder := Growth.award(award.profile,"CH01",359,"fixture:2","B01")
	check(remainder.profile.research_xp.CH01 == 359 and remainder.profile.materials.forge == 4,"fraction stays research only")
	check(Store._valid_v2_growth(remainder.profile),"research fields validate for persistence")
	print("Numerical progression: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
