extends Control
## Screen-space pointer, separate from world coordinates and camera movement.
var direction := Vector2.LEFT
var text_label: Label
var route_icon: Control
var icon_kind := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(184,36)
	route_icon = Control.new()
	route_icon.set_script(load("res://scripts/ui/generated_ui_icon.gd"))
	route_icon.position = Vector2(40,3)
	route_icon.size = Vector2(30,30)
	add_child(route_icon)
	text_label = MineStyle.label(self,"",Vector2(75,5),Vector2(105,25),16,MineStyle.INK)
	text_label.autowrap_mode = TextServer.AUTOWRAP_OFF

func update_target(toward: Vector2, title: String, distance: int, kind: String = "route") -> void:
	direction = toward.normalized()
	if icon_kind != kind:
		icon_kind = kind
		route_icon.configure(kind)
	text_label.text = Words.text("HUD_NAV_DISTANCE",{"distance":distance})
	tooltip_text = title
	queue_redraw()

func _draw() -> void:
	draw_style_box(MineStyle.box(Color("fff3d7"),MineStyle.COPPER,1),Rect2(Vector2.ZERO,size))
	draw_line(Vector2(36,5),Vector2(36,31),MineStyle.COPPER,1)
	var center := Vector2(18,18)
	var side := direction.orthogonal()
	draw_line(center-direction*13,center+direction*13,MineStyle.INK,2,true)
	draw_polyline(PackedVector2Array([center+direction*4+side*8,center+direction*14,center+direction*4-side*8]),MineStyle.INK,2,true)
