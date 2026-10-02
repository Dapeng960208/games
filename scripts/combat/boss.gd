class_name MineBoss
extends MineEnemy
## Room integration contract:
##   spawn  : BossScript.new(), assign room/position, then add_child()
##   config : configure_boss("BO01".."BO04", difficulty, optional_seed)
##   tick   : inherited _physics_process drives BossBrain exactly once
##   render : EnemyBody draws the body; this actor draws bars and arena markers
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
var _solar_disabled: bool = false
var _grave_spawned: int = 0
var _grave_receipts: Array[Dictionary] = []
var _grave_registered: Dictionary = {}

func configure_boss(id: String, difficulty: int = 0, seed_value: int = 0, ruleset: int = 1, calibration_snapshot: Dictionary = {}) -> bool:
	var resolved: Dictionary = Profiles.resolve(id, difficulty, ruleset, calibration_snapshot)
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
	# Reconfiguration/retry starts a fresh encounter, including finite attempts.
	if is_instance_valid(room) and is_instance_valid(room.enemy_skills):
		room.enemy_skills.cancel_owner(self)
	_retire_owned_children()
	_complete = false
	_completion_payload.clear()
	_reinforcement_queue.clear()
	_requested_phases.clear()
	_requested_reinforcement_count = 0
	_requested_reinforcement_threat = 0
	_solar_disabled = false
	_grave_spawned = 0
	_grave_receipts.clear()
	_grave_registered.clear()
	if has_meta("boss_weakpoint"):
		remove_meta("boss_weakpoint")
	for key: String in ["enemy_pod_broken", "enemy_charge_wall_stop"]:
		if has_meta(key): remove_meta(key)
	if health != null:
		health.reset(float(profile.get("max_hp", 1.0)), int(profile.get("ruleset_version", 1)))
	status = StatusScript.new(int(profile.get("ruleset_version", 1)))
	if boss_id == "BO01":
		status.grant_guard(health.maximum * 0.22, 3600.0, "boss_solar", health.maximum)
	boss_brain = BossBrainScript.new()
	boss_brain.configure(profile, boss_seed)
	brain = boss_brain
	state = &"emerging"
	state_time = 0.8
	_load_boss_art()
	# MineEnemy creates the shared visual before the boss profile loads its much
	# larger portrait. Register the final ground pivot and alpha mask on that
	# existing visual so recoil and surface contacts use the same body we draw.
	if is_instance_valid(body_visual):
		body_visual.configure(self)
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
		if boss_id == "BO01":
			_solar_disabled = true
			status.guards.erase("boss_solar")
		if boss_id == "BO04": _cancel_drum_haste()
		queue_redraw()
	return accepted

func apply_biome_counter(kind: String, duration: float = 2.6) -> bool:
	if boss_brain == null or _complete or not is_alive():
		return false
	var accepted: bool = boss_brain.apply_biome_counter(kind, duration)
	if accepted and kind == "solar_conduit":
		_solar_disabled = true
		status.guards.erase("boss_solar")
	if accepted and kind == "war_drum": _cancel_drum_haste()
	if accepted:
		queue_redraw()
	return accepted

func cast_enemy_skill(skill: Dictionary) -> void:
	if _complete or not is_alive():
		return
	if str(skill.get("kind", "")) == "ground_area" and str(skill.get("shape", "")) == "line" and not skill.get("paths", []).is_empty():
		# Runtime ground areas own one segment each. Release each frozen stroke
		# shown by the warning, including parallel faults and the stitch fence.
		for path: Array in skill.get("paths", []):
			if path.size() < 2: continue
			var stroke: Dictionary = skill.duplicate(true)
			stroke.erase("paths")
			stroke["origin"] = Vector2(path[0])
			stroke["target"] = Vector2(path[1])
			stroke["points"] = [path[0], path[1]]
			stroke["range"] = Vector2(path[0]).distance_to(Vector2(path[1]))
			stroke["direction"] = Vector2(path[0]).direction_to(Vector2(path[1]))
			super.cast_enemy_skill(stroke)
		return
	if str(skill.get("thematic_action", "")) == "grave_recall":
		# Non-rewarding boss adds deliberately never enter the loot corpse pool.
		# These separate death receipts preserve actual revival in boss arenas.
		# Each call is finite, and a descendant cannot register a second receipt.
		if not can_recall_grave() or not is_instance_valid(room) or not room.has_method("spawn_enemy_summon"):
			return
		var receipt: Dictionary = _grave_receipts.pop_front()
		var raised: Node2D = room.spawn_enemy_summon(self, str(receipt.enemy_id), Vector2(receipt.position))
		if is_instance_valid(raised):
			_grave_spawned += 1
			raised.set_meta("boss_grave_recalled", true)
		return
	super.cast_enemy_skill(skill)

func can_recall_grave() -> bool:
	return boss_id == "BO03" and not _complete and boss_brain != null and not boss_brain.grave_sealed and _grave_spawned < int(profile.get("grave_recall_limit", 2)) and not _grave_receipts.is_empty()

func grave_recall_target() -> Vector2:
	return Vector2(_grave_receipts[0].position) if not _grave_receipts.is_empty() else position

func notify_reinforcement_death(enemy: Node2D) -> bool:
	if boss_id != "BO03" or _complete or not is_instance_valid(enemy) or bool(enemy.get_meta("boss_grave_recalled", false)):
		return false
	if enemy.has_method("is_alive") and bool(enemy.is_alive()): return false
	var owner_ref: Variant = enemy.get("owner_enemy")
	if not owner_ref is WeakRef or owner_ref.get_ref() != self or str(enemy.get("actor_kind")) != "enemy" or str(enemy.get("enemy_id")) not in ["M19", "M20", "M21", "M22", "M23", "M24", "M25", "M26", "M27"]:
		return false
	var source_id: int = enemy.get_instance_id()
	if _grave_registered.has(source_id) or _grave_registered.size() >= int(profile.get("grave_recall_limit", 2)):
		return false
	_grave_registered[source_id] = true
	_grave_receipts.append({"enemy_id":str(enemy.get("enemy_id")), "position":enemy.position, "source_id":source_id})
	return true

func _cancel_drum_haste() -> void:
	if not is_instance_valid(room) or not is_instance_valid(room.enemy_skills): return
	for support: Dictionary in room.enemy_skills.supports.duplicate():
		if int(support.get("owner_id", 0)) == get_instance_id() and str(support.get("kind", "")) == "haste":
			room.enemy_skills._remove_support(support)

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
	value["solar_shield"] = status.shield() if status != null else 0.0
	value["solar_disabled"] = _solar_disabled
	value["grave_spawned"] = _grave_spawned
	value["grave_receipts"] = _grave_receipts.size()
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
	var solar_before: float = float(status.guards.get("boss_solar", {}).get("amount", 0.0)) if status != null else 0.0
	var result: bool = super.take_damage(amount * multiplier, kind, from_direction, context)
	if not _complete and boss_id == "BO01" and solar_before > 0.0 and float(status.guards.get("boss_solar", {}).get("amount", 0.0)) <= 0.0:
		_solar_disabled = true
		boss_brain.apply_biome_counter("solar_conduit", 2.8)
	# The inherited receipt captures actual loss before lethal/phase callbacks.
	# A legal support or CombatStatus shield contact confirms even without HP loss.
	return bool(last_damage_result.get("confirmed", false)) if int(profile.get("ruleset_version", Numerical.LEGACY)) == Numerical.V2 else result

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
	# The room adds its difficulty level growth when consuming this request.
	# Retain each boss region's base level so later-area adds do not fall back
	# to level one simply because the catalog wave has no explicit level.
	for member: Dictionary in selected.get("members", []):
		if not member.has("level"):
			member["level"] = int(Profiles.LEVELS.get(boss_id, 1))
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
	_retire_owned_children()
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

func _retire_owned_children() -> void:
	if not is_instance_valid(room) or not is_instance_valid(room.enemies):
		return
	for child: Node in room.enemies.get_children():
		if child == self: continue
		var owner_ref: Variant = child.get("owner_enemy")
		if owner_ref is WeakRef and owner_ref.get_ref() == self:
			child.queue_free()

func _draw() -> void:
	if health == null:
		return
	draw_set_transform(Vector2(0, 25), 0.0, Vector2(1.0, 0.46))
	draw_circle(Vector2.ZERO, navigation_radius * 1.12, Color(0.20,0.17,0.25,0.28))
	draw_set_transform(Vector2.ZERO)
	if boss_brain != null:
		preload("res://scripts/combat/boss_skill_presentation.gd").draw_action(self,boss_brain.action_presentation(),bool(Game.profile.get("settings",{}).get("reduced_fx",false)))
	# The body child is the sole body renderer, including its impact material
	# and anchored transform. A second static portrait here hid that reaction.
	var phase_value: int = boss_brain.phase_index() if boss_brain != null else 1
	for index: int in 3:
		var color := Color("d28d48") if index < phase_value else Color("b9a8b3")
		draw_circle(Vector2(-16 + index * 16, body_bounds.position.y - 24), 4.5, color)
	if boss_brain != null and boss_brain.weakpoint_open():
		draw_arc(Vector2.ZERO, navigation_radius + 12.0, -PI*0.5, PI*1.5, 48, Color("bfe8a7"), 4.0, true)
		draw_circle(Vector2(0, -34), 8.0 + sin(lifetime*8.0)*2.0, Color(0.68,0.95,0.58,0.7))
	var bar_width: float = 176.0
	var bar_y: float = body_bounds.position.y - 14.0
	draw_rect(Rect2(-bar_width*0.5, bar_y, bar_width, 10), Color("f1d9b4"))
	draw_rect(Rect2(-bar_width*0.5, bar_y, bar_width*health.current/maxf(1.0,health.maximum), 10), Color("d65b65"))
	draw_rect(Rect2(-bar_width*0.5, bar_y, bar_width, 10), Color("5b4261"), false, 1.5)
	if boss_id == "BO01" and status.shield() > 0.0:
		draw_rect(Rect2(-bar_width*0.5, bar_y+12, bar_width * clampf(status.shield()/(health.maximum*0.22),0.0,1.0), 4), Color("6accc9"))
		draw_arc(Vector2(0,-30), navigation_radius+14.0, 0.0, TAU, 48, Color(0.42,0.88,0.87,0.65), 3.0, true)
	var label: String = str(profile.get("name_en" if TranslationServer.get_locale().begins_with("en") else "name", boss_id))
	var font: Font = room.fx_font if is_instance_valid(room) and room.get("fx_font") != null else ThemeDB.fallback_font
	var label_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_rect(Rect2(-label_width*0.5-6,bar_y-45,label_width+12,21),Color(1.0,.945,.82,.95))
	draw_rect(Rect2(-label_width*0.5-6,bar_y-45,label_width+12,21),Color("80617e"),false,1.0)
	draw_string(font, Vector2(-label_width*0.5, bar_y-28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("49364f"))

func draw_body_fallback(canvas: Node2D, tint: Color) -> void:
	# EnemyBody invokes this during its own draw, with the final foot offset
	# already removed. The fallback shares recoil, mirroring and flash instead
	# of becoming a second unmoving body on the gameplay actor.
	var colors: Dictionary = EnemyPalette.colors_for(boss_id, profile)
	match boss_id:
		"BO01":
			canvas.draw_rect(Rect2(-52,-72,104,92),(colors.primary as Color)*tint,true)
			for x: float in [-32.0,0.0,32.0]:
				canvas.draw_rect(Rect2(x-10,-105,20,42),(colors.shade as Color)*tint,true)
				canvas.draw_circle(Vector2(x,-105),10,(colors.energy as Color)*tint)
			canvas.draw_line(Vector2(-45,-25),Vector2(-88,16),(colors.trim as Color)*tint,15,true)
			canvas.draw_line(Vector2(45,-25),Vector2(86,9),(colors.trim as Color)*tint,12,true)
		"BO02":
			for index: int in 8:
				var direction := Vector2.from_angle(index*TAU/8.0)
				canvas.draw_polyline(PackedVector2Array([direction*22,direction*58+direction.orthogonal()*10,direction*82]),(colors.shade as Color)*tint,9,true)
			canvas.draw_circle(Vector2(0,-24),48,Color(colors.primary,.82)*tint)
			canvas.draw_circle(Vector2(0,-20),30,(colors.energy as Color)*tint)
		"BO03":
			for angle: float in [-2.55,-0.58,0.58,2.55]:
				var direction := Vector2.from_angle(angle)
				canvas.draw_colored_polygon(PackedVector2Array([direction*18,direction*82+direction.orthogonal()*25,direction*75-direction.orthogonal()*18]),(colors.primary as Color)*tint)
			canvas.draw_rect(Rect2(-29,-72,58,102),(colors.outline as Color)*tint,true)
			canvas.draw_circle(Vector2(0,-22),14,(colors.energy as Color)*tint)
		_:
			canvas.draw_arc(Vector2(0,-30),55,PI,TAU,40,(colors.primary as Color)*tint,22,true)
			for index: int in 4:
				var direction := Vector2.from_angle(index*TAU/4.0+PI*.25)
				canvas.draw_line(direction*38,direction*80,(colors.shade as Color)*tint,13,true)
				canvas.draw_circle(direction*87,14,(colors.trim as Color)*tint)
			canvas.draw_circle(Vector2(0,-25),16,(colors.energy as Color)*tint)
	if bool(Game.profile.get("settings", {}).get("enemy_skill_paths", true)) and state in [&"windup", &"telegraph", &"locked"]:
		canvas.draw_arc(Vector2.ZERO,navigation_radius,0,TAU,40,Color(0.89,0.28,0.27,0.52)*tint,2.0,true)
