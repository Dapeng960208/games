extends Node
const Fixtures = preload("res://tests/persistence/test_numerical_instance_storage.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func item(id: String, level: int, rarity: String = "white") -> Dictionary:
	return Acquisition.roll_item({"instance_id":id,"source_event_id":"test:s06:"+id,"template_id":"EQ03","item_level":level,"rarity":rarity,"power_type":"physical","source":"purchase" if rarity == "white" else "craft"},1764)
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	if not Game.profile_path.contains("test_numerical_forging_lifecycle"):
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"isolated new profile")
	var profile: Dictionary = Fixtures.fixture_profile()
	profile.hero_xp.CH01 = 3600
	profile.permanent_gold = 1000000
	profile.materials = {"forge":10000,"race:B01":10000,"race:B02":10000,"race:B03":10000,"race:B04":10000,"core:B01":1000,"core:B02":1000,"core:B03":1000,"core:B04":1000}
	profile.equipment["low-source"] = item("low-source",1)
	profile.equipment["high-target"] = item("high-target",20,"gold")
	profile.equipment["overflow"] = item("overflow",20)
	profile.equipment.overflow.location = "pending"
	var fixture_ok: bool = Game._commit_profile(profile)
	check(fixture_ok,"save forge fixture: "+Game.last_error)
	if not fixture_ok:
		_finish()
		return
	var before: Dictionary = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	var failed := Game.forge_equipment_v2("enhance",{"instance_id":"low-source"},"actual:enhance:1")
	check(not failed.ok and Game.profile == before,"failed enhancement save leaves wallet/rank/history unchanged")
	check(Game.pending_forging_v2().get("operation_id", "") == "actual:enhance:1","failed transaction exposed for reopened UI retry")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	check(Game.upgrade_equipment("low-source","actual:enhance:1"),"actual upgrade bridge commits retry")
	check(Game.profile.equipment["low-source"].enhancement_rank == 1 and Game.profile.permanent_gold == int(before.permanent_gold)-40,"one charge one rank")
	var committed: Dictionary = Game.profile.duplicate(true)
	check(Game.upgrade_equipment("low-source","actual:enhance:1") and Game.profile == committed,"same operation retry survives changed current revision")
	check(Game.pending_forging_v2().is_empty(),"successful write clears unpaid retry cache")
	for rank in range(2,11): check(Game.upgrade_equipment("low-source","actual:enhance:"+str(rank)),"real rank "+str(rank))
	check(Game.profile.permanent_gold == int(before.permanent_gold)-2500,"Lv1 ten actual rank charges exact")
	var inheritance := Game.quote_forging_v2("inherit",{"source_instance_id":"low-source","target_instance_id":"high-target"})
	check(inheritance.ok and inheritance.gold == 1530,"actual inheritance quote includes all canonical base differences")
	var move := Game.forge_equipment_v2("inherit",{"source_instance_id":"low-source","target_instance_id":"high-target"},"actual:inherit")
	check(move.ok and Game.profile.equipment["low-source"].enhancement_rank == 0 and Game.profile.equipment["high-target"].enhancement_rank == 10,"actual inheritance transfers without consuming source identity")
	Game.reload_profile()
	check(Game.profile.equipment["low-source"].enhancement_rank == 0 and Game.profile.equipment["high-target"].enhancement_rank == 10,"disk reload never restores consumed rank")
	check(Game.set_equipment_lock_v2("high-target",true),"lock persists")
	check(not Game.forge_equipment_v2("sell",{"instance_id":"high-target"},"actual:blocked-sale").ok,"locked recycling blocked")
	check(Game.set_equipment_lock_v2("high-target",false),"unlock persists")
	var old_affixes: Array = Game.profile.equipment["high-target"].affix_type_and_quantile.duplicate(true)
	var request := {"instance_id":"high-target","affix_index":0,"affix_type":str(old_affixes[0].type)}
	before = Game.profile.duplicate(true)
	var paid := Game.forge_equipment_v2("reforge",request,"actual:reforge")
	check(paid.ok and Game.profile.equipment["high-target"].has("pending_reforge"),"paid affix proposal persists before choice")
	if not paid.ok:
		failures.append(str(paid))
		_finish()
		return
	var pending: Dictionary = Game.profile.equipment["high-target"].pending_reforge.duplicate(true)
	var gold_after: int = int(Game.profile.permanent_gold)
	check(Game.profile.equipment["high-target"].affix_type_and_quantile == old_affixes,"paid preview does not silently replace old affix")
	Game.reload_profile()
	check(Acquisition._canonical(Game.profile.equipment["high-target"].pending_reforge.new_affix) == Acquisition._canonical(pending.new_affix),"pending candidate survives reopen/reload")
	check(not Game.forge_equipment_v2("refine",{"instance_id":"high-target","affix_index":0},"actual:blocked-refine").ok,"unfinished paid choice blocks another mutation")
	check(Game.resolve_reforge_v2("high-target","keep","actual:keep").ok,"keep old completes paid choice")
	check(Game.profile.equipment["high-target"].affix_type_and_quantile == old_affixes and Game.profile.permanent_gold == gold_after,"keeping old has no second fee or refund")
	check(Game.profile.equipment["high-target"].reforge_slot == 0,"permanent bound affix slot survives keeping old")
	check(not Game.forge_equipment_v2("reforge",{"instance_id":"high-target","affix_index":1,"affix_type":str(old_affixes[1].type)},"actual:other-slot").ok,"cannot bind second affix slot")
	var refine_index := -1
	for index in old_affixes.size():
		if int(old_affixes[index].u) < 100: refine_index = index; break
	if refine_index >= 0:
		var k: Dictionary = Game.profile.equipment["high-target"].main_rolls.duplicate(true)
		check(Game.forge_equipment_v2("refine",{"instance_id":"high-target","affix_index":refine_index},"actual:refine").ok,"actual refine commits")
		check(Game.profile.equipment["high-target"].affix_type_and_quantile[refine_index].u == mini(100,int(old_affixes[refine_index].u)+10) and Game.profile.equipment["high-target"].main_rolls == k,"refine only raises selected u")
	check(Game.claim_pending_equipment("overflow","actual:claim"),"claim overflow-owned record")
	check(Game.forge_equipment_v2("dismantle",{"instance_id":"overflow"},"actual:dismantle").ok,"formerly claimed pending item can be retired")
	Game.reload_profile()
	check(not Game.profile.equipment.has("overflow") and Game.profile.pending_claim_receipts["actual:claim"] == "overflow","retired claim tombstone survives full validation/reload")
	committed = Game.profile.duplicate(true)
	check(Game.forge_equipment_v2("dismantle",{"instance_id":"overflow"},"actual:dismantle").ok and Game.profile == committed,"retired instance replay returns prior receipt no second refund")
	check(not Game.forge_equipment_v2("sell",{"instance_id":"overflow"},"actual:sell-after-dismantle").ok,"sell and dismantle mutually exclusive")
	var malformed: Dictionary = Fixtures.document(Game.profile.duplicate(true))
	malformed.profile.pending_claim_receipts["fake:retired"] = "never-owned"
	check(not ProfileStore._valid_document(malformed),"claim tombstone requires proven retirement")
	before = Game.profile.duplicate(true)
	Game._store.max_document_bytes = 1
	check(not Game.forge_equipment_v2("enhance",{"instance_id":"low-source"},"actual:cancel").ok,"failed unpaid candidate can be canceled")
	check(Game.cancel_pending_forging_v2("actual:cancel") and Game.profile == before and Game.pending_forging_v2().is_empty(),"cancel changes no equipment or currencies")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	Game._store.max_document_bytes = 1
	check(not Game.forge_equipment_v2("enhance",{"instance_id":"low-source"},"actual:context").ok,"freeze failed operation before cross-page equip")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	var equipped_ok := Game.equip_item("low-source")
	check(equipped_ok,"another camp page can equip without forging")
	var wallet_before: int = int(Game.profile.permanent_gold)
	var conflict := Game.forge_equipment_v2("enhance",{"instance_id":"low-source"},"actual:context")
	check(not conflict.ok and conflict.error == "OPERATION_CONFLICT" and Game.profile.permanent_gold == wallet_before and Game.profile.equipment["low-source"].enhancement_rank == 0,"incidental item change rejects cached candidate instead of rerolling same ID")
	check(Game.cancel_pending_forging_v2("actual:context"),"unpaid conflicted operation can be canceled")
	_level_gates()
	_finish()

func _level_gates() -> void:
	for kind: String in ["reforge","refine"]:
		var unlock := 5 if kind == "reforge" else 10
		for level in [unlock-1,unlock]:
			check(Game.new_profile(),"gate isolated reset")
			var fixture: Dictionary = Fixtures.fixture_profile()
			fixture.hero_xp.CH01 = preload("res://scripts/domain/progression/hero_progression.gd").thresholds()[level-1]
			fixture.permanent_gold = 10000
			fixture.materials = {"forge":100,"race:B01":100}
			fixture.equipment["gate-item"] = item("gate-item",1,"gold")
			fixture.equipment["gate-item"].affix_type_and_quantile[0].u = 40
			check(Game._commit_profile(fixture),"save gate fixture")
			var request := {"instance_id":"gate-item","affix_index":0}
			if kind == "reforge": request["affix_type"] = fixture.equipment["gate-item"].affix_type_and_quantile[0].type
			var allowed: bool = level == unlock
			var before: Dictionary = Game.profile.duplicate(true)
			check(bool(Game.quote_forging_v2(kind,request).ok) == allowed,kind+" authoritative quote level "+str(level))
			var result := Game.forge_equipment_v2(kind,request,"gate:"+kind+":"+str(level))
			check(bool(result.ok) == allowed,kind+" actual Game level "+str(level))
			if not allowed: check(Game.profile == before,kind+" locked operation never charges")

func _finish() -> void:
	print("Numerical forging lifecycle: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
