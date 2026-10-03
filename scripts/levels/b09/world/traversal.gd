extends RefCounted
## Finite candidate route. Gear rewards use its isolated profile only.
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
var room: Node2D
var node_index := -1
var difficulty := 0
var seed_value := 309
var finished := false
var last_error := ""
var _changing := false
var _rewarded: Dictionary = {}

func configure(host: Node2D, selected_difficulty: int, selected_seed: int) -> bool:
	if room != null or not is_instance_valid(host) or selected_difficulty not in range(5) or Game.run == null: return false
	if not Game.profile_path.begins_with("user://test_b09_candidate/"): return false
	room=host
	difficulty=selected_difficulty
	seed_value=selected_seed
	room.interaction_requested.connect(_requested)
	return true

func start() -> bool:
	return _install(0) if node_index == -1 else false

func _install(index: int) -> bool:
	if _changing or index not in range(Content.room_ids().size()): return false
	_changing=true
	var id: String=Content.room_ids()[index]
	var context := {"room_id":id,"biome_id":"B09","b09_candidate":true,"role":"boss" if id=="BO09" else "branch","reward_enabled":false,"node_index":index,"difficulty":difficulty,"seed":seed_value+index}
	var previous := Snapshot.capture(room)
	var prepared: Dictionary=room.prepare_expedition_node(context)
	if not bool(prepared.get("valid",false)):
		last_error=str(prepared.get("error","B09 layout unavailable"))
		_changing=false
		return false
	prepared["runtime"]=previous
	room.apply_prepared_expedition_node(prepared)
	node_index=index
	_changing=false
	return true

func advance(expected_index: int) -> bool:
	if _changing or finished or expected_index!=node_index or not is_instance_valid(room) or not room.objective_complete or room._living_enemy_count()>0: return false
	if room.player.position.distance_to(room.exit_position)>68 or not room.has_line_of_sight(room.player.position,room.exit_position): return false
	var inventory: Variant=room.get_meta("b09_inventory") if room.has_meta("b09_inventory") else null
	if inventory!=null and not _rewarded.has(node_index):
		if not inventory.clear_reward(room.layout_id,difficulty,seed_value+node_index):
			last_error=inventory.last_error
			return false
		_rewarded[node_index]=true
	if node_index+1==Content.room_ids().size():
		finished=true
		room.set_input_blocked(true)
		return true
	return _install(node_index+1)

func _requested(kind: String, payload: Dictionary) -> void:
	if kind=="b09_candidate_next" and not advance(int(payload.get("node_index",-1))): room.set_input_blocked(false)
