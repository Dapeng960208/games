extends Node
const Driver=preload("res://tests/levels/b08/l43_scripted_input.gd")
const Capture=preload("res://tests/levels/b08/test_l43_natural_capture.gd")
var checks:=0
var failures:=0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("B08 natural safety: "+message)
func _ready() -> void:
	var driver=Driver.new()
	driver.step(null,0,false)
	check(driver.requests.is_empty(),"dead-player early return does not access room or submit inputs")
	driver.step(null,Driver.LIMIT_SECONDS,true)
	check(driver.requests.is_empty(),"deadline blocks all input before room access")
	driver.next_input=1
	driver.step(null,.5,true)
	check(driver.requests.is_empty(),"input cadence rejects early requests")
	check(Driver.LIMIT_SECONDS==35 and Capture.MAX_CAPTURES==6,"bounded gameplay and PNG counts")
	var source:=FileAccess.get_file_as_string("res://tests/levels/b08/test_l43_natural_capture.gd")+FileAccess.get_file_as_string("res://tests/levels/b08/l43_scripted_input.gd")
	# This harness is evidence: forbid shortcuts used in controlled phase tests.
	for forbidden: String in ["PROCESS_MODE_DISABLED","._begin(","._release(","._land(","._die(","wind.advance(","health.current=","player.position=","_next_wave=","release_gate=","cooldowns[",".save_profile("]:
		check(not source.contains(forbidden),"no fixture shortcut "+forbidden)
	check(source.contains("await RenderingServer.frame_post_draw"),"capture/state observed after final renderer pass")
	check(source.contains("Game.run!=trial") and source.contains("trial.hp"),"terminal snapshot survives demo run deletion")
	check(source.contains("Game.reload_profile()") and source.contains("persisted_profile_unchanged"),"restore isolated trial and verify profile bytes")
	print("B08_L43_NATURAL_SAFETY checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
