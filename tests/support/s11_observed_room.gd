extends RoomController
## Observation only: every production presentation call still runs unchanged.
## No actor, damage, AI, geometry, resource or status is modified here.
var recording := false
var packets: Array[Dictionary] = []
var releases: Array[Dictionary] = []
var actor_roster: Dictionary = {}

func _ready() -> void:
	super._ready()
	enemies.child_entered_tree.connect(_actor_entered)
	scan_actors()

func _actor_entered(actor: Node) -> void:
	if not actor is EnemyActor: return
	if actor.is_node_ready(): _capture_actor(actor)
	else: actor.ready.connect(_capture_actor.bind(actor),CONNECT_ONE_SHOT)

func _capture_actor(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor is EnemyActor or not is_instance_valid(actor.health): return
	var id := str(actor.get_instance_id())
	if not actor_roster.has(id):
		actor_roster[id] = {"id":id,"template":actor.enemy_id,"rank":actor.rank,"actor_kind":actor.actor_kind,"level":actor.enemy_level,
			"spawn_t":elapsed,"initial_hp":actor.health.current,"max_hp":actor.health.maximum,"actor_damage":actor.contact_damage,
			"armor":actor.armor,"magic_resist":actor.magic_resist,"initial_shield":actor.status.shield(),"profile":actor.profile.duplicate(true)}
		actor.tree_exiting.connect(_actor_exiting.bind(weakref(actor),id),CONNECT_ONE_SHOT)
	actor_roster[id]["last_hp"] = actor.health.current
	actor_roster[id]["last_shield"] = actor.status.shield()
	actor_roster[id]["last_seen_t"] = elapsed

func _actor_exiting(reference: WeakRef, id: String) -> void:
	var actor: Node = reference.get_ref()
	if not is_instance_valid(actor) or not actor_roster.has(id): return
	_capture_actor(actor)
	actor_roster[id]["exit_t"] = elapsed

func scan_actors() -> void:
	for actor: Node in enemies.get_children(): _capture_actor(actor)

func add_deployment(kind: String, at: Vector2, options: Dictionary) -> Node2D:
	var deployment := super.add_deployment(kind,at,options)
	if recording and is_instance_valid(deployment):
		var id := deployment.get_instance_id()
		releases.append({"t":elapsed,"kind":"deployment_created","deployment_kind":kind,"id":id,"position":[at.x,at.y],"health":deployment.health,"max_health":deployment.max_health,"radius":deployment.radius,"lifetime":deployment.lifetime})
		deployment.tree_exiting.connect(_deployment_exiting.bind(weakref(deployment),id,kind))
	return deployment

func _deployment_exiting(reference: WeakRef, id: int, kind: String) -> void:
	if not recording: return
	var deployment: Node2D = reference.get_ref()
	if is_instance_valid(deployment):
		releases.append({"t":elapsed,"kind":"deployment_retired","deployment_kind":kind,"id":id,"health":deployment.health,"elapsed":deployment.elapsed,"lifetime":deployment.lifetime,"destroyed_by_damage":float(deployment.health)<=0,"charge":deployment.resonance_charge})

func spawn_ability_projectile(at: Vector2, direction: Vector2, amount: float, options: Dictionary) -> ProjectileActor:
	var projectile := super.spawn_ability_projectile(at,direction,amount,options)
	if recording:
		var boss: Node2D = _boss_actor if is_instance_valid(_boss_actor) else null
		var offset: Vector2 = boss.position-at if is_instance_valid(boss) else Vector2.ZERO
		releases.append({"t":elapsed,"kind":"projectile","source":str(options.get("source","")),"root_event_id":str(options.get("root_event_id","")),
			"created":is_instance_valid(projectile),"amount":amount,"origin":[at.x,at.y],"direction":[direction.x,direction.y],
			"boss_position":[boss.position.x,boss.position.y] if is_instance_valid(boss) else [],"boss_velocity":[boss.velocity.x,boss.velocity.y] if is_instance_valid(boss) else [],
			"boss_forward_distance":offset.dot(direction),"boss_lateral_error":absf(offset.cross(direction)),"speed":options.get("speed",0),
			"active_elapsed":float(player.abilities.active.get("elapsed",0)),"active_serial":int(player.abilities.active.get("serial",0)),"player_aim":[player.aim_direction.x,player.aim_direction.y]})
	return projectile

func add_damage_text(at: Vector2, amount: float, kind: StringName, context: Dictionary = {}) -> void:
	if recording and amount > 0.0:
		var target: Node = context.get("target")
		if not is_instance_valid(target) and str(kind) not in ["received","heal","guard"]:
			for candidate in enemies.get_children():
				if not candidate is EnemyActor: continue
				var anchor: Vector2 = candidate.position - Vector2(0, 65 if candidate.body_texture != null else 26)
				if anchor.distance_squared_to(at) < .01:
					target = candidate
					break
		if is_instance_valid(target): _capture_actor(target)
		var packet := {"t":elapsed,"amount":amount,"kind":str(kind),"feedback_kind":str(context.get("feedback_kind","hp")),
			"target_id":target.get_instance_id() if is_instance_valid(target) else 0,
			"target_kind":str(target.get("actor_kind")) if is_instance_valid(target) else "player" if str(kind) in ["received","heal","guard"] else "unknown",
			"target_template":str(target.get("enemy_id")) if is_instance_valid(target) and target is EnemyActor else "",
			"target_rank":str(target.get("rank")) if is_instance_valid(target) and target is EnemyActor else "",
			"boss":target is BossActor,"weakpoint":target.boss_brain.weakpoint_open() if target is BossActor else false}
		for key: String in ["damage_source","skill_slot","root_event_id","attack_id","damage_type","source_id","source_name","proc_depth","critical","X","H"]:
			if context.has(key): packet[key] = context[key]
		packets.append(packet)
	super.add_damage_text(at, amount, kind, context)
