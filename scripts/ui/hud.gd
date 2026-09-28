extends Control

signal relic_details_requested()

var room: Node
var health_label: Label
var gold_label: Label
var retained_label: Label
var dash_label: Label
var relic_label: Label
var hint_label: Label
var health_bar: ProgressBar
var relic_row: Control
var previous_relics := ""
var toast: Label
var toast_remaining := 0.0
var has_drawn_state := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MineStyle.make_theme()
	var top := MineStyle.panel(self,Vector2(24,20),Vector2(292,72))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_label = MineStyle.label(top,"HEALTH",Vector2(16,4),Vector2(256,35),20)
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(16,45)
	health_bar.size = Vector2(256,8)
	health_bar.max_value = Balance.PLAYER_HP
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0d131a")
	var fill := StyleBoxFlat.new()
	fill.bg_color = MineStyle.RED
	health_bar.add_theme_stylebox_override("background",background)
	health_bar.add_theme_stylebox_override("fill",fill)
	top.add_child(health_bar)
	health_bar.size = Vector2(256,8)
	var region := MineStyle.label(self,"REGION",Vector2(370,24),Vector2(540,35),20,MineStyle.MUTED)
	region.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bottom := MineStyle.panel(self,Vector2(24,610),Vector2(1232,90))
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_label = MineStyle.label(bottom,"CARRIED",Vector2(16,8),Vector2(220,28),19,MineStyle.AMBER)
	retained_label = MineStyle.label(bottom,"RETAINED",Vector2(16,41),Vector2(220,27),16,MineStyle.MUTED)
	MineStyle.label(bottom,"ACTIONS",Vector2(260,7),Vector2(948,27),16)
	relic_label = MineStyle.label(bottom,"NO_RELICS",Vector2(260,40),Vector2(720,33),18,MineStyle.CYAN)
	relic_row = Control.new()
	relic_row.position = Vector2(252,38)
	relic_row.size = Vector2(946,46)
	relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(relic_row)
	toast = MineStyle.label(self,"",Vector2(350,65),Vector2(580,32),17,MineStyle.CYAN)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash_label = MineStyle.label(self,"DASH_READY",Vector2(1020,570),Vector2(226,32),17,MineStyle.CYAN)
	dash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label = MineStyle.label(self,"",Vector2(380,568),Vector2(570,34),19,MineStyle.AMBER)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MineStyle.label(self,"HUD_HINT",Vector2(28,570),Vector2(350,32),16,MineStyle.MUTED)
	refresh()

func _process(delta: float) -> void:
	toast_remaining = maxf(0,toast_remaining-delta)
	if toast != null:
		toast.visible = toast_remaining > 0
	refresh()

func refresh() -> void:
	if Game.run == null or health_label == null:
		return
	health_label.text = Words.text("HEALTH",{"hp":ceili(Game.run.hp),"max":int(Balance.PLAYER_HP)})
	health_bar.value = Game.run.hp
	gold_label.text = Words.text("CARRIED",{"gold":Game.run.gold})
	retained_label.text = Words.text("RETAINED",{"gold":Balance.death_keep(Game.run.gold)})
	var names: PackedStringArray = []
	for id in Game.run.relics:
		names.append(Words.text("RELIC_"+id.to_upper()+"_NAME"))
	relic_label.text = Words.text("NO_RELICS")
	relic_label.visible = names.is_empty()
	var signature := ",".join(Game.run.relics)
	if signature != previous_relics:
		for child in relic_row.get_children():
			child.queue_free()
		for i in range(Game.run.relics.size()):
			var id: String = Game.run.relics[i]
			var chip := MineStyle.button(relic_row,"RELIC_"+id.to_upper()+"_NAME",Vector2(i*234,0),Vector2(224,44),func(): relic_details_requested.emit())
			chip.focus_mode = Control.FOCUS_NONE
			chip.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
			chip.add_theme_font_size_override("font_size",16)
			chip.tooltip_text = Words.text("RELIC_"+id.to_upper()+"_DESC")
			MineArt.relic(chip,id,Vector2(12,2),Vector2(40,40))
		if has_drawn_state and not Game.run.relics.is_empty():
			toast.text = Words.text("RELIC_ACQUIRED",{"name":names[-1]})
			toast_remaining = 4.0
		previous_relics = signature
	has_drawn_state = true
	if is_instance_valid(room):
		hint_label.text = room.interaction_hint()
		if is_instance_valid(room.player):
			var cooldown: float = room.player.dash_cooldown
			dash_label.text = Words.text("DASH_COOLDOWN",{"time":"%.1f" % cooldown}) if cooldown > 0 else Words.text("DASH_READY")
