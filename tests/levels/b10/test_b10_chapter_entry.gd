extends SceneTree
## Production entry and saved route compatibility, including isolated previews.
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Routes = preload("res://scripts/domain/world/route_generator.gd")
const Expedition = preload("res://scripts/app/expedition_controller.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	check(Rules.value("planned_chapters") == 10, "removed chapters are absent from the ten-region plan")
	var plans := Catalog.region_plan()
	check(plans.size() == 10 and plans[-1].biome_id == "B10", "final dragon court occupies the tenth row")
	check(plans[-1].name == "星辉龙庭", "isolated previews never show the removed demon identity")
	check(not Catalog.biomes().has("B07") and not Catalog.biomes().has("B08") and not Catalog.biomes().has("B09"), "planned chapters cannot acquire playable membership")
	var errors := Catalog.validate()
	check(errors.is_empty(), "registered identities validate: " + str(errors))
	if Rules.b05_candidate_enabled():
		check(not Catalog.b10_enabled(), "candidate profile cannot enter the production final court")
		check(Rules.value("level_cap") == (30 if Rules.b06_candidate_enabled() else 25), "isolated preview keeps its historical growth cap")
		check(Catalog.room_ids().size() == (36 if Rules.b06_candidate_enabled() else 30), "candidate roster is unchanged")
		check(not Routes.generate_single_biome("B10", 71, [], 20).get("valid", true), "candidate cannot construct a final-court route")
	else:
		check(Rules.chapter_enabled("B10") and Rules.value("level_cap") == 50, "production has explicit final-court membership and Lv50 growth")
		check(Catalog.biomes().keys() == ["B01", "B02", "B03", "B04", "B10"], "final court does not release candidates")
		check(Catalog.room_ids().size() == 30 and Catalog.enemy_ids().size() == 72 and Catalog.bosses().size() == 11, "six rooms, eighteen ordinary species and seven dragons registered")
		check(not "B10" in Expedition.unlocked_biomes({"bosses":["BO01", "BO02", "BO03"]}), "final court is locked before the fourth boss")
		check("B10" in Expedition.unlocked_biomes({"bosses":["BO01", "BO02", "BO03", "BO04"]}), "fourth-boss extraction enables the final court")
		for level: int in [1, 20, 46, 50]:
			var route := Routes.generate_single_biome("B10", 71, [], level)
			check(route.get("valid", false), "final-court route exists at departure Lv%d" % level)
			if not route.get("valid", false): continue
			check(route.node_count == 9 and route.template_ids == ["L55", "L56", "L57", "L58", "L59", "L60"], "each of the six guardians occurs once before the final arena")
			check(route.nodes[-1].room_id == "BO10" and route.nodes[-1].role == "boss", "ninth station is the nine-headed final boss")
			check(route.nodes.all(func(node: Dictionary) -> bool: return node.biome_id == "B10"), "final chapter keeps all stations within its own dragon court")
			var chosen := Routes.choose(route, 1, "L55")
			check(chosen.get("valid", false) and chosen.template_ids == route.template_ids, "a visible choice preserves the remaining dragon-room order")
			check(not Routes.choose(route, 1, "L60").get("valid", true), "a saved choice cannot skip the earlier guardians")
		check(not Routes.generate_single_biome("B10", 71, [], 51).get("valid", true), "departure beyond Lv50 is rejected")
		check(not Routes.generate("B10", 71, [], 20).get("valid", true), "final court never enters the historical descent-ring route API")
		check(not Routes.generate("B01", 71, [], 21).get("valid", true), "the historical route API keeps its original Lv20 bound")
	# Historical version-one schedules remain the same after a new region ships.
	for origin: String in ["B01", "B02", "B03", "B04"]:
		var legacy := Routes.generate(origin, 960208, [], 20)
		check(legacy.get("valid", false), origin + " retains its existing saved-route generation")
		if legacy.get("valid", false):
			check(legacy.nodes.all(func(node: Dictionary) -> bool: return node.biome_id in ["B01", "B02", "B03", "B04"]), origin + " retains the immutable four-region descent ring")
	print("B10 chapter entry: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
