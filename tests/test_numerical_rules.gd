extends SceneTree
const Rules = preload("res://config/numerical_rules.gd")
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

func _initialize() -> void:
	check(Rules.default_ruleset() == Rules.V2, "S10 production new profiles use V2")
	check(not Rules.is_v2({}), "missing version stays legacy")
	check(Rules.is_v2({"ruleset_version":2}), "explicit version opts in")
	check(Rules.frozen_versions(2).scale_version == 10, "scale is versioned separately")
	check(Rules.frozen_versions(1).scale_version == 1, "old adventure retains scale")
	var copy := Rules.parameters()
	copy.runtime_enabled = false
	copy.growth.attack = 999
	check(Rules.value("runtime_enabled"), "parameter copies cannot disable production")
	check(is_equal_approx(float(Rules.value("growth").attack), 0.04), "nested copies are independent")
	print("Numerical rules: 7 checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
