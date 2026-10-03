extends Node
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
var room: Node2D
var route: RefCounted
var hud: Label
var menu: PanelContainer
var heroes: OptionButton
var difficulties: OptionButton
var restart: Button

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=preload("res://scripts/presentation/components/style.gd").make_theme()
	canvas.add_child(ui)
	menu=PanelContainer.new()
	menu.position=Vector2(400,160)
	menu.custom_minimum_size=Vector2(480,320)
	ui.add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	menu.add_child(box)
	var title := Label.new()
	title.text="B09 霜晶王庭 · 独立开发预览"
	title.add_theme_font_size_override("font_size",24)
	box.add_child(title)
	var detail := Label.new()
	detail.text="Lv45 裸装测试角色 / L49–L54 → 霜晶女王\n方向键/右键移动 · 左键普攻 · Q/W/E/R 技能\n空格闪避 · F 暖灯/出口；七房有限遭遇。"
	box.add_child(detail)
	heroes=OptionButton.new()
	for name: String in ["战士","枪手","法师"]: heroes.add_item(name)
	box.add_child(heroes)
	difficulties=OptionButton.new()
	for d in 5: difficulties.add_item("D"+str(d))
	box.add_child(difficulties)
	var begin := Button.new()
	begin.text="进入雪阶外庭"
	begin.disabled=not Rules.b09_candidate_enabled()
	begin.pressed.connect(_start)
	box.add_child(begin)
	if begin.disabled: detail.text="请使用 tools/play_b09.ps1 启动隔离预览。"
	var hud_panel := PanelContainer.new()
	hud_panel.position=Vector2(12,10)
	var background := StyleBoxFlat.new()
	background.bg_color=Color("fff0da")
	background.border_color=Color("927091")
	background.set_border_width_all(1)
	background.content_margin_left=12
	background.content_margin_right=12
	background.content_margin_top=8
	background.content_margin_bottom=8
	hud_panel.add_theme_stylebox_override("panel",background)
	ui.add_child(hud_panel)
	hud_panel.hide()
	hud=Label.new()
	hud.add_theme_color_override("font_color",Color("48374b"))
	hud.add_theme_font_override("font",preload("res://scripts/presentation/hud/world_label_layer.gd").font())
	hud.add_theme_font_size_override("font_size",18)
	hud_panel.add_child(hud)
	restart=Button.new()
	restart.text="返回职业选择"
	restart.position=Vector2(1090,16)
	restart.pressed.connect(_restart)
	ui.add_child(restart)
	restart.hide()
	if Rules.b09_candidate_enabled() and OS.get_cmdline_user_args().has("--b09-auto"): _start.call_deferred()

func _start() -> void:
	if not Rules.b09_candidate_enabled(): return
	Game.run=null
	if not Game.new_profile(): hud.text=Game.last_error; return
	Game.profile.selected_hero=["CH01","CH02","CH03"][heroes.selected]
	if not Game.start_run(): hud.text=Game.last_error; return
	# Only the disposable run is elevated. Production profile caps stay unchanged.
	var base := Progression.hero_base(ContentRegistry.hero(Game.run.hero_id),45,{},45)
	for key: String in ["max_hp","attack","ability_power","armor","magic_resist","resource_max","resource_regen","starting_resource","resource_regen_delay","level"]:
		if base.has(key): Game.run.stats[key]=base[key]
	Game.run.level=45
	Game.run.max_hp=float(Game.run.stats.max_hp)
	Game.run.hp=Game.run.max_hp
	Game.run.resource=float(Game.run.stats.starting_resource)
	room=load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	for actor: Node in room.enemies.get_children(): actor.free()
	route=Traversal.new()
	if not route.configure(room,difficulties.selected,309) or not route.start(): hud.text="B09 加载失败："+route.last_error; return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b09-room="):
			var index := Content.room_ids().find(argument.trim_prefix("--b09-room="))
			if index>=0: route._install(index)
	menu.hide()
	hud.get_parent().show()
	restart.show()
	if OS.get_cmdline_user_args().has("--b09-capture"): _capture.call_deferred()

func _capture() -> void:
	room.set_input_blocked(true)
	room.player.position=room.ARENA.get_center()
	if not room.valid_ground(room.player.position,Balance.PLAYER_RADIUS):
		room.player.position=Content.point(Content.room(room.layout_id).encounter_anchors[0])
	var focus := Node2D.new()
	focus.position=room.ARENA.get_center()
	room.add_child(focus)
	room.camera.target=focus
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/b09/"))
	get_viewport().get_texture().get_image().save_png("res://artifacts/b09/"+room.layout_id.to_lower()+".png")
	print("B09_VISUAL_CAPTURE ",room.layout_id)
	get_tree().quit()

func _process(_delta: float) -> void:
	if not is_instance_valid(room) or route==null or Game.run==null: return
	var name: String=Content.room(room.layout_id).name
	hud.text="B09 · %s · D%d · %d / 7\nHP %d / %d · 资源 %d · 敌人 %d\nF 暖灯/出口 · %s" % [name,route.difficulty,route.node_index+1,int(Game.run.hp),int(Game.run.max_hp),int(Game.run.resource),room._living_enemy_count(),room.interaction_hint()]
	if route.finished: hud.text+="\n霜晶王庭预览完成"
	elif Game.run.hp<=0: hud.text+="\n角色倒下 · 返回职业选择重新开始"

func _restart() -> void:
	if is_instance_valid(room): room.free()
	room=null
	route=null
	Game.run=null
	hud.text=""
	hud.get_parent().hide()
	restart.hide()
	menu.show()
