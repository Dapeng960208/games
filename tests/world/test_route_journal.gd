extends Node
## Visual proof using the real expedition coordinator and main modal. The
## isolated profile belongs to this capture, never to the running player's save.
var app: Node
var checks := 0
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(40.0).timeout.connect(func(): push_error("Route journal capture timed out"); get_tree().quit(1))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ROUTE_JOURNAL: "+message)

func frames(count: int = 3) -> void:
	for index: int in count: await get_tree().process_frame

func capture(label: String) -> void:
	await frames()
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/route_journal_"+label+".png")

func _run() -> void:
	if not Game.profile_path.contains("test_route_journal"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated profile starts")
	Game.profile.hero_xp.CH01 = ContentRegistry.XP_THRESHOLDS[9]
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":2,"seed":960208}),"actual level-ten route starts")
	await frames(6)
	app._clear_modals()
	app.show_expedition(true)
	await frames()
	var chart: Control = app.ui.find_child("ExpeditionRouteChart",true,false)
	var snapshot: Dictionary = app.expedition.snapshot()
	check(snapshot.route.nodes.size()==10,"long route uses the live ten-node plan")
	check(chart.find_child("JourneyMap",true,false)!=null,"illustrated timeline installs")
	check(chart.find_child("RouteOptions",true,false)!=null,"live branches install")
	var cards: Array = chart.find_children("Choose_*","Button",true,false)
	check(cards.size()==app.expedition.next_options().size(),"all legal branch choices are shown")
	for card: Button in cards:
		var reward: Label = card.find_child("RouteReward",true,false)
		check(reward.text==app.expedition.preview(card.name.trim_prefix("Choose_")).reward,"real reward amounts and extraction rule stay intact")
		for item: Node in card.get_children():
			if item is Label: check(item.position.y+item.size.y<=card.size.y,"Chinese notes fit the illustrated card")
	check(get_viewport().get_visible_rect().encloses(chart.get_global_rect()),"route chart fits the actual main modal")
	await capture("zh")
	Words.locale = "en"
	app._pop_modal()
	await frames()
	app.show_expedition(true)
	await frames()
	chart = app.ui.find_child("ExpeditionRouteChart",true,false)
	cards = chart.find_children("Choose_*","Button",true,false)
	for card: Button in cards:
		for item: Node in card.get_children():
			if item is Label: check(item.position.y+item.size.y<=card.size.y,"English notes fit without clipping")
	await capture("en")
	# Detach only the main screen's navigation callback: verify one click cannot
	# submit twice without advancing or writing the test's gameplay state.
	chart.choice_requested.disconnect(app._advance_expedition)
	var submissions := [0]
	chart.choice_requested.connect(func(_id: String): submissions[0] += 1)
	if not cards.is_empty():
		cards[0].pressed.emit()
		cards[0].pressed.emit()
	check(submissions[0]==1,"route submit guard emits a choice once")
	check(app.expedition.snapshot()==snapshot,"viewing and rebuilding cannot reroll or mutate the route")
	chart.configure(app.expedition,false)
	cards = chart.find_children("Choose_*","Button",true,false)
	for card: Button in cards: check(card.disabled,"preview-only chart cannot depart")
	app._pop_modal()
	Words.locale = "zh_CN"
	app.set_process(false)
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free()
	Game.run = null
	await frames(2)
	print("ROUTE_JOURNAL_RESULT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
