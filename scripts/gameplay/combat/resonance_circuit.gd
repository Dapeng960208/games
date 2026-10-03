extends Node2D
## Two movable anchors turn hostile paths into a finite, player-timed attack.
## Circuit damage is a child event: it never retriggers equipment or basic procs.
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const MAX_CHARGE := 3
const PLACEMENT_RANGE := 460.0
const MAX_LENGTH := 680.0
const MIN_LENGTH := 100.0
const TINT := Color("77ddd5")
var room: Node2D
var anchors: Array[Vector2] = []
var charge: int = 0
var age: float = 0.0
var arm_time: float = 0.0
var cooldown: float = 0.0
var feedback_time: float = 0.0
var message: String = "C 在鼠标位置布桩 · 两桩连线"
var pulse: float = 0.0
var burst: float = 0.0
var burst_charge: int = 0
var previous_positions: Dictionary = {}
var captured_enemies: Dictionary = {}
var captured_shots: int = 0
var discharges: int = 0
var sprite: Texture2D
var font: Font

func configure(host: Node2D) -> void:
	room = host
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite = Sampler.sampled("asset://circuit/relay_v1.png")
	font = load(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf"))
	reset_room()

func reset_room() -> void:
	anchors.clear()
	charge = 0
	arm_time = 0.0
	cooldown = 0.0
	burst = 0.0
	pulse = 0.0
	previous_positions.clear()
	captured_enemies.clear()
	message = "C 在鼠标位置布桩 · 两桩连线"
	feedback_time = 0.0
	queue_redraw()

func _available() -> bool:
	return is_instance_valid(room) and is_instance_valid(room.player) and room.controls_enabled() and room.pointer_controls_enabled()

func _nearby() -> bool:
	return anchors.size() == 2 and room.player.position.distance_to(Geometry2D.get_closest_point_to_segment(room.player.position, anchors[0], anchors[1])) < 850.0

func _say(text: String) -> bool:
	message = text
	feedback_time = 2.5
	return false

func place(at: Vector2) -> bool:
	if not _available() or cooldown > 0.0:
		return false
	if not at.is_finite() or room.player.position.distance_to(at) > PLACEMENT_RANGE:
		return _say("布桩距离过远 · 靠近目标再按 C")
	if not room.valid_ground(at, 20.0) or not room.has_line_of_sight(room.player.position, at):
		return _say("此处不可布桩 · 选择可见的平地")
	if not anchors.is_empty():
		var other: Vector2 = anchors.back()
		var length: float = other.distance_to(at)
		if length < MIN_LENGTH or length > MAX_LENGTH:
			return _say("两桩间距需为 100–680 · 调整鼠标位置")
		if not room.has_line_of_sight(other, at):
			return _say("连线被障碍阻断 · 移到同一片空地")
	if anchors.size() == 2:
		anchors.pop_front()
	anchors.append(at)
	charge = 0
	arm_time = 0.4
	cooldown = 0.2
	previous_positions.clear()
	captured_enemies.clear()
	pulse = 0.4
	_say("引诱敌人或弹道穿线 · V 释放电能" if anchors.size() == 2 else "再按 C 放第二桩 · 拉出一条战线")
	room.add_ring(at, TINT, 35.0, 0.3)
	queue_redraw()
	return true

func advance(delta: float) -> void:
	if not is_instance_valid(room) or get_tree().paused or delta <= 0.0:
		return
	age += delta
	arm_time = maxf(0.0, arm_time - delta)
	cooldown = maxf(0.0, cooldown - delta)
	feedback_time = maxf(0.0, feedback_time - delta)
	pulse = maxf(0.0, pulse - delta)
	burst = maxf(0.0, burst - delta)
	if anchors.size() == 2 and arm_time <= 0.0 and _nearby():
		var present: Dictionary = {}
		for enemy: Node2D in room.enemies.get_children():
			if not enemy.is_alive() or enemy.actor_kind in ["objective", "anchor"]:
				continue
			var id: int = enemy.get_instance_id()
			present[id] = enemy.position
			if previous_positions.has(id) and not captured_enemies.has(id) and charge < MAX_CHARGE:
				var start: Vector2 = previous_positions[id]
				if start.distance_squared_to(enemy.position) > 0.01 and Geometry2D.segment_intersects_segment(start, enemy.position, anchors[0], anchors[1]) != null:
					captured_enemies[id] = true
					_add_charge(enemy.position)
		previous_positions = present
	if _available():
		if InputMap.has_action("circuit_place") and Input.is_action_just_pressed("circuit_place"):
			place(room.get_local_mouse_position())
		if InputMap.has_action("circuit_release") and Input.is_action_just_pressed("circuit_release"):
			discharge()
	queue_redraw()

func _add_charge(at: Vector2) -> void:
	charge = mini(MAX_CHARGE, charge + 1)
	pulse = 0.5
	room.add_ring(at, TINT, 27.0, 0.24)
	_say("满能！V 释放 · 满能期间不再拦截弹道" if charge == MAX_CHARGE else "电能 %d / 3 · V 现在释放或继续诱敌" % charge)
	if is_instance_valid(room.combat_audio): room.combat_audio.pickup()

## A shot can be absorbed only before the first real victim and before walls.
func intercept(start: Vector2, end: Vector2, first_victim_fraction: float = 1.0) -> bool:
	# Hovering a HUD control blocks aiming input, not a deployed device's defense.
	if anchors.size() != 2 or charge >= MAX_CHARGE or arm_time > 0.0 or not is_instance_valid(room) or not room.controls_enabled() or not _nearby():
		return false
	var crossing: Variant = Geometry2D.segment_intersects_segment(start, end, anchors[0], anchors[1])
	if crossing == null or start.distance_squared_to(end) < 0.001:
		return false
	var fraction: float = start.distance_to(crossing) / start.distance_to(end)
	if fraction >= first_victim_fraction:
		return false
	_add_charge(crossing)
	captured_shots += 1
	return true

func discharge() -> bool:
	if not _available() or anchors.size() != 2 or cooldown > 0.0 or arm_time > 0.0:
		return false
	if not _nearby(): return _say("回路距离过远 · 返回连线附近")
	if charge <= 0: return _say("回路尚未蓄能 · 引敌人或弹道穿过连线")
	var spent: int = charge
	charge = 0
	cooldown = 0.7
	burst = 0.5
	burst_charge = spent
	discharges += 1
	var hero: String = room.player.hero_id()
	var width: float = 38.0 + spent * 12.0
	var power: float = room.player.attack_power() * (0.8 + 0.9 * spent)
	var hits: int = 0
	for enemy: Node2D in room.enemies.get_children():
		if not enemy.is_alive() or enemy.actor_kind in ["objective", "anchor"]:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(enemy.position, anchors[0], anchors[1])
		if enemy.position.distance_to(closest) > width + float(enemy.navigation_radius) or not room.has_line_of_sight(closest, enemy.position):
			continue
		var direction: Vector2 = (enemy.position - closest).normalized()
		if direction == Vector2.ZERO: direction = (anchors[1] - anchors[0]).orthogonal().normalized()
		var context: Dictionary = {"damage_type":"magic","attacker_stats":Game.run.stats.duplicate(true),"original_basic":false, "equipment_eligible":false, "proc_depth":1, "attack_id":"circuit:"+str(discharges), "root_event_id":"circuit:"+str(discharges)}
		room.resolve_direct_hit(enemy, power, &"circuit", "", 120.0 if hero == "CH01" else 25.0, direction, context)
		if enemy.is_alive():
			enemy.apply_status("chill", power)
			if hero == "CH02" and room.player.has_method("class_mark_target"): room.player.class_mark_target(enemy)
		hits += 1
	if hero == "CH03" and room.player.has_method("charge_resonance"):
		room.player.charge_resonance((anchors[0] + anchors[1]) * 0.5, anchors[0].distance_to(anchors[1]) * 0.5 + 120.0, spent)
	elif hits > 0:
		Game.restore_resource(float(spent * 6))
	if is_instance_valid(room.combat_audio): room.combat_audio.cast("CH03", "ultimate")
	_say("回路释放 · %d 格电能 · 命中 %d" % [spent, hits])
	queue_redraw()
	return true

func status() -> Dictionary:
	var hint: String = "C 布置引雷桩"
	if feedback_time > 0.0: hint = message
	elif anchors.size() == 1: hint = "C 再放一桩 · 两桩形成回路"
	elif anchors.size() == 2:
		hint = "V 释放 · 满能不再拦截" if charge >= MAX_CHARGE else "诱敌穿线蓄能 · V 释放 · C 重布清空电能"
	return {"anchors":anchors.size(), "charge":charge, "max_charge":MAX_CHARGE, "hint":hint}

func _draw() -> void:
	if anchors.size() == 2:
		var a: Vector2 = anchors[0]
		var b: Vector2 = anchors[1]
		var tint: Color = Color("f4be72") if charge == MAX_CHARGE else TINT
		# The slim field is a friendly cable; enemy tells stay solid red/orange.
		draw_line(a, b, Color(0.01,0.035,0.045,0.8), 7.0, true)
		draw_line(a, b, Color(tint, 0.25 + charge * 0.13), 1.5 + charge * 0.65, true)
		var normal: Vector2 = (b-a).orthogonal().normalized()
		for index: int in 12:
			var t: float = fposmod(float(index)/12.0 + age * 0.14, 1.0)
			var point: Vector2 = a.lerp(b,t)
			draw_circle(point, 1.6 + charge * 0.4, Color(tint, 0.75))
		if charge > 0 or pulse > 0.0:
			var path := PackedVector2Array()
			for index: int in 25:
				var t: float = float(index)/24.0
				var displacement: float = sin(index*3.7+floor(age*16.0))*sin(t*PI)*(3.0+charge*2.0)
				path.append(a.lerp(b,t)+normal*displacement)
			draw_polyline(path,Color(tint,0.6),1.2,true)
		if burst > 0.0:
			var progress: float = 1.0-burst/0.5
			var width: float = (38.0 + burst_charge*12.0)*sin(progress*PI*0.5)
			draw_line(a,b,Color(tint,burst*0.36),width*2.0,true)
			draw_line(a+normal*width,b+normal*width,Color(tint,burst*1.4),2.0,true)
			draw_line(a-normal*width,b-normal*width,Color(tint,burst*1.4),2.0,true)
			draw_line(a,b,Color("e5fff9")*Color(1,1,1,burst*1.8),4.0,true)
	for index: int in anchors.size():
		var at: Vector2 = anchors[index]
		draw_circle(at + Vector2(0,3),19,Color(0.01,0.02,0.025,0.42))
		draw_arc(at,22.0+pulse*7.0,0,TAU,32,Color(TINT,0.45+pulse),1.6,true)
		if sprite != null: draw_texture_rect(sprite,Rect2(at+Vector2(-38,-66),Vector2(76,76)),false)
		else: draw_circle(at,10,TINT)
		if font != null:
			draw_string(font,at+Vector2(-3,30),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,TINT)
