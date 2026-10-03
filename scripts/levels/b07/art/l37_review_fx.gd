extends RefCounted
## Explicit L37 review ornaments only. Existing commands, clocks, danger
## boundaries and projectile positions remain the sole combat authority.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Properties = preload("res://scripts/domain/combat/combat_properties.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const ROOT := "asset://levels/b07/effects/"
const REVIEW_FLAG := "--b07-convergence-review"
# Measured alpha > 16 bounds, not the PNG canvas size. The source bytes and RGB
# are untouched. Anchors identify the spear tip, open ring or visible body.
const FRAMES := {
	"spear_impact":{"region":Rect2(279,175,1348,534),"anchor":Vector2(1626,480)},
	"sand_landing":{"region":Rect2(35,167,1498,666),"anchor":Vector2(768,512)},
	"sand_ball":{"region":Rect2(358,273,763,488),"anchor":Vector2(880,515)},
	"sand_disc":{"region":Rect2(189,167,1189,713),"anchor":Vector2(783.5,523.5)}
}

static func enabled(canvas: Node2D) -> bool:
	var args := OS.get_cmdline_user_args()
	if REVIEW_FLAG not in args or "--b07-art-trial" not in args or "--b07-midground-trial" not in args: return false
	if not Rules.b07_candidate_enabled(): return false
	var room: Variant = Properties.read(canvas,"room")
	if not room is Node2D or Properties.read(room,"enemy_skills") != canvas: return false
	var layout: Dictionary = Properties.read(room,"layout",{})
	return bool(layout.get("b07_candidate",false)) and str(layout.get("blueprint_room_id","")) == "L37" and str(Properties.read(room,"layout_id","")) == "L37"

static func effect_spec(canvas: Node2D, command: Dictionary, reduced: bool = false) -> Dictionary:
	# This seam receives released _flash records only, never a tell or an actor
	# pose. A cancelled leap therefore cannot show an invented landing impact.
	if reduced or not enabled(canvas) or not bool(command.get("b07_command",false)): return {}
	if not command.has("color") or float(command.get("remaining",0)) <= 0 or bool(command.get("harmless",false)): return {}
	var ability := str(command.get("ability_id",""))
	var caster := str(command.get("caster_enemy_id",""))
	var kind := str(command.get("kind",""))
	var shape := str(command.get("shape",""))
	var at: Vector2 = command.get("target",Vector2.ZERO)
	var direction: Vector2 = command.get("direction",Vector2.RIGHT)
	var id := ""
	var width := 0.0
	var rotation := 0.0
	if caster == "B07-M01" and ability == "B07-M01:sun_spear" and kind == "melee" and shape == "line":
		if not canvas.has_method("_line_segment"): return {}
		# Reuse exactly the runtime's wall-clipped segment. This is a release
		# glint at its tip, not evidence that a victim was actually hit.
		var line: Array = canvas.call("_line_segment",command)
		if line.size() != 2 or not line[0] is Vector2 or not line[1] is Vector2: return {}
		var distance: float = Vector2(line[0]).distance_to(line[1])
		if distance <= .001: return {}
		at = line[1]
		direction = Vector2(line[0]).direction_to(line[1])
		rotation = direction.angle()
		width = minf(64,distance)
		id = "spear_impact"
	elif caster == "B07-M02" and shape == "circle":
		if ability == "B07-M02:camouflage_leap" and kind == "charge" and bool(command.get("landing_only",false)):
			id = "sand_landing"
			width = minf(96,float(command.get("radius",0))*1.65)
		elif ability == "B07-M02:camouflage_leap:follow" and kind == "ground_area" and bool(command.get("lob",false)):
			# The implemented sand ball is a delayed ground impact, not a
			# travelling projectile. Do not invent a launch path or flight time.
			id = "sand_ball"
			width = minf(34,float(command.get("radius",0))*.68)
			rotation = direction.angle()
	if id.is_empty() or width <= 0 or not at.is_finite() or not direction.is_finite(): return {}
	return {"id":id,"position":at,"direction":direction,"rotation":rotation,"width":width}

static func projectile_spec(canvas: Node2D, command: Dictionary, reduced: bool = false) -> Dictionary:
	if reduced or not enabled(canvas) or not bool(command.get("b07_command",false)): return {}
	if str(command.get("caster_enemy_id","")) != "B07-M03" or str(command.get("kind","")) != "projectile": return {}
	if str(command.get("ability_id","")) not in ["B07-M03:returning_disc","B07-M03:returning_disc:follow"]: return {}
	if not command.get("position") is Vector2 or not command.get("direction") is Vector2: return {}
	var at: Vector2 = command.position
	var direction: Vector2 = command.direction
	if not at.is_finite() or not direction.is_finite() or direction.is_zero_approx(): return {}
	# Keep the floor-aligned disc level. The existing trail and a small arrow
	# use the actual shot direction, including the separately warned return.
	return {"id":"sand_disc","position":at,"direction":direction,"rotation":0.0,"width":clampf(float(command.get("radius",11))*2.6,12,36)}

static func draw_effect(canvas: Node2D, command: Dictionary, reduced: bool) -> bool:
	return _draw_frame(canvas,effect_spec(canvas,command,reduced))

static func draw_projectile(canvas: Node2D, command: Dictionary, reduced: bool) -> bool:
	var spec := projectile_spec(canvas,command,reduced)
	if not _draw_frame(canvas,spec): return false
	var at: Vector2 = spec.position
	var direction: Vector2 = Vector2(spec.direction).normalized()
	var tip := at+direction*5
	var back := tip-direction*7
	canvas.draw_polyline(PackedVector2Array([back+direction.orthogonal()*3,tip,back-direction.orthogonal()*3]),Color("fff5d7"),1.5,true)
	return true

static func _draw_frame(canvas: Node2D, spec: Dictionary) -> bool:
	if spec.is_empty(): return false
	var texture := Sampler.sampled(ROOT+str(spec.id)+"/effect_candidate.png")
	if texture == null: return false # Keep the existing procedural fallback.
	var frame: Dictionary = FRAMES[spec.id]
	var region: Rect2 = frame.region
	if not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return false
	var factor: float = float(spec.width)/region.size.x
	var rect := Rect2((region.position-Vector2(frame.anchor))*factor,region.size*factor)
	canvas.draw_set_transform(spec.position,float(spec.rotation))
	canvas.draw_texture_rect_region(texture,rect,region,Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO)
	return true
