class_name HeroVisual
extends RefCounted
## Authored ImageGen characters are the production body layer. The original
## geometry is a missing-asset fallback only. Presentation never drives combat.

const INK := Color("111b20")
const METAL := Color("607078")
const ORANGE := Color("c87535")
const IVORY := Color("e4d7bb")
const TEAL := Color("69cecb")
const GENERATED_HEIGHT := 88.0
const FOOT_OFFSET := 8.0
const WalkAtlas = preload("res://scripts/combat/hero_walk_atlas.gd")
const BasicAtlas = preload("res://scripts/combat/hero_basic_atlas.gd")
const SkillAtlas = preload("res://scripts/combat/hero_skill_atlas.gd")
const ArtFamily = preload("res://scripts/combat/hero_art_family.gd")
const STRIDE_PER_WORLD_UNIT := .12
static var _generated_assets: Dictionary = {}
static var _action_banks: Dictionary = {}

static func _action_bank(hero: String, bank: String) -> Dictionary:
	var replacement: String = ArtFamily.metadata_path(hero,"actions",bank)
	var metadata_path: String = replacement if not replacement.is_empty() else "res://assets/generated/heroes/%s_actions_%s_v2.json" % [hero,bank]
	if _action_banks.has(metadata_path):
		return _action_banks[metadata_path]
	if not FileAccess.file_exists(metadata_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary or not parsed.get("frames",[]) is Array:
		return {}
	var data: Dictionary = parsed
	var path: String = str(data.get("texture","res://assets/generated/heroes/%s_actions_%s_v2.png" % [hero,bank]))
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(path)
	if source == null or source.is_empty():
		return {}
	if not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	elif texture == null:
		texture = ImageTexture.create_from_image(source)
	var standard_height: float = maxf(1.0,float(data.get("body_height",source.get_height()*.36)))
	var frames: Dictionary = {}
	for frame_index in data.frames.size():
		var item: Dictionary = data.frames[frame_index]
		var raw: Array = item.get("region",item.get("cell",[]))
		var foot: Array = item.get("foot",[])
		if raw.size() != 4 or foot.size() != 2:
			continue
		var region := Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
		if not Rect2(Vector2.ZERO,texture.get_size()).encloses(region) or region.size.x <= 0 or region.size.y <= 0:
			continue
		var scale_value: float = GENERATED_HEIGHT/standard_height
		var anchor := Vector2(float(foot[0]),float(foot[1]))
		var bounds := Rect2((region.position-anchor)*scale_value+Vector2(0,FOOT_OFFSET),region.size*scale_value)
		var anchors: Dictionary = {"foot":Vector2(0,FOOT_OFFSET)}
		for label: String in ["head","grip","muzzle","core","left_hand","right_hand"]:
			var point: Array = item.get(label,[])
			if point.size() == 2:
				anchors[label] = (Vector2(float(point[0]),float(point[1]))-anchor)*scale_value+Vector2(0,FOOT_OFFSET)
		frames[str(item.get("name","idle"))] = {"texture":texture,"path":path,"region":region,"bounds":bounds,"anchors":anchors,"bank":bank,"phase":str(item.get("name","idle")),"frame_index":frame_index,"body_height":GENERATED_HEIGHT,"source_body_height":standard_height,"facing_x":-1 if int(data.get("facing_x",1)) < 0 else 1,"art_family":"storybook" if not replacement.is_empty() else "original"}
	if not frames.has("idle") or not frames.has("windup") or not frames.has("release") or not frames.has("recovery"):
		return {}
	_action_banks[metadata_path] = frames
	return frames

static func action_frame_info(hero: String, bank: String = "front", phase: String = "idle") -> Dictionary:
	var frames: Dictionary = _action_bank(hero,bank)
	return frames.get(phase,frames.get("idle",{})).duplicate()

static func walk_frame_info(hero: String, bank: String = "front", distance: float = 0.0) -> Dictionary:
	return WalkAtlas.frame_info(hero,bank,distance)

static func basic_frame_info(hero: String, bank: String, phase: String, progress: float) -> Dictionary:
	return BasicAtlas.frame_info(hero,bank,phase,progress)

## The available gunner sheets have two facing banks, not an articulated weapon
## or eight aim directions. Reuse their shouldered poses without rotating the
## whole body: the original fire/ready cells throw the head back/lower the rifle.
static func gunner_shooting_frame(bank: String, pose: Dictionary) -> Dictionary:
	var slot: String = str(pose.get("slot", ""))
	var phase: String = str(pose.get("phase", "idle"))
	if slot not in ["basic", "q", "secondary", "ultimate"] or phase not in ["windup", "release", "recovery"] or bank not in ["front", "back"]:
		return {}
	var progress: float = float(pose.get("authored_phase_progress",pose.get("progress",0.0)))
	if not is_finite(progress):
		return {}
	var clip: Dictionary = SkillAtlas.load_clip("res://assets/generated/heroes/CH02_secondary_%s_v1.json" % bank)
	if str(clip.get("hero_id","")) != "CH02" or str(clip.get("slot","")) != "secondary" or str(clip.get("bank","")) != bank:
		return {}
	var name: String = "lock"
	if phase == "windup" and slot in ["basic", "secondary"] and progress < 0.5:
		name = "brace"
	elif phase == "recovery":
		name = "absorb"
	var frame: Dictionary = clip.frames.get(name,{}).duplicate(true)
	if frame.is_empty():
		return {}
	# Keep the six-source-frame atlas contract intact. This presentation mapping
	# deliberately plays only stable shoulder poses, not a six-frame firing clip.
	frame["phase"] = phase
	frame["phase_progress"] = clampf(progress,0.0,1.0)
	frame["source_slot"] = "secondary"
	frame["slot"] = slot
	frame["skill_sequence"] = true
	frame["gun_shooting_pose"] = true
	frame["gun_recoil"] = 1.6 if slot == "secondary" else 0.7
	return frame

## Basic feedback ends at 290 ms; the real weapon cooldown can last longer.
## Keep the rifle shouldered through that existing cooldown, including the gap
## before the next held shot. This owns no timer and cannot fire or extend a cast.
static func gunner_presentation_pose(p: Node2D, pose: Dictionary) -> Dictionary:
	if p.hero_id() != "CH02":
		return pose
	var feedback: Node = p.get_node_or_null("HeroFeedback")
	# A finished skill leaves a short feedback tail. A subsequent real basic
	# release must use its own contact frame/anchor even while that tail exists.
	# Read the recorded visual age; never infer a shot from stale shot/shots fields.
	if is_instance_valid(feedback) and p.abilities != null and not p.abilities.busy() and str(feedback.get("_basic")) == "attack_strike":
		var age: float = float(feedback.get("_basic_age"))
		if age < 0.29:
			var basic: Dictionary = pose.duplicate()
			basic.merge({"slot":"basic", "phase":"release" if age < 0.09 else "recovery",
				"progress":clampf(age/0.09 if age < 0.09 else (age-0.09)/0.20,0.0,1.0),
				"direction":feedback.get("_shot_direction")},true)
			basic.erase("authored_phase_progress")
			return basic
	if str(pose.get("phase", "idle")) != "idle" or float(p.shot_cooldown) <= 0.0:
		return pose
	var held: Dictionary = pose.duplicate()
	held.merge({"phase":"recovery", "slot":"basic", "progress":1.0, "authored_phase_progress":1.0,
		"direction":p.aim_direction, "gun_hold":true},true)
	return held

static func presentation_frame_info(hero: String, bank: String, pose: Dictionary, stride: float, walking: bool, dash: bool = false) -> Dictionary:
	var phase: String = str(pose.get("phase", "idle"))
	if hero == "CH02" and not dash:
		var gun: Dictionary = gunner_shooting_frame(bank,pose)
		if not gun.is_empty():
			return gun
	if phase != "idle" and not dash:
		var skill: Dictionary = SkillAtlas.frame_info(hero,str(pose.get("slot", "")),bank,phase,float(pose.get("authored_phase_progress",pose.get("progress",0.0))))
		if not skill.is_empty():
			return skill
	if hero == "CH01" and str(pose.get("slot", "")) == "basic" and phase != "idle" and not dash:
		var basic: Dictionary = basic_frame_info(hero,bank,phase,float(pose.get("progress",0.0)))
		if not basic.is_empty():
			return basic
	return motion_frame_info(hero,bank,phase,stride,walking,dash)

## Frozen launch-point sampling, independent of the previous rendered idle pose.
## Projectiles use this display anchor without moving their physical origin.
static func release_muzzle_local(hero: String, slot: String, direction: Vector2) -> Vector2:
	var aim: Vector2 = direction.normalized() if direction.is_finite() and direction.length_squared() > 0.001 else Vector2.RIGHT
	var bank: String = "back" if aim.y < -0.20 else "front"
	var pose: Dictionary = {"phase":"release","slot":slot,"progress":0.0,"authored_phase_progress":0.0}
	var asset: Dictionary = presentation_frame_info(hero,bank,pose,0.0,false)
	if asset.is_empty():
		return aim * 36.0 + Vector2(0,-20)
	var flip: float = source_horizontal_flip(aim,asset)
	var muzzle: Vector2 = asset.anchors.get("muzzle",asset.anchors.get("right_hand",Vector2(26,-28)))
	# Match the old basic-strike lean; authored sequences carry their own recoil.
	var lean: Vector2 = aim * (5.0 if hero == "CH01" else 1.5) if slot == "basic" else Vector2.ZERO
	return _action_offset(asset,hero,aim,lean,pose) + muzzle * Vector2(flip,1.0)

## A generated rear view can face left even when the front view faces right.
## Compose its authored orientation with the requested aim; anchors follow the
## exact same transform as the pixels instead of assuming every source is SE.
static func source_horizontal_flip(aim: Vector2, asset: Dictionary) -> float:
	return (-1.0 if aim.x < -.05 else 1.0) * (-1.0 if int(asset.get("facing_x",1)) < 0 else 1.0)

static func _action_offset(asset: Dictionary, hero: String, aim: Vector2, lean: Vector2, pose: Dictionary) -> Vector2:
	if bool(asset.get("gun_shooting_pose",false)):
		# The stock and shoulder remain one authored pose. A sub-two-pixel recoil
		# translates them together; body draw and projectile launch share this path.
		return -aim * float(asset.gun_recoil) * (1.0-clampf(float(pose.get("progress",0.0)),0.0,1.0)) if str(pose.phase) == "release" else Vector2.ZERO
	var authored_motion: bool = str(asset.phase) == "walk" or bool(asset.get("basic_sequence",false)) or bool(asset.get("skill_sequence",false)) or str(asset.get("path","")).contains("CH01_storybook_")
	var offset: Vector2 = Vector2.ZERO if authored_motion else lean
	if str(pose.phase) == "release" and not authored_motion:
		offset += aim * (2.5 if hero == "CH01" else -3.8 if hero == "CH02" else 1.6) * (1.0 - clampf(float(pose.progress),0.0,1.0))
	return offset

static func motion_frame_info(hero: String, bank: String, pose_phase: String, stride: float, walking: bool, dash: bool = false) -> Dictionary:
	# Player.stride is accumulated collision-resolved travel multiplied by .12.
	# A stride angle/TAU cycle would run almost three times too fast here.
	if pose_phase == "idle" and walking and not dash:
		var walk: Dictionary = walk_frame_info(hero,bank,stride/STRIDE_PER_WORLD_UNIT)
		if not walk.is_empty():
			return walk
	return action_frame_info(hero,bank,pose_phase)

static func _walk_is_moving(p: Node2D, stride: float, velocity: Vector2) -> bool:
	# Requested velocity remains nonzero against walls. Observe resolved travel
	# once per physics frame so blocked input returns to idle without foot skating.
	var frame: int = Engine.get_physics_frames()
	var previous: Dictionary = p.get_meta("_hero_visual_motion",{})
	var walking: bool = velocity.length_squared() > 4.0
	if not previous.is_empty():
		if frame != int(previous.frame) or not is_equal_approx(stride,float(previous.stride)):
			walking = walking and stride > float(previous.stride)+.00001
		else:
			walking = walking and bool(previous.walking)
	else:
		walking = walking and stride > .00001
	p.set_meta("_hero_visual_motion",{"frame":frame,"stride":stride,"walking":walking})
	return walking


static func _generated_asset(hero: String) -> Dictionary:
	var path := ""
	for variant: String in ["combat", "portrait"]:
		var candidate: String = "res://assets/generated/heroes/%s_%s_v1.png" % [hero, variant]
		if ResourceLoader.exists(candidate) or FileAccess.file_exists(candidate):
			path = candidate
			break
	if path.is_empty():
		return {}
	if _generated_assets.has(path):
		return _generated_assets[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		var source_image: Image = Image.load_from_file(path)
		if source_image == null or source_image.is_empty():
			return {}
		source_image.generate_mipmaps()
		texture = ImageTexture.create_from_image(source_image)
	if texture == null:
		return {}
	var source: Image = texture.get_image()
	var region: Rect2 = _visible_region(source) if source != null else Rect2(Vector2.ZERO, texture.get_size())
	if region.size.y < 1.0:
		return {}
	# Portrait source art is much larger than its battlefield footprint. Mipmaps
	# keep the original detail from turning into flickering bright speckles.
	if source != null and not source.has_mipmaps():
		source.generate_mipmaps()
		texture = ImageTexture.create_from_image(source)
	var width: float = region.size.x / region.size.y * GENERATED_HEIGHT
	var bounds := Rect2(Vector2(-width * .5, FOOT_OFFSET - GENERATED_HEIGHT), Vector2(width, GENERATED_HEIGHT))
	var result := {"texture":texture,"region":region,"bounds":bounds,"path":path}
	_generated_assets[path] = result
	return result


static func _visible_region(source: Image) -> Rect2:
	# Almost-transparent export speckles must not count as body height. Only the
	# source sampling rectangle changes; the original pixels/alpha stay intact.
	var rgba: Image = source
	if source.get_format() != Image.FORMAT_RGBA8:
		rgba = source.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = rgba.get_data()
	var width: int = rgba.get_width()
	var height: int = rgba.get_height()
	var min_x: int = width
	var min_y: int = height
	var max_x: int = -1
	var max_y: int = -1
	for y in height:
		var row: int = y * width * 4 + 3
		for x in width:
			if bytes[row + x * 4] > 16:
				min_x = mini(min_x,x)
				max_x = maxi(max_x,x)
				min_y = mini(min_y,y)
				max_y = maxi(max_y,y)
	if max_x < min_x:
		return Rect2()
	return Rect2(min_x,min_y,max_x-min_x+1,max_y-min_y+1)


static func asset_path(hero: String) -> String:
	var frame: Dictionary = action_frame_info(hero)
	if not frame.is_empty():
		return str(frame.path)
	return str(_generated_asset(hero).get("path", ""))


static func asset_bounds(hero: String) -> Rect2:
	var frame: Dictionary = action_frame_info(hero)
	if not frame.is_empty():
		return frame.bounds
	return _generated_asset(hero).get("bounds", Rect2())


static func draw_hero(p: Node2D) -> void:
	var hero := str(p.call("hero_id"))
	var aim: Vector2 = p.get("aim_direction")
	if aim.length_squared() < 0.01:
		aim = Vector2.RIGHT
	else:
		aim = aim.normalized()
	var velocity: Vector2 = p.get("velocity")
	var state := str(p.get("visual_state")).trim_prefix("cast_").trim_prefix("release_")
	var remaining := float(p.get("visual_remaining"))
	var duration := maxf(0.001, float(p.get("visual_duration")))
	var progress := clampf(1.0 - remaining / duration, 0.0, 1.0)
	var stride := float(p.get("stride"))
	var walking := _walk_is_moving(p,stride,velocity)
	var step := sin(stride) * (1.0 if walking else 0.0)
	var hurt := clampf(float(p.get("hurt_flash")) * 7.0, 0.0, 0.72)
	var dash := float(p.get("dash_remaining")) > 0.0 or state == "dash"
	var bob := absf(step) * (1.5 if hero == "CH01" else 2.4)
	var lean := Vector2(velocity.x * 0.007 if walking else 0.0, -bob)
	if state == "attack_windup":
		lean -= aim * progress * (4.0 if hero == "CH01" else 1.5)
	elif state == "attack_strike":
		lean += aim * (1.0 - progress) * (5.0 if hero == "CH01" else 1.5)
	if dash:
		_draw_dash(p, hero, velocity, aim)
	var feedback: Node = p.get_node_or_null("HeroFeedback")
	var pose: Dictionary = feedback.pose_state() if is_instance_valid(feedback) else {"phase":"idle","progress":0.0,"direction":aim,"slot":"basic"}
	pose = gunner_presentation_pose(p,pose)
	var pose_aim: Vector2 = pose.get("direction",aim)
	if pose_aim.length_squared() > .01:
		aim = pose_aim.normalized()
	var bank: String = "back" if aim.y < -.20 else "front"
	var motion_frame: Dictionary = presentation_frame_info(hero,bank,pose,stride,walking,dash)
	if not motion_frame.is_empty():
		p.set_meta("hero_visual_source",motion_frame.path)
		p.set_meta("hero_visual_pose",str(motion_frame.phase))
		p.set_meta("hero_visual_bank",bank)
		p.set_meta("hero_visual_frame",int(motion_frame.get("frame_index",-1)))
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_draw_action_frame(p,motion_frame,hero,aim,lean,pose,hurt)
		_draw_protection(p)
		return
	var generated: Dictionary = _generated_asset(hero)
	if not generated.is_empty():
		p.set_meta("hero_visual_source", generated.path)
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_draw_generated(p, generated, hero, aim, lean, step, state, progress, hurt)
		_draw_protection(p)
		return
	p.set_meta("hero_visual_source", "geometry_fallback")
	_draw_shadow(p, hero)
	_draw_feet(p, hero, step, aim, hurt)
	if hero == "CH01" and state == "attack_strike":
		_draw_melee_arc(p, aim, progress)
	p.draw_set_transform(lean)
	match hero:
		"CH02":
			_draw_scout(p, aim, state, progress, hurt)
		"CH03":
			_draw_resonator(p, aim, state, progress, hurt)
		_:
			_draw_breaker(p, aim, state, progress, hurt)
	p.draw_set_transform(Vector2.ZERO)
	_draw_protection(p)
	if float(p.get("visual_hitstop")) > 0.0:
		# A short pressure mark at the weapon, never a screen-wide flash.
		var at := aim * (63.0 if hero == "CH01" else 43.0) + lean
		p.draw_line(at - aim.orthogonal() * 5.0, at + aim.orthogonal() * 5.0, IVORY, 2.0, true)

static func _draw_action_frame(p: Node2D, asset: Dictionary, hero: String, aim: Vector2, lean: Vector2, pose: Dictionary, hurt: float) -> void:
	var shadow_width: float = 23.0 if hero == "CH01" else 18.0
	p.draw_set_transform(Vector2(0,FOOT_OFFSET),0.0,Vector2(shadow_width/12.0,.48))
	var shadow_color := Color(.24,.25,.34,.28) if str(asset.get("path","")).contains("CH01_storybook_") else Color(.012,.02,.023,.64)
	p.draw_circle(Vector2.ZERO,12.0,shadow_color)
	p.draw_set_transform(Vector2.ZERO)
	var flip: float = source_horizontal_flip(aim,asset)
	p.set_meta("hero_visual_flip",flip)
	# Authored walking and basic swings carry their own body weight. Registered
	# feet must not receive the old whole-image bob/lean or release translation.
	var offset: Vector2 = _action_offset(asset,hero,aim,lean,pose)
	# The atlas contains real torso/limb/weapon poses. Only tiny translation
	# adds recoil; no whole-image aiming rotation or second weapon is layered on.
	p.draw_set_transform(offset,0.0,Vector2(flip,1.0))
	var modulation := Color(1.0+hurt*.45,1.0-hurt*.2,1.0-hurt*.3,1.0)
	p.draw_texture_rect_region(asset.texture,asset.bounds,asset.region,modulation)
	p.draw_set_transform(Vector2.ZERO)
	var muzzle: Vector2 = asset.anchors.get("muzzle",asset.anchors.get("right_hand",Vector2(26,-28)))
	var grip: Vector2 = asset.anchors.get("grip",Vector2(15,-26))
	p.set_meta("hero_muzzle_local",offset+muzzle*Vector2(flip,1.0))
	p.set_meta("hero_grip_local",offset+grip*Vector2(flip,1.0))
	p.set_meta("hero_foot_local",Vector2(0,FOOT_OFFSET))
	var tint: Color = ORANGE if hero == "CH01" else IVORY if hero == "CH02" else TEAL
	var marker: Vector2 = aim*30
	p.draw_polyline(PackedVector2Array([marker-aim*5+aim.orthogonal()*3.5,marker,marker-aim*5-aim.orthogonal()*3.5]),Color(tint,.62),1.2,true)


static func _draw_generated(p: Node2D, asset: Dictionary, hero: String, aim: Vector2, lean: Vector2, step: float, state: String, progress: float, hurt: float) -> void:
	# Feet are grounded near the existing actor/collision origin; image scaling
	# and this contact shadow do not alter any attack radius or physical shape.
	var shadow_width: float = 23.0 if hero == "CH01" else 18.0
	p.draw_set_transform(Vector2(0, FOOT_OFFSET), 0.0, Vector2(shadow_width / 12.0, .48))
	p.draw_circle(Vector2.ZERO, 12.0, Color(0.012,0.02,0.023,.64))
	p.draw_set_transform(Vector2.ZERO)
	var direction_tint: Color = ORANGE if hero == "CH01" else (IVORY if hero == "CH02" else TEAL)
	# A small ground-facing marker tells the actual attack direction even though
	# this initial single image has no independently articulated weapon layer.
	var marker: Vector2 = aim * 31.0
	p.draw_polyline(PackedVector2Array([marker-aim*5.0+aim.orthogonal()*4.0,marker,marker-aim*5.0-aim.orthogonal()*4.0]),Color(direction_tint,.78),1.5,true)
	if hero == "CH01" and state == "attack_strike":
		_draw_melee_arc(p, aim, progress)
	var squash := Vector2.ONE
	if state == "attack_windup":
		squash = Vector2(1.0 + progress * .035, 1.0 - progress * .05)
	elif state in ["attack_strike", "attack_recoil"]:
		squash = Vector2(1.0 - (1.0-progress)*.025, 1.0 + (1.0-progress)*.035)
	var flip: float = -1.0 if aim.x < -0.05 else 1.0
	p.draw_set_transform(lean, step * .018, squash * Vector2(flip,1.0))
	var modulation := Color(1.0 + hurt*.45,1.0-hurt*.2,1.0-hurt*.3,1.0)
	p.draw_texture_rect_region(asset.texture,asset.bounds,asset.region,modulation)
	p.draw_set_transform(Vector2.ZERO)
	var muzzle: float = float(p.get("muzzle_flash"))
	if muzzle > 0.0:
		var flash: Vector2 = aim * 39.0 + Vector2(0,-12)
		p.draw_circle(flash,4.0,Color(direction_tint,.85))
		p.draw_line(flash,flash+aim*14.0,IVORY,2.0,true)
	if state in ["q", "secondary", "f", "ultimate"]:
		p.draw_arc(Vector2.ZERO,27.0+sin(progress*PI)*7.0,aim.angle()-.9,aim.angle()+.9,18,Color(direction_tint,.7),2.0,true)
	if float(p.get("visual_hitstop")) > 0.0:
		var at: Vector2 = aim * (63.0 if hero == "CH01" else 43.0)
		p.draw_line(at-aim.orthogonal()*5.0,at+aim.orthogonal()*5.0,IVORY,2.0,true)


static func _draw_shadow(p: Node2D, hero: String) -> void:
	var width := 27.0 if hero == "CH01" else 20.0
	p.draw_set_transform(Vector2(0, 21), 0.0, Vector2(width / 12.0, 0.52))
	p.draw_circle(Vector2.ZERO, 12.0, Color(0.015, 0.027, 0.035, 0.45))
	p.draw_set_transform(Vector2.ZERO)


static func _draw_feet(p: Node2D, hero: String, step: float, aim: Vector2, hurt: float) -> void:
	var spacing := 11.0 if hero == "CH01" else 7.5
	var travel := 4.5 if hero == "CH01" else 6.0
	var boot := Color("394447") if hero == "CH01" else Color("294947")
	if hero == "CH03":
		boot = Color("4b443d")
	for side in [-1.0, 1.0]:
		var ankle := Vector2(side * spacing, 17.0 + step * side * travel)
		var toe := ankle + Vector2(aim.x * 4.0, 8.0 + maxf(0.0, aim.y) * 2.0)
		p.draw_line(ankle - Vector2(0, 5), toe, INK, 11.0, true)
		p.draw_line(ankle - Vector2(0, 5), toe, _tint(boot, hurt), 7.0, true)
		p.draw_line(toe - Vector2(3, 1), toe + Vector2(3, 1), Color("a69f85"), 2.0, true)
		if hero == "CH02":
			p.draw_line(ankle - Vector2(1, 4), ankle + Vector2(1, 2), IVORY, 3.0, true)


static func _draw_breaker(p: Node2D, aim: Vector2, state: String, progress: float, hurt: float) -> void:
	var body := _tint(Color("252b2d"), hurt)
	var plate := _tint(ORANGE, hurt)
	# Squat twin pressure tanks and a left shoulder slab remain asymmetric.
	_poly(p, [Vector2(-19, -17), Vector2(16, -17), Vector2(19, 11), Vector2(-19, 13)], Color("46504d"))
	for x in [-10.0, 8.0]:
		p.draw_line(Vector2(x, -14), Vector2(x, 9), INK, 11.0, true)
		p.draw_line(Vector2(x, -14), Vector2(x, 9), Color("737568"), 7.0, true)
	_poly(p, [Vector2(-19, -16), Vector2(16, -15), Vector2(21, 10), Vector2(13, 20), Vector2(-16, 18), Vector2(-23, 4)], body)
	_poly(p, [Vector2(-22, -19), Vector2(-5, -20), Vector2(-3, -3), Vector2(-24, 0), Vector2(-28, -8)], plate)
	p.draw_line(Vector2(-22, -14), Vector2(-9, -15), IVORY.darkened(0.2), 2.0, true)
	for rivet in [Vector2(-21, -5), Vector2(-8, -6)]:
		p.draw_circle(rivet, 1.7, INK)
	_poly(p, [Vector2(-12, 0), Vector2(10, -2), Vector2(13, 12), Vector2(-13, 13)], _tint(Color("725c47"), hurt))
	p.draw_line(Vector2(-13, 11), Vector2(15, 10), METAL, 4.0, true)
	p.draw_rect(Rect2(-3, 8, 7, 6), ORANGE)
	_draw_head(p, aim, Vector2(0, -21), 11.5, _tint(Color("777764"), hurt), IVORY, true)
	# The exposed piston arm and hammer track the actual attack sector.
	var weapon_angle := aim.angle() + 0.38
	var reach := 43.0
	if state == "attack_windup":
		weapon_angle = aim.angle() - lerpf(0.38, deg_to_rad(50), progress)
		reach = lerpf(43.0, 77.0, progress)
	elif state == "attack_strike":
		weapon_angle = aim.angle() + lerpf(deg_to_rad(-50), deg_to_rad(50), progress)
		reach = 85.0
	elif state in ["attack_recovery", "attack_recoil"]:
		weapon_angle = aim.angle() + lerpf(deg_to_rad(50), 0.38, progress)
		reach = lerpf(85.0, 43.0, progress)
	elif state == "secondary":
		weapon_angle = aim.angle() + lerpf(-1.1, 1.1, progress)
		reach = 76.0
	elif state == "ultimate":
		weapon_angle = aim.angle() - sin(progress * PI) * 1.1
		reach = 45.0 + sin(progress * PI) * 21.0
	elif state == "q":
		weapon_angle = aim.angle()
		reach = 52.0
	var direction := Vector2.from_angle(weapon_angle)
	var elbow := Vector2(15, -2) + direction * 8.0
	var grip := direction * (reach - 23.0)
	p.draw_line(Vector2(15, -8), elbow, INK, 12.0, true)
	p.draw_line(Vector2(15, -8), elbow, plate, 8.0, true)
	p.draw_line(elbow, grip, INK, 10.0, true)
	p.draw_line(elbow, grip, METAL.lightened(0.17), 5.0, true)
	p.draw_circle(grip, 4.5, _tint(Color("8b795c"), hurt))
	p.draw_line(direction * 15.0, direction * reach, INK, 7.0, true)
	p.draw_line(direction * 15.0, direction * reach, Color("9c9680"), 3.5, true)
	var perpendicular := direction.orthogonal()
	_poly(p, [direction * (reach - 9) - perpendicular * 17, direction * (reach + 11) - perpendicular * 17,
		direction * (reach + 15) + perpendicular * 15, direction * (reach - 9) + perpendicular * 15], plate)
	p.draw_line(direction * (reach + 11) - perpendicular * 12, direction * (reach + 13) + perpendicular * 11, IVORY, 3.0, true)
	var count := int(p.get("passive_count"))
	for i in range(3):
		var pos := direction * (reach - 1) + perpendicular * float(i - 1) * 8.0
		p.draw_circle(pos, 3.0, INK)
		p.draw_circle(pos, 1.7, Color("f0c77d") if i < count else Color("5c4d3c"))


static func _draw_scout(p: Node2D, aim: Vector2, state: String, progress: float, hurt: float) -> void:
	var olive := _tint(Color("72785e"), hurt)
	var dark := _tint(Color("294947"), hurt)
	# A short single-sided survey cape and a tall measuring needle.
	_poly(p, [Vector2(-10, -21), Vector2(-21, -11), Vector2(-23, 15), Vector2(-12, 9), Vector2(-5, -3)], olive)
	p.draw_line(Vector2(-18, -20), Vector2(-18, -36), INK, 4.0, true)
	p.draw_line(Vector2(-18, -20), Vector2(-18, -36), IVORY, 1.5, true)
	p.draw_line(Vector2(-21, -30), Vector2(-14, -30), ORANGE, 2.0, true)
	_poly(p, [Vector2(-11, -15), Vector2(10, -16), Vector2(15, -1), Vector2(9, 17), Vector2(-9, 17), Vector2(-14, 0)], dark)
	_poly(p, [Vector2(-8, -11), Vector2(7, -11), Vector2(8, 7), Vector2(-6, 8)], olive)
	p.draw_line(Vector2(-9, -10), Vector2(10, 11), _tint(IVORY, hurt), 3.5, true)
	p.draw_rect(Rect2(-9, 10, 17, 4), Color("8c7856"))
	p.draw_circle(Vector2(-12, 7), 5, INK)
	p.draw_arc(Vector2(-12, 7), 3.0, -0.5, 4.8, 12, Color("baac7c"), 1.5, true)
	_draw_head(p, aim, Vector2(0, -22), 9.0, olive, Color("ddd3b9"), false)
	var recoil := clampf(float(p.get("muzzle_flash")) * 45.0, 0.0, 5.0)
	var extension := 0.0
	if state == "secondary" or state == "ultimate":
		extension = sin(progress * PI) * 7.0
	var gun_origin := aim * (10.0 - recoil)
	_draw_aiming_arms(p, aim, gun_origin, dark, IVORY.darkened(0.23))
	var angle := aim.angle()
	var original_transform: Vector2 = p.get("velocity")
	var bob := absf(sin(float(p.get("stride")))) * (2.4 if original_transform.length_squared() > 4.0 else 0.0)
	# Keep the parent body offset when rotating the independently aimed weapon.
	var lean := Vector2(original_transform.x * 0.007, -bob)
	if state == "attack_windup":
		lean -= aim * progress * 1.5
	elif state == "attack_strike":
		lean += aim * (1.0 - progress) * 1.5
	p.draw_set_transform(lean + gun_origin, angle)
	_poly(p, [Vector2(-12, -7), Vector2(-1, -2), Vector2(-12, 7)], olive)
	_poly(p, [Vector2(-1, -5), Vector2(24 + extension, -5), Vector2(30 + extension, -2), Vector2(30 + extension, 3), Vector2(0, 5)], Color("ddd3b9"))
	p.draw_line(Vector2(7, -1), Vector2(35 + extension, -1), INK, 3.0, true)
	p.draw_line(Vector2(8, -8), Vector2(26 + extension, -8), ORANGE, 2.0, true)
	for tick in range(4):
		p.draw_line(Vector2(10 + tick * 4, -8), Vector2(10 + tick * 4, -5), INK, 1.0, true)
	if float(p.get("muzzle_flash")) > 0.0:
		_poly(p, [Vector2(35 + extension, -4), Vector2(49 + extension, -1), Vector2(35 + extension, 2)], Color("f8e5b0"), Color.TRANSPARENT)
	p.draw_set_transform(lean)
	# Two engraved route chevrons, with the ready indication confined to the cape.
	var ready := int(p.get("passive_count")) > 0
	var mark := Color("f0d485") if ready else Color("bbb298")
	p.draw_polyline(PackedVector2Array([Vector2(-19, 2), Vector2(-16, 5), Vector2(-19, 8)]), mark, 1.5, true)


static func _draw_resonator(p: Node2D, aim: Vector2, state: String, progress: float, hurt: float) -> void:
	var white := _tint(Color("d2d1bb"), hurt)
	var brown := _tint(Color("4b443d"), hurt)
	var blue := _tint(Color("3e8d8d"), hurt)
	# Offset receiver dish and four unequal-height capacitor canisters.
	p.draw_circle(Vector2(-21, -15), 11.0, INK)
	p.draw_circle(Vector2(-21, -15), 8.0, white.darkened(0.25))
	p.draw_arc(Vector2(-21, -15), 5.0, -2.7, 1.1, 18, blue, 2.0, true)
	p.draw_line(Vector2(-22, -15), Vector2(-28, -24), IVORY, 2.0, true)
	p.draw_circle(Vector2(-28, -24), 2.0, TEAL)
	var count := int(p.get("passive_count"))
	for i in range(4):
		var x := -13.0 + i * 8.0
		var y := -23.0 - float(i % 2) * 5.0
		p.draw_line(Vector2(x, y), Vector2(x, 3), INK, 7.0, true)
		p.draw_line(Vector2(x, y), Vector2(x, 2), Color("8c9b93"), 4.0, true)
		p.draw_line(Vector2(x, y + 2), Vector2(x, y + 7), TEAL if i < count else Color("355558"), 3.0, true)
	_poly(p, [Vector2(-12, -12), Vector2(12, -11), Vector2(16, 6), Vector2(8, 18), Vector2(-13, 16), Vector2(-17, 1)], brown)
	_poly(p, [Vector2(-11, -10), Vector2(8, -11), Vector2(12, 7), Vector2(5, 10), Vector2(-11, 7)], white)
	p.draw_line(Vector2(-8, -8), Vector2(8, 7), blue, 4.0, true)
	p.draw_circle(Vector2(-6, 4), 4.0, INK)
	p.draw_circle(Vector2(-6, 4), 2.0, TEAL)
	p.draw_rect(Rect2(-11, 11, 24, 4), blue.darkened(0.3))
	_draw_head(p, aim, Vector2(1, -22), 9.5, white, TEAL, false)
	p.draw_circle(Vector2(11, -23), 4.5, INK)
	p.draw_circle(Vector2(11, -23), 2.5, blue)
	var recoil := clampf(float(p.get("muzzle_flash")) * 27.0, 0.0, 3.5)
	var origin := aim * (11.0 - recoil)
	_draw_aiming_arms(p, aim, origin, white, brown)
	var tip := origin + aim * 28.0
	var cross := aim.orthogonal()
	p.draw_polyline(PackedVector2Array([Vector2(-14, 4), Vector2(-20, 13), origin - aim * 3.0]), INK, 4.0, true)
	p.draw_polyline(PackedVector2Array([Vector2(-14, 4), Vector2(-20, 13), origin - aim * 3.0]), blue, 1.5, true)
	p.draw_line(origin - aim * 6.0, tip - aim * 6.0, INK, 8.0, true)
	p.draw_line(origin - aim * 5.0, tip - aim * 6.0, white, 4.0, true)
	for side in [-1.0, 1.0]:
		p.draw_line(tip - aim * 11.0, tip - aim * 5.0 + cross * side * 7.0, INK, 5.0, true)
		p.draw_line(tip - aim * 5.0 + cross * side * 7.0, tip + cross * side * 7.0, white, 3.0, true)
	var casting := state in ["q", "secondary", "f", "ultimate"]
	if casting or float(p.get("muzzle_flash")) > 0.0:
		var radius := 3.0 + sin(progress * PI) * 3.0 if casting else 3.0
		p.draw_circle(tip, radius, Color(0.41, 0.81, 0.8, 0.22))
		p.draw_line(tip - cross * 6, tip - aim * 3 + cross * 1, TEAL, 1.6, true)
		p.draw_line(tip - aim * 3 + cross * 1, tip + cross * 6, TEAL, 1.6, true)


static func _draw_head(p: Node2D, aim: Vector2, center: Vector2, radius: float, shell: Color, visor: Color, heavy: bool) -> void:
	# Face position follows aim while the equipment never mirrors across the body.
	p.draw_circle(center, radius + 1.8, INK)
	p.draw_circle(center, radius, shell)
	var face := center + Vector2(aim.x * 3.5, aim.y * 2.5)
	if aim.y < -0.45:
		p.draw_arc(center, radius - 3.0, -2.8, -0.3, 12, shell.darkened(0.34), 2.3, true)
		p.draw_line(center + Vector2(-4, 5), center + Vector2(4, 5), Color("7d8175"), 2.0, true)
	else:
		p.draw_line(face + Vector2(-6, -1), face + Vector2(6, -1), INK, 5.0, true)
		p.draw_line(face + Vector2(-4.5, -1), face + Vector2(4.5, -1), visor, 2.0, true)
		p.draw_line(face + Vector2(-3, 5), face + Vector2(3, 5), INK, 2.0, true)
	if heavy:
		p.draw_line(center + Vector2(-12, -7), center + Vector2(12, -7), INK, 4.0, true)
		p.draw_line(center + Vector2(-11, -8), center + Vector2(10, -8), ORANGE, 3.0, true)
	else:
		p.draw_line(center + Vector2(-6, -7), center + Vector2(3, -9), shell.lightened(0.2), 2.0, true)


static func _draw_aiming_arms(p: Node2D, aim: Vector2, origin: Vector2, sleeve: Color, glove: Color) -> void:
	var cross := aim.orthogonal()
	for side in [-1.0, 1.0]:
		var shoulder := Vector2(side * 11.0, -6.0)
		var elbow: Vector2 = origin + cross * side * 9.0
		var hand := origin + aim * (10.0 if side > 0.0 else 1.0)
		p.draw_line(shoulder, elbow, INK, 8.0, true)
		p.draw_line(shoulder, elbow, sleeve, 5.0, true)
		p.draw_line(elbow, hand, INK, 7.0, true)
		p.draw_line(elbow, hand, glove, 4.5, true)
		p.draw_circle(hand, 3.0, glove)


static func _draw_melee_arc(p: Node2D, aim: Vector2, progress: float) -> void:
	var angle := aim.angle()
	var half_angle := deg_to_rad(50.0)
	var opacity := lerpf(0.65, 0.16, progress)
	# Exactly the basic attack's 105 px / 100 degree envelope, not a 360-degree halo.
	p.draw_arc(Vector2.ZERO, 104.0, angle - half_angle, angle + half_angle, 22, Color(0.94, 0.65, 0.31, opacity), 2.0, true)
	var sweep := lerpf(angle - half_angle, angle + half_angle, progress)
	var tail := maxf(angle - half_angle, sweep - 0.58)
	p.draw_arc(Vector2.ZERO, 88.0, tail, sweep, 9, Color(0.92, 0.69, 0.39, opacity * 0.55), 8.0, true)
	p.draw_arc(Vector2.ZERO, 97.0, tail, sweep, 9, Color(0.99, 0.87, 0.64, opacity), 2.5, true)


static func _draw_dash(p: Node2D, hero: String, velocity: Vector2, aim: Vector2) -> void:
	var direction := velocity.normalized() if velocity.length_squared() > 1.0 else aim
	var tint := ORANGE if hero == "CH01" else (Color("cfca94") if hero == "CH02" else TEAL)
	var cross := direction.orthogonal()
	for i in range(3):
		var length := 14.0 + float(i) * 7.0
		var at := -direction * (18.0 + float(i) * 8.0) + cross * float(i - 1) * 9.0
		var color := Color(tint, 0.44 - float(i) * 0.1)
		p.draw_line(at, at - direction * length, color, 3.0 if hero == "CH01" else 1.7, true)
	if hero == "CH03":
		p.draw_arc(-direction * 24, 20.0, direction.angle() + 0.8, direction.angle() + 5.4, 15, Color(TEAL, 0.3), 1.5, true)


static func _draw_protection(p: Node2D) -> void:
	var shield := 0.0
	var game := p.get_node_or_null("/root/Game")
	if game != null:
		var run: Variant = game.get("run")
		if run != null:
			shield = float(run.get("shield"))
	if shield > 0.0:
		# Open shield brackets leave the ground and attack previews unobscured.
		for i in range(3):
			var start := float(i) * TAU / 3.0 + 0.14
			p.draw_arc(Vector2(0, -2), 33.0, start, start + 1.15, 12, Color(0.57, 0.82, 0.88, 0.66), 2.0, true)
	if float(p.get("invulnerable")) > 0.0:
		p.draw_line(Vector2(-19, 28), Vector2(-11, 28), Color(0.93, 0.88, 0.72, 0.7), 1.5, true)
		p.draw_line(Vector2(11, 28), Vector2(19, 28), Color(0.93, 0.88, 0.72, 0.7), 1.5, true)


static func _tint(base: Color, hurt: float) -> Color:
	return base.lerp(Color("e7b9a0"), hurt)


static func _poly(p: Node2D, vertices: Array, fill: Color, outline: Color = INK) -> void:
	var polygon := PackedVector2Array(vertices)
	p.draw_colored_polygon(polygon, fill)
	if outline.a > 0.0:
		polygon.append(polygon[0])
		p.draw_polyline(polygon, outline, 1.6, true)
