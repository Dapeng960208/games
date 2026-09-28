extends SceneTree
## Each mode must run in a NEW Godot process, sharing --test-profile=<isolated path>.
## Modes: write, read, abrupt_write, abrupt_read. Repeat either read to check idempotency.

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RESTART FAIL: " + description)

func _run() -> void:
	var mode := ""
	var test_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--test-profile="):
			test_profile = argument.trim_prefix("--test-profile=")
	# Explicit isolation is required before any reset or write in this test.
	if test_profile.is_empty() or test_profile == "user://profile.json":
		push_error("Pass an isolated --test-profile path; player profile is not a test target.")
		quit(1)
		return
	var game: Node = root.get_node("Game")
	_check(game.profile_path == test_profile, "autoload used the isolated path before loading")
	match mode:
		"write":
			_check(game.new_profile(), "reset isolated fixture")
			_check(game.start_run(), "first process starts extraction")
			_check(game.add_gold(117) and game.equip_relic("split"), "collect extraction rewards")
			var extracted: Dictionary = game.finish_run("extracted")
			_check(extracted.get("retained") == 117, "117 extraction gold committed")
			_check(game.start_run(), "same session can depart again")
			_check(game.add_gold(119) and game.equip_relic("ember") and game.equip_relic("arc"), "collect death rewards")
			game.damage_player(100.0)
			_check(game.run == null and game.last_result.get("retained") == 23, "119 death gold retains floor 23")
			_check(game.profile.permanent_gold == 140 and game.profile.total_runs == 2, "writer committed exact final balance")
		"read":
			_check(game.run == null and game.has_profile, "new process loads a finished profile")
			_check(game.profile.permanent_gold == 140 and game.profile.total_runs == 2, "new process sees 140 gold and two runs")
			_check(game.profile.discoveries == ["split", "ember", "arc"], "all three discoveries survive a process restart")
			_check(game.last_result.get("outcome") == "death" and game.last_result.get("retained") == 23, "last death receipt survives")
			_check(game.last_result.get("collected") == 119 and game.last_result.get("lost") == 96, "last result retains full accounting")
			game.finish_run("death")
			game.finish_run("extracted")
			_check(game.profile.permanent_gold == 140 and game.profile.total_runs == 2, "reopening settlement cannot pay again")
		"abrupt_write":
			_check(game.new_profile() and game.start_run(), "create unfinished expedition")
			_check(game.add_gold(119) and game.equip_relic("arc"), "persist abandonment receipt with 119 gold and arc")
			_check(game.run != null and game.profile.permanent_gold == 0, "exit with active expedition and no reward granted")
			# Deliberately skip finish_run: the next process must abandon, never resume.
		"abrupt_read":
			_check(game.run == null, "unfinished expedition never resumes")
			_check(game.profile.permanent_gold == 23 and game.profile.total_runs == 1, "startup abandonment pays floor 23 exactly once")
			_check(game.profile.discoveries == ["arc"], "abandonment preserves the discovery")
			_check(game.last_result.get("outcome") == "abandoned" and game.last_result.get("collected") == 119, "startup stores an abandonment result")
			game.finish_run("extracted")
			_check(game.profile.permanent_gold == 23 and game.profile.total_runs == 1, "settlement calls after recovery do not pay again")
		_:
			_check(false, "unknown --mode: " + mode)
	_check(game.last_error.is_empty(), "no unresolved storage error")
	print("RESTART TEST ", mode, ": ", checks - failures, "/", checks, " passed; profile=", test_profile)
	quit(1 if failures else 0)
