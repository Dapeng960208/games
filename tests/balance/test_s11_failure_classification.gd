extends "res://tests/balance/test_s11_battle_matrix.gd"
## Classification regression with the SAME real scene, fixture, AI and receiver.
## Only the declared test input policy stays idle. Natural incoming attacks may
## kill the player; no health, damage, phase, geometry or status is modified.
class IdleInput:
	extends RefCounted
	var rejected: Dictionary = {}
	var decisions: Array[Dictionary] = []
	func step(_time: float) -> void:
		pass

func initialize_directed_scenario() -> void:
	check(measurement_protocol.get("experiment")=="failure_classification","failure regression has an explicit separate protocol")
	config["experiment"]="failure_classification"
	driver=IdleInput.new()
	fixture["test_input_policy"]="Intentional idle input, real production scene/AI/receivers unchanged; not balance evidence"
	fixture["expected_outcome"]=arg("expected-outcome","time_limit")

func finish_record() -> void:
	super.finish_record()
	var row: Dictionary = rows.back()
	row["baseline_ttk_evidence"]=false
	row["directed_phase_releases"]={}
	row["tolerance"]={}
	check(row.outcome==arg("expected-outcome","time_limit"),"actual unchanged scene reaches expected failure outcome")
	check(bool(row.input_diagnostics.zero_offense) and bool(row.input_diagnostics.failed_before_offense),"failure retains explicit zero-offense diagnosis")
	check(int(row.input_diagnostics.controller_calls)>0 and int(row.input_diagnostics.controller_calls)==int(row.input_diagnostics.controller_opportunities),"declared idle controller was called normally")
	if row.outcome=="player_died": check(not trail.all_events.is_empty() and run_ref.hp==0,"actual native incoming receipt caused death")
