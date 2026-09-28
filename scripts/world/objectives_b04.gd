extends RefCounted
## B04 mechanisms use scene actors, editable optical paths and recoverable lamps.
## The shared host owns rendering, collision validation, hazards and completion.

const OBELISK := "B04_resonance_obelisk"
const CRYSTAL := "B04_crystal_cluster"
const RECEIVER := "B04_broken_receiver"
const SHAPES: Array[String] = ["圆环", "三角", "三道纹"]
var host
var clock: float = 0.0
var finished: bool = false
var work_id: String = ""
var order: Array[int] = []
var pulse: float = 2.0
var pulse_index: int = 0
var route_index: int = -1
var route_step: int = 0
var stability: float = 100.0
var selected_shape: int = -1
var carried_lamp: int = -1
var last_disc: int = -1
var last_correct_disc: int = -1
var sequence: Array[int] = [0, 2, 4]
var sequence_progress: int = 0
var mistake_cooldown: float = 0.0
var sound_seen: float = -100.0
var sound_until: float = 0.0
var lamps: Array[Dictionary] = []
var mirrors: Array[Dictionary] = []
var bridges: Array[Vector2] = []
var closed_bridge: int = -1
var warned_bridge: int = -1
var bridge_warning: float = 0.0
var bridge_cycle: float = 6.0

func configure(next_host) -> void:
	host = next_host
	clock = 0.0
	finished = false
	work_id = ""
	order.clear()
	pulse = 2.0
	pulse_index = 0
	route_index = -1
	route_step = 0
	stability = 100.0
	selected_shape = -1
	carried_lamp = -1
	last_disc = -1
	last_correct_disc = -1
	sequence_progress = 0
	mistake_cooldown = 0.0
	sound_seen = -100.0
	sound_until = 0.0
	lamps.clear()
	mirrors.clear()
	bridges.clear()
	closed_bridge = -1
	warned_bridge = -1
	bridge_warning = 0.0
	bridge_cycle = 6.0
	match str(host.room_id):
		"L19": _setup_locks()
		"L20": _setup_escort()
		"L21": _setup_mirrors()
		"L22": _setup_weaving()
		"L23": _setup_lamps()
		"L24": _setup_discs()
	for item: Dictionary in host.elements.values():
		var id: String = item.id
		item.required = id.begins_with("lock_") or id == "escort_light" or id.begins_with("inscription_") or id.begins_with("weave_column_") or (id.begins_with("echo_disc_") and sequence.has(int(item.get("index", -1))))
		if id == "escort_light" or id == "attack_echo" or id.begins_with("inscription_") or id.begins_with("bridge_") or id.begins_with("weave_line_") or id.begins_with("echo_disc_") or id.begins_with("mirror_inlet_"):
			item.interactive = false
	host.message = status_text()

func tick(delta: float) -> void:
	if finished or delta <= 0.0 or _paused():
		return
	clock += delta
	mistake_cooldown = maxf(0.0, mistake_cooldown - delta)
	match str(host.room_id):
		"L19": _tick_locks(delta)
		"L20": _tick_escort(delta)
		"L21": _tick_mirrors(delta)
		"L22": _tick_weaving()
		"L23": _tick_lamps(delta)
		"L24": _tick_discs()
	host.message = status_text()

func interact(id: String, actor: Node2D) -> bool:
	if finished or not is_instance_valid(actor) or _paused():
		return false
	var item: Dictionary = host.element(id)
	if item.is_empty() or not bool(item.get("active", true)) or not host.near(item.position):
		return false
	match str(host.room_id):
		"L19":
			if id.begins_with("lock_") and not bool(item.done):
				work_id = id
				host.event("resonance_lock_started", {"id":id})
				return true
		"L20":
			if id.begins_with("route_"):
				route_index = int(item.route)
				host.event("escort_route_selected", {"route":route_index,"step":route_step,"target":item.destination})
				return true
			if id.begins_with("echo_fragment_") and not bool(item.done):
				item.done = true
				item.active = false
				stability = minf(100.0, stability + 8.0)
				host.event("echo_fragment_recovered", {"id":id})
				return true
		"L21":
			if id.begins_with("mirror_"):
				var mirror: Dictionary = mirrors[int(item.index)]
				mirror.angle = float(mirror.angle) + PI / 4.0
				item.angle = mirror.angle
				item.description = "反射面每次转 45°；对准铭文后维持光束"
				_tick_mirrors(0.0)
				host.event("calibration_mirror_turned", {"id":id,"angle":mirror.angle})
				return true
		"L22":
			if id.begins_with("sound_shape_"):
				selected_shape = int(item.index)
				host.event("sound_shape_selected", {"shape":selected_shape})
				return true
			if id.begins_with("weave_column_") and not bool(item.done) and selected_shape >= 0:
				if int(item.index) == selected_shape:
					host.set_done(id)
					var token: Dictionary = host.element("sound_shape_" + str(selected_shape))
					token.active = false
					token.done = true
					selected_shape = -1
					host.event("sound_shape_installed", {"id":id})
					if int(host.completed_count) >= 3:
						_clear_weave_lines()
						_complete()
				else:
					_weave_mistake(int(item.index))
				return true
		"L23":
			if id.begins_with("lamp_") and id != "lamp_receiver":
				var index: int = int(item.index)
				var lamp: Dictionary = lamps[index]
				if int(_lamp_entity(index).get("taken_by", 0)) != 0:
					return false
				if carried_lamp == index:
					_drop_lamp(index)
				elif carried_lamp < 0:
					carried_lamp = index
					lamp.docked = false
					item.done = false
				else:
					return false
				return true
			if id == "lamp_receiver":
				if carried_lamp >= 0:
					_dock_lamp(carried_lamp)
					return true
				if _lit_lamp_count() >= 2:
					_complete("full" if _lit_lamp_count() == 3 else "reduced")
					return true
		"L24":
			if id == "sequence_record":
				item.description = _sequence_text()
				return true
	return false

func on_target_hit(_id: String, _context: Dictionary) -> void:
	pass

func on_target_destroyed(id: String) -> void:
	if finished:
		return
	if str(host.room_id) == "L22" and id.begins_with("weave_knot_"):
		var index: int = int(id.trim_prefix("weave_knot_"))
		host.remove_blocker("weave_line_" + str(index))
		var line: Dictionary = host.element("weave_line_" + str(index))
		if not line.is_empty():
			line.active = false
			line.done = true
		host.event("weave_line_cut", {"index":index})

func on_player_sound(at: Vector2, context: Dictionary = {}) -> void:
	if str(host.room_id) != "L20" or finished or _paused():
		return
	if bool(context.get("dot", false)) or int(context.get("proc_depth", 0)) > 0 or str(context.get("damage_source", "primary")) in ["burn", "corrosion", "system", "echo"]:
		return
	sound_seen = maxf(sound_seen, float(_property(host.room, "last_player_sound_time", -100.0)))
	sound_until = clock + 1.2
	var echo: Dictionary = host.element("attack_echo")
	echo.position = at
	echo.active = true
	echo.description = "原始攻击声源：听声怪调查此处；持续伤害不刷新"
	# M28 consumes the room's actual last_player_sound_position/time. This
	# marker mirrors that source; it does not invent an unconsumed AI command.
	host.event("echo_lure", {"position":at,"duration":1.2})

func blocks_dash() -> bool:
	return false

func navigation_target() -> Dictionary:
	if finished:
		return {}
	var id: String = ""
	match str(host.room_id):
		"L19":
			id = work_id
			if id.is_empty():
				id = _nearest_unfinished("lock_", 3)
		"L20":
			id = "route_1" if route_index < 0 else "escort_light"
		"L21":
			for index: int in range(2):
				if not bool(host.element("inscription_" + str(index)).done):
					id = "mirror_" + str(index)
					break
		"L22":
			if selected_shape >= 0:
				id = "weave_column_" + str(selected_shape)
			else:
				for index: int in range(3):
					if not bool(host.element("weave_column_" + str(index)).done):
						id = "sound_shape_" + str(index)
						break
		"L23":
			id = "lamp_receiver" if carried_lamp >= 0 or _lit_lamp_count() >= 2 else _nearest_unfinished("lamp_", 3)
		"L24":
			id = "echo_disc_" + str(sequence[mini(sequence_progress, sequence.size() - 1)])
	var item: Dictionary = host.element(id)
	return {"position":item.position,"title":str(item.label)} if not item.is_empty() else {}

func _nearest_unfinished(prefix: String, count: int) -> String:
	var nearest: String = ""
	var distance: float = INF
	for index: int in range(count):
		var item: Dictionary = host.element(prefix + str(index))
		if item.is_empty() or bool(item.done):
			continue
		var next_distance: float = Vector2(item.position).distance_squared_to(host.player().position)
		if next_distance < distance:
			distance = next_distance
			nearest = str(item.id)
	return nearest

func status_text() -> String:
	match str(host.room_id):
		"L19": return "拆除共鸣锁 %d/3；E 开始拆锁，站近保持。顺序改变环波与径向波" % order.size()
		"L20": return "护送光点 %d/4 段；选择路线后靠近护送。原始攻击可把敌人引向回声" % route_step
		"L21": return "已照亮铭文 %d/2；E 转动反射石 45°，保持场景光束对准铭文" % int(host.completed_count)
		"L22": return "装入声纹 %d/3；当前携带：%s。对照形状，线结可用普攻切断" % [int(host.completed_count), "无" if selected_shape < 0 else SHAPES[selected_shape]]
		"L23": return "出口光束 %d/2；E 搬灯，再在接收器 E 安放。两灯可选金币离开，三灯全保" % _lit_lamp_count()
		"L24": return "踩盘顺序：%s（%d/3）；错误不清进度，回声落在旧位置" % [_sequence_text(), sequence_progress]
	return ""

func _setup_locks() -> void:
	host.required_count = 3
	for index: int in range(3):
		var at: Vector2 = host.safe_point(host.point(index))
		host.add_element("lock_" + str(index), at, "共鸣锁 " + str(index + 1), "mechanism", OBELISK, {"index":index,"description":"E 开始拆除，保持附近 1.8 秒；离开保留进度","wave_mode":"ring"})

func _tick_locks(delta: float) -> void:
	if not work_id.is_empty():
		var lock: Dictionary = host.element(work_id)
		if not lock.is_empty() and not bool(lock.done) and host.near(lock.position, 92.0):
			lock.progress = minf(1.0, float(lock.progress) + delta / 1.8)
			if float(lock.progress) >= 1.0:
				order.append(int(lock.index))
				lock.wave_mode = "line"
				host.set_done(work_id)
				host.event("resonance_lock_released", {"index":lock.index,"order":order.duplicate(),"wave_mode":"line"})
				work_id = ""
				if order.size() >= 3:
					_complete()
					return
	pulse -= delta
	if pulse > 0.0:
		return
	pulse = 3.2
	var index: int = pulse_index % 3
	pulse_index += 1
	var source: Dictionary = host.element("lock_" + str(index))
	var at: Vector2 = source.position
	if not host.near(at, 560.0):
		return
	if bool(source.done):
		var direction: Vector2 = Vector2.RIGHT.rotated(float(order.find(index)) * TAU / 3.0)
		host.add_hazard(at - direction * 110.0, 18.0, 8.0, 1.15, 0.25, {"shape":"line","target":at + direction * 110.0,"width":36.0,"enemies":true,"exclusive_group":"resonance_lock_wave"})
	else:
		host.add_hazard(at, 120.0, 8.0, 1.15, 0.25, {"shape":"ring","inner_radius":72.0,"enemies":true,"exclusive_group":"resonance_lock_wave"})

func _setup_escort() -> void:
	host.required_count = 1
	var entry: Vector2 = host.layout.get("entry", Vector2(180, 900))
	host.add_element("escort_light", host.safe_point(entry + Vector2(100, 0)), "定位光点", "escort", CRYSTAL, {"description":"先选一条路线，再靠近光点护送","stability":stability})
	for index: int in range(3):
		host.add_element("route_" + str(index), Vector2.ZERO, ["上侧内院", "中央石街", "下侧内院"][index], "route", RECEIVER, {"route":index})
		host.add_element("echo_fragment_" + str(index), host.safe_point(Vector2(780 + index * 600, 1420 - (index % 2) * 1100)), "回声碎片", "pickup", CRYSTAL, {"description":"回收可稳定光点；不是必需目标"})
	host.add_element("attack_echo", entry, "攻击回声", "echo", CRYSTAL, {"active":false})
	_update_route_choices()

func _update_route_choices() -> void:
	var light: Dictionary = host.element("escort_light")
	var destination: Vector2 = host.point(0)
	var center: Vector2 = Vector2(720.0 + route_step * 590.0, 900.0)
	if route_step >= 3:
		center = destination
	for index: int in range(3):
		var route: Dictionary = host.element("route_" + str(index))
		route.position = host.safe_point(Vector2(light.position) + Vector2(65, float(index - 1) * 82.0))
		route.destination = host.safe_point(center + Vector2(0.0, 0.0 if route_step >= 3 else float(index - 1) * 450.0))
		route.description = "E 选择此段路线；光点只在你靠近时前进"
		route.active = true

func _tick_escort(delta: float) -> void:
	var actual_sound: float = float(_property(host.room, "last_player_sound_time", -100.0))
	if actual_sound > sound_seen:
		sound_seen = actual_sound
		on_player_sound(_property(host.room, "last_player_sound_position", host.player().position), {"damage_source":"primary","original_basic":true})
	if clock >= sound_until:
		host.element("attack_echo").active = false
	if route_index < 0:
		return
	var light: Dictionary = host.element("escort_light")
	if not host.near(light.position, 185.0):
		return
	var nearby: Array = host.enemies_near(light.position, 140.0)
	stability = maxf(35.0, stability - (delta * 3.0 if not nearby.is_empty() else 0.0))
	light.stability = stability
	var target: Vector2 = host.element("route_" + str(route_index)).destination
	var arrived: bool = host.move_element("escort_light", target, 105.0 if nearby.is_empty() else 62.0, delta)
	light.progress = (float(route_step) + (0.75 if not arrived else 1.0)) / 4.0
	if arrived:
		route_step += 1
		route_index = -1
		host.event("escort_route_reached", {"step":route_step,"position":light.position})
		if route_step >= 4:
			host.set_done("escort_light")
			_complete("full" if stability >= 60.0 else "reduced")
		else:
			_update_route_choices()

func _setup_mirrors() -> void:
	host.required_count = 2
	for index: int in range(2):
		host.add_element("inscription_" + str(index), host.safe_point(host.point(index)), "遗迹铭文 " + str(index + 1), "receiver", OBELISK, {"description":"将校准光束对准这里，保持 1.6 秒"})
	var keys: Array[String] = ["west_reflector_causeway", "east_reflector_causeway", "north_reflector_causeway", "south_reflector_causeway"]
	for index: int in range(4):
		var at: Vector2 = host.safe_point(_marker(keys[index], Vector2(930 + (index % 2) * 880, 680 + (index / 2) * 420)))
		var inlet: Vector2 = host.safe_point(at + Vector2(0, -115.0))
		var target: Vector2 = host.element("inscription_" + str(index % 2)).position
		var incoming: Vector2 = inlet.direction_to(at)
		var desired: Vector2 = at.direction_to(target)
		var normal: Vector2 = (incoming - desired).normalized()
		if normal.is_zero_approx():
			normal = incoming.orthogonal()
		# A quarter turn of the surface would reverse the reflected ray into
		# the opposite inscription. Start one 45-degree interaction short of
		# alignment so all initial rays leave sideways without solving a goal.
		var mirror: Dictionary = {"position":at,"inlet":inlet,"angle":normal.angle() - PI / 4.0,"target":index % 2}
		mirrors.append(mirror)
		host.add_element("mirror_" + str(index), at, "反射石 " + str(index + 1), "mirror", CRYSTAL, {"index":index,"angle":mirror.angle,"description":"E 转动 45°；只反射场景校准光"})
		host.add_element("mirror_inlet_" + str(index), inlet, "校准光源", "beam", "", {"beam_from":inlet,"beam_to":at,"beam_color":Color(.7,.8,.57,.7),"interactive":false,"required":false,"visual_height":28.0})
	_tick_mirrors(0.0)

func _tick_mirrors(delta: float) -> void:
	var lit: Array[int] = []
	for index: int in range(mirrors.size()):
		var mirror: Dictionary = mirrors[index]
		var at: Vector2 = mirror.position
		var incoming: Vector2 = Vector2(mirror.inlet).direction_to(at)
		var normal := Vector2.from_angle(float(mirror.angle))
		var outgoing: Vector2 = (incoming - 2.0 * normal * incoming.dot(normal)).normalized()
		var end: Vector2 = at + outgoing * 1300.0
		if host.room.has_method("blocked_fraction"):
			end = at.lerp(end, float(host.room.blocked_fraction(at, end, 0.0)))
		var element: Dictionary = host.element("mirror_" + str(index))
		element.beam_from = at
		element.beam_to = end
		element.incident_from = mirror.inlet
		element.angle = mirror.angle
		for target_index: int in range(2):
			var inscription: Dictionary = host.element("inscription_" + str(target_index))
			if _segment_distance(inscription.position, at, end) <= 42.0 and outgoing.dot(Vector2(inscription.position) - at) > 0.0 and not lit.has(target_index):
				lit.append(target_index)
	for target_index: int in range(2):
		var inscription: Dictionary = host.element("inscription_" + str(target_index))
		inscription.lit = lit.has(target_index)
		if bool(inscription.done):
			continue
		if bool(inscription.lit):
			inscription.progress = minf(1.0, float(inscription.progress) + delta / 1.6)
			if float(inscription.progress) >= 1.0:
				host.set_done("inscription_" + str(target_index))
				host.event("inscription_illuminated", {"index":target_index})
	if int(host.completed_count) >= 2:
		_complete()

func _setup_weaving() -> void:
	host.required_count = 3
	var entry: Vector2 = host.layout.get("entry", Vector2(180, 900))
	for index: int in range(3):
		host.add_element("sound_shape_" + str(index), host.safe_point(entry + Vector2(180, float(index - 1) * 115.0)), SHAPES[index] + "声纹", "pickup", CRYSTAL, {"index":index,"description":"E 选择携带此形状；找相同纹样织柱"})
		var at: Vector2 = host.safe_point(host.point(index))
		host.add_element("weave_column_" + str(index), at, SHAPES[index] + "织柱", "receiver", OBELISK, {"index":index,"description":"安装同形声纹；错误只触发预警，不清进度"})
		_add_weave_line(index, at)

func _tick_weaving() -> void:
	if selected_shape >= 0 and is_instance_valid(host.player()):
		host.element("sound_shape_" + str(selected_shape)).position = host.player().position + Vector2(0, -25)

func _add_weave_line(index: int, at: Vector2) -> void:
	# Authored spawn/goal anchors must remain reachable. Try both sides of
	# the column instead of silently losing a line when a spawn is too close.
	for offset: float in [-105.0, 105.0, -165.0, 165.0]:
		var anchor: Vector2 = host.safe_point(at + Vector2(offset, -60))
		var end: Vector2 = host.safe_point(at + Vector2(offset, 60))
		var blocker := Rect2(Vector2(minf(anchor.x, end.x) - 10.0, minf(anchor.y, end.y)), Vector2(20.0, maxf(30.0, absf(end.y - anchor.y))))
		if not host.set_blocker("weave_line_" + str(index), blocker, true):
			continue
		var knot: Dictionary = host.add_target("weave_knot_" + str(index), anchor - Vector2(0, 36), 28.0, CRYSTAL, "线结 · 可普攻切断", {"objective_target":true})
		host.add_element("weave_line_" + str(index), (anchor + end) * 0.5, "可切断线束", "beam", "", {"beam_from":knot.position,"beam_to":end,"description":"攻击线结可永久切断；外圈保留绕行"})
		return

func _weave_mistake(index: int) -> void:
	if mistake_cooldown > 0.0:
		return
	mistake_cooldown = 1.5
	var at: Vector2 = host.element("weave_column_" + str(index)).position
	host.add_hazard(at - Vector2(0, 115), 14.0, 7.0, 1.1, 0.25, {"shape":"line","target":at + Vector2(0, 115),"width":28.0,"enemies":true})
	host.event("sound_shape_mismatch", {"column":index,"carried":selected_shape,"progress_preserved":true})

func _clear_weave_lines() -> void:
	for index: int in range(3):
		host.remove_blocker("weave_line_" + str(index))
		var line: Dictionary = host.element("weave_line_" + str(index))
		if not line.is_empty():
			line.active = false

func _setup_lamps() -> void:
	host.required_count = 2
	var exit: Vector2 = host.layout.get("exit", Vector2(2696, 900))
	var receiver: Vector2 = host.safe_point(exit - Vector2(180, 0))
	host.add_element("lamp_receiver", receiver, "双光接收器", "receiver", OBELISK, {"description":"带灯时 E 安放；两束光后可 E 选金币完成，三灯全保"})
	var keys: Array[String] = ["north_bridge", "middle_bridge", "south_bridge"]
	for index: int in range(3):
		var at: Vector2 = host.safe_point(host.point(index))
		lamps.append({"position":at,"home":at,"docked":false,"was_taken":false})
		bridges.append(_marker(keys[index], Vector2(1400, 410 + index * 500)))
		host.add_element("lamp_" + str(index), at, "移动矿灯 " + str(index + 1), "lamp", RECEIVER, {"index":index,"description":"E 搬运/放下；失落时回到可达灯座"})
		host.add_element("bridge_" + str(index), bridges[index], "石桥 " + str(index + 1), "bridge", "", {"description":"暗桥收缩前显示倒计时；桥上有人时等待","illuminated":false})
		_register_lamp(index, at)

func _tick_lamps(delta: float) -> void:
	for index: int in range(lamps.size()):
		var lamp: Dictionary = lamps[index]
		var item: Dictionary = host.element("lamp_" + str(index))
		var entity: Dictionary = _lamp_entity(index)
		var thief_id: int = int(entity.get("taken_by", 0))
		if thief_id != 0:
			var thief: Object = instance_from_id(thief_id)
			if is_instance_valid(thief) and (not thief.has_method("is_alive") or thief.is_alive()):
				lamp.position = thief.position
				lamp.was_taken = true
				lamp.docked = false
				item.done = false
				item.description = "被吞灯兽搬走：击败它会完整归还"
				if carried_lamp == index:
					carried_lamp = -1
			else:
				entity.taken_by = 0
				entity.dark_remaining = 0.0
				_return_lamp(index)
		elif bool(lamp.was_taken):
			_return_lamp(index)
		elif carried_lamp == index:
			lamp.position = host.player().position
			item.description = "正在携带：到出口接收器 E 安放，或 E 安全放下"
		elif not entity.is_empty() and not bool(lamp.docked):
			lamp.position = entity.get("position", lamp.position)
		if not _valid_point(lamp.position, 10.0):
			_return_lamp(index)
		item.position = lamp.position
		item.beam_from = lamp.position
		lamp.bridge_target = _nearest_bridge(lamp.position) if not bool(lamp.docked) and thief_id == 0 else -1
		item.beam_to = host.element("lamp_receiver").position if bool(lamp.docked) else (bridges[int(lamp.bridge_target)] if int(lamp.bridge_target) >= 0 else lamp.position)
		item.beam_color = Color(.7, .86, .55, .7 if thief_id == 0 else 0.0)
		item.lit = thief_id == 0
		if not entity.is_empty():
			entity.position = lamp.position
			entity.enabled = not bool(lamp.docked)
	_tick_bridges(delta)
	host.completed_count = _lit_lamp_count()
	if _lit_lamp_count() >= 3:
		_complete()

func _tick_bridges(delta: float) -> void:
	for index: int in range(3):
		var illuminated: bool = false
		for lamp_index: int in range(lamps.size()):
			if int(_lamp_entity(lamp_index).get("taken_by", 0)) == 0 and int(lamps[lamp_index].get("bridge_target", -1)) == index:
				illuminated = true
		var bridge: Dictionary = host.element("bridge_" + str(index))
		bridge.illuminated = illuminated
		if illuminated and closed_bridge == index:
			host.remove_blocker("retract_bridge_" + str(index))
			closed_bridge = -1
	bridge_cycle -= delta
	if warned_bridge < 0 and bridge_cycle <= 0.0:
		bridge_cycle = 8.0
		for offset: int in range(3):
			var index: int = (pulse_index + offset) % 3
			if not bool(host.element("bridge_" + str(index)).illuminated):
				warned_bridge = index
				bridge_warning = 2.2
				pulse_index = index + 1
				break
	if warned_bridge < 0:
		return
	var warning: Dictionary = host.element("bridge_" + str(warned_bridge))
	if bool(warning.illuminated):
		warned_bridge = -1
		warning.progress = 0.0
		return
	bridge_warning = maxf(0.0, bridge_warning - delta)
	warning.progress = 1.0 - bridge_warning / 2.2
	warning.description = "暗桥将收缩：%.1f 秒；桥上有人时等待" % bridge_warning
	var center: Vector2 = bridges[warned_bridge]
	if bridge_warning > 0.0 or host.near(center, 165.0) or not host.enemies_near(center, 170.0).is_empty():
		return
	if closed_bridge >= 0:
		host.remove_blocker("retract_bridge_" + str(closed_bridge))
	var index: int = warned_bridge
	if host.set_blocker("retract_bridge_" + str(index), Rect2(center + Vector2(-18, -115), Vector2(36, 230)), true):
		closed_bridge = index
		host.event("dark_bridge_retracted", {"bridge":index,"remaining_open":2})
	warned_bridge = -1

func _nearest_bridge(at: Vector2) -> int:
	var nearest: int = -1
	var distance: float = 520.0
	for index: int in range(bridges.size()):
		var next_distance: float = at.distance_to(bridges[index])
		if next_distance < distance:
			nearest = index
			distance = next_distance
	return nearest

func _dock_lamp(index: int) -> void:
	var receiver: Vector2 = host.element("lamp_receiver").position
	lamps[index].position = host.safe_point(receiver + Vector2(-48, float(index - 1) * 62.0))
	lamps[index].docked = true
	carried_lamp = -1
	host.element("lamp_" + str(index)).done = true
	host.element("lamp_" + str(index)).description = "已向出口投射光束"
	var entity: Dictionary = _lamp_entity(index)
	if not entity.is_empty():
		entity.position = lamps[index].position
		entity.enabled = false
	host.event("lamp_docked", {"index":index,"beams":_lit_lamp_count()})

func _drop_lamp(index: int) -> void:
	lamps[index].position = host.safe_point(host.player().position)
	carried_lamp = -1
	var entity: Dictionary = _lamp_entity(index)
	if not entity.is_empty():
		entity.position = lamps[index].position
	host.element("lamp_" + str(index)).position = lamps[index].position

func _return_lamp(index: int) -> void:
	var nearest: Vector2 = lamps[index].home
	var distance: float = INF
	for stand: Dictionary in lamps:
		var candidate: Vector2 = stand.home
		if _valid_point(candidate, 14.0) and Vector2(lamps[index].position).distance_squared_to(candidate) < distance:
			nearest = candidate
			distance = Vector2(lamps[index].position).distance_squared_to(candidate)
	lamps[index].position = host.safe_point(nearest)
	lamps[index].was_taken = false
	lamps[index].docked = false
	if carried_lamp == index:
		carried_lamp = -1
	var entity: Dictionary = _lamp_entity(index)
	if not entity.is_empty():
		entity.position = lamps[index].position
		entity.taken_by = 0
		entity.dark_remaining = 0.0
		entity.enabled = true
	host.element("lamp_" + str(index)).description = "矿灯已完整回到安全灯座，可再次搬运"
	host.event("lamp_recovered", {"index":index,"position":lamps[index].position})

func _register_lamp(index: int, at: Vector2) -> void:
	var props: Variant = _property(host.room, "enemy_props", null)
	if not is_instance_valid(props):
		return
	var entities: Variant = _property(props, "entities", null)
	if entities is Array:
		for entity_index: int in range(entities.size() - 1, -1, -1):
			if str(entities[entity_index].get("id", "")) == "L23:objective_lamp:" + str(index):
				entities.remove_at(entity_index)
		entities.append({"id":"L23:objective_lamp:" + str(index),"kind":"scene_lamp","tags":["scene_lamp","objective_lamp"],"position":at,"radius":22.0,"enabled":true,"taken_by":0,"dark_remaining":0.0,"cooldown":0.0})

func _lamp_entity(index: int) -> Dictionary:
	var props: Variant = _property(host.room, "enemy_props", null)
	var entities: Variant = _property(props, "entities", [])
	for entity: Dictionary in entities:
		if str(entity.get("id", "")) == "L23:objective_lamp:" + str(index):
			return entity
	return {}

func _lit_lamp_count() -> int:
	var count: int = 0
	for index: int in range(lamps.size()):
		if bool(lamps[index].docked) and int(_lamp_entity(index).get("taken_by", 0)) == 0:
			count += 1
	return count

func _setup_discs() -> void:
	host.required_count = 3
	var keys: Array[String] = ["western_disc", "northwest_disc", "northeast_disc", "eastern_disc", "southern_disc"]
	var names: Array[String] = ["圆", "叉", "三角", "波", "菱"]
	for index: int in range(5):
		var at: Vector2 = host.safe_point(_marker(keys[index], host.point(index % 3)))
		host.add_element("echo_disc_" + str(index), at, str(index + 1) + " · " + names[index], "pressure", CRYSTAL, {"index":index,"description":"踏入石盘；顺序始终显示在记录碑和目标提示","radius":42.0})
	host.add_element("sequence_record", host.safe_point(Vector2(1400, 1160)), "顺序：" + _sequence_text(), "record", OBELISK, {"description":_sequence_text(),"always_label":true})

func _tick_discs() -> void:
	var current: int = -1
	for index: int in range(5):
		if host.near(host.element("echo_disc_" + str(index)).position, 42.0):
			current = index
			break
	if current < 0:
		last_disc = -1
		return
	if current == last_disc:
		return
	last_disc = current
	if current == sequence[sequence_progress]:
		var previous_index: int = last_correct_disc
		if last_correct_disc >= 0:
			var previous: Vector2 = host.element("echo_disc_" + str(last_correct_disc)).position
			host.add_hazard(previous, 88.0, 9.0, 1.3, 0.25, {"shape":"ring","inner_radius":0.0,"enemies":true})
		last_correct_disc = current
		sequence_progress += 1
		host.set_done("echo_disc_" + str(current))
		host.event("echo_sequence_step", {"disc":current,"progress":sequence_progress,"previous_echo":previous_index})
		if sequence_progress >= sequence.size():
			_complete()
	elif mistake_cooldown <= 0.0:
		mistake_cooldown = 1.5
		host.add_hazard(host.element("echo_disc_" + str(current)).position, 76.0, 7.0, 1.2, 0.25, {"shape":"ring","inner_radius":0.0,"enemies":true})
		host.event("echo_sequence_mistake", {"disc":current,"progress_preserved":sequence_progress})

func _sequence_text() -> String:
	return "①圆 → ③三角 → ⑤菱"

func _complete(quality: String = "full") -> void:
	if finished:
		return
	finished = true
	for index: int in range(3):
		host.remove_blocker("retract_bridge_" + str(index))
	if str(host.room_id) == "L20":
		for index: int in range(3):
			host.element("route_" + str(index)).active = false
	host.finish(quality)

func _marker(kind: String, fallback: Vector2) -> Vector2:
	for marker: Dictionary in host.layout.get("visual_markers", []):
		if str(marker.get("kind", "")) == kind:
			return marker.position
	return fallback

func _valid_point(at: Vector2, radius: float) -> bool:
	return not host.room.has_method("valid_ground") or bool(host.room.valid_ground(at, radius))

func _paused() -> bool:
	return host != null and is_instance_valid(host.room) and host.room.is_inside_tree() and host.room.get_tree().paused

func _property(object: Variant, key: String, fallback: Variant) -> Variant:
	if not is_instance_valid(object) or not object is Object:
		return fallback
	for property: Dictionary in object.get_property_list():
		if str(property.name) == key:
			return object.get(key)
	return fallback

func _segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var t: float = clampf((point - start).dot(segment) / maxf(0.001, segment.length_squared()), 0.0, 1.0)
	return point.distance_to(start + segment * t)
