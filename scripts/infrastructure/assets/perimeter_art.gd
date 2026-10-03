class_name WorldPerimeterArt
extends RefCounted
## Sparse room-specific accents complement a complete painted environment.
## The illustration owns all four boundaries; no sprite strip reconstructs it.

const PropArt = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
const Identity = preload("res://scripts/presentation/world/prop_identity.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
const NORTH_ACCENTS := {
	"L01":["bell_tree","bronze_bench"], "L02":["glass_greenhouse","crystal_valve"],
	"L03":["bell_tree","seed_cradle"], "L04":["crystal_lens","copper_furnace"],
	"L05":["lift_pod","glass_greenhouse"], "L06":["copper_furnace","coolant_amphora"], "BO01":["prism_arch","glass_greenhouse"],
	"L07":["wax_stall","leaf_boat"], "L08":["wing_observatory","wing_banner"],
	"L09":["molting_pavilion","chrysalis_rack"], "L10":["pollen_well","resin_vein"],
	"L11":["leaf_loom","chitin_sculpture"], "L12":["nectar_calyx","leaf_arch"], "BO02":["queen_cradle","chrysalis_rack"],
	"L13":["coffin_postoffice","lavender_cottage"], "L14":["sweet_warehouse","sweet_crate"],
	"L15":["chime_pavilion","chime_mast"], "L16":["candle_bakery","candy_vat"],
	"L17":["tailor_shop","dress_form"], "L18":["lavender_cottage","moon_sail_ferry"], "BO03":["mayor_hall","chime_pavilion"],
	"L19":["drum_rack","windsock"], "L20":["roast_stall","melon_cart"],
	"L21":["bone_bench","scoreboard"], "L22":["bone_anvil","bellows_lizard"],
	"L23":["lantern_tree","signal_fire"], "L24":["tooth_gate","tribal_standard"], "BO04":["trophy_plinth","tribal_standard"]}

static func recipes(layout: Dictionary, biome: String, occupied: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if Art.environment_definition(biome).is_empty(): return result
	var used: Dictionary = occupied.duplicate()
	var reserved: Dictionary = Identity.reserved_identities(layout,biome)
	var arena: Rect2 = layout.get("arena",Rect2(0,0,2800,1800))
	var blueprint_id: String = str(layout.get("blueprint_room_id",layout.get("room_id","")))
	var accents: Array = NORTH_ACCENTS.get(blueprint_id,[])
	# Only two specific objects distinguish this room's outside story. Complete
	# vegetation, walls, water, houses and foreground already belong to the plate.
	for index: int in range(accents.size()):
		var at := Vector2(arena.position.x+arena.size.x*(.28+.44*index),arena.position.y-60)
		var original: String = biome+"_prop_"+str(accents[index])
		var asset: String = Identity.choose_asset(original,biome,used,reserved,false,true)
		if not PropArt.has_authored_asset(asset): continue
		var size := Vector2(180,140)
		result.append({"id":blueprint_id+":edge_feature:"+str(index),"depth_kind":"perimeter","asset":asset,"name":Identity.display_name(asset),"visual_identity":PropArt.visual_identity(asset),"foot":at,"art_size":size,"visual_bounds":PropArt.bounds_at(asset,at,size),"biome_id":biome,"non_solid":true,"occludes":false})
	return result

static func draw_item(canvas: CanvasItem, item: Dictionary) -> void:
	PropArt.draw_asset(canvas,str(item.get("asset","")),item.get("foot",Vector2.ZERO),item.get("art_size",Vector2(180,140)))
