class_name RoomController
extends Node2D
const Numerical = preload("res://scripts/infrastructure/content/runtime_rules.gd")

signal interaction_requested(kind: String, payload: Dictionary)
signal hint_changed(key: String, data: Dictionary)
signal room_completed()

const PlayerScene = preload("res://scenes/gameplay/characters/hero.tscn")
const EnemyScene = preload("res://scenes/gameplay/monsters/enemy.tscn")
const ProjectileScene = preload("res://scenes/gameplay/combat/projectile.tscn")
const DeploymentScript = preload("res://scripts/gameplay/characters/hero_deployment.gd")
const CameraScript = preload("res://scripts/gameplay/world/world_camera.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
const EnemyProfilesScript = preload("res://scripts/domain/combat/enemy_profiles.gd")
const EnemyArtScript = preload("res://scripts/presentation/monsters/enemy_art.gd")
const EnemyNumericalV2Script = preload("res://scripts/domain/combat/enemy_numbers.gd")
const EnemyDifficultyScript = preload("res://scripts/domain/combat/enemy_difficulty.gd")
const EnemySkillsScript = preload("res://scripts/gameplay/monsters/enemy_skill_runtime.gd")
const EnemyTelegraphsScript = preload("res://scripts/presentation/monsters/enemy_telegraphs.gd")
const PropsScript = preload("res://scripts/presentation/world/room_props.gd")
const AudioScript = preload("res://scripts/presentation/combat/combat_audio.gd")
const ImpactScript = preload("res://scripts/presentation/combat/impact_feedback.gd")
const DefeatScript = preload("res://scripts/presentation/monsters/enemy_defeat_feedback.gd")
const SkillInputScript = preload("res://scripts/presentation/combat/skill_input_feedback.gd")
const Generator = preload("res://scripts/gameplay/world/room_generator.gd")
const CircuitScript = preload("res://scripts/gameplay/combat/resonance_circuit.gd")
const ClassRelics = preload("res://scripts/domain/combat/class_relics.gd")
const RoomRewards = preload("res://scripts/domain/world/room_rewards.gd")
const InteractionSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const WorldArt = preload("res://scripts/infrastructure/assets/world_art.gd")
const DEFAULT_ARENA := Rect2(0, 0, 2800, 1800)
const GroundBoundary = preload("res://scripts/gameplay/world/room_boundary.gd")
var ARENA: Rect2 = DEFAULT_ARENA
var ground_polygon := PackedVector2Array()
const EXIT_POSITION := Vector2(2696, 900)
const RELIC_POSITIONS := {"split": Vector2(425,959), "ember": Vector2(1466,354), "arc": Vector2(1962,885)}

var player: HeroActor
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
const Crit = preload("res://scripts/domain/combat/crit_policy.gd")
var crit_rolls: Dictionary = {}
var true_bonus_roots: Dictionary = {}
var primary_hit_roots: Dictionary = {}
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
var enemy_telegraphs: Node2D
var enemy_props: Node2D
var difficulty: int = 0
var use_generated_layout: bool = true
var run_seed: int = -1
var layout_seed: int = -1
var encounter_progress: Dictionary = {}
var _encounter_spawn_retry: Dictionary = {}
var configuration_ready: bool = false
var configuration_error: String = ""
var enemy_corpses: Array[Dictionary] = []
var combat_audio: Node
var impact_feedback: Node2D
var defeat_feedback: Node2D
var skill_input_feedback: Node2D
var _contact_pulse_until: float = -1.0
var _contact_pulse_heavy: bool = false
var circuit: Node2D
var circuit_training: Node2D
var last_player_sound_position := Vector2.ZERO
var last_player_sound_time: float = -100.0
var interaction_textures: Dictionary = {}
var _navigation_cache: RefCounted = preload("res://scripts/gameplay/world/navigation_cache.gd").new()
var expedition_context: Dictionary = {}
var b05_mechanics: Node2D
var b06_mechanics: Node2D
var b06_environment: Node2D
var _b06_environment_tide: Node2D
var _b06_previous_native_water: bool = false
var _b06_previous_visibility: Array[Dictionary] = []
var objectives: Node2D
var _prepared_initial: Dictionary = {}
var _expedition_restore: Dictionary = {}
var _expedition_ready: bool = false
var _completion_emitted: bool = false
var _node_loot_spawned: int = 0
var _natural_spawn_serial: int = 0
var _boss_actor: Node2D
var _boss_defeated: bool = false
var _terrain_canvas: Node2D
var _floor_canvas: Node2D
var _terrain_geometry: Array[Rect2] = []
var _terrain_owner_id: int = -1
var terrain_redraw_count: int = 0
var _depth_canvas: Node2D
var _enemy_visual_counts: Dictionary = {}
var _enemy_visual_room_key: String = ""

var _encounters_service = preload("res://scripts/gameplay/world/services/encounters_service.gd").new(self)
var _interactions_service = preload("res://scripts/gameplay/world/services/interactions_service.gd").new(self)
var _feedback_service = preload("res://scripts/gameplay/world/services/feedback_service.gd").new(self)
var _navigation_service = preload("res://scripts/gameplay/world/services/navigation_service.gd").new(self)

func _enter_tree() -> void:
	# A retained room can be removed and reattached without receiving _ready again.
	if is_node_ready(): _configure_b06_environment.call_deferred()

func _exit_tree() -> void:
	_release_b06_environment()

func _ready() -> void:
	# Every raised object and actor shares one depth plane; feet provide the
	# ordering while floor drawings, projectiles and UI keep their fixed layers.
	y_sort_enabled = true
	enemies.z_index = 2
	enemies.y_sort_enabled = true
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
	_create_ground_canvases()
	player = PlayerScene.instantiate()
	player.room = self
	player.position = layout.get("entry", Vector2(250,360))
	add_child(player)
	player.z_index = 2
	combat_audio = AudioScript.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)
	impact_feedback = ImpactScript.new()
	impact_feedback.name = "ImpactFeedback"
	add_child(impact_feedback)
	defeat_feedback = DefeatScript.new()
	defeat_feedback.name = "DefeatFeedback"
	add_child(defeat_feedback)
	skill_input_feedback = SkillInputScript.new()
	skill_input_feedback.name = "SkillInputFeedback"
	add_child(skill_input_feedback)
	skill_input_feedback.configure(self)
	circuit = CircuitScript.new()
	circuit.name = "ResonanceCircuit"
	add_child(circuit)
	circuit.configure(self)
	enemy_skills = EnemySkillsScript.new()
	enemy_skills.name = "EnemySkills"
	add_child(enemy_skills)
	enemy_skills.configure(self)
	enemy_skills.z_index = 4
	enemy_telegraphs = EnemyTelegraphsScript.new()
	add_child(enemy_telegraphs)
	enemy_telegraphs.configure(self)
	interaction_overlay = Node2D.new()
	interaction_overlay.z_index = 8
	interaction_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(interaction_overlay)
	interaction_overlay.draw.connect(func() -> void: _draw_interaction_focus(interaction_overlay))
	for icon_key: String in ["interaction", "exit", "loot"]:
		var icon: Texture2D = InteractionSampler.sampled("asset://ui/" + icon_key + "_v1.png")
		if icon != null:
			interaction_textures[icon_key] = icon
	camera = CameraScript.new()
	add_child(camera)
	_configure_world_view()
	_previous_player_position = player.position
	fx_font = ThemeDB.fallback_font
	if ResourceLoader.exists(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf")):
		fx_font = load(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf"))
	for id in relic_positions:
		var asset_path: String = ClassRelics.art_path(id)
		if ResourceLoader.exists(AssetCatalog.resolve(asset_path)):
			relic_textures[id] = load(AssetCatalog.resolve(asset_path))
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
	if blocked:
		if is_instance_valid(b05_mechanics): b05_mechanics.cancel_interaction()
		if is_instance_valid(player):
			player.clear_buffered_skill()
			player.clear_movement_target()
			player.attack_buffer = 0.0
		if is_instance_valid(skill_input_feedback): skill_input_feedback.clear_feedback()

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
		var movement_held: bool = InputMap.has_action("click_move") and Input.is_action_pressed("click_move")
		var attack_held: bool = player.attack_input_held() if is_instance_valid(player) else Input.is_action_pressed("attack")
		if not attack_held and not secondary_held and not movement_held:
			pointer_release_gate = false
	return not pointer_release_gate

func _physics_process(delta: float) -> void:
	if Game.run == null:
		return
	elapsed += delta
	if is_instance_valid(b06_mechanics):
		if input_blocked or Game.run.hp <= 0.0: b06_mechanics.cancel_interaction()
		b06_mechanics.tick(delta,false)
	if is_instance_valid(b05_mechanics):
		if input_blocked or Game.run.hp <= 0.0: b05_mechanics.cancel_interaction()
		b05_mechanics.tick(delta,false)
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
	if is_instance_valid(circuit): circuit.advance(delta)
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
	_refresh_terrain_canvas()
	if is_instance_valid(_floor_canvas): _floor_canvas.queue_redraw()

func _create_ground_canvases() -> void:
	# Godot retains each canvas's draw list. Keep stationary obstacle art out of
	# the 60-Hz effects/cursor redraw, while lamp darkness remains below it.
	_floor_canvas = Node2D.new()
	_floor_canvas.name = "DynamicFloor"
	_floor_canvas.z_index = -3
	add_child(_floor_canvas)
	_floor_canvas.draw.connect(func() -> void:
		if is_instance_valid(enemy_props): enemy_props.draw_floor(_floor_canvas))
	_terrain_canvas = Node2D.new()
	_terrain_canvas.name = "StaticTerrain"
	_terrain_canvas.z_index = -2
	add_child(_terrain_canvas)
	_terrain_canvas.draw.connect(func() -> void:
		if is_instance_valid(enemy_props): enemy_props.draw_obstacles(_terrain_canvas))
	_depth_canvas = preload("res://scripts/presentation/world/room_depth_layer.gd").new()
	_depth_canvas.name = "RaisedScenery"
	add_child(_depth_canvas)
	_refresh_terrain_canvas()

func _refresh_terrain_canvas() -> void:
	if not is_instance_valid(_terrain_canvas): return
	var owner_id: int = enemy_props.get_instance_id() if is_instance_valid(enemy_props) else 0
	if owner_id == _terrain_owner_id and _terrain_geometry == obstructions: return
	_terrain_owner_id = owner_id
	_terrain_geometry.assign(obstructions)
	_terrain_canvas.material = WorldArt.material_for(_biome_id())
	_terrain_canvas.queue_redraw()
	if is_instance_valid(_depth_canvas):
		_depth_canvas.configure(self,layout,_biome_id(),enemy_props.obstacle_recipes if is_instance_valid(enemy_props) else [])
	terrain_redraw_count += 1

func clamp_actor(at: Vector2, radius: float) -> Vector2:
	if not ground_polygon.is_empty(): return GroundBoundary.clamp_point(ground_polygon, at, radius)
	return Vector2(clampf(at.x, ARENA.position.x + radius, ARENA.end.x - radius), clampf(at.y, ARENA.position.y + radius, ARENA.end.y - radius))

func _configure_ground_boundary() -> void:
	ARENA = layout.get("arena", DEFAULT_ARENA)
	if (str(layout.get("biome_id","")) == "B05" or bool(layout.get("b06_candidate",false))) and layout.get("ground_polygon") is PackedVector2Array:
		ground_polygon = layout.ground_polygon
		ARENA = GroundBoundary.bounds(ground_polygon)
		return
	ground_polygon = PackedVector2Array()
	if bool(layout.get("fixed_layout", false)) or bool(layout.get("painted_service", false)):
		ground_polygon = WorldArt.environment_ground_polygon(ARENA, _biome_id(), WorldArt.environment_room_id(layout))
		if not ground_polygon.is_empty(): ARENA = GroundBoundary.bounds(ground_polygon)

func _configure_world_view() -> void:
	var painted_arena: Rect2 = layout.get("arena", ARENA)
	$MineBackdrop.configure(painted_arena, _biome_id(), layout_seed, WorldArt.environment_room_id(layout))
	$MineBackdrop.configure_layout(layout,Numerical.b05_candidate_enabled())
	if is_instance_valid(camera):
		camera.configure(self, player, ARENA, $MineBackdrop.painted_bounds())
	_configure_b06_environment()

func _create_b06_environment(id: String) -> Node2D:
	var path := "res://scripts/levels/b06/world/environment_pilot.gd" if id == "L31" else "res://scripts/levels/b06/world/environment_batch.gd"
	if not ResourceLoader.exists(AssetCatalog.resolve(path)): return null
	var script: Script = load(AssetCatalog.resolve(path))
	return script.new() if script != null and script.can_instantiate() else null

func _configure_b06_environment() -> void:
	_release_b06_environment()
	# The isolated process gate is required in addition to matching authored data.
	# Merely preparing a B06 layout for a tool/fixture cannot enable candidate art.
	if not is_inside_tree() or not Numerical.b06_candidate_enabled(): return
	if not bool(layout.get("b06_candidate",false)) or str(layout.get("biome_id","")) != "B06" or _biome_id() != "B06": return
	if layout_id not in ["L31","L32","L33","L34","L35","L36","BO06"] or str(layout.get("room_id","")) != layout_id: return
	if not is_instance_valid(b06_mechanics) or b06_mechanics.room_id != layout_id: return
	var environment: Node2D = _create_b06_environment(layout_id)
	if not is_instance_valid(environment): return
	_b06_environment_tide = b06_mechanics
	_b06_previous_native_water = b06_mechanics.native_water_visual
	b06_environment = environment
	# Configure before attaching or hiding the fallback; failure is visual only.
	if not environment.configure(layout,b06_mechanics):
		_release_b06_environment()
		return
	environment.name = "B06Environment"
	add_child(environment)
	# Only superseded scenery is hidden. Props, actors, gameplay mechanisms,
	# projectiles, telegraphs, feedback, interactions and HUD remain untouched.
	for layer: Node2D in [get_node_or_null("MineBackdrop"),_floor_canvas,_terrain_canvas,_depth_canvas]:
		if not is_instance_valid(layer): continue
		_b06_previous_visibility.append({"node":layer,"visible":layer.visible})
		layer.hide()

func _release_b06_environment() -> void:
	if is_instance_valid(b06_environment): b06_environment.free()
	b06_environment = null
	# Helpers clear their flag on exit; restore the value we actually took over
	# after freeing them, including failure and retained-room tree exit paths.
	if is_instance_valid(_b06_environment_tide):
		_b06_environment_tide.native_water_visual = _b06_previous_native_water
		_b06_environment_tide.queue_redraw()
	_b06_environment_tide = null
	for previous: Dictionary in _b06_previous_visibility:
		if is_instance_valid(previous.node): previous.node.visible = previous.visible
	_b06_previous_visibility.clear()

func enemy_ruleset() -> int:
	return Game.run.ruleset_version() if Game.run != null else Numerical.LEGACY

func enemy_calibration() -> Dictionary:
	return Game.run.enemy_calibration_snapshot.duplicate(true) if Game.run != null else {}

func spawn_enemy(at: Vector2, id: String = "", level: int = 1, options: Dictionary = {}) -> EnemyActor:
	return _encounters_service.spawn_enemy(at, id, level, options)

func _assign_enemy_appearance(enemy: EnemyActor) -> void:
	if enemy.static_actor or EnemyArtScript.variant_count(enemy.enemy_id) == 0:
		return
	var room_key: String = layout_id + ":" + str(layout_seed)
	if room_key != _enemy_visual_room_key:
		_enemy_visual_counts.clear()
		_enemy_visual_room_key = room_key
	var serial: int = int(_enemy_visual_counts.get(enemy.enemy_id, 0))
	# Assign after a valid spawn but before _ready installs the body. The
	# counter survives actor deaths and all finite reinforcement waves.
	enemy.profile["visual_variant_index"] = EnemyArtScript.variant_index_for(enemy.enemy_id, serial, layout_id, layout_seed)
	_enemy_visual_counts[enemy.enemy_id] = serial + 1

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

func spawn_enemy_summon(caster: Node2D, id: String, at: Vector2) -> EnemyActor:
	return _encounters_service.spawn_enemy_summon(caster, id, at)

func spawn_enemy_skill_anchor(caster: Node2D, at: Vector2, health_amount: float, anchor_kind: String = "") -> EnemyActor:
	return _encounters_service.spawn_enemy_skill_anchor(caster, at, health_amount, anchor_kind)

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

func notify_enemy_charge(caster: Node2D, from: Vector2, to: Vector2) -> void:
	if is_instance_valid(objectives) and objectives.has_method("notify_charge_impact"):
		objectives.notify_charge_impact(caster, from, to)

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

func telegraph_canvas_transform(canvas: Node2D) -> Transform2D:
	# Brains publish room-local geometry. One matrix transforms points, vectors,
	# ring angles and radii together, including a rotated/scaled room or layer.
	return canvas.global_transform.affine_inverse() * global_transform

func draw_enemy_telegraph(canvas: Node2D, data: Dictionary) -> void:
	if data.is_empty():
		return
	canvas.draw_set_transform_matrix(telegraph_canvas_transform(canvas))
	var origin: Vector2 = data.get("origin", Vector2.ZERO)
	var target: Vector2 = data.get("target", origin)
	var direction: Vector2 = data.get("direction",Vector2.RIGHT)
	var radius: float = float(data.get("radius",48.0))
	var reach: float = float(data.get("range",96.0))
	var locked: bool = bool(data.get("locked",false))
	var style: Dictionary = EnemyTelegraphsScript.palette(locked, bool(Game.profile.get("settings",{}).get("reduced_fx",false)))
	var tint: Color = style.edge
	var fill := Color(tint,float(style.fill_alpha))
	var width: float = float(style.width)
	var shape: String = str(data.get("shape","cone"))
	var targets: Array = data.get("targets",[])
	if not targets.is_empty():
		for point: Vector2 in targets:
			if shape == "ring":
				_draw_warning_ring(canvas,point,radius,data,direction,style)
			else:
				canvas.draw_circle(point,radius,fill)
				_warning_arc(canvas,point,radius,0,TAU,40,tint,width)
	if shape in ["circle","ring"] and targets.is_empty():
		var center: Vector2 = target if str(data.get("kind","")) in ["ground_area","charge"] or str(data.get("action","")) == "steal_scene_lamp" else origin
		if shape == "circle":
			canvas.draw_circle(center,radius,fill)
			_warning_arc(canvas,center,radius,0,TAU,48,tint,width)
		else:
			_draw_warning_ring(canvas,center,radius,data,direction,style)
	elif shape in ["cone","arc","sector"]:
		var angle: float = float(data.get("angle",1.5))
		var fan := PackedVector2Array([origin])
		for step in range(25):
			fan.append(origin+direction.rotated(-angle*.5+angle*step/24.0)*reach)
		fan.append(origin)
		canvas.draw_colored_polygon(fan,fill)
		_warning_polyline(canvas,fan,tint,width)
	var points: Array = data.get("points",[])
	var angles: Array = data.get("projectile_angles",[])
	var explicit_paths: Array = data.get("paths",[])
	if not explicit_paths.is_empty():
		for points_in_path: Array in explicit_paths:
			var path := PackedVector2Array(points_in_path)
			if path.size() >= 2:
				canvas.draw_polyline(path,Color(tint,float(style.path_alpha)),maxf(3.0,float(data.get("width",12.0))),true)
				_warning_polyline(canvas,path,tint,width)
	elif points.size() >= 2:
		var rotations: Array = angles if not angles.is_empty() else [0.0]
		for angle_degrees in rotations:
			var path := PackedVector2Array()
			for point: Vector2 in points:
				path.append(origin+(point-origin).rotated(deg_to_rad(float(angle_degrees))))
			canvas.draw_polyline(path,Color(tint,float(style.path_alpha)),maxf(3.0,float(data.get("width",12.0))),true)
			_warning_polyline(canvas,path,tint,width)
	elif shape == "line":
		canvas.draw_line(origin,target,Color(tint,float(style.path_alpha)),maxf(3,float(data.get("width",12.0))),true)
		_warning_line(canvas,origin,target,tint,width)
	if explicit_paths.is_empty() and points.size() < 2:
		for angle_degrees in angles:
			var dir: Vector2 = direction.rotated(deg_to_rad(float(angle_degrees)))
			_warning_line(canvas,origin,origin+dir*reach,tint,width)
	if str(data.get("landing_shape","")) in ["circle","ring"]:
		if str(data.landing_shape) == "ring":
			_draw_warning_ring(canvas,target,radius,data,direction,style)
		else:
			_warning_arc(canvas,target,radius,0,TAU,40,tint,width)
	elif str(data.get("landing_shape","")) == "cone":
		var landing_angle: float = float(data.get("angle",1.8))
		var fan := PackedVector2Array([target])
		for index in range(25):
			fan.append(target+direction.rotated(-landing_angle*.5+landing_angle*index/24.0)*reach)
		fan.append(target)
		canvas.draw_colored_polygon(fan,fill)
		_warning_polyline(canvas,fan,tint,width)
	var combo: Array = data.get("combo_directions",[])
	if combo.size() > 1:
		for index in combo.size():
			var dir: Vector2 = combo[index]
			var end: Vector2 = origin+dir*reach
			_warning_line(canvas,origin,end,Color(tint,.45),1.0)
			canvas.draw_circle(end,9.0,Color("1b2529"))
			if fx_font != null:
				canvas.draw_string(fx_font,end+Vector2(-4,4),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,tint)
	var timing: Dictionary = data if data.has("release_progress") else EnemyTelegraphsScript.presentation_data(data)
	# A single clockwise arc reaches full only at release. The last segment and
	# its radial tick mark where tracking stops; no flashing or reset on lock.
	canvas.draw_arc(origin,12.0,0,TAU,32,EnemyTelegraphsScript.INK,5.0,true)
	var lock_angle: float = -PI*.5 + TAU*float(timing.lock_fraction)
	canvas.draw_arc(origin,12.0,lock_angle,PI*1.5,16,Color(EnemyTelegraphsScript.LOCKED,.4),2.0,true)
	var progress: float = float(timing.release_progress)
	if progress > .0001:
		_warning_arc(canvas,origin,12.0,-PI*.5,-PI*.5+TAU*progress,32,tint,2.0)
	var tick := Vector2.from_angle(lock_angle)
	_warning_line(canvas,origin+tick*9.0,origin+tick*15.0,EnemyTelegraphsScript.LOCKED,1.5)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

func _warning_line(canvas: Node2D, start: Vector2, finish: Vector2, tint: Color, width: float) -> void:
	canvas.draw_line(start,finish,EnemyTelegraphsScript.INK,width+2.2,true)
	canvas.draw_line(start,finish,tint,width,true)

func _warning_polyline(canvas: Node2D, points: PackedVector2Array, tint: Color, width: float) -> void:
	canvas.draw_polyline(points,EnemyTelegraphsScript.INK,width+2.2,true)
	canvas.draw_polyline(points,tint,width,true)

func _warning_arc(canvas: Node2D, center: Vector2, radius: float, start: float, finish: float, segments: int, tint: Color, width: float) -> void:
	canvas.draw_arc(center,radius,start,finish,segments,EnemyTelegraphsScript.INK,width+2.2,true)
	canvas.draw_arc(center,radius,start,finish,segments,tint,width,true)

func _draw_warning_ring(canvas: Node2D, center: Vector2, radius: float, data: Dictionary, direction: Vector2, style: Dictionary) -> void:
	var inner: float = maxf(0,float(data.get("inner_radius",radius*.48)))
	var gap: float = deg_to_rad(clampf(float(data.get("ring_gap_degrees",0)),0,180))
	var start: float = float(data.get("ring_start",direction.angle()+gap*.5 if gap > 0 else 0.0))
	var finish: float = float(data.get("ring_end",start+TAU-gap))
	var tint: Color = style.edge
	var width: float = float(style.width)
	for index in range(40):
		var a := Vector2.from_angle(lerpf(start,finish,index/40.0))
		var b := Vector2.from_angle(lerpf(start,finish,(index+1)/40.0))
		var polygon := PackedVector2Array([center+a*inner,center+a*radius,center+b*radius,center+b*inner])
		if inner <= .001:
			polygon = PackedVector2Array([center,center+a*radius,center+b*radius])
		canvas.draw_colored_polygon(polygon,Color(tint,float(style.fill_alpha)))
	_warning_arc(canvas,center,radius,start,finish,48,tint,width)
	if inner > 0:
		_warning_arc(canvas,center,inner,start,finish,40,tint,width)
	if gap > 0:
		for angle in [start,finish]:
			var ray := Vector2.from_angle(angle)
			_warning_line(canvas,center+ray*inner,center+ray*radius,tint,width)
		_warning_line(canvas,center+direction*(inner+8),center+direction*(radius-8),Color("9be1c6"),1.3)

func _spawn_wave() -> void:
	_encounters_service._spawn_wave()

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
	var frozen_power: float = player.primary_power_snapshot()
	var frozen_stats: Dictionary = player.primary_stats_snapshot()
	var projectile_origin: Vector2 = player.position
	var visual_muzzle: Vector2 = player.position+HeroVisual.release_muzzle_local(player.hero_id(),"basic",direction)
	if player.hero_id() == "CH03" and player.role_kit != null and player.role_kit.has_method("projectile_origin"):
		var star_origin: Vector2 = player.role_kit.projectile_origin(direction)
		if valid_ground(star_origin, 2.0) and has_line_of_sight(player.position, star_origin): projectile_origin = star_origin
		var companion: Node2D = player.role_kit.get("companion")
		if is_instance_valid(companion): visual_muzzle = player.position+companion.position+direction.normalized()*12.0
	var projectile := spawn_projectile(projectile_origin, direction, frozen_power * (1.5 if critical else 1.0), &"primary")
	if projectile == null:
		return false
	record_attack()
	projectile.speed = 950.0 if player.hero_id() == "CH02" else 720.0
	projectile.distance_left = player.stat("range", 650.0 if player.hero_id() == "CH02" else 480.0)
	projectile.remaining = projectile.distance_left / projectile.speed + 0.1
	projectile.attack_id = attack_serial
	projectile.critical = critical
	projectile.options["power"] = frozen_power
	projectile.options["attacker_stats"] = frozen_stats
	projectile.options["class_state"] = player.primary_class_snapshot()
	projectile.options["visual_hero"] = player.hero_id()
	projectile.options["basic_variant"] = player.basic_attack_variant()
	projectile.arc_ready = Game.run.relics.has("arc") and Game.run.shots % 3 == 0
	projectile.configure_player_visual(visual_muzzle)
	return true

func spawn_projectile(at: Vector2, direction: Vector2, damage: float, source: StringName, ignore_id: int = 0) -> ProjectileActor:
	if projectiles.get_child_count() >= Balance.MAX_PROJECTILES:
		return null
	var projectile: ProjectileActor = ProjectileScene.instantiate()
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

func resolve_weapon_hit(projectile: ProjectileActor, target: EnemyActor) -> void:
	if Game.run == null or not target.is_alive():
		return
	# Only weapon projectiles enter this function. Burn / arc call health directly.
	if projectile.source not in [&"primary", &"child"]:
		return
	var hit_position := target.position
	var is_primary := projectile.source == &"primary"
	telemetry["primary_hits" if is_primary else "child_hits"] += 1
	if is_primary:
		var context: Dictionary = {"attack_id":"basic:" + str(projectile.attack_id),"root_event_id":"basic:" + str(projectile.attack_id),"original_basic":true,"equipment_eligible":true,"attack_delivery":"projectile"}
		context["power"] = float(projectile.options.get("power", projectile.damage))
		context["attacker_stats"] = projectile.options.get("attacker_stats", Game.run.stats).duplicate(true)
		context["class_state"] = projectile.options.get("class_state", {}).duplicate(true)
		context["basic_variant"] = int(projectile.options.get("basic_variant",0))
		var reserved: Dictionary = _prepare_relics(context, projectile.trigger_budget, projectile.arc_ready)
		context["native_statuses"] = [ClassRelics.native_status(player.hero_id())] if bool(reserved.get("burn", false)) else []
		var confirmed: bool = resolve_direct_hit(target, projectile.damage, projectile.source, "", 0.0, projectile.direction, context)
		if confirmed and not Numerical.is_v2(Game.run.stats):
			player.on_primary_hit(target)
		if confirmed or not Numerical.is_v2(Game.run.stats):
			_emit_reserved_relics(reserved, context, hit_position, target, projectile.direction)
	else:
		var delivered: Dictionary = projectile.options.duplicate(true)
		delivered["attack_delivery"] = "projectile"
		resolve_derived_hit(target, projectile.damage, projectile.source, projectile.direction, delivered)
	add_ring(projectile.position, Color("f0c77f"), 16.0, 0.15)

func _trigger_arc(origin: Vector2, excluded: EnemyActor, coefficient: float = Balance.ARC_RATIO) -> void:
	var candidates: Array[EnemyActor] = []
	for candidate in enemies.get_children():
		if candidate != excluded and candidate.is_alive() and candidate.position.distance_to(origin) <= Balance.ARC_RANGE and has_line_of_sight(origin, candidate.position):
			candidates.append(candidate)
	candidates.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool: return a.position.distance_squared_to(origin) < b.position.distance_squared_to(origin))
	for i in range(mini(candidates.size(), Balance.ARC_TARGETS)):
		var target := candidates[i]
		_add_effect({"kind":&"arc","from":origin,"to":target.position,"remaining":0.24,"duration":0.24})
		target.take_damage(player.relic_power() * coefficient, &"arc")
		telemetry["arc_hits"] += 1

func enemy_died(enemy: EnemyActor) -> void:
	_encounters_service.enemy_died(enemy)

func _update_gold(delta: float) -> void:
	_interactions_service._update_gold(delta)

func nearby_interaction() -> Dictionary:
	return _interactions_service.nearby_interaction()

func interaction_hint() -> String:
	return _interactions_service.interaction_hint()

func _interaction_key() -> String:
	return _interactions_service._interaction_key()

func interact() -> void:
	_interactions_service.interact()

func _add_effect(effect: Dictionary) -> void:
	_feedback_service._add_effect(effect)

func add_ring(at: Vector2, color: Color, radius: float, duration: float) -> void:
	_feedback_service.add_ring(at, color, radius, duration)

func add_slash(at: Vector2, direction: Vector2) -> void:
	_feedback_service.add_slash(at, direction)

func add_damage_text(at: Vector2, amount: float, kind: StringName, context: Dictionary = {}) -> void:
	_feedback_service.add_damage_text(at, amount, kind, context)

func _draw() -> void:
	# A disabled test fixture or a synchronous interaction can mutate geometry
	# between ticks; refresh its retained obstacle draw list on this path too.
	_refresh_terrain_canvas()
	if not is_instance_valid(enemy_props):
		_draw_cover()
	for corpse: Dictionary in enemy_corpses:
		draw_line(corpse.at-Vector2(7,3),corpse.at+Vector2(6,4),Color("6d6150"),3.0)
		draw_line(corpse.at-Vector2(5,-3),corpse.at+Vector2(4,-5),Color("3f5353"),2.0)
	_draw_exit()
	var archive: Dictionary = skill_archive()
	if not archive.is_empty():
		var archive_at: Vector2 = archive.position
		var archive_icon: Texture2D = interaction_textures.get("loot")
		if archive_icon != null:
			draw_texture_rect(archive_icon, Rect2(archive_at-Vector2(25,44), Vector2(50,50)), false, Color.WHITE if objective_rewarded else Color(.6,.6,.6,.75))
		draw_arc(archive_at, 30, 0, TAU, 32, Color("7acfc0") if objective_rewarded else Color("8c877a"), 2.0, true)
	if not expedition_context.is_empty() and str(expedition_context.get("role","")) in ["entrance","supply"]:
		var at: Vector2 = layout.get("service_position",Vector2(1260,900))
		var icon: Texture2D = interaction_textures.get("loot")
		if icon != null: draw_texture_rect(icon,Rect2(at-Vector2(34,46),Vector2(68,68)),false)
		draw_arc(at,44,0,TAU,36,Color("e0bb72"),2,true)
	# Legacy ground relics belong only to legacy mine runs, never chapter scenes.
	if expedition_context.is_empty():
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
	_interactions_service._draw_exit()

func _draw_relic(id: String, at: Vector2) -> void:
	_interactions_service._draw_relic(id, at)

func _draw_relic_fallback(id: String) -> void:
	_interactions_service._draw_relic_fallback(id)

func _all_inputs_released() -> bool:
	if is_instance_valid(player) and player.attack_input_held():
		return false
	for action: String in ["click_move","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return false
	return true

func _living_enemy_count() -> int:
	return _encounters_service._living_enemy_count()

func valid_ground(at: Vector2, radius: float = 0.0) -> bool:
	return _navigation_service.valid_ground(at, radius)

func move_actor(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	return _navigation_service.move_actor(from, displacement, radius)

func _movement_contact(from: Vector2, to: Vector2, radius: float) -> Vector2:
	return _navigation_service._movement_contact(from, to, radius)

func blocked_fraction(from: Vector2, to: Vector2, radius: float = 0.0) -> float:
	return _navigation_service.blocked_fraction(from, to, radius)

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	return _navigation_service.has_line_of_sight(from, to)

func navigation_direction(from: Vector2, to: Vector2, radius: float) -> Vector2:
	return _navigation_service.navigation_direction(from, to, radius)

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

func intercept_enemy_projectile(from: Vector2, to: Vector2, first_victim_fraction: float = 1.0) -> bool:
	return is_instance_valid(circuit) and circuit.intercept(from, to, first_victim_fraction)

func strike_area(at: Vector2, radius: float, amount: float, source: StringName, applied_status: String = "", push: float = 0.0, direction: Vector2 = Vector2.ZERO, arc_degrees: float = 360.0, original: bool = true, context: Dictionary = {}, confirmed_only: bool = false) -> Array:
	var hit: Array = []
	var confirmed: Array = []
	if context.is_empty():
		context = {"attack_id":("basic:" if source == &"primary" else "area:") + str(attack_serial),"root_event_id":("basic:" if source == &"primary" else "area:") + str(attack_serial)}
		if source != &"primary":
			attack_serial += 1
	if not context.has("attack_delivery"): context["attack_delivery"] = "area"
	if not context.has("damage_type"): context["damage_type"] = "magic" if player.hero_id() == "CH03" else "physical"
	if not context.has("attacker_stats"): context["attacker_stats"] = Game.run.stats.duplicate(true)
	var reserved: Dictionary = {}
	if source == &"primary":
		reserved = _prepare_relics(context, Balance.TRIGGER_BUDGET, Game.run.shots % 3 == 0)
		context["basic_variant"] = player.basic_attack_variant()
		context["native_statuses"] = [ClassRelics.native_status(player.hero_id())] if bool(reserved.get("burn", false)) else []
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
		var contact_direction: Vector2 = offset.normalized() if not offset.is_zero_approx() else direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
		if arc_degrees < 360.0 and not offset.is_zero_approx() and direction.dot(offset.normalized()) < cos(deg_to_rad(arc_degrees) * 0.5):
			continue
		if original:
			var target_context: Dictionary = context.duplicate()
			if source == &"primary" and (confirmed.size() if Numerical.is_v2(Game.run.stats) else hit.size()) >= 3:
				target_context["native_statuses"] = []
			target_context["original_basic"] = source == &"primary"
			target_context["equipment_eligible"] = true
			if resolve_direct_hit(enemy, amount, source, applied_status, push, contact_direction, target_context):
				confirmed.append(enemy)
		else:
			var before_hp: float = enemy.health.current
			var before_shield: float = enemy.status.shield()
			resolve_derived_hit(enemy, amount, source, contact_direction, context)
			var received: bool = bool(enemy.last_damage_result.get("confirmed", false)) if Numerical.is_v2(Game.run.stats) else (enemy.health.current < before_hp or enemy.status.shield() < before_shield)
			if not applied_status.is_empty() and enemy.is_alive() and received:
				# Field control follows a confirmed derived contact and its captured
				# power. It never enters equipment/passive or Shock-consumption hooks.
				enemy.apply_status(applied_status, float(context.get("power", player.skill_power())))
		hit.append(enemy)
		if (source == &"field" or (source == &"ultimate" and player.hero_id() == "CH03")) and hit.size() >= 12:
			break
	var relic_targets: Array = confirmed if Numerical.is_v2(Game.run.stats) else hit
	if not relic_targets.is_empty():
		if source == &"primary":
			_emit_reserved_relics(reserved, context, relic_targets[0].position, relic_targets[0], direction)
	# Basic melee selects one actual recipient for its class passive. Other
	# callers retain the geometric hit list used by existing skill/relic rules.
	return confirmed if confirmed_only else hit

func resolve_direct_hit(target: EnemyActor, amount: float, source: StringName, applied_status: String = "", push: float = 0.0, direction: Vector2 = Vector2.ZERO, attack_context: Dictionary = {}) -> bool:
	if Game.run == null or not target.is_alive():
		return false
	if Numerical.is_v2(Game.run.stats):
		return _resolve_numerical_direct_hit(target, amount, source, applied_status, push, direction, attack_context)
	var context: Dictionary = attack_context.duplicate()
	context.merge({"target":target,"target_states":target.status.states.keys(),"X":amount,"H":float(context.get("power", player.basic_power() if source == &"primary" else player.skill_power())),"damage_source":context.get("damage_source","primary" if source == &"primary" else "skill"),"skill_slot":str(context.get("skill_slot",source)),"proc_depth":int(context.get("proc_depth",0))}, true)
	if Numerical.is_v2(Game.run.stats):
		context["X"] = Numerical.integer(amount)
		context["H"] = Numerical.integer(float(context.H))
	if not context.has("attack_id"):
		attack_serial += 1
		context["attack_id"] = "direct:" + str(attack_serial)
		context["root_event_id"] = context.attack_id
	context["original_basic"] = bool(context.get("original_basic", source == &"primary"))
	context["equipment_eligible"] = bool(context.get("equipment_eligible", true))
	if not context.has("damage_type"): context["damage_type"] = "magic" if player.hero_id() == "CH03" else "physical"
	if not context.has("attacker_stats"): context["attacker_stats"] = Game.run.stats.duplicate(true)
	var native_statuses: Array = context.get("native_statuses", []).duplicate()
	if not applied_status.is_empty() and player.loadout.effects.reserve_native(str(context.root_event_id), "native:" + applied_status):
		native_statuses.append(applied_status)
	var modifiers: Dictionary = player.loadout.event("before_hit", context)
	var root_id: String = str(context.root_event_id)
	if source == &"primary" and not crit_rolls.has(root_id):
		crit_rolls[root_id] = Crit.roll(run_seed, layout_id + ":" + root_id, Crit.chance(context.attacker_stats, float(modifiers.get("crit_bonus", 0.0)))) if Crit.enabled(context.attacker_stats) else randf() < clampf(player.stat("crit_chance", 0.05) + float(modifiers.get("crit_bonus", 0.0)), 0.0, 0.75)
		if crit_rolls.size() > 256:
			crit_rolls.erase(crit_rolls.keys()[0])
	context["critical"] = source == &"primary" and bool(crit_rolls.get(root_id, false))
	var shock: float = target.status.consume_shock()
	var bonus: float = player.stat("damage_bonus", 0.0)
	bonus += float(modifiers.get("damage_bonus", 0.0))
	if target.status.has("corrosion"):
		bonus += 0.08 + player.stat("corrosion_damage_bonus", 0.0)
	if player.has_method("class_modify_hit_amount"):
		amount = player.class_modify_hit_amount(target, amount, source, context)
	var final_amount: float = amount * (1.0 + minf(float(Numerical.value("caps").damage_bonus) if Numerical.is_v2(Game.run.stats) else 0.6, bonus)) * (player.stat("crit_multiplier", 1.5) if bool(context.critical) else 1.0)
	final_amount *= player.hit_chain.multiplier(source, context)
	if Numerical.is_v2(Game.run.stats):
		final_amount = Numerical.integer(final_amount)
		context["ruleset_version"] = Numerical.V2
	var health_before: float = target.health.current
	var shield_before: float = target.status.shield()
	if Crit.enabled(context.get("attacker_stats", {})): context["already_critical"] = true
	target.take_damage(final_amount, source, direction, context)
	# Snapshot the original packet before any shock/true-damage follow-up. A
	# shield hit and a killing blow count; an immune or zero-damage body does not.
	var confirmed: bool = target.health.current < health_before or target.status.shield() < shield_before
	if confirmed:
		# Contact belongs to this packet, before true damage, class procs or shock.
		# A follow-up must not turn a shield tap into a fictitious original break.
		context["hp_damage"] = maxf(0.0, health_before - target.health.current)
		context["shield_damage"] = maxf(0.0, shield_before - target.status.shield())
		context["shield_broken"] = shield_before > 0.0 and target.status.shield() <= 0.0
		var true_bonus: float = maxf(0.0, player.stat("true_damage_bonus", 0.0))
		if true_bonus > 0.0 and bool(context.equipment_eligible) and target.is_alive():
			var true_context: Dictionary = context.duplicate(true)
			true_context.merge({"damage_type":"true","critical":false,"equipment_eligible":false,"original_basic":false,"proc_depth":1},true)
			target.take_damage(true_bonus, &"equipment_true", direction, true_context)
		if player.has_method("class_record_hit"): player.class_record_hit(target, source, context)
		ClassRelics.on_original_hit(self, context)
		_confirm_contact(target, direction, source, bool(context.critical), float(context.hp_damage) + float(context.shield_damage), false, context)
	if target.is_alive() and shock > 0.0:
		target.take_damage(shock, &"shock", direction, {"damage_type":"magic","attacker_stats":Game.run.stats,"equipment_eligible":false})
		add_ring(target.position, Color("81d8e0"), 25.0, 0.2)
	for status_id: String in native_statuses:
		var status_power: float = float(context.H)
		var status_duration: float = -1.0
		if status_id == ClassRelics.native_status(player.hero_id()) and source == &"primary" and Game.run.relics.has("ember"):
			var rank: int = int(Game.run.stats.get("relic_levels",{}).get("RL02",1))
			status_power = ClassRelics.native_status_power(player.hero_id(),player.relic_power() if player.hero_id()=="CH03" else status_power,rank)
			status_duration = ClassRelics.native_status_duration(player.hero_id(),rank,self)
		if target.is_alive() and target.apply_status(status_id, status_power, status_duration):
			var status_context: Dictionary = context.duplicate()
			status_context["applied_states"] = [status_id]
			player.loadout.event("status_applied", status_context)
	# A blocked hit cannot create a physical impact. Shield absorption is a
	# confirmed contact too, even when the target loses no health.
	if confirmed and target.is_alive() and push > 0.0:
		target.apply_knockback(direction, push * float(modifiers.get("knockback_scale", 1.0)))
	player.loadout.event("after_hit", context)
	player.combat_time = 5.0
	return confirmed

## V2 owns one transaction: preview X/P/B/C/K, receive a loss receipt, then
## consume class/status resources and dispatch native/equipment effects.
func _resolve_numerical_direct_hit(target: EnemyActor, amount: float, source: StringName, applied_status: String, push: float, direction: Vector2, attack_context: Dictionary) -> bool:
	if not is_finite(amount) or Numerical.integer(amount) <= 0:
		return false
	var context: Dictionary = attack_context.duplicate()
	var original: bool = source in [&"primary", &"q", &"secondary", &"f", &"ultimate", &"skill"] and int(context.get("proc_depth", 0)) == 0 and bool(context.get("equipment_eligible", true)) and bool(context.get("original", true))
	if not original:
		resolve_derived_hit(target, amount, source, direction, context)
		return bool(target.last_damage_result.get("confirmed", false))
	context["ruleset_version"] = Numerical.V2
	context["X"] = Numerical.integer(amount)
	context["H"] = Numerical.integer(float(context.get("power", player.basic_power() if source == &"primary" else player.skill_power())))
	context.merge({"target":target,"target_states":target.status.states.keys(),"damage_source":"primary" if source == &"primary" else "skill","skill_slot":str(context.get("skill_slot",source)),"proc_depth":0,"original_basic":source == &"primary","equipment_eligible":true}, true)
	if not context.has("attack_id"):
		attack_serial += 1
		context["attack_id"] = "direct:" + str(attack_serial)
	if str(context.get("root_event_id", "")).is_empty():
		context["root_event_id"] = context.attack_id
	if not context.has("damage_type"): context["damage_type"] = "magic" if player.hero_id() == "CH03" else "physical"
	if not context.has("attacker_stats"): context["attacker_stats"] = Game.run.stats.duplicate(true)
	var root_id: String = str(context.root_event_id)
	var native_statuses: Array = context.get("native_statuses", []).duplicate()
	if not applied_status.is_empty() and applied_status not in native_statuses:
		native_statuses.append(applied_status)
	context["native_statuses"] = native_statuses
	# Keep the pre-hit values even when this contact kills or grants a class shield.
	context["target_full_hp"] = target.health.current == target.health.maximum
	context["shield"] = Game.run.shield
	var modifiers: Dictionary = player.loadout.event("before_hit", context)
	if not crit_rolls.has(root_id):
		crit_rolls[root_id] = Crit.roll(run_seed, layout_id + ":" + root_id, Crit.chance(context.attacker_stats, float(modifiers.get("crit_bonus", 0.0)))) if Crit.enabled(context.attacker_stats) else randf() < clampf(player.stat("crit_chance", 0.05) + float(modifiers.get("crit_bonus", 0.0)), 0.0, 0.75)
		if not Crit.enabled(context.attacker_stats): _trim_root_history(crit_rolls)
	context["critical"] = bool(crit_rolls[root_id])
	var bonus: float = player.stat("damage_bonus", 0.0) + float(modifiers.get("damage_bonus", 0.0))
	if "corrosion" in context.target_states:
		bonus += 0.08 + player.stat("corrosion_damage_bonus", 0.0)
	var base: float = player.class_modify_hit_amount(target, float(context.X), source, context)
	var final_amount: int = Numerical.integer(base * (1.0 + clampf(bonus, 0.0, float(Numerical.value("caps").damage_bonus))) * ((Crit.multiplier(context.attacker_stats) if Crit.enabled(context.attacker_stats) else player.stat("crit_multiplier", 1.5)) if context.critical else 1.0) * player.hit_chain.multiplier(source, context))
	if Crit.enabled(context.get("attacker_stats", {})): context["already_critical"] = true
	target.take_damage(final_amount, source, direction, context)
	var receipt: Dictionary = target.last_damage_result.duplicate()
	if not bool(receipt.get("confirmed", false)):
		return false
	context.merge(receipt, true)
	native_statuses = _commit_numerical_native(context)
	# Consume the old charge before native/equipment applications can replace it.
	var shock: Variant = target.status.consume_shock()
	player.class_record_hit(target, source, context)
	if source == &"primary" and not primary_hit_roots.has(root_id):
		primary_hit_roots[root_id] = true
		_trim_root_history(primary_hit_roots)
		player.on_primary_hit(target)
	ClassRelics.on_original_hit(self, context)
	_confirm_contact(target, direction, source, bool(context.critical), float(context.hp_damage) + float(context.shield_damage), false, context)
	var target_id: int = target.get_instance_id()
	var injected: Dictionary = true_bonus_roots.get(root_id, {})
	var true_bonus: int = Numerical.integer(player.stat("true_damage_bonus", 0.0))
	if true_bonus > 0 and not injected.has(target_id):
		injected[target_id] = true
		true_bonus_roots[root_id] = injected
		_trim_root_history(true_bonus_roots)
		if target.is_alive():
			var true_context: Dictionary = context.duplicate()
			true_context.merge({"damage_source":"equipment","damage_type":"true","critical":false,"equipment_eligible":false,"original_basic":false,"proc_depth":1}, true)
			target.take_damage(true_bonus, &"equipment_true", direction, true_context)
	if target.is_alive() and shock > 0:
		target.take_damage(shock, &"shock", direction, {"ruleset_version":Numerical.V2,"damage_type":"magic","attacker_stats":context.attacker_stats,"equipment_eligible":false,"original_basic":false,"proc_depth":1,"critical":false})
		add_ring(target.position, Color("81d8e0"), 25.0, 0.2)
	for status_id: String in native_statuses:
		var status_power: Variant = context.H
		var status_duration: float = -1.0
		if status_id == ClassRelics.native_status(player.hero_id()) and source == &"primary" and Game.run.relics.has("ember"):
			var rank: int = int(Game.run.stats.get("relic_levels", {}).get("RL02", 1))
			status_power = ClassRelics.native_status_power(player.hero_id(), player.relic_power() if player.hero_id() == "CH03" else status_power, rank, Numerical.V2)
			status_duration = ClassRelics.native_status_duration(player.hero_id(), rank, self)
		if target.is_alive() and target.apply_status(status_id, status_power, status_duration):
			var status_context: Dictionary = context.duplicate()
			status_context["applied_states"] = [status_id]
			player.loadout.event("status_applied", status_context)
	if target.is_alive() and push > 0.0:
		target.apply_knockback(direction, push * float(modifiers.get("knockback_scale", 1.0)))
	player.loadout.event("after_hit", context)
	player.combat_time = 5.0
	return true

func _trim_root_history(history: Dictionary) -> void:
	while history.size() > 256:
		history.erase(history.keys()[0])

## Rejected contacts leave all four native/relic/equipment packet slots intact.
func _commit_numerical_native(context: Dictionary) -> Array:
	var accepted: Array = []
	var root_id: String = str(context.get("root_event_id", ""))
	if root_id.is_empty() or int(context.get("proc_depth", 0)) > 0 or not bool(context.get("equipment_eligible", false)):
		return accepted
	for packet_id: String in context.get("relic_reservations", []):
		player.loadout.effects.reserve_native(root_id, packet_id)
	for status_id: String in context.get("native_statuses", []):
		var packet_id: String = "relic:ember" if "relic:ember" in context.get("relic_reservations", []) and status_id == ClassRelics.native_status(player.hero_id()) else "native:" + status_id
		if player.loadout.effects.reserve_native(root_id, packet_id):
			accepted.append(status_id)
	return accepted

func resolve_derived_hit(target: EnemyActor, amount: float, source: StringName, direction: Vector2, attack_context: Dictionary = {}) -> void:
	if Game.run == null or not target.is_alive():
		return
	# Turrets/fields and child bolts keep their existing damage path. A visual
	# confirmation must never promote a derived packet into an equipment proc.
	var context: Dictionary = attack_context.duplicate()
	context.merge({"damage_source":str(source),"skill_slot":str(source),"equipment_eligible":false,"original_basic":false,"proc_depth":maxi(1,int(context.get("proc_depth",1)))},true)
	if Numerical.is_v2(Game.run.stats): context["critical"] = false
	if Crit.enabled(context.get("attacker_stats", {})) and bool(context.get("spell_critical_eligible", false)) and source in [&"field", &"node", &"node_detonation", &"node_echo", &"q"] and not bool(context.get("dot",false)):
		var root_id: String = str(context.get("root_event_id", context.get("crit_event_id", "")))
		if not root_id.is_empty():
			if not crit_rolls.has(root_id):
				crit_rolls[root_id] = Crit.roll(run_seed, layout_id + ":" + root_id, Crit.chance(context.attacker_stats))
			context["critical"] = bool(crit_rolls[root_id])
			context["already_critical"] = false
	var health_before: float = target.health.current
	var shield_before: float = target.status.shield()
	if Numerical.is_v2(Game.run.stats):
		amount = Numerical.integer(amount)
		context["ruleset_version"] = Numerical.V2
	target.take_damage(amount, source, direction, context)
	context["hp_damage"] = maxf(0.0, health_before - target.health.current)
	context["shield_damage"] = maxf(0.0, shield_before - target.status.shield())
	context["shield_broken"] = shield_before > 0.0 and target.status.shield() <= 0.0
	if Numerical.is_v2(Game.run.stats): context.merge(target.last_damage_result, true)
	var consumed: float = float(context.hp_damage) + float(context.shield_damage)
	if consumed > 0.0:
		_confirm_contact(target, direction, source, bool(context.get("critical",false)), consumed, source != &"node_detonation", context)

func _confirm_contact(target: EnemyActor, direction: Vector2, source: StringName, critical: bool, damage: float, passive: bool = false, context: Dictionary = {}) -> void:
	# This is reached only after HP or shield was actually consumed. Whiffs,
	# invulnerability and periodic status packets do not manufacture an impact.
	var hero: String = player.hero_id()
	# This is the skill's frozen origin category, never its current input slot.
	var contact_kind: StringName = StringName(str(context.get("skill_slot", context.get("origin_slot", str(source)))))
	var default_heavy: bool = str(contact_kind).contains("ultimate") or str(contact_kind).contains("secondary") or contact_kind in [&"circuit", &"node_detonation"] or (hero == "CH03" and contact_kind == &"f")
	# Explicit projectile tiers preserve the gunner's light-light-light-finisher rhythm.
	# This is presentation metadata only; damage and proc attribution are already settled.
	var heavy: bool = not passive and (critical or bool(context.get("heavy", default_heavy)))
	var material: String = target.impact_material()
	var forward: Vector2 = direction.normalized() if not direction.is_zero_approx() else (target.position-player.position).normalized()
	# One contact clock drives both bodies. A cluster can upgrade the weight,
	# while later recipients use the player's remaining pause without refreshing it.
	var pulse: bool = not passive and (elapsed >= _contact_pulse_until or (heavy and not _contact_pulse_heavy))
	if pulse:
		if elapsed >= _contact_pulse_until:
			_contact_pulse_until = elapsed + .055
		_contact_pulse_heavy = heavy
		var pause: float = (.074 if heavy else .042) if hero == "CH01" else (.030 if heavy else .015) if hero == "CH02" else (.038 if heavy else .024)
		if Numerical.is_v2(Game.run.stats):
			pause = (.065 if contact_kind == &"ultimate" else .055 if heavy else .025) if hero == "CH01" else (.035 if contact_kind == &"secondary" else .020 if heavy else .012) if hero == "CH02" else (.045 if contact_kind in [&"f", &"ultimate"] else .032 if heavy else .018)
		player.hit_feedback(minf(.085, pause + (.006 if critical else 0.0)))
	target.receive_confirmed_impact(forward, .28 if passive else 1.3 if heavy else .95 if hero == "CH01" else .65, heavy, hero, -1.0 if passive else player.visual_hitstop)
	var at: Vector2 = target.position + Vector2(0, target.body_bounds.end.y-target.body_bounds.size.y*.53)
	var event: Dictionary = {"hero_id":hero,"source":str(source),"heavy":heavy,"passive":passive,"critical":critical,"killed":not target.is_alive(),"material":material,"damage":damage,"anchor":weakref(target),"anchor_offset":at-target.position}
	event["basic_variant"] = int(context.get("basic_variant",0)) if source == &"primary" else 0
	event["hp_damage"] = float(context.get("hp_damage", damage))
	event["shield_damage"] = float(context.get("shield_damage", 0.0))
	event["shield_broken"] = bool(context.get("shield_broken", false))
	var surface: Dictionary = target.impact_anchor(forward)
	if not surface.is_empty():
		var visual: Node2D = surface.anchor.get_ref()
		if is_instance_valid(visual):
			event["visual_anchor"] = surface.anchor
			event["visual_offset"] = surface.local_offset
			at = to_local(visual.to_global(surface.local_offset))
	if is_instance_valid(impact_feedback):
		impact_feedback.confirm_hit(at, forward, event)
	var feedback: Node = player.get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.impact(at, forward, str(source), critical)
	if is_instance_valid(combat_audio):
		if float(event.shield_damage) > 0.0:
			# One clear membrane/crack sound, including a shield-breaking overflow.
			combat_audio.shield_contact(hero, bool(event.shield_broken), passive)
		else:
			combat_audio.impact(hero, heavy, material, passive)
	# One contact pulse per cluster, with separate per-target visual reactions.
	# Only presentation pauses; movement, dodge and damage timing stay responsive.
	if pulse:
		if is_instance_valid(camera):
			var kick: float = (3.1 if heavy else 1.75) if hero == "CH01" else (1.65 if heavy else .65) if hero == "CH02" else (2.1 if heavy else .95)
			camera.impact(kick, forward, heavy)

func resolve_melee_relics(target: EnemyActor, direction: Vector2) -> void:
	# Native relics were reserved and dispatched inside the shared attack root.
	telemetry.primary_hits += 1

func _prepare_relics(context: Dictionary, budget: int, arc_ready: bool) -> Dictionary:
	if Game.run == null or not Numerical.is_v2(Game.run.stats):
		return _reserve_relics(context, budget, arc_ready)
	# Preview packet availability without spending it on an immune contact.
	var effects: RefCounted = player.loadout.effects
	var prior_roots: Dictionary = effects.roots
	effects.roots = prior_roots.duplicate()
	var root_id: String = str(context.get("root_event_id", ""))
	if effects.roots.has(root_id): effects.roots[root_id] = effects.roots[root_id].duplicate(true)
	var reserved: Dictionary = _reserve_relics(context, budget, arc_ready)
	effects.roots = prior_roots
	var packets: Array[String] = []
	for channel: String in ["burn", "split", "arc"]:
		if reserved.has(channel): packets.append("relic:" + ("ember" if channel == "burn" else channel))
	context["relic_reservations"] = packets
	return reserved

func _reserve_relics(context: Dictionary, budget: int, arc_ready: bool) -> Dictionary:
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

func _emit_reserved_relics(reserved: Dictionary, context: Dictionary, at: Vector2, target: EnemyActor, direction: Vector2) -> void:
	if Game.run != null and Numerical.is_v2(Game.run.stats):
		reserved = reserved.duplicate()
		var committed: Dictionary = player.loadout.effects.roots.get(str(context.get("root_event_id", "")), {}).get("reserved", {})
		for channel: String in reserved.keys():
			if not bool(committed.get("relic:" + ("ember" if channel == "burn" else channel), false)):
				reserved.erase(channel)
	ClassRelics.apply_reserved(self, reserved, context, at, target, direction)

func spawn_ability_projectile(at: Vector2, direction: Vector2, amount: float, options: Dictionary) -> ProjectileActor:
	if Game.run == null:
		return null
	if bool(options.get("deployment_origin", false)) and not valid_ground(at, 2.0):
		return null
	if not bool(options.get("deployment_origin", false)) and str(options.get("source", "")) != "node" and not has_line_of_sight(player.position, at):
		at = player.position
	var projectile := spawn_projectile(at, direction, amount, StringName(options.get("source", "skill")))
	if projectile == null:
		return null
	projectile.options = options.duplicate()
	if bool(options.get("original",false)) and str(options.get("source","")) in ["q","secondary","f","ultimate","skill"]:
		projectile.options["visual_hero"] = player.hero_id()
	if not projectile.options.has("root_event_id"):
		attack_serial += 1
		projectile.options["root_event_id"] = "ability:" + str(attack_serial)
		projectile.options["attack_id"] = projectile.options.root_event_id
	projectile.speed = float(options.get("speed", 950.0))
	projectile.distance_left = float(options.get("range", 650.0))
	projectile.remaining = projectile.distance_left / projectile.speed + 0.1
	projectile.pierce_remaining = int(options.get("pierce", 0))
	if projectile.options.has("visual_hero"):
		var visual_muzzle: Vector2 = at if bool(options.get("deployment_origin", false)) else player.position+HeroVisual.release_muzzle_local(player.hero_id(),str(options.get("source","basic")),direction)
		if player.hero_id() == "CH03" and player.role_kit != null:
			var companion: Node2D = player.role_kit.get("companion")
			if is_instance_valid(companion): visual_muzzle = player.position+companion.position+direction.normalized()*12.0
		projectile.configure_player_visual(visual_muzzle)
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

func node_echo(origin: Vector2, reach: float, amount: float, _applied_status: String = "", hit_ids: Array = [], attack_context: Dictionary = {}) -> Array:
	var context: Dictionary = attack_context.duplicate(true)
	context.merge({"damage_type":"magic","equipment_eligible":false,"original_basic":false,"proc_depth":1},true)
	if not context.has("attacker_stats"): context["attacker_stats"] = Game.run.stats.duplicate(true)
	for deployment in get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.room != self or deployment.kind != "node" or not deployment.is_active() or deployment.position.distance_to(origin) > reach or not has_line_of_sight(origin, deployment.position):
			continue
		add_ring(deployment.position, Color("8bd0c8"), 70.0, 0.25)
		for target in targets_in_radius(deployment.position, 70.0):
			if target.get_instance_id() in hit_ids:
				continue
			hit_ids.append(target.get_instance_id())
			resolve_derived_hit(target, amount, &"node_echo", (target.position-deployment.position).normalized(), context)
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
	_draw_equipment_loot(canvas)
	for id: String in relic_positions:
		var at: Vector2 = relic_positions[id]
		if Game.run.relics.has(id) and player.position.distance_to(at) < 125.0 and has_line_of_sight(player.position, at):
			_draw_world_label(canvas, at+Vector2(0,46), "Equipped" if english else "已装配", false, Color("758b80"), "interaction")
	if selected.is_empty():
		return
	if not expedition_context.is_empty() and selected.kind != "buff":
		var focus_at: Vector2 = selected.get("position",exit_position)
		_draw_world_label(canvas,focus_at-Vector2(0,72),str(selected.get("label","继续远征")),true,Color("e2bd7e"),"loot" if selected.kind == "loot" else "exit" if selected.kind in ["next","early_extract","extract"] else "interaction")
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

func loot_position() -> Vector2:
	return clamp_actor(exit_position+Vector2(-180,55),28)

func _draw_equipment_loot(canvas: Node2D) -> void:
	if expedition_context.is_empty(): return
	var offers: Array = Game.pending_field_equipment()
	if offers.is_empty(): return
	var at := loot_position()
	var pulse := .85+.15*sin(float(Time.get_ticks_msec())*.003)
	canvas.draw_set_transform(at,0,Vector2(1,.46))
	canvas.draw_circle(Vector2.ZERO,49,Color(1,.78,.35,.15*pulse))
	canvas.draw_arc(Vector2.ZERO,42,0,TAU,48,Color("cc9e57"),2,true)
	canvas.draw_set_transform(Vector2.ZERO)
	for index: int in mini(offers.size(),3):
		var art: Texture2D = preload("res://scripts/infrastructure/assets/equipment_art.gd").texture(str(offers[index].equipment_id))
		if art == null: continue
		var extent := art.get_size()*minf(62.0/art.get_width(),62.0/art.get_height())
		var center := at+Vector2((index-mini(offers.size(),3)*.5+.5)*32,-25-index*6)
		canvas.draw_texture_rect(art,Rect2(center-extent*.5,extent),false)
	if player.position.distance_to(at) > Balance.INTERACTION_RADIUS:
		_draw_world_label(canvas,at+Vector2(0,32),("Loot ×%d" if Words.locale == "en" else "战利品 ×%d") % offers.size(),false,Color("e2bd7e"),"loot")

func _draw_world_label(canvas: Node2D, at: Vector2, label: String, actionable: bool, tint: Color, icon_key: String = "interaction") -> void:
	var font_size: int = 16
	var width: float = fx_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon: Texture2D = interaction_textures.get(icon_key)
	var icon_space: float = 32.0 if icon != null else 0.0
	var key: String = _interaction_key() if actionable else ""
	var key_width: float = maxf(20, fx_font.get_string_size(key,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+10)
	var lead: float = icon_space + (key_width+8.0 if actionable else 0.0)
	var start: Vector2 = at - Vector2((width + lead) * .5,0)
	var label_tint := Color("392447") if actionable else Color("706579")
	var panel_rect := Rect2(start+Vector2(-6,-23),Vector2(width+lead+12.0,32))
	canvas.draw_rect(panel_rect,Color("fff0d2"))
	canvas.draw_rect(panel_rect,Color("ae8748"),false,1.2)
	if icon != null:
		var source_size: Vector2 = icon.get_size()
		var image_scale: float = minf(26.0/source_size.x,26.0/source_size.y)
		var extent: Vector2 = source_size * image_scale
		var icon_at: Vector2 = start + Vector2(0,-20) + (Vector2(26,26)-extent)*0.5
		canvas.draw_texture_rect(icon,Rect2(icon_at,extent),false)
		start.x += icon_space
	if actionable:
		canvas.draw_rect(Rect2(start+Vector2(0,-15),Vector2(key_width,20)),Color("392447"))
		canvas.draw_rect(Rect2(start+Vector2(0,-15),Vector2(key_width,20)),tint,false,1.2)
		canvas.draw_string(fx_font,start+Vector2(5,0),key,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff0d2"))
		start.x += key_width+8.0
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
	if is_instance_valid(circuit): circuit.reset_room()
	if is_instance_valid(defeat_feedback): defeat_feedback.clear_feedback()
	if is_instance_valid(skill_input_feedback): skill_input_feedback.clear_feedback()
	if is_instance_valid(enemy_telegraphs): enemy_telegraphs.clear()
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
	_enemy_visual_counts.clear()
	_enemy_visual_room_key = ""
	layout = next
	_configure_ground_boundary()
	obstructions.assign(next.obstructions)
	_navigation_cache.prepare(obstructions, ARENA, [12.0,14.0,18.0,24.0], ground_polygon)
	exit_position = next.exit
	encounter_zones = next.get("encounter_zones", []).duplicate(true)
	activated_encounters.clear()
	encounter_progress.clear()
	_encounter_spawn_retry.clear()
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
		player.passives.reset()
		player.position = next.entry
		player.loadout.event("room_enter", {"room_id":layout_id,"unvisited":true})
		gold_drops.clear()
		_configure_world_view()
	configuration_ready = true
	configuration_error = ""
	queue_redraw()
	_refresh_terrain_canvas()
	return true

func _encounters_exhausted() -> bool:
	return _encounters_service._encounters_exhausted()

func _encounter_plan(index: int) -> Dictionary:
	return _encounters_service._encounter_plan(index)

func _objective_encounters_pending() -> bool:
	# B05 objectives describe mechanisms; its ordinary finite zones still
	# require traversal/clearance even when no extra objective task is pending.
	if bool(layout.get("b06_candidate",false)) or str(expedition_context.get("biome_id",""))=="B05": return not _encounters_exhausted()
	if not is_instance_valid(objectives):
		return false
	for index in encounter_zones.size():
		if objectives.encounter_directive(index).is_empty():
			continue
		if not activated_encounters.has(index):
			return true
		var progress: Dictionary = encounter_progress.get(index,{})
		if progress.is_empty() or int(progress.next_wave) < progress.plan.waves.size():
			return true
	return false

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
	return _encounters_service._spawn_encounter_wave(index, definitions)

func _escort_spawn_candidates(directive: Dictionary, definitions: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not directive.has("position") or not directive.has("destination"):
		return result
	var radius: float = 24.0
	for definition: Dictionary in definitions:
		radius = maxf(radius, float(definition.navigation_radius))
	var cursor: Vector2 = directive.position
	var destination: Vector2 = directive.destination
	# Sample one bounded stretch of the actual navigable path. Offsets are
	# swept from that path, so a nearby point across a pit is never preferred.
	for step in 24:
		if cursor.distance_to(destination) <= 12.0:
			break
		var direction: Vector2 = navigation_direction(cursor,destination,radius)
		var next: Vector2 = move_actor(cursor,direction*minf(48.0,cursor.distance_to(destination)),radius)
		if next.distance_to(cursor) < 1.0:
			break
		cursor = next
		result.append(cursor)
		for side: float in [-1.0,1.0]:
			result.append(move_actor(cursor,direction.orthogonal()*side*(radius*2.0+12.0),radius))
	return result

func _encounter_spawn_clear(at: Vector2, radius: float, safe_distance: float, planned: Array[Vector2], radii: Array[float]) -> bool:
	return _encounters_service._encounter_spawn_clear(at, radius, safe_distance, planned, radii)

func _update_encounters(delta: float = 0.0) -> void:
	if get_tree().paused:
		return
	if not _encounter_spawn_retry.is_empty():
		var geometry: int = hash(obstructions)
		for index in _encounter_spawn_retry.keys():
			var retry: Dictionary = _encounter_spawn_retry[index]
			retry.remaining = float(retry.remaining)-maxf(0.0,delta) if is_finite(delta) else float(retry.remaining)
			# A changed bridge/obstacle can make placement valid immediately. Only
			# unchanged failures are throttled; the normal reinforcement timer stays.
			if int(retry.geometry) != geometry or float(retry.remaining) <= .00001:
				_encounter_spawn_retry.erase(index)
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
		var directive: Dictionary = objectives.encounter_directive(index) if is_instance_valid(objectives) else {}
		if not directive.is_empty():
			if not bool(directive.get("ready",false)) or activated_encounters.size() < index:
				continue
		elif player.position.distance_to(zone.center) > float(zone.get("activation_distance",520)):
			continue
		var plan: Dictionary = _encounter_plan(index)
		if plan.is_empty() or plan.waves.is_empty() or not _can_spawn_encounter_wave(index,plan.waves[0],float(plan.get("concurrent_threat_budget",18))) or not _spawn_encounter_wave(index,plan.waves[0]):
			return
		if is_instance_valid(b05_mechanics): b05_mechanics.encounter_started(index)
		activated_encounters[index] = true
		encounter_progress[index] = {"plan":plan,"next_wave":1,"reinforce_elapsed":0.0}
		wave = activated_encounters.size()
		break

func navigation_target() -> Dictionary:
	return _navigation_service.navigation_target()

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
	elif bool(context.get("b06_candidate",false)) and str(context.get("biome_id","")) == "B06":
		next = preload("res://scripts/levels/b06/world/room_layouts.gd").build(id,seed_value)
	elif role == "boss":
		var script_path: String = "res://scripts/domain/world/boss_layouts.gd"
		if ResourceLoader.exists(AssetCatalog.resolve(script_path)) and ResourceLoader.exists(AssetCatalog.resolve("res://scripts/gameplay/bosses/boss_actor.gd")):
			next = load(AssetCatalog.resolve(script_path)).build(id,seed_value)
	else:
		next = Generator.generate(id,seed_value) if use_generated_layout else Layouts.build(id)
	if next.is_empty() or not next.has("entry") or not next.has("exit"):
		return {"valid":false,"error":"房间布局未能加载："+id}
	var props: Node2D = PropsScript.new()
	if role not in ["entrance","supply"]:
		if not props.configure(self,next):
			var error: String = "; ".join(props.configuration_errors)
			props.free()
			return {"valid":false,"error":error}
	else:
		props.room = self
		props.layout = next.duplicate(true)
		props.room_id = id
		props.biome_id = str(context.get("biome_id","B01"))
		props.obstacle_recipes = preload("res://scripts/presentation/world/room_appearance.gd").recipe(next,props.biome_id)
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
	_release_b06_environment()
	if is_instance_valid(b06_mechanics): b06_mechanics.free()
	b06_mechanics = null
	if is_instance_valid(b05_mechanics): b05_mechanics.free()
	b05_mechanics = null
	if is_instance_valid(circuit): circuit.reset_room()
	ClassRelics.reset_room(self)
	if is_instance_valid(circuit_training): circuit_training.free()
	circuit_training = null
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
	_enemy_visual_counts.clear()
	_enemy_visual_room_key = ""
	_configure_ground_boundary()
	difficulty = clampi(int(expedition_context.get("difficulty",0)),0,4)
	layout_seed = int(expedition_context.get("seed",41827))
	run_seed = layout_seed
	obstructions.assign(layout.get("obstructions",[]))
	_navigation_cache.prepare(obstructions, ARENA, [12.0,14.0,18.0,24.0], ground_polygon)
	exit_position = layout.exit
	encounter_zones = layout.get("encounter_zones",[]).duplicate(true)
	activated_encounters.clear()
	encounter_progress.clear()
	_encounter_spawn_retry.clear()
	enemy_corpses.clear()
	gold_drops.clear()
	effects.clear()
	if is_instance_valid(impact_feedback): impact_feedback.clear_feedback()
	if is_instance_valid(defeat_feedback): defeat_feedback.clear_feedback()
	if is_instance_valid(skill_input_feedback): skill_input_feedback.clear_feedback()
	if is_instance_valid(enemy_telegraphs): enemy_telegraphs.clear()
	_contact_pulse_until = -1.0
	_contact_pulse_heavy = false
	crit_rolls.clear()
	true_bonus_roots.clear()
	primary_hit_roots.clear()
	relic_positions.clear()
	wave = 0
	objective_wave_count = encounter_zones.size()
	objective_complete = false
	objective_rewarded = false
	_completion_emitted = false
	_boss_actor = null
	_boss_defeated = false
	_node_loot_spawned = 0
	_natural_spawn_serial = 0
	_expedition_ready = false
	progress_retry_timer = 0
	enemy_props = prepared.props
	enemy_props.name = "RoomProps"
	add_child(enemy_props)
	spawn_enabled = str(expedition_context.get("role","")) not in ["entrance","supply","boss"]
	if is_instance_valid(player):
		player.cancel_actions()
		player.passives.reset()
		player.position = layout.entry
		_previous_player_position = player.position
		_configure_world_view()
	else:
		_expedition_restore = Game.expedition_snapshot().get("runtime",{}).duplicate(true)
	configuration_ready = true
	configuration_error = ""
	queue_redraw()
	_refresh_terrain_canvas()

func _activate_expedition_content() -> void:
	if bool(layout.get("b06_candidate",false)) and not is_instance_valid(b06_mechanics):
		b06_mechanics = preload("res://scripts/levels/b06/world/tide_runtime.gd").new()
		add_child(b06_mechanics)
		if not b06_mechanics.configure(layout_id,difficulty,enemy_calibration()):
			configuration_error = "B06 tide configuration rejected"
			return
		b06_mechanics.load_candidate_art()
	_configure_b06_environment()
	if str(layout.get("biome_id","")) == "B05" and not is_instance_valid(b05_mechanics):
		b05_mechanics = preload("res://scripts/levels/b05/world/room_mechanisms.gd").new()
		add_child(b05_mechanics)
		if not b05_mechanics.configure_room(self,layout.get("b05_geometry",{}),difficulty):
			configuration_error = "B05 mechanism configuration rejected"
			return
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
		if layout_id in ["L01", "L11"]:
			var claimed: Array[String] = []
			for receipt: Dictionary in state.get("optional_claims", {}).values():
				if int(receipt.node_index) == int(state.node_index): claimed.append(str(receipt.objective_id))
			objectives = load(AssetCatalog.resolve("res://scripts/gameplay/world/room_objectives.gd")).new()
			objectives.name = "RoomObjectives"
			add_child(objectives)
			objectives.configure_cleared(self, layout, role, claimed)
			objectives.set_process(false)
	elif role in ["entrance","supply"]:
		objective_complete = true
		objective_rewarded = true
	elif role == "boss":
		var boss_script: String = "res://scripts/gameplay/bosses/boss_actor.gd"
		if ResourceLoader.exists(AssetCatalog.resolve(boss_script)):
			var boss: Node2D = load(AssetCatalog.resolve(boss_script)).new()
			boss.room = self
			boss.position = layout.get("boss_spawn",Vector2(1800,900))
			if bool(layout.get("b06_candidate",false)) and layout_id == "BO06":
				boss.configure(preload("res://scripts/levels/b06/combat/enemy_skills.gd").boss_profile(difficulty),{"reward_enabled":false,"actor_kind":"boss"})
			else:
				boss.configure_boss(layout_id,difficulty,0,enemy_ruleset(),enemy_calibration())
			boss.completed.connect(func(_id: String,_payload: Dictionary) -> void: _boss_defeated = true)
			_boss_actor = boss
			enemies.add_child(boss)
			if bool(layout.get("b06_candidate",false)):
				b06_mechanics.bind_boss(boss)
				objectives = load(AssetCatalog.resolve("res://scripts/gameplay/world/room_objectives.gd")).new()
				add_child(objectives)
				objectives.configure(self,layout,role)
			else:
				objectives = load(AssetCatalog.resolve("res://scripts/gameplay/world/boss_arena.gd")).new()
				add_child(objectives)
				objectives.configure_boss_arena(self,layout,boss)
	else:
		objectives = load(AssetCatalog.resolve("res://scripts/gameplay/world/room_objectives.gd")).new()
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
			if not task_done or _objective_encounters_pending(): _update_encounters(delta)
			objective_complete = task_done and _living_enemy_count() == 0 and not _objective_encounters_pending()
	if bool(layout.get("b06_candidate",false)) and not bool(expedition_context.get("b06_progression",false)):
		# Preview traversal has no persistent progression or economic settlement.
		if objective_complete and not _completion_emitted:
			_completion_emitted = true
			room_completed.emit()
		return
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
	var event_id: String = Game.run.id+":node:"+str(int(expedition_context.node_index))+":complete"
	var quality: String = str(objectives.status().get("quality","full")) if is_instance_valid(objectives) else "full"
	var bosses: Array = Game.profile.bosses.duplicate()
	for boss_id: String in Game.run.boss_defeats:
		if not bosses.has(boss_id): bosses.append(boss_id)
	var rewards: Dictionary = RoomRewards.build(layout_id, quality, player.hero_id(), layout_seed, event_id, Game.reward_discovery_ids(), Game.run.expedition.pending_equipment.keys(), bosses, difficulty, int(Game.run.expedition.get("reward_policy_version", 0)))
	if rewards.is_empty():
		configuration_error = "Invalid reward outcome: " + layout_id + "/" + quality
		return
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
	var path: String = "res://scripts/domain/combat/combat_snapshot.gd"
	return load(AssetCatalog.resolve(path)).capture(self) if ResourceLoader.exists(AssetCatalog.resolve(path)) else {}

func restore_expedition_runtime(runtime: Dictionary) -> bool:
	if runtime.is_empty(): return false
	if not is_instance_valid(player):
		_expedition_restore = runtime.duplicate(true)
		return true
	var path: String = "res://scripts/domain/combat/combat_snapshot.gd"
	return bool(load(AssetCatalog.resolve(path)).restore_room_entry(self,runtime)) if ResourceLoader.exists(AssetCatalog.resolve(path)) else false

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
				spawn_enemy(at,str(member.get("enemy_id","")),_boss_actor.enemy_level if enemy_ruleset() == Numerical.V2 else int(member.get("level",1))+difficulty*2,_boss_actor.reinforcement_spawn_options())

func on_objective_event(_kind: String, _data: Dictionary) -> void:
	queue_redraw()

func claim_optional_objective_reward(id: String) -> bool:
	if not objective_rewarded or Game.run == null or expedition_context.is_empty() or not is_instance_valid(objectives): return false
	if RoomRewards.optional_definition(layout_id, id).is_empty(): return false
	var item: Dictionary = objectives.element(id)
	if item.is_empty() or not bool(item.get("optional_reward", false)) or bool(item.get("sealed", false)): return false
	var at: Vector2 = item.get("interaction_position", item.position)
	if player.position.distance_to(at) > 100.0 or not has_line_of_sight(player.position, at): return false
	var state: Dictionary = Game.expedition_snapshot()
	var success: bool = Game.claim_expedition_optional_reward(int(expedition_context.node_index), id, expedition_runtime_snapshot(), str(state.get("checkpoint_id", "")))
	if success:
		add_ring(at, Color("b9de91"), 35.0, .32)
		if is_instance_valid(combat_audio): combat_audio.pickup()
	return success

func skill_archive() -> Dictionary:
	if Game.run == null or expedition_context.is_empty(): return {}
	var archive: Dictionary = layout.get("fixed_room", {}).get("skill_archive", {})
	if archive.is_empty() or Game.skill_group_learned(str(archive.get("group_id", ""))): return {}
	var coordinates: Array = archive.get("position", [])
	if coordinates.size() != 2: return {}
	var at: Vector2 = Vector2(float(coordinates[0]), float(coordinates[1])) * preload("res://scripts/domain/world/fixed_room_layouts.gd").PLAYFIELD_SCALE
	if not valid_ground(at, 18.0): return {}
	return {"group_id":str(archive.group_id),"position":at}

func _service_layout(context: Dictionary) -> Dictionary:
	var scale: float = preload("res://scripts/domain/world/fixed_room_layouts.gd").PLAYFIELD_SCALE
	var service_arena := Rect2(DEFAULT_ARENA.position*scale, DEFAULT_ARENA.size*scale)
	return {"room_id":str(context.room_id),"seed":int(context.get("seed",0)),"arena":service_arena,"painted_service":true,"entry":Vector2(960,900)*scale,"exit":Vector2(1760,900)*scale,"service_position":Vector2(1260,900)*scale,"obstructions":[],"static_obstructions":[],"static_obstruction_kinds":[],"prop_instances":[],"spawn_points":[],"objective_points":[],"encounter_zones":[],"interactables":[],"hazard_zones":[],"visual_markers":[],"topology_probes":[]}
