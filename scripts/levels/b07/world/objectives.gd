extends RefCounted
var host: Node2D
func configure(value: Node2D) -> void:
	host = value
	host.required_count = 0
	host.completed_count = 0
	host.finished = true
	var definition: Dictionary = host.layout.get("b07_geometry",{})
	for mirror: Dictionary in definition.get("mirrors",[]):
		var at := preload("res://scripts/levels/b07/world/room_geometry.gd").world_point(mirror.position)
		host.add_element(str(mirror.id),at,"三态引光镜","utility","",{"interactive":true,"required":false,"repeatable":true,"description":"F操作0.6秒转向；青虚线为下一方向，金线显形/压坛，不伤玩家"})
	for gate: Dictionary in definition.get("manual_gates",[]):
		var at := preload("res://scripts/levels/b07/world/room_geometry.gd").world_point(gate.position)
		host.add_element(str(gate.id),at,"手动开闸","utility","",{"interactive":true,"required":false,"repeatable":true,"description":"战斗结束后直接开闸，镜态不会造成软锁"})
func tick(_delta: float) -> void: pass
func interact(id: String, actor: Node2D) -> bool:
	return is_instance_valid(host.room.b07_mechanics) and host.room.b07_mechanics.interact(id,actor)
func status_text() -> String: return "金色镜光显形/压坛；青虚线预览下一态。战后可手动开闸。"
func status_text_en() -> String: return "Gold mirror light reveals or suppresses. Teal dashes preview rotation. Gates open manually after combat."
func encounter_directive(_index: int) -> Dictionary: return {}
func blocks_dash() -> bool: return false
