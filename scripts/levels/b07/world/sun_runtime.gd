extends Node2D
## Room-owned mirror geometry and real actor effects; never deals player damage.
const State = preload("res://scripts/levels/b07/world/sun_state.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Numbers = preload("res://scripts/levels/b07/combat/enemy_numbers.gd")
const ReviewSkins = preload("res://scripts/levels/b07/art/l37_prop_skins.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
var state = State.new()
var room_id := ""
var room: Node2D
var definition: Dictionary = {}
var _interactor: WeakRef
var _mirror_id := ""
var _reveal: Dictionary = {}
var _boss: WeakRef
var _altar: Node2D

func configure(id: String, difficulty: int = 0, calibration: Variant = null) -> bool:
	if not room_id.is_empty(): return false
	definition = Geometry.room(id)
	if definition.is_empty(): return false
	var boss_hp := 0.0
	if id == "BO07":
		var profile: Dictionary = Numbers.boss(difficulty,calibration)
		if profile.is_empty(): return false
		boss_hp = float(profile.max_hp)
	if not state.configure(id,definition.mirrors,str(definition.altar.id),int(definition.required_mirrors),boss_hp): return false
	room_id = id
	room = get_parent()
	# Actual beams/state cues stay above the depth-sorted review skins.
	z_index = 3 if ReviewSkins.enabled(room) else 1
	queue_redraw()
	return true

func bind_boss(actor: Node2D) -> void:
	_boss = weakref(actor)
	_altar = preload("res://scripts/levels/b07/world/altar_target.gd").new()
	_altar.room = room
	_altar.mechanism_host = self
	_altar.position = Geometry.world_point(definition.altar.position)
	_altar.configure({"enemy_id":"B07-ALTAR","name":"太阳祭坛护罩","max_hp":state.altar_max_hp,"damage":0,"move_speed":0,"armor":0,"magic_resist":0,"ruleset_version":2,"scale_version":10},{"reward_enabled":false,"actor_kind":"objective"})
	room.enemies.add_child(_altar)

func interact(id: String, actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(room) or not room.controls_enabled(): return false
	if state.mirrors.has(id):
		if not _in_range(actor,id) or not state.begin_rotation(id): return false
		_interactor = weakref(actor)
		_mirror_id = id
		return true
	for gate: Dictionary in definition.manual_gates:
		if gate.id == id:
			return actor.position.distance_to(Geometry.world_point(gate.position)) <= 90 and state.open_manual_gate(room.objective_complete)
	return false

func _in_range(actor: Node2D, id: String) -> bool:
	for mirror: Dictionary in definition.mirrors:
		if mirror.id == id:
			var at := Geometry.world_point(mirror.position)
			return actor.position.distance_to(at) <= 90 and room.has_line_of_sight(actor.position,at)
	return false

func cancel_interaction() -> void:
	state.cancel_rotation()
	_interactor = null
	_mirror_id = ""

func notify_actor_hit(id: String, consumed: float) -> void:
	if id == "player" and is_finite(consumed) and consumed > 0: cancel_interaction()

func tick(delta: float, paused: bool = false) -> void:
	if paused or not is_finite(delta) or delta <= 0 or (is_inside_tree() and get_tree().paused): return
	var actor: Node2D = _interactor.get_ref() if _interactor != null else null
	var valid: bool = is_instance_valid(actor) and _in_range(actor,_mirror_id) and room.controls_enabled()
	state.tick(delta,valid)
	if state.channel().id == "": _interactor = null; _mirror_id = ""
	for key in _reveal.keys():
		_reveal[key] = maxf(0,float(_reveal[key])-delta)
		if _reveal[key] <= 0: _reveal.erase(key)
	if _boss != null and is_instance_valid(_boss.get_ref()):
		var boss: Node2D = _boss.get_ref()
		var ratio: float = boss.health.current/maxf(1,boss.health.maximum)
		state.set_phase(3 if ratio <= .35 else 2 if ratio <= .7 else 1)
	for enemy: Node in room.enemies.get_children():
		if not str(Props.read(enemy,"enemy_id","")).begins_with("B07-M"): continue
		if str(enemy.enemy_id) in ["B07-M02","B07-M12","B07-M15"]:
			# Fade BODY only; health bars, targetability and all tells remain intact.
			if is_instance_valid(enemy.body_visual): enemy.body_visual.modulate.a = 1.0 if not bool(enemy.get_meta("b07_camouflaged",false)) or is_revealed(enemy) else .4
	queue_redraw()

func is_lit(actor: Node2D) -> bool:
	if not is_instance_valid(actor): return false
	for key: String in state.mirrors:
		var path: Array = state.current_direction(key).path
		for index in range(path.size()-1):
			var a := Geometry.world_point(path[index])
			var b := Geometry.world_point(path[index+1])
			if actor.position.distance_to(Geometry2D.get_closest_point_to_segment(actor.position,a,b)) <= 38: return true
	return false

func is_revealed(actor: Node2D) -> bool:
	return is_lit(actor) or float(_reveal.get(actor.get_instance_id(),0)) > 0 or (is_instance_valid(room.player) and actor.position.distance_to(room.player.position) <= 120)

func reveal_actor(actor: Node2D, seconds: float = 3.0) -> void:
	if is_instance_valid(actor) and is_finite(seconds) and seconds > 0:
		_reveal[actor.get_instance_id()] = maxf(seconds,float(_reveal.get(actor.get_instance_id(),0)))

func filter_damage(actor: Node2D, amount: float, from_direction: Vector2, damage_type: String) -> float:
	if str(Props.read(actor,"enemy_id","")) == "BO07": return amount * state.boss_multiplier()
	if damage_type == "true" or not str(Props.read(actor,"enemy_id","")).begins_with("B07-M"): return amount
	var id := str(actor.enemy_id)
	if id not in ["B07-M01","B07-M04","B07-M08","B07-M11","B07-M17"] or not is_lit(actor): return amount
	# Incoming vector points from attacker towards target, so negate it.
	if from_direction.length_squared() <= .001: return amount
	var incoming := -from_direction.normalized()
	var reduction := .2 if actor.aim_direction.normalized().dot(incoming) >= .5 else 0.0
	if bool(actor.get_meta("b07_shield_active",false)):
		var shield_direction: Vector2 = actor.get_meta("b07_shield_direction",Vector2.RIGHT)
		if shield_direction.normalized().dot(incoming) >= .5: reduction = maxf(reduction,.35)
	return amount*(1.0-reduction)

func boss_damage_multiplier() -> float: return state.boss_multiplier()
func checkpoint() -> Dictionary: return state.checkpoint()
func restore_checkpoint(value: Dictionary) -> bool:
	if not state.restore(value): return false
	cancel_interaction()
	_reveal.clear()
	if is_instance_valid(_altar): _altar.synchronize()
	queue_redraw()
	return true
func _exit_tree() -> void:
	if is_instance_valid(_altar): _altar.queue_free()

func _draw() -> void:
	if definition.is_empty(): return
	for mirror: Dictionary in definition.mirrors:
		var at := Geometry.world_point(mirror.position)
		var current: Dictionary = state.current_direction(mirror.id)
		var next: Dictionary = state.current_direction(mirror.id,true)
		var points := Geometry.points(current.path)
		var preview := Geometry.points(next.path)
		for i in range(preview.size()-1): draw_dashed_line(preview[i],preview[i+1],Color(.1,.6,.6,.55),2,10)
		draw_polyline(points,Color("f9da79"),7,true)
		draw_polyline(points,Color("fff0bc"),2,true)
		if ReviewSkins.skin_recipes(room).is_empty(): draw_circle(at,23,Color("396f6b"))
		draw_arc(at,24,0,TAU,30,Color("f4c972"),3,true)
		draw_line(at,at+(points[1]-points[0]).normalized()*30,Color("fff3dc"),5,true)
		if _mirror_id == mirror.id: draw_arc(at,30,-PI/2,-PI/2+TAU*float(state.channel().elapsed)/.6,30,Color("bf6b46"),4,true)
	if is_instance_valid(room):
		for enemy in room.enemies.get_children():
			if bool(enemy.get_meta("b07_camouflaged",false)):
				draw_circle(enemy.position+Vector2(-7,4),3,Color("786451"))
				draw_circle(enemy.position+Vector2(7,4),3,Color("786451"))
	var altar_at := Geometry.world_point(definition.altar.position)
	draw_arc(altar_at,43,0,TAU,40,Color("57ad9a") if state.gate_open else Color("c78042"),4,true)

## Freeze at warning start. Reorienting a mirror invalidates that exact hazard.
func enemy_attack_lines(_actor: Node2D, maximum: int = 2) -> Array:
	var result: Array = []
	for id: String in state.mirrors:
		var path: Array = state.current_direction(id).path
		if path.size() < 2: continue
		# Leave mirror interaction radius clear: hostile emission starts beyond it.
		var start := Geometry.world_point(path[0])
		var finish := Geometry.world_point(path[1])
		if start.distance_to(finish) <= 130: continue
		start += start.direction_to(finish)*110
		result.append({"origin":start,"target":finish,"mirror_id":id,"mirror_state":int(state.mirrors[id])})
		if result.size() >= clampi(maximum,1,2): break
	return result

func enemy_line_valid(command: Dictionary) -> bool:
	var id := str(command.get("mirror_id",""))
	return state.mirrors.has(id) and state.mirrors[id] == command.get("mirror_state",-1)

func admit_persistent_area(point: Vector2, radius: float) -> bool:
	if not point.is_finite() or not is_finite(radius) or radius < 0: return false
	for mirror: Dictionary in definition.mirrors:
		if point.distance_to(Geometry.world_point(mirror.position)) <= 90+radius: return false
	return true
