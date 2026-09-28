extends RefCounted
## B02 objectives use the room's actual anchors and safe collision helpers.
## Damage is always delegated to telegraphed host hazards / real attack targets.

const ROOT := "B02_root_barrier"
const NEST := "B02_spore_nest"
const ROCK := "B02_fungal_rock"
var host
var clock: float = 0.0
var finished: bool = false
var state: Dictionary = {}
var targets: Dictionary = {}

func configure(next_host) -> void:
	host = next_host
	clock = 0.0
	finished = false
	state.clear()
	targets.clear()
	match str(host.room_id):
		"L07": _configure_filters()
		"L08": _configure_mushrooms()
		"L09": _configure_pods()
		"L10": _configure_fans()
		"L11": _configure_research()
		"L12": _configure_acid()

func tick(delta: float) -> void:
	if finished or delta <= 0.0 or not is_finite(delta) or _paused():
		return
	# Small deterministic steps preserve pressure windows and water conservation.
	var remaining: float = minf(delta, 60.0)
	while remaining > 0.00001 and not finished:
		var step: float = minf(remaining, 0.1)
		clock += step
		match str(host.room_id):
			"L07": _tick_filters(step)
			"L08": _tick_mushrooms(step)
			"L09": _tick_pods(step)
			"L10": _tick_fans(step)
			"L11": _tick_research(step)
			"L12": _tick_acid(step)
		remaining -= step

func interact(id: String, actor: Node2D) -> bool:
	var optional_after_finish: bool = str(host.room_id) == "L11" and id == "research_2"
	if (finished and not optional_after_finish) or _paused() or not is_instance_valid(actor) or actor != host.player():
		return false
	var item: Dictionary = host.element(id)
	if item.is_empty() or not bool(item.get("active", true)) or bool(item.get("done", false)) or not host.near(item.position):
		return false
	match str(host.room_id):
		"L07": return _interact_filters(id)
		"L08": return _interact_mushrooms(id)
		"L09": return false # Identification is visual; only actual attacks break pods.
		"L10": return _interact_fan(id)
		"L11": return _interact_research(id)
		"L12": return _interact_acid(id)
	return false

func on_target_hit(id: String, context: Dictionary) -> void:
	if finished or _paused():
		return
	if str(host.room_id) == "L09" and id.begins_with("decoy_"):
		if float(context.get("damage", context.get("amount", 1.0))) <= 0.0:
			return
		var item: Dictionary = host.element(id)
		if item.is_empty() or clock < float(item.get("bubble_ready", 0.0)):
			return
		item.bubble_ready = clock + 2.0
		item.description = "假囊鼓泡：离开虚线圆圈；停止攻击可避免继续喷孢"
		host.add_hazard(item.position, 105.0, 9.0, 1.1, 0.35, {"kind":"decoy_spores","enemies":true})
		host.event("decoy_warning", {"id":id})

func on_target_destroyed(id: String) -> void:
	var optional_after_finish: bool = str(host.room_id) == "L11" and id == "research_nest_2"
	if (finished and not optional_after_finish) or _paused():
		return
	var item: Dictionary = host.element(id)
	if item.is_empty() or bool(item.get("done", false)):
		return
	match str(host.room_id):
		"L09":
			if id.begins_with("main_pod_"):
				host.set_done(id)
				if int(host.completed_count) >= 2:
					_finish("reduced" if int(state.false_pods) >= 2 else "full")
			elif id.begins_with("decoy_"):
				item.done = true
				state.false_pods += 1
				host.event("decoy_destroyed", {"id":id,"count":state.false_pods})
		"L11":
			if id.begins_with("thin_wall_"):
				item.done = true
				_remove_static_obstacle(item.wall_rect)
				state.broken_walls[id] = true
				host.event("thin_wall_opened", {"id":id})
			elif id.begins_with("research_nest_"):
				item.done = true
				var package: Dictionary = host.element("research_" + id.trim_prefix("research_nest_"))
				package.sealed = false
				package.description = "幼巢已打开，按 E 回收研究包" + ("（可选）" if bool(package.optional) else "")

func blocks_dash() -> bool:
	return str(host.room_id) == "L07" and not str(state.get("carrying", "")).is_empty()

func navigation_target() -> Dictionary:
	if finished:
		return {"position":host.layout.exit,"title":"目标完成 · 前往出口"}
	var ids: Array[String] = []
	match str(host.room_id):
		"L07":
			if blocks_dash():
				ids.append("water_wheel")
			else:
				for index: int in 3: ids.append("filter_%d" % index)
		"L08":
			for index: int in 3: ids.append("mushroom_%d" % index)
		"L09":
			for index: int in 2: ids.append("main_pod_%d" % index)
		"L10":
			for index: int in 3: ids.append("fan_%d" % index)
		"L11":
			for index: int in 2:
				var package: Dictionary = host.element("research_%d" % index)
				if not bool(package.done):
					ids.append(("research_nest_%d" if bool(package.sealed) else "research_%d") % index)
		"L12":
			for index: int in 4:
				if not bool(state.open[index]) and not bool(host.element("reaction_%d" % (index / 2)).done):
					ids.append("sluice_%d" % index)
			if ids.is_empty():
				for index: int in 2: ids.append("reaction_%d" % index)
	var destination: Dictionary = {}
	var best: float = INF
	for id: String in ids:
		var item: Dictionary = host.element(id)
		if item.is_empty() or bool(item.done):
			continue
		var distance: float = host.player().position.distance_squared_to(item.position)
		if distance < best:
			best = distance
			destination = {"id":id,"position":item.position,"title":str(item.label)}
	return destination

func status_text() -> String:
	match str(host.room_id):
		"L07": return "滤芯 %d/3 · %s" % [host.completed_count, "携带中：不能冲刺，E 可放下" if blocks_dash() else "搬到东岸净水轮；丢失滤芯可在岸台巢点找回"]
		"L08": return "灯蕈 %d/3 · 踩住平台待伞盖展开，再按 E 采集" % host.completed_count
		"L09": return "主囊 %d/2 · 攻击双环脉纹主囊；斑点假囊受击会鼓泡" % host.completed_count
		"L10": return "净化风机 %d/3 · 顺序自选；旋转风标过载时 E 中断并重试" % host.completed_count
		"L11": return "研究包 %d/2 · 普攻打开幼巢；第三包可选，薄墙可打破" % host.completed_count
		"L12": return "反应槽 %d/2 · 开堰门引流；中央排空杆可降低收益提前完成" % host.completed_count
	return ""

func draw_world(canvas: Node2D) -> void:
	# Compact mechanical markings complement the original B02 prop art. Shape,
	# motion and fill communicate state without relying on color or text alone.
	var ink := Color("d3e4bd")
	for item: Dictionary in host.elements.values():
		if bool(item.get("done", false)) or not bool(item.get("active", true)):
			continue
		var at: Vector2 = item.position
		match str(item.get("kind", "")):
			"pressure":
				canvas.draw_arc(at, 91.0, 0.0, TAU, 40, Color(ink,.36), 2.0, true)
				canvas.draw_arc(at, 85.0, -PI*.5, -PI*.5+TAU*maxf(.001,float(item.pressure)), 40, ink, 3.0, true)
			"fan":
				var direction: Vector2 = item.direction
				var tip: Vector2 = at+direction*125.0
				canvas.draw_line(at+direction*45.0,tip,ink,3.0,true)
				canvas.draw_line(tip,tip-direction.rotated(.55)*22.0,ink,3.0,true)
				canvas.draw_line(tip,tip-direction.rotated(-.55)*22.0,ink,3.0,true)
				if str(item.phase) == "overload":
					for blade: int in 3:
						var vector: Vector2 = Vector2.RIGHT.rotated(clock*3.0+blade*TAU/3.0)
						canvas.draw_line(at+vector*40.0,at+vector*63.0,Color("f3b46b"),5.0,true)
			"water_level":
				canvas.draw_rect(Rect2(at+Vector2(-36,25),Vector2(72,10)),Color(ink,.25),false,2)
				canvas.draw_rect(Rect2(at+Vector2(-34,27),Vector2(68*clampf(float(item.progress),0,1),6)),ink)
		if str(item.get("pattern", "")) == "double_ring":
			var radius: float = 45.0+sin(clock*3.0)*2.0
			canvas.draw_arc(at,radius,0,TAU,40,ink,2.5,true)
			canvas.draw_arc(at,radius+9.0,0,TAU,40,ink,2.5,true)
		elif str(item.get("pattern", "")) == "spots":
			for spot: int in 8:
				canvas.draw_circle(at+Vector2.RIGHT.rotated(spot*TAU/8.0)*49.0,4.0,ink)

func _paused() -> bool:
	return is_instance_valid(host.room) and host.room.is_inside_tree() and host.room.get_tree().paused

func _finish(quality: String = "full") -> void:
	if finished:
		return
	finished = true
	host.finish(quality)

func _extra_position(index: int, fallback: Vector2) -> Vector2:
	var controls: Array = []
	for item: Dictionary in host.layout.get("interactables", []):
		if not bool(item.get("required", false)):
			controls.append(item.position)
	return host.safe_point(controls[index] if index < controls.size() else fallback)

func _visual(id: String, at: Vector2, label: String, kind: String, asset: String, extra: Dictionary = {}) -> Dictionary:
	extra["interactable"] = false
	extra["required"] = false
	return host.add_element(id, at, label, kind, asset, extra)

func _target(id: String, at: Vector2, hp: float, asset: String, label: String, extra: Dictionary) -> void:
	var item: Dictionary = host.add_target(id, at, hp, asset, label, extra)
	targets[id] = item.get("target_actor")

func _occupied(rectangle: Rect2) -> bool:
	var padded: Rect2 = rectangle.grow(28.0)
	var actor: Node2D = host.player()
	if is_instance_valid(actor) and padded.has_point(actor.position):
		return true
	for enemy: Node2D in host.enemies_near(rectangle.get_center(), rectangle.size.length() * 0.5 + 36.0):
		if padded.has_point(enemy.position):
			return true
	if str(host.room_id) == "L07":
		for index: int in 3:
			var filter: Dictionary = host.element("filter_%d" % index)
			if not bool(filter.done) and str(state.carrying) != str(filter.id) and padded.has_point(filter.position):
				return true
	return false

func _remove_static_obstacle(rectangle: Rect2) -> void:
	# Host owns the collision array and navigation invalidation.
	if host.has_method("remove_static_obstacle"):
		host.remove_static_obstacle(rectangle)
	else:
		push_error("B02 objective host requires remove_static_obstacle(Rect2)")

func _configure_filters() -> void:
	host.required_count = 3
	state = {"carrying":"","bridge_switch":7.0,"bridge_lane":0,"bridges":[],"steal_ready":{},"thefts":{}}
	for index: int in 3:
		host.add_element("filter_%d" % index, host.point(index), "滤芯 %d" % (index + 1), "carry", ROCK, {"description":"按 E 搬起；携带仍可攻击，不能冲刺"})
	var wheel: Vector2 = host.safe_point(Vector2(2480.0, 900.0))
	host.add_element("water_wheel", wheel, "净水轮 · 交付滤芯", "delivery", ROOT, {"required":false,"description":"把三枚滤芯逐一搬到东岸"})
	host.add_element("carry_drop", host.point(0), "放下滤芯", "drop", ROCK, {"required":false,"carried":true,"active":false,"description":"安全放在脚边，之后可以重新拾取"})
	for zone: Dictionary in host.layout.get("hazard_zones", []):
		if str(zone.kind) == "occupied_bridge_wait":
			state.bridges.append(zone.rect)
	for index: int in state.bridges.size():
		_visual("root_bridge_%d" % index, state.bridges[index].get_center(), "活根桥 · 通行", "bridge", ROOT, {"description":"桥上有角色或滤芯时等待通过"})

func _interact_filters(id: String) -> bool:
	if id == "water_wheel":
		var carried: String = state.carrying
		if carried.is_empty():
			host.message = "先搬起一枚滤芯"
			return false
		host.element(carried).position = host.element(id).position
		host.element(carried).active = true
		host.set_done(carried)
		state.carrying = ""
		host.element("carry_drop").active = false
		host.event("filter_delivered", {"id":carried})
		if int(host.completed_count) >= 3:
			for index: int in state.bridges.size():
				host.remove_blocker("root_bridge_%d" % index)
			_finish()
		return true
	if id == "carry_drop":
		return _drop_filter()
	if not id.begins_with("filter_") or not str(state.carrying).is_empty():
		return false
	_cancel_theft(id, false)
	state.carrying = id
	host.element(id).active = false
	host.element("carry_drop").active = true
	host.element("carry_drop").position = host.player().position
	host.event("filter_lifted", {"id":id})
	return true

func _drop_filter() -> bool:
	var carried: String = state.carrying
	if carried.is_empty():
		return false
	var item: Dictionary = host.element(carried)
	item.position = host.safe_point(host.player().position + Vector2(36.0, 0.0))
	item.active = true
	state.steal_ready[carried] = clock + 2.0
	state.carrying = ""
	host.element("carry_drop").active = false
	host.event("filter_dropped", {"id":carried})
	return true

func _tick_filters(delta: float) -> void:
	if blocks_dash():
		host.element("carry_drop").position = host.player().position
		host.element(str(state.carrying)).position = host.player().position
	for index: int in 3:
		var id: String = "filter_%d" % index
		var item: Dictionary = host.element(id)
		if state.thefts.has(id):
			_tick_theft(id, delta)
			continue
		if item.done or state.carrying == id or clock < float(state.steal_ready.get(id, 0.0)):
			continue
		for enemy: Node2D in host.enemies_near(item.position, 48.0):
			if str(enemy.get("enemy_id")) != "M16":
				continue
			var bank: int = clampi(floori(item.position.x / 950.0), 0, 2)
			state.thefts[id] = {"thief":weakref(enemy),"original":item.position,"destination":host.safe_point(Vector2([425.68,1400.0,2341.22][bank],1500.0)),"phase":"warning","timer":1.0,"deadline":clock+24.0}
			item.description = "吸管锁定：1 秒后拖走！现在拾起滤芯或击杀偷取者可打断"
			item.always_label = true
			item.beam_from = enemy.position
			item.beam_to = item.position
			host.event("filter_theft_warning", {"id":id})
			break
	if clock < float(state.bridge_switch) - 1.2:
		return
	var closing_lane: int = 1 - int(state.bridge_lane)
	for index: int in state.bridges.size():
		var bridge: Dictionary = host.element("root_bridge_%d" % index)
		if index % 2 == closing_lane:
			bridge.description = "根桥正在收拢预警；桥上有物体则等待"
	if clock < float(state.bridge_switch):
		return
	for index: int in state.bridges.size():
		if index % 2 == closing_lane and _occupied(state.bridges[index]):
			return
	# Open the replacement route before closing any old span.
	for index: int in state.bridges.size():
		if index % 2 != closing_lane:
			host.remove_blocker("root_bridge_%d" % index)
	for index: int in state.bridges.size():
		var id: String = "root_bridge_%d" % index
		var closed: bool = false
		if index % 2 == closing_lane:
			closed = host.set_blocker(id, state.bridges[index], true)
		host.element(id).label = "活根桥 · 收拢" if closed else "活根桥 · 通行"
		host.element(id).progress = 1.0 if closed else 0.0
	state.bridge_lane = closing_lane
	state.bridge_switch = clock + 7.0
	host.event("root_bridge_switched", {"closed_lane":closing_lane})

func _cancel_theft(id: String, restore: bool) -> void:
	if not state.thefts.has(id):
		return
	var item: Dictionary = host.element(id)
	if restore:
		item.position = host.safe_point(state.thefts[id].original)
		item.description = "吸管已断开：滤芯返回原安全点，可重新搬起"
		item.label = "滤芯 · 可找回"
	item.erase("beam_from")
	item.erase("beam_to")
	item.always_label = false
	state.thefts.erase(id)
	state.steal_ready[id] = clock + 8.0

func _tick_theft(id: String, delta: float) -> void:
	var theft: Dictionary = state.thefts[id]
	var enemy = theft.thief.get_ref()
	var item: Dictionary = host.element(id)
	if not is_instance_valid(enemy) or not enemy.is_alive() or clock >= float(theft.deadline):
		_cancel_theft(id, true)
		host.event("filter_theft_cancelled", {"id":id})
		return
	item.beam_from = enemy.position
	item.beam_to = item.position
	if str(theft.phase) == "warning":
		theft.timer = maxf(0.0,float(theft.timer)-delta)
		if float(theft.timer) <= 0.0:
			theft.phase = "dragging"
			item.description = "滤芯正在沿地面拖向岸台；仍可拾回，击杀偷取者可中断"
		return
	if host.move_element(id, theft.destination, 115.0, delta):
		_cancel_theft(id, false)
		item.description = "岸台巢点的滤芯，按 E 找回；任务物保持完整"
		host.event("filter_recoverable", {"id":id,"position":item.position})

func _configure_mushrooms() -> void:
	host.required_count = 3
	state = {"cloud_tick":1.5,"clouds":[]}
	for index: int in 3:
		host.add_element("mushroom_%d" % index, host.point(index), "闭合灯蕈 %d" % (index + 1), "pressure", NEST, {"pressure":0.0,"opened":false,"description":"站在平台上持续施压，使伞盖展开后采集"})
	host.add_element("seal_mushrooms", host.safe_point(Vector2(350.0, 900.0)), "提前封存 · 较少金币", "fallback", ROCK, {"required":false,"description":"已采两株后可封存；继续第三株取得完整奖励"})
	for index: int in 2:
		var center: Vector2 = Vector2(720.0 + index * 1260.0, 895.0)
		state.clouds.append(center)
		_visual("drifting_cloud_%d" % index, center, "漂移孢云", "cloud", NEST, {"radius":58.0,"description":"只覆盖局部条带，稳定外圈始终可走"})

func _tick_mushrooms(delta: float) -> void:
	for index: int in 3:
		var item: Dictionary = host.element("mushroom_%d" % index)
		if item.done:
			continue
		var pressed: bool = host.near(item.position, 95.0) or not host.enemies_near(item.position, 75.0).is_empty()
		item.pressure = clampf(float(item.pressure) + delta * (1.0 if pressed else -1.8), 0.0, 1.0)
		item.progress = item.pressure
		item.opened = float(item.pressure) >= 0.8
		item.label = ("展开灯蕈 " if item.opened else "闭合灯蕈 ") + str(index + 1)
		var edge_id: String = "platform_edge_%d" % index
		var edge: Rect2 = Rect2(item.position + Vector2(110.0, -40.0), Vector2(22.0, 80.0))
		if pressed and float(item.pressure) >= 0.8 and not _occupied(edge):
			if not bool(item.get("edge_attempted", false)):
				item.edge_attempted = true
				item.edge_sunk = host.set_blocker(edge_id, edge, true)
		elif float(item.pressure) <= 0.05:
			host.remove_blocker(edge_id)
			item.edge_sunk = false
			item.edge_attempted = false
	for index: int in 2:
		var cloud: Dictionary = host.element("drifting_cloud_%d" % index)
		cloud.position = host.safe_point(state.clouds[index] + Vector2(sin(clock * 0.34 + index * PI) * 260.0, sin(clock * 0.21) * 30.0))
	if clock >= float(state.cloud_tick):
		state.cloud_tick = clock + 2.2
		var index: int = floori(clock / 2.2) % 2
		host.add_hazard(host.element("drifting_cloud_%d" % index).position, 62.0, 6.0, 0.9, 0.65, {"kind":"drifting_spores"})

func _interact_mushrooms(id: String) -> bool:
	if id == "seal_mushrooms":
		if int(host.completed_count) < 2:
			host.message = "至少采两株灯蕈才能封存"
			return false
		_finish("reduced")
		return true
	if not id.begins_with("mushroom_"):
		return false
	var item: Dictionary = host.element(id)
	if not bool(item.opened):
		host.message = "先站稳压下浮台，等待灯蕈展开"
		return false
	host.set_done(id)
	host.remove_blocker("platform_edge_" + id.trim_prefix("mushroom_"))
	host.event("pressed_mushroom_collected", {"id":id})
	if int(host.completed_count) >= 3:
		_finish()
	return true

func _configure_pods() -> void:
	host.required_count = 2
	state = {"false_pods":0,"wall_tick":5.0,"wall_out":false,"next_pulse":0.0}
	for index: int in 2:
		var id: String = "main_pod_%d" % index
		_target(id, host.point(index), 70.0, NEST, "主囊 · 双环脉纹", {"pattern":"double_ring","pulse":true,"interactable":false,"description":"双重同心脉纹；普攻可破坏，不需要任何技能"})
	for index: int in 3:
		var id: String = "decoy_%d" % index
		_target(id, _extra_position(index, host.point(index % 2) + Vector2(180.0, 200.0)), 45.0, NEST, "假囊 · 斑点纹", {"required":false,"pattern":"spots","bubble_ready":0.0,"interactable":false,"description":"断续斑点纹；受到攻击后鼓泡，留出逃离窗口"})
	_visual("living_wall_tip", host.safe_point(Vector2(1040.0, 810.0)), "活墙缓慢伸缩", "wall_tip", ROOT)

func _tick_pods(_delta: float) -> void:
	if clock >= float(state.next_pulse):
		state.next_pulse = clock + 1.8
		for index: int in 2:
			var pod: Dictionary = host.element("main_pod_%d" % index)
			if not bool(pod.done) and host.near(pod.position, 300.0):
				# Reuse the original cached resonant synthesis; the existing audio
				# node owns mute, voice cap, pause and mixer cleanup for this cue.
				var audio: Node = host.room.get("combat_audio")
				if is_instance_valid(audio) and audio.has_method("impact") and audio.impact("CH03", true):
					host.event("main_pod_resonance", {"id":pod.id})
				break
	if clock < float(state.wall_tick):
		return
	var item: Dictionary = host.element("living_wall_tip")
	var edge: Rect2 = Rect2(item.position - Vector2(24.0, 45.0), Vector2(48.0, 90.0))
	if _occupied(edge):
		return
	state.wall_out = not bool(state.wall_out)
	if state.wall_out:
		state.wall_out = host.set_blocker("living_wall_tip", edge, true)
	else:
		host.remove_blocker("living_wall_tip")
	item.progress = 1.0 if state.wall_out else 0.0
	state.wall_tick = clock + 5.0

func _configure_fans() -> void:
	host.required_count = 3
	state = {"cloud_tick":2.0}
	var directions: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]
	for index: int in 3:
		var direction: Vector2 = directions[index]
		host.add_element("fan_%d" % index, host.point(index), "风机 %d · %s" % [index + 1, ["←","→","↓"][index]], "fan", ROOT, {"phase":"idle","heat":0.0,"timer":0.0,"direction":direction,"description":"E 启动；风标过载时 E 中断，净化进度保留"})
		_visual("fan_cloud_%d" % index, host.safe_point(host.point(index) + direction * 170.0), "待驱散孢云", "cloud", NEST, {"radius":62.0})

func _interact_fan(id: String) -> bool:
	if not id.begins_with("fan_") or id.begins_with("fan_cloud_"):
		return false
	var fan: Dictionary = host.element(id)
	match str(fan.phase):
		"idle":
			fan.phase = "warming"
			fan.timer = 0.9
			fan.description = "风机预热，箭头方向即将形成风带"
			host.event("fan_started", {"id":id,"direction":fan.direction})
			return true
		"warming", "running", "overload":
			fan.phase = "cooldown"
			fan.timer = 0.8
			fan.heat = 0.0
			fan.description = "已中断；稍后可重启，已有净化进度保留"
			host.event("fan_interrupted", {"id":id})
			return true
	return false

func _tick_fans(delta: float) -> void:
	for index: int in 3:
		var id: String = "fan_%d" % index
		var fan: Dictionary = host.element(id)
		if str(fan.phase) in ["warming", "cooldown", "overload"]:
			fan.timer = maxf(0.0, float(fan.timer) - delta)
			if float(fan.timer) <= 0.0:
				match str(fan.phase):
					"warming": fan.phase = "running"
					"cooldown": fan.phase = "idle"
					"overload":
						host.add_hazard(fan.position, 130.0, 12.0, 0.9, 0.3, {"kind":"fan_overload","enemies":true})
						fan.phase = "cooldown"
						fan.timer = 1.4
						fan.heat = 0.0
						host.event("fan_overload_recoverable", {"id":id})
		if str(fan.phase) != "running":
			continue
		var direction: Vector2 = fan.direction
		host.move_element("fan_cloud_%d" % index, fan.position + direction * 440.0, 90.0, delta)
		for enemy: Node2D in host.enemies_near(fan.position, 460.0):
			var offset: Vector2 = enemy.position - Vector2(fan.position)
			if float(enemy.get("navigation_radius")) <= 22.0 and str(enemy.get("rank")) != "elite" and not bool(enemy.get("static_actor")) and offset.dot(direction) > 0.0 and absf(offset.cross(direction)) < 95.0:
				host.displace(enemy, direction * 72.0 * delta)
		if not bool(fan.done):
			fan.progress = minf(1.0, float(fan.progress) + delta / 6.0)
			fan.heat = float(fan.heat) + delta / 3.0
			if float(fan.progress) >= 1.0:
				host.set_done(id)
				fan.description = "净化完成，风带稳定"
			elif float(fan.heat) >= 1.0:
				fan.phase = "overload"
				fan.timer = 1.6
				fan.description = "旋转风标：即将过载！E 中断可避免爆风并保留进度"
				host.event("fan_overload_warning", {"id":id})
	if int(host.completed_count) >= 3:
		_finish()
		return
	if clock >= float(state.cloud_tick):
		state.cloud_tick = clock + 2.6
		var index: int = floori(clock / 2.6) % 3
		host.add_hazard(host.element("fan_cloud_%d" % index).position, 60.0, 6.0, 1.0, 0.45, {"kind":"fan_spore_cloud","enemies":true})

func _configure_research() -> void:
	host.required_count = 2
	state = {"broken_walls":{},"gutter_tick":2.5,"optional":false}
	for index: int in 3:
		host.add_element("research_%d" % index, host.point(index), "研究包 %d%s" % [index + 1, " · 可选" if index == 2 else " · 必需"], "research", ROCK, {"required":index < 2,"sealed":true,"optional":index == 2,"description":"先普攻打开旁边幼巢，研究包不会被摧毁"})
		var id: String = "research_nest_%d" % index
		_target(id, host.safe_point(host.point(index) + Vector2(-48.0, 0.0)), 45.0, NEST, "封存幼巢", {"required":false,"interactable":false,"description":"可用基础攻击打开；旁边的研究包保持完整"})
	var obstacles: Array = host.layout.get("obstructions", []).duplicate()
	for index: int in obstacles.size():
		var rectangle: Rect2 = obstacles[index]
		if not _is_thin_wall(index, rectangle):
			continue
		var face: Vector2 = rectangle.get_center() + Vector2(0.0, rectangle.size.y * 0.5 + 35.0)
		if rectangle.size.x < rectangle.size.y:
			face = rectangle.get_center() + Vector2(rectangle.size.x * 0.5 + 35.0, 0.0)
		var id: String = "thin_wall_%d" % index
		_target(id, host.safe_point(face), 55.0, ROOT, "薄菌墙 · 可破", {"required":false,"wall_rect":rectangle,"interactable":false,"description":"普攻或引导啮墙兽咬穿；破墙后沟槽会出现渗流预警"})

func _is_thin_wall(index: int, rectangle: Rect2) -> bool:
	var kinds: Array = host.layout.get("obstruction_kinds", [])
	if index < kinds.size() and str(kinds[index]) == "breakable_wall":
		return true
	for instance: Dictionary in host.layout.get("prop_instances", []):
		if instance.get("collision_rect", Rect2()) == rectangle and not bool(instance.get("destroyed", false)):
			return str(instance.get("kind", "")) == "breakable_wall" or "thin_wall" in instance.get("tags", [])
	return false

func _interact_research(id: String) -> bool:
	if not id.begins_with("research_") or id.begins_with("research_nest_"):
		return false
	var item: Dictionary = host.element(id)
	if bool(item.sealed):
		host.message = "研究包仍被幼巢包裹，先用普攻打开旁边的幼巢"
		return false
	if bool(item.optional):
		item.done = true
		state.optional = true
		host.event("optional_research_recovered", {"id":id})
	else:
		host.set_done(id)
	if int(host.completed_count) >= 2:
		_finish()
	return true

func _tick_research(_delta: float) -> void:
	for id: String in targets:
		if not id.begins_with("thin_wall_") or bool(host.element(id).done):
			continue
		# RoomProps/EnemyAI owns M18's bite and per-caster wall budget. Mirror a
		# wall already removed there instead of inventing another proximity bite.
		if not host.room.obstructions.has(host.element(id).wall_rect):
			host.on_target_destroyed(id)
			if is_instance_valid(targets[id]):
				targets[id].queue_free()
			host.event("thin_wall_external_bite_synced", {"id":id})
	if state.broken_walls.is_empty() or clock < float(state.gutter_tick):
		return
	state.gutter_tick = clock + 3.5
	var opened: Dictionary = host.element(str(state.broken_walls.keys()[floori(clock / 3.5) % state.broken_walls.size()]))
	# The new leak follows the opened wall's short gutter, never the outer road.
	var at: Vector2 = host.safe_point(opened.position + Vector2(0.0, 45.0))
	host.add_hazard(at, 24.0, 8.0, 1.1, 0.4, {"shape":"line","target":host.safe_point(at + Vector2(0.0, 150.0)),"width":36.0,"kind":"connected_gutter","enemies":true})

func _configure_acid() -> void:
	host.required_count = 2
	state = {"levels":[0.95,0.65,0.95,0.55],"open":[false,false,false,false],"tank_charge":[0.0,0.0],"draining":false,"drain_warning":0.0,"overflow_ready":[0.0,0.0,0.0,0.0],"pool_rects":[],"dry":[false,false,false,false],"surface_retry":[0.0,0.0,0.0,0.0]}
	var kinds: Array = host.layout.get("obstruction_kinds", [])
	for index: int in host.layout.get("obstructions", []).size():
		if index < kinds.size() and str(kinds[index]) == "acid_reservoir":
			state.pool_rects.append(host.layout.obstructions[index])
	for index: int in 2:
		host.add_element("reaction_%d" % index, host.point(index), "废料反应槽 %d" % (index + 1), "reaction", NEST, {"description":"从相邻堰门引入酸液，持续反应后自动失活"})
	for index: int in 4:
		var rectangle: Rect2 = state.pool_rects[index]
		host.add_element("sluice_%d" % index, _extra_position(index, rectangle.get_center() + Vector2(rectangle.size.x * 0.5 + 55.0, 0.0)), "堰门 %d · 关闭" % (index + 1), "sluice", ROOT, {"required":false,"description":"E 开关；改变下一池水位与附近酸区，中央环台始终安全"})
		_visual("acid_level_%d" % index, rectangle.get_center(), "水位 %d%%" % roundi(float(state.levels[index])*100.0), "water_level", ROCK, {"progress":state.levels[index],"radius":52.0})
	host.add_element("drain_all", host.safe_point(Vector2(1400.0,900.0)), "提前排空 · 较少金币", "fallback", ROOT, {"required":false,"description":"无需反应即可排空离开；完整引流可取得完整奖励"})

func _interact_acid(id: String) -> bool:
	if id == "drain_all":
		if bool(state.draining):
			return false
		state.draining = true
		state.drain_warning = 0.8
		host.element(id).description = "排空阀开启：水位下降后开放出口，奖励降低"
		host.event("acid_early_drain")
		return true
	if not id.begins_with("sluice_") or bool(state.draining):
		return false
	var index: int = id.trim_prefix("sluice_").to_int()
	state.open[index] = not bool(state.open[index])
	host.element(id).label = "堰门 %d · %s" % [index+1,"开启" if state.open[index] else "关闭"]
	host.event("sluice_toggled", {"index":index,"open":state.open[index]})
	return true

func _tick_acid(delta: float) -> void:
	if bool(state.draining):
		state.drain_warning = maxf(0.0, float(state.drain_warning) - delta)
		if float(state.drain_warning) <= 0.0:
			var total: float = 0.0
			for index: int in 4:
				state.levels[index] = maxf(0.0, float(state.levels[index]) - delta * 0.55)
				total += float(state.levels[index])
			if total <= 0.001:
				_update_pool_surfaces()
				_finish("reduced")
				return
	else:
		for index: int in 4:
			if not bool(state.open[index]):
				continue
			var amount: float = minf(float(state.levels[index]), delta * 0.24)
			state.levels[index] = float(state.levels[index]) - amount
			if index < 3:
				state.levels[index + 1] = minf(1.25, float(state.levels[index + 1]) + amount * 0.5)
			var tank: int = index / 2
			if not bool(host.element("reaction_%d" % tank).done):
				state.tank_charge[tank] = minf(0.6, float(state.tank_charge[tank]) + amount * 0.5)
				host.element("reaction_%d" % tank).progress = float(state.tank_charge[tank]) / 0.6
				if float(state.tank_charge[tank]) >= 0.59999:
					host.set_done("reaction_%d" % tank)
					host.event("acid_reaction_completed", {"tank":tank})
	_update_pool_surfaces()
	if int(host.completed_count) >= 2:
		_finish()

func _update_pool_surfaces() -> void:
	for index: int in 4:
		var level: float = float(state.levels[index])
		var item: Dictionary = host.element("acid_level_%d" % index)
		item.progress = level
		item.label = "水位 %d%%" % roundi(level*100.0)
		var rectangle: Rect2 = state.pool_rects[index]
		if level <= 0.15 and not bool(state.dry[index]):
			_remove_static_obstacle(rectangle)
			host.remove_blocker("acid_pool_%d" % index)
			state.dry[index] = true
			host.event("pool_floor_exposed", {"index":index})
		elif level > 0.35 and bool(state.dry[index]) and clock >= float(state.surface_retry[index]) and not _occupied(rectangle):
			# Occupants/topology may reject reflooding; never rebuild the large
			# validation graph each simulation step while that remains true.
			state.surface_retry[index] = clock + 1.2
			if host.set_blocker("acid_pool_%d" % index, rectangle, true):
				state.dry[index] = false
		if level >= 0.95 and not bool(state.draining) and clock >= float(state.overflow_ready[index]):
			state.overflow_ready[index] = clock + 3.2
			var zones: Array = host.layout.get("hazard_zones", [])
			if index < zones.size():
				var bank: Rect2 = zones[index].rect
				host.add_hazard(bank.position + Vector2(15.0,bank.size.y*0.5), bank.size.y*0.45, 9.0, 1.4, 0.5, {"shape":"line","target":bank.end-Vector2(15.0,bank.size.y*0.5),"width":bank.size.y*0.8,"kind":"acid_overflow","enemies":true})
