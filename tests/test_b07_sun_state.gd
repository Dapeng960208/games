extends SceneTree
const Sun = preload("res://scripts/world/b07_sun_state.gd")
const Geometry = preload("res://scripts/world/b07_room_geometry.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL "+label)
func _initialize() -> void:
	for id: String in ["L37","L38","L39","L40","L41","L42","BO07"]:
		var definition := Geometry.room(id)
		if definition.is_empty():
			check(false,"missing room "+id)
			continue
		var state := Sun.new()
		check(state.configure(id,definition.mirrors,definition.altar.id,definition.required_mirrors,10000 if id=="BO07" else 0),id+" configure")
		var first: String = definition.mirrors[0].id
		check(state.begin_rotation(first),"rotation starts")
		check(not state.tick(.59) and state.mirrors[first]==0,"0.6s required")
		var before := state.checkpoint()
		check(not state.tick(5,true,true) and state.checkpoint()==before,"paused channel frozen")
		state.tick(.01,false)
		check(state.mirrors[first]==0 and state.channel().id=="","leave/hit cancels")
		check(state.begin_rotation(first) and state.tick(.6) and state.mirrors[first]==1,"rotation commits once")
		check(not state.tick(10) and state.mirrors[first]==1,"no repeated holding")
		if id == "BO07":
			state.set_phase(2)
			check(state.boss_multiplier()==.7,"one mirror insufficient")
			var second: String=definition.mirrors[1].id
			check(state.begin_rotation(second) and state.tick(.6),"second mirror")
			check(state.suppression==8 and state.exposure==4 and state.boss_multiplier()==1.15,"two mirrors suppress+expose")
			state.tick(4)
			check(state.boss_multiplier()==1.0,"exposure expires before suppression")
			state.tick(4)
			check(state.boss_multiplier()==.7,"suppression expires at8")
			check(state.damage_altar(800) and state.altar_hp==0 and state.boss_multiplier()==1.0,"direct damage alternative removes altar")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(state.checkpoint()))
		check(state.restore(saved),"JSON state restores")
		var stable := state.checkpoint()
		var invalid: Dictionary=saved.duplicate(true); invalid.mirrors[first]=3
		check(not state.restore(invalid) and state.checkpoint()==stable,"invalid mirror atomic rejection")
		invalid=saved.duplicate(true); invalid.altar_hp=INF
		check(not state.restore(invalid),"reject nonfinite")
		check(not state.open_manual_gate(false) and state.open_manual_gate(true),"combat-only fallback gate")
	print("B07 SUN STATE ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
