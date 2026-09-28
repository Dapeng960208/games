class_name MineRoom
extends Node2D

signal interaction_requested(kind: String, payload: Dictionary)
signal hint_changed(key: String, data: Dictionary)

const PlayerScene = preload("res://scenes/player.tscn")
const EnemyScene = preload("res://scenes/enemy.tscn")
const ProjectileScene = preload("res://scenes/projectile.tscn")
const ARENA := Rect2(48, 106, 1184, 488)
const EXIT_POSITION := Vector2(140, 360)
const RELIC_POSITIONS := {"split": Vector2(400,220), "ember": Vector2(640,220), "arc": Vector2(880,220)}

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

func _ready() -> void:
	player = PlayerScene.instantiate()
	player.room = self
	player.position = Vector2(250,360)
	add_child(player)
	player.z_index = 2
	fx_font = ThemeDB.fallback_font
	for id in RELIC_POSITIONS:
		var asset_path: String = "res://assets/ui/relic_" + id + ".png"
		if ResourceLoader.exists(asset_path):
			relic_textures[id] = load(asset_path)
	for at in [Vector2(760,400),Vector2(910,350),Vector2(1020,415),Vector2(1010,290)]:
		spawn_enemy(at)
	set_input_blocked(false)

func controls_enabled() -> bool:
	return not input_blocked and not release_gate and Game.run != null and not get_tree().paused

func set_input_blocked(blocked: bool) -> void:
	input_blocked = blocked
	release_gate = true

func _physics_process(delta: float) -> void:
	if Game.run == null:
		return
	elapsed += delta
	if release_gate and not input_blocked:
		if not Input.is_action_pressed("attack") and not Input.is_action_pressed("dash") and not Input.is_action_pressed("interact"):
			release_gate = false
	elif controls_enabled() and Input.is_action_just_pressed("interact"):
		interact()
		if get_tree().paused or input_blocked:
			return
	if spawn_enabled:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer += Balance.ENEMY_SPAWN_INTERVAL
			_spawn_wave()
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

func spawn_enemy(at: Vector2) -> MineEnemy:
	if enemies.get_child_count() >= Balance.MAX_ENEMIES:
		return null
	var enemy: MineEnemy = EnemyScene.instantiate()
	enemy.room = self
	enemy.position = clamp_actor(at, Balance.ENEMY_RADIUS)
	enemies.add_child(enemy)
	return enemy

func _spawn_wave() -> void:
	wave += 1
	var entrances := [Vector2(1150,190),Vector2(1145,510),Vector2(760,540),Vector2(680,145)]
	for i in range(mini(Balance.WAVE_BASE_COUNT + wave / Balance.WAVE_GROWTH_EVERY, Balance.WAVE_MAX_COUNT)):
		var at: Vector2 = entrances[(wave + i) % entrances.size()] + Vector2(i * 30,0)
		if at.distance_to(player.position) < Balance.ENEMY_SPAWN_SAFE_DISTANCE:
			at = Vector2(1150,360) if player.position.x < 650 else Vector2(400,500)
		spawn_enemy(at)

func fire_from_player(direction: Vector2) -> bool:
	if Game.run == null or projectiles.get_child_count() >= Balance.MAX_PROJECTILES:
		return false
	Game.run.shots += 1
	telemetry["shots"] += 1
	var projectile := spawn_projectile(player.position + direction * 30.0, direction, Balance.SHOT_DAMAGE, &"primary")
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
	projectile.ignored_enemy = ignore_id
	projectiles.add_child(projectile)
	return projectile

func resolve_weapon_hit(projectile: SparkProjectile, target: MineEnemy) -> void:
	if Game.run == null or not target.is_alive():
		return
	# Only weapon projectiles enter this function. Burn / arc call health directly.
	if projectile.source not in [&"primary", &"child"]:
		return
	var relics: Array = Game.run.relics.duplicate()
	var hit_position := target.position
	var is_primary := projectile.source == &"primary"
	telemetry["primary_hits" if is_primary else "child_hits"] += 1
	target.take_damage(projectile.damage, projectile.source, projectile.direction)
	add_ring(projectile.position, Color("f0c77f"), 16.0, 0.15)
	var budget := projectile.trigger_budget
	if relics.has("ember") and budget > 0:
		budget -= 1
		target.apply_burn()
	if is_primary and relics.has("split") and budget > 0:
		budget -= 1
		for side in [-1.0, 1.0]:
			var direction := projectile.direction.rotated(side * Balance.SPLIT_ANGLE)
			var child := spawn_projectile(hit_position + direction * 22, direction, Balance.SHOT_DAMAGE * Balance.SPLIT_RATIO, &"child", target.get_instance_id())
			if child != null:
				child.trigger_budget = mini(1, budget)
				telemetry["split_spawned"] += 1
	if is_primary and projectile.arc_ready and relics.has("arc") and budget > 0:
		_trigger_arc(hit_position, target)

func _trigger_arc(origin: Vector2, excluded: MineEnemy) -> void:
	var candidates: Array[MineEnemy] = []
	for candidate in enemies.get_children():
		if candidate != excluded and candidate.is_alive() and candidate.position.distance_to(origin) <= Balance.ARC_RANGE:
			candidates.append(candidate)
	candidates.sort_custom(func(a: MineEnemy, b: MineEnemy) -> bool: return a.position.distance_squared_to(origin) < b.position.distance_squared_to(origin))
	for i in range(mini(candidates.size(), Balance.ARC_TARGETS)):
		var target := candidates[i]
		_add_effect({"kind":&"arc","from":origin,"to":target.position,"remaining":0.24,"duration":0.24})
		target.take_damage(Balance.SHOT_DAMAGE * Balance.ARC_RATIO, &"arc")
		telemetry["arc_hits"] += 1

func enemy_died(enemy: MineEnemy) -> void:
	if Game.run == null:
		return
	telemetry["kills"] += 1
	Game.record_kill()
	gold_drops.append({"at":enemy.position,"amount":Balance.GOLD_PER_ENEMY,"age":0.0})
	add_ring(enemy.position, Color("e6aa4a"), 35.0, 0.35)

func _update_gold(delta: float) -> void:
	for i in range(gold_drops.size() - 1, -1, -1):
		var drop: Dictionary = gold_drops[i]
		drop["age"] += delta
		var offset: Vector2 = player.position - drop["at"]
		if offset.length() <= Balance.GOLD_PICKUP_RADIUS:
			if Game.add_gold(drop["amount"]):
				telemetry["gold_collected"] += drop["amount"]
				add_ring(drop["at"], Color("e6aa4a"), 21.0, 0.2)
				gold_drops.remove_at(i)
		elif offset.length() <= Balance.GOLD_ATTRACT_RADIUS:
			drop["at"] = drop["at"].move_toward(player.position, Balance.GOLD_ATTRACT_SPEED * delta)

func nearby_interaction() -> Dictionary:
	if Game.run == null or player == null:
		return {}
	if player.position.distance_to(EXIT_POSITION) <= Balance.INTERACTION_RADIUS:
		return {"kind":"extract"}
	for id in RELIC_POSITIONS:
		if not Game.run.relics.has(id) and player.position.distance_to(RELIC_POSITIONS[id]) <= Balance.INTERACTION_RADIUS:
			return {"kind":"relic","id":id}
	return {}

func interaction_hint() -> String:
	var nearby := nearby_interaction()
	if nearby.is_empty():
		return ""
	if nearby["kind"] == "extract":
		return tr("INTERACT_EXTRACT")
	var id: String = nearby["id"]
	return tr("INTERACT_RELIC").format({"name":tr("RELIC_" + id.to_upper() + "_NAME")})

func interact() -> void:
	if not controls_enabled():
		return
	var nearby := nearby_interaction()
	if nearby.is_empty():
		return
	if nearby["kind"] == "extract":
		set_input_blocked(true)
		interaction_requested.emit("extract", {})
	else:
		var id: String = nearby["id"]
		if Game.equip_relic(id):
			add_ring(RELIC_POSITIONS[id], Color("67c7d5"), 64.0, 0.65)

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
	_draw_exit()
	for id in RELIC_POSITIONS:
		_draw_relic(id, RELIC_POSITIONS[id])
	for drop in gold_drops:
		var at: Vector2 = drop["at"]
		draw_circle(at, 12, Color(0.9,0.66,0.29,0.1))
		draw_colored_polygon(PackedVector2Array([at+Vector2(-5,0),at+Vector2(0,-6),at+Vector2(6,-2),at+Vector2(4,5),at+Vector2(-4,5)]),Color("e6aa4a"))
		draw_line(at+Vector2(-3,0),at+Vector2(3,-2),Color("fff0b5"),1.5)
	for effect in effects:
		var alpha: float = effect["remaining"] / effect["duration"]
		match effect["kind"]:
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
	var at := EXIT_POSITION
	var nearby := player != null and player.position.distance_to(at) <= Balance.INTERACTION_RADIUS
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
	var nearby: bool = player != null and player.position.distance_to(at) <= Balance.INTERACTION_RADIUS
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
