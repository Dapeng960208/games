extends RefCounted
## B03 machinery objectives. All damage and obstruction changes go through host.
const DRONE := "B03_wrecked_drone"
const POWER := "B03_transformer"
const PIPE := "B03_pipe_manifold"
var host
var _finished := false
var _carried := ""
var _order: Array[int] = []
var _clock := 0.0
var _rail_timer := 3.0
var _pulse_timer := 4.0
var _pulse_locked := false
var _pulse_count := 0
var _selected_reactor := -1
var _reactor_index := 0
var _steam_timer := 3.0
var _cargo_selected := 0
var _cargo_serial := 0
var _cargo_id := ""
var _cargo_phase := "flying"
var _cargo_fall := 0.0
var _cargo_landing := -1
var _cargo_passes := 0

func configure(next_host) -> void:
	host = next_host
	_finished = false
	_carried = ""
	_order.clear()
	_clock = 0.0
	_rail_timer = 3.0
	_pulse_timer = 4.0
	_pulse_locked = false
	_pulse_count = 0
	_selected_reactor = -1
	_reactor_index = 0
	_steam_timer = 3.0
	_cargo_selected = 0
	_cargo_serial = 0
	_cargo_passes = 0
	match str(host.room_id):
		"L13": _configure_arms()
		"L14": _configure_lights()
		"L15": _configure_magnets()
		"L16": _configure_reactors()
		"L17": _configure_conveyors()
		"L18": _configure_cargo()

func tick(delta: float) -> void:
	if delta <= 0.0 or _finished:
		return
	# Small steps keep pulse and landing warnings honest after a slow frame.
	var remaining := delta
	while remaining > 0.0001 and not _finished:
		var step := minf(remaining, .1)
		_clock += step
		_tick(step)
		remaining -= step

func _tick(delta: float) -> void:
	if not _carried.is_empty() and is_instance_valid(host.player()):
		host.element(_carried).position = host.player().position + Vector2(0, -28)
	match str(host.room_id):
		"L13": _tick_arms(delta)
		"L14": _tick_lights(delta)
		"L15": _tick_magnets(delta)
		"L16": _tick_reactors(delta)
		"L17": _tick_conveyors(delta)
		"L18": _tick_cargo(delta)

func interact(id: String, actor: Node2D) -> bool:
	var item: Dictionary = host.element(id)
	if _finished or item.is_empty() or not is_instance_valid(actor) or not bool(item.get("active", true)) or not bool(item.get("interactive", true)) or actor.position.distance_to(item.get("interaction_position", item.position)) > 100.0:
		return false
	if bool(item.get("done", false)) and not bool(item.get("repeatable", false)):
		return false
	match str(host.room_id):
		"L13":
			if str(item.kind) != "docking_arm": return false
			item.phase = "修复中" if bool(item.get("offline", false)) else "校准中"
			item["working"] = true
			host.message = "守住联轴器；离开会暂停，敌人只能打退当前刻度"
			return true
		"L14": return _interact_light(id, item)
		"L15":
			if str(item.kind) != "magnet_control": return false
			if _pulse_locked:
				host.message = "箭头已锁定；本次脉冲结束后可切换"
				return false
			var cart: Dictionary = host.element("cart_%d" % int(item.index))
			if bool(cart.done): return false
			cart.polarity = -int(cart.polarity)
			_update_magnet_label(cart)
			return true
		"L16": return _interact_reactor(item)
		"L17": return _interact_conveyor(id, item)
		"L18": return _interact_cargo(id, item)
	return false

func blocks_dash() -> bool:
	return false

func navigation_target() -> Dictionary:
	if _finished: return {}
	var ids: Array[String] = []
	match str(host.room_id):
		"L13":
			ids.assign(["arm_0", "arm_1"])
		"L14":
			for index in 3: ids.append(("battery_%d" if _carried.is_empty() else "lamp_%d") % index)
		"L15":
			for index in 2:
				if not bool(host.element("cart_%d" % index).done): ids.append("magnet_%d" % index)
		"L16":
			if _reactor_index < 3:
				var reactor: Dictionary = host.element("reactor_%d" % _reactor_index)
				ids.append(("reactor_%d" if bool(reactor.offline) or _selected_reactor == _reactor_index else "valve_%d") % _reactor_index)
		"L17":
			if not _carried.is_empty(): ids.append("assembly_table")
			else:
				for index in 3: ids.append("part_%d" % index)
		"L18":
			if _cargo_phase == "landed":
				var landing: Dictionary = host.element("landing_%d" % _cargo_landing)
				return {"position": landing.get("interaction_position", landing.position), "title": "回收已落地货舱"}
			ids.append("crane_console")
	var closest: Dictionary = {}
	var distance := INF
	var actor: Node2D = host.player()
	for id in ids:
		var item: Dictionary = host.element(id)
		if item.is_empty() or bool(item.get("done", false)) or not bool(item.get("active", true)): continue
		var at: Vector2 = item.get("interaction_position", item.position)
		var next_distance: float = actor.position.distance_to(at) if is_instance_valid(actor) else 0.0
		if next_distance < distance:
			distance = next_distance
			closest = {"position": at, "title": str(item.label)}
	return closest

func status_text() -> String:
	var count := int(host.completed_count)
	match str(host.room_id):
		"L13": return "校准两条对接臂 %d/2 · E启动后守住三道刻度；损坏只退当前刻度" % count
		"L14": return "搬运电池点亮应急灯 %d/3 · %s · 点灯顺序改变货轨与来敌方向" % [count, "携带电池，前往未亮灯" if not _carried.is_empty() else "E拾取电池，一次携带一块"]
		"L15": return "磁力引导维修车 %d/2 · E切换吸/排；%.1f秒后脉冲，箭头锁定后走绝缘外圈" % [count, maxf(0, _pulse_timer)]
		"L16": return "依序冷却反应罐 %d/3 · 阀门导冷雾至%d号罐；过热后E修复重试" % [count, mini(3, _reactor_index + 1)]
		"L17": return "原型部件交付 %d/3 · %s · E旋转薄掩体切换挡弹方向" % [count, "携带部件，送往中央装配台" if not _carried.is_empty() else "从移动传送带拾取部件"]
		"L18": return "货舱回收 %d/3 · 控制台选择%d号拦截位，或普攻射落；落地预警后E回收" % [count, _cargo_selected + 1]
	return ""

func on_target_hit(_id: String, _context: Dictionary) -> void:
	pass

func on_target_destroyed(id: String) -> void:
	if str(host.room_id) == "L17" and id.begins_with("part_"):
		var part: Dictionary = host.element(id)
		part["destroyed"] = false
		part["attackable"] = false
		part["broken"] = true
		part.phase = "破损部件 · 仍可交付"
		host.quality = "repaired"
		return
	if str(host.room_id) == "L18" and id == _cargo_id and _cargo_phase == "flying":
		var closest := -1
		var distance := INF
		for index in 3:
			var landing: Dictionary = host.element("landing_%d" % index)
			if bool(landing.get("captured", false)): continue
			var current: float = Vector2(landing.position).distance_to(host.element(id).position)
			if current < distance:
				distance = current
				closest = index
		if closest >= 0: _begin_fall(closest, "shot")

func _finish_if(count: int) -> void:
	if int(host.completed_count) >= count:
		_finished = true
		host.finish(str(host.quality))

func _control(index: int, fallback: Vector2) -> Vector2:
	var found := 0
	for item: Dictionary in host.layout.get("interactables", []):
		if "control" in str(item.get("id", "")):
			if found == index: return item.get("position", fallback)
			found += 1
	return fallback

func _interaction_side(at: Vector2) -> Vector2:
	for offset: Vector2 in [Vector2(0, 90), Vector2(90, 0), Vector2(0, -90), Vector2(-90, 0)]:
		var candidate: Vector2 = at + offset
		if Vector2(host.safe_point(candidate, 24)).is_equal_approx(candidate): return candidate
	return host.safe_point(at + Vector2(0, 90), 18)

func _configure_arms() -> void:
	for index in 2:
		var item: Dictionary = host.add_element("arm_%d" % index, host.point(index), "对接臂%d · E校准" % (index + 1), "docking_arm", PIPE, {"steps": 0, "partial": 0.0, "working": false, "offline": false, "damage_count": 0, "damage_cooldown": 0.0, "repair": 0.0, "phase": "待校准", "rotation": -.35})
		# Close the two short authored bridge crossings; crossing C stays open.
		var gate := Vector2(1154.05 if index == 0 else 1768.92, 708.2)
		for marker: Dictionary in host.layout.get("visual_markers", []):
			if str(marker.get("kind", "")) == ("fixed_connection_a" if index == 0 else "fixed_connection_b"):
				gate = marker.position
		item["gate"] = gate
		host.add_element("bridge_%d" % index, gate, "臂%d联轴器" % (index + 1), "bridge_coupler", PIPE, {"required": false, "interactive": false, "visual_height": 58.0, "phase": "桥口关闭"})
		host.set_blocker("arm_gate_%d" % index, Rect2(gate - Vector2(90, 10), Vector2(180, 20)), true)

func _tick_arms(delta: float) -> void:
	for index in 2:
		var item: Dictionary = host.element("arm_%d" % index)
		if bool(item.done): continue
		item.damage_cooldown = maxf(0, float(item.damage_cooldown) - delta)
		if not bool(item.working) or not host.near(item.position, 125): continue
		if bool(item.offline):
			item.repair = float(item.repair) + delta
			item.phase = "修复 %.1f/2秒" % float(item.repair)
			if float(item.repair) >= 2.0:
				item.offline = false
				item.damage_count = 0
				item.repair = 0.0
				item.working = false
				item.phase = "已修复 · E继续"
			continue
		if not host.enemies_near(item.position, 98).is_empty() and float(item.damage_cooldown) <= 0:
			item.partial = 0.0
			item.damage_count = int(item.damage_count) + 1
			item.damage_cooldown = 1.8
			item.phase = "当前刻度受损"
			host.event("arm_step_damaged", {"index": index, "preserved_steps": int(item.steps)})
			if int(item.damage_count) >= 3:
				item.offline = true
				item.working = false
				item.phase = "联轴器停机 · E修复"
				host.quality = "repaired"
			continue
		item.partial = float(item.partial) + delta
		if float(item.partial) >= 3.0:
			item.steps = int(item.steps) + 1
			item.partial = 0.0
			item.rotation = -.35 + float(item.steps) * .35
			host.event("arm_calibration_step", {"index": index, "step": int(item.steps)})
		item.progress = (float(item.steps) + float(item.partial) / 3.0) / 3.0
		item.phase = "刻度%d/3" % int(item.steps)
		if int(item.steps) >= 3:
			host.set_done(str(item.id))
			host.remove_blocker("arm_gate_%d" % index)
			host.element("bridge_%d" % index).phase = "桥口开放"
			host.element("bridge_%d" % index).done = true
			item.phase = "对接通行"
			host.event("arm_calibrated", {"index": index, "position": item.position, "angle": item.rotation})
	_finish_if(2)

func _configure_lights() -> void:
	host.ambient_darkness = .42
	host.event("lighting_changed", {"ambient_darkness": .42, "preserve_combat_visibility": true})
	for index in 3:
		host.add_element("lamp_%d" % index, host.point(index), "应急灯%d · 需要电池" % (index + 1), "emergency_lamp", POWER, {"index": index, "phase": "断电"})
		host.add_element("battery_%d" % index, host.safe_point(host.point(index) + Vector2(-175, 120)), "便携电池 · E搬运", "battery", POWER, {"required": false, "visual_height": 52.0, "carried": false})

func _interact_light(id: String, item: Dictionary) -> bool:
	if str(item.kind) == "battery":
		if not _carried.is_empty():
			host.message = "一次只能搬一块电池"
			return false
		_carried = id
		item.carried = true
		item.interactive = false
		return true
	if str(item.kind) != "emergency_lamp": return false
	if _carried.is_empty():
		host.message = "需要先从地面搬来一块电池"
		return false
	host.element(_carried).active = false
	_carried = ""
	host.set_done(id)
	item.phase = "供电中"
	_order.append(int(item.index))
	var direction: Vector2 = Vector2(host.layout.get("entry", Vector2.ZERO)).direction_to(item.position)
	if _order.size() > 1:
		direction = Vector2(host.point(_order[_order.size() - 2])).direction_to(item.position)
	host.event("light_powered", {"index": int(item.index), "position": item.position, "order": _order.duplicate(), "ambient_darkness": maxf(0, .42 - .14 * _order.size()), "encounter_direction": direction, "rail_index": int(item.index), "preserve_combat_visibility": true})
	_finish_if(3)
	return true

func _tick_lights(delta: float) -> void:
	_rail_timer -= delta
	if _rail_timer > 0 or _order.is_empty(): return
	_rail_timer = 4.5
	var zones: Array = host.layout.get("hazard_zones", [])
	for index in _order:
		if index >= zones.size(): continue
		var rect: Rect2 = zones[index].get("rect", Rect2(host.point(index), Vector2(100, 125)))
		var start := rect.get_center() - Vector2(0, rect.size.y * .5)
		host.add_hazard(start, 25, 7, 1.1, .25, {"shape": "line", "target": start + Vector2(0, rect.size.y), "width": 44.0, "enemies": true})

func _configure_magnets() -> void:
	for index in 2:
		var rail: Vector2 = host.point(index)
		host.add_element("rail_%d" % index, rail, "维修导轨%d" % (index + 1), "rail", PIPE, {"required": false, "interactive": false})
		var start: Vector2 = host.safe_point(rail + Vector2(-190 if index == 0 else 190, -205 if index == 0 else 205))
		var cart: Dictionary = host.add_element("cart_%d" % index, start, "维修车%d" % (index + 1), "magnet_cart", DRONE, {"index": index, "interactive": false, "polarity": 1, "rail": rail, "move_target": start, "start_distance": start.distance_to(rail), "locked_target": start})
		host.add_element("magnet_%d" % index, host.safe_point(rail + Vector2(110, -100)), "磁控%d · E切换" % (index + 1), "magnet_control", POWER, {"required": false, "index": index, "repeatable": true})
		_update_magnet_label(cart)

func _update_magnet_label(cart: Dictionary) -> void:
	var control: Dictionary = host.element("magnet_%d" % int(cart.index))
	if not control.is_empty(): control.phase = "下次吸入" if int(cart.polarity) > 0 else "下次排开"
	cart.phase = "吸入" if int(cart.polarity) > 0 else "排开"

func _tick_magnets(delta: float) -> void:
	_pulse_timer -= delta
	for index in 2:
		var cart: Dictionary = host.element("cart_%d" % index)
		if bool(cart.done): continue
		host.move_element(str(cart.id), cart.move_target, 112, delta)
		var distance: float = Vector2(cart.position).distance_to(cart.rail)
		cart.progress = clampf(1.0 - distance / maxf(1, float(cart.start_distance)), 0, 1)
		if distance <= 26:
			host.set_done(str(cart.id))
			cart.phase = "精确入轨"
			host.element("magnet_%d" % index).active = false
			host.event("cart_docked", {"index": index, "position": cart.position})
	if _pulse_timer <= 1.0 and not _pulse_locked:
		_pulse_locked = true
		for index in 2:
			var cart: Dictionary = host.element("cart_%d" % index)
			if bool(cart.done): continue
			var direction: Vector2 = Vector2(cart.position).direction_to(cart.rail) * int(cart.polarity)
			var distance: float = minf(98, Vector2(cart.position).distance_to(cart.rail)) if int(cart.polarity) > 0 else 65.0
			cart.locked_target = host.safe_point(cart.position + direction * distance)
			cart.beam_to = cart.locked_target
			cart.phase = "箭头锁定"
		var zones: Array = host.layout.get("hazard_zones", [])
		if not zones.is_empty():
			var rect: Rect2 = zones[_pulse_count % zones.size()].get("rect", Rect2())
			host.add_hazard(rect.get_center(), 65, 4, 1.0, .2, {"enemies": true})
	if _pulse_timer <= 0:
		for index in 2:
			var cart: Dictionary = host.element("cart_%d" % index)
			if bool(cart.done): continue
			cart.move_target = cart.locked_target
			if is_instance_valid(host.player()) and host.near(cart.position, 140):
				host.displace(host.player(), Vector2(cart.position).direction_to(cart.locked_target) * 18)
			host.event("magnet_pulse", {"index": index, "from": cart.position, "target": cart.locked_target, "polarity": int(cart.polarity)})
			cart.polarity = -int(cart.polarity)
			_update_magnet_label(cart)
		_pulse_timer = 4.0
		_pulse_locked = false
		_pulse_count += 1
	_finish_if(2)

func _configure_reactors() -> void:
	for index in 3:
		host.add_element("reactor_%d" % index, host.point(index), "反应罐%d" % (index + 1), "reactor", POWER, {"index": index, "temperature": 68.0, "stable": 0.0, "offline": false, "repairing": false, "repair": 0.0, "phase": "待冷却"})
	for index in 4:
		host.add_element("valve_%d" % index, _control(index, host.point(mini(index, 2)) + Vector2(0, 140)), "冷雾阀%d · E导流" % (index + 1), "thermal_valve", PIPE, {"index": index, "required": false, "repeatable": true, "phase": "关闭"})

func _interact_reactor(item: Dictionary) -> bool:
	if str(item.kind) == "reactor":
		if not bool(item.offline):
			host.message = "使用阀门将冷雾引向当前反应罐"
			return false
		item.repairing = true
		item.phase = "检修中 · 留在附近"
		return true
	if str(item.kind) != "thermal_valve" or _reactor_index >= 3: return false
	var index := int(item.index)
	if index != _reactor_index and index != 3:
		host.message = "先稳定%d号罐，使用对应阀或总控阀" % (_reactor_index + 1)
		return false
	var reactor: Dictionary = host.element("reactor_%d" % _reactor_index)
	if bool(reactor.offline):
		host.message = "反应罐已保护停机；先到罐旁E修复"
		return false
	_selected_reactor = _reactor_index
	for valve_index in 4:
		var valve: Dictionary = host.element("valve_%d" % valve_index)
		valve.erase("beam_to")
		valve.phase = "关闭"
	item.beam_to = reactor.position
	item.phase = "冷雾→%d号罐" % (_reactor_index + 1)
	host.event("coolant_redirected", {"index": _reactor_index, "from": item.position, "to": reactor.position, "temperature": reactor.temperature})
	return true

func _tick_reactors(delta: float) -> void:
	_steam_timer -= delta
	for index in 3:
		var reactor: Dictionary = host.element("reactor_%d" % index)
		if bool(reactor.done): continue
		if bool(reactor.offline):
			if bool(reactor.repairing) and host.near(reactor.position, 115):
				reactor.repair = float(reactor.repair) + delta
				if float(reactor.repair) >= 2.0:
					reactor.offline = false
					reactor.repairing = false
					reactor.repair = 0.0
					reactor.temperature = 62.0
					reactor.phase = "已修复 · 重新导流"
			continue
		var cooling := index == _selected_reactor
		var rate := -14.0 if cooling else (3.2 if index == _reactor_index else .55)
		if cooling and not host.enemies_near(reactor.position, 110).is_empty(): rate += 5.0
		reactor.temperature = clampf(float(reactor.temperature) + delta * rate, 18, 100)
		reactor.phase = "%.0f℃ · %s" % [float(reactor.temperature), "冷雾导入" if cooling else "升温"]
		reactor.progress = clampf((68.0 - float(reactor.temperature)) / 42.0, 0, .85)
		if float(reactor.temperature) >= 100:
			reactor.offline = true
			reactor.phase = "过热停机 · E修复"
			reactor.stable = 0.0
			if _selected_reactor == index: _selected_reactor = -1
			host.quality = "repaired"
			host.event("reactor_overheated", {"index": index})
		elif cooling and float(reactor.temperature) <= 30:
			reactor.stable = float(reactor.stable) + delta
			reactor.progress = .85 + .15 * minf(1, float(reactor.stable) / 2.0)
			if float(reactor.stable) >= 2.0:
				host.set_done(str(reactor.id))
				reactor.phase = "稳定"
				_selected_reactor = -1
				_reactor_index += 1
				host.event("reactor_stabilized", {"index": index})
		if not bool(reactor.done) and float(reactor.temperature) >= 85 and _steam_timer <= 0:
			host.add_hazard(reactor.position, 76, 7, 1.1, .3, {"enemies": true})
	if _steam_timer <= 0: _steam_timer = 3.5
	_finish_if(3)

func _configure_conveyors() -> void:
	var table: Vector2 = host.safe_point(host.point(1) + Vector2(128, 145), 45)
	host.add_element("assembly_table", table, "中央装配台 · E交付", "assembly_table", PIPE, {"required": false, "repeatable": true})
	var starts: Array[Vector2] = [host.point(0), Vector2(700, host.point(1).y), host.point(2)]
	var ends: Array[Vector2] = [Vector2(host.point(0).x, 1500), Vector2(2310, host.point(1).y), Vector2(510, host.point(2).y)]
	for index in 3:
		var item: Dictionary = host.add_target("part_%d" % index, starts[index], 32, DRONE, "原型部件%d · E拾取" % (index + 1), {"index": index, "start": starts[index], "end": ends[index], "toward_end": true, "carried": false, "visual_height": 64.0})
		item.kind = "conveyor_part"
		item.interactive = true
	var markers: Array = host.layout.get("visual_markers", [])
	var added := 0
	for marker: Dictionary in markers:
		if not "cover" in str(marker.get("kind", "")) and not "cover" in str(marker.get("id", "")): continue
		var at: Vector2 = host.safe_point(Vector2(marker.get("position", table)) + Vector2(0, 160), 65)
		var id := "cover_%d" % added
		var item: Dictionary = host.add_element(id, at, "旋转掩体 · E转向", "rotating_cover", PIPE, {"required": false, "repeatable": true, "vertical": false, "rotation": 0.0, "phase": "横挡"})
		item["interaction_position"] = _interaction_side(item.position)
		host.set_blocker(id, _cover_rect(item, false), true)
		added += 1
		if added >= 4: break
	# Layouts may expose marker names as tags, so keep four explicit corner controls.
	while added < 4:
		var offset := Vector2(-430 if added % 2 == 0 else 430, -290 if added < 2 else 290)
		var id := "cover_%d" % added
		var item: Dictionary = host.add_element(id, host.safe_point(host.point(1) + offset, 65), "旋转掩体 · E转向", "rotating_cover", PIPE, {"required": false, "repeatable": true, "vertical": false, "rotation": 0.0, "phase": "横挡"})
		item["interaction_position"] = _interaction_side(item.position)
		host.set_blocker(id, _cover_rect(item, false), true)
		added += 1

func _cover_rect(item: Dictionary, vertical: bool) -> Rect2:
	var size := Vector2(18, 104) if vertical else Vector2(104, 18)
	return Rect2(Vector2(item.position) - size * .5, size)

func _interact_conveyor(id: String, item: Dictionary) -> bool:
	if str(item.kind) == "rotating_cover":
		var vertical := not bool(item.vertical)
		if not host.set_blocker(id, _cover_rect(item, vertical), true):
			host.message = "转向范围有人或路线不安全；退开一点再操作"
			return false
		item.vertical = vertical
		item.rotation = PI * .5 if vertical else 0.0
		item.phase = "竖挡" if vertical else "横挡"
		host.event("cover_rotated", {"id": id, "vertical": vertical})
		return true
	if str(item.kind) == "conveyor_part":
		if not _carried.is_empty(): return false
		_carried = id
		item.carried = true
		item.interactive = false
		item.attackable = false
		var target = item.get("target_actor")
		if is_instance_valid(target): target.queue_free()
		return true
	if str(item.kind) != "assembly_table" or _carried.is_empty(): return false
	var part: Dictionary = host.element(_carried)
	part.position = item.position + Vector2(-46 + 46 * int(part.index), -45)
	part.carried = false
	part.interactive = false
	part.phase = "已交付"
	host.set_done(_carried)
	_carried = ""
	_finish_if(3)
	return true

func _tick_conveyors(delta: float) -> void:
	for index in 3:
		var item: Dictionary = host.element("part_%d" % index)
		if bool(item.done) or bool(item.carried): continue
		var destination: Vector2 = item.end if bool(item.toward_end) else item.start
		var arrived: bool = host.move_element(str(item.id), destination, 62, delta)
		if arrived:
			item.toward_end = not bool(item.toward_end)
		item.phase = "破损 · 仍可交付" if bool(item.get("broken", false)) else "传送中 · 可拾取"

func _configure_cargo() -> void:
	for index in 3:
		# Keep each authored route anchor open after its cargo becomes a blocker.
		var landing: Vector2 = host.safe_point(host.point(index) + Vector2(0, 100), 48)
		host.add_element("landing_%d" % index, landing, "回收位%d" % (index + 1), "cargo_landing", "", {"index": index, "interactive": false, "captured": false, "phase": "等待拦截", "radius": 70.0, "interaction_position": _interaction_side(landing)})
	host.add_element("crane_console", _control(0, host.point(0) - Vector2(300, 0)), "地面吊机 · E选择拦截位", "crane_console", POWER, {"required": false, "repeatable": true, "phase": "拦截1号位"})
	_spawn_cargo()

func _spawn_cargo() -> void:
	_cargo_serial += 1
	_cargo_id = "flying_cargo_%d" % _cargo_serial
	_cargo_phase = "flying"
	_cargo_fall = 0.0
	_cargo_landing = -1
	var at := Vector2(400, host.point(0).y)
	host.add_target(_cargo_id, at, 32, DRONE, "低空货舱 · 普攻可射落", {"required": false, "visual_height": 80.0, "phase": "巡回飞行"})
	host.add_element("crane_shadow", at + Vector2(0, 58), "吊机投影", "crane_shadow", "", {"required": false, "interactive": false, "radius": 35.0})

func _interact_cargo(id: String, item: Dictionary) -> bool:
	if str(item.kind) == "crane_console":
		for offset in range(1, 4):
			var index := (_cargo_selected + offset) % 3
			if not bool(host.element("landing_%d" % index).captured):
				_cargo_selected = index
				item.phase = "拦截%d号位" % (index + 1)
				item.beam_to = host.point(index)
				return true
		return false
	if str(item.kind) != "cargo_landing" or not bool(item.captured) or str(item.phase) != "已落地 · E回收": return false
	host.set_done(id)
	item.phase = "安全掩体"
	item.interactive = false
	host.event("cargo_recovered", {"index": int(item.index), "position": item.position})
	_finish_if(3)
	if not _finished:
		for offset in range(1, 4):
			var next := (_cargo_selected + offset) % 3
			if not bool(host.element("landing_%d" % next).captured):
				_cargo_selected = next
				break
		host.element("crane_console").phase = "拦截%d号位" % (_cargo_selected + 1)
		_spawn_cargo()
	return true

func _begin_fall(index: int, source: String) -> void:
	if _cargo_phase != "flying": return
	_cargo_phase = "falling"
	_cargo_landing = index
	_cargo_fall = 1.25
	var cargo: Dictionary = host.element(_cargo_id)
	cargo.active = false
	var actor = cargo.get("target_actor")
	if is_instance_valid(actor):
		actor.queue_free()
	host.element("crane_shadow").active = false
	var landing: Dictionary = host.element("landing_%d" % index)
	landing.phase = "落下预警 · 离开圆圈"
	landing["fall_hazard"] = host.add_hazard(landing.position, 70, 12, 1.2, .2, {"enemies": true})
	host.event("cargo_intercepted", {"index": index, "landing": landing.position, "source": source, "phase": "falling"})

func _tick_cargo(delta: float) -> void:
	if _cargo_phase == "landed": return
	if _cargo_phase == "falling":
		_cargo_fall -= delta
		if _cargo_fall > 0: return
		var landing: Dictionary = host.element("landing_%d" % _cargo_landing)
		# Retry safely while occupied; a falling crate never materialises on a hero.
		if not host.set_blocker("cargo_cover_%d" % _cargo_landing, Rect2(Vector2(landing.position) - Vector2(37, 24), Vector2(74, 48)), true):
			landing.phase = "等待落点腾空"
			return
		landing.asset = DRONE
		landing.captured = true
		landing.interactive = true
		landing.phase = "已落地 · E回收"
		_cargo_phase = "landed"
		return
	var cargo: Dictionary = host.element(_cargo_id)
	var previous: Vector2 = cargo.position
	cargo.position = previous + Vector2(165 * delta, 0)
	host.element("crane_shadow").position = cargo.position + Vector2(0, 58)
	var selected: Dictionary = host.element("landing_%d" % _cargo_selected)
	if not bool(selected.captured) and previous.x <= Vector2(selected.position).x and Vector2(cargo.position).x >= Vector2(selected.position).x:
		_begin_fall(_cargo_selected, "crane")
	elif Vector2(cargo.position).x > 2520:
		cargo.position = Vector2(400, host.point(0).y)
		_cargo_passes += 1
		host.event("cargo_looped", {"passes": _cargo_passes})
