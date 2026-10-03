extends Node2D
## Two controlled actual-EnemyVisual/codex panels. No claim of natural combat.
const Art = preload("res://scripts/combat/b06_native_art.gd")
const Enemy = preload("res://scripts/combat/enemy.gd")
const Skills = preload("res://scripts/combat/b06_enemy_skills.gd")
const Codex = preload("res://scripts/ui/monster_codex.gd")
class Arena extends Node2D:
	var player := Node2D.new()
	var enemy_skills: Node2D
	var fx_font: Font = ThemeDB.fallback_font
	var enemies := Node2D.new()
	func _init() -> void:
		add_child(enemies)
		add_child(player)
		player.position = Vector2(-5000,-5000)
	func enemy_died(_enemy: Node2D) -> void: pass
var specimens: Array[Dictionary] = []
var start := 2
var first := 2
var rows := 4
var pages := 2
var arena: Arena
var output := ""
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	output = OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	if output.is_empty() or not Game.profile_path.contains("test_b06_ordinary_capture"):
		get_tree().quit(2); return
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().size = Vector2i(2560,1440)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if "--remaining-art" in OS.get_cmdline_user_args():
		first=10; rows=3; pages=3
	arena = Arena.new(); arena.process_mode=Node.PROCESS_MODE_DISABLED; add_child(arena)
	for page in pages:
		start = first + page*rows
		for child in arena.enemies.get_children(): child.free()
		for child in get_children():
			if child is Control: child.free()
		specimens.clear()
		for row in rows:
			var identity := "B06-M%02d" % (start+row)
			for column in 3:
				var phase_name: String = ["idle","telegraph","execute"][column]
				var actor := Enemy.new()
				actor.room = arena
				actor.position = Vector2(270+column*245,200+row*160)
				actor.configure(Skills.profile(identity,30,4),{"reward_enabled":false})
				arena.enemies.add_child(actor)
				actor.state = &"chase" if column==0 else StringName(phase_name)
				actor.state_time = 0.5
				actor.aim_direction = Vector2.LEFT if page==1 else Vector2.RIGHT
				actor.body_visual.synchronize_b06_release()
				actor.body_visual.skill_badge.hide()
				check(actor.body_visual.selected_frame.name==phase_name,identity+" actual dispatch "+phase_name)
				var outlet: Dictionary = actor.body_visual.b06_visual_outlet()
				check(outlet.texture_path==Art.frame(identity,phase_name).texture_path,identity+" outlet uses actual selected source")
				specimens.append({"actor":actor,"phase":phase_name,"identity":identity,"outlet":outlet.position})
			var box := Control.new(); add_child(box)
			var portrait := Codex.portrait(box,identity,Vector2(1000,90+row*160),Vector2(140,140))
			check(portrait.texture is AtlasTexture,identity+" actual codex native atlas")
			check(portrait.size.x<=140.1 and portrait.size.y<=140.1,identity+" portrait inside cell")
		queue_redraw()
		for frame in 5: await get_tree().process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			check(image.get_size()==Vector2i(2560,1440),"actual native 2K viewport")
			check(image.save_png(output.path_join("b06-m%02d-m%02d-native-2k.png" % [start,start+rows-1]))==OK,"capture saved")
	print("B06 ordinary art/codex: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("e8edf0"))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(20,27),"B06 M%02d-M%02d | CONTROLLED ACTOR POSES + ACTUAL CODEX PORTRAITS" % [start,start+rows-1],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("17354c"))
	draw_string(font,Vector2(20,49),"Native1254 sources; fixed identity registration; fixed world size. Candidate visuals, not natural combat acceptance.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("394b58"))
	for col in 3: draw_string(font,Vector2(240+col*245,76),["IDLE","TELEGRAPH","RELEASE"][col],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("17354c"))
	draw_string(font,Vector2(1040,76),"CODEX",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("17354c"))
	for row in rows:
		draw_string(font,Vector2(20,158+row*160),"B06-M%02d" % (start+row),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("17354c"))
		draw_line(Vector2(20,239+row*160),Vector2(1230,239+row*160),Color("bccad2"))
	for item: Dictionary in specimens:
		var foot: Vector2 = item.actor.position+Vector2(0,18)
		draw_line(foot-Vector2(25,0),foot+Vector2(25,0),Color("268146"),1)
		draw_circle(item.outlet,2,Color("155ec2"))
