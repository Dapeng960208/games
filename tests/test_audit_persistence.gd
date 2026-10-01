extends SceneTree
## A14/A15/A20: frozen transaction rules, exact UTF-8 durability, failure retention.
const Store = preload("res://scripts/core/profile_store.gd")
const History = preload("res://scripts/core/economy_history.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
var checks := 0
var failures := 0
var directory := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AUDIT PERSISTENCE: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _document(profile: Dictionary, revision: int = 1) -> Dictionary:
	return {"schema_version": 3, "revision": revision, "profile_initialized": true,
		"profile": profile, "active_run": null}

func _write(path: String, document: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(Store._serialize(document))
	file.close()

func _sale(ids: Array, level: int = 0) -> Dictionary:
	var sorted := ids.duplicate()
	sorted.sort()
	var items := {}
	var total := 0
	for id: String in sorted:
		var price := History.sell_price(id, level, 1)
		items[id] = {"level": level, "price": price}
		total += price
	return {"kind": "sale", "item": ",".join(sorted), "items": items, "price": total}

func _set_purchase(id: String, partial: bool = false) -> Dictionary:
	var items := History.set_items(id, 1)
	if partial: items.resize(3)
	var price := 0
	for item: String in items: price += History.item_price(item, 1) * 9 / 10
	return {"kind": "purchase_set", "item": id, "items": items, "price": price}

func _economy_profile() -> Dictionary:
	var profile := Store.fresh_profile()
	profile.applied_transactions.merge({
		"legacy-purchase": {"kind": "purchase", "item": "EQ03", "price": 180, "level": 0},
		"legacy-upgrade": {"kind": "upgrade", "item": "EQ03", "price": 340, "level": 5},
		"legacy-set": _set_purchase("S09"),
		"legacy-partial": _set_purchase("S10", true),
		"legacy-sale": _sale(["EQ03", "EQ61"], 5),
	})
	return profile

func _economy() -> void:
	var profile := _economy_profile()
	check(Store._valid_document(_document(profile)), "all legitimate unversioned economy receipts validate")
	check(History.V1_PRICES.size() == 96 and History.V1_SETS.size() == 14, "frozen catalog includes all 96 items and 14 sets")
	for id: String in Registry.equipment_ids():
		check(History.item_price(id, 1) == int(Registry.equipment(id).price), "v1 price snapshot matches " + id)
	var original := Registry._equipment.duplicate(true)
	# Mutate actual live catalog data, not a transcription of the validator.
	for id: String in Registry.equipment_ids():
		Registry._equipment[id].price = int(Registry._equipment[id].price) + 777
		Registry._equipment[id].set_id = ""
	check(Store.equipment_sell_price("EQ03", 5) != 225, "fixture changes live sale price")
	check(Store._valid_document(_document(profile)), "legacy purchase, set, partial, upgrade, and sale survive live repricing and regrouping")
	check(History.sell_price("EQ03", 5, 1) == 225 and History.upgrade_price(5, 1) == 340,
		"frozen sale refunds and upgrade costs retain original five-step schedule")
	var path := directory + "/economy.json"
	var store := Store.new(path)
	check(store.save_document(profile), "repriced historical profile saves")
	check(store.save_document(profile), "second historical save creates validated backup")
	var invalid := profile.duplicate(true)
	invalid.applied_transactions["legacy-sale"].price += 1
	check(not store.save_document(invalid) and store.last_error == "STORAGE_INVALID_DATA", "forged sale sum rejected")
	var primary := _document(invalid, 99)
	_write(path, primary)
	var recovery := Store.new(path)
	var recovered := recovery.load_document()
	check(not recovered.is_empty() and recovery.warning == "STORAGE_RECOVERED", "frozen receipts recover valid backup after tampered primary")
	Registry._equipment = original
	for id: String in profile.applied_transactions:
		if id != "starter_grant_v1": profile.applied_transactions[id].economy_version = 1
	check(Store._valid_document(_document(profile)), "explicit v1 versions validate")
	for id: String in ["legacy-purchase", "legacy-upgrade", "legacy-set", "legacy-partial", "legacy-sale"]:
		invalid = profile.duplicate(true)
		invalid.applied_transactions[id].price += 1
		check(not Store._valid_document(_document(invalid)), "arbitrary amount rejected for " + id)
		invalid = profile.duplicate(true)
		invalid.applied_transactions[id].economy_version = 99
		check(not Store._valid_document(_document(invalid)), "unknown economy version rejected for " + id)
	invalid = profile.duplicate(true)
	invalid.applied_transactions["legacy-sale"].items.EQ03.price += 1
	invalid.applied_transactions["legacy-sale"].price += 1
	check(not Store._valid_document(_document(invalid)), "coordinated forged line amount and sum rejected")
	invalid = profile.duplicate(true)
	invalid.applied_transactions["legacy-upgrade"].level = 0
	check(not Store._valid_document(_document(invalid)), "zero-level paid upgrade rejected")

func _capacity() -> void:
	var profile := Store.fresh_profile()
	var path := directory + "/bytes.json"
	var store := Store.new(path)
	check(store.save_document(profile) and store.save_document(profile), "capacity fixture creates primary and backup")
	# A valid multibyte transaction ID makes character counting observably wrong.
	profile.applied_transactions["购买交易"] = {"kind": "purchase", "item": "EQ03", "price": 180, "level": 0}
	var capacity := store.storage_capacity(profile)
	var encoded := Store._serialize(store._next_document(profile, null, true))
	check(encoded.size() > JSON.stringify(store._next_document(profile, null, true)).length(), "UTF-8 bytes differ from character count")
	check(capacity.bytes == encoded.size() and capacity.remaining_transactions == 4094, "capacity reports exact future document bytes and remaining receipt IDs")
	store.max_document_bytes = encoded.size()
	check(store.save_document(profile), "exact byte limit is accepted")
	check(FileAccess.get_file_as_bytes(path).size() == store.max_document_bytes, "written bytes equal checked bytes")
	var reload := Store.new(path)
	reload.max_document_bytes = store.max_document_bytes
	check(not reload.load_document().is_empty(), "exact byte limit reloads")
	var before := FileAccess.get_file_as_bytes(path)
	var backup := FileAccess.get_file_as_bytes(path + ".bak")
	store.max_document_bytes -= 1
	check(not store.save_document(profile) and store.last_error == "STORAGE_CAPACITY_EXCEEDED", "one byte over the same limit rejected before write")
	check(FileAccess.get_file_as_bytes(path) == before and FileAccess.get_file_as_bytes(path + ".bak") == backup,
		"oversize refusal preserves both primary and backup byte-for-byte")
	check(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak.tmp"), "oversize refusal creates no write intent")
	check(not store._write_document(path + ".direct", store._current) and not FileAccess.file_exists(path + ".direct"), "low-level writer has identical byte guard")
	var lower_reader := Store.new(path)
	lower_reader.max_document_bytes = store.max_document_bytes
	var recovered := lower_reader.load_document()
	check(not recovered.is_empty() and lower_reader.warning == "STORAGE_RECOVERED" and recovered.profile.applied_transactions.size() == 1,
		"same read ceiling rejects oversized primary and recovers smaller backup")

func _long_ledger() -> void:
	var profile := Store.fresh_profile()
	var ids: Array = []
	for set_id: String in ["S09", "S10", "S11"]: ids.append_array(History.set_items(set_id, 1))
	for cycle in range(1000):
		for set_id: String in ["S09", "S10", "S11"]:
			profile.applied_transactions["buy_%04d_%s" % [cycle, set_id]] = _set_purchase(set_id)
		profile.applied_transactions["sale_%04d" % cycle] = _sale(ids)
	for id: String in profile.applied_transactions:
		if id != "starter_grant_v1": profile.applied_transactions[id].economy_version = 1
	check(Store._valid_document(_document(profile)), "4001-receipt long-ledger fixture is structurally valid")
	var store := Store.new(directory + "/long.json")
	var capacity := store.storage_capacity(profile)
	check(capacity.bytes > 1_048_576 and capacity.bytes < Store.MAX_DOCUMENT_BYTES, "real full document crosses old 1 MiB cutoff with room remaining")
	check(capacity.remaining_transactions == 95, "long ledger retains exact receipt-count headroom")
	check(store.save_document(profile), "first >1MiB save succeeds")
	profile.permanent_gold = 7
	check(store.save_document(profile), "second >1MiB save succeeds")
	var reloaded := Store.new(store.path).load_document()
	check(not reloaded.is_empty() and reloaded.profile.permanent_gold == 7 and reloaded.profile.applied_transactions == JSON.parse_string(JSON.stringify(profile.applied_transactions)),
		"fresh store restarts latest large revision with every anti-replay ID and receipt intact")
	var child_output: Array = []
	var child_status := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/test_audit_persistence.gd", "--", "--reload-path", ProjectSettings.globalize_path(store.path)], child_output, true)
	var child_log := "\n".join(child_output)
	check(child_status == 0 and child_log.contains("PERSISTENCE CHILD RESTART PASS") and not child_log.contains("ERROR:"),
		"separate real Godot process reopens two-save >1MiB history without errors")
	# Upper-bound sizing covers the worst current legitimate batch shape without evicting history.
	var maximum := Store.fresh_profile()
	var biggest := _sale(Registry.equipment_ids(), 5)
	biggest.economy_version = 1
	for index in range(Store.MAX_TRANSACTIONS - 1):
		maximum.applied_transactions[("😀".repeat(150) + "%010d" % index)] = biggest
	check(Store._valid_document(_document(maximum)), "maximum ledger receipt shape and 160-character IDs validate")
	var maximal_bytes: int = store.storage_capacity(maximum).bytes
	check(maximal_bytes < Store.MAX_DOCUMENT_BYTES, "32MiB holds all 4096 receipts even full-catalog sales with max-length multibyte IDs")
	print("A15 long ledger bytes=", capacity.bytes, "; maximum receipt-shape bytes=", maximal_bytes)

func _result(rules: int, outcome: String) -> Dictionary:
	var retained := Store.retained_gold(1001, outcome, rules)
	return {"run_id": "receipt-%d-%s" % [rules, outcome], "outcome": outcome,
		"collected": 1001, "retained": retained, "lost": 1001 - retained,
		"permanent_gold": retained, "wallet_before": 0, "wallet_after": retained,
		"rules_version": rules, "discoveries": [], "kills": 1, "shots": 2, "elapsed": 3.0}

func _settlement() -> void:
	check(Store.retained_gold(1001, "death") == 500 and Store.retained_gold(1001, "abandoned") == 500,
		"new death and voluntary abandonment retain identical floor-half gold")
	check(Store.retained_gold(1001, "death", 1) == 200 and Store.retained_gold(1001, "abandoned", 1) == 200,
		"v1 historical death and abandonment remain one fifth")
	check(Store.retained_gold(1001, "death", 2) == 500 and Store.retained_gold(1001, "abandoned", 2) == 200,
		"v2 historical asymmetric payouts remain unchanged")
	for rules in [1, 2, 3]:
		for outcome: String in ["death", "abandoned", "extracted"]:
			var profile := Store.fresh_profile()
			profile.last_result = _result(rules, outcome)
			profile.permanent_gold = profile.last_result.retained
			check(Store._valid_document(_document(profile)), "result validates under its own rule %d %s" % [rules, outcome])
			if rules < 3 and outcome == "abandoned":
				profile.last_result.retained = 500
				profile.last_result.lost = 501
				check(not Store._valid_document(_document(profile)), "old abandonment cannot be reinterpreted as new half retention")
	var original := {"schema_version": 1, "revision": 1, "active_run": {
		"id": "legacy-active", "gold": 1001, "discoveries": [], "kills": 1, "shots": 2, "elapsed": 3.0},
		"profile": {"permanent_gold": 0, "discoveries": [], "total_runs": 0, "last_result": {},
			"settings": {"language": "en", "reduced_fx": false, "fullscreen": false}}}
	var path := directory + "/legacy.json"
	_write(path, original)
	var bytes := FileAccess.get_file_as_bytes(path)
	var blocked := Store.new(path)
	blocked.max_document_bytes = bytes.size()
	check(blocked.load_document().is_empty() and blocked.last_error == "STORAGE_CAPACITY_EXCEEDED", "failed larger v1 migration reports capacity failure")
	check(FileAccess.get_file_as_bytes(path) == bytes and FileAccess.get_file_as_bytes(path + ".v1.bak") == bytes,
		"failed migration preserves original and one-time migration backup")
	var migrated := Store.new(path).load_document()
	check(not migrated.is_empty() and migrated.profile.last_result.retained == 200 and migrated.profile.last_result.rules_version == 1,
		"retry migrates old active run once with historical abandonment")
	var again := Store.new(path).load_document()
	check(not again.is_empty() and again.profile.total_runs == 1 and again.profile.permanent_gold == 200, "migration restart never pays twice")

func _presets() -> void:
	var profile := Store.fresh_profile()
	profile.loadout_presets = {"CH01": profile.loadout.duplicate(), "CH02": profile.loadout.duplicate()}
	profile.loadout_presets.CH02.weapon = "EQ61"
	check(Store._valid_document(_document(profile)), "optional preset may retain a known sold item for safe controller fallback")
	profile.loadout_presets.CH02.weapon = ""
	check(Store._valid_document(_document(profile)), "sale may clear an unavailable preset reference")
	profile.loadout_presets.CH02.weapon = "EQ62"
	check(not Store._valid_document(_document(profile)), "preset cannot equip a helmet in weapon slot")
	profile.loadout_presets.CH02.weapon = "UNKNOWN"
	check(not Store._valid_document(_document(profile)), "unknown preset item rejected")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--reload-path":
		var loaded := Store.new(args[1]).load_document()
		var valid: bool = not loaded.is_empty() and int(loaded.revision) == 2 and loaded.profile.permanent_gold == 7 \
			and loaded.profile.applied_transactions.size() == 4001 and loaded.profile.applied_transactions.has("buy_0000_S09") \
			and loaded.profile.applied_transactions.has("sale_0999")
		if valid: print("PERSISTENCE CHILD RESTART PASS")
		quit(0 if valid else 1)
		return
	directory = "user://audit_persistence_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_economy()
	_capacity()
	_long_ledger()
	_settlement()
	_presets()
	print("AUDIT PERSISTENCE ", checks - failures, "/", checks, " checks passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)
