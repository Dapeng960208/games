class_name MineBoss
extends MineEnemy
## Room integration contract:
##   spawn  : BossScript.new(), assign room/position, then add_child()
##   config : configure_boss("BO01".."BO04", difficulty, optional_seed)
##   tick   : inherited _physics_process drives BossBrain exactly once
##   render : this CanvasItem draws its art/fallback and the room telegraph
##   finish : completed signal + is_complete()/completion_snapshot()
## Arena actors call apply_arena_counter(). The room drains each finite add wave
## once through take_reinforcement_requests(); spawned adds should use
## reinforcement_spawn_options() so they have no gold/XP and die with the boss.

signal phase_changed(boss_id: String, phase: int, health_ratio: float)
signal weakpoint_changed(boss_id: String, open: bool, weakpoint_id: String, duration: float)
signal reinforcement_requested(request: Dictionary)
signal completed(boss_id: String, payload: Dictionary)

const Profiles = preload("res://scripts/combat/boss_profiles.gd")
const BossBrainScript = preload("res://scripts/combat/boss_brain.gd")
const BossTextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const BossImageBounds = preload("res://scripts/combat/hero_visual.gd")

var boss_id: String = ""
var boss_seed: int = 0
var boss_brain: BossBrain
var _complete: bool = false
var _completion_payload: Dictionary = {}
var _reinforcement_queue: Array[Dictionary] = []
var _requested_phases: Array[int] = []
var _requested_reinforcement_count: int = 0
var _requested_reinforcement_threat: int = 0
var _boss_art_path: String = ""

func configure_boss(id: String, difficulty: int = 0, seed_value: int = 0) -> bool:
	var resolved: Dictionary = Profiles.resolve(id, difficulty)
	if resolved.is_empty() or not Profiles.validate(resolved).is_empty():
		return false
	boss_seed = seed_value if seed_value != 0 else id.hash() ^ (difficulty * 104729)
	configure(resolved, {"reward_enabled":false, "actor_kind":"boss", "zone_index":-1})
	return true

func configure(next_profile: Dictionary, options: Dictionary = {}) -> void:
	var enforced: Dictionary = options.duplicate(true)
	enforced["reward_enabled"] = false
	enforced["actor_kind"] = "boss"
	super.configure(next_profile, enforced)
	boss_id = str(profile.get("boss_id", profile.get("enemy_id", "")))
	rank = "boss"
	actor_kind = "boss"
	reward_enabled = false
	if is_node_ready():
		_initialize_boss_runtime()

func _ready() -> void:
	super._ready()
	_initialize_boss_runtime()

func _initialize_boss_runtime() -> void:
	if boss_id.is_empty() or profile.is_empty():
		return
	if health != null:
		health.reset(float(profile.get("max_hp", 1.0)))
	boss_brain = BossBrainScript.new()
	boss_brain.configure(profile, boss_seed)
	brain = boss_brain
	state = &"emerging"
	state_time = 0.8
	_load_boss_art()
	queue_redraw()

func _load_boss_art() -> void:
	_boss_art_path = str(profile.get("visual_asset", "res://assets/bosses/" + boss_id + ".png"))
	body_texture = BossTextureSampler.sampled(_boss_art_path) if FileAccess.file_exists(_boss_art_path) or ResourceLoader.exists(_boss_art_path) else null
	body_region = Rect2()
	if body_texture == null:
		body_bounds = Rect2(-82, -122, 164, 164)
		return
	var image: Image = body_texture.get_image()
	body_region = BossImageBounds._visible_region(image) if image != null and not image.is_empty() else Rect2(Vector2.ZERO, body_texture.get_size())
	var height: float = clampf(navigation_radius * 3.45, 170.0, 220.0)
	var width: float = body_region.size.x / maxf(1.0, body_region.size.y) * height
	body_bounds = Rect2(-width * 0.5, 48.0 - height, width, height)

func boss_phase_started(next_phase: int, ratio: float) -> void:
	# Every phase owns a fresh hazard set. This removes pools/charges from the old
	# phase before its reinforcement notification can be consumed by the room.
	if is_instance_valid(room) and is_instance_valid(room.enemy_skills):
		room.enemy_skills.cancel_owner(self)
	phase_changed.emit(boss_id, next_phase, ratio)
	_queue_reinforcement_wave(next_phase)
	queue_redraw()

func boss_weakpoint_changed(open: bool, id: String, duration: float) -> void:
	set_meta("boss_weakpoint", id if open else "")
	weakpoint_changed.emit(boss_id, open, id, duration)
	queue_redraw()

func apply_arena_counter(counter_id: String, payload: Dictionary = {}) -> bool:
	if boss_brain == null or _complete:
		return false
	var accepted: bool = boss_brain.apply_arena_counter(counter_id, payload)
	if accepted:
		queue_redraw()
	return accepted

func take_reinforcement_requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = _reinforcement_queue.duplicate(true)
	_reinforcement_queue.clear()
	return result

func reinforcement_spawn_options() -> Dictionary:
	return {"owner":self, "reward_enabled":false, "actor_kind":"enemy", "zone_index":zone_index}

func reinforcement_status() -> Dictionary:
	return {
		"requested_phases":_requested_phases.duplicate(),
		"count":_requested_reinforcement_count,
		"threat":_requested_reinforcement_threat,
		"cap":int(profile.get("reinforcement_cap",0)),
		"budget":int(profile.get("reinforcement_budget",0)),
		"pending":_reinforcement_queue.size(),
	}

func combat_snapshot() -> Dictionary:
	var value: Dictionary = boss_brain.combat_snapshot() if boss_brain != null else {"boss_id":boss_id, "phase":1, "state":str(state)}
	value["health_ratio"] = health.current / maxf(1.0, health.maximum) if health != null else 1.0
	value["reinforcements"] = reinforcement_status()
	value["complete"] = _complete
	return value

func render_state() -> Dictionary:
	return {
		"asset_path":_boss_art_path,
		"asset_loaded":body_texture != null,
		"bounds":body_bounds,
		"phase":boss_brain.phase_index() if boss_brain != null else 1,
		"weakpoint":str(get_meta("boss_weakpoint", "")),
	}

func is_complete() -> bool:
	return _complete

func completion_snapshot() -> Dictionary:
	return _completion_payload.duplicate(true) if _complete else {
		"boss_id":boss_id,
		"complete":false,
		"phase":boss_brain.phase_index() if boss_brain != null else 1,
	}

func take_damage(amount: float, kind: StringName, from_direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
	var multiplier: float = boss_brain.incoming_damage_multiplier() if boss_brain != null else 1.0
	return super.take_damage(amount * multiplier, kind, from_direction, context)

func _queue_reinforcement_wave(next_phase: int) -> void:
	if next_phase in _requested_phases:
		return
	var selected: Dictionary = {}
	for wave: Dictionary in profile.get("reinforcement_waves", []):
		if int(wave.get("phase", 0)) == next_phase:
			selected = wave.duplicate(true)
			break
	if selected.is_empty():
		return
	var count: int = int(selected.get("count", 0))
	var threat: int = int(selected.get("threat", 0))
	if _requested_reinforcement_count + count > int(profile.get("reinforcement_cap", 0)) or _requested_reinforcement_threat + threat > int(profile.get("reinforcement_budget", 0)):
		return
	_requested_phases.append(next_phase)
	_requested_reinforcement_count += count
	_requested_reinforcement_threat += threat
	selected.merge({
		"boss_id":boss_id,
		"reward_enabled":false,
		"owner_required":true,
		"cap_remaining":int(profile.get("reinforcement_cap", 0))-_requested_reinforcement_count,
		"budget_remaining":int(profile.get("reinforcement_budget", 0))-_requested_reinforcement_threat,
	}, true)
	if is_instance_valid(room):
		selected["spawn_points"] = room.layout.get("reinforcement_spawns", room.layout.get("spawn_points", [])).duplicate()
	_reinforcement_queue.append(selected)
	reinforcement_requested.emit(selected.duplicate(true))

func _die() -> void:
	if _complete:
		return
	_complete = true
	if boss_brain != null:
		boss_brain.stop(self)
	if is_instance_valid(room) and is_instance_valid(room.enemy_skills):
		room.enemy_skills.cancel_owner(self)
	_completion_payload = {
		"boss_id":boss_id,
		"complete":true,
		"phase":boss_brain.phase_index() if boss_brain != null else 1,
		"elapsed":lifetime,
		"reinforcements":reinforcement_status(),
		"counters":boss_brain.counter_snapshot() if boss_brain != null else {},
	}
	if is_instance_valid(room) and room.has_method("enemy_died"):
		room.enemy_died(self)
	completed.emit(boss_id, _completion_payload.duplicate(true))
	queue_free()

func _draw() -> void:
	if health == null:
		return
	if is_instance_valid(room) and room.has_method("draw_enemy_telegraph") and boss_brain != null:
		room.draw_enemy_telegraph(self, boss_brain.current_telegraph())
	draw_set_transform(Vector2(0, 25), 0.0, Vector2(1.0, 0.46))
	draw_circle(Vector2.ZERO, navigation_radius * 1.12, Color(0.01,0.015,0.02,0.62))
	draw_set_transform(Vector2.ZERO)
	if body_texture != null:
		if body_region.has_area():
			draw_texture_rect_region(body_texture, body_bounds, body_region, Color.WHITE)
		else:
			draw_texture_rect(body_texture, body_bounds, false, Color.WHITE)
	else:
		_draw_boss_fallback()
	var phase_value: int = boss_brain.phase_index() if boss_brain != null else 1
	for index: int in 3:
		var color := Color("f0ad68") if index < phase_value else Color("38434a")
		draw_circle(Vector2(-16 + index * 16, body_bounds.position.y - 24), 4.5, color)
	if boss_brain != null and boss_brain.weakpoint_open():
		draw_arc(Vector2.ZERO, navigation_radius + 12.0, -PI*0.5, PI*1.5, 48, Color("bfe8a7"), 4.0, true)
		draw_circle(Vector2(0, -34), 8.0 + sin(lifetime*8.0)*2.0, Color(0.68,0.95,0.58,0.7))
	var bar_width: float = 176.0
	var bar_y: float = body_bounds.position.y - 14.0
	draw_rect(Rect2(-bar_width*0.5, bar_y, bar_width, 10), Color("0a1015"))
	draw_rect(Rect2(-bar_width*0.5, bar_y, bar_width*health.current/maxf(1.0,health.maximum), 10), Color("d95f51"))
	draw_rect(Rect2(-bar_width*0.5, bar_y, bar_width, 10), Color("efc185"), false, 1.5)
	var label: String = str(profile.get("name_en" if TranslationServer.get_locale().begins_with("en") else "name", boss_id))
	var font: Font = room.fx_font if is_instance_valid(room) and room.get("fx_font") != null else ThemeDB.fallback_font
	var label_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(-label_width*0.5, bar_y-7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f1dfbd"))

func _draw_boss_fallback() -> void:
	match boss_id:
		"BO01":
			draw_rect(Rect2(-52,-72,104,92),Color("48535a"),true)
			for x: float in [-32.0,0.0,32.0]:
				draw_rect(Rect2(x-10,-105,20,42),Color("743c2c"),true)
				draw_circle(Vector2(x,-105),10,Color("e1884f"))
			draw_line(Vector2(-45,-25),Vector2(-88,16),Color("b08a63"),15,true)
			draw_line(Vector2(45,-25),Vector2(86,9),Color("9c6b46"),12,true)
		"BO02":
			for index: int in 8:
				var direction := Vector2.from_angle(index*TAU/8.0)
				draw_polyline(PackedVector2Array([direction*22,direction*58+direction.orthogonal()*10,direction*82]),Color("657a53"),9,true)
			draw_circle(Vector2(0,-24),48,Color(0.45,0.67,0.48,0.82))
			draw_circle(Vector2(0,-20),30,Color("744e68"))
		"BO03":
			for angle: float in [-2.55,-0.58,0.58,2.55]:
				var direction := Vector2.from_angle(angle)
				draw_colored_polygon(PackedVector2Array([direction*18,direction*82+direction.orthogonal()*25,direction*75-direction.orthogonal()*18]),Color("596a79"))
			draw_rect(Rect2(-29,-72,58,102),Color("202c37"),true)
			draw_circle(Vector2(0,-22),14,Color("85d3dc"))
		_:
			draw_arc(Vector2(0,-30),55,PI,TAU,40,Color("8d7b78"),22,true)
			for index: int in 4:
				var direction := Vector2.from_angle(index*TAU/4.0+PI*.25)
				draw_line(direction*38,direction*80,Color("69616c"),13,true)
				draw_circle(direction*87,14,Color("a47c5d"))
			draw_circle(Vector2(0,-25),16,Color("e8c96f"))
	draw_arc(Vector2.ZERO,navigation_radius,0,TAU,40,Color(0.91,0.57,0.38,0.48),2.0,true)
