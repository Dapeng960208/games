extends SceneTree
## Focused contract: the two chosen clans stay intact at each departure band,
## and serialized version-one routes retain their published descent schedule.
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Routes = preload("res://scripts/world/route_generator.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func same_clan(route: Dictionary, biome: String) -> bool:
	for node: Dictionary in route.get("nodes",[]):
		if node.get("biome_id","") != biome: return false
		if Routes.is_template_node(node):
			if Catalog.room(str(node.room_id)).get("biome_id","") != biome: return false
			for option: String in node.options:
				if Catalog.room(option).get("biome_id","") != biome: return false
		elif node.role == "boss":
			if node.room_id != Catalog.biomes()[biome].boss_id: return false
	return true

func route_identity(route: Dictionary) -> PackedStringArray:
	var identity := PackedStringArray([str(int(route.get("dynamic_version",0))),str(int(route.get("seed",0)))])
	for node: Dictionary in route.get("nodes",[]):
		identity.append(str(node.get("biome_id",""))+":"+str(node.get("room_id",""))+":"+str(node.get("role",""))+":"+"/".join(node.get("options",[])))
	return identity

func run_checks() -> void:
	for biome: String in ["B02","B03"]:
		for band: Array in [[1,6],[5,8],[10,10],[15,12]]:
			var level: int = band[0]
			var route: Dictionary = Routes.generate_single_biome(biome,73,[],level)
			var label := "%s Lv.%d" % [biome,level]
			check(route.get("valid",false) and route.get("dynamic_version") == 2,label+" creates a version-two expedition")
			if not route.get("valid",false): continue
			check(route.nodes.size() == band[1],label+" preserves the declared departure length")
			check(same_clan(route,biome),label+" keeps every node, option and boss in the selected clan")
			var restored: Dictionary = JSON.parse_string(JSON.stringify(route))
			var chosen := Routes.choose(restored,1,str(restored.nodes[1].options.back()))
			check(chosen.get("valid",false) and same_clan(chosen,biome),label+" keeps the clan after a saved route choice")
			check(chosen == Routes.generate_single_biome(biome,73,chosen.get("choices",[]),level),label+" replays its committed choices deterministically")
	var version_one: Dictionary = Routes.generate("B02",73,[],15)
	check(version_one.get("dynamic_version") == 1 and version_one.nodes[-1].biome_id == "B04","existing generate API retains version-one descent")
	var restored_one: Dictionary = JSON.parse_string(JSON.stringify(version_one))
	check(route_identity(restored_one) == route_identity(version_one),"version-one route identities and eligible choices survive JSON restore without migration")
	var chosen_one := Routes.choose(restored_one,1,str(restored_one.nodes[1].options.back()))
	check(chosen_one.get("valid",false) and chosen_one.get("dynamic_version") == 1 and chosen_one.nodes[-1].biome_id == "B04","restored version-one choices retain their original boss clan")
	var legacy: Dictionary = Routes.generate("B02",73)
	check(not legacy.has("dynamic_version") and legacy.nodes.size()==8,"historical eight-node route API remains unchanged")
	print("SINGLE BIOME ROUTES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
