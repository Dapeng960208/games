extends SceneTree
## Pure advice contracts: no profile writes, Game operations, rendering or scene.
## Root runs this with tools/test.ps1 -Suite equipment_advice -SkipImport.
const Advice = preload("res://scripts/presentation/equipment/equipment_advice.gd")
const Text = preload("res://scripts/infrastructure/localization/strings.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EQUIPMENT ADVICE FAIL: " + label)

func joined(hero: String, before: Dictionary, after: Dictionary) -> String:
	return "\n".join(Advice.summarize(hero, before, after))

func _role_deltas() -> void:
	Text.set_locale("en")
	for hero: String in ["CH01", "CH02"]:
		var ignored := joined(hero, {"attack":20.0, "ability_power":0.0}, {"attack":20.0, "ability_power":10.0})
		check(not ignored.contains("Gain:") and not ignored.contains("Skill power"), hero + " does not turn AP into permanent skill power")
		check(joined(hero, {"attack":20.0}, {"attack":25.0}).contains("Gain: Attack +5.0"), hero + " shows actual attack delta")
	check(joined("CH03", {"attack":18.0, "ability_power":28.0}, {"attack":18.0, "ability_power":38.0}).contains("Gain: Skill power +7.0"), "mage follows actual attack plus 0.7 AP skill formula")
	check(not joined("CH03", {"attack":18.0, "ability_power":28.0}, {"attack":11.0, "ability_power":38.0}).contains("Gain:"), "opposing mage attack and AP changes can cancel exactly")
	check(joined("CH03", {"attack":18.0, "ability_power":28.0}, {"attack":22.0, "ability_power":28.0}).contains("Skill power +4.0"), "attack remains relevant to mage skill power")
	for hero: String in ["CH01", "CH02", "CH03"]:
		check(joined(hero, {"attack_interval":0.5}, {"attack_interval":0.4}).contains("Gain: Attack interval -0.100 s"), hero + " faster primary interval is a gain")
		check(joined(hero, {"attack_interval":0.4}, {"attack_interval":0.5}).contains("Cost: Attack interval +0.100 s"), hero + " slower primary interval is a cost")
		check(joined(hero, {"cooldown_reduction":0.1}, {"cooldown_reduction":0.2}).contains("Gain: Cooldown reduction +10.0 pp"), hero + " cooldown reduction uses correct direction and percentage points")
		check(joined(hero, {"cooldown_reduction":0.2}, {"cooldown_reduction":0.1}).contains("Cost: Cooldown reduction -10.0 pp"), hero + " reduced cooldown reduction is a cost")
		var mana := Advice.summarize(hero, {"resource_max":100.0, "max_mana":100.0}, {"resource_max":120.0, "max_mana":120.0})
		if hero == "CH03": check(mana.size() == 1 and mana[0].contains("Max mana +20.0"), "mage mana delta appears once, without double-counting aliases")
		else: check(not "\n".join(mana).contains("mana") and not "\n".join(mana).contains("Gain:"), hero + " cannot mistake mana for rage or energy")
	check(not joined("CH01", {"attack":20.0}, {"attack":20.000001}).contains("Gain:"), "floating noise does not create a zero-rounded gain")
	check(not joined("CH01", {"attack":20.0}, {"attack":20.001}).contains("+0.0"), "compact rounding never promises plus zero")
	check(not joined("CH02", {}, {"attack_interval":0.4}).contains("Attack interval"), "missing interval does not mean zero-second attacks")

func _set_warnings_and_tradeoffs() -> void:
	for pair: Array in [[2,1,2],[4,3,4],[6,5,6]]:
		check(Advice.lost_tiers({"sets":{"S02":pair[0]}}, {"sets":{"S02":pair[1]}}) == ["S02:" + str(pair[2])], "one-item loss crosses the true " + str(pair[2]) + "-piece threshold")
	for pair: Array in [[3,2],[5,4],[6,6],[1,0],[1,2]]:
		check(Advice.lost_tiers({"sets":{"S02":pair[0]}}, {"sets":{"S02":pair[1]}}).is_empty(), "non-crossing counts do not invent a set loss")
	check(Advice.lost_tiers({"sets":{"S02":6}}, {}) == ["S02:6", "S02:4", "S02:2"], "all lost tiers remain available to UI warning treatment")
	check(Advice.lost_tiers({"sets":{"S02":2,"S01":2}}, {}) == Advice.lost_tiers({"sets":{"S01":2,"S02":2}}, {}), "set warning order is independent of dictionary insertion order")
	var before := {"attack":20.0, "max_hp":100.0, "armor":5.0, "move_speed":200.0, "sets":{"S02":2}}
	var after := {"attack":25.0, "max_hp":80.0, "armor":3.0, "move_speed":220.0, "sets":{"S02":1}}
	for locale: String in ["zh_CN", "en"]:
		Text.set_locale(locale)
		var result := Advice.summarize("CH01", before, after)
		check(result.size() == 3, locale + " severe trade fits three lines")
		check(result[0].begins_with("Lose " if locale == "en" else "失去"), locale + " lost set always takes the first line")
		check(result[1].begins_with("Gain: " if locale == "en" else "收益："), locale + " one meaningful gain remains visible")
		check(result[2].begins_with("Cost: " if locale == "en" else "代价："), locale + " gains cannot hide the main cost")
		for line: String in result: check(line.length() <= (56 if locale == "en" else 28), locale + " summary fits compact detail width")
		for line: String in Advice.summarize("CH01", {"sets":{"S02":6}}, {}):
			check(line.length() <= (56 if locale == "en" else 28), locale + " several lost tiers remain a short warning")

func _purpose_and_relevance() -> void:
	var magic := {"base_stats":{"ability_power":10.0,"max_mana":15.0}}
	var mixed := {"base_stats":{"ability_power":10.0,"armor":4.0}}
	var attack := {"base_stats":{"attack":4.0}}
	for locale: String in ["zh_CN", "en"]:
		Text.set_locale(locale)
		for hero: String in ["CH01", "CH02"]:
			check(not Advice.is_relevant(magic, hero), locale + " magical-only item is not prioritized for " + hero)
			check(Advice.is_relevant(mixed, hero), locale + " useful armor is retained on a mixed-role item for " + hero)
			check(Advice.purpose(mixed, hero).contains("Survival" if locale == "en" else "生存"), locale + " mixed item explains its real defensive purpose")
			check(not Advice.purpose(magic, hero).contains("Mana reserve" if locale == "en" else "法力储备"), locale + " physical role is not promised mana benefit")
		check(Advice.is_relevant(magic, "CH03") and Advice.is_relevant(attack, "CH03"), locale + " mage AP and attack both contribute")
		check(Advice.purpose(magic, "CH03").contains("Mana reserve" if locale == "en" else "法力储备"), locale + " mana purpose belongs to mage")
		check(Advice.is_relevant({"affix_text":"Conditional effect"}, "CH01"), locale + " unknown conditional-only item is not declared useless")
		check(not Advice.is_relevant({}, "CH01") and not Advice.is_relevant(attack, "unknown"), locale + " empty item and unknown hero are not recommended")
		check(not Advice.is_relevant({"allowed_heroes":["CH03"], "base_stats":{"attack":8}}, "CH01"), locale + " explicit item role metadata is respected")
		for hero: String in ["CH01", "CH02", "CH03"]:
			for id: String in Registry.equipment_ids():
				check(Advice.purpose(Registry.equipment(id), hero).length() <= (56 if locale == "en" else 28), locale + " real item purpose remains short: " + hero + "/" + id)

func _resolved_upgrades_and_purity() -> void:
	Text.set_locale("en")
	var profile: Dictionary = Store.fresh_profile()
	var original_profile: Dictionary = profile.duplicate(true)
	var before: Dictionary = Resolver.resolve("CH01", 1, profile.loadout, profile.equipment)
	var refined: Dictionary = profile.equipment.duplicate(true)
	refined.EQ01.level = 5
	var after: Dictionary = Resolver.resolve("CH01", 1, profile.loadout, refined)
	var before_copy: Dictionary = before.duplicate(true)
	var after_copy: Dictionary = after.duplicate(true)
	var result := Advice.summarize("CH01", before, after)
	check("\n".join(result).contains("Attack +2.0"), "upgrade summary reports the actual resolver delta, not total equipment value")
	check(not "\n".join(result).contains("+6.0"), "refining does not report the whole upgraded item as new gain")
	check(Advice.summarize("CH01", before, before).size() == 1 and not joined("CH01", before, before).contains("Gain:"), "identical resolved stats never imply an upgrade")
	var ignored: Dictionary = after.duplicate(true)
	ignored["temporary_buffs"] = {"amplify":{"damage_bonus":0.5}}
	ignored["relic_levels"] = {"RL01":2}
	check(Advice.summarize("CH01", before, ignored) == result, "conditional buff and relic metadata is not counted as permanent stat value")
	check(Advice.summarize("CH01", before, after) == result, "same snapshots produce deterministic advice")
	var item: Dictionary = Registry.equipment("EQ04")
	var copy: Dictionary = item.duplicate(true)
	Advice.purpose(item, "CH01")
	Advice.is_relevant(item, "CH03")
	Advice.lost_tiers(before, after)
	check(before == before_copy and after == after_copy and profile == original_profile and item == copy, "all helper entry points leave caller dictionaries unchanged")

func _run() -> void:
	var original_locale: String = Text.locale
	_role_deltas()
	_set_warnings_and_tradeoffs()
	_purpose_and_relevance()
	_resolved_upgrades_and_purity()
	Text.set_locale(original_locale)
	print("EQUIPMENT ADVICE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
