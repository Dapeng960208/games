extends SceneTree
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Learning = preload("res://scripts/domain/progression/field_learning.gd")
const RunData = preload("res://scripts/domain/expedition/run_session.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILURE LEARNING POLICY FAIL: " + label)

func _result(gold: int, outcome: String, rules: int) -> Dictionary:
	var retained: int = Store.retained_gold(gold, outcome, rules)
	return {"run_id":"historical:" + str(rules) + ":" + outcome,"outcome":outcome,
		"collected":gold,"retained":retained,"lost":gold - retained,"permanent_gold":100 + retained,
		"wallet_before":100,"wallet_after":100 + retained,"rules_version":rules,
		"discoveries":[],"kills":3,"shots":4,"elapsed":12.5}

func _document(result: Dictionary, schema: int = 3) -> Dictionary:
	var profile: Dictionary = Store.fresh_profile()
	profile.last_result = result.duplicate(true)
	profile.permanent_gold = result.permanent_gold
	profile.total_runs = 1
	return {"schema_version":schema,"revision":1,"profile":profile,"active_run":null}

func _fixture(kills: int = 1, entry_kills: int = 0) -> Dictionary:
	return {"demo":false,"hero_id":"CH01","kills":kills,
		"expedition":{"phase":"combat","room_entry_kills":entry_kills,"node_index":1,"completed_nodes":[0]}}

func _run() -> void:
	_check(Store.SETTLEMENT_RULES_VERSION == 2, "new settlements declare rules two")
	for gold: int in [0, 1, 4, 5, 9, 25, 37, 100, 1_000_000_000_000]:
		for outcome: String in ["extracted", "death", "abandoned"]:
			var historical: int = gold if outcome == "extracted" else int(gold / 5)
			var current: int = gold if outcome == "extracted" else int(gold / (2 if outcome == "death" else 5))
			_check(Store.retained_gold(gold, outcome, 1) == historical, "historical settlement " + str(gold) + outcome)
			_check(Store.retained_gold(gold, outcome, 2) == current, "current settlement " + str(gold) + outcome)
			_check(Store.retained_gold(gold, outcome) == current, "default settlement uses current rules")
	_check(Store.retained_gold(7, "death") == 3, "death rounds down")
	_check(Store.retained_gold(9, "abandoned") == 1, "abandon still rounds down to twenty percent")
	_check(Store.retained_gold(-10, "death") == -1, "negative purse rejected")
	_check(Store.retained_gold(10, "not_an_outcome") == -1, "unknown outcome rejected")
	_check(Store.retained_gold(10, "death", 3) == -1, "unknown rule rejected")
	for outcome: String in ["extracted", "death", "abandoned"]:
		for rules: int in [1, 2]:
			var document: Dictionary = _document(_result(37, outcome, rules))
			var before: Dictionary = document.duplicate(true)
			_check(Store._valid_document(document), "rule " + str(rules) + " " + outcome + " result validates")
			_check(document == before, "historical verification never mutates snapshots")
			var json_copy: Dictionary = JSON.parse_string(JSON.stringify(document))
			_check(Store._valid_document(json_copy), "JSON numeric representations validate")
			if rules == 1:
				for schema: int in [1, 2, 3]:
					var missing: Dictionary = document.duplicate(true)
					missing.schema_version = schema
					missing.profile.last_result.erase("rules_version")
					_check(Store._valid_document(missing), "missing rules remain historical in schema " + str(schema))
			else:
				var wrong: Dictionary = document.duplicate(true)
				wrong.schema_version = 1
				_check(not Store._valid_document(wrong), "schema one cannot claim future settlement rules")
	for bad: Variant in [-1, 0, 3, 999, 1.5, "1", "2", null]:
		for schema: int in [1, 2, 3]:
			var wrong: Dictionary = _document(_result(25, "death", 1), schema)
			wrong.profile.last_result.rules_version = bad
			_check(not Store._valid_document(wrong), "unknown or malformed historical rules rejected " + str(bad))
	var spoofed: Dictionary = _document(_result(37, "death", 2))
	spoofed.profile.last_result.erase("rules_version")
	_check(not Store._valid_document(spoofed), "missing rules cannot reinterpret new death amount as old")
	var legacy: Dictionary = _document(_result(37, "death", 1), 1)
	legacy.profile.last_result.erase("rules_version")
	legacy.active_run = {"id":"interrupted-legacy","gold":37,"discoveries":[],"kills":2,"shots":4,"elapsed":5.0}
	_check(Store._valid_document(legacy), "legacy interrupted fixture validates")
	var legacy_before: Dictionary = legacy.duplicate(true)
	var migrated: Dictionary = Store._migrate_v1(legacy)
	_check(migrated.last_result.rules_version == 1 and migrated.last_result.retained == 7, "v1 interruption explicitly uses historical twenty percent")
	_check(migrated.last_result.wallet_before == legacy.profile.permanent_gold, "migration retains original wallet")
	_check(legacy == legacy_before, "migration does not alter old snapshot")
	var stable_result: Dictionary = _result(37, "death", 1)
	var stable_document: Dictionary = _document(stable_result, 1)
	stable_document.profile.last_result.erase("rules_version")
	var migrated_history: Dictionary = Store._migrate_v1(stable_document)
	_check(migrated_history.last_result.retained == 7 and migrated_history.last_result.rules_version == 1, "old death history does not change to fifty percent")
	# Exercise persisted history, not only validator calls.
	var save_path: String = "user://failure-learning-policy-" + str(Time.get_ticks_usec()) + ".json"
	var storage := Store.new(save_path)
	_check(storage.save_document(migrated_history), "historical migrated profile saves")
	var reader := Store.new(save_path)
	var loaded: Dictionary = reader.load_document()
	_check(not loaded.is_empty() and loaded.profile.last_result == JSON.parse_string(JSON.stringify(migrated_history.last_result)), "historical receipt reload is unchanged")
	var new_profile: Dictionary = Store.fresh_profile()
	new_profile.last_result = _result(37, "death", 2)
	new_profile.last_result.field_xp_gained = 6
	new_profile.last_result.hero_xp_gained = 36
	new_profile.hero_xp.CH01 = 36
	new_profile.permanent_gold = 118
	new_profile.total_runs = 1
	_check(reader.save_document(new_profile), "new death result with field XP saves")
	var latest := Store.new(save_path)
	loaded = latest.load_document()
	_check(not loaded.is_empty() and loaded.profile.last_result == JSON.parse_string(JSON.stringify(new_profile.last_result)), "new receipt round trips without history rewrite")
	for bad: Variant in [-1, 19, 1.5, "2"]:
		var bad_result: Dictionary = new_profile.last_result.duplicate(true)
		bad_result.field_xp_gained = bad
		_check(not Store._valid_result(bad_result, 3), "malformed field XP rejected")
	var excess: Dictionary = new_profile.last_result.duplicate(true)
	excess.hero_xp_gained = 5
	_check(not Store._valid_result(excess, 3), "field XP cannot exceed reported total XP")
	var abandon_result: Dictionary = _result(37, "abandoned", 2)
	abandon_result.field_xp_gained = 2
	abandon_result.hero_xp_gained = 2
	_check(not Store._valid_result(abandon_result, 3), "abandon history cannot claim field XP")
	var historical_field: Dictionary = _result(37, "death", 1)
	historical_field.field_xp_gained = 2
	historical_field.hero_xp_gained = 2
	_check(not Store._valid_result(historical_field, 3), "legacy rule cannot claim a new field reward")
	var profile: Dictionary = Store.fresh_profile()
	for pair: Array in [[0,0],[1,2],[8,16],[9,18],[10,18],[1000000,18]]:
		var run: Dictionary = _fixture(pair[0])
		var run_before: Dictionary = run.duplicate(true)
		var profile_before: Dictionary = profile.duplicate(true)
		_check(Learning.calculate(run, profile, "death") == pair[1], "first room kills " + str(pair[0]))
		_check(run == run_before and profile == profile_before, "calculation is pure")
	_check(Learning.calculate(_fixture(45, 44), profile, "death") == 2, "prior committed room kills excluded")
	_check(Learning.calculate(_fixture(44, 44), profile, "death") == 0, "no unfinished kills gives no reward")
	_check(Learning.calculate(_fixture(10, 44), profile, "death") == 0, "negative kill delta gives no reward")
	_check(Learning.calculate(_fixture(-1), profile, "death") == 0, "negative kill total rejected")
	_check(Learning.calculate(_fixture(1, -1), profile, "death") == 0, "negative entry count rejected")
	for outcome: String in ["extracted", "abandoned", "", "win"]:
		_check(Learning.calculate(_fixture(9), profile, outcome) == 0, "only death earns field learning")
	for phase: String in ["safe", "cleared", ""]:
		var run: Dictionary = _fixture(9)
		run.expedition.phase = phase
		_check(Learning.calculate(run, profile, "death") == 0, "noncombat phase excluded")
	var completed: Dictionary = _fixture(9)
	completed.expedition.completed_nodes.append(1)
	_check(Learning.calculate(completed, profile, "death") == 0, "completed node never double grants")
	var demo: Dictionary = _fixture(9)
	demo.demo = true
	_check(Learning.calculate(demo, profile, "death") == 0, "demo never grants persistent field XP")
	var non_expedition: Dictionary = _fixture(9)
	non_expedition.expedition = {}
	_check(Learning.calculate(non_expedition, profile, "death") == 0, "legacy/nonexpedition run excluded")
	for invalid: Variant in [null, {}, 5, "run", {"kills":1}]:
		_check(Learning.calculate(invalid, profile, "death") == 0, "invalid run excluded")
	for xp: int in [3590, 3599, 3600, 3601, -1]:
		var capped: Dictionary = profile.duplicate(true)
		capped.hero_xp.CH01 = xp
		var expected: int = maxi(0, 3600 - xp) if xp >= 0 else 0
		_check(Learning.calculate(_fixture(9), capped, "death") == expected, "XP cap or invalid XP " + str(xp))
	var unknown: Dictionary = _fixture(9)
	unknown.hero_id = "missing"
	_check(Learning.calculate(unknown, profile, "death") == 0, "unknown hero rejected")
	var state := RunData.new()
	state.kills = 24
	state.expedition = _fixture(24, 20).expedition
	_check(Learning.calculate(state, profile, "death") == 8, "real RunSession uses unfinished room delta")
	state.demo = true
	_check(Learning.calculate(state, profile, "death") == 0, "real RunSession demo excluded")
	print("FAILURE LEARNING POLICY: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
