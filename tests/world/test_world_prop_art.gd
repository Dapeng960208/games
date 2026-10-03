extends Node
## Semantic selection, complete raw-atlas crops, and projected ground anchors.
## Gameplay keys survive the four-faction replacement without alias chaining.
const Art = preload("res://scripts/infrastructure/assets/world_prop_art.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const EXPECTED_IDENTITIES := {
	"B01_winch": "B03_transformer", "B01_ore_cart": "B03_wrecked_drone", "B01_crate_stack": "B03_pipe_manifold",
	"B02_spore_nest": "B01_winch", "B02_root_barrier": "B01_crate_stack", "B02_fungal_rock": "B01_ore_cart",
	"B03_transformer": "T03_pumpkin_lantern", "B03_pipe_manifold": "T03_grave_barrier", "B03_wrecked_drone": "T03_funeral_cart",
	"B04_crystal_cluster": "T04_terracotta_cache", "B04_resonance_obelisk": "T04_war_totem", "B04_broken_receiver": "T04_signal_gong"
}
const BEACONS := ["beacon_heal", "beacon_resource", "beacon_guard", "beacon_haste", "beacon_damage", "beacon_dormant"]
var checks: int = 0
var failures: int = 0
var native_definitions: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WORLD_PROP_ART: " + description)

func _run() -> void:
	for path: String in Art.MANIFESTS:
		_validate_manifest(path)
	var selected_crops: Dictionary = {}
	for gameplay_key: String in EXPECTED_IDENTITIES:
		var native_key: String = str(EXPECTED_IDENTITIES[gameplay_key])
		_validate_selected(gameplay_key, native_key)
		var selected: Dictionary = Art.definition_for_asset(gameplay_key)
		var signature: String = str(selected.get("path", "")) + ":" + str(selected.get("source", Rect2()))
		check(not selected_crops.has(signature), "each gameplay identity selects a distinct painted prop: " + gameplay_key)
		selected_crops[signature] = gameplay_key
	for key: String in BEACONS:
		_validate_selected(key, key)
		check(str(Art.definition_for_asset(key).get("path", "")).contains("storybook_beacons_v1"), "beacon uses the dedicated illustrated atlas: " + key)
	check(Art.definition_for_asset("no_such_prop").is_empty() and not Art.has_authored_asset("no_such_prop"), "unknown identities do not silently choose unrelated art")
	check(Art.fitted_scale("B01_winch", Vector2.ZERO) == 0.0, "zero-area requested art cannot gain size")
	check(Art.sprite_quad({"asset": "B01_winch", "visual_size": Vector2.ZERO}).is_empty(), "missing requested body size creates no quad")
	var tint: Color = Art.authored_tint(Color(.6, .7, .8, .35))
	check(is_equal_approx(tint.a, .35) and tint.r < .995 and tint.g < .995 and tint.b < .995, "painted source colors bypass legacy white-command grading without changing alpha")
	print("WORLD_PROP_ART checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _validate_manifest(path: String) -> void:
	check(FileAccess.file_exists(AssetCatalog.resolve(path)), "manifest exists: " + path)
	if not FileAccess.file_exists(AssetCatalog.resolve(path)): return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
	check(value is Dictionary and value.get("regions") is Dictionary, "manifest exposes complete regions: " + path)
	if not value is Dictionary or not value.get("regions") is Dictionary: return
	var parent: Texture2D = Sampler.sampled(str(value.get("texture", "")))
	check(parent != null, "raw authored atlas loads: " + path)
	if parent == null: return
	check(Sampler.sampled(str(value.texture)) == parent, "atlas sampler shares its original cached texture: " + path)
	var atlas: Rect2 = Rect2(Vector2.ZERO, parent.get_size())
	var source: Image = parent.get_image()
	check(source != null and not source.is_empty(), "atlas retains readable pixels: " + path)
	if source == null or source.is_empty(): return
	check(source.get_pixel(0, 0).a < .01 and source.get_pixel(source.get_width() - 1, source.get_height() - 1).a < .01, "raw atlas exterior remains transparent: " + path)
	for key: String in value.regions:
		var raw_region: Array = value.regions[key]
		check(raw_region.size() == 4, "region has four source coordinates: " + key)
		if raw_region.size() != 4: continue
		var area := Rect2(float(raw_region[0]), float(raw_region[1]), float(raw_region[2]), float(raw_region[3]))
		check(area.has_area() and atlas.encloses(area), "complete object crop stays inside its raw atlas: " + key)
		var raw_foot: Array = value.get("anchors", {}).get(key, [])
		var raw_ground: Array = value.get("ground_footprints", {}).get(key, [])
		check(raw_foot.size() == 2 and raw_ground.size() == 4, "object has explicit projected base and ground metadata: " + key)
		if raw_foot.size() != 2 or raw_ground.size() != 4: continue
		var foot := Vector2(float(raw_foot[0]), float(raw_foot[1]))
		var ground := Rect2(float(raw_ground[0]), float(raw_ground[1]), float(raw_ground[2]), float(raw_ground[3]))
		var local := Rect2(Vector2.ZERO, area.size)
		check(local.has_point(foot), "base anchor is crop-local and inside the crop: " + key)
		check(ground.has_area() and local.encloses(ground), "estimated ground footprint is contained in the crop: " + key)
		check(ground.has_point(foot), "projected base anchor lies on the supporting ground footprint: " + key)
		if atlas.encloses(area):
			check(source.get_region(Rect2i(area)).get_used_rect().has_area(), "complete crop contains actual visible art: " + key)
		native_definitions[key] = {"path": str(value.texture), "source": area, "foot": foot, "ground": ground}

func _validate_selected(gameplay_key: String, native_key: String) -> void:
	var definition: Dictionary = Art.definition_for_asset(gameplay_key)
	var expected: Dictionary = native_definitions.get(native_key, {})
	check(not expected.is_empty(), "expected native theme exists: " + gameplay_key + " -> " + native_key)
	check(Art.has_authored_asset(gameplay_key) and definition == expected, "functional identity selects its intended single-hop theme: " + gameplay_key)
	if definition.is_empty() or expected.is_empty(): return
	var texture: Texture2D = Art.texture_for_asset(gameplay_key)
	check(texture is AtlasTexture, "runtime prop uses its explicit atlas region: " + gameplay_key)
	if not texture is AtlasTexture: return
	var selected := texture as AtlasTexture
	check(Art.texture_for_asset(gameplay_key) == texture, "runtime selected texture is cached: " + gameplay_key)
	check(selected.atlas == Sampler.sampled(str(expected.path)) and selected.region == expected.source and selected.filter_clip, "selected crop shares raw source and clips neighboring props: " + gameplay_key)
	check(texture.get_size() == Vector2(expected.source.size) and Art.local_region(gameplay_key) == Rect2(Vector2.ZERO, texture.get_size()), "runtime coordinates become crop-local: " + gameplay_key)
	var world_foot := Vector2(1375, 905)
	var target_size := Vector2(130, 96)
	var scale: float = Art.fitted_scale(gameplay_key, target_size)
	var bounds: Rect2 = Art.bounds_at(gameplay_key, world_foot, target_size)
	check(scale > 0.0 and bounds.size.x <= target_size.x + .001 and bounds.size.y <= target_size.y + .001, "fit keeps the whole prop within requested dimensions: " + gameplay_key)
	check((bounds.position + Vector2(expected.foot) * scale).is_equal_approx(world_foot), "projected ground anchor registers exactly at the actual world foot: " + gameplay_key)
	for rotation: float in [0.0, PI * .5, -.45]:
		var collision := Rect2(1220, 760, 48, 32)
		var recipe: Dictionary = {"asset": gameplay_key, "visual_size": target_size, "rotation": rotation, "collision_rect": collision}
		var quad: PackedVector2Array = Art.sprite_quad(recipe)
		check(quad.size() == 4, "rotated body has a complete four-corner quad: " + gameplay_key)
		if quad.size() != 4: continue
		var enclosing := Rect2(quad[0], Vector2.ZERO)
		for corner: Vector2 in quad: enclosing = enclosing.expand(corner)
		check(enclosing.size.x <= target_size.x + .001 and enclosing.size.y <= target_size.y + .001, "rotated fitted art stays within the requested silhouette size: " + gameplay_key)
		check(recipe.collision_rect == collision, "art fitting never rewrites the gameplay collision footprint: " + gameplay_key)
