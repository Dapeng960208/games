class_name DamageNumbers
extends RefCounted
## Presentation only. Callers supply consumed HP, absorbed shield or actual
## restoration, after gameplay has resolved. This never rolls a critical hit.

const INK := Color("452f53")
const STYLES := {
	"kinetic": {"color":Color("fff4d7"), "mark":""},
	"fire": {"color":Color("ff9768"), "mark":"火"},
	"electric": {"color":Color("ffdf64"), "mark":"雷"},
	"cold": {"color":Color("8ce8ff"), "mark":"冰"},
	"corrosion": {"color":Color("b2ee83"), "mark":"蚀"},
	"true": {"color":Color("f3b3ff"), "mark":"真"},
	"magic": {"color":Color("c7b4ff"), "mark":"魔"},
}

static func damage_kind(source: String, context: Dictionary = {}) -> String:
	var supplied: String = str(context.get("damage_kind", ""))
	# A debuff applied by a physical hit does not change that hit's element.
	# Only the actual DOT/status packet uses the status as its own damage kind.
	if supplied.is_empty() and (bool(context.get("dot", false)) or source in ["burn", "shock", "chill", "corrosion", "bleed"]):
		supplied = str(context.get("status", source))
	if supplied.is_empty(): supplied = str(context.get("damage_type", source))
	match supplied:
		"fire", "thermal", "burn": return "fire"
		"electric", "electricity", "shock", "lightning": return "electric"
		"cold", "ice", "chill": return "cold"
		"corrosion", "toxic", "acid", "poison": return "corrosion"
		"true", "true_damage", "equipment_true": return "true"
		"magic", "spell", "arcane": return "magic"
		_: return "kinetic"

static func presentation(amount: float, source: String, context: Dictionary = {}) -> Dictionary:
	var type: String = damage_kind(source, context)
	var category: String = str(context.get("feedback_kind", "damage"))
	var critical: bool = bool(context.get("critical", false)) and category in ["damage", "received", "shield"] and type != "true"
	var style: Dictionary = STYLES[type]
	var tint: Color = style.color
	var marker: String = str(style.mark)
	var prefix: String = ""
	match category:
		"heal":
			tint = Color("98edb4")
			marker = ""
			prefix = "+"
		"guard":
			tint = Color("9cddff")
			marker = "盾"
			prefix = "+"
		"shield":
			tint = Color("9cddff")
			marker = "盾"
		"received":
			prefix = "−"
			if type == "kinetic": tint = Color("ffadb1")
	var label: String = prefix + _amount_label(amount) + ("!" if critical else "")
	return {"damage_kind":type, "feedback_kind":category, "critical":critical,
		"font_size":31 if critical else 21, "outline_size":4 if critical else 3,
		"color":tint, "marker":marker, "label":label}

static func _amount_label(amount: float) -> String:
	if amount < 0.1: return "%.2f" % amount if amount >= 0.01 else "<0.01"
	if amount < 1.0: return "%.1f" % amount
	return str(roundi(amount))

static func draw_number(canvas: Node2D, font: Font, event: Dictionary) -> void:
	if font == null: return
	var t: float = clampf(float(event.age) / float(event.duration), 0.0, 1.0)
	var fade: float = minf(1.0, (1.0 - t) * 3.0)
	var style: Dictionary = event.get("presentation", presentation(float(event.amount), str(event.get("source", ""))))
	var at: Vector2 = event.at
	# Reduced effects keep the same numbers, colors and actual critical size;
	# only the motion is removed. No scale-pulsing or camera shake is added.
	if not bool(event.get("reduced", false)):
		at.y -= 28.0 * (1.0 - pow(1.0 - t, 2.0))
	var size: int = int(style.font_size)
	var label: String = str(style.label)
	var marker: String = str(style.marker)
	var marker_size: int = 13
	var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var marker_width: float = font.get_string_size(marker, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_size).x + 5.0 if not marker.is_empty() else 0.0
	at.x -= (width + marker_width) * 0.5
	canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(style.outline_size), Color(INK, fade))
	canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(style.color, fade))
	if not marker.is_empty():
		var mark_at: Vector2 = at + Vector2(width + 5.0, -2.0)
		canvas.draw_string_outline(font, mark_at, marker, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_size, 3, Color(INK, fade))
		canvas.draw_string(font, mark_at, marker, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_size, Color(style.color, fade))
