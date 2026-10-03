extends SceneTree
const Native = preload("res://scripts/domain/equipment/numerical_profile.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	var original := Store.fresh_profile()
	var profile := Native.fresh(original)
	check(not profile.is_empty(),"native profile exists")
	if profile.is_empty(): quit(1); return
	check(profile == Native.fresh(original),"deterministic retry grants identical identity")
	check(not original.has("ruleset_version"),"legacy fixture unchanged")
	check(profile.ruleset_version == 2 and profile.scale_version == 10 and not profile.has("numerical_migration"),"native version, no fabricated migration")
	check(profile.equipment.size() == 12 and profile.permanent_gold == 0,"six original templates per legal type, unchanged wallet")
	for hero: String in Store.HERO_IDS:
		var loadout: Dictionary = profile.loadout_presets[hero]
		check(loadout.size() == 8 and loadout.legs == "" and loadout.ring == "","new slots empty")
		for id: String in loadout.values():
			if id.is_empty(): continue
			var item: Dictionary = profile.equipment[id]
			check(Instances.can_equip(item,hero,1) and not item.has("legacy_equip_waiver"),"legal native starter without waiver")
			check(item.enhancement_rank == 0 and item.enhancement_gold_ledger.is_empty() and item.material_ledger.is_empty(),"free starter has no fake paid history")
	check(profile.loadout_presets.CH01 == profile.loadout_presets.CH02 and profile.loadout_presets.CH01 != profile.loadout_presets.CH03,"physical presets share identity, magic compatible")
	var document := {"schema_version":3,"revision":1,"profile_initialized":true,"profile":profile,"active_run":null}
	check(Store._valid_document(document),"production schema accepts native profile")
	check(Store._valid_document(JSON.parse_string(JSON.stringify(document))),"JSON reload preserves schema")
	print("Native numerical profile: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
