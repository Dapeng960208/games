extends SceneTree
const Geometry = preload("res://scripts/levels/b06/world/room_geometry.gd")
const Content = preload("res://scripts/levels/b06/world/content.gd")
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	for id: String in Content.room_ids():
		var definition := Geometry.room(id)
		check(not definition.is_empty(),id + " geometry")
		check(Geometry.validate(id).is_empty(),id + " corridors " + str(Geometry.validate(id)))
		check(Geometry.patch_at(id,Geometry.world_point(definition.entry)).is_empty(),id + " dry entry")
		check(Geometry.patch_at(id,Geometry.world_point(definition.exit)).is_empty(),id + " dry exit")
		for gate: Dictionary in definition.gates:
			check(Geometry.patch_at(id,Geometry.world_point(gate.position)).is_empty(),id + " dry gate")
			check(definition.shallow_patches.any(func(p: Dictionary) -> bool: return p.id == gate.patch_id),id + " linked gate")
	check(Geometry.room("L30").is_empty(),"no B05 geometry override")
	for failure in failures: printerr(failure)
	print("B06 room geometry: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
