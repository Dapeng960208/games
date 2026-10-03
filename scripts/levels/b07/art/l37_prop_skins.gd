extends "res://scripts/presentation/world/room_depth_sprite.gd"
## Visual skins of existing L37 mechanisms/covers only, never gameplay entities.
## Reuse actor-depth ordering and the common player-occlusion fade unchanged.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Properties = preload("res://scripts/domain/combat/combat_properties.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const ROOT := "asset://levels/b07/rooms/shared/"
const FLAGS := ["--b07-art-trial","--b07-midground-trial","--b07-convergence-review"]
# Measured alpha > 16 regions. Ground roots are centers of the visible base
# footprints, not transparent canvas bottoms. Original RGB and aspect survive.
const FRAMES := {
	"sun_mirror_pedestal":{"region":Rect2(248,66,783,1126),"root":Vector2(638,971)},
	"sun_altar_disc":{"region":Rect2(49,176,1158,910),"root":Vector2(628,653)},
	"low_stone_cover":{"region":Rect2(65,247,1135,878),"root":Vector2(632.5,780)}
}

static func enabled(owner_room: Node2D) -> bool:
	if not is_instance_valid(owner_room) or not Rules.b07_candidate_enabled(): return false
	for flag: String in FLAGS:
		if flag not in OS.get_cmdline_user_args(): return false
	var layout: Dictionary = Properties.read(owner_room,"layout",{})
	return str(Properties.read(owner_room,"layout_id","")) == "L37" and bool(layout.get("b07_candidate",false)) and str(layout.get("blueprint_room_id","")) == "L37"

static func skin_recipes(owner_room: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not enabled(owner_room): return result
	var definition := Geometry.room("L37")
	for mirror: Dictionary in definition.mirrors:
		result.append(_skin(str(mirror.id),"sun_mirror_pedestal",Geometry.world_point(mirror.position),80.0*Geometry.SCALE))
	result.append(_skin(str(definition.altar.id),"sun_altar_disc",Geometry.world_point(definition.altar.position),140.0*Geometry.SCALE))
	for cover: Dictionary in definition.stone_covers:
		var rect := Geometry.cover_rect(cover.rect)
		var item := _skin(str(cover.id),"low_stone_cover",rect.get_center(),rect.size.x)
		if item.is_empty(): return []
		item["collision_rect"] = rect # Read-only identity of the existing cover.
		result.append(item)
	# Fail closed as one visual family; retain the original rendering if any
	# source is missing, rather than suppressing a cover without its skin.
	for item: Dictionary in result:
		if item.is_empty(): return []
	return result

static func _skin(id: String, source: String, foot: Vector2, width: float) -> Dictionary:
	var texture := Sampler.sampled(ROOT+source+"/source_candidate.png")
	var frame: Dictionary = FRAMES[source]
	var region: Rect2 = frame.region
	if texture == null or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region): return {}
	var factor := width/region.size.x
	var bounds := Rect2(foot+(region.position-Vector2(frame.root))*factor,region.size*factor)
	return {"id":id,"depth_kind":"b07_review_skin","source":source,"texture":texture,"source_region":region,"source_root":frame.root,"foot":foot,"visual_bounds":bounds,"occludes":true,"destroyed":false}

static func replaces_cover(item: Dictionary, skins: Array[Dictionary]) -> bool:
	if str(item.get("kind","")) != "b07_low_stone": return false
	for skin: Dictionary in skins:
		if skin.get("source") == "low_stone_cover" and skin.get("collision_rect") == item.get("collision_rect"): return true
	return false

static func ground_recipes(owner_room: Node2D, originals: Array) -> Array:
	var skins := skin_recipes(owner_room)
	if skins.is_empty(): return originals
	return originals.filter(func(item: Dictionary) -> bool: return not replaces_cover(item,skins))

func _draw() -> void:
	if recipe.is_empty() or bool(recipe.get("destroyed",false)): return
	# The base class does not apply a biome material to this depth_kind.
	var bounds: Rect2 = recipe.visual_bounds
	draw_texture_rect_region(recipe.texture,Rect2(bounds.position-position,bounds.size),recipe.source_region,Color.WHITE)
