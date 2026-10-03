extends Button
## Compact instrument key: the whole cell remains a keyboard and pointer target.
## Combat input is not emitted here; the HUD opens its paused detail view on press.

const CELL_SIZE := Vector2(88,110)
const ICON_RECT := Rect2(16,8,56,56)
const INK := Color("34382f")
const COPPER := Color("b18b4c")
const MUTED := Color("817967")
const WARNING := Color("ae463f")

const TextureSampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
var hero_id := "CH01"
var slot := "q"
var skill_id := ""
var icon_id := ""
var key := "Q"
var generated_texture: Texture2D
var bezel_texture: Texture2D
var lock_texture: Texture2D
var painted_icons := false
var state: Dictionary = {}
var unlock_flash := 0.0
var input_flash := 0.0
var input_reason := ""

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = CELL_SIZE
	size = CELL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for style_name in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(style_name,StyleBoxEmpty.new())
	add_theme_font_size_override("font_size",18)

func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	queue_redraw()

func configure(next_hero_id: String, next_slot: String, next_key: String) -> void:
	hero_id = next_hero_id
	slot = next_slot
	key = next_key
	name = "Skill_"+slot
	var path := "asset://skills/"+hero_id+"_"+slot+"_v1.png"
	generated_texture = TextureSampler.sampled(path)
	if FileAccess.file_exists(AssetCatalog.resolve("res://scripts/infrastructure/assets/storybook_art.gd")):
		var art: Script = load(AssetCatalog.resolve("res://scripts/infrastructure/assets/storybook_art.gd")) as Script
		bezel_texture = art.texture("gold_bezel")
		lock_texture = art.texture("lock")
		var ability: Texture2D = art.texture("dodge" if slot == "dash" else "ability_"+hero_id+"_"+slot)
		if ability != null:
			generated_texture = ability
			painted_icons = true
	queue_redraw()

func update_state(next_state: Dictionary) -> void:
	if bool(state.get("locked",false)) and not bool(next_state.get("locked",false)):
		unlock_flash = 3.5
	state = next_state.duplicate(true)
	_update_identity()
	tooltip_text = str(state.get("details",""))
	queue_redraw()

func _update_identity() -> void:
	var next_skill_id := str(state.get("skill_id",""))
	var next_icon_id := str(state.get("icon_id",state.get("icon","")))
	if next_icon_id.is_empty() and not next_skill_id.is_empty():
		next_icon_id = "asset://skill."+next_skill_id.to_lower()
	elif not next_icon_id.is_empty() and not next_icon_id.begins_with("asset://") and not next_icon_id.begins_with("res://"):
		next_icon_id = "asset://"+next_icon_id
	if next_skill_id == skill_id and next_icon_id == icon_id: return
	skill_id = next_skill_id
	icon_id = next_icon_id
	if not skill_id.is_empty(): hero_id = skill_id.get_slice("_",0)
	# Identity changes load once. Combat redraws use the cached texture.
	if not icon_id.is_empty():
		generated_texture = TextureSampler.sampled(icon_id) if FileAccess.file_exists(AssetCatalog.resolve(icon_id)) else null

func _process(delta: float) -> void:
	if get_tree().paused: return
	if unlock_flash <= 0.0 and input_flash <= 0.0: return
	unlock_flash = maxf(0.0,unlock_flash-delta)
	input_flash = maxf(0.0,input_flash-delta)
	queue_redraw()

func notify_input(reason: String) -> void:
	input_reason = reason
	input_flash = 0.20 if reason == "accepted" else 0.30 if reason == "queued" else 0.45
	queue_redraw()

func _draw() -> void:
	var accent: Color = state.get("accent",Color("ac6d2f"))
	var locked := bool(state.get("locked",false))
	var insufficient := bool(state.get("insufficient",false))
	var remaining := maxf(0.0,float(state.get("cooldown",0.0)))
	var duration := maxf(0.001,float(state.get("duration",1.0)))
	var active := is_hovered() or has_focus()
	var center := Vector2(size.x*.5,36)
	var border := Color("8b826f") if locked else COPPER
	var frame := GameStyle.box(Color("e7e7de") if locked else Color("faf8f1"),accent if active else Color("bfa97f"),2 if active else 1)
	frame.set_corner_radius_all(10)
	draw_style_box(frame,Rect2(center-Vector2(35,35),Vector2(70,70)))
	if input_flash > 0.0:
		var tint: Color = accent if input_reason in ["accepted", "queued"] else WARNING
		draw_arc(center,35,0,TAU,48,Color(tint,minf(1,input_flash*5)),3,true)
	if unlock_flash > 0.0:
		draw_arc(center,35,0,TAU,48,Color("d3a349"),3,true)
	if generated_texture != null:
		var source_size := generated_texture.get_size()
		var image_scale := minf(ICON_RECT.size.x/source_size.x,ICON_RECT.size.y/source_size.y)
		var extent := source_size*image_scale
		draw_texture_rect(generated_texture,Rect2(Vector2(center.x-ICON_RECT.size.x*.5,ICON_RECT.position.y)+(ICON_RECT.size-extent)*.5,extent),false,Color(1,1,1,.18 if locked else 1))
	else:
		draw_set_transform(Vector2(18,13))
		_draw_glyph(Color("f6d19b") if not locked else Color("b0a4ac"))
		draw_set_transform(Vector2.ZERO)
	# The live rounded frame replaces the low-resolution circular bezel.
	var overlay := Color(.16,.12,.19,.77)
	if bool(state.get("casting",false)):
		draw_circle(center,28,overlay)
		_center_text("CAST" if Words.locale == "en" else "施放中",42,18,Color("fff1cf"))
		draw_arc(center,29,-PI*.5,-PI*.5+TAU*float(state.get("cast_progress",0)),40,accent,3,true)
	elif bool(state.get("queued",false)):
		draw_circle(center,28,overlay)
		_center_text(("NEXT %d" if Words.locale == "en" else "接招%d") % maxi(1,int(state.get("queue_position",1))),42,18,Color("b8eadb"))
	elif remaining > 0.0 and not locked:
		draw_circle(center,28,overlay)
		var ratio := clampf(remaining/duration,0,1)
		draw_arc(center,29,-PI*.5,-PI*.5+TAU*(1-ratio),40,accent,3,true)
		_center_text(str(ceili(remaining)) if remaining >= 1 else "%.1f" % remaining,44,24,Color("fff1cf"))
	elif locked:
		if lock_texture != null: draw_texture_rect(lock_texture,Rect2(center-Vector2(12,17),Vector2(24,28)),false,Color(.70,.77,.80,1))
		else: _draw_lock(Vector2(size.x*.5,22),Color("a6b0b8"))
		_center_text("Locked" if Words.locale == "en" else "未学会",54,18,Color("e6dac8"))
	elif insufficient:
		draw_circle(center,28,Color(.34,.12,.19,.32))
		_center_text("LOW" if Words.locale == "en" else "不足",62,18,Color("ffdbc0"))
	var title := str(state.get("name",""))
	if slot == "dash": title = "Dodge" if Words.locale == "en" else "闪避"
	var font := get_theme_font("font","Button")
	if font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x > size.x-4:
		# Full localized names are always in the focus/hover detail. Keep the
		# standing label readable at18px instead of shrinking it into a caption.
		while title.length() > 1 and font.get_string_size(title+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,18).x > size.x-4:
			title = title.left(title.length()-1)
		title += "…"
	_center_text(title,84,18,MUTED if locked else INK)
	var key_text := key
	var compact_keys := {"鼠标左键":"左键","鼠标右键":"右键","鼠标中键":"中键","鼠标侧键 1":"侧键1","鼠标侧键 2":"侧键2","Left click":"LMB","Right click":"RMB","Middle click":"MMB","Mouse side 1":"M4","Mouse side 2":"M5"}
	key_text = str(compact_keys.get(key_text,key_text))
	if font.get_string_size(key_text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x > size.x-16:
		while key_text.length() > 1 and font.get_string_size(key_text+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,18).x > size.x-16:
			key_text = key_text.left(key_text.length()-1)
		key_text += "…"
	var key_width := minf(size.x-4,maxf(26,font.get_string_size(key_text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+12))
	var key_rect := Rect2((size.x-key_width)*.5,89,key_width,21)
	draw_style_box(GameStyle.box(Color("51334d"),Color("b68d54"),1),key_rect)
	_center_text(key_text,106,18,Color("fff1cf"))

func _center_text(value: String, baseline: float, font_size: int, color: Color) -> void:
	var font := get_theme_font("font","Button")
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var at := Vector2((size.x-width)*0.5,baseline)
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,1,Color(1,.94,.80,.22))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _stroke(points: Array, color: Color, width: float = 2.0) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	draw_polyline(packed,color,width,true)

func _draw_lock(at: Vector2, color: Color) -> void:
	draw_arc(at+Vector2(0,0),4,PI,TAU,12,color,2.0,true)
	draw_rect(Rect2(at+Vector2(-6,0),Vector2(12,9)),color,false,2.0)
	draw_line(at+Vector2(0,3),at+Vector2(0,6),color,1.5,true)

func _draw_glyph(color: Color) -> void:
	# Distinct silhouettes drafted for the game's instrument language. These are
	# used only while a skill's generated transparent miniature is unavailable.
	var center := Vector2(26,23)
	if slot == "dash":
		for index in range(2):
			var x := center.x-12+index*13
			_stroke([Vector2(x,12),Vector2(x+9,23),Vector2(x,34)],color,3.0)
		return
	var slot_index := int(skill_id.get_slice("_SK",1))-1 if not skill_id.is_empty() else ["q","secondary","f","ultimate"].find(slot)
	match hero_id:
		"CH02":
			match slot_index:
				0:
					_stroke([Vector2(12,33),Vector2(35,11),Vector2(41,17)],color,4.0)
					_stroke([Vector2(30,11),Vector2(38,11),Vector2(38,19)],INK,2.0)
				1:
					draw_arc(center,13,0,TAU,24,color,2.0,true)
					_stroke([center+Vector2(-18,0),center+Vector2(18,0)],INK)
					_stroke([center+Vector2(0,-18),center+Vector2(0,18)],INK)
				2:
					_stroke([Vector2(10,32),Vector2(18,18),Vector2(26,32),Vector2(34,18),Vector2(42,32)],color,3.0)
					_stroke([Vector2(12,34),Vector2(40,34)],INK)
				_:
					for index in range(3):
						var x := 15+index*11
						_stroke([Vector2(x-4,15),Vector2(x,10),Vector2(x+4,15)],color,2.5)
						_stroke([Vector2(x,11),Vector2(x,35)],INK,2.0)
		"CH03":
			match slot_index:
				0:
					_stroke([Vector2(32,8),Vector2(19,23),Vector2(29,23),Vector2(21,38)],color,3.5)
				1:
					for index in range(3):
						draw_arc(center,5+index*5,0.3,5.9,28,color,2.0,true)
				2:
					_stroke([Vector2(26,7),Vector2(40,16),Vector2(36,31),Vector2(26,39),Vector2(16,31),Vector2(12,16),Vector2(26,7)],color,2.5)
					_stroke([Vector2(26,14),Vector2(26,31)],INK,2.0)
				_:
					for index in range(6):
						var axis := Vector2.from_angle(index*TAU/6)
						draw_line(center+axis*6,center+axis*17,color,2.5,true)
					draw_circle(center,5,INK)
		_:
			match slot_index:
				0:
					_stroke([Vector2(16,36),Vector2(34,13)],INK,4.0)
					_stroke([Vector2(24,12),Vector2(38,23)],color,8.0)
				1:
					_stroke([Vector2(13,12),Vector2(39,12),Vector2(37,27),Vector2(26,38),Vector2(15,27),Vector2(13,12)],color,2.5)
					_stroke([Vector2(26,17),Vector2(26,29)],INK,3.0)
				2:
					_stroke([Vector2(11,32),Vector2(19,20),Vector2(25,31),Vector2(33,12),Vector2(42,32)],color,3.0)
					_stroke([Vector2(12,37),Vector2(40,37)],INK,2.0)
				_:
					_stroke([Vector2(12,26),Vector2(17,12),Vector2(26,18),Vector2(35,12),Vector2(40,26),Vector2(32,37),Vector2(20,37),Vector2(12,26)],color,2.5)
					draw_circle(center,5,INK)
