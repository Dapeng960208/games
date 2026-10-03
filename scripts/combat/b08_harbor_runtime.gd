extends RefCounted
## L44-only support and destructible chime jobs. No global state or rewards.
const Actor = preload("res://scripts/combat/b08_actor.gd")
var room: Node2D
var clock := 0.0
var support: Dictionary = {}
var chimes: Dictionary = {}
func configure(host: Node2D) -> void: room = host
func reset() -> void:
	support.clear()
	chimes.clear()
	clock = 0
func choose_support(caster: Node2D) -> Node2D:
	var chosen: Node2D
	var distance := INF
	for actor: Node2D in room.enemies.get_children():
		if actor==caster or not actor.is_alive() or actor.static_actor or actor.rank=="boss": continue
		if not room.has_line_of_sight(caster.position,actor.position): continue
		var separation: float = actor.position.distance_to(caster.position)
		if separation<=320 and separation<distance and not support.has(actor.get_instance_id()): chosen=actor; distance=separation
	return chosen
func grant_support(caster: Node2D, target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.is_alive() or target==caster or target.static_actor or target.rank=="boss": return false
	if support.has(target.get_instance_id()) or caster.position.distance_to(target.position)>320 or not room.has_line_of_sight(caster.position,target.position): return false
	support[target.get_instance_id()] = {"target":weakref(target),"expires":clock+5.0,"active":false,"used":false,"shield":int(caster.profile.difficulty)>=2}
	return true
func begin_reposition(actor: Node2D) -> void:
	var boon: Dictionary = support.get(actor.get_instance_id(),{})
	if not boon.is_empty() and not boon.used and clock<float(boon.expires): boon.active=true; boon.used=true
func reposition_multiplier(actor: Node2D) -> float:
	var boon: Dictionary = support.get(actor.get_instance_id(),{})
	return 1.15 if bool(boon.get("active",false)) and clock<float(boon.get("expires",0)) else 1.0
func end_reposition(actor: Node2D, distance: float, completed: bool) -> void:
	var id: int = actor.get_instance_id()
	var boon: Dictionary = support.get(id,{})
	if boon.is_empty() or not bool(boon.active): return
	if completed and distance>=20 and clock<float(boon.expires) and bool(boon.shield):
		# Duration is an explicit candidate choice where the authored row has none.
		actor.status.grant_guard_result(round(actor.health.maximum*.04),4.0,"b08_priest_reposition",actor.health.maximum)
	support.erase(id)
func spawn_chime(caster: Node2D, action: Dictionary) -> WeakRef:
	if chimes.has(caster.get_instance_id()) or chimes.size()>=2 or room.enemies.get_child_count()>=18: return null
	var bell: MineEnemy = Actor.new()
	bell.room = room
	var profile: Dictionary = caster.profile.duplicate(true)
	profile["enemy_id"] = "B08-CHIME"
	profile["name"] = "落风铃"
	# The design leaves bell HP unspecified; use 10% of its own caster as a
	# local, documented diagnostic choice, never a shared balance coefficient.
	profile["max_hp"] = maxi(1,roundi(caster.health.maximum*.10))
	profile["navigation_radius"] = 14.0
	bell.configure(profile,{"reward_enabled":false,"static_actor":true,"owner":caster})
	bell.position = room.clamp_actor(action.target,14)
	room.enemies.add_child(bell)
	chimes[caster.get_instance_id()] = {"owner":weakref(caster),"bell":weakref(bell),"action":action.duplicate(true),"phase":"armed","remaining":0.0,"echo_radius":55.0 if int(caster.profile.difficulty)>=4 else 80.0}
	return weakref(bell)
func release_chime(caster: Node2D, action: Dictionary) -> void:
	var job: Dictionary = chimes.get(caster.get_instance_id(),{})
	if job.is_empty() or not _valid(job): return
	job.action = action.duplicate(true)
	room.hit_circle(caster,job.action,.9,80)
	if int(caster.profile.difficulty)>=2:
		job.phase="echo_warning"
		job.remaining=.8
	else: _remove(caster.get_instance_id())
func cancel_chime(caster: Node2D) -> void: _remove(caster.get_instance_id())
func actor_died(actor: Node2D) -> void:
	support.erase(actor.get_instance_id())
	for id: int in chimes.keys():
		var job: Dictionary = chimes[id]
		if job.owner.get_ref()==actor or job.bell.get_ref()==actor: _remove(id)
func _valid(job: Dictionary) -> bool:
	var caster: Node2D = job.owner.get_ref()
	var bell: Node2D = job.bell.get_ref()
	return is_instance_valid(caster) and caster.is_alive() and is_instance_valid(bell) and bell.is_alive() and not bell.is_queued_for_deletion()
func _remove(id: int) -> void:
	if not chimes.has(id): return
	var bell: Node2D = chimes[id].bell.get_ref()
	if is_instance_valid(bell) and not bell.is_queued_for_deletion(): bell.queue_free()
	chimes.erase(id)
	room.release_warning(str(id))
func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0 or (room.is_inside_tree() and room.get_tree().paused): return
	clock += delta
	for id: int in support.keys():
		var actor: Node2D = support[id].target.get_ref()
		if not is_instance_valid(actor) or not actor.is_alive() or clock>=float(support[id].expires): support.erase(id)
	for id: int in chimes.keys():
		var job: Dictionary = chimes[id]
		if not _valid(job): _remove(id); continue
		if job.phase!="echo_warning": continue
		job.remaining -= delta
		if float(job.remaining)<=0.000001:
			room.hit_circle(job.owner.get_ref(),job.action,.3,float(job.echo_radius))
			_remove(id)
func draw_warnings(canvas: Node2D) -> void:
	for job: Dictionary in chimes.values():
		if not _valid(job) or job.phase!="echo_warning": continue
		canvas.draw_arc(job.action.target,float(job.echo_radius),0,TAU,48,Color("db615b"),3)
		canvas.draw_arc(job.action.target,float(job.echo_radius)+5,-PI*.5,-PI*.5+TAU*(1.0-float(job.remaining)/.8),48,Color("f0b558"),2)
