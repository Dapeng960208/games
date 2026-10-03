extends RefCounted
## Diagnostic-only; not required by B06 or the production save contract.
## Closed, isolated B06 hostile-combat checkpoint. Rebuilds hostile actors and
## frozen commands; never writes Game's production expedition/save schema.
## Player casts/projectiles/deployments fail closed until their complete action
## serializers are available. They are never silently dropped on restoration.
const Codec = preload("res://scripts/combat/b06_combat_state_codec.gd")
const HeroSnapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Skills = preload("res://scripts/combat/b06_enemy_skills.gd")
const Geometry = preload("res://scripts/world/b06_room_geometry.gd")
const ACTOR_FIELDS := ["position","velocity","state","state_time","aim_direction","knockback","_pushes","hurt_flash","burn_remaining","burn_tick","lifetime","reaction_cooldown","reaction_remaining","navigation_timer","navigation_vector","aggro_target","aggro_hold","_biome_counters","_ordinary_slow_remaining","_ordinary_slow_multiplier"]
const ROOM_FIELDS := ["activated_encounters","encounter_progress","_encounter_spawn_retry","_natural_spawn_serial","elapsed","wave","objective_complete","objective_rewarded","_completion_emitted","_boss_defeated"]
var last_error := ""
func _reject(reason: String) -> Dictionary:
	last_error = reason
	return {}
func _supported(room: Node2D) -> bool:
	if not Game.profile_path.contains("test_b06_") or Game.run == null or not bool(room.layout.get("b06_candidate",false)): return false
	if not room.player.velocity.is_zero_approx() or room.player.abilities.busy() or room.player.dash_remaining>0 or room.player.attack_remaining>0 or room.player.attack_buffer>0 or not room.player._pending_skill_slot.is_empty() or not room.player.knockback.is_zero_approx() or room.projectiles.get_child_count()>0: return false
	for deployed in room.get_tree().get_nodes_in_group("hero_deployments"):
		if deployed.room == room: return false
	return true
func capture(room: Node2D) -> Dictionary:
	last_error = ""
	if not _supported(room): return _reject("Player action/projectile/deployment or non-isolated profile is not supported by this candidate format.")
	var bindings := {"player":room.player}
	var ordinal := 0
	for actor in room.enemies.get_children():
		if not actor.is_alive() or actor.is_queued_for_deletion(): return _reject("Retire pending deaths before capture.")
		var id := "boss:BO06" if actor.actor_kind == "boss" else str(actor.get_meta("b06_checkpoint_id",""))
		for bound_id: String in room.b06_mechanics._actors:
			if room.b06_mechanics._actors[bound_id].actor.get_ref() == actor: id = bound_id; break
		if id.is_empty():
			id = "actor:%d" % ordinal
			while bindings.has(id): ordinal += 1; id = "actor:%d" % ordinal
			actor.set_meta("b06_checkpoint_id",id)
		if bindings.has(id): return _reject("Duplicate stable actor identity.")
		bindings[id] = actor
		ordinal += 1
	if bindings.size()>65: return _reject("Actor snapshot limit exceeded.")
	var to_id := func(actor: Node2D) -> String:
		for id: String in bindings:
			if bindings[id] == actor: return id
		return ""
	var records: Array = []
	for id: String in bindings:
		if id == "player": continue
		var actor: Node2D = bindings[id]
		var values := {}
		for field: String in ACTOR_FIELDS: values[field] = actor.get(field)
		var status := {"clock":actor.status.clock,"shock_cooldown":actor.status.shock_cooldown,"states":actor.status.states,"guards":actor.status.guards,"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}
		var metadata := {}
		for key in actor.get_meta_list():
			if str(key).begins_with("b06_") or str(key).begins_with("enemy_skill_"): metadata[str(key)] = actor.get_meta(key)
		var record := {"id":id,"profile":actor.profile,"kind":actor.actor_kind,"static":actor.static_actor,"spawn_id":actor.reward_spawn_id,"zone":actor.zone_index,"maximum":actor.health.maximum,"hp":actor.health.current,"parent_actor":actor.owner_enemy,"values":values,"status":status,"metadata":metadata,"brain":{}}
		if actor.brain != null:
			if not actor.brain.has_method("capture_candidate"): return _reject("Actor brain has no candidate serializer.")
			record.brain = actor.brain.capture_candidate(to_id)
			if record.brain.is_empty(): return _reject("Actor command contains an unsupported reference.")
		var brain_saved: Dictionary = record.brain
		record.erase("brain")
		var encoded := Codec.encode(record,to_id)
		if not encoded.ok: return _reject("Actor values contain unsupported state.")
		encoded.value["brain"] = brain_saved
		records.append(encoded.value)
	var room_values := {}
	for field: String in ROOM_FIELDS: room_values[field] = room.get(field)
	# Encounter dictionaries have integer keys; keep them explicit across JSON.
	for field: String in ["activated_encounters","encounter_progress","_encounter_spawn_retry"]:
		var mapped := {}
		for key in room_values[field]: mapped[str(int(key))] = room_values[field][key]
		room_values[field] = mapped
	var encoded_room := Codec.encode(room_values,to_id)
	var runtime: Dictionary = room.enemy_skills.b06.capture_candidate(to_id)
	var hero := HeroSnapshot.capture(room)
	if runtime.is_empty() or hero.is_empty() or not encoded_room.ok: return _reject("Runtime, hero or encounter state is not serializable.")
	return {"version":1,"format":"b06_hostile_combat","room_id":room.layout_id,"difficulty":room.difficulty,"hero_id":Game.run.hero_id,"hero":hero,"player_position":[room.player.position.x,room.player.position.y],"actors":records,"room":encoded_room.value,"runtime":runtime,"tide":room.b06_mechanics.checkpoint()}
func restore(room: Node2D, value: Dictionary) -> bool:
	last_error = ""
	if not _supported(room): last_error = "Current player action cannot be overwritten."; return false
	if value.size()!=11 or not value.has_all(["version","format","room_id","difficulty","hero_id","hero","player_position","actors","room","runtime","tide"]): return false
	if value.version!=1 or value.format!="b06_hostile_combat" or value.room_id!=room.layout_id or value.difficulty!=room.difficulty or value.hero_id!=Game.run.hero_id: return false
	if not value.actors is Array or value.actors.size()>64 or not value.hero is Dictionary or not HeroSnapshot.validate(value.hero,Game.run.hero_id,Game.run.stats): return false
	if not value.player_position is Array or value.player_position.size()!=2 or not Codec._number(value.player_position[0]) or not Codec._number(value.player_position[1]): return false
	var player_position := Vector2(value.player_position[0],value.player_position[1])
	if not Geometry2D.is_point_in_polygon(player_position,Geometry.polygon(room.layout_id)): return false
	var tide_probe := preload("res://scripts/world/b06_tide_runtime.gd").new()
	if not tide_probe.configure(room.layout_id,room.difficulty) or not value.tide is Dictionary or not tide_probe.restore_checkpoint(value.tide): tide_probe.free(); return false
	# Detached actor staging prevents rejected saves from replacing the current
	# population. Actors' ready hooks require a tree, but their processing is off.
	var staging := Node2D.new()
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	room.add_child(staging)
	var bindings := {"player":room.player}
	var records: Array = []
	var ok := true
	for raw: Variant in value.actors:
		if not raw is Dictionary or raw.size()!=13 or not raw.has_all(["id","profile","kind","static","spawn_id","zone","maximum","hp","parent_actor","values","status","metadata","brain"]): ok=false; break
		if not raw.id is String or raw.id.is_empty() or bindings.has(raw.id) or not raw.profile is Dictionary or not raw.static is bool or not raw.spawn_id is String or not raw.brain is Dictionary: ok=false; break
		if raw.kind not in ["enemy","boss","hazard_endpoint"] or not Codec._number(raw.maximum) or not Codec._number(raw.hp) or float(raw.hp)<=0 or float(raw.hp)>float(raw.maximum) or float(raw.maximum)>1e8: ok=false; break
		if not Codec._number(raw.zone) or int(raw.zone)!=raw.zone or int(raw.zone)<-1 or int(raw.zone)>1: ok=false; break
		var decoded_profile := Codec.decode(raw.profile,func(_id): return null)
		if not decoded_profile.ok or not decoded_profile.value is Dictionary: ok=false; break
		var profile: Dictionary = decoded_profile.value
		if int(profile.get("ruleset_version",0))!=2: ok=false; break
		if raw.kind=="boss" and profile.get("enemy_id")!="BO06": ok=false; break
		if raw.kind=="enemy" and Skills.profile(str(profile.get("enemy_id","")),int(profile.get("enemy_level",0)),room.difficulty,str(profile.get("rank","normal")),profile.get("enemy_calibration_snapshot",{}),int(profile.get("b06_numerical_version",1))).is_empty(): ok=false; break
		if raw.kind=="hazard_endpoint" and not bool(raw.static): ok=false; break
		if raw.kind!="hazard_endpoint":
			var canonical: Dictionary = Skills.boss_profile(room.difficulty,profile.get("enemy_calibration_snapshot",{}),int(profile.get("b06_numerical_version",1))) if raw.kind=="boss" else Skills.profile(str(profile.enemy_id),int(profile.enemy_level),room.difficulty,str(profile.get("rank","normal")),profile.get("enemy_calibration_snapshot",{}),int(profile.get("b06_numerical_version",1)))
			if canonical.is_empty(): ok=false; break
			if raw.kind=="boss" and (tide_probe.boss_state==null or int(tide_probe.boss_state.snapshot().maximum_hp)!=int(canonical.max_hp)): ok=false; break
			for field: String in ["max_hp","damage","armor","magic_resist","move_speed","navigation_radius","enemy_level","ruleset_version"]:
				if not Codec._number(profile.get(field)) or absf(float(profile.get(field))-float(canonical.get(field))) > 0.00000001: last_error="Profile mismatch: "+field+" "+str(profile.get(field))+" / "+str(canonical.get(field)); ok=false; break
			if not ok: break
			if float(raw.maximum)>float(canonical.max_hp): ok=false; break
		var actor: Node2D = load("res://scripts/combat/boss.gd").new() if raw.kind=="boss" else load("res://scenes/enemy.tscn").instantiate()
		actor.room = room
		actor.configure(profile,{"reward_enabled":false,"actor_kind":raw.kind,"static_actor":raw.static,"zone_index":int(raw.zone),"reward_spawn_id":raw.spawn_id})
		staging.add_child(actor)
		actor.health.reset(float(raw.maximum),2)
		actor.health.current = raw.hp
		bindings[str(raw.id)] = actor
		records.append(raw)
	var resolver := func(id: String) -> Node2D: return bindings.get(id)
	var decoded_records: Array = []
	if ok:
		for raw: Dictionary in records:
			var without_brain: Dictionary = raw.duplicate(true)
			without_brain.erase("brain")
			var decoded := Codec.decode(without_brain,resolver)
			if not decoded.ok or not decoded.value is Dictionary: ok=false; break
			var record: Dictionary = decoded.value
			var actor: Node2D = bindings[record.id]
			if not record.values is Dictionary or record.values.size()!=ACTOR_FIELDS.size() or not record.values.has_all(ACTOR_FIELDS) or not record.values.position is Vector2 or not Geometry2D.is_point_in_polygon(record.values.position,Geometry.polygon(room.layout_id)): ok=false; break
			if not _actor_values_valid(record.values): last_error="Actor values rejected: "+str(record.id); ok=false; break
			if not record.metadata is Dictionary or not record.status is Dictionary or not HeroSnapshot._status_valid(record.status,float(record.maximum),true): ok=false; break
			if actor.brain != null and (not actor.brain.has_method("validate_candidate") or not actor.brain.validate_candidate(raw.brain,resolver)): last_error="Brain validation rejected: "+str(raw.id); ok=false; break
			if actor.brain == null and not raw.brain.is_empty(): ok=false; break
			if record.kind=="boss" and int(record.maximum)!=int(record.profile.max_hp): ok=false; break
			if record.kind=="enemy":
				var expected_maximum := int(record.profile.max_hp)
				if record.parent_actor is WeakRef and record.parent_actor.get_ref().actor_kind=="boss": expected_maximum=int(roundf(expected_maximum*.5))
				if int(record.maximum)!=expected_maximum: ok=false; break
			actor.owner_enemy = record.parent_actor
			actor.position = record.values.position
			for key: String in record.metadata: actor.set_meta(key,record.metadata[key])
			decoded_records.append(record)
	var decoded_room := Codec.decode(value.room,resolver)
	if not decoded_room.ok or not decoded_room.value is Dictionary or decoded_room.value.size()!=ROOM_FIELDS.size() or not decoded_room.value.has_all(ROOM_FIELDS): ok=false
	if ok and not _room_values_valid(decoded_room.value): ok=false
	if ok and not room.enemy_skills.b06.validate_candidate(value.runtime,resolver): last_error="Runtime validation rejected"; ok=false
	if not ok:
		if last_error.is_empty(): last_error = "Staged actor, brain, encounter or runtime validation rejected."
		staging.free()
		tide_probe.free()
		return false
	# Every external/runtime validator has accepted. Commit the staged actor set.
	room.enemy_skills.reset_room()
	for actor in room.enemies.get_children(): actor.free()
	room.b06_mechanics._actors.clear()
	room.b06_mechanics._bindings.clear()
	room._boss_actor = null
	for record: Dictionary in decoded_records:
		var actor: Node2D = bindings[record.id]
		actor.reparent(room.enemies)
		actor.health.reset(float(record.maximum),2)
		actor.health.current = record.hp
		actor.owner_enemy = record.parent_actor
		for field: String in ACTOR_FIELDS:
			if field=="_pushes": actor._pushes.assign(record.values[field])
			elif field=="state": actor.state=StringName(record.values[field])
			else: actor.set(field,record.values[field])
		actor.status.clock = float(record.status.clock)
		actor.status.shock_cooldown = float(record.status.shock_cooldown)
		actor.status.states = record.status.states
		actor.status.guards = record.status.guards
		for key: String in record.metadata: actor.set_meta(key,record.metadata[key])
		actor.set_meta("b06_checkpoint_id",record.id)
		if actor.actor_kind=="boss":
			room._boss_actor = actor
			actor.completed.connect(func(_id,_payload): room._boss_defeated=true)
		else: room.b06_mechanics.register_actor(str(record.id),actor)
		if actor.brain != null: actor.brain.restore_candidate(records[decoded_records.find(record)].brain,resolver)
	for field: String in ROOM_FIELDS:
		var restored: Variant = decoded_room.value[field]
		if field in ["activated_encounters","encounter_progress","_encounter_spawn_retry"]:
			var numeric := {}
			for key: String in restored: numeric[int(key)] = restored[key]
			restored = numeric
		room.set(field,restored)
	room.b06_mechanics.restore_checkpoint(value.tide)
	if is_instance_valid(room._boss_actor): room.b06_mechanics.bind_boss(room._boss_actor)
	HeroSnapshot.restore(room,value.hero)
	room.player.position = player_position
	room.enemy_skills.b06.restore_candidate(value.runtime,resolver)
	staging.free()
	tide_probe.free()
	return true

func _actor_values_valid(values: Dictionary) -> bool:
	for key: String in ["position","velocity","aim_direction","knockback","navigation_vector"]:
		if not values[key] is Vector2 or not values[key].is_finite(): return false
	if values.state not in ["emerging","idle","chase","reposition","windup","telegraph","locked","execute","recovery","phase_shift"]: return false
	for key: String in ["state_time","hurt_flash","burn_remaining","burn_tick","lifetime","reaction_cooldown","reaction_remaining","navigation_timer","aggro_hold","_ordinary_slow_remaining","_ordinary_slow_multiplier"]:
		if not Codec._number(values[key]) or (key!="navigation_timer" and float(values[key])<0): return false
	if not values.aggro_target is WeakRef and values.aggro_target!=null: return false
	if not values._biome_counters is Dictionary or not values._pushes is Array or values._pushes.size()>16: return false
	for push: Variant in values._pushes:
		if not push is Dictionary or not push.has_all(["travel","elapsed","duration"]) or not push.travel is Vector2 or not Codec._number(push.elapsed) or not Codec._number(push.duration) or float(push.elapsed)<0 or float(push.duration)<=0 or float(push.elapsed)>float(push.duration): return false
	return true
func _room_values_valid(values: Dictionary) -> bool:
	for key: String in ["activated_encounters","encounter_progress","_encounter_spawn_retry"]:
		if not values[key] is Dictionary or values[key].size()>2: return false
		for zone: String in values[key]:
			if not zone.is_valid_int() or int(zone)<0 or int(zone)>1 or zone!=str(int(zone)): return false
	for key: String in ["_natural_spawn_serial","elapsed","wave"]:
		if not Codec._number(values[key]) or float(values[key])<0: return false
	for key: String in ["objective_complete","objective_rewarded","_completion_emitted","_boss_defeated"]:
		if not values[key] is bool: return false
	if values.objective_rewarded: return false
	for zone: String in values.encounter_progress:
		var progress: Variant = values.encounter_progress[zone]
		if not progress is Dictionary or not progress.has_all(["plan","next_wave","reinforce_elapsed"]) or not progress.plan is Dictionary or not progress.plan.get("waves") is Array: return false
		if not Codec._number(progress.next_wave) or progress.next_wave!=int(progress.next_wave) or int(progress.next_wave)<0 or int(progress.next_wave)>progress.plan.waves.size(): return false
		if not Codec._number(progress.reinforce_elapsed) or float(progress.reinforce_elapsed)<0: return false
	return true
