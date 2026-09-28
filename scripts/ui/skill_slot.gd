extends Button
## Compact instrument key: the whole cell remains a keyboard and pointer target.
## Combat input is not emitted here; the HUD opens its paused detail view on press.

const CELL_SIZE := Vector2(52,64)
const ICON_RECT := Rect2(4,2,44,44)
const INK := Color("f1eadc")
const COPPER := Color("826345")
const MUTED := Color("84929a")
const WARNING := Color("e46b69")

const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
var hero_id := "CH01"
var slot := "q"
var key := "Q"
var generated_texture: Texture2D
var state: Dictionary = {}

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
	add_theme_font_size_override("font_size",16)

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
	var path := "res://assets/generated/skills/"+hero_id+"_"+slot+"_v1.png"
	generated_texture = TextureSampler.sampled(path)
	queue_redraw()

func update_state(next_state: Dictionary) -> void:
	state = next_state.duplicate()
	tooltip_text = str(state.get("details",""))
	queue_redraw()

func _draw() -> void:
	var accent: Color = state.get("accent",Color("e6aa4a"))
	var locked := bool(state.get("locked",false))
	var insufficient := bool(state.get("insufficient",false))
	var remaining := maxf(0.0,float(state.get("cooldown",0.0)))
	var duration := maxf(0.001,float(state.get("duration",1.0)))
	var active := is_hovered() or has_focus()
	var border := MUTED if locked else (WARNING if insufficient else COPPER)
	if active:
		border = accent
	var cell := Rect2(Vector2(0.5,0.5),size-Vector2.ONE)
	draw_rect(cell,Color(0.055,0.085,0.11,0.78 if active else 0.57))
	draw_rect(cell,border,false,2.0 if active else 1.0)
	draw_line(Vector2(7,1),Vector2(size.x-7,1),accent,2.0,true)
	if generated_texture != null:
		var source_size := generated_texture.get_size()
		var image_scale := minf(ICON_RECT.size.x/source_size.x,ICON_RECT.size.y/source_size.y)
		var extent := source_size*image_scale
		draw_texture_rect(generated_texture,Rect2(ICON_RECT.position+(ICON_RECT.size-extent)*0.5,extent),false,Color(1,1,1,0.4 if locked else 1.0))
	else:
		_draw_glyph(accent if not locked else MUTED)
	if remaining > 0.0 and not locked:
		var ratio := clampf(remaining/duration,0.0,1.0)
		draw_rect(Rect2(2,2,size.x-4,40*ratio),Color(0.02,0.035,0.05,0.78))
		draw_rect(Rect2(size.x-4,42-40*ratio,2,40*ratio),accent)
		_center_text(str(ceili(remaining)) if remaining >= 1.0 else "%.1f" % remaining,31,18,INK)
	elif locked:
		draw_rect(Rect2(2,2,size.x-4,40),Color(0.02,0.035,0.05,0.62))
		_draw_lock(Vector2(size.x*0.5,12),MUTED)
		_center_text("L"+str(int(state.get("unlock",1))),39,16,INK)
	elif insufficient:
		# A crossed resource tick is visible without relying on red alone.
		draw_line(Vector2(36,32),Vector2(44,40),WARNING,2.0,true)
		draw_line(Vector2(44,32),Vector2(36,40),WARNING,2.0,true)
	draw_line(Vector2(6,46),Vector2(size.x-6,46),Color(border,0.55),1.0)
	_center_text(key,size.y-3,16,INK if not locked else MUTED)

func _center_text(value: String, baseline: float, font_size: int, color: Color) -> void:
	var font := get_theme_font("font","Button")
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var at := Vector2((size.x-width)*0.5,baseline)
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color("0d131a"))
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
	var center := Vector2(size.x*0.5,23)
	if slot == "dash":
		for index in range(2):
			var x := center.x-12+index*13
			_stroke([Vector2(x,12),Vector2(x+9,23),Vector2(x,34)],color,3.0)
		return
	var slot_index := ["q","secondary","f","ultimate"].find(slot)
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
