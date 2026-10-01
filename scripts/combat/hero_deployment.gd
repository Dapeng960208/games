class_name HeroDeployment
extends Node2D
## Persistent arcane crystals/constellation fields and timed brass grenades.
## Player effects stay below danger warnings and never block actor movement.

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
		options["damage_type"] = "physical" if kind in ["trap", "grenade"] else "magic"
	if not options.has("attacker_stats"):
		options["attacker_stats"] = Game.run.stats.duplicate() if Game.run != null else {}
	radius = float(options.get("radius", 160.0))
	damage = float(options.get("damage", 0.0))
	lifetime = float(options.get("lifetime", 10.0))
	health = float(options.get("health", 35.0))
	max_health = health
	setup_time = 0.0 if kind == "field" else float(options.get("fuse", 0.65)) if kind == "grenade" else 0.35
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
			room.strike_area(position, radius, damage, "field", "chill", 0.0, Vector2.ZERO, 360.0, false, _damage_context())
			next_attack += 1.0
			pulse = 0.22
			_emit_feedback_pulse()
			emitted_pulse = true
		# Gameplay catches up every authored tick; old pulses are never replayed
		# as a burst of sound on the same frame.
		if emitted_pulse:
			_play_deployment_audio("field_pulse")
	elif kind == "grenade" and elapsed + 0.00001 >= setup_time:
		# Commit retirement before the blast. Re-entry and a large catch-up delta
		# can never detonate this grenade twice, even without an occupied zone.
		alive = false
		_play_deployment_audio("grenade_burst")
		var throw_direction: Vector2 = position - Vector2(options.get("origin", position - Vector2.RIGHT))
		room.strike_area(position, radius, damage, "f", "", float(options.get("knockback", 30.0)), throw_direction.normalized(), 360.0, true, _damage_context(true))
		_emit_feedback_pulse()
		queue_free()
		return
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
		# Simultaneous victims share the committed skill root, including the
		# captured power/attributes and heavy-contact tier of a timed grenade.
		context["root_event_id"] = str(options.get("root_event_id", "deployment:" + str(get_instance_id())))
		context["attack_id"] = str(options.get("attack_id", context.root_event_id))
		context["heavy"] = bool(options.get("heavy", false))
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
	var ink := Color("a98bed")
	var paper := Color("a5f2ed")
	if kind == "field":
		_draw_dome(ink, paper)
		return
	if kind == "grenade":
		_draw_grenade(clampf((lifetime - elapsed) / 0.12, 0.0, 1.0))
		return
	if kind == "trap":
		_draw_trap(expansion, opacity, Color(Color("72aaa3"), opacity), Color(Color("d8d5b8"), opacity))
		return
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var bob: float = 0.0 if reduced else sin(elapsed * 2.4) * 2.0
	var crystal := Vector2(0.0, -26.0 * expansion + bob)
	# A low rune base and a suspended faceted crystal distinguish a spell focus
	# from the gunner's hardware. The floor remains visible beneath the glyphs.
	draw_colored_polygon(_deployment_ellipse(Vector2(0, 4), Vector2(18, 6), 24), Color(0.07, 0.045, 0.11, opacity * 0.28))
	draw_polyline(_deployment_ellipse(Vector2(0, 2), Vector2(24, 12) * maxf(expansion, 0.1), 32), Color(ink, opacity * 0.72), 1.7, true)
	if not reduced:
		draw_polyline(_deployment_ellipse(Vector2(0, 2), Vector2(17, 8) * maxf(expansion, 0.1), 24), Color(paper, opacity * 0.36), 1.0, true)
		for index in range(3):
			var axis: Vector2 = Vector2.RIGHT.rotated(index * TAU / 3.0 - PI * 0.5)
			var at := Vector2(axis.x * 20.0, 2.0 + axis.y * 10.0)
			_draw_arcane_rune(at, 3.8, Color(paper, opacity * 0.65))
		if charge_flash > 0.0:
			var intake: float = clampf(charge_flash / 0.34, 0.0, 1.0)
			draw_arc(crystal, 13.0 + (1.0 - intake) * 11.0, 0.0, TAU, 24, Color(paper, opacity * intake * 0.45), 1.5, true)
	var shape := PackedVector2Array([crystal + Vector2(0, -15), crystal + Vector2(10, -3), crystal + Vector2(6, 9), crystal + Vector2(0, 15), crystal + Vector2(-8, 5), crystal + Vector2(-10, -3)])
	draw_colored_polygon(shape, Color("7750ac", opacity * 0.94))
	draw_colored_polygon(PackedVector2Array([crystal + Vector2(0, -15), crystal + Vector2(10, -3), crystal + Vector2(0, 15), crystal + Vector2(1, -2)]), Color("b7a1ec", opacity * 0.9))
	draw_colored_polygon(PackedVector2Array([crystal + Vector2(-10, -3), crystal + Vector2(1, -2), crystal + Vector2(0, 15), crystal + Vector2(-8, 5)]), Color("526ea9", opacity * 0.92))
	shape.append(shape[0])
	draw_polyline(shape, Color("30254c", opacity), 2.7, true)
	draw_line(crystal + Vector2(0, -13), crystal + Vector2(1, -2), Color(paper, opacity * 0.88), 1.7, true)
	draw_line(crystal + Vector2(1, -2), crystal + Vector2(8, -3), Color(paper, opacity * 0.8), 1.2, true)
	_draw_arcane_rune(crystal + Vector2(0, 1), 3.5, Color("eafaf3", opacity * 0.94))
	if pulse > 0.0:
		var strength: float = clampf(pulse / 0.18, 0.0, 1.0)
		var tip: Vector2 = crystal + fire_direction * (12.0 + strength * 18.0)
		var side: Vector2 = fire_direction.orthogonal() * (2.0 + strength * 3.0)
		draw_polyline(PackedVector2Array([crystal + side, tip, crystal - side]), Color(paper, opacity * strength), 2.0, true)
		if not reduced:
			draw_arc(crystal, 13.0 + (1.0 - strength) * 12.0, -PI * 0.85, PI * 0.5, 24, Color(ink, opacity * strength * 0.55), 1.3, true)
	if health < max_health or damaged_flash > 0.0:
		draw_rect(Rect2(-17, 20, 34, 3), Color("30254c", opacity))
		draw_rect(Rect2(-17, 20, 34 * health / maxf(1.0, max_health), 3), Color(paper, opacity))
	if is_active():
		_draw_resonance_charge(opacity)

func _draw_resonance_charge(opacity: float) -> void:
	var readout: Dictionary = resonance_readout()
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var flash: float = 0.0 if reduced else clampf(charge_flash / 0.34, 0.0, 1.0)
	var tint := Color("c7b3ff") if bool(readout.full) else Color("80e8d7")
	# Three crystal sockets carry the actual stored charge, separate from the
	# firing flash. Empty and filled shapes remain distinct without hue alone.
	for index in 3:
		var center := Vector2(-13.0 + index * 13.0, -53.0)
		var shape := PackedVector2Array([center+Vector2(0,-5),center+Vector2(5,0),center+Vector2(0,5),center+Vector2(-5,0),center+Vector2(0,-5)])
		draw_colored_polygon(shape, Color("30254c", opacity * .92))
		draw_polyline(shape, Color("30254c", opacity), 3.5, true)
		draw_polyline(shape, Color(tint, opacity * (1.0 if index < resonance_charge else .28)), 1.4, true)
		if index < resonance_charge:
			draw_line(center-Vector2(0,2.5),center+Vector2(0,2.5),Color(tint,opacity),2.7,true)
			if flash > 0.0 and index == resonance_charge-1:
				draw_arc(center,7+(1-flash)*9,0,TAU,20,Color(tint,opacity*flash*.65),1.6,true)
	if bool(readout.full):
		draw_line(Vector2(-18,-61),Vector2(18,-61),Color(tint,opacity*.85),1.5,true)
	if bool(readout.connected) and owner_player.hero_level() >= 3:
		var alpha: float = opacity * (1.0 if bool(readout.available) else .35)
		var at := Vector2(25,-47)
		var settings: Dictionary = Game.profile.get("settings", {})
		var label: String = ControlBindings.label_for("skill_f", settings.get("controls", {}), Words.locale)
		draw_string_outline(NODE_FONT,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,4,Color(0.02,0.04,0.05,alpha))
		draw_string(NODE_FONT,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(tint,alpha))

func _draw_grenade(opacity: float) -> void:
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var fuse: float = maxf(0.01, float(options.get("fuse", 0.65)))
	var remaining: float = clampf(1.0 - elapsed / fuse, 0.0, 1.0)
	var landing: float = clampf(elapsed / 0.18, 0.0, 1.0)
	var lift: float = 22.0 * pow(1.0 - landing, 2.0) + sin(landing * PI) * 5.0
	var body := Vector2(0, -9.0 - lift)
	var angle: float = (1.0 - landing) * -0.28
	var brass := Color("e7b568", opacity)
	var amber := Color("ffd28b", opacity)
	# The placement and blast circle share the true legal landing point. Only
	# this local canister hop is airborne; drawing never supplies a damage point.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(brass, opacity * 0.3), 1.6, true)
	for index in range(8):
		var axis: Vector2 = Vector2.RIGHT.rotated(index * TAU / 8.0)
		draw_line(axis * (radius - 4.0), axis * (radius + 3.0), Color(amber, opacity * 0.56), 1.5, true)
	draw_colored_polygon(_deployment_ellipse(Vector2(0, 3), Vector2(10, 4), 20), Color(0.14, 0.075, 0.03, opacity * 0.3))
	var hull: PackedVector2Array = _deployment_local_shape(PackedVector2Array([Vector2(-5,-10),Vector2(4,-10),Vector2(7,-6),Vector2(7,7),Vector2(4,10),Vector2(-5,10),Vector2(-7,7),Vector2(-7,-6)]), body, angle)
	draw_colored_polygon(hull, Color("97653a", opacity))
	hull.append(hull[0])
	draw_polyline(hull, Color("4c342d", opacity), 2.7, true)
	draw_line(body + Vector2(-5,-6).rotated(angle), body + Vector2(5,-6).rotated(angle), brass, 2.5, true)
	draw_line(body + Vector2(-5,6).rotated(angle), body + Vector2(5,6).rotated(angle), brass, 2.5, true)
	draw_line(body + Vector2(-3,-2).rotated(angle), body + Vector2(-3,3).rotated(angle), Color("fff0c0", opacity), 1.8, true)
	var cap: Vector2 = body + Vector2(0,-12).rotated(angle)
	draw_line(cap + Vector2(-3,0).rotated(angle), cap + Vector2(3,0).rotated(angle), Color("65514a", opacity), 3.0, true)
	var spark: Vector2 = cap + Vector2(2,-5).rotated(angle)
	draw_line(cap, spark, brass, 1.7, true)
	draw_circle(spark, 2.1, Color("fff3c2", opacity))
	if remaining > 0.0:
		draw_arc(body, 17.0, -PI * 0.5, -PI * 0.5 + TAU * remaining, 36, amber, 2.2, true)
	if not reduced:
		var flicker: float = 0.65 + 0.35 * sin(elapsed * 43.0)
		draw_line(spark - Vector2(3,0), spark + Vector2(3,0), Color(amber, opacity * flicker), 1.1, true)
		draw_line(spark - Vector2(0,3), spark + Vector2(0,3), Color(amber, opacity * flicker), 1.1, true)
		if landing < 1.0:
			draw_line(body + Vector2(3,-20), body + Vector2(1,-12), Color(brass, opacity * (1.0 - landing) * 0.5), 1.2, true)
			draw_line(body + Vector2(-3,-16), body + Vector2(-2,-11), Color(amber, opacity * (1.0 - landing) * 0.34), 1.0, true)

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
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var strength: float = clampf(pulse / 0.22, 0.0, 1.0)
	# The true damage boundary remains exact in both modes. There is no filled
	# dome or elevated frame to obscure enemies, their feet or warning markings.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(ink, fading * (0.58 + strength * 0.28)), 2.0 + strength * 0.65, true)
	for index in range(6):
		var axis: Vector2 = Vector2.RIGHT.rotated(index * TAU / 6.0 - PI * 0.5)
		var at: Vector2 = axis * radius
		_draw_arcane_rune(at, 5.0, Color(paper, fading * (0.68 + strength * 0.2)))
	_draw_arcane_rune(Vector2.ZERO, 10.0, Color(paper, fading * (0.48 + strength * 0.4)))
	if reduced:
		return
	# A few stationary stars linked into asymmetric constellations give this
	# sustained spell its own silhouette without filling the interior with haze.
	var stars := PackedVector2Array()
	for index in range(8):
		var angle: float = index * TAU / 8.0 + PI * 0.13
		var reach: float = radius * (0.57 if index % 2 == 0 else 0.73)
		stars.append(Vector2.RIGHT.rotated(angle) * reach)
	for link: Vector2i in [Vector2i(0,2),Vector2i(2,5),Vector2i(5,0),Vector2i(1,4),Vector2i(4,7)]:
		draw_line(stars[link.x], stars[link.y], Color(ink, fading * (0.14 + strength * 0.12)), 1.0, true)
	for index in stars.size():
		var star: Vector2 = stars[index]
		var half: float = 2.6 if index % 2 == 0 else 1.8
		draw_line(star - Vector2(half,0), star + Vector2(half,0), Color(paper, fading * 0.7), 1.2, true)
		draw_line(star - Vector2(0,half), star + Vector2(0,half), Color(paper, fading * 0.7), 1.2, true)
	for index in range(12):
		var angle: float = index * TAU / 12.0
		draw_arc(Vector2.ZERO, radius * 0.94, angle + 0.055, angle + TAU / 24.0, 7, Color(paper, fading * 0.28), 1.1, true)
	if pulse > 0.0:
		# pulse is authored by the real one-second damage tick and lasts 0.22 s.
		draw_arc(Vector2.ZERO, radius * (0.2 + (1.0 - strength) * 0.8), 0.0, TAU, 64, Color(paper, strength * 0.56 * fading), 2.0, true)

func _draw_arcane_rune(at: Vector2, size: float, tint: Color) -> void:
	var glyph := PackedVector2Array([at + Vector2(0,-size),at + Vector2(size * 0.68,0),at + Vector2(0,size),at + Vector2(-size * 0.68,0),at + Vector2(0,-size)])
	draw_polyline(glyph, tint, 1.3, true)
	draw_line(at + Vector2(-size * 0.85,0), at + Vector2(size * 0.85,0), tint, 1.1, true)

func _deployment_ellipse(center: Vector2, axes: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments + 1):
		var angle: float = index * TAU / float(segments)
		points.append(center + Vector2(cos(angle) * axes.x, sin(angle) * axes.y))
	return points

func _deployment_local_shape(points: PackedVector2Array, origin: Vector2, angle: float) -> PackedVector2Array:
	var transformed := PackedVector2Array()
	for point: Vector2 in points:
		transformed.append(origin + point.rotated(angle))
	return transformed
