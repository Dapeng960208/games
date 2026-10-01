extends "res://tests/test_s11_battle_matrix.gd"
const ObservedSkills = preload("res://tests/support/s11_directed_enemy_skills.gd")
const REPRESENTATIVE_IDS := {1:"M05",2:"M15",3:"M22",4:"M34"}
var elite: MineEnemy

func scenario_room_role() -> String:
	return "entrance" # Production service arena, explicitly no authored wave.

func requires_room_objectives() -> bool:
	return false

func drives_room_objectives() -> bool:
	return false

func scenario_complete() -> bool:
	return not is_instance_valid(elite) or not elite.is_alive()

func initialize_directed_scenario() -> void:
	check(measurement_protocol.get("experiment")=="elite_fixture","separate elite actor protocol")
	config["experiment"]="elite_fixture"
	config["encounter"]="representative_elite"
	check(room.enemies.get_child_count()==0 and room.enemy_skills.active_effect_count()==0,"empty production service arena before controlled actor initialization")
	var native_skill_layer: int = room.enemy_skills.z_index
	room.enemy_skills.set_script(ObservedSkills)
	room.enemy_skills.configure(room)
	room.enemy_skills.z_index=native_skill_layer
	var id: String = REPRESENTATIVE_IDS[int(config.chapter)]
	var at := room.player.position+Vector2(260,0)
	for radius: float in [260.0,220.0,180.0]:
		var found := false
		for i in 16:
			var point: Vector2 = room.player.position+Vector2.from_angle(TAU*float(i)/16.0)*radius
			if room.valid_ground(point,45.0) and room.has_line_of_sight(room.player.position,point):
				at=point;found=true;break
		if found: break
	elite=room.spawn_enemy(at,id,int(config.chapter)*5,{"rank":"elite","reward_enabled":false,"zone_index":-1})
	check(is_instance_valid(elite) and elite.rank=="elite" and elite.enemy_level==int(config.chapter)*5,"production elite factory installed same chapter/level profile")
	fixture["directed_initial_conditions"]={"synthetic":true,"mode":"representative_elite","production_service_arena":room.layout.duplicate(true),"initialization_before_clock_and_physics":true,"elite_id":id,"elite_profile":elite.profile.duplicate(true) if is_instance_valid(elite) else {},"elite_initial_position":[elite.position.x,elite.position.y] if is_instance_valid(elite) else [],"player_hp":run_ref.hp,"player_shield":run_ref.shield,"player_resource":run_ref.resource,"reward_enabled":false,"scope":"One published representative elite per chapter, same ID/level across D0-D4; not authored elite-wave coverage or all eighteen natural behaviors."}

func requires_attack_evidence() -> bool:
	return false # A high-output legal first hit may end this single actor.

func finish_record() -> void:
	super.finish_record()
	var row: Dictionary = rows.back()
	row["baseline_ttk_evidence"]=false
	row["directed_phase_releases"]={}
	row["tolerance"]={}
	row["executed_enemy_commands"]=room.enemy_skills.executed_commands.duplicate(true)
	row["outcome"]="elite_defeated" if completed and run_ref.hp>0 else "player_died" if run_ref.hp<=0 else "elite_time_limit"
