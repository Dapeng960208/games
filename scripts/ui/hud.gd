extends Control
## Bright expedition ribbons; every value is read from the live room and run.
signal relic_details_requested()
signal skill_details_requested(slot: String)
signal inventory_requested()
signal layout_changed(screen_size: Vector2)

const HUD_INK := Color("392843")
const HUD_MUTED := Color("766474")
const HUD_AMBER := Color("a66a2e")
const HUD_CYAN := Color("257f83")
const HUD_RED := Color("e6664f")
const GrowthReadout = preload("res://scripts/ui/progression_readout.gd")
const RewardPolicy = preload("res://scripts/world/room_rewards.gd")
const QuestLocalization = preload("res://scripts/ui/quest_localization.gd")
const Bindings = preload("res://scripts/core/control_bindings.gd")

const SKILLS := ["q","secondary","f","ultimate"]
const KEYS := ["Q","W","E","R"]
const SKILL_ACTIONS := ["skill_q","skill_secondary","skill_f","skill_ultimate","dash"]
const BUFF_ORDER := ["damage","guard","supply_guard","haste","burn","shock","chill","corrosion","bleed","grievous","damage_reduction","invulnerable"]
const COMBAT_STATUS_LABELS := {"burn":"灼烧","shock":"感电","chill":"寒冷","corrosion":"腐蚀","bleed":"流血","grievous":"重伤","damage_reduction":"减伤","invulnerable":"无敌"}
const COMBAT_STATUS_NOTES := {"burn":"持续受到魔法伤害。","shock":"后续命中可引发电击。","chill":"移动速度降低。","corrosion":"护甲降低并持续受到物理伤害。","bleed":"持续受到物理伤害。","grievous":"受到的治疗降低 40%。","damage_reduction":"临时降低受到的伤害。","invulnerable":"持续时间内免疫伤害。"}


## A reusable silhouette, rather than a permanent opaque rectangular card.
class ParchmentPlate extends Panel:
	var artwork: Texture2D
	var ribbon := true
	var art_key := "paper"
	var skin: Texture2D
	var compass: Texture2D
	var reward_bullet_y := 147.0
	var skin_scale := 1.0
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)
		var sampler = preload("res://scripts/ui/texture_sampler.gd")
		artwork = sampler.sampled("res://assets/generated/ui/storybook_parchment_v1.png")
		if FileAccess.file_exists("res://scripts/ui/storybook_art.gd"):
			var art: Script = load("res://scripts/ui/storybook_art.gd") as Script
			var mapped_key: String = {"expedition_plaque":"hero_ribbon","circuit_ribbon":"skill_ribbon","paper":"hero_ribbon"}.get(art_key,art_key)
			skin = art.texture(mapped_key)
			if art_key in ["paper","hero_ribbon","circuit_ribbon"]: skin = null
			compass = art.texture("compass")
			if skin != null and art_key != "quest_note":
				var target_height: float = {"hero_ribbon":117.0,"expedition_plaque":35.0,"circuit_ribbon":85.0}.get(art_key,size.y)
				skin_scale = target_height/skin.get_height()
				var bitmap: Image = skin.get_image()
				bitmap.resize(maxi(1,roundi(bitmap.get_width()*skin_scale)),maxi(1,roundi(target_height)),Image.INTERPOLATE_LANCZOS)
				bitmap.generate_mipmaps()
				skin = ImageTexture.create_from_image(bitmap)
	func _paper(at: Rect2) -> void:
		if skin != null:
			var box := StyleBoxTexture.new()
			box.texture = skin
			var margins: Array = [72,20,72,20] if art_key in ["skill_ribbon","circuit_ribbon"] else [116,56,76,42]
			for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
				box.set_texture_margin(side,float(margins[side])*skin_scale)
				box.set_expand_margin(side,0)
			box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
			box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
			draw_style_box(box,at)
			return
		# Native parchment fallback remains readable while new art is imported.
		var box := MineStyle.paper_box()
		draw_style_box(box,at)
	func _draw() -> void:
		match art_key:
			"hero_ribbon":
				_paper(Rect2(78,0,size.x-78,124))
			"expedition_plaque":
				var plaque_width := minf(188,size.x-16)
				_paper(Rect2((size.x-plaque_width)*.5,-2,plaque_width,35))
			"circuit_ribbon":
				_paper(Rect2(40,2,size.x-40,size.y-2))
			"quest_note":
				# A soft page wash sits only under the text; no standing hard card.
				if skin != null:
					draw_texture_rect(skin,Rect2(Vector2.ZERO,size),false,Color(1,1,1,.80))
				else:
					draw_style_box(MineStyle.box(Color(.99,.93,.80,.62),Color.TRANSPARENT,0),Rect2(10,4,size.x-10,size.y-6))
				draw_line(Vector2(35,34),Vector2(size.x-8,34),Color("af8f59"),1.5,true)
				if compass != null:
					draw_texture_rect(compass,Rect2(3,3,34,34),false)
				else:
					var center := Vector2(20,20)
					draw_arc(center,12,0,TAU,28,Color("b68d54"),2,true)
					draw_polyline(PackedVector2Array([center+Vector2(0,-18),center+Vector2(7,0),center+Vector2(0,18),center+Vector2(-7,0),center+Vector2(0,-18)]),Color("392843"),2,true)
					draw_polyline(PackedVector2Array([center+Vector2(-18,0),center+Vector2(0,-7),center+Vector2(18,0),center+Vector2(0,7),center+Vector2(-18,0)]),Color("392843"),2,true)
				for y in [52.0,reward_bullet_y]:
					draw_circle(Vector2(20,y),7,Color("543b40"))
					draw_circle(Vector2(20,y),5,Color("f3cf87") if y < 60 else Color("d2c4a6"))
			"skill_ribbon":
				_paper(Rect2(Vector2.ZERO,size))
			_:
				_paper(Rect2(Vector2.ZERO,size))

class ExpeditionBeads extends Control:
	var current := 1
	var count := 6
	var bead: Texture2D
	var compass: Texture2D
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if FileAccess.file_exists("res://scripts/ui/storybook_art.gd"):
			var art: Script = load("res://scripts/ui/storybook_art.gd") as Script
			bead = art.texture("route_bead")
			compass = art.texture("compass")
	func _draw() -> void:
		var y := size.y*.5
		var first := 14.0
		var last := size.x-53.0
		draw_line(Vector2(first,y+2),Vector2(size.x-13,y+2),Color(.18,.13,.12,.22),5,true)
		draw_line(Vector2(first,y),Vector2(size.x-13,y),Color("46383b"),7,true)
		draw_line(Vector2(first,y-1),Vector2(size.x-13,y-1),Color("dab573"),3,true)
		for index in maxi(1,count):
			var x := first+(last-first)*float(index)/maxf(1,count-1)
			var at := Vector2(x,y)
			if bead != null:
				draw_texture_rect(bead,Rect2(at-Vector2(15,15),Vector2(30,30)),false)
			else:
				draw_circle(at,14,Color("573f38"))
				draw_circle(at,12,Color("d5ab63"))
				draw_circle(at,10,Color("484451"))
			draw_circle(at,9,Color("f4cd78") if index < current else Color("445160"))
			draw_arc(at,10,-PI*.94,-PI*.16,18,Color("fff1b4") if index < current else Color("8c999f"),1.5,true)
			if index == current-1: draw_arc(at,15,0,TAU,28,Color("deb65e"),1.5,true)
		if compass != null:
			draw_texture_rect(compass,Rect2(size.x-39,y-17,34,34),false,Color(1,.91,.61,.92))
		else:
			draw_polyline(PackedVector2Array([Vector2(size.x-33,y+8),Vector2(size.x-24,y-13),Vector2(size.x-15,y+8),Vector2(size.x-33,y+8)]),Color("a66a2e"),1.5,true)

class HeroBust extends Control:
	var hero_id := ""
	var texture: Texture2D
	var portrait_is_cutout := false
	func configure(id: String) -> void:
		if hero_id == id: return
		hero_id = id
		var path := "res://assets/generated/heroes/"+id+"_storybook_portrait_v1.png"
		portrait_is_cutout = FileAccess.file_exists(path)
		if not portrait_is_cutout: path = "res://assets/generated/heroes/"+id+"_portrait_v1.png"
		texture = preload("res://scripts/ui/texture_sampler.gd").sampled(path)
		queue_redraw()
	func _draw() -> void:
		if texture == null: return
		if portrait_is_cutout:
			var source := texture.get_size()
			var extent := source*minf(size.x/source.x,size.y/source.y)
			draw_texture_rect(texture,Rect2(Vector2(0,size.y-extent.y),extent),false)
		else:
			var source := texture.get_size()
			var region := Rect2(source*Vector2(.25,.012),source*Vector2(.52,.40))
			var extent := region.size*minf((size.x-24)/region.size.x,(size.y-20)/region.size.y)
			draw_texture_rect_region(texture,Rect2(Vector2((size.x-extent.x)*.5,size.y-10-extent.y),extent),region)

class PassiveGlyph extends Control:
	var hero_id := "CH01"
	var accent := Color("257f83")
	func _draw() -> void:
		var center := size*.5
		draw_circle(center+Vector2(0,2),23,Color(.20,.12,.12,.18))
		draw_circle(center,23,Color("a66a2e"))
		draw_circle(center,20,Color("fff1cf"))
		draw_arc(center,22,-PI*.95,-PI*.08,32,Color("ffe8a2"),2,true)
		if hero_id == "CH01":
			draw_polyline(PackedVector2Array([center+Vector2(-10,-12),center+Vector2(10,-12),center+Vector2(9,4),center+Vector2(0,13),center+Vector2(-9,4),center+Vector2(-10,-12)]),accent,2.5,true)
			draw_line(center+Vector2(0,-7),center+Vector2(0,7),accent,2.5,true)
		elif hero_id == "CH02":
			draw_arc(center,11,0,TAU,32,accent,2.5,true)
			draw_circle(center,4,accent)
			for axis in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
				draw_line(center+axis*13,center+axis*17,accent,2,true)
		else:
			for i in 6:
				var axis := Vector2.from_angle(i*TAU/6)
				draw_line(center+axis*7,center+axis*15,accent,2.5,true)
			draw_arc(center,7,0,TAU,24,accent,2,true)

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
		var artwork := "pressure" if effect == "damage" else "guard" if effect == "supply_guard" else effect
		if effect in ["damage","guard","supply_guard","haste"]:
			generated_texture = Sampler.sampled("res://assets/generated/props/buff_"+artwork+"_v1.png")
		elif effect in ["burn","shock","chill","corrosion"]:
			generated_texture = Sampler.sampled("res://assets/generated/ui/state_"+effect+"_v1.png")

	func update_state(next_state: Dictionary) -> void:
		state = next_state.duplicate(true)
		queue_redraw()

	func remaining_seconds() -> int:
		return ceili(maxf(0.0,float(state.get("remaining",0.0))))

	func _draw() -> void:
		if state.is_empty(): return
		var accent: Color = state.get("color",Color("e6aa4a"))
		var active := is_hovered() or has_focus()
		draw_style_box(MineStyle.box(Color("fff3d7"),Color("c49b60"),1),PAINTED_RECT)
		draw_rect(PAINTED_RECT,accent if active else Color("826345"),false,2.0 if active else 1.0)
		if generated_texture != null:
			var source := generated_texture.get_size()
			var extent := source*minf(22.0/source.x,22.0/source.y)
			draw_texture_rect(generated_texture,Rect2(Vector2(22,14)-extent*0.5,extent),false)
		else:
			_draw_glyph(accent)
		var font := get_theme_font("font","Button")
		var value := ("RDY" if Words.locale == "en" else "待机") if bool(state.get("prepared",false)) else str(remaining_seconds())
		var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var at := Vector2((size.x-width)*0.5,39)
		draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,2,Color("fff3d7"))
		draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("392843"))

	func _draw_glyph(accent: Color) -> void:
		# Original, distinct silhouettes remain usable before generated PNG import.
		if effect in ["guard","supply_guard","damage_reduction","invulnerable"]:
			draw_polyline(PackedVector2Array([Vector2(14,6),Vector2(30,6),Vector2(29,17),Vector2(22,24),Vector2(15,17),Vector2(14,6)]),accent,2.0,true)
			draw_line(Vector2(22,10),Vector2(22,18),accent,2.0,true)
			if effect == "invulnerable": draw_arc(Vector2(22,14),13,0,TAU,28,accent,1.5,true)
		elif effect == "grievous":
			draw_line(Vector2(22,5),Vector2(22,23),accent,4,true)
			draw_line(Vector2(13,14),Vector2(31,14),accent,4,true)
			draw_line(Vector2(11,4),Vector2(34,25),Color("f3ddc1"),2,true)
		elif effect == "bleed":
			draw_colored_polygon(PackedVector2Array([Vector2(22,4),Vector2(29,17),Vector2(27,22),Vector2(22,25),Vector2(17,22),Vector2(15,17)]),accent)
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
var experience_label: Label
var experience_bar: ProgressBar
var progression_button: Button
var observed_run_id := ""
var observed_level := -1
var growth_info: Dictionary = {}
var notifications: Array[Dictionary] = []
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
var class_label: Label
var class_bar: ProgressBar
var passive_panel: Panel
var passive_title: Label
var passive_state: Label
var passive_hint: Label
var passive_bar: ProgressBar
var passive_glyph: Control
var passive_button: Button
var passive_snapshot: Dictionary = {}
var inventory_button: Button
var attack_label: Label
var attack_plate: Panel
var equipment_actions: Control
var screen_size := Vector2.ZERO
var _route_button: Control
var _compact_layout := false
var _skill_feedback_actor: Node
var quest_panel: Panel
var quest_progress: Label
var quest_reward: Label
var expedition_label: Label
var expedition_beads: Control
var hero_bust: Control
var skill_ribbon: Panel
var quest_reward_signature := ""
var cached_quest_reward := ""
var quest_button: Button
var quest_full_action := ""
var quest_bullets: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MineStyle.make_theme()
	status_panel = _plate(self,Vector2(12,22),Vector2(374,126),"hero_ribbon")
	status_panel.name = "HeroRibbon"
	hero_bust = HeroBust.new()
	hero_bust.position = Vector2(-6,-21)
	hero_bust.size = Vector2(132,146)
	hero_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_child(hero_bust)
	hero_label = _line(status_panel,"",Vector2(125,3),Vector2(234,30),21,HUD_INK)
	experience_label = _line(status_panel,"",Vector2(206,30),Vector2(105,22),16,HUD_MUTED)
	experience_label.name = "ExperienceValue"
	experience_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	experience_label.hide()
	experience_bar = MineStyle.meter(status_panel,Vector2(86,51),Vector2(225,3),Color("b38b42"))
	experience_bar.name = "ExperienceProgress"
	experience_bar.hide()
	progression_button = Button.new()
	progression_button.name = "ProgressionReadout"
	progression_button.position = Vector2(120,0)
	progression_button.size = Vector2(239,78)
	progression_button.custom_minimum_size = Vector2(44,44)
	progression_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	progression_button.mouse_filter = Control.MOUSE_FILTER_STOP
	for skin in ["normal","hover","pressed","focus"]:
		progression_button.add_theme_stylebox_override(skin,StyleBoxEmpty.new())
	status_panel.add_child(progression_button)
	_bind_detail(progression_button,"progression")
	progression_button.pressed.connect(func(): skill_details_requested.emit("progression"))
	health_bar = MineStyle.meter(status_panel,Vector2(125,38),Vector2(234,18),Color("da6243"))
	health_label = _line(status_panel,"",Vector2(137,35),Vector2(210,24),17,Color("fff7e1"))
	guard_icon = _icon(status_panel,"state_guard",Vector2(7,105),Vector2(20,20))
	shield_label = _line(status_panel,"",Vector2(29,104),Vector2(49,22),16,HUD_CYAN)
	shield_bar = MineStyle.meter(status_panel,Vector2(125,57),Vector2(234,3),Color("4b9aa6"))
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_icon = _icon(status_panel,"resource_rage",Vector2(125,69),Vector2(20,20))
	resource_label = _line(status_panel,"",Vector2(150,66),Vector2(110,23),15,HUD_MUTED)
	resource_bar = MineStyle.meter(status_panel,Vector2(270,73),Vector2(89,8),Color("8c9fa2"))
	class_label = _line(status_panel,"",Vector2(120,98),Vector2(240,21),16,HUD_MUTED)
	class_label.mouse_filter = Control.MOUSE_FILTER_STOP
	class_bar = MineStyle.meter(status_panel,Vector2(125,109),Vector2(234,2),HUD_CYAN)
	class_bar.hide()
	buff_row = Control.new()
	buff_row.name = "ActiveRoomBuffs"
	buff_row.position = Vector2(12,154)
	buff_row.size = Vector2(140,44)
	buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(buff_row)
	buff_row.hide()
	location_panel = _plate(self,Vector2(461,22),Vector2(358,62),"expedition_plaque")
	location_panel.name = "ExpeditionRibbon"
	expedition_label = _line(location_panel,"",Vector2(97,-1),Vector2(172,28),19,HUD_INK)
	expedition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expedition_beads = ExpeditionBeads.new()
	expedition_beads.position = Vector2(10,28)
	expedition_beads.size = Vector2(338,36)
	expedition_beads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_panel.add_child(expedition_beads)
	quest_panel = _plate(self,Vector2(1000,387),Vector2(264,166),"quest_note")
	quest_panel.name = "QuestRibbon"
	region_label = _line(quest_panel,"",Vector2(43,6),Vector2(203,29),20,HUD_INK)
	objective_label = _line(quest_panel,"",Vector2(34,42),Vector2(218,69),17,HUD_INK)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	objective_label.max_lines_visible = -1
	objective_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	quest_progress = _line(quest_panel,"",Vector2(34,112),Vector2(218,21),16,HUD_MUTED)
	objective_bar = MineStyle.meter(quest_panel,Vector2(34,133),Vector2(218,2),Color("bd964e"))
	objective_bar.hide()
	quest_reward = _line(quest_panel,"",Vector2(34,139),Vector2(218,22),16,HUD_INK)
	quest_button = Button.new()
	quest_button.name = "QuestDetails"
	quest_button.position = Vector2(12,36)
	quest_button.size = Vector2(240,126)
	quest_button.custom_minimum_size = Vector2(44,44)
	quest_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	quest_button.mouse_filter = Control.MOUSE_FILTER_STOP
	for state in ["normal","hover","pressed","focus"]: quest_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	quest_panel.add_child(quest_button)
	_bind_detail(quest_button,"quest")
	quest_button.pressed.connect(func():
		quest_button.grab_focus()
		focused_control = quest_button
		active_detail_slot = "quest"
		_update_tooltip())
	relic_row = Control.new()
	relic_row.position = Vector2(1116,68)
	relic_row.size = Vector2(148,44)
	relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(relic_row)
	gold_label = _compact_button(self,"",Vector2(1130,16),Vector2(134,44),func(): skill_details_requested.emit("wallet"))
	gold_label.name = "Wallet"
	gold_label.add_theme_color_override("font_color",HUD_INK)
	_icon(gold_label,"gold",Vector2(8,9),Vector2(26,26))
	for state in ["normal","hover","pressed","focus"]:
		gold_label.get_theme_stylebox(state).content_margin_left = 32
	_bind_detail(gold_label,"wallet")
	retained_label = _line(self,"",Vector2.ZERO,Vector2.ZERO,16)
	retained_label.hide()
	skill_dock = Control.new()
	skill_dock.position = Vector2(388,596)
	skill_dock.size = Vector2(504,112)
	skill_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skill_dock)
	skill_ribbon = _plate(skill_dock,Vector2(0,36),Vector2(504,73),"skill_ribbon")
	for i in range(5):
		var slot: String = SKILLS[i] if i < 4 else "dash"
		var cell := Button.new()
		cell.set_script(load("res://scripts/ui/skill_slot.gd"))
		cell.position = Vector2(8+i*88,0)
		skill_dock.add_child(cell)
		cell.configure(Game.run.hero_id if Game.run != null else "CH01",slot,_key_for_slot(i))
		cell.pressed.connect(func(): skill_details_requested.emit(slot))
		_bind_detail(cell,slot)
		skill_slots.append(cell)
	equipment_actions = Control.new()
	equipment_actions.name = "EquipmentActions"
	equipment_actions.size = Vector2(184,112)
	equipment_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(equipment_actions)
	inventory_button = _compact_button(equipment_actions,"背包  [B]",Vector2(0,0),Vector2(184,44),func(): inventory_requested.emit())
	inventory_button.name = "Backpack"
	_bind_detail(inventory_button,"inventory")
	attack_plate = _plate(equipment_actions,Vector2(0,53),Vector2(184,55),"paper")
	details_button = _compact_button(equipment_actions,"Tab",Vector2(0,58),Vector2(44,44),func(): skill_details_requested.emit("q"))
	details_button.name = "CombatDetails"
	_bind_detail(details_button,"q")
	attack_label = _line(equipment_actions,"",Vector2(52,55),Vector2(132,51),16,HUD_MUTED)
	attack_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	attack_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	passive_panel = _plate(self,Vector2(14,590),Vector2(288,118),"passive_ribbon")
	passive_panel.name = "HeroPassive"
	passive_glyph = PassiveGlyph.new()
	passive_glyph.position = Vector2(7,4)
	passive_glyph.size = Vector2(48,48)
	passive_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	passive_panel.add_child(passive_glyph)
	passive_title = _line(passive_panel,"",Vector2(62,7),Vector2(210,24),18,HUD_INK)
	passive_state = _line(passive_panel,"",Vector2(62,34),Vector2(210,23),16,HUD_CYAN)
	passive_bar = MineStyle.meter(passive_panel,Vector2(14,59),Vector2(260,3),HUD_CYAN)
	passive_hint = _line(passive_panel,"",Vector2(14,66),Vector2(260,48),16,HUD_MUTED)
	passive_hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	passive_hint.max_lines_visible = 2
	passive_button = Button.new()
	passive_button.name = "PassiveDetails"
	passive_button.position = Vector2.ZERO
	passive_button.size = passive_panel.size
	passive_button.mouse_filter = Control.MOUSE_FILTER_STOP
	for skin in ["normal","hover","pressed","focus"]:
		passive_button.add_theme_stylebox_override(skin,StyleBoxEmpty.new())
	passive_panel.add_child(passive_button)
	_bind_detail(passive_button,"passive")
	passive_button.pressed.connect(func(): passive_button.grab_focus())
	toast = _line(self,"",Vector2(352,94),Vector2(576,60),17,HUD_CYAN)
	toast.name = "GrowthAndLootNotice"
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.max_lines_visible = 3
	toast.add_theme_color_override("font_outline_color",Color("fff3d7"))
	toast.add_theme_constant_override("outline_size",3)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = _line(self,"",Vector2(380,568),Vector2(520,26),17,HUD_AMBER)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation = Control.new()
	navigation.set_script(load("res://scripts/ui/navigation_marker.gd"))
	add_child(navigation)
	navigation.hide()
	tooltip_panel = _plate(self,Vector2(450,378),Vector2(380,210))
	tooltip_panel.name = "InstrumentTooltip"
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_panel.gui_input.connect(_tooltip_input)
	tooltip_panel.mouse_entered.connect(func(): hovered_control = tooltip_panel; hover_grace = 0.2)
	tooltip_panel.mouse_exited.connect(func():
		if hovered_control == tooltip_panel:
			hovered_control = null
			hover_grace = 0.2)
	tooltip_title = _line(tooltip_panel,"",Vector2(14,9),Vector2(352,28),19,HUD_INK)
	tooltip_body = MineStyle.label(tooltip_panel,"",Vector2(14,44),Vector2(352,154),16,HUD_INK)
	tooltip_body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tooltip_panel.hide()
	resized.connect(_apply_layout)
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	refresh()

## All measurements are native Control coordinates in the HUD's CanvasLayer.
## Camera movement and the much larger world arena never change this layout.
func _apply_layout() -> void:
	if status_panel == null: return
	screen_size = size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	var margin := 12.0
	_compact_layout = screen_size.x < 1020 or screen_size.y < 620
	var stacked := screen_size.x < 880
	status_panel.position = Vector2(margin,22)
	gold_label.position = Vector2(screen_size.x-gold_label.size.x-margin,16)
	var route_width := clampf(screen_size.x-570,190,358)
	location_panel.size.x = route_width
	location_panel.position = Vector2(clampf((screen_size.x-route_width)*.5,402,screen_size.x-route_width-166),22)
	if screen_size.x < 760:
		location_panel.position = Vector2(margin,154)
	expedition_label.position.x = (route_width-172)*.5
	expedition_beads.size.x = route_width-20
	expedition_beads.queue_redraw()
	location_panel.queue_redraw()
	buff_row.position = Vector2(margin,154 if screen_size.x >= 760 else 220)
	relic_row.position = Vector2(screen_size.x-relic_row.size.x-margin,118)
	var cell_width := 80.0 if _compact_layout else 88.0
	skill_dock.size = Vector2(cell_width*5+16,112)
	skill_dock.position.y = screen_size.y-skill_dock.size.y-margin
	skill_ribbon.size.x = skill_dock.size.x
	for i in skill_slots.size():
		skill_slots[i].custom_minimum_size.x = cell_width
		skill_slots[i].size.x = cell_width
		skill_slots[i].position.x = 8+i*cell_width
	equipment_actions.size.x = 176 if _compact_layout else 184
	equipment_actions.position = Vector2(screen_size.x-equipment_actions.size.x-margin,skill_dock.position.y)
	inventory_button.size.x = equipment_actions.size.x
	attack_label.size.x = equipment_actions.size.x-52
	attack_plate.size.x = equipment_actions.size.x
	passive_panel.size.x = clampf(screen_size.x-skill_dock.size.x-equipment_actions.size.x-48,220,288)
	passive_panel.position = Vector2(margin,screen_size.y-passive_panel.size.y-margin)
	if stacked:
		passive_panel.size.x = 272
		passive_panel.position.y = skill_dock.position.y-passive_panel.size.y-12
		equipment_actions.position.y = passive_panel.position.y
		skill_dock.position.x = (screen_size.x-skill_dock.size.x)*.5
	else:
		skill_dock.position.x = clampf((screen_size.x-skill_dock.size.x)*.5,passive_panel.get_rect().end.x+12,equipment_actions.position.x-skill_dock.size.x-12)
	passive_title.size.x = passive_panel.size.x-76
	passive_state.size.x = passive_panel.size.x-76
	passive_bar.size.x = passive_panel.size.x-28
	passive_hint.size.x = passive_panel.size.x-28
	passive_button.size = passive_panel.size
	quest_panel.size.x = 256 if _compact_layout else 272
	quest_panel.position.x = screen_size.x-quest_panel.size.x-margin
	region_label.size.x = quest_panel.size.x-58
	objective_label.size.x = quest_panel.size.x-48
	quest_progress.size.x = quest_panel.size.x-48
	quest_reward.size.x = quest_panel.size.x-48
	quest_button.size.x = quest_panel.size.x-24
	toast.position = Vector2(maxf(24,(screen_size.x-576)*.5),94)
	toast.size.x = minf(576,screen_size.x-48)
	hint_label.size.x = minf(520,screen_size.x-32)
	hint_label.position = Vector2((screen_size.x-hint_label.size.x)*.5,skill_dock.position.y-31)
	tooltip_panel.size.x = minf(380,screen_size.x-32)
	tooltip_title.size.x = tooltip_panel.size.x-28
	tooltip_body.size.x = tooltip_panel.size.x-28
	if is_instance_valid(_route_button): _route_button.position = route_button_rect().position
	layout_changed.emit(screen_size)

func route_button_rect() -> Rect2:
	# The route control is owned by Main; the HUD reserves and positions it.
	var narrow := screen_size.x < 1120
	return Rect2(screen_size.x-(146 if narrow else 292),68 if narrow else 16,134,44)

func place_route_button(button: Control) -> void:
	_route_button = button
	button.position = route_button_rect().position
	button.size = route_button_rect().size

func _plate(parent: Node, at: Vector2, extent: Vector2, art_key: String = "paper") -> Panel:
	var panel := ParchmentPlate.new()
	panel.art_key = art_key
	panel.position = at
	panel.size = extent
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	parent.add_child(panel)
	return panel

func _icon(parent: Node, icon_key: String, at: Vector2, extent: Vector2) -> Control:
	var icon := Control.new()
	icon.set_script(load("res://scripts/ui/generated_ui_icon.gd"))
	icon.position = at
	icon.size = extent
	parent.add_child(icon)
	icon.configure(icon_key)
	if icon_key == "gold" and FileAccess.file_exists("res://scripts/ui/storybook_art.gd"):
		var art: Script = load("res://scripts/ui/storybook_art.gd") as Script
		var painted: Texture2D = art.texture("coin")
		if painted != null: icon.generated_texture = painted
	return icon

func _line(parent: Node, text_value: String, at: Vector2, extent: Vector2, font_size: int, color: Color = HUD_INK) -> Label:
	var node := MineStyle.literal(parent,text_value,at,extent,font_size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.clip_text = true
	return node

func _compact_button(parent: Node, text_value: String, at: Vector2, extent: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.add_theme_color_override("font_color",HUD_INK)
	button.add_theme_color_override("font_hover_color",HUD_CYAN)
	button.add_theme_color_override("font_focus_color",HUD_CYAN)
	button.text = text_value
	button.position = at
	button.size = extent
	button.custom_minimum_size = Vector2(44,44)
	button.add_theme_font_size_override("font_size",16)
	for state in ["normal","hover","pressed","focus"]:
		var skin: StyleBox = MineStyle.box(Color("fff3d7"),HUD_AMBER if state != "normal" else MineStyle.COPPER)
		if state != "focus" and extent.x > 54 and FileAccess.file_exists("res://scripts/ui/storybook_art.gd"):
			var art: Script = load("res://scripts/ui/storybook_art.gd") as Script
			var texture: Texture2D = art.texture("skill_ribbon")
			if texture != null:
				var scale_factor := extent.y/texture.get_height()
				var bitmap: Image = texture.get_image()
				bitmap.resize(maxi(1,roundi(bitmap.get_width()*scale_factor)),maxi(1,roundi(extent.y)),Image.INTERPOLATE_LANCZOS)
				bitmap.generate_mipmaps()
				var painted := StyleBoxTexture.new()
				painted.texture = ImageTexture.create_from_image(bitmap)
				var margins: Array = [72,20,72,20]
				for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: painted.set_texture_margin(side,float(margins[side])*scale_factor)
				skin = painted
		skin.set_content_margin_all(3)
		if state == "focus" and skin is StyleBoxFlat: skin.bg_color = Color.TRANSPARENT
		button.add_theme_stylebox_override(state,skin)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _keycap(parent: Node, value: String, at: Vector2, extent: Vector2) -> Label:
	var panel := Panel.new()
	panel.position = at
	panel.size = extent
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := MineStyle.box(Color("453a47"),Color("b68d54"),1)
	skin.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel",skin)
	parent.add_child(panel)
	var label := _line(panel,value,Vector2(0,-2),extent,16,Color("fff1cf"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

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
	for action in ["move_left","move_right","move_up","move_down","click_move","attack","skill_q","skill_secondary","skill_f","skill_ultimate","dash","interact"]:
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if active_detail_slot == "inventory": inventory_requested.emit()
			elif not active_detail_slot.begins_with("buff:") and active_detail_slot not in ["quest","passive"]:
				skill_details_requested.emit(active_detail_slot)

func _process(delta: float) -> void:
	hover_grace = maxf(0,hover_grace-delta)
	var can_notify := interaction_enabled and not get_tree().paused
	if can_notify:
		toast_remaining = maxf(0,toast_remaining-delta)
		if toast_remaining <= 0 and not notifications.is_empty():
			var notification: Dictionary = notifications.pop_front()
			toast.text = str(notification.text)
			toast_remaining = float(notification.duration)
	if toast != null: toast.visible = toast_remaining > 0 and can_notify
	refresh()
	_update_pointer_guard(get_global_mouse_position())
	_update_tooltip()

func refresh() -> void:
	_bind_skill_input_feedback()
	_update_buffs()
	if Game.run == null or health_label == null: return
	if hero_definition.get("id","") != Game.run.hero_id:
		hero_definition = ContentRegistry.hero(Game.run.hero_id)
	var hero: Dictionary = hero_definition
	var stats: Dictionary = Game.run.stats
	var kind: String = hero.get("resource_type","rage")
	var max_resource: float = float(stats.get("resource_max",hero.get("resource_max",100)))
	hero_label.text = MineStyle.content_text(hero,"name")+"   Lv."+str(Game.run.level)
	hero_bust.configure(Game.run.hero_id)
	_update_growth()
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
	resource_label.size.x = 144 if Words.locale == "en" else 110
	resource_bar.position.x = 296 if Words.locale == "en" else 270
	resource_bar.size.x = 63 if Words.locale == "en" else 89
	resource_bar.max_value = max_resource
	resource_bar.value = Game.run.resource
	if resource_kind != kind:
		resource_kind = kind
		resource_icon.configure("resource_"+kind)
		resource_label.add_theme_color_override("font_color",HUD_INK)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("84989d")
		resource_bar.add_theme_stylebox_override("fill",fill)
	gold_label.text = Words.text("HUD_GOLD_COMPACT",{"gold":Game.run.gold})
	retained_label.text = Words.text("RETAINED",{"gold":Balance.death_keep(Game.run.gold)})
	_update_skills()
	_update_relics()
	_update_passive()
	var english := Words.locale == "en"
	inventory_button.text = "Backpack  [B]" if english else "背包  [B]"
	var attack_key := Bindings.secondary_label("attack",Game.profile.get("settings",{}).get("controls",{}),Words.locale)
	attack_label.tooltip_text = attack_key
	if english: attack_key = attack_key.replace("Left click","LMB").replace("Right click","RMB")
	attack_label.text = ("%s Attack\nAuto: %s" if english else "%s 普攻\n自动：%s") % [attack_key,("ON" if english else "开启") if Game.profile.get("settings",{}).get("auto_attack",false) else ("OFF" if english else "关闭")]
	if is_instance_valid(room):
		hint_label.text = room.interaction_hint()
		# The world now draws its short E tag on the actual focused object.
		hint_label.visible = not hint_label.text.is_empty() and room.get("interaction_overlay") == null
		_update_quest_and_route()

		_update_navigation()

func _update_quest_and_route() -> void:
	region_label.text = Words.text("ROOM_"+str(room.layout_id))
	var target: Dictionary = room.navigation_target()
	var title_key := str(target.get("title","NAV_EXIT"))
	var text_value := Words.text(title_key) if Words.catalog.has(title_key) else MineStyle.content_text(target,"name",title_key)
	var completed: int = room.activated_encounters.size() if room.objective_complete else maxi(0,room.activated_encounters.size()-1)
	var required: int = maxi(1,room.encounter_zones.size())
	var quality := "full"
	if is_instance_valid(room.get("objectives")):
		var progress: Dictionary = room.objectives.status()
		completed = int(progress.get("completed",0))
		quality = str(progress.get("quality","full"))
		required = maxi(1,int(progress.get("required",1)))
		if not room.objective_complete: text_value = QuestLocalization.action_for_status(progress,Words.locale == "en")
	var action_parts := PackedStringArray()
	var reward_parts := PackedStringArray()
	for part: String in text_value.split(" · "):
		var action_clause := part.contains("；") or part.contains(";")
		if not action_clause and (part.contains("金币") or part.contains("装备") or part.contains("防具") or part.contains("Gold") or part.contains("gold")):
			reward_parts.append(part)
		else:
			action_parts.append(part)
	quest_full_action = _localized_quest_action(" · ".join(action_parts))
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if Words.locale == "en" else TextServer.AUTOWRAP_ARBITRARY
	objective_label.text = quest_full_action
	objective_label.tooltip_text = text_value
	objective_bar.max_value = required
	objective_bar.value = required if room.objective_complete else completed
	quest_progress.text = ("Complete · Find the exit" if Words.locale == "en" else "已完成 · 前往出口") if room.objective_complete else (("Progress %d / %d" if Words.locale == "en" else "当前进度  %d / %d") % [completed,required])
	quest_reward.text = _localized_quest_action(" · ".join(reward_parts))
	if quest_reward.text.is_empty():
		quest_reward.text = _reward_caption(quality)
	quest_reward.tooltip_text = quest_reward.text
	# Short objectives fit as the two bullet lines in the selected reference;
	# long actions can use all three lines without cutting their instructions.
	var font := objective_label.get_theme_font("font")
	# Measure the same shaped lines that the Label actually paints. Font's
	# default word-boundary wrapping can omit the last CJK grapheme here.
	var line_height := font.get_height(17)+objective_label.get_theme_constant("line_spacing")
	var visible_lines := 2 if _compact_layout else 3
	objective_label.max_lines_visible = visible_lines
	objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var action_height := maxf(23,ceilf(mini(visible_lines,objective_label.get_line_count())*line_height)+2)
	objective_label.size.y = action_height
	var progress_token := "%d/%d" % [completed,required]
	quest_progress.visible = not objective_label.text.replace(" ","").contains(progress_token)
	quest_progress.position.y = objective_label.position.y+action_height+2
	quest_reward.position.y = quest_progress.position.y+(25 if quest_progress.visible else 0)
	quest_panel.size.y = maxf(110,quest_reward.position.y+26)
	var header_bottom := maxf(148,relic_row.position.y+relic_row.size.y+12)
	quest_panel.position.y = maxf(header_bottom,minf(screen_size.y*.51,equipment_actions.position.y-quest_panel.size.y-20))
	# At camera limits the player moves away from screen centre. Keep the paper
	# objective readable without hiding that character behind its default right dock.
	quest_panel.position.x = screen_size.x-quest_panel.size.x-12
	if is_instance_valid(room.player) and is_instance_valid(room.camera):
		var foot: Vector2 = room.player.get_global_transform_with_canvas().origin
		var zoom_value: Vector2 = room.camera.zoom
		var hero_extent := Vector2(106,preload("res://scripts/combat/presentation_metrics.gd").HERO_BODY_HEIGHT+20)*zoom_value
		var hero_rect := Rect2(foot-Vector2(hero_extent.x*.5,hero_extent.y-12),hero_extent).grow(14)
		if quest_panel.get_rect().intersects(hero_rect): quest_panel.position.x = 32
	quest_panel.set("reward_bullet_y",quest_reward.position.y+11)
	quest_button.size.y = quest_panel.size.y-36
	quest_panel.queue_redraw()
	var current := 1
	var count := maxi(1,room.encounter_zones.size())
	if room.get("expedition_context") != null and not room.expedition_context.is_empty():
		var context: Dictionary = room.expedition_context
		var definition: Dictionary = WorldCatalog.bosses().get(room.layout_id,{}) if context.get("role") == "boss" else WorldCatalog.room(room.layout_id)
		region_label.text = MineStyle.content_text(definition,"name",str(context.get("name",room.layout_id)))
		count = maxi(1,Game.run.expedition.get("route",{}).get("nodes",[]).size())
		current = int(context.get("node_index",0))+1
	else:
		current = clampi(room.activated_encounters.size(),1,count)
	expedition_label.text = ("Expedition  %d / %d" if Words.locale == "en" else "远征  %d / %d") % [current,count]
	expedition_beads.current = current
	expedition_beads.count = count
	expedition_beads.queue_redraw()

func _localized_quest_action(value: String) -> String:
	return QuestLocalization.translate_action(value,Words.locale == "en")

func _reward_caption(quality: String) -> String:
	var context: Dictionary = room.expedition_context if room.get("expedition_context") != null else {}
	var role := str(context.get("role",""))
	if role in ["entrance","supply"]:
		return "Prepare for the next stop" if Words.locale == "en" else "整备后继续探索"
	if context.is_empty():
		return "Completion XP: 30" if Words.locale == "en" else "完成奖励  +30 经验"
	var signature := str(room.layout_id)+":"+quality+":"+Game.run.hero_id+":"+Words.locale
	if signature != quest_reward_signature:
		quest_reward_signature = signature
		var rewards: Dictionary = RewardPolicy.build(str(room.layout_id),quality,Game.run.hero_id,int(room.get("layout_seed")),"hud-preview")
		if rewards.is_empty():
			cached_quest_reward = "Rewards at completion" if Words.locale == "en" else "完成目标后结算奖励"
		else:
			var gear_count: int = rewards.get("equipment",[]).size()
			cached_quest_reward = ("%d gold · %d gear" if Words.locale == "en" else "%d 金币 · %d 件装备") % [int(rewards.get("gold",0)),gear_count]
	return cached_quest_reward

func _key_for_slot(index: int) -> String:
	return Bindings.label_for(SKILL_ACTIONS[index],Game.profile.get("settings",{}).get("controls",{}),Words.locale)

func _update_growth() -> void:
	var xp := int(Game.profile.get("hero_xp",{}).get(Game.run.hero_id,0))
	if int(growth_info.get("xp",-1)) != xp or str(growth_info.get("hero_id","")) != Game.run.hero_id:
		growth_info = GrowthReadout.describe(Game.run.hero_id,xp)
	experience_label.text = ("MAX" if Words.locale == "en" else "满级") if growth_info.capped else "%d/%d XP" % [int(growth_info.progress),int(growth_info.span)]
	experience_bar.max_value = int(growth_info.span)
	experience_bar.value = experience_bar.max_value if growth_info.capped else int(growth_info.progress)
	if observed_run_id != Game.run.id:
		observed_run_id = Game.run.id
		observed_level = Game.run.level
		notifications.clear()
		toast_remaining = 0.0
	elif Game.run.level > observed_level:
		var unlocked := false
		for slot: String in SKILLS:
			var skill: Dictionary = hero_definition.skills[slot]
			var threshold := int(skill.unlock)
			if threshold <= observed_level or threshold > Game.run.level: continue
			var title := ("Lv.%d · Unlocked %s %s" if Words.locale == "en" else "Lv.%d · 已解锁 %s %s") % [threshold,GrowthReadout.key_for(slot),MineStyle.content_text(skill,"name")]
			_queue_notification(title+"\n"+GrowthReadout.unlock_hint(Game.run.hero_id,slot),5.0)
			unlocked = true
		if not unlocked:
			_queue_notification(("Reached Lv.%d" if Words.locale == "en" else "成长至 Lv.%d") % Game.run.level,3.0)
		observed_level = Game.run.level

func _queue_notification(message: String, duration: float = 4.0) -> void:
	# Level-up and relic receipts often arrive in the same frame. Keep both.
	if notifications.size() >= 8: notifications.pop_front()
	notifications.append({"text":message,"duration":duration})

func _update_passive() -> void:
	if not is_instance_valid(room) or not is_instance_valid(room.get("player")) or not room.player.has_method("class_status"):
		passive_panel.hide()
		return
	passive_snapshot = room.player.class_status()
	passive_panel.show()
	var english := Words.locale == "en"
	var current := int(passive_snapshot.get("current",0))
	var maximum := maxi(1,int(passive_snapshot.get("max",3)))
	var cooldown := float(passive_snapshot.get("cooldown",passive_snapshot.get("icd",0.0)))
	passive_title.text = str(passive_snapshot.get("name",""))
	passive_state.text = ("Stacks %d / %d" if english else "累积  %d / %d") % [current,maximum]
	if cooldown > 0:
		passive_state.text = ("%d/%d · %.1fs" if english else "%d/%d · 冷却%.1f秒") % [current,maximum,cooldown]
	elif bool(passive_snapshot.get("ready",false)):
		passive_state.text += " · Ready" if english else " · 已就绪"
	var triggers: Dictionary = {
		"CH01": ["普攻命中满3次，自动获得护盾。","Land 3 basic hits to gain a shield."],
		"CH02": ["同目标普攻2次，下一击触发弱点。","Hit one target twice; the next hit exploits its weakness."],
		"CH03": ["普攻与技能交替满3层，下次技能回蓝。","Alternate attacks and skills 3 times; the next skill restores mana."]
	}
	passive_hint.text = str(triggers.get(Game.run.hero_id,["被动自动生效。","This passive triggers automatically."])[1 if english else 0])
	passive_bar.max_value = maximum
	passive_bar.value = current
	var accent: Color = passive_snapshot.get("color",HUD_CYAN)
	# Resource accents can be pale gold or lime; use dark teal for paper text.
	passive_state.add_theme_color_override("font_color",HUD_CYAN if cooldown <= 0 else HUD_MUTED)
	passive_glyph.hero_id = Game.run.hero_id
	passive_glyph.accent = accent
	passive_glyph.queue_redraw()
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	passive_bar.add_theme_stylebox_override("fill",fill)
	class_label.text = ("Passive %d/%d · Automatic" if english else "被动 %d/%d · 自动触发") % [current,maximum]
	class_label.tooltip_text = str(passive_snapshot.get("hint",""))
	class_bar.max_value = maximum
	class_bar.value = current

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
		if is_instance_valid(room.get("player")) and room.player.status != null:
			for guard_source: String in room.player.status.guards:
				if not guard_source.begins_with("supply:"): continue
				var guard: Dictionary = room.player.status.guards[guard_source]
				if float(guard.get("amount",0)) <= 0 or float(guard.get("remaining",0)) <= 0: continue
				var prepared: bool = CombatStatus.is_prepared_supply_guard(guard_source)
				active_buffs["supply_guard"] = {"effect":"supply_guard","name":"预备护盾","name_en":"Reserve shield","description":"首次吸收伤害才开始计时；耗尽或离开本房间后失效。","description_en":"The timer starts on the first absorbed hit. Ends when depleted or leaving this room.","remaining":guard.remaining,"duration":4.0,"amount":guard.amount,"prepared":prepared,"source":"supply","color":HUD_CYAN}
			for effect: String in room.player.status.states:
				var state: Dictionary = room.player.status.states[effect]
				if not COMBAT_STATUS_LABELS.has(effect) or float(state.get("remaining",0.0)) <= 0.0: continue
				var beneficial := effect in ["damage_reduction","invulnerable"]
				active_buffs[effect] = {"effect":effect,"name":COMBAT_STATUS_LABELS[effect],"name_en":effect.replace("_"," ").capitalize(),"description":COMBAT_STATUS_NOTES[effect],"remaining":state.remaining,"duration":state.remaining,"source":"combat","color":Color("92dfda") if beneficial else Color("eb9278")}
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
		chip.position = Vector2((ordinal%6)*48,floori(ordinal/6.0)*48)
		chip.update_state(active_buffs[effect])
		ordinal += 1
	buff_row.size = Vector2(maxi(0,mini(6,ordinal)*48-4),maxi(0,ceili(ordinal/6.0)*48-4))
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
	if bool(state.get("prepared",false)):
		summary = "Ready · 4s after first absorbed hit" if english else "待机 · 首次承伤后持续 4 秒"
	if effect in ["guard","supply_guard"] and state.has("amount"):
		summary += ("\nShield remaining: %d" if english else "\n当前护盾：%d") % ceili(float(state.amount))
	var note := "Same type refreshes its duration; does not stack. Ends when leaving the room." if english else "同类再次获得只刷新持续时间，不叠加。离开房间时失效。"
	if str(state.get("source","")) == "combat":
		note = "Live combat status. The timer follows the actual effect." if english else "实战状态计时，与角色实际效果同步。"
	elif str(state.get("source","")) == "supply":
		note = "Purchased protection for this room. Waiting does not consume it; it cannot be carried into the next room." if english else "本房购买防护：待机不消耗时间，不能带入下一房间。"
	return {"name":MineStyle.content_text(state,"name"),"description":MineStyle.content_text(state,"description"),"summary":summary,"remaining":remaining,"duration":duration,"state":state.duplicate(true),"note":note}

## Temporary buff paint is measured independently of the standing HUD footprint.
func active_buff_coverage_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for chip: BuffChip in buff_chips.values():
		if chip.is_visible_in_tree(): result.append(Rect2(chip.global_position+BuffChip.PAINTED_RECT.position,BuffChip.PAINTED_RECT.size))
	return result

func _update_relics() -> void:
	var relic_ids := ",".join(Game.run.relics)
	var biome: String = load("res://scripts/combat/race_relics.gd").biome_id(room)
	var signature := biome+":"+relic_ids
	if signature == previous_relics: return
	for child in relic_row.get_children(): child.queue_free()
	for i in range(Game.run.relics.size()):
		var id: String = Game.run.relics[i]
		var chip := _compact_button(relic_row,"",Vector2((i%4)*52,floori(i/4.0)*52),Vector2(44,44),func(): relic_details_requested.emit())
		chip.name = "Relic_"+id
		_bind_detail(chip,"relic:"+id)
		var art := MineArt.relic(chip,id,Vector2(4,4),Vector2(36,36))
		var info := _relic_info(id)
		if info.get("texture") is Texture2D: art.texture = info.texture
	if has_drawn_state and not Game.run.relics.is_empty() and previous_relics.get_slice(":",1) != relic_ids:
		_queue_notification(Words.text("RELIC_ACQUIRED",{"name":str(_relic_info(str(Game.run.relics[-1])).get("name",""))}))
	previous_relics = signature
	has_drawn_state = true
	relic_row.size = Vector2(maxi(0,mini(4,Game.run.relics.size())*52-8),maxi(0,ceili(Game.run.relics.size()/4.0)*52-8))
	relic_row.position.x = screen_size.x-relic_row.size.x-12

func _relic_info(id: String) -> Dictionary:
	if ResourceLoader.exists("res://scripts/combat/class_relics.gd"):
		var ledger_id: String = {"split":"RL01","ember":"RL02","arc":"RL03"}.get(id,id)
		var rank := int(Game.expedition_snapshot().get("relic_levels",{}).get(ledger_id,1))
		var biome: String = load("res://scripts/combat/race_relics.gd").biome_id(room)
		return load("res://scripts/combat/class_relics.gd").display(Game.run.hero_id,id,rank,biome)
	var key := "RELIC_"+id.to_upper()
	return {"name":Words.text(key+"_NAME"),"description":Words.text(key+"_DESC")}

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
	var casting := false
	var queued := false
	var queue_position := 0
	var busy := false
	var cast_progress := 0.0
	if is_instance_valid(room) and is_instance_valid(room.player):
		var actor: Node = room.player
		var active: Dictionary = actor.abilities.active
		casting = not active.is_empty() and str(active.spec.slot) == slot
		queue_position = actor.queued_action_position(slot)
		queued = queue_position > 0
		busy = slot != "dash" and ((not active.is_empty() and not actor.abilities.recovery_chain_ready()) or actor._basic_chain_remaining > 0.0 or actor.dash_remaining > 0.0 or (actor.attack_remaining > 0.0 and not actor.attack_resolved))
		if casting:
			cast_progress = clampf(float(active.elapsed) / maxf(.001, float(active.spec.duration)), 0.0, 1.0)
			state = "Casting" if Words.locale == "en" else "施放中"
		elif queued:
			state = ("Combo queued · Step %d" if Words.locale == "en" else "连招待施放 · 第%d步") % queue_position
		elif busy and not locked and cooldown <= 0 and not insufficient:
			state = "Action in progress" if Words.locale == "en" else "动作中"
	var summary := Words.text("HUD_FINAL_COST",{"cost":snappedf(cost,0.1),"resource":MineStyle.content_text(hero_definition,"resource_name"),"cooldown":snappedf(float(skill.get("cooldown",0)),0.1)})
	return {"name":MineStyle.content_text(skill,"name"),"description":MineStyle.content_text(skill,"description",Words.text("HUD_DASH_DESCRIPTION")),"summary":summary,"state":state,"locked":locked,"unlock":int(skill.get("unlock",1)),"cooldown":cooldown,"duration":float(skill.get("cooldown",0)),"insufficient":insufficient,"casting":casting,"queued":queued,"queue_position":queue_position,"busy":busy,"cast_progress":cast_progress,"accent":MineStyle.resource_color(resource_kind),"ready":not locked and cooldown <= 0 and not insufficient and not busy and not queued}

func _bind_skill_input_feedback() -> void:
	var next_actor: Node = room.player if is_instance_valid(room) and is_instance_valid(room.get("player")) else null
	if next_actor == _skill_feedback_actor: return
	if is_instance_valid(_skill_feedback_actor) and _skill_feedback_actor.is_connected("skill_input_feedback", _on_skill_input_feedback):
		_skill_feedback_actor.disconnect("skill_input_feedback", _on_skill_input_feedback)
	_skill_feedback_actor = next_actor
	if is_instance_valid(next_actor):
		next_actor.connect("skill_input_feedback", _on_skill_input_feedback)

func _on_skill_input_feedback(slot: String, reason: String, _details: Dictionary) -> void:
	var index: int = SKILLS.find(slot)
	if index >= 0 and index < skill_slots.size() and interaction_enabled:
		skill_slots[index].notify_input(reason)

func _update_skills() -> void:
	for i in range(skill_slots.size()):
		var slot: String = SKILLS[i] if i < 4 else "dash"
		skill_slots[i].key = _key_for_slot(i)
		var info := skill_info(slot)
		info["description"] = str(info.get("description",""))
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
	elif active_detail_slot == "quest":
		tooltip_title.text = region_label.text
		body = quest_full_action+"\n\n"+quest_progress.text+"\n"+quest_reward.text
		if not room.expedition_context.is_empty():
			body += "\n"+("Extract successfully to retain equipment." if Words.locale == "en" else "装备需成功撤离带回。")
	elif active_detail_slot == "progression":
		tooltip_title.text = ("Hero growth · Lv.%d" if Words.locale == "en" else "角色成长 · Lv.%d") % Game.run.level
		body = experience_label.text+"\n"+GrowthReadout.next_goal(Game.run.hero_id,int(growth_info.get("xp",0)))
		body += "\n"+class_label.text
		body += "\n\n"+("Room XP is saved on completion. Defeat removes unsettled room XP and preserves your earned levels. Click to inspect your character." if Words.locale == "en" else "完成房间后结算经验。死亡损失本房未结算经验，保留已有等级。点击查看角色属性。")
		var pending := 30 if Game.run.staged_tutorial else 0
		for value: int in Game.run.staged_xp.values(): pending += value
		if pending > 0:
			body += ("\nPending this room: %d XP" if Words.locale == "en" else "\n本房待结算：%d 经验") % pending
	elif active_detail_slot == "passive":
		tooltip_title.text = passive_title.text
		body = str(passive_snapshot.get("description",""))+"\n\n"+passive_state.text+"\n"+str(passive_snapshot.get("hint",""))
	elif active_detail_slot == "inventory":
		tooltip_title.text = "Backpack & character" if Words.locale == "en" else "背包与角色属性"
		body = "Press B or click to change equipment and inspect your live character stats. The game pauses while the backpack is open." if Words.locale == "en" else "按 B 或点击打开背包，查看与更换装备、比较加成和角色实时属性。背包打开时游戏暂停。"
	elif active_detail_slot.begins_with("relic:"):
		var info := _relic_info(active_detail_slot.trim_prefix("relic:"))
		tooltip_title.text = str(info.get("name",""))
		body = str(info.get("description",""))
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
		body = str(info.description)+"\n\n"+str(info.summary)+"\n"+str(info.state)+"\n\n"+Words.text("HUD_DETAIL_HINT")
	tooltip_body.text = body
	tooltip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if Words.locale == "en" else TextServer.AUTOWRAP_ARBITRARY
	var detail_line_height := tooltip_body.get_theme_font("font").get_height(16)+tooltip_body.get_theme_constant("line_spacing")
	tooltip_panel.size.y = maxf(164,ceilf(tooltip_body.get_line_count()*detail_line_height)+64)
	tooltip_panel.size.y = minf(minf(420,screen_size.y-32),tooltip_panel.size.y)
	tooltip_body.size.y = tooltip_panel.size.y-54
	tooltip_body.clip_text = true
	tooltip_body.max_lines_visible = maxi(1,floori(tooltip_body.size.y/detail_line_height))
	tooltip_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if target != tooltip_panel:
		var bounds := target.get_global_rect()
		if active_detail_slot == "quest":
			# A long action can move its note upwards. Its detail stays beside
			# the note so hovering never covers the source's click target.
			tooltip_panel.position = Vector2(clampf(bounds.position.x-tooltip_panel.size.x,16,screen_size.x-tooltip_panel.size.x-16),clampf(bounds.position.y,16,screen_size.y-tooltip_panel.size.y-16))
		else:
			var tooltip_y := bounds.position.y-tooltip_panel.size.y
			# Touch the source's edge; slow pointers and trackpads need no timed jump.
			if tooltip_y < 140: tooltip_y = bounds.end.y
			tooltip_panel.position = Vector2(clampf(bounds.get_center().x-tooltip_panel.size.x*.5,16,screen_size.x-tooltip_panel.size.x-16),clampf(tooltip_y,16,screen_size.y-tooltip_panel.size.y-16))
	tooltip_panel.show()

## Actual screen-space boxes, used by QA instead of the full-screen root rect.
func coverage_rects() -> Array[Rect2]:
	var result: Array[Rect2] = [status_panel.get_global_rect().merge(hero_bust.get_global_rect()),location_panel.get_global_rect(),quest_panel.get_global_rect(),gold_label.get_global_rect(),skill_dock.get_global_rect(),equipment_actions.get_global_rect()]
	if is_instance_valid(passive_panel) and passive_panel.visible: result.append(passive_panel.get_global_rect())
	if Game.run != null and not Game.run.relics.is_empty(): result.append(relic_row.get_global_rect())
	if is_instance_valid(_route_button): result.append(_route_button.get_global_rect())
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
	var battle_rect := Rect2(32,160,screen_size.x-64,maxf(80,skill_dock.position.y-178))
	navigation.visible = not battle_rect.has_point(target_ui) and distance > 90.0
	if not navigation.visible: return
	var center := screen_size*.5
	var direction := target_ui-center
	if direction.length_squared() < 0.01: return
	var unit := direction.normalized()
	var factor := minf(maxf(80,screen_size.x*.5-navigation.size.x*.5-24)/maxf(absf(unit.x),0.001),maxf(40,battle_rect.size.y*.5-24)/maxf(absf(unit.y),0.001))
	var edge := center+unit*factor
	var bottom := minf(skill_dock.position.y,minf(passive_panel.position.y,equipment_actions.position.y))-navigation.size.y-12
	navigation.position = Vector2(clampf(edge.x-navigation.size.x*.5,20,screen_size.x-navigation.size.x-20),clampf(edge.y-navigation.size.y*.5,166,maxf(166,bottom)))
	# Move the pointer beside a standing note rather than over its text.
	if navigation.get_rect().intersects(quest_panel.get_rect().grow(6)):
		var above := quest_panel.position.y-navigation.size.y-8
		var below := quest_panel.get_rect().end.y+8
		if below <= bottom: navigation.position.y = below
		elif above >= 166: navigation.position.y = above
		else: navigation.position.x = maxf(20,quest_panel.position.x-navigation.size.x-12)
	if navigation.get_rect().intersects(buff_row.get_rect()) and buff_row.visible:
		navigation.position.x = buff_row.get_rect().end.x+8
	var title_key := str(target.get("title","NAV_EXIT"))
	var title := Words.text(title_key) if Words.catalog.has(title_key) else MineStyle.content_text(target,"name",title_key)
	navigation.update_target(unit,title,roundi(distance),"exit" if target.get("kind","") == "extract" else "route")
