class_name HeroPassives
extends RefCounted
## Compatibility adapter. The role kit owns state and confirmed originals.
var owner_player: Node2D
var _capture_serial: int = 0
var _restored_serial: int = 0

func configure(player: Node2D) -> void:
	owner_player = player

func reset() -> void:
	pass

func tick(_delta: float) -> void:
	pass

func before_hit(_target: Node2D, amount: float, _source: StringName, _context: Dictionary) -> float:
	return amount

func record_hit(target: Node2D, source: StringName, context: Dictionary) -> void:
	if not is_instance_valid(owner_player) or owner_player.role_kit == null: return
	if int(context.get("proc_depth", 0)) != 0 or not bool(context.get("equipment_eligible", false)): return
	if source == &"primary" and not bool(context.get("original_basic", false)): return
	if float(context.get("hp_damage", 0.0)) + float(context.get("shield_damage", 0.0)) <= 0.0: return
	owner_player.role_kit.on_original_hit(target, context, {"confirmed":true, "hp_damage":float(context.get("hp_damage", 0.0)), "shield_damage":float(context.get("shield_damage", 0.0))})

func skill_committed(_slot: String, _cast_id: int) -> void:
	# Cooperation/mastery starts at first actual release, never at payment.
	pass

func snapshot() -> Dictionary:
	if not is_instance_valid(owner_player) or owner_player.role_kit == null: return {}
	var result: Dictionary = owner_player.role_kit.hud_state().duplicate(true)
	result["current"] = int(result.get("star_stacks", result.get("starlight", result.get("empowered_rounds", 0))))
	result["max"] = 3
	result["icd"] = float(result.get("rearm_remaining", 0.0))
	result["cooldown"] = float(result.get("icd", 0.0))
	result["name"] = str(result.get("name", "怒气狂战" if owner_player.hero_id() == "CH01" else "机动装填" if owner_player.hero_id() == "CH02" else "星辉协奏"))
	result["hint"] = str(result.get("hint", result.name))
	return result

func capture_same_room() -> Dictionary:
	if not is_instance_valid(owner_player) or owner_player.role_kit == null or Game.run == null: return {}
	_capture_serial += 1
	return {"source":weakref(self), "owner":weakref(owner_player), "room":weakref(owner_player.room), "serial":_capture_serial, "run_id":str(Game.run.id), "role_state":owner_player.export_role_state()}

func restore_same_room(state: Dictionary) -> bool:
	if not is_instance_valid(owner_player) or Game.run == null: return false
	for key: String in ["source", "owner", "room"]:
		if not state.get(key) is WeakRef: return false
	if state.source.get_ref() != self or state.owner.get_ref() != owner_player or state.room.get_ref() != owner_player.room or str(state.get("run_id", "")) != str(Game.run.id): return false
	var serial: int = int(state.get("serial", -1))
	if serial != _capture_serial or serial <= _restored_serial or not state.get("role_state") is Dictionary: return false
	owner_player.restore_role_state(state.role_state)
	_restored_serial = serial
	return true
