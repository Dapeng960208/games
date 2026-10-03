class_name StarCompanion
extends Node2D
## A single cosmetic follower. The actor owns every primary and spell packet.

const ART := "asset://heroes/ch03_star_companion.svg"
const ATLAS := "asset://heroes/ch03_star_companion.json"

var owner_player: Node2D
var state: String = "follow"
var state_remaining: float = 0.0
var animation_clock: float = 0.0
var _texture: Texture2D
var _atlas: Dictionary = {}
var _direction := Vector2.RIGHT
var _follow_offset := Vector2(-32.0, -58.0)

func configure(player: Node2D) -> void:
	owner_player = player
	position = _follow_offset
	z_index = 2
	_load_art()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_player) or Game.run == null or Game.run.hp <= 0.0:
		visible = false
		return
	visible = true
	if get_tree().paused or not is_finite(delta) or delta <= 0.0:
		return
	animation_clock += delta
	state_remaining = maxf(0.0, state_remaining - delta)
	if state_remaining <= 0.0:
		state = "follow"
	var side: float = -1.0 if owner_player.aim_direction.x >= 0.0 else 1.0
	var follow := Vector2(side * 32.0, -58.0 + sin(animation_clock * 3.0) * 3.0)
	position = position.lerp(follow, 1.0 - exp(-10.0 * delta))
	queue_redraw()

func primary_created(direction: Vector2) -> void:
	_direction = direction.normalized()
	_play("basic", 0.28)

func spell_released(skill_id: String, chorus: bool = false) -> void:
	_direction = owner_player.aim_direction.normalized()
	var action: String = {"CH03_SK02":"leap", "CH03_SK03":"guard", "CH03_SK04":"chorus", "CH03_SK06":"guard", "CH03_SK08":"vortex", "CH03_SK10":"chorus", "CH03_SK11":"patrol", "CH03_SK12":"leap"}.get(skill_id, "basic")
	_play("chorus" if chorus else action, 2.0 if skill_id in ["CH03_SK08", "CH03_SK11"] else 0.45)

func projectile_origin(direction: Vector2) -> Vector2:
	# Room-relative position; visual height does not change ground collision.
	var ground: Vector2 = owner_player.position + Vector2(position.x, -8.0)
	return ground + direction.normalized() * 12.0

func hud_state() -> String:
	return state

func _play(action: String, duration: float) -> void:
	state = action
	state_remaining = duration
	animation_clock = 0.0
	queue_redraw()

func _load_art() -> void:
	if _texture != null:
		return
	var path: String = AssetCatalog.resolve(ART)
	var atlas_path: String = AssetCatalog.resolve(ATLAS)
	if ResourceLoader.exists(path):
		_texture = load(path) as Texture2D
	if FileAccess.file_exists(atlas_path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
		if data is Dictionary:
			_atlas = data

func _draw() -> void:
	if _texture == null:
		return
	var clip: Dictionary = _atlas.get("states", {}).get(state, {})
	var regions: Array = clip.get("regions", [])
	if regions.is_empty():
		return
	var frame: int = int(animation_clock * float(clip.get("fps", 8.0)))
	frame = frame % regions.size() if bool(clip.get("loop", state == "follow")) else mini(frame, regions.size() - 1)
	var region: Array = regions[frame]
	if region.size() != 4:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if _direction.x < 0.0 else 1.0, 1.0))
	draw_texture_rect_region(_texture, Rect2(-Vector2(18.0, 18.0), Vector2(36.0, 36.0)), Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3])))
	draw_set_transform(Vector2.ZERO)
