extends Control
## Compact mining instruments: large legible numbers without large permanent cards.
signal relic_details_requested()
signal skill_details_requested(slot: String)

const SKILLS := ["q","secondary","f","ultimate"]
const KEYS := ["Q","RMB","F","R"]
const BUFF_ORDER := ["damage","guard","haste"]

## A 44 px input target carries only a 40 px painted buff indicator.
## State is copied from RoomProps; this control never owns or advances a timer.
class BuffChip extends Button:
	const Sampler = preload("res://scripts/ui/texture_sampler.gd")
	const PAINTED_RECT := Rect2(2,2,40,40)
	var effect := ""
	var state: Dictionary = {}
	var generated_texture: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(44,44)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_theme_font_size_override("font_size",16)
		for style_name in ["normal","hover","pressed","disabled","focus"]:
			add_theme_stylebox_override(style_name,StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton: accept_event())

	func configure(next_effect: String) -> void:
		effect = next_effect
		name = "Buff_"+effect
		var artwork := "pressure" if effect == "damage" else effect
		generated_texture = Sampler.sampled("res://assets/generated/props/buff_"+artwork+"_v1.png")

	func update_state(next_state: Dictionary) -> void:
		state = next_state.duplicate(true)
		queue_redraw()

	func remaining_seconds() -> int:
		return ceili(maxf(0.0,float(state.get("remaining",0.0))))

	func _draw() -> void:
		if state.is_empty(): return
		var accent: Color = state.get("color",Color("e6aa4a"))
		var active := is_hovered() or has_focus()
		draw_rect(PAINTED_RECT,Color(0.035,0.055,0.068,0.86))
		draw_rect(PAINTED_RECT,accent if active else Color("826345"),false,2.0 if active else 1.0)
		if generated_texture != null:
			var source := generated_texture.get_size()
			var extent := source*minf(22.0/source.x,22.0/source.y)
			draw_texture_rect(generated_texture,Rect2(Vector2(22,14)-extent*0.5,extent),false)
		else:
			_draw_glyph(accent)
		var font := get_theme_font("font","Button")
		var value := str(remaining_seconds())
		var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var at := Vector2((size.x-width)*0.5,39)
		draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,3,Color("0d131a"))
		draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f1eadc"))

	func _draw_glyph(accent: Color) -> void:
		# Original, distinct silhouettes remain usable before generated PNG import.
		if effect == "guard":
			draw_polyline(PackedVector2Array([Vector2(14,6),Vector2(30,6),Vector2(29,17),Vector2(22,24),Vector2(15,17),Vector2(14,6)]),accent,2.0,true)
			draw_line(Vector2(22,10),Vector2(22,18),accent,2.0,true)
		elif effect == "haste":
			for x in [14.0,23.0]:
				draw_polyline(PackedVector2Array([Vector2(x,6),Vector2(x+7,14),Vector2(x,22)]),accent,2.5,true)
		else:
			draw_polyline(PackedVector2Array([Vector2(25,5),Vector2(16,15),Vector2(25,15),Vector2(20,24)]),accent,2.5,true)
			draw_line(Vector2(11,9),Vector2(14,9),accent,2.0,true)
			draw_line(Vector2(30,20),Vector2(33,20),accent,2.0,true)

var room: Node
var health_label: Label
var gold_label: Button
var retained_label: Label
var health_bar: ProgressBar
var resource_bar: ProgressBar
var resource_label: Label
var shield_label: Label
var shield_bar: ProgressBar
var hero_label: Label
var relic_row: Control
var hint_label: Label
var region_label: Label
var objective_label: Label
var objective_bar: ProgressBar
var status_panel: Panel
var location_panel: Panel
var skill_dock: Control
var skill_slots: Array[Button] = []
var details_button: Button
var navigation: Control
var toast: Label
var toast_remaining := 0.0
var previous_relics := "uninitialized"
var has_drawn_state := false
var hero_definition: Dictionary = {}
var resource_kind := ""
var tooltip_panel: Panel
var tooltip_title: Label
var tooltip_body: Label
var hovered_control: Control
var focused_control: Control
var last_hover_control: Control
var hover_grace := 0.0
var interaction_enabled := true
var active_detail_slot := "q"
var resource_icon: Control
var guard_icon: Control
var buff_row: Control
var buff_chips: Dictionary = {}
var active_buffs: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MineStyle.make_theme()
	status_panel = _plate(self,Vector2(16,14),Vector2(276,84))
	hero_label = _line(status_panel,"",Vector2(10,2),Vector2(256,23),17,MineStyle.AMBER)
	_icon(status_panel,"health",Vector2(7,24),Vector2(24,24))
	health_label = _line(status_panel,"",Vector2(34,25),Vector2(160,22),16)
	guard_icon = _icon(status_panel,"state_guard",Vector2(189,24),Vector2(24,24))
	shield_label = _line(status_panel,"",Vector2(200,25),Vector2(66,22),16,MineStyle.CYAN)
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_bar = MineStyle.meter(status_panel,Vector2(10,48),Vector2(256,6),MineStyle.RED)
	shield_bar = MineStyle.meter(status_panel,Vector2(10,44),Vector2(256,3),MineStyle.CYAN)
	resource_icon = _icon(status_panel,"resource_rage",Vector2(7,53),Vector2(24,24))
	resource_label = _line(status_panel,"",Vector2(34,54),Vector2(232,22),16)
	resource_bar = MineStyle.meter(status_panel,Vector2(10,77),Vector2(256,3),MineStyle.CYAN)
	buff_row = Control.new()
	buff_row.name = "ActiveRoomBuffs"
	buff_row.position = Vector2(16,102)
	buff_row.size = Vector2(140,44)
	buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(buff_row)
	buff_row.hide()
	location_panel = _plate(self,Vector2(408,14),Vector2(464,44))
	_icon(location_panel,"objective",Vector2(6,5),Vector2(34,34))
	region_label = _line(location_panel,"",Vector2(44,0),Vector2(410,22),16,MineStyle.MUTED)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label = _line(location_panel,"",Vector2(44,20),Vector2(410,21),16,MineStyle.INK)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	objective_bar = MineStyle.meter(location_panel,Vector2(10,42),Vector2(444,2),MineStyle.AMBER)
	relic_row = Control.new()
	relic_row.position = Vector2(1116,16)
	relic_row.size = Vector2(148,44)
	relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(relic_row)
	gold_label = _compact_button(self,"",Vector2(16,660),Vector2(184,44),func(): skill_details_requested.emit("wallet"))
	gold_label.name = "Wallet"
	gold_label.add_theme_color_override("font_color",MineStyle.AMBER)
	_icon(gold_label,"gold",Vector2(8,9),Vector2(26,26))
	for state in ["normal","hover","pressed","focus"]:
		gold_label.get_theme_stylebox(state).content_margin_left = 34
	_bind_detail(gold_label,"wallet")
	retained_label = _line(self,"",Vector2.ZERO,Vector2.ZERO,16)
	retained_label.hide()
	skill_dock = Control.new()
	skill_dock.position = Vector2(460,640)
	skill_dock.size = Vector2(360,68)
	skill_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skill_dock)
	for i in range(5):
		var slot: String = SKILLS[i] if i < 4 else "dash"
		var cell := Button.new()
		cell.set_script(load("res://scripts/ui/skill_slot.gd"))
		cell.position = Vector2(4+i*60,4)
		skill_dock.add_child(cell)
		cell.configure(Game.run.hero_id if Game.run != null else "CH01",slot,KEYS[i] if i < 4 else Words.text("HUD_DASH_KEY"))
		cell.pressed.connect(func(): skill_details_requested.emit(slot))
		_bind_detail(cell,slot)
		skill_slots.append(cell)
	details_button = _compact_button(skill_dock,"Tab",Vector2(308,12),Vector2(48,44),func(): skill_details_requested.emit("q"))
	details_button.name = "CombatDetails"
	_bind_detail(details_button,"q")
	toast = _line(self,"",Vector2(420,78),Vector2(440,28),17,MineStyle.CYAN)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = _line(self,"",Vector2(380,605),Vector2(520,26),17,MineStyle.AMBER)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation = Control.new()
	navigation.set_script(load("res://scripts/ui/navigation_marker.gd"))
	add_child(navigation)
	navigation.hide()
	tooltip_panel = _plate(self,Vector2(450,418),Vector2(380,210))
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_panel.gui_input.connect(_tooltip_input)
	tooltip_panel.mouse_entered.connect(func(): hovered_control = tooltip_panel; hover_grace = 0.2)
	tooltip_panel.mouse_exited.connect(func():
		if hovered_control == tooltip_panel:
			hovered_control = null
			hover_grace = 0.2)
	tooltip_title = _line(tooltip_panel,"",Vector2(14,9),Vector2(352,28),19,MineStyle.AMBER)
	tooltip_body = MineStyle.label(tooltip_panel,"",Vector2(14,44),Vector2(352,154),16)
	tooltip_panel.hide()
	refresh()

func _plate(parent: Node, at: Vector2, extent: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = at
	panel.size = extent
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := MineStyle.box(Color(0.035,0.055,0.068,0.86),Color("574937"))
	skin.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel",skin)
	parent.add_child(panel)
	return panel

func _icon(parent: Node, icon_key: String, at: Vector2, extent: Vector2) -> Control:
	var icon := Control.new()
	icon.set_script(load("res://scripts/ui/generated_ui_icon.gd"))
	icon.position = at
	icon.size = extent
	parent.add_child(icon)
	icon.configure(icon_key)
	return icon

func _line(parent: Node, text_value: String, at: Vector2, extent: Vector2, font_size: int, color: Color = MineStyle.INK) -> Label:
	var node := MineStyle.literal(parent,text_value,at,extent,font_size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.clip_text = true
	return node

func _compact_button(parent: Node, text_value: String, at: Vector2, extent: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = text_value
	button.position = at
	button.size = extent
	button.custom_minimum_size = Vector2(44,44)
	button.add_theme_font_size_override("font_size",16)
	for state in ["normal","hover","pressed","focus"]:
		var skin := MineStyle.box(Color(0.035,0.055,0.068,0.86),MineStyle.AMBER if state != "normal" else MineStyle.COPPER)
		skin.set_content_margin_all(3)
		if state == "focus": skin.bg_color = Color.TRANSPARENT
		button.add_theme_stylebox_override(state,skin)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _bind_detail(control: Control, slot: String) -> void:
	control.set_meta("detail_slot",slot)
	control.mouse_entered.connect(func():
		hovered_control = control
		last_hover_control = control
		hover_grace = 0.2
		active_detail_slot = slot)
	control.mouse_exited.connect(func():
		if hovered_control == control:
			hovered_control = null
			hover_grace = 0.2)
	control.focus_entered.connect(func(): focused_control = control; active_detail_slot = slot)
	control.focus_exited.connect(func():
		if focused_control == control: focused_control = null)

func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	for control in find_children("*","BaseButton",true,false):
		control.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		hovered_control = null
		focused_control = null
		last_hover_control = null
		hover_grace = 0.0
		if tooltip_panel != null: tooltip_panel.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_update_pointer_guard(event.position)
	if not interaction_enabled or not is_instance_valid(focused_control): return
	var playing := false
	for action in ["move_left","move_right","move_up","move_down","skill_q","skill_f","skill_ultimate","dash","interact"]:
		playing = playing or event.is_action_pressed(action)
	if event is InputEventMouseButton and event.pressed:
		playing = playing or not _pointer_over_instruments(event.position)
	if playing:
		focused_control.release_focus()
		focused_control = null

func _pointer_over_instruments(at: Vector2) -> bool:
	if not interaction_enabled: return false
	for control in find_children("*","BaseButton",true,false):
		if control.is_visible_in_tree() and control.get_global_rect().has_point(at): return true
	return tooltip_panel != null and tooltip_panel.visible and tooltip_panel.get_global_rect().has_point(at)

func _update_pointer_guard(at: Vector2) -> void:
	if not is_instance_valid(room) or not room.has_method("set_pointer_input_blocked"): return
	room.set_pointer_input_blocked(_pointer_over_instruments(at))

func _tooltip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		tooltip_panel.accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT and not active_detail_slot.begins_with("buff:"):
			skill_details_requested.emit(active_detail_slot)

func _process(delta: float) -> void:
	hover_grace = maxf(0,hover_grace-delta)
	toast_remaining = maxf(0,toast_remaining-delta)
	if toast != null: toast.visible = toast_remaining > 0
	refresh()
	_update_pointer_guard(get_global_mouse_position())
	_update_tooltip()

func refresh() -> void:
	_update_buffs()
	if Game.run == null or health_label == null: return
	if hero_definition.get("id","") != Game.run.hero_id:
		hero_definition = ContentRegistry.hero(Game.run.hero_id)
	var hero: Dictionary = hero_definition
	var stats: Dictionary = Game.run.stats
	var kind: String = hero.get("resource_type","rage")
	var max_resource: float = float(stats.get("resource_max",hero.get("resource_max",100)))
	hero_label.text = MineStyle.content_text(hero,"name")+"  /  Lv."+str(Game.run.level)
	health_label.text = Words.text("HUD_HP_COMPACT",{"hp":ceili(Game.run.hp),"max":ceili(Game.run.max_hp)})
	health_bar.max_value = Game.run.max_hp
	health_bar.value = Game.run.hp
	shield_label.text = "+"+str(ceili(Game.run.shield)) if Game.run.shield > 0 else ""
	shield_label.tooltip_text = Words.text("SHIELD_VALUE",{"shield":ceili(Game.run.shield)})
	shield_bar.max_value = Game.run.max_hp
	shield_bar.value = Game.run.shield
	shield_bar.visible = Game.run.shield > 0
	guard_icon.visible = Game.run.shield > 0
	resource_label.text = MineStyle.content_text(hero,"resource_name")+"  "+str(floori(Game.run.resource))+" / "+str(int(max_resource))
	resource_bar.max_value = max_resource
	resource_bar.value = Game.run.resource
	if resource_kind != kind:
		resource_kind = kind
		resource_icon.configure("resource_"+kind)
		resource_label.add_theme_color_override("font_color",MineStyle.resource_color(kind))
		var fill := StyleBoxFlat.new()
		fill.bg_color = MineStyle.resource_color(kind)
		resource_bar.add_theme_stylebox_override("fill",fill)
	gold_label.text = Words.text("HUD_GOLD_COMPACT",{"gold":Game.run.gold})
	retained_label.text = Words.text("RETAINED",{"gold":Balance.death_keep(Game.run.gold)})
	_update_skills()
	_update_relics()
	if is_instance_valid(room):
		hint_label.text = room.interaction_hint()
		# The world now draws its short E tag on the actual focused object.
		hint_label.visible = not hint_label.text.is_empty() and room.get("interaction_overlay") == null
		region_label.text = Words.text("ROOM_"+str(room.layout_id))
		if room.get("expedition_context") != null and not room.expedition_context.is_empty():
			var context: Dictionary = room.expedition_context
			var definition: Dictionary = WorldCatalog.bosses().get(room.layout_id,{}) if context.get("role") == "boss" else WorldCatalog.room(room.layout_id)
			var display_name: String = str(definition.get("name",context.get("name",room.layout_id)))
			region_label.text = str(int(context.get("node_index",0))+1)+" / 8 · "+display_name
		var target: Dictionary = room.navigation_target()
		var title_key := str(target.get("title","NAV_EXIT"))
		objective_label.text = Words.text(title_key) if Words.catalog.has(title_key) else MineStyle.content_text(target,"name",title_key)
		objective_label.tooltip_text = objective_label.text
		objective_bar.max_value = maxi(1,room.encounter_zones.size())
		objective_bar.value = room.activated_encounters.size() if room.objective_complete else maxi(0,room.activated_encounters.size()-1)
		if is_instance_valid(room.get("objectives")):
			var progress: Dictionary = room.objectives.status()
			objective_bar.max_value = maxi(1,int(progress.get("required",1)))
			objective_bar.value = objective_bar.max_value if room.objective_complete else int(progress.get("completed",0))
		_update_navigation()

func _update_buffs() -> void:
	if buff_row == null: return
	active_buffs.clear()
	if Game.run != null and is_instance_valid(room):
		var source: Node = room.get("enemy_props")
		if is_instance_valid(source) and source.has_method("active_buffs"):
			for state: Dictionary in source.active_buffs():
				var effect := str(state.get("effect",""))
				if effect in BUFF_ORDER and float(state.get("remaining",0.0)) > 0.0:
					active_buffs[effect] = state
	for effect: String in buff_chips.keys():
		if active_buffs.has(effect): continue
		var expired: Control = buff_chips[effect]
		if expired.has_focus(): expired.release_focus()
		if hovered_control == expired: hovered_control = null
		if focused_control == expired: focused_control = null
		if last_hover_control == expired:
			last_hover_control = null
			hover_grace = 0.0
		expired.hide()
		buff_row.remove_child(expired)
		expired.queue_free()
		buff_chips.erase(effect)
	var ordinal := 0
	for effect: String in BUFF_ORDER:
		if not active_buffs.has(effect): continue
		if not buff_chips.has(effect):
			var new_chip := BuffChip.new()
			buff_row.add_child(new_chip)
			new_chip.configure(effect)
			new_chip.focus_mode = Control.FOCUS_ALL if interaction_enabled else Control.FOCUS_NONE
			_bind_detail(new_chip,"buff:"+effect)
			buff_chips[effect] = new_chip
		var chip: BuffChip = buff_chips[effect]
		chip.position = Vector2(ordinal*48,0)
		chip.update_state(active_buffs[effect])
		ordinal += 1
	buff_row.size.x = maxi(0,ordinal*48-4)
	buff_row.visible = ordinal > 0
	if active_detail_slot.begins_with("buff:") and not active_buffs.has(active_detail_slot.trim_prefix("buff:")) and tooltip_panel != null:
		tooltip_panel.hide()

func buff_info(effect: String) -> Dictionary:
	if not active_buffs.has(effect): return {}
	var state: Dictionary = active_buffs[effect]
	var remaining := maxf(0.0,float(state.get("remaining",0.0)))
	var duration := float(state.get("duration",0.0))
	var english := Words.locale == "en"
	var summary := "Duration %.0fs · Remaining %.1fs" % [duration,remaining] if english else "持续 %.0f 秒 · 剩余 %.1f 秒" % [duration,remaining]
	if effect == "guard" and state.has("amount"):
		summary += ("\nShield remaining: %d" if english else "\n当前护盾：%d") % ceili(float(state.amount))
	var note := "Same type refreshes its duration; does not stack. Ends when leaving the room." if english else "同类再次获得只刷新持续时间，不叠加。离开房间时失效。"
	return {"name":MineStyle.content_text(state,"name"),"description":MineStyle.content_text(state,"description"),"summary":summary,"remaining":remaining,"duration":duration,"state":state.duplicate(true),"note":note}

## Temporary buff paint is measured independently of the standing HUD footprint.
func active_buff_coverage_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for chip: BuffChip in buff_chips.values():
		if chip.is_visible_in_tree(): result.append(Rect2(chip.global_position+BuffChip.PAINTED_RECT.position,BuffChip.PAINTED_RECT.size))
	return result

func _update_relics() -> void:
	var signature := ",".join(Game.run.relics)
	if signature == previous_relics: return
	for child in relic_row.get_children(): child.queue_free()
	for i in range(Game.run.relics.size()):
		var id: String = Game.run.relics[i]
		var chip := _compact_button(relic_row,"",Vector2(i*52,0),Vector2(44,44),func(): relic_details_requested.emit())
		chip.name = "Relic_"+id
		_bind_detail(chip,"relic:"+id)
		MineArt.relic(chip,id,Vector2(4,4),Vector2(36,36))
	if has_drawn_state and not Game.run.relics.is_empty():
		toast.text = Words.text("RELIC_ACQUIRED",{"name":Words.text("RELIC_"+Game.run.relics[-1].to_upper()+"_NAME")})
		toast_remaining = 4.0
	previous_relics = signature
	has_drawn_state = true

func skill_info(slot: String) -> Dictionary:
	if Game.run == null: return {}
	if hero_definition.is_empty(): hero_definition = ContentRegistry.hero(Game.run.hero_id)
	var skill: Dictionary = hero_definition.get("dash",{}).duplicate(true) if slot == "dash" else hero_definition.get("skills",{}).get(slot,{}).duplicate(true)
	if slot != "dash" and is_instance_valid(room) and is_instance_valid(room.player):
		skill.merge(room.player.skill_definition(slot),true)
	var cooldown := 0.0
	if is_instance_valid(room) and is_instance_valid(room.player):
		cooldown = float(room.player.dash_cooldown) if slot == "dash" else float(room.player.cooldowns.get(slot,0))
	var locked: bool = Game.run.level < int(skill.get("unlock",1))
	var cost := float(skill.get("cost",0))
	var insufficient: bool = Game.run.resource < cost
	var state := Words.text("HUD_SKILL_LOCK",{"level":skill.get("unlock",1)}) if locked else Words.text("HUD_REMAINING",{"time":"%.1f" % cooldown}) if cooldown > 0 else Words.text("HUD_RESOURCE_MISSING",{"amount":ceili(cost-Game.run.resource),"resource":MineStyle.content_text(hero_definition,"resource_name")}) if insufficient else Words.text("HUD_READY")
	var summary := Words.text("HUD_FINAL_COST",{"cost":snappedf(cost,0.1),"resource":MineStyle.content_text(hero_definition,"resource_name"),"cooldown":snappedf(float(skill.get("cooldown",0)),0.1)})
	return {"name":MineStyle.content_text(skill,"name"),"description":MineStyle.content_text(skill,"description",Words.text("HUD_DASH_DESCRIPTION")),"summary":summary,"state":state,"locked":locked,"unlock":int(skill.get("unlock",1)),"cooldown":cooldown,"duration":float(skill.get("cooldown",0)),"insufficient":insufficient,"accent":MineStyle.resource_color(resource_kind),"ready":not locked and cooldown <= 0 and not insufficient}

func _update_skills() -> void:
	for i in range(skill_slots.size()):
		var slot: String = SKILLS[i] if i < 4 else "dash"
		skill_slots[i].key = KEYS[i] if i < 4 else Words.text("HUD_DASH_KEY")
		var info := skill_info(slot)
		info["details"] = str(info.name)+"\n"+str(info.summary)+"\n"+str(info.state)
		skill_slots[i].update_state(info)
		# The same accessible text is shown by our focus-aware instrument tooltip;
		# suppress the engine's second native tooltip above that custom surface.
		skill_slots[i].tooltip_text = ""

func _update_tooltip() -> void:
	if tooltip_panel == null or Game.run == null: return
	var target: Control = hovered_control if is_instance_valid(hovered_control) else null
	if not is_instance_valid(target) and hover_grace > 0 and is_instance_valid(last_hover_control):
		target = last_hover_control
	if not is_instance_valid(target): target = focused_control
	if not interaction_enabled or not is_instance_valid(target):
		tooltip_panel.hide()
		return
	if target != tooltip_panel: active_detail_slot = str(target.get_meta("detail_slot","q"))
	var body: String
	if active_detail_slot == "wallet":
		tooltip_title.text = Words.text("CARRIED",{"gold":Game.run.gold})
		body = retained_label.text+"\n\n"+Words.text("HUD_WALLET_NOTE")
	elif active_detail_slot.begins_with("relic:"):
		var key := "RELIC_"+active_detail_slot.trim_prefix("relic:").to_upper()
		tooltip_title.text = Words.text(key+"_NAME")
		body = Words.text(key+"_DESC")
	elif active_detail_slot.begins_with("buff:"):
		var info := buff_info(active_detail_slot.trim_prefix("buff:"))
		if info.is_empty():
			tooltip_panel.hide()
			return
		tooltip_title.text = str(info.name)
		body = str(info.description)+"\n"+str(info.summary)+"\n\n"+str(info.note)
	else:
		var info := skill_info(active_detail_slot)
		tooltip_title.text = str(info.name)
		body = str(info.summary)+"\n"+str(info.state)+"\n\n"+Words.text("HUD_DETAIL_HINT")
	tooltip_body.text = body
	tooltip_panel.size.y = maxf(164,tooltip_body.get_theme_font("font").get_multiline_string_size(body,HORIZONTAL_ALIGNMENT_LEFT,352,16).y+64)
	tooltip_panel.size.y = minf(280,tooltip_panel.size.y)
	tooltip_body.size.y = tooltip_panel.size.y-54
	if target != tooltip_panel:
		var bounds := target.get_global_rect()
		var tooltip_y := bounds.position.y-tooltip_panel.size.y
		# Touch the source's edge; slow pointers and trackpads need no timed jump.
		if tooltip_y < 112: tooltip_y = bounds.end.y
		tooltip_panel.position = Vector2(clampf(bounds.get_center().x-190,16,884),tooltip_y)
	tooltip_panel.show()

## Actual screen-space boxes, used by QA instead of the full-screen root rect.
func coverage_rects() -> Array[Rect2]:
	var result: Array[Rect2] = [status_panel.get_global_rect(),location_panel.get_global_rect(),gold_label.get_global_rect(),skill_dock.get_global_rect()]
	if not Game.run.relics.is_empty(): result.append(relic_row.get_global_rect())
	return result

func _update_navigation() -> void:
	if navigation == null or not is_instance_valid(room.player) or not room.has_method("navigation_target"): return
	var target: Dictionary = room.navigation_target()
	if target.is_empty():
		navigation.hide()
		return
	var world_position: Vector2 = target.get("position",Vector2.ZERO)
	var distance: float = room.player.global_position.distance_to(world_position)
	var target_ui: Vector2 = get_global_transform_with_canvas().affine_inverse()*(room.get_canvas_transform()*world_position)
	navigation.visible = not Rect2(32,112,1216,484).has_point(target_ui) and distance > 90.0
	if not navigation.visible: return
	var direction := target_ui-Vector2(640,360)
	if direction.length_squared() < 0.01: return
	var unit := direction.normalized()
	var factor := minf(554.0/maxf(absf(unit.x),0.001),190.0/maxf(absf(unit.y),0.001))
	var edge := Vector2(640,360)+unit*factor
	navigation.position = Vector2(clampf(edge.x-navigation.size.x*0.5,20,1260-navigation.size.x),clampf(edge.y-navigation.size.y*0.5,154,536))
	var title_key := str(target.get("title","NAV_EXIT"))
	var title := Words.text(title_key) if Words.catalog.has(title_key) else MineStyle.content_text(target,"name",title_key)
	navigation.update_target(unit,title,roundi(distance),"exit" if target.get("kind","") == "extract" else "route")
