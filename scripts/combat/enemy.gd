class_name MineEnemy
extends CharacterBody2D

const HealthScript = preload("res://scripts/combat/health.gd")
const StatusScript = preload("res://scripts/combat/combat_status.gd")
const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const BrainScript = preload("res://scripts/combat/enemy_brain.gd")
const ImageBounds = preload("res://scripts/combat/hero_visual.gd")
static var _body_regions: Dictionary = {}
var room: Node2D
var health: CombatHealth
var state: StringName = &"emerging"
var state_time: float = Balance.ENEMY_SPAWN_GRACE
var aim_direction := Vector2.LEFT
var knockback := Vector2.ZERO
var hurt_flash: float = 0.0
var burn_remaining: float = 0.0
var burn_tick: float = 0.0
var lifetime: float = 0.0
var body_texture: Texture2D
var empty_body_texture: Texture2D
var body_region := Rect2()
var body_bounds := Rect2(-43,-48,86,86)
var status_textures: Dictionary = {}
var status: CombatStatus = StatusScript.new()
var rank: String = "normal"
var armor: float = 0.0
var reaction_cooldown: float = 0.0
var reaction_remaining: float = 0.0
var navigation_timer: float = 0.0
var navigation_vector := Vector2.ZERO
var last_damage_context: Dictionary = {}
var profile: Dictionary = {}
var brain: RefCounted
var enemy_id: String = ""
var enemy_level: int = 1
var navigation_radius: float = Balance.ENEMY_RADIUS
var move_speed: float = Balance.ENEMY_SPEED
var attack_range: float = Balance.ENEMY_RANGE
var contact_damage: float = Balance.ENEMY_DAMAGE
var actor_kind: String = "enemy"
var static_actor: bool = false
var reward_enabled: bool = true
var zone_index: int = -1
var threat_cost: float = 1.0
var owner_enemy: WeakRef
var training_ai_disabled: bool = false

func configure(next_profile: Dictionary, options: Dictionary = {}) -> void:
	profile = next_profile.duplicate(true)
	enemy_id = str(profile.get("enemy_id", ""))
	enemy_level = int(profile.get("enemy_level", 1))
	navigation_radius = float(profile.get("navigation_radius", Balance.ENEMY_RADIUS))
	move_speed = float(profile.get("move_speed", Balance.ENEMY_SPEED))
	attack_range = float(profile.get("attack_range", Balance.ENEMY_RANGE))
	contact_damage = float(profile.get("damage", Balance.ENEMY_DAMAGE))
	armor = float(profile.get("armor", 0.0))
	rank = str(profile.get("rank", "normal"))
	zone_index = int(options.get("zone_index", profile.get("zone_index", -1)))
	threat_cost = float(profile.get("effective_threat_cost", 1.0))
	reward_enabled = bool(options.get("reward_enabled", true))
	static_actor = bool(options.get("static_actor", false))
	actor_kind = str(options.get("actor_kind", "enemy"))
	if is_instance_valid(options.get("owner", null)):
		owner_enemy = weakref(options.owner)
	if static_actor:
		set_meta("enemy_skill_anchor", true)

func cast_enemy_skill(skill: Dictionary) -> void:
	if room.enemy_skills != null and is_alive():
		room.enemy_skills.emit_skill(self, skill)

func _exit_tree() -> void:
	if is_instance_valid(room) and is_instance_valid(room.enemy_skills):
		room.enemy_skills.cancel_owner(self)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body_texture = TextureSampler.sampled("res://assets/characters/rust_mite.png")
	if not enemy_id.is_empty():
		var generated_path: String = "res://assets/generated/enemies/" + enemy_id + "_v1.png"
		if FileAccess.file_exists(generated_path) or ResourceLoader.exists(generated_path):
			body_texture = TextureSampler.sampled(generated_path)
			if not _body_regions.has(generated_path):
				_body_regions[generated_path] = ImageBounds._visible_region(body_texture.get_image())
			body_region = _body_regions[generated_path]
			var height: float = clampf(navigation_radius*3.8,66.0,88.0)
			var width: float = body_region.size.x / maxf(1.0,body_region.size.y) * height
			body_bounds = Rect2(-width*.5,18.0-height,width,height)
		if enemy_id == "M35":
			empty_body_texture = TextureSampler.sampled("res://assets/generated/enemies/M35_empty_v1.png")
	if static_actor:
		body_texture = null
	for id: String in ["burn", "shock", "chill", "corrosion"]:
		status_textures[id] = TextureSampler.sampled("res://assets/generated/ui/state_" + id + "_v1.png")
	health = HealthScript.new()
	add_child(health)
	health.reset(float(profile.get("max_hp", Balance.ENEMY_HP)))
	health.depleted.connect(_die)
	if not profile.is_empty() and not static_actor:
		brain = BrainScript.new()
		brain.configure(profile)

func is_alive() -> bool:
	return health != null and not health.dead

func visible_status_ids() -> Array[String]:
	var active: Array[String] = []
	for id: String in ["burn", "shock", "chill", "corrosion"]:
		if status.has(id):
			active.append(id)
	return active

func _physics_process(delta: float) -> void:
	if not is_alive() or Game.run == null:
		return
	if owner_enemy != null:
		var owner_actor: Node2D = owner_enemy.get_ref()
		if not is_instance_valid(owner_actor) or not owner_actor.is_alive():
			queue_free()
			return
	lifetime += delta
	hurt_flash = maxf(0.0, hurt_flash - delta)
	tick_statuses(delta)
	if not is_alive():
		return
	if static_actor:
		queue_redraw()
		return
	var victim: Node2D = room.player
	for deployment in get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.room == room and deployment.kind == "node" and deployment.is_alive() and position.distance_to(deployment.position) < position.distance_to(victim.position) and room.has_line_of_sight(position, deployment.position):
			victim = deployment
	var offset: Vector2 = victim.position - position
	var distance := offset.length()
	reaction_cooldown = maxf(0.0, reaction_cooldown - delta)
	reaction_remaining = maxf(0.0, reaction_remaining - delta)
	navigation_timer -= delta
	velocity = Vector2.ZERO
	if training_ai_disabled:
		_finish_motion(delta)
		return
	if brain != null:
		brain.tick(self, delta, victim)
		if state == &"chase":
			velocity += _separation()
		if status.has("chill"):
			velocity *= 0.9 if rank == "boss" else 0.8
		_finish_motion(delta)
		return
	state_time -= delta
	match state:
		&"emerging":
			if state_time <= 0.0:
				state = &"chase"
		&"chase":
			if distance > 0.1:
				aim_direction = offset / distance
			if distance <= Balance.ENEMY_RANGE + Balance.PLAYER_RADIUS and room.has_line_of_sight(position, victim.position):
				state = &"windup"
				state_time = Balance.ENEMY_WINDUP
			else:
				if navigation_timer <= 0.0:
					navigation_vector = room.navigation_direction(position, victim.position, navigation_radius)
					navigation_timer = 0.18
				velocity = navigation_vector * Balance.ENEMY_SPEED + _separation()
				if status.has("chill"):
					velocity *= 0.9 if rank == "boss" else 0.8
		&"windup":
			if state_time <= 0.0:
				state = &"recovery"
				state_time = Balance.ENEMY_RECOVERY
				room.add_slash(position, aim_direction)
				if distance <= Balance.ENEMY_RANGE + Balance.PLAYER_RADIUS and offset.normalized().dot(aim_direction) > 0.35 and room.has_line_of_sight(position, victim.position):
					victim.receive_damage(Balance.ENEMY_DAMAGE, position)
		&"recovery":
			if state_time <= 0.0:
				state = &"chase"
	_finish_motion(delta)

func _finish_motion(delta: float) -> void:
	if room.enemy_skills != null:
		velocity *= room.enemy_skills.movement_multiplier(self)
	velocity += knockback
	if reaction_remaining > 0.0:
		velocity = knockback
	knockback = knockback.move_toward(Vector2.ZERO, Balance.ENEMY_KNOCKBACK_DECAY * delta)
	position = room.move_actor(position, velocity * delta, navigation_radius)
	queue_redraw()

func _separation() -> Vector2:
	var force := Vector2.ZERO
	for other in room.enemies.get_children():
		if other == self or not other.is_alive() or other.static_actor:
			continue
		var offset: Vector2 = position - other.position
		var distance := offset.length()
		var spacing: float = maxf(Balance.ENEMY_SEPARATION_DISTANCE, navigation_radius + other.navigation_radius + 4.0)
		if distance > 0.01 and distance < spacing:
			force += offset / distance * (spacing - distance) * Balance.ENEMY_SEPARATION_STRENGTH
	return force.limit_length(move_speed * Balance.ENEMY_SEPARATION_SPEED_RATIO)

func take_damage(amount: float, kind: StringName, from_direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
	if not is_alive() or Game.run == null:
		return false
	if room.enemy_skills != null:
		amount = room.enemy_skills.filter_incoming_damage(self, amount, kind, from_direction)
	if amount <= 0.0:
		return false
	last_damage_context = context.duplicate()
	if last_damage_context.is_empty():
		last_damage_context = {"damage_source":str(kind),"equipment_eligible":false,"original_basic":false,"proc_depth":1}
	if kind == &"primary" or kind == &"child":
		knockback += from_direction * Balance.ENEMY_KNOCKBACK
	hurt_flash = 0.1
	var final_amount: float = amount * 100.0 / (100.0 + maxf(0.0, armor))
	final_amount = status.absorb(final_amount)
	if brain != null:
		var hit_context: Dictionary = context.duplicate()
		hit_context.merge({"damage":final_amount,"kind":str(kind),"direction":from_direction},true)
		brain.on_damaged(self, hit_context)
	room.add_damage_text(position - Vector2(0, 65 if body_texture != null else 26), final_amount, kind)
	return health.damage(final_amount)

func apply_burn() -> void:
	apply_status("burn", room.player.attack_power())

func tick_burn(delta: float) -> void:
	tick_statuses(delta)

func apply_status(id: String, power: float, duration: float = -1.0) -> bool:
	if not is_alive():
		return false
	if id not in ["burn", "shock", "chill", "corrosion", "guard"]:
		return false
	if id == "guard":
		status.grant_guard(power, 4.0 if duration <= 0.0 else duration, "enemy", health.maximum)
	else:
		var duration_bonus: float = room.player.stat("status_duration", 0.0)
		if id == "chill":
			duration_bonus += float(room.player.loadout.modifiers().get("chill_duration_bonus", 0.0))
		var life: float = duration if duration > 0.0 else (4.0 if id == "corrosion" else 3.0) * (1.0 + minf(0.4, duration_bonus))
		status.apply(id, power * (1.0 + room.player.stat("burn_damage", 0.0)) if id == "burn" else power, life, power)
	burn_remaining = float(status.states.get("burn", {}).get("remaining", 0.0))
	burn_tick = float(status.states.get("burn", {}).get("tick", 0.0))
	queue_redraw()
	return true

func tick_statuses(delta: float) -> void:
	for tick: Dictionary in status.tick(delta):
		if not is_alive():
			break
		if tick.kind == "burn":
			room.telemetry["burn_ticks"] += 1
		var event_id: String = "dot:" + str(get_instance_id()) + ":" + str(status.clock)
		take_damage(float(tick.damage), StringName(tick.kind), Vector2.ZERO, {"attack_id":event_id,"root_event_id":event_id,"damage_source":tick.kind,"proc_depth":1,"equipment_eligible":false,"original_basic":false,"target_states":[tick.kind],"H":float(tick.H),"X":float(tick.damage)})
	burn_remaining = float(status.states.get("burn", {}).get("remaining", 0.0))
	burn_tick = float(status.states.get("burn", {}).get("tick", 0.0))

func apply_knockback(direction: Vector2, distance: float) -> void:
	if static_actor:
		return
	if rank == "boss":
		room.add_ring(position, Color("beb09a"), 24.0, 0.2)
		return
	var length: float = distance * (0.5 if rank == "elite" else 1.0)
	position = room.move_actor(position, direction * length, navigation_radius)
	if rank == "normal" and reaction_cooldown <= 0.0:
		reaction_cooldown = 1.0
		reaction_remaining = 0.12

func _die() -> void:
	room.enemy_died(self)
	queue_free()

func _draw() -> void:
	if health == null:
		return
	if static_actor:
		_draw_skill_anchor()
		return
	if brain != null:
		room.draw_enemy_telegraph(self, brain.current_telegraph())
	var reduced: bool = Game.profile.get("settings", {}).get("reduced_fx", false)
	if state == &"emerging":
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 24, Color(0.9, 0.42, 0.41, 0.65), 2.0, true)
		draw_line(Vector2(-5,-30), Vector2(5,-30), Color("e46b69"), 2.0)
	if state == &"windup":
		var progress := 1.0 - state_time / Balance.ENEMY_WINDUP
		var fan := PackedVector2Array([Vector2.ZERO])
		for i in range(13):
			fan.append(aim_direction.rotated(-1.15 + float(i) / 12.0 * 2.3) * (Balance.ENEMY_RANGE + 8.0))
		draw_colored_polygon(fan, Color(0.89, 0.28, 0.24, 0.13 + progress * 0.15))
		draw_polyline(fan, Color(0.95, 0.44, 0.40, 0.85), 1.5, true)
		draw_arc(Vector2.ZERO, 42 if body_texture != null else 25, -PI / 2, -PI / 2 + TAU * progress, 24, Color("f1b466"), 3, true)
	draw_set_transform(Vector2(0,10), 0.0, Vector2(1,0.5))
	draw_circle(Vector2.ZERO, 22.0, Color(0.02, 0.03, 0.04, 0.6))
	draw_set_transform(Vector2.ZERO)
	if body_texture != null:
		draw_arc(Vector2.ZERO,navigation_radius,0,TAU,24,Color(0.89,0.42,0.41,0.25),1.0,true)
		var tint := Color(1,1,1,.35 if bool(get_meta("enemy_shadow_stealth",false)) else 1.0)
		if hurt_flash > 0.0 and not reduced:
			var lift: float = .12*clampf(hurt_flash/.1,0.0,1.0)
			tint.r += lift
			tint.g += lift
			tint.b += lift
		var image_texture: Texture2D = body_texture
		if enemy_id == "M35" and empty_body_texture != null and (not is_instance_valid(room.enemy_props) or not room.enemy_props.carried_by(self)):
			image_texture = empty_body_texture
		if body_region.has_area():
			draw_texture_rect_region(image_texture,body_bounds,body_region,tint)
		else:
			draw_texture_rect(image_texture,body_bounds,false,tint)
	else:
		_draw_fallback_body()
	if bool(get_meta("solid_owner_ring",false)) or str(profile.get("behavior_id","")) == "solid_ring_decoy":
		draw_circle(Vector2(0,18),12.0,Color(.6,.77,.85,.65))
	if state == &"windup" and brain == null:
		var marker_y := -70.0 if body_texture != null else -35.0
		draw_line(Vector2(0,marker_y), Vector2(0,marker_y+8), Color("fff0cf"), 3)
		draw_circle(Vector2(0,marker_y+13), 1.8, Color("fff0cf"))
	if burn_remaining > 0.0:
		for i in range(3):
			var base := Vector2(-10 + i * 10, -34 if body_texture != null else -17)
			var flicker := 3.0 * sin(lifetime * 14 + i)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-4,0),base+Vector2(1,-14-flicker),base+Vector2(5,0)]),Color("e6aa4a"))
	var visible_statuses: Array[String] = visible_status_ids()
	var status_x: float = -float(visible_statuses.size()) * 10.0
	for id: String in visible_statuses:
		var icon: Texture2D = status_textures.get(id)
		var color: Color = {"burn":Color("e6aa4a"),"shock":Color("eed897"),"chill":Color("98d8e2"),"corrosion":Color("a7c783")}[id]
		draw_rect(Rect2(status_x,-76,18,18),Color(.04,.065,.07,.88))
		if icon != null:
			var icon_size: Vector2 = icon.get_size()
			var extent: Vector2 = icon_size * minf(18.0/icon_size.x,18.0/icon_size.y)
			draw_texture_rect(icon,Rect2(Vector2(status_x,-76)+(Vector2(18,18)-extent)*.5,extent),false)
		else:
			draw_circle(Vector2(status_x+9,-67),4.0,color)
		status_x += 20.0
	if status.shield() > 0.0:
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 24, Color("addbca"), 2.0, true)
	if health.current < health.maximum or (not enemy_id.is_empty() and position.distance_to(room.player.position)<520):
		var bar_y: float = body_bounds.position.y-8.0 if body_texture != null else -40.0
		draw_rect(Rect2(-18,bar_y,36,4),Color("0d131a"))
		draw_rect(Rect2(-18,bar_y,36 * health.current / health.maximum,4),Color("e46b69"))
	if not enemy_id.is_empty():
		var nearby: bool = position.distance_to(room.player.position)<300
		var english: bool = Words.locale == "en"
		var caption: String = "Lv.%d" % enemy_level
		if rank == "elite":
			caption += " Elite" if english else " 精英"
		if nearby or hurt_flash > 0:
			caption += " " + str(profile.get("name_en" if english else "name",enemy_id))
		var text_width: float = room.fx_font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		draw_rect(Rect2(-text_width*.5-3,25,text_width+6,16),Color(.035,.05,.06,.82))
		draw_string(room.fx_font,Vector2(-text_width*.5,37),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("e8d3ab"))

func _draw_skill_anchor() -> void:
	var plate: bool = str(get_meta("enemy_skill_anchor_kind", "")) == "weld_cover" or actor_kind == "cover"
	var facing: Vector2 = get_meta("enemy_skill_anchor_direction",Vector2.RIGHT)
	draw_set_transform(Vector2.ZERO,facing.angle())
	if plate:
		draw_rect(Rect2(-8,-24,16,48),Color("35464d"))
		draw_rect(Rect2(-8,-24,16,48),Color("d89652"),false,2)
		for y in [-15,0,15]:
			draw_line(Vector2(-5,y),Vector2(5,y),Color("9eaa9d"),2)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-10,0),Vector2(0,-13),Vector2(10,0),Vector2(0,13)]),Color("497784"))
		draw_circle(Vector2.ZERO,5,Color("a5e1dd"))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(-13,-32,26,3),Color("17252b"))
	draw_rect(Rect2(-13,-32,26*health.current/maxf(1,health.maximum),3),Color("dfad65"))

func _draw_fallback_body() -> void:
	var walk := sin(lifetime * 9.0) * (3.0 if state == &"chase" else 0.0)
	for side in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([Vector2(side*8,0),Vector2(side*23,-8+walk),Vector2(side*29,6+walk)]), Color("75614e"), 4.0, true)
		draw_polyline(PackedVector2Array([Vector2(side*9,5),Vector2(side*21,13-walk),Vector2(side*23,21-walk)]), Color("4c5c63"), 4.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6),Vector2(13,12),Vector2(-12,12)]), Color("43505a"))
	draw_polyline(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6)]), Color("917458"), 2.0, true)
	draw_line(Vector2(-13,-4),Vector2(14,-4),Color("19252c"),6.0)
	draw_line(Vector2(-9,-4),Vector2(10,-4),Color("e99663"),3.0)
	draw_circle(Vector2(0,5),5.0,Color("a07447"))
	draw_circle(Vector2(0,5),2.0,Color("f4cf80"))
