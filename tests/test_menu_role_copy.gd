extends Node
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _ready() -> void:
	if not Game.profile_path.contains("test_menu_role_copy"): get_tree().quit(2); return
	Game.run = null
	check(Game.new_profile(),"isolated profile")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	# Test the real resume predicate and labels without instantiating combat rooms.
	Game.run_started.disconnect(app._on_run_started)
	for locale: String in ["zh_CN","en"]:
		Words.locale = locale
		Game.run = null
		app.show_menu()
		check(app.screen.find_child("ContinueJourney",true,false).text == ("返回营地" if locale == "zh_CN" else "Return to camp"),"camp action text matches camp branch")
		check(not app._has_resumable_expedition(),"camp branch has no expedition")
		check(Game.start_run({"expedition":true,"biome_id":"B01","seed":7331}),"real expedition begins")
		app.show_menu()
		check(app._has_resumable_expedition(),"real saved expedition selects resume branch")
		check(app.screen.find_child("ContinueJourney",true,false).text == ("继续远征" if locale == "zh_CN" else "Continue expedition"),"resume action text matches expedition branch")
		var words: Array = app.HERO_LOOPS.CH03
		var text: String = str(words[1] if locale == "zh_CN" else words[4])
		for key: String in ["Q","W","E","R"]: check(text.contains(key),"mage introduces standalone "+key)
		check(text.contains("独立") if locale == "zh_CN" else text.contains("independently"),"skills are independently usable")
		check(text.contains("额外") if locale == "zh_CN" else text.contains("bonus"),"alternation is an extra reward")
	Game.run = null
	app.set_process(false)
	await app.music.wait_for_cleanup()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("MENU ROLE COPY: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
