extends SceneTree
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Stats = preload("res://scripts/domain/combat/stat_resolver.gd")
const Effects = preload("res://scripts/domain/combat/equipment_effects.gd")
const Health = preload("res://scripts/domain/combat/health.gd")
const EnemySkills = preload("res://scripts/gameplay/monsters/enemy_skill_runtime.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	for input in [-1.0, 0.0, 0.49, 0.5, 1.5, 10.49, 10.5]:
		check(Numbers.integer(input) == int(floor(maxf(0, input) + .5)), "half-up %s" % input)
	for hero in ["CH01", "CH02", "CH03"]:
		var old := Stats.resolve(hero, 1, {}, {})
		var next := Stats.resolve(hero, 1, {}, {}, 2)
		for key in Stats.FLAT_KEYS:
			if not next.has(key): continue
			check(next[key] is int, "%s/%s integer" % [hero,key])
			check(next[key] == Numbers.integer(float(old[key]) * 10), "%s/%s exactly scaled" % [hero,key])
		check(next.move_speed == old.move_speed and next.range == old.range and next.attack_interval == old.attack_interval, "unscaled geometry/timing")
		check(is_equal_approx(next.armor_damage_reduction,old.armor_damage_reduction), "same mitigation ratio")
	check(Stats.clamp_equipment_contributions({"attack":999999},2).attack == 999999, "flat gear cap removed")
	check(Stats.clamp_equipment_contributions({"attack":999999}).attack == 45, "legacy cap retained")
	var fx := Effects.new()
	fx.stats = {"ruleset_version":2,"max_hp":101}
	check(fx.skill_cost(0) == 0, "zero cost remains zero")
	check(fx.skill_cost(.1) == 10, "positive minimum scales to ten")
	for raw in range(1, 30):
		fx.roots.clear()
		fx.cooldowns.clear()
		var root: Dictionary = fx._root("case")
		var out := {"triggered":[],"bonus_hits":[]}
		var ctx := {"X":raw,"target_id":"a","target_alive":true,"nearby_targets":[{"id":"b","alive":true,"distance":1},{"id":"c","alive":true,"distance":2}]}
		fx._bonus(out,ctx,root,"test",0,1,3,false)
		var sum := 0
		for packet: Dictionary in out.bonus_hits:
			for amount: Variant in packet.damage_by_target.values():
				check(amount is int, "derived integer")
				sum += int(amount)
		check(sum <= int(raw * 6 / 5), "all-target derived budget")
		check(root.damage_spent == sum, "exact spent ledger")
	var heal_out := {"heal_ratio":0.0}
	fx._heal(heal_out,{"max_hp":101,"hp":1},.02)
	fx._heal(heal_out,{"max_hp":101,"hp":1},.02)
	check(heal_out.heal_amount == 3, "rounded candidates respect floor3% healing budget")
	var health := Health.new()
	health.reset(100.5,2)
	health.damage(1.5)
	check(health.maximum is int and health.current is int and health.current == 99, "actor integer storage")
	health.free()
	var skills := EnemySkills.new()
	check(skills._anchor_health({"ruleset_version":2},1000) == 800, "anchor cap scaled")
	check(skills._anchor_health({"ruleset_version":2,"scale_version":10},350) == 350, "anchor not double scaled")
	check(skills._anchor_health({},1000) == 80, "legacy anchor cap")
	skills.free()
	print("Numerical stat/budget checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
