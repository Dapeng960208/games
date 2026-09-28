class_name MineWorldCamera
extends Camera2D
## World-only tracking camera. HUD and modal menus belong on a CanvasLayer.

const WORLD_ZOOM := Vector2(0.85, 0.85)
const RENDER_MARGIN := 64.0
var target: Node2D
var arena: Rect2
var render_bounds: Rect2


func configure(room: Node2D, player: Node2D, world_arena: Rect2) -> void:
	target = player
	arena = world_arena
	render_bounds = arena.grow(RENDER_MARGIN)
	zoom = WORLD_ZOOM
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	limit_smoothed = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_priority = 100
	# Collision stays at the authored arena; a render-only border keeps articulated
	# shoulders, weapons and feet visible when the collider reaches that edge.
	var top_left: Vector2 = room.to_global(render_bounds.position)
	var bottom_right: Vector2 = room.to_global(render_bounds.end)
	limit_left = int(top_left.x)
	limit_top = int(top_left.y)
	limit_right = int(bottom_right.x)
	limit_bottom = int(bottom_right.y)
	follow_target()
	if is_inside_tree():
		make_current()
		force_update_scroll()


func _physics_process(_delta: float) -> void:
	follow_target()


func follow_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position
