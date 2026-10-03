extends RefCounted
## Versioned safe-boundary mirror payload. No active hostile save promise.
const State = preload("res://scripts/world/b07_sun_state.gd")
const Geometry = preload("res://scripts/world/b07_room_geometry.gd")
const Numbers = preload("res://scripts/combat/b07_enemy_numbers.gd")
const Calibration = preload("res://scripts/combat/enemy_calibration.gd")
static func capture(room: Node) -> Dictionary:
	var host: Variant = room.get("b07_mechanics")
	if not is_instance_valid(host): return {}
	var result := {"version":1,"room_id":str(room.get("layout_id")),"difficulty":int(room.get("difficulty")),"calibration":room.enemy_calibration(),"mechanisms":host.checkpoint()}
	return result if validate_checkpoint(result) else {}
static func validate_checkpoint(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=5 or not value.has_all(["version","room_id","difficulty","calibration","mechanisms"]): return false
	if value.version!=1 or not value.room_id is String or not value.mechanisms is Dictionary or not Calibration.valid(value.calibration): return false
	if not (value.difficulty is int or value.difficulty is float) or not is_finite(float(value.difficulty)) or value.difficulty != int(value.difficulty) or value.difficulty < 0 or value.difficulty > 4: return false
	var definition := Geometry.room(value.room_id)
	if definition.is_empty(): return false
	var hp := 0.0
	if value.room_id == "BO07":
		var boss := Numbers.boss(int(value.difficulty),value.calibration)
		if boss.is_empty(): return false
		hp = float(boss.max_hp)
	var probe := State.new()
	return probe.configure(value.room_id,definition.mirrors,definition.altar.id,int(definition.required_mirrors),hp) and probe.restore(value.mechanisms)
static func restore(room: Node, value: Dictionary) -> bool:
	if not validate_checkpoint(value) or value.room_id != room.get("layout_id") or value.difficulty != room.get("difficulty") or value.calibration != room.enemy_calibration(): return false
	var host: Variant = room.get("b07_mechanics")
	return is_instance_valid(host) and host.restore_checkpoint(value.mechanisms)
