extends RefCounted
var host: Node2D
func configure(value: Node2D) -> void:
	host = value
	host.required_count = 0
	host.completed_count = 0
	host.finished = true
	for gate: Dictionary in host.layout.get("b06_geometry",{}).get("gates",[]):
		var at := preload("res://scripts/levels/b06/world/room_geometry.gd").world_point(gate.position)
		host.add_element(str(gate.id),at,"排水闸","utility","",{"interactive":true,"required":false,"repeatable":true,"description":"操作0.6秒排水8秒，冷却16秒；受击或离开取消"})
	var definition: Dictionary = host.layout.get("b06_geometry",{})
	if definition.has("tide_bell"):
		var at := preload("res://scripts/levels/b06/world/room_geometry.gd").world_point(definition.tide_bell)
		host.add_element("tide_bell",at,"潮钟","utility","",{"interactive":true,"required":false,"repeatable":true,"description":"提前显示下一轮固定潮线方向"})
func tick(_delta: float) -> void: pass
func interact(id: String, actor: Node2D) -> bool:
	if id == "tide_bell": return is_instance_valid(host.room.b06_mechanics) and host.room.b06_mechanics.reveal_next_tide(actor,func(): return Game.run != null and Game.run.hp > 0.0,host.room.has_line_of_sight)
	return is_instance_valid(host.room.b06_mechanics) and host.room.b06_mechanics.interact(id,actor,"player",func(): return Game.run != null and Game.run.hp > 0.0,host.room.has_line_of_sight)
func status_text() -> String: return "潮汐：退潮8秒→预告2秒→高潮6秒。干桥与排水闸始终可达。"
func status_text_en() -> String: return "Tide: low 8s, warning 2s, high 6s. Dry bridges and gates remain reachable."
func encounter_directive(_index: int) -> Dictionary: return {}
func blocks_dash() -> bool: return false
