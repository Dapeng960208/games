extends "res://tests/levels/b05/test_b05_balance_matrix.gd"
func initialize_directed_scenario() -> void:
	check(str(config.hero_id)=="CH01" and controlled_room_id.is_empty(),"counter skill sensitivity is separate warrior Boss diagnostic")
	var policy:=arg("counter-policy","all_skills")
	check(policy in ["all_skills","q_approach"],"predeclared legal counter policy")
	driver=preload("res://tests/support/b05_counter_skill_controller.gd").new()
	driver.counter_policy=policy
	driver.configure(room)
	config["experiment"]="legal_counter_skill_sensitivity:"+policy
	fixture["controller_policy"]={"version":"b05-root-counter-sensitivity-v1","name":policy,"baseline":"b05-zero-basic-controller-v1 unchanged","no_damage_resource_cooldown_or_geometry_override":true,"not_part_of_frozen_acceptance_matrix":true}
