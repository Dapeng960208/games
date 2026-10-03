extends SceneTree
## Low-residency regression for lazy bodies, deterministic variants, and HD padding.
const Art = preload("res://scripts/combat/enemy_art.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var before := Sampler.textures.size()
	check(Art.entry_for("").is_empty() and Art.entry_for("unknown").is_empty(), "Unknown identities stay empty")
	check(Sampler.textures.size() == before, "Unknown identities load no textures")
	var body := Art.entry_for("M12")
	check(not body.is_empty() and Art._entries.size() == 1, "Only requested canonical identity loads")
	check(Art._variants.size() == 1 and Art._variants.has("M12"), "Other chapter variants remain unloaded")
	var size := Sampler.textures.size()
	var snapshot: Array = Art._variants.M12.duplicate(true)
	check(Art.entry_for("M12") == body and Sampler.textures.size() == size, "Repeated body query does not grow texture cache")
	check(Art.variant_index_for("M12", 0, "L07", 1001) == Art.variant_index_for("M12", 0, "L07", 1001), "Variant selection remains deterministic")
	for index: int in Art.variant_count("M12"):
		var variant := Art.variant_entry_for("M12", index)
		check(variant.visual_variant_index == index, "Original variant indexes stay stable")
		check(bool(variant.get("hd_variant", false)) == (index in Art.VARIANT_HD_INDICES.M12), "Exact approved HD overrides remain selected")
		if index in [5, 6, 7]:
			check(variant.texture.get_size() == Vector2(1280,1280), "Virtual transparent HD canvas retained")
	check(not Art.skill_icon_for("M12").is_empty(), "Requested skill badge remains available")
	check(not Art.entry_for("M37").is_empty() and Art._entries.size() == 2, "Expansion body loads independently")
	check(not Art.entry_for("BO01").is_empty() and Art._entries.size() == 3, "Boss body loads independently")
	check(Art._variants.M12 == snapshot, "Later identities leave existing variants unchanged")
	check(Sampler.textures.size()-before <= 10, "Selected identities do not preload unrelated art")
	print("ENEMY_ART_RESIDENCY checks=%d entries=%d textures_added=%d failures=%d" % [checks, Art._entries.size(), Sampler.textures.size()-before, failures])
	quit(1 if failures else 0)
