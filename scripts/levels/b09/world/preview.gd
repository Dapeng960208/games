extends Node
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Traversal = preload("res://scripts/levels/b09/world/traversal.gd")
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Inventory = preload("res://scripts/levels/b09/equipment/candidate_inventory.gd")
const CandidateHUD = preload("res://scripts/levels/b09/world/candidate_hud.gd")
var inventory: RefCounted
var room: Node2D
var route: RefCounted
var hud: Control
var start_error: Label
var _hud_interaction_enabled := true
var menu: PanelContainer
var heroes: OptionButton
var difficulties: OptionButton
var restart: Button

func _ready() -> void:
	# Apply after the native window opens: startup --resolution may be clamped
	# to the current desktop even when a larger render target was requested.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b09-resolution="):
			var requested := argument.trim_prefix("--b09-resolution=")
			if requested in ["1280x720","1920x1080","2560x1440","3840x2160"]:
				var dimensions := requested.split("x")
				get_window().size=Vector2i(int(dimensions[0]),int(dimensions[1]))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=preload("res://scripts/presentation/components/style.gd").make_theme()
	canvas.add_child(ui)
	menu=PanelContainer.new()
	menu.custom_minimum_size=Vector2(480,320)
	ui.add_child(menu)
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.offset_left=-240
	menu.offset_top=-160
	menu.offset_right=240
	menu.offset_bottom=160
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	menu.add_child(box)
	var title := Label.new()
	title.text="B09 霜晶王庭 · 独立开发预览"
	title.add_theme_font_size_override("font_size",24)
	box.add_child(title)
	var detail := Label.new()
	detail.text="Lv45 测试角色 / L49–L54 → 霜晶女王\n方向键/右键移动 · 左键普攻 · Q/W/E/R 技能\n空格闪避 · F 暖灯/出口；清房获装\n行囊可领取测试套装；七房有限遭遇。"
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
	start_error=Label.new()
	start_error.add_theme_color_override("font_color",Color("bb6254"))
	start_error.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	box.add_child(start_error)
	start_error.hide()
	restart=Button.new()
	restart.text="返回职业选择"
	restart.pressed.connect(_restart)
	ui.add_child(restart)
	restart.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	restart.offset_left=-180
	restart.offset_top=16
	restart.offset_right=-16
	restart.offset_bottom=50
	restart.hide()
	if Rules.b09_candidate_enabled() and OS.get_cmdline_user_args().has("--b09-auto"): _start.call_deferred()

func _start() -> void:
	if not Rules.b09_candidate_enabled(): return
	Game.run=null
	if not Game.has_profile and not Game.new_profile(): _show_start_error(Game.last_error); return
	Game.profile.selected_hero=["CH01","CH02","CH03"][heroes.selected]
	if not Game.start_run(): _show_start_error(Game.last_error); return
	inventory=Inventory.new()
	if not inventory.configure(): _show_start_error(inventory.last_error); return
	room=load("res://scenes/gameplay/world/room.tscn").instantiate()
	room.geometry_enabled=false
	room.spawn_enabled=false
	add_child(room)
	for actor: Node in room.enemies.get_children(): actor.free()
	route=Traversal.new()
	if not route.configure(room,difficulties.selected,309) or not route.start(): _show_start_error("B09 加载失败："+route.last_error); return
	inventory.attach_room(room,false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b09-room="):
			var index := Content.room_ids().find(argument.trim_prefix("--b09-room="))
			if index>=0: route._install(index)
	var combat_canvas := CanvasLayer.new()
	combat_canvas.layer=4
	room.add_child(combat_canvas)
	hud=CandidateHUD.new()
	hud.room=room
	hud.candidate_route=route
	combat_canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.inventory_button.name="B09EquipmentOpen"
	var backpack_shortcut := Shortcut.new()
	backpack_shortcut.events=InputMap.action_get_events("backpack")
	hud.inventory_button.shortcut=backpack_shortcut
	hud.inventory_requested.connect(inventory._open)
	_hud_interaction_enabled=true
	start_error.hide()
	menu.hide()
	restart.show()
	if OS.get_cmdline_user_args().has("--b09-capture"): _capture.call_deferred()

func _show_start_error(message: String) -> void:
	_restart()
	start_error.text=message
	start_error.show()

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
	if not is_instance_valid(hud) or inventory==null: return
	var enabled: bool=not inventory.panel.visible
	if enabled!=_hud_interaction_enabled:
		hud.set_interaction_enabled(enabled)
		_hud_interaction_enabled=enabled

func _restart() -> void:
	if is_instance_valid(room): room.free()
	room=null
	route=null
	inventory=null
	Game.run=null
	hud=null
	start_error.hide()
	restart.hide()
	menu.show()
