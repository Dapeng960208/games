class_name HeroVisual
extends RefCounted
## Authored ImageGen characters are the production body layer. The original
## registered idle is the missing-pose fallback. Presentation never drives combat.

const GENERATED_HEIGHT := preload("res://scripts/shared/presentation_metrics.gd").HERO_BODY_HEIGHT
const FOOT_OFFSET := 8.0
const WalkAtlas = preload("res://scripts/presentation/characters/hero_walk_atlas.gd")
const BasicAtlas = preload("res://scripts/presentation/characters/hero_basic_atlas.gd")
const SkillAtlas = preload("res://scripts/presentation/characters/hero_skill_atlas.gd")
const ArtFamily = preload("res://scripts/presentation/characters/hero_art_family.gd")
const DirectionalAtlas = preload("res://scripts/presentation/characters/hero_directional_atlas.gd")
const STRIDE_PER_WORLD_UNIT := .12
static var _action_banks: Dictionary = {}

static func prewarm(hero: String) -> void:
	if not DirectionalAtlas.load_combat_clips(hero).is_empty(): return
	DirectionalAtlas.load_family(hero)
	# Include the static fallback: brief contact/recovery poses can select it
	# even when idle and windup use an atlas. Its alpha scan must not run on
	# the first hit's render frame, while input is already live.
	_idle_body(hero)
	for bank: String in ["front","back"]:
		_action_bank(hero,bank)
		BasicAtlas.frame_info(hero,bank,"windup",0.0)
		for slot: String in ["q","secondary","f","ultimate"]: SkillAtlas.frame_info(hero,slot,bank,"windup",0.0)
	WalkAtlas.frame_info(hero,"front",0.0)

static func _action_bank(hero: String, bank: String) -> Dictionary:
	var replacement: String = ArtFamily.metadata_path(hero,"actions",bank)
	if hero == "CH01" and replacement.is_empty(): return {}
	var metadata_path: String = replacement if not replacement.is_empty() else "asset://heroes/%s_actions_%s_v2.json" % [hero,bank]
	if _action_banks.has(metadata_path):
		return _action_banks[metadata_path]
	if not FileAccess.file_exists(AssetCatalog.resolve(metadata_path)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(metadata_path)))
	if not parsed is Dictionary or not parsed.get("frames",[]) is Array:
		return {}
	var data: Dictionary = parsed
	var path: String = str(data.get("texture","asset://heroes/%s_actions_%s_v2.png" % [hero,bank]))
	var texture: Texture2D = load(AssetCatalog.resolve(path)) if ResourceLoader.exists(AssetCatalog.resolve(path)) else null
	var source: Image = texture.get_image() if texture != null else Image.load_from_file(AssetCatalog.resolve(path))
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
		var contacts: Array[Vector2] = []
		for contact: Variant in item.get("foot_contacts",[]):
			if contact is Array and contact.size() == 2:
				contacts.append((Vector2(float(contact[0]),float(contact[1]))-anchor)*scale_value+Vector2(0,FOOT_OFFSET))
		frames[str(item.get("name","idle"))] = {"texture":texture,"path":path,"region":region,"bounds":bounds,"anchors":anchors,"bank":bank,"phase":str(item.get("name","idle")),"frame_index":frame_index,"body_height":GENERATED_HEIGHT,"source_body_height":standard_height,"facing_x":-1 if int(data.get("facing_x",1)) < 0 else 1,"art_family":"storybook" if not replacement.is_empty() else "original"}
		frames[str(item.get("name","idle"))]["foot_contacts"] = contacts
	if not frames.has("idle") or not frames.has("windup") or not frames.has("release") or not frames.has("recovery"):
		return {}
	_action_banks[metadata_path] = frames
	return frames

static func action_frame_info(hero: String, bank: String = "front", phase: String = "idle") -> Dictionary:
	var authored: Dictionary = DirectionalAtlas.combat_frame_info(hero,Vector2(1,-1) if bank == "back" else Vector2(1,1),phase,0.0,"idle" if phase == "idle" else "basic")
	if not authored.is_empty(): return authored
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
	var clip: Dictionary = SkillAtlas.load_clip("asset://heroes/CH02_secondary_%s_v1.json" % bank)
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
				"direction":feedback.get("_basic_direction")},true)
			basic.erase("authored_phase_progress")
			return basic
	if str(pose.get("phase", "idle")) != "idle" or float(p.shot_cooldown) <= 0.0 or not is_instance_valid(feedback) or str(feedback.get("_basic")) != "attack_strike":
		return pose
	var held: Dictionary = pose.duplicate()
	held.merge({"phase":"recovery", "slot":"basic", "progress":1.0, "authored_phase_progress":1.0,
		"direction":feedback.get("_basic_direction"), "gun_hold":true},true)
	return held

static func presentation_frame_info(hero: String, bank: String, pose: Dictionary, stride: float, walking: bool, dash: bool = false) -> Dictionary:
	var phase: String = str(pose.get("phase", "idle"))
	var action: String = str(pose.get("skill_id",""))
	var sample: float = float(pose.get("authored_phase_progress",pose.get("progress",0.0)))
	if dash:
		action = "dash"
		sample = float(pose.get("dash_progress",0.0))
	elif phase == "idle":
		action = "walk" if walking else "reload" if hero == "CH02" and pose.has("reload_progress") else "idle"
		sample = fposmod(stride/STRIDE_PER_WORLD_UNIT,150.0)/150.0 if walking else float(pose.get("reload_progress",pose.get("idle_progress",0.0)))
	elif action.is_empty():
		action = "basic" if str(pose.get("slot","basic")) == "basic" else hero+"_SK%02d" % (["q","secondary","f","ultimate"].find(str(pose.get("slot","")))+1)
	var complete: Dictionary = DirectionalAtlas.combat_frame_info(hero,pose.get("direction",Vector2.RIGHT),phase,sample,action)
	if not complete.is_empty(): return complete
	if dash:
		return dodge_frame_info(hero,bank,float(pose.get("dash_progress",0.0)))
	var directed: Dictionary = DirectionalAtlas.frame_info(hero,pose.get("direction",Vector2.RIGHT),phase,float(pose.get("progress",0.0)))
	if not directed.is_empty(): return directed
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

## No dedicated dodge atlas is approved. Reuse an intact low authored stance;
## the small foot-anchored weight change below is presentation, not a new clip.
static func dodge_frame_info(hero: String, bank: String, progress: float) -> Dictionary:
	var frame: Dictionary
	if hero == "CH02":
		frame = gunner_shooting_frame(bank,{"slot":"secondary","phase":"windup","progress":0.0})
	else:
		frame = action_frame_info(hero,bank,"recovery" if hero == "CH01" else "windup" if progress < .72 else "recovery")
	if frame.is_empty():
		return action_frame_info(hero,bank,"idle")
	frame["source_phase"] = str(frame.phase)
	frame["phase"] = "dodge"
	frame["slot"] = "dodge"
	frame.erase("gun_shooting_pose")
	frame.erase("gun_recoil")
	frame["dodge_presentation"] = true
	return frame

## Movement and dodge may face away from the pointer. A committed action still
## uses its recorded aim; this does not write Player.aim_direction or shot data.
static func presentation_direction(aim: Vector2, velocity: Vector2, pose: Dictionary, walking: bool, dash_direction: Vector2 = Vector2.ZERO, dash: bool = false, resolved_motion: Vector2 = Vector2.ZERO) -> Vector2:
	var direction: Vector2 = pose.get("direction",aim)
	if dash and dash_direction.is_finite() and not dash_direction.is_zero_approx():
		direction = dash_direction
	elif str(pose.get("phase","idle")) == "idle" and walking and velocity.is_finite() and velocity.length_squared() > 4.0:
		direction = resolved_motion if resolved_motion.is_finite() and not resolved_motion.is_zero_approx() else velocity
	return direction.normalized() if direction.is_finite() and direction.length_squared() > .001 else Vector2.RIGHT

## Pixels and attachment anchors always share this transform. Shooting poses
## retain the original unrotated anatomy and frozen launch-point contract.
static func body_transform(asset: Dictionary, hero: String, aim: Vector2, lean: Vector2, pose: Dictionary, walking: bool = false, stride: float = 0.0) -> Transform2D:
	var flip: float = source_horizontal_flip(aim,asset)
	var transform := Transform2D(0.0,Vector2(flip,1.0),0.0,_action_offset(asset,hero,aim,lean,pose))
	if bool(asset.get("dodge_presentation",false)) and not bool(asset.get("articulated_clip",false)):
		var pressure: float = sin(clampf(float(pose.get("dash_progress",0.0)),0.0,1.0)*PI)
		var squat: float = .065 if hero == "CH01" else .05 if hero == "CH02" else .035
		var rotation: float = aim.x*.024*pressure if hero == "CH01" else 0.0
		transform = Transform2D(rotation,Vector2(flip*(1.0+pressure*.015),1.0-pressure*squat),0.0,Vector2.ZERO)
		transform.origin = Vector2(0,FOOT_OFFSET)-transform.basis_xform(Vector2(0,FOOT_OFFSET))
	elif hero == "CH03" and walking and str(asset.get("phase","idle")) == "idle" and str(pose.get("phase","idle")) == "idle":
		# The rejected mage walking sheet stays disabled. A restrained torso sway
		# carries the approved idle illustration while both soles remain grounded.
		var breath: float = absf(sin(stride*.34))
		transform = Transform2D(Vector2(flip,0),Vector2(aim.x*.012,1.0-breath*.012),Vector2.ZERO)
		transform.origin = Vector2(0,FOOT_OFFSET)-transform.basis_xform(Vector2(0,FOOT_OFFSET))
	return transform

## Frozen launch-point sampling, independent of the previous rendered idle pose.
## Projectiles use this display anchor without moving their physical origin.
static func release_muzzle_local(hero: String, slot: String, direction: Vector2) -> Vector2:
	var aim: Vector2 = direction.normalized() if direction.is_finite() and direction.length_squared() > 0.001 else Vector2.RIGHT
	var bank: String = "back" if aim.y < -0.20 else "front"
	var pose: Dictionary = {"phase":"release","slot":slot,"progress":0.0,"authored_phase_progress":0.0,"direction":aim}
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
	if bool(asset.get("directional_sequence",false)): return 1.0
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
	var direction: Vector2 = previous.get("direction",velocity.normalized())
	if not previous.is_empty():
		if frame != int(previous.frame) or not is_equal_approx(stride,float(previous.stride)):
			walking = walking and stride > float(previous.stride)+.00001
			var travel: Vector2 = p.position-Vector2(previous.get("position",p.position))
			if walking and travel.length_squared() > .00001:
				direction = travel.normalized()
		else:
			walking = walking and bool(previous.walking)
	else:
		walking = walking and stride > .00001
	p.set_meta("_hero_visual_motion",{"frame":frame,"stride":stride,"walking":walking,"position":p.position,"direction":direction})
	return walking


static func _idle_body(hero: String) -> Dictionary:
	return action_frame_info(hero,"front","idle")


static func asset_path(hero: String) -> String:
	var frame: Dictionary = action_frame_info(hero)
	if not frame.is_empty():
		return str(frame.path)
	return str(_idle_body(hero).get("path", ""))


static func asset_bounds(hero: String) -> Rect2:
	var frame: Dictionary = action_frame_info(hero)
	if not frame.is_empty():
		return frame.bounds
	return _idle_body(hero).get("bounds", Rect2())


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
	var feedback: Node = p.get_node_or_null("HeroFeedback")
	var pose: Dictionary = feedback.pose_state() if is_instance_valid(feedback) else {"phase":"idle","progress":0.0,"direction":aim,"slot":"basic"}
	pose = gunner_presentation_pose(p,pose)
	pose["idle_progress"] = fposmod(float(p.get("combat_time")),1.8)/1.8
	if hero == "CH02" and p.has_method("class_state_view"):
		var class_view: Dictionary = p.class_state_view()
		if bool(class_view.get("reloading",false)): pose["reload_progress"] = float(class_view.get("reload_progress",0.0))
	if dash:
		pose = pose.duplicate()
		pose["dash_progress"] = clampf(float(p.get("dash_elapsed"))/maxf(.001,float(p.get("dash_elapsed"))+float(p.get("dash_remaining"))),0.0,1.0)
	var resolved_motion: Vector2 = p.get_meta("_hero_visual_motion",{}).get("direction",Vector2.ZERO)
	aim = presentation_direction(aim,velocity,pose,walking,p.get("dash_direction"),dash,resolved_motion)
	pose = pose.duplicate()
	pose["direction"] = aim
	p.set_meta("hero_presentation_direction",aim)
	var bank: String = "back" if aim.y < -.20 else "front"
	var motion_frame: Dictionary = presentation_frame_info(hero,bank,pose,stride,walking,dash)
	if not motion_frame.is_empty():
		p.set_meta("hero_visual_source",motion_frame.path)
		p.set_meta("hero_visual_pose",str(motion_frame.phase))
		p.set_meta("hero_visual_bank",str(motion_frame.get("bank",bank)))
		p.set_meta("hero_directional_key",str(motion_frame.get("direction_key","")))
		p.set_meta("hero_visual_frame",int(motion_frame.get("frame_index",-1)))
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_draw_action_frame(p,motion_frame,hero,aim,lean,pose,hurt,walking,stride)
		_draw_protection(p)
		return
	var generated: Dictionary = _idle_body(hero)
	if not generated.is_empty():
		p.set_meta("hero_visual_source", generated.path)
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_draw_action_frame(p,generated,hero,aim,lean,pose,hurt,walking,stride)
		_draw_protection(p)
		return
	p.set_meta("hero_visual_source", "missing_registered_body")
	_draw_protection(p)

static func _draw_action_frame(p: Node2D, asset: Dictionary, hero: String, aim: Vector2, lean: Vector2, pose: Dictionary, hurt: float, walking: bool = false, stride: float = 0.0) -> void:
	var flip: float = source_horizontal_flip(aim,asset)
	p.set_meta("hero_visual_flip",flip)
	var transform: Transform2D = body_transform(asset,hero,aim,lean,pose,walking,stride)
	_draw_contact_shadow(p,hero,asset,transform,pose)
	# The atlas contains real torso/limb/weapon poses. Only tiny translation
	# adds recoil; no whole-image aiming rotation or second weapon is layered on.
	p.draw_set_transform_matrix(transform)
	var modulation := Color(1.0+hurt*.45,1.0-hurt*.2,1.0-hurt*.3,1.0)
	p.draw_texture_rect_region(asset.texture,asset.bounds,asset.region,modulation)
	p.draw_set_transform(Vector2.ZERO)
	var muzzle: Vector2 = asset.anchors.get("muzzle",asset.anchors.get("right_hand",Vector2(26,-28)))
	var grip: Vector2 = asset.anchors.get("grip",Vector2(15,-26))
	p.set_meta("hero_muzzle_local",transform*muzzle)
	p.set_meta("hero_grip_local",transform*grip)
	p.set_meta("hero_foot_local",transform*Vector2(0,FOOT_OFFSET))
	p.set_meta("hero_body_transform",transform)


static func _draw_contact_shadow(p: Node2D, hero: String, asset: Dictionary, transform: Transform2D, pose: Dictionary) -> void:
	var width: float = 27.0 if hero == "CH01" else 22.0 if hero == "CH02" else 21.0
	var phase: String = str(pose.get("phase","idle"))
	var weight: float = 0.0
	if str(pose.get("slot","")) == "basic" and phase in ["windup","release"]:
		weight = float(pose.get("progress",0.0)) if phase == "windup" else 1.0-float(pose.get("progress",0.0))
		weight *= .14 if hero == "CH01" else .045 if hero == "CH02" else .07
	if bool(asset.get("dodge_presentation",false)):
		weight = sin(clampf(float(pose.get("dash_progress",0.0)),0.0,1.0)*PI)*.12
	# Two translucent tiers read as warm daylight contact, without a black oval
	# swallowing the boots or a bright ring competing with enemy floor warnings.
	for layer in 2:
		var extent: float = width*(1.0+weight)*(1.16 if layer == 0 else .84)
		p.draw_set_transform(Vector2(2,FOOT_OFFSET+1.5),0.0,Vector2(extent/12.0,.54 if layer == 0 else .36))
		p.draw_circle(Vector2.ZERO,12.0,Color(Color("594c68"),.085 if layer == 0 else .19))
	p.draw_set_transform(Vector2.ZERO)
	var contacts: Array = asset.get("foot_contacts",[])
	if contacts.is_empty():
		var spread: float = 10.0 if hero == "CH01" else 7.0
		contacts = [Vector2(-spread,FOOT_OFFSET),Vector2(spread,FOOT_OFFSET)]
	for point: Vector2 in contacts:
		var ground: Vector2 = transform*point
		p.draw_set_transform(ground+Vector2(0,1.0),0.0,Vector2(1.28 if hero == "CH01" else 1.0,.36))
		p.draw_circle(Vector2.ZERO,4.0,Color(Color("50435b"),.24))
	p.draw_set_transform(Vector2.ZERO)


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
