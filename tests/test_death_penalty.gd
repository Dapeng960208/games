extends SceneTree
const Learning = preload("res://scripts/core/field_learning.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var profile := {"hero_xp":{"CH01":180}}
	var record := {"hero_id":"CH01","kills":8,"demo":false,"expedition":{"phase":"combat","node_index":1,"completed_nodes":[],"room_entry_kills":0,"route":{"dynamic_version":2}}}
	check(Learning.calculate(record,profile,"death") == 0,"new dungeon discards unbanked kill XP")
	check(profile.hero_xp.CH01 == 180,"existing hero XP and level remain banked")
	record.expedition.route.dynamic_version = 1
	check(Learning.calculate(record,profile,"death") == 16,"historical run retains its settlement policy")
	check(Learning.calculate(record,profile,"extracted") == 0,"extraction never duplicates completed XP")
	check(Learning.calculate(record,profile,"abandoned") == 0,"abandonment cannot farm XP")
	print("DEATH PENALTY 5 checks; ",failures," failures")
	quit(1 if failures else 0)
