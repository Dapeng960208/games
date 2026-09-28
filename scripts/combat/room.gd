class_name MineRoom
extends Node2D

signal interaction_requested(kind: String, payload: Dictionary)
signal hint_changed(key: String, data: Dictionary)
signal room_completed()

const PlayerScene = preload("res://scenes/player.tscn")
const EnemyScene = preload("res://scenes/enemy.tscn")
const ProjectileScene = preload("res://scenes/projectile.tscn")
const DeploymentScript = preload("res://scripts/combat/hero_deployment.gd")
const CameraScript = preload("res://scripts/combat/world_camera.gd")
const Layouts = preload("res://scripts/world/room_layouts.gd")
const EnemyProfilesScript = preload("res://scripts/combat/enemy_profiles.gd")
const EnemySkillsScript = preload("res://scripts/combat/enemy_skill_runtime.gd")
const PropsScript = preload("res://scripts/world/room_props.gd")
const AudioScript = preload("res://scripts/combat/combat_audio.gd")
const Generator = preload("res://scripts/world/room_generator.gd")
const InteractionSampler = preload("res://scripts/ui/texture_sampler.gd")
const ARENA := Rect2(0, 0, 2800, 1800)
const EXIT_POSITION := Vector2(2696, 900)
const RELIC_POSITIONS := {"split": Vector2(425,959), "ember": Vector2(1466,354), "arc": Vector2(1962,885)}

var player: SalvagerPlayer
@onready var enemies: Node2D = $Enemies
@onready var projectiles: Node2D = $Projectiles
var telemetry: Dictionary = {"shots":0,"primary_hits":0,"child_hits":0,"split_spawned":0,"burn_ticks":0,"arc_hits":0,"kills":0,"gold_collected":0,"dashes":0,"player_hits":0}
var gold_drops: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var input_blocked: bool = false
var release_gate: bool = true
var spawn_timer: float = Balance.ENEMY_SPAWN_INTERVAL
var wave: int = 0
var elapsed: float = 0.0
var current_hint: String = ""
var spawn_enabled: bool = true
var fx_font: Font
var relic_textures: Dictionary = {}
var geometry_enabled: bool = true
var obstructions: Array[Rect2] = []
var objective_complete: bool = false
var objective_wave_count: int = 3
var objective_rewarded: bool = false
var tutorial_distance: float = 0.0
var _previous_player_position := Vector2.ZERO
var attack_serial: int = 0
var crit_rolls: Dictionary = {}
var layout_id: String = "L01"
var layout: Dictionary = {}
var exit_position := EXIT_POSITION
var relic_positions: Dictionary = RELIC_POSITIONS.duplicate()
var encounter_zones: Array = []
var activated_encounters: Dictionary = {}
var camera: Camera2D
var progress_retry_timer: float = 0.0
var pointer_input_blocked: bool = false
var pointer_release_gate: bool = false
var interaction_overlay: Node2D
var enemy_skills: Node2D
var enemy_props: Node2D
var difficulty: int = 0
var use_generated_layout: bool = true
var run_seed: int = -1
var layout_seed: int = -1
var encounter_progress: Dictionary = {}
var configuration_ready: bool = false
var configuration_error: String = ""
var enemy_corpses: Array[Dictionary] = []
var combat_audio: Node
var last_player_sound_position := Vector2.ZERO
var last_player_sound_time: float = -100.0
var interaction_textures: Dictionary = {}
var _navigation_cache: RefCounted = preload("res://scripts/combat/navigation_cache.gd").new()
var expedition_context: Dictionary = {}
var objectives: Node2D
var _prepared_initial: Dictionary = {}
var _expedition_restore: Dictionary = {}
var _expedition_ready: bool = false
var _completion_emitted: bool = false
var _node_loot_spawned: int = 0
var _boss_actor: Node2D
var _boss_defeated: bool = false

func _ready() -> void:
	if not _prepared_initial.is_empty():
		_install_expedition_layout(_prepared_initial)
		_prepared_initial = {}
	elif geometry_enabled:
		if not load_room_layout(layout_id):
			input_blocked = true
			spawn_enabled = false
			set_physics_process(false)
			return
	else:
		configuration_ready = true
	player = PlayerScene.instantiate()
	player.room = self
	player.position = layout.get("entry", Vector2(250,360))
	add_child(player)
	player.z_index = 2
	combat_audio = AudioScript.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)
	enemy_skills = EnemySkillsScript.new()
	enemy_skills.name = "EnemySkills"
	add_child(enemy_skills)
	enemy_skills.configure(self)
	enemy_skills.z_index = 4
	interaction_overlay = Node2D.new()
	interaction_overlay.z_index = 8
	interaction_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(interaction_overlay)
	interaction_overlay.draw.connect(func() -> void: _draw_interaction_focus(interaction_overlay))
	for icon_key: String in ["interaction", "exit", "loot"]:
		var icon: Texture2D = InteractionSampler.sampled("res://assets/generated/ui/" + icon_key + "_v1.png")
		if icon != null:
			interaction_textures[icon_key] = icon
	camera = CameraScript.new()
	add_child(camera)
	camera.configure(self, player, ARENA)
	$MineBackdrop.configure(ARENA, _biome_id(), hash(layout_id))
	_previous_player_position = player.position
	fx_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		fx_font = load("res://assets/fonts/NotoSansSC.ttf")
	for id in relic_positions:
		var asset_path: String = "res://assets/ui/relic_" + id + ".png"
		if ResourceLoader.exists(asset_path):
			relic_textures[id] = load(asset_path)
	if not expedition_context.is_empty():
		_activate_expedition_content()
		if not _expedition_restore.is_empty():
			restore_expedition_runtime(_expedition_restore)
		_expedition_restore = {}
	elif encounter_zones.is_empty():
		for at in [Vector2(760,400),Vector2(910,350),Vector2(1020,415),Vector2(1010,290)]:
			spawn_enemy(at)
	else:
		_update_encounters()
	set_input_blocked(false)

func controls_enabled() -> bool:
	return not input_blocked and not release_gate and Game.run != null and not get_tree().paused

func set_input_blocked(blocked: bool) -> void:
	input_blocked = blocked
	release_gate = true

func set_pointer_input_blocked(blocked: bool) -> void:
	pointer_input_blocked = blocked
	if blocked:
		pointer_release_gate = true
		if player != null:
			player.attack_buffer = 0.0

func pointer_controls_enabled() -> bool:
	if pointer_input_blocked:
		return false
	if pointer_release_gate:
		var secondary_held: bool = InputMap.has_action("skill_secondary") and Input.is_action_pressed("skill_secondary")
		if not Input.is_action_pressed("attack") and not secondary_held:
			pointer_release_gate = false
	return not pointer_release_gate

func _physics_process(delta: float) -> void:
	if Game.run == null:
		return
	elapsed += delta
	if is_instance_valid(enemy_props):
		enemy_props.update(delta)
	if is_instance_valid(objectives) and not objective_complete:
		objectives.tick(delta)
	for index in range(enemy_corpses.size()-1,-1,-1):
		enemy_corpses[index].remaining -= delta
		if float(enemy_corpses[index].remaining) <= 0:
			enemy_corpses.remove_at(index)
	progress_retry_timer = maxf(0.0, progress_retry_timer - delta)
	if release_gate and not input_blocked:
		if _all_inputs_released():
			release_gate = false
	elif controls_enabled() and Input.is_action_just_pressed("interact"):
		interact()
		if get_tree().paused or input_blocked:
			return
	if not expedition_context.is_empty():
		_tick_expedition(delta)
	elif spawn_enabled and not objective_complete:
		if encounter_zones.is_empty():
			spawn_timer -= delta
			if spawn_timer <= 0.0 and wave < objective_wave_count - 1:
				spawn_timer += Balance.ENEMY_SPAWN_INTERVAL
				_spawn_wave()
		else:
			_update_encounters(delta)
		var all_encounters: bool = wave >= objective_wave_count - 1 if encounter_zones.is_empty() else _encounters_exhausted()
		if all_encounters and _living_enemy_count() == 0:
			objective_complete = true
			objective_rewarded = Game.grant_hero_xp(30, Game.run.id + ":room:" + layout_id)
			progress_retry_timer = 1.0
			room_completed.emit()
	if expedition_context.is_empty() and objective_complete and not objective_rewarded and progress_retry_timer <= 0.0:
		var reward_key: String = Game.run.id + ":room:" + layout_id
		objective_rewarded = Game.run.completed_reward_ids.has(reward_key) or Game.grant_hero_xp(30, reward_key)
		progress_retry_timer = 1.0
	if player.dash_remaining <= 0.0 and not player.abilities.busy() and player.knockback.length_squared() < 1.0:
		tutorial_distance += minf(player.position.distance_to(_previous_player_position), player.stat("move_speed", 220.0) * delta * 1.2)
	_previous_player_position = player.position
	if progress_retry_timer <= 0.0 and tutorial_distance >= 100.0 and int(telemetry.kills) > 0 and not Game.profile.get("tutorial_completed", []).has(Game.run.hero_id):
		Game.complete_hero_tutorial()
		progress_retry_timer = 1.0
	_update_gold(delta)
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["remaining"] -= delta
		if effects[i]["remaining"] <= 0.0:
			effects.remove_at(i)
	var next_hint := interaction_hint()
	if next_hint != current_hint:
		current_hint = next_hint
		hint_changed.emit(current_hint, {})
	queue_redraw()

func clamp_actor(at: Vector2, radius: float) -> Vector2:
	return Vector2(clampf(at.x, ARENA.position.x + radius, ARENA.end.x - radius), clampf(at.y, ARENA.position.y + radius, ARENA.end.y - radius))

func spawn_enemy(at: Vector2, id: String = "", level: int = 1, options: Dictionary = {}) -> MineEnemy:
	if _living_enemy_count() >= Balance.MAX_ENEMIES:
		return null
	var resolved: Dictionary = {}
	if not id.is_empty():
		resolved = options.get("profile", EnemyProfilesScript.resolve(id, level, str(options.get("rank","normal")))).duplicate(true)
		if resolved.is_empty():
			return null
	elif options.has("profile"):
		resolved = options.profile.duplicate(true)
	var zone: int = int(options.get("zone_index", resolved.get("zone_index", -1)))
	if zone >= 0 and _zone_actor_count(zone) >= 6:
		return null
	var enemy: MineEnemy = EnemyScene.instantiate()
	enemy.room = self
	enemy.configure(resolved, options)
	var radius: float = enemy.navigation_radius
	enemy.position = clamp_actor(at, radius)
	if not valid_ground(enemy.position, radius):
		for step in range(1, 40):
			var found: bool = false
			for side in range(12):
				var candidate: Vector2 = at + Vector2.RIGHT.rotated(side * TAU / 12.0) * step * 12.0
				if valid_ground(candidate, radius):
					enemy.position = candidate
					found = true
					break
			if found:
				break
	if not valid_ground(enemy.position, radius):
		enemy.free()
		return null
	enemies.add_child(enemy)
	enemy.z_index = 2
	return enemy

func _zone_actor_count(zone: int) -> int:
	var count: int = 0
	for actor in enemies.get_children():
		if actor.actor_kind != "objective" and actor.is_alive() and actor.zone_index == zone and not actor.is_queued_for_deletion():
			count += 1
	return count

func _zone_threat(zone: int) -> float:
	var value: float = 0.0
	for actor in enemies.get_children():
		if actor.actor_kind != "objective" and actor.is_alive() and actor.zone_index == zone and not actor.is_queued_for_deletion():
			value += actor.threat_cost
	return value

func spawn_enemy_summon(caster: Node2D, id: String, at: Vector2) -> MineEnemy:
	if not is_instance_valid(caster) or not caster.is_alive():
		return null
	var children: int = 0
	for actor in enemies.get_children():
		if actor.owner_enemy != null and actor.owner_enemy.get_ref() == caster and actor.actor_kind == "enemy" and actor.is_alive() and not actor.is_queued_for_deletion():
			children += 1
	if children >= 2:
		return null
	var resolved: Dictionary = EnemyProfilesScript.resolve(id, caster.enemy_level)
	if resolved.is_empty():
		return null
	var budget: float = float(caster.profile.get("encounter_budget",18.0))
	if not _can_allocate_enemy_child(caster,float(resolved.effective_threat_cost),budget,true):
		return null
	return spawn_enemy(at,id,caster.enemy_level,{"owner":caster,"reward_enabled":false,"zone_index":caster.zone_index,"profile":resolved})

func spawn_enemy_skill_anchor(caster: Node2D, at: Vector2, health_amount: float, anchor_kind: String = "") -> MineEnemy:
	if not is_instance_valid(caster) or not caster.is_alive() or not valid_ground(at,10.0):
		return null
	if not _can_allocate_enemy_child(caster,1.0,float(caster.profile.get("encounter_budget",18.0)),anchor_kind == "summon_pod"):
		return null
	var anchor_profile: Dictionary = {"max_hp":maxf(1.0,health_amount),"navigation_radius":10.0,"effective_threat_cost":1.0}
	var anchor: MineEnemy = spawn_enemy(at,"",1,{"profile":anchor_profile,"owner":caster,"reward_enabled":false,"zone_index":caster.zone_index,"actor_kind":"hazard_endpoint","static_actor":true})
	if is_instance_valid(anchor):
		anchor.set_meta("enemy_skill_anchor_kind",anchor_kind)
	return anchor

func _can_allocate_enemy_child(caster: Node2D, threat: float, budget: float, use_reservation: bool) -> bool:
	var commitment: Dictionary = _zone_commitments(caster.zone_index)
	var reserved_count: int = int(caster.profile.get("reserved_summon_count",0))
	var used: int = 0
	for actor in enemies.get_children():
		if actor.is_alive() and not actor.is_queued_for_deletion() and actor.owner_enemy != null and actor.owner_enemy.get_ref() == caster:
			if actor.actor_kind == "enemy" or str(actor.get_meta("enemy_skill_anchor_kind","")) == "summon_pod":
				used += 1
	var consume_slot: int = 1 if use_reservation and reserved_count > used else 0
	var reserved_threat: float = float(caster.profile.get("reserved_summon_threat",0.0))/maxi(1,reserved_count) if consume_slot > 0 else 0.0
	return int(commitment.slots)+1-consume_slot <= 6 and _room_committed_slots()+1-consume_slot <= 18 and float(commitment.threat)+threat-reserved_threat <= budget+.00001

func enemy_skill_targets() -> Array:
	var result: Array = []
	if is_instance_valid(player) and Game.run != null:
		result.append(player)
	for deployment in get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.room == self and deployment.kind == "node" and deployment.is_alive():
			result.append(deployment)
	return result

func apply_enemy_utility(caster: Node2D, skill: Dictionary) -> Dictionary:
	if not is_instance_valid(enemy_props):
		return {"success":false,"reason":"unavailable"}
	return enemy_props.utility(caster,str(skill.get("action","")),skill)

func consume_enemy_corpse(caster: Node2D, radius: float) -> bool:
	for index in enemy_corpses.size():
		var corpse: Dictionary = enemy_corpses[index]
		if int(corpse.zone) == caster.zone_index and caster.position.distance_to(corpse.at) <= radius and has_line_of_sight(caster.position,corpse.at):
			enemy_corpses.remove_at(index)
			return true
	return false

func draw_enemy_telegraph(canvas: Node2D, data: Dictionary) -> void:
	if data.is_empty():
		return
	var origin: Vector2 = canvas.to_local(data.get("origin",canvas.position))
	var target: Vector2 = canvas.to_local(data.get("target",canvas.position))
	var direction: Vector2 = data.get("direction",Vector2.RIGHT)
	var radius: float = float(data.get("radius",48.0))
	var reach: float = float(data.get("range",96.0))
	var tint := Color("ffbf69") if bool(data.get("locked",false)) else Color("ef7b67")
	var fill := Color(tint,.12)
	var shape: String = str(data.get("shape","cone"))
	var targets: Array = data.get("targets",[])
	if not targets.is_empty():
		for point: Vector2 in targets:
			if shape == "ring":
				_draw_warning_ring(canvas,canvas.to_local(point),radius,data,direction,tint)
			else:
				canvas.draw_circle(canvas.to_local(point),radius,fill)
				canvas.draw_arc(canvas.to_local(point),radius,0,TAU,40,tint,1.7,true)
	if shape in ["circle","ring"] and targets.is_empty():
		var center: Vector2 = target if str(data.get("kind","")) in ["ground_area","charge"] or str(data.get("action","")) == "steal_scene_lamp" else origin
		if shape == "circle":
			canvas.draw_circle(center,radius,fill)
			canvas.draw_arc(center,radius,0,TAU,48,tint,2.0,true)
		else:
			_draw_warning_ring(canvas,center,radius,data,direction,tint)
	elif shape in ["cone","arc","sector"]:
		var angle: float = float(data.get("angle",1.5))
		var fan := PackedVector2Array([origin])
		for step in range(25):
			fan.append(origin+direction.rotated(-angle*.5+angle*step/24.0)*reach)
		fan.append(origin)
		canvas.draw_colored_polygon(fan,fill)
		canvas.draw_polyline(fan,tint,1.5,true)
	var points: Array = data.get("points",[])
	var angles: Array = data.get("projectile_angles",[])
	var explicit_paths: Array = data.get("paths",[])
	if not explicit_paths.is_empty():
		for points_in_path: Array in explicit_paths:
			var path := PackedVector2Array()
			for point: Vector2 in points_in_path:
				path.append(canvas.to_local(point))
			if path.size() >= 2:
				canvas.draw_polyline(path,Color(tint,.18),maxf(3.0,float(data.get("width",12.0))),true)
				canvas.draw_polyline(path,tint,1.5,true)
	elif points.size() >= 2:
		var rotations: Array = angles if not angles.is_empty() else [0.0]
		var world_origin: Vector2 = data.get("origin",canvas.position)
		for angle_degrees in rotations:
			var path := PackedVector2Array()
			for point: Vector2 in points:
				path.append(canvas.to_local(world_origin+(point-world_origin).rotated(deg_to_rad(float(angle_degrees)))))
			canvas.draw_polyline(path,Color(tint,.18),maxf(3.0,float(data.get("width",12.0))),true)
			canvas.draw_polyline(path,tint,1.5,true)
	elif shape == "line":
		canvas.draw_line(origin,target,Color(tint,.18),maxf(3,float(data.get("width",12.0))),true)
		canvas.draw_line(origin,target,tint,1.5,true)
	if explicit_paths.is_empty() and points.size() < 2:
		for angle_degrees in angles:
			var dir: Vector2 = direction.rotated(deg_to_rad(float(angle_degrees)))
			canvas.draw_line(origin,origin+dir*reach,tint,1.2,true)
	if str(data.get("landing_shape","")) in ["circle","ring"]:
		if str(data.landing_shape) == "ring":
			_draw_warning_ring(canvas,target,radius,data,direction,tint)
		else:
			canvas.draw_arc(target,radius,0,TAU,40,tint,2.0,true)
	elif str(data.get("landing_shape","")) == "cone":
		var landing_angle: float = float(data.get("angle",1.8))
		var fan := PackedVector2Array([target])
		for index in range(25):
			fan.append(target+direction.rotated(-landing_angle*.5+landing_angle*index/24.0)*reach)
		fan.append(target)
		canvas.draw_colored_polygon(fan,fill)
		canvas.draw_polyline(fan,tint,1.5,true)
	var combo: Array = data.get("combo_directions",[])
	if combo.size() > 1:
		for index in combo.size():
			var dir: Vector2 = combo[index]
			var end: Vector2 = origin+dir*reach
			canvas.draw_line(origin,end,Color(tint,.35),1.0,true)
			canvas.draw_circle(end,9.0,Color("1b2529"))
			if fx_font != null:
				canvas.draw_string(fx_font,end+Vector2(-4,4),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,tint)
	canvas.draw_arc(origin,12.0,-PI*.5,-PI*.5+TAU*float(data.get("progress",0)),24,tint,2.0,true)

func _draw_warning_ring(canvas: Node2D, center: Vector2, radius: float, data: Dictionary, direction: Vector2, tint: Color) -> void:
	var inner: float = maxf(0,float(data.get("inner_radius",radius*.48)))
	var gap: float = deg_to_rad(clampf(float(data.get("ring_gap_degrees",0)),0,180))
	var start: float = float(data.get("ring_start",direction.angle()+gap*.5 if gap > 0 else 0.0))
	var finish: float = float(data.get("ring_end",start+TAU-gap))
	canvas.draw_arc(center,radius,start,finish,48,tint,2,true)
	if inner > 0:
		canvas.draw_arc(center,inner,start,finish,40,tint,1.4,true)
	for index in range(40):
		var a := Vector2.from_angle(lerpf(start,finish,index/40.0))
		var b := Vector2.from_angle(lerpf(start,finish,(index+1)/40.0))
		var polygon := PackedVector2Array([center+a*inner,center+a*radius,center+b*radius,center+b*inner])
		if inner <= .001:
			polygon = PackedVector2Array([center,center+a*radius,center+b*radius])
		canvas.draw_colored_polygon(polygon,Color(tint,.11))
	if gap > 0:
		for angle in [start,finish]:
			var ray := Vector2.from_angle(angle)
			canvas.draw_line(center+ray*inner,center+ray*radius,tint,2,true)
		canvas.draw_line(center+direction*(inner+8),center+direction*(radius-8),Color("9be1c6"),1.3,true)

func _spawn_wave() -> void:
	wave += 1
	var entrances := [Vector2(1150,190),Vector2(1145,510),Vector2(760,540),Vector2(680,145)]
	for i in range(mini(Balance.WAVE_BASE_COUNT + wave / Balance.WAVE_GROWTH_EVERY, Balance.WAVE_MAX_COUNT)):
		var at: Vector2 = entrances[(wave + i) % entrances.size()] + Vector2(i * 30,0)
		if at.distance_to(player.position) < Balance.ENEMY_SPAWN_SAFE_DISTANCE:
			at = Vector2(1150,360) if player.position.x < 650 else Vector2(400,500)
		spawn_enemy(at)

func record_attack() -> void:
	record_player_sound()
	Game.run.shots += 1
	telemetry["shots"] += 1
	attack_serial += 1

func record_player_sound() -> void:
	if is_instance_valid(player):
		last_player_sound_position = player.position
		last_player_sound_time = elapsed

func enemy_utility_target(caster: Node2D, action: String) -> Vector2:
	if action == "last_player_sound":
		return last_player_sound_position if elapsed-last_player_sound_time <= 1.2 else player.position
	if is_instance_valid(enemy_props):
		var selected: Dictionary = enemy_props.target_for(caster,action)
		if bool(selected.get("valid",false)):
			return selected.position
	return player.position

func fire_from_player(direction: Vector2, critical: bool = false) -> bool:
	if Game.run == null or projectiles.get_child_count() >= Balance.MAX_PROJECTILES:
		return false
	if player.hero_id() == "CH01":
		return player.fire(direction)
	record_attack()
	var projectile := spawn_projectile(player.position, direction, player.attack_power() * (1.5 if critical else 1.0), &"primary")
	projectile.speed = 950.0 if player.hero_id() == "CH02" else 720.0
	projectile.distance_left = player.stat("range", 650.0 if player.hero_id() == "CH02" else 480.0)
	projectile.remaining = projectile.distance_left / projectile.speed + 0.1
	projectile.attack_id = attack_serial
	projectile.critical = critical
	projectile.options["power"] = player.attack_power()
	projectile.arc_ready = Game.run.relics.has("arc") and Game.run.shots % 3 == 0
	return true

func spawn_projectile(at: Vector2, direction: Vector2, damage: float, source: StringName, ignore_id: int = 0) -> SparkProjectile:
	if projectiles.get_child_count() >= Balance.MAX_PROJECTILES:
		return null
	var projectile: SparkProjectile = ProjectileScene.instantiate()
	projectile.room = self
	projectile.position = at
	projectile.direction = direction.normalized()
	projectile.damage = damage
	projectile.source = source
	if source == &"primary":
		attack_serial += 1
		projectile.attack_id = attack_serial
	projectile.ignored_enemy = ignore_id
	projectiles.add_child(projectile)
	return projectile

func resolve_weapon_hit(projectile: SparkProjectile, target: MineEnemy) -> void:
	if Game.run == null or not target.is_alive():
		return
	# Only weapon projectiles enter this function. Burn / arc call health directly.
	if projectile.source not in [&"primary", &"child"]:
		return
	var hit_position := target.position
	var is_primary := projectile.source == &"primary"
	telemetry["primary_hits" if is_primary else "child_hits"] += 1
	if is_primary:
		var context: Dictionary = {"attack_id":"basic:" + str(projectile.attack_id),"root_event_id":"basic:" + str(projectile.attack_id),"original_basic":true,"equipment_eligible":true}
		var reserved: Dictionary = _prepare_relics(context, projectile.trigger_budget, projectile.arc_ready)
		context["native_statuses"] = ["burn"] if bool(reserved.get("burn", false)) else []
		resolve_direct_hit(target, projectile.damage, projectile.source, "", 0.0, projectile.direction, context)
		player.on_primary_hit(target)
		player.hit_feedback(0.03)
		_emit_reserved_relics(reserved, context, hit_position, target, projectile.direction)
	else:
		target.take_damage(projectile.damage, projectile.source, projectile.direction)
	add_ring(projectile.position, Color("f0c77f"), 16.0, 0.15)

func _trigger_arc(origin: Vector2, excluded: MineEnemy, coefficient: float = Balance.ARC_RATIO) -> void:
	var candidates: Array[MineEnemy] = []
	for candidate in enemies.get_children():
		if candidate != excluded and candidate.is_alive() and candidate.position.distance_to(origin) <= Balance.ARC_RANGE and has_line_of_sight(origin, candidate.position):
			candidates.append(candidate)
	candidates.sort_custom(func(a: MineEnemy, b: MineEnemy) -> bool: return a.position.distance_squared_to(origin) < b.position.distance_squared_to(origin))
	for i in range(mini(candidates.size(), Balance.ARC_TARGETS)):
		var target := candidates[i]
		_add_effect({"kind":&"arc","from":origin,"to":target.position,"remaining":0.24,"duration":0.24})
		target.take_damage(player.attack_power() * coefficient, &"arc")
		telemetry["arc_hits"] += 1

func enemy_died(enemy: MineEnemy) -> void:
	if is_instance_valid(enemy_props):
		enemy_props.return_stolen(enemy)
	if is_instance_valid(enemy_skills):
		enemy_skills.cancel_owner(enemy)
	for child in enemies.get_children():
		if child.owner_enemy != null and child.owner_enemy.get_ref() == enemy:
			child.queue_free()
	if Game.run == null:
		return
	if not enemy.reward_enabled:
		return
	enemy_corpses.append({"at":enemy.position,"remaining":18.0,"zone":enemy.zone_index})
	if enemy_corpses.size() > 48:
		enemy_corpses.pop_front()
	telemetry["kills"] += 1
	Game.record_kill()
	var context: Dictionary = enemy.last_damage_context.duplicate()
	context["target"] = enemy
	if not context.has("attack_id"):
		context["attack_id"] = "death:" + str(enemy.get_instance_id())
		context["root_event_id"] = context.attack_id
	player.loadout.event("kill", context)
	var amount: int = Balance.GOLD_PER_ENEMY
	if not expedition_context.is_empty():
		amount = mini(2,maxi(0,36-_node_loot_spawned))
		_node_loot_spawned += amount
	if amount > 0: gold_drops.append({"at":enemy.position,"amount":amount,"age":0.0})
	add_ring(enemy.position, Color("e6aa4a"), 35.0, 0.35)

func _update_gold(delta: float) -> void:
	for i in range(gold_drops.size() - 1, -1, -1):
		var drop: Dictionary = gold_drops[i]
		drop["age"] += delta
		var offset: Vector2 = player.position - drop["at"]
		if offset.length() <= Balance.GOLD_PICKUP_RADIUS:
			if Game.add_gold(drop["amount"]):
				if is_instance_valid(combat_audio):
					combat_audio.pickup()
				telemetry["gold_collected"] += drop["amount"]
				add_ring(drop["at"], Color("e6aa4a"), 21.0, 0.2)
				gold_drops.remove_at(i)
		elif offset.length() <= Balance.GOLD_ATTRACT_RADIUS:
			drop["at"] = drop["at"].move_toward(player.position, Balance.GOLD_ATTRACT_SPEED * delta)

func nearby_interaction() -> Dictionary:
	if Game.run == null or player == null:
		return {}
	if is_instance_valid(objectives):
		var task: Dictionary = objectives.nearby_interaction(player.position)
		if not task.is_empty():
			return task
	if not expedition_context.is_empty():
		var role: String = str(expedition_context.get("role", ""))
		var service_at: Vector2 = layout.get("service_position", Vector2(1260,900))
		if role in ["entrance", "supply"] and player.position.distance_to(service_at) < 100:
			return {"kind":"relic_choice" if role == "entrance" else "supply", "position":service_at, "label":"选择遗物" if role == "entrance" else "途中补给"}
		if (objective_rewarded or role in ["entrance", "supply"]) and player.position.distance_to(exit_position) <= Balance.INTERACTION_RADIUS and has_line_of_sight(player.position,exit_position):
			var kind: String = "extract" if role == "boss" else ("early_extract" if bool(expedition_context.get("early_extraction",false)) else "next")
			return {"kind":kind,"position":exit_position,"label":"完成远征 · 撤离" if role == "boss" else "前往下一站"}
		if is_instance_valid(enemy_props):
			var supply: Dictionary = enemy_props.nearest_interaction(player.position)
			if not supply.is_empty() and bool(supply.get("available",false)): return supply
		return {}
	if player.position.distance_to(exit_position) <= Balance.INTERACTION_RADIUS and has_line_of_sight(player.position, exit_position):
		return {"kind":"extract"}
	for id in relic_positions:
		if not Game.run.relics.has(id) and player.position.distance_to(relic_positions[id]) <= Balance.INTERACTION_RADIUS and has_line_of_sight(player.position, relic_positions[id]):
			return {"kind":"relic","id":id}
	if is_instance_valid(enemy_props):
		var prop: Dictionary = enemy_props.nearest_interaction(player.position)
		if not prop.is_empty() and bool(prop.get("available",false)):
			return prop
	return {}

func interaction_hint() -> String:
	var nearby := nearby_interaction()
	if nearby.is_empty():
		return ""
	if nearby.kind in ["objective","next","early_extract","relic_choice","supply"]:
		return "[E] " + str(nearby.get("label","继续远征"))
	if nearby["kind"] == "extract":
		return tr("INTERACT_EXTRACT")
	if nearby.kind == "buff":
		return "[E] " + str(nearby.get("name_en" if Words.locale == "en" else "name",""))
	var id: String = nearby["id"]
	return tr("INTERACT_RELIC").format({"name":tr("RELIC_" + id.to_upper() + "_NAME")})

func interact() -> void:
	if not controls_enabled():
		return
	var nearby := nearby_interaction()
	if nearby.is_empty():
		return
	if nearby.kind == "objective":
		objectives.interact(str(nearby.id),player)
	elif nearby.kind in ["next","early_extract","relic_choice","supply"]:
		set_input_blocked(true)
		interaction_requested.emit(str(nearby.kind),expedition_context.duplicate(true))
	elif nearby["kind"] == "extract":
		set_input_blocked(true)
		interaction_requested.emit("extract", {})
	elif nearby.kind == "buff":
		enemy_props.interact(str(nearby.id),player)
	else:
		var id: String = nearby["id"]
		if Game.equip_relic(id):
			if is_instance_valid(combat_audio):
				combat_audio.pickup()
			add_ring(relic_positions[id], Color("67c7d5"), 64.0, 0.65)

func _add_effect(effect: Dictionary) -> void:
	# Visuals also have a hard cap; combat state never depends on effects surviving.
	if effects.size() >= 120:
		effects.pop_front()
	effects.append(effect)

func add_ring(at: Vector2, color: Color, radius: float, duration: float) -> void:
	_add_effect({"kind":&"ring","at":at,"color":color,"radius":radius,"remaining":duration,"duration":duration})

func add_slash(at: Vector2, direction: Vector2) -> void:
	_add_effect({"kind":&"slash","at":at,"direction":direction,"remaining":0.2,"duration":0.2})

func add_damage_text(at: Vector2, amount: float, kind: StringName) -> void:
	if Game.profile.get("settings", {}).get("damage_numbers", true):
		_add_effect({"kind":&"text","at":at,"amount":amount,"source":kind,"remaining":0.6,"duration":0.6})

func _draw() -> void:
	if is_instance_valid(enemy_props):
		enemy_props.draw_floor(self)
		enemy_props.draw_obstacles(self)
	else:
		_draw_cover()
	for corpse: Dictionary in enemy_corpses:
		draw_line(corpse.at-Vector2(7,3),corpse.at+Vector2(6,4),Color("6d6150"),3.0)
		draw_line(corpse.at-Vector2(5,-3),corpse.at+Vector2(4,-5),Color("3f5353"),2.0)
	_draw_exit()
	if not expedition_context.is_empty() and str(expedition_context.get("role","")) in ["entrance","supply"]:
		var at: Vector2 = layout.get("service_position",Vector2(1260,900))
		var icon: Texture2D = interaction_textures.get("loot")
		if icon != null: draw_texture_rect(icon,Rect2(at-Vector2(34,46),Vector2(68,68)),false)
		draw_arc(at,44,0,TAU,36,Color("e0bb72"),2,true)
	for id in relic_positions:
		_draw_relic(id, relic_positions[id])
	if interaction_overlay != null:
		interaction_overlay.queue_redraw()
	for drop in gold_drops:
		var at: Vector2 = drop["at"]
		draw_circle(at, 12, Color(0.9,0.66,0.29,0.1))
		draw_colored_polygon(PackedVector2Array([at+Vector2(-5,0),at+Vector2(0,-6),at+Vector2(6,-2),at+Vector2(4,5),at+Vector2(-4,5)]),Color("e6aa4a"))
		draw_line(at+Vector2(-3,0),at+Vector2(3,-2),Color("fff0b5"),1.5)
	for effect in effects:
		var alpha: float = effect["remaining"] / effect["duration"]
		match effect["kind"]:
			&"hero_arc":
				var half: float = deg_to_rad(float(effect.degrees)) * 0.5
				var angle: float = effect.direction.angle()
				draw_arc(effect.at, effect.radius, angle-half, angle+half, 24, Color(effect.color,alpha), 4.0,true)
			&"ring":
				draw_arc(effect["at"], effect["radius"] * (1.0 - alpha * 0.65), 0, TAU, 24, Color(effect["color"],alpha), 1.5,true)
			&"arc":
				var start: Vector2 = effect["from"]
				var end: Vector2 = effect["to"]
				var tangent: Vector2 = (end - start).normalized().orthogonal()
				var points := PackedVector2Array([start,start.lerp(end,0.22)+tangent*12,start.lerp(end,0.48)-tangent*10,start.lerp(end,0.7)+tangent*9,end])
				draw_polyline(points,Color(0.4,0.78,0.84,alpha*0.3),8.0,true)
				draw_polyline(points,Color(0.8,0.97,1.0,alpha),2.0,true)
			&"slash":
				var angle: float = effect["direction"].angle()
				draw_arc(effect["at"],Balance.ENEMY_RANGE,-0.85+angle,0.85+angle,14,Color(0.95,0.5,0.43,alpha),5.0,true)
			&"text":
				var color := Color("e6aa4a") if effect["source"] == &"burn" else Color("67c7d5") if effect["source"] == &"arc" else Color("f1eadc")
				var text_at: Vector2 = effect["at"] - Vector2(0,(1.0-alpha)*24.0)
				var label := str(snappedf(effect["amount"],0.1))
				draw_string(fx_font,text_at+Vector2(1,1),label,HORIZONTAL_ALIGNMENT_CENTER,-1,16,Color(0.03,0.05,0.07,alpha))
				draw_string(fx_font,text_at,label,HORIZONTAL_ALIGNMENT_CENTER,-1,16,Color(color,alpha))
	if controls_enabled():
		var cursor := get_global_mouse_position()
		if ARENA.has_point(cursor):
			draw_circle(cursor,2.0,Color("f1eadc"))
			for axis in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				draw_line(cursor+axis*6.0,cursor+axis*12.0,Color("67c7d5"),1.5,true)

func _draw_exit() -> void:
	var at := exit_position
	var nearby := player != null and player.position.distance_to(at) <= Balance.INTERACTION_RADIUS and has_line_of_sight(player.position, at)
	draw_rect(Rect2(at-Vector2(41,58),Vector2(82,116)),Color("102026"))
	draw_rect(Rect2(at-Vector2(41,58),Vector2(82,116)),Color("8a7759"),false,2.0)
	for x in [-32,-16,0,16,32]:
		draw_line(at+Vector2(x,-52),at+Vector2(x,48),Color("2a4248"),2.0)
	draw_rect(Rect2(at-Vector2(46,63),Vector2(92,12)),Color("766344"))
	draw_rect(Rect2(at+Vector2(-46,51),Vector2(92,12)),Color("766344"))
	draw_circle(at+Vector2(0,-43),5.0,Color("80b69a"))
	draw_arc(at,56.0,0,TAU,40,Color(0.50,0.71,0.60,0.6 if nearby else 0.2),2.0,true)
	draw_polyline(PackedVector2Array([at+Vector2(-10,-3),at+Vector2(0,-13),at+Vector2(10,-3)]),Color("a6d5b7"),3.0,true)
	draw_line(at+Vector2(0,-12),at+Vector2(0,14),Color("a6d5b7"),3.0)

func _draw_relic(id: String, at: Vector2) -> void:
	var collected: bool = Game.run == null or Game.run.relics.has(id)
	var nearby: bool = player != null and player.position.distance_to(at) <= Balance.INTERACTION_RADIUS and has_line_of_sight(player.position, at)
	draw_set_transform(at)
	draw_colored_polygon(PackedVector2Array([Vector2(-27,-7),Vector2(-18,-16),Vector2(18,-16),Vector2(27,-7),Vector2(27,20),Vector2(-27,20)]),Color("1c2d35"))
	draw_polyline(PackedVector2Array([Vector2(-27,20),Vector2(-27,-7),Vector2(-18,-16),Vector2(18,-16),Vector2(27,-7),Vector2(27,20)]),Color("8b6948"),1.5,true)
	draw_line(Vector2(-21,24),Vector2(21,24),Color("a57d4c"),3.0)
	if collected:
		draw_circle(Vector2(0,3),4.0,Color("526d69"))
	else:
		var pulse := 0.75 + 0.15 * sin(elapsed * 2.0)
		draw_circle(Vector2(0,-3),34.0,Color(0.4,0.78,0.84,0.04*pulse))
		draw_circle(Vector2(0,-3),22.0,Color(0.4,0.78,0.84,0.08*pulse))
		if relic_textures.has(id):
			draw_texture_rect(relic_textures[id],Rect2(-25,-30,50,50),false)
		else:
			_draw_relic_fallback(id)
		if nearby:
			draw_arc(Vector2.ZERO,40,0,TAU,32,Color("e6aa4a"),1.5,true)
	draw_set_transform(Vector2.ZERO)

func _draw_relic_fallback(id: String) -> void:
	var color := Color("67c7d5")
	match id:
		"split":
			draw_polyline(PackedVector2Array([Vector2(-12,4),Vector2(0,-13),Vector2(12,4),Vector2(-12,4)]),color,2.0,true)
			draw_line(Vector2(0,16),Vector2(0,2),Color("f1eadc"),2.0)
			draw_line(Vector2(0,2),Vector2(-15,-10),color,2.0)
			draw_line(Vector2(0,2),Vector2(15,-10),color,2.0)
		"ember":
			draw_colored_polygon(PackedVector2Array([Vector2(-10,8),Vector2(-11,-1),Vector2(-4,-8),Vector2(-1,-18),Vector2(6,-6),Vector2(11,0),Vector2(9,8),Vector2(0,12)]),Color("e6aa4a"))
			draw_colored_polygon(PackedVector2Array([Vector2(-4,8),Vector2(0,-5),Vector2(5,8)]),Color("f8dfa0"))
		"arc":
			draw_arc(Vector2.ZERO,15,-0.5,PI+0.5,24,color,2.0,true)
			draw_polyline(PackedVector2Array([Vector2(4,-13),Vector2(-6,1),Vector2(4,1),Vector2(-4,15)]),Color("d6fbff"),3.0,true)

func _all_inputs_released() -> bool:
	for action: String in ["attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return false
	return true

func _living_enemy_count() -> int:
	var count: int = 0
	for enemy in enemies.get_children():
		if enemy.actor_kind != "objective" and enemy.is_alive() and not enemy.is_queued_for_deletion():
			count += 1
	return count

func valid_ground(at: Vector2, radius: float = 0.0) -> bool:
	if at != clamp_actor(at, radius):
		return false
	for wall: Rect2 in obstructions:
		var nearest := Vector2(clampf(at.x, wall.position.x, wall.end.x), clampf(at.y, wall.position.y, wall.end.y))
		if wall.has_point(at) or nearest.distance_squared_to(at) < radius * radius:
			return false
	return true

func move_actor(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var result: Vector2 = clamp_actor(from, radius)
	var steps: int = maxi(1, int(ceil(displacement.length() / 4.0)))
	var part: Vector2 = displacement / float(steps)
	for i in range(steps):
		var next: Vector2 = clamp_actor(result + part, radius)
		if valid_ground(next, radius):
			result = next
		else:
			var horizontal := Vector2(next.x, result.y)
			var vertical := Vector2(result.x, next.y)
			if valid_ground(horizontal, radius):
				result = horizontal
			if valid_ground(Vector2(result.x, vertical.y), radius):
				result.y = vertical.y
	return result

func blocked_fraction(from: Vector2, to: Vector2, radius: float = 0.0) -> float:
	var result: float = 1.0
	var offset: Vector2 = to - from
	var allowed: Rect2 = ARENA.grow(-radius)
	if offset.x > 0.0: result = minf(result, (allowed.end.x - from.x) / offset.x)
	elif offset.x < 0.0: result = minf(result, (allowed.position.x - from.x) / offset.x)
	if offset.y > 0.0: result = minf(result, (allowed.end.y - from.y) / offset.y)
	elif offset.y < 0.0: result = minf(result, (allowed.position.y - from.y) / offset.y)
	for wall: Rect2 in obstructions:
		var box: Rect2 = wall.grow(radius)
		var start: float = 0.0
		var finish: float = 1.0
		var intersects: bool = true
		for axis in range(2):
			if absf(offset[axis]) < 0.00001:
				if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
					intersects = false
					break
			else:
				var near: float = (box.position[axis] - from[axis]) / offset[axis]
				var far: float = (box.end[axis] - from[axis]) / offset[axis]
				start = maxf(start, minf(near, far))
				finish = minf(finish, maxf(near, far))
				if start > finish:
					intersects = false
					break
		if intersects and finish >= 0.0 and start <= 1.0:
			result = minf(result, maxf(0.0, start - 0.0001))
	return clampf(result, 0.0, 1.0)

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	return blocked_fraction(from, to) >= 1.0

func navigation_direction(from: Vector2, to: Vector2, radius: float) -> Vector2:
	return _navigation_cache.direction(from, to, radius, obstructions, ARENA)

func targets_in_radius(at: Vector2, radius: float) -> Array:
	var targets: Array = []
	for enemy in enemies.get_children():
		if enemy.is_alive() and at.distance_to(enemy.position) <= radius and has_line_of_sight(at, enemy.position):
			targets.append(enemy)
	targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var a_distance: float = at.distance_squared_to(a.position)
		var b_distance: float = at.distance_squared_to(b.position)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(a_distance, b_distance) else a_distance < b_distance)
	return targets

func strike_area(at: Vector2, radius: float, amount: float, source: StringName, applied_status: String = "", push: float = 0.0, direction: Vector2 = Vector2.ZERO, arc_degrees: float = 360.0, original: bool = true, context: Dictionary = {}) -> Array:
	var hit: Array = []
	if context.is_empty():
		context = {"attack_id":("basic:" if source == &"primary" else "area:") + str(attack_serial),"root_event_id":("basic:" if source == &"primary" else "area:") + str(attack_serial)}
		if source != &"primary":
			attack_serial += 1
	var reserved: Dictionary = {}
	if source == &"primary":
		reserved = _prepare_relics(context, Balance.TRIGGER_BUDGET, Game.run.shots % 3 == 0)
		context["native_statuses"] = ["burn"] if bool(reserved.get("burn", false)) else []
	var candidates: Array = targets_in_radius(at, radius)
	if source == &"primary":
		candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			var a_offset: Vector2 = a.position - at
			var b_offset: Vector2 = b.position - at
			var a_aim: float = absf(a_offset.cross(direction))
			var b_aim: float = absf(b_offset.cross(direction))
			return a_offset.length_squared() < b_offset.length_squared() if is_equal_approx(a_aim, b_aim) else a_aim < b_aim)
	for enemy in candidates:
		var offset: Vector2 = enemy.position - at
		if arc_degrees < 360.0 and not offset.is_zero_approx() and direction.dot(offset.normalized()) < cos(deg_to_rad(arc_degrees) * 0.5):
			continue
		if original:
			var target_context: Dictionary = context.duplicate()
			if source == &"primary" and hit.size() >= 3:
				target_context["native_statuses"] = []
			target_context["original_basic"] = source == &"primary"
			target_context["equipment_eligible"] = true
			resolve_direct_hit(enemy, amount, source, applied_status, push, offset.normalized(), target_context)
		else:
			enemy.take_damage(amount, source)
			if not applied_status.is_empty():
				enemy.apply_status(applied_status, player.attack_power())
		hit.append(enemy)
		if (source == &"field" or (source == &"ultimate" and player.hero_id() == "CH03")) and hit.size() >= 12:
			break
	if not hit.is_empty():
		player.hit_feedback(0.065 if source == &"ultimate" else 0.055 if source == &"secondary" else 0.03)
		if source == &"primary":
			_emit_reserved_relics(reserved, context, hit[0].position, hit[0], direction)
	return hit

func resolve_direct_hit(target: MineEnemy, amount: float, source: StringName, applied_status: String = "", push: float = 0.0, direction: Vector2 = Vector2.ZERO, attack_context: Dictionary = {}) -> void:
	if Game.run == null or not target.is_alive():
		return
	var context: Dictionary = attack_context.duplicate()
	context.merge({"target":target,"target_states":target.status.states.keys(),"X":amount,"H":float(context.get("power", player.attack_power())),"damage_source":"primary" if source == &"primary" else "skill","skill_slot":str(source),"proc_depth":0}, true)
	if not context.has("attack_id"):
		attack_serial += 1
		context["attack_id"] = "direct:" + str(attack_serial)
		context["root_event_id"] = context.attack_id
	context["original_basic"] = bool(context.get("original_basic", source == &"primary"))
	context["equipment_eligible"] = bool(context.get("equipment_eligible", true))
	var native_statuses: Array = context.get("native_statuses", []).duplicate()
	if not applied_status.is_empty() and player.loadout.effects.reserve_native(str(context.root_event_id), "native:" + applied_status):
		native_statuses.append(applied_status)
	var modifiers: Dictionary = player.loadout.event("before_hit", context)
	var root_id: String = str(context.root_event_id)
	if source == &"primary" and not crit_rolls.has(root_id):
		crit_rolls[root_id] = randf() < clampf(player.stat("crit_chance", 0.05) + float(modifiers.get("crit_bonus", 0.0)), 0.0, 0.45)
		if crit_rolls.size() > 256:
			crit_rolls.erase(crit_rolls.keys()[0])
	context["critical"] = source == &"primary" and bool(crit_rolls.get(root_id, false))
	var shock: float = target.status.consume_shock()
	var bonus: float = player.stat("damage_bonus", 0.0)
	bonus += float(modifiers.get("damage_bonus", 0.0))
	if target.status.has("corrosion"):
		bonus += 0.08 + player.stat("corrosion_damage_bonus", 0.0)
	var final_amount: float = amount * (1.0 + minf(0.6, bonus)) * (player.stat("crit_multiplier", 1.5) if bool(context.critical) else 1.0)
	var health_before: float = target.health.current
	var shield_before: float = target.status.shield()
	target.take_damage(final_amount, source, direction, context)
	if target.health.current < health_before or target.status.shield() < shield_before:
		var feedback: Node = player.get_node_or_null("HeroFeedback")
		if is_instance_valid(feedback):
			feedback.impact(target.position, direction, str(source), bool(context.critical))
	if is_instance_valid(combat_audio) and (target.health.current < health_before or target.status.shield() < shield_before):
		combat_audio.impact(player.hero_id(),bool(context.critical) or str(source).contains("ultimate") or str(source).contains("secondary"))
	if target.is_alive() and shock > 0.0:
		target.take_damage(shock, &"shock")
		add_ring(target.position, Color("81d8e0"), 25.0, 0.2)
	for status_id: String in native_statuses:
		var status_power: float = float(context.H)
		if status_id == "burn" and source == &"primary" and Game.run.relics.has("ember"):
			status_power *= _relic_rank_multiplier("RL02")
		if target.is_alive() and target.apply_status(status_id, status_power):
			var status_context: Dictionary = context.duplicate()
			status_context["applied_states"] = [status_id]
			player.loadout.event("status_applied", status_context)
	if target.is_alive() and push > 0.0:
		target.apply_knockback(direction, push * float(modifiers.get("knockback_scale", 1.0)))
	player.loadout.event("after_hit", context)
	player.combat_time = 5.0

func resolve_melee_relics(target: MineEnemy, direction: Vector2) -> void:
	# Native relics were reserved and dispatched inside the shared attack root.
	telemetry.primary_hits += 1

func _prepare_relics(context: Dictionary, budget: int, arc_ready: bool) -> Dictionary:
	var reserved: Dictionary = {}
	if Game.run == null or budget <= 0:
		return reserved
	var root: String = str(context.root_event_id)
	if Game.run.relics.has("ember") and player.loadout.effects.reserve_native(root, "relic:ember"):
		reserved["burn"] = true
		budget -= 1
	if budget > 0 and Game.run.relics.has("split"):
		if player.loadout.effects.reserve_native(root, "relic:split"):
			reserved["split"] = Balance.SPLIT_RATIO * _relic_rank_multiplier("RL01")
			budget -= 1
	if budget > 0 and arc_ready and Game.run.relics.has("arc"):
		# The plan caps equipment-derived coefficients; native relics share packet
		# count but retain their own published .4 / .35 coefficients.
		if player.loadout.effects.reserve_native(root, "relic:arc"):
			reserved["arc"] = Balance.ARC_RATIO * _relic_rank_multiplier("RL03")
	return reserved

func _relic_rank_multiplier(id: String) -> float:
	var rank: int = clampi(int(Game.run.stats.get("relic_levels",{}).get(id,1)),1,2)
	return 1.0 + 0.5 * float(rank-1)

func _emit_reserved_relics(reserved: Dictionary, context: Dictionary, at: Vector2, target: MineEnemy, direction: Vector2) -> void:
	if reserved.has("split"):
		for side: float in [-1.0, 1.0]:
			var child := spawn_projectile(at, direction.rotated(side * Balance.SPLIT_ANGLE), player.attack_power() * float(reserved.split), &"child", target.get_instance_id())
			if child != null:
				child.trigger_budget = 0
				child.options["root_event_id"] = context.root_event_id
				telemetry.split_spawned += 1
	if reserved.has("arc"):
		_trigger_arc(at, target, float(reserved.arc))

func spawn_ability_projectile(at: Vector2, direction: Vector2, amount: float, options: Dictionary) -> SparkProjectile:
	if Game.run == null:
		return null
	if str(options.get("source", "")) != "node" and not has_line_of_sight(player.position, at):
		at = player.position
	var projectile := spawn_projectile(at, direction, amount, StringName(options.get("source", "skill")))
	if projectile == null:
		return null
	projectile.options = options.duplicate()
	if not projectile.options.has("root_event_id"):
		attack_serial += 1
		projectile.options["root_event_id"] = "ability:" + str(attack_serial)
		projectile.options["attack_id"] = projectile.options.root_event_id
	projectile.speed = float(options.get("speed", 950.0))
	projectile.distance_left = float(options.get("range", 650.0))
	projectile.remaining = projectile.distance_left / projectile.speed + 0.1
	projectile.pierce_remaining = int(options.get("pierce", 0))
	return projectile

func add_deployment(kind: String, at: Vector2, options: Dictionary) -> Node2D:
	if kind in ["node", "trap"]:
		var existing: Array = []
		for deployment in get_tree().get_nodes_in_group("hero_deployments"):
			if deployment.room == self and deployment.kind == kind and deployment.is_alive():
				existing.append(deployment)
		if existing.size() >= 2:
			existing[0].retire()
	var deployment: Node2D = DeploymentScript.new()
	deployment.position = at
	deployment.configure(self, kind, options)
	add_child(deployment)
	return deployment

func node_echo(origin: Vector2, reach: float, amount: float, _applied_status: String = "", hit_ids: Array = []) -> Array:
	for deployment in get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.room != self or deployment.kind != "node" or not deployment.is_active() or deployment.position.distance_to(origin) > reach or not has_line_of_sight(origin, deployment.position):
			continue
		add_ring(deployment.position, Color("8bd0c8"), 70.0, 0.25)
		for target in targets_in_radius(deployment.position, 70.0):
			if target.get_instance_id() in hit_ids:
				continue
			hit_ids.append(target.get_instance_id())
			target.take_damage(amount, &"node_echo")
	return hit_ids

func add_arc_visual(at: Vector2, direction: Vector2, radius: float, degrees: float, color: Color, duration: float) -> void:
	_add_effect({"kind":&"hero_arc","at":at,"direction":direction,"radius":radius,"degrees":degrees,"color":color,"remaining":duration,"duration":duration})

func add_arc_between(from: Vector2, to: Vector2) -> void:
	_add_effect({"kind":&"arc","from":from,"to":to,"remaining":0.22,"duration":0.22})

func _draw_cover() -> void:
	var kinds: Array = layout.get("obstruction_kinds", [])
	for index in obstructions.size():
		var box: Rect2 = obstructions[index]
		var kind: String = str(kinds[index]) if index < kinds.size() else "machinery"
		if camera != null:
			var view_size: Vector2 = get_viewport_rect().size / camera.zoom
			var view := Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size).grow(80.0)
			if not view.intersects(box):
				continue
		var shadow := Rect2(box.position + Vector2(8,11), box.size)
		draw_rect(shadow, Color(0.018,0.025,0.025,0.7))
		draw_rect(box, Color("172024"))
		if kind.contains("pit") or kind.contains("water") or kind.contains("void"):
			_draw_void_cover(box, kind.contains("water"))
			continue
		var body: PackedVector2Array = _beveled_outline(box.grow(-3.0), 12.0)
		draw_colored_polygon(body, Color("303937"))
		var closed: PackedVector2Array = body.duplicate()
		closed.append(body[0])
		draw_polyline(closed, Color("6c705e"), 2.0, true)
		draw_line(box.position + Vector2(17,8), Vector2(box.end.x-17,box.position.y+8), Color("8b836a"), 3.0, true)
		draw_line(Vector2(box.end.x-7,box.position.y+19), box.end-Vector2(7,19), Color("1e292b"), 5.0, true)
		var interior: Rect2 = box.grow(-17.0)
		if interior.size.x > 30.0 and interior.size.y > 30.0:
			var columns: int = maxi(1, int(ceil(interior.size.x / 125.0)))
			var rows: int = maxi(1, int(ceil(interior.size.y / 112.0)))
			var size: Vector2 = interior.size / Vector2(columns, rows)
			for column in columns:
				for row in rows:
					var panel := Rect2(interior.position + Vector2(column,row) * size + Vector2(3,3), size - Vector2(6,6))
					draw_rect(panel, Color("36403d") if (column+row+index)%2 == 0 else Color("2b3434"))
					draw_line(panel.position, Vector2(panel.end.x,panel.position.y), Color("4d5750"), 1.4, true)
					draw_line(Vector2(panel.position.x,panel.end.y), panel.end, Color("192427"), 2.0, true)
					if (column+row+index)%3 == 0:
						for vent in range(4):
							var y: float = panel.get_center().y - 12.0 + vent * 7.0
							draw_line(Vector2(panel.position.x+12,y),Vector2(panel.end.x-12,y),Color("172428"),2.0,true)
		# Embedded winch drums sit inside the collision footprint. No decorative
		# pipe or rim creates an additional invisible collision surface.
		if minf(box.size.x, box.size.y) > 110.0:
			var center: Vector2 = box.get_center()
			var radius: float = minf(51.0, minf(box.size.x, box.size.y) * .23)
			draw_circle(center + Vector2(4,5), radius+7.0, Color("1a2527"))
			draw_circle(center, radius, Color("49514a"))
			for ring in range(4):
				draw_arc(center, radius-5.0-ring*5.0, 0.0, TAU, 32, Color("7a7861") if ring%2==0 else Color("2b3839"), 2.5, true)
			for spoke in range(6):
				var axis := Vector2.RIGHT.rotated(spoke*TAU/6.0)
				draw_line(center+axis*9.0,center+axis*(radius-6.0),Color("293737"),4.0,true)
			draw_circle(center, 11.0, Color("9b8257"))
			draw_circle(center, 4.0, Color("253638"))
		for x in range(int(box.position.x)+22, int(box.end.x)-12, 68):
			for y: float in [box.position.y+12.0,box.end.y-12.0]:
				draw_circle(Vector2(x,y),3.0,Color("172528"))
				draw_circle(Vector2(x-0.6,y-0.7),1.8,Color("8f8872"))
		for corner: Vector2 in [box.position+Vector2(14,14),Vector2(box.end.x-14,box.position.y+14),box.end-Vector2(14,14),Vector2(box.position.x+14,box.end.y-14)]:
			draw_line(corner-Vector2(6,0),corner+Vector2(0,6),Color("af864e"),3.0,true)
			draw_line(corner-Vector2(1,5),corner+Vector2(5,1),Color("af864e"),2.0,true)

func _beveled_outline(box: Rect2, bevel: float) -> PackedVector2Array:
	var cut: float = minf(bevel, minf(box.size.x,box.size.y)*.2)
	return PackedVector2Array([box.position+Vector2(cut,0),Vector2(box.end.x-cut,box.position.y),Vector2(box.end.x,box.position.y+cut),box.end-Vector2(0,cut),box.end-Vector2(cut,0),Vector2(box.position.x+cut,box.end.y),Vector2(box.position.x,box.end.y-cut),box.position+Vector2(0,cut)])

func _draw_void_cover(box: Rect2, water: bool) -> void:
	draw_rect(box.grow(-6.0), Color("1e3337") if water else Color("0b151c"))
	for inset in [10.0,18.0,27.0]:
		if minf(box.size.x,box.size.y) > inset*2.0:
			draw_rect(box.grow(-inset), Color(0.12,0.2,0.22,.45), false, 1.0)
	for x in range(int(box.position.x)+18,int(box.end.x)-12,48):
		draw_line(Vector2(x,box.position.y+5),Vector2(x+12,box.position.y+5),Color("9b8256"),3.0)
		draw_line(Vector2(x,box.end.y-5),Vector2(x+12,box.end.y-5),Color("9b8256"),3.0)

func _draw_interaction_focus(canvas: Node2D) -> void:
	if Game.run == null or player == null or fx_font == null:
		return
	var selected: Dictionary = nearby_interaction()
	var english: bool = str(Game.profile.get("settings", {}).get("language", "zh_CN")) == "en"
	for id: String in relic_positions:
		var at: Vector2 = relic_positions[id]
		if Game.run.relics.has(id) and player.position.distance_to(at) < 125.0 and has_line_of_sight(player.position, at):
			_draw_world_label(canvas, at+Vector2(0,46), "Equipped" if english else "已装配", false, Color("758b80"), "interaction")
	if selected.is_empty():
		return
	if not expedition_context.is_empty() and selected.kind != "buff":
		var focus_at: Vector2 = selected.get("position",exit_position)
		_draw_world_label(canvas,focus_at-Vector2(0,72),str(selected.get("label","继续远征")),true,Color("e2bd7e"),"exit" if selected.kind in ["next","early_extract","extract"] else "interaction")
		return
	var extract: bool = selected.kind == "extract"
	var buff: bool = selected.kind == "buff"
	var at: Vector2 = selected.position if buff else (exit_position if extract else relic_positions[selected.id])
	var size := Vector2(49,65) if extract else Vector2(35,31)
	var tint := Color("afd5b9") if extract else Color("e2bd7e")
	for side: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var corner: Vector2 = at + size*side
		canvas.draw_line(corner,corner-Vector2(side.x*10,0),tint,2.0,true)
		canvas.draw_line(corner,corner-Vector2(0,side.y*10),tint,2.0,true)
	var label: String = ("Extract" if objective_complete else "Leave early") if english else ("确认撤离" if objective_complete else "提前撤离")
	if buff:
		label = str(selected.get("name_en" if english else "name",""))
	elif not extract:
		label = tr("RELIC_" + str(selected.id).to_upper() + "_NAME")
	_draw_world_label(canvas, at-Vector2(0,size.y+19), label, true, tint, "interaction" if buff else ("exit" if extract else "loot"))

func _draw_world_label(canvas: Node2D, at: Vector2, label: String, actionable: bool, tint: Color, icon_key: String = "interaction") -> void:
	var font_size: int = 16
	var width: float = fx_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon: Texture2D = interaction_textures.get(icon_key)
	var icon_space: float = 32.0 if icon != null else 0.0
	var lead: float = icon_space + (28.0 if actionable else 0.0)
	var start: Vector2 = at - Vector2((width + lead) * .5,0)
	var label_tint := Color("fff1d1") if actionable else Color("bdccc0")
	canvas.draw_rect(Rect2(start+Vector2(-6,-23),Vector2(width+lead+12.0,32)),Color(0.035,0.055,0.06,0.94))
	if icon != null:
		var source_size: Vector2 = icon.get_size()
		var image_scale: float = minf(26.0/source_size.x,26.0/source_size.y)
		var extent: Vector2 = source_size * image_scale
		var icon_at: Vector2 = start + Vector2(0,-20) + (Vector2(26,26)-extent)*0.5
		canvas.draw_texture_rect(icon,Rect2(icon_at,extent),false)
		start.x += icon_space
	if actionable:
		canvas.draw_rect(Rect2(start+Vector2(0,-15),Vector2(20,20)),Color("202e30"))
		canvas.draw_rect(Rect2(start+Vector2(0,-15),Vector2(20,20)),tint,false,1.2)
		canvas.draw_string(fx_font,start+Vector2(6,0),"E",HORIZONTAL_ALIGNMENT_LEFT,-1,13,label_tint)
		start.x += 28.0
	# A one-pixel same-color stroke keeps Chinese glyphs legible under camera
	# zoom without enlarging the compact label or introducing a standing panel.
	canvas.draw_string_outline(fx_font,start,label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,1,label_tint)
	canvas.draw_string(fx_font,start,label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,label_tint)
func load_room_layout(id: String, room_difficulty: int = -1, seed_override: int = -1) -> bool:
	if run_seed < 0:
		run_seed = (hash(Game.run.id) & 0x7fffffff) if Game.run != null else 41827
	var requested_seed: int = seed_override if seed_override >= 0 else run_seed
	var next: Dictionary = Generator.generate(id,requested_seed) if use_generated_layout else Layouts.build(id)
	if next.is_empty():
		configuration_error = "Unable to generate room " + id
		return false
	# Validate all three supplies before replacing the current room. A failed
	# candidate never exposes an empty arena or a partly configured buff set.
	var prepared_props: Node2D = PropsScript.new()
	if not prepared_props.configure(self,next):
		configuration_error = "Unable to place room supplies: " + "; ".join(prepared_props.configuration_errors)
		prepared_props.free()
		return false
	layout_seed = requested_seed
	if room_difficulty >= 0:
		difficulty = clampi(room_difficulty,0,4)
	if is_instance_valid(enemy_skills):
		enemy_skills.reset_room()
	if is_instance_valid(enemy_props):
		enemy_props.clear()
		enemy_props.free()
	enemy_props = prepared_props
	enemy_props.name = "RoomProps"
	add_child(enemy_props)
	enemy_corpses.clear()
	layout_id = id
	layout = next
	obstructions.assign(next.obstructions)
	_navigation_cache.prepare(obstructions, ARENA)
	exit_position = next.exit
	encounter_zones = next.get("encounter_zones", []).duplicate(true)
	activated_encounters.clear()
	encounter_progress.clear()
	objective_wave_count = encounter_zones.size()
	objective_complete = false
	objective_rewarded = false
	wave = 0
	var points: Array = next.get("objective_points", [])
	var ids: Array = ["split", "ember", "arc"]
	for index in mini(ids.size(), points.size()):
		relic_positions[ids[index]] = points[index]
	if is_instance_valid(player):
		for enemy in enemies.get_children():
			enemy.queue_free()
		for projectile in projectiles.get_children():
			projectile.queue_free()
		for deployment in get_tree().get_nodes_in_group("hero_deployments"):
			if deployment.room == self:
				deployment.retire()
		player.cancel_actions()
		player.position = next.entry
		player.loadout.event("room_enter", {"room_id":layout_id,"unvisited":true})
		gold_drops.clear()
		$MineBackdrop.configure(ARENA,str(WorldCatalog.room(layout_id).get("biome_id","B01")),hash(layout_id))
		if camera != null:
			camera.follow_target()
	configuration_ready = true
	configuration_error = ""
	queue_redraw()
	return true

func _encounters_exhausted() -> bool:
	if activated_encounters.size() != encounter_zones.size():
		return false
	for index in encounter_progress:
		var progress: Dictionary = encounter_progress[index]
		if int(progress.next_wave) < progress.plan.waves.size():
			return false
	return true

func _encounter_plan(index: int) -> Dictionary:
	return EnemyProfilesScript.encounter_plan(layout_id,index,difficulty)

func _zone_commitments(index: int) -> Dictionary:
	var slots: int = _zone_actor_count(index)
	var threat: float = _zone_threat(index)
	for actor in enemies.get_children():
		if actor.actor_kind == "objective" or not actor.is_alive() or actor.is_queued_for_deletion() or actor.zone_index != index:
			continue
		var reserve: int = int(actor.profile.get("reserved_summon_count",0))
		if reserve <= 0:
			continue
		var used: int = 0
		var dependent_threat: float = 0.0
		for dependent in enemies.get_children():
			if dependent.is_alive() and not dependent.is_queued_for_deletion() and dependent.owner_enemy != null and dependent.owner_enemy.get_ref() == actor:
				if dependent.actor_kind == "enemy" or str(dependent.get_meta("enemy_skill_anchor_kind","")) == "summon_pod":
					used += 1
					dependent_threat += dependent.threat_cost
		slots += maxi(0,reserve-used)
		threat += maxf(0,float(actor.profile.get("reserved_summon_threat",0.0))-dependent_threat)
	return {"slots":slots,"threat":threat}

func _can_spawn_encounter_wave(index: int, definitions: Array, budget: float) -> bool:
	var commitment: Dictionary = _zone_commitments(index)
	var slots: int = int(commitment.slots)
	var threat: float = float(commitment.threat)
	var added_slots: int = 0
	for definition: Dictionary in definitions:
		var cost: int = 1+int(definition.get("reserved_summon_count",0))
		slots += cost
		added_slots += cost
		threat += float(definition.get("encounter_budget_cost",definition.get("effective_threat_cost",1)))
	return slots <= 6 and _room_committed_slots()+added_slots <= 18 and threat <= budget

func _room_committed_slots() -> int:
	var zones: Dictionary = {}
	for actor in enemies.get_children():
		if actor.actor_kind != "objective" and actor.is_alive() and not actor.is_queued_for_deletion():
			zones[actor.zone_index] = true
	var slots: int = 0
	for zone: int in zones:
		slots += int(_zone_commitments(zone).slots)
	return slots

func _spawn_encounter_wave(index: int, definitions: Array) -> bool:
	var zone: Dictionary = encounter_zones[index]
	var spawns: Array = zone.get("spawn_points",[])
	var planned: Array[Vector2] = []
	var planned_radii: Array[float] = []
	var accepted: Array[MineEnemy] = []
	for spawn_index in definitions.size():
		var definition: Dictionary = definitions[spawn_index]
		var at: Vector2 = spawns[spawn_index%spawns.size()] if not spawns.is_empty() else zone.center
		var radius: float = float(definition.navigation_radius)
		var safe_distance: float = float(zone.get("minimum_player_spawn_distance",360.0))
		var valid: bool = _encounter_spawn_clear(at,radius,safe_distance,planned,planned_radii)
		if not valid:
			valid = false
			for ring in range(4):
				for turn in range(48):
					var candidate: Vector2 = player.position+Vector2.RIGHT.rotated(turn*TAU/48.0)*(safe_distance+ring*55.0)
					if _encounter_spawn_clear(candidate,radius,safe_distance,planned,planned_radii):
						at = candidate
						valid = true
						break
				if valid:
					break
		if not valid:
			return false
		planned.append(at)
		planned_radii.append(radius)
	for spawn_index in definitions.size():
		var definition: Dictionary = definitions[spawn_index]
		var spawned: MineEnemy = spawn_enemy(planned[spawn_index],str(definition.enemy_id),int(definition.enemy_level),{"profile":definition,"zone_index":index})
		if spawned == null:
			# Placement and budget are checked before the batch. If an invalid
			# definition still fails, keep the pending wave intact for retry.
			for actor in accepted:
				actor.queue_free()
			return false
		accepted.append(spawned)
	add_ring(zone.center,Color("d8b580"),95.0,.6)
	return true

func _encounter_spawn_clear(at: Vector2, radius: float, safe_distance: float, planned: Array[Vector2], radii: Array[float]) -> bool:
	if not valid_ground(at,radius) or at.distance_to(player.position)+.001 < safe_distance:
		return false
	for index in planned.size():
		if planned[index].distance_to(at) < radius+radii[index]+6.0:
			return false
	for actor in enemies.get_children():
		if actor.is_alive() and not actor.is_queued_for_deletion() and actor.position.distance_to(at) < radius+actor.navigation_radius+6.0:
			return false
	return true

func _update_encounters(delta: float = 0.0) -> void:
	if get_tree().paused:
		return
	for index in encounter_progress:
		var progress: Dictionary = encounter_progress[index]
		var plan: Dictionary = progress.plan
		if int(progress.next_wave) >= plan.waves.size():
			continue
		var commitment: Dictionary = _zone_commitments(index)
		var pending: Array = plan.waves[int(progress.next_wave)]
		var budget: float = float(plan.get("concurrent_threat_budget",18.0))
		var eligible: bool = _zone_actor_count(index) <= int(plan.get("reinforce_alive_threshold",2)) and float(commitment.threat) <= budget*float(plan.get("reinforce_threat_fraction",.3)) and _can_spawn_encounter_wave(index,pending,budget)
		progress.reinforce_elapsed = float(progress.reinforce_elapsed)+delta if eligible else 0.0
		if eligible and float(progress.reinforce_elapsed)+.00001 >= float(plan.get("reinforce_delay_seconds",3.0)) and _spawn_encounter_wave(index,pending):
			progress.next_wave = int(progress.next_wave)+1
			progress.reinforce_elapsed = 0.0
	# Regions activate in sequence after the prior finite plan has been exhausted.
	if _living_enemy_count() > 0:
		return
	for progress: Dictionary in encounter_progress.values():
		if int(progress.next_wave) < progress.plan.waves.size():
			return
	for index in encounter_zones.size():
		if activated_encounters.has(index):
			continue
		var zone: Dictionary = encounter_zones[index]
		if player.position.distance_to(zone.center) > float(zone.get("activation_distance",520)):
			continue
		var plan: Dictionary = _encounter_plan(index)
		if plan.is_empty() or plan.waves.is_empty() or not _can_spawn_encounter_wave(index,plan.waves[0],float(plan.get("concurrent_threat_budget",18))) or not _spawn_encounter_wave(index,plan.waves[0]):
			return
		activated_encounters[index] = true
		encounter_progress[index] = {"plan":plan,"next_wave":1,"reinforce_elapsed":0.0}
		wave = activated_encounters.size()
		break

func navigation_target() -> Dictionary:
	if player == null:
		return {}
	if not expedition_context.is_empty():
		var role: String = str(expedition_context.get("role",""))
		if role == "entrance": return {"position":exit_position,"title":"完成整备后前往第一处矿区 · M 查看路线","kind":"next"}
		if role == "supply": return {"position":layout.get("service_position",exit_position),"title":"购买补给，或前往下一站","kind":"supply"}
		if objective_rewarded: return {"position":exit_position,"title":"领取成长奖励，继续远征" if role != "boss" else "首领已击败 · 前往撤离井","kind":"next" if role != "boss" else "extract"}
		if is_instance_valid(objectives) and not objectives.is_complete():
			return objectives.navigation_target()
	if not objective_complete:
		if _living_enemy_count() > 0:
			var closest: MineEnemy = null
			for enemy in enemies.get_children():
				if enemy.actor_kind != "objective" and enemy.is_alive() and (closest == null or enemy.position.distance_squared_to(player.position) < closest.position.distance_squared_to(player.position)):
					closest = enemy
			if closest != null:
				return {"position":closest.position,"title":"清理遭遇区域","name_en":"Clear the encounter","kind":"encounter"}
		for index in encounter_progress:
			var progress: Dictionary = encounter_progress[index]
			if int(progress.next_wave) < progress.plan.waves.size():
				return {"position":encounter_zones[index].center,"title":"准备迎接增援","name_en":"Prepare for reinforcements","kind":"encounter"}
		for index in encounter_zones.size():
			if not activated_encounters.has(index):
				return {"position":encounter_zones[index].center,"title":"探索下一矿区","name_en":"Explore the next sector","kind":"objective"}
	return {"position":exit_position,"title":"撤离升降井","name_en":"Extraction lift","kind":"extract"}

func _biome_id() -> String:
	return str(expedition_context.get("biome_id",WorldCatalog.room(layout_id).get("biome_id","B01")))

func prepare_expedition_node(context: Dictionary) -> Dictionary:
	# Validation and prop placement happen before the durable node transaction.
	# No current room, player, reward or RNG stream is mutated here.
	var id: String = str(context.get("room_id",""))
	var role: String = str(context.get("role",""))
	var seed_value: int = int(context.get("seed",41827))
	var next: Dictionary = {}
	if role in ["entrance","supply"]:
		next = _service_layout(context)
	elif role == "boss":
		var script_path: String = "res://scripts/world/boss_layouts.gd"
		if ResourceLoader.exists(script_path) and ResourceLoader.exists("res://scripts/combat/boss.gd"):
			next = load(script_path).build(id,seed_value)
	else:
		next = Generator.generate(id,seed_value) if use_generated_layout else Layouts.build(id)
	if next.is_empty() or not next.has("entry") or not next.has("exit"):
		return {"valid":false,"error":"房间布局未能加载："+id}
	var props: Node2D = PropsScript.new()
	if role not in ["entrance","supply","boss"]:
		if not props.configure(self,next):
			var error: String = "; ".join(props.configuration_errors)
			props.free()
			return {"valid":false,"error":error}
	else:
		props.room = self
		props.layout = next.duplicate(true)
		props.room_id = id
		props.biome_id = str(context.get("biome_id","B01"))
		props.obstacle_recipes = preload("res://scripts/world/room_appearance.gd").recipe(next,props.biome_id)
		props.z_index = 1
	return {"valid":true,"layout":next,"props":props,"context":context.duplicate(true),"runtime":expedition_runtime_snapshot()}

func discard_prepared_expedition_node(prepared: Dictionary) -> void:
	var props: Variant = prepared.get("props")
	if is_instance_valid(props) and props.get_parent() == null:
		props.free()

func apply_prepared_expedition_node(prepared: Dictionary) -> void:
	assert(bool(prepared.get("valid",false)))
	if not is_node_ready():
		_prepared_initial = prepared
		return
	_install_expedition_layout(prepared)
	_activate_expedition_content()
	restore_expedition_runtime(prepared.get("runtime",{}))
	set_input_blocked(false)

func _install_expedition_layout(prepared: Dictionary) -> void:
	if is_instance_valid(objectives):
		objectives.reset()
		objectives.free()
	objectives = null
	if is_instance_valid(enemy_skills): enemy_skills.reset_room()
	if is_instance_valid(enemy_props):
		enemy_props.clear()
		enemy_props.free()
	for container: Node in [get_node("Enemies"),get_node("Projectiles")]:
		for actor in container.get_children():
			container.remove_child(actor)
			actor.queue_free()
	if is_inside_tree():
		for deployment in get_tree().get_nodes_in_group("hero_deployments"):
			if deployment.room == self: deployment.retire()
	expedition_context = prepared.context.duplicate(true)
	layout = prepared.layout.duplicate(true)
	layout_id = str(expedition_context.room_id)
	difficulty = clampi(int(expedition_context.get("difficulty",0)),0,4)
	layout_seed = int(expedition_context.get("seed",41827))
	run_seed = layout_seed
	obstructions.assign(layout.get("obstructions",[]))
	_navigation_cache.prepare(obstructions,ARENA)
	exit_position = layout.exit
	encounter_zones = layout.get("encounter_zones",[]).duplicate(true)
	activated_encounters.clear()
	encounter_progress.clear()
	enemy_corpses.clear()
	gold_drops.clear()
	effects.clear()
	crit_rolls.clear()
	relic_positions.clear()
	wave = 0
	objective_wave_count = encounter_zones.size()
	objective_complete = false
	objective_rewarded = false
	_completion_emitted = false
	_boss_actor = null
	_boss_defeated = false
	_node_loot_spawned = 0
	_expedition_ready = false
	progress_retry_timer = 0
	enemy_props = prepared.props
	enemy_props.name = "RoomProps"
	add_child(enemy_props)
	spawn_enabled = str(expedition_context.get("role","")) not in ["entrance","supply","boss"]
	if is_instance_valid(player):
		player.cancel_actions()
		player.position = layout.entry
		_previous_player_position = player.position
		$MineBackdrop.configure(ARENA,_biome_id(),layout_seed)
		if camera != null: camera.follow_target()
	else:
		_expedition_restore = Game.expedition_snapshot().get("runtime",{}).duplicate(true)
	configuration_ready = true
	configuration_error = ""
	queue_redraw()

func _activate_expedition_content() -> void:
	if not is_instance_valid(player): return
	var state: Dictionary = Game.expedition_snapshot()
	var role: String = str(expedition_context.get("role",""))
	if str(state.get("phase","")) == "cleared" and int(state.get("node_index",-1)) == int(expedition_context.get("node_index",-2)):
		# This is a persisted safe checkpoint, whose objectives and rewards have
		# already committed. Reopening it cannot spawn another paid encounter.
		objective_complete = true
		objective_rewarded = true
		_completion_emitted = true
		spawn_enabled = false
	elif role in ["entrance","supply"]:
		objective_complete = true
		objective_rewarded = true
	elif role == "boss":
		var boss_script: String = "res://scripts/combat/boss.gd"
		if ResourceLoader.exists(boss_script):
			var boss: Node2D = load(boss_script).new()
			boss.room = self
			boss.position = layout.get("boss_spawn",Vector2(1800,900))
			boss.configure_boss(layout_id,difficulty)
			boss.completed.connect(func(_id: String,_payload: Dictionary) -> void: _boss_defeated = true)
			_boss_actor = boss
			enemies.add_child(boss)
			objectives = load("res://scripts/world/boss_arena.gd").new()
			add_child(objectives)
			objectives.configure_boss_arena(self,layout,boss)
	else:
		objectives = load("res://scripts/world/room_objectives.gd").new()
		objectives.name = "RoomObjectives"
		add_child(objectives)
		objectives.configure(self,layout,role)
		_update_encounters()
	_expedition_ready = true

func _tick_expedition(delta: float) -> void:
	if not _expedition_ready: return
	var role: String = str(expedition_context.get("role",""))
	if role in ["entrance","supply"]: return
	if not objective_complete:
		if role == "boss":
			_update_boss_encounter()
			objective_complete = _boss_defeated and _living_enemy_count() == 0
		else:
			var task_done: bool = is_instance_valid(objectives) and objectives.is_complete()
			if not task_done: _update_encounters(delta)
			objective_complete = task_done and _living_enemy_count() == 0
	if not objective_complete or objective_rewarded or progress_retry_timer > 0.0: return
	# Safe checkpoints contain no continuing enemy damage. Preserve absolute HP,
	# resource, beneficial guards and all cooldowns; only end the finished fight.
	if is_instance_valid(enemy_skills): enemy_skills.reset_room()
	if is_instance_valid(objectives): objectives.hazards.clear()
	player.status.states.clear()
	player._enemy_status_origins.clear()
	# Collect remaining visible coins at the completed-room checkpoint. This
	# avoids silently deleting earned pickups when a player chooses a route.
	for index in range(gold_drops.size()-1,-1,-1):
		if Game.add_gold(int(gold_drops[index].amount)):
			telemetry.gold_collected += int(gold_drops[index].amount)
			gold_drops.remove_at(index)
	var event_id: String = Game.run.id+":node:"+str(expedition_context.node_index)+":complete"
	var quality: String = str(objectives.status().get("quality","full")) if is_instance_valid(objectives) else "full"
	var rewards: Dictionary = {"xp":80 if role == "boss" else 30,"mastery":0 if role == "boss" else 180,"gold":80 if role == "boss" else (6 if quality in ["reduced","repaired"] else 12)}
	var equipment_ids: Array = ContentRegistry.equipment_ids()
	if not equipment_ids.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = layout_seed ^ 0x45515549
		var eq_id: String = str(equipment_ids[rng.randi_range(0,equipment_ids.size()-1)])
		rewards["equipment"] = [{"drop_id":event_id+":equipment","equipment_id":eq_id}]
	if role == "boss": rewards["boss_id"] = layout_id
	objective_rewarded = Game.commit_expedition_completion(event_id,expedition_runtime_snapshot(),rewards)
	progress_retry_timer = 1.0
	if objective_rewarded and not _completion_emitted:
		if is_instance_valid(enemy_skills): enemy_skills.reset_room()
		if is_instance_valid(objectives):
			objectives.hazards.clear()
			objectives.set_process(false)
		for projectile in projectiles.get_children(): projectile.queue_free()
		_completion_emitted = true
		room_completed.emit()

func expedition_runtime_snapshot() -> Dictionary:
	if not is_instance_valid(player):
		return Game.expedition_snapshot().get("runtime",{}).duplicate(true) if Game.run != null else {}
	var path: String = "res://scripts/combat/combat_snapshot.gd"
	return load(path).capture(self) if ResourceLoader.exists(path) else {}

func restore_expedition_runtime(runtime: Dictionary) -> bool:
	if runtime.is_empty(): return false
	if not is_instance_valid(player):
		_expedition_restore = runtime.duplicate(true)
		return true
	var path: String = "res://scripts/combat/combat_snapshot.gd"
	return bool(load(path).restore_room_entry(self,runtime)) if ResourceLoader.exists(path) else false

func objective_blocks_dash() -> bool:
	return is_instance_valid(objectives) and objectives.blocks_dash()

func _update_boss_encounter() -> void:
	if not is_instance_valid(_boss_actor) or not _boss_actor.is_alive(): return
	for request: Dictionary in _boss_actor.take_reinforcement_requests():
		var points: Array = request.get("spawn_points",layout.get("spawn_points",[]))
		var serial: int = 0
		for member: Dictionary in request.get("members",[]):
			for index in int(member.get("count",1)):
				var at: Vector2 = points[serial%points.size()] if not points.is_empty() else _boss_actor.position+Vector2(220,0)
				serial += 1
				if at.distance_to(player.position) < 360:
					at = clamp_actor(player.position+player.position.direction_to(at)*360,24)
				spawn_enemy(at,str(member.get("enemy_id","")),int(member.get("level",1))+difficulty*2,_boss_actor.reinforcement_spawn_options())

func on_objective_event(_kind: String, _data: Dictionary) -> void:
	queue_redraw()

func _service_layout(context: Dictionary) -> Dictionary:
	return {"room_id":str(context.room_id),"seed":int(context.get("seed",0)),"arena":ARENA,"entry":Vector2(960,900),"exit":Vector2(1760,900),"service_position":Vector2(1260,900),"obstructions":[],"static_obstructions":[],"static_obstruction_kinds":[],"prop_instances":[],"spawn_points":[],"objective_points":[],"encounter_zones":[],"interactables":[],"hazard_zones":[],"visual_markers":[],"topology_probes":[]}
