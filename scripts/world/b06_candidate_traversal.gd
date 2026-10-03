extends RefCounted
## Explicit isolated traversal. Does not mutate chapter unlocks, expedition node
## transactions or rewards. In-progress hostile checkpoint support is separate.
const Candidate = preload("res://scripts/world/b06_candidate.gd")
const CombatSnapshot = preload("res://scripts/combat/combat_snapshot.gd")
var room: Node2D
var node_index := -1
var difficulty := 0
var seed_value := 0
var finished := false
var _changing := false
var last_error := ""
func configure(host: Node2D, selected_difficulty: int, selected_seed: int) -> bool:
	if room != null or not is_instance_valid(host) or selected_difficulty < 0 or selected_difficulty > 4: return false
	# A candidate must never borrow the player's normal profile location.
	if not Game.profile_path.contains("test_b06_") or Game.run == null: return false
	room = host
	difficulty = selected_difficulty
	seed_value = selected_seed
	room.interaction_requested.connect(_requested)
	return true
func start() -> bool:
	if node_index != -1 or not is_instance_valid(room): return false
	return _install(0)
func _context(index: int) -> Dictionary:
	var context: Dictionary = Candidate.route()[index].duplicate(true)
	context.merge({"node_index":index,"difficulty":difficulty,"seed":seed_value+index},true)
	return context
func _install(index: int) -> bool:
	if _changing or index < 0 or index >= Candidate.route().size(): return false
	_changing = true
	var context := _context(index)
	var previous: Dictionary = CombatSnapshot.capture(room)
	if not previous.is_empty(): context["runtime"] = previous
	var prepared: Dictionary = room.prepare_expedition_node(context)
	if not bool(prepared.get("valid",false)):
		last_error = str(prepared.get("error","candidate preparation failed"))
		_changing = false
		return false
	room.apply_prepared_expedition_node(prepared)
	node_index = index
	_changing = false
	return true
func advance(expected_index: int) -> bool:
	if _changing or finished or expected_index != node_index or not is_instance_valid(room) or not room.objective_complete: return false
	if room._living_enemy_count() > 0: return false
	if room.player.position.distance_to(room.exit_position) > 68: return false
	if not room.has_line_of_sight(room.player.position,room.exit_position): return false
	if node_index+1 == Candidate.route().size():
		finished = true
		room.set_input_blocked(true)
		return true
	return _install(node_index+1)
func _requested(kind: String, payload: Dictionary) -> void:
	if kind != "b06_candidate_next": return
	if not advance(int(payload.get("node_index",-1))): room.set_input_blocked(false)
func checkpoint() -> Dictionary:
	last_error = ""
	if not is_instance_valid(room) or node_index < 0 or not room.objective_complete or room._living_enemy_count() > 0:
		last_error = "Active hostile actor checkpoints are not admitted by the clear-boundary traversal format."
		return {}
	if room.projectiles.get_child_count() > 0 or room.enemy_skills.active_effect_count() > 0:
		last_error = "Wait for active projectiles and hostile effects to retire before this clear-boundary checkpoint."
		return {}
	var hero := CombatSnapshot.capture(room)
	if hero.is_empty() or not CombatSnapshot.validate(hero,Game.run.hero_id,Game.run.stats): return {}
	return {"version":1,"format":"b06_clear_boundary","room_id":room.layout_id,"node_index":node_index,"difficulty":difficulty,"seed":seed_value,"finished":finished,"hero":hero,"tide":room.b06_mechanics.checkpoint(),"profile_id":str(Game.profile.get("id","")),"hero_id":Game.run.hero_id}
func restore_checkpoint(value: Dictionary) -> bool:
	if not is_instance_valid(room) or _changing or value.size() != 11 or not value.has_all(["version","format","room_id","node_index","difficulty","seed","finished","hero","tide","profile_id","hero_id"]): return false
	if value.version != 1 or value.format != "b06_clear_boundary" or value.hero_id != Game.run.hero_id or value.profile_id != str(Game.profile.get("id","")): return false
	if not value.node_index is int and not value.node_index is float: return false
	if not is_finite(float(value.node_index)) or float(value.node_index) != floorf(float(value.node_index)): return false
	var index := int(value.node_index)
	if index < 0 or index >= Candidate.route().size() or value.room_id != Candidate.route()[index].room_id or value.difficulty != difficulty or value.seed != seed_value or not value.finished is bool: return false
	if bool(value.finished) and index != Candidate.route().size()-1: return false
	if not value.hero is Dictionary or not CombatSnapshot.validate(value.hero,Game.run.hero_id,Game.run.stats) or not value.tide is Dictionary: return false
	var probe := preload("res://scripts/world/b06_tide_runtime.gd").new()
	var tide_ok := probe.configure(str(value.room_id),difficulty) and probe.restore_checkpoint(value.tide)
	probe.free()
	if not tide_ok: return false
	if not _install(index): return false
	for actor in room.enemies.get_children(): actor.free()
	room.enemy_skills.reset_room()
	room._boss_actor = null
	room.objective_complete = true
	room.objective_rewarded = false
	room._completion_emitted = true
	if not room.b06_mechanics.restore_checkpoint(value.tide): return false
	if not CombatSnapshot.restore(room,value.hero): return false
	room.player.position = room.exit_position
	finished = bool(value.finished)
	room.set_input_blocked(finished)
	return true
