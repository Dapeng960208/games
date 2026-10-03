class_name EnemyVisual
extends Node2D
## Body-only presentation. The owner keeps collision, AI, telegraphs and UI.
## Registered ordinary bodies use restrained pose transforms; native candidate
## chapters supply current frames with source regions and absolute foot anchors.

const SkillPresentation = preload("res://scripts/presentation/monsters/enemy_skill_presentation.gd")
const Palette = preload("res://scripts/presentation/monsters/enemy_palette.gd")
const Art = preload("res://scripts/presentation/monsters/enemy_art.gd")
const GAITS: Dictionary = {
	"skirmisher": {"stride":30.0,"bob":1.8,"roll":0.026,"lean":0.032,"squash":0.021,"impact":1.0},
	"tank": {"stride":43.0,"bob":1.0,"roll":0.016,"lean":0.020,"squash":0.016,"impact":0.62},
	"assassin": {"stride":24.0,"bob":1.5,"roll":0.030,"lean":0.056,"squash":0.025,"impact":1.08},
	"caster": {"stride":36.0,"bob":0.7,"roll":0.009,"lean":0.018,"squash":0.010,"impact":0.83},
	"support": {"stride":34.0,"bob":0.9,"roll":0.013,"lean":0.022,"squash":0.014,"impact":0.88},
}
static var _contact_masks: Dictionary = {}

var actor: Node2D
## -1 follows the live setting. Explicit values are useful for previews.
var reduced_fx_override: int = -1
var stride_phase: float = 0.0
var movement_weight: float = 0.0
var phase: StringName = &"idle"
var phase_progress: float = 0.0
var body_offset := Vector2.ZERO
var body_scale := Vector2.ONE
var body_rotation: float = 0.0
var facing: float = 1.0
var flash_strength: float = 0.0
var selected_frame: Dictionary = {}
var asset_mode: String = "static_pose"

var _previous_position := Vector2.ZERO
var _clock: float = 0.0
var _phase_elapsed: float = 0.0
var _phase_duration: float = 0.0
var _movement_direction := Vector2.ZERO
var _gait: Dictionary = GAITS.skirmisher
var _archetype: String = "skirmisher"
var _impact_direction := Vector2.ZERO
var _impact_strength: float = 0.0
var _impact_elapsed: float = 0.0
var _impact_duration: float = 0.0
var _impact_age: float = 0.0
var _impact_heavy: bool = false
var _reaction_style: String = "CH01"
var _contact_hold_remaining: float = 0.0
var _contact_release_remaining: float = 0.0
var _bank: Dictionary = {}
var _foot := Vector2(0, 18)
var _body_material: ShaderMaterial
var _palette_colors: Dictionary = {}
var _storybook_entry: Dictionary = {}
var skill_badge: SkillBadge

class SkillBadge extends Node2D:
	var icon: Dictionary = {}
	var command: Dictionary = {}
	var identity: String = ""
	var info: Dictionary = {}
	var show_detail: bool = false
	var detail_slot: int = 0
	var locked: bool = false
	var progress: float = 0.0
	var reduced_fx: bool = false
	func _draw() -> void:
		if not visible: return
		var active: bool = not command.is_empty()
		var edge := Color("c86558") if locked else Color("d4a34f") if active else Color("ab9c84")
		draw_circle(Vector2.ZERO, 14.0, Color("fff0cf"))
		var texture: Texture2D = icon.get("texture")
		if texture != null:
			draw_texture_rect_region(texture, Rect2(-12,-12,24,24), icon.region)
		else:
			SkillPresentation.draw_identity(self,identity,Vector2.ZERO,10.0,Color("6d4a70"))
		draw_arc(Vector2.ZERO,14.0,0,TAU,32,Color("6d4a70"),1.3,true)
		if active:
			draw_arc(Vector2.ZERO,15.5,-PI*.5,-PI*.5+TAU*maxf(.02,progress),32,edge,2.0 if reduced_fx else 2.6,true)
			var count: int = mini(7,int(command.get("stage_count",1)))
			for index: int in count:
				draw_circle(Vector2((index-(count-1)*.5)*5.0,20.0),1.7,edge if index <= int(command.get("stage",0)) else Color("bba68b"))
		if show_detail:
			var at := detail_origin()
			var matrix: Transform2D = get_global_transform_with_canvas()
			var bounds: Rect2 = matrix * Rect2(at,Vector2(254,61))
			var viewport: Rect2 = get_viewport_rect().grow(-8)
			var offset := Vector2.ZERO
			if bounds.end.x > viewport.end.x: offset.x = viewport.end.x-bounds.end.x
			elif bounds.position.x < viewport.position.x: offset.x = viewport.position.x-bounds.position.x
			if bounds.end.y > viewport.end.y: offset.y = viewport.end.y-bounds.end.y
			elif bounds.position.y < viewport.position.y: offset.y = viewport.position.y-bounds.position.y
			at += matrix.basis_xform_inv(offset)
			SkillPresentation.draw_card(self,info,at)

	func detail_origin() -> Vector2:
		var at := Vector2(21,-29) if detail_slot == 0 else Vector2(-275,-86)
		# Keep optional B05 prose above all native poses and their attack organs.
		if identity.begins_with("B05-M"): at.y = -78.0 if detail_slot == 0 else -140.0
		return at

func configure(enemy: Node2D) -> void:
	actor = enemy
	name = "EnemyBody"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Explicit advance after resolved movement avoids process-order dependence.
	set_process(false)
	set_physics_process(false)
	_previous_position = actor.position
	var definition: Dictionary = actor.get("profile")
	_archetype = str(definition.get("archetype", "skirmisher"))
	_gait = GAITS.get(_archetype, GAITS.skirmisher)
	_storybook_entry = Art.install(actor)
	var bounds: Rect2 = actor.get("body_bounds")
	_foot = _storybook_entry.get("world_foot",Vector2(0,bounds.end.y))
	if actor.has_method("b06_body_frame") and not actor.call("b06_body_frame").is_empty():
		_foot = Vector2.ZERO
	# Ordinary identities keep their registered current body. Native candidate
	# chapters supply their own active pose banks below.
	_bank = {}
	if bool(_storybook_entry.get("b05_native_bank",false)):
		_bank = preload("res://scripts/levels/b05/art/enemy_art.gd").bank(str(actor.get("enemy_id")))
		_bank["world_reference_height"] = float(_storybook_entry.world_reference_height)
	if bool(_storybook_entry.get("b06_native_bank",false)):
		_bank = preload("res://scripts/levels/b06/art/native_art.gd").bank(str(actor.get("enemy_id")))
		_bank["world_reference_height"] = float(_storybook_entry.world_reference_height)
	if not bool(actor.get("static_actor")) and (str(actor.get("enemy_id")).begins_with("M") or str(actor.get("enemy_id")).begins_with("B05-M") or str(actor.get("enemy_id")).begins_with("B06-M")):
		skill_badge = SkillBadge.new()
		skill_badge.name = "EnemySkillBadge"
		skill_badge.identity = str(actor.get("enemy_id"))
		skill_badge.icon = Art.skill_icon_for(skill_badge.identity)
		# Nearby prose and icons stay below the room's z=5 danger geometry,
		# regardless of the owning actor's body layer.
		skill_badge.z_as_relative = false
		skill_badge.z_index = 4
		skill_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# This sibling stays upright, outside the body's palette and mirroring.
		actor.add_child(skill_badge)
		skill_badge.position = Vector2(34, bounds.position.y - 3)
		if bool(_bank.get("b05_native_bank",false)):
			var factor: float=float(_bank.world_reference_height)/float(_bank.body_height)
			for frames: Array in _bank.clips.values():
				for frame: Dictionary in frames:
					skill_badge.position.y=minf(skill_badge.position.y,(frame.region.position.y-frame.foot.y)*factor+_foot.y-3.0)
		skill_badge.visible = false
	# Prepare compact CPU alpha data while configuring the room, never on the
	# first strike. Include authored frames and M35's alternate empty silhouette.
	_prepare_contact_mask(actor.get("body_texture"))
	_prepare_contact_mask(_bank.get("texture"))
	if bool(_bank.get("b05_native_bank",false)) or bool(_bank.get("b06_native_bank",false)):
		for frames: Array in _bank.get("clips",{}).values():
			for frame: Dictionary in frames: _prepare_contact_mask(frame.get("texture"))
	_prepare_contact_mask(actor.get("empty_body_texture"))
	_body_material = Palette.material_for(str(actor.get("enemy_id")), definition, not _storybook_entry.is_empty())
	_palette_colors = Palette.colors_for(str(actor.get("enemy_id")), definition)
	_body_material.set_shader_parameter("textured_body", actor.get("body_texture") != null or _bank.get("texture") != null)
	material = _body_material
	_read_phase(0.0)
	_update_skill_badge()
	_update_pose(0.0)
	_select_frame()
	queue_redraw()

func advance(delta: float) -> void:
	if not is_instance_valid(actor) or delta <= 0.0:
		return
	if is_inside_tree() and get_tree().paused:
		_previous_position = actor.position
		return
	var step: float = minf(delta, 0.1)
	_clock += step
	_read_phase(step)
	_update_skill_badge()
	var displacement: Vector2 = actor.position - _previous_position
	_previous_position = actor.position
	var distance: float = displacement.length()
	var speed: float = maxf(1.0, float(actor.get("move_speed")))
	var knockback: Vector2 = actor.get("knockback")
	var displaced: bool = actor.has_method("has_pending_displacement") and bool(actor.call("has_pending_displacement"))
	# Sliding on impact, authored lunges and teleports are not footfalls.
	var locomotion: bool = phase in [&"chase", &"reposition"] and not actor.has_meta("enemy_skill_motion") and not displaced and float(actor.get("reaction_remaining")) <= 0.0 and knockback.length() < speed * 0.35 and _impact_elapsed >= _impact_duration
	var moving: bool = locomotion and distance > 0.025 and distance < maxf(48.0, speed * delta * 2.5)
	if moving:
		stride_phase = fposmod(stride_phase + distance / float(_bank.get("cycle_distance", _gait.stride)) * TAU, TAU)
		_movement_direction = displacement / distance
	var target_weight: float = clampf(distance / maxf(1.0, speed * delta), 0.0, 1.0) if moving else 0.0
	var body_step: float = step
	if _contact_hold_remaining > 0.0:
		var held: float = minf(body_step, _contact_hold_remaining)
		_contact_hold_remaining = maxf(0.0, _contact_hold_remaining - held)
		body_step -= held
		if _contact_hold_remaining <= 0.0:
			# A burst must visibly release before another contact may hold it.
			# This clock is independent of impacts that restart the recoil curve.
			_contact_release_remaining = 0.08
	_contact_release_remaining = maxf(0.0, _contact_release_remaining - body_step)
	if _impact_elapsed < _impact_duration:
		_impact_age += step
		_impact_elapsed = minf(_impact_duration, _impact_elapsed + body_step)
	if body_step > 0.0:
		movement_weight = move_toward(movement_weight, target_weight, body_step * (12.0 if moving else 18.0))
		_update_pose(body_step)
		_select_frame()
	else:
		# Hold only the local body pose/frame. The parent's resolved position,
		# AI phase and telegraph progress above keep their authoritative clocks.
		# The short material flash also fades normally instead of staying white.
		_update_contact_flash()
	queue_redraw()

func receive_impact(direction: Vector2, strength: float = 1.0, heavy: bool = false, reaction_style: String = "CH01", contact_pause: float = -1.0) -> void:
	if not is_instance_valid(actor) or strength <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	var already_held: bool = _contact_hold_remaining > 0.0
	var coordinated: bool = is_finite(contact_pause) and contact_pause >= 0.0
	if coordinated:
		# Live contacts supply the attacker's actual remaining visual pause.
		# Even a weaker recoil kept below shares that clock; AI/movement stay live.
		_contact_hold_remaining = clampf(contact_pause, 0.0, 0.085)
	# Simultaneous pellets/ticks cannot perpetually replace the contact pose.
	# A real heavy contact may upgrade a light pose within the original window.
	# Coordinated contacts already share the live player's remaining deadline;
	# standalone previews keep their original hold deadline below.
	if already_held and (not heavy or _impact_heavy):
		return
	if _contact_release_remaining > 0.0 and _impact_elapsed < _impact_duration:
		if not (heavy and not _impact_heavy) and clampf(strength, 0.15, 1.6) <= _impact_strength:
			return
	# A node or field tick must not erase the direct hit's compression/recovery.
	# Stronger contacts may upgrade immediately; weaker ones wait until the body settles.
	if _impact_duration > 0.0 and _impact_elapsed < _impact_duration:
		var remaining_weight: float = _impact_strength * pow(1.0 - _impact_elapsed / _impact_duration, 2.0)
		if (not heavy and _impact_heavy and _impact_elapsed < 0.10) or strength < remaining_weight:
			return
	var aim: Vector2 = actor.get("aim_direction")
	_impact_direction = direction.normalized() if direction.length_squared() > 0.0001 else -aim.normalized()
	if _impact_direction.length_squared() < 0.0001:
		_impact_direction = Vector2.RIGHT
	# Replace, rather than accumulate, rapid hits so crowds cannot amplify sway.
	_impact_strength = clampf(strength, 0.15, 1.6)
	_impact_heavy = heavy
	_reaction_style = reaction_style if reaction_style in ["CH01", "CH02", "CH03"] else "CH01"
	_impact_duration = (0.20 if heavy else 0.13) if _reaction_style == "CH02" else (0.22 if heavy else 0.17) if _reaction_style == "CH03" else (0.25 if heavy else 0.18)
	_impact_elapsed = 0.0
	_impact_age = 0.0
	if not coordinated and not already_held and _contact_release_remaining <= 0.0 and strength >= 0.5:
		# Derived field/node contacts arrive at .28 strength and keep a small
		# flowing recoil; direct contacts match the attacker's hit-stop cadence.
		_contact_hold_remaining = (0.074 if heavy else 0.042) if _reaction_style == "CH01" else (0.030 if heavy else 0.015) if _reaction_style == "CH02" else (0.038 if heavy else 0.024)
	_update_pose(0.0)
	_select_frame()
	queue_redraw()

func _read_phase(delta: float) -> void:
	var next_phase: StringName = StringName(actor.get("state"))
	var remaining: float = maxf(0.0, float(actor.get("state_time")))
	if next_phase != phase:
		phase = next_phase
		_phase_elapsed = 0.0
		_phase_duration = remaining
	else:
		_phase_elapsed += delta
	phase_progress = clampf(1.0 - remaining / _phase_duration, 0.0, 1.0) if _phase_duration > 0.001 else clampf(_phase_elapsed / 0.2, 0.0, 1.0)
	var brain: Variant = actor.get("brain")
	if brain is Object and brain.has_method("current_telegraph") and phase in [&"telegraph", &"locked"]:
		var tell: Dictionary = brain.call("current_telegraph")
		phase_progress = clampf(float(tell.get("progress", phase_progress)), 0.0, 1.0)

func _update_skill_badge() -> void:
	if not is_instance_valid(skill_badge): return
	var brain: Variant = actor.get("brain")
	skill_badge.info = SkillPresentation.readout(brain) if brain is RefCounted else {}
	skill_badge.command = skill_badge.info.get("command",{})
	skill_badge.visible = actor.has_method("is_alive") and bool(actor.call("is_alive"))
	skill_badge.locked = bool(skill_badge.info.get("locked",false))
	skill_badge.progress = float(skill_badge.info.get("progress",0.0))
	skill_badge.reduced_fx = _reduced_fx()
	var room: Variant = preload("res://scripts/domain/combat/combat_properties.gd").read(actor,"room")
	var candidates: Array[int] = SkillPresentation.detail_candidates(room) if room is Node else []
	skill_badge.detail_slot = candidates.find(actor.get_instance_id())
	skill_badge.show_detail = skill_badge.detail_slot >= 0
	skill_badge.queue_redraw()

func _update_pose(_delta: float) -> void:
	var reduced: bool = _reduced_fx()
	var amplitude: float = 0.42 if reduced else 1.0
	var aim: Vector2 = actor.get("aim_direction")
	if aim.length_squared() > 0.001:
		aim = aim.normalized()
	else:
		aim = Vector2(facing, 0)
	# A small dead zone prevents left/right flicker while aiming vertically.
	if absf(aim.x) > 0.15 and _impact_elapsed >= _impact_duration:
		facing = -1.0 if aim.x < 0.0 else 1.0
	var step_wave: float = sin(stride_phase)
	var footfall: float = (1.0 - cos(stride_phase * 2.0)) * 0.5
	body_offset = Vector2(0, -footfall * float(_gait.bob) * movement_weight)
	body_scale = Vector2(1.0 + footfall * float(_gait.squash) * movement_weight, 1.0 - footfall * float(_gait.squash) * movement_weight)
	body_rotation = step_wave * float(_gait.roll) * movement_weight + _movement_direction.x * float(_gait.lean) * movement_weight
	# Static bodies retain a nearly still breathing silhouette while stopped.
	var breath: float = sin(_clock * (2.2 if _archetype == "tank" else 2.8)) * 0.003 * (1.0 - movement_weight)
	body_scale += Vector2(-breath * 0.5, breath)
	var p: float = phase_progress
	var weight: float = 1.12 if _archetype == "tank" else 0.82 if _archetype in ["caster", "support"] else 1.0
	match phase:
		&"telegraph", &"windup":
			var prepare: float = smoothstep(0.0, 1.0, p)
			body_offset += -aim * (1.2 + prepare * 2.0) * weight
			body_scale += Vector2(0.022, -0.034) * prepare
			body_rotation -= aim.x * (0.025 + prepare * 0.035)
		&"locked":
			body_offset += -aim * 3.3 * weight + Vector2(0, 1.1)
			body_scale += Vector2(0.035, -0.055)
			body_rotation -= aim.x * 0.065
		&"execute":
			# Maintain a forward silhouette for held charges, without new impulses.
			var release: float = 1.0 - 0.35 * smoothstep(0.0, 1.0, p)
			body_offset += aim * 5.6 * weight * release
			body_scale += Vector2(-0.027, 0.035) * release
			body_rotation += aim.x * 0.085 * release
		&"recovery":
			var settle: float = 1.0 - smoothstep(0.0, 1.0, p)
			body_offset += aim * 2.1 * weight * settle + Vector2(0, 0.9 * settle)
			body_scale += Vector2(0.015, -0.022) * settle
			body_rotation += aim.x * 0.035 * settle
		&"emerging":
			body_scale += Vector2(0.018, -0.035) * (1.0 - p)
	var action_brain: Variant = actor.get("brain")
	if action_brain is Object and action_brain.has_method("action_presentation"):
		var pose: Dictionary = preload("res://scripts/presentation/monsters/boss_skill_presentation.gd").body_pose(action_brain.action_presentation())
		body_offset += pose.offset
		body_scale += pose.scale
		body_rotation += float(pose.rotation)
	var impact: float = 0.0
	if _impact_duration > 0.0 and _impact_elapsed < _impact_duration:
		var t: float = _impact_elapsed / _impact_duration
		# Immediate recoil, a single small counter-settle, then exactly neutral.
		impact = pow(1.0 - t, 2.0)
		var settle: float = sin(t * PI) * (1.0 - t) * 0.2
		var mass: float = float(_gait.impact) * _impact_strength
		var recoil: float = (6.0 if _impact_heavy else 3.8) * mass
		if _reaction_style == "CH02": recoil *= 0.72
		elif _reaction_style == "CH03": recoil *= 0.58
		body_offset += _impact_direction * recoil * (impact - settle)
		if _reaction_style == "CH03":
			# Crystal energy contracts the silhouette, followed by one small release.
			body_scale -= Vector2(0.045, 0.040) * mass * (impact - settle * 0.55)
		else:
			# Compression follows the incoming force, rather than always flattening
			# the body vertically. These are display scales, never collider scales.
			var axis := Vector2(_impact_direction.x * _impact_direction.x, _impact_direction.y * _impact_direction.y)
			var compression: float = 0.026 if _reaction_style == "CH02" else 0.078
			var spread: float = 0.012 if _reaction_style == "CH02" else 0.040
			body_scale += (Vector2(axis.y, axis.x) * spread - axis * compression) * mass * impact
		body_rotation += _impact_direction.x * (0.022 if _reaction_style == "CH02" else 0.016 if _reaction_style == "CH03" else 0.06 if _impact_heavy else 0.04) * mass * impact
		# Recoil is shown with facing held; no randomized shake or flicker.
	body_offset = body_offset.limit_length(12.0) * amplitude
	body_scale = Vector2.ONE + (body_scale - Vector2.ONE) * amplitude
	body_rotation = clampf(body_rotation * amplitude, -0.16, 0.16)
	position = _foot + body_offset
	rotation = body_rotation
	# Mirroring is about the source foot, not its sometimes asymmetric crop.
	var source_facing: float = -1.0 if str(_bank.get("facing", "right")) == "left" else 1.0
	scale = Vector2(body_scale.x * facing * source_facing, body_scale.y)
	_update_contact_flash()

func _update_contact_flash() -> void:
	var flash_age: float = maxf(0.0, _impact_age - 0.012)
	var flash_fade: float = pow(maxf(0.0, 1.0 - flash_age / (0.065 if _impact_heavy else 0.045)), 1.3)
	# Flash age follows real time, independently of the held recoil pose.
	flash_strength = 0.0 if _reduced_fx() or _impact_elapsed >= _impact_duration else minf(0.60, (0.60 if _impact_heavy else 0.54) * _impact_strength) * flash_fade
	if _body_material != null:
		_body_material.set_shader_parameter("impact_mix", flash_strength)

func _reduced_fx() -> bool:
	if reduced_fx_override >= 0:
		return reduced_fx_override > 0
	if not is_inside_tree():
		return false
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return false
	var saved: Variant = game.get("profile")
	return bool(saved.get("settings", {}).get("reduced_fx", false)) if saved is Dictionary else false

func _select_frame() -> void:
	selected_frame = {}
	asset_mode = "storybook_static" if not _storybook_entry.is_empty() else "static_pose"
	if _bank.is_empty() or _using_empty_body():
		return
	var clips: Dictionary = _bank.clips
	var action: String = "idle"
	var progress: float = 0.0
	if _impact_elapsed < _impact_duration and clips.has("recoil"):
		action = "recoil"
		progress = _impact_elapsed / _impact_duration
	elif phase in [&"telegraph", &"locked", &"windup", &"execute", &"recovery"]:
		action = "telegraph" if phase == &"windup" else str(phase)
		progress = phase_progress
		if not clips.has(action) and clips.has("attack"):
			action = "attack"
			match phase:
				&"telegraph", &"windup": progress = phase_progress * 0.3
				&"locked": progress = 0.3 + phase_progress * 0.18
				&"execute": progress = 0.48 + phase_progress * 0.25
				&"recovery": progress = 0.73 + phase_progress * 0.27
	elif movement_weight > 0.03 and phase in [&"chase", &"reposition"]:
		action = "walk"
		progress = stride_phase / TAU
	var frames: Array = clips.get(action, clips.get("idle", []))
	if frames.is_empty():
		return
	selected_frame = frames[mini(frames.size() - 1, int(clampf(progress, 0.0, 1.0) * frames.size()))]
	asset_mode = "storybook_frames" if not _storybook_entry.is_empty() else "authored_frames"

func _using_empty_body() -> bool:
	if str(actor.get("enemy_id")) != "M35" or actor.get("empty_body_texture") == null:
		return false
	var room: Variant = actor.get("room")
	if not is_instance_valid(room):
		return true
	var props: Variant = room.get("enemy_props")
	return not is_instance_valid(props) or not props.has_method("carried_by") or not bool(props.call("carried_by", actor))

func body_frame() -> Dictionary:
	if is_instance_valid(actor) and actor.has_method("b06_body_frame"):
		var native: Dictionary = actor.call("b06_body_frame")
		if not native.is_empty():
			native.bounds.position -= _foot
			return native
	if not is_instance_valid(actor):
		return {}
	if not selected_frame.is_empty() and not _using_empty_body():
		var factor: float = float(_bank.get("world_reference_height",maxf(1.0,(actor.get("body_bounds") as Rect2).size.y))) / float(_bank.body_height) * float(selected_frame.get("source_pose_scale",1.0))
		var region: Rect2 = selected_frame.region
		return {"texture":selected_frame.get("texture",_bank.texture),"region":region,"bounds":Rect2((region.position - selected_frame.foot) * factor, region.size * factor),"name":selected_frame.name,"source_family":str(_bank.get("source_family", "legacy")),"full_color":not _storybook_entry.is_empty()}
	var bounds: Rect2 = actor.get("body_bounds")
	return {"texture":actor.get("empty_body_texture") if _using_empty_body() else actor.get("body_texture"),"region":actor.get("body_region"),"bounds":Rect2(bounds.position - _foot, bounds.size),"name":"static","fallback_colors":_palette_colors,"source_family":Art.FAMILY if not _storybook_entry.is_empty() else "legacy","full_color":not _storybook_entry.is_empty()}

## Incoming direction is expressed in the actor parent's coordinates. The
## returned point is local to this visual, so mirroring, recoil and authored
## foot registration are followed without changing the actor's physics origin.
func contact_anchor(incoming_direction: Vector2) -> Dictionary:
	if not is_instance_valid(actor) or not incoming_direction.is_finite(): return {}
	var frame: Dictionary = body_frame()
	var texture: Texture2D = frame.get("texture")
	var bounds: Rect2 = frame.get("bounds", Rect2())
	if texture == null or not bounds.has_area(): return {}
	var region: Rect2 = frame.get("region", Rect2())
	if not region.has_area(): region = Rect2(Vector2.ZERO, texture.get_size())
	var key: int = texture.get_instance_id()
	if not _contact_masks.has(key): return {}
	var visible: BitMap = _contact_masks[key]
	var global_direction: Vector2 = actor.get_parent().global_transform.basis_xform(incoming_direction) if actor.get_parent() is Node2D else incoming_direction
	var local_direction: Vector2 = global_transform.basis_xform_inv(global_direction).normalized()
	if local_direction.is_zero_approx(): local_direction = Vector2.RIGHT
	var center := Vector2(bounds.get_center().x, bounds.end.y - bounds.size.y * 0.53)
	if not _opaque_contact(visible, region, bounds, center):
		# Some silhouettes have a hollow chest or an off-center authored pose.
		# Find an actual nearby opaque pixel before tracing its incoming surface.
		var found: bool = false
		for ring in range(1, 13):
			for spoke in 16:
				var candidate: Vector2 = center + Vector2.from_angle(float(spoke) * TAU / 16.0) * float(ring) * minf(bounds.size.x, bounds.size.y) / 24.0
				if _opaque_contact(visible, region, bounds, candidate):
					center = candidate
					found = true
					break
			if found: break
		if not found: return {}
	var reach: float = bounds.size.length()
	var start: Vector2 = center - local_direction * reach
	var samples: int = clampi(ceili(reach * 2.0), 32, 256)
	var previous: Vector2 = start
	for index in range(1, samples + 1):
		var point: Vector2 = start.lerp(center, float(index) / samples)
		if _opaque_contact(visible, region, bounds, point):
			# Refine the silhouette boundary; keep the opaque end of the interval.
			for refinement in 5:
				var middle: Vector2 = previous.lerp(point, 0.5)
				if _opaque_contact(visible, region, bounds, middle): point = middle
				else: previous = middle
			return {"anchor":weakref(self), "local_offset":point}
		previous = point
	return {"anchor":weakref(self), "local_offset":center}

static func _prepare_contact_mask(texture: Texture2D) -> void:
	if texture == null or _contact_masks.has(texture.get_instance_id()): return
	var source: Image = texture.get_image()
	if source == null or source.is_empty(): return
	if source.is_compressed() and source.decompress() != OK: return
	var mask := BitMap.new()
	mask.create_from_image_alpha(source, 0.18)
	# One bit per source pixel; retain no decoded RGBA copies per monster.
	if _contact_masks.size() >= 96: _contact_masks.clear()
	_contact_masks[texture.get_instance_id()] = mask

static func _opaque_contact(mask: BitMap, region: Rect2, bounds: Rect2, point: Vector2) -> bool:
	if not bounds.has_point(point): return false
	var pixel := Vector2i(region.position + (point - bounds.position) * region.size / bounds.size)
	return Rect2i(Vector2i.ZERO, mask.get_size()).has_point(pixel) and mask.get_bitv(pixel)

func _draw() -> void:
	if not is_instance_valid(actor):
		return
	var frame: Dictionary = body_frame()
	var texture: Texture2D = frame.get("texture")
	var tint := Color(1, 1, 1, 0.35 if bool(actor.get_meta("enemy_shadow_stealth", false)) else 1.0)
	_body_material.set_shader_parameter("textured_body", texture != null)
	if texture != null:
		var region: Rect2 = frame.region
		if region.has_area():
			draw_texture_rect_region(texture, frame.bounds, region, tint)
		else:
			draw_texture_rect(texture, frame.bounds, false, tint)
	else:
		_draw_fallback(tint)

func _draw_fallback(tint: Color) -> void:
	if actor.has_method("draw_body_fallback"):
		draw_set_transform(-_foot)
		actor.call("draw_body_fallback", self, tint)
		draw_set_transform(Vector2.ZERO)
		return
	# The geometry fallback also stops its legs when actual movement stops.
	var walk: float = sin(stride_phase) * 2.5 * movement_weight
	draw_set_transform(-_foot)
	for side: float in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([Vector2(side*8,0),Vector2(side*23,-8+walk*side),Vector2(side*29,6+walk*side)]),(_palette_colors.trim as Color)*tint,4.0,true)
		draw_polyline(PackedVector2Array([Vector2(side*9,5),Vector2(side*21,13-walk*side),Vector2(side*23,21-walk*side)]),(_palette_colors.shade as Color)*tint,4.0,true)
	draw_colored_polygon(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6),Vector2(13,12),Vector2(-12,12)]),(_palette_colors.primary as Color)*tint)
	draw_polyline(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6)]),(_palette_colors.highlight as Color)*tint,2.0,true)
	draw_line(Vector2(-13,-4),Vector2(14,-4),(_palette_colors.outline as Color)*tint,6.0)
	draw_line(Vector2(-9,-4),Vector2(10,-4),(_palette_colors.energy as Color)*tint,3.0)
	draw_circle(Vector2(0,5),5.0,(_palette_colors.trim as Color)*tint)
	draw_circle(Vector2(0,5),2.0,(_palette_colors.energy as Color)*tint)
	draw_set_transform(Vector2.ZERO)

## Display-only native organ point in room coordinates. It follows the exact
## selected texture, fixed anatomy scale, mirroring and recoil transform.
func b05_visual_outlet() -> Dictionary:
	if not bool(_bank.get("b05_native_bank",false)) or selected_frame.is_empty() or not selected_frame.has("outlet"): return {}
	var factor: float=float(_bank.world_reference_height)/float(_bank.body_height)
	var local_point: Vector2=(Vector2(selected_frame.outlet)-Vector2(selected_frame.foot))*factor
	var room: Variant=preload("res://scripts/domain/combat/combat_properties.gd").read(actor,"room")
	var world_point:=to_global(local_point)
	return {"position":room.to_local(world_point) if room is Node2D else world_point,"pose":selected_frame.name,"texture_path":selected_frame.get("texture_path","")}

## All authored emission organs in the same display-only room coordinates.
## Projectile simulation continues using its frozen ground-plane path.
func b05_visual_outlets() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not bool(_bank.get("b05_native_bank",false)) or selected_frame.is_empty(): return result
	var factor: float=float(_bank.world_reference_height)/float(_bank.body_height)
	var room: Variant=preload("res://scripts/domain/combat/combat_properties.gd").read(actor,"room")
	for source: Vector2 in selected_frame.get("outlets",[]):
		var world_point:=to_global((source-Vector2(selected_frame.foot))*factor)
		result.append({"position":room.to_local(world_point) if room is Node2D else world_point,"pose":selected_frame.name,"texture_path":selected_frame.get("texture_path","")})
	return result

func synchronize_b05_release() -> void:
	if not bool(_bank.get("b05_native_bank",false)): return
	_read_phase(0.0)
	_update_pose(0.0)
	_select_frame()
	queue_redraw()

## B06 display-only outlet follows the selected pose and complete visual transform.
func b06_visual_outlet() -> Dictionary:
	if not bool(_bank.get("b06_native_bank",false)) or selected_frame.is_empty(): return {}
	var factor: float = float(_bank.world_reference_height) / float(_bank.body_height) * float(selected_frame.get("source_pose_scale",1.0))
	var point: Vector2 = (Vector2(selected_frame.outlet) - Vector2(selected_frame.foot)) * factor
	var room: Variant = preload("res://scripts/domain/combat/combat_properties.gd").read(actor,"room")
	var world_point := to_global(point)
	return {"position":room.to_local(world_point) if room is Node2D else world_point,"pose":selected_frame.name,"texture_path":selected_frame.get("texture_path","")}

func synchronize_b06_release() -> void:
	if not bool(_bank.get("b06_native_bank",false)): return
	_read_phase(0.0)
	_update_pose(0.0)
	_select_frame()
	queue_redraw()
