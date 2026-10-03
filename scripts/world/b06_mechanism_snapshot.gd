extends RefCounted
## Optional versioned payload for the existing safe-boundary save contract.
## It contains no player/hostile actor positions, attacks or projectiles.
const Runtime = preload("res://scripts/world/b06_tide_runtime.gd")
static func capture(room: Node) -> Dictionary:
	var host: Variant = room.get("b06_mechanics")
	if not host is Object or not host.has_method("checkpoint"): return {}
	var result := {"version":1,"room_id":str(room.get("layout_id")),"difficulty":int(room.get("difficulty")),"mechanisms":host.checkpoint()}
	return result if validate_checkpoint(result) else {}
static func validate_checkpoint(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=4 or not value.has_all(["version","room_id","difficulty","mechanisms"]): return false
	if value.version!=1 or not value.room_id is String or not value.mechanisms is Dictionary: return false
	if not value.difficulty is int and not value.difficulty is float: return false
	if not is_finite(float(value.difficulty)) or value.difficulty!=int(value.difficulty) or int(value.difficulty)<0 or int(value.difficulty)>4: return false
	var probe := Runtime.new()
	var accepted := probe.configure(value.room_id,int(value.difficulty)) and probe.restore_checkpoint(value.mechanisms)
	probe.free()
	return accepted
static func restore(room: Node, value: Dictionary) -> bool:
	if not validate_checkpoint(value) or value.room_id!=str(room.get("layout_id")) or value.difficulty!=int(room.get("difficulty")): return false
	var host: Variant = room.get("b06_mechanics")
	return host is Object and host.has_method("restore_checkpoint") and bool(host.restore_checkpoint(value.mechanisms))
