class_name MineWorldCamera
extends Camera2D
## World-only tracking camera. HUD and modal menus belong on a CanvasLayer.

const WORLD_ZOOM := Vector2(0.85, 0.85)
const RENDER_MARGIN := 200.0
const IMPACT_MERGE_SECONDS := 0.055
const LIGHT_IMPACT_SECONDS := 0.11
const HEAVY_IMPACT_SECONDS := 0.145
var target: Node2D
var arena: Rect2
var render_bounds: Rect2
var impact_remaining: float = 0.0
var impact_strength: float = 0.0
var _impact_elapsed: float = 0.0
var _impact_duration: float = LIGHT_IMPACT_SECONDS
var _impact_direction := Vector2.UP
var _impact_started: int = 0
var _impact_merged: int = 0
var _impact_boosted: int = 0
var _peak_offset: float = 0.0

func _ready() -> void:
	Game.changed.connect(_read_settings)
	get_viewport().size_changed.connect(_fit_render_frame)
	_read_settings()


func impact(strength: float, direction: Vector2 = Vector2.ZERO, heavy: bool = false) -> void:
	if not _impact_enabled():
		_clear_impact()
		return
	if is_inside_tree() and get_tree().paused: return
	if not is_finite(strength) or strength <= 0.0: return
	var bounded_strength: float = minf(3.5 if heavy else 1.85, strength)
	# One area attack can confirm several contacts in a physics frame. Keep the
	# first direction and clock, otherwise a crowd becomes a sustained shake.
	if impact_remaining > 0.0 and _impact_elapsed < IMPACT_MERGE_SECONDS:
		_impact_merged += 1
		if bounded_strength > impact_strength:
			impact_strength = bounded_strength
			_impact_boosted += 1
			_update_impact_offset()
		return
	_impact_direction = direction.normalized() if direction.is_finite() and not direction.is_zero_approx() else Vector2.UP
	_impact_duration = HEAVY_IMPACT_SECONDS if heavy else LIGHT_IMPACT_SECONDS
	_impact_elapsed = 0.0
	impact_remaining = _impact_duration
	impact_strength = bounded_strength
	_impact_started += 1
	_update_impact_offset()


func impact_stats() -> Dictionary:
	return {"started": _impact_started, "merged": _impact_merged,
		"boosted": _impact_boosted, "peak_offset": _peak_offset,
		"remaining": impact_remaining, "elapsed": _impact_elapsed,
		"strength": impact_strength, "direction": _impact_direction}


func _reduced_fx() -> bool:
	return bool(Game.profile.get("settings", {}).get("reduced_fx", false))


func _impact_enabled() -> bool:
	# A steady world is the comfort default, including saves from before this
	# preference existed. Contact feedback stays on bodies and in the HUD.
	return bool(Game.profile.get("settings", {}).get("camera_shake", false)) and not _reduced_fx()


func _read_settings() -> void:
	if not _impact_enabled(): _clear_impact()


func _clear_impact() -> void:
	impact_remaining = 0.0
	impact_strength = 0.0
	_impact_elapsed = 0.0
	offset = Vector2.ZERO


func _update_impact_offset() -> void:
	var progress: float = clampf(_impact_elapsed / _impact_duration, 0.0, 1.0)
	# Contact kicks immediately, settles through zero, then has one shallow
	# counter-movement. No random angle and no oscillating screen shake.
	var envelope: float
	if progress < 0.38:
		envelope = pow(1.0 - progress / 0.38, 2.0)
	else:
		var rebound: float = (progress - 0.38) / 0.62
		envelope = -0.16 * sin(rebound * PI) * (1.0 - rebound)
	offset = _impact_direction * impact_strength * envelope
	_peak_offset = maxf(_peak_offset, offset.length())


func configure(room: Node2D, player: Node2D, world_arena: Rect2, painted_bounds: Rect2 = Rect2()) -> void:
	target = player
	arena = world_arena
	render_bounds = painted_bounds if painted_bounds.has_area() else arena.grow(RENDER_MARGIN)
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	limit_smoothed = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_priority = 100
	# The painted landscape is the view limit; its ground outline alone limits
	# feet. Keep foreground, water and architecture visible beyond that outline.
	var top_left: Vector2 = room.to_global(render_bounds.position)
	var bottom_right: Vector2 = room.to_global(render_bounds.end)
	limit_left = int(top_left.x)
	limit_top = int(top_left.y)
	limit_right = int(bottom_right.x)
	limit_bottom = int(bottom_right.y)
	_fit_render_frame()
	follow_target()
	if is_inside_tree():
		make_current()
		force_update_scroll()

func _fit_render_frame() -> void:
	if not render_bounds.has_area() or not is_inside_tree(): return
	var extent: Vector2 = get_viewport().get_visible_rect().size
	var fitted: float = maxf(WORLD_ZOOM.x, maxf(extent.x/render_bounds.size.x, extent.y/render_bounds.size.y))
	zoom = Vector2.ONE*fitted


func _physics_process(delta: float) -> void:
	if not _impact_enabled(): _clear_impact()
	if is_inside_tree() and get_tree().paused: return
	follow_target()
	if impact_remaining > 0.0:
		_impact_elapsed = minf(_impact_duration, _impact_elapsed + maxf(0.0, delta))
		impact_remaining = maxf(0.0, _impact_duration - _impact_elapsed)
		_update_impact_offset()
		if impact_remaining <= 0.0:
			offset = Vector2.ZERO
			impact_strength = 0.0
	else:
		offset = Vector2.ZERO
		impact_strength = 0.0


func follow_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position
