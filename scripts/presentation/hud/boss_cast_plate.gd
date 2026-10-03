extends Control
## Screen-space cast feedback stays readable above world warnings and away from
## HUD instruments. It reads the same frozen telegraph that owns the attack.
const Presentation = preload("res://scripts/presentation/monsters/boss_skill_presentation.gd")
var info: Dictionary = {}
var cast_font: Font

func _ready() -> void:
	name = "BossCastPlate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 6
	hide()

func update_cast(room: Node, screen: Vector2, obstacles: Array[Rect2], font: Font) -> void:
	# A defeated actor may already be freed while the room retains its handle.
	# Validate the raw value before assigning it to a typed Node variable.
	var boss_ref: Variant = room.get("_boss_actor") if is_instance_valid(room) else null
	if not is_instance_valid(boss_ref):
		info.clear()
		hide()
		return
	var boss: Node = boss_ref
	if boss.is_queued_for_deletion() or not boss.is_alive() or boss.get("boss_brain") == null:
		info.clear()
		hide()
		return
	cast_font = font
	info = Presentation.readout(boss.boss_brain)
	size = Presentation.cast_rect(info,cast_font,Vector2.ZERO).size
	var preferred := Vector2((screen.x-size.x)*.5,157)
	# B06's authored north lane contains the boss head, name/health and bell.
	# Keep both idle library information and live danger timing in a side dock.
	if str(room.layout.get("biome_id","")) == "B06" and bool(room.layout.get("b06_candidate",false)) and screen.x >= 880:
		preferred = Vector2(screen.x-size.x-12,210)
	# Shift below intersecting instruments, including a live toast. Coordinates
	# are local to the HUD; camera movement cannot move this plate into the HUD.
	var candidate := Rect2(preferred,size)
	for _pass: int in obstacles.size()+1:
		var next_y := candidate.position.y
		for obstacle: Rect2 in obstacles:
			if candidate.intersects(obstacle.grow(8)):
				next_y = maxf(next_y,obstacle.end.y+12)
		if is_equal_approx(next_y,candidate.position.y): break
		candidate.position.y = next_y
	position = Vector2(clampf(candidate.position.x,12,maxf(12,screen.x-size.x-12)),clampf(candidate.position.y,12,maxf(12,screen.y-size.y-12)))
	show()
	queue_redraw()

func cast_rect() -> Rect2:
	return get_global_rect() if visible else Rect2()

func _draw() -> void:
	if not info.is_empty() and cast_font != null:
		Presentation.draw_cast(self,info,cast_font,Vector2(size.x*.5,28))
