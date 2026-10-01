extends Control
## A temporary ribbon reading authoritative combat state; it never advances buffs.
const PAINTED_RECT := Rect2(0, 0, 236, 102)
var state: Dictionary = {}
var pulse: float = 0.0
var last_count: int = 0

func _init() -> void:
	name = "HitChainReadout"
	size = PAINTED_RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hide()

func update_state(value: Dictionary) -> void:
	var count: int = int(value.get("count", 0))
	if count > last_count: pulse = .22
	last_count = count
	state = value.duplicate()
	visible = count > 0
	queue_redraw()

func _process(delta: float) -> void:
	if get_tree().paused: return
	if pulse > 0.0:
		pulse = maxf(0.0, pulse - delta)
		queue_redraw()

func _text(value: String, at: Vector2, font_size: int, tint: Color, outline: int = 0) -> void:
	var font: Font = get_theme_default_font()
	if outline > 0: draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color("492d47"))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)

func _draw() -> void:
	if state.is_empty() or int(state.count) <= 0: return
	var hero: String = str(state.get("hero", "CH01"))
	var accent: Color = Color("f78629") if hero == "CH01" else Color("edb534") if hero == "CH02" else Color("ad66ed")
	var ink := Color("492d47")
	var tier: int = int(state.tier)
	var english: bool = Words.locale == "en"
	var ribbon := PackedVector2Array([Vector2(4,7),Vector2(224,2),Vector2(231,19),Vector2(224,79),Vector2(230,98),Vector2(8,96),Vector2(12,81),Vector2(2,61)])
	draw_colored_polygon(ribbon, Color("fff0cc"))
	ribbon.append(ribbon[0])
	draw_polyline(ribbon, Color("b98a53"), 2.0, true)
	draw_line(Vector2(12,29),Vector2(220,25),Color(accent,.45),2.0,true)
	_text("HIT CHAIN" if english else "连击增伤", Vector2(14,23), 16, ink)
	_text(("MAX" if english else "满层") if tier == 5 else ("NEXT x%d" if english else "下一档 x%d") % int(state.next), Vector2(136,22), 13, Color("80614f"))
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var font_size: int = 44 + (roundi(sin(pulse/.22*PI)*4.0) if not reduced else 0)
	_text("x%d" % int(state.count), Vector2(14,69), font_size, accent.lightened(.10), 5)
	_text("+%.1f%%" % (float(state.bonus)*100.0), Vector2(137,49), 22, ink)
	var captions: Array = ["蓄势","炽热","狂热","超燃","无双","极限连击"] if not english else ["BUILDING","HOT","BLAZING","RAMPAGE","UNSTOPPABLE","LEGENDARY"]
	_text(str(captions[tier]), Vector2(137,68), 12 if english else 16, ink)
	for index in 5:
		var x: float = 18 + index*41
		draw_line(Vector2(x,78),Vector2(x+31,78), accent if index < tier else Color("d4bf9d"), 4.0, true)
	draw_line(Vector2(18,89),Vector2(219,89), Color("dbcaab"), 5.0, true)
	var ratio: float = clampf(float(state.remaining)/maxf(.01,float(state.duration)),0.0,1.0)
	if ratio > 0.0: draw_line(Vector2(18,89),Vector2(18+201*ratio,89), Color("32bcca") if hero == "CH03" else accent, 5.0, true)
