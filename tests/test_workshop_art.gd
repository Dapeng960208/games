extends SceneTree
## Real renderer previews; uses an isolated profile and never starts combat.
var app: Node
var game: Node

func _initialize() -> void:
	call_deferred("render_pages")

func frames() -> void:
	for _i in range(3):
		await process_frame

func capture(filename: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+filename+".png")
	print("CAPTURE ",filename)

func render_pages() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_") or DisplayServer.get_name() == "headless":
		push_error("Visual QA requires --Graphical and an isolated test_ profile.")
		quit(2)
		return
	if not game.new_profile():
		quit(1)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	for language in ["zh_CN","en"]:
		Words.set_locale(language)
		app.show_workshop("heroes")
		await capture("imagegen_heroes_"+language+"_1280")
		app.show_workshop("skills")
		await capture("imagegen_skills_"+language+"_1280")
		app.screen.get_node("Workshop")._show_branches()
		await capture("imagegen_branches_"+language+"_1280")
		app._pop_modal()
		app.show_camp()
		await capture("imagegen_camp_"+language+"_1280")
	for dimensions in [Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size = dimensions
		app.show_workshop("heroes")
		await capture("imagegen_heroes_en_"+str(dimensions.x))
	root.size = Vector2i(1280,720)
	print("WORKSHOP_ART_TEST_RESULT rendered=10")
	quit(0)
