class_name HeroDeployment
extends Node2D
## Original industrial silhouettes: a three-legged capacitor, folded cold-line
## plate, and segmented dome. Never borrows enemy warning colors or blocks actors.

var room: Node2D
var owner_player: Node2D
var kind: String = "node"
var options: Dictionary = {}
var health: float = 35.0
var max_health: float = 35.0
var radius: float = 160.0
var damage: float = 0.0
var lifetime: float = 10.0
var elapsed: float = 0.0
var alive: bool = true
var setup_time: float = 0.35
var next_attack: float = 1.55
var pulse: float = 0.0
var damaged_flash: float = 0.0
var collision_radius: float = 14.0
var fire_direction := Vector2.RIGHT
var resonance_charge: int = 0
var charge_flash: float = 0.0
var _charged_casts: Dictionary = {}
const NODE_FONT = preload("res://assets/fonts/NotoSansSC.ttf")

func configure(host: Node2D, deployment_kind: String, configuration: Dictionary) -> void:
	room = host
	kind = deployment_kind
	options = configuration.duplicate()
	owner_player = options.get("owner_player", null)
	if not options.has("damage_type"):
		options["damage_type"] = "physical" if kind == "trap" else "magic"
	if not options.has("attacker_stats"):
		options["attacker_stats"] = Game.run.stats.duplicate() if Game.run != null else {}
	radius = float(options.get("radius", 160.0))
	damage = float(options.get("damage", 0.0))
	lifetime = float(options.get("lifetime", 10.0))
	health = float(options.get("health", 35.0))
	max_health = health
	setup_time = 0.0 if kind == "field" else 0.35
	next_attack = 1.0 if kind == "field" else setup_time + 1.2
	add_to_group("hero_deployments")
	z_index = -1 if kind == "field" else 1
	queue_redraw()

func is_alive() -> bool:
	return alive and not is_queued_for_deletion()

func is_active() -> bool:
	return is_alive() and elapsed >= setup_time

func ready_to_attack() -> bool:
	return is_active()

func receive_damage(amount: float, _origin: Vector2 = Vector2.ZERO) -> bool:
	if kind != "node" or not is_alive() or amount <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	damaged_flash = 0.18
	if health <= 0.0:
		retire(true)
	return true

func retire(destroyed: bool = false) -> void:
	if not alive:
		return
	alive = false
	if is_instance_valid(room):
		room.add_ring(position, Color("b79977") if destroyed else Color("69918e"), 28.0, 0.28)
	queue_free()

func _physics_process(delta: float) -> void:
	if not alive or Game.run == null:
		return
	if Game.run.hp <= 0.0:
		retire()
		return
	advance(delta)

func advance(delta: float) -> void:
	if not alive:
		return
	elapsed += maxf(0.0, delta)
	pulse = maxf(0.0, pulse - delta)
	charge_flash = maxf(0.0, charge_flash - delta)
	damaged_flash = maxf(0.0, damaged_flash - delta)
	if kind == "field" and bool(options.get("follow_player", false)) and is_instance_valid(owner_player):
		position = owner_player.position
	if kind == "field":
		# Tick at t=5 (or 4/7) before expiry. No immediate free tick on creation.
		var emitted_pulse: bool = false
		while next_attack <= minf(elapsed, lifetime) + 0.00001:
			room.strike_area(position, radius, damage, "field", "", 0.0, Vector2.ZERO, 360.0, false, _damage_context())
			next_attack += 1.0
			pulse = 0.22
			_emit_feedback_pulse()
			emitted_pulse = true
		# Gameplay catches up every authored tick; old pulses are never replayed
		# as a burst of sound on the same frame.
		if emitted_pulse:
			_play_deployment_audio("field_pulse")
	elif kind == "trap" and elapsed >= setup_time and elapsed <= lifetime:
		var targets: Array = room.targets_in_radius(position, radius)
		for target: Node2D in targets:
			if is_instance_valid(target) and target.is_alive() and room.has_line_of_sight(position, target.position):
				_play_deployment_audio("trap_trigger")
				room.strike_area(position, radius, damage, "f", "chill", 0.0, Vector2.ZERO, 360.0, true, _damage_context(true))
				room.add_ring(position, Color("c1dcce"), radius, 0.35)
				_emit_feedback_pulse()
				retire()
				return
	elif kind == "node":
		_observe_resonance_bolts()
		while next_attack <= minf(elapsed, lifetime) + 0.00001:
			_fire_node()
			next_attack += 1.2
	if elapsed >= lifetime:
		retire()
	else:
		queue_redraw()

func charge_node(amount: int = 1) -> bool:
	if kind != "node" or not is_active() or amount <= 0:
		return false
	var previous: int = resonance_charge
	resonance_charge = mini(3, resonance_charge + amount)
	if previous == resonance_charge:
		return false
	# Charging is an intake, not a cannon shot. Keep its pose and sound separate
	# from the firing pulse, and acknowledge only a real increase in stored energy.
	charge_flash = 0.34
	if is_instance_valid(room) and is_instance_valid(room.get("combat_audio")):
		room.combat_audio.resonance_charge(resonance_charge)
	queue_redraw()
	return true

func resonance_readout() -> Dictionary:
	var connected: bool = is_active() and is_instance_valid(owner_player) and owner_player.position.distance_to(position) <= 260.0 and room.has_line_of_sight(owner_player.position, position)
	var available: bool = false
	if connected and Game.run != null and owner_player.hero_level() >= 3:
		var definition: Dictionary = owner_player.skill_definition("f")
		available = float(owner_player.cooldowns.get("f", 0.0)) <= 0.0 and Game.run.resource >= float(definition.cost) and not owner_player.abilities.busy() and owner_player.dash_remaining <= 0.0
	return {"charge":resonance_charge, "full":resonance_charge == 3, "connected":connected, "available":available, "radius":100.0 + resonance_charge * 20.0}

func _observe_resonance_bolts() -> void:
	if not is_active() or not is_instance_valid(room) or not is_instance_valid(room.projectiles):
		return
	for projectile: Node2D in room.projectiles.get_children():
		if projectile.source != &"q" or str(projectile.options.get("status", "")) != "shock":
			continue
		var cast_key: String = str(projectile.options.get("root_event_id", projectile.get_instance_id()))
		if _charged_casts.has(cast_key) or position.distance_to(projectile.position) > 90.0 or not room.has_line_of_sight(position, projectile.position):
			continue
		_charged_casts[cast_key] = true
		charge_node(1)

func detonate() -> bool:
	if kind != "node" or not is_active():
		return false
	# Commit retirement before damage so this node cannot chain or trigger twice.
	alive = false
	var blast_radius: float = 100.0 + resonance_charge * 20.0
	var power: float = float(options.get("power", damage))
	room.strike_area(position, blast_radius, power * (1.0 + resonance_charge * 0.65), "node_detonation", "", 0.0, Vector2.ZERO, 360.0, false, _damage_context())
	room.add_ring(position, Color("78d9d1"), blast_radius, 0.38)
	if is_instance_valid(owner_player):
		var feedback: Node = owner_player.get_node_or_null("HeroFeedback")
		if is_instance_valid(feedback):
			feedback.class_event("node_burst", position, Vector2.RIGHT, blast_radius, resonance_charge)
	queue_free()
	return true

func _damage_context(original: bool = false) -> Dictionary:
	var context: Dictionary = {"power":float(options.get("power", damage)), "damage_type":str(options.get("damage_type", "magic")), "attacker_stats":options.get("attacker_stats", {}), "equipment_eligible":original, "original_basic":false}
	if original:
		# A trap's simultaneous victims still share one equipment trigger root.
		context["root_event_id"] = "deployment:" + str(get_instance_id())
		context["attack_id"] = context.root_event_id
	return context

func _fire_node() -> void:
	var targets: Array = room.targets_in_radius(position, radius)
	targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var da: float = position.distance_squared_to(a.position)
		var db: float = position.distance_squared_to(b.position)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(da, db) else da < db)
	for target: Node2D in targets:
		if not is_instance_valid(target) or not target.is_alive() or not room.has_line_of_sight(position, target.position):
			continue
		var direction: Vector2 = (target.position - position).normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		var projectile_options: Dictionary = _damage_context()
		projectile_options.merge({"source":"node", "original":false, "speed":700.0, "range":radius + 24.0, "color":Color("67bab5")})
		var projectile: Node2D = room.spawn_ability_projectile(position, direction, damage, projectile_options)
		if is_instance_valid(projectile):
			fire_direction = direction
			pulse = 0.18
			_emit_feedback_pulse()
			_play_deployment_audio("node_fire")
		return

func _play_deployment_audio(cue: String) -> void:
	if not is_instance_valid(room):
		return
	var audio: Variant = room.get("combat_audio")
	if is_instance_valid(audio) and audio.has_method("deployment"):
		# Rejection is final for this event: no queued retry after a full pool,
		# mute or the room-wide per-cue clustering window.
		audio.deployment(cue)

func _emit_feedback_pulse() -> void:
	if not is_instance_valid(owner_player):
		return
	var feedback: Node2D = owner_player.get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.deployment_pulse(kind, position, radius)

func _draw() -> void:
	var expansion: float = 1.0 if setup_time <= 0.0 else clampf(elapsed / setup_time, 0.0, 1.0)
	var opacity: float = clampf(lifetime - elapsed, 0.0, 1.0)
	var ink := Color("72aaa3")
	ink.a = opacity
	var paper := Color("d8d5b8")
	paper.a = opacity
	if kind == "field":
		_draw_dome(ink, paper)
		return
	if kind == "trap":
		_draw_trap(expansion, opacity, ink, paper)
		return
	# Three splayed struts and stacked capacitors form a recognizable node.
	draw_circle(Vector2(0,5), 17.0, Color(0.025,0.045,0.05,0.55 * opacity))
	for index in range(3):
		var foot: Vector2 = Vector2.RIGHT.rotated(index * TAU / 3.0 + PI / 6.0) * (8.0 + expansion * 13.0)
		draw_line(Vector2(0,2), foot, Color("424c48"), 5.0, true)
		draw_line(Vector2(0,2), foot, ink, 1.5, true)
		draw_circle(foot, 3.0, paper)
	draw_rect(Rect2(-8,-16 * expansion,16,21 * expansion), Color("284845"))
	draw_rect(Rect2(-8,-16 * expansion,16,21 * expansion), paper, false, 1.5)
	for index in range(3):
		var y: float = -11.0 + index * 5.0
		draw_line(Vector2(-4,y), Vector2(4,y), Color("e8ffee") if index < resonance_charge else Color("9bdcd1") if pulse > 0.0 else ink, 3.5 if index < resonance_charge else 2.0)
	draw_line(Vector2(0,-16 * expansion), Vector2(0,-25 * expansion), paper, 2.0)
	draw_circle(Vector2(0,-26 * expansion), 3.0 + pulse * 12.0, ink)
	if pulse > 0.0:
		var strength: float = clampf(pulse / 0.18, 0.0, 1.0)
		var emitter := Vector2(0,-26 * expansion)
		var tip: Vector2 = emitter + fire_direction * (12.0 + strength * 20.0)
		var side: Vector2 = fire_direction.orthogonal() * (2.0 + strength * 4.0)
		draw_polyline(PackedVector2Array([emitter + side, tip, emitter - side]), Color(paper, opacity * strength), 2.3, true)
		draw_arc(Vector2(0,-7), 14.0 + (1.0-strength) * 25.0, 0.0, TAU, 32, Color(ink, opacity * strength * 0.7), 1.6, true)
	if health < max_health or damaged_flash > 0.0:
		draw_rect(Rect2(-17,20,34,3), Color("24312f"))
		draw_rect(Rect2(-17,20,34 * health / maxf(1.0,max_health),3), paper)
	if is_active():
		_draw_resonance_charge(opacity)

func _draw_resonance_charge(opacity: float) -> void:
	var readout: Dictionary = resonance_readout()
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var flash: float = 0.0 if reduced else clampf(charge_flash / 0.34, 0.0, 1.0)
	var tint := Color("c7b3ff") if bool(readout.full) else Color("80e8d7")
	# Three legible crystal sockets above the silhouette show energy per node,
	# even when its cannon is firing. Their shape remains readable without color.
	for index in 3:
		var center := Vector2(-13.0 + index * 13.0, -39.0)
		var shape := PackedVector2Array([center+Vector2(0,-5),center+Vector2(5,0),center+Vector2(0,5),center+Vector2(-5,0),center+Vector2(0,-5)])
		draw_colored_polygon(shape, Color(0.025,0.045,0.055,opacity * .94))
		draw_polyline(shape, Color("081718"), 3.5, true)
		draw_polyline(shape, Color(tint, opacity * (1.0 if index < resonance_charge else .28)), 1.4, true)
		if index < resonance_charge:
			draw_line(center-Vector2(0,2.5),center+Vector2(0,2.5),Color(tint,opacity),2.7,true)
			if flash > 0.0 and index == resonance_charge-1:
				draw_arc(center,7+(1-flash)*9,0,TAU,20,Color(tint,opacity*flash*.65),1.6,true)
	if bool(readout.full):
		draw_line(Vector2(-18,-47),Vector2(18,-47),Color(tint,opacity*.85),1.5,true)
	if bool(readout.connected) and owner_player.hero_level() >= 3:
		var alpha: float = opacity * (1.0 if bool(readout.available) else .35)
		var at := Vector2(26,-34)
		draw_string_outline(NODE_FONT,at,"F",HORIZONTAL_ALIGNMENT_LEFT,-1,13,4,Color(0.02,0.04,0.05,alpha))
		draw_string(NODE_FONT,at,"F",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(tint,alpha))

func _draw_trap(expansion: float, opacity: float, ink: Color, paper: Color) -> void:
	var unfold: float = 1.0 - pow(1.0-expansion, 3.0)
	var reach: float = radius * maxf(unfold, 0.04)
	for index in range(12):
		var angle: float = index * TAU / 12.0
		draw_arc(Vector2.ZERO, reach, angle + 0.02, angle + TAU / 24.0, 7, Color(ink, opacity * 0.34), 1.4, true)
	for index in range(6):
		var axis: Vector2 = Vector2.RIGHT.rotated(index * TAU / 6.0 + (1.0-unfold) * PI / 5.0)
		var side: Vector2 = axis.orthogonal()
		var hinge: Vector2 = axis * 7.0
		var tip: Vector2 = axis * (10.0 + unfold * 18.0)
		var leaf := PackedVector2Array([hinge-side*3.0, tip-side*5.0, tip+axis*5.0, tip+side*5.0, hinge+side*3.0, hinge-side*3.0])
		draw_colored_polygon(leaf, Color("294c48"))
		draw_polyline(leaf, Color(paper, opacity * 0.85), 1.6, true)
		draw_line(hinge, tip, Color(ink, opacity), 2.0, true)
		if expansion >= 1.0:
			var edge: Vector2 = axis * radius
			draw_line(edge-axis*6.0, edge, Color(paper, opacity * 0.55), 1.4, true)
			draw_line(edge-side*4.0, edge+side*4.0, Color(ink, opacity * 0.48), 1.2, true)
	draw_circle(Vector2.ZERO, 8.0, Color("203f3e"))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 18, paper, 1.5, true)
	draw_polyline(PackedVector2Array([Vector2(-5,1),Vector2(-1,-3),Vector2(2,2),Vector2(5,-1)]), Color("b8e8dd"), 1.8, true)
	if expansion < 1.0:
		draw_arc(Vector2.ZERO, 34.0, -PI * 0.5, -PI * 0.5 + TAU * expansion, 28, Color(paper, opacity * 0.7), 1.8, true)

func _draw_dome(ink: Color, paper: Color) -> void:
	var fading: float = clampf(lifetime - elapsed, 0.0, 1.0)
	var ring_radius: float = radius * (0.96 + minf(elapsed * 0.2, 0.04))
	var strength: float = clampf(pulse / 0.22, 0.0, 1.0)
	# Sparse low-opacity material keeps enemy silhouettes and warning lines clear.
	draw_circle(Vector2.ZERO, ring_radius, Color(ink, fading * 0.035))
	for index in range(18):
		var angle: float = index * TAU / 18.0
		draw_arc(Vector2.ZERO, ring_radius, angle + 0.025, angle + TAU / 18.0 - 0.045, 10, Color(ink, fading * (0.58 + strength * 0.32)), 2.2, true)
		draw_arc(Vector2.ZERO, ring_radius * 0.92, angle + 0.08, angle + TAU / 18.0 - 0.03, 8, Color(paper, fading * (0.24 + strength * 0.3)), 1.1, true)
		var axis: Vector2 = Vector2.RIGHT.rotated(angle)
		draw_line(axis * ring_radius * 0.97, axis * ring_radius * 1.02, Color(paper, fading * 0.65), 1.6, true)
		if strength > 0.0 and index % 3 == 0:
			draw_line(axis * radius * 0.22, axis * radius * 0.87, Color(ink, fading * strength * 0.32), 1.2, true)
	for index in range(6):
		var foot: Vector2 = Vector2.RIGHT.rotated(index * TAU / 6.0 + PI / 6.0) * ring_radius
		var top: Vector2 = foot + Vector2(0,-15.0-strength*3.0)
		draw_arc(foot, 7.0, 0.0, TAU, 16, Color(ink, fading * 0.65), 1.4, true)
		draw_line(foot+Vector2(-3,0), top+Vector2(-3,0), Color(ink, fading * (0.5+strength*0.4)), 1.6, true)
		draw_line(foot+Vector2(3,0), top+Vector2(3,0), Color(ink, fading * (0.5+strength*0.4)), 1.6, true)
		draw_line(top-Vector2(5,0), top+Vector2(5,0), Color(paper, fading * (0.6+strength*0.35)), 2.0, true)
		draw_circle(top, 6.0+strength*5.0, Color(ink, fading * strength * 0.07))
	if pulse > 0.0:
		draw_arc(Vector2.ZERO, radius * (0.38 + (1.0-strength) * 0.62), 0.0, TAU, 64, Color(ink, strength * 0.78 * fading), 2.5, true)
	var center := PackedVector2Array()
	for index in range(7):
		center.append(Vector2.RIGHT.rotated(index * TAU / 6.0) * 10.0)
	draw_polyline(center, Color(paper, fading * (0.42+strength*0.5)), 1.3, true)
	draw_line(Vector2(-5,0), Vector2(5,0), Color(ink, fading * 0.6), 1.2)
	draw_line(Vector2(0,-5), Vector2(0,5), Color(ink, fading * 0.6), 1.2)
