extends SceneTree
## Pure S01 packet boundaries. Always run with an isolated user-data directory.
const Rules = preload("res://config/numerical_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Status = preload("res://scripts/combat/combat_status.gd")
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("NUMERICAL PACKETS FAIL: " + label)

func integer_amount(actual: Variant, expected: int, label: String) -> void:
	check(actual is int and actual == expected, label + " actual=" + str(actual))

func _initialize() -> void:
	_test_damage()
	_test_status()
	_test_guards()
	_test_legacy()
	print("Numerical packets: %d/%d checks passed; failures=%s" % [checks - failures.size(), checks, failures])
	quit(0 if failures.is_empty() else 1)

func _test_damage() -> void:
	var defender: Dictionary = {"ruleset_version":Rules.V2,"armor":1000,"magic_resist":250,"damage_reduction":0.2}
	var attacker: Dictionary = {"armor_penetration":500,"crit_multiplier":1.5}
	var context: Dictionary = {"armor_multiplier":0.85}
	var original: Array = [attacker.duplicate(true),defender.duplicate(true),context.duplicate(true)]
	integer_amount(Damage.resolve(1000, "physical", attacker, defender, context).damage, 593, "corrosion then penetration then DR then one final round")
	check(original == [attacker,defender,context], "damage arithmetic never mutates snapshots")
	integer_amount(Damage.resolve(1000, "magic", attacker, defender).damage, 640, "magic uses matching defense")
	integer_amount(Damage.resolve(1000, "true", attacker, defender).damage, 1000, "true damage bypasses resistance and reduction")
	integer_amount(Damage.resolve(1000, "physical", {}, {"armor":1000}, {"ruleset_version":Rules.V2}).damage, 500, "context can explicitly opt in")
	var legacy: Variant = Damage.resolve(100, "physical", {"ruleset_version":Rules.V2}, {"armor":100}).damage
	check(legacy is float and legacy == 50.0, "attacker alone does not upgrade legacy damage")
	legacy = Damage.resolve(100, "physical", {}, defender, {"ruleset_version":Rules.LEGACY}).damage
	check(legacy is float and is_equal_approx(legacy, 100.0 / 11.0 * 0.8), "explicit context overrides defender version")
	integer_amount(Damage.resolve(1000, "physical", {}, {"ruleset_version":Rules.V2,"armor":500,"damage_reduction":1.0}, {"armor_penetration":1000}).damage, 350, "penetration floors at zero and DR caps at 65 percent")
	integer_amount(Damage.resolve(1.5, "physical", {"crit_multiplier":1.5}, {"ruleset_version":Rules.V2,"armor":500}, {"critical":true,"already_critical":false}).damage, 1, "explicit critical construction rounds raw packet before defense")
	integer_amount(Damage.resolve(5, "physical", {}, {"ruleset_version":Rules.V2,"armor":1000}, {"post_defense_multiplier":1.35}).damage, 3, "ordinary weakpoint belongs before final rounding")
	integer_amount(Damage.resolve(5 * 1.35, "physical", {}, {"ruleset_version":Rules.V2,"armor":1000}).damage, 3, "caller-side Boss weakpoint retains fractional intermediate")
	for kind: String in ["physical","magic","true"]:
		integer_amount(Damage.resolve(1000, kind, attacker, defender, {"invulnerable":true}).damage, 0, "immunity suppresses " + kind)
	for defense: int in [0,100,250,1000,2500]:
		var old: float = Damage.resolve(100, "physical", {}, {"armor":defense / 10.0}).damage
		integer_amount(Damage.resolve(1000, "physical", {}, {"ruleset_version":Rules.V2,"armor":defense}).damage, Rules.integer(old * 10.0), "scaled defense preserves mitigation " + str(defense))
	for pair: Array in [[0.0,0],[0.49,0],[0.5,1],[1.5,2],[12.5,13],[-1.0,0],[NAN,0],[INF,0]]:
		integer_amount(Damage.resolve(pair[0], "true", {}, defender).damage, pair[1], "nonnegative half-up damage " + str(pair[0]))
		integer_amount(Damage.healing(pair[0], false, Rules.V2), pair[1], "nonnegative half-up healing " + str(pair[0]))
	integer_amount(Damage.healing(12.5, true, Rules.V2), 8, "healing rounds after grievous, never before")

func _test_status() -> void:
	for data: Dictionary in [{"kind":"burn","power":376.0,"damage":45},{"kind":"corrosion","power":270.0,"damage":22},{"kind":"bleed","power":245.0,"damage":25}]:
		var state := Status.new(Rules.V2)
		check(state.apply(data.kind, data.power, 3.6, 100.5), "accept V2 " + data.kind)
		integer_amount(state.states[data.kind].power, int(data.power), "integer snapshot " + data.kind)
		integer_amount(state.states[data.kind].H, 101, "integer source H " + data.kind)
		var ticks: Array[Dictionary] = state.tick(3.6)
		check(ticks.size() == 3 and not state.has(data.kind), "only whole-second ticks, fractional duration retained " + data.kind)
		for packet: Dictionary in ticks:
			integer_amount(packet.damage, data.damage, "integer tick " + data.kind)
			check(packet.H is int and packet.power is int, "integer tick metadata " + data.kind)
	var state := Status.new(Rules.V2)
	check(state.apply("burn", 100.5, 3.0), "half-up status input accepted")
	integer_amount(state.states.burn.power, 101, "status snapshot uses half-up")
	state.tick(0.75)
	var before: Dictionary = state.states.burn.duplicate(true)
	check(not state.apply("burn", 100.49, 9.0) and state.states.burn == before, "weak status rejected atomically after quantization")
	check(state.apply("burn", 100.7, 1.0) and state.states.burn.remaining == 2.25, "equal integer strength refresh cannot shorten duration")
	check(state.tick(0.25).size() == 1, "accepted refresh keeps fractional tick remainder")
	state.apply("burn", 102, 1.0)
	check(state.states.burn.remaining == 1.0, "stronger status gets its own lifetime")
	state.apply("burn", 100000, 9.0)
	state.apply("burn", 100001, 1.0)
	check(state.states.burn.remaining == 1.0, "integer strength comparison never treats a stronger point as approximate equality")
	check(state.apply("shock", 6, 3.0), "shock accepted")
	integer_amount(state.consume_shock(), 2, "shock quarter-packet rounds half-up")
	check(not state.has("shock") and state.shock_cooldown == 1.0, "shock consumed once with original cooldown")
	state.apply("shock", 6, 3.0)
	integer_amount(state.consume_shock(), 0, "cooldown blocks shock without fractional result")
	check(state.has("shock"), "cooldown does not consume pending shock")
	state.apply("damage_reduction", 0.5, 3.0)
	state.apply("brace_guard", 0.7, 1.0)
	check(state.states.damage_reduction.power == 0.5 and state.states.brace_guard.power == 0.65, "reduction ratios remain unscaled")
	check(state.damage_modifiers().damage_reduction == 0.65, "reduction families use strongest")
	state.apply("invulnerable", 1000)
	state.apply("grievous", 1000)
	integer_amount(state.states.invulnerable.power, 1, "invulnerability flag remains one")
	integer_amount(state.states.grievous.power, 1, "grievous flag remains one")
	check(state.healing_multiplier() == 0.6, "grievous ratio unchanged")
	for invalid: float in [NAN,INF]:
		check(not state.apply("burn", invalid), "nonfinite status rejected")

func _test_guards() -> void:
	var state := Status.new(Rules.V2)
	integer_amount(state.shield(), 0, "empty V2 shield is integer")
	var configured := Status.new()
	configured.ruleset_version = Rules.V2
	integer_amount(configured.shield_summary().total_absorbed, 0, "per-instance property opt-in returns integer feedback before first hit")
	var result: Dictionary = state.grant_guard_result(999.0, 4.0, "hero", 101.0)
	check(result.accepted_refresh and result.increased, "new hero shield is accepted and increased")
	integer_amount(state.guards.hero.amount, 51, "hero cap rounds half-up")
	result = state.grant_guard_result(999.0, 4.0, "equipment", 101.0, true)
	check(result.accepted_refresh and not result.increased, "accepted source can be hidden by a larger pool")
	integer_amount(state.guards.equipment.amount, 35, "equipment cap rounds independently")
	integer_amount(state.shield(), 51, "coexisting sources use maximum rather than sum")
	state.tick(0.5)
	result = state.grant_guard_result(51.0, 4.0, "hero", 101.0)
	check(result.accepted_refresh and not result.increased and state.guards.hero.remaining == 4.0, "equal refresh accepts without increasing pool")
	var before: Dictionary = state.guards.duplicate(true)
	result = state.grant_guard_result(50.0, 10.0, "hero", 101.0)
	check(not result.accepted_refresh and not result.increased and state.guards == before, "weaker same-source guard cannot extend strong shield")
	check(not state.grant_guard(51.0, 4.0, "hero", 101.0), "bool guard API still means effective increase")
	integer_amount(state.absorb(12.5), 0, "shield rounds incoming boundary then absorbs")
	integer_amount(state.guards.hero.amount, 38, "hero pool loses integer damage")
	integer_amount(state.guards.equipment.amount, 22, "overlapping pool loses same damage once")
	integer_amount(state.total_absorbed, 13, "integer feedback counts effective loss once")
	integer_amount(state.absorb(50), 12, "integer overflow passes to health")
	integer_amount(state.total_absorbed, 51, "absorption feedback excludes overflow")
	state.tick(0.0)
	check(state.guards.is_empty(), "zero-time reconciliation clears depleted pools")
	state.grant_guard(5, 4.0, "supply:ready:2", 100)
	state.tick(5.0)
	check(state.guards["supply:ready:2"].remaining == 4.0, "prepared reserve does not spend time early")
	state.absorb(0.49)
	check(state.guards.has("supply:ready:2"), "zero rounded packet cannot activate reserve")
	state.absorb(0.5)
	check(state.guards.has("supply:active:2") and not state.guards.has("supply:ready:2"), "positive integer absorption activates reserve")
	integer_amount(state.guards["supply:active:2"].amount, 4, "reserve loses exactly one")
	for invalid: float in [0.0,-1.0,NAN,INF]:
		before = state.guards.duplicate(true)
		result = state.grant_guard_result(invalid, 4.0, "invalid", 100.0)
		check(not result.accepted_refresh and state.guards == before, "invalid guard amount has no mutation")

func _test_legacy() -> void:
	check(Rules.default_ruleset() == Rules.V2, "S10 enables new runs without changing explicit legacy packet rules")
	var state := Status.new()
	check(state.ruleset_version == Rules.LEGACY, "status defaults to legacy")
	state.apply("burn", 10.5, 3.0)
	var tick: Dictionary = state.tick(1.0)[0]
	check(tick.damage is float and is_equal_approx(tick.damage, 1.26), "legacy DOT retains fractions")
	state.apply("shock", 5.0)
	check(state.consume_shock() == 1.25, "legacy shock retains fractions")
	check(Damage.healing(12.5, true) == 7.5, "legacy healing retains fractions")
	state.grant_guard(20.5, 4.0, "hero", 101.0)
	check(not state.grant_guard(10.0, 8.0, "hero", 101.0) and state.guards.hero.remaining == 8.0, "legacy weaker guard keeps original refresh behavior")
	check(state.absorb(0.25) == 0.0 and state.shield() == 20.25 and state.total_absorbed == 0.25, "legacy shield and feedback retain fractions")
