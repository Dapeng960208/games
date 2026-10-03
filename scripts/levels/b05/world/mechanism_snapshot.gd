extends RefCounted
## Pure JSON validator: safe to preload from save validation, no scene/autoload.
const Geometry = preload("res://scripts/levels/b05/world/room_geometry.gd")
const Numbers = preload("res://scripts/levels/b05/combat/enemy_numbers.gd")
const Network = preload("res://scripts/levels/b05/world/root_network.gd")
const SHIELD_SECONDS := 12.0

static func validate_checkpoint(value: Variant) -> bool:
	if not value is Dictionary: return false
	var keys: Array = ["version","room_id","shield_duration","interaction_radius","gate_positions","network","production_version","difficulty","well_modes","well_activation","boss_phase","boss_cycle","plant_guards"]
	if value.get("production_version") == 2: keys.append("sunleaf_closed")
	if not _keys(value,keys): return false
	if value.version != 1 or not _integer(value.production_version,1,2) or not _integer(value.difficulty,0,4): return false
	if value.shield_duration != SHIELD_SECONDS or value.interaction_radius != 68.0: return false
	if not value.room_id is String: return false
	var definition := Geometry.room(value.room_id)
	if definition.is_empty(): return false
	if value.production_version == 2:
		if not value.sunleaf_closed is Dictionary or value.sunleaf_closed.size()!=definition.get("spotlights",[]).size(): return false
		for spec: Dictionary in definition.get("spotlights",[]):
			if not value.sunleaf_closed.get(str(spec.id)) is bool: return false
	var frontline := Numbers.ordinary("B05-M01",int(definition.enemy_level),int(value.difficulty),"normal",{},1)
	if frontline.is_empty(): return false
	var wells := {}
	var gates := {}
	var positions := {}
	for spec: Dictionary in definition.get("root_wells",[]):
		var at := Geometry.world_point(spec.position)
		wells[spec.id] = {"x":at.x,"y":at.y,"frontline_hp":frontline.max_hp,"network_id":spec.network_id}
	for spec: Dictionary in definition.get("gates",[]):
		var at := Geometry.world_point(spec.position)
		gates[spec.id] = {"x":at.x,"y":at.y,"well_ids":spec.well_ids,"bridge_id":spec.bridge_id}
		positions[spec.id] = {"x":at.x,"y":at.y}
	if not value.gate_positions is Dictionary or value.gate_positions.size()!=positions.size() or not value.network is Dictionary: return false
	for id in positions:
		if not value.gate_positions.get(id) is Dictionary or not _keys(value.gate_positions[id],["x","y"]): return false
		for axis in ["x","y"]:
			if not _number(value.gate_positions[id][axis],-10000,10000) or absf(float(value.gate_positions[id][axis])-float(positions[id][axis]))>0.000001: return false
	var state: Dictionary = value.network
	if not _keys(state,["version","wells","gates","cooldowns","locks","channel"]): return false
	for field: String in ["wells","gates","cooldowns","locks","channel"]:
		if not state[field] is Dictionary or state[field].size() > 128: return false
	for id in state.wells:
		if not _id(id) or not state.wells[id] is Dictionary or not _keys(state.wells[id],["x","y","network_id","maximum","hp","closed"]): return false
	for id in state.gates:
		if not _id(id) or not state.gates[id] is Dictionary or not _keys(state.gates[id],["well_ids","bridge_id","open"]): return false
	for timers: Dictionary in [state.cooldowns,state.locks]:
		for id in timers:
			if not _id(id) or not _number(timers[id],0,12): return false
	if not state.channel.is_empty() and not _keys(state.channel,["gate_id","actor_id","remaining"]): return false
	var network := Network.new()
	if not network.configure(wells,gates) or not network.restore(state): return false
	if not value.well_activation is Dictionary or value.well_activation.size() != wells.size(): return false
	for id in wells:
		if not value.well_activation.get(id) is bool: return false
	if not value.well_modes is Dictionary or value.well_modes.size() > wells.size(): return false
	for id in value.well_modes:
		var mode: Variant = value.well_modes[id]
		if not wells.has(id) or not mode is Dictionary or not _keys(mode,["mode","remaining"]) or mode.mode not in ["shield","speed"] or not _number(mode.remaining,0,6): return false
	if not _integer(value.boss_phase,0,3) or not _number(value.boss_cycle,0,6): return false
	if value.room_id == "BO05" and int(value.boss_phase) > 0:
		var scheduled := 0
		for enabled: bool in value.well_activation.values():
			if enabled: scheduled += 1
		if scheduled != (1 if int(value.boss_phase) == 1 else 2): return false
	if not value.plant_guards is Dictionary or value.plant_guards.size() > 128: return false
	for id in value.plant_guards:
		var plant: Variant = value.plant_guards[id]
		if not _id(id) or not plant is Dictionary or not _keys(plant,["enemy_id","maximum_hp","guard"]): return false
		if not plant.enemy_id is String or Numbers.ordinary(plant.enemy_id,int(definition.enemy_level),int(value.difficulty)).is_empty(): return false
		if not _number(plant.maximum_hp,1,100000000) or not plant.guard is Dictionary: return false
		if not plant.guard.is_empty():
			if not _keys(plant.guard,["amount","remaining"]) or not _number(plant.guard.amount,0,ceilf(float(plant.maximum_hp)*0.12)) or not _number(plant.guard.remaining,0,SHIELD_SECONDS): return false
	return true

static func _keys(value: Dictionary, names: Array) -> bool:
	if value.size() != names.size(): return false
	for name in names:
		if not value.has(name): return false
	return true
static func _id(value: Variant) -> bool:
	return value is String and value.length() > 0 and value.length() <= 160
static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,minimum,maximum) and float(value) == floorf(float(value))
