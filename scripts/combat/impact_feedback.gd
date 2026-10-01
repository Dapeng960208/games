extends Node2D
## Confirmed contact only. This layer has no strong references to actors, damage
## resolvers or gameplay RNG. Enemy danger telegraphs remain above it.

const MAX_EVENTS: int = 32
const CONTACT_ANCHOR_TIME: float = 0.08
const AMBER := Color("f0b86b")
const IVORY := Color("fff0c9")
const JADE := Color("77e5d5")
const VIOLET := Color("c5a9ed")
const CONTACT_INK := Color("17232b")
const SHIELD_BLUE := Color("9bddec")
const SHIELD_EDGE := Color("e5faff")
const NumberPresentation = preload("res://scripts/combat/damage_numbers.gd")
var events: Array[Dictionary] = []
var accepted_events: int = 0
var culled_events: int = 0
var active_peak: int = 0
var _serial: int = 0
var _font: Font

func _init() -> void:
	name = "ImpactFeedback"
	z_index = 3
	process_mode = Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		_font = load("res://assets/fonts/NotoSansSC.ttf")

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	for index in range(events.size() - 1, -1, -1):
		contact_position(events[index])
		events[index].age += delta
		if float(events[index].age) >= float(events[index].duration):
			events.remove_at(index)
	# Clear the last rendered frame as well as the event data.
	queue_redraw()

func confirm_hit(at: Vector2, direction: Vector2, event: Dictionary) -> void:
	var damage: float = float(event.get("damage", 0.0))
	if not at.is_finite() or not is_finite(damage) or damage <= 0.0:
		return
	var reduced: bool = _reduced()
	var heavy: bool = bool(event.get("heavy", false))
	var passive: bool = bool(event.get("passive", false))
	var critical: bool = bool(event.get("critical", false))
	var hero: String = str(event.get("hero_id", "CH01"))
	if hero not in ["CH01", "CH02", "CH03"]:
		hero = "CH01"
	var material: String = str(event.get("material", "stone"))
	if material not in ["stone", "metal", "organic"]:
		material = "stone"
	var dir: Vector2 = direction.normalized() if direction.is_finite() and direction.length_squared() > 0.001 else Vector2.RIGHT
	var nearby: int = 0
	for old in events:
		if old.kind == "hit" and float(old.age) < 0.06 and Vector2(old.at).distance_squared_to(at) < 75.0 * 75.0:
			nearby += 1
	# Close simultaneous cleave targets retain their own point of contact,
	# with smaller debris instead of overlapping full-size explosions.
	var density: float = maxf(0.58, 1.0 - nearby * 0.14)
	var radius: float = (43.0 if heavy else 26.0) + (5.0 if critical else 0.0)
	_serial += 1
	var hit: Dictionary = {"kind":"hit", "at":at, "direction":dir, "hero_id":hero,
		"heavy":heavy, "passive":passive, "critical":critical, "killed":bool(event.get("killed", false)),
		"material":material, "source":str(event.get("source", "primary")),
		"damage":float(event.get("damage", 0.0)), "age":0.0,
		"duration":0.12 if reduced or passive else (0.27 if heavy else 0.19),
		"radius":radius * density * (0.55 if passive else 1.0), "density":density, "reduced":reduced, "serial":_serial}
	# Keep the original packet's absorption separate from flesh/armour contact.
	# Older callers without a split remain ordinary body hits.
	hit["hp_damage"] = maxf(0.0, float(event.get("hp_damage", damage)))
	hit["shield_damage"] = maxf(0.0, float(event.get("shield_damage", 0.0)))
	hit["shield_broken"] = float(hit.shield_damage) > 0.0 and bool(event.get("shield_broken", false))
	if bool(hit.shield_broken) and not reduced and not passive:
		hit.duration = maxf(float(hit.duration), 0.26)
	# WeakRef is mandatory: cosmetic debris must never keep its victim alive.
	if event.get("anchor") is WeakRef:
		hit.anchor = event.anchor
		hit.anchor_offset = event.get("anchor_offset", Vector2.ZERO) if event.get("anchor_offset", Vector2.ZERO) is Vector2 else Vector2.ZERO
	if event.get("visual_anchor") is WeakRef and event.get("visual_offset") is Vector2:
		hit.visual_anchor = event.visual_anchor
		hit.visual_offset = event.visual_offset
	_append(hit)
	accepted_events += 1

func contact_position(event: Dictionary) -> Vector2:
	var at: Vector2 = event.get("at", Vector2.ZERO)
	if str(event.get("kind", "")) != "hit":
		return at
	if float(event.get("age", 0.0)) >= CONTACT_ANCHOR_TIME:
		event.erase("anchor")
		event.erase("visual_anchor")
		return at
	if is_inside_tree() and get_tree().paused:
		return at
	if event.get("visual_anchor") is WeakRef:
		var visual: Object = event.visual_anchor.get_ref()
		if not is_instance_valid(visual) or not visual is Node2D or visual.is_queued_for_deletion():
			# Do not jump back to the actor's old center if its body disappears.
			event.erase("visual_anchor")
			event.erase("anchor")
			return at
		var surface: Vector2 = to_local(visual.to_global(Vector2(event.visual_offset)))
		if surface.is_finite():
			event.at = surface
			return surface
		return at
	if not event.get("anchor") is WeakRef:
		return at
	var actor: Object = event.anchor.get_ref()
	if not is_instance_valid(actor) or not actor is Node2D or actor.is_queued_for_deletion():
		event.erase("anchor")
		return at
	var point: Vector2 = actor.position + Vector2(event.get("anchor_offset", Vector2.ZERO))
	if point.is_finite():
		event.at = point
		return point
	return at

func add_floating_damage(at: Vector2, amount: float, kind: StringName, context: Dictionary = {}) -> void:
	if amount <= 0.0 or not is_finite(amount) or not at.is_finite():
		return
	var lane: int = 0
	for old in events:
		if old.kind == "number" and float(old.age) < 0.28 and Vector2(old.origin).distance_squared_to(at) < 42.0 * 42.0:
			lane += 1
	var offset := Vector2(float((lane % 3) - 1) * 29.0 if lane > 0 else 0.0, -float(lane % 3) * 17.0)
	_append({"kind":"number", "at":at + offset, "origin":at, "amount":amount,
		"source":str(kind), "age":0.0, "duration":0.72, "reduced":_reduced(),
		"presentation":NumberPresentation.presentation(amount, str(kind), context)})

func clear_feedback() -> void:
	events.clear()
	queue_redraw()

func _append(event: Dictionary) -> void:
	if events.size() >= MAX_EVENTS:
		var oldest_number: int = -1
		for index in events.size():
			if events[index].kind == "number":
				oldest_number = index
				break
		events.remove_at(oldest_number if oldest_number >= 0 else 0)
		culled_events += 1
	events.append(event)
	active_peak = maxi(active_peak, events.size())
	queue_redraw()

func _reduced() -> bool:
	return bool(Game.profile.get("settings", {}).get("reduced_fx", false))

func _draw() -> void:
	for event in events:
		if event.kind == "number":
			_draw_number(event)
			continue
		# The strike's knockback can happen after confirm_hit in the same frame.
		var at: Vector2 = contact_position(event)
		var dir: Vector2 = event.direction
		var t: float = clampf(float(event.age) / float(event.duration), 0.0, 1.0)
		var fade: float = (1.0 - t) * (1.0 - t) * (0.52 if bool(event.get("passive", false)) else 1.0)
		var radius: float = event.radius
		var hero: String = event.hero_id
		if float(event.shield_damage) > 0.0:
			_draw_shield_contact(at, dir, radius, t, fade, event)
			# Pure absorption has no flesh fragments or armour sparks. Overflow
			# retains the class-shaped contact underneath the ruptured membrane.
			if float(event.hp_damage) <= 0.0:
				continue
		if bool(event.reduced):
			# A fixed contact mark: no drifting particles, pulsing or camera motion.
			var tint: Color = JADE if hero == "CH03" else IVORY if hero == "CH02" else AMBER
			var normal := dir.orthogonal()
			draw_line(at - dir * 7.0, at + dir * 8.0, Color(tint, 0.85 * fade), 2.0, true)
			draw_line(at - normal * 5.0, at + normal * 5.0, Color(tint, 0.65 * fade), 1.5, true)
			continue
		match hero:
			"CH01": _draw_cleave(at, dir, radius, t, fade, event)
			"CH02":
				if str(event.source) == "f":
					_draw_blast_contact(at, dir, radius, t, fade, event)
				else:
					_draw_pierce(at, dir, radius, t, fade, event)
			"CH03": _draw_crystal(at, dir, radius, t, fade, event)

func _draw_shield_contact(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, event: Dictionary) -> void:
	var n := dir.orthogonal()
	var broken: bool = bool(event.shield_broken)
	var half_height: float = minf(radius * 0.68, 26.0)
	var width: float = half_height * 0.36
	if bool(event.reduced):
		# Preserve the distinction with two fixed, disconnected halves. No burst
		# or additional camera kick when reduced effects is selected.
		var gap: float = 4.0 if broken else 0.0
		_contact_line(PackedVector2Array([at - n * half_height, at - dir * width - n * gap]), SHIELD_BLUE, fade, 2.0)
		_contact_line(PackedVector2Array([at - dir * width + n * gap, at + n * half_height]), SHIELD_BLUE, fade, 2.0)
		return
	# A narrow shield facet facing the incoming strike, not an AoE warning ring.
	# Two convex half-planes are pinched together, then separate on a real break.
	var separation: float = smoothstep(0.05, 0.8, t) * (13.0 if broken else 0.0)
	var dent: float = sin(minf(1.0, t * 2.0) * PI) * (2.5 if not broken else 1.0)
	for side: float in [-1.0, 1.0]:
		var center: Vector2 = at + n * side * separation + dir * dent
		var fragment := PackedVector2Array([
			center - dir * width * 0.8 + n * side * 1.0,
			center - dir * width + n * side * half_height * 0.55,
			center + n * side * half_height,
			center + dir * width * 0.7 + n * side * half_height * 0.50,
			center + dir * width * 0.45 + n * side * 1.0])
		draw_colored_polygon(fragment, Color(SHIELD_BLUE, fade * (0.24 if broken else 0.18)))
		var outline: PackedVector2Array = fragment.duplicate()
		outline.append(fragment[0])
		_contact_line(outline, SHIELD_BLUE, fade * 0.95, 1.7)
		if broken:
			# The newly exposed edge is brighter, leaving the body and enemy tell visible.
			_contact_line(PackedVector2Array([fragment[0], center - dir * width * 0.05 + n * side * 3.0, fragment[4]]), SHIELD_EDGE, fade, 2.0)
	if not broken:
		var contact: float = _core_strength(event, 0.055, 0.075)
		_contact_line(PackedVector2Array([at - n * 5.0, at + dir * 2.0, at + n * 5.0]), SHIELD_EDGE, contact, 2.2)

func _draw_cleave(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, event: Dictionary) -> void:
	var n := dir.orthogonal()
	var snap: float = _core_strength(event, 0.075, 0.09)
	var center := at + dir * (1.0 + t * 2.0)
	var extent: float = radius * 0.45
	# A broad diagonal axe bite, with a bright cutting edge and copper wake.
	# Its narrow waist keeps the actual enemy silhouette readable on contact.
	var cut := (n + dir * 0.32).normalized()
	var core := PackedVector2Array([center - cut * extent * 1.12,
		center - cut * extent * 0.75 - dir * extent * 0.26,
		center + cut * extent * 0.78 - dir * extent * 0.12,
		center + cut * extent * 1.15,
		center + cut * extent * 0.72 + dir * extent * 0.22,
		center - cut * extent * 0.68 + dir * extent * 0.12])
	_contact_chip(core, AMBER, snap)
	draw_line(center - cut * extent * 0.9, center + cut * extent * 0.94, Color(IVORY, snap), 3.1, true)
	# One broken, flattened pressure front; it reads as compression, not a spell ring.
	if bool(event.heavy):
		var pressure := PackedVector2Array()
		for index in 9:
			var angle: float = lerpf(-1.15, 1.15, float(index) / 8.0)
			pressure.append(center + dir * cos(angle) * radius * (0.28 + t * 0.35) + n * sin(angle) * radius * (0.4 + t * 0.45))
		_contact_line(pressure, AMBER, fade * 0.55, 2.2)
	_draw_fragments(at, dir, radius, t, fade, event, 7 if bool(event.heavy) else 5)

func _draw_blast_contact(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, event: Dictionary) -> void:
	var snap: float = _core_strength(event, 0.055, 0.075)
	var shard := PackedVector2Array([at - dir * 7.0, at - dir.orthogonal() * 8.0,
		at + dir * 10.0, at + dir.orthogonal() * 8.0])
	_contact_chip(shard, AMBER, snap)
	for index in 6:
		var ray := dir.rotated(TAU * index / 6.0 + 0.18)
		var reach: float = radius * (0.34 + t * 0.65)
		_contact_line(PackedVector2Array([at + ray * reach * 0.55, at + ray * reach]), AMBER if index % 2 == 0 else IVORY, fade * 0.8, 2.2)
	_draw_fragments(at, dir, radius * 0.7, t, fade, event, 4)

func _draw_pierce(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, event: Dictionary) -> void:
	var n := dir.orthogonal()
	var snap: float = _core_strength(event, 0.055, 0.07)
	var tip := at + dir * radius * (0.85 + t * 0.12)
	var half_width: float = radius * 0.13
	var flash := PackedVector2Array([at - dir * radius * 0.38,
		at - dir * 2.0 - n * half_width, tip, at + n * half_width])
	_contact_chip(flash, IVORY, snap)
	_contact_line(PackedVector2Array([at - dir * 5.0, tip]), AMBER, fade * 0.85, 1.8)
	for index in (6 if bool(event.heavy) else 4):
		var noise: float = _noise(int(event.serial), index)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var ray := dir.rotated(side * (0.38 + noise * 0.72))
		var reach: float = radius * (0.5 + noise * 0.42)
		var start := at + ray * reach * (0.12 + t * 0.42)
		var end := at + ray * reach * (0.45 + t * 0.52)
		_contact_line(PackedVector2Array([start, end]), IVORY if index % 3 == 0 else AMBER, fade * 0.85, 1.5)
	if str(event.material) != "metal":
		_draw_fragments(at, dir, radius * 0.65, t, fade * 0.7, event, 3)

func _draw_crystal(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, event: Dictionary) -> void:
	var snap: float = _core_strength(event, 0.08, 0.095)
	var n := dir.orthogonal()
	var extent: float = radius * 0.38
	var core := PackedVector2Array([at - dir * extent, at - n * extent * 0.66,
		at + dir * extent, at + n * extent * 0.66])
	_contact_chip(core, JADE, snap)
	draw_line(at - dir * extent * 0.6, at + dir * extent * 0.6, Color(IVORY, snap), 2.3, true)
	if bool(event.heavy):
		for facet in 3:
			var angle: float = dir.angle() + facet * TAU / 3.0
			draw_arc(at, radius * (0.35 + t * 0.18), angle, angle + 0.75, 8, Color(VIOLET, fade * 0.68), 1.6, true)
	# Split into separate facets after the central fracture; unlike a gun spark,
	# the pieces open sideways. This is a local contact, never an extra AoE tell.
	var opening: float = smoothstep(0.04, 0.55, t)
	var count: int = 6 if bool(event.heavy) else 4
	for index in count:
		var noise: float = _noise(int(event.serial), index)
		var ray := dir.rotated(TAU * float(index) / float(count) + noise * 0.33)
		var reach: float = radius * (0.62 + noise * 0.3)
		var bend := at + ray * reach * 0.5 + ray.orthogonal() * (noise - 0.5) * 10.0
		var end := at + ray * reach * (0.68 + t * 0.25)
		var fracture := PackedVector2Array([at + ray * (3.0 + opening * 5.0), bend, end])
		var tint: Color = JADE if index % 2 == 0 else VIOLET
		_contact_line(fracture, tint, fade * 0.9, 1.8)
		var shard_at := end + ray * t * 3.0
		var size: float = radius * (0.09 + noise * 0.03)
		var shard := PackedVector2Array([shard_at - ray * size,
			shard_at + ray.orthogonal() * size * 0.5, shard_at + ray * size,
			shard_at - ray.orthogonal() * size * 0.5])
		_contact_chip(shard, tint, fade * (0.5 + opening * 0.25))

func _core_strength(event: Dictionary, light_end: float, heavy_end: float) -> float:
	# Absolute time gives two or more visible frames at ordinary frame rates.
	# No oscillation, repeated flash or extra effect on a whiff. Passive contact
	# scales the entire core as well as its debris (previously only debris faded).
	var end: float = heavy_end if bool(event.heavy) else light_end
	return (1.0 - smoothstep(0.012, end, float(event.age))) * (0.52 if bool(event.passive) else 1.0)

func _contact_chip(points: PackedVector2Array, tint: Color, opacity: float) -> void:
	if opacity <= 0.001:
		return
	draw_colored_polygon(points, Color(tint, opacity))
	var rim: PackedVector2Array = points.duplicate()
	rim.append(points[0])
	draw_polyline(rim, Color(CONTACT_INK, opacity * 0.85), 1.5, true)

func _contact_line(points: PackedVector2Array, tint: Color, opacity: float, width: float) -> void:
	# One small under-stroke, not a full-screen glow or an opaque impact decal.
	draw_polyline(points, Color(CONTACT_INK, opacity * 0.65), width + 1.8, true)
	draw_polyline(points, Color(tint, opacity), width, true)

func _draw_fragments(at: Vector2, dir: Vector2, radius: float, t: float, fade: float, event: Dictionary, count: int) -> void:
	var material: String = event.material
	var tint: Color = Color("d8b17b") if material == "metal" else Color("b6a18a") if material == "stone" else Color("adbe83")
	for index in count:
		var noise: float = _noise(int(event.serial), index)
		var ray := dir.rotated((float(index) / float(maxi(count - 1, 1)) - 0.5) * 3.6 + (noise - 0.5) * 0.3)
		var reach: float = radius * (0.62 + noise * 0.35)
		var point := at + ray * reach * (0.23 + t * 0.67) + Vector2(0, t * t * 6.0)
		if material == "metal":
			_contact_line(PackedVector2Array([point - ray * (4.0 + noise * 3.0), point]), tint, fade, 1.65)
		else:
			var size: float = 1.8 + noise * 2.0
			var chip := PackedVector2Array([point - ray * size, point + ray.orthogonal() * size * 0.65, point + ray * size * 0.8])
			_contact_chip(chip, tint, fade * 0.85)

func _draw_number(event: Dictionary) -> void:
	NumberPresentation.draw_number(self, _font, event)

func _noise(serial: int, index: int) -> float:
	# Cosmetic deterministic variation never advances the room's seeded RNG.
	var value: float = sin(float(serial * 71 + index * 137) * 0.731) * 4375.8545
	return value - floorf(value)
