extends RefCounted
## L37 review-only UI placement. Reads live presentation bounds; never mutates
## commands, actors, clocks or card contents. Crowded fallback is diagnostic,
## not a promise that every possible viewport admits non-overlapping cards.
const Fx = preload("res://scripts/levels/b07/art/l37_review_fx.gd")
const Cards = preload("res://scripts/presentation/monsters/enemy_skill_presentation.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
const Hero = preload("res://scripts/presentation/characters/hero_visual.gd")
const SIZE := Vector2(254,61)
const GAP := 10.0

const BATCH_META := &"_l37_skill_card_batch"
const COORDINATOR := "L37SkillCardBatch"

class Coordinator extends Node:
	var refresh: Callable
	func _process(_delta: float) -> void:
		refresh.call(get_parent())

static func enabled(room: Node) -> bool:
	if not is_instance_valid(room): return false
	var runtime: Node2D = Props.read(room,"enemy_skills")
	return is_instance_valid(runtime) and Fx.enabled(runtime)

static func ensure(room: Node) -> bool:
	if not enabled(room): return false
	if room.get_node_or_null(COORDINATOR) == null:
		var coordinator := Coordinator.new()
		coordinator.name = COORDINATOR
		# Camera and telegraphs use 100. Publish after those and ordinary HUD
		# processing, once all actor physics have completed for this render.
		coordinator.process_priority = 10000
		coordinator.refresh = publish
		room.add_child(coordinator)
	return true

## The runtime and frozen-scene tests use this same read-only presentation
## transaction. Never refresh from an individual actor's physics or _draw.
static func publish(room: Node) -> Dictionary:
	if not enabled(room):
		if is_instance_valid(room): room.remove_meta(BATCH_META)
		return {}
	var ids := Cards.detail_candidates(room)
	var placements: Dictionary = {}
	var obstacles := body_rects(room)
	obstacles.append_array(hud_rects(room.get_parent()))
	var occupied: Array[Rect2] = []
	var enemies: Node = Props.read(room,"enemies")
	# Clear old selections and refresh all readouts before planning any card.
	for actor: Node in enemies.get_children():
		var badge: Node2D = actor.get_node_or_null("EnemySkillBadge")
		if badge == null: continue
		var alive: bool = not actor.is_queued_for_deletion() and actor.has_method("is_alive") and actor.call("is_alive")
		var brain: Variant = Props.read(actor,"brain")
		badge.info = Cards.readout(brain).duplicate(true) if alive and brain is RefCounted else {}
		badge.command = badge.info.get("command",{})
		badge.visible = alive
		badge.locked = bool(badge.info.get("locked",false))
		badge.progress = float(badge.info.get("progress",0.0))
		badge.detail_slot = ids.find(actor.get_instance_id())
		badge.show_detail = badge.detail_slot >= 0
	for id: int in ids:
		var owner: Node2D = instance_from_id(id)
		if not is_instance_valid(owner): continue
		var badge: Node2D = owner.get_node_or_null("EnemySkillBadge")
		if badge == null: continue
		var matrix := badge.get_global_transform_with_canvas()
		var native: Rect2 = matrix * Rect2(badge.detail_origin(),SIZE)
		var chosen := choose(native,badge.get_viewport_rect().grow(-8),obstacles,occupied)
		occupied.append(chosen.rect)
		chosen["origin"] = displaced_origin(matrix,badge.detail_origin(),Vector2(chosen.rect.position)-native.position)
		placements[id] = chosen
	var batch := {"frame":Engine.get_process_frames(),"selected_ids":ids,"placements":placements}
	room.set_meta(BATCH_META,batch)
	for actor: Node in enemies.get_children():
		var badge: Node2D = actor.get_node_or_null("EnemySkillBadge")
		if badge != null: badge.queue_redraw()
	return batch

static func placement(badge: Node2D) -> Dictionary:
	if not is_instance_valid(badge): return {}
	var actor: Node2D = badge.get_parent()
	var room: Node = Props.read(actor,"room")
	if not enabled(room): return {}
	var batch: Dictionary = room.get_meta(BATCH_META,{})
	return batch.get("placements",{}).get(actor.get_instance_id(),{})

## Real visible HUD content only: full-screen roots and layout containers
## are not obstacles. Canvas transforms include viewport/canvas scaling.
static func hud_rects(scene: Node) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if is_instance_valid(scene): _collect_hud(scene,false,result)
	return result

static func _collect_hud(node: Node, in_canvas: bool, result: Array[Rect2]) -> void:
	if node is CanvasLayer:
		if not node.visible: return
		in_canvas = true
	if in_canvas and node is Control and node.is_visible_in_tree():
		var content: bool = node is Panel or node is PanelContainer or node is BaseButton or node is Label or node is RichTextLabel or node is TextureRect or node is ProgressBar
		if node is Label or node is RichTextLabel: content = not node.text.is_empty()
		var rect: Rect2 = node.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,node.size)
		if content and rect.has_area() and not rect.encloses(node.get_viewport_rect()): result.append(rect)
	for child: Node in node.get_children(): _collect_hud(child,in_canvas,result)

## Unlike basis_xform_inv, affine_inverse handles the camera's .72 scale.
static func displaced_origin(matrix: Transform2D, origin: Vector2, screen_offset: Vector2) -> Vector2:
	return origin+matrix.affine_inverse().basis_xform(screen_offset)

## Pure geometry seam for small deterministic tests. Cards remain at their
## native size. Search nearby first, then perimeter slots. If all slots are
## blocked, keep the least-overlapping perimeter slot and report its overlap.
static func choose(native: Rect2, viewport: Rect2, bodies: Array[Rect2], occupied: Array[Rect2]) -> Dictionary:
	var points: Array[Vector2] = [native.position]
	for offset: Vector2 in [Vector2(0,-native.size.y-GAP),Vector2(0,native.size.y+GAP),Vector2(-native.size.x-GAP,0),Vector2(native.size.x+GAP,0)]:
		points.append(native.position+offset)
	var nearby_count := points.size()
	var xmax := maxf(viewport.position.x,viewport.end.x-native.size.x)
	var ymax := maxf(viewport.position.y,viewport.end.y-native.size.y)
	var y := viewport.position.y
	while y <= ymax:
		points.append(Vector2(viewport.position.x,y))
		points.append(Vector2(xmax,y))
		y += native.size.y+GAP
	var x := viewport.position.x
	while x <= xmax:
		points.append(Vector2(x,viewport.position.y))
		points.append(Vector2(x,ymax))
		x += native.size.x+GAP
	var best := Rect2(viewport.position,native.size)
	var best_score := INF
	for index: int in points.size():
		var at: Vector2 = points[index].clamp(viewport.position,Vector2(xmax,ymax))
		var rect := Rect2(at,native.size)
		var overlap := 0.0
		for body: Rect2 in bodies: overlap += rect.intersection(body.grow(GAP)).get_area()
		# Existing cards have priority even in a crowded fallback.
		for card: Rect2 in occupied: overlap += rect.intersection(card.grow(GAP)).get_area()*1000.0
		if overlap <= .001:
			return {"rect":rect,"perimeter":index>=nearby_count,"fallback":false,"overlap_score":0.0,"fits_viewport":viewport.encloses(rect)}
		if index >= nearby_count and overlap < best_score:
			best = rect
			best_score = overlap
	return {"rect":best,"perimeter":true,"fallback":true,"overlap_score":best_score,"fits_viewport":viewport.encloses(best)}

static func body_rects(room: Node) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var enemies: Node = Props.read(room,"enemies")
	for actor: Node2D in enemies.get_children():
		if actor.is_queued_for_deletion() or not actor.is_alive(): continue
		var visual: Node2D = Props.read(actor,"body_visual")
		if visual == null or not visual.has_method("body_frame"): continue
		var frame: Dictionary = visual.body_frame()
		var bounds: Rect2 = frame.get("bounds",Rect2())
		if bounds.has_area(): result.append(visual.get_global_transform_with_canvas()*bounds)
	var player: Node2D = Props.read(room,"player")
	if is_instance_valid(player):
		var bounds := hero_rect(player)
		if bounds.has_area(): result.append(bounds)
	return result

static func hero_rect(player: Node2D) -> Rect2:
	# Match HeroVisual's selected frame and body transform without calling its
	# drawing path or its stateful locomotion sampler.
	var hero := str(player.hero_id())
	var velocity: Vector2 = player.velocity
	var stride: float = player.stride
	var motion: Dictionary = player.get_meta("_hero_visual_motion",{})
	var walking: bool = velocity.length_squared()>4.0 and stride>.00001
	if not motion.is_empty():
		walking = velocity.length_squared()>4.0 and (stride>float(motion.stride)+.00001 if Engine.get_physics_frames()!=int(motion.frame) or not is_equal_approx(stride,float(motion.stride)) else bool(motion.walking))
	var aim: Vector2 = player.aim_direction
	aim = aim.normalized() if aim.length_squared()>=.01 else Vector2.RIGHT
	var state := str(player.visual_state).trim_prefix("cast_").trim_prefix("release_")
	var progress := clampf(1.0-float(player.visual_remaining)/maxf(.001,float(player.visual_duration)),0,1)
	var dash: bool = float(player.dash_remaining)>0 or state=="dash"
	var lean := Vector2(velocity.x*.007 if walking else 0.0,-absf(sin(stride)*(1.0 if walking else 0.0))*(1.5 if hero=="CH01" else 2.4))
	if state=="attack_windup": lean -= aim*progress*(4.0 if hero=="CH01" else 1.5)
	elif state=="attack_strike": lean += aim*(1.0-progress)*(5.0 if hero=="CH01" else 1.5)
	var feedback: Node = player.get_node_or_null("HeroFeedback")
	var pose: Dictionary = feedback.pose_state() if is_instance_valid(feedback) else {"phase":"idle","progress":0.0,"direction":aim,"slot":"basic"}
	pose = Hero.gunner_presentation_pose(player,pose).duplicate(true)
	if dash: pose["dash_progress"] = clampf(float(player.dash_elapsed)/maxf(.001,float(player.dash_elapsed)+float(player.dash_remaining)),0,1)
	aim = Hero.presentation_direction(aim,velocity,pose,walking,player.dash_direction,dash,motion.get("direction",Vector2.ZERO))
	pose["direction"] = aim
	var frame: Dictionary = Hero.presentation_frame_info(hero,"back" if aim.y<-.20 else "front",pose,stride,walking,dash)
	if frame.is_empty(): return Rect2()
	return player.get_global_transform_with_canvas()*Hero.body_transform(frame,hero,aim,lean,pose,walking,stride)*Rect2(frame.bounds)
