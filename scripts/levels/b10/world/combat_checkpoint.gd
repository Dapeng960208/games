extends RefCounted
## B10 alone preserves its finite encounter and frozen hostile state. Every
## reference is a local actor index; stored old IDs only remap hit receipts.
## No Node or asset path is loaded from a save. Validate before replacement.
const Skills = preload("res://scripts/levels/b10/combat/enemy_skills.gd")
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
const ACTOR_FIELDS := ["state","state_time","aim_direction","knockback","lifetime","burn_remaining","burn_tick","reaction_remaining","reaction_cooldown","_ordinary_slow_remaining","_ordinary_slow_multiplier"]
const ENEMY_BRAIN := ["phase","cooldown","remaining","duration","cycle","serial","command","active","locked_origin"]
const BOSS_BRAIN := ["phase","state","state_time","state_duration","action_index","current_action","command","weakpoint","weakpoint_time","elapsed","stopped","_actions_used","_action_ready_at","_released_pose","_recovery_elapsed","_cores_initialized","_rebuild_at","_rebuild_index","_rebuild_used","_cast_serial"]
const COLLECTIONS := ["jobs","projectiles","hazards","motions","supports","visuals","marks"]
const ROOT_KEYS := ["version","room_id","difficulty","elapsed","player_position","player_instance","guardian_started","boss_defeated","cleared","encounters","actors","collections","extension"]
const EXTENSION_KEYS := ["clock","serial","cores","effects","links","echo_ready","repaired","hit_receipts","current_phase","exposed_phase","ordinary_initialized","boss"]

static func capture(room: Node2D) -> Dictionary:
	if not bool(room.layout.get("b10_final",false)): return {}
	var actor_indices: Dictionary={room.player.get_instance_id():-2}
	var actors: Array=[]
	for actor: Node2D in room.enemies.get_children():
		if actor.is_alive() and not actor.is_queued_for_deletion():
			actor_indices[actor.get_instance_id()]=actors.size()
			actors.append(actor)
	var records: Array=[]
	for actor: Node2D in actors:
		var state: Dictionary={}
		for key: String in ACTOR_FIELDS: state[key]=_pack(actor.get(key),actor_indices)
		var brain: Dictionary={}
		if actor.brain!=null:
			for key: String in BOSS_BRAIN if actor.rank=="boss" else ENEMY_BRAIN: brain[key]=_pack(actor.brain.get(key),actor_indices)
		records.append({"id":actor.enemy_id,"level":actor.enemy_level,"rank":actor.rank,"hp":actor.health.current,"maximum":actor.health.maximum,
			"position":[actor.position.x,actor.position.y],"kind":actor.actor_kind,"static_actor":actor.static_actor,"reward":actor.reward_enabled,"receipt":actor.reward_spawn_id,"zone":actor.zone_index,
			"old_instance":actor.get_instance_id(),"owner":actor_indices.get(actor.owner_enemy.get_ref().get_instance_id(),-1) if actor.owner_enemy!=null and is_instance_valid(actor.owner_enemy.get_ref()) else -1,
			"state":state,"brain":brain,"states":_pack(actor.status.states,actor_indices),"guards":_pack(actor.status.guards,actor_indices),"status_clock":actor.status.clock,"shock_cooldown":actor.status.shock_cooldown,
			"anchor":str(actor.get_meta("enemy_skill_anchor_kind","")),"guard_rounds":int(actor.get_meta("b10_guard_rounds",0))})
	var encounters: Dictionary={}
	for index: int in room.encounter_progress:
		var progress: Dictionary=room.encounter_progress[index]
		encounters[str(index)]={"next_wave":int(progress.next_wave),"reinforce_elapsed":float(progress.reinforce_elapsed)}
	var collections: Dictionary={}
	for key: String in COLLECTIONS: collections[key]=_pack(room.enemy_skills.get(key),actor_indices)
	var extension: RefCounted=room.enemy_skills.b10
	var links: Dictionary={}
	var echo: Dictionary={}
	for old_id: int in extension.links:
		if actor_indices.has(old_id): links[str(actor_indices[old_id])]=extension.links[old_id]
	for old_id: int in extension.echo_ready:
		if actor_indices.has(old_id): echo[str(actor_indices[old_id])]=extension.echo_ready[old_id]
	var live_effects: Array=[]
	for effect: Dictionary in extension.effects:
		if room.enemy_skills._alive(effect.target.get_ref()): live_effects.append(effect)
	var value: Dictionary={"version":1,"room_id":room.layout_id,"difficulty":room.difficulty,"elapsed":room.elapsed,
		"player_position":[room.player.position.x,room.player.position.y],"player_instance":room.player.get_instance_id(),"guardian_started":room._b10_guard_started,"boss_defeated":room._boss_defeated,"cleared":room.objective_complete,
		"encounters":encounters,"actors":records,"collections":collections,"extension":{
			"clock":extension.clock,"serial":extension.serial,"cores":_pack(extension.cores,actor_indices),"effects":_pack(live_effects,actor_indices),
			"links":links,"echo_ready":echo,"repaired":_pack(extension.repaired,actor_indices),"hit_receipts":_pack(extension.hit_receipts,actor_indices),
			"current_phase":extension.current_phase,"exposed_phase":extension.exposed_phase,"ordinary_initialized":extension.ordinary_initialized,
			"boss":actor_indices.get(extension.boss_ref.get_ref().get_instance_id(),-1) if extension.boss_ref!=null and is_instance_valid(extension.boss_ref.get_ref()) else -1}}
	return value if validate_checkpoint(value) else {}

static func validate_checkpoint(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=ROOT_KEYS.size() or not value.has_all(ROOT_KEYS) or value.version!=1: return false
	if value.room_id not in ["L55","L56","L57","L58","L59","L60","BO10"] or not _integer(value.difficulty,0,4): return false
	if not _number(value.elapsed,86400) or not _point(value.player_position,str(value.room_id)) or not _integer(value.player_instance,1,9223372036854775807): return false
	if not value.guardian_started is bool or not value.boss_defeated is bool or not value.cleared is bool or not value.actors is Array or value.actors.size()>24: return false
	if not value.encounters is Dictionary or value.encounters.size()>1 or not value.collections is Dictionary or not value.collections.has_all(COLLECTIONS) or value.collections.size()!=COLLECTIONS.size(): return false
	if not value.extension is Dictionary or value.extension.size()!=EXTENSION_KEYS.size() or not value.extension.has_all(EXTENSION_KEYS) or not _json(value.extension): return false
	if not _number(value.extension.clock,86400) or not _integer(value.extension.current_phase,0,3) or not _integer(value.extension.exposed_phase,0,3) or not value.extension.cores is Array or value.extension.cores.size()>3 or not value.extension.effects is Array or value.extension.effects.size()>128: return false
	if not _integer(value.extension.serial,0,1000000) or not value.extension.ordinary_initialized is bool: return false
	for key: String in ["links","echo_ready","repaired","hit_receipts"]:
		if not value.extension[key] is Dictionary: return false
	for key: String in COLLECTIONS:
		if not value.collections[key] is Array or value.collections[key].size()>128 or not _json(value.collections[key]): return false
		for command: Variant in value.collections[key]:
			if not _command(command,value.actors.size()) or not _reference(command.get("owner"),value.actors.size(),false): return false
	for key: String in value.encounters:
		var progress: Variant=value.encounters[key]
		if key!="0" or not progress is Dictionary or not _integer(progress.get("next_wave"),1,3) or not _number(progress.get("reinforce_elapsed"),86400): return false
	var boss_count:=0
	var zone_count:=0
	var bodies:=0
	var old_instances: Dictionary={str(int(value.player_instance)):true}
	for record: Variant in value.actors:
		if not record is Dictionary or not record.has_all(["id","level","rank","hp","maximum","position","kind","static_actor","reward","receipt","zone","old_instance","owner","state","brain","states","guards","status_clock","shock_cooldown","anchor","guard_rounds"]): return false
		if not record.id is String or not _integer(record.level,1,50) or not _number(record.maximum,10000000) or float(record.maximum)<=0 or not _number(record.hp,float(record.maximum)) or float(record.hp)<=0: return false
		if not _point(record.position,str(value.room_id)) or not _integer(record.owner,-1,value.actors.size()-1) or not _integer(record.old_instance,1,9223372036854775807) or not _integer(record.zone,-1,0) or not _integer(record.guard_rounds,0,2): return false
		if not record.static_actor is bool or not record.reward is bool or not record.receipt is String or record.receipt.length()>160 or not record.anchor is String: return false
		var old_id:=str(int(record.old_instance))
		if old_instances.has(old_id): return false
		old_instances[old_id]=true
		if record.id.begins_with("B10-M"):
			var authored: Dictionary=Skills.profile(record.id,int(record.level),int(value.difficulty),str(record.rank))
			if authored.is_empty() or record.kind!="enemy" or record.static_actor: return false
			var maximum:=float(authored.max_hp)*(.5 if int(record.owner)>=0 else 1.0)
			if not is_equal_approx(float(record.maximum),roundf(maximum)): return false
		elif Skills.is_boss(record.id):
			boss_count+=1
			if record.kind!="boss" or record.reward or record.rank!="boss" or record.static_actor or int(record.owner)!=-1: return false
			if record.id!=str(Geometry.room(str(value.room_id)).get("dragon_id","")) or not is_equal_approx(float(record.maximum),float(Skills.boss_profile(record.id,int(value.difficulty)).max_hp)): return false
		elif not (record.id=="B10-CORE" and record.static_actor and record.kind=="objective" and not record.reward) and not (record.id=="" and record.static_actor and record.kind=="hazard_endpoint" and record.anchor=="b10_scale_stone" and not record.reward): return false
		if not record.state is Dictionary or not record.state.has_all(ACTOR_FIELDS) or not record.brain is Dictionary or not record.states is Dictionary or not record.guards is Dictionary or not _json(record): return false
		if record.state.state not in ["emerging","chase","telegraph","locked","execute","recovery","phase_shift"] or not _number(record.state.state_time,300): return false
		if not _vector(record.state.aim_direction) or not _vector(record.state.knockback) or not _number(record.status_clock,86400) or not _number(record.shock_cooldown,10): return false
		if not record.static_actor and not _brain(record.brain,record.kind=="boss",value.actors.size()): return false
		if record.static_actor and not record.brain.is_empty(): return false
		if not _status(record.states,record.guards): return false
		for field: String in ["burn_remaining","burn_tick","lifetime","reaction_remaining","reaction_cooldown","_ordinary_slow_remaining","_ordinary_slow_multiplier"]:
			if not _number(record.state[field],86400): return false
		if int(record.zone)==0 and record.kind!="objective": zone_count+=1
		if record.kind!="objective": bodies+=1
		for key: String in record.brain:
			if key not in (BOSS_BRAIN if record.kind=="boss" else ENEMY_BRAIN): return false
	if boss_count>1 or zone_count>6 or bodies>18 or (value.boss_defeated and boss_count>0): return false
	if value.room_id!="BO10" and boss_count>0 and not value.guardian_started: return false
	if value.cleared and not value.actors.is_empty(): return false
	if not value.cleared and not value.boss_defeated and (value.guardian_started or value.room_id=="BO10") and boss_count!=1: return false
	if not _integer(value.extension.boss,-1,value.actors.size()-1): return false
	if int(value.extension.boss)>=0 and value.actors[int(value.extension.boss)].kind!="boss": return false
	if value.room_id!="BO10" and value.guardian_started and (not value.encounters.has("0") or int(value.encounters["0"].next_wave)!=3): return false
	for index in value.actors.size():
		var record: Dictionary=value.actors[index]
		if int(record.owner)==index: return false
		if record.id.begins_with("B10-M") and int(record.owner)>=0:
			if record.id!="B10-M01" or value.actors[int(record.owner)].id!="BO10" or record.reward: return false
	for core: Variant in value.extension.cores:
		if not core is Dictionary or not core.has_all(["index","actor","owner","position","health","boss"]) or not _integer(core.index,0,2) or int(core.index)!=value.extension.cores.find(core) or not _reference(core.actor,value.actors.size()) or not _reference(core.owner,value.actors.size()) or not _number(core.health,10000000) or not _vector(core.position) or not core.boss is bool: return false
		if int(core.actor["$ref"])>=0 and value.actors[int(core.actor["$ref"])].id!="B10-CORE": return false
		if int(core.actor["$ref"])>=0 and not is_equal_approx(float(value.actors[int(core.actor["$ref"])].maximum),maxf(10,float(core.health))): return false
		var raw_cores: Array=Geometry.room(str(value.room_id)).get("star_cores",[])
		if int(core.index)>=raw_cores.size(): return false
		var core_position: Array=core.position["$v"]
		if not Vector2(float(core_position[0]),float(core_position[1])).is_equal_approx(Geometry.world_point(raw_cores[int(core.index)].position)): return false
		if core.has("restore_at") and not _number(core.restore_at,86408): return false
	var linked_counts: Dictionary={}
	for key: String in value.extension.links:
		if not _index(key,value.actors.size()) or not _integer(value.extension.links[key],0,value.extension.cores.size()-1) or not str(value.actors[int(key)].id).begins_with("B10-M"): return false
		var core_index:=int(value.extension.links[key])
		linked_counts[core_index]=int(linked_counts.get(core_index,0))+1
		if linked_counts[core_index]>2: return false
	for key: String in value.extension.echo_ready:
		if not _index(key,value.actors.size()) or not _number(value.extension.echo_ready[key],86410): return false
	for key: String in value.extension.repaired:
		if not _index(key,value.extension.cores.size()) or value.extension.repaired[key]!=true: return false
	for key: String in value.extension.hit_receipts:
		if key.rfind(":")<0 or not key.get_slice(":",key.get_slice_count(":")-1).is_valid_int() or not _number(value.extension.hit_receipts[key],86400): return false
	for effect: Variant in value.extension.effects:
		if not effect is Dictionary or not effect.has_all(["kind","target","remaining"]) or effect.kind not in ["stance","guard","haste","echo_mark","stone","exposed"] or not _reference(effect.target,value.actors.size(),false) or not _number(effect.remaining,30): return false
		if effect.kind in ["stance","guard","exposed"] and not _vector(effect.get("direction")): return false
		if effect.has("source") and not _reference(effect.source,value.actors.size()): return false
		if effect.has("rear_only") and not effect.rear_only is bool: return false
	return _json(value) and JSON.stringify(value).length()<=750000

static func restore(room: Node2D, value: Dictionary) -> bool:
	if not validate_checkpoint(value) or value.room_id!=room.layout_id or int(value.difficulty)!=room.difficulty: return false
	room.enemy_skills.reset_room()
	for actor: Node in room.enemies.get_children(): actor.free()
	room._boss_actor=null
	room._b10_guard_started=bool(value.guardian_started)
	room._boss_defeated=bool(value.boss_defeated)
	room.objective_complete=bool(value.cleared)
	room.elapsed=float(value.elapsed)
	room.player.position=Vector2(float(value.player_position[0]),float(value.player_position[1]))
	room._previous_player_position=room.player.position
	room.activated_encounters.clear()
	room.encounter_progress.clear()
	for key: String in value.encounters:
		room.activated_encounters[int(key)]=true
		room.encounter_progress[int(key)]={"plan":room._encounter_plan(int(key)),"next_wave":int(value.encounters[key].next_wave),"reinforce_elapsed":float(value.encounters[key].reinforce_elapsed)}
	room.wave=room.activated_encounters.size()
	var actors: Array=[]
	var instance_map: Dictionary={str(int(value.player_instance)):room.player.get_instance_id()}
	for record: Dictionary in value.actors:
		var p: Dictionary
		if Skills.is_boss(record.id): p=Skills.boss_profile(record.id,room.difficulty)
		elif record.id.begins_with("B10-M"): p=Skills.profile(record.id,int(record.level),room.difficulty,str(record.rank))
		else: p={"enemy_id":record.id,"max_hp":record.maximum,"damage":0,"armor":0,"magic_resist":0,"ruleset_version":2,"scale_version":10,"navigation_radius":10.0 if record.kind=="hazard_endpoint" else 16.0,"effective_threat_cost":0.0}
		p["max_hp"]=record.maximum
		var actor: Node2D
		if record.kind=="boss":
			actor=load("res://scripts/gameplay/bosses/boss_actor.gd").new()
			actor.room=room
			actor.position=Vector2(float(record.position[0]),float(record.position[1]))
			actor.configure(p,{"reward_enabled":false,"actor_kind":"boss","zone_index":-1})
			actor.completed.connect(func(_id: String,_payload: Dictionary) -> void: room._boss_defeated=true)
			room.enemies.add_child(actor)
			room._boss_actor=actor
		else:
			actor=room.spawn_enemy(Vector2(float(record.position[0]),float(record.position[1])),"",int(record.level),{"profile":p,"static_actor":record.static_actor,"actor_kind":record.kind,"reward_enabled":record.reward,"reward_spawn_id":record.receipt,"zone_index":int(record.zone)})
		if not is_instance_valid(actor): return false
		actor.health.current=record.hp
		actor.set_meta("b10_guard_rounds",int(record.guard_rounds))
		if record.id=="B10-CORE": actor.set_meta("b10_star_core",true)
		if not record.anchor.is_empty(): actor.set_meta("enemy_skill_anchor_kind",record.anchor)
		actors.append(actor)
		instance_map[str(int(record.old_instance))]=actor.get_instance_id()
	for index in actors.size():
		var actor: Node2D=actors[index]
		var record: Dictionary=value.actors[index]
		if int(record.owner)>=0: actor.owner_enemy=weakref(actors[int(record.owner)])
		for key: String in ACTOR_FIELDS: actor.set(key,_unpack(record.state[key],actors,room.player,instance_map))
		for key: String in record.brain:
			var decoded: Variant=_unpack(record.brain[key],actors,room.player,instance_map)
			if key=="_rebuild_used": decoded=_integer_keys(decoded)
			actor.brain.set(key,decoded)
		if record.kind=="boss": actor.brain._last_actor=weakref(actor)
		actor.status.states=_unpack(record.states,actors,room.player,instance_map)
		actor.status.guards=_unpack(record.guards,actors,room.player,instance_map)
		actor.status.clock=float(record.status_clock)
		actor.status.shock_cooldown=float(record.shock_cooldown)
	for key: String in COLLECTIONS:
		var typed: Array[Dictionary]=[]
		for record: Dictionary in value.collections[key]: typed.append(_unpack(record,actors,room.player,instance_map))
		room.enemy_skills.set(key,typed)
	var extension: RefCounted=room.enemy_skills.b10
	var state: Dictionary=value.extension
	for key: String in ["clock","serial","current_phase","exposed_phase","ordinary_initialized"]: extension.set(key,state[key])
	extension.cores.assign(_unpack(state.cores,actors,room.player,instance_map))
	extension.effects.assign(_unpack(state.effects,actors,room.player,instance_map))
	extension.repaired=_integer_keys(_unpack(state.repaired,actors,room.player,instance_map))
	extension.links.clear()
	extension.echo_ready.clear()
	for key: String in state.links:
		if int(key)>=0 and int(key)<actors.size(): extension.links[actors[int(key)].get_instance_id()]=int(state.links[key])
	for key: String in state.echo_ready:
		if int(key)>=0 and int(key)<actors.size(): extension.echo_ready[actors[int(key)].get_instance_id()]=float(state.echo_ready[key])
	extension.hit_receipts.clear()
	for key: String in state.hit_receipts:
		var cut:=key.rfind(":")
		var old_id:=key.substr(cut+1)
		if instance_map.has(old_id): extension.hit_receipts[key.substr(0,cut+1)+str(instance_map[old_id])]=float(state.hit_receipts[key])
	extension.boss_ref=weakref(actors[int(state.boss)]) if int(state.boss)>=0 and int(state.boss)<actors.size() else null
	for index in extension.cores.size():
		var core: Node2D=extension.cores[index].actor.get_ref()
		if is_instance_valid(core): core.health.depleted.connect(extension._core_destroyed.bind(index,weakref(core)))
	for effect: Dictionary in extension.effects:
		if str(effect.get("kind",""))!="stone": continue
		var stone: Node2D=effect.target.get_ref()
		if not is_instance_valid(stone) or stone.owner_enemy==null: continue
		var caster: Node2D=stone.owner_enemy.get_ref()
		if is_instance_valid(caster):
			stone.health.depleted.connect(func() -> void:
				if room.difficulty>=4 and is_instance_valid(caster): extension._recover(caster,2.0))
	for motion: Dictionary in room.enemy_skills.motions:
		var actor: Node2D=room.enemy_skills._owner(motion)
		if is_instance_valid(actor): actor.set_meta("enemy_skill_motion",true)
	return true

static func _pack(value: Variant, indices: Dictionary) -> Variant:
	if value is Vector2: return {"$v":[value.x,value.y]}
	if value is Color: return {"$c":[value.r,value.g,value.b,value.a]}
	if value is WeakRef:
		var actor: Object=value.get_ref()
		return {"$ref":indices.get(actor.get_instance_id(),-1) if is_instance_valid(actor) else -1}
	if value is StringName: return str(value)
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[str(key)]=_pack(value[key],indices)
		return result
	if value is Array:
		var result: Array=[]
		for child: Variant in value: result.append(_pack(child,indices))
		return result
	return value

static func _unpack(value: Variant, actors: Array, player: Node2D, instances: Dictionary) -> Variant:
	if value is Dictionary:
		if value.has("$v"): return Vector2(float(value["$v"][0]),float(value["$v"][1]))
		if value.has("$c"): return Color(float(value["$c"][0]),float(value["$c"][1]),float(value["$c"][2]),float(value["$c"][3]))
		if value.has("$ref"):
			var index:=int(value["$ref"])
			return weakref(player) if index==-2 else weakref(actors[index]) if index>=0 and index<actors.size() else weakref(RefCounted.new())
		var result: Dictionary={}
		for key: String in value: result[key]=_unpack(value[key],actors,player,instances)
		if result.get("owner") is WeakRef and is_instance_valid(result.owner.get_ref()): result["owner_id"]=result.owner.get_ref().get_instance_id()
		if result.has("hit_ids"):
			result.hit_ids=result.hit_ids.map(func(id: Variant) -> int: return int(instances.get(str(int(id)),0)))
		return result
	if value is Array:
		var result: Array=[]
		for child: Variant in value: result.append(_unpack(child,actors,player,instances))
		return result
	return value

static func _integer_keys(value: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: Variant in value: result[int(key)]=value[key]
	return result

static func _vector(value: Variant) -> bool:
	return value is Dictionary and value.size()==1 and value.has("$v") and _json(value)

static func _reference(value: Variant, count: int, empty: bool = true) -> bool:
	return value is Dictionary and value.size()==1 and value.has("$ref") and _integer(value["$ref"],-1 if empty else 0,count-1)

static func _references_valid(value: Variant, count: int) -> bool:
	if value is Dictionary:
		if value.has("$ref"): return _integer(value["$ref"],-2,count-1)
		for child: Variant in value.values():
			if not _references_valid(child,count): return false
	elif value is Array:
		for child: Variant in value:
			if not _references_valid(child,count): return false
	return true

static func _index(key: String, count: int) -> bool:
	return key.is_valid_int() and str(int(key))==key and int(key)>=0 and int(key)<count

static func _command(value: Variant, count: int) -> bool:
	if not value is Dictionary or not _json(value) or not _references_valid(value,count): return false
	if value.is_empty(): return true
	if value.get("kind","") not in ["melee","projectile","charge","ground_area","b10_stance","b10_guard","b10_transfer","b10_reposition","b10_repair","b10_harmonize","b10_waymark","b10_summon","b10_scale_stone"]: return false
	if value.get("shape","") not in ["circle","cone","line","ring"]: return false
	for key: String in ["origin","target","direction","position","start","last_position","transfer_destination"]:
		if value.has(key) and not _vector(value[key]): return false
	for key: String in ["damage","remaining","range","radius","width","speed","duration","elapsed","travel_distance","distance_left","next_tick","tick_interval"]:
		if value.has(key) and not _number(value[key],10000000 if key=="damage" else 86400): return false
	for key: String in ["points","targets","waypoints"]:
		if not value.has(key): continue
		if not value[key] is Array: return false
		for point: Variant in value[key]:
			if not _vector(point): return false
	if value.has("paths"):
		if not value.paths is Array or value.paths.size()>5: return false
		for path: Variant in value.paths:
			if not path is Array or path.size()<2 or path.size()>4: return false
			for point: Variant in path:
				if not _vector(point): return false
	if value.has("hit_ids"):
		if not value.hit_ids is Array: return false
		for id: Variant in value.hit_ids:
			if not _integer(id,1,9223372036854775807): return false
	if value.has("followups"):
		if not value.followups is Array or value.followups.size()>8: return false
		for follow: Variant in value.followups:
			if not _command(follow,count): return false
	return true

static func _brain(value: Dictionary, boss: bool, count: int) -> bool:
	var fields: Array=BOSS_BRAIN if boss else ENEMY_BRAIN
	if value.size()!=fields.size() or not value.has_all(fields) or not _command(value.command,count): return false
	if boss:
		if not _integer(value.phase,1,3) or value.state not in ["emerging","phase_shift","recovery","telegraph","locked","core_rebuild"] or not value.stopped is bool or not value._cores_initialized is bool or not value.current_action is String or not value.weakpoint is String: return false
		for key: String in ["state_time","state_duration","weakpoint_time","elapsed","_recovery_elapsed","_rebuild_at"]:
			if not _number(value[key],86416): return false
		for key: String in ["action_index","_cast_serial"]:
			if not _integer(value[key],0,1000000): return false
		if not _integer(value._rebuild_index,-1,2) or not _command(value._released_pose,count): return false
		for key: String in ["_actions_used","_action_ready_at","_rebuild_used"]:
			if not value[key] is Dictionary: return false
		for key: String in value._actions_used:
			if not _integer(value._actions_used[key],0,1000000): return false
		for key: String in value._action_ready_at:
			if not _number(value._action_ready_at[key],86430): return false
		for key: String in value._rebuild_used:
			if not _index(key,3) or value._rebuild_used[key]!=true: return false
	else:
		if value.phase not in ["emerging","chase","telegraph","locked","execute","recovery"] or not value.active is bool or not _vector(value.locked_origin): return false
		for key: String in ["cooldown","remaining","duration"]:
			if not _number(value[key],300): return false
		for key: String in ["cycle","serial"]:
			if not _integer(value[key],0,1000000): return false
	return true

static func _status(states: Dictionary, guards: Dictionary) -> bool:
	for key: String in states:
		var state: Variant=states[key]
		if key not in preload("res://scripts/domain/combat/combat_status.gd").VALID_STATES or not state is Dictionary or not state.has_all(["remaining","tick","power","H","applied_at"]): return false
		for field: String in ["remaining","tick","power","H","applied_at"]:
			if not _number(state[field],10000000): return false
	for guard: Variant in guards.values():
		if not guard is Dictionary or not guard.has_all(["remaining","amount"]) or not _number(guard.remaining,86400) or not _number(guard.amount,10000000): return false
	return true

static func _number(value: Variant, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=minimum and value<=maximum

static func _point(value: Variant, room_id: String) -> bool:
	return value is Array and value.size()==2 and _number(value[0],3000) and _number(value[1],2000) and Geometry.anchor_clearance(room_id,Vector2(float(value[0]),float(value[1])))>=0

static func _json(value: Variant, depth: int = 0) -> bool:
	if depth>16: return false
	if value==null or value is bool: return true
	if value is int or value is float: return is_finite(float(value)) and absf(float(value))<=9223372036854775807.0
	if value is String: return value.length()<=512
	if value is Array:
		if value.size()>512: return false
		for child: Variant in value:
			if not _json(child,depth+1): return false
		return true
	if value is Dictionary:
		if value.size()>512: return false
		if value.has("$v"):
			if value.size()!=1 or not value["$v"] is Array or value["$v"].size()!=2: return false
			for coordinate: Variant in value["$v"]:
				if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate))>100000: return false
			return true
		if value.has("$c"):
			if value.size()!=1 or not value["$c"] is Array or value["$c"].size()!=4: return false
			for component: Variant in value["$c"]:
				if not _number(component,1): return false
			return true
		if value.has("$ref"): return value.size()==1 and _integer(value["$ref"],-2,23)
		for key: Variant in value:
			if not key is String or key.length()>160 or not _json(value[key],depth+1): return false
		return true
	return false
