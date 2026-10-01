extends Node

const Routes = preload("res://scripts/world/route_generator.gd")
var checks := 0
var failures := 0
var app: Node
var viewport: SubViewport

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for frame in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func run_checks() -> void:
	if not Game.profile_path.contains("test_dynamic_route_ui"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated profile created")
	check(Game.start_run(),"training receipt starts")
	check(Game.grant_hero_xp(ContentRegistry.XP_THRESHOLDS[14],"route-ui-level15"),"level fifteen earned through production XP API")
	check(not Game.finish_run("extracted").is_empty(),"training settles through production API")
	check(Game.hero_level("CH01") == 15,"departure hero is level fifteen")
	for pair: Array in [[1,6],[4,6],[5,8],[9,8],[10,10],[14,10],[15,12],[20,12]]:
		check(Routes.node_count_for_level(pair[0]) == pair[1],"departure prediction matches level band "+str(pair[0]))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	app = load("res://scenes/main.tscn").instantiate()
	viewport.add_child(app)
	await frames()
	app.show_camp()
	await frames()
	var summary := ""
	for label: Label in app.screen.find_children("*","Label",true,false): summary += label.text
	check(summary.contains("预计 12 站"),"camp predicts twelve stops for the selected departure hero")
	app._start_run()
	await frames()
	check(Game.run.expedition.route.nodes.size() == 12,"UI starts the real twelve-node production route")
	var relic_panel: Control = app.modals[-1].node.find_child("ExpeditionRelicModal",true,false)
	var descriptions: Array[Node] = relic_panel.find_children("RelicDescription","Label",true,false)
	var full_descriptions_fit := descriptions.size() == 3
	for description: Label in descriptions:
		full_descriptions_fit = full_descriptions_fit and description.max_lines_visible == -1 and not description.clip_text and description.get_parent().get_global_rect().encloses(description.get_global_rect())
	check(full_descriptions_fit,"relic choices expose full wrapped class and race descriptions inside their cards")
	check(Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(relic_panel.get_global_rect()),"measured relic modal stays fully within the game canvas")
	Words.set_locale("en")
	app._clear_modals()
	app._show_expedition_relic(Game.expedition_snapshot().relic_offers[0])
	await frames()
	var english_relic_panel: Control = app.modals[-1].node.find_child("ExpeditionRelicModal",true,false)
	var english_descriptions_fit := true
	for description: Label in english_relic_panel.find_children("RelicDescription","Label",true,false):
		english_descriptions_fit = english_descriptions_fit and description.get_parent().get_global_rect().encloses(description.get_global_rect())
	check(english_descriptions_fit and Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(english_relic_panel.get_global_rect()),"full English relic explanations stay visible within the fitted modal")
	Words.set_locale("zh_CN")
	check(app.expedition_status.text.contains("[M]"),"persistent route control preserves its keyboard shortcut")
	check(app.hud.expedition_label.text.contains("1 / 12") and app.hud.expedition_beads.count == 12,"HUD route label and progression beads show the actual total")
	app.room.process_mode = Node.PROCESS_MODE_DISABLED
	app.show_expedition(false)
	await frames()
	var chart: Control = app.modals[-1].node.find_child("ExpeditionRouteChart",true,false)
	var timeline: ScrollContainer = chart.find_child("RouteTimeline",true,false)
	var progress: Label = chart.find_child("RouteProgress",true,false)
	check(progress.text.contains("1/12"),"route chart shows live current progress")
	check(chart.find_children("RouteNode*","Panel",true,false).size() == 12,"all twelve nodes exist inside the route timeline")
	check(timeline.clip_contents and timeline.get_global_rect().end.x <= 1250,"long timeline clips within the game panel")
	timeline.scroll_horizontal = int(timeline.get_h_scroll_bar().max_value)
	await frames()
	var final_node: Control = chart.find_child("RouteNode11",true,false)
	check(timeline.get_global_rect().encloses(final_node.get_global_rect()),"horizontal scrolling exposes the final boss node fully")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		viewport.get_texture().get_image().save_png("res://artifacts/demo_ui_route12_final.png")
	app._clear_modals()
	Game.finish_run("abandoned")
	await frames()
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(),"route UI music releases playback resources before exit")
	app.free()
	await frames()
	print("DYNAMIC ROUTE UI: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
