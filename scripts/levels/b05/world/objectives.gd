extends RefCounted
## Counterplay is optional for ordinary clear credit; enemies remain the gate.
var host: Node2D
func configure(value: Node2D) -> void:
	host = value
	host.required_count = 0
	host.completed_count = 0
	host.finished = true
	var definition: Dictionary = host.layout.get("b05_geometry",{})
	for gate: Dictionary in definition.get("gates",[]):
		var at := preload("res://scripts/levels/b05/world/room_geometry.gd").world_point(gate.position)
		host.add_element(str(gate.id),at,"根系水闸","utility","",{"interactive":true,"required":false,"repeatable":true,"description":"持续操作0.6秒关闭根井并开放藤桥；受击或离开会取消"})
func tick(_delta: float) -> void:
	pass
func interact(id: String, actor: Node2D) -> bool:
	if not is_instance_valid(host.room.b05_mechanics): return false
	return host.room.b05_mechanics.interact(id,actor,"player",func(): return Game.run != null and Game.run.hp > 0.0,host.room.has_line_of_sight)
func status_text() -> String:
	return "根井：范围220内刷新12%护盾，每12秒一次。拆井断网；植物与根井均可直接攻击。"
func status_text_en() -> String:
	return "Root wells: 12% shield within 220, at most once per 12s. Break wells to disconnect roots; all classes can attack them."
func encounter_directive(_index: int) -> Dictionary:
	return {}
func blocks_dash() -> bool:
	return false
