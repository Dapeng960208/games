extends RefCounted
var host: Node2D
func configure(value: Node2D) -> void:
	host=value
	host.required_count=0
	host.completed_count=0
	host.finished=true
	for id: String in host.room.b09_mechanics.lamps:
		host.add_element(id,host.room.b09_mechanics.lamps[id].at,"暖灯","utility","",{"interactive":true,"required":false,"repeatable":true,"description":"引导0.6秒：160范围除冰8秒、破一层晶面，冷却16秒"})
func tick(_delta: float) -> void: pass
func interact(id: String, actor: Node2D) -> bool: return host.room.b09_mechanics.interact(id,actor)
func status_text() -> String: return "粗雪停止滑行；暖灯破晶面；裂桥预告2秒，单侧关闭4秒。"
func status_text_en() -> String: return "Snow stops gliding. Lanterns break crystal plates. Bridges warn 2s, close one side for 4s."
func encounter_directive(_index: int) -> Dictionary: return {}
func blocks_dash() -> bool: return false
