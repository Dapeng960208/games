extends RefCounted
## Rust mine objectives. All control points stay reachable using basic movement.
var host
var timer: float = 0.0
var phase: int = 0
var carried: String = ""
var cart_route: Array[Vector2] = []
var route_index: int = 0
var unloaded: bool = false
var stopped: bool = false
var valves: Array[float] = [28.0, 76.0, 35.0]
var furnace_stable: float = 0.0
var belt_direction: float = 1.0
var tracks: Array[Dictionary] = []
var plate_progress: Array[float] = [0.0, 0.0]
var last_pressure: Array[float] = [0.0, 0.0]
var bridge_change: Dictionary = {}
var loaded_edges: Dictionary = {}

func configure(next_host) -> void:
	host = next_host
	match host.room_id:
		"L01":
			for i in 3:
				host.add_element("brake_" + str(i), host.point(i), "制动器 " + str(i + 1), "brake", "B01_winch", {"description": "释放后矿车通过亮灯轨道，敌我都需避让", "always_label": true})
			_add_side_crate()
		"L02":
			var start: Vector2 = host.safe_point(host.layout.entry + Vector2(180, 0))
			host.add_element("cargo_cart", start, "载货滑车", "escort", "B01_ore_cart", {"description": "靠近自动推车，离开暂停；保全重货：18 金币 + 1 件防具；E 卸货提速：34 金币，不含装备", "interaction_label": "卸货提速 · 完成获 34 金币，无装备", "cargo_health": 100.0, "repeatable": true, "always_label": true})
			cart_route = [host.safe_point(Vector2(950, 430)), host.safe_point(Vector2(1780, 1370)), host.point(0)]
			for index in cart_route.size():
				_optional("route_" + str(index), cart_route[index], "滑车路线 " + str(index + 1), "", "", false)
			timer = 6.0
		"L03":
			for i in 2:
				host.add_element("key_" + str(i), host.point(i), "齿轮钥芯 " + str(i + 1), "key", "B01_crate_stack", {"description": "取走钥芯，留意夹击刻线；不停机完成：12 金币 + 1 件机动装备", "visual_height": 70.0})
			_optional("gear_stop", host.safe_point(Vector2(1400, 300)), "齿轮总停机", "B01_winch", "关闭地面旋转与咬合；停机完成：30 金币，不含装备")
			timer = 4.0
		"L04":
			var shapes: Array[String] = ["▲", "●", "◆"]
			for i in 3:
				var at: Vector2 = host.point(i)
				host.add_element("scale_" + str(i), at, shapes[i] + " 秤台", "scale", "B01_winch", {"description": "搬入相同形状矿匣；错误配对不丢失矿匣；完成：14 金币 + 1 件进攻装备", "shape": i, "always_label": true})
				_optional("crate_" + str(i), host.safe_point(at + Vector2(-1500, 0)), shapes[i] + " 矿匣", "B01_crate_stack", "E 拾起；搬运时仍可攻击，再次 E 可放下")
				host.element("crate_" + str(i))["shape"] = i
			_optional("drop_crate", host.layout.entry, "放下矿匣", "", "安全放在脚边")
			host.element("drop_crate").active = false
			timer = 7.0
		"L05":
			for i in 2:
				host.add_element("beacon_" + str(i), host.point(i), "救援供电 " + str(i + 1), "hold", "B01_winch", {"description": "环内供电 8 秒，离开保留进度；敌群载重增加边缘压力；完成：18 金币 + 1 件生存装备", "interactive": false, "always_label": true, "radius": 105.0})
		"L06":
			var labels: Array[String] = ["卸压", "降温", "排渣"]
			for i in 3:
				host.add_element("valve_" + str(i), host.point(i), labels[i], "valve", "B01_winch", {"description": "E 将此表向 50 校准；会缓慢扰动另两表，三表保持 38–62 共 4 秒", "repeatable": true, "always_label": true})
			_optional("furnace_core", host.safe_point(Vector2(1400, 880)), "取出炉芯", "B01_crate_stack", "三表稳定后取芯：24 金币 + 2 件进攻装备")
			host.element("furnace_core").active = false
			_optional("furnace_cut", host.safe_point(host.layout.exit + Vector2(-200, 160)), "紧急切断炉管", "B01_crate_stack", "立即结束调压；切管完成：8 金币，不含装备")
			timer = 5.0

func configure_cleared(next_host, claimed_optional: Array = []) -> void:
	host = next_host
	if host.room_id == "L01" and not claimed_optional.has("side_crate"):
		_add_side_crate()

func _add_side_crate() -> void:
	_optional("side_crate", host.safe_point(host.layout.exit + Vector2(-260, 230)), "装卸侧箱", "B01_crate_stack", "清理敌群并完成目标后：18 金币 + 1 件职业防具；装备撤离后保留")
	host.element("side_crate").merge({"optional_reward": true, "claim_message": "侧箱已回收：18 金币 + 1 件职业防具；装备需成功撤离保留", "claim_event": "optional_salvage", "reward_tendency": "defense_gold"}, true)

func _optional(id: String, at: Vector2, label: String, asset: String, description: String, interactive: bool = true) -> void:
	host.add_element(id, at, label, "utility", asset, {"description": description, "required": false, "interactive": interactive})

func tick(delta: float) -> void:
	if host.room_id == "L01":
		_tick_tracks(delta)
		return
	if host.finished:
		return
	match host.room_id:
		"L02": _tick_escort(delta)
		"L03": _tick_gears(delta)
		"L04": _tick_belts(delta)
		"L05": _tick_beacons(delta)
		"L06": _tick_furnace(delta)

func interact(id: String, actor: Node2D) -> bool:
	if host.finished and id != "side_crate":
		return false
	match host.room_id:
		"L01":
			if id.begins_with("brake_"):
				var index: int = int(id.trim_prefix("brake_"))
				if host.role != "elite_objective" and index != host.completed_count:
					host.message = "按编号释放；精英目标可自由决定次序"
					return false
				host.set_done(id)
				_release_cart(index)
				if host.completed_count >= 3:
					host.finish()
				return true
			if id == "side_crate" and host.finished:
				return host.claim_optional(id)
		"L02":
			if id == "cargo_cart" and not unloaded:
				unloaded = true
				host.quality = "reduced"
				host.element(id).label = "轻载滑车"
				host.element(id).interactive = false
				host.element(id).description = "轻载滑车：靠近 165 步推动；完成获得 34 金币，不含装备"
				host.message = "已卸下重货：滑车提速；完成获得 34 金币，不含装备"
				return true
		"L03":
			if id == "gear_stop":
				stopped = true
				host.set_done(id)
				host.message = "齿轮已停机：完成获得 30 金币，不含装备"
				return true
			if id.begins_with("key_"):
				host.set_done(id)
				if host.completed_count >= 2:
					host.finish("full" if stopped else "mobile")
					host.element("gear_stop").interactive = false
				return true
		"L04":
			if id == "drop_crate":
				return _drop_crate(actor)
			if id.begins_with("crate_") and carried.is_empty():
				carried = id
				host.element(id).carried = true
				host.element("drop_crate").active = true
				host.element("drop_crate").position = actor.position
				return true
			if id.begins_with("scale_") and not carried.is_empty():
				if int(host.element(carried).shape) != int(host.element(id).shape):
					host.add_hazard(host.element(id).position, 100, 10, 1.2, .2)
					host.message = "形状不匹配！矿匣已保留，躲开秤台冲击后重新分拣"
					return true
				host.set_done(id)
				host.element(carried).active = false
				carried = ""
				host.element("drop_crate").active = false
				if host.completed_count >= 3:
					host.finish()
				return true
		"L06":
			if id.begins_with("valve_"):
				var index: int = int(id.trim_prefix("valve_"))
				var correction: float = clampf(50 - valves[index], -18, 18)
				valves[index] += correction
				valves[(index + 1) % 3] = clampf(valves[(index + 1) % 3] - correction * .12, 0, 100)
				valves[(index + 2) % 3] = clampf(valves[(index + 2) % 3] + correction * .08, 0, 100)
				host.event("valve_adjusted", {"index": index, "values": valves.duplicate()})
				return true
			if id == "furnace_core" and furnace_stable >= 4.0:
				for index in 3:
					host.set_done("valve_" + str(index))
				host.set_done(id)
				host.finish()
				return true
			if id == "furnace_cut":
				host.set_done(id)
				host.finish("reduced")
				host.message = "紧急切管完成：8 金币，不含装备；清理剩余敌人后开放通路"
				return true
	return false

func _release_cart(index: int) -> void:
	var start: Vector2 = host.element("brake_" + str(index)).position
	var end: Vector2 = host.safe_point(start + Vector2(450 if index != 1 else -450, 0))
	host.add_hazard(start, 1, 28, 1.4, 1.3, {"shape": "line", "target": end, "width": 62.0, "enemies": true})
	var id: String = "passing_cart_" + str(index)
	_optional(id, start, "矿车来向 →", "B01_ore_cart", "", false)
	tracks.append({"id": id, "start": start, "end": end, "time": -1.4})
	host.event("minecart_bell", {"position": start, "target": end})
	if is_instance_valid(host.room.get("combat_audio")):
		host.room.combat_audio.pickup()

func _tick_tracks(delta: float) -> void:
	for track: Dictionary in tracks:
		track.time = float(track.time) + delta
		if float(track.time) >= 0:
			host.element(track.id).position = Vector2(track.start).lerp(track.end, clampf(float(track.time) / 1.3, 0, 1))
		if float(track.time) > 1.3:
			host.element(track.id).active = false

func _tick_escort(delta: float) -> void:
	var cart: Dictionary = host.element("cargo_cart")
	if not bridge_change.is_empty():
		bridge_change.tell = float(bridge_change.tell) - delta
		if float(bridge_change.tell) <= 0 and not bool(bridge_change.closed):
			var rect: Rect2 = bridge_change.rect
			if not rect.grow(35).has_point(cart.position):
				bridge_change.closed = host.set_blocker("collapsed_bridge", rect)
			bridge_change.attempts = int(bridge_change.attempts) + 1
			# Do not retry expensive route validation each frame when the bridge is
			# structurally unsafe to close. Occupancy simply postpones this cycle.
			if not bool(bridge_change.closed):
				bridge_change.clear()
		elif bool(bridge_change.get("closed", false)):
			bridge_change.life = float(bridge_change.life) - delta
			if float(bridge_change.life) <= 0:
				host.remove_blocker("collapsed_bridge")
				bridge_change.clear()
	if host.near(cart.position, 165):
		if host.move_element("cargo_cart", cart_route[route_index], 110.0 if unloaded else 78.0, delta):
			route_index += 1
			if route_index >= cart_route.size():
				host.remove_blocker("collapsed_bridge")
				cart.interactive = false
				host.set_done("cargo_cart")
				host.finish("reduced" if unloaded or float(cart.cargo_health) < 50 else "full")
				return
		cart.phase = "推行中"
	else:
		cart.phase = "等待靠近"
	var enemies: Array = host.enemies_near(cart.position, 105)
	if not enemies.is_empty() and not unloaded:
		var previous_health: float = float(cart.cargo_health)
		cart.cargo_health = maxf(0, float(cart.cargo_health) - delta * 2.0)
		if previous_health >= 50.0 and float(cart.cargo_health) < 50.0:
			cart.description = "重货损失过半：完成获得 34 金币，不含装备；E 卸货可提速"
			host.message = "重货损失过半：完成改为 34 金币，不含装备；可卸货提速"
		if float(cart.cargo_health) <= 0:
			unloaded = true
			cart.label = "轻载滑车"
			cart.interactive = false
			cart.description = "轻载滑车：靠近 165 步推动；完成获得 34 金币，不含装备"
			host.message = "重货受损，滑车仍可护送；完成获得 34 金币，不含装备"
	cart.progress = float(route_index) / float(cart_route.size())
	timer -= delta
	if timer <= 0:
		timer = 9.0
		phase = 1 - phase
		var zones: Array = host.layout.get("hazard_zones", [])
		if zones.size() >= 2:
			var rect: Rect2 = zones[phase].rect
			host.add_hazard(rect.position + Vector2(0, rect.size.y * .5), 1, 0, 1.8, .2, {"shape": "line", "target": rect.end - Vector2(0, rect.size.y * .5), "width": rect.size.y})
			bridge_change = {"rect": rect, "tell": 1.8, "closed": false, "life": 4.0, "attempts": 0}
			host.event("bridge_crack", {"rect": rect, "preserve_other_route": true})

func _tick_gears(delta: float) -> void:
	if stopped:
		return
	var actor: Node2D = host.player()
	for index in 2:
		var center: Vector2 = host.point(index)
		var offset: Vector2 = actor.position - center
		if offset.length() <= 160 and offset.length() > 12:
			host.displace(actor, offset.normalized().orthogonal() * (28 if index == 0 else -28) * delta)
	timer -= delta
	if timer <= 0:
		timer = 4.0
		var at: Vector2 = host.point(phase % 2) + Vector2(85, 0)
		host.add_hazard(at, 65, 14, 1.2, .25)
		phase += 1

func _tick_belts(delta: float) -> void:
	timer -= delta
	if timer <= 0:
		timer = 7.0
		belt_direction *= -1
		host.event("belt_reversed", {"direction": belt_direction})
	var actor: Node2D = host.player()
	for index in 3:
		var y: float = host.point(index).y
		if absf(actor.position.y - y) < 70 and actor.position.x > 650 and actor.position.x < 2160:
			host.displace(actor, Vector2(35 * belt_direction * delta, 0))
		var id: String = "crate_" + str(index)
		var crate: Dictionary = host.element(id)
		if crate.active and id != carried and absf(Vector2(crate.position).y - y) < 90:
			var next: Vector2 = crate.position + Vector2(22 * belt_direction * delta, 0)
			next.x = clampf(next.x, 690, 1980)
			crate.position = host.room.move_actor(crate.position, next - Vector2(crate.position), 24.0)
	if not carried.is_empty():
		host.element(carried).position = actor.position + Vector2(0, -40)
		host.element("drop_crate").position = actor.position
		# A nearby matching or wrong scale must win E over the drop action.
		var near_scale: bool = false
		for index in 3:
			if not bool(host.element("scale_" + str(index)).done) and host.near(host.point(index), 100):
				near_scale = true
		host.element("drop_crate").interactive = not near_scale

func _drop_crate(actor: Node2D) -> bool:
	if carried.is_empty():
		return false
	var crate: Dictionary = host.element(carried)
	crate.position = host.safe_point(actor.position + Vector2(0, 48))
	crate.carried = false
	carried = ""
	host.element("drop_crate").active = false
	return true

func _tick_beacons(delta: float) -> void:
	for index in 2:
		var id: String = "beacon_" + str(index)
		var beacon: Dictionary = host.element(id)
		if beacon.done:
			continue
		if host.near(beacon.position, 105):
			plate_progress[index] = minf(8.0, plate_progress[index] + delta)
		beacon.progress = plate_progress[index] / 8.0
		var weight: int = host.enemies_near(beacon.position, 145).size() + (1 if host.near(beacon.position, 145) else 0)
		beacon.phase = "载重 " + str(weight)
		last_pressure[index] -= delta
		if weight >= 3 and last_pressure[index] <= 0:
			last_pressure[index] = 4.0
			host.add_hazard(beacon.position, 155, 10, 1.2, .3, {"shape": "ring", "inner_radius": 112.0})
			var zones: Array = host.layout.get("hazard_zones", [])
			var edge_index: int = 0 if index == 0 else 3
			if zones.size() > edge_index and not loaded_edges.has(index):
				loaded_edges[index] = {"rect": zones[edge_index].rect, "tell": 1.2, "closed": false}
		if loaded_edges.has(index):
			var edge: Dictionary = loaded_edges[index]
			edge.tell = float(edge.tell) - delta
			if weight < 3:
				host.remove_blocker("pod_edge_" + str(index))
				loaded_edges.erase(index)
			elif float(edge.tell) <= 0 and not bool(edge.closed):
				edge.closed = host.set_blocker("pod_edge_" + str(index), edge.rect)
				if not bool(edge.closed):
					loaded_edges.erase(index)
		if plate_progress[index] >= 8:
			host.set_done(id)
	if host.completed_count >= 2:
		for index in 2:
			host.remove_blocker("pod_edge_" + str(index))
		host.finish()

func _tick_furnace(delta: float) -> void:
	var stable: bool = true
	for index in 3:
		if furnace_stable < 4:
			valves[index] = clampf(valves[index] + sin(host.elapsed * .3 + index * 2.1) * .45 * delta, 0, 100)
		stable = stable and valves[index] >= 38 and valves[index] <= 62
		var item: Dictionary = host.element("valve_" + str(index))
		item.phase = str(roundi(valves[index])) + " / 38–62"
		item.progress = clampf(1 - absf(valves[index] - 50) / 50, 0, 1)
	if stable:
		furnace_stable = minf(4, furnace_stable + delta)
	else:
		furnace_stable = maxf(0, furnace_stable - delta * .5)
	if furnace_stable >= 4:
		host.element("furnace_core").active = true
		host.message = "三表已锁定稳定！前往中心取芯"
	timer -= delta
	if timer <= 0 and furnace_stable < 4:
		timer = 5.0
		host.add_hazard(host.point(phase % 3) + Vector2(100, 50), 75, 12, 1.4, .4)
		phase += 1

func status_text() -> String:
	match host.room_id:
		"L01":
			if host.finished:
				return "侧箱：18 金币 + 职业防具 · 清理敌群后可回收" if host.optional_ids().has("side_crate") else "制动完成 · 侧箱已回收"
			return "释放制动器 %d/3 · %s" % [host.completed_count, "自由选择顺序" if host.role == "elite_objective" else "按 1 → 2 → 3"]
		"L02":
			var reduced: bool = unloaded or float(host.element("cargo_cart").get("cargo_health", 100.0)) < 50.0
			return "靠近自动推车 %d/3 · %s" % [route_index, "34 金币 · 无装备" if reduced else "18 金币 + 防具"]
		"L03": return "取回钥芯 %d/2 · %s" % [host.completed_count, "停机：30 金币 · 无装备" if stopped else "不停机：12 金币 + 机动装备"]
		"L04": return "搬匣分拣 %d/3%s · 14 金币 + 进攻装备" % [host.completed_count, " · 搬运中" if not carried.is_empty() else ""]
		"L05": return "占据信标 %d/2 · 18 金币 + 生存装备" % host.completed_count
		"L06":
			if host.finished:
				return "切管完成 · 8 金币 · 无装备" if host.quality == "reduced" else "精密取芯完成 · 24 金币 + 2 件进攻装备"
			return "调表 38–62：%d / %d / %d · 稳定 %.1f/4 秒 · 取芯 24 金币 + 2 件进攻装备" % [roundi(valves[0]), roundi(valves[1]), roundi(valves[2]), furnace_stable]
	return ""

func blocks_dash() -> bool:
	return false

func encounter_directive(index: int) -> Dictionary:
	if host.room_id != "L02" or index != 2:
		return {}
	# The final finite encounter guards the last escort leg. Reaching the old
	# far-side sector ahead of the cart must not spend this encounter early.
	return {"ready": route_index >= 2, "position": host.element("cargo_cart").position, "destination": cart_route.back()}

func navigation_target() -> Dictionary:
	var choices: Array[String] = []
	match host.room_id:
		"L01":
			if host.role != "elite_objective":
				choices.append("brake_" + str(mini(2, host.completed_count)))
			else:
				choices.assign(["brake_0", "brake_1", "brake_2"])
		"L02": choices.append("cargo_cart")
		"L03": choices.assign(["key_0", "key_1"])
		"L04":
			if not carried.is_empty():
				choices.append("scale_" + str(host.element(carried).shape))
			else:
				choices.assign(["crate_0", "crate_1", "crate_2"])
		"L05": choices.assign(["beacon_0", "beacon_1"])
		"L06":
			if furnace_stable >= 4:
				choices.append("furnace_core")
			else:
				for index in 3:
					if valves[index] < 38 or valves[index] > 62:
						choices.append("valve_" + str(index))
				if choices.is_empty():
					choices.append("valve_0")
	var nearest: Dictionary = {}
	var distance: float = INF
	for id: String in choices:
		var item: Dictionary = host.element(id)
		if item.is_empty() or bool(item.done) or not bool(item.active):
			continue
		var current: float = host.player().position.distance_squared_to(item.position)
		if current < distance:
			distance = current
			nearest = {"position": item.position, "id": id}
	return nearest

func draw_world(canvas: Node2D) -> void:
	match host.room_id:
		"L03":
			for index in 2:
				var center: Vector2 = host.point(index)
				canvas.draw_arc(center, 160, 0, TAU, 64, Color(.47, .42, .31, .46), 2, true)
				for tooth in 12:
					var angle: float = float(tooth) * TAU / 12.0 + (0.0 if stopped else host.elapsed * .13 * (1 if index == 0 else -1))
					var out: Vector2 = Vector2.RIGHT.rotated(angle)
					canvas.draw_line(center + out * 146, center + out * 159, Color(.58, .49, .32, .52), 4, true)
		"L04":
			for index in 3:
				var y: float = host.point(index).y
				for offset: float in [-70.0, 70.0]:
					canvas.draw_line(Vector2(650, y + offset), Vector2(2160, y + offset), Color(.44, .41, .31, .5), 2, true)
				for chevron in 10:
					var at := Vector2(700 + chevron * 140 + fmod(host.elapsed * 22 * belt_direction, 100), y)
					var direction := Vector2(12 * belt_direction, 0)
					canvas.draw_line(at - direction + Vector2(0, -8), at + direction, Color(.64, .51, .28, .46), 2, true)
					canvas.draw_line(at - direction + Vector2(0, 8), at + direction, Color(.64, .51, .28, .46), 2, true)
		"L05":
			for index in 2:
				var item: Dictionary = host.element("beacon_" + str(index))
				canvas.draw_arc(item.position, 105, 0, TAU, 64, Color(.43, .75, .7, .6), 2, true)
		"L06":
			for index in 3:
				var at: Vector2 = host.element("valve_" + str(index)).position + Vector2(-42, -108)
				canvas.draw_rect(Rect2(at, Vector2(84, 8)), Color(.14, .19, .18, .9))
				canvas.draw_rect(Rect2(at + Vector2(84 * .38, 0), Vector2(84 * .24, 8)), Color(.46, .73, .57, .9))
				canvas.draw_line(at + Vector2(84 * valves[index] / 100, -3), at + Vector2(84 * valves[index] / 100, 11), Color("ecd9a9"), 2)

func on_target_hit(_id: String, _context: Dictionary) -> void:
	pass

func on_target_destroyed(_id: String) -> void:
	pass
