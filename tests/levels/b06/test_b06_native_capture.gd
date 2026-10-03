extends Node2D
## Actual 2560x1440 registration/codex sheet. Not a gameplay acceptance image.
const Art = preload("res://scripts/levels/b06/art/native_art.gd")
var specimens: Array[Dictionary] = []
var output := ""
func _ready() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b06_native_capture") or DisplayServer.get_name()=="headless":
		push_error("B06 native capture requires managed graphical isolated profile")
		get_tree().quit(2)
		return
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	for i in 3:
		var pose: String = ["idle","telegraph","execute"][i]
		specimens.append({"frame":Art.frame("B06-M01",pose),"ground":Vector2(120+i*205,270),"height":155.0,"label":"M01 / "+pose})
	for i in 3:
		var id: String = ["drain_gate","reef_pillar","tide_clock"][i]
		specimens.append({"frame":Art.prop_frame(id),"ground":Vector2(760+i*195,270),"height":155.0,"label":id})
	for i in 7:
		var pose: String = ["idle","melee-telegraph","melee-execute","cannon-telegraph","cannon-execute","exposed","defeated"][i]
		var col := i%4
		var row := i/4
		specimens.append({"frame":Art.frame("BO06",pose),"ground":Vector2(148+col*310,465+row*195),"height":140.0,"label":"BO06 / "+pose})
	queue_redraw()
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var captured := get_viewport().get_texture().get_image()
	if captured.get_size()!=Vector2i(2560,1440):
		push_error("Capture must be actual 2K")
		get_tree().quit(1)
		return
	var path := output.path_join("b06-native-registration-2k.png")
	var error := captured.save_png(path)
	var report: Dictionary = {"image":path,"dimensions":[2560,1440],"renderer":RenderingServer.get_video_adapter_name(),"candidate_only":true,"gameplay_acceptance":false,"specimens":[]}
	for item: Dictionary in specimens:
		report.specimens.append({"pose":item.frame.name,"source":item.frame.texture_path,"reference_height":item.frame.reference_height,"ground":[item.ground.x,item.ground.y]})
	var file := FileAccess.open(AssetCatalog.resolve(output.path_join("native-capture.json")),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("B06 native capture: ",path," result=",error)
	if "--hold-preview" in OS.get_cmdline_user_args(): return
	get_tree().quit(0 if error==OK else 1)
func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("e8edf0"))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(25,28),"B06 | NATIVE SOURCE REGISTRATION / CODEX PREVIEW",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("17354c"))
	draw_string(font,Vector2(25,51),"Candidate visuals; fixed scale per identity. Ground=green  Core=orange  Outlet=blue. No geometry / gameplay acceptance.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("394b58"))
	for item: Dictionary in specimens:
		var placed: Dictionary = Art.draw_frame(self,item.frame,item.ground,item.height)
		draw_line(item.ground-Vector2(24,0),item.ground+Vector2(24,0),Color("268146"),1.0)
		draw_circle(item.ground,2,Color("268146"))
		draw_circle(placed.core,2,Color("ca711e"))
		draw_circle(placed.outlet,2,Color("155ec2"))
		draw_string(font,item.ground+Vector2(-75,44),item.label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("17354c"))
